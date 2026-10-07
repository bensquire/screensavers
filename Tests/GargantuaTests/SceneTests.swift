import XCTest

@testable import GargantuaCore

final class SceneTests: XCTestCase {

    private func scene(_ settings: GargantuaSettings = .default) -> GargantuaScene {
        GargantuaScene(settings: settings, seed: 4)
    }

    // MARK: - Camera

    /// A ray grazing the slab has a path length through it of about 2h/sin(i),
    /// which diverges as i goes to zero and blows the near side out. The drift
    /// must respect that floor at every moment, not on average.
    func testCameraNeverEntersTheDiskPlane() {
        let s = scene()
        let p = s.parameters
        // The floor scales with the slab: 0.8 deg per 1.15 units of outer
        // half-thickness, clamped to a sane band.
        let floor = min(max((0.8 / 1.15) * p.diskHalfOuter, 0.15), 3.0)

        var camera = OrbitCamera()
        var lowest = Double.greatestFiniteMagnitude
        for step in 0..<20_000 {
            let t = Double(step) * 0.05  // 1000 seconds, past every drift period
            camera.update(time: t, parameters: p)
            let position = camera.current.position
            let horizontal = (position.x * position.x + position.z * position.z).squareRoot()
            let inclination = abs(atan2(position.y, horizontal)) * 180 / .pi
            lowest = min(lowest, inclination)
        }
        XCTAssertGreaterThanOrEqual(
            lowest, floor - 1e-6,
            "the camera swung to \(lowest) degrees, inside the \(floor) degree floor")
    }

    /// Too close and the camera is inside the disk's glare; too far and the hole
    /// becomes a speck. The drift must stay between them for its whole cycle.
    func testCameraStaysAtAWorkingDistance() {
        let s = scene()
        let p = s.parameters
        var camera = OrbitCamera()
        var nearest = Double.greatestFiniteMagnitude
        var furthest = 0.0
        for step in 0..<20_000 {
            camera.update(time: Double(step) * 0.05, parameters: p)
            let r = camera.current.position
            let distance = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            nearest = min(nearest, distance)
            furthest = max(furthest, distance)
        }
        // Well outside the disk, which ends at 25M, and never so far that it
        // becomes a speck.
        XCTAssertGreaterThan(
            nearest, p.diskOuterRadius * 1.5, "the camera came within \(nearest) of the disk")
        XCTAssertLessThan(
            furthest, p.dist * 1.3, "the camera drifted out to \(furthest), past 1.3x its distance")
    }

    /// The accumulation pass projects onto this basis to reproject the previous
    /// frame; if it stopped being orthonormal the history would land in the
    /// wrong place and the image would smear.
    func testCameraBasisStaysOrthonormal() {
        let s = scene()
        var camera = OrbitCamera()
        for step in 0..<2000 {
            let t = Double(step) * 0.31
            camera.update(time: t, parameters: s.parameters)
            let c = camera.current
            XCTAssertEqual(dot(c.right, c.right), 1.0, accuracy: 1e-9, "t = \(t) s")
            XCTAssertEqual(dot(c.up, c.up), 1.0, accuracy: 1e-9, "t = \(t) s")
            XCTAssertEqual(dot(c.forward, c.forward), 1.0, accuracy: 1e-9, "t = \(t) s")
            XCTAssertEqual(dot(c.right, c.up), 0.0, accuracy: 1e-9, "t = \(t) s")
            XCTAssertEqual(dot(c.right, c.forward), 0.0, accuracy: 1e-9, "t = \(t) s")
            XCTAssertEqual(dot(c.up, c.forward), 0.0, accuracy: 1e-9, "t = \(t) s")
        }
    }

    /// The accumulation pass reprojects history with the previous pose. If
    /// `previous` were not the pose from before the last update, the history
    /// would be reprojected from the wrong place.
    func testCameraKeepsThePreviousPose() {
        let s = scene()
        var camera = OrbitCamera()
        camera.update(time: 10, parameters: s.parameters)
        let first = camera.current

        camera.update(time: 10.5, parameters: s.parameters)

        XCTAssertEqual(
            camera.previous.position, first.position, "previous is not the pose before the update")
        XCTAssertNotEqual(
            camera.current.position, first.position, "the camera did not move in half a second")
    }

    /// aimDrift is deliberately zero: unattended on a wall, a composition that
    /// slowly slides off centre reads as an error rather than as life.
    func testTheHoleStaysCentredForTheScreensaver() {
        let s = scene()
        XCTAssertEqual(s.parameters.aimDrift, 0, "the shipped look drifts its aim")
        var camera = OrbitCamera()
        for step in 0..<2000 {
            let t = Double(step) * 0.37
            camera.update(time: t, parameters: s.parameters)
            let c = camera.current
            // Forward points from the camera straight at the origin.
            let toOrigin = normalize(SIMD3<Double>(0, 0, 0) - c.position)
            XCTAssertEqual(
                dot(c.forward, toOrigin), 1.0, accuracy: 1e-9, "t = \(t) s: the hole is off centre")
        }
    }

