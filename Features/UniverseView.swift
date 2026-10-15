import SwiftUI

struct NanoHome: View {
    @Bindable var store: LabStore
    var body: some View {
        TabView {
            Tab("Universe", systemImage: "sparkles") { UniverseView(store: store) }
            Tab("Discoveries", systemImage: "book.closed") { DiscoveriesView(store: store) }
            Tab("Lab", systemImage: "chart.xyaxis.line") { ExperimentsView(store: store) }
        }
    }
}

private enum UniverseSheet: Identifiable {
    case tuning(WorldTool, String), worlds, guide
    var id: String {
        switch self {
        case .tuning(let tool, let id): return "\(tool.id)-\(id)"
        case .worlds: return "worlds"
        case .guide: return "guide"
        }
    }
}

struct UniverseView: View {
    @Bindable var store: LabStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: UniverseSheet?
    @State private var path: [String] = []
    private var world: TorusWorld { store.selectedWorld }
    private var message: LabStore.PlayMessage? {
        guard store.playMessage?.worldID == world.id else { return nil }
        return store.playMessage
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    worldStage
                    intention
                    HStack(spacing: 12) {
                        PlayActionButton(title: "Scatter stardust", detail: "Seed new life", symbol: "sparkles", color: .orange, identifier: "scatterStardust") {
                            store.play(.stardust, in: world.id)
                        }
                        PlayActionButton(title: "Send a pulse", detail: "Give a little energy", symbol: "bolt.fill", color: .blue, identifier: "sendPulse") {
                            store.play(.pulse, in: world.id)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Shape your world").font(.headline)
                            Spacer()
                            Text("Tap to turn a dial").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            ForEach(WorldTool.allCases) { tool in
                                Button { sheet = .tuning(tool, world.id) } label: {
                                    ToolTile(tool: tool, value: world.parameters[keyPath: tool.keyPath])
                                }
                                .buttonStyle(PlayPressStyle())
                                .accessibilityIdentifier("tune-\(tool.id)")
                                .accessibilityLabel("\(tool.title), \(Int(world.parameters[keyPath: tool.keyPath] * 100)) percent")
                                .accessibilityHint("Opens a dial and explains how this changes your world")
                            }
                        }
                    }
                    nextDiscovery
                    if let warning = store.persistenceMessage {
                        Label(warning, systemImage: "externaldrive.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
                    }
                    Text("An open-ended cosmic fable. Follow a hunch. See what happens.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Your universe")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { sheet = .worlds } label: { Label(world.name, systemImage: "circle.hexagongrid") }
                        .accessibilityIdentifier("chooseUniverse")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Pace of time", selection: $store.lab.speed) {
                            Text("Wander · 1×").tag(1.0)
                            Text("Unfold · 4×").tag(4.0)
                            Text("Fast forward · 12×").tag(12.0)
                        }
                        Toggle("See fields", isOn: $store.showFields)
                        Toggle("See trails", isOn: $store.showTrails)
                        Button("How this world works", systemImage: "questionmark.circle") { sheet = .guide }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .accessibilityLabel("Universe options")
                }
            }
            .navigationDestination(for: String.self) { WorldDetailView(store: store, worldID: $0) }
            .sheet(item: $sheet, onDismiss: { store.save() }) { destination in
                switch destination {
                case .tuning(let tool, let id): WorldTuningSheet(store: store, worldID: id, tool: tool)
                case .worlds: WorldShelf(store: store)
                case .guide: SimulationGuide()
                }
            }
            .task(id: store.playMessage?.id) {
                guard let id = store.playMessage?.id else { return }
                do { try await Task.sleep(for: .seconds(7)) } catch { return }
                if store.playMessage?.id == id { store.playMessage = nil }
            }
        }
    }

    private var worldStage: some View {
        VStack(spacing: 0) {
            TorusViewport(world: world, showFields: store.showFields, showTrails: store.showTrails, isRunning: store.lab.isRunning, visualCue: store.visualCue)
                .aspectRatio(1.8, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(world.name).font(.title2.bold())
                        Text(world.stageLabel).font(.caption)
                    }
                    .foregroundStyle(.white).shadow(color: .black, radius: 5).padding(16).allowsHitTesting(false)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button { path.append(world.id) } label: {
                        Label("Dive in", systemImage: "viewfinder").font(.caption.bold())
                    }
                    .buttonStyle(.glass).tint(.white).padding(12)
                    .accessibilityIdentifier("diveIntoWorld")
                }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(world.metrics.population) particles · \(world.metrics.matureCount) at the rim")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                    Text("\(world.radius.formatted(.number.precision(.fractionLength(2))))× size · \(Int(store.lab.speed))× time")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                Button {
                    store.lab.isRunning.toggle()
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Label(store.lab.isRunning ? "Pause" : "Let it unfold", systemImage: store.lab.isRunning ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.regular)
                .accessibilityIdentifier("universePlayPause")
                .accessibilityLabel(store.lab.isRunning ? "Pause universe" : "Let it unfold")
            }
            .padding(14)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var intention: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message?.isDiscovery == true ? "sparkle" : "hand.draw")
                .font(.title3).foregroundStyle(message?.isDiscovery == true ? .orange : .blue)
                .frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(message?.title ?? "Small gestures. New possibilities.").font(.subheadline.weight(.semibold))
                Text(message?.detail ?? (store.lab.isRunning ? "Plant a little dust, then watch it gather. Every world finds its own way." : "Your world is resting. Make a change, then press play to see it unfold."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("worldResponse")
    }

    private var nextDiscovery: some View {
        let discoveries = store.discoveries(in: world)
        let unlocked = discoveries.filter(\.isUnlocked).count
        let next = discoveries.first { !$0.isUnlocked }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(next == nil ? "A world of your own" : "Something to try", systemImage: "sparkle.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(unlocked) / \(discoveries.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(next.map { invitation(for: $0.id) } ?? "You've seen the first chapter. Try another world, change its conditions, and discover a different balance.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(discoveries) { discovery in
                    Capsule().fill(discovery.isUnlocked ? Color.blue : Color.primary.opacity(0.08)).frame(height: 4)
                }
            }
            .accessibilityLabel("\(unlocked) of \(discoveries.count) discoveries")
        }
        .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func invitation(for discoveryID: String) -> String {
        switch discoveryID {
        case "sowed-dust": return "Scatter stardust into the loop. You have planted the possibility of a new particle."
        case "first-birth": return "Let time move after scattering dust. Watch for a new jewel joining the current."
        case "first-bond": return "Try stronger Bonds and a calmer Flow. Give nearby opposites time to connect."
        case "coherence": return "Try balanced Warmth with a calmer Flow. Watch particles find a steady direction."
        case "rim-harmony": return "Give a coherent particle time to reach the glass. The rim is a place to support the next generation."
        default: return "Let the rim gather more mature particles. As it steadies, your world can make room to grow."
        }
    }
}

