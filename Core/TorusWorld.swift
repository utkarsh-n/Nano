import Foundation

/// An invented, deterministic particle ecology. Rendering and wall-clock time never enter its rules.
struct TorusWorld: Codable, Equatable, Identifiable, Sendable {
    static let fixedDelta: Double = 1.0 / 30.0
    static let maximumPopulation = 96
    static let particleMaterial = 4.0

    var id: String
    var name: String
    var seed: UInt64
    var parameters: TorusParameters
    var particles: [TorusParticle] = []
    var bonds: [TorusBond] = []
    var dust: [DustDeposit] = []
    var radius: Double = 1
    var tick: Int = 0
    var metrics = TorusMetrics()
    var history: [MetricSample] = []
    var events: [SimulationEvent] = []
    var comparisonBaseline = ComparisonBaseline()
    var dustInputTotal: Double = 0
    var energyInputTotal: Double = 0
    var structuralDustSpent: Double = 0
    var initialMaterialTotal: Double = 0
    var birthCount: Int = 0

    private var nextParticleID = 1
    private var nextBondID = 1
    private var nextEventID = 1
    private var nextDustID = 1
    private var bondDwell: [String: Double] = [:]
    private var milestones: Set<SimulationEventKind> = []
    private var lastParameterEventTick: Int?
    private var radiusWindow: [Double] = [1]
    private var radiusWindowStartTick: Int = 0

    var time: Double { Double(tick) * Self.fixedDelta }
    var capacity: Int { min(Self.maximumPopulation, Int((40 * radius * radius).rounded(.down))) }
    var matureCapacity: Int { min(64, max(8, capacity - 12)) }
    var deadZoneCenter: Vector2 { Vector2(x: -0.48 * radius, y: 0.38 * radius) }
    var deadZoneRadius: Double { 0.19 * radius }
    var availableDust: Double { dust.reduce(0) { $0 + $1.amount } }
    var totalMaterial: Double { Double(particles.count) * Self.particleMaterial + availableDust + structuralDustSpent }
    var stageLabel: String {
        if milestones.contains(.legacy) { return "A new generation" }
        if milestones.contains(.rimHarmony) { return "Outer harmony" }
        if milestones.contains(.learning) { return "Learning together" }
        if milestones.contains(.bond) { return "First connections" }
        return "Finding coherence"
    }

    init(id: String, name: String, seed: UInt64, parameters: TorusParameters) {
        self.id = id
        self.name = name
        self.seed = seed
        self.parameters = parameters.clamped
        // Equal starting matter and cohorts across presets; only subsequent conditions differ.
        for index in 0..<24 {
            let noise = SimulationNoise.unit(seed: seed, a: UInt64(index), channel: 1)
            let angle = Double(index) / 24 * .pi * 2 + (noise - 0.5) * 0.07
            let older = index < 4
            let distance = older ? 0.90 : 0.49 + noise * 0.32
            let radial = Vector2.polar(angle: angle)
            let position = radial * distance
            particles.append(TorusParticle(
                id: nextParticleID, position: position,
                velocity: radial.perpendicular * (older ? 0.22 : 0.16 + noise * 0.06) + radial * 0.015,
                energy: older ? 0.57 : 0.35 + noise * 0.25,
                coherence: older ? 0.78 : 0.30 + noise * 0.32,
                polarity: index.isMultiple(of: 2) ? 1 : -1, generation: 0, parentID: nil,
                age: older ? 24 : noise * 15, learningPreference: (noise - 0.5) * 0.20,
                trail: [position]
            ))
            nextParticleID += 1
        }
        for index in 0..<24 {
            dust.append(DustDeposit(id: nextDustID,
                position: .polar(angle: Double(index) / 24 * .pi * 2, radius: index.isMultiple(of: 2) ? 0.67 : 0.77),
                amount: 0.5))
            nextDustID += 1
        }
        initialMaterialTotal = totalMaterial
        refreshMetrics()
        history = [MetricSample(time: time, metrics: metrics)]
    }

    mutating func reset() {
        self = TorusWorld(id: id, name: name, seed: seed, parameters: parameters)
    }

    func clone(id: String, name: String) -> TorusWorld {
        var copy = self
        copy.id = id
        copy.name = name
        return copy
    }

