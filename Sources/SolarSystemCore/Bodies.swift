import CAstronomy

/// The bodies we draw. Deliberately excludes Pluto — astronomy-engine supports it,
/// but its 248-year period makes it useless as a visible trail.
public enum Planet: Int, CaseIterable, Sendable {
    case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune

    var astroBody: astro_body_t {
        switch self {
        case .mercury: return BODY_MERCURY
        case .venus: return BODY_VENUS
        case .earth: return BODY_EARTH
        case .mars: return BODY_MARS
        case .jupiter: return BODY_JUPITER
        case .saturn: return BODY_SATURN
        case .uranus: return BODY_URANUS
        case .neptune: return BODY_NEPTUNE
        }
    }

    public var name: String {
        switch self {
        case .mercury: return "Mercury"
        case .venus: return "Venus"
        case .earth: return "Earth"
        case .mars: return "Mars"
        case .jupiter: return "Jupiter"
        case .saturn: return "Saturn"
        case .uranus: return "Uranus"
        case .neptune: return "Neptune"
        }
    }

    /// Sidereal orbital period in days, straight from astronomy-engine.
    public var orbitalPeriodDays: Double {
        Astronomy_PlanetOrbitalPeriod(astroBody)
    }

    public var orbitalPeriodYears: Double {
        orbitalPeriodDays / Constants.daysPerJulianYear
    }

    /// Display colour, linear-ish sRGB. Chosen for the dark-field look, not albedo accuracy.
    public var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .mercury: return (0.62, 0.60, 0.57)
        case .venus: return (0.91, 0.75, 0.48)
        case .earth: return (0.30, 0.66, 1.00)
        case .mars: return (0.89, 0.38, 0.24)
        case .jupiter: return (0.85, 0.63, 0.40)
        case .saturn: return (0.91, 0.84, 0.60)
        case .uranus: return (0.50, 0.83, 0.88)
        case .neptune: return (0.25, 0.38, 0.88)
        }
    }

    /// Mean radius in km (IAU 2015 nominal values).
    public var meanRadiusKm: Double {
        switch self {
        case .mercury: return 2_439.7
        case .venus: return 6_051.8
        case .earth: return 6_371.0
        case .mars: return 3_389.5
        case .jupiter: return 69_911.0
        case .saturn: return 58_232.0
        case .uranus: return 25_362.0
        case .neptune: return 24_622.0
        }
    }
}

public enum Constants {
    public static let kmPerAU = 1.495978707e8
    /// Neptune's semi-major axis, the outer edge of the drawn system.
    public static let outermostOrbitAU = 30.07
    /// IAU 2015 nominal solar radius.
    public static let sunRadiusKm = 695_700.0
    public static let daysPerJulianYear = 365.25
    public static let secondsPerJulianYear = 365.25 * 86400.0

    /// Speed of the Sun on its orbit around the galactic centre. Measurements cluster
    /// in the 220–235 km/s range depending on the assumed distance to Sgr A*; 230 is
    /// a reasonable middle. This is the *total* galactic orbital speed, not the ~19.5 km/s
    /// peculiar motion of the Sun relative to the Local Standard of Rest.
    public static let solarGalacticSpeedKmS = 230.0

    /// How far the Sun travels along its galactic orbit in one Julian year, in AU.
    /// ≈ 48.5 AU/yr — the number that makes the "vortex" pictures wrong: Earth's orbital
    /// radius is 1 AU but the helix advances ~48 AU per turn.
    public static let solarDriftAUPerYear =
        solarGalacticSpeedKmS * secondsPerJulianYear / kmPerAU
}
