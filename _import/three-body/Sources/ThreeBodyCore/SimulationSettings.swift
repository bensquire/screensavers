import Foundation

/// Integrator quality. Higher settings cost more force evaluations per unit of
/// simulated time but keep the relative energy error smaller for longer, which
/// is what determines how many periods a published orbit survives before chaos
/// takes it apart.
public enum Accuracy: String, CaseIterable {
    case standard
    case high
    case extreme

    public var order: IntegratorOrder {
        switch self {
        case .standard: return .fourth
        case .high: return .sixth
        case .extreme: return .eighth
        }
    }

    /// Step size as a fraction of the shortest local dynamical timescale.
    ///
    /// Measured on Burrau's problem (the worst case here) to t = 40, these give
    /// peak relative energy errors of roughly 2e-6, 2e-8 and 3e-9 for a few
    /// hundred to a few thousand force evaluations per unit of simulated time —
    /// against a measured throughput of ~10 million per second, so even the top
    /// tier costs a fraction of a frame.
    public var eta: Double {
        switch self {
        case .standard: return 0.025
        case .high: return 0.020
        case .extreme: return 0.015
        }
    }

    public var displayName: String {
        switch self {
        case .standard: return "Standard — 4th order"
        case .high: return "High — 6th order"
        case .extreme: return "Extreme — 8th order"
        }
    }
}

/// Which pool of starting conditions to draw scenes from.
///
/// The two halves are genuinely different in kind, not just in parameters. The
/// catalogue is a fixed set of solutions from the literature: each one replays
/// from identical initial conditions every time, which is the point — the
/// figure-eight is only the figure-eight for one exact set of numbers.
/// Generated systems are drawn fresh every scene and never repeat.
public enum SceneMode: String, CaseIterable {
    /// Known solutions only — periodic orbits and the classical configurations.
    case knownOrbits
    /// Procedurally generated systems only.
    case randomSystems
    /// Both pools.
    case both

    public var families: Set<ScenarioFamily> {
        switch self {
        case .knownOrbits: return [.periodic, .classical]
        case .randomSystems: return [.hierarchical, .chaotic, .flyby]
        case .both: return Set(ScenarioFamily.allCases)
        }
    }

    public var displayName: String {
        switch self {
        case .knownOrbits: return "Known orbits — the catalogue"
        case .randomSystems: return "Random systems — never repeats"
        case .both: return "Both"
        }
    }

    public var explanation: String {
        switch self {
        case .knownOrbits:
            return "The figure-eight and ten other periodic solutions, plus "
                + "Lagrange, Euler and Burrau. Fixed initial conditions, so "
                + "each replays identically."
        case .randomSystems:
            return "Hierarchical triples, chaotic and free-fall systems, and "
                + "flyby encounters — generated fresh, never the same twice."
        case .both:
            return "Alternates between the catalogue and freshly generated "
                + "systems."
        }
    }
}

/// Everything the simulation and renderer need, decoupled from where the values
/// were stored (screensaver defaults, the preview app, or a unit test).
public struct SimulationSettings {
    public var mode: SceneMode = .both
    public var families: Set<ScenarioFamily> { mode.families }
    public var accuracy: Accuracy = .high

    /// Multiplies each scenario's own suggested pace.
    public var speed: Double = 1.0

    /// Visible tail length, in real seconds of history.
    public var trailSeconds: Double = 7.0

    /// Real seconds before a scene is retired and a new one fades in.
    public var sceneDuration: Double = 150.0

    /// Slow the animation through close encounters and speed it up through
    /// quiet stretches, rather than playing at one fixed pace.
    public var adaptivePlayback: Bool = true

    public var showHUD: Bool = true
    public var showGlow: Bool = true
    public var showStars: Bool = true
    /// 0…1, scales the number of background stars.
    public var starDensity: Double = 0.55

    /// The memberwise initialiser is internal, so a public one is needed for
    /// anything outside Core to build settings of its own.
    public init() {}

    public static let `default` = SimulationSettings()

    /// The one place each adjustable range is written down. Both the options
    /// sheet's sliders and `clamped()` read these, so a slider can never offer
    /// a value that persistence will quietly claw back.
    public enum Limits {
        public static let speed: ClosedRange<Double> = 0.1...4.0
        public static let trailSeconds: ClosedRange<Double> = 0.5...30.0
        public static let sceneDuration: ClosedRange<Double> = 20...900
        public static let starDensity: ClosedRange<Double> = 0...1
    }
}

public extension ClosedRange where Bound == Double {
    /// Clamp, treating a non-finite value as "fall back to `fallback`".
    public func clamp(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
