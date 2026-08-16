import AppKit
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
    private let store = SettingsStore(defaults: .standard)

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

if renderThumbnail() { exit(0) }

let app = NSApplication.shared
let delegate = PreviewAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
