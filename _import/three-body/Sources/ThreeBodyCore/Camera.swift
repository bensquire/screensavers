import Foundation

/// Auto-framing camera.
///
/// The hard part is not keeping up — it is holding still. Bodies orbit, so the
/// bounding box of a three-body system *oscillates*, and a camera that tracks
/// it faithfully breathes in and out and slides side to side at the orbital
/// frequency. Filtering does not help: the oscillation has a period of seconds,
/// and any filter slow enough to suppress it is too slow to follow anything
/// real. Three things fix it properly.
///
/// **Centre on the centre of mass, not the bounding box.** Every scene is
/// integrated in its centre-of-mass frame and momentum is conserved exactly, so
/// the centre of mass of all three bodies sits at the origin and *stays there*
/// for the entire scene. Framing about it removes essentially all lateral
/// motion, where a bounding-box centre wanders every orbit.
///
/// **Expand promptly, contract lazily.** Nothing may leave the frame, so growth
/// is followed quickly. Shrinkage is not urgent, so it is followed over many
/// seconds — which means the periodic contraction half of every orbit never
/// registers at all, and the zoom simply sits near the widest recent extent.
///
/// **Contract only when it is clearly worth it.** Below a threshold the camera
/// does not move at all, so ordinary orbital variation produces no zoom
/// whatsoever.
///
/// A separate mechanism handles genuine discontinuities: when the set of framed
/// bodies changes the target jumps, and rather than chase it the jump is parked
/// in an offset that decays to zero. (That idea, and framing a tight pair by its
/// centre of mass, are from Kirk Long's ThreeBodyBot.)
public struct Camera {
    /// World-space point shown at the centre of the view.
    public private(set) var center: Vec2 = .zero
    /// World units per point (screen coordinate). Larger = zoomed further out.
    public private(set) var worldPerPoint: Double = 0.01

    /// Fraction of the way to close on a target in `dt`, for a time constant
    /// of `tau`. Written once: five separate copies of this had already drifted
    /// into guarding different arguments against zero.
    @inline(__always)
    public static func approach(dt: Double, tau: Double) -> Double {
        1.0 - exp(-max(dt, 0) / max(tau, 1e-9))
    }

    /// Extra room around the framed points.
    /// Padding around the framed content.
    ///
    /// Widening this to absorb the residual brief disappearances was measured
    /// and made them *more* frequent (19 → 25 across 60 scenes): a wider target
    /// means the camera holds a bigger view, drops below the contraction
    /// threshold more often, and then has to expand again. Left where it is.
    private let margin: Double = 1.18
    /// Once the camera does resize, it aims slightly wider than strictly
    /// needed, so ordinary motion does not immediately demand another change.
    private let headroom: Double = 1.10
    /// Prevents runaway zoom when the framed points momentarily coincide.
    public var minimumHalfExtent: Double = 0.35
    /// Hard ceiling on how far out the camera will pull. Chasing a body that is
    /// leaving at speed otherwise zooms out without limit, shrinking everything
    /// worth looking at to nothing before the escape logic gives up on it.
    /// Beyond this the departing body simply leaves the frame, which is the
    /// honest depiction anyway.
    public var maximumHalfExtent: Double = .infinity

    /// Seconds to follow the frame growing. Short: nothing may leave frame.
    private let expandTime: Double = 0.8
    /// Seconds to follow the frame shrinking. Long, deliberately: this is what
    /// stops the camera breathing once per orbit.
    private let contractTime: Double = 90.0
    /// Contract only when the content has become this much smaller than the
    /// frame. Above it the camera holds completely still — which, since a
    /// three-body system routinely shrinks and regrows by a factor of two or
    /// three every orbit, is most of the time. The camera would rather sit at
    /// the widest recent extent, with the system small but steady, than track
    /// every expansion and collapse faithfully.
    private let contractThreshold: Double = 0.28
    /// Seconds to follow the centre. Only matters when the framed set is a
    /// subset whose centre of mass genuinely moves.
    private let centerTime: Double = 2.0
    /// Hard ceiling on how fast the zoom may change, in e-folds per second.
    ///
    /// The thresholds above decide *whether* to move; these decide how fast,
    /// and they are what finally guarantees smoothness. Without them a violent
    /// system like Burrau's — which genuinely flings bodies out and hauls them
    /// back — can demand a fivefold reframing in a second, and honouring that
    /// demand looks like a fault however correctly it tracks.
    private let expandRateLimit: Double = 0.35
    private let contractRateLimit: Double = 0.05
    /// Fraction of the outstanding offset retained each frame at 60 fps.
    private let relaxation: Double = 0.972
    /// Final guarantees on what the view may do in one second, whatever the
    /// mechanisms above ask for: e-folds of zoom, and screen points of pan.
    ///
    /// Everything else here decides *what* the camera wants; these decide what
    /// it is allowed to do. Having a single clamp on the output is what makes
    /// smoothness a property of the camera rather than something that has to be
    /// re-established every time one of the inputs is tuned.
    private let outputZoomRateLimit: Double = 0.20
    /// The ceiling when content is *already outside* the frame.
    ///
    /// Slow zoom is what stops the camera breathing, but it also means a body
    /// swinging outward can outrun the frame and vanish for seconds at a time.
    /// The distinction that matters is between a discretionary adjustment,
    /// which should be unhurried, and a mistake being made right now, which
    /// should be corrected at once. Only the second case gets this.
    private let recoveryZoomRateLimit: Double = 1.8
    private let outputPanRateLimit: Double = 220.0

