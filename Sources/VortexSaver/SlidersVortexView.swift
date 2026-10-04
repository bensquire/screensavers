import AppKit
import SaverKit
import ScreenSaver
import VortexCore
import VortexRender
import os.log

private let log = OSLog(subsystem: "com.bensquire.SlidersVortex", category: "screensaver")

/// The screensaver entry point. `NSPrincipalClass` in Info.plist names this
/// class, so the `@objc` name must stay exactly as written — Swift's mangled
/// name would not be found by the loader.
@objc(SlidersVortexView)
final class SlidersVortexView: ScreenSaverView {

    private let store: VortexSettingsStore
    private var frameClock: FrameClock
    /// Nil only if Metal is unavailable, in which case the view stays black
    /// rather than taking the whole screensaver host down with it.
    private var tunnel: VortexMetalView?
    /// What the live view was built with, so an unchanged start does not
    /// rebuild it. Constructing one loads the shader library, builds every
    /// pipeline and generates its scene — far too much to do twice for nothing.
    private var builtWith: VortexSettings?

    private lazy var configController = VortexConfigureSheet(store: store) {
        [weak self] settings in
        guard let self else { return }
        // Only a running view is rebuilt. A stopped one has already handed its
        // GPU resources back and picks the new settings up when it next starts.
        guard self.tunnel != nil else { return }
        self.rebuild(with: Self.settings(from: settings, isPreview: self.isPreview))
    }

    /// Set in `init`, once there is a `self` for it to manage.
    private var lifecycle: SaverLifecycle!

    override init?(frame: NSRect, isPreview: Bool) {
        let identifier =
            Bundle(for: SlidersVortexView.self).bundleIdentifier
            ?? VortexSettingsStore.bundleIdentifier
        self.store = VortexSettingsStore(defaults: SaverPreferences(moduleIdentifier: identifier))
        self.frameClock = FrameClock(nominalInterval: FrameClock.frameInterval)

        super.init(frame: frame, isPreview: isPreview)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        lifecycle = SaverLifecycle(view: self, frameInterval: FrameClock.frameInterval) {
            [weak self] in self?.stopAnimation()
        }
        rebuild(with: Self.settings(from: store.settings, isPreview: isPreview))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — the module is instantiated by frame")
    }

    override var isOpaque: Bool { true }

    /// Stored settings, toned down for the System Settings thumbnail.
    private static func settings(
        from stored: VortexSettings, isPreview: Bool
    ) -> VortexSettings {
        var settings = stored
        if isPreview {
            // The tile is a couple of hundred points across, so the full field
            // reads as noise and costs more than the thumbnail is worth.
            settings.density *= 0.5
        }
        return settings
    }

    /// Replaces the Metal view. Needed rather than mutating one because the
    /// particle count decides the size of the GPU buffers.
    private func rebuild(with settings: VortexSettings) {
        guard settings != builtWith || tunnel == nil else { return }
        releaseView()

        let view: VortexMetalView
        do {
            view = try VortexMetalView(frame: bounds, settings: settings)
        } catch {
            // Staying black is a defensible policy on a machine without a
            // working GPU; being undiagnosable is not.
            os_log(
                "could not create the renderer: %{public}@", log: log, type: .error,
                String(describing: error))
            return
        }
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        tunnel = view
        builtWith = settings
    }

    override func startAnimation() {
        frameClock.reset()
        // Pick up anything changed in the options sheet since last time.
        rebuild(with: Self.settings(from: store.settings, isPreview: isPreview))
        super.startAnimation()
    }

    /// Gives the Metal view back as well as stopping the timer. It holds the
    /// particle buffers, the offscreen scene target and the drawables, and the
    /// host keeps a stopped view alive indefinitely; see `SaverLifecycle`.
    override func stopAnimation() {
        super.stopAnimation()
        releaseView()
    }

    private func releaseView() {
        tunnel?.removeFromSuperview()
        tunnel = nil
        builtWith = nil
    }

    override func animateOneFrame() {
        guard !lifecycle.isSuspended else { return }
        super.animateOneFrame()
        tunnel?.advance(deltaTime: frameClock.tick())
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? { configController.window }
}
