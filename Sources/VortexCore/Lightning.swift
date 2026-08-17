import Foundation
import SaverCore

/// A discharge arcing along the tunnel wall.
///
/// Unlike the particle field, a bolt's geometry is built on the CPU: it is a
/// one-off polyline whose shape comes from repeated random subdivision, and
/// there are never more than a couple alive, so per-frame upload is cheaper than
/// any scheme for keeping it resident.
public struct Bolt {

    /// Screen-space triangle-strip vertices, two per point of the polyline.
    public let vertices: [SIMD2<Float>]
    /// Where the discharge starts on screen, and so where its shockwave is centred.
    public let origin: SIMD2<Double>
    public let color: SIMD3<Float>
    public let lifetimeMs: Double
    public private(set) var ageMs: Double = 0

    /// Snaps to full brightness, then decays — the shape of a real discharge,
    /// and the reason a bolt reads as a flash rather than a fade-in.
    public var intensity: Float {
        let t = ageMs / lifetimeMs
        if t < 0.12 { return Float(t / 0.12) }
        return Float(pow(1 - (t - 0.12) / 0.88, 1.8))
    }

    public var isFinished: Bool { ageMs >= lifetimeMs }

    public mutating func advance(byMs delta: Double) { ageMs += delta }

    /// Builds a bolt wrapped around the tunnel wall, or `nil` if the result was
    /// too short on screen to be worth drawing.
    ///
    /// The anchors are projected through the same perspective and bend the
    /// particles use, so the arc appears to lie on the cylinder rather than
    /// floating in front of it.
    public init?(
        layout: Layout,
        bendX: Double,
        bendY: Double,
        spin: Double,
        rng: inout SplitMix64
    ) {
        let zStart = 0.45 + rng.nextDouble() * 1.6
        let zEnd = zStart + 0.8 + rng.nextDouble() * 2.0
        let angleStart = rng.nextDouble() * 2 * .pi + spin
        let angleSweep = (0.6 + rng.nextDouble() * 1.9) * (rng.nextDouble() < 0.5 ? -1 : 1)

        let anchorCount = 10
        var points: [SIMD2<Double>] = []
        points.reserveCapacity(anchorCount)
        for i in 0..<anchorCount {
            let t = Double(i) / Double(anchorCount - 1)
            points.append(
                layout.project(
                    z: zStart + (zEnd - zStart) * t,
                    angle: angleStart + angleSweep * t,
                    radius: Tunnel.radius * (0.92 + rng.nextDouble() * 0.16),
                    bendX: bendX, bendY: bendY))
        }

        // Midpoint displacement, four times. The offset shrinks by 0.6 per pass, so
        // early passes set the bolt's overall wander and later ones only add crackle.
        for pass in 0..<4 {
            var refined: [SIMD2<Double>] = [points[0]]
            refined.reserveCapacity(points.count * 2)
            for i in 0..<(points.count - 1) {
                let a = points[i], b = points[i + 1]
                let delta = b - a
                let length = (delta.x * delta.x + delta.y * delta.y).squareRoot()
                let normal =
                    length > 0
                    ? SIMD2(-delta.y / length, delta.x / length)
                    : SIMD2(0.0, 0.0)
                let offset = (rng.nextDouble() - 0.5) * length * 0.45 * pow(0.6, Double(pass))
                refined.append((a + b) * 0.5 + normal * offset)
                refined.append(b)
            }
            points = refined
        }

        // A bolt that subdivided into a knot barely wider than a few pixels reads as
        // a flicker of noise rather than lightning, so it is dropped instead.
        let span = points[points.count - 1] - points[0]
        guard (span.x * span.x + span.y * span.y).squareRoot() >= layout.minDimension * 0.1 else {
            return nil
        }

        let thickness = (1.5 + rng.nextDouble() * 2.5) * layout.scale
        self.origin = points[0]
        self.vertices = Bolt.ribbon(along: points, thickness: thickness)
        self.color =
            rng.nextDouble() < 0.5
            ? SIMD3(0.95, 0.99, 1.0)
            : SIMD3(0.55, 0.82, 1.0)
        self.lifetimeMs = 140 + rng.nextDouble() * 200
    }

    /// Expands a polyline into a triangle strip, tapering toward both ends.
    static func ribbon(along points: [SIMD2<Double>], thickness: Double) -> [SIMD2<Float>] {
        var vertices: [SIMD2<Float>] = []
        vertices.reserveCapacity(points.count * 2)
        let last = points.count - 1
        for i in 0...last {
            // Central difference, so the ribbon follows the curve rather than
            // kinking at every vertex.
            let before = points[max(0, i - 1)]
            let after = points[min(last, i + 1)]
            let delta = after - before
            let length = (delta.x * delta.x + delta.y * delta.y).squareRoot()
            let normal =
                length > 0
                ? SIMD2(-delta.y / length, delta.x / length)
                : SIMD2(0.0, 0.0)
            let taper = sin(Double(i) / Double(last) * .pi)
            let halfWidth = thickness * (0.35 + 0.65 * taper)
            let point = points[i]
            vertices.append(SIMD2(point + normal * halfWidth))
            vertices.append(SIMD2(point - normal * halfWidth))
        }
        return vertices
    }
}

/// The pressure wave a bolt throws off.
///
/// A shock is never drawn directly. It is packed into a uniform the particle
/// shaders read, so the ring shows up as the particles it passes over briefly
/// brightening and fattening — which sells the tunnel as a volume of stuff
/// rather than a flat backdrop.
public struct Shock {
    public let origin: SIMD2<Double>
    public let lifetimeMs: Double
    public private(set) var ageMs: Double = 0

    public init(origin: SIMD2<Double>, lifetimeMs: Double) {
        self.origin = origin
        self.lifetimeMs = lifetimeMs
    }

    public var isFinished: Bool { ageMs >= lifetimeMs }

    public mutating func advance(byMs delta: Double) { ageMs += delta }

    /// Packed for the shaders as (x, y, radius, intensity).
    public func packed(maxRadius: Double) -> SIMD4<Float> {
        let t = ageMs / lifetimeMs
        // Decelerating expansion — fast off the mark, easing out as it fades.
        let radius = maxRadius * (1 - pow(1 - t, 2))
        let intensity = t < 0.08 ? t / 0.08 : pow(1 - (t - 0.08) / 0.92, 2.2)
        return SIMD4(Float(origin.x), Float(origin.y), Float(radius), Float(intensity))
    }
}