    // MARK: - Winding

    /// The differential winding runs as a sawtooth so the shear cannot grow
    /// without bound. The reset must always happen under the cross-fade: at the
    /// moment either phase wraps, its blend weight has to have handed over
    /// completely to the other, or the reset shows as a jump.
    func testWindingResetsWithoutEverBeingSeen() {
        let p = SceneParameters()
        let period = p.windPeriod
        let churnRate = p.spinSign * p.turbSpeed * p.pace

        for step in 0...4000 {
            let churn = Double(step) / 4000 * 3 * period
            let t = churn / churnRate
            let wind = WindPhase(time: t, parameters: p)
            let x = (churn / period) - (churn / period).rounded(.down)
            let blend = Double(wind.differential.z)

            // Phase A wraps at x = 0 and 1; phase B at x = 0.5.
            if x < 0.02 || x > 0.98 {
                XCTAssertEqual(
                    blend, 1.0, accuracy: 1e-6, "x = \(x): phase A reset while it was visible")
            }
            if abs(x - 0.5) < 0.02 {
                XCTAssertEqual(
                    blend, 0.0, accuracy: 1e-6, "x = \(x): phase B reset while it was visible")
            }
            XCTAssertGreaterThanOrEqual(blend, 0, "x = \(x): blend \(blend) is below 0")
            XCTAssertLessThanOrEqual(blend, 1, "x = \(x): blend \(blend) is above 1")
        }
    }

    /// The rigid carrier is folded to one turn and the sawtooth to one period,
    /// so neither grows large enough that a frame's rotation falls below
    /// float32's resolution in the shader — checked over half a day.
    func testWindingStaysResolvableForever() {
        let p = SceneParameters()
        for hours in stride(from: 0.0, through: 12.0, by: 0.25) {
            let wind = WindPhase(time: hours * 3600, parameters: p)
            XCTAssertTrue(wind.rigid.isFinite, "after \(hours) h the carrier angle is \(wind.rigid)")
            XCTAssertLessThanOrEqual(
                abs(wind.rigid), 2 * .pi, "after \(hours) h the carrier angle is \(wind.rigid)")
            XCTAssertLessThan(
                abs(wind.differential.x), Float(p.windPeriod),
                "after \(hours) h phase A has grown to \(wind.differential.x)")
            XCTAssertLessThan(
                abs(wind.differential.y), Float(p.windPeriod),
                "after \(hours) h phase B has grown to \(wind.differential.y)")
        }
    }

    // MARK: - Hot spots

    /// Hot spots must turn up, sit inside the disk just outside the ISCO, hand
    /// their angle to the shader as a unit vector rather than a number that
    /// grows without bound, and never exceed the uniform array's capacity.
    func testHotSpotsAppearOrbitAndExpire() {
        let s = scene()
        var everLive = false
        var maxLive = 0
        var t = 0.0
        while t < 400 {
            t += 1.0 / 60
            s.update(deltaTime: 1.0 / 60)
            let live = s.events.spots.filter { $0.w > 0 }
            maxLive = max(maxLive, live.count)
            if !live.isEmpty { everLive = true }
            for spot in live {
                XCTAssertGreaterThanOrEqual(
                    Double(spot.x), s.parameters.diskInnerRadius,
                    "t = \(t) s: a spot at r = \(spot.x) is inside the disk's inner edge")
                XCTAssertLessThan(
                    Double(spot.x), s.parameters.diskOuterRadius,
                    "t = \(t) s: a spot at r = \(spot.x) is outside the disk")
                let unit = Double(spot.y * spot.y + spot.z * spot.z)
                XCTAssertEqual(
                    unit, 1.0, accuracy: 1e-5, "t = \(t) s: a spot's angle is not a unit vector")
                XCTAssertLessThanOrEqual(
                    Double(spot.w), 0.41, "t = \(t) s: a spot is \(spot.w) strong")
            }
        }
        XCTAssertTrue(everLive, "no hot spots in almost seven minutes")
        XCTAssertLessThanOrEqual(
            maxLive, DiskEvents.maxSpots, "\(maxLive) spots were live at once")
    }

    /// A flare stacks on top of the hot spots, so it has to stay well short of
    /// becoming the subject — and has to happen at all.
    func testFlaresStayModest() {
        let s = scene()
        var peak = 1.0
        for frame in 0..<(600 * 60) {
            s.update(deltaTime: 1.0 / 60)
            XCTAssertGreaterThanOrEqual(
                s.events.flare, 1.0, "frame \(frame): a flare dimmed the disk to \(s.events.flare)")
            peak = max(peak, s.events.flare)
        }
        XCTAssertLessThanOrEqual(peak, 1.66, "a flare brightened the disk \(peak)x")
        XCTAssertGreaterThan(peak, 1.0, "no flare in ten minutes")
    }