    mutating func startComparisonBaseline() {
        comparisonBaseline = ComparisonBaseline(time: time, radius: radius, births: birthCount,
            dustInput: dustInputTotal, energyInput: energyInputTotal)
        radiusWindow = [radius]
        radiusWindowStartTick = tick
        history.removeAll(keepingCapacity: true)
        refreshMetrics()
        history.append(MetricSample(time: time, metrics: metrics))
    }

    mutating func apply(_ command: TorusCommand) {
        switch command {
        case .setParameters(let value):
            let newValue = value.clamped
            guard newValue != parameters else { return }
            parameters = newValue
            // Native sliders may send hundreds of changes during one gesture.
            if lastParameterEventTick == nil || tick - (lastParameterEventTick ?? tick) >= 30 {
                record(.intervention, "Conditions changed", "The field now follows your new conditions.")
                lastParameterEventTick = tick
            }
        case .flipPolarity(let particleID):
            guard let index = particles.firstIndex(where: { $0.id == particleID }) else { return }
            particles[index].polarity *= -1
            particles[index].energy = max(0, particles[index].energy - 0.02)
            removeInvalidBonds()
            record(.intervention, "Polarity inverted", "Attraction and repulsion change around this particle.", particleID: particleID)
        case .energize(let particleID, let amount):
            guard amount.isFinite, amount > 0,
                  let index = particles.firstIndex(where: { $0.id == particleID }) else { return }
            let input = min(amount, 10)
            particles[index].energy = bounded(particles[index].energy + input)
            energyInputTotal += input
            record(.intervention, "Energy added", "A local impulse joins the experiment's measured energy input.", particleID: particleID)
        case .nudge(let particleID, let direction):
            guard direction.isFinite, direction.length > 0.000_001,
                  let index = particles.firstIndex(where: { $0.id == particleID }), !particles[index].isMature else { return }
            let impulse = direction.limited(to: 1) * 0.22
            particles[index].velocity = (particles[index].velocity + impulse).limited(to: 0.85)
            particles[index].energy = bounded(particles[index].energy + 0.10)
            energyInputTotal += 0.10 + impulse.lengthSquared * 0.5
            record(.intervention, "Trajectory nudged", "A directional impulse changes this particle's path.", particleID: particleID)
        case .seedDust(let position, let amount):
            guard position.isFinite, amount.isFinite, amount > 0 else { return }
            let input = min(amount, 1_000)
            let radial = position.length > 0.000_001 ? position.normalized : Vector2(x: 1, y: 0)
            let point = radial * bounded(position.length, radius * 0.40, radius * 0.87)
            if let closest = dust.indices.min(by: { (dust[$0].position - point).lengthSquared < (dust[$1].position - point).lengthSquared }),
               (dust[closest].position - point).length < radius * 0.10 || dust.count >= 48 {
                dust[closest].amount += input
            } else {
                dust.append(DustDeposit(id: nextDustID, position: point, amount: input))
                nextDustID += 1
            }
            dustInputTotal += input
            record(.intervention, "Dust seeded", "New material gathers at the selected place.")
        case .dissolveBond(let bondID):
            guard let index = bonds.firstIndex(where: { $0.id == bondID }) else { return }
            let bond = bonds.remove(at: index)
            bondDwell.removeValue(forKey: pairKey(bond.a, bond.b))
            record(.intervention, "A bond released", "Both particles can find a new relationship.", particleID: bond.a)
        }
        refreshMetrics()
    }

    mutating func step() {
        let dt = Self.fixedDelta
        tick += 1
        parameters = parameters.clamped
        let newDust = parameters.dustInput * 2.4 * dt
        if !dust.isEmpty {
            // The external emitter follows the same timeline in matched experiments.
            let source = (tick / 120) % min(24, dust.count)
            dust[source].amount += newDust
            dustInputTotal += newDust
        }
        removeInvalidBonds()
        updateMotion(dt: dt)
        updateBonds(dt: dt)
        formParticles()
        expandStructure(dt: dt)
        // Keep actual tick observations for an exact 30-second rate, independent of chart sampling.
        radiusWindow.append(radius)
        if radiusWindow.count > 901 {
            radiusWindow.removeFirst()
            radiusWindowStartTick += 1
        }
        refreshMetrics()
        if tick.isMultiple(of: 30) {
            history.append(MetricSample(time: time, metrics: metrics))
            if history.count > 901 { history.removeFirst(history.count - 901) }
        }
    }

