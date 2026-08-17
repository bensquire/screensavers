import XCTest

@testable import SolarSystemRender

/// The screensaver's stored preference is a contract shared between Swift and a shell
/// script that has to work without a build. It cannot be imported there, so it is copied
/// — and it drifted once already. This asserts the copies still agree.
final class ScalePresetTests: XCTestCase {

    private var scriptSource: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SolarSystemCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Scripts/scale-mode.sh")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testScriptUsesTheSameDomainAndKey() {
        let script = scriptSource
        XCTAssertFalse(script.isEmpty, "could not read Scripts/scale-mode.sh")
        XCTAssertTrue(script.contains("DOMAIN=\"\(ScalePreset.Preference.domain)\""))
        XCTAssertTrue(script.contains("KEY=\"\(ScalePreset.Preference.key)\""))
    }

    /// Every preset the screensaver offers must be reachable from the script, or a mode
    /// exists in the UI with no way to set it from a terminal.
    func testScriptCanSetEverySelectablePreset() {
        let script = scriptSource
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

    func testSelectableExcludesTheDemonstrationPreset() {
        XCTAssertFalse(ScalePreset.selectable.contains(.trueScale))
        XCTAssertEqual(ScalePreset.selectable.count, 3)
    }
}
