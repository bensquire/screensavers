import XCTest

@testable import VortexCore

final class SceneTests: XCTestCase {

    private let layout = Layout(pointWidth: 1440, pointHeight: 900, backingScale: 2)

    private func scene(_ settings: VortexSettings = .default) -> VortexScene {
        VortexScene(layout: layout, settings: settings, seed: 7)
    }

    // MARK: - Particles

    /// The field is built from a seed so a run can be reproduced exactly; a
    /// generator that drew on anything else would give a different tunnel each
    /// time, and a seed that changed nothing would give the same one.
    func testFieldIsReproducibleFromItsSeed() {
        let a = ParticleSet(count: 500, seed: 42)
        let b = ParticleSet(count: 500, seed: 42)
        XCTAssertEqual(a.streaks, b.streaks, "seed 42 built two different sets of streaks")
        XCTAssertEqual(a.sprites, b.sprites, "seed 42 built two different sets of sprites")

        let different = ParticleSet(count: 500, seed: 43)
        XCTAssertNotEqual(a.streaks, different.streaks, "seeds 42 and 43 built the same streaks")
    }

    /// The particle clock reaches the GPU as a Float of milliseconds, so it must
    /// never be allowed to grow with the session.
    func testParticleClockStaysSmallOverALongSession() {
        let scene = scene(VortexSettings(flowSpeed: 2.5, lightning: false, density: 0.25))
        // Three hours at 30 fps.
        for _ in 0..<(3 * 3600 * 30) {
            scene.update(deltaTime: 1.0 / 30, layout: layout)
        }
        XCTAssertLessThan(
            scene.particleClockMs, VortexScene.particleClockLimitMs,
            "after three hours the particle clock is \(scene.particleClockMs) ms")
        XCTAssertGreaterThan(
            scene.particleGeneration, 10, "the clock was rebased only \(scene.particleGeneration) times")
        let particles = scene.particles.streaks + scene.particles.sprites
        for (index, particle) in particles.enumerated() {
            XCTAssertGreaterThanOrEqual(
                Double(particle.z0), Tunnel.zNear - 1e-4, "particle \(index) is in front of the tunnel")
            XCTAssertLessThanOrEqual(
                Double(particle.z0), Tunnel.zFar + 1e-4, "particle \(index) is beyond the tunnel")
            XCTAssertLessThan(
                abs(particle.angle), 7, "particle \(index)'s angle has grown to \(particle.angle)")
            XCTAssertLessThan(
                abs(particle.wobblePhase), 7,
                "particle \(index)'s wobble phase has grown to \(particle.wobblePhase)")
            XCTAssertLessThan(
                abs(particle.twinklePhase), 7,
                "particle \(index)'s twinkle phase has grown to \(particle.twinklePhase)")
        }
    }

    /// 22% of particles become sprites and the rest streaks; a field that lost
    /// particles in the split, or put a sprite kind among the streaks, would be
    /// drawn by the wrong pipeline.
    func testFieldSplitsIntoStreaksAndSprites() {
        let set = ParticleSet(count: 5400, seed: 1)

        XCTAssertEqual(
            set.streaks.count + set.sprites.count, 5400, "particles were lost in the split")
        // A sample of 5400 should land close to the 22%.
        let spriteFraction = Double(set.sprites.count) / 5400
        XCTAssertEqual(
            spriteFraction, 0.22, accuracy: 0.03, "\(spriteFraction) of the particles are sprites")
        XCTAssertTrue(
            set.streaks.allSatisfy { $0.kind == ParticleKind.streak }, "a sprite is among the streaks")
        XCTAssertTrue(
            set.sprites.allSatisfy { $0.kind == ParticleKind.glint || $0.kind == ParticleKind.haze },
            "a streak is among the sprites")
    }

    /// Particles sit on the tunnel wall, moving forward; one in front of the
    /// camera, out in the volume or standing still would show as a stray.
    func testParticlesStartInsideTheTunnel() {
        let set = ParticleSet(count: 2000, seed: 3)
        for (index, particle) in (set.streaks + set.sprites).enumerated() {
            XCTAssertGreaterThanOrEqual(
                particle.z0, Float(Tunnel.zNear), "particle \(index) starts in front of the tunnel")
            XCTAssertLessThanOrEqual(
                particle.z0, Float(Tunnel.zFar), "particle \(index) starts beyond the tunnel")
            XCTAssertEqual(
                Double(particle.radius), Tunnel.radius, accuracy: 0.15,
                "particle \(index) is at radius \(particle.radius), off the wall")
            XCTAssertGreaterThan(particle.speed, 0, "particle \(index) does not move")
        }
    }

