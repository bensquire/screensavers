import AppKit
import Metal
import SaverKit
import VortexCore
import VortexRender

/// A plain window running the same scene as the screensaver, so it can be
/// developed and watched without installing it and locking the screen.
///
///   ,  options        F  full screen        Q  quit
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var tunnel: VortexMetalView!
    private var configController: VortexConfigureSheet!
    private var timer: Timer?
    private var frameClock = FrameClock(nominalInterval: FrameClock.frameInterval)
    private let store = VortexSettingsStore(
        defaults: SaverPreferences(moduleIdentifier: VortexSettingsStore.bundleIdentifier))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Sliders Vortex — Preview"
        window.center()
        window.backgroundColor = .black

        install(settings: store.settings, frame: frame)

        configController = VortexConfigureSheet(store: store) { [weak self] settings in
            guard let self else { return }
            self.install(settings: settings, frame: self.window.contentView?.bounds ?? frame)
        }

        buildMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        frameClock.reset()
        let interval = FrameClock.frameInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tunnel.advance(deltaTime: self.frameClock.tick())
        }
        // Keep animating while a menu is open or the window is being resized.
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// The particle count is baked into the GPU buffers, so a settings change
    /// swaps the whole view rather than mutating it.
    private func install(settings: VortexSettings, frame: NSRect) {
        guard let view = try? VortexMetalView(frame: frame, settings: settings) else {
            FileHandle.standardError.write(Data("Metal is unavailable\n".utf8))
            exit(1)
        }
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        tunnel = view
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Options…", action: #selector(showOptions), keyEquivalent: ","
        ).target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showOptions() {
        window.beginSheet(configController.window, completionHandler: nil)
    }
}

/// Headless frame render, for the System Settings thumbnails.
///
///   VortexApp --render out.png --width 90 --height 58 --at 40
///
/// Unlike the Core Graphics savers this needs a GPU, so the tiles are rendered
/// on a real machine and committed — which is what a release wants anyway, since
/// it keeps the build a pure compile-and-link.
func renderThumbnail() -> Bool {
    let args = CommandLine.arguments
    guard let flag = args.firstIndex(of: "--render"), flag + 1 < args.count else { return false }
    let path = args[flag + 1]

    func value(_ name: String, _ fallback: Double) -> Double {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
        return Double(args[i + 1]) ?? fallback
    }
    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    let width = Int(value("--width", 90))
    let height = Int(value("--height", 58))
    let settleSeconds = value("--at", 40)

    // Streak widths and sprite sizes are in absolute pixels, so rendering
    // straight into a 180-pixel tile gives streaks as wide as the tunnel and an
    // additive blend that saturates to white. Render it large and scale down,
    // which is what the tile is meant to be a picture of.
    let supersample = max(1, Int((900.0 / Double(max(width, 1))).rounded(.up)))
    let renderWidth = width * supersample
    let renderHeight = height * supersample

    guard let device = MTLCreateSystemDefaultDevice() else { fail("no Metal device") }
    var settings = VortexSettings.default
    settings.density *= 0.5

    let layout = Layout(
        pointWidth: Double(renderWidth), pointHeight: Double(renderHeight), backingScale: 1)
    let scene = VortexScene(layout: layout, settings: settings, seed: 20_260_816)
    guard let renderer = try? VortexRenderer(device: device, particles: scene.particles) else {
        fail("could not create the renderer")
    }

    // Run the scene forward so the tunnel has drifted somewhere interesting
    // rather than sitting at its symmetric starting pose.
    let step = FrameClock.frameInterval
    var t = 0.0
    while t < settleSeconds {
        scene.update(deltaTime: step, layout: layout)
        t += step
    }

    guard
        let full = renderer.renderToImage(
            scene: scene, width: renderWidth, height: renderHeight)
    else { fail("could not render the frame") }
    guard let image = downsample(full, to: CGSize(width: width, height: height)) else {
        fail("could not scale the frame down")
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("could not encode PNG")
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        fail("could not write \(path): \(error)")
    }
    print("wrote \(path) (\(width)×\(height), rendered at \(supersample)×)")
    return true
}

/// Area-averaging scale-down, so the many thin streaks average into the tile
/// rather than a handful of them being point-sampled into fat bright lines.
func downsample(_ image: CGImage, to size: CGSize) -> CGImage? {
    guard
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: size))
    return context.makeImage()
}

// No `--bench` here yet. Say so and stop, rather than falling through and
// opening a preview window that never exits — `make bench` would hang on it.
if CommandLine.arguments.contains("--bench") {
    FileHandle.standardError.write(
        Data("this saver has no --bench mode; see GargantuaApp or ThreeBodyApp\n".utf8))
    exit(2)
}

if renderThumbnail() { exit(0) }

let app = NSApplication.shared
let delegate = PreviewAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
