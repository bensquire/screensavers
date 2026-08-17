import Foundation

/// Closed-form properties of a Kerr black hole, as functions of its spin.
///
/// These are the same quantities the shader integrates its way around, computed
/// here because several things outside the shader need them: the hot spots have
/// to be placed relative to the ISCO, the camera's tilt floor comes from the
/// disk geometry, and the marcher's step control needs to know where the photon
/// sphere is. Deriving them twice would let the two drift apart.
public enum KerrGeometry {

    /// Spin is clamped just short of extremal, where the horizon and the ISCO
    /// both degenerate and the formulas below stop being meaningful.
    public static let maxSpin = 0.998

    /// Event horizon radius, in units of M.
    public static func horizon(spin a: Double) -> Double {
        1 + (max(0, 1 - a * a)).squareRoot()
    }

    /// Innermost stable circular orbit — the Bardeen-Press-Teukolsky result.
    ///
    /// Returns 6 for a still hole and falls to 1 at extremal prograde spin,
    /// which is why a spinning hole gets a disk reaching much further in and
    /// running much hotter.
    public static func isco(spin a: Double) -> Double {
        let s = abs(a)
        let z1 = 1 + cbrt(1 - s * s) * (cbrt(1 + s) + cbrt(1 - s))
        let z2 = (3 * s * s + z1 * z1).squareRoot()
        return 3 + z2 - (max(0, (3 - z1) * (3 + z1 + 2 * z2))).squareRoot()
    }

    /// Keplerian angular velocity of a prograde circular orbit. Collapses to
    /// r^-3/2 when the hole is still.
    public static func omega(radius r: Double, spin a: Double) -> Double {
        1 / (r * r.squareRoot() + a)
    }

    /// Midpoint of the prograde and retrograde equatorial photon orbits, which
    /// is where the marcher tightens its stride. Both are 3M at zero spin.
    public static func photonRadius(spin a: Double) -> Double {
        func orbit(_ sign: Double) -> Double {
            2 * (1 + cos((2.0 / 3.0) * acos(sign * min(abs(a), maxSpin))))
        }
        return 0.5 * (orbit(-1) + orbit(1))
    }

    /// Normalisation putting the hottest annulus at the requested temperature.
    ///
    /// The emissivity profile is x^3 (1 - sqrt(x))^p over x = diskIn/r.
    /// Substituting y = sqrt(x) gives y^6 (1-y)^p, whose derivative vanishes at
    /// y = 6/(6+p) — so the peak is exact rather than numerically hunted.
    ///
    /// This mirrors `radial` in the shader's `sampleDisk`; the two must change
    /// together.
    public static func temperatureNormalisation(innerEdge p: Double) -> Double {
        let y = 6 / (6 + p)
        return 1 / pow(pow(y, 6) * pow(1 - y, p), 0.25)
    }
}
