import AppKit
import Metal
import QuartzCore

/// An `NSView` backed by a `CAMetalLayer`, for savers that draw with Metal.
///
/// Deliberately not an `MTKView`: that brings its own display link, and both
/// hosts here — `ScreenSaverView` and the preview apps — already own the timer
/// deciding when a frame happens. Two clocks would fight.
///
/// Subclasses supply a command buffer and encode into the drawable; everything
/// else — layer setup, backing-scale policy, drawable sizing, and refusing hit
/// tests — lives here, so two savers cannot answer those differently.
open class MetalLayerView: NSView {

    /// Backing scale is capped rather than taken from the display.
    ///
    /// Beyond 2x the extra pixels cost real time and buy nothing a screensaver's
    /// viewer will lean in to see — and for a saver that adapts its resolution
    /// to hold a frame rate, the pixels would only be handed straight back.
    public static let maximumBackingScale: CGFloat = 2

    private let device: MTLDevice

    public var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    public init(frame: NSRect, device: MTLDevice) {
        self.device = device
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — the view is created by frame")
    }

    open override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        // Nothing ever reads the drawable back, which lets the driver skip
        // allocating it as a sampleable texture.
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    open override var isOpaque: Bool { true }

    /// Transparent to the mouse.
    ///
    /// The engine dismisses the screensaver when it sees input, and a view that
    /// answers a hit test is a view that can swallow the event meant to end the
    /// session. Nothing here listens for input anyway; a screensaver that will
    /// not quit is not a failure worth risking on that alone.
    open override func hitTest(_ point: NSPoint) -> NSView? { nil }

    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    /// The display's backing scale, after the cap. Savers that size anything in
    /// device pixels — line widths, sprite radii — need this rather than the
    /// window's raw value, or they get the cap wrong.
    public var backingScale: CGFloat {
        min(window?.backingScaleFactor ?? 1, Self.maximumBackingScale)
    }

    /// Upper bound on drawable pixels, before any render-scale reduction.
    ///
    /// The backing-scale cap alone does not bound this: a 6K display at 2x is
    /// four times the pixels of a laptop panel, and for a saver whose cost is
    /// per-pixel that is the difference between comfortable and unusable.
    /// Override to put a ceiling on it.
    open var maximumDrawablePixels: Double { .infinity }

    /// The drawable's size in device pixels, after the backing-scale and pixel
    /// caps.
    public var drawableSize: CGSize {
        let width = bounds.width * backingScale
        let height = bounds.height * backingScale
        // Both axes by the same factor, so the aspect ratio — and therefore the
        // framing — is untouched. Uncapped, this is 1 and costs a divide.
        let shrink = min(1, (maximumDrawablePixels / Double(width * height)).squareRoot())
        return CGSize(
            width: max(1, (width * CGFloat(shrink)).rounded(.down)),
            height: max(1, (height * CGFloat(shrink)).rounded(.down)))
    }

    private func updateDrawableSize() {
        guard let metalLayer else { return }
        metalLayer.contentsScale = backingScale
        let size = drawableSize
        guard size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        drawableSizeChanged()
    }

    /// Called after the drawable has been resized. Override to drop anything
    /// sized against the old one — accumulated frames, cached targets.
    open func drawableSizeChanged() {}

    /// Draws one frame, if there is anything to draw into.
    ///
    /// `encode` receives the drawable's texture and the command buffer, which is
    /// presented and committed once it returns.
    public func present(
        commandBuffer makeCommandBuffer: () -> MTLCommandBuffer?,
        encode: (MTLTexture, MTLCommandBuffer) -> Void
    ) {
        guard let metalLayer,
            metalLayer.drawableSize.width >= 1, metalLayer.drawableSize.height >= 1,
            let drawable = metalLayer.nextDrawable(),
            let commandBuffer = makeCommandBuffer()
        else { return }

        encode(drawable.texture, commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
