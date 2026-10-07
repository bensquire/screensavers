import XCTest

@testable import GargantuaCore

/// The closed-form Kerr quantities, against values that are known rather than
/// merely reproduced — these are what the whole scene's geometry is built on, so
/// a transcription slip here would move the disk, the shadow and the hot spots
/// together and look plausible while doing it.
final class KerrTests: XCTestCase {

    /// r+ = M + sqrt(M^2 - a^2) is the shadow's edge. Pinned at both limits — 2M
    /// for a still hole, 1M at extremal spin — so a slip in either term shows.
    func testHorizonMatchesSchwarzschildAndExtremal() {
        XCTAssertEqual(KerrGeometry.horizon(spin: 0), 2.0, accuracy: 1e-12)
        XCTAssertEqual(KerrGeometry.horizon(spin: 1), 1.0, accuracy: 1e-12)
        XCTAssertEqual(KerrGeometry.horizon(spin: 0.6), 1.8, accuracy: 1e-12)
        // Retrograde spin has the same horizon: it depends on a^2.
        XCTAssertEqual(
            KerrGeometry.horizon(spin: -0.6), KerrGeometry.horizon(spin: 0.6), accuracy: 1e-12)
    }

    /// The ISCO is where the disk starts, so a wrong value moves its inner edge.
    /// Bardeen-Press-Teukolsky: 6M at zero spin, 1M prograde extremal; the
    /// published value at Interstellar's spin of 0.6 is 3.829M.
    func testISCOMatchesTheKnownValues() {
        XCTAssertEqual(KerrGeometry.isco(spin: 0), 6.0, accuracy: 1e-9)
        XCTAssertEqual(KerrGeometry.isco(spin: 1), 1.0, accuracy: 1e-6)
        XCTAssertEqual(KerrGeometry.isco(spin: 0.6), 3.829, accuracy: 0.001)
    }

    /// Between the pinned values, a sign slip in the spin term would push the
    /// ISCO out as spin rises, or inside the horizon.
    func testISCOFallsAsSpinRises() {
        var previous = KerrGeometry.isco(spin: 0)
        for spin in stride(from: 0.05, through: 0.95, by: 0.05) {
            let r = KerrGeometry.isco(spin: spin)
            XCTAssertLessThan(r, previous, "spin \(spin): the ISCO grew to \(r) from \(previous)")
            XCTAssertGreaterThan(
                r, KerrGeometry.horizon(spin: spin), "spin \(spin): the ISCO \(r) is inside the horizon")
            previous = r
        }
    }

    /// The photon ring is drawn at this radius. Prograde and retrograde photon
    /// orbits coincide at 3M when the hole is still, so their midpoint is 3M too;
    /// spin splits them, and the midpoint must stay outside the horizon or the
    /// ring is drawn inside the shadow.
    func testPhotonRadiusIsThreeAtZeroSpin() {
        XCTAssertEqual(KerrGeometry.photonRadius(spin: 0), 3.0, accuracy: 1e-9)
        for spin in [0.3, 0.6, 0.9] {
            let photon = KerrGeometry.photonRadius(spin: spin)
            XCTAssertGreaterThan(
                photon, KerrGeometry.horizon(spin: spin),
                "spin \(spin): the photon radius \(photon) is inside the horizon")
        }
    }

    /// The disk turns at Omega = 1/(r^3/2 + a). Without spin that must be
    /// Kepler's r^-3/2, and the spin term must enter with its sign: at the same
    /// radius a = -0.6 turns faster than a = +0.6.
    func testOrbitalRateCollapsesToKeplerWithoutSpin() {
        for r in [3.0, 6.0, 20.0] {
            XCTAssertEqual(
                KerrGeometry.omega(radius: r, spin: 0), pow(r, -1.5), accuracy: 1e-12,
                "r = \(r): the rate at zero spin is not Kepler's")
        }
        XCTAssertGreaterThan(
            KerrGeometry.omega(radius: 6, spin: -0.6),
            KerrGeometry.omega(radius: 6, spin: 0.6),
            "at r = 6 the spin term has the wrong sign")
    }

    /// tempNorm is 1/peakFlux^(1/4), so the profile it normalises should reach
    /// exactly 1 at its maximum; if it drifted, the whole disk would wash out or
    /// dim, at every inner-edge exponent.
    func testTemperatureNormalisationPutsThePeakAtOne() {
        for exponent in [0.5, 1.0, 1.5] {
            let norm = KerrGeometry.temperatureNormalisation(innerEdge: exponent)
            var peak = 0.0
            // The shader's `radial`, as a function of x = diskIn/r.
            for step in 1...4000 {
                let x = Double(step) / 4000
                let value = x * x * x * pow(max(0, 1 - x.squareRoot()), exponent)
                peak = max(peak, pow(value, 0.25) * norm)
            }
            XCTAssertEqual(peak, 1.0, accuracy: 1e-3, "exponent \(exponent): the peak is \(peak)")
        }
    }
}
