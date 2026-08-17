import Foundation
import SolarSystemCore
import simd

// Prints the ephemeris and frame transforms in a form you can diff against
// JPL Horizons by hand. Run: swift run ssverify [--date 2026-08-07T00:00:00Z]

func parseDate(_ args: [String]) -> Date {
    guard let i = args.firstIndex(of: "--date"), i + 1 < args.count else {
        return Date()
    }
    if let d = parseISODate(args[i + 1]) { return d }
    FileHandle.standardError.write(Data("bad --date value: \(args[i + 1])\n".utf8))
    exit(2)
}

func fmt(_ v: Double, _ width: Int = 14, _ places: Int = 9) -> String {
    String(format: "%\(width).\(places)f", v)
}

let args = Array(CommandLine.arguments.dropFirst())
let date = parseDate(args)

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime]
let stamp = iso.string(from: date)

print("Solar System — ephemeris verification")
print("date: \(stamp)")
print("engine: astronomy-engine (C), heliocentric, no light-time or aberration correction")
print("")

// ---------------------------------------------------------------------------
print("[1] Heliocentric position, J2000 equatorial (EQJ), AU")
print("    Compare against JPL Horizons with:")
print("      EPHEM_TYPE=VECTORS  CENTER='500@10'  REF_PLANE='FRAME'  OUT_UNITS='AU-D'")
print("    (CENTER 500@10 = Sun body centre; REF_PLANE=FRAME = ICRF ≡ EQJ)")
print("")
print(
    "  body       \("X".padding(toLength: 14, withPad: " ", startingAt: 0))"
        + " \("Y".padding(toLength: 14, withPad: " ", startingAt: 0))"
        + " \("Z".padding(toLength: 14, withPad: " ", startingAt: 0))"
        + "   r (AU)")

for planet in Planet.allCases {
    let p = try Ephemeris.helioPosition(planet, at: date)
    let r = simd_length(p)
    print(
        "  \(planet.name.padding(toLength: 9, withPad: " ", startingAt: 0))"
            + " \(fmt(p.x)) \(fmt(p.y)) \(fmt(p.z))"
            + "  \(fmt(r, 12, 7))")
}
print("")

// ---------------------------------------------------------------------------
print("[2] Same positions rotated into galactic coordinates, AU")
print("    +x → galactic centre, +y → direction of galactic rotation, +z → NGP")
print("")
for planet in Planet.allCases {
    let eqj = try Ephemeris.helioPosition(planet, at: date)
    let gal = GalacticFrame.galactic(fromEQJ: eqj)
    print(
        "  \(planet.name.padding(toLength: 9, withPad: " ", startingAt: 0))"
            + " \(fmt(gal.x)) \(fmt(gal.y)) \(fmt(gal.z))")
}
print("")

// ---------------------------------------------------------------------------
print("[3] Frame invariants (independent of date)")
let angle = GalacticFrame.eclipticToGalacticPlaneAngleDegrees
print("    ecliptic / galactic plane angle : \(fmt(angle, 10, 4))°   (expect ≈ 60.19°)")
let pole = GalacticFrame.eclipticPoleInGalactic
print(
    "    ecliptic pole in galactic xyz   : "
        + String(format: "(%+.4f, %+.4f, %+.4f)", pole.x, pole.y, pole.z))
print(
    "    ecliptic pole galactic l, b     : "
        + String(
            format: "l=%7.2f°  b=%+6.2f°",
            atan2(pole.y, pole.x) * 180 / .pi,
            asin(pole.z) * 180 / .pi))
let m = GalacticFrame.eqjToGal
let det = simd_determinant(m)
let residual = m * m.transpose - matrix_identity_double3x3
let orthoErr = (0..<3).reduce(0.0) { acc, c in
    max(acc, simd_reduce_max(simd_abs(residual[c])))
}
print("    rotation determinant           : \(fmt(det, 10, 6))   (expect 1.0)")
print("    max |M·Mᵀ − I|                 : \(String(format: "%10.3e", orthoErr))   (expect ~0)")
print("")
print("    NOTE: 60.19°, not 90°. The 'vortex' animations draw the ecliptic")
print("          perpendicular to the Sun's travel; it is tilted by 30° from that.")
print("")

// ---------------------------------------------------------------------------
print("[4] Galactic drift, true scale")
print(String(format: "    Sun's galactic orbital speed   : %8.1f km/s", Constants.solarGalacticSpeedKmS))
print(String(format: "    → drift per Julian year        : %8.2f AU", Constants.solarDriftAUPerYear))
print("")
print("    Helix geometry per planet at true scale:")
print("      body       orbit r (AU)   pitch (AU/turn)   pitch:radius   deviation from straight")
for planet in Planet.allCases {
    let r = try simd_length(Ephemeris.helioPosition(planet, at: date))
    let pitch = Constants.solarDriftAUPerYear * planet.orbitalPeriodYears
    let ratio = pitch / r
    // Angle between the body's path and the Sun's straight track.
    let deviation = atan(2 * Double.pi * r / pitch) * 180 / .pi
    print(
        "      \(planet.name.padding(toLength: 9, withPad: " ", startingAt: 0))"
            + String(format: " %10.3f    %14.1f   %10.1f:1   %8.2f°", r, pitch, ratio, deviation))
}
print("")
print("    This is why the reference image can't be literal: even Mercury's path")
print("    deviates only a few degrees from the Sun's straight line through the galaxy.")
print("")

// ---------------------------------------------------------------------------
let model = DisplayModel(config: SceneConfig(), epoch: date)
let snap = try model.snapshot(at: date)
print("[5] Scene-space output with default display config")
print(
    String(
        format: "    radial exponent      : %.3f  (r' = r^e; Earth 1 AU → 1 unit)",
        SceneConfig().scale.radialExponent))
print(
    String(
        format: "    drift                : %.4f units/yr = %.4f%% of true",
        SceneConfig().scale.driftUnitsPerYear,
        SceneConfig().scale.driftFractionOfTrue * 100))
let boundingRadius =
    snap.bodies
    .flatMap(\.trail)
    .map { simd_length($0 - snap.sunPosition) }
    .max() ?? 0
print(String(format: "    scene bounding radius: %.3f units", boundingRadius))
print("")
for b in snap.bodies {
    let p = b.scenePosition
    print(
        "  \(b.planet.name.padding(toLength: 9, withPad: " ", startingAt: 0))"
            + String(format: " %9.4f %9.4f %9.4f   trail pts %4d", p.x, p.y, p.z, b.trail.count))
}
print("")

// ---------------------------------------------------------------------------
// Frame budget matters here: a screensaver rebuilding every trail each frame is
// doing a few thousand ephemeris evaluations per frame.
print("[6] Per-frame cost of a full snapshot")
let warmup = 5, runs = 60
for _ in 0..<warmup { _ = try model.snapshot(at: date) }
var total = 0.0
var samples = 0
for i in 0..<runs {
    let t = date.addingTimeInterval(Double(i) * 86400)
    let start = DispatchTime.now().uptimeNanoseconds
    let s = try model.snapshot(at: t)
    total += Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    samples = s.bodies.reduce(0) { $0 + $1.trail.count }
}
let avg = total / Double(runs)
print(String(format: "    ephemeris evaluations per frame : %6d", samples))
print(String(format: "    mean snapshot time              : %6.2f ms", avg))
print(String(format: "    → headroom at 30 fps (33.3 ms)  : %6.1f%% of budget", avg / 33.3 * 100))
print(String(format: "    → headroom at 60 fps (16.7 ms)  : %6.1f%% of budget", avg / 16.7 * 100))
