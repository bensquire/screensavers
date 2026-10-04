import AppKit
import SaverKit
import VortexCore

/// The options sheet System Settings shows for the vortex.
public final class VortexConfigureSheet: NSObject {

    private let store: VortexSettingsStore
    private var working: VortexSettings
    /// Called when the user commits, so the running view can pick the change up.
    private let onCommit: (VortexSettings) -> Void

    private static let sliderSpecs: [SliderSpec<VortexSettings>] = [
        SliderSpec(
            title: "Flow speed",
            range: VortexSettings.Limits.flowSpeed,
            keyPath: \.flowSpeed,
            format: { String(format: "%.2f×", $0) }),
        SliderSpec(
            title: "Density",
            range: VortexSettings.Limits.density,
            keyPath: \.density,
            format: { String(format: "%.0f%%", $0 * 100) }),
    ]

    /// The grid in the sheet now showing. Held here because it is its sliders'
    /// target, and a control does not retain its target.
    private var sliders: SliderGrid<VortexSettings>?
    private var shown: NSWindow?

    public init(store: VortexSettingsStore, onCommit: @escaping (VortexSettings) -> Void) {
        self.store = store
        self.working = store.settings
        self.onCommit = onCommit
        super.init()
    }

    /// A fresh sheet each time it is asked for, showing the settings as they are now.
    ///
    /// Built once and shown again, a sheet carries whatever it showed last time — a
    /// value dragged and then cancelled, or one saved since by another instance —
    /// into the next commit. And the host can dismiss it its own way, leaving a
    /// window that has already been ended. Solar System's sheet is rebuilt for the
    /// same reasons.
    public var window: NSWindow {
        working = store.settings
        let window = makeWindow()
        shown = window
        return window
    }

    private func makeWindow() -> NSWindow {
        let sheet = OptionsSheet(
            title: "Sliders Vortex",
            subtitle: "A tunnel of drifting light, with the occasional discharge "
                + "down the wall.")

        let grid = OptionsSheet.grid()
        let sliders = SliderGrid<VortexSettings>(specs: Self.sliderSpecs) {
            [weak self] keyPath, value in
            self?.working[keyPath: keyPath] = value
        }
        sliders.install(in: grid, settings: working)
        self.sliders = sliders
        sheet.add(grid, stretched: true)
        sheet.addSeparator()

        let lightning = NSButton(
            checkboxWithTitle: "Lightning", target: self, action: #selector(toggleChanged(_:)))
        lightning.state = working.lightning ? .on : .off
        sheet.add(lightning)

        sheet.add(
            OptionsSheet.note(
                "Density trades a fuller tunnel for fill rate. The particles are "
                    + "evaluated on the GPU, so it costs no processor time either way."),
            stretched: true)

        return sheet.makeWindow(
            title: "Sliders Vortex", target: self,
            cancel: #selector(cancel(_:)), commit: #selector(commit(_:)))
    }

    // MARK: - Actions

    @objc private func toggleChanged(_ sender: NSButton) {
        working.lightning = sender.state == .on
    }

    @objc private func commit(_ sender: Any?) {
        store.settings = working
        onCommit(store.settings)
        close()
    }

    @objc private func cancel(_ sender: Any?) {
        close()
    }

    private func close() {
        if let shown { OptionsSheet.close(shown) }
        shown = nil
        sliders = nil
    }
}
