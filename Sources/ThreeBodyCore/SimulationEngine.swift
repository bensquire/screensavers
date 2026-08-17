import Foundation
import SaverKit

/// Diagnostics for the HUD. Energy and angular momentum are exact constants of
/// the true motion, so these numbers are a direct readout of how much the
/// integration has strayed.
public struct SimulationStats {
    public var simulatedTime: Double = 0
    public var relativeEnergyError: Double = 0
    public var angularMomentumError: Double = 0
    public var lastStepSize: Double = 0
    public var forceEvaluationsPerSecond: Double = 0
    /// True when the step budget ran out — the scene is then running in slow
    /// motion through a close encounter rather than cutting accuracy.
    public var stepBudgetExhausted: Bool = false
    public var minimumSeparation: Double = 0
}

/// How a scene finished, when it finished for a reason worth showing.
///
/// A scene that simply ran out its clock has no ending — it just cross-fades.
/// These two are the moments where the system genuinely resolves itself, so
/// they get marked before the lights go down.
public struct SceneEnding {
    public enum Kind {
        /// A body became unbound and is leaving for good.
        case escape
        /// Two bodies touched and merged.
        case collision
    }

    public let kind: Kind
    /// Where it happened, in world coordinates, so the camera can pan and zoom
    /// under it and the marker stays put.
    public let position: Vec2
    /// Palette slots of the bodies involved, so the effect is drawn in their
    /// colours.
    public let colorIndices: [Int]
    /// Kinetic energy shed by an inelastic merge, as a multiple of the
    /// scene's own total energy — an absolute figure is meaningless without
    /// that scale. Zero for an escape.
    public let energyLostRelative: Double
    /// Real seconds since it fired.
    public var age: Double = 0
}

/// Everything drawn for one body that is not its physical state: its trail, and
/// the palette slot it keeps for the whole scene.
///
/// One array rather than two parallel ones, because bodies can disappear
/// mid-scene when a pair merges and two arrays that must have the same index
/// removed from both is a standing invitation to recolour the survivors.
public struct BodyView {
    public var trail = Trail()
    /// Palette slot, assigned by mass rank at scene start and kept thereafter.
    public var colorIndex: Int
}

/// Owns the physics, the trails, the camera and the scene lifecycle.
/// Deliberately free of AppKit so it can be exercised from a command-line test.
public final class SimulationEngine {

    private enum Phase {
        case fadingIn
        case running
        case fadingOut
    }

    public var settings: SimulationSettings {
        didSet { applySettings() }
    }

    public private(set) var system: NBodySystem
    public private(set) var scenario: Scenario
    public private(set) var bodyViews: [BodyView]
    public private(set) var camera = Camera()
    public private(set) var stats = SimulationStats()

    /// 0 = black, 1 = fully visible. Drives the cross-fade between scenes.
    public private(set) var visibility: Double = 0

    /// Set when the scene resolves itself rather than just running out of time.
    public private(set) var ending: SceneEnding?

    private var stepper: AdaptiveStepper
    private var rng: SplitMix64
    private var phase: Phase = .fadingIn
    private var phaseTime: Double = 0
    private var sceneRealTime: Double = 0
    private var escapeConfirmedFor: Double = 0
    /// Set by the physics step when it halted on two bodies touching.
    private var contactDetected = false
    private var framingMode: FramingMode = .all
    /// Diagnostic: how many times the framing set has changed this scene.
    private var framingModeAge: Double = 0
    private var recentScenarioNames: [String] = []

    /// The scene's initial span, which sets the physical scale everything
    /// relative is measured against (contact radii, camera zoom limit).
    private var sceneExtent: Double = 1
    private var referenceEnergy: Double = 0
    private var referenceAngularMomentum: Double = 0
    private var referenceScale: Double = 1

