import XCTest

@testable import GargantuaCore

/// The closed-form Kerr quantities, against values that are known rather than
/// merely reproduced — these are what the whole scene's geometry is built on, so
/// a transcription slip here would move the disk, the shadow and the hot spots
/// together and look plausible while doing it.
final class KerrTests: XCTestCase {

    func testHorizonMatchesSchwarzschildAndExtremal() {
        // r+ = M + sqrt(M^2 - a^2): 2M for a still hole, M at extremal spin.
        XCTAssertEqual(KerrGeometry.horizon(spin: 0), 2.0, accuracy: 1e-12)
        XCTAssertEqual(KerrGeometry.horizon(spin: 1), 1.0, accuracy: 1e-12)
        XCTAssertEqual(KerrGeometry.horizon(spin: 0.6), 1.8, accuracy: 1e-12)
        // Retrograde spin has the same horizon: it depends on a^2.
        XCTAssertEqual(
            KerrGeometry.horizon(spin: -0.6), KerrGeometry.horizon(spin: 0.6), accuracy: 1e-12)
    }

    func testISCOMatchesTheKnownValues() {
        // Bardeen-Press-Teukolsky: 6M at zero spin, 1M prograde extremal,
        // 9M retrograde extremal.
        XCTAssertEqual(KerrGeometry.isco(spin: 0), 6.0, accuracy: 1e-9)
        XCTAssertEqual(KerrGeometry.isco(spin: 1), 1.0, accuracy: 1e-6)
        // Interstellar's spin. The published value for a = 0.6 is 3.829M.
        XCTAssertEqual(KerrGeometry.isco(spin: 0.6), 3.829, accuracy: 0.001)
    }

    func testISCOFallsAsSpinRises() {
        var previous = KerrGeometry.isco(spin: 0)
        for spin in stride(from: 0.05, through: 0.95, by: 0.05) {
            let r = KerrGeometry.isco(spin: spin)
            XCTAssertLessThan(r, previous, "ISCO should shrink with prograde spin")
            XCTAssertGreaterThan(r, KerrGeometry.horizon(spin: spin))
            previous = r
        }
    }

    func testPhotonRadiusIsThreeAtZeroSpin() {
        // Prograde and retrograde photon orbits coincide at 3M when the hole is
        // still, so their midpoint is 3M too.
        XCTAssertEqual(KerrGeometry.photonRadius(spin: 0), 3.0, accuracy: 1e-9)
        // Spin splits them, but the midpoint stays outside the horizon.
        for spin in [0.3, 0.6, 0.9] {
            XCTAssertGreaterThan(
                KerrGeometry.photonRadius(spin: spin), KerrGeometry.horizon(spin: spin))
        }
    }

    func testOrbitalRateCollapsesToKeplerWithoutSpin() {
        // Omega = 1/(r^3/2 + a) is r^-3/2 at a = 0.
        for r in [3.0, 6.0, 20.0] {
            XCTAssertEqual(
                KerrGeometry.omega(radius: r, spin: 0), pow(r, -1.5), accuracy: 1e-12)
        }
        // Prograde spin speeds an orbit up relative to retrograde at the same
        // radius, which is what frame dragging means here.
        XCTAssertGreaterThan(
            KerrGeometry.omega(radius: 6, spin: -0.6),
            KerrGeometry.omega(radius: 6, spin: 0.6))
    }

    func testTemperatureNormalisationPutsThePeakAtOne() {
        // tempNorm is 1/peakFlux^(1/4), so the profile it normalises should
        // reach exactly 1 at its maximum and stay below elsewhere.
        for exponent in [0.5, 1.0, 1.5] {
            let norm = KerrGeometry.temperatureNormalisation(innerEdge: exponent)
            var peak = 0.0
            // The shader's `radial`, as a function of x = diskIn/r.
            for step in 1...4000 {
                let x = Double(step) / 4000
                let value = x * x * x * pow(max(0, 1 - x.squareRoot()), exponent)
                peak = max(peak, pow(value, 0.25) * norm)
            }
            XCTAssertEqual(peak, 1.0, accuracy: 1e-3, "exponent \(exponent)")
        }
    }
}