    private mutating func updateMotion(dt: Double) {
        let count = particles.count
        guard count > 0 else { return }
        let indices = Dictionary(uniqueKeysWithValues: particles.enumerated().map { ($0.element.id, $0.offset) })
        var forces = Array(repeating: Vector2.zero, count: count)
        var degree = Array(repeating: 0, count: count)
        var tension = Array(repeating: 0.0, count: count)
        var crowding = Array(repeating: 0, count: count)
        let reach = radius * 0.24

        if count > 1 {
            for first in 0..<(count - 1) {
                for second in (first + 1)..<count {
                    let delta = particles[second].position - particles[first].position
                    let distance = max(0.000_1, delta.length)
                    guard distance < reach else { continue }
                    let direction = delta / distance
                    let matching = particles[first].polarity == particles[second].polarity
                    let strength = (1 - distance / reach) * (matching ? -0.16 : 0.12)
                    var force = direction * strength
                    if distance < radius * 0.065 {
                        force -= direction * (0.38 * (1 - distance / (radius * 0.065)))
                        crowding[first] += 1
                        crowding[second] += 1
                    }
                    forces[first] += force
                    forces[second] -= force
                }
            }
        }

        for index in bonds.indices {
            guard let first = indices[bonds[index].a], let second = indices[bonds[index].b] else { continue }
            let delta = particles[second].position - particles[first].position
            let distance = max(0.000_1, delta.length)
            let stretch = distance - radius * 0.11
            let spring = delta / distance * stretch * (0.55 + parameters.linkStrength * 2.1)
            let damping = (particles[second].velocity - particles[first].velocity) * (parameters.linkStrength * 0.12)
            forces[first] += spring + damping
            forces[second] -= spring + damping
            degree[first] += 1
            degree[second] += 1
            let stress = abs(stretch) / (radius * 0.20)
            tension[first] += stress
            tension[second] += stress
            bonds[index].tension = bounded(stress)
            bonds[index].age += dt
        }

        let elders = particles.filter(\.isMature)
        var matureCount = elders.count
        for index in particles.indices {
            var particle = particles[index]
            particle.age += dt
            let supplied = parameters.energyInput * (particle.isMature ? 0.055 : 0.17) * dt
            energyInputTotal += supplied
            let drain = particle.isMature ? 0.038 * particle.energy : 0.014 + particle.velocity.length * 0.04 + particle.energy * 0.10 + Double(degree[index]) * parameters.linkStrength * 0.006
            particle.energy = bounded(particle.energy + supplied - drain * dt)
            let radial = particle.position.normalized

            if particle.isMature {
                let angle = atan2(particle.position.y, particle.position.x) + dt * 0.013
                particle.position = .polar(angle: angle, radius: radius * 0.97)
                particle.velocity = particle.position.normalized.perpendicular * (radius * 0.013)
                particle.coherence += (0.96 - particle.coherence) * dt * 0.5
                if tick.isMultiple(of: 6) { appendTrail(to: &particle) }
                particles[index] = particle
                continue
            }

            var harmony = 0.0
            for elder in elders {
                harmony = max(harmony, 1 - (elder.position - particle.position).length / (radius * 0.28))
            }
            harmony = bounded(harmony)
            let inDeadZone = (particle.position - deadZoneCenter).length < deadZoneRadius
            let heat = bounded((particle.energy - 0.72) / 0.28)
            let tangent = radial.perpendicular
            let outwardSpeed = max(0.003, 0.013 + particle.coherence * 0.033 + particle.learningPreference * 0.009 - Double(degree[index]) * parameters.linkStrength * 0.007)
            let targetSpeed = 0.10 + particle.energy * 0.20 + parameters.energyInput * 0.025
            let desired = tangent * targetSpeed + radial * outwardSpeed
            forces[index] += (desired - particle.velocity) * (0.85 / (1 + Double(degree[index]) * parameters.linkStrength * 0.35))
            let noise = Vector2(
                x: SimulationNoise.smooth(seed: seed, id: particle.id, tick: tick, channel: 11),
                y: SimulationNoise.smooth(seed: seed, id: particle.id, tick: tick, channel: 12))
            let disturbance = (parameters.turbulence * 0.28 + heat * 0.29 + (inDeadZone ? 0.20 : 0)) * (1 - harmony * 0.72)
            forces[index] += noise * disturbance
            if inDeadZone { forces[index] -= radial * 0.025 }
            particle.velocity = (particle.velocity + forces[index].limited(to: 1.2) * dt).limited(to: 0.85)
            particle.position += particle.velocity * dt
            confine(&particle)

            let alignment = bounded(particle.velocity.normalized.dot(tangent), 0, 1)
            let targetCoherence = bounded(0.18 + alignment * 0.73 + Double(degree[index]) * 0.055 + harmony * 0.10 - parameters.turbulence * 0.31 - heat * 0.38 - tension[index] * 0.14 - Double(crowding[index]) * 0.055 - (inDeadZone ? 0.23 : 0))
            particle.coherence += (targetCoherence - particle.coherence) * (1 - exp(-dt / 2.0))
            particle.coherence = bounded(particle.coherence)
            if degree[index] > 0 {
                let preference = bounded(particle.velocity.dot(radial) * 8 + Double(particle.polarity) * 0.06, -1, 1)
                particle.learningPreference += (preference - particle.learningPreference) * dt * 0.10
                if bonds.contains(where: { ($0.a == particle.id || $0.b == particle.id) && $0.age > 2 }) {
                    record(.learning, "A shared direction", "Time together leaves a preference that can outlast the bond.", particleID: particle.id)
                }
            }
            if particle.coherence > 0.68 && particle.age > 2 {
                record(.coherence, "A coherent vector", "A steady direction gives this particle a stronger path through the field.", particleID: particle.id)
            }
            if inDeadZone {
                particle.timeInDeadZone += dt
                if particle.timeInDeadZone > 1 {
                    particle.experiencedDeadZone = true
                    record(.deadZone, "Stillness can mislead", "A quiet-looking pocket disrupts the particle's direction.", particleID: particle.id)
                }
            } else {
                if particle.timeInDeadZone > 0 && particle.experiencedDeadZone {
                    record(.escape, "A way through", "Motion and new relationships carry a particle beyond the disturbed pocket.", particleID: particle.id)
                }
                particle.timeInDeadZone = 0
            }

            // Expansion opens structural roles for later cohorts while retaining a mobile population.
            let canMature = matureCount < matureCapacity && particle.position.length > radius * 0.88 && particle.coherence > 0.68 && particle.energy > 0.20 && particle.energy < 0.93 && particle.velocity.length < 0.50
            particle.maturityProgress = canMature ? particle.maturityProgress + dt : max(0, particle.maturityProgress - dt * 0.6)
            if particle.maturityProgress >= 1.6 {
                particle.isMature = true
                particle.position = particle.position.normalized * (radius * 0.97)
                particle.velocity = particle.position.normalized.perpendicular * (radius * 0.013)
                matureCount += 1
                record(.rimHarmony, "The outer ring answers", "A sustained coherent arrival becomes part of the structure and steadies nearby lives.", particleID: particle.id)
            }
            if tick.isMultiple(of: 6) { appendTrail(to: &particle) }
            particles[index] = particle
        }
        removeInvalidBonds()
    }

