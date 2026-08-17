import Foundation
import simd

/// How heliocentric AU are mapped into scene units.
///
/// In every mode the *direction* of each planet from the Sun is exact, and so is the
/// timing: orbital phase, inclination, and the 60.19° tilt of the ecliptic to the
/// galactic plane are untouched, as is the angular signature of eccentricity (a body
/// still visibly sweeps faster at perihelion).
///
/// What compression does change is radial distance — and eccentricity is partly a radial
/// quantity, so an ellipse is drawn rounder than it is. At the default exponent the
/// perihelion/aphelion excursion is damped to ~0.38 of true: Mercury's e=0.206 reads as
/// about 0.079. The angular motion is still exactly right; the shape is not.
public enum ScaleMode: Sendable {
    /// 1 scene unit = 1 AU, drift = the real 48.52 AU/yr. Astronomically honest and
    /// visually useless: Earth's path deviates ~7.5° from a straight line and Mercury
    /// is invisible next to Neptune.
    case trueScale

    /// Radius remapped as r' = r^exponent, drift set independently.
    /// exponent 1.0 reduces to linear. Earth (1 AU) always maps to 1 unit.
    case compressed(radialExponent: Double, driftUnitsPerYear: Double)

    public var radialExponent: Double {
        switch self {
        case .trueScale: return 1.0
        case let .compressed(e, _): return e
        }
    }

    public var driftUnitsPerYear: Double {
        switch self {
        case .trueScale: return Constants.solarDriftAUPerYear
        case let .compressed(_, d): return d
        }
    }

    /// Whether this is the untouched 1× mode.
    public var isTrue: Bool {
        if case .trueScale = self { return true }
        return false
    }

    /// Drift rate as a fraction of reality. Meaningful because Earth's 1 AU orbit maps
    /// to 1 scene unit under any exponent, so units/yr and AU/yr are directly comparable.
    public var driftFractionOfTrue: Double {
        driftUnitsPerYear / Constants.solarDriftAUPerYear
    }
}

/// How much past trajectory to draw behind each body.
public enum TrailMode: Sendable {
    /// A multiple of each planet's own orbital period — every planet shows the same
    /// fraction of a loop. Neptune's trail then spans 165 years of drift.
    case orbits(Double)
    /// The same wall-clock window for every planet. Inner planets coil many times,
    /// outer planets trace a short arc.
    case years(Double)

    /// The shorter of a fixed window and a revolution count. This is the only mode
    /// that looks right across a 700:1 spread in orbital period: `maxOrbits` stops
    /// Mercury from drawing an illegible ball of 125 overlapping loops, while
    /// `maxYears` gives the outer planets enough elapsed time for the galactic
    /// drift to be visible as a helix rather than a closed ellipse.
    case adaptive(maxYears: Double, maxOrbits: Double)

    /// The adaptive caps, when this is an adaptive trail. Lets callers seed defaults
    /// from the configured value rather than restating the numbers.
    public var adaptiveCaps: (maxYears: Double, maxOrbits: Double)? {
        if case let .adaptive(y, o) = self { return (y, o) }
        return nil
    }

    func duration(for planet: Planet) -> TimeInterval {
        switch self {
        case let .orbits(n):
            return n * planet.orbitalPeriodDays * 86400
        case let .years(y):
            return y * Constants.secondsPerJulianYear
        case let .adaptive(maxYears, maxOrbits):
            return min(
                maxYears * Constants.secondsPerJulianYear,
                maxOrbits * planet.orbitalPeriodDays * 86400
            )
        }
    }

    /// How many orbital revolutions this trail spans for a planet — used to keep the
    /// sample count proportional to the amount of curvature actually being drawn.
    func revolutions(for planet: Planet) -> Double {
        duration(for: planet) / (planet.orbitalPeriodDays * 86400)
    }
}

public struct SceneConfig: Sendable {
    public var scale: ScaleMode
    public var trail: TrailMode
    /// Samples per trail. Cost is linear in this; 240 is smooth at 4K.
    public var trailSamples: Int
    /// Simulated Julian years advanced per second of real time.
    public var yearsPerSecond: Double
    /// How much the star field's motion is exaggerated relative to the Sun's drift.
    ///
    /// Purely a visual cue and knowingly unphysical: true stellar parallax over this
    /// animation is about half a degree, far too small to see. Since the scene is drawn
    /// Sun-relative, nothing else on screen translates, so without this the system looks
    /// parked. Set to 0 for no star motion at all.
    public var starParallax: Double
    /// Scene radius of the Sun. Every body is sized relative to this.
    ///
    /// Sits comfortably inside Mercury's compressed orbit (~0.70 units), so a Sun this
    /// dominant still doesn't swallow the inner system.
    public var sunDisplayRadius: Double
    /// Body radii are compressed as `(R / R_sun)^exponent`.
    ///
    /// True scale is hopeless: the Sun is 109 Earth radii, and at 1 unit = 1 AU the Sun
    /// is 0.0047 units across while Earth is 0.00004 — both far below one pixel. A flat
    /// set of hand-picked sizes is the other failure mode, and makes every body look the
    /// same. 0.45 keeps the real ordering and a legible hierarchy: the Sun renders 8.3×
    /// Earth, Jupiter 2.9×, Mercury 0.65×.
    public var bodyRadiusExponent: Double
    /// Floor on a body's scene radius, in scene units.
    ///
    /// Needed once distances are real: the inner system is then 1/77th of the scene, so
    /// Earth and Mercury fall below a pixel and their trails end in nothing. Zero (the
    /// default) leaves the size law untouched.
    public var minimumBodyRadius: Double

