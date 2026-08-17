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
}
