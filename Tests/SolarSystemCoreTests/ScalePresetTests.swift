import XCTest

@testable import SolarSystemRender

/// The screensaver's stored preference is a contract shared between Swift and a shell
/// script that has to work without a build. It cannot be imported there, so it is copied
/// — and it drifted once already. This asserts the copies still agree.
final class ScalePresetTests: XCTestCase {

    /// Throws, so a test that cannot read the script fails on that rather than
    /// on a misleading "cannot set" against an empty string.
    private func scriptSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SolarSystemCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Scripts/scale-mode.sh")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// A script writing to a different domain or key than the saver reads would
    /// report success and change nothing on screen.
    func testScriptUsesTheSameDomainAndKey() throws {
        let script = try scriptSource()
        XCTAssertTrue(
            script.contains("DOMAIN=\"\(ScalePreset.Preference.domain)\""),
            "Scripts/scale-mode.sh writes a different domain than \(ScalePreset.Preference.domain)")
        XCTAssertTrue(
            script.contains("KEY=\"\(ScalePreset.Preference.key)\""),
            "Scripts/scale-mode.sh writes a different key than \(ScalePreset.Preference.key)")
    }

    /// Every preset the screensaver offers must be reachable from the script, or a mode
    /// exists in the UI with no way to set it from a terminal.
    func testScriptCanSetEverySelectablePreset() throws {
        let script = try scriptSource()
        for preset in ScalePreset.selectable {
            XCTAssertTrue(
                script.contains("VALUE=\(preset.rawValue)"),
                "Scripts/scale-mode.sh cannot set '\(preset.rawValue)'"
            )
        }
    }

    /// The fallback key is derived, not restated.
    func testFallbackKeyIsDerived() {
        XCTAssertEqual(
            ScalePreset.Preference.fallbackKey,
            "\(ScalePreset.Preference.domain).\(ScalePreset.Preference.key)"
        )
    }

    /// True scale is a demonstration of why the compressed presets exist; offered
    /// as a screensaver it draws planets too small to see.
    func testSelectableExcludesTheDemonstrationPreset() {
        XCTAssertFalse(
            ScalePreset.selectable.contains(.trueScale), "true scale is offered as a screensaver mode")
        XCTAssertEqual(
            ScalePreset.selectable.count, 3, "\(ScalePreset.selectable.count) presets are offered, not 3")
    }
}
