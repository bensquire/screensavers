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

    func testTheBuildCompilesTheShaderTheLoaderLooksFor() throws {
        let conf = try saverConf()

        // ShaderLibrary asks the bundle for "Vortex.metallib"; the build script
        // names the output from METAL_LIBRARY. They have to be the same word.
        XCTAssertEqual(
            conf["METAL_LIBRARY"], ShaderLibrary.name,
            "saver.conf builds a differently-named metallib than ShaderLibrary loads")

        let source = try XCTUnwrap(conf["METAL_SOURCES"])
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
        XCTAssertEqual(window.frame.width, OptionsSheet.contentWidth, accuracy: 1)
        XCTAssertLessThan(window.frame.height, 600, "too tall for a settings sheet")
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

    func testTheSaverIsBuiltFromTheModulesItNeeds() throws {
        let conf = try saverConf()
        let modules = try XCTUnwrap(conf["MODULES"]).split(separator: " ").map(String.init)
        // build-saver.sh compiles these in the order given, so a dependency
        // listed after its dependent will not resolve.
        XCTAssertEqual(modules, ["SaverCore", "SaverKit", "VortexCore", "VortexRender", "VortexSaver"])

        let frameworks = try XCTUnwrap(conf["FRAMEWORKS"]).split(separator: " ").map(String.init)
        XCTAssertTrue(frameworks.contains("Metal"), "the saver links Metal at runtime")
        XCTAssertTrue(frameworks.contains("QuartzCore"), "CAMetalLayer comes from QuartzCore")
    }
}
