import XCTest

@testable import VortexCore

final class SceneTests: XCTestCase {

    private let layout = Layout(pointWidth: 1440, pointHeight: 900, backingScale: 2)

    private func scene(_ settings: VortexSettings = .default) -> VortexScene {
        VortexScene(layout: layout, settings: settings, seed: 7)
    }

    // MARK: - Particles

    func testFieldIsReproducibleFromItsSeed() {
        let a = ParticleSet(count: 500, seed: 42)
        let b = ParticleSet(count: 500, seed: 42)
        XCTAssertEqual(a.streaks, b.streaks)
        XCTAssertEqual(a.sprites, b.sprites)

        let different = ParticleSet(count: 500, seed: 43)
        XCTAssertNotEqual(a.streaks, different.streaks)
    }

    func testFieldSplitsIntoStreaksAndSprites() {
        let set = ParticleSet(count: 5400, seed: 1)
        XCTAssertEqual(set.streaks.count + set.sprites.count, 5400)
        // 22% of particles become sprites; a sample of 5400 should land close.
        let spriteFraction = Double(set.sprites.count) / 5400
        XCTAssertEqual(spriteFraction, 0.22, accuracy: 0.03)
        XCTAssertTrue(set.streaks.allSatisfy { $0.kind == ParticleKind.streak })
        XCTAssertTrue(
            set.sprites.allSatisfy { $0.kind == ParticleKind.glint || $0.kind == ParticleKind.haze })
    }

    func testParticlesStartInsideTheTunnel() {
        let set = ParticleSet(count: 2000, seed: 3)
        for particle in set.streaks + set.sprites {
            XCTAssertGreaterThanOrEqual(particle.z0, Float(Tunnel.zNear))
            XCTAssertLessThanOrEqual(particle.z0, Float(Tunnel.zFar))
            // Particles sit on the wall, not scattered through the volume.
            XCTAssertEqual(Double(particle.radius), Tunnel.radius, accuracy: 0.15)
            XCTAssertGreaterThan(particle.speed, 0)
        }
    }

    // MARK: - Clocks

    func testParticleClockRunsWithTheFlowSpeed() {
        let slow = scene(VortexSettings(flowSpeed: 0.5, lightning: false, density: 0.05))
        let fast = scene(VortexSettings(flowSpeed: 2.0, lightning: false, density: 0.05))
        for _ in 0..<600 {
            slow.update(deltaTime: 1.0 / 60, layout: layout)
            fast.update(deltaTime: 1.0 / 60, layout: layout)
        }
        // Real time is shared; only the particles' own clock is scaled.
        XCTAssertEqual(slow.elapsedMs, fast.elapsedMs, accuracy: 1e-9)
        XCTAssertEqual(fast.particleClockMs / slow.particleClockMs, 4.0, accuracy: 1e-6)
    }

    func testLongGapsAreNotIntegrated() {
        let s = scene()
        // The display slept for a minute. Advancing by the whole gap would jump
        // the tunnel; the clamp caps a single step at 48ms.
        s.update(deltaTime: 60, layout: layout)
        XCTAssertEqual(s.elapsedMs, 48, accuracy: 1e-9)
    }

    func testFlowNeverStops() {
        // warp is allowed to go negative, but the multiplier it feeds is floored,
        // so the tunnel can slow down without ever reversing or freezing.
        let s = scene()
        var previous = s.particleClockMs
        for _ in 0..<20_000 {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            XCTAssertGreaterThan(s.particleClockMs, previous)
            previous = s.particleClockMs
        }
        XCTAssertGreaterThan(s.warp, -0.4)
        XCTAssertLessThan(s.warp, 0.6)
    }

    // MARK: - Steering

    func testBendStaysOnScreen() {
        let s = scene()
        for _ in 0..<40_000 {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            // The sum of sines is bounded by 0.97, and the eased follower cannot
            // overshoot it, so the vanishing point stays within the frame.
            XCTAssertLessThan(abs(s.bendPixels.x), Float(layout.maxBendPixels))
            XCTAssertLessThan(abs(s.bendPixels.y), Float(layout.maxBendPixels))
        }
    }

