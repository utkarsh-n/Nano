import Foundation

struct TorusParameters: Codable, Equatable, Sendable {
    var dustInput: Double
    var energyInput: Double
    var polarityBias: Double
    var turbulence: Double
    var linkStrength: Double

    static let balanced = TorusParameters(dustInput: 0.48, energyInput: 0.46, polarityBias: 0, turbulence: 0.18, linkStrength: 0.50)
    static let energetic = TorusParameters(dustInput: 0.67, energyInput: 0.86, polarityBias: 0.18, turbulence: 0.52, linkStrength: 0.35)
    static let cooperative = TorusParameters(dustInput: 0.40, energyInput: 0.40, polarityBias: -0.08, turbulence: 0.12, linkStrength: 0.88)

    var clamped: TorusParameters {
        TorusParameters(dustInput: bounded(dustInput), energyInput: bounded(energyInput), polarityBias: bounded(polarityBias, -1, 1), turbulence: bounded(turbulence), linkStrength: bounded(linkStrength))
    }
}

struct TorusParticle: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var position: Vector2
    var velocity: Vector2
    var energy: Double
    var coherence: Double
    var polarity: Int
    var generation: Int
    var parentID: Int?
    var isMature: Bool = false
    var age: Double = 0
    var maturityProgress: Double = 0
    var learningPreference: Double = 0
    var timeInDeadZone: Double = 0
    var experiencedDeadZone: Bool = false
    var trail: [Vector2] = []
}

struct TorusBond: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var a: Int
    var b: Int
    var age: Double = 0
    var tension: Double = 0
}

struct DustDeposit: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var position: Vector2
    var amount: Double
}

enum SimulationEventKind: String, Codable, CaseIterable, Sendable {
    case formation, coherence, bond, learning, deadZone, escape, rimHarmony, legacy, expansion, intervention
}

struct SimulationEvent: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var kind: SimulationEventKind
    var time: Double
    var title: String
    var detail: String
    var particleID: Int?
}

enum TorusCommand: Codable, Equatable, Sendable {
    case setParameters(TorusParameters)
    case flipPolarity(particleID: Int)
    case energize(particleID: Int, amount: Double)
    case nudge(particleID: Int, direction: Vector2)
    case seedDust(position: Vector2, amount: Double)
    case dissolveBond(bondID: Int)
}

struct ComparisonBaseline: Codable, Equatable, Sendable {
    var time: Double = 0
    var radius: Double = 1
    var births: Int = 0
    var dustInput: Double = 0
    var energyInput: Double = 0
}
