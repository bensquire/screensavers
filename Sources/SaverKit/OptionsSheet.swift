import AppKit

/// Builds the options window System Settings shows for a screensaver.
///
/// Sheets are assembled in code rather than from a nib, so every saver was
/// otherwise going to repeat the same header, the same label columns, and the
/// same OK/Cancel row. More to the point it was going to repeat the same
/// mistake: System Settings presents the sheet *wider* than its `fittingSize`,
/// so anything laid out from intrinsic widths ends up with its right-hand column
/// stranded in the middle of the window. Everything added through `add(…,
/// stretched: true)` is pinned to the content width instead, which is what keeps
/// value labels against the right margin at whatever size the host chooses.
public final class OptionsSheet {

    /// Horizontal inset applied on both sides, so stretched rows are pinned to
    /// the content width less this much on each side.
    private static let margin: CGFloat = 20

    /// The sheet's width, fixed.
    ///
    /// It has to be pinned rather than derived. A wrapping label asked for its
    /// fitting size with no width to wrap against reports the width of its text
    /// on ONE line, and since the rows are pinned to the content's width, that
    /// propagates outward and sets the width of the whole sheet — which is how
    /// a sheet with a long explanatory paragraph came out 1167pt wide.
    public static let contentWidth: CGFloat = 460

    /// Width available to a row once both margins are taken off. Wrapping text
    /// is given this explicitly, for the same reason.
    public static let bodyWidth: CGFloat = contentWidth - margin * 2

    public let content: NSStackView

    public init(title: String, subtitle: String) {
        content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(
            top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin)
        content.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        header.addArrangedSubview(titleField)

        let subtitleField = NSTextField(wrappingLabelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.preferredMaxLayoutWidth = Self.bodyWidth
        header.addArrangedSubview(subtitleField)

        add(header, stretched: true)
    }

    /// Adds a row. `stretched` pins it to both margins — use it for anything with
    /// a right-hand edge that should stay put: grids, separators, wrapping text.
    public func add(_ view: NSView, stretched: Bool = false) {
        content.addArrangedSubview(view)
        if stretched {
            view.widthAnchor.constraint(
                equalTo: content.widthAnchor, constant: -Self.margin * 2
            ).isActive = true
        }
    }

    public func addSeparator() {
        let box = NSBox()
        box.boxType = .separator
        add(box, stretched: true)
    }

    /// Wraps the sheet up with a right-aligned Cancel/OK row and returns the
    /// window. Escape cancels and Return commits, as in any other sheet.
    public func makeWindow(
        title: String,
        target: AnyObject,
        cancel: Selector,
        commit: Selector
    ) -> NSWindow {
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cancelButton = NSButton(title: "Cancel", target: target, action: cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        let okButton = NSButton(title: "OK", target: target, action: commit)
        okButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(okButton)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        add(buttons, stretched: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 620),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.title = title
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        return window
    }

    /// Dismisses whether the window is a real sheet or a loose window, which
    /// differs between System Settings and running the saver standalone.
    public static func close(_ window: NSWindow) {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }

    // MARK: - Pieces

    public static func sectionLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return field
    }

    /// Width a label column needs to show all of `titles` without truncating.
    ///
    /// Every sheet has to size its column this way rather than guessing: a
    /// fixed 92pt silently clipped "Doppler beaming" and ran it under the
    /// slider beside it.
    public static func labelColumnWidth(fitting titles: [String]) -> CGFloat {
        let widths = titles.map { fieldLabel($0, width: nil).intrinsicContentSize.width }
        return max(minimumLabelWidth, widths.max() ?? 0).rounded(.up)
    }

    /// The left column of a grid row. A fixed width is what makes every row line
    /// up — pass `nil` to leave it unconstrained, which is how
    /// `labelColumnWidth(fitting:)` measures one.
    public static func fieldLabel(_ text: String, width: CGFloat? = minimumLabelWidth)
        -> NSTextField
    {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return field
    }

    /// Narrowest label column worth using, so a sheet of short titles still has
    /// its sliders lined up rather than jammed against the left margin.
    public static let minimumLabelWidth: CGFloat = 92

    /// The right column of a grid row: the current value of the control beside
    /// it. Monospaced digits so the text does not jitter as a slider moves.
    public static func valueLabel(width: CGFloat = 66) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    /// The middle column. Deliberately given no width: this is the control that
    /// absorbs whatever slack the sheet's real width leaves, which is what keeps
    /// the fixed columns either side of it aligned.
    public static func slider(
        value: Double,
        range: ClosedRange<Double>,
        target: AnyObject,
        action: Selector
    ) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: target,
            action: action)
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        return slider
    }

    public static func grid() -> NSGridView {
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    /// A wrapping paragraph of secondary text, for explaining what a control
    /// actually does.
    public static func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = bodyWidth
        return field
    }
}

/// One numeric setting: what it is called, the range it may take, where it lives
/// in `Settings`, and how its value reads.
public struct SliderSpec<Settings> {
    public let title: String
    public let range: ClosedRange<Double>
    public let keyPath: WritableKeyPath<Settings, Double>
    public let format: (Double) -> String

    public init(
        title: String,
        range: ClosedRange<Double>,
        keyPath: WritableKeyPath<Settings, Double>,
        format: @escaping (Double) -> String
    ) {
        self.title = title
        self.range = range
        self.keyPath = keyPath
        self.format = format
    }
}

/// Builds a grid of labelled sliders and keeps their value labels in step.
///
/// Every saver's sheet was otherwise repeating the same three things: a spec
/// list, an array of controls indexed by `slider.tag`, and a refresh loop. The
/// tag-to-spec correspondence was a convention each copy had to get right —
/// here it is the type's own invariant, which is why there is no defensive
/// bounds check.
public final class SliderGrid<Settings>: NSObject {

    private let specs: [SliderSpec<Settings>]
    private var labels: [NSTextField] = []
    private let onChange: (WritableKeyPath<Settings, Double>, Double) -> Void

    /// - Parameter onChange: called with the setting that moved and its new
    ///   value, so the owner keeps sole possession of the settings struct.
    public init(
        specs: [SliderSpec<Settings>],
        onChange: @escaping (WritableKeyPath<Settings, Double>, Double) -> Void
    ) {
        self.specs = specs
        self.onChange = onChange
        super.init()
    }

    /// Adds one row per spec to `grid`, reading initial values from `settings`.
    public func install(in grid: NSGridView, settings: Settings) {
        let column = OptionsSheet.labelColumnWidth(fitting: specs.map(\.title))

        for (index, spec) in specs.enumerated() {
            let slider = OptionsSheet.slider(
                value: settings[keyPath: spec.keyPath], range: spec.range,
                target: self, action: #selector(sliderMoved(_:)))
            slider.tag = index
            let label = OptionsSheet.valueLabel()
            labels.append(label)
            grid.addRow(with: [
                OptionsSheet.fieldLabel(spec.title, width: column), slider, label,
            ])
        }
        refresh(settings)
    }

    /// Rewrites every value label from `settings`.
    public func refresh(_ settings: Settings) {
        for (index, spec) in specs.enumerated() {
            labels[index].stringValue = spec.format(settings[keyPath: spec.keyPath])
        }
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let spec = specs[sender.tag]
        // The label is this type's own business, so the owner is not obliged to
        // call back into it — which would make the two mutually dependent.
        labels[sender.tag].stringValue = spec.format(sender.doubleValue)
        onChange(spec.keyPath, sender.doubleValue)
    }
}
