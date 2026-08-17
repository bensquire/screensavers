import Foundation
import GargantuaCore

/// Drives the render scale to hold a frame budget.
///
/// Per-pixel geodesic integration is expensive enough that no single fixed scale
/// is right for every display and every camera angle — an edge-on framing
/// marches far more disk than a steep one. So the scale is driven, not chosen.
///
/// Unlike the WebGL original this measures the GPU directly. There, wall-clock
/// time was quantised by vsync and lied about headroom, and the timer-query
/// extension bracketed CPU gaps too, so the controller needed to cross-check two
/// untrustworthy clocks. Metal reports a command buffer's actual GPU start and
/// end times, which is the number that was wanted all along.
public struct AdaptiveResolution {

    public static let minimumScale = GargantuaSettings.Limits.renderScale.lowerBound
    public static let maximumScale = GargantuaSettings.Limits.renderScale.upperBound

    /// Fraction of the output resolution the march runs at.
    public private(set) var renderScale: Double

    /// Set false to pin the scale where it is.
    public var isEnabled = true

    /// Share of each frame the GPU is allowed to spend on the march.
    ///
    /// Not 1.0, deliberately. The controller settles wherever cost sits between
    /// 0.62 and 1.15 of its budget, so a budget of one whole frame interval
    /// means it settles at very nearly a whole frame interval — measured at 16.5
    /// ms of a 16.7 ms frame on an M1 Pro, which is a screensaver holding the
    /// GPU at full tilt indefinitely. Leaving a third of the frame idle costs
    /// resolution and buys back the fans.
    public static let utilisation = 0.65

    /// Seconds per frame the GPU is allowed.
    public var budget: Double = Self.utilisation / GargantuaRenderer.framesPerSecond

    /// Smoothed GPU cost of a frame, in seconds.
    public private(set) var smoothedCost: Double = 0

    /// Frames since the last change. A change reallocates every target and drops
    /// the accumulation history, so they have to be rare.
    private var framesSinceChange = 0
    private var direction = 0
    private var agreementStreak = 0

    public init(renderScale: Double = 0.55) {
        self.renderScale = renderScale.clamped(to: Self.minimumScale...Self.maximumScale)
    }

    /// Pins the scale, for the fixed-resolution setting and for thumbnails.
    public mutating func fix(at scale: Double) {
        isEnabled = false
        renderScale = scale.clamped(to: Self.minimumScale...Self.maximumScale)
    }

    /// Records a frame's measured GPU time. Returns true when the scale changed,
    /// which the caller must treat as invalidating everything size-dependent.
    public mutating func note(gpuSeconds: Double) -> Bool {
        guard gpuSeconds > 0, gpuSeconds.isFinite else { return false }
        // Exponential average: a single frame is noisy enough — GPU clock states
        // alone swing it by half — that acting on one makes the scale hunt
        // visibly.
        smoothedCost = smoothedCost > 0 ? smoothedCost + (gpuSeconds - smoothedCost) * 0.05 : gpuSeconds

        guard isEnabled else { return false }
        framesSinceChange += 1
        guard framesSinceChange >= 60 else { return false }

        let overBudget = smoothedCost > budget * 1.15
        let headroom = smoothedCost < budget * 0.62 && renderScale < Self.maximumScale
        let wanted = overBudget ? -1 : (headroom ? 1 : 0)

        // Two consecutive readings must agree before moving.
        if wanted == 0 || wanted != direction {
            direction = wanted
            agreementStreak = 1
            return false
        }
        agreementStreak += 1
        guard agreementStreak >= 2 else { return false }

        // March cost is very close to linear in pixel count, so correcting the
        // scale by 1/sqrt(ratio) lands near the budget in one move rather than
        // creeping toward it.
        let gain = wanted < 0 ? max(1 / (smoothedCost / budget).squareRoot(), 0.70) : 1.12
        // Quantised, so the scale settles on a value rather than drifting by
        // fractions of a percent forever.
        let next = (renderScale * gain / 0.02).rounded() * 0.02
        let clamped = next.clamped(to: Self.minimumScale...Self.maximumScale)
        guard abs(clamped - renderScale) >= 0.019 else { return false }

        renderScale = clamped
        agreementStreak = 0
        framesSinceChange = 0
        return true
    }
}
