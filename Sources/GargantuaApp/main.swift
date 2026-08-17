import AppKit
import GargantuaCore
import GargantuaRender
import Metal
import SaverKit

/// A plain window running the same scene as the screensaver, so it can be
/// developed and watched without installing it and locking the screen.
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var blackHole: GargantuaMetalView!
    private var configController: GargantuaConfigureSheet!
    private var timer: Timer?
    private var frameClock = FrameClock(nominalInterval: 1.0 / GargantuaRenderer.framesPerSecond)
    private let store = GargantuaSettingsStore(
        defaults: SaverPreferences(moduleIdentifier: GargantuaSettingsStore.bundleIdentifier))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Gargantua — Preview"
        window.center()
        window.backgroundColor = .black

        install(settings: store.settings, frame: frame)

        configController = GargantuaConfigureSheet(store: store) { [weak self] settings in
            guard let self else { return }
            self.install(settings: settings, frame: self.window.contentView?.bounds ?? frame)
        }

        buildMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        frameClock.reset()
        let interval = 1.0 / GargantuaRenderer.framesPerSecond
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.blackHole.advance(deltaTime: self.frameClock.tick())
            // The adaptive controller is the interesting number while developing,
            // so it goes in the title rather than needing a HUD.
            if self.blackHole.scene.frameIndex % 60 == 0 {
                self.window.title = String(
                    format: "Gargantua — Preview  ·  render scale %.0f%%",
                    self.blackHole.renderScale * 100)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func install(settings: GargantuaSettings, frame: NSRect) {
        guard let view = try? GargantuaMetalView(frame: frame, settings: settings) else {
            FileHandle.standardError.write(Data("Metal is unavailable\n".utf8))
            exit(1)
        }
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        blackHole = view
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

/// Headless frame render, for the System Settings thumbnails and for comparing
/// against the WebGL original.
///
///   GargantuaApp --render out.png --width 90 --height 58 --at 40
///
/// `--at` runs the scene forward that many seconds first. The accumulation
/// buffer needs a few frames to converge whatever the settle time, so the last
/// stretch is always rendered rather than simulated.
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
    // Rendered large and scaled down when the target is small: the disk's rim is
    // near-discontinuous seen this close to edge-on, and one sample per pixel
    // cannot hold it at thumbnail size.
    let supersample = max(1, Int((900.0 / Double(max(width, 1))).rounded(.up)))
    let renderWidth = width * supersample
    let renderHeight = height * supersample

    guard let device = MTLCreateSystemDefaultDevice() else { fail("no Metal device") }
    var settings = GargantuaSettings.default
    settings.adaptiveResolution = false
    settings.renderScale = 1.0

    let scene = GargantuaScene(settings: settings)
    guard let renderer = try? GargantuaRenderer(device: device) else {
        fail("could not create the renderer")
    }
    renderer.fixRenderScale(at: 1.0)

    guard let target = device.makeReadableTarget(width: renderWidth, height: renderHeight) else {
        fail("could not create the render target")
    }

    let step = 1.0 / GargantuaRenderer.framesPerSecond
    // Everything up to the last second is simulated only — the camera drift and
    // the disk's churn are pure functions of time, so there is no need to draw
    // frames nobody sees.
    var t = 0.0
    let settleWithoutDrawing = max(0, settleSeconds - 1.0)
    while t < settleWithoutDrawing {
        scene.update(deltaTime: step)
        t += step
    }
    // Then draw for real, so the accumulation buffer converges.
    while t < settleSeconds {
        scene.update(deltaTime: step)
        renderer.renderSynchronously(scene: scene, deltaTime: step, to: target)
        t += step
    }

    guard let full = renderer.readBack(texture: target) else { fail("could not read the frame") }
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

/// Measures what a frame actually costs on this GPU.
///
///   GargantuaApp --bench [--width 2560] [--height 1600] [--frames 90]
///
/// Reports the GPU's own elapsed time per frame — the number the adaptive
/// controller runs on, and the only one that says whether a setting is
/// affordable. Wall-clock time here would be quantised by nothing in
/// particular, since these frames are submitted back to back.
func runBenchmark() -> Bool {
    let args = CommandLine.arguments
    guard args.contains("--bench") else { return false }

    func value(_ name: String, _ fallback: Int) -> Int {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
        return Int(args[i + 1]) ?? fallback
    }
    let width = value("--width", 2560)
    let height = value("--height", 1600)
    let frames = value("--frames", 90)

    guard let device = MTLCreateSystemDefaultDevice() else { return true }
    print("device: \(device.name)   output: \(width)x\(height)   \(frames) frames each\n")

    func measure(scale: Double, steps: Double) -> (median: Double, worst: Double) {
        var settings = GargantuaSettings.default
        settings.adaptiveResolution = false
        let scene = GargantuaScene(settings: settings)
        guard let renderer = try? GargantuaRenderer(device: device),
            let target = device.makeReadableTarget(width: width, height: height)
        else { return (0, 0) }
        renderer.fixRenderScale(at: scale)

        let step = 1.0 / GargantuaRenderer.framesPerSecond
        var samples: [Double] = []
        for i in 0..<frames {
            scene.update(deltaTime: step)
            guard let buffer = renderer.makeCommandBuffer() else { continue }
            renderer.render(scene: scene, deltaTime: step, to: target, in: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            // The first few frames pay for pipeline warm-up and the first
            // accumulation, which is not what a steady-state frame costs.
            if i >= 10 { samples.append((buffer.gpuEndTime - buffer.gpuStartTime) * 1000) }
        }
        samples.sort()
        guard !samples.isEmpty else { return (0, 0) }
        return (samples[samples.count / 2], samples[Int(Double(samples.count) * 0.95)])
    }

    let budget = 1000.0 / GargantuaRenderer.framesPerSecond
    print("render   march      GPU ms/frame        of frame")
    print("scale    pixels     median   p95        budget")
    for scale in [0.30, 0.40, 0.55, 0.70, 0.85, 1.00] {
        let (median, worst) = measure(scale: scale, steps: SceneParameters().steps)
        let marchPixels = Double(width * height) * scale * scale / 1_000_000
        print(
            String(
                format: "%.2f     %5.2fM     %6.2f  %6.2f     %3.0f%%",
                scale, marchPixels, median, worst, median / budget * 100))
    }

    // What the thing actually settles at, which is the only number that says
    // how hard it leans on the machine.
    var settings = GargantuaSettings.default
    settings.adaptiveResolution = true
    let scene = GargantuaScene(settings: settings)
    guard let renderer = try? GargantuaRenderer(device: device),
        let target = device.makeReadableTarget(width: width, height: height)
    else { return true }

    let step = 1.0 / GargantuaRenderer.framesPerSecond
    var recent: [Double] = []
    for _ in 0..<900 {
        scene.update(deltaTime: step)
        guard let buffer = renderer.makeCommandBuffer() else { continue }
        renderer.render(scene: scene, deltaTime: step, to: target, in: buffer)
        buffer.commit()
        buffer.waitUntilCompleted()
        let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
        renderer.noteFrameCost(gpuSeconds: ms / 1000)
        recent.append(ms)
        if recent.count > 120 { recent.removeFirst() }
    }
    recent.sort()
    let settled = recent[recent.count / 2]
    let interval = 1000.0 / GargantuaRenderer.framesPerSecond
    print(
        String(
            format: "\nadaptive settles at: scale %.2f   %.1f ms/frame   %.0f%% of a %.0f ms frame",
            renderer.renderScale, settled, settled / interval * 100, interval))
    return true
}

if runBenchmark() { exit(0) }
if renderThumbnail() { exit(0) }

let app = NSApplication.shared
let delegate = PreviewAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
