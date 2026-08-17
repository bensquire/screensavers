import AppKit
import SaverKit
import VortexCore

/// The options sheet System Settings shows for the vortex.
public final class VortexConfigureSheet: NSObject {

    private let store: VortexSettingsStore
    private var working: VortexSettings
    /// Called when the user commits, so the running view can pick the change up.
    private let onCommit: (VortexSettings) -> Void

    private struct SliderSpec {
        let title: String
        let range: ClosedRange<Double>
        let keyPath: WritableKeyPath<VortexSettings, Double>
        let format: (Double) -> String
    }

    private static let sliderSpecs: [SliderSpec] = [
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

    /// Parallel to `sliderSpecs`; a slider's `tag` is its index here.
    private var sliderControls: [(slider: NSSlider, label: NSTextField)] = []
    private var lightningCheck: NSButton!

    public init(store: VortexSettingsStore, onCommit: @escaping (VortexSettings) -> Void) {
        self.store = store
        self.working = store.settings
        self.onCommit = onCommit
        super.init()
    }

    public private(set) lazy var window: NSWindow = makeWindow()

    private func makeWindow() -> NSWindow {
        let sheet = OptionsSheet(
            title: "Sliders Vortex",
            subtitle: "A tunnel of drifting light, with the occasional discharge "
                + "down the wall.")

        let grid = OptionsSheet.grid()
        for (index, spec) in Self.sliderSpecs.enumerated() {
            let slider = OptionsSheet.slider(
                value: working[keyPath: spec.keyPath], range: spec.range,
                target: self, action: #selector(sliderChanged(_:)))
            slider.tag = index
            let label = OptionsSheet.valueLabel()
            sliderControls.append((slider, label))
            grid.addRow(with: [OptionsSheet.fieldLabel(spec.title), slider, label])
        }
        sheet.add(grid, stretched: true)
        sheet.addSeparator()

        lightningCheck = NSButton(
            checkboxWithTitle: "Lightning", target: self, action: #selector(toggleChanged(_:)))
        lightningCheck.state = working.lightning ? .on : .off
        sheet.add(lightningCheck)

        let note = NSTextField(
            wrappingLabelWithString:
                "Density trades a fuller tunnel for fill rate. The particles are "
                + "evaluated on the GPU, so it costs no processor time either way.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 0
        sheet.add(note, stretched: true)

        let window = sheet.makeWindow(
            title: "Sliders Vortex", target: self,
            cancel: #selector(cancel(_:)), commit: #selector(commit(_:)))
        refreshLabels()
        return window
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        let spec = Self.sliderSpecs[sender.tag]
        working[keyPath: spec.keyPath] = sender.doubleValue
        refreshLabels()
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        working.lightning = lightningCheck.state == .on
    }

    private func refreshLabels() {
        for (index, spec) in Self.sliderSpecs.enumerated() where index < sliderControls.count {
            sliderControls[index].label.stringValue = spec.format(working[keyPath: spec.keyPath])
        }
    }

    @objc private func commit(_ sender: Any?) {
        store.settings = working
        onCommit(store.settings)
        OptionsSheet.close(window)
    }

    @objc private func cancel(_ sender: Any?) {
        working = store.settings
        OptionsSheet.close(window)
    }
}