    private let fadeDuration: Double = 1.6
    /// A scene that ends on an escape or a collision fades more slowly, to
    /// give the send-off room to play.
    private let endingFadeDuration: Double = 3.0
    /// Real seconds an escape must persist before the scene is retired.
    private let escapeHoldTime: Double = 3.5
    /// Give up on a scene whose energy error has become embarrassing.
    private let energyErrorLimit: Double = 5e-3
    /// Screen points per second the bodies should typically cover — about a
    /// seventh of a 1440-point window each second. Chosen so the catalogue
    /// orbits keep roughly the pace they were designed at (the figure-eight
    /// takes about 13 seconds a revolution) while the wide generated systems,
    /// which were running several times too slow, are brought up to match.
    private let targetPointsPerSecond: Double = 210.0
    private let minPlaybackRate: Double = 0.2
    /// Capped well below what the pacing controller would sometimes ask for:
    /// past this the scene evolves faster than the camera can follow without
    /// visible work, and a steadier frame is worth more than the extra speed.
    private let maxPlaybackRate: Double = 8.0
    /// Span at which a tightly bound pair is collapsed to its centre of mass
    /// for framing, as a multiple of its own separation. Below this the pair's
    /// orbit is a feature worth watching; above it, it is just jitter.
    private let pairCollapseRatio: Double = 6.0
    /// Minimum seconds between changes of framing mode.
    private let framingModeDwell: Double = 9.0
    /// Widest span the camera will try to hold, as a multiple of the closest
    /// pair's separation. Comfortably above the ~16 a hierarchical triple
    /// reaches, so only genuinely degenerate configurations trip it.
    private let maxFramingRange: Double = 22.0
    /// Work ceiling per frame, in force evaluations. Normal scenes use a few
    /// hundred; the cap only bites inside an exceptionally deep encounter,
    /// where the scene visibly slows rather than quietly losing accuracy.
    private let maxForceEvaluationsPerFrame = 60_000

    /// `scenario` pins the opening scene; the engine picks randomly from there
    /// on. Used by the test renderer to look at a specific configuration.
    public init(
        settings: SimulationSettings = .default,
        seed: UInt64? = nil,
        scenario: Scenario? = nil
    ) {
        self.settings = settings
        // Seed from the clock unless a caller wants a reproducible run.
        self.rng = SplitMix64(
            seed: seed ?? UInt64(Date().timeIntervalSince1970 * 1000) &* 2654435761)
        let first =
            scenario
            ?? Scenarios.random(families: settings.families, excluding: [], using: &rng)
        self.scenario = first
        self.system = first.system
        self.bodyViews = first.bodies.indices.map { BodyView(colorIndex: $0) }
        self.stepper = AdaptiveStepper(order: settings.accuracy.order, eta: settings.accuracy.eta)
        beginScene(first)
    }

    /// Palette slot for the body currently at `index`. Bodies can disappear
    /// mid-scene when two merge, so position in the array is not a stable
    /// identity — this is.
    public func colorIndex(at index: Int) -> Int {
        index < bodyViews.count ? bodyViews[index].colorIndex : index
    }

    /// The trail of the body currently at `index`.
    public func trail(at index: Int) -> Trail? {
        index < bodyViews.count ? bodyViews[index].trail : nil
    }

    // MARK: - Scene lifecycle

    /// Retire the current scene immediately (used by the preview app's
    /// keyboard shortcut).
    public func advanceToNextScene() {
        if phase != .fadingOut {
            phase = .fadingOut
            phaseTime = 0
        }
    }

