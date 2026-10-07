import SaverCore
import XCTest

final class NumericTests: XCTestCase {

    /// `wrapped(modulo:)` promises a result in `0..<modulus`, and the star fields,
    /// the disk's winding and Vortex's particles all rely on it. A negative value
    /// within rounding of zero came back as the modulus itself: -1e-17 modulo 1
    /// gave 1.0, and -1e-14 modulo a 2560-point width gave 2560.0.
    func testATinyNegativeValueWrapsToZeroRatherThanTheModulus() {
        let cases: [(value: Double, modulus: Double)] = [
            (-1e-20, 1), (-1e-17, 1), (-5e-17, 1), (-1e-14, 2560),
        ]

        for (value, modulus) in cases {
            let wrapped = value.wrapped(modulo: modulus)

            XCTAssertLessThan(
                wrapped, modulus, "\(value) modulo \(modulus) came back as \(wrapped)")
            XCTAssertGreaterThanOrEqual(
                wrapped, 0, "\(value) modulo \(modulus) came back as \(wrapped)")
        }
    }
}
