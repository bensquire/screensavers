import Foundation
import Metal

/// Finds the compiled shaders.
///
/// A shipped saver carries `Vortex.metallib`, built alongside the Swift by
/// `Scripts/build-saver.sh`. Tests and `swift run` have no such bundle, so they
/// fall back to compiling `Vortex.metal` from the source tree — which keeps the
/// shaders a single file rather than a checked-in binary plus the source it came
/// from, at the cost of a few hundred milliseconds in development only.
public enum ShaderLibrary {

    /// Only exists to name the bundle this module was loaded from.
    private final class BundleToken {}

    public static func load(device: MTLDevice) throws -> MTLLibrary {
        let bundle = Bundle(for: BundleToken.self)
        if let url = bundle.url(forResource: "Vortex", withExtension: "metallib") {
            return try device.makeLibrary(URL: url)
        }
        guard let library = try? compileFromSource(device: device) else {
            throw VortexRenderer.Failure.missingLibrary
        }
        return library
    }

    /// Compiles the `.metal` sitting beside this file. `#filePath` resolves to
    /// the build machine, so this only ever succeeds in a source checkout —
    /// exactly the case it is meant for.
    static func compileFromSource(device: MTLDevice) throws -> MTLLibrary {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Vortex.metal")
        return try device.makeLibrary(
            source: String(contentsOf: source, encoding: .utf8), options: nil)
    }
}
