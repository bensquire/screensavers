import CoreGraphics
import Foundation
import Metal
import SaverKit
import VortexCore

extension VortexRenderer {

    /// Renders one frame into a fresh readable texture and returns it as an
    /// image — the whole offscreen path in one call, for tests and thumbnails.
    public func renderToImage(scene: VortexScene, width: Int, height: Int) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // Managed rather than shared: it is the one storage mode that reads back
        // on both Apple Silicon and Intel.
        descriptor.storageMode = .managed
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
        renderSynchronously(scene: scene, to: target)
        return readBack(texture: target)
    }
}
