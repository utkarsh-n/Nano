import Foundation

struct Vector2: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    static let zero = Vector2(x: 0, y: 0)
    var lengthSquared: Double { x * x + y * y }
    var length: Double { sqrt(lengthSquared) }
    var normalized: Vector2 { length > 0.000_001 ? self / length : .zero }
    var perpendicular: Vector2 { Vector2(x: -y, y: x) }
    var isFinite: Bool { x.isFinite && y.isFinite }

    func dot(_ other: Vector2) -> Double { x * other.x + y * other.y }
    func limited(to maximum: Double) -> Vector2 {
        lengthSquared > maximum * maximum ? normalized * maximum : self
    }
    static func polar(angle: Double, radius: Double = 1) -> Vector2 {
        Vector2(x: cos(angle) * radius, y: sin(angle) * radius)
    }
    static func + (lhs: Vector2, rhs: Vector2) -> Vector2 { Vector2(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Vector2, rhs: Vector2) -> Vector2 { Vector2(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static prefix func - (value: Vector2) -> Vector2 { Vector2(x: -value.x, y: -value.y) }
    static func * (lhs: Vector2, rhs: Double) -> Vector2 { Vector2(x: lhs.x * rhs, y: lhs.y * rhs) }
    static func / (lhs: Vector2, rhs: Double) -> Vector2 { Vector2(x: lhs.x / rhs, y: lhs.y / rhs) }
    static func += (lhs: inout Vector2, rhs: Vector2) { lhs = lhs + rhs }
    static func -= (lhs: inout Vector2, rhs: Vector2) { lhs = lhs - rhs }
}

func bounded(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
    value.isFinite ? min(upper, max(lower, value)) : lower
}

/// Counter-based randomness keeps external disturbances aligned across cloned experiments.
/// World identity and array traversal order never enter the random key.
enum SimulationNoise {
    static func unit(seed: UInt64, a: UInt64, b: UInt64 = 0, channel: UInt64 = 0) -> Double {
        var value = seed &+ a &* 0x9E3779B97F4A7C15 &+ b &* 0xD1B54A32D192ED03 &+ channel &* 0x94D049BB133111EB
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }

    static func smooth(seed: UInt64, id: Int, tick: Int, channel: UInt64) -> Double {
        let period = 36
        let bucket = UInt64(max(0, tick / period))
        let raw = Double(tick % period) / Double(period)
        let blend = raw * raw * (3 - 2 * raw)
        let first = unit(seed: seed, a: UInt64(id), b: bucket, channel: channel)
        let second = unit(seed: seed, a: UInt64(id), b: bucket + 1, channel: channel)
        return (first + (second - first) * blend) * 2 - 1
    }
}
