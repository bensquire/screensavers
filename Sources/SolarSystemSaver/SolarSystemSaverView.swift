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

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // SceneKit drives its own display link, so this timer only needs to exist, not
        // to be fast. A slow interval keeps the legacyScreenSaver host quiet.
        animationTimeInterval = 1.0 / 5.0
        wantsLayer = true

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
        addSubview(view)
        sceneView = view
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SolarSystemSaverView is instantiated by ScreenSaverEngine, not a nib")
    }

    // ScreenSaverView's timer. SceneKit already redraws on its own display link, so
    // there is nothing to do per tick — overriding it empty avoids the default
    // implementation's needsDisplay churn on top of SceneKit's own loop.
    public override func animateOneFrame() {}

    public override func startAnimation() {
        super.startAnimation()
        sceneView?.isPlaying = true
    }

    public override func stopAnimation() {
        super.stopAnimation()
        sceneView?.isPlaying = false
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