    private func beginScene(_ scene: Scenario) {
        scenario = scene
        system = scene.system
        // Palette by mass rank, not by array position: the heaviest body is
        // the same colour in every scene, so the hierarchy reads at a glance.
        let byMass = scene.bodies.indices.sorted { scene.bodies[$0].mass > scene.bodies[$1].mass }
        bodyViews = scene.bodies.indices.map { _ in BodyView(colorIndex: 0) }
        for (rank, body) in byMass.enumerated() { bodyViews[body].colorIndex = rank }
        ending = nil
        camera.reset()
        contactDetected = false
        framingMode = .all
        framingModeAge = 0
        sceneExtent = max(system.maximumSeparation, 1e-9)
        // Cap how far the camera will zoom in. A binary can harden without
        // limit; magnifying it without limit would just smear the trails across
        // the screen and lose all sense of the original configuration.
        camera.minimumHalfExtent = 0.05 * sceneExtent
        camera.maximumHalfExtent = 3.0 * sceneExtent
        sceneRealTime = 0
        escapeConfirmedFor = 0
        referenceEnergy = system.totalEnergy
        referenceAngularMomentum = system.angularMomentum
        // Characteristic angular momentum for the error denominator when the
        // true value is zero (free-fall scenes start with L = 0 exactly).
        referenceScale = max(
            abs(referenceAngularMomentum),
            system.totalMass * system.maximumSeparation
                * max(system.kineticEnergy, 1e-6).squareRoot())
        playbackRate = 1.0
        smoothedScreenSpeed = 0
        stats = SimulationStats()
        applySettings()

        recentScenarioNames.append(scene.name)
        if recentScenarioNames.count > 4 { recentScenarioNames.removeFirst() }
    }

    private func applySettings() {
        stepper.integrator = SymplecticIntegrator(order: settings.accuracy.order)
        stepper.eta = settings.accuracy.eta
        let span = settings.trailSeconds * simulatedTimePerRealSecond
        for i in bodyViews.indices {
            bodyViews[i].trail.span = span
        }
    }

    /// Smoothed playback multiplier, 1 = the scenario's nominal pace.
    public private(set) var playbackRate: Double = 1.0
    private var smoothedScreenSpeed: Double = 0

    private var simulatedTimePerRealSecond: Double {
        scenario.timeScale * settings.speed * playbackRate
    }

    /// Hold the *apparent* speed roughly constant.
    ///
    /// Earlier versions paced the scene from dynamical timescales, which sounds
    /// principled and is the wrong quantity: a timescale knows nothing about
    /// how big the system looks on screen. A wide, cold triple whose closest
    /// pair had drawn in slightly would be slowed to 60% while visibly barely
    /// moving, because the arithmetic could not tell "close" from "close *and*
    /// fast".
    ///
    /// What actually reads as the right pace is how fast things cross the
    /// screen, so that is what is controlled. Screen speed already folds in
    /// everything that matters — how fast the bodies move, and how far out the
    /// camera has had to pull to hold them — so a wide slow system speeds up
    /// and a violent close encounter slows down, both for the same reason.
    private func updatePlaybackRate(dt: Double) {
        guard settings.adaptivePlayback else {
            playbackRate = 1.0
            return
        }
        guard camera.worldPerPoint > 0 else { return }

        // Root-mean-square speed across the bodies, not the maximum. A
        // figure-eight's fastest body at the crossing is about four times the
        // typical speed, and pacing to that moment slowed the entire orbit to a
        // quarter speed to accommodate it. The RMS is what the eye reads as
        // "how fast this scene is going".
        var sumSquares = 0.0
        for body in system.bodies { sumSquares += body.velocity.lengthSquared }
        let rms = (sumSquares / Double(max(system.bodies.count, 1))).squareRoot()
        let nominalPace = scenario.timeScale * settings.speed
        let instantaneous = rms / camera.worldPerPoint * nominalPace
        guard instantaneous > 1e-9 else { return }

        // Smooth the measurement before acting on it. A periodic orbit has a
        // brief speed peak every revolution; responding to the peak itself
        // slowed the whole orbit fourfold to accommodate a moment of it.
        if smoothedScreenSpeed <= 0 {
            smoothedScreenSpeed = instantaneous
        } else {
            let alpha = Camera.approach(dt: dt, tau: 2.5)
            smoothedScreenSpeed += (instantaneous - smoothedScreenSpeed) * alpha
        }

        let target = min(
            max(
                targetPointsPerSecond / smoothedScreenSpeed,
                minPlaybackRate), maxPlaybackRate)

        // Dead zone, so ordinary orbital variation changes nothing at all.
        guard abs(target - playbackRate) > 0.2 * playbackRate else { return }

        // Slowing down may happen promptly — arriving late to an encounter is
        // worse than lingering after one — but speeding back up is gradual, and
        // both are slow enough that the pace never visibly lurches.
        playbackRate += (target - playbackRate) * Camera.approach(dt: dt, tau: 2.5)
    }

