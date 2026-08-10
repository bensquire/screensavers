import AppKit
import Foundation
import SceneKit
import SolarSystemCore
import SolarSystemRender

struct LaunchOptions {
    var width: Int = 1280
    var height: Int = 720
    var renderPath: String?
    var date: Date = Date()
    var allowsCameraControl: Bool = true
    var zoom: Double = SolarSystemRenderer.defaultZoom
    var elevation: Double? = nil
    var azimuth: Double? = nil
    var cameraMotion = true
    var orbitPeriod: Double? = nil
    var inclination: Double? = nil
    var phase: Double? = nil
    var roll: Double? = nil
    var cameraTrace = false
    var preset: ScalePreset? = nil
    var config = SceneConfig()
    /// For --render: how far into the animation to jump before snapshotting.
    var renderAtSeconds: Double = 0
}

func parseOptions() -> LaunchOptions {
    var o = LaunchOptions()
    // Seeded from the live defaults rather than restated, so a tuning change in
    // SceneConfig cannot silently leave the CLI (or the help text below) behind.
    let d = SceneConfig()
    let caps = d.trail.adaptiveCaps ?? (maxYears: 70, maxOrbits: 4)
    var exponent = d.scale.radialExponent
    var drift = d.scale.driftUnitsPerYear
    var trailYears: Double? = nil
    var trailOrbits: Double? = nil
    var maxYears = caps.maxYears
    var maxOrbits = caps.maxOrbits
    var samples = d.trailSamples
    var yearsPerSecond = d.yearsPerSecond
    var starParallax = d.starParallax
    var sunRadius = d.sunDisplayRadius
    var bodyExponent = d.bodyRadiusExponent
    let cam = SolarSystemRenderer.CameraOrbit()

    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    func value(_ name: String) -> String? {
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("missing value for \(name)\n".utf8))
            exit(2)
        }
        i += 1
        return args[i]
    }

    while i < args.count {
        let a = args[i]
        switch a {
        case "--render": o.renderPath = value(a)
        case "--width": o.width = Int(value(a) ?? "") ?? o.width
        case "--height": o.height = Int(value(a) ?? "") ?? o.height
        case "--at": o.renderAtSeconds = Double(value(a) ?? "") ?? 0
        case "--zoom": o.zoom = Double(value(a) ?? "") ?? o.zoom
        case "--elevation": o.elevation = Double(value(a) ?? "")
        case "--azimuth": o.azimuth = Double(value(a) ?? "")
        case "--no-camera-motion": o.cameraMotion = false
        case "--camera-trace": o.cameraTrace = true
        case "--orbit-period": o.orbitPeriod = Double(value(a) ?? "")
        case "--inclination": o.inclination = Double(value(a) ?? "")
        case "--phase": o.phase = Double(value(a) ?? "")
        case "--roll": o.roll = Double(value(a) ?? "")
        case "--exponent": exponent = Double(value(a) ?? "") ?? exponent
        case "--drift": drift = Double(value(a) ?? "") ?? drift
        case "--trail-years": trailYears = Double(value(a) ?? "")
        case "--trail-orbits": trailOrbits = Double(value(a) ?? "")
        case "--trail-max-years": maxYears = Double(value(a) ?? "") ?? maxYears
        case "--trail-max-orbits": maxOrbits = Double(value(a) ?? "") ?? maxOrbits
        case "--samples": samples = Int(value(a) ?? "") ?? samples
        case "--years-per-second": yearsPerSecond = Double(value(a) ?? "") ?? yearsPerSecond
        case "--star-parallax": starParallax = Double(value(a) ?? "") ?? starParallax
        case "--sun-radius": sunRadius = Double(value(a) ?? "") ?? sunRadius
        case "--body-exponent": bodyExponent = Double(value(a) ?? "") ?? bodyExponent
        case "--true-scale": o.preset = .trueScale
        case "--true-distances": o.preset = .trueDistances
        case "--birds-eye": o.preset = .birdsEye
        case "--no-camera-control": o.allowsCameraControl = false
        case "--date":
            let s = value(a) ?? ""
            guard let parsed = parseISODate(s) else {
                FileHandle.standardError.write(Data("bad --date: \(s)\n".utf8))
                exit(2)
            }
            o.date = parsed
        case "--help", "-h":
            print(
                """
                SolarSystemApp — astronomically-positioned solar system drifting through the galaxy

                  --render PATH        render one frame to PNG and exit (no window needed)
                  --at SECONDS         animation time to render at (with --render)
                  --width N            (default 1280)
                  --height N           (default 720)
                  --date ISO8601       simulation start date (default: now)
                  --exponent E         radial compression r' = r^E (1.0 = linear, default \(exponent))
                  --drift U            scene units of galactic drift per year (default \(drift))
                  --true-scale         everything at 1x: real distances, sizes and drift
                  --true-distances     real relative orbit sizes, drift still compressed
                  --birds-eye          fixed top-down orrery, galactic drift switched off
                  --trail-max-years Y  adaptive trail cap in years (default \(maxYears))
                  --trail-max-orbits N adaptive trail cap in revolutions (default \(maxOrbits))
                  --trail-years Y      force a fixed window in years for every planet
                  --trail-orbits N     force a fixed revolution count for every planet
                  --samples N          points per 3-revolution trail (default \(samples))
                  --years-per-second Y simulated years per real second (default \(yearsPerSecond))
                  --star-parallax N    exaggeration of star motion, 0 = none (default \(starParallax))
                  --sun-radius R       scene radius of the Sun (default \(sunRadius))
                  --body-exponent E    body size compression (R/Rsun)^E (default \(bodyExponent))
                  --zoom Z             crop; >1 crops in, <1 pulls back (default \(o.zoom))
                  --elevation D        pin the camera at an angle from the travel axis, 0 =
                                       directly behind the Sun, 90 = side on (stops the orbit)
                  --azimuth D          pin its rotation about that axis (stops the orbit)
                  --roll D             tilt of the Sun's track below horizontal (default \(cam.rollDegrees))
                  --orbit-period S     seconds for one revolution round the Sun (default \(cam.periodSeconds))
                  --inclination D      camera orbit's tilt to the ecliptic (default \(cam.inclinationDegrees))
                  --phase D            starting position on the orbit (default \(cam.phaseDegrees))
                  --no-camera-motion   hold the camera still instead of orbiting
                  --no-camera-control  disable mouse orbiting
                  --camera-trace       print camera position/target/distance over time
                """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown option: \(a)\n".utf8))
            exit(2)
        }
        i += 1
    }

    var built = SceneConfig(
        scale: .compressed(radialExponent: exponent, driftUnitsPerYear: drift),
        trail: trailOrbits.map { TrailMode.orbits($0) }
            ?? trailYears.map { TrailMode.years($0) }
            ?? .adaptive(maxYears: maxYears, maxOrbits: maxOrbits),
        trailSamples: samples,
        yearsPerSecond: yearsPerSecond,
        starParallax: starParallax,
        sunDisplayRadius: sunRadius,
        bodyRadiusExponent: bodyExponent
    )
    if let preset = o.preset { built = preset.config(base: built) }
    o.config = built
    return o
}

