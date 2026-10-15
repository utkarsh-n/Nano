import SwiftUI

enum LabSheet: Identifiable {
    case controls(String), comparison, guide
    var id: String {
        switch self {
        case .controls(let id): return "controls-\(id)"
        case .comparison: return "comparison"
        case .guide: return "guide"
        }
    }
}

struct ExperimentsView: View {
    @Bindable var store: LabStore
    @State private var mode = "Compare"
    @State private var metric: MetricKind = .radius
    @State private var path: [String] = []
    @State private var sheet: LabSheet?

    private var worlds: [TorusWorld] { mode == "Compare" ? store.comparedWorlds : store.lab.worlds }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Small beginnings. Different possibilities.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        Picker("View", selection: $mode) {
                            Text("Observe").tag("Observe")
                            Text("Compare").tag("Compare")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("viewMode")

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: geometry.size.width > 680 ? 300 : geometry.size.width - 32), spacing: 16)], spacing: 16) {
                            ForEach(worlds) { world in
                                WorldCard(world: world, store: store, onInspect: {
                                    store.selectedWorldID = world.id
                                    path.append(world.id)
                                }, onControls: {
                                    store.selectedWorldID = world.id
                                    sheet = .controls(world.id)
                                })
                            }
                        }
                        if worlds.isEmpty {
                            ContentUnavailableView("Choose your worlds", systemImage: "circle.grid.2x2", description: Text("Select two experiments to compare how they grow."))
                        }
                        GrowthPanel(worlds: worlds, store: store, metric: $metric)
                        QuickControls(store: store, onMore: { sheet = .controls(store.selectedWorldID) })
                        if let message = store.persistenceMessage {
                            Label(message, systemImage: "externaldrive.badge.exclamationmark")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                            Text("\(store.simulatedTime) simulated")
                            Spacer()
                            Button("How it grows") { sheet = .guide }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("Experiments")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Choose comparisons", systemImage: "rectangle.on.rectangle") { sheet = .comparison }
                    Button("Add torus", systemImage: "plus") { store.addWorld(); mode = "Observe" }
                        .disabled(store.lab.worlds.count >= 6)
                        .accessibilityIdentifier("addWorld")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TransportBar(store: store) {
                    path.append(store.selectedWorldID)
                }
            }
            .navigationDestination(for: String.self) { id in
                WorldDetailView(store: store, worldID: id)
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .controls(let id): WorldControlsSheet(store: store, worldID: id)
                case .comparison: ComparisonSheet(store: store)
                case .guide: SimulationGuide()
                }
            }
        }
    }
}

private struct WorldCard: View {
    let world: TorusWorld
    @Bindable var store: LabStore
    let onInspect: () -> Void
    let onControls: () -> Void

    private var subtitle: String {
        let p = world.parameters
        if p.energyInput > 0.72 { return "High energy" }
        if p.linkStrength > 0.75 { return "Strong bonds" }
        if p.turbulence > 0.6 { return "Turbulent" }
        return "Balanced"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(store.color(for: world.id)).frame(width: 9, height: 9)
                Button(action: onInspect) { Text(world.name).font(.headline).foregroundStyle(.primary) }
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button("Inspect particles", systemImage: "viewfinder", action: onInspect)
                    Button("World controls", systemImage: "slider.horizontal.3", action: onControls)
                    Button("Clone experiment", systemImage: "square.on.square") { store.clone(world.id) }
                        .disabled(store.lab.worlds.count >= 6)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36).foregroundStyle(.secondary)
                }
                .accessibilityLabel("\(world.name) actions")
            }
            .padding(.horizontal, 14).padding(.vertical, 3)

            TorusViewport(world: world, showFields: store.showFields, showTrails: store.showTrails, selectedParticleID: nil, isRunning: store.lab.isRunning)
                .aspectRatio(2.05, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 5)
                .overlay(alignment: .bottomTrailing) {
                    Button(action: onInspect) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold)).padding(10)
                    }
                    .buttonStyle(.glass)
                    .tint(.white)
                    .accessibilityLabel("Dive into \(world.name)")
                    .padding(12)
                }

            HStack(spacing: 0) {
                metricValue("\(world.metrics.population)", label: "particles")
                Divider().frame(height: 16)
                metricValue("\(Int(world.metrics.coherentProportion * 100))%", label: "coherent")
                Divider().frame(height: 16)
                metricValue("\(world.metrics.matureCount)", label: "at rim")
            }
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func metricValue(_ value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(value).fontWeight(.semibold).monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
        .font(.caption).frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct TransportBar: View {
    @Bindable var store: LabStore
    var worldTime: Double? = nil
    var onInspect: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(store.lab.isRunning ? "Pause simulation" : "Run simulation", systemImage: store.lab.isRunning ? "pause.fill" : "play.fill") {
                store.lab.isRunning.toggle()
            }
            .labelStyle(.iconOnly).frame(width: 40, height: 40)
            .buttonStyle(.glass).accessibilityIdentifier("playPause")
            Button("Advance one step", systemImage: "forward.end.fill") { store.lab.stepOnce() }
                .labelStyle(.iconOnly).frame(width: 30, height: 40)
                .disabled(store.lab.isRunning).accessibilityIdentifier("stepOnce")
            Picker("Simulation speed", selection: $store.lab.speed) {
                Text("1×").tag(1.0)
                Text("4×").tag(4.0)
                Text("12×").tag(12.0)
            }
            .pickerStyle(.segmented).frame(maxWidth: 180)
            if let onInspect {
                Button("Inspect \(store.selectedWorld.name)", action: onInspect)
                    .font(.callout).lineLimit(1).minimumScaleFactor(0.75)
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                    .accessibilityIdentifier("inspectWorld")
            } else {
                Text(worldTime.map(store.formattedTime) ?? store.simulatedTime).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

private struct QuickControls: View {
    @Bindable var store: LabStore
    let onMore: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("\(store.selectedWorld.name) controls", systemImage: "slider.horizontal.3").font(.headline)
                Spacer()
                Button("All settings", action: onMore).font(.subheadline)
            }
            HStack {
                Text("Energy").font(.subheadline)
                Slider(value: store.parameterBinding(\.energyInput, worldID: store.selectedWorldID), in: 0...1)
                    .accessibilityLabel("Energy input")
                Text(store.selectedWorld.parameters.energyInput, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit()).frame(width: 40)
            }
            Divider()
            Toggle("Show field lines", isOn: $store.showFields).font(.subheadline)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ComparisonSheet: View {
    @Bindable var store: LabStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.lab.worlds) { world in
                        Toggle(world.name, isOn: Binding(get: { store.comparisonIDs.contains(world.id) }, set: { include in
                            if include {
                                if store.comparisonIDs.count == 2 { store.comparisonIDs.removeFirst() }
                                store.comparisonIDs.append(world.id)
                            } else { store.comparisonIDs.removeAll { $0 == world.id } }
                        }))
                    }
                } footer: { Text("Choose up to two worlds. Cloning an experiment copies its complete state so you can change one condition and compare what happens.") }
            }
            .navigationTitle("Compare worlds").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