    private func confine(_ particle: inout TorusParticle) {
        let distance = particle.position.length
        let minimum = radius * 0.365
        let maximum = radius * 0.978
        let radial = distance > 0.000_001 ? particle.position / distance : Vector2(x: 1, y: 0)
        if distance < minimum {
            particle.position = radial * minimum
            let normalSpeed = particle.velocity.dot(radial)
            if normalSpeed < 0 { particle.velocity -= radial * (normalSpeed * 1.35) }
        } else if distance > maximum {
            particle.position = radial * maximum
            let normalSpeed = particle.velocity.dot(radial)
            if normalSpeed > 0 { particle.velocity -= radial * (normalSpeed * 1.25) }
        }
    }

    private func appendTrail(to particle: inout TorusParticle) {
        particle.trail.append(particle.position)
        if particle.trail.count > 12 { particle.trail.removeFirst(particle.trail.count - 12) }
    }

    private func pairKey(_ a: Int, _ b: Int) -> String { a < b ? "\(a):\(b)" : "\(b):\(a)" }

    private mutating func removeInvalidBonds() {
        let lookup = Dictionary(uniqueKeysWithValues: particles.map { ($0.id, $0) })
        bonds.removeAll { bond in
            guard let a = lookup[bond.a], let b = lookup[bond.b] else { return true }
            return a.isMature || b.isMature || a.polarity == b.polarity || (a.position - b.position).length > radius * (0.23 + parameters.linkStrength * 0.16)
        }
    }

