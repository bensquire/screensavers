import AppKit
import GargantuaCore
import SaverKit

/// The options sheet System Settings shows for the black hole.
public final class GargantuaConfigureSheet: NSObject {

    private let store: GargantuaSettingsStore
    private var working: GargantuaSettings
    private let onCommit: (GargantuaSettings) -> Void

    private struct SliderSpec {
        let title: String
        let range: ClosedRange<Double>
        let keyPath: WritableKeyPath<GargantuaSettings, Double>
        let format: (Double) -> String
    }

    private static let sliderSpecs: [SliderSpec] = [
        SliderSpec(
            title: "Pace",
            range: GargantuaSettings.Limits.pace,
            keyPath: \.pace,
            format: { String(format: "%.2f×", $0) }),
        SliderSpec(
            title: "Doppler beaming",
            range: GargantuaSettings.Limits.beaming,
            keyPath: \.beaming,
            format: { String(format: "%.0f%%", $0 * 100) }),
        SliderSpec(
            title: "Stars",
            range: GargantuaSettings.Limits.stars,
            keyPath: \.stars,
            format: { String(format: "%.0f%%", $0 * 100) }),
        SliderSpec(
            title: "Render scale",
            range: GargantuaSettings.Limits.renderScale,
            keyPath: \.renderScale,
            format: { String(format: "%.0f%%", $0 * 100) }),
    ]

    /// Parallel to `sliderSpecs`; a slider's `tag` is its index here.
    private var sliderControls: [(slider: NSSlider, label: NSTextField)] = []
    private var adaptiveCheck: NSButton!

    public init(store: GargantuaSettingsStore, onCommit: @escaping (GargantuaSettings) -> Void) {
        self.store = store
        self.working = store.settings
        self.onCommit = onCommit
        super.init()
    }

    public private(set) lazy var window: NSWindow = makeWindow()

    private func makeWindow() -> NSWindow {
        let sheet = OptionsSheet(
            title: "Gargantua",
            subtitle: "A spinning black hole, ray-traced per pixel. Light paths are "
                + "real null geodesics integrated in Kerr-Schild coordinates.")

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

        adaptiveCheck = NSButton(
            checkboxWithTitle: "Adapt render scale to hold 60fps",
            target: self, action: #selector(toggleChanged(_:)))
        adaptiveCheck.state = working.adaptiveResolution ? .on : .off
        sheet.add(adaptiveCheck)

        let note = NSTextField(
            wrappingLabelWithString:
                "Every pixel integrates a light path through curved spacetime, so cost "
                + "scales with resolution. Left to adapt, the scale is driven to hold the "
                + "frame rate; fixed, the slider above decides it.\n\n"
                + "Doppler beaming is the bright-limb/dim-limb asymmetry a real orbiting "
                + "disk shows. Interstellar dropped it because it broke the shot, so it is "
                + "off by default — the gravitational redshift, which is just as real, is "
                + "always on.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 0
        sheet.add(note, stretched: true)

        let window = sheet.makeWindow(
            title: "Gargantua", target: self,
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
        working.adaptiveResolution = adaptiveCheck.state == .on
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
