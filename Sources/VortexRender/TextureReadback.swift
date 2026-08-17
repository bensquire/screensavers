import CoreGraphics
import Foundation
import Metal
import SaverKit
import VortexCore

extension VortexRenderer {

    /// Renders one frame into a fresh readable texture and returns it as an
    /// image — the whole offscreen path in one call, for tests and thumbnails.
    public func renderToImage(scene: VortexScene, width: Int, height: Int) -> CGImage? {
        guard let target = device.makeReadableTarget(width: width, height: height) else {
            return nil
        }
        renderSynchronously(scene: scene, to: target)
        return readBack(texture: target)
    }
}
