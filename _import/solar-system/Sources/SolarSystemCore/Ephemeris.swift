import CAstronomy
import Foundation
import simd

public enum EphemerisError: Error, CustomStringConvertible {
    case engineFailure(body: String, status: UInt32)

    public var description: String {
        switch self {
        case let .engineFailure(body, status):
            return "astronomy-engine failed for \(body) (status \(status))"
        }
    }
}

/// Parses the two date forms the tools accept: a full ISO-8601 timestamp, or a bare
/// calendar date read as UTC midnight. Shared so the app and ssverify cannot disagree.
public func parseISODate(_ text: String) -> Date? {
    let full = ISO8601DateFormatter()
    full.formatOptions = [.withInternetDateTime]
    if let d = full.date(from: text) { return d }
    let dayOnly = ISO8601DateFormatter()
    dayOnly.formatOptions = [.withFullDate]
    dayOnly.timeZone = TimeZone(identifier: "UTC")
    return dayOnly.date(from: text)
}

public enum Ephemeris {
    /// J2000.0 = 2000-01-01T12:00:00Z, the epoch astronomy-engine measures `ut` from.
    public static let j2000 = Date(timeIntervalSinceReferenceDate: -31_579_200)

    static func astroTime(_ date: Date) -> astro_time_t {
        // `ut` is days of Universal Time since J2000. Going through days rather than
        // calendar components avoids any Calendar/timezone involvement.
        Astronomy_TimeFromDays(date.timeIntervalSince(j2000) / 86400.0)
    }

    /// Heliocentric position in the J2000 equatorial frame.
    public static func helioPosition(_ planet: Planet, at date: Date) throws -> SIMD3<Double> {
        try helioPosition(planet, time: astroTime(date))
    }

    /// Position at a Terrestrial Time expressed in days since J2000.
    ///
    /// JPL Horizons timestamps vector tables in TDB (≡ TT to well under a millisecond
    /// here). Going in via TT rather than UTC removes ΔT from any comparison, so a
    /// Horizons fixture test measures ephemeris error and nothing else.
    public static func helioPosition(
        _ planet: Planet, terrestrialTimeDays tt: Double
    ) throws -> SIMD3<Double> {
        try helioPosition(planet, time: Astronomy_TerrestrialTime(tt))
    }

    private static func helioPosition(_ planet: Planet, time: astro_time_t) throws -> SIMD3<Double> {
        let v = Astronomy_HelioVector(planet.astroBody, time)
        guard v.status == ASTRO_SUCCESS else {
            throw EphemerisError.engineFailure(body: planet.name, status: v.status.rawValue)
        }
        return SIMD3(v.x, v.y, v.z)
    }
}