    // MARK: - Per-frame update

    public func update(deltaTime rawDelta: Double, viewSize: (width: Double, height: Double)) {
        // A screensaver can be paused, or the machine can sleep; a huge delta
        // would try to integrate hours of dynamics in one frame.
        let dt = min(max(rawDelta, 0), 1.0 / 20.0)
        phaseTime += dt
        sceneRealTime += dt

        switch phase {
        case .fadingIn:
            visibility = min(1, phaseTime / fadeDuration)
            if visibility >= 1 {
                phase = .running
                phaseTime = 0
            }
        case .running:
            visibility = 1
        case .fadingOut:
            let duration = ending == nil ? fadeDuration : endingFadeDuration
            visibility = max(0, 1 - phaseTime / duration)
            if visibility <= 0 {
                let next = Scenarios.random(
                    families: settings.families,
                    excluding: recentScenarioNames,
                    using: &rng)
                beginScene(next)
                phase = .fadingIn
                phaseTime = 0
                visibility = 0
                return
            }
        }

        updatePlaybackRate(dt: dt)
        // Trails are specified in seconds of screen time, so their span in
        // simulated time has to follow the playback rate as it changes.
        let span = settings.trailSeconds * simulatedTimePerRealSecond
        for i in bodyViews.indices { bodyViews[i].trail.span = span }
        advancePhysics(by: dt)
        updateCameraAndTrails(dt: dt, viewSize: viewSize)
        ending?.age += dt

        if phase == .running {
            // Contact is checked before the softer reasons: two bodies that
            // have touched are no longer the system the other tests describe.
            if contactDetected,
                let pair = system.touchingPair(
                    contactScale: NBodySystem.Contact.scale * sceneExtent)
            {
                resolveCollision(pair)
            } else if shouldRetireScene(dt: dt) {
                retireScene()
            }
        }
    }

    /// Merge the pair, mark the moment, and start the send-off.
    private func resolveCollision(_ pair: (i: Int, j: Int)) {
        let colors = [bodyViews[pair.i].colorIndex, bodyViews[pair.j].colorIndex]
        let result = system.merge(pair.i, pair.j)
        let position = system.bodies[result.index].position

        // The surviving trail belongs to the merged body; the absorbed one's
        // history goes with it, and the palette slots shift down to match.
        bodyViews.remove(at: max(pair.i, pair.j))

        // Report the loss against the scene's energy scale before it changes.
        let energyScale = max(abs(referenceEnergy), 1e-12)

        // An inelastic merge genuinely removes kinetic energy from the system,
        // so the old baseline would read as a huge integration failure and trip
        // the accuracy cut-out. Re-baseline onto the post-merge system.
        referenceEnergy = system.totalEnergy
        referenceAngularMomentum = system.angularMomentum
        stats.relativeEnergyError = 0
        stats.angularMomentumError = 0

        ending = SceneEnding(
            kind: .collision,
            position: position,
            colorIndices: colors,
            energyLostRelative: result.kineticEnergyLost / energyScale)
        retireScene()
    }

    private func retireScene() {
        guard phase != .fadingOut else { return }
        phase = .fadingOut
        phaseTime = 0
    }

    private func advancePhysics(by dt: Double) {
        let interval = dt * simulatedTimePerRealSecond
        guard interval > 0 else { return }

        // Time symmetrisation takes a trial step before the real one, so a
        // step costs twice its nominal evaluation count.
        let evaluationsPerStep = 2 * settings.accuracy.order.forceEvaluationsPerStep
        let stepBudget = max(16, maxForceEvaluationsPerFrame / evaluationsPerStep)

        // Contact is tested per integrator step, not per frame: two bodies
        // cross the contact radius in far less than a frame.
        let contactRadiusScale = NBodySystem.Contact.scale * sceneExtent
        let result = stepper.advance(&system, by: interval, maxSteps: stepBudget) { state in
            state.touchingPair(contactScale: contactRadiusScale) != nil
        }
        contactDetected = result.stopped

        stats.simulatedTime = system.time
        stats.lastStepSize = result.lastStep
        stats.stepBudgetExhausted = result.steps >= stepBudget
        stats.minimumSeparation = system.minimumSeparation
        if dt > 0 {
            stats.forceEvaluationsPerSecond = Double(result.steps * evaluationsPerStep) / dt
        }

        let energy = system.totalEnergy
        let denominator = max(abs(referenceEnergy), 1e-12)
        stats.relativeEnergyError = abs(energy - referenceEnergy) / denominator
        stats.angularMomentumError =
            abs(system.angularMomentum - referenceAngularMomentum) / max(referenceScale, 1e-12)
    }