let options = parseOptions()
let model = DisplayModel(config: options.config, epoch: options.date)
let renderer = SolarSystemRenderer(model: model, startDate: options.date)
renderer.zoom = options.zoom
if let preset = options.preset { preset.apply(to: renderer) }
// Any explicit viewpoint pins the camera; otherwise it orbits.
renderer.orbit.enabled =
    options.cameraMotion
    && options.elevation == nil && options.azimuth == nil
if let e = options.elevation { renderer.orbit.elevationDegrees = e }
if let a = options.azimuth { renderer.orbit.azimuthDegrees = a }
if let p = options.orbitPeriod { renderer.orbit.periodSeconds = p }
if let inc = options.inclination { renderer.orbit.inclinationDegrees = inc }
if let ph = options.phase { renderer.orbit.phaseDegrees = ph }
if let r = options.roll { renderer.orbit.rollDegrees = r }
renderer.reframe(aspectRatio: Double(options.width) / Double(options.height))

if options.cameraTrace {
    // Sample the camera over real seconds to see what it is actually doing.
    print("  t(s)   phase     cam.x    cam.y    cam.z    tgt.x    tgt.y    tgt.z    dist")
    var i = 0.0
    while i <= 120.0 {
        renderer.update(to: renderer.date(forElapsed: i))
        let c = renderer.cameraState
        print(
            String(
                format: "%6.2f  %6.1f   %7.3f  %7.3f  %7.3f  %7.3f  %7.3f  %7.3f  %7.3f",
                i,
                renderer.orbit.phaseDegrees
                    + 360 * i / renderer.orbit.periodSeconds,
                c.position.x, c.position.y, c.position.z,
                c.target.x, c.target.y, c.target.z, c.distance))
        i += 5.0
    }
    exit(0)
}

if let path = options.renderPath {
    // Offscreen path: no window, no run loop. Makes visual iteration scriptable.
    guard let device = MTLCreateSystemDefaultDevice() else {
        FileHandle.standardError.write(Data("no Metal device available\n".utf8))
        exit(1)
    }
    if options.renderAtSeconds > 0 {
        renderer.update(to: renderer.date(forElapsed: options.renderAtSeconds))
    }

    let scnRenderer = SCNRenderer(device: device, options: nil)
    scnRenderer.scene = renderer.scene
    scnRenderer.pointOfView = renderer.pointOfView

    let size = CGSize(width: options.width, height: options.height)
    renderer.setOverlaySize(size)
    scnRenderer.overlaySKScene = renderer.overlayScene
    let image = scnRenderer.snapshot(
        atTime: 0, with: size, antialiasingMode: .multisampling4X
    )

    guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        let iso = ISO8601DateFormatter()
        print(
            "wrote \(path)  (\(options.width)x\(options.height), sim date \(iso.string(from: renderer.currentDate)))"
        )
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

let app = NSApplication.shared
let host = AppHost(renderer: renderer, options: options)
app.delegate = host
app.setActivationPolicy(.regular)
app.run()
