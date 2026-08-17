import AppKit
import Foundation
import Metal
import SaverKit
import SceneKit
import SolarSystemCore
import SpriteKit

/// How much the renderer is asked to do.
///
/// System Settings creates a second, live instance of the screensaver for its preview
/// thumbnail, and paying full price for a postage stamp makes the settings pane stutter.
/// Expressed as one choice rather than two independent knobs so the cheap variant is
/// reachable from the app too — otherwise it is the one path nobody ever looks at.
public enum RenderQuality: Sendable {
    case full
    case preview

    public var trailSamples: Int {
        switch self {
        case .full: return SceneConfig().trailSamples
        case .preview: return 72
        }
    }

    public var antialiasing: SCNAntialiasingMode {
        switch self {
        case .full: return .multisampling4X
        case .preview: return .none
        }
    }
}

/// An `SCNView` wired to a `SolarSystemRenderer`.
///
/// Both hosts — the windowed app and the screensaver — previously built this themselves:
/// the same eight view settings, the same first-frame-timestamp bookkeeping, and their
/// own re-fit-on-resize. They had already drifted apart (only one applied a hysteresis to
/// aspect changes, only one parked the display link when hidden), and host wiring is
/// exactly the seam that the shared render target was supposed to remove.
public final class SolarSystemSceneView: SCNView, SCNSceneRendererDelegate, SaverFrameCapturing {

    /// The most recent frame, for `make verify`.
    ///
    /// SceneKit draws on the GPU, so the view's backing store is empty and
    /// `cacheDisplay` would capture nothing.
    ///
    /// Deliberately an offscreen `SCNRenderer` rather than the view's own
    /// `snapshot()`. `snapshot()` trips an assertion inside
    /// `AppleParavirtTexture` on a virtualised GPU — which is what CI runs on —
    /// and an assertion aborts the process rather than returning nil, so the
    /// whole verify step died. Rendering into a texture we allocate ourselves is
    /// the path the Metal savers already use there without trouble.
    public func captureSaverFrame() -> NSImage? {
        // Declining is the only option on a virtualised GPU: SceneKit asserts
        // there rather than failing, which takes the whole process with it.
        guard let device = MTLCreateSystemDefaultDevice(), !device.isParavirtual,
            bounds.width > 1, bounds.height > 1
        else { return nil }

        let width = Int(bounds.width), height = Int(bounds.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        guard let target = device.makeTexture(descriptor: descriptor),
            let queue = device.makeCommandQueue(),
            let commandBuffer = queue.makeCommandBuffer()
        else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = pointOfView
        renderer.render(
            atTime: 0,
            viewport: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height),
            commandBuffer: commandBuffer,
            passDescriptor: pass)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return target.readBack(using: queue)?.asSaverFrame
    }

    private let solarSystem: SolarSystemRenderer
    /// SceneKit hands out an absolute host timestamp; the scene wants time since the
    /// first frame. Latched here rather than in each host.
    private var firstFrameTime: TimeInterval?
    private var lastAspect: Double = 0

    public init(
        renderer: SolarSystemRenderer,
        frame: NSRect,
        quality: RenderQuality = .full,
        allowsCameraControl: Bool = false
    ) {
        self.solarSystem = renderer
        super.init(frame: frame, options: nil)

        scene = renderer.scene
        pointOfView = renderer.pointOfView
        backgroundColor = .black
        antialiasingMode = quality.antialiasing
        autoresizingMask = [.width, .height]
        self.allowsCameraControl = allowsCameraControl
        isPlaying = true
        // SceneKit drives its own display link, so without this it renders at
        // the panel's native rate — 60 or 120 — regardless of what the hosting
        // ScreenSaverView's timer is doing. It was the most expensive of the
        // four savers by a distance for exactly that reason.
        preferredFramesPerSecond = Int(FrameClock.framesPerSecond)
        delegate = self
        overlaySKScene = renderer.overlayScene
        reframeIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SolarSystemSceneView is constructed in code, not from a nib")
    }

    public override func layout() {
        super.layout()
        reframeIfNeeded()
    }

    /// The camera fit depends on aspect ratio, so it has to be redone when the viewport
    /// changes — and each display gets its own instance with its own shape.
    private func reframeIfNeeded() {
        guard bounds.height > 0 else { return }
        let aspect = Double(bounds.width / bounds.height)
        guard abs(aspect - lastAspect) > 0.001 else { return }
        lastAspect = aspect
        solarSystem.reframe(aspectRatio: aspect)
    }

    // MARK: - SCNSceneRendererDelegate

    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let start = firstFrameTime ?? time
        firstFrameTime = start
        solarSystem.update(to: solarSystem.date(forElapsed: time - start))
    }
}