    private mutating func updateBonds(dt: Double) {
        guard particles.count > 1 else { return }
        var degrees: [Int: Int] = [:]
        var existing: Set<String> = []
        for bond in bonds {
            degrees[bond.a, default: 0] += 1
            degrees[bond.b, default: 0] += 1
            existing.insert(pairKey(bond.a, bond.b))
        }
        var nextDwell: [String: Double] = [:]
        for first in 0..<(particles.count - 1) {
            let a = particles[first]
            guard !a.isMature else { continue }
            for second in (first + 1)..<particles.count {
                let b = particles[second]
                guard !b.isMature, a.polarity != b.polarity,
                      degrees[a.id, default: 0] < 2, degrees[b.id, default: 0] < 2 else { continue }
                let key = pairKey(a.id, b.id)
                guard !existing.contains(key), (a.position - b.position).length < radius * 0.17,
                      (a.velocity - b.velocity).length < 0.27 else { continue }
                let dwell = (bondDwell[key] ?? 0) + dt
                if dwell >= 0.8 + (1 - parameters.linkStrength) * 0.6 {
                    bonds.append(TorusBond(id: nextBondID, a: a.id, b: b.id))
                    nextBondID += 1
                    degrees[a.id, default: 0] += 1
                    degrees[b.id, default: 0] += 1
                    existing.insert(key)
                    record(.bond, "A first connection", "Opposite particles move together long enough to form a bond.", particleID: a.id)
                } else {
                    nextDwell[key] = dwell
                }
            }
        }
        bondDwell = nextDwell
    }

    private mutating func formParticles() {
        guard particles.count < capacity else { return }
        for index in dust.indices {
            guard particles.count < capacity, dust[index].amount >= Self.particleMaterial else { continue }
            let position = dust[index].position
            // Crowding leaves material unincorporated rather than silently discarding it.
            guard particles.filter({ !$0.isMature && ($0.position - position).length < radius * 0.12 }).count < 3 else { continue }
            let parent = particles.filter { $0.isMature && ($0.position - position).length < radius * 0.39 }
                .min { ($0.position - position).lengthSquared < ($1.position - position).lengthSquared }
            let random = SimulationNoise.unit(seed: seed, a: UInt64(nextParticleID), channel: 21)
            let polarity = random < (parameters.polarityBias + 1) * 0.5 ? 1 : -1
            let preference = bounded((parent?.learningPreference ?? 0) * 0.65 + (random - 0.5) * 0.18, -1, 1)
            let radial = position.normalized
            let particle = TorusParticle(id: nextParticleID, position: position,
                velocity: radial.perpendicular * 0.14 + radial * 0.012,
                energy: parameters.energyInput * 0.65, coherence: parent == nil ? 0.18 : 0.28, polarity: polarity,
                generation: (parent?.generation).map { $0 + 1 } ?? 0, parentID: parent?.id,
                learningPreference: preference, trail: [position])
            particles.append(particle)
            dust[index].amount -= Self.particleMaterial
            nextParticleID += 1
            birthCount += 1
            // Initial excitation is supplied by the energy field and included in its input ledger.
            energyInputTotal += particle.energy
            record(.formation, "Dust becomes a life", "Enough local material has gathered for a new particle to form.", particleID: particle.id)
            if parent != nil {
                record(.legacy, "A beginning with memory", "A new particle inherits a tendency from a mature node, with room for variation.", particleID: particle.id)
            }
        }
    }

