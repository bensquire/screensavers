import AppKit
import GargantuaCore
import SaverKit

/// The options sheet System Settings shows for the black hole.
public final class GargantuaConfigureSheet: NSObject {

    private let store: GargantuaSettingsStore
    private var working: GargantuaSettings
    private let onCommit: (GargantuaSettings) -> Void

    private static let sliderSpecs: [SliderSpec<GargantuaSettings>] = [
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

    private lazy var sliders = SliderGrid<GargantuaSettings>(specs: Self.sliderSpecs) {
        [weak self] keyPath, value in
        self?.working[keyPath: keyPath] = value
    }

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
        sliders.install(in: grid, settings: working)
        sheet.add(grid, stretched: true)
        sheet.addSeparator()

        let adaptive = NSButton(
            checkboxWithTitle: "Adapt render scale to hold 60fps",
            target: self, action: #selector(toggleChanged(_:)))
        adaptive.state = working.adaptiveResolution ? .on : .off
        sheet.add(adaptive)

        sheet.add(
            OptionsSheet.note(
                "Every pixel integrates a light path through curved spacetime, so cost "
                    + "scales with resolution. Left to adapt, the scale is driven to hold "
                    + "the frame rate; fixed, the slider above decides it.\n\n"
                    + "Doppler beaming is the bright-limb/dim-limb asymmetry a real "
                    + "orbiting disk shows. Interstellar dropped it because it broke the "
                    + "shot, so it is off by default — the gravitational redshift, which "
                    + "is just as real, is always on."),
            stretched: true)

        return sheet.makeWindow(
            title: "Gargantua", target: self,
            cancel: #selector(cancel(_:)), commit: #selector(commit(_:)))
    }

    // MARK: - Actions

    @objc private func toggleChanged(_ sender: NSButton) {
        working.adaptiveResolution = sender.state == .on
    }

    @objc private func commit(_ sender: Any?) {
        store.settings = working
        onCommit(store.settings)
        OptionsSheet.close(window)
    }

    @objc private func cancel(_ sender: Any?) {
        working = store.settings
        sliders.refresh(working)
        OptionsSheet.close(window)
    }
}