    func testSteeringRateIsIndependentOfFrameRate() {
        // The easing used to be per-frame, which made the tunnel wander at twice
        // the speed on a 120Hz display. Same wall-clock, same pose.
        let at60 = scene()
        let at120 = scene()
        for _ in 0..<600 { at60.update(deltaTime: 1.0 / 60, layout: layout) }
        for _ in 0..<1200 { at120.update(deltaTime: 1.0 / 120, layout: layout) }

        XCTAssertEqual(at60.elapsedMs, at120.elapsedMs, accuracy: 1e-6)
        XCTAssertEqual(at60.bendPixels.x, at120.bendPixels.x, accuracy: 1.0)
        XCTAssertEqual(at60.bendPixels.y, at120.bendPixels.y, accuracy: 1.0)
        // Not exact: the easing target moves within a step, so a finer step
        // tracks it slightly differently and the spin integrates that difference.
        // Within a percent is the claim — the per-frame version was out by 2x.
        XCTAssertEqual(at60.tubeSpin / at120.tubeSpin, 1.0, accuracy: 0.01)
    }

    // MARK: - Lightning

    func testLightningStrikesAndFades() {
        let s = scene(VortexSettings(flowSpeed: 1, lightning: true, density: 0.05))
        var everStruck = false
        // Strikes are 22-38s apart, so two minutes is several.
        for _ in 0..<(120 * 60) {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            if !s.bolts.isEmpty { everStruck = true }
            for bolt in s.bolts {
                XCTAssertGreaterThanOrEqual(bolt.intensity, 0)
                XCTAssertLessThanOrEqual(bolt.intensity, 1.0001)
                XCTAssertFalse(bolt.vertices.isEmpty)
            }
        }
        XCTAssertTrue(everStruck, "no lightning in two minutes")
        // Every bolt is short-lived, so none should still be alive at the end of
        // a two-minute run unless one has failed to expire.
        XCTAssertTrue(s.bolts.count <= 2)
    }

    func testLightningCanBeTurnedOff() {
        let s = scene(VortexSettings(flowSpeed: 1, lightning: false, density: 0.05))
        for _ in 0..<(180 * 60) {
            s.update(deltaTime: 1.0 / 60, layout: layout)
            XCTAssertTrue(s.bolts.isEmpty)
            // Shocks only ever arrive as a bolt's aftermath.
            XCTAssertTrue(s.shockUniforms.allSatisfy { $0.w == 0 })
        }
    }

    func testShocksExpandAndFade() {
        var shock = Shock(origin: SIMD2(100, 200), lifetimeMs: 1000)
        let maxRadius = 800.0

        let start = shock.packed(maxRadius: maxRadius)
        XCTAssertEqual(start.z, 0, accuracy: 1e-5, "a new shock has no radius")
        XCTAssertEqual(start.w, 0, accuracy: 1e-5, "and has not brightened yet")

        shock.advance(byMs: 80)  // the 8% mark, where intensity peaks
        XCTAssertEqual(shock.packed(maxRadius: maxRadius).w, 1.0, accuracy: 1e-5)

        var radius = shock.packed(maxRadius: maxRadius).z
        var intensity = shock.packed(maxRadius: maxRadius).w
        for _ in 0..<9 {
            shock.advance(byMs: 100)  // to 980ms, just short of the end
            let next = shock.packed(maxRadius: maxRadius)
            XCTAssertGreaterThan(next.z, radius, "the ring only ever expands")
            XCTAssertLessThan(next.w, intensity, "and only ever fades after its peak")
            radius = next.z
            intensity = next.w
        }
        // By the end it has grown to fill the screen and faded to nothing.
        XCTAssertEqual(radius, Float(maxRadius), accuracy: 1.0)
        XCTAssertEqual(intensity, 0, accuracy: 0.01)

        XCTAssertFalse(shock.isFinished)
        shock.advance(byMs: 20)
        XCTAssertTrue(shock.isFinished)
    }

    // MARK: - Settings

    func testSettingsAreClampedOnTheWayIn() {
        // A hand-edited or stale plist must not be able to produce a scene the
        // options sheet could never have made.
        let wild = VortexSettings(flowSpeed: 99, lightning: true, density: -4)
        XCTAssertEqual(wild.flowSpeed, VortexSettings.Limits.flowSpeed.upperBound)
        XCTAssertEqual(wild.density, VortexSettings.Limits.density.lowerBound)
        XCTAssertGreaterThan(wild.particleCount, 0)
    }

    func testDensityScalesTheField() {
        let half = VortexSettings(flowSpeed: 1, lightning: true, density: 0.5)
        XCTAssertEqual(half.particleCount, Tunnel.particleCount / 2)
    }
}
