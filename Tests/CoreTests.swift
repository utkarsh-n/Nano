import Foundation
import Testing
@testable import NanoCore

@Suite("Deterministic torus ecology")
struct CoreTests {
    private func run(_ world: inout TorusWorld, seconds: Int) {
        for _ in 0..<(seconds * 30) { world.step() }
    }

    @Test("Presets share a real initial state and begin with empty growth history")
    func initialConditions() {
        let lab = ExperimentLab.makeDefault()
        #expect(lab.worlds.count == 3)
        #expect(lab.worlds.map(\.name) == ["Aster", "Mica", "Nova"])
        #expect(lab.worlds[0].particles == lab.worlds[1].particles)
        #expect(lab.worlds[0].dust == lab.worlds[2].dust)
        #expect(lab.worlds[0].parameters != lab.worlds[1].parameters)
        for world in lab.worlds {
            #expect(world.time == 0)
            #expect(world.radius == 1)
            #expect(world.metrics.matureCount == 0)
            #expect(world.history.count == 1)
            #expect(world.history[0].time == 0)
            #expect(world.metrics.growthPerMinute == 0)
            #expect(world.metrics.radiusGrowthPer100Dust == nil)
        }
    }

    @Test("Cloning preserves future evolution even when world identity changes")
    func deterministicClone() {
        var first = TorusWorld(id: "a", name: "Original", seed: 730, parameters: .balanced)
        run(&first, seconds: 12)
        var clone = first.clone(id: "b", name: "Different identity")
        for _ in 0..<900 {
            first.step()
            clone.step()
        }
        clone.id = first.id
        clone.name = first.name
        #expect(first == clone)
    }

    @Test("Changing field conditions produces substantive different outcomes")
    func parameterConsequences() {
        var balanced = TorusWorld(id: "a", name: "Balanced", seed: 46_021, parameters: .balanced)
        var energetic = TorusWorld(id: "b", name: "Energetic", seed: 46_021, parameters: .energetic)
        run(&balanced, seconds: 60)
        run(&energetic, seconds: 60)
        #expect(balanced.particles != energetic.particles)
        #expect(balanced.metrics.matureCount > energetic.metrics.matureCount)
        #expect(abs(balanced.metrics.meanCoherence - energetic.metrics.meanCoherence) > 0.05)
        #expect(balanced.energyInputTotal != energetic.energyInputTotal)
        print("60 s evidence — balanced: population \(balanced.metrics.population), mature \(balanced.metrics.matureCount), coherence \(balanced.metrics.coherentProportion), radius \(balanced.radius); energetic: population \(energetic.metrics.population), mature \(energetic.metrics.matureCount), coherence \(energetic.metrics.coherentProportion), radius \(energetic.radius)")
    }

    @Test("Maturity creates a real inherited cohort and material-backed expansion")
    func generativeLineage() {
        var world = TorusWorld(id: "a", name: "Lineage", seed: 46_021, parameters: .balanced)
        run(&world, seconds: 90)
        #expect(world.metrics.matureCount > 0)
        let children = world.particles.filter { $0.parentID != nil }
        #expect(!children.isEmpty)
        for child in children {
            let parent = world.particles.first { $0.id == child.parentID }
            #expect(parent?.isMature == true)
            #expect(child.generation == (parent?.generation ?? -1) + 1)
        }
        #expect(world.radius > 1.002)
        #expect(world.structuralDustSpent > 0)
        #expect(abs(world.structuralDustSpent - (world.radius - 1) * 80) < 0.000_001)
        for kind in [SimulationEventKind.formation, .bond, .rimHarmony, .legacy, .expansion] {
            #expect(world.events.contains { $0.kind == kind })
        }
        #expect(world.events.allSatisfy { $0.time <= world.time })
    }

    @Test("Expansion opens mature roles for descendants rather than freezing the first cohort")
    func laterGenerations() {
        var world = TorusWorld(id: "future", name: "Future", seed: 46_021, parameters: .balanced)
        run(&world, seconds: 240)
        #expect(world.metrics.matureCount > 24)
        #expect(world.particles.contains { $0.generation >= 2 })
        #expect(world.metrics.mobileCount >= 1)
        #expect(world.capacity > 40)
        #expect(world.metrics.matureCount <= world.matureCapacity)
        #expect(abs(world.totalMaterial - world.initialMaterialTotal - world.dustInputTotal) < 0.000_001)
        print("240 s lineage — population \(world.metrics.population), mature \(world.metrics.matureCount), generation \(world.particles.map(\.generation).max() ?? 0), radius \(world.radius)")
    }

