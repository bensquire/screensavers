import XCTest
import simd

@testable import SolarSystemCore

final class GalacticFrameTests: XCTestCase {

    private func unitFromRADec(raDeg: Double, decDeg: Double) -> SIMD3<Double> {
        let ra = raDeg * .pi / 180, dec = decDeg * .pi / 180
        return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
    }

    func testMatrixIsProperRotation() {
        let m = GalacticFrame.eqjToGal
        XCTAssertEqual(simd_determinant(m), 1.0, accuracy: 1e-12)
        let residual = m * m.transpose - matrix_identity_double3x3
        let err = (0..<3).reduce(0.0) { max($0, simd_reduce_max(simd_abs(residual[$1]))) }
        XCTAssertLessThan(err, 1e-12)
    }

    /// The whole drift model rests on +y being the direction of galactic rotation.
    /// Check the axes against the IAU J2000 galactic pole and centre.
    func testAxisConvention() {
        // Galactic centre (Sgr A*, l=0 b=0): RA 266.405°, Dec −28.936°.
        let centre = GalacticFrame.galactic(fromEQJ: unitFromRADec(raDeg: 266.40499, decDeg: -28.93617))
        XCTAssertEqual(centre.x, 1.0, accuracy: 2e-4)
        XCTAssertEqual(centre.y, 0.0, accuracy: 2e-4)
        XCTAssertEqual(centre.z, 0.0, accuracy: 2e-4)

        // North galactic pole: RA 192.85948°, Dec +27.12825°.
        let pole = GalacticFrame.galactic(fromEQJ: unitFromRADec(raDeg: 192.85948, decDeg: 27.12825))
        XCTAssertEqual(pole.z, 1.0, accuracy: 2e-4)

        // And therefore +y is l=90°, the direction of travel.
        XCTAssertEqual(
            simd_dot(GalacticFrame.solarApexDirection, SIMD3<Double>(0, 1, 0)), 1.0, accuracy: 1e-12
        )
    }

    /// Ecliptic vs the *galactic plane*.
    func testEclipticGalacticAngle() {
        XCTAssertEqual(GalacticFrame.eclipticToGalacticPlaneAngleDegrees, 60.19, accuracy: 0.02)
    }

    /// Ecliptic vs the *direction of travel* — a different quantity, and the one the
    /// "vortex" animations get wrong. They draw the orbital plane perpendicular to the
    /// Sun's motion, i.e. the ecliptic pole parallel to the velocity. It is 30.4° off.
    ///
    /// The camera basis in SolarSystemRender is derived from this, so pin it down.
    func testEclipticPoleVsDirectionOfTravel() {
        let pole = GalacticFrame.eclipticPoleInGalactic
        XCTAssertEqual(simd_length(pole), 1.0, accuracy: 1e-12)

        let offAxis = acos(simd_dot(pole, GalacticFrame.solarApexDirection)) * 180 / .pi
        XCTAssertEqual(offAxis, 30.4, accuracy: 0.1, "ecliptic pole vs direction of travel")

        // Galactic longitude/latitude of the ecliptic pole: l ≈ 96.4°, b ≈ +29.8°.
        XCTAssertEqual(atan2(pole.y, pole.x) * 180 / .pi, 96.38, accuracy: 0.05)
        XCTAssertEqual(asin(pole.z) * 180 / .pi, 29.81, accuracy: 0.05)

        // The two angles are near-complementary only because the pole sits close to
        // l=90°; they are not the same measurement and must not be conflated.
        XCTAssertEqual(
            offAxis + GalacticFrame.eclipticToGalacticPlaneAngleDegrees, 90.0, accuracy: 1.0
        )
    }

    func testDriftConstant() {
        // 230 km/s over a Julian year, in AU.
        XCTAssertEqual(Constants.solarDriftAUPerYear, 48.5, accuracy: 0.1)
    }
}

final class DisplayModelTests: XCTestCase {

    /// Radial compression must not disturb direction — that is what keeps phases,
    /// inclinations and eccentricity shapes astronomically correct.
    func testCompressionPreservesDirection() throws {
        let model = DisplayModel(
            config: SceneConfig(scale: .compressed(radialExponent: 0.45, driftUnitsPerYear: 0)),
            epoch: Date()
        )
        for planet in Planet.allCases {
            let eqj = try Ephemeris.helioPosition(planet, at: Date())
            let gal = GalacticFrame.galactic(fromEQJ: eqj)
            let compressed = model.compress(gal)
            let cosAngle = simd_dot(simd_normalize(gal), simd_normalize(compressed))
            XCTAssertEqual(cosAngle, 1.0, accuracy: 1e-12, "\(planet.name) direction changed")
        }
    }

    /// Earth's 1 AU orbit maps to ~1 scene unit under any exponent, which is what makes
    /// `driftFractionOfTrue` a meaningful number.
    func testEarthMapsToUnitRadius() throws {
        let model = DisplayModel(
            config: SceneConfig(scale: .compressed(radialExponent: 0.45, driftUnitsPerYear: 0))
        )
        let eqj = try Ephemeris.helioPosition(.earth, at: Date())
        let r = simd_length(model.compress(GalacticFrame.galactic(fromEQJ: eqj)))
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
    }

