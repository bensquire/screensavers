import Foundation
import SceneKit
import SolarSystemCore
import SpriteKit
import simd

/// Builds and drives the SceneKit scene.
///
/// Everything is rendered *relative to the Sun*: each frame we subtract the Sun's
/// absolute galactic position from every point. Two reasons — coordinates stay bounded
/// (a screensaver left running for days would otherwise accumulate a huge offset and
/// lose float precision), and the camera naturally travels with the system. Because
/// nothing else on screen then translates, the scrolling star field is what makes the
/// scene read as travelling rather than parked — see `StarField`.
public final class SolarSystemRenderer {

    public let scene = SCNScene()
    private let model: DisplayModel
    public let startDate: Date
    /// Simulated date currently displayed.
    public private(set) var currentDate: Date

    private let cameraNode = SCNNode()
    private let contentNode = SCNNode()
    private var bodyNodes: [Planet: SCNNode] = [:]
    private var trailNodes: [Planet: SCNNode] = [:]
    /// One per body, holding the colour ramp and index buffer that never change.
    private var ribbons: [Planet: Ribbon] = [:]
    private let sunRibbon: Ribbon
    private let sunNode: SCNNode
    private let sunTrailNode = SCNNode()
    private var framedRadius: Double = 1
    private var cameraTarget = SIMD3<Double>(0, 0, 0)
    private let dateOverlay = DateOverlay()
    private let starField: StarField
    /// Low-pass state for the camera fit; see the smoothing note in `fitCamera`.
    private var smoothedDistance: Double = 0
    private var lastFitElapsed: Double?

    /// Crop factor read by `fitCamera` on every update, so it survives a resize without
    /// the caller having to restate it.
    ///
    /// Above 1 crops in; below 1 pulls the camera back. Below 1 by default because the
    /// view from behind needs it: an exact fit puts the camera *inside* the trail
    /// structure, which is ~22 units deep along the travel axis, so the nearest loops
    /// wrap off the frame edges.
    public static let defaultZoom = 0.85
    public var zoom: Double = SolarSystemRenderer.defaultZoom

    public init(model: DisplayModel, startDate: Date) {
        self.model = model
        self.startDate = startDate
        self.currentDate = startDate
        self.sunNode = Geometry.bodyNode(
            radius: model.sunRadius, color: (1.0, 0.94, 0.78), boost: Self.sunBoost
        )
        self.sunRibbon = Ribbon(
            sampleCount: Self.sunAxisSamples,
            color: (1.0, 0.88, 0.60),
            gamma: 4.2,
            intensity: model.config.scale.isTrue ? 0.30 : 0.75,
            taperFrom: 0.04
        )
        // Every body's largest disc, for the framing margin — constant once configured.
        self.maximumBodyRadius = Planet.allCases.map { model.bodyRadius(of: $0) }.max() ?? 0

        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(contentNode)

        // Starfield sits on its own node far outside the scene, unaffected by drift.
        let stars = StarField(
            sceneExtent: model.sceneExtent, parallax: model.config.starParallax
        )
        scene.rootNode.addChildNode(stars.node)
        self.starField = stars

        sunNode.position = SCNVector3(0, 0, 0)  // Sun-relative scene: always the origin
        contentNode.addChildNode(sunNode)
        contentNode.addChildNode(sunTrailNode)

        for planet in Planet.allCases {
            // Brightness rises with size so bloom reinforces the size hierarchy instead
            // of flattening it — an unlit 3px dot and a 40px one otherwise pick up
            // similar halos and end up looking the same.
            //
            // Capped below the Sun's. Without the cap a planet on the size floor is
            // boosted 1.34× while the Sun gets 1.00×, so the planets are brighter than
            // the star they orbit; packed inside Mercury's orbit they then merge with it
            // into one white blob and the Sun cannot be picked out at all.
            let relative = model.bodyRadius(of: planet) / max(1e-9, model.sunRadius)
            let node = Geometry.bodyNode(
                radius: model.bodyRadius(of: planet),
                color: planet.color,
                boost: min(Self.sunBoost * 0.85, 1.00 + 0.55 * pow(relative, 0.5))
            )
            bodyNodes[planet] = node
            contentNode.addChildNode(node)

            let trail = SCNNode()
            trailNodes[planet] = trail
            contentNode.addChildNode(trail)

            ribbons[planet] = Ribbon(
                sampleCount: model.sampleCount(for: planet),
                color: planet.color,
                gamma: Self.trailGamma, intensity: 1.1
            )
        }

        setupCamera()
        update(to: startDate)
    }

