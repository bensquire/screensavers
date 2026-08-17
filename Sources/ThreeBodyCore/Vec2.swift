import Foundation

/// Double-precision 2-D vector. All simulation state uses this; rendering
/// converts to `CGPoint` only at the last moment.
public struct Vec2: Equatable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var lengthSquared: Double { x * x + y * y }
    public var length: Double { (x * x + y * y).squareRoot() }

    public var normalized: Vec2 {
        let l = length
        return l > 0 ? Vec2(x / l, y / l) : .zero
    }

    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }

    /// z-component of the 3-D cross product, which is all a 2-D system needs
    /// for angular momentum.
    public func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (v: Vec2, s: Double) -> Vec2 { Vec2(v.x * s, v.y * s) }
    public static func * (s: Double, v: Vec2) -> Vec2 { Vec2(v.x * s, v.y * s) }
    public static func / (v: Vec2, s: Double) -> Vec2 { Vec2(v.x / s, v.y / s) }
    static prefix func - (v: Vec2) -> Vec2 { Vec2(-v.x, -v.y) }

    public static func += (a: inout Vec2, b: Vec2) {
        a.x += b.x
        a.y += b.y
    }
    public static func -= (a: inout Vec2, b: Vec2) {
        a.x -= b.x
        a.y -= b.y
    }
    public static func *= (a: inout Vec2, s: Double) {
        a.x *= s
        a.y *= s
    }
}
