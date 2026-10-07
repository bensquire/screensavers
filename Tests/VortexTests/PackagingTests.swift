import AppKit
import SaverKit
import XCTest

@testable import VortexRender

/// The shaders are compiled from source in tests and loaded from a `.metallib`
/// in the shipped bundle, so nothing else here exercises the packaged path. A
/// mismatch between what `Scripts/build-saver.sh` writes and what
/// `ShaderLibrary` looks for would leave the built saver drawing nothing, while
/// every other test passed.
final class PackagingTests: XCTestCase {

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // VortexTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
    }

    private func saverConf() throws -> [String: String] {
        let url = Self.repositoryRoot.appendingPathComponent("savers/vortex/saver.conf")
        let text = try String(contentsOf: url, encoding: .utf8)
        var settings: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, !parts[0].hasPrefix("#") else { continue }
            settings[String(parts[0])] =
                String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return settings
    }

    /// ShaderLibrary asks the bundle for "Vortex.metallib"; the build script names
    /// the output from METAL_LIBRARY. If they or the source path drift, the
    /// built saver draws nothing while every other test passes.
    func testTheBuildCompilesTheShaderTheLoaderLooksFor() throws {
        let conf = try saverConf()

        XCTAssertEqual(
            conf["METAL_LIBRARY"], ShaderLibrary.name,
            "saver.conf builds a differently-named metallib than ShaderLibrary loads")

        let source = try XCTUnwrap(conf["METAL_SOURCES"], "saver.conf has no METAL_SOURCES")
        let path = Self.repositoryRoot.appendingPathComponent(source)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "saver.conf points METAL_SOURCES at \(source), which does not exist")
    }

    /// The options sheet is built from a fixed width on purpose. A wrapping
    /// label asked for its fitting size with nothing to wrap against reports its
    /// text on one line, and since rows are pinned to the content width, that
    /// propagates outward — which is how Gargantua's sheet came out 1167pt wide,
    /// far too wide for System Settings to present.
    @MainActor
    func testTheOptionsSheetIsAWorkableSize() {
        let store = VortexSettingsStore(
            defaults: SaverPreferences(moduleIdentifier: "test.vortex.sheet"))
        let window = VortexConfigureSheet(store: store, onCommit: { _ in }).window
        XCTAssertEqual(
            window.frame.width, OptionsSheet.contentWidth, accuracy: 1,
            "the sheet is \(window.frame.width) pt wide")
        XCTAssertLessThan(
            window.frame.height, 600, "the sheet is \(window.frame.height) pt, too tall for a settings sheet")
        XCTAssertTrue(window.canBecomeKey, "a sheet that cannot become key never appears")
    }

    /// The slider label column is sized from the longest title; a fixed 92pt
    /// silently truncated "Doppler beaming" under the slider beside it.
    @MainActor
    func testSliderTitlesAreNotTruncated() {
        let store = VortexSettingsStore(
            defaults: SaverPreferences(moduleIdentifier: "test.vortex.labels"))
        let window = VortexConfigureSheet(store: store, onCommit: { _ in }).window
        window.contentView?.layoutSubtreeIfNeeded()

        func labels(_ view: NSView) -> [NSTextField] {
            if let field = view as? NSTextField { return [field] }
            return view.subviews.flatMap(labels)
        }
        let found = labels(window.contentView ?? NSView()).filter { !$0.stringValue.isEmpty }
        XCTAssertGreaterThan(found.count, 3, "found no labels — the check would be vacuous")
        for field in found {
            // Wrapping paragraphs are meant to be narrower than their one-line
            // width; only single-line labels must fit.
            guard field.maximumNumberOfLines == 1 else { continue }
            XCTAssertGreaterThanOrEqual(
                field.frame.width, field.intrinsicContentSize.width - 0.5,
                "'\(field.stringValue)' is clipped")
        }
    }

    /// The column has to fit the longest title, and the two sheets that build
    /// their rows differently must agree about that — the first version of this
    /// fix only reached the sheets going through SliderGrid.
    @MainActor
    func testLabelColumnFitsItsTitles() {
        XCTAssertEqual(
            OptionsSheet.labelColumnWidth(fitting: ["a"]), OptionsSheet.minimumLabelWidth,
            "a short title did not get the minimum column")
        let wide = OptionsSheet.labelColumnWidth(fitting: ["Doppler beaming"])
        XCTAssertGreaterThan(
            wide, OptionsSheet.minimumLabelWidth, "a long title did not widen the column")
        let needed = OptionsSheet.fieldLabel("Doppler beaming", width: nil).intrinsicContentSize.width
        XCTAssertGreaterThanOrEqual(
            wide, needed, "the column is \(wide) pt for a title that needs \(needed)")
        XCTAssertEqual(
            OptionsSheet.labelColumnWidth(fitting: ["a", "Doppler beaming"]),
            OptionsSheet.labelColumnWidth(fitting: ["Doppler beaming", "a"]),
            "the column width depends on the titles' order")
    }

    /// build-saver.sh compiles MODULES in the order given and links FRAMEWORKS;
    /// a module out of order or a framework left out breaks only the bundle
    /// build, which no other test runs.
    func testTheSaverIsBuiltFromTheModulesItNeeds() throws {
        let conf = try saverConf()
        let modules = try XCTUnwrap(conf["MODULES"], "saver.conf has no MODULES")
            .split(separator: " ").map(String.init)
        XCTAssertEqual(
            modules, ["SaverCore", "SaverKit", "VortexCore", "VortexRender", "VortexSaver"],
            "saver.conf's MODULES changed, or a dependency is listed after its dependent")

        let frameworks = try XCTUnwrap(conf["FRAMEWORKS"], "saver.conf has no FRAMEWORKS")
            .split(separator: " ").map(String.init)
        XCTAssertTrue(frameworks.contains("Metal"), "the saver links Metal at runtime")
        XCTAssertTrue(frameworks.contains("QuartzCore"), "CAMetalLayer comes from QuartzCore")
    }
}
