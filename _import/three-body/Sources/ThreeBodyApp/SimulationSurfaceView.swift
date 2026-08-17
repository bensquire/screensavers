import AppKit
import ThreeBodyCore
import ThreeBodyRender

/// The preview app's canvas: the same engine and renderer the screensaver uses,
/// driven by a timer instead of by `ScreenSaverView`.
final class SimulationSurfaceView: NSView {

    let engine: SimulationEngine
    private let renderer = Renderer()
    private var timer: Timer?
    private var frameClock = FrameClock()

    init(frame: NSRect, settings: SimulationSettings) {
        self.engine = SimulationEngine(settings: settings)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func start() {
        stop()
        frameClock.reset()
        let timer = Timer(timeInterval: FrameClock.frameInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Keep animating while menus are tracking or the window is resizing.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        engine.update(
            deltaTime: frameClock.tick(),
            viewSize: (width: Double(bounds.width), height: Double(bounds.height)))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        renderer.draw(
            engine: engine,
            in: ctx,
            size: bounds.size,
            time: CACurrentMediaTime(),
            showHUD: engine.settings.showHUD)
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ", "n":
            engine.advanceToNextScene()
        case "h":
            engine.settings.showHUD.toggle()
        case "g":
            engine.settings.showGlow.toggle()
        case "f":
            window?.toggleFullScreen(nil)
        case "q":
            NSApp.terminate(nil)
        default:
            super.keyDown(with: event)
        }
    }
}
