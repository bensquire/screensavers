import AppKit
import SaverKit
import ScreenSaver
import ThreeBodyCore
import ThreeBodyRender

/// The screensaver entry point. `NSPrincipalClass` in Info.plist names this
/// class, so the `@objc` name must stay exactly as written — Swift's mangled
/// name would not be found by the loader.
@objc(ThreeBodyProblemView)
final class ThreeBodyProblemView: ScreenSaverView {

    private let store: SettingsStore
    private let engine: SimulationEngine
    private let renderer = Renderer()
    private var frameClock = FrameClock()

    private lazy var configController = ConfigureSheetController(store: store) {
        [weak self] settings in
        self?.engine.settings = settings
    }

    override init?(frame: NSRect, isPreview: Bool) {
        // System Settings keeps each module's preferences in its own domain.
        let identifier =
            Bundle(for: ThreeBodyProblemView.self).bundleIdentifier
            ?? SettingsStore.bundleIdentifier
        self.store = SettingsStore(defaults: SaverPreferences(moduleIdentifier: identifier))

        self.engine = SimulationEngine(
            settings: Self.settings(from: store, isPreview: isPreview))

        super.init(frame: frame, isPreview: isPreview)

        renderer.uiScale = isPreview ? 0.5 : 1.0
        animationTimeInterval = FrameClock.softwareFrameInterval
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — the module is instantiated by frame")
    }

    override var isOpaque: Bool { true }

    /// Stored settings, toned down for the System Settings thumbnail. Static so
    /// `init` can use it before `super.init`, and so the two callers below
    /// cannot drift apart.
    private static func settings(
        from store: SettingsStore,
        isPreview: Bool
    ) -> SimulationSettings {
        var settings = store.settings
        if isPreview {
            // The thumbnail is a couple of hundred points wide; the readout
            // would be unreadable and the stars would look like noise.
            settings.showHUD = false
            settings.starDensity *= 0.6
        }
        return settings
    }

    override func startAnimation() {
        frameClock.reset()
        // Pick up any changes made in the options sheet since last time.
        engine.settings = Self.settings(from: store, isPreview: isPreview)
        super.startAnimation()
    }

    override func animateOneFrame() {
        super.animateOneFrame()

        engine.update(
            deltaTime: frameClock.tick(),
            viewSize: (width: Double(bounds.width), height: Double(bounds.height)))
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        renderer.draw(
            engine: engine,
            in: ctx,
            size: bounds.size,
            time: CACurrentMediaTime(),
            showHUD: engine.settings.showHUD)
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? { configController.window }
}
