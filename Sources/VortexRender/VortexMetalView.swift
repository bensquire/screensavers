import AppKit
import Metal
import QuartzCore
import VortexCore

/// An `NSView` backed by a `CAMetalLayer` that draws the tunnel.
///
/// Deliberately not an `MTKView`: that brings its own display link, and both
/// hosts here — `ScreenSaverView` and the preview app — already own the timer
/// that decides when a frame happens. Two clocks would fight.
public final class VortexMetalView: NSView {

    public let scene: VortexScene
    private let renderer: VortexRenderer

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

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
        super.init(frame: frame)

        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — the view is created by frame")
    }

    public override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        // Nothing ever reads the drawable back, which lets the driver skip
        // allocating it as a sampleable texture.
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    public override var isOpaque: Bool { true }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let metalLayer else { return }
        let scale = window?.backingScaleFactor ?? 1
        metalLayer.contentsScale = scale
        let layout = currentLayout()
        metalLayer.drawableSize = CGSize(width: layout.width, height: layout.height)
    }

    /// The drawable is capped at 2× regardless of the display, so this is the one
    /// place that decides how many pixels a frame actually costs.
    private func currentLayout() -> Layout {
        Layout(
            pointWidth: Double(bounds.width),
            pointHeight: Double(bounds.height),
            backingScale: Double(window?.backingScaleFactor ?? 1))
    }

    /// Advances the scene by `deltaTime` seconds and draws it.
    public func advance(deltaTime: Double) {
        scene.update(deltaTime: deltaTime, layout: currentLayout())
        draw()
    }

    private func draw() {
        guard let metalLayer,
            metalLayer.drawableSize.width >= 1, metalLayer.drawableSize.height >= 1,
            let drawable = metalLayer.nextDrawable(),
            let commandBuffer = renderer.makeCommandBuffer()
        else { return }

        renderer.render(scene: scene, to: drawable.texture, in: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
