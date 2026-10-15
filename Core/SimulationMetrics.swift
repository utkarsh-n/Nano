import Foundation

struct TorusMetrics: Codable, Equatable, Sendable {
    var population: Int = 0
    var mobileCount: Int = 0
    var coherentProportion: Double = 0
    var matureCount: Int = 0
    var radius: Double = 1
    var growthPerMinute: Double = 0
    var meanEnergy: Double = 0
    var meanCoherence: Double = 0
    var dustInputTotal: Double = 0
    var energyInputTotal: Double = 0
    var birthsPer100Dust: Double?
    var radiusGrowthPer100Dust: Double?
    var radiusGrowthPer100Energy: Double?
}

struct MetricSample: Codable, Equatable, Identifiable, Sendable {
    var time: Double
    var metrics: TorusMetrics
    var id: Double { time }
}

enum MetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case population, coherence, maturity, radius, growth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .population: return "Population"
        case .coherence: return "Coherence"
        case .maturity: return "Mature rim"
        case .radius: return "Radius"
        case .growth: return "Growth / min"
        }
    }
    var unit: String {
        switch self {
        case .population, .maturity: return "particles"
        case .coherence: return "%"
        case .radius: return "×"
        case .growth: return "× / min"
        }
    }
    func value(in metrics: TorusMetrics) -> Double {
        switch self {
        case .population: return Double(metrics.population)
        case .coherence: return metrics.coherentProportion * 100
        case .maturity: return Double(metrics.matureCount)
        case .radius: return metrics.radius
        case .growth: return metrics.growthPerMinute
        }
    }
}
