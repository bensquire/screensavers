import Foundation

/// SplitMix64 — small, fast, and seedable, so a scene can be reproduced
/// exactly from its seed (handy when a run produces something worth keeping).
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1), taken from the top 53 bits.
    ///
    /// Spelled out rather than deferring to `Double.random(in:using:)` because the
    /// mapping from bits to value is then ours: the solar-system starfield is seeded
    /// and its geometry is compared across builds, so this has to keep producing the
    /// same numbers even if the standard library changes how it draws a Double.
    public mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform in [lower, upper).
    ///
    /// Built on `nextDouble` rather than `Double.random(in:using:)` so the
    /// reproducibility promise above covers every caller — otherwise seeded
    /// output would survive a standard-library change in some places and not
    /// others, which is worse than not promising it at all.
    public mutating func double(_ lower: Double, _ upper: Double) -> Double {
        lower + nextDouble() * (upper - lower)
    }

    public mutating func bool(_ probability: Double) -> Bool {
        double(0, 1) < probability
    }

    /// Uniform in the logarithm, so every factor-of-two band is equally likely.
    ///
    /// The right distribution for anything measured as a ratio — masses, orbit
    /// separations. Drawing those uniformly clusters them near the middle of
    /// the range and makes genuinely lopsided systems vanishingly rare.
    public mutating func logUniform(_ lower: Double, _ upper: Double) -> Double {
        exp(double(log(lower), log(upper)))
    }

    /// ±1 with equal probability.
    public mutating func sign() -> Double {
        bool(0.5) ? 1 : -1
    }
}
