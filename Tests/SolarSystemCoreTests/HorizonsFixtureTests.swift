import XCTest
import simd

@testable import SolarSystemCore

/// Ground truth from JPL Horizons, fetched 2026-08-07 via the public API:
///
///   https://ssd.jpl.nasa.gov/api/horizons.api?format=text
///     &COMMAND='499' &EPHEM_TYPE='VECTORS' &CENTER='500@10'
///     &REF_PLANE='FRAME' &OUT_UNITS='AU-D' &VEC_TABLE='2'
///     &START_TIME='2026-08-07' &STOP_TIME='2026-08-08' &STEP_SIZE='1 d'
///
/// CENTER='500@10' is the Sun's body centre and REF_PLANE='FRAME' is ICRF, which
/// matches astronomy-engine's EQJ to well below our tolerance. Epoch is
/// JD 2461259.5 TDB = 2026-Aug-07 00:00 TDB.
final class HorizonsFixtureTests: XCTestCase {

    /// TT days since J2000 for JD 2461259.5.
    static let epochTT = 2_461_259.5 - 2_451_545.0

    static let fixtures: [(Planet, SIMD3<Double>)] = [
        (.mercury, SIMD3(2.733586046168486e-01, 1.633263592574216e-01, 5.891948043350413e-02)),
        (.venus, SIMD3(-4.547541389113513e-02, -6.625429592946182e-01, -2.952489008841777e-01)),
        (.earth, SIMD3(7.065849396576847e-01, -6.675153606373795e-01, -2.893632966356902e-01)),
        (.mars, SIMD3(8.189535970266916e-01, 1.136779107128789e+00, 4.993263810431536e-01)),
        (.jupiter, SIMD3(-3.162566119148378e+00, 3.867762186888531e+00, 1.734811055180067e+00)),
        (.saturn, SIMD3(9.328749084785100e+00, 1.502141206133714e+00, 2.187066667554721e-01)),
        (.uranus, SIMD3(9.124256935024416e+00, 1.578247591902906e+01, 6.783129690515014e+00)),
        (.neptune, SIMD3(2.984649099414190e+01, 1.390661088287304e+00, -1.738214310021826e-01)),
    ]

    /// Tolerance is expressed as an angle as seen from the Sun, because that is what
    /// astronomy-engine documents (~1 arcminute worst case) and what actually matters
    /// for a rendered position. 1 arcminute = 2.909e-4 rad.
    func testHeliocentricPositionsMatchHorizons() throws {
        let toleranceArcmin = 1.0
        for (planet, expected) in Self.fixtures {
            let actual = try Ephemeris.helioPosition(planet, terrestrialTimeDays: Self.epochTT)

            let angle = simd_length(simd_cross(simd_normalize(actual), simd_normalize(expected)))
            let arcmin = asin(min(1, angle)) * 180 / .pi * 60
            let radialErr = abs(simd_length(actual) - simd_length(expected))

            XCTAssertLessThan(
                arcmin, toleranceArcmin,
                "\(planet.name): angular error \(arcmin) arcmin exceeds \(toleranceArcmin)"
            )
            // Radial error should stay well under 1e-4 of the orbit radius.
            XCTAssertLessThan(
                radialErr / simd_length(expected), 1e-4,
                "\(planet.name): fractional radial error \(radialErr / simd_length(expected))"
            )
        }
    }

    /// Prints the measured deviation for every planet so the real accuracy is on record
    /// rather than merely bounded by the assertion above.
    func testReportAccuracy() throws {
        var worst = 0.0
        for (planet, expected) in Self.fixtures {
            let actual = try Ephemeris.helioPosition(planet, terrestrialTimeDays: Self.epochTT)
            let sep = simd_length(simd_cross(simd_normalize(actual), simd_normalize(expected)))
            let arcsec = asin(min(1, sep)) * 180 / .pi * 3600
            let deltaAU = simd_length(actual - expected)
            worst = max(worst, arcsec)
            print(
                String(
                    format: "  %-8s %8.2f arcsec   %.3e AU", (planet.name as NSString).utf8String!, arcsec,
                    deltaAU))
        }
        print(String(format: "  worst: %.2f arcsec", worst))
    }
}
