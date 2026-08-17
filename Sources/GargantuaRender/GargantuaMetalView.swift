import AppKit
import GargantuaCore
import Metal
import SaverKit

/// Draws the black hole into a `CAMetalLayer`.
///
/// Layer setup, backing-scale policy and drawable sizing all come from
/// `MetalLayerView`; what is left here is the scene, how a frame is encoded, and
/// feeding the adaptive controller what the GPU actually spent.
public final class GargantuaMetalView: MetalLayerView, SaverFrameCapturing {

    public let scene: GargantuaScene
    private let renderer: GargantuaRenderer

    /// Last frame's measured GPU time, written by the completion handler on
    /// whatever thread Metal calls it from and consumed on the next frame.
    ///
    /// Cheaper than hopping to the main queue every frame just to hand over one
    /// number, and the controller only ever acts on a smoothed average anyway.
    private let lastGPUSeconds = Atomic<Double>(0)

    public init(frame: NSRect, settings: GargantuaSettings = .default) throws {
        self.scene = GargantuaScene(settings: settings)
        self.renderer = try GargantuaRenderer()
        super.init(frame: frame, device: renderer.device)

        if !settings.adaptiveResolution {
            renderer.fixRenderScale(at: settings.renderScale)
        }
    }

    /// 4K, matching what the WebGL original allowed itself.
    ///
    /// Beyond this the march stops being affordable at any render scale the
    /// controller is willing to pick — at 2560x1600 a full-scale frame already
    /// costs 50ms on an M1 Pro, and pixels scale that linearly.
    public override var maximumDrawablePixels: Int { 3840 * 2160 }

    public override func drawableSizeChanged() {
        // Every target is about to be reallocated, so the frames accumulated in
        // them describe a different image.
        renderer.invalidateHistory()
    }

    /// Renders the current scene into a readable texture, for `make verify`.
    public func captureSaverFrame() -> NSImage? {
        let size = drawableSize
        return renderer.renderToImage(
            scene: scene, deltaTime: 1.0 / GargantuaRenderer.framesPerSecond,
            width: Int(size.width), height: Int(size.height))?.asSaverFrame
    }

    /// Advances the scene by `deltaTime` seconds and draws it.
    public func advance(deltaTime: Double) {
        // Metal reports what the GPU actually spent, which is the number the
        // adaptive controller wants — unlike wall-clock time, which vsync
        // quantises and which cannot tell "just fast enough" from "four times
        // faster than needed".
        if let elapsed = lastGPUSeconds.take() {
            renderer.noteFrameCost(gpuSeconds: elapsed)
        }

        scene.update(deltaTime: deltaTime)
        present(commandBuffer: renderer.makeCommandBuffer) { texture, commandBuffer in
            renderer.render(
                scene: scene, deltaTime: deltaTime, to: texture, in: commandBuffer)
            commandBuffer.addCompletedHandler { [lastGPUSeconds] buffer in
                lastGPUSeconds.store(buffer.gpuEndTime - buffer.gpuStartTime)
            }
        }
    }

    /// Fraction of the output the march is currently running at, for the preview
    /// app's readout.
    public var renderScale: Double { renderer.renderScale }
}

/// A single value handed between the GPU's completion thread and the main one.
///
/// `OSAllocatedUnfairLock` would do, but it is a heavier dependency than one
/// `Double` warrants and this is not contended — the writer runs once a frame.
final class Atomic<Value>: @unchecked Sendable {
    private var value: Value?
    private let lock = NSLock()

    init(_ initial: Value?) { value = initial }

    func store(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    /// Returns the stored value and clears it, so a frame's cost is only ever
    /// counted once.
    func take() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value = nil
        return current
    }
}
