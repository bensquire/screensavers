import CoreGraphics
import Foundation
import Metal
import VortexCore

extension VortexRenderer {

    /// Copies a rendered texture back to the CPU as an image.
    ///
    /// Used by the thumbnail renderer and by tests that need to assert on what
    /// was actually drawn — which is the only way to catch a shader that
    /// compiles, binds and draws nothing.
    public func readBack(texture: MTLTexture) -> CGImage? {
        guard texture.width > 0, texture.height > 0 else { return nil }

        // A managed texture's CPU copy is stale until the GPU is told to push it.
        if texture.storageMode == .managed {
            guard let commandBuffer = makeCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder()
            else { return nil }
            blit.synchronize(resource: texture)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        let bytesPerRow = texture.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        pixels.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }

        // The target is BGRA; Core Graphics is told so rather than the channels
        // being swapped by hand.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: texture.width,
            height: texture.height,
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

    /// Renders one frame into a fresh readable texture. The whole offscreen path
    /// in one call, for tests and thumbnails.
    public func renderToImage(scene: VortexScene, width: Int, height: Int) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
        renderSynchronously(scene: scene, to: target)
        return readBack(texture: target)
    }
}
