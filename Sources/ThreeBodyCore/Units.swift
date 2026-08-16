import Foundation

/// Maps the simulation's dimensionless numbers onto real astrophysical units.
///
/// The integrator works with G = 1 because that is how the periodic-orbit
/// literature states its solutions, and because it keeps the arithmetic well
/// conditioned. But "t = 23.013" means nothing to look at, so everything shown
/// on screen is converted to solar masses, astronomical units and years.
///
/// The mapping is a genuine choice of scale, not a fudge. Fixing
/// 1 mass unit = 1 M☉ and 1 length unit = 1 AU determines the time unit
/// completely, because G is not free once the other two are set:
///
///     G = 4π² AU³ M☉⁻¹ yr⁻²    ⟹    1 time unit = 1/(2π) yr
///
/// The check that this is right: a body circling 1 M☉ at 1 AU takes exactly one
/// year. In dimensionless terms that orbit has period 2π, and 2π × 1/(2π) = 1.
/// `Tests/main.swift` verifies it by integration rather than by algebra.
public enum Units {

    /// Gravitational constant in AU³ M☉⁻¹ yr⁻², which is 4π² by construction.
    public static let gravitationalConstant = 4.0 * Double.pi * Double.pi

    /// One internal time unit, in years.
    public static let yearsPerTimeUnit = 1.0 / (2.0 * Double.pi)

    /// One astronomical unit, in metres (IAU 2012 definition).
    public static let metresPerAU = 1.495_978_707e11
    /// One Julian year, in seconds.
    public static let secondsPerYear = 365.25 * 24.0 * 3600.0

    /// One internal velocity unit, in km/s — 2π AU/yr, i.e. Earth's orbital
    /// speed of 29.78 km/s, which is a useful sanity anchor.
    public static let kilometresPerSecondPerVelocityUnit =
        (metresPerAU / secondsPerYear) * 2.0 * Double.pi / 1000.0

    // MARK: - Conversions

    public static func years(fromTimeUnits t: Double) -> Double { t * yearsPerTimeUnit }
    public static func timeUnits(fromYears t: Double) -> Double { t / yearsPerTimeUnit }
    public static func kilometresPerSecond(fromVelocityUnits v: Double) -> Double {
        v * kilometresPerSecondPerVelocityUnit
    }
    public static func velocityUnits(fromKilometresPerSecond v: Double) -> Double {
        v / kilometresPerSecondPerVelocityUnit
    }

    // MARK: - Display

    /// Elapsed time, in whatever unit keeps the number readable.
    public static func formatTime(_ timeUnits: Double) -> String {
        let y = years(fromTimeUnits: timeUnits)
        guard y.isFinite else { return "—" }
        if y < 1.0 / 12.0 { return String(format: "%.1f days", y * 365.25) }
        if y < 1 { return String(format: "%.1f months", y * 12) }
        if y < 1000 { return String(format: "%.2f years", y) }
        return String(format: "%.3g years", y)
    }

    /// A duration such as a timestep, which can be very small indeed.
    public static func formatShortDuration(_ timeUnits: Double) -> String {
        let y = years(fromTimeUnits: timeUnits)
        guard y.isFinite, y > 0 else { return "—" }
        let days = y * 365.25
        if days < 1.0 / 86400.0 { return String(format: "%.2e s", days * 86400) }
        if days < 1 { return String(format: "%.3g hours", days * 24) }
        if days < 400 { return String(format: "%.3g days", days) }
        return String(format: "%.3g years", y)
    }

    public static func formatMass(_ massUnits: Double) -> String {
        guard massUnits.isFinite else { return "—" }
        if massUnits < 10 { return String(format: "%.2f M☉", massUnits) }
        return String(format: "%.1f M☉", massUnits)
    }

    public static func formatDistance(_ lengthUnits: Double) -> String {
        guard lengthUnits.isFinite else { return "—" }
        if lengthUnits < 0.01 { return String(format: "%.3g AU", lengthUnits) }
        if lengthUnits < 10 { return String(format: "%.2f AU", lengthUnits) }
        return String(format: "%.0f AU", lengthUnits)
    }

    public static func formatSpeed(_ velocityUnits: Double) -> String {
        guard velocityUnits.isFinite else { return "—" }
        return String(format: "%.1f km/s", kilometresPerSecond(fromVelocityUnits: velocityUnits))
    }
}