    public init(
        scale: ScaleMode = .compressed(radialExponent: 0.38, driftUnitsPerYear: 0.32),
        trail: TrailMode = .adaptive(maxYears: 70, maxOrbits: 4),
        trailSamples: Int = 240,
        yearsPerSecond: Double = 0.35,
        starParallax: Double = 16,
        sunDisplayRadius: Double = 0.36,
        bodyRadiusExponent: Double = 0.45,
        minimumBodyRadius: Double = 0
    ) {
        self.scale = scale
        self.trail = trail
        self.trailSamples = trailSamples
        self.yearsPerSecond = yearsPerSecond
        self.starParallax = starParallax
        self.sunDisplayRadius = sunDisplayRadius
        self.bodyRadiusExponent = bodyRadiusExponent
        self.minimumBodyRadius = minimumBodyRadius
    }
}

public struct BodySnapshot: Sendable {
    public let planet: Planet
    public let scenePosition: SIMD3<Double>
    /// Past trajectory through galactic space, oldest first, newest last.
    public let trail: [SIMD3<Double>]
}

public struct SystemSnapshot: Sendable {
    public let sunPosition: SIMD3<Double>
    public let bodies: [BodySnapshot]
}

/// Turns real ephemeris output into scene-space geometry.
public struct DisplayModel {
    public var config: SceneConfig
    /// The instant at which the Sun sits at the scene origin. Drift accumulates from here.
    public let epoch: Date

    public init(config: SceneConfig = SceneConfig(), epoch: Date = Date()) {
        self.config = config
        self.epoch = epoch
    }

    /// Offset of the Sun from the scene origin at `date`, purely from galactic travel.
    public func sunOffset(at date: Date) -> SIMD3<Double> {
        let years = date.timeIntervalSince(epoch) / Constants.secondsPerJulianYear
        return GalacticFrame.solarApexDirection * (config.scale.driftUnitsPerYear * years)
    }

    /// Radial compression. Direction is preserved exactly; only |r| is remapped.
    func compress(_ galactic: SIMD3<Double>) -> SIMD3<Double> {
        let r = simd_length(galactic)
        guard r > 1e-12 else { return .zero }
        let exponent = config.scale.radialExponent
        let remapped = exponent == 1.0 ? r : pow(r, exponent)
        return galactic * (remapped / r)
    }

    /// Full scene-space position of a planet at `date`, including the Sun's drift.
    public func scenePosition(of planet: Planet, at date: Date) throws -> SIMD3<Double> {
        let eqj = try Ephemeris.helioPosition(planet, at: date)
        return compress(GalacticFrame.galactic(fromEQJ: eqj)) + sunOffset(at: date)
    }

    /// Scene radius of the Sun's sphere. At `.trueScale` this is the Sun's actual
    /// radius in AU (0.00465) — correct, and about a twentieth of a pixel.
    public var sunRadius: Double {
        switch config.scale {
        case .trueScale: return Constants.sunRadiusKm / Constants.kmPerAU
        case .compressed: return config.sunDisplayRadius
        }
    }

    /// Scene radius of a planet's sphere, preserving the real size ordering.
    public func bodyRadius(of planet: Planet) -> Double {
        switch config.scale {
        case .trueScale:
            return planet.meanRadiusKm / Constants.kmPerAU
        case .compressed:
            let ratio = planet.meanRadiusKm / Constants.sunRadiusKm
            let r = config.sunDisplayRadius * pow(ratio, config.bodyRadiusExponent)
            return max(r, config.minimumBodyRadius)
        }
    }

    /// Samples scale with the number of revolutions drawn, so a trail covering 30 Earth
    /// orbits doesn't get the same 240 points as one covering 3 and turn into a polygon.
    /// `trailSamples` is the budget for a 3-revolution trail.
    public func sampleCount(for planet: Planet) -> Int {
        let revs = config.trail.revolutions(for: planet)
        let scaled = Double(config.trailSamples) * max(1.0, revs / 3.0)
        return min(4000, max(2, Int(scaled)))
    }

    /// Longest trail any body draws. Used for the Sun's own track, which has to span
    /// the whole structure — derived rather than assuming Neptune is always the longest.
    public var longestTrailDuration: TimeInterval {
        Planet.allCases.map { config.trail.duration(for: $0) }.max() ?? 0
    }

    /// Rough radius of everything drawn, in scene units: the drift accumulated over the
    /// longest trail plus the outermost orbit. Spans ~26 units at the default compression
    /// and ~3,400 at true scale, so anything sized in scene units — the star field, the
    /// depth clip planes — has to be derived from it rather than hard-coded.
    public var sceneExtent: Double {
        let drift =
            config.scale.driftUnitsPerYear
            * (longestTrailDuration / Constants.secondsPerJulianYear)
        // Through `compress` rather than restating the r^e law, so the two cannot diverge.
        let outermost = simd_length(compress(SIMD3(Constants.outermostOrbitAU, 0, 0)))
        return max(1, drift + outermost)
    }

    public func snapshot(at date: Date) throws -> SystemSnapshot {
        var bodies: [BodySnapshot] = []
        let sunNow = sunOffset(at: date)

        for planet in Planet.allCases {
            let duration = config.trail.duration(for: planet)
            let n = sampleCount(for: planet)
            var trail: [SIMD3<Double>] = []
            trail.reserveCapacity(n)

            for i in 0..<n {
                // i = 0 is the oldest sample, i = n-1 is `date` itself.
                let f = Double(i) / Double(n - 1)
                let t = date.addingTimeInterval(-duration * (1 - f))
                trail.append(try scenePosition(of: planet, at: t))
            }

            bodies.append(
                BodySnapshot(planet: planet, scenePosition: trail[n - 1], trail: trail)
            )
        }

        return SystemSnapshot(sunPosition: sunNow, bodies: bodies)
    }
}
