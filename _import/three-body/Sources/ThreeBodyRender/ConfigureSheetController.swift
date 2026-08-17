import AppKit
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

    private var accuracyPopUp: NSPopUpButton!
    /// Parallel to `sliderSpecs`; a slider's `tag` is its index here.
    private var sliderControls: [(slider: NSSlider, label: NSTextField)] = []
    private var hudCheck: NSButton!
    private var playbackCheck: NSButton!
    private var glowCheck: NSButton!
    private var starsCheck: NSButton!
    private var modeButtons: [NSButton] = []
    private var modeExplanation: NSTextField!

    public init(store: SettingsStore, onCommit: @escaping (SimulationSettings) -> Void) {
        self.store = store
        self.working = store.settings
        self.onCommit = onCommit
        super.init()
    }

    public private(set) lazy var window: NSWindow = makeWindow()

    // MARK: - Construction

    private func makeWindow() -> NSWindow {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let headerBox = header(
            "Three-Body Problem",
            subtitle: "Newtonian gravity, integrated with a "
                + "time-symmetric adaptive symplectic method.")
        content.addArrangedSubview(headerBox)
        headerBox.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40)
            .isActive = true

        // Scene mode
        let modeBox = NSStackView()
        modeBox.orientation = .vertical
        modeBox.alignment = .leading
        modeBox.spacing = 6
        modeBox.addArrangedSubview(sectionLabel("Scenes"))
        for mode in SceneMode.allCases {
            let button = NSButton(
                radioButtonWithTitle: mode.displayName,
                target: self, action: #selector(modeChanged(_:)))
            button.tag = SceneMode.allCases.firstIndex(of: mode) ?? 0
            button.state = working.mode == mode ? .on : .off
            modeButtons.append(button)
            modeBox.addArrangedSubview(button)
        }
        modeExplanation = NSTextField(wrappingLabelWithString: working.mode.explanation)
        modeExplanation.font = NSFont.systemFont(ofSize: 11)
        modeExplanation.textColor = .secondaryLabelColor
        modeExplanation.preferredMaxLayoutWidth = 0
        modeBox.addArrangedSubview(modeExplanation)
        content.addArrangedSubview(modeBox)
        modeBox.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40)
            .isActive = true

        let topSeparator = separator()
        content.addArrangedSubview(topSeparator)

        // Numeric controls, aligned in a grid.
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        accuracyPopUp = NSPopUpButton()
        accuracyPopUp.addItems(withTitles: Accuracy.allCases.map { $0.displayName })
        accuracyPopUp.selectItem(at: Accuracy.allCases.firstIndex(of: working.accuracy) ?? 1)
        accuracyPopUp.target = self
        accuracyPopUp.action = #selector(accuracyChanged(_:))
        accuracyPopUp.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        grid.addRow(with: [fieldLabel("Integrator"), accuracyPopUp, NSGridCell.emptyContentView])

        for (index, spec) in Self.sliderSpecs.enumerated() {
            let control = slider(spec: spec, value: working[keyPath: spec.keyPath])
            control.tag = index
            let label = valueLabel()
            sliderControls.append((control, label))
            grid.addRow(with: [fieldLabel(spec.title), control, label])
        }

        content.addArrangedSubview(grid)
        let bottomSeparator = separator()
        content.addArrangedSubview(bottomSeparator)

        playbackCheck = NSButton(
            checkboxWithTitle: "Slow down through close encounters",
            target: self, action: #selector(toggleChanged(_:)))
        playbackCheck.state = working.adaptivePlayback ? .on : .off
        content.addArrangedSubview(playbackCheck)

        hudCheck = NSButton(
            checkboxWithTitle: "Show readout (orbit name, energy drift)",
            target: self, action: #selector(toggleChanged(_:)))
        hudCheck.state = working.showHUD ? .on : .off
        glowCheck = NSButton(
            checkboxWithTitle: "Glow around bodies",
            target: self, action: #selector(toggleChanged(_:)))
        glowCheck.state = working.showGlow ? .on : .off
        starsCheck = NSButton(
            checkboxWithTitle: "Background stars",
            target: self, action: #selector(toggleChanged(_:)))
        starsCheck.state = working.showStars ? .on : .off
        content.addArrangedSubview(hudCheck)
        content.addArrangedSubview(glowCheck)
        content.addArrangedSubview(starsCheck)

        // Buttons
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(commit(_:)))
        ok.keyEquivalent = "\r"
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(ok)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(buttons)

        // Pin everything that should reach both margins to the content width.
        // The slider column has no width of its own and absorbs whatever slack
        // the sheet's actual width leaves, so the value column stays put
        // against the right margin at any size.
        for stretched in [buttons, grid, topSeparator, bottomSeparator] {
            stretched.widthAnchor.constraint(
                equalTo: content.widthAnchor,
                constant: -40
            ).isActive = true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.title = "Three-Body Problem"
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)

        refreshLabels()
        return window
    }

    // MARK: - Small builders

    private func header(_ title: String, subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .semibold)

        let subtitleField = NSTextField(wrappingLabelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        // Wrap to whatever width the sheet actually gets, like the mode
        // explanation below it, rather than to a width guessed here.
        subtitleField.preferredMaxLayoutWidth = 0

        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(subtitleField)
        return stack
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return field
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 92).isActive = true
        return field
    }

    private func valueLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 66).isActive = true
        return field
    }

    private func slider(spec: SliderSpec, value: Double) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: spec.range.lowerBound,
            maxValue: spec.range.upperBound,
            target: self,
            action: #selector(sliderChanged(_:)))
        slider.isContinuous = true
        // Deliberately no width: this is the column that absorbs slack, so the
        // fixed label and value columns keep their alignment at any sheet width.
        slider.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        return slider
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
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
        modeExplanation.stringValue = working.mode.explanation
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
        working.adaptivePlayback = playbackCheck.state == .on
        working.showHUD = hudCheck.state == .on
        working.showGlow = glowCheck.state == .on
        working.showStars = starsCheck.state == .on
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
        working = store.settings
        close()
    }

    private func close() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}
