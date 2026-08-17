import Foundation

/// Where the camera is and which way it is pointing.
///
/// The previous frame's basis is kept alongside the current one because the
/// accumulation pass reprojects through it — rotation alone is not enough once
/// the camera orbits, since the disk is only tens of M away and one frame's
/// parallax is several pixels.
public struct CameraState: Equatable {
    public var position = SIMD3<Double>(0, 0, 30)
    public var right = SIMD3<Double>(1, 0, 0)
    public var up = SIMD3<Double>(0, 1, 0)
    public var forward = SIMD3<Double>(0, 0, -1)
    /// 2 * tan(fovY / 2).
    public var scale: Double = 1
}

/// Flies the camera.
///
/// Every channel is a sum of sines at periods written in seconds and chosen to
/// be mutually incommensurate, so the pose never returns to where it was. The
/// periods are deliberately long — an earlier form buried them in frequency
/// coefficients and they all came out between six and ninety minutes, which is
/// indistinguishable from a still image.
///
/// There is no input handling. The WebGL original could be dragged; a
/// screensaver that consumes a mouse event is a screensaver that fails to
/// dismiss itself, so the shipping build listened to nothing and neither does
/// this.
public struct OrbitCamera {

    /// Degrees of tilt floor per unit of outer half-thickness.
    ///
    /// Never sit exactly in the disk plane: a ray grazing the slab has a path
    /// length through it of about 2h/sin(i), which diverges as i goes to zero
    /// and blows the near side out. What is safe therefore scales with the slab
    /// itself rather than being a fixed angle.
    private static let tiltPerHalfThickness = 0.8 / 1.15

    /// Sum of the inclination drift amplitudes below.
    private static let driftTilt = 3.10

    public private(set) var current = CameraState()
    public private(set) var previous = CameraState()

    public init() {}

    private static func osc(_ t: Double, _ period: Double, _ phase: Double) -> Double {
        sin(t * (2 * .pi / period) + phase)
    }

    private static func minimumTilt(_ p: SceneParameters) -> Double {
        min(max(tiltPerHalfThickness * p.diskHalfOuter, 0.15), 3.0)
    }

    /// The legal inclination range on whichever side of the disk the camera is
    /// already on. The drift reads its bounds from here so it cannot wander into
    /// the blow-out on its own.
    private static func tiltBand(_ angle: Double, _ p: SceneParameters) -> ClosedRange<Double> {
        let m = minimumTilt(p)
        return angle < 0 ? (-89.0)...(-m) : m...89.0
    }

    /// Advances to time `t`, in seconds, keeping the previous pose.
    public mutating func update(time t: Double, parameters p: SceneParameters) {
        previous = current
        let d = p.drift * p.pace

        // Inclination is the money motion: within a few degrees of edge-on, a
        // small change visibly opens and closes the lensed arcs over the shadow.
        // The swing is scaled to whatever headroom the base angle leaves above
        // the tilt floor rather than assumed to fit inside it — a shallow
        // framing drifts less, instead of swinging through the plane and being
        // snapped back, which read as a jump cut once per cycle.
        let band = Self.tiltBand(p.incl, p)
        let base = min(max(p.incl, band.lowerBound), band.upperBound)
        let swing =
            d
            * (1.70 * Self.osc(t, 131, 0.0)
                + 0.95 * Self.osc(t, 67, 1.31)
                + 0.45 * Self.osc(t, 41, 2.71))
        let room = abs(base) - Self.minimumTilt(p)
        let inclination = min(
            max(base + swing * min(1, room / max(d * Self.driftTilt, 1e-6)), band.lowerBound),
            band.upperBound)

        // A full revolution every seven minutes. The disk is axisymmetric, so
        // this reads almost entirely on the lensed starfield — which is the
        // point: stars streaming around the shadow is the clearest evidence that
        // space is bent. It is also the only channel that never turns around, so
        // it sets the floor under how slow the scene can look, and the wobble on
        // top has to stay well inside it.
        let azimuth = (d * (t * (360.0 / 420.0) + 8.0 * Self.osc(t, 240, 0.4))) * .pi / 180 + 1.9

        let distance =
            p.dist
            * (1 + d * (0.055 * Self.osc(t, 181, 0.0) + 0.026 * Self.osc(t, 89, 2.13)))
        let roll = d * 1.2 * Self.osc(t, 223, 0.0) * .pi / 180

        let ir = inclination * .pi / 180
        let position = SIMD3(
            distance * cos(ir) * cos(azimuth),
            distance * sin(ir),
            distance * cos(ir) * sin(azimuth))

        // Nudging the aim point is the only channel that moves the hole across
        // the frame rather than orbiting around it, which is why it has its own
        // dial — and why the screensaver sets it to zero.
        let aw = d * p.aimDrift
        let aim = SIMD3(
            aw * 0.9 * Self.osc(t, 151, 0.7),
            aw * 0.55 * Self.osc(t, 113, 2.2),
            aw * 0.9 * Self.osc(t, 179, 4.1))

        let forward = normalize(aim - position)
        var right = normalize(cross(forward, SIMD3(0, 1, 0)))
        if !right.x.isFinite { right = SIMD3(1, 0, 0) }
        let up = cross(right, forward)

        let cr = cos(roll), sr = sin(roll)
        current = CameraState(
            position: position,
            right: right * cr + up * sr,
            up: up * cr - right * sr,
            forward: forward,
            scale: 2 * tan(p.fov * .pi / 360))
    }

    /// Forgets the previous pose, so the next frame does not reproject against a
    /// camera from before a discontinuity.
    public mutating func resetHistory() {
        previous = current
    }
}

// MARK: - Small vector helpers
//
// SIMD3<Double> has no geometry functions of its own in the standard library,
// and pulling in simd for three lines would put a framework dependency in the
// one module that is meant to stay Foundation-only.

func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
    a.x * b.x + a.y * b.y + a.z * b.z
}

func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x)
}

func normalize(_ a: SIMD3<Double>) -> SIMD3<Double> {
    let length = dot(a, a).squareRoot()
    return length > 0 ? a / length : SIMD3(0, 0, 0)
}