    /// How the scene is being framed right now. Changing between these is a
    /// discontinuity the camera has to absorb rather than chase.
    private enum FramingMode: Equatable {
        /// All bodies individually.
        case all
        /// A tightly bound pair reduced to its centre of mass, plus the rest.
        case pairCollapsed(i: Int, j: Int)
        /// Only the surviving pair; a departing body is being let go.
        case pairOnly(i: Int, j: Int)
    }

    /// The point to centre the view on: the centre of mass of whichever bodies
    /// are being framed. Framing the whole system anchors on the origin, which
    /// is stationary for the entire scene because the scene is integrated in
    /// its centre-of-mass frame.
    private func framingAnchor(for mode: FramingMode) -> Vec2 {
        switch mode {
        case .all:
            return system.centerOfMass
        case .pairCollapsed:
            return system.centerOfMass
        case .pairOnly(let i, let j):
            guard system.bodies.indices.contains(i), system.bodies.indices.contains(j) else {
                return system.centerOfMass
            }
            return NBodySystem.combined(system.bodies[i], system.bodies[j]).position
        }
    }

    /// Half-extents about `anchor` that keep everything in `mode` on screen.
    ///
    /// Folded directly rather than gathered into an array first: the trails
    /// hold thousands of samples each, and the camera only ever reduces them to
    /// two numbers. Building a nine-thousand-element array sixty times a second
    /// to compute a pair of maxima is work with no result.
    private func framingExtents(for mode: FramingMode, anchor: Vec2) -> (x: Double, y: Double) {
        var halfX = 0.0
        var halfY = 0.0

        func include(_ p: Vec2) {
            halfX = max(halfX, abs(p.x - anchor.x))
            halfY = max(halfY, abs(p.y - anchor.y))
        }
        func includeBodyAndTrail(_ index: Int) {
            guard index < bodyViews.count else { return }
            include(system.bodies[index].position)
            for sample in bodyViews[index].trail.samples { include(sample.position) }
        }

        switch mode {
        case .all:
            for i in system.bodies.indices { includeBodyAndTrail(i) }
        case .pairOnly(let i, let j):
            includeBodyAndTrail(i)
            includeBodyAndTrail(j)
        case .pairCollapsed(let i, let j):
            // The pair contributes one point — its centre of mass — so its
            // internal orbit stops driving the camera. Everyone else is framed
            // normally, tails included.
            guard system.bodies.indices.contains(i), system.bodies.indices.contains(j) else {
                return framingExtents(for: .all, anchor: anchor)
            }
            include(NBodySystem.combined(system.bodies[i], system.bodies[j]).position)
            for k in system.bodies.indices where k != i && k != j { includeBodyAndTrail(k) }
        }
        return (halfX, halfY)
    }

