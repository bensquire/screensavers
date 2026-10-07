import AppKit
import SaverKit
import ThreeBodyCore

/// The options sheet shown by System Settings, built in code so the bundle
/// needs no nib.
public final class ConfigureSheetController: NSObject {

    private let store: SettingsStore
    private var working: SimulationSettings
    /// Called when the user commits changes, so the live view can pick them up.
    private let onCommit: (SimulationSettings) -> Void

    /// One numeric setting: what it is called, the range it may take, how its
    /// value reads, and where it lives in `SimulationSettings`. Adding a
    /// setting means adding one row here and nothing else.
    private struct SliderSpec {
        let title: String
        let range: ClosedRange<Double>
        let keyPath: WritableKeyPath<SimulationSettings, Double>
        let format: (Double) -> String
    }

    private static let sliderSpecs: [SliderSpec] = [
        SliderSpec(
            title: "Speed",
            range: SimulationSettings.Limits.speed,
            keyPath: \.speed,
            format: { String(format: "%.2f×", $0) }),
        SliderSpec(
            title: "Trail length",
            range: SimulationSettings.Limits.trailSeconds,
            keyPath: \.trailSeconds,
            format: { String(format: "%.1f s", $0) }),
        SliderSpec(
            title: "Scene length",
            range: SimulationSettings.Limits.sceneDuration,
            keyPath: \.sceneDuration,
            format: { String(format: "%.0f s", $0) }),
        SliderSpec(
            title: "Star density",
            range: SimulationSettings.Limits.starDensity,
            keyPath: \.starDensity,
            format: { String(format: "%.0f%%", $0 * 100) }),
    ]

    /// One on/off setting, in the order the checkboxes are shown; a checkbox's
    /// `tag` is its index here.
    private static let toggleSpecs: [(title: String, keyPath: WritableKeyPath<SimulationSettings, Bool>)] = [
        ("Slow down through close encounters", \.adaptivePlayback),
        ("Show readout (orbit name, energy drift)", \.showHUD),
        ("Glow around bodies", \.showGlow),
        ("Background stars", \.showStars),
    ]

    /// Parallel to `sliderSpecs`; a slider's `tag` is its index here.
    private var sliderControls: [(slider: NSSlider, label: NSTextField)] = []
    private var modeButtons: [NSButton] = []
    private var modeExplanation: NSTextField?

    public init(store: SettingsStore, onCommit: @escaping (SimulationSettings) -> Void) {
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

    private var shown: NSWindow?

    // MARK: - Construction

    private func makeWindow() -> NSWindow {
        modeButtons = []
        sliderControls = []
        let sheet = OptionsSheet(
            title: "Three-Body Problem",
            subtitle: "Newtonian gravity, integrated with a "
                + "time-symmetric adaptive symplectic method.")

        // Scene mode
        let modeBox = NSStackView()
        modeBox.orientation = .vertical
        modeBox.alignment = .leading
        modeBox.spacing = 6
        modeBox.addArrangedSubview(OptionsSheet.sectionLabel("Scenes"))
        for mode in SceneMode.allCases {
            let button = NSButton(
                radioButtonWithTitle: mode.displayName,
                target: self, action: #selector(modeChanged(_:)))
            button.tag = SceneMode.allCases.firstIndex(of: mode) ?? 0
            button.state = working.mode == mode ? .on : .off
            modeButtons.append(button)
            modeBox.addArrangedSubview(button)
        }
        let modeExplanation = NSTextField(wrappingLabelWithString: working.mode.explanation)
        modeExplanation.font = NSFont.systemFont(ofSize: 11)
        modeExplanation.textColor = .secondaryLabelColor
        modeExplanation.preferredMaxLayoutWidth = OptionsSheet.bodyWidth
        modeBox.addArrangedSubview(modeExplanation)
        self.modeExplanation = modeExplanation
        sheet.add(modeBox, stretched: true)

        sheet.addSeparator()

        // Numeric controls, aligned in a grid. The column is sized across the
        // popup's label as well as the sliders', since they share it — this
        // sheet builds its own rows rather than going through SliderGrid, so it
        // has to ask for the width explicitly.
        let grid = OptionsSheet.grid()
        let column = OptionsSheet.labelColumnWidth(
            fitting: ["Integrator"] + Self.sliderSpecs.map(\.title))

        let accuracyPopUp = NSPopUpButton()
        accuracyPopUp.addItems(withTitles: Accuracy.allCases.map { $0.displayName })
        accuracyPopUp.selectItem(at: Accuracy.allCases.firstIndex(of: working.accuracy) ?? 1)
        accuracyPopUp.target = self
        accuracyPopUp.action = #selector(accuracyChanged(_:))
        accuracyPopUp.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        grid.addRow(with: [
            OptionsSheet.fieldLabel("Integrator", width: column), accuracyPopUp,
            NSGridCell.emptyContentView,
        ])

        for (index, spec) in Self.sliderSpecs.enumerated() {
            let control = OptionsSheet.slider(
                value: working[keyPath: spec.keyPath], range: spec.range,
                target: self, action: #selector(sliderChanged(_:)))
            control.tag = index
            let label = OptionsSheet.valueLabel()
            sliderControls.append((control, label))
            grid.addRow(with: [
                OptionsSheet.fieldLabel(spec.title, width: column), control, label,
            ])
        }

        sheet.add(grid, stretched: true)
        sheet.addSeparator()

        for (index, toggle) in Self.toggleSpecs.enumerated() {
            let check = NSButton(
                checkboxWithTitle: toggle.title, target: self, action: #selector(toggleChanged(_:)))
            check.tag = index
            check.state = working[keyPath: toggle.keyPath] ? .on : .off
            sheet.add(check)
        }

        let window = sheet.makeWindow(
            title: "Three-Body Problem", target: self,
            cancel: #selector(cancel(_:)), commit: #selector(commit(_:)))
        refreshLabels()
        return window
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < SceneMode.allCases.count else { return }
        working.mode = SceneMode.allCases[sender.tag]
        // Radio buttons only auto-deselect within a shared superview; these are
        // in a stack view, so keep the group consistent explicitly.
        for button in modeButtons {
            button.state = button === sender ? .on : .off
        }
        modeExplanation?.stringValue = working.mode.explanation
    }

    @objc private func accuracyChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if index >= 0 && index < Accuracy.allCases.count {
            working.accuracy = Accuracy.allCases[index]
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let spec = Self.sliderSpecs[sender.tag]
        working[keyPath: spec.keyPath] = sender.doubleValue
        refreshLabels()
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < Self.toggleSpecs.count else { return }
        working[keyPath: Self.toggleSpecs[sender.tag].keyPath] = sender.state == .on
    }

    private func refreshLabels() {
        for (index, spec) in Self.sliderSpecs.enumerated() where index < sliderControls.count {
            sliderControls[index].label.stringValue = spec.format(working[keyPath: spec.keyPath])
        }
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
    }
}
