import AppKit
import SaverKit
import ThreeBodyCore
import ThreeBodyRender

/// A plain window running the same simulation as the screensaver, so the thing
/// can be developed and watched without installing it and locking the screen.
///
///   Space / N  next scene      H  toggle readout
///   G  toggle glow             F  full screen        Q  quit
///
/// Accepts `--mode known|random|both` to override the stored scene mode for
/// this run only. Two instances share one preferences domain, so a launch
/// argument is the only way to run them side by side on different modes.
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var surface: SimulationSurfaceView!
    private var configController: ConfigureSheetController!
    private let store = SettingsStore(
        defaults: SaverPreferences(moduleIdentifier: SettingsStore.bundleIdentifier))

    /// `--mode` from the command line, if given. Not persisted.
    private static func modeOverride() -> SceneMode? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--mode"),
            flag + 1 < arguments.count
        else { return nil }
        switch arguments[flag + 1].lowercased() {
        case "known", "knownorbits", "catalogue": return .knownOrbits
        case "random", "randomsystems": return .randomSystems
        case "both": return .both
        default: return nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)

        var settings = store.settings
        let override = Self.modeOverride()
        if let override { settings.mode = override }

        window.title =
            override == nil
            ? "Three-Body Problem — Preview"
            : "Three-Body Problem — \(settings.mode.displayName)"
        window.center()
        window.backgroundColor = .black

        surface = SimulationSurfaceView(frame: frame, settings: settings)
        surface.autoresizingMask = [.width, .height]
        window.contentView = surface

        configController = ConfigureSheetController(store: store) { [weak self] settings in
            self?.surface.engine.settings = settings
        }

        buildMenu()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(surface)
        NSApp.activate(ignoringOtherApps: true)
        surface.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Options…", action: #selector(showOptions),
            keyEquivalent: ","
        ).target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Next Scene", action: #selector(nextScene),
            keyEquivalent: "n"
        ).target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showOptions() {
        window.beginSheet(configController.window, completionHandler: nil)
    }

    @objc private func nextScene() {
        surface.engine.advanceToNextScene()
    }
}

/// Headless frame render, for the System Settings thumbnails.
///
///   ThreeBodyApp --render out.png --width 90 --height 58 --at 40
///
/// The renderer is Core Graphics, so unlike a SceneKit saver this needs no GPU
/// and works anywhere — including a CI runner, though the tiles are committed
/// rather than built so the release stays a pure compile-and-link.
func renderThumbnail() -> Bool {
    let args = CommandLine.arguments
    guard let flag = args.firstIndex(of: "--render"), flag + 1 < args.count else { return false }
    let path = args[flag + 1]

    func value(_ name: String, _ fallback: Double) -> Double {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
        return Double(args[i + 1]) ?? fallback
    }
    let size = CGSize(width: value("--width", 90), height: value("--height", 58))
    let settleSeconds = value("--at", 40)

    var settings = SimulationSettings.default
    // A tile is a couple of hundred points across: the readout would be
    // illegible and the stars would read as noise.
    settings.showHUD = false
    settings.starDensity *= 0.6
    settings.sceneDuration = 100_000

    let engine = SimulationEngine(
        settings: settings, seed: 20260816,
        scenario: Scenarios.figureEight)
    let renderer = Renderer()
    renderer.uiScale = 0.5

    let step = 1.0 / 60.0
    var t = 0.0
    while t < settleSeconds {
        engine.update(deltaTime: step, viewSize: (Double(size.width), Double(size.height)))
        t += step
    }

    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
    else {
        FileHandle.standardError.write(Data("could not create a bitmap context\n".utf8))
        exit(1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    renderer.draw(engine: engine, in: ctx.cgContext, size: size, time: t, showHUD: false)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(size.width))×\(Int(size.height)))")
    return true
}

