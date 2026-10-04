import Foundation
import simd

/// `DisplayModel.snapshot(at:)` for every frame, without paying for the
/// ephemeris at every sample.
///
/// A trail is resampled from scratch each frame, because every one of its
/// samples sits a fixed interval behind the moving present. Done directly that
/// is 2,320 evaluations of the planetary theory per frame — 70,000 a second at
/// 30 fps, almost all of them for positions that were computed a frame ago a
/// hair's breadth away. It was the single largest cost in the Solar System
/// saver: a full core, on its own.
///
/// The samples are evenly spaced in time, so they all fall at the same fraction
/// of the way between consecutive points of a fixed grid with the same spacing.
/// The ephemeris is evaluated on that grid, once per grid point, and each sample
/// is a Catmull-Rom blend of its four neighbours on it. Per frame that is a
/// handful of new grid points — however far the present moved — instead of
/// thousands.
///
/// Only the Sun-relative orbit is interpolated. The galactic drift is linear in
/// time, so it is added back exactly. The grid is the trail's own sample
/// spacing, so the cubic's error stays well inside the error already accepted by
/// drawing the trail as straight segments between those samples: at the default
/// settings 3e-5 of the orbit's radius, against a segment sag of 8e-4 — a few
/// thousandths of a pixel. `TrailSamplerTests` holds it to the direct
/// computation.
public final class TrailSampler {

    public let model: DisplayModel
    private var tracks: [Track]

    public init(model: DisplayModel) {
        self.model = model
        self.tracks = Planet.allCases.map { planet in
            let samples = model.sampleCount(for: planet)
            return Track(
                planet: planet, sampleCount: samples,
                spacing: model.config.trail.duration(for: planet) / Double(samples - 1))
        }
    }

    /// The same snapshot `DisplayModel.snapshot(at:)` returns, to within the
    /// interpolation error.
    public func snapshot(at date: Date) throws -> SystemSnapshot {
        var bodies: [BodySnapshot] = []
        bodies.reserveCapacity(tracks.count)
        for index in tracks.indices {
            let trail = try tracks[index].trail(at: date, model: model)
            bodies.append(
                BodySnapshot(
                    planet: tracks[index].planet,
                    scenePosition: trail[trail.count - 1],
                    trail: trail))
        }
        return SystemSnapshot(sunPosition: model.sunOffset(at: date), bodies: bodies)
    }

    /// One planet's grid, and the window of it the current trail needs.
    private struct Track {
        let planet: Planet
        let sampleCount: Int
        /// Seconds between grid points, and between trail samples.
        let spacing: TimeInterval

        /// Positions at grid points `firstKnot ..< firstKnot + knots.count`,
        /// where grid point k sits at `epoch + k * spacing`.
        var knots: [SIMD3<Double>] = []
        var firstKnot = 0

        mutating func trail(at date: Date, model: DisplayModel) throws -> [SIMD3<Double>] {
            let n = sampleCount
            guard spacing > 0, spacing.isFinite else {
                return try model.trail(of: planet, at: date)
            }

            // Sample i sits at grid coordinate `start + i`, so every sample has
            // the same fractional part, and one set of weights serves them all.
            let elapsed = date.timeIntervalSince(model.epoch)
            let start = (elapsed - spacing * Double(n - 1)) / spacing
            let base = start.rounded(.down)
            guard base.magnitude < Double(Int.max / 4) else {
                return try model.trail(of: planet, at: date)
            }
            let u = start - base
            let first = Int(base)

            // Catmull-Rom needs one grid point either side of each interval.
            try cover(first - 1...first + n + 1, model: model)

            let w0 = 0.5 * u * (-1 + u * (2 - u))
            let w1 = 0.5 * (2 + u * u * (-5 + 3 * u))
            let w2 = 0.5 * u * (1 + u * (4 - 3 * u))
            let w3 = 0.5 * u * u * (u - 1)

            let drift = model.driftPerSecond
            var trail: [SIMD3<Double>] = []
            trail.reserveCapacity(n)
            var k = first - 1 - firstKnot
            for i in 0..<n {
                // Split and annotated: four overloaded SIMD terms in one
                // expression put the type checker over its time limit.
                let near: SIMD3<Double> = w1 * knots[k + 1] + w2 * knots[k + 2]
                let far: SIMD3<Double> = w0 * knots[k] + w3 * knots[k + 3]
                let t = (base + u + Double(i)) * spacing
                trail.append(near + far + drift * t)
                k += 1
            }
            return trail
        }

        /// Makes `knots` hold exactly the grid points in `range`, keeping the ones
        /// already computed and evaluating only the rest.
        private mutating func cover(_ range: ClosedRange<Int>, model: DisplayModel) throws {
            let held = firstKnot..<(firstKnot + knots.count)
            let old = knots
            let offset = firstKnot
            knots = try range.map { held.contains($0) ? old[$0 - offset] : try knot($0, model: model) }
            firstKnot = range.lowerBound
        }

        private func knot(_ k: Int, model: DisplayModel) throws -> SIMD3<Double> {
            try model.orbitalPosition(
                of: planet, at: model.epoch.addingTimeInterval(Double(k) * spacing))
        }
    }
}