    private var smoothedCenter: Vec2 = .zero
    /// Current half-extents in world units, before the offset is applied.
    private var halfWidth: Double = 1
    private var halfHeight: Double = 1
    private var centerOffset: Vec2 = .zero
    private var logScaleOffset: Double = 0
    private var initialised = false

    public mutating func reset() {
        initialised = false
        centerOffset = .zero
        logScaleOffset = 0
    }

    /// `anchor` is the point to centre on — the centre of mass of the framed
    /// bodies, which is stationary for as long as the framed set is the whole
    /// system. `requiredHalfExtents` is how far from it the content reaches,
    /// already folded by the caller.
    public mutating func update(
        anchor: Vec2,
        requiredHalfExtents: (x: Double, y: Double),
        viewSize: (width: Double, height: Double),
        deltaTime: Double
    ) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let dt = max(deltaTime, 0)

        // Follow the anchor. Usually it does not move at all.
        if initialised {
            smoothedCenter += (anchor - smoothedCenter) * Camera.approach(dt: dt, tau: centerTime)
        } else {
            smoothedCenter = anchor
        }

        let requiredX = min(
            max(requiredHalfExtents.x, minimumHalfExtent) * margin, maximumHalfExtent)
        let requiredY = min(
            max(requiredHalfExtents.y, minimumHalfExtent) * margin, maximumHalfExtent)

        // Is anything outside the frame right now? Compared without the margin:
        // eating into the padding is fine, leaving the screen is not.
        let shownHalfX = worldPerPoint * viewSize.width / 2
        let shownHalfY = worldPerPoint * viewSize.height / 2
        let clipping =
            initialised
            && (requiredHalfExtents.x > shownHalfX || requiredHalfExtents.y > shownHalfY)

        guard initialised else {
            halfWidth = requiredX
            halfHeight = requiredY
            center = smoothedCenter
            worldPerPoint = scale(viewSize: viewSize)
            centerOffset = .zero
            logScaleOffset = 0
            initialised = true
            return
        }

        halfWidth = follow(current: halfWidth, required: requiredX, dt: dt, urgent: clipping)
        halfHeight = follow(current: halfHeight, required: requiredY, dt: dt, urgent: clipping)

        // Frame-rate independent decay of whatever discontinuity is outstanding.
        let decay = pow(relaxation, dt * 60.0)
        centerOffset *= decay
        logScaleOffset *= decay

        let desiredCenter = smoothedCenter + centerOffset
        let desiredScale = exp(log(scale(viewSize: viewSize)) + logScaleOffset)

        // Rate-limit the emitted values, not just the targets.
        let zoomStep = log(desiredScale) - log(worldPerPoint)
        let zoomLimit = (clipping ? recoveryZoomRateLimit : outputZoomRateLimit) * dt
        worldPerPoint *= exp(min(max(zoomStep, -zoomLimit), zoomLimit))

        let panLimit = outputPanRateLimit * dt * worldPerPoint
        let delta = desiredCenter - center
        let distance = delta.length
        center += distance > panLimit && distance > 0 ? delta * (panLimit / distance) : delta
    }

    /// Asymmetric response: grow quickly, shrink slowly, and hold still in
    /// between.
    private func follow(current: Double, required: Double, dt: Double, urgent: Bool) -> Double {
        let expanding = required > current
        let target: Double
        if expanding {
            let alpha = Camera.approach(dt: dt, tau: urgent ? 0.12 : expandTime)
            target = current + (required * headroom - current) * alpha
        } else if required < current * contractThreshold {
            let alpha = Camera.approach(dt: dt, tau: contractTime)
            target = current + (required * headroom - current) * alpha
        } else {
            return current
        }

        // Rate limit in log space, so the cap means the same thing at every
        // zoom level.
        guard current > 0, target > 0 else { return target }
        let limit =
            (expanding ? (urgent ? recoveryZoomRateLimit : expandRateLimit) : contractRateLimit)
            * dt
        let step = log(target) - log(current)
        return current * exp(min(max(step, -limit), limit))
    }

    private func scale(viewSize: (width: Double, height: Double)) -> Double {
        max(halfWidth * 2.0 / viewSize.width, halfHeight * 2.0 / viewSize.height)
    }

    /// Absorb a change in the framed set rather than chasing it: the view keeps
    /// exactly what it was showing, and the correction decays away over about a
    /// second.
    public mutating func absorbDiscontinuity(previousCenter: Vec2, previousScale: Double) {
        guard initialised, previousScale > 0, worldPerPoint > 0 else { return }
        centerOffset = previousCenter - smoothedCenter
        logScaleOffset = log(previousScale) - log(worldPerPoint) + logScaleOffset
        center = previousCenter
        worldPerPoint = previousScale
    }

    /// World → view coordinates (origin at the view's bottom-left, y up).
    public func project(_ p: Vec2, viewSize: (width: Double, height: Double)) -> (
        x: Double, y: Double
    ) {
        let dx = (p.x - center.x) / worldPerPoint
        let dy = (p.y - center.y) / worldPerPoint
        return (viewSize.width * 0.5 + dx, viewSize.height * 0.5 + dy)
    }
}