    @Test("Slider bursts coalesce and repeated interventions preserve one-time story evidence")
    func eventRetention() {
        var world = TorusWorld(id: "events", name: "Events", seed: 46_021, parameters: .balanced)
        run(&world, seconds: 20)
        let story = world.events.filter { $0.kind != .intervention }
        #expect(story.contains { $0.kind == .formation })
        #expect(story.contains { $0.kind == .rimHarmony })
        for index in 0..<300 {
            var parameters = world.parameters
            parameters.dustInput = index.isMultiple(of: 2) ? 0.4 : 0.5
            world.apply(.setParameters(parameters))
        }
        #expect(world.events.filter { $0.title == "Conditions changed" }.count == 1)
        for _ in 0..<90 { world.apply(.flipPolarity(particleID: 1)) }
        #expect(world.events.count <= 64)
        for event in story { #expect(world.events.contains(event)) }
    }

    @Test("Growth rate uses exactly 30 simulated seconds at fractional-second ticks")
    func exactGrowthWindow() {
        var world = TorusWorld(id: "rate", name: "Rate", seed: 46_021, parameters: .balanced)
        var radii = [world.radius]
        for tick in 1...1_877 {
            world.step()
            radii.append(world.radius)
            if [901, 1_217, 1_877].contains(tick) {
                let expected = (world.radius - radii[tick - 900]) / 30 * 60
                #expect(abs(world.metrics.growthPerMinute - expected) < 0.000_000_001)
            }
        }
        world.startComparisonBaseline()
        let startRadius = world.radius
        for _ in 0..<45 { world.step() }
        #expect(abs(world.metrics.growthPerMinute - (world.radius - startRadius) / 1.5 * 60) < 0.000_000_001)
    }

    @Test("Micro commands are local and their external inputs are accounted for")
    func localInterventions() {
        var lab = ExperimentLab.makeDefault()
        let untouched = lab.worlds[1]
        let original = lab.worlds[0]
        let particleID = original.particles[5].id
        lab.apply(.flipPolarity(particleID: particleID), to: "aster")
        lab.apply(.energize(particleID: particleID, amount: 0.35), to: "aster")
        lab.apply(.nudge(particleID: particleID, direction: Vector2(x: 1, y: 0.2)), to: "aster")
        lab.apply(.seedDust(position: Vector2(x: 0.7, y: 0), amount: 6), to: "aster")
        #expect(lab.worlds[1] == untouched)
        #expect(lab.worlds[0].particles[5].polarity == -original.particles[5].polarity)
        #expect(lab.worlds[0].particles[5].velocity != original.particles[5].velocity)
        #expect(lab.worlds[0].dustInputTotal == 6)
        #expect(lab.worlds[0].energyInputTotal > 0.45)
        #expect(abs(lab.worlds[0].totalMaterial - original.totalMaterial - 6) < 0.000_001)
        #expect(lab.worlds[0].events.filter { $0.kind == .intervention }.count == 4)
    }

    @Test("Finite state, population limits, reciprocal graph and conserved material survive extremes")
    func boundedStressRun() {
        var world = TorusWorld(id: "stress", name: "Stress", seed: 908,
            parameters: TorusParameters(dustInput: 1, energyInput: 1, polarityBias: 0, turbulence: 1, linkStrength: 1))
        for step in 0..<2_400 {
            if step.isMultiple(of: 150), let particle = world.particles.last {
                world.apply(.flipPolarity(particleID: particle.id))
                world.apply(.nudge(particleID: particle.id, direction: Vector2(x: -0.3, y: 0.8)))
            }
            world.step()
            if !step.isMultiple(of: 60) { continue }
            #expect(world.particles.count <= TorusWorld.maximumPopulation)
            #expect(world.particles.count <= world.capacity)
            #expect(world.radius.isFinite && world.radius >= 1 && world.radius <= 2.5)
            #expect(Set(world.particles.map(\.id)).count == world.particles.count)
            #expect(world.dust.allSatisfy { $0.amount.isFinite && $0.amount >= -0.000_001 })
            #expect(abs(world.totalMaterial - world.initialMaterialTotal - world.dustInputTotal) < 0.000_001)
            for particle in world.particles {
                #expect(particle.position.isFinite && particle.velocity.isFinite)
                #expect((0...1).contains(particle.energy) && (0...1).contains(particle.coherence))
                #expect(particle.position.length >= world.radius * 0.365 - 0.000_001)
                #expect(particle.position.length <= world.radius * 0.978 + 0.000_001)
                #expect(particle.trail.count <= 12)
                #expect(world.bonds.filter { $0.a == particle.id || $0.b == particle.id }.count <= 2)
            }
            for bond in world.bonds {
                let a = world.particles.first { $0.id == bond.a }
                let b = world.particles.first { $0.id == bond.b }
                #expect(a != nil && b != nil && bond.a != bond.b)
                #expect(a?.polarity != b?.polarity)
                #expect(a?.isMature == false && b?.isMature == false)
            }
        }
    }

    @Test("Zero field input is reported as zero and cannot create unlimited material")
    func zeroInput() {
        var world = TorusWorld(id: "zero", name: "Zero", seed: 40,
            parameters: TorusParameters(dustInput: 0, energyInput: 0, polarityBias: 0, turbulence: 0.1, linkStrength: 0.5))
        run(&world, seconds: 60)
        #expect(world.dustInputTotal == 0)
        #expect(world.energyInputTotal == 0)
        #expect(world.metrics.birthsPer100Dust == nil)
        #expect(world.metrics.radiusGrowthPer100Energy == nil)
        #expect(abs(world.totalMaterial - world.initialMaterialTotal) < 0.000_001)
        #expect(world.radius <= 1 + 12.0 / 80)
    }

    @Test("A saved state resumes exactly, including lineage, randomness and metrics")
    func codableRoundTrip() throws {
        var original = ExperimentLab.makeDefault()
        original.advance(steps: 360)
        original.apply(.seedDust(position: Vector2(x: -0.6, y: 0.2), amount: 5), to: "nova")
        let encoded = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(ExperimentLab.self, from: encoded)
        #expect(restored == original)
        original.advance(steps: 300)
        restored.advance(steps: 300)
        #expect(restored == original)
    }

    @Test("Clone comparison starts at one common observed baseline")
    func comparisonBaseline() {
        var lab = ExperimentLab.makeDefault()
        lab.advance(steps: 450)
        lab.cloneWorld(sourceID: "aster", targetID: "mica")
        #expect(lab.worlds[0].particles == lab.worlds[1].particles)
        #expect(lab.worlds[0].comparisonBaseline == lab.worlds[1].comparisonBaseline)
        #expect(lab.worlds[0].history.count == 1)
        #expect(lab.worlds[0].history[0].time == 15)
        #expect(lab.worlds[0].metrics.radiusGrowthPer100Dust == nil)
        lab.advance(steps: 90)
        #expect(lab.worlds[0].metrics == lab.worlds[1].metrics)
        #expect(lab.worlds[0].history == lab.worlds[1].history)
    }

    @Test("Pause and malformed commands cannot move or corrupt a world")
    func pauseAndInvalidInput() {
        var lab = ExperimentLab.makeDefault()
        lab.isRunning = false
        let before = lab.worlds
        lab.advance(steps: 30)
        #expect(lab.worlds == before)
        lab.apply(.seedDust(position: Vector2(x: .nan, y: 0), amount: 10), to: "aster")
        lab.apply(.energize(particleID: 1, amount: .infinity), to: "aster")
        lab.apply(.nudge(particleID: 1, direction: Vector2(x: .nan, y: 0)), to: "aster")
        #expect(lab.worlds == before)
        lab.stepOnce()
        #expect(lab.worlds.allSatisfy { $0.tick == 1 })
    }

    @Test("Stardust adds real material while paused and can become a particle on a step")
    func playbookStardust() {
        var lab = ExperimentLab.makeDefault()
        lab.isRunning = false
        let before = lab.worlds[0]
        let commands = WorldPlaybook.commands(for: .stardust, in: before)
        #expect(commands.count == 1)
        guard case let .seedDust(position, amount) = commands[0] else {
            Issue.record("Stardust must prepare a material input command.")
            return
        }
        #expect(position.isFinite)
        #expect(position.length >= before.radius * 0.40 && position.length <= before.radius * 0.87)
        #expect(amount >= TorusWorld.particleMaterial && amount <= 8)
        #expect(commands == WorldPlaybook.commands(for: .stardust, in: before.clone(id: "clone", name: "Clone")))
        for command in commands { lab.apply(command, to: before.id) }
        #expect(lab.worlds[0].dustInputTotal == before.dustInputTotal + amount)
        #expect(abs(lab.worlds[0].totalMaterial - before.totalMaterial - amount) < 0.000_001)
        #expect(lab.worlds[0].birthCount == before.birthCount)
        let paused = lab.worlds[0]
        lab.advance(steps: 90)
        #expect(lab.worlds[0] == paused)
        lab.stepOnce()
        #expect(lab.worlds[0].birthCount > before.birthCount)
        #expect(lab.worlds[0].events.contains { $0.kind == .formation })
    }

    @Test("A pulse energizes a small mobile group without moving time or changing elders")
    func playbookPulse() {
        var world = TorusWorld(id: "pulse", name: "Pulse", seed: 46_021, parameters: .balanced)
        run(&world, seconds: 4)
        let before = world
        let commands = WorldPlaybook.commands(for: .pulse, in: world)
        #expect(!commands.isEmpty && commands.count <= 8)
        var recipientIDs: Set<Int> = []
        var injected = 0.0
        for command in commands {
            guard case let .energize(particleID, amount) = command else {
                Issue.record("A pulse must use the existing measured energy input command.")
                return
            }
            #expect(before.particles.first(where: { $0.id == particleID })?.isMature == false)
            #expect(amount > 0 && amount <= 0.16)
            recipientIDs.insert(particleID)
            injected += amount
            world.apply(command)
        }
        #expect(recipientIDs.count == commands.count)
        #expect(world.time == before.time)
        #expect(abs(world.energyInputTotal - before.energyInputTotal - injected) < 0.000_001)
        for original in before.particles {
            guard let particle = world.particles.first(where: { $0.id == original.id }) else { continue }
            #expect(particle.position == original.position && particle.velocity == original.velocity)
            if recipientIDs.contains(original.id) {
                #expect(particle.energy > original.energy && particle.energy <= 0.90)
            } else {
                #expect(particle == original)
            }
        }
    }

    @Test("Full worlds store stardust honestly and do not promise or manufacture births")
    func playbookFullCapacity() {
        var world = TorusWorld(id: "full", name: "Full", seed: 46_021, parameters: .balanced)
        let prototype = world.particles[5]
        while world.particles.count < world.capacity {
            var particle = prototype
            particle.id = 1_000 + world.particles.count
            world.particles.append(particle)
        }
        let population = world.particles.count
        let material = world.totalMaterial
        #expect(WorldPlaybook.feedback(for: .stardust, in: world).contains("stored"))
        #expect(WorldPlaybook.feedback(for: .stardust, in: world).contains("room"))
        for command in WorldPlaybook.commands(for: .stardust, in: world) { world.apply(command) }
        #expect(abs(world.totalMaterial - material - 6) < 0.000_001)
        world.step()
        #expect(world.particles.count == population)
        #expect(world.birthCount == 0)
    }

    @Test("A pulse does not waste energy on mature or already highly energized particles")
    func playbookPulseWithoutRecipients() {
        var world = TorusWorld(id: "rest", name: "Rest", seed: 46_021, parameters: .balanced)
        for index in world.particles.indices { world.particles[index].isMature = true }
        #expect(WorldPlaybook.commands(for: .pulse, in: world).isEmpty)
        #expect(WorldPlaybook.feedback(for: .pulse, in: world).contains("no wandering"))
        for index in world.particles.indices {
            world.particles[index].isMature = false
            world.particles[index].energy = 0.98
        }
        #expect(WorldPlaybook.commands(for: .pulse, in: world).isEmpty)
        #expect(WorldPlaybook.feedback(for: .pulse, in: world).contains("plenty of energy"))
    }

    @Test("Discoveries recognize real existing worlds and preserve previously earned milestones")
    func playbookDiscoveries() throws {
        var world = TorusWorld(id: "discoveries", name: "Discoveries", seed: 46_021, parameters: .balanced)
        let initial = WorldPlaybook.discoveries(in: world, progress: WorldPlayProgress())
        #expect(initial.count == 6 && Set(initial.map(\.id)).count == 6)
        #expect(initial.allSatisfy { !$0.isUnlocked })

        run(&world, seconds: 90)
        let restoredWorld = try JSONDecoder().decode(TorusWorld.self, from: JSONEncoder().encode(world))
        let discoveries = WorldPlaybook.discoveries(in: restoredWorld, progress: WorldPlayProgress())
        #expect(discoveries.first { $0.id == "sowed-dust" }?.isUnlocked == false)
        #expect(discoveries.filter { $0.id != "sowed-dust" }.allSatisfy { $0.isUnlocked })

        var progress = WorldPlayProgress()
        progress.unlockedDiscoveryIDs.formUnion(discoveries.filter(\.isUnlocked).map(\.id))
        let restoredProgress = try JSONDecoder().decode(WorldPlayProgress.self, from: JSONEncoder().encode(progress))
        #expect(restoredProgress == progress)
        let quietWorld = TorusWorld(id: world.id, name: world.name, seed: world.seed, parameters: .balanced)
        let retained = WorldPlaybook.discoveries(in: quietWorld, progress: restoredProgress)
        #expect(retained.filter(\.isUnlocked).map(\.id) == discoveries.filter(\.isUnlocked).map(\.id))

        // Ambient input cannot award the player's dust action; a recorded manual drop can.
        for command in WorldPlaybook.commands(for: .stardust, in: world) { world.apply(command) }
        #expect(WorldPlaybook.discoveries(in: world, progress: WorldPlayProgress())
            .first { $0.id == "sowed-dust" }?.isUnlocked == true)
    }
}
