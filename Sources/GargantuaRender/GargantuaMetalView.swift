import AppKit
import GargantuaCore
import Metal
import QuartzCore

/// An `NSView` backed by a `CAMetalLayer` that draws the black hole.
///
/// Not an `MTKView`, for the same reason as the other Metal saver here: that
/// brings its own display link, and both hosts already own the timer deciding
/// when a frame happens.
public final class GargantuaMetalView: NSView {

    public let scene: GargantuaScene
    private let renderer: GargantuaRenderer

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    /// Capped at 2. The march is per-pixel geodesic integration, so a third of
    /// the pixels again is a third of the cost again for detail nobody leans in
    /// to see — and the adaptive controller would only claw it straight back by
    /// dropping render scale.
    private static let maximumBackingScale: CGFloat = 2

    public init(frame: NSRect, settings: GargantuaSettings = .default) throws {
        self.scene = GargantuaScene(settings: settings)
        self.renderer = try GargantuaRenderer()
        super.init(frame: frame)

        if !settings.adaptiveResolution {
            renderer.fixRenderScale(at: settings.renderScale)
        }
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
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    public override var isOpaque: Bool { true }

    /// Transparent to the mouse.
    ///
    /// The engine dismisses the screensaver when it sees input, and a view that
    /// answers a hit-test is a view that can swallow the event meant to end the
    /// session. Nothing here listens for input anyway; a screensaver that will
    /// not quit is not a failure worth risking on that alone.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
        let scale = min(window?.backingScaleFactor ?? 1, Self.maximumBackingScale)
        metalLayer.contentsScale = scale
        let size = CGSize(
            width: max(1, (bounds.width * scale).rounded(.down)),
            height: max(1, (bounds.height * scale).rounded(.down)))
        guard size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        // Every buffer is about to be reallocated, so the accumulated frames in
        // them describe a different image.
        renderer.invalidateHistory()
    }

    /// Advances the scene by `deltaTime` seconds and draws it.
    public func advance(deltaTime: Double) {
        scene.update(deltaTime: deltaTime)
        draw(deltaTime: deltaTime)
    }

    private func draw(deltaTime: Double) {
        guard let metalLayer,
            metalLayer.drawableSize.width >= 1, metalLayer.drawableSize.height >= 1,
            let drawable = metalLayer.nextDrawable(),
            let commandBuffer = renderer.makeCommandBuffer()
        else { return }

        renderer.render(
            scene: scene, deltaTime: deltaTime, to: drawable.texture, in: commandBuffer)
        // Metal reports what the GPU actually spent, which is the number the
        // adaptive controller wants — unlike wall-clock time, which vsync
        // quantises and which cannot tell "just fast enough" from "four times
        // faster than needed".
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let elapsed = buffer.gpuEndTime - buffer.gpuStartTime
            DispatchQueue.main.async { self?.renderer.noteFrameCost(gpuSeconds: elapsed) }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Fraction of the output the march is currently running at, for the preview
    /// app's readout.
    public var renderScale: Double { renderer.renderScale }
}
