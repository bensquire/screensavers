import XCTest

@testable import GargantuaCore

final class SceneTests: XCTestCase {

    private func scene(_ settings: GargantuaSettings = .default) -> GargantuaScene {
        GargantuaScene(settings: settings, seed: 4)
    }

    // MARK: - Camera

    func testCameraNeverEntersTheDiskPlane() {
        // A ray grazing the slab has a path length through it of about
        // 2h/sin(i), which diverges as i goes to zero and blows the near side
        // out. The drift must respect that floor at every moment, not on
        // average.
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
        XCTAssertGreaterThanOrEqual(lowest, floor - 1e-6, "the camera swung into the disk plane")
    }

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
        XCTAssertGreaterThan(nearest, p.diskOuterRadius * 1.5)
        XCTAssertLessThan(furthest, p.dist * 1.3)
    }

    func testCameraBasisStaysOrthonormal() {
        // The accumulation pass projects onto this basis to reproject the
        // previous frame; if it stopped being orthonormal the history would land
        // in the wrong place and the image would smear.
        let s = scene()
        var camera = OrbitCamera()
        for step in 0..<2000 {
            camera.update(time: Double(step) * 0.31, parameters: s.parameters)
            let c = camera.current
            XCTAssertEqual(dot(c.right, c.right), 1.0, accuracy: 1e-9)
            XCTAssertEqual(dot(c.up, c.up), 1.0, accuracy: 1e-9)
            XCTAssertEqual(dot(c.forward, c.forward), 1.0, accuracy: 1e-9)
            XCTAssertEqual(dot(c.right, c.up), 0.0, accuracy: 1e-9)
            XCTAssertEqual(dot(c.right, c.forward), 0.0, accuracy: 1e-9)
            XCTAssertEqual(dot(c.up, c.forward), 0.0, accuracy: 1e-9)
        }
    }

    func testCameraKeepsThePreviousPose() {
        let s = scene()
        var camera = OrbitCamera()
        camera.update(time: 10, parameters: s.parameters)
        let first = camera.current
        camera.update(time: 10.5, parameters: s.parameters)
        XCTAssertEqual(camera.previous.position, first.position)
        XCTAssertNotEqual(camera.current.position, first.position)
    }

    func testTheHoleStaysCentredForTheScreensaver() {
        // aimDrift is deliberately zero: unattended on a wall, a composition
        // that slowly slides off centre reads as an error rather than as life.
        let s = scene()
        XCTAssertEqual(s.parameters.aimDrift, 0)
        var camera = OrbitCamera()
        for step in 0..<2000 {
            camera.update(time: Double(step) * 0.37, parameters: s.parameters)
            let c = camera.current
            // Forward points from the camera straight at the origin.
            let toOrigin = normalize(SIMD3<Double>(0, 0, 0) - c.position)
            XCTAssertEqual(dot(c.forward, toOrigin), 1.0, accuracy: 1e-9)
        }
    }

    // MARK: - Winding

    func testWindingResetsWithoutEverBeingSeen() {
        // The differential winding runs as a sawtooth so the shear cannot grow
        // without bound. The reset must always happen under the cross-fade: at
        // the moment either phase wraps, its blend weight has to have handed
        // over completely to the other.
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
                XCTAssertEqual(blend, 1.0, accuracy: 1e-6, "phase A reset while it was visible")
            }
            if abs(x - 0.5) < 0.02 {
                XCTAssertEqual(blend, 0.0, accuracy: 1e-6, "phase B reset while it was visible")
            }
            XCTAssertGreaterThanOrEqual(blend, 0)
            XCTAssertLessThanOrEqual(blend, 1)
        }
    }

    func testWindingStaysResolvableForeverAndTurnsTheRightWay() {
        let p = SceneParameters()
        // Half a day. The rigid carrier is folded to one turn, so it never grows
        // large enough that a frame's rotation falls below float32's resolution.
        for hours in stride(from: 0.0, through: 12.0, by: 0.25) {
            let wind = WindPhase(time: hours * 3600, parameters: p)
            XCTAssertLessThanOrEqual(abs(wind.rigid), 2 * .pi)
            XCTAssertTrue(wind.rigid.isFinite)
            XCTAssertLessThan(abs(wind.differential.x), Float(p.windPeriod))
            XCTAssertLessThan(abs(wind.differential.y), Float(p.windPeriod))
        }
    }

    // MARK: - Hot spots

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
                // Placed just outside the ISCO, and inside the disk.
                XCTAssertGreaterThanOrEqual(Double(spot.x), s.parameters.diskInnerRadius)
                XCTAssertLessThan(Double(spot.x), s.parameters.diskOuterRadius)
                // The angle is handed over as a unit vector, never as a number
                // that grows without bound.
                let unit = Double(spot.y * spot.y + spot.z * spot.z)
                XCTAssertEqual(unit, 1.0, accuracy: 1e-5)
                XCTAssertLessThanOrEqual(Double(spot.w), 0.41)
            }
        }
        XCTAssertTrue(everLive, "no hot spots in almost seven minutes")
        XCTAssertLessThanOrEqual(maxLive, DiskEvents.maxSpots)
    }

    func testFlaresStayModest() {
        let s = scene()
        var peak = 1.0
        for _ in 0..<(600 * 60) {
            s.update(deltaTime: 1.0 / 60)
            XCTAssertGreaterThanOrEqual(s.events.flare, 1.0)
            peak = max(peak, s.events.flare)
        }
        // Stacks on top of the hot spots, so it has to stay well short of
        // becoming the subject.
        XCTAssertLessThanOrEqual(peak, 1.66)
        XCTAssertGreaterThan(peak, 1.0, "no flare in ten minutes")
    }

    // MARK: - Clocks and settings

    func testLongGapsAreNotIntegrated() {
        let s = scene()
        s.update(deltaTime: 60)
        XCTAssertEqual(s.time, 0.1, accuracy: 1e-9)
    }

    func testAccumulationWindowIsFixedInSeconds() {
        // A frame-count window would stretch the effective exposure as the frame
        // rate drops — exactly when the disk has had time to shear underneath
        // it, which turns accumulation into smearing.
        let s = scene()
        let at60 = Double(s.accumulationAlpha(deltaTime: 1.0 / 60))
        let at30 = Double(s.accumulationAlpha(deltaTime: 1.0 / 30))
        XCTAssertGreaterThan(at30, at60, "a longer frame must blend in more of it")

        // Two 60Hz frames should converge as far as one 30Hz frame.
        let twoFast = 1 - (1 - at60) * (1 - at60)
        XCTAssertEqual(twoFast, at30, accuracy: 1e-9)
    }

    func testSettingsAreClampedAndReachTheParameters() {
        let wild = GargantuaSettings(
            pace: 99, beaming: -3, stars: 44, adaptiveResolution: true, renderScale: 9)
        XCTAssertEqual(wild.pace, GargantuaSettings.Limits.pace.upperBound)
        XCTAssertEqual(wild.beaming, 0)
        XCTAssertEqual(wild.stars, GargantuaSettings.Limits.stars.upperBound)
        XCTAssertEqual(wild.renderScale, GargantuaSettings.Limits.renderScale.upperBound)

        let s = scene(
            GargantuaSettings(
                pace: 2, beaming: 1, stars: 0.5, adaptiveResolution: false, renderScale: 0.5))
        XCTAssertEqual(s.parameters.pace, 2)
        XCTAssertEqual(s.parameters.beaming, 1)
        XCTAssertEqual(s.parameters.stars, 0.5)
        // Everything else stays at the shipped look.
        XCTAssertEqual(s.parameters.spin, 0.6)
        XCTAssertEqual(s.parameters.redshift, 1)
    }

    func testTheDiskStartsAtTheISCO() {
        // The parameter is a floor; the ISCO wins whenever it is larger, which
        // at spin 0.6 it is.
        let p = SceneParameters()
        XCTAssertEqual(p.diskInnerRadius, KerrGeometry.isco(spin: 0.6), accuracy: 1e-9)
        XCTAssertGreaterThan(p.diskInnerRadius, p.diskIn)
        XCTAssertGreaterThan(p.diskOuterRadius, p.diskInnerRadius)
    }

    func testLinearisedThicknessMatchesTheProfileAtBothEnds() {
        // The shader uses h(r) = hA*r + hB instead of the pow, so the two have
        // to agree where it matters.
        let p = SceneParameters()
        let c = p.diskHalfCoefficients
        XCTAssertEqual(c.a * p.diskInnerRadius + c.b, p.diskH, accuracy: 1e-12)
        XCTAssertEqual(c.a * p.diskOuterRadius + c.b, p.diskHalfOuter, accuracy: 1e-12)
        XCTAssertGreaterThan(c.min, 0)
    }
}
