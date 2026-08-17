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

    func testTheBuildCompilesTheShaderTheLoaderLooksFor() throws {
        let conf = try saverConf()
        XCTAssertEqual(
            conf["METAL_LIBRARY"], ShaderLibrary.name,
            "saver.conf builds a differently-named metallib than ShaderLibrary loads")

        let source = try XCTUnwrap(conf["METAL_SOURCES"])
        let path = Self.repositoryRoot.appendingPathComponent(source)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "saver.conf points METAL_SOURCES at \(source), which does not exist")
    }

    func testTheSaverIsBuiltFromTheModulesItNeeds() throws {
        let conf = try saverConf()
        let modules = try XCTUnwrap(conf["MODULES"]).split(separator: " ").map(String.init)
        // build-saver.sh compiles these in the order given, so a dependency
        // listed after its dependent will not resolve.
        XCTAssertEqual(
            modules, ["SaverKit", "GargantuaCore", "GargantuaRender", "GargantuaSaver"])

        let frameworks = try XCTUnwrap(conf["FRAMEWORKS"]).split(separator: " ").map(String.init)
        XCTAssertTrue(frameworks.contains("Metal"))
        XCTAssertTrue(frameworks.contains("QuartzCore"), "CAMetalLayer comes from QuartzCore")
    }

    func testTheHotSpotCapacityAgreesWithTheShader() throws {
        // SPOT_COUNT in Gargantua.metal is a compile-time constant sizing the
        // uniform array; DiskEvents.maxSpots decides how many are filled. If
        // they disagree, spots are silently dropped or the buffer overruns.
        let url = Self.repositoryRoot
            .appendingPathComponent("Sources/GargantuaRender/Gargantua.metal")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(
            source.contains("constant int SPOT_COUNT = 3;"),
            "the shader's SPOT_COUNT no longer matches DiskEvents.maxSpots")
    }
}
