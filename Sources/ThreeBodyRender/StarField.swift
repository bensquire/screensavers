import CoreGraphics
import Foundation
import SaverKit
import ThreeBodyCore

/// The backdrop of stars, drifting slowly.
///
/// The drift is ambient rather than physical: it is not tied to the camera, and
/// it does not claim the observer is going anywhere in particular. Parallaxing
/// with the camera would be the "honest" alternative and looks terrible, because
/// the simulation's zoom range spans several orders of magnitude — the stars
/// would either sit motionless or tear across the screen.
///
/// What it does borrow from reality is depth. Each star drifts at a rate set by
/// its own brightness, so the bright ones near the front slide visibly while the
/// faint ones behind barely move, and the field reads as having thickness. They
/// do not twinkle: there is no atmosphere out here to make them.
public struct StarField {
    private struct Star {
        var x: Double
        var y: Double
        var size: Double
        var brightness: Double
        /// 0 = far and slow, 1 = near and quick.
        var depth: Double
    }

    /// Points per second for the nearest layer.
    ///
    /// The first attempt at this used 2.4, which sounds slow-and-tasteful and
    /// was in practice invisible: brightness is distributed as b², so the
    /// *typical* star sat near the far end of the depth range and crawled along
    /// at under one point per second. The number that matters is not the
    /// nearest layer's speed but the median star's, and it wants to be several
    /// points per second before the field reads as moving at all.
    public var driftSpeed: Double = 14.0
    /// Direction of travel, in radians.
    public var driftAngle: Double = 0.9

    private var stars: [Star] = []
    private var generatedSize: CGSize = .zero
    private var generatedDensity: Double = -1

    public mutating func regenerateIfNeeded(size: CGSize, density: Double, seed: UInt64 = 0x5EED) {
        guard size.width > 0, size.height > 0 else { return }
        if size == generatedSize && abs(density - generatedDensity) < 0.001 { return }

        generatedSize = size
        generatedDensity = density

        // Scale with area so a 6K display is not sparser than a laptop screen.
        let area = Double(size.width * size.height)
        let count = Int(area / 5200.0 * max(density, 0) * 2.0)
        var rng = SplitMix64(seed: seed)
        stars = (0..<count).map { _ in
            // Squared brightness distribution: mostly faint, a few bright.
            let b = rng.double(0, 1)
            return Star(
                x: rng.double(0, Double(size.width)),
                y: rng.double(0, Double(size.height)),
                size: 0.7 + b * b * 1.9,
                brightness: 0.10 + b * b * 0.75,
                depth: 0.35 + b * b * 0.65)
        }
    }

    /// `time` is a monotonic clock in seconds; only differences matter.
    ///
    /// `pixelScale` is the backing-store scale, and it matters more than it
    /// looks: star rectangles snapped to whole device pixels take Core
    /// Graphics' fast fill path, while fractional ones force an antialiased
    /// rasterisation that measures **forty times slower** — 1.67 ms against
    /// 0.04 ms for three hundred stars. Snapping to device pixels rather than
    /// points keeps the drift as fine-grained as the display can actually
    /// show, so nothing is lost by taking the quick route.
    public func draw(
        in ctx: CGContext, size: CGSize, time: Double, alpha: Double, pixelScale: Double
    ) {
        guard !stars.isEmpty, alpha > 0.01, size.width > 0, size.height > 0 else { return }

        let width = Double(size.width)
        let height = Double(size.height)
        let travel = time * driftSpeed
        let dx = cos(driftAngle) * travel
        let dy = sin(driftAngle) * travel

        let quantum = 1.0 / max(pixelScale, 1.0)
        func snap(_ v: Double) -> Double { (v / quantum).rounded() * quantum }

        // Bucket by brightness so the whole sky is five fill calls rather than
        // a few thousand.
        let buckets = 5
        var rects = [[CGRect]](repeating: [], count: buckets)
        for star in stars {
            // Wrap rather than scroll off: a star leaving one edge reappears at
            // the other, and at one or two pixels across nobody sees it happen.
            let x = wrap(star.x + dx * star.depth, width)
            let y = wrap(star.y + dy * star.depth, height)
            let extent = max(snap(star.size), quantum)
            let bucket = min(buckets - 1, max(0, Int(star.brightness * Double(buckets))))
            rects[bucket].append(
                CGRect(
                    x: snap(x - extent / 2),
                    y: snap(y - extent / 2),
                    width: extent,
                    height: extent))
        }

        for bucket in 0..<buckets where !rects[bucket].isEmpty {
            let value = (Double(bucket) + 0.5) / Double(buckets)
            // Slightly blue-white, like real starlight.
            ctx.setFillColor(
                red: CGFloat(value * 0.92),
                green: CGFloat(value * 0.95),
                blue: CGFloat(min(1.0, value * 1.05)),
                alpha: CGFloat(alpha))
            ctx.fill(rects[bucket])
        }
    }

    private func wrap(_ value: Double, _ modulus: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: modulus)
        return r < 0 ? r + modulus : r
    }
}
