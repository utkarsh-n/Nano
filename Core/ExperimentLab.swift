import Foundation

struct ExperimentLab: Codable, Equatable, Sendable {
    var formatVersion: Int = 1
    var worlds: [TorusWorld]
    var isRunning: Bool = true
    var speed: Double = 1

    static func makeDefault() -> ExperimentLab {
        let seed: UInt64 = 46_021
        return ExperimentLab(worlds: [
            TorusWorld(id: "aster", name: "Aster", seed: seed, parameters: .balanced),
            TorusWorld(id: "mica", name: "Mica", seed: seed, parameters: .energetic),
            TorusWorld(id: "nova", name: "Nova", seed: seed, parameters: .cooperative)
        ])
    }

    mutating func advance(steps: Int = 1) {
        guard isRunning else { return }
        for _ in 0..<max(0, min(steps, 3_600)) { stepOnce() }
    }

    mutating func stepOnce() {
        for index in worlds.indices { worlds[index].step() }
    }

    mutating func apply(_ command: TorusCommand, to worldID: String) {
        guard let index = worlds.firstIndex(where: { $0.id == worldID }) else { return }
        worlds[index].apply(command)
    }

    mutating func cloneWorld(sourceID: String, targetID: String) {
        guard sourceID != targetID,
              let source = worlds.firstIndex(where: { $0.id == sourceID }),
              let target = worlds.firstIndex(where: { $0.id == targetID }) else { return }
        let targetName = worlds[target].name
        worlds[source].startComparisonBaseline()
        worlds[target] = worlds[source].clone(id: targetID, name: targetName)
    }

    mutating func resetAll() {
        for index in worlds.indices { worlds[index].reset() }
    }

    mutating func addWorld(name: String, seed: UInt64) {
        // The renderer is designed for a small set of experiments, not an unbounded particle farm.
        guard worlds.count < 6 else { return }
        var serial = worlds.count + 1
        while worlds.contains(where: { $0.id == "torus-\(serial)" }) { serial += 1 }
        worlds.append(TorusWorld(id: "torus-\(serial)", name: name, seed: seed, parameters: .balanced))
    }
}
