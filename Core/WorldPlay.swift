import Foundation

enum WorldAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case stardust, pulse
    var id: String { rawValue }
}

struct WorldPlayProgress: Codable, Equatable, Sendable {
    var dustDrops: Int = 0
    var energyPulses: Int = 0
    var adjustments: Int = 0
    var unlockedDiscoveryIDs: Set<String> = []
}

struct WorldDiscovery: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var isUnlocked: Bool
}

/// Small, local interventions. These prepare ordinary simulation commands; they never step time,
/// manufacture a milestone, or replace the world's existing material and energy accounting.
enum WorldPlaybook {
    static func commands(for action: WorldAction, in world: TorusWorld) -> [TorusCommand] {
        switch action {
        case .stardust:
            return [.seedDust(position: dustPosition(in: world), amount: 6)]
        case .pulse:
            return pulseRecipients(in: world).map { particle in
                .energize(particleID: particle.id, amount: min(0.16, 0.90 - particle.energy))
            }
        }
    }

    /// Describe the commands prepared from this same pre-action snapshot. The caller can append
    /// its playback hint; a paused lab still accepts interventions without advancing its clock.
    static func feedback(for action: WorldAction, in world: TorusWorld) -> String {
        switch action {
        case .stardust:
            if world.particles.count >= world.capacity {
                return "Stardust stored. New particles need more room."
            }
            return "A little stardust, ready for a new beginning."
        case .pulse:
            let count = pulseRecipients(in: world).count
            if count == 0 {
                return world.particles.contains(where: { !$0.isMature })
                    ? "These particles already have plenty of energy."
                    : "There are no wandering particles to receive a pulse."
            }
            return count == 1 ? "A gentle spark for one particle." : "A gentle spark for \(count) particles."
        }
    }

    static func discoveries(in world: TorusWorld, progress: WorldPlayProgress) -> [WorldDiscovery] {
        let recorded = Set(world.events.map(\.kind))
        let handPlacedDust = progress.dustDrops > 0 || world.events.contains {
            $0.kind == .intervention && $0.title == "Dust seeded"
        }
        let firstBirth = world.birthCount > 0 || recorded.contains(.formation)
        let firstBond = !world.bonds.isEmpty || recorded.contains(.bond) || recorded.contains(.learning)
        let coherent = recorded.contains(.coherence) || (world.time > 0 && world.particles.contains {
            !$0.isMature && $0.coherence > 0.68 && $0.age > 2
        })
        let mature = world.particles.contains(where: \.isMature) || world.metrics.matureCount > 0 || recorded.contains(.rimHarmony)
        let expanded = world.radius >= 1.012 || recorded.contains(.expansion)

        func discovery(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ observed: Bool) -> WorldDiscovery {
            WorldDiscovery(id: id, title: title, detail: detail, symbol: symbol,
                isUnlocked: observed || progress.unlockedDiscoveryIDs.contains(id))
        }

        return [
            discovery("sowed-dust", "A small beginning", "Add a little stardust to your world.", "sparkles", handPlacedDust),
            discovery("first-birth", "Hello, little one", "Let gathered dust become a new particle.", "sun.max.fill", firstBirth),
            discovery("first-bond", "Better together", "Two particles find a lasting connection.", "link", firstBond),
            discovery("coherence", "A steady direction", "A particle finds a coherent path through the field.", "point.topleft.down.to.point.bottomright.curvepath", coherent),
            discovery("rim-harmony", "At the glass", "A particle joins the rim and steadies the lives nearby.", "circle.dotted.circle", mature),
            discovery("expansion", "Room to grow", "The living ring grows beyond its first boundary.", "arrow.up.left.and.arrow.down.right", expanded)
        ]
    }

    private static func pulseRecipients(in world: TorusWorld) -> [TorusParticle] {
        Array(world.particles.filter { !$0.isMature && $0.energy.isFinite && $0.energy <= 0.87 }
            .sorted {
                $0.energy == $1.energy ? $0.id < $1.id : $0.energy < $1.energy
            }.prefix(8))
    }

    private static func dustPosition(in world: TorusWorld) -> Vector2 {
        let radius = world.radius
        let mobile = world.particles.filter { !$0.isMature }
        var candidates = world.dust.filter {
            $0.position.isFinite && $0.position.length >= radius * 0.40 && $0.position.length <= radius * 0.87
        }.map(\.position)
        if candidates.isEmpty {
            candidates = (0..<12).map { .polar(angle: Double($0) / 12 * .pi * 2, radius: radius * 0.68) }
        }
        let scored = candidates.map { position -> (position: Vector2, score: Double) in
            let neighbors = mobile.filter { ($0.position - position).length < radius * 0.16 }.count
            let storedDust = world.dust.filter { ($0.position - position).length < radius * 0.10 }
                .reduce(0) { $0 + $1.amount }
            let disturbed = (position - world.deadZoneCenter).length < world.deadZoneRadius
            // Avoid crowded pockets and spread repeated paused drops instead of hiding all of
            // the player's material in one already-rich deposit.
            return (position, Double(neighbors) * 12 + storedDust * 0.25 + (disturbed ? 40 : 0))
        }
        return scored.min { $0.score < $1.score }?.position ?? Vector2(x: radius * 0.68, y: 0)
    }
}