    private func currentFramingMode() -> FramingMode {
        let pair = system.closestPair()
        guard system.bodies.count > 2 else { return .all }

        // Once a body looks like it is leaving, stop chasing it. Following it
        // out shrinks the surviving pair to a speck in the corner, and the
        // story of an ejection is the binary that remains.
        //
        // This starts the moment an escape is *detected*, not when it is
        // confirmed a few seconds later, so the camera is already settled by
        // the time the send-off plays.
        let alreadyPairOnly: Bool
        if case .pairOnly = framingMode { alreadyPairOnly = true } else { alreadyPairOnly = false }
        let releaseRatio = alreadyPairOnly ? maxFramingRange * 0.6 : maxFramingRange
        if escapeConfirmedFor > 0.15
            || ending?.kind == .escape
            || system.maximumSeparation > releaseRatio * pair.separation
        {
            return .pairOnly(i: pair.i, j: pair.j)
        }

        // A pair bound tightly relative to the third body orbits fast, and
        // framing both of them makes the whole view wobble at that frequency.
        // Collapse it to one point instead.
        // Hysteresis: enter collapsed framing at the full ratio, leave it only
        // once well clear, so a system sitting near the threshold cannot
        // oscillate between modes every few frames.
        let alreadyCollapsed: Bool
        if case .pairCollapsed = framingMode {
            alreadyCollapsed = true
        } else {
            alreadyCollapsed = false
        }
        let threshold = alreadyCollapsed ? pairCollapseRatio * 0.42 : pairCollapseRatio
        if system.maximumSeparation > threshold * pair.separation {
            return .pairCollapsed(i: pair.i, j: pair.j)
        }
        return .all
    }

    private func updateCamera(
        mode: FramingMode,
        viewSize: (width: Double, height: Double),
        dt: Double
    ) {
        let anchor = framingAnchor(for: mode)
        let extents = framingExtents(for: mode, anchor: anchor)
        camera.update(
            anchor: anchor,
            requiredHalfExtents: extents,
            viewSize: viewSize,
            deltaTime: dt)
    }

    private func updateCameraAndTrails(dt: Double, viewSize: (width: Double, height: Double)) {
        framingModeAge += dt
        var mode = currentFramingMode()
        // Reframing is expensive to watch, so it is rationed: whatever the
        // geometry does, the view will not be rebuilt more often than this.
        if mode != framingMode && framingModeAge < framingModeDwell {
            mode = framingMode
        }
        if mode != framingMode {
            framingModeAge = 0
            // The target is about to jump. Hand the camera the view it is
            // showing right now so the change is invisible this frame and gets
            // absorbed over the next second instead.
            let previousCenter = camera.center
            let previousScale = camera.worldPerPoint
            framingMode = mode
            updateCamera(mode: mode, viewSize: viewSize, dt: dt)
            camera.absorbDiscontinuity(
                previousCenter: previousCenter,
                previousScale: previousScale)
        } else {
            updateCamera(mode: mode, viewSize: viewSize, dt: dt)
        }

        // Roughly one sample per 1.5 points of screen travel.
        let spacing = camera.worldPerPoint * 1.5
        for i in system.bodies.indices where i < bodyViews.count {
            bodyViews[i].trail.record(
                position: system.bodies[i].position,
                time: system.time,
                minimumSpacing: spacing)
        }
    }

    // MARK: - Scene retirement

    private func shouldRetireScene(dt: Double) -> Bool {
        if sceneRealTime >= settings.sceneDuration { return true }

        // The integration has lost its grip (usually an exceptionally deep
        // encounter); the honest response is to move on, not to keep drawing.
        if stats.relativeEnergyError > energyErrorLimit { return true }

        if let escapee = system.unboundBody() {
            escapeConfirmedFor += dt

            // Only once it has held for the full confirmation window is the
            // body really gone rather than out on a long excursion.
            if escapeConfirmedFor >= escapeHoldTime {
                // Marked on the surviving pair rather than on the body that
                // left: that is what stays on screen, and a pulse spreading
                // from the binary reads as the system letting go.
                let pair = system.closestPair()
                let binary = NBodySystem(bodies: [system.bodies[pair.i], system.bodies[pair.j]])
                ending = SceneEnding(
                    kind: .escape,
                    position: binary.centerOfMass,
                    colorIndices: [bodyViews[escapee].colorIndex],
                    energyLostRelative: 0)
                return true
            }
        } else {
            // Decay rather than reset. The escape test is geometric and can
            // drop out for a frame or two mid-encounter; discarding seconds of
            // accumulated evidence each time made it flicker, and every flicker
            // reframed the camera.
            escapeConfirmedFor = max(0, escapeConfirmedFor - dt * 2.0)
        }
        return false
    }

}