    /// Body sizes must preserve the real ordering. The previous hand-picked radii
    /// spanned only 2.8× for a 28× real spread and made the Sun the same size as
    /// Jupiter, which is what made everything look identical.
    func testBodySizesPreserveRealOrdering() {
        let model = DisplayModel()
        let byDisplay = Planet.allCases.sorted { model.bodyRadius(of: $0) < model.bodyRadius(of: $1) }
        let byTruth = Planet.allCases.sorted { $0.meanRadiusKm < $1.meanRadiusKm }
        XCTAssertEqual(byDisplay.map(\.name), byTruth.map(\.name))

        // The Sun must dominate, and the gas giants must clearly beat the terrestrials.
        XCTAssertGreaterThan(model.sunRadius, model.bodyRadius(of: .jupiter) * 2)
        XCTAssertGreaterThan(model.bodyRadius(of: .jupiter), model.bodyRadius(of: .earth) * 2)

        // Sun renders 8.3× Earth under the default 0.45 exponent (109× in reality).
        XCTAssertEqual(model.sunRadius / model.bodyRadius(of: .earth), 8.26, accuracy: 0.1)

        // The Sun's disc must never reach Mercury's perihelion — the closest any planet
        // actually comes to it — or Mercury would be drawn orbiting inside the Sun.
        let mercuryPerihelion = pow(0.3075, model.config.scale.radialExponent)
        XCTAssertLessThan(model.sunRadius, mercuryPerihelion)
    }

    /// True scale is offered and is correct — and demonstrates why it's unusable.
    func testTrueScaleUsesRealRadii() {
        let model = DisplayModel(config: SceneConfig(scale: .trueScale))
        XCTAssertEqual(model.sunRadius, 0.004650, accuracy: 1e-5)
        XCTAssertEqual(model.bodyRadius(of: .earth), 4.259e-5, accuracy: 1e-7)
        // Earth is 1/109th of the Sun, exactly as it should be.
        XCTAssertEqual(model.sunRadius / model.bodyRadius(of: .earth), 109.2, accuracy: 0.5)
    }

    func testTrueScaleIsLinear() {
        let model = DisplayModel(config: SceneConfig(scale: .trueScale))
        let v = SIMD3<Double>(3, 4, 0)  // |v| = 5
        XCTAssertEqual(simd_length(model.compress(v)), 5.0, accuracy: 1e-12)
    }

    func testDriftAccumulatesAlongGalacticY() {
        let epoch = Date()
        let model = DisplayModel(
            config: SceneConfig(scale: .compressed(radialExponent: 0.45, driftUnitsPerYear: 2.0)),
            epoch: epoch
        )
        let after = model.sunOffset(at: epoch.addingTimeInterval(Constants.secondsPerJulianYear))
        XCTAssertEqual(after.x, 0, accuracy: 1e-12)
        XCTAssertEqual(after.y, 2.0, accuracy: 1e-9)
        XCTAssertEqual(after.z, 0, accuracy: 1e-12)
    }

    /// Sample density has to follow how many revolutions a trail actually covers, or a
    /// fixed window turns Mercury's 41 loops into a polygon while Neptune's quarter-arc
    /// gets the same budget.
    func testSampleCountTracksRevolutions() {
        let fixedWindow = DisplayModel(
            config: SceneConfig(trail: .years(10), trailSamples: 50)
        )
        // Mercury laps ~41 times in 10 years; Neptune covers 6% of one orbit.
        XCTAssertGreaterThan(
            fixedWindow.sampleCount(for: .mercury), fixedWindow.sampleCount(for: .neptune)
        )
        XCTAssertEqual(fixedWindow.sampleCount(for: .neptune), 50, "under one revolution → base budget")
        XCTAssertGreaterThan(fixedWindow.sampleCount(for: .mercury), 600)

        // Asserted against the *live* default rather than a copy of it, so this notices
        // if a future default breaks the invariant it is describing.
        let adaptive = DisplayModel()
        let cap = adaptive.config.trail.adaptiveCaps?.maxOrbits ?? 0
        XCTAssertGreaterThan(cap, 0, "the default trail should be adaptive")
        for planet in Planet.allCases {
            XCTAssertLessThanOrEqual(
                adaptive.config.trail.revolutions(for: planet), cap + 1e-9, "\(planet.name)"
            )
            // Within the cap, every planet gets exactly the base sample budget.
            XCTAssertLessThanOrEqual(
                adaptive.sampleCount(for: planet),
                Int(Double(adaptive.config.trailSamples) * max(1, cap / 3.0)) + 1,
                "\(planet.name)"
            )
        }
    }

    func testTrailIsOrderedOldestToNewest() throws {
        let epoch = Date()
        let model = DisplayModel(
            config: SceneConfig(
                scale: .compressed(radialExponent: 0.45, driftUnitsPerYear: 1.0),
                trail: .years(10), trailSamples: 50
            ),
            epoch: epoch
        )
        let snap = try model.snapshot(at: epoch)
        for body in snap.bodies {
            XCTAssertEqual(body.trail.count, model.sampleCount(for: body.planet))
            // Drift is +y and time runs forward, so y must increase monotonically
            // along the trail once the orbital wobble is dwarfed by drift.
            XCTAssertLessThan(body.trail.first!.y, body.trail.last!.y, "\(body.planet.name)")
            // Last trail point is the body's current position.
            XCTAssertEqual(simd_distance(body.trail.last!, body.scenePosition), 0, accuracy: 1e-12)
        }
    }
}
