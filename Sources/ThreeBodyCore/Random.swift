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

    /// Uniform in [lower, upper).
    public mutating func double(_ lower: Double, _ upper: Double) -> Double {
        Double.random(in: lower..<upper, using: &self)
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
