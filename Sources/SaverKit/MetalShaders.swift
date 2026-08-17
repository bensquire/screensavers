import CoreGraphics
import Foundation
import Metal

/// Finding and loading a saver's compiled shaders.
///
/// A shipped saver carries a `.metallib` built alongside its Swift by
/// `Scripts/build-saver.sh`. Tests and `swift run` have no such bundle, so they
/// fall back to compiling the `.metal` source from the checkout — which keeps
/// the shaders a single file rather than a checked-in binary plus the source it
/// came from, at the cost of a few hundred milliseconds in development only.
public enum MetalShaders {

    public enum Failure: Error, CustomStringConvertible {
        case missingLibrary(String)

        public var description: String {
            switch self {
            case .missingLibrary(let name):
                return "\(name).metallib is missing from the bundle"
            }
        }
    }

    /// - Parameters:
    ///   - name: base name of both the `.metallib` resource and the `.metal`
    ///     source, which must match what `saver.conf` declares.
    ///   - token: any class from the module whose bundle holds the library.
    ///   - sourceFile: pass `#filePath` from a file sitting beside the `.metal`
    ///     source. It resolves to the build machine, so it only ever succeeds in
    ///     a source checkout — exactly the case it is meant for.
    public static func load(
        named name: String,
        token: AnyClass,
        sourceFile: String,
        device: MTLDevice
    ) throws -> MTLLibrary {
        let bundle = Bundle(for: token)
        if let url = bundle.url(forResource: name, withExtension: "metallib") {
            return try device.makeLibrary(URL: url)
        }
        guard let library = try? compile(named: name, sourceFile: sourceFile, device: device) else {
            throw Failure.missingLibrary(name)
        }
        return library
    }

    /// Compiles the `.metal` sitting beside `sourceFile`.
    public static func compile(
        named name: String, sourceFile: String, device: MTLDevice
    ) throws -> MTLLibrary {
        let url = URL(fileURLWithPath: sourceFile)
            .deletingLastPathComponent()
            .appendingPathComponent("\(name).metal")
        return try device.makeLibrary(
            source: String(contentsOf: url, encoding: .utf8), options: nil)
    }
}

extension MTLTexture {

    /// Copies this texture back to the CPU as an image.
    ///
    /// For thumbnail rendering and for tests that need to assert on what was
    /// actually drawn — the only way to catch a shader that compiles, binds,
    /// draws, and produces nothing.
    ///
    /// The texture must have been created with `.managed` or `.shared` storage;
    /// a `.private` one has no CPU copy to read.
    public func readBack(using queue: MTLCommandQueue) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        // A managed texture's CPU copy is stale until the GPU is told to push it.
        if storageMode == .managed {
            guard let commandBuffer = queue.makeCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder()
            else { return nil }
            blit.synchronize(resource: self)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            getBytes(
                buffer.baseAddress!,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0)
        }

        // The targets are BGRA; Core Graphics is told so rather than the
        // channels being swapped by hand.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
                .union(.byteOrder32Little),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }
}