    // MARK: - Clocks and settings

    /// After the display sleeps, the next frame's delta is the whole gap.
    /// Integrating it would jump the disk and the camera.
    func testLongGapsAreNotIntegrated() {
        let s = scene()

        s.update(deltaTime: 60)

        XCTAssertEqual(
            s.time, 0.1, accuracy: 1e-9, "a 60 s gap advanced the scene by \(s.time) s, not 0.1 s")
    }

    /// A frame-count window would stretch the effective exposure as the frame
    /// rate drops — exactly when the disk has had time to shear underneath it,
    /// which turns accumulation into smearing.
    func testAccumulationWindowIsFixedInSeconds() {
        let s = scene()
        let at60 = Double(s.accumulationAlpha(deltaTime: 1.0 / 60))
        let at30 = Double(s.accumulationAlpha(deltaTime: 1.0 / 30))
        XCTAssertGreaterThan(at30, at60, "a longer frame must blend in more of it")

        // Two 60Hz frames should converge as far as one 30Hz frame.
        let twoFast = 1 - (1 - at60) * (1 - at60)
        XCTAssertEqual(
            twoFast, at30, accuracy: 1e-9,
            "two 60 Hz frames blend \(twoFast), one 30 Hz frame \(at30)")
    }

    /// A hand-edited plist can hold anything; the settings type clamps it into
    /// what the options sheet could have produced.
    func testSettingsAreClampedIntoTheirLimits() {
        let wild = GargantuaSettings(
            pace: 99, beaming: -3, stars: 44, adaptiveResolution: true, renderScale: 9)

        XCTAssertEqual(wild.pace, GargantuaSettings.Limits.pace.upperBound, "pace 99 was not clamped")
        XCTAssertEqual(wild.beaming, 0, "beaming -3 was not clamped")
        XCTAssertEqual(wild.stars, GargantuaSettings.Limits.stars.upperBound, "stars 44 was not clamped")
        XCTAssertEqual(
            wild.renderScale, GargantuaSettings.Limits.renderScale.upperBound,
            "render scale 9 was not clamped")
    }

    /// The options reach the scene through its parameters; a setting that never
    /// arrived, or one that disturbed the rest of the shipped look, would only
    /// show on screen.
    func testSettingsReachTheSceneParameters() {
        let settings = GargantuaSettings(
            pace: 2, beaming: 1, stars: 0.5, adaptiveResolution: false, renderScale: 0.5)

        let s = scene(settings)

        XCTAssertEqual(s.parameters.pace, 2, "pace did not reach the scene")
        XCTAssertEqual(s.parameters.beaming, 1, "beaming did not reach the scene")
        XCTAssertEqual(s.parameters.stars, 0.5, "stars did not reach the scene")
        XCTAssertEqual(s.parameters.spin, 0.6, "a setting changed the shipped spin")
        XCTAssertEqual(s.parameters.redshift, 1, "a setting changed the shipped redshift")
    }

    /// The disk-start parameter is a floor; the ISCO wins whenever it is larger,
    /// which at spin 0.6 it is. Gas drawn inside the ISCO would be on orbits that
    /// cannot exist.
    func testTheDiskStartsAtTheISCO() {
        let p = SceneParameters()
        XCTAssertEqual(
            p.diskInnerRadius, KerrGeometry.isco(spin: 0.6), accuracy: 1e-9,
            "the disk starts at \(p.diskInnerRadius), not the ISCO")
        XCTAssertGreaterThan(p.diskInnerRadius, p.diskIn, "the ISCO did not win over the floor")
        XCTAssertGreaterThan(
            p.diskOuterRadius, p.diskInnerRadius, "the disk ends before it starts")
    }

    /// The shader uses h(r) = hA*r + hB instead of the pow, so the two have to
    /// agree where it matters, or the slab's edges are drawn at the wrong
    /// thickness.
    func testLinearisedThicknessMatchesTheProfileAtBothEnds() {
        let p = SceneParameters()
        let c = p.diskHalfCoefficients
        XCTAssertEqual(
            c.a * p.diskInnerRadius + c.b, p.diskH, accuracy: 1e-12,
            "the linear thickness is wrong at the inner edge")
        XCTAssertEqual(
            c.a * p.diskOuterRadius + c.b, p.diskHalfOuter, accuracy: 1e-12,
            "the linear thickness is wrong at the outer edge")
        XCTAssertGreaterThan(c.min, 0, "the thickness reaches \(c.min)")
    }
}