    private mutating func expandStructure(dt: Double) {
        let mobile = particles.filter { !$0.isMature }
        let mature = particles.count - mobile.count
        guard mature >= 3, !mobile.isEmpty, radius < 2.5 else { return }
        let coherent = mobile.filter { $0.coherence > 0.65 }.count
        let coherence = Double(coherent) / Double(mobile.count)
        let participation = min(1, Double(coherent) / 8)
        let meanEnergy = mobile.reduce(0) { $0 + $1.energy } / Double(mobile.count)
        let support = min(1, Double(mature) / 8)
        let usableEnergy = bounded((meanEnergy - 0.12) / 0.50)
        let potential = 0.0024 * support * coherence * participation * usableEnergy * dt
        let energyAvailable = particles.reduce(0) { $0 + max(0, $1.energy - 0.10) }
        let change = max(0, min(potential, availableDust / 80, energyAvailable / 8, 2.5 - radius))
        guard change > 0 else { return }
        var materialCost = change * 80
        for index in dust.indices where materialCost > 0 {
            let withdrawn = min(materialCost, dust[index].amount)
            dust[index].amount -= withdrawn
            materialCost -= withdrawn
            structuralDustSpent += withdrawn
        }
        var energyCost = change * 8
        for index in particles.indices where energyCost > 0 {
            let withdrawn = min(energyCost, max(0, particles[index].energy - 0.10))
            particles[index].energy -= withdrawn
            energyCost -= withdrawn
        }
        let oldRadius = radius
        radius += change
        let scale = radius / oldRadius
        for index in particles.indices {
            particles[index].position = particles[index].position * scale
            particles[index].trail = particles[index].trail.map { $0 * scale }
        }
        for index in dust.indices { dust[index].position = dust[index].position * scale }
        if radius >= 1.012 {
            record(.expansion, "Room for another generation", "Coherent activity and a mature rim turn material into a larger, more capacious world.")
        }
    }

    private mutating func refreshMetrics() {
        let mobile = particles.filter { !$0.isMature }
        let mobileCount = mobile.count
        let denominator = Double(max(1, mobileCount))
        let dustSinceBaseline = dustInputTotal - comparisonBaseline.dustInput
        let energySinceBaseline = energyInputTotal - comparisonBaseline.energyInput
        let radiusSinceBaseline = max(0, radius - comparisonBaseline.radius)
        let startRadius = radiusWindow.first ?? comparisonBaseline.radius
        let elapsed = Double(tick - radiusWindowStartTick) * Self.fixedDelta
        metrics = TorusMetrics(
            population: particles.count, mobileCount: mobileCount,
            coherentProportion: Double(mobile.filter { $0.coherence > 0.65 }.count) / denominator,
            matureCount: particles.count - mobileCount, radius: radius,
            growthPerMinute: elapsed > 0.000_001 ? max(0, radius - startRadius) / elapsed * 60 : 0,
            meanEnergy: mobile.reduce(0) { $0 + $1.energy } / denominator,
            meanCoherence: mobile.reduce(0) { $0 + $1.coherence } / denominator,
            dustInputTotal: dustInputTotal, energyInputTotal: energyInputTotal,
            birthsPer100Dust: dustSinceBaseline > 0.000_001 ? Double(birthCount - comparisonBaseline.births) / dustSinceBaseline * 100 : nil,
            radiusGrowthPer100Dust: dustSinceBaseline > 0.000_001 ? radiusSinceBaseline / dustSinceBaseline * 100 : nil,
            radiusGrowthPer100Energy: energySinceBaseline > 0.000_001 ? radiusSinceBaseline / energySinceBaseline * 100 : nil)
    }

    private mutating func record(_ kind: SimulationEventKind, _ title: String, _ detail: String, particleID: Int? = nil) {
        if kind != .intervention {
            guard !milestones.contains(kind) else { return }
            milestones.insert(kind)
        }
        events.append(SimulationEvent(id: nextEventID, kind: kind, time: time, title: title, detail: detail, particleID: particleID))
        nextEventID += 1
        while events.count > 64, let oldestIntervention = events.firstIndex(where: { $0.kind == .intervention }) {
            // One-time story evidence must remain inspectable after many sandbox interventions.
            events.remove(at: oldestIntervention)
        }
    }
}