/// Times the renderer, deterministically.
///
///   ThreeBodyApp --bench [--width 2560] [--height 1600] [--frames 300]
///
/// Offscreen and fixed-seed on purpose. Sampling the preview app instead gives
/// numbers that swing from 20% to 100% between launches, because the engine
/// seeds itself from the clock and the cost depends entirely on which scenario
/// it picked and how long the trails have grown.
func runBenchmark() -> Bool {
    let args = CommandLine.arguments
    guard args.contains("--bench") else { return false }

    func value(_ name: String, _ fallback: Int) -> Int {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
        return Int(args[i + 1]) ?? fallback
    }
    let width = value("--width", 2560)
    let height = value("--height", 1600)
    let frames = value("--frames", 300)
    let size = CGSize(width: width, height: height)

    let frameMs = FrameClock.frameInterval * 1000

    func measure(
        _ label: String,
        _ scenario: Scenario = Scenarios.figureEight,
        _ configure: (inout SimulationSettings) -> Void = { _ in }
    ) {
        var settings = SimulationSettings.default
        configure(&settings)
        // Fixed seed and fixed scenario, so every variant draws the same thing.
        let engine = SimulationEngine(
            settings: settings, seed: 20_260_816, scenario: scenario)
        let renderer = Renderer()

        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let gc = NSGraphicsContext(bitmapImageRep: rep)
        else { return }

        let step = 1.0 / FrameClock.framesPerSecond
        var drawTimes: [Double] = []
        var updateTimes: [Double] = []
        var t = 0.0
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        for frame in 0..<frames {
            let updateStart = CACurrentMediaTime()
            engine.update(
                deltaTime: step, viewSize: (Double(size.width), Double(size.height)))
            let drawStart = CACurrentMediaTime()
            t += step
            renderer.draw(
                engine: engine, in: gc.cgContext, size: size, time: t,
                showHUD: settings.showHUD)
            gc.flushGraphics()
            // The trails need time to grow before a frame is representative.
            if frame >= 60 {
                updateTimes.append((drawStart - updateStart) * 1000)
                drawTimes.append((CACurrentMediaTime() - drawStart) * 1000)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        drawTimes.sort()
        updateTimes.sort()
        guard !drawTimes.isEmpty else { return }
        let draw = drawTimes[drawTimes.count / 2]
        let update = updateTimes[updateTimes.count / 2]
        let updateWorst = updateTimes[Int(Double(updateTimes.count) * 0.95)]
        print(
            String(
                format: "  %@ physics %6.2f ms (p95 %6.2f)   draw %5.2f ms   total %3.0f%%",
                label.padding(toLength: 22, withPad: " ", startingAt: 0),
                update, updateWorst, draw, (update + draw) / frameMs * 100))
    }

    print("output \(width)x\(height), \(frames) frames, fixed seed\n")
    print("--- figure-eight (a gentle, closed orbit) ---")
    measure("everything on")
    measure("no glow") { $0.showGlow = false }
    measure("no HUD") { $0.showHUD = false }
    measure("no stars") { $0.showStars = false }
    measure("short trails") { $0.trailSeconds = SimulationSettings.Limits.trailSeconds.lowerBound }
    measure("nothing but bodies") {
        $0.showGlow = false
        $0.showHUD = false
        $0.showStars = false
        $0.trailSeconds = SimulationSettings.Limits.trailSeconds.lowerBound
    }

    // Burrau's problem is the worst case the catalogue contains: three bodies
    // in a chaotic dance with repeated close encounters, which is exactly what
    // makes an adaptive integrator take tiny steps.
    print("\n--- Pythagorean/Burrau (chaotic, close encounters) ---")
    for accuracy in Accuracy.allCases {
        measure(
            "\(accuracy.rawValue) (\(accuracy.order))", Scenarios.pythagorean
        ) { $0.accuracy = accuracy }
    }
    return true
}

if runBenchmark() { exit(0) }
if renderThumbnail() { exit(0) }

let app = NSApplication.shared
let delegate = PreviewAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
