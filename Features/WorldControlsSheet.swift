import SwiftUI

struct WorldControlsSheet: View {
    @Bindable var store: LabStore
    let worldID: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    private var world: TorusWorld { store.world(worldID) ?? store.selectedWorld }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ParameterRow(title: "Energy", symbol: "bolt", value: store.parameterBinding(\.energyInput, worldID: worldID), identifier: "energyInput")
                    ParameterRow(title: "Dust influx", symbol: "sparkles", value: store.parameterBinding(\.dustInput, worldID: worldID), identifier: "dustInput")
                } header: { Text("Inputs") } footer: {
                    Text("Dust creates new particles. Energy fuels motion, but too much can disturb alignment.")
                }
                Section {
                    ParameterRow(title: "Turbulence", symbol: "wind", value: store.parameterBinding(\.turbulence, worldID: worldID), identifier: "turbulence")
                    ParameterRow(title: "Link strength", symbol: "link", value: store.parameterBinding(\.linkStrength, worldID: worldID), identifier: "linkStrength")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Polarity bias", systemImage: "plusminus")
                            Spacer()
                            Text(world.parameters.polarityBias, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: store.parameterBinding(\.polarityBias, worldID: worldID), in: -1...1)
                            .accessibilityLabel("Polarity bias")
                        HStack { Text("Negative"); Spacer(); Text("Balanced"); Spacer(); Text("Positive") }
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: { Text("Relationships") } footer: {
                    Text("Strong bonds help particles synchronize, but make it harder to change direction. Bias changes the polarity of new particles.")
                }
                Section("Display") {
                    Toggle("Show field lines", isOn: $store.showFields).accessibilityIdentifier("showFields")
                    Toggle("Show motion trails", isOn: $store.showTrails).accessibilityIdentifier("showTrails")
                }
                Section("Experiment") {
                    Menu("Apply preset", systemImage: "slider.horizontal.3") {
                        Button("Balanced") { store.apply(.setParameters(.balanced), to: worldID) }
                        Button("High energy") { store.apply(.setParameters(.energetic), to: worldID) }
                        Button("Strong bonds") { store.apply(.setParameters(.cooperative), to: worldID) }
                    }
                    Button("Clone experiment", systemImage: "square.on.square") {
                        store.clone(worldID)
                        dismiss()
                    }
                    .disabled(store.lab.worlds.count >= 6).accessibilityIdentifier("cloneExperiment")
                    Button("Restart from the beginning", systemImage: "arrow.counterclockwise", role: .destructive) { confirmReset = true }
                }
                Section("Input efficiency") {
                    LabeledContent("Births / 100 dust", value: efficiency(world.metrics.birthsPer100Dust))
                    LabeledContent("Radius / 100 dust", value: efficiency(world.metrics.radiusGrowthPer100Dust))
                    LabeledContent("Radius / 100 energy", value: efficiency(world.metrics.radiusGrowthPer100Energy))
                    Text("Measured since the last comparison baseline. Added dust and particle energy are included.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(world.name) controls").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.save(); dismiss() } } }
            .confirmationDialog("Restart \(world.name)?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Restart experiment", role: .destructive) { store.reset(worldID) }
            } message: { Text("The current population and history will be reset. Your current parameter settings are kept.") }
        }
        .presentationDetents([.large])
    }

    private func efficiency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2)))
    }
}

private struct ParameterRow: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let identifier: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...1)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 5)
    }
}

struct SimulationGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A small particle can change an entire world.").font(.title2.bold())
                    Text("Nano is an open sandbox inspired by The Little Nanoparticle That Could. Each world runs on the same fictional rules. Change its conditions and follow the lives that emerge.")
                }
                Section("The cycle") {
                    Label("Dust gathers until a new particle forms.", systemImage: "sparkles")
                    Label("Opposite polarities attract; matching ones repel.", systemImage: "plusminus")
                    Label("Steady motion and compatible bonds build coherence.", systemImage: "link")
                    Label("Calm, coherent particles join the outer ring.", systemImage: "circle.dotted.circle")
                    Label("The rim supports expansion and guides the next generation.", systemImage: "arrow.triangle.branch")
                }
                Section("Explore") {
                    Text("Tap Inspect, then tap a particle. Pinch to look closer; pan with two fingers. Double-tap with two fingers to reset the view.")
                    Text("Pause to intervene precisely. Flip polarity, add energy, change a trajectory, or release a bond. Nothing moves while paused until you step or resume.")
                }
                Section("Compare") {
                    Text("Clone a world to copy its state and start a comparison baseline. Change one condition, then compare population, coherence, mature rim, radius, or growth rate. There is no single winning score.")
                    Text("Rates use simulated time. Coherence is the fraction of mobile particles above the coherence threshold; mature rim particles are counted separately.")
                }
                Section {
                    Text("The glass torus is a visual metaphor. This is a fictional particle ecology, not a model of quantum mechanics.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How it grows").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
