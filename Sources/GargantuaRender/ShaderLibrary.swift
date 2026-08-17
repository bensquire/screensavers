import Foundation
import Metal
import SaverKit

/// Locates this saver's compiled shaders. The mechanics live in
/// `SaverKit.MetalShaders`; this only names the library and the bundle.
public enum ShaderLibrary {

    /// Only exists to name the bundle this module was loaded from.
    private final class BundleToken {}

    /// Must match `METAL_LIBRARY` in `savers/gargantua/saver.conf`.
    public static let name = "Gargantua"

    public static func load(device: MTLDevice) throws -> MTLLibrary {
        try MetalShaders.load(
            named: name, token: BundleToken.self, sourceFile: #filePath, device: device)
    }

    /// Compiles from the checkout, for tests.
    public static func compileFromSource(device: MTLDevice) throws -> MTLLibrary {
        try MetalShaders.compile(named: name, sourceFile: #filePath, device: device)
    }
}