    // MARK: - Clocks

    /// Flow speed scales only the particles' own clock. If it scaled real time
    /// too, lightning and steering would speed up with it.
    func testParticleClockRunsWithTheFlowSpeed() {
        let slow = scene(VortexSettings(flowSpeed: 0.5, lightning: false, density: 0.05))
        let fast = scene(VortexSettings(flowSpeed: 2.0, lightning: false, density: 0.05))
        for _ in 0..<600 {
            slow.update(deltaTime: 1.0 / 60, layout: layout)
            fast.update(deltaTime: 1.0 / 60, layout: layout)
        }
        XCTAssertEqual(
            slow.elapsedMs, fast.elapsedMs, accuracy: 1e-9, "flow speed changed real time")
        let ratio = fast.particleClockMs / slow.particleClockMs
        XCTAssertEqual(
            ratio, 4.0, accuracy: 1e-6, "flow 2.0 ran the particles \(ratio)x as fast as flow 0.5")
    }

    /// The display slept for a minute. Advancing by the whole gap would jump the
    /// tunnel; the clamp caps a single step at 48 ms.
    func testLongGapsAreNotIntegrated() {
        let s = scene()

        s.update(deltaTime: 60, layout: layout)

        XCTAssertEqual(
            s.elapsedMs, 48, accuracy: 1e-9, "a 60 s gap advanced the scene by \(s.elapsedMs) ms")
    }

    /// warp is allowed to go negative, but the multiplier it feeds is floored,
    /// so the tunnel can slow down without ever reversing or freezing.
    func testFlowNeverStops() {
        let s = scene()
        var previous = s.particleClockMs
        for frame in 0..<20_000 {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            XCTAssertGreaterThan(
                s.particleClockMs, previous, "frame \(frame): the flow stopped or reversed")
            previous = s.particleClockMs
        }
        XCTAssertGreaterThan(s.warp, -0.4, "warp fell to \(s.warp)")
        XCTAssertLessThan(s.warp, 0.6, "warp rose to \(s.warp)")
    }

    // MARK: - Steering

    /// The sum of sines is bounded by 0.97, and the eased follower cannot
    /// overshoot it, so the vanishing point stays within the frame.
    func testBendStaysOnScreen() {
        let s = scene()
        for frame in 0..<40_000 {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            XCTAssertLessThan(
                abs(s.bendPixels.x), Float(layout.maxBendPixels),
                "frame \(frame): the bend is \(s.bendPixels.x) px across, off screen")
            XCTAssertLessThan(
                abs(s.bendPixels.y), Float(layout.maxBendPixels),
                "frame \(frame): the bend is \(s.bendPixels.y) px down, off screen")
        }
    }

    /// The easing used to be per-frame, which made the tunnel wander at twice the
    /// speed on a 120Hz display. Same wall-clock, same pose.
    func testSteeringRateIsIndependentOfFrameRate() {
        let at60 = scene()
        let at120 = scene()
        for _ in 0..<600 { at60.update(deltaTime: 1.0 / 60, layout: layout) }
        for _ in 0..<1200 { at120.update(deltaTime: 1.0 / 120, layout: layout) }

        XCTAssertEqual(
            at60.elapsedMs, at120.elapsedMs, accuracy: 1e-6, "the two runs covered different times")
        XCTAssertEqual(
            at60.bendPixels.x, at120.bendPixels.x, accuracy: 1.0,
            "the bend is \(at60.bendPixels.x) px at 60 Hz, \(at120.bendPixels.x) px at 120 Hz")
        XCTAssertEqual(
            at60.bendPixels.y, at120.bendPixels.y, accuracy: 1.0,
            "the bend is \(at60.bendPixels.y) px at 60 Hz, \(at120.bendPixels.y) px at 120 Hz")
        // Not exact: the easing target moves within a step, so a finer step
        // tracks it slightly differently and the spin integrates that difference.
        // Within a percent is the claim — the per-frame version was out by 2x.
        let spinRatio = at60.tubeSpin / at120.tubeSpin
        XCTAssertEqual(
            spinRatio, 1.0, accuracy: 0.01, "the spin at 60 Hz is \(spinRatio)x the spin at 120 Hz")
    }

    // MARK: - Lightning

