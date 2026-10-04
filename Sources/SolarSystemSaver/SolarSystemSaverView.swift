import AppKit
import Foundation
import SaverKit
import ScreenSaver
import SolarSystemCore
import SolarSystemRender
import os.log

/// The screensaver entry point.
///
/// `@objc(SolarSystemSaverView)` fixes the Objective-C class name so Info.plist can
/// name `NSPrincipalClass` as a bare `SolarSystemSaverView` rather than a Swift-mangled
/// or module-qualified symbol.
@objc(SolarSystemSaverView)
public final class SolarSystemSaverView: ScreenSaverView {

    /// The storage contract lives with `ScalePreset`, since the raw values are half of
    /// it. Also settable from a terminal — see Scripts/scale-mode.sh.
    private static let log = OSLog(
        subsystem: ScalePreset.Preference.domain, category: "preferences"
    )

    /// Mirrored into standard defaults as well as the module's ByHost store —
    /// see `SaverPreferences`, which is where this project's version of this
    /// workaround now lives so every saver gets it.
    private static let preferences = SaverPreferences(
        moduleIdentifier: ScalePreset.Preference.domain)

    /// Read and written through two stores.
    ///
    /// `ScreenSaverDefaults` is the documented mechanism and works fine in a normal
    /// process, but the options sheet is presented from a sandboxed host and a write
    /// there is not guaranteed to land. Mirroring into standard defaults costs nothing
    /// and means the setting survives even when the ByHost write is refused.
    public static var scalePreset: ScalePreset {
        get {
            // Clamped to what is actually offered, so a preference left behind by a
            // preset that is no longer selectable falls back rather than sticking.
            for raw in [preferences.string(forKey: ScalePreset.Preference.key)] {
                if let raw, let p = ScalePreset(rawValue: raw),
                    ScalePreset.selectable.contains(p)
                {
                    return p
                }
            }
            return .stylised
        }
        set {
            preferences.set(newValue.rawValue, forKey: ScalePreset.Preference.key)
            preferences.synchronize()
            os_log(
                "scaleMode set to %{public}@, reads back %{public}@",
                log: log, type: .info, newValue.rawValue, scalePreset.rawValue)
        }
    }

    private var sceneView: SolarSystemSceneView?
    private var configWindow: NSWindow?
    private var lifecycle: SaverLifecycle?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // SceneKit drives its own display link, so this timer only needs to exist, not
        // to be fast. A slow interval keeps the legacyScreenSaver host quiet.
        let lifecycle = SaverLifecycle(view: self, frameInterval: 1.0 / 5.0) {
            [weak self] in self?.stopAnimation()
        }
        lifecycle.onChange = { [weak self] in self?.applyPacing() }
        self.lifecycle = lifecycle
        installSceneView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SolarSystemSaverView is instantiated by ScreenSaverEngine, not a nib")
    }

    /// Builds the scene, starting from today's date, unless one is already up.
    ///
    /// Parked rather than playing: a playing `SCNView` runs its own display link
    /// the moment it is in a window, whatever the host has or has not asked for,
    /// so it waits for `startAnimation` like every other saver here.
    private func installSceneView() {
        guard sceneView == nil else { return }
        // System Settings creates a second live instance for its preview thumbnail.
        let quality: RenderQuality = isPreview ? .preview : .full
        var config = Self.scalePreset.config()
        config.trailSamples = quality.trailSamples

        let start = Date()
        let renderer = SolarSystemRenderer(
            model: DisplayModel(config: config, epoch: start), startDate: start
        )
        Self.scalePreset.apply(to: renderer)
        let view = SolarSystemSceneView(renderer: renderer, frame: bounds, quality: quality)
        view.isPlaying = false
        addSubview(view)
        sceneView = view
    }

    /// Plays only while there is someone to see it, at the rate the lifecycle asks for.
    private func applyPacing() {
        guard let sceneView, let lifecycle else { return }
        let playing = isAnimating && !lifecycle.isSuspended
        if sceneView.isPlaying != playing { sceneView.isPlaying = playing }
        let fps = Int(lifecycle.framesPerSecond)
        if sceneView.preferredFramesPerSecond != fps { sceneView.preferredFramesPerSecond = fps }
    }

    // ScreenSaverView's timer. SceneKit already redraws on its own display link, so
    // there is no drawing to do per tick — only checking that it should still be
    // drawing at all, which is cheap at this interval.
    public override func animateOneFrame() {
        applyPacing()
    }

    public override func startAnimation() {
        super.startAnimation()
        installSceneView()
        applyPacing()
    }

    /// Takes the whole scene down, not just the display link. An `SCNView` with HDR,
    /// bloom and 4x multisampling holds well over a hundred megabytes of render
    /// targets at Retina resolution, and the host keeps a stopped view alive
    /// indefinitely — see `SaverLifecycle`. The next start builds a fresh one, from
    /// that day's date.
    public override func stopAnimation() {
        super.stopAnimation()
        sceneView?.isPlaying = false
        sceneView?.removeFromSuperview()
        sceneView = nil
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        sceneView?.frame = bounds
    }

    // MARK: - Options sheet

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        // Always a fresh window.
        //
        // Caching one and handing the same instance back looks like an optimisation and
        // is a bug: the host can dismiss the sheet its own way — Escape, clicking away —
        // without our Done action ever running, and the next Options click then gets a
        // window that has already been ended. It fails to present, and the picker looks
        // broken from then on. Rebuilding also means the selection always reflects the
        // preference as it stands right now.
        configWindow?.orderOut(nil)

        // One line of description per row, so the rows are shallow.
        let rowHeight = 40
        let height = 40 + rowHeight * ScalePreset.selectable.count
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: CGFloat(height)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: window.contentLayoutRect)
        let current = Self.scalePreset

        for (index, preset) in ScalePreset.selectable.enumerated() {
            let y = height - 30 - rowHeight * index
            let radio = NSButton(
                radioButtonWithTitle: preset.title,
                target: self,
                action: #selector(selectPreset(_:))
            )
            radio.frame = NSRect(x: 18, y: CGFloat(y), width: 344, height: 18)
            radio.state = (preset == current) ? .on : .off
            radio.tag = index
            content.addSubview(radio)

            let blurb = NSTextField(wrappingLabelWithString: preset.blurb)
            blurb.frame = NSRect(x: 37, y: CGFloat(y - 17), width: 326, height: 15)
            blurb.font = .systemFont(ofSize: 11)
            blurb.textColor = .secondaryLabelColor
            content.addSubview(blurb)
        }

        let done = NSButton(title: "Done", target: self, action: #selector(closeConfigureSheet(_:)))
        done.frame = NSRect(x: 280, y: 10, width: 84, height: 28)
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        content.addSubview(done)

        window.contentView = content
        configWindow = window
        return window
    }

    /// Written the moment a choice is clicked rather than on Done, so the setting
    /// persists however the host chooses to dismiss the sheet.
    @objc private func selectPreset(_ sender: NSButton) {
        guard ScalePreset.selectable.indices.contains(sender.tag) else { return }
        Self.scalePreset = ScalePreset.selectable[sender.tag]
    }

    @objc private func closeConfigureSheet(_ sender: NSButton) {
        guard let window = configWindow else { return }
        // The host presents this as a sheet; end it through its parent when there is one.
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
        configWindow = nil
    }
}
