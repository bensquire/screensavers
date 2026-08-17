import AppKit
import GargantuaCore
import GargantuaRender
import SaverKit
import ScreenSaver

/// The screensaver entry point. `NSPrincipalClass` in Info.plist names this
/// class, so the `@objc` name must stay exactly as written — Swift's mangled
/// name would not be found by the loader.
@objc(GargantuaView)
final class GargantuaView: ScreenSaverView {

    private let store: GargantuaSettingsStore
    private var frameClock: FrameClock
    /// Nil only if Metal is unavailable, in which case the view stays black
    /// rather than taking the screensaver host down with it.
    private var blackHole: GargantuaMetalView?

    private lazy var configController = GargantuaConfigureSheet(store: store) {
        [weak self] settings in
        self?.rebuild(with: settings)
    }

    override init?(frame: NSRect, isPreview: Bool) {
        let identifier =
            Bundle(for: GargantuaView.self).bundleIdentifier
            ?? GargantuaSettingsStore.bundleIdentifier
        self.store = GargantuaSettingsStore(
            defaults: SaverPreferences(moduleIdentifier: identifier))
        self.frameClock = FrameClock(nominalInterval: 1.0 / GargantuaRenderer.framesPerSecond)

        super.init(frame: frame, isPreview: isPreview)

        animationTimeInterval = 1.0 / GargantuaRenderer.framesPerSecond
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        rebuild(with: Self.settings(from: store, isPreview: isPreview))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — the module is instantiated by frame")
    }

    override var isOpaque: Bool { true }

    private static func settings(
        from store: GargantuaSettingsStore, isPreview: Bool
    ) -> GargantuaSettings {
        var settings = store.settings
        if isPreview {
            // The tile is a couple of hundred points across, so it can afford to
            // march every pixel — and the adaptive controller needs sixty frames
            // before it does anything, which a preview may never reach.
            settings.adaptiveResolution = false
            settings.renderScale = 1.0
        }
        return settings
    }

    /// Replaces the Metal view. Settings feed both the render targets' sizes and
    /// the scene's parameters, so a change starts a fresh one.
    private func rebuild(with settings: GargantuaSettings) {
        blackHole?.removeFromSuperview()
        blackHole = nil

        guard let view = try? GargantuaMetalView(frame: bounds, settings: settings) else { return }
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        blackHole = view
    }

    override func startAnimation() {
        frameClock.reset()
        rebuild(with: Self.settings(from: store, isPreview: isPreview))
        super.startAnimation()
    }

    override func animateOneFrame() {
        super.animateOneFrame()
        blackHole?.advance(deltaTime: frameClock.tick())
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? { configController.window }
}
