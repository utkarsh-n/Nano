import SwiftUI

struct WorldDetailView: View {
    @Bindable var store: LabStore
    let worldID: String
    @State private var selectedParticleID: Int?
    @State private var sheet: LabSheet?
    @State private var particleList = false
    @State private var showHistory = false

    private var world: TorusWorld { store.world(worldID) ?? store.selectedWorld }
    private var particle: TorusParticle? {
        world.particles.first { $0.id == selectedParticleID } ?? world.particles.first { !$0.isMature } ?? world.particles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(world.stageLabel).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("Radius \(world.radius.formatted(.number.precision(.fractionLength(2))))×")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                TorusViewport(world: world, showFields: store.showFields, showTrails: store.showTrails, selectedParticleID: particle?.id, onSelectParticle: { selectedParticleID = $0 }, isRunning: store.lab.isRunning)
                    .aspectRatio(1.3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(alignment: .topLeading) {
                        if let event = world.events.last(where: { $0.kind != .intervention }) {
                            Text(event.title)
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.black.opacity(0.65), in: Capsule()).padding(12)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    Label("Tap a particle. Pinch to explore.", systemImage: "hand.draw").foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose") { particleList = true }
                }
                .font(.caption)
                if let particle {
                    ParticleInspector(particle: particle, world: world, store: store)
                }
                HStack {
                    Button("Add a little dust", systemImage: "sparkles") {
                        store.apply(.seedDust(position: Vector2(x: world.radius * 0.6, y: 0), amount: 8), to: worldID)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Story", systemImage: "text.book.closed") { showHistory = true }.buttonStyle(.bordered)
                }
                .font(.subheadline)
                Text("Every particle is part of this experiment. Actions here affect \(world.name) only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(world.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("World controls", systemImage: "slider.horizontal.3") { sheet = .controls(worldID) }
                    .accessibilityIdentifier("worldControls")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { TransportBar(store: store, worldTime: world.time) }
        .onAppear {
            store.selectedWorldID = worldID
            if selectedParticleID == nil { selectedParticleID = particle?.id }
        }
        .sheet(item: $sheet) { _ in WorldControlsSheet(store: store, worldID: worldID) }
        .sheet(isPresented: $particleList) {
            ParticleChooser(world: world, selectedParticleID: $selectedParticleID)
        }
        .sheet(isPresented: $showHistory) { StoryHistory(store: store, worldID: worldID, onFollow: { id in selectedParticleID = id }) }
    }
}

private struct ParticleInspector: View {
    let particle: TorusParticle
    let world: TorusWorld
    let store: LabStore

    private var bonds: [TorusBond] { world.bonds.filter { $0.a == particle.id || $0.b == particle.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(uiImage: ParticleArtwork.image(for: particle))
                    .resizable().scaledToFit().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nano \(particle.id)").font(.title3.bold())
                    Text("Generation \(particle.generation) · \(particle.isMature ? "At the glass" : "Finding a way")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(particle.polarity > 0 ? "Positive" : "Negative")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(particle.polarity > 0 ? .orange : .blue)
                    .accessibilityIdentifier("particlePolarity")
            }
            HStack {
                value("Energy", value: "\(Int(particle.energy * 100))%")
                Divider().frame(height: 30)
                value("Coherence", value: "\(Int(particle.coherence * 100))%")
                Divider().frame(height: 30)
                value("Bonds", value: "\(bonds.count)")
            }
            if let parentID = particle.parentID {
                Label("Inherited from Nano \(parentID)", systemImage: "arrow.triangle.branch")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 10) {
                Button("Flip polarity", systemImage: "plusminus") {
                    store.apply(.flipPolarity(particleID: particle.id), to: world.id)
                }
                .accessibilityIdentifier("flipPolarity")
                Button("Energize", systemImage: "bolt") {
                    store.apply(.energize(particleID: particle.id, amount: 0.2), to: world.id)
                }
                .accessibilityIdentifier("energizeParticle")
            }
            .buttonStyle(.bordered).controlSize(.regular)
            HStack(spacing: 10) {
                Button("Nudge outward", systemImage: "arrow.up.right") {
                    store.apply(.nudge(particleID: particle.id, direction: particle.position), to: world.id)
                }
                .accessibilityIdentifier("nudgeParticle")
                Button("Release bonds", systemImage: "link.badge.plus") {
                    for bond in bonds { store.apply(.dissolveBond(bondID: bond.id), to: world.id) }
                }
                .disabled(bonds.isEmpty)
            }
            .buttonStyle(.bordered).controlSize(.regular)
            .disabled(particle.isMature)
            if particle.isMature {
                Text("At the glass, this particle supports the ring and helps the next generation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func value(_ label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ParticleChooser: View {
    let world: TorusWorld
    @Binding var selectedParticleID: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(world.particles) { particle in
                Button {
                    selectedParticleID = particle.id
                    dismiss()
                } label: {
                    HStack {
                        Image(uiImage: ParticleArtwork.image(for: particle))
                            .resizable().scaledToFit().frame(width: 36, height: 36)
                        VStack(alignment: .leading) {
                            Text("Nano \(particle.id)").foregroundStyle(.primary)
                            Text("Generation \(particle.generation) · \(particle.isMature ? "At rim" : "Mobile")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedParticleID == particle.id { Image(systemName: "checkmark") }
                    }
                }
            }
            .navigationTitle("Follow a particle").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private enum ParticleArtwork {
    static let pearl = load("NanoPearl")
    static let warmJewel = load("NanoGold")
    static let coolCrystal = load("NanoCrystal")

    static func image(for particle: TorusParticle) -> UIImage {
        particle.isMature ? pearl : particle.polarity > 0 ? warmJewel : coolCrystal
    }

    private static func load(_ name: String) -> UIImage {
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let image = UIImage(contentsOfFile: path) else { return UIImage() }
        return image
    }
}

private struct StoryHistory: View {
    @Bindable var store: LabStore
    let worldID: String
    let onFollow: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private var events: [SimulationEvent] { (store.world(worldID)?.events ?? []).filter { $0.kind != .intervention }.reversed() }

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView("A story is forming", systemImage: "sparkles", description: Text("Run the simulation to see the first connections, new particles, and outer-ring arrivals."))
                }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(event.title).font(.headline)
                            Spacer()
                            Text("\(Int(event.time))s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(event.detail).font(.subheadline).foregroundStyle(.secondary)
                        if let id = event.particleID {
                            Button("Follow Nano \(id)") { onFollow(id); dismiss() }.font(.caption)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Inside the story").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
