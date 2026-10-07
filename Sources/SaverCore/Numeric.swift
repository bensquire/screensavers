import Foundation

extension Double {

    /// Clamped into `range`, with a non-finite value falling back to the range's
    /// lower bound.
    ///
    /// The NaN guard is the point: `min`/`max` propagate NaN rather than
    /// rejecting it, so a hand-edited or corrupt plist could otherwise put a NaN
    /// into a setting, and from there into a uniform, where it turns a whole
    /// frame black with nothing to show why.
    public func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    /// Reduced into `0..<modulus`, whatever the sign — a floor modulo, unlike
    /// `truncatingRemainder`, whose result keeps the sign of the dividend. For
    /// angles, and for anything else that wraps.
    public func wrapped(modulo modulus: Double) -> Double {
        let remainder = self - modulus * (self / modulus).rounded(.down)
        // A negative value within rounding of zero lands on `modulus` itself
        // (-1e-17 wrapped modulo 1 is 1.0), which is zero on the circle.
        return remainder == modulus ? 0 : remainder
    }
}