private struct PlayActionButton: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let identifier: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol).font(.title2.weight(.medium)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(color.opacity(0.14)))
        }
        .buttonStyle(PlayPressStyle()).accessibilityIdentifier(identifier)
    }
}

private struct ToolTile: View {
    let tool: WorldTool
    let value: Double
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.06), lineWidth: 4)
                Circle().trim(from: 0, to: value * 0.75).stroke(tool.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(135))
                Image(systemName: tool.symbol).font(.title3).foregroundStyle(tool.tint)
            }
            .frame(width: 44, height: 44)
            Text(tool.title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            Text(tool.settingName(for: value)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct PlayPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct WorldShelf: View {
    @Bindable var store: LabStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.lab.worlds) { world in
                        Button {
                            store.selectedWorldID = world.id
                            UISelectionFeedbackGenerator().selectionChanged()
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "circle.hexagongrid.fill").font(.title2).foregroundStyle(store.color(for: world.id))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(world.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(world.metrics.population) particles · \(world.stageLabel)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if world.id == store.selectedWorldID { Image(systemName: "checkmark.circle.fill") }
                            }.padding(.vertical, 6)
                        }
                    }
                } footer: { Text("Each world has its own conditions. Time moves together; your gestures affect only the world you choose.") }
                Section {
                    Button("Begin a new world", systemImage: "plus.circle.fill") { store.addWorld(); dismiss() }.disabled(store.lab.worlds.count >= 6)
                    Button("Make a twin of \(store.selectedWorld.name)", systemImage: "square.on.square") { store.clone(store.selectedWorldID); dismiss() }.disabled(store.lab.worlds.count >= 6)
                } footer: { Text("Twins begin in the same state. Change one and compare their journeys in the Lab. Up to six worlds can live here.") }
            }
            .navigationTitle("Your worlds").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct DiscoveriesView: View {
    @Bindable var store: LabStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("World", selection: $store.selectedWorldID) {
                        ForEach(store.lab.worlds) { Text($0.name).tag($0.id) }
                    }
                } footer: { Text("Little chapters in \(store.selectedWorld.name)'s story. Explore at your own pace; there is no single way to grow.") }
                Section {
                    ForEach(store.discoveries(in: store.selectedWorld)) { discovery in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: discovery.isUnlocked ? discovery.symbol : "circle.dashed")
                                .font(.title3).foregroundStyle(discovery.isUnlocked ? .blue : .secondary)
                                .frame(width: 40, height: 40).background(Color.blue.opacity(discovery.isUnlocked ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(discovery.title).font(.headline)
                                    Spacer(minLength: 0)
                                    if discovery.isUnlocked { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) }
                                }
                                Text(discovery.detail).font(.subheadline).foregroundStyle(.secondary)
                                Text(discovery.isUnlocked ? "Discovered" : "Waiting to unfold").font(.caption.weight(.medium)).foregroundStyle(discovery.isUnlocked ? .blue : .secondary)
                            }
                        }.padding(.vertical, 8).accessibilityElement(children: .combine)
                    }
                }
                Section {
                    Text("These are milestones in a fictional ecology, inspired by the story of a little particle finding its place. They reflect events in your world, not a score or a scientific claim.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Discoveries")
        }
    }
}