    /// Viewport width / height. The camera fit depends on it, so a value set for 16:9
    /// wastes space on 16:10 or a portrait pane.
    public private(set) var aspectRatio: Double = 16.0 / 9.0

    /// Re-fit for a viewport size. Call on resize.
    public func reframe(aspectRatio: Double) {
        guard aspectRatio > 0 else { return }
        self.aspectRatio = aspectRatio
        lastFitElapsed = nil  // snap to the new framing instead of gliding to it
        lockedFit = nil  // a pinned camera must re-fit for the new viewport shape
        update(to: currentDate)
    }

    private static let fieldOfViewDegrees: Double = 42
    /// Brightness ramp exponent for trail ribbons. Shared with the camera fit so the two
    /// cannot disagree about where a trail stops being visible.
    private static let trailGamma: Double = 2.2
    /// Samples along the Sun's own straight track.
    private static let sunAxisSamples = 49
    /// Slack left around the framed content so the outermost disc and its bloom halo are
    /// not sliced by the frame edge.
    private static let framePadding = 1.04
    /// The Sun should always be the brightest thing in its own system.
    private static let sunBoost = 1.6
    /// A trail may never be drawn wider than this fraction of the orbit it traces.
    private static let maxTrailWidthFraction = 0.09
    private let maximumBodyRadius: Double

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.fieldOfViewDegrees)
        // Pin the FOV to the vertical axis so the fitting maths in fitCamera is
        // deterministic; .automatic switches axes based on aspect ratio.
        camera.projectionDirection = .vertical
        // Clip planes follow the scene rather than assuming its size.
        camera.zNear = max(0.01, model.sceneExtent * 0.002)
        camera.zFar = model.sceneExtent * 80
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        // Threshold has to stay above the starfield's brightest values or every faint
        // star grows a soft halo and the sky reads as foggy rather than black.
        camera.bloomIntensity = 0.95
        camera.bloomThreshold = 0.62
        // Tighter than it looks like it wants to be: a wide blur gives every body a halo
        // of the same size regardless of its own, which erases the size differences.
        camera.bloomBlurRadius = 11
        camera.bloomIterationCount = 3
        camera.colorFringeStrength = 0
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    /// The camera's own orbit around the Sun — effectively an extra planet.
    ///
    /// It revolves continuously rather than oscillating. That matters: an earlier version
    /// swung back and forth between two angles, and any reversal reads as a wobble rather
    /// than travel. A closed orbit never reverses, so the motion always resolves into a
    /// direction the eye can follow.
    public struct CameraOrbit: Sendable {
        public var enabled: Bool = true
        /// Seconds for one full revolution around the Sun.
        public var periodSeconds: Double = 80
        /// Inclination of the camera's orbit to the ecliptic, in degrees.
        ///
        /// 0° would put the camera in the ecliptic itself — a true extra planet, but it
        /// would then view the other orbits permanently edge-on. Tilting it opens the
        /// plane up and, because the ecliptic pole is 30.4° off the direction of travel,
        /// also decides how far behind and ahead of the Sun the orbit carries the camera.
        ///
        /// 55° sweeps it from ~30° off the travel axis (behind the Sun, looking along its
        /// motion) through side-on and round to ~150° (ahead, looking back). It also sets
        /// how far the Sun's track tips on screen: the drift axis keeps a constant
        /// component of 0.86·cos(inclination) along the up vector, so a shallower orbit
        /// drives the track further down the frame.
        public var inclinationDegrees: Double = 55
        /// Position on the orbit at t=0, in degrees. 290° starts with the Sun high on the
        /// right and its track running down into the bottom-left corner.
        public var phaseDegrees: Double = 290
        /// Roll about the view axis, in degrees. Biases the Sun's track towards the
        /// bottom-left rather than running flat across the frame.
        public var rollDegrees: Double = 32

        /// Fixed viewpoint used when `enabled` is false: angle from the travel axis
        /// (0° dead astern, 90° side on) and rotation about it.
        public var elevationDegrees: Double = 20
        public var azimuthDegrees: Double = 180

        /// Public so callers can read the defaults rather than restating them.
        public init() {}
    }

    public var orbit = CameraOrbit()

    /// What the camera fit sizes itself to.
    public enum Framing: Sendable {
        /// Everything drawn, trails included. Right when the trails *are* the picture.
        case wholeTrail
        /// Only the bodies and the Sun — the orbital extent, ~60 AU.
        ///
        /// Needed once the drift is real: the trail structure is then 3,396 AU long
        /// against 60 AU wide, so fitting all of it squashes the entire solar system
        /// into a 28-pixel thread. Framing the bodies instead puts Neptune near the
        /// frame edge, bunches the inner planets at the centre where they belong, and
        /// lets the trails run off the edges.
        case orbitalExtent
    }

    public var framing: Framing = .wholeTrail

    /// Star scroll rate for a scene that has no drift of its own, as a fraction of the
    /// scene extent per second.
    ///
    /// The orrery zeroes the galactic drift so the orbits close, which also freezes the
    /// star field solid — the field is scrolled by how far the Sun has travelled, and
    /// that is now always zero. The Sun really is still moving; the orrery has just
    /// chosen not to draw that motion in the planets' paths, so the sky may still slide.
    public var idleStarDriftFraction: Double = 0

    /// Pins the camera to an explicit direction, overriding the orbit. Used by the
    /// bird's-eye preset, whose viewpoint is defined by the ecliptic rather than by any
    /// angle relative to the Sun's travel.
    public var fixedDirection: SIMD3<Double>? {
        didSet { lockedFit = nil }
    }

    /// Cached fit for a pinned camera: aspect ratio it was computed for, and the framed
    /// extent it produced.
    private var lockedFit: Double?
    /// Reused across frames so the fit allocates nothing; ~74 KB/frame otherwise.
    private var samplesR: [(value: Double, weight: Double)] = []
    private var samplesU: [(value: Double, weight: Double)] = []
    /// `pow(f, trailGamma)` per sample index, cached per trail length — it is a pure
    /// function of the position along the trail and was costing 2,320 `pow`s a frame.
    private var weightRamps: [Int: [Double]] = [:]

    private func weightRamp(count n: Int) -> [Double] {
        if let r = weightRamps[n] { return r }
        let r = (0..<n).map { pow(Double($0) / Double(n - 1), Self.trailGamma) }
        weightRamps[n] = r
        return r
    }

    /// Real seconds since the animation started, recovered from simulated time so the
    /// camera path stays in step with the scene however it is being driven.
    private func elapsedRealSeconds(for date: Date) -> Double {
        let perSecond = model.config.yearsPerSecond * Constants.secondsPerJulianYear
        guard perSecond > 0 else { return 0 }
        return date.timeIntervalSince(startDate) / perSecond
    }

    /// Unit vector from the Sun to the camera at a point in time.
    ///
    /// The camera follows its own orbit around the Sun, like an extra planet: a circle
    /// inclined to the ecliptic, with the ascending node aligned to the Sun's direction
    /// of travel. Only the *direction* comes from here — the radius is whatever the
    /// framing fit needs, so the composition stays correct all the way round.
    /// The camera orbit's plane, in galactic coordinates.
    ///
    /// The node line is the direction of travel projected into the ecliptic, so the orbit
    /// is oriented against something meaningful rather than an arbitrary axis. Derived in
    /// one place because the camera's position and its up vector both depend on it — if
    /// they disagreed, the camera would be flying one orbit while framed against another.
    private var orbitFrame: (node: SIMD3<Double>, inPlane: SIMD3<Double>, normal: SIMD3<Double>) {
        let drift = GalacticFrame.solarApexDirection
        let pole = GalacticFrame.eclipticPoleInGalactic
        let node = simd_normalize(drift - pole * simd_dot(drift, pole))
        let inPlane = simd_normalize(simd_cross(pole, node))
        let i = orbit.inclinationDegrees * .pi / 180
        return (node, inPlane, simd_normalize(cos(i) * pole - sin(i) * inPlane))
    }

    private func cameraDirection(atElapsed t: Double) -> SIMD3<Double> {
        if let fixed = fixedDirection { return simd_normalize(fixed) }

        let drift = GalacticFrame.solarApexDirection
        let pole = GalacticFrame.eclipticPoleInGalactic
        let frame = orbitFrame

        guard orbit.enabled, orbit.periodSeconds > 0 else {
            let e = orbit.elevationDegrees * .pi / 180
            let a = orbit.azimuthDegrees * .pi / 180
            let e1 = simd_normalize(pole - drift * simd_dot(pole, drift))
            let e2 = simd_normalize(simd_cross(drift, e1))
            let view = simd_normalize(cos(e) * drift + sin(e) * (cos(a) * e1 + sin(a) * e2))
            return -view
        }

        // Tilt the in-plane perpendicular out of the ecliptic to incline the orbit.
        let i = orbit.inclinationDegrees * .pi / 180
        let tilted = cos(i) * frame.inPlane + sin(i) * pole
        let u = (orbit.phaseDegrees + 360 * t / orbit.periodSeconds) * .pi / 180
        return simd_normalize(cos(u) * frame.node + sin(u) * tilted)
    }

    /// Screen basis for a camera offset direction.
    ///
    /// Screen-right is kept along the drift axis wherever that is meaningful, so the
    /// Sun's track holds a consistent angle however far round the orbit the camera is.
    /// If the camera swings near the travel axis that projection shrinks to nothing, at
    /// which point any perpendicular will do — hence the fallback.
    private func cameraBasis(
        direction dir: SIMD3<Double>
    ) -> (dir: SIMD3<Double>, up: SIMD3<Double>) {
        let view = -dir

        // A pinned camera has no orbit to take its up vector from, so derive a stable
        // one: the drift axis projected into the screen plane, which keeps the frame
        // level and identical every frame.
        let levelUp: SIMD3<Double>
        if fixedDirection != nil {
            let drift = GalacticFrame.solarApexDirection
            let hint = drift - view * simd_dot(drift, view)
            let right =
                simd_length(hint) > 0.12
                ? simd_normalize(hint)
                : simd_normalize(simd_cross(view, GalacticFrame.eclipticPoleInGalactic))
            levelUp = simd_normalize(simd_cross(right, view))
        } else {
            // The camera orbit's own normal — fixed in world space, and perpendicular to
            // the view direction by construction, so no degenerate case to guard.
            //
            // Deriving up from the drift axis instead pinned the Sun's track to a constant
            // screen angle, which acted as a gimbal: it held the most prominent feature
            // still while the camera moved behind it, and combined with a fit that
            // re-centres every frame it stabilised the orbit right out of view. The
            // orbit's normal gives a turntable — the system visibly rotates as the camera
            // goes round, which is what makes the motion read. It also keeps the track
            // pointing downwards throughout, since the drift axis has a constant component
            // (0.86·cos inclination) along it.
            levelUp = orbitFrame.normal
        }

        // Roll about the view axis, biasing the Sun's track towards the bottom-left.
        let right = simd_normalize(simd_cross(view, levelUp))
        let roll = orbit.rollDegrees * .pi / 180
        return (dir: dir, up: simd_normalize(cos(roll) * levelUp + sin(roll) * right))
    }

    /// Re-fits and repositions the camera for one frame.
    ///
    /// Called every frame rather than once at startup, because the camera is moving and
    /// the optimal distance changes with the viewing angle: a view down the drift axis
    /// needs a very different distance from a side view of the same content. Reusing the
    /// caller's snapshot keeps this free of extra ephemeris work.
    /// Returns the framed half-extent, which sets ribbon width — returned rather than
    /// stashed in a property so callers cannot read a stale value from a previous frame.
    @discardableResult
    private func fitCamera(
        snapshot snap: SystemSnapshot,
        dir: SIMD3<Double>,
        up: SIMD3<Double>,
        elapsedSeconds: Double
    ) -> Double {
        guard aspectRatio > 0 else { return framedRadius }
        let right = simd_normalize(simd_cross(-dir, up))

        // Fit to where the *visible* mass is, weighting every sample by the brightness
        // it will actually be drawn with.
        //
        // Two earlier approaches both failed. A bounding sphere over-provisions whichever
        // screen axis isn't binding. A hard bounding box is worse than it sounds: it is
        // set by the extreme tips of the faintest trail tails, which drags the frame
        // centre away from the bright mass and opens a dead band on the opposite side.
        // Both were replaced; see the percentile rationale below.
        var sumW = 0.0
        var sumD = 0.0, sumD2 = 0.0
        samplesR.removeAll(keepingCapacity: true)
        samplesU.removeAll(keepingCapacity: true)

        func include(_ world: SIMD3<Double>, weight: Double) {
            guard weight > 1e-6 else { return }
            let v = world - snap.sunPosition
            let r = simd_dot(v, right), u = simd_dot(v, up), d = simd_dot(v, dir)
            sumW += weight
            samplesR.append((r, weight))
            samplesU.append((u, weight))
            sumD += weight * d
            sumD2 += weight * d * d
        }

        for body in snap.bodies {
            if framing == .wholeTrail {
                let n = body.trail.count
                guard n > 1 else { continue }
                let ramp = weightRamp(count: n)
                for (i, p) in body.trail.enumerated() {
                    include(p, weight: ramp[i])
                }
            }
            // The body itself is a bright disc, worth more than one ribbon sample.
            include(body.scenePosition, weight: framing == .wholeTrail ? 12 : 1)
        }
        include(snap.sunPosition, weight: framing == .wholeTrail ? 40 : 1)
        guard sumW > 0 else { return framedRadius }

        // Weighted percentiles rather than mean ± k·sigma. The composition is strongly
        // asymmetric — the Sun is the brightest thing and sits at one end, with trails
        // streaming away from it — so a symmetric window about the mean reserves as much
        // room beyond the Sun as the trails need on the other side, and that empty half
        // becomes a dead band. Percentiles find the two ends independently, and clip the
        // faint tail without clipping the Sun.
        let (loR, hiR) = weightedRange(&samplesR, totalWeight: sumW)
        let (loU, hiU) = weightedRange(&samplesU, totalWeight: sumW)

        // A body's disc and bloom halo extend past its centre point, so without this
        // margin the outermost planet gets its dot sliced by the frame edge.
        let bodyMargin = maximumBodyRadius * 1.8

        let rawTarget: SIMD3<Double>
        let halfWidth: Double
        let halfHeight: Double
        if fixedDirection != nil {
            // A pinned camera centres on the Sun, not on the content's centre of
            // brightness. Those are not the same point: the planets are strung out
            // around their orbits at any instant, so the weighted middle of everything
            // drawn sits off to one side, and an orrery whose Sun is not in the middle
            // of the frame reads as misaligned. Framed symmetrically about the origin.
            rawTarget = .zero
            halfWidth = max(abs(loR), abs(hiR)) + bodyMargin
            halfHeight = max(abs(loU), abs(hiU)) + bodyMargin
        } else {
            rawTarget = right * ((loR + hiR) / 2) + up * ((loU + hiU) / 2)
            halfWidth = (hiR - loR) / 2 + bodyMargin
            halfHeight = (hiU - loU) / 2 + bodyMargin
        }
        framedRadius = max(halfWidth, halfHeight)

        // `fieldOfView` is pinned to the vertical axis in setupCamera().
        let tanHalfFov = tan(Self.fieldOfViewDegrees * .pi / 360)
        let neededForHeight = halfHeight / tanHalfFov
        let neededForWidth = halfWidth / (tanHalfFov * aspectRatio)

        // Push back far enough that the near side of the content is in front of the
        // camera. Using the *maximum* depth here is far too conservative once the view
        // swings towards the travel axis: the content is then ~4.5 units deep, almost
        // all of it faint trail tail, and reserving for the very nearest point shrinks
        // everything to the middle of the frame. Weighting depth the same way as the
        // lateral extent references the plane the visible mass actually occupies.
        let meanD = sumD / sumW
        let sdD = (max(0, sumD2 / sumW - meanD * meanD)).squareRoot()
        let depthReference = meanD + 1.2 * sdD

        let rawDistance =
            max(neededForHeight, neededForWidth)
            * Self.framePadding / max(0.01, zoom)
            + max(0, depthReference)

        // Low-pass the fit before using it.
        //
        // The fit is recomputed every frame from where the bodies currently are, so the
        // raw target and distance oscillate at the inner planets' orbital frequency —
        // unsmoothed that was ~20px of frame shift and a 4.7% zoom throb several times a
        // second, which read as the camera wobbling rather than orbiting.
        //
        // Two time constants, both well under the camera's revolution period so the fit
        // tracks the viewing angle rather than trailing it.
        //
        // Distance genuinely has to move: the helix is long and thin, so its projected
        // extent changes ~25% between end-on and side-on. It needs a longer constant than
        // the target only to suppress the inner planets' orbital jitter — at 7 s a 2.9 s
        // Earth cycle is attenuated ~15×, which is ample, while an 80 s orbit passes
        // through nearly untouched.
        let targetTau = 3.0, distanceTau = 7.0
        if let last = lastFitElapsed {
            let dt = max(0, elapsedSeconds - last)
            cameraTarget += (rawTarget - cameraTarget) * (1 - exp(-dt / targetTau))
            smoothedDistance += (rawDistance - smoothedDistance) * (1 - exp(-dt / distanceTau))
        } else {
            cameraTarget = rawTarget
            smoothedDistance = rawDistance
        }
        lastFitElapsed = elapsedSeconds

        let target = cameraTarget
        let pos = target + dir * smoothedDistance
        cameraNode.position = SCNVector3(pos.x, pos.y, pos.z)
        cameraNode.look(
            at: SCNVector3(target.x, target.y, target.z),
            up: SCNVector3(up.x, up.y, up.z),
            localFront: SCNVector3(0, 0, -1)
        )
        return framedRadius
    }

    /// Rebuilds body positions and trail geometry for a simulated date, and advances the
    /// camera along its orbit.
    public func update(to date: Date) {
        currentDate = date
        guard let snap = try? model.snapshot(at: date) else { return }
        let origin = snap.sunPosition

        let elapsed = elapsedRealSeconds(for: date)
        let basis = cameraBasis(direction: cameraDirection(atElapsed: elapsed))

        // A pinned camera is fitted once and then left alone. Re-fitting every frame
        // would keep nudging the target and distance as the planets move round their
        // orbits — small, but a camera that is supposed to be motionless must not drift
        // at all. Recomputed only when the viewport shape changes.
        let framed: Double
        if fixedDirection != nil, let locked = lockedFit {
            framed = locked
        } else {
            framed = fitCamera(
                snapshot: snap, dir: basis.dir, up: basis.up, elapsedSeconds: elapsed
            )
            if fixedDirection != nil { lockedFit = framed }
        }

        // Everything else is drawn Sun-relative and therefore static; the star field
        // scrolling is what makes the scene read as travelling rather than parked.
        // Signed along the drift axis, not a magnitude — the sign matters if the scene
        // is ever run at a date before the epoch.
        starField.update(
            driftDistance: simd_dot(origin, GalacticFrame.solarApexDirection)
                + elapsed * idleStarDriftFraction * model.sceneExtent
        )

        // Measured from what the camera is aimed at, not the origin — the two differ
        // once the framing offset kicks in, and ribbons oriented against the wrong
        // vector turn edge-on and thin out at the edges of frame.
        // `fitCamera` placed the camera at `cameraTarget + basis.dir * distance`, so the
        // direction back to it is exactly the basis vector we already have.
        let toCamera = basis.dir
        let width = Self.ribbonHalfWidth(framedRadius: framed)

        // The Sun's own track: a straight line by construction, defining the axis the
        // whole system helixes around. Sampled rather than drawn as a two-point line so
        // the brightness ramp is smooth.
        do {
            // Length of the Sun's own track. Spanning the whole trail window is right
            // when the trails are framed, but when the camera is framing the orbits the
            // track is far longer than the view — only its brightest, widest end is on
            // screen, which reads as a bar across the picture rather than a receding
            // line. Scale it to the frame instead.
            let axisLength: Double
            switch framing {
            case .wholeTrail:
                axisLength =
                    model.config.scale.driftUnitsPerYear
                    * (model.longestTrailDuration / Constants.secondsPerJulianYear)
            case .orbitalExtent:
                axisLength = framed * 6
            }
            let back = -GalacticFrame.solarApexDirection * axisLength
            let last = Self.sunAxisSamples - 1
            let axis = (0...last).map { i in back * (1 - Double(i) / Double(last)) }
            // Dimmer and thinner when the camera is close to the orbits: at that range
            // only the track's brightest, widest end is on screen and it reads as a bar
            // laid across the picture rather than a line receding into the distance.
            let axisWidth = framing == .orbitalExtent ? width * 0.35 : width * 1.05
            sunTrailNode.geometry = sunRibbon.geometry(
                points: axis, origin: .zero, toCamera: toCamera, halfWidth: axisWidth
            )
        }

        dateOverlay.update(date: date)

        for body in snap.bodies {
            let p = body.scenePosition - origin
            bodyNodes[body.planet]?.position = SCNVector3(p.x, p.y, p.z)

            // Ribbon width is a fraction of the framed scene, which is right while every
            // orbit is a similar size — but once distances are real the inner orbits are
            // a tiny fraction of the frame, and a trail drawn at the scene's width is
            // half as wide as Mercury's whole orbit. Four inner planets drawn like that,
            // overlapping additively, saturate into one white blob with the Sun lost
            // inside it. Cap each trail against the orbit it is actually tracing.
            let orbitRadius = simd_length(body.scenePosition - origin)
            trailNodes[body.planet]?.geometry = ribbons[body.planet]?.geometry(
                points: body.trail, origin: origin, toCamera: toCamera,
                halfWidth: min(width, orbitRadius * Self.maxTrailWidthFraction)
            )
        }
    }

    /// Ribbon thickness scales with the framed size so it looks the same at any zoom.
    private static func ribbonHalfWidth(framedRadius: Double) -> Double {
        max(0.004, framedRadius * 0.0055)
    }

    public func date(forElapsed realSeconds: Double) -> Date {
        startDate.addingTimeInterval(
            realSeconds * model.config.yearsPerSecond * Constants.secondsPerJulianYear
        )
    }

    /// Low and high weighted percentiles of a sample set. Sorts in place; the caller's
    /// arrays are scratch buffers rebuilt each frame.
    private func weightedRange(
        _ samples: inout [(value: Double, weight: Double)],
        totalWeight: Double,
        lowFraction: Double = 0.02,
        highFraction: Double = 0.98
    ) -> (low: Double, high: Double) {
        guard !samples.isEmpty, totalWeight > 0 else { return (0, 0) }
        samples.sort { $0.value < $1.value }

        func quantile(_ f: Double) -> Double {
            let threshold = totalWeight * f
            var cumulative = 0.0
            for s in samples {
                cumulative += s.weight
                if cumulative >= threshold { return s.value }
            }
            return samples[samples.count - 1].value
        }
        return (quantile(lowFraction), quantile(highFraction))
    }

    public var pointOfView: SCNNode { cameraNode }

    /// The faint date readout, to be attached as the renderer's `overlaySKScene`.
    public var overlayScene: SKScene { dateOverlay.scene }

    /// Sizes the overlay explicitly. Only the offscreen renderer needs this — a live
    /// view's overlay is sized by SpriteKit, and setting it as well is what made the
    /// readout jitter.
    public func setOverlaySize(_ size: CGSize) {
        dateOverlay.setSize(size)
        dateOverlay.update(date: currentDate)
    }

    /// Camera state for diagnostics — lets a trace distinguish "the camera is sweeping"
    /// from "the framing is jittering frame to frame".
    public var cameraState: (position: SIMD3<Double>, target: SIMD3<Double>, distance: Double) {
        let p = SIMD3<Double>(
            Double(cameraNode.position.x),
            Double(cameraNode.position.y),
            Double(cameraNode.position.z)
        )
        return (p, cameraTarget, simd_distance(p, cameraTarget))
    }
}
