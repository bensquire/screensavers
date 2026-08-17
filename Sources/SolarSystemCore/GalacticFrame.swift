import CAstronomy
import Foundation
import simd

/// Conversion from the J2000 equatorial frame (EQJ), which is what
/// `Astronomy_HelioVector` / `Astronomy_HelioState` return, into galactic coordinates.
///
/// Galactic frame axis convention (verified in `GalacticFrameTests`):
///   +x → galactic centre (l=0°, b=0°)
///   +y → direction of galactic rotation (l=90°) — this is the way the Sun is travelling
///   +z → north galactic pole (b=+90°)
///
/// The matrix comes from astronomy-engine's `Astronomy_Rotation_EQJ_GAL()`, so the
/// pole constants are not hand-rolled here.
public enum GalacticFrame {

    /// EQJ → GAL as a simd matrix, derived by pushing the three basis vectors through
    /// the engine's own rotation routine. Building it this way means we inherit the
    /// engine's index convention instead of guessing at its row/column ordering.
    public static let eqjToGal: simd_double3x3 = {
        let rot = Astronomy_Rotation_EQJ_GAL()
        func mapped(_ v: SIMD3<Double>) -> SIMD3<Double> {
            var input = astro_vector_t()
            input.status = ASTRO_SUCCESS
            input.x = v.x
            input.y = v.y
            input.z = v.z
            input.t = Astronomy_TimeFromDays(0)
            let out = Astronomy_RotateVector(rot, input)
            return SIMD3(out.x, out.y, out.z)
        }
        // Column j of a matrix is the image of basis vector e_j.
        return simd_double3x3(
            columns: (
                mapped(SIMD3(1, 0, 0)),
                mapped(SIMD3(0, 1, 0)),
                mapped(SIMD3(0, 0, 1))
            ))
    }()

    public static func galactic(fromEQJ v: SIMD3<Double>) -> SIMD3<Double> {
        eqjToGal * v
    }

    /// Unit vector, in galactic coordinates, of the Sun's travel around the galaxy.
    /// By construction of the frame this is exactly +y (l=90°, toward Cygnus).
    public static let solarApexDirection = SIMD3<Double>(0, 1, 0)

    /// The ecliptic north pole expressed in galactic coordinates — i.e. the normal of
    /// the plane the planets orbit in, in the frame the scene is built in.
    /// Camera placement needs this: a viewing direction ~55–65° off this vector shows
    /// the orbital plane as a well-opened ellipse rather than edge-on.
    public static let eclipticPoleInGalactic: SIMD3<Double> = simd_normalize(
        galactic(fromEQJ: eclipticPoleEQJ)
    )

    /// Mean obliquity of the ecliptic at J2000.0, in degrees.
    public static let obliquityJ2000Degrees = 23.4392911

    /// Ecliptic north pole in the J2000 equatorial frame.
    public static let eclipticPoleEQJ: SIMD3<Double> = {
        let e = obliquityJ2000Degrees * .pi / 180
        return SIMD3(0, -sin(e), cos(e))
    }()

    /// Angle between the ecliptic plane and the galactic plane, in degrees.
    /// Computed rather than hard-coded so it can be asserted in tests: ≈ 60.19°.
    /// This is the number the "vortex" videos get wrong by assuming 90°.
    public static var eclipticToGalacticPlaneAngleDegrees: Double {
        let cosAngle = simd_dot(eclipticPoleInGalactic, SIMD3<Double>(0, 0, 1))
        return acos(max(-1, min(1, cosAngle))) * 180 / .pi
    }

    /// Galactic longitude and latitude of a unit vector, in degrees.
    public static func longitudeLatitudeDegrees(
        of v: SIMD3<Double>
    ) -> (l: Double, b: Double) {
        let u = simd_normalize(v)
        return (atan2(u.y, u.x) * 180 / .pi, asin(max(-1, min(1, u.z))) * 180 / .pi)
    }
}