    /// Strikes are 22-38 s apart, so two minutes should see several, each with
    /// an intensity in range and a path to draw — and none left alive at the
    /// end unless one failed to expire.
    func testLightningStrikesAndFades() {
        let s = scene(VortexSettings(flowSpeed: 1, lightning: true, density: 0.05))
        var everStruck = false
        for frame in 0..<(120 * 60) {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            if !s.bolts.isEmpty { everStruck = true }
            for bolt in s.bolts {
                XCTAssertGreaterThanOrEqual(
                    bolt.intensity, 0, "frame \(frame): a bolt is at \(bolt.intensity)")
                XCTAssertLessThanOrEqual(
                    bolt.intensity, 1.0001, "frame \(frame): a bolt is at \(bolt.intensity)")
                XCTAssertFalse(bolt.vertices.isEmpty, "frame \(frame): a bolt has no path")
            }
        }
        XCTAssertTrue(everStruck, "no lightning in two minutes")
        XCTAssertLessThanOrEqual(
            s.bolts.count, 2, "\(s.bolts.count) bolts are still alive after two minutes")
    }

    /// With lightning off nothing strikes, and no shock rings appear, since a
    /// shock only ever arrives as a bolt's aftermath.
    func testLightningCanBeTurnedOff() {
        let s = scene(VortexSettings(flowSpeed: 1, lightning: false, density: 0.05))
        for frame in 0..<(180 * 60) {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            XCTAssertTrue(s.bolts.isEmpty, "frame \(frame): lightning struck with it turned off")
            XCTAssertTrue(
                s.shockUniforms.allSatisfy { $0.w == 0 },
                "frame \(frame): a shock ring appeared with lightning off")
        }
    }

    /// A shock ring starts with no radius and no light, peaks at 8% of its life,
    /// then only ever grows and fades until it fills the screen and is gone.
    func testShocksExpandAndFade() {
        var shock = Shock(origin: SIMD2(100, 200), lifetimeMs: 1000)
        let maxRadius = 800.0

        let start = shock.packed(maxRadius: maxRadius)
        XCTAssertEqual(start.z, 0, accuracy: 1e-5, "a new shock has no radius")
        XCTAssertEqual(start.w, 0, accuracy: 1e-5, "and has not brightened yet")

        shock.advance(byMs: 80)  // the 8% mark, where intensity peaks
        let peak = shock.packed(maxRadius: maxRadius).w
        XCTAssertEqual(peak, 1.0, accuracy: 1e-5, "at 8% of its life the shock is at \(peak)")

        var radius = shock.packed(maxRadius: maxRadius).z
        var intensity = shock.packed(maxRadius: maxRadius).w
        for step in 1...9 {
            shock.advance(byMs: 100)  // to 980ms, just short of the end
            let next = shock.packed(maxRadius: maxRadius)
            XCTAssertGreaterThan(next.z, radius, "step \(step): the ring only ever expands")
            XCTAssertLessThan(next.w, intensity, "step \(step): and only ever fades after its peak")
            radius = next.z
            intensity = next.w
        }
        XCTAssertEqual(
            radius, Float(maxRadius), accuracy: 1.0, "at 980 ms the ring is \(radius), not full screen")
        XCTAssertEqual(intensity, 0, accuracy: 0.01, "at 980 ms the ring is still \(intensity) bright")

        XCTAssertFalse(shock.isFinished, "the shock finished before its lifetime")
        shock.advance(byMs: 20)
        XCTAssertTrue(shock.isFinished, "the shock outlived its lifetime")
    }

    // MARK: - Settings

    /// A hand-edited or stale plist must not be able to produce a scene the
    /// options sheet could never have made.
    func testSettingsAreClampedOnTheWayIn() {
        let wild = VortexSettings(flowSpeed: 99, lightning: true, density: -4)

        XCTAssertEqual(
            wild.flowSpeed, VortexSettings.Limits.flowSpeed.upperBound, "flow speed 99 was not clamped")
        XCTAssertEqual(
            wild.density, VortexSettings.Limits.density.lowerBound, "density -4 was not clamped")
        XCTAssertGreaterThan(wild.particleCount, 0, "the lowest density draws no particles")
    }

    /// Density scales the particle count directly; a setting that stopped
    /// scaling it would leave every density drawing the same tunnel.
    func testDensityScalesTheField() {
        let half = VortexSettings(flowSpeed: 1, lightning: true, density: 0.5)

        XCTAssertEqual(
            half.particleCount, Tunnel.particleCount / 2,
            "half density draws \(half.particleCount) of \(Tunnel.particleCount) particles")
    }
}
