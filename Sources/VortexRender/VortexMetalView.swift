import AppKit
import Metal
import SaverKit
import VortexCore

/// Draws the tunnel into a `CAMetalLayer`.
///
/// Layer setup, backing-scale policy and drawable sizing all come from
/// `MetalLayerView`; what is left here is the scene and how a frame is encoded.
public final class VortexMetalView: MetalLayerView, SaverFrameCapturing {

    public let scene: VortexScene
    private let renderer: VortexRenderer

    /// - Parameter seed: fixes the particle field, so a thumbnail or a test
    ///   renders the same tunnel every time.
    ///
    /// Settings are taken at construction because `density` decides the size of
    /// the GPU buffers. Changing options replaces the view rather than mutating
    /// it, which is cheap enough at the rate a person edits a settings sheet.
    public init(
        frame: NSRect,
        settings: VortexSettings = .default,
        seed: UInt64 = 0x5EED_1234
    ) throws {
        let layout = Layout(
            pointWidth: Double(frame.width), pointHeight: Double(frame.height),
            backingScale: 1)
        self.scene = VortexScene(layout: layout, settings: settings, seed: seed)
        self.renderer = try VortexRenderer(particles: scene.particles)
        super.init(frame: frame, device: renderer.device)
    }

    /// `Layout` does the point-to-pixel conversion itself, and its `scale` sizes
    /// streak widths and the aberration — so it is given the view's points and
    /// the capped backing scale, not the already-multiplied drawable size.
    private func currentLayout() -> Layout {
        Layout(
            pointWidth: Double(bounds.width),
            pointHeight: Double(bounds.height),
            backingScale: Double(backingScale))
    }

    /// Renders the current scene into a readable texture, for `make verify`.
    public func captureSaverFrame() -> NSImage? {
        let size = drawableSize
        return renderer.renderToImage(
            scene: scene, width: Int(size.width), height: Int(size.height))?.asSaverFrame
    }

    /// Advances the scene by `deltaTime` seconds and draws it.
    public func advance(deltaTime: Double) {
        scene.update(deltaTime: deltaTime, layout: currentLayout())
        present(commandBuffer: renderer.makeCommandBuffer) { texture, commandBuffer in
            renderer.render(scene: scene, to: texture, in: commandBuffer)
        }
    }
}
