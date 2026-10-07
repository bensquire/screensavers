import GargantuaCore
import XCTest

@testable import GargantuaRender

/// The shaders are compiled from source in tests and loaded from a `.metallib`
/// in the shipped bundle, so nothing else here exercises the packaged path. A
/// mismatch between what `Scripts/build-saver.sh` writes and what
/// `ShaderLibrary` looks for would leave the built saver drawing nothing, while
/// every other test passed.
final class PackagingTests: XCTestCase {

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GargantuaTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
    }

    private func saverConf() throws -> [String: String] {
        let url = Self.repositoryRoot.appendingPathComponent("savers/gargantua/saver.conf")
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

    /// saver.conf names the metallib and its source. If either drifts from what
    /// ShaderLibrary loads, the built saver draws nothing while every other test
    /// passes, because the tests compile the shader from source.
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

    /// build-saver.sh compiles MODULES in the order given and links FRAMEWORKS;
    /// a module out of order or a framework left out breaks only the bundle
    /// build, which no other test runs.
    func testTheSaverIsBuiltFromTheModulesItNeeds() throws {
        let conf = try saverConf()
        let modules = try XCTUnwrap(conf["MODULES"], "saver.conf has no MODULES")
            .split(separator: " ").map(String.init)
        XCTAssertEqual(
            modules, ["SaverCore", "SaverKit", "GargantuaCore", "GargantuaRender", "GargantuaSaver"],
            "saver.conf's MODULES changed, or a dependency is listed after its dependent")

        let frameworks = try XCTUnwrap(conf["FRAMEWORKS"], "saver.conf has no FRAMEWORKS")
            .split(separator: " ").map(String.init)
        XCTAssertTrue(frameworks.contains("Metal"), "the saver links Metal at runtime")
        XCTAssertTrue(frameworks.contains("QuartzCore"), "CAMetalLayer comes from QuartzCore")
    }

    /// SPOT_COUNT in Gargantua.metal sizes the uniform array and
    /// DiskEvents.maxSpots decides how many are filled. If they disagree, spots
    /// are silently dropped or the buffer overruns. Compared with maxSpots itself:
    /// against a literal, changing both together would fail and changing only
    /// maxSpots would pass.
    func testTheHotSpotCapacityAgreesWithTheShader() throws {
        let url = Self.repositoryRoot
            .appendingPathComponent("Sources/GargantuaRender/Gargantua.metal")
        let source = try String(contentsOf: url, encoding: .utf8)

        let declaration = "constant int SPOT_COUNT = \(DiskEvents.maxSpots);"

        XCTAssertTrue(
            source.contains(declaration),
            "the shader does not declare SPOT_COUNT as DiskEvents.maxSpots (\(DiskEvents.maxSpots))")
    }
}
