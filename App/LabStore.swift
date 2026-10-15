import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class LabStore {
    var lab: ExperimentLab
    var selectedWorldID: String
    var comparisonIDs: [String]
    var showFields = true
    var showTrails = true
    var persistenceMessage: String?
    var playProgress: [String: WorldPlayProgress] = [:]
    var visualCue: TorusVisualCue?
    var playMessage: PlayMessage?
    private var lastTuningTick = -1
    private var lastTuningTime = 0.0
    private var recoveryMessage: String?
    private var mayOverwriteSave = true
    private let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
    private var lastSaveTime: Double = 0

    private struct SavedLab: Codable {
        var version = 1
        var lab: ExperimentLab
        var selectedWorldID: String
        var comparisonIDs: [String]
        var showFields: Bool
        var showTrails: Bool
        var playProgress: [String: WorldPlayProgress]?
    }

    init() {
        lab = .makeDefault()
        selectedWorldID = "aster"
        comparisonIDs = ["aster", "mica"]
        if isTesting { lab.isRunning = false; return }
        do {
            let path = try Self.saveURL()
            if FileManager.default.fileExists(atPath: path.path) {
                let saved = try JSONDecoder().decode(SavedLab.self, from: Data(contentsOf: path))
                guard saved.version == 1, saved.lab.formatVersion == 1,
                      !saved.lab.worlds.isEmpty, saved.lab.worlds.count <= 6 else {
                    preserveUnreadableSave(path)
                    return
                }
                lab = saved.lab
                selectedWorldID = lab.worlds.contains { $0.id == saved.selectedWorldID } ? saved.selectedWorldID : lab.worlds[0].id
                comparisonIDs = saved.comparisonIDs.filter { id in lab.worlds.contains { $0.id == id } }
                showFields = saved.showFields
                showTrails = saved.showTrails
                playProgress = saved.playProgress ?? [:]
            }
        } catch {
            if let path = try? Self.saveURL() { preserveUnreadableSave(path) }
            else { persistenceMessage = "The sandbox storage is unavailable on this device." }
        }
    }

    var selectedWorld: TorusWorld { world(selectedWorldID) ?? lab.worlds[0] }
    var comparedWorlds: [TorusWorld] { lab.worlds.filter { comparisonIDs.contains($0.id) } }
    var simulatedTime: String {
        formattedTime(lab.worlds.map(\.time).max() ?? 0)
    }
    func formattedTime(_ time: Double) -> String {
        let seconds = Int(time)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func world(_ id: String) -> TorusWorld? { lab.worlds.first { $0.id == id } }

    func apply(_ command: TorusCommand, to worldID: String) {
        lab.apply(command, to: worldID)
        recordDiscoveries(announce: false)
    }

    struct PlayMessage: Identifiable {
        let id = UUID()
        let worldID: String
        let title: String
        let detail: String
        let isDiscovery: Bool
    }

    func play(_ action: WorldAction, in worldID: String) {
        guard let world = world(worldID) else { return }
        let commands = WorldPlaybook.commands(for: action, in: world)
        guard !commands.isEmpty else {
            playMessage = PlayMessage(worldID: worldID, title: "A quiet moment", detail: WorldPlaybook.feedback(for: action, in: world), isDiscovery: false)
            return
        }
        for command in commands { apply(command, to: worldID) }
        var progress = playProgress[worldID] ?? WorldPlayProgress()
        if action == .stardust { progress.dustDrops += 1 } else { progress.energyPulses += 1 }
        playProgress[worldID] = progress
        let recipients = Set(commands.compactMap { command -> Int? in
            if case .energize(let id, _) = command { return id }
            return nil
        })
        let position = commands.compactMap { command -> Vector2? in
            if case .seedDust(let position, _) = command { return position }
            return nil
        }.first
        visualCue = TorusVisualCue(kind: action == .stardust ? .stardust : .pulse, worldID: worldID, particleIDs: recipients, position: position)
        playMessage = PlayMessage(worldID: worldID, title: action == .stardust ? "A little possibility, planted." : "A spark through your world.", detail: WorldPlaybook.feedback(for: action, in: world) + (lab.isRunning ? "" : " Press play to watch it unfold."), isDiscovery: false)
        UIImpactFeedbackGenerator(style: action == .stardust ? .soft : .medium).impactOccurred()
        recordDiscoveries(announce: false)
        save()
    }

    func tune(_ key: WritableKeyPath<TorusParameters, Double>, to value: Double, in worldID: String) {
        guard var parameters = world(worldID)?.parameters else { return }
        let value = min(1, max(0, value))
        guard abs(parameters[keyPath: key] - value) > 0.0001 else { return }
        parameters[keyPath: key] = value
        apply(.setParameters(parameters), to: worldID)
        var progress = playProgress[worldID] ?? WorldPlayProgress()
        progress.adjustments += 1
        playProgress[worldID] = progress
        let tick = Int(value * 20)
        let now = ProcessInfo.processInfo.systemUptime
        if tick != lastTuningTick, now - lastTuningTime > 0.08 {
            lastTuningTick = tick
            lastTuningTime = now
            UISelectionFeedbackGenerator().selectionChanged()
            let kind: TorusVisualCue.Kind = key == \.energyInput ? .warmth : key == \.turbulence ? .flow : .bonds
            visualCue = TorusVisualCue(kind: kind, worldID: worldID)
        }
    }

    func discoveries(in world: TorusWorld) -> [WorldDiscovery] {
        WorldPlaybook.discoveries(in: world, progress: playProgress[world.id] ?? WorldPlayProgress())
    }

    private func recordDiscoveries(announce: Bool) {
        for world in lab.worlds {
            var progress = playProgress[world.id] ?? WorldPlayProgress()
            let newlyEarned = discoveries(in: world).filter { $0.isUnlocked && !progress.unlockedDiscoveryIDs.contains($0.id) }
            guard !newlyEarned.isEmpty else { continue }
            progress.unlockedDiscoveryIDs.formUnion(newlyEarned.map(\.id))
            playProgress[world.id] = progress
            if announce, world.id == selectedWorldID, let discovery = newlyEarned.last {
                playMessage = PlayMessage(worldID: world.id, title: discovery.title, detail: discovery.detail, isDiscovery: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    func parameterBinding(_ key: WritableKeyPath<TorusParameters, Double>, worldID: String) -> Binding<Double> {
        Binding(get: { self.world(worldID)?.parameters[keyPath: key] ?? 0 }, set: { value in
            guard var parameters = self.world(worldID)?.parameters else { return }
            parameters[keyPath: key] = value
            self.apply(.setParameters(parameters), to: worldID)
        })
    }

    func addWorld() {
        let names = ["Aster", "Mica", "Nova", "Lyra", "Cleo", "Vega"]
        let name = names.first { candidate in !lab.worlds.contains { $0.name == candidate } } ?? "World \(lab.worlds.count + 1)"
        lab.addWorld(name: name, seed: 46_021)
        if let last = lab.worlds.last { selectedWorldID = last.id }
        save()
    }

    func clone(_ id: String) {
        guard lab.worlds.count < 6, let index = lab.worlds.firstIndex(where: { $0.id == id }) else { return }
        lab.worlds[index].startComparisonBaseline()
        let targetID = UUID().uuidString
        let name = "\(lab.worlds[index].name) copy"
        let clone = lab.worlds[index].clone(id: targetID, name: name)
        lab.worlds.append(clone)
        playProgress[targetID] = playProgress[id]
        comparisonIDs = [id, targetID]
        selectedWorldID = targetID
        save()
    }

    func reset(_ id: String) {
        guard let index = lab.worlds.firstIndex(where: { $0.id == id }) else { return }
        lab.worlds[index].reset()
        playProgress[id] = nil
        save()
    }

    func color(for id: String) -> Color {
        let index = lab.worlds.firstIndex { $0.id == id } ?? 0
        return [.cyan, .pink, .orange, .purple, .mint, .indigo][index % 6]
    }

    func runClock() async {
        recordDiscoveries(announce: false)
        var previous = ProcessInfo.processInfo.systemUptime
        var accumulator = 0.0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(66)) } catch { break }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = min(0.25, max(0, now - previous))
            previous = now
            if lab.isRunning {
                accumulator += elapsed * lab.speed
                let steps = Int(accumulator / TorusWorld.fixedDelta)
                if steps > 0 {
                    lab.advance(steps: steps)
                    recordDiscoveries(announce: true)
                    accumulator -= Double(steps) * TorusWorld.fixedDelta
                }
            } else { accumulator = 0 }
            if now - lastSaveTime > 10 { save(); lastSaveTime = now }
        }
    }

    func save() {
        guard !isTesting, mayOverwriteSave else { return }
        do {
            let payload = SavedLab(lab: lab, selectedWorldID: selectedWorldID, comparisonIDs: comparisonIDs, showFields: showFields, showTrails: showTrails, playProgress: playProgress)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: Self.saveURL(), options: .atomic)
            persistenceMessage = recoveryMessage
        } catch { persistenceMessage = "Your changes are running, but could not be saved on this device." }
    }

    private func preserveUnreadableSave(_ path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        do {
            let recovery = path.deletingLastPathComponent().appendingPathComponent("recovery-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: path, to: recovery)
            recoveryMessage = "The previous save could not be opened. A recovery copy was preserved; this is a new sandbox."
            persistenceMessage = recoveryMessage
        } catch {
            mayOverwriteSave = false
            persistenceMessage = "The previous save could not be opened. It has been kept untouched; this session cannot be saved."
        }
    }

    private static func saveURL() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Nano", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("sandbox-v1.json")
    }
}
