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
    /// first frame. Accumulated frame by frame rather than taken as a difference from
    /// the first one, so that time spent paused — stopped, or asleep with the
    /// display — is not suddenly simulated when drawing resumes: at the default pace
    /// a night's pause would otherwise jump the scene ten thousand years ahead.
    private var frameClock = FrameClock()
    private var elapsed: Double = 0
    /// Longest step one frame may advance by. Anything longer was a pause.
    private static let maximumFrameStep: Double = 0.1
    private var lastAspect: Double = 0

    /// A viewport shape waiting to be applied by the render thread.
    ///
    /// `layout()` runs on the main thread and the scene is updated on SceneKit's
    /// rendering thread, and both used to call into the renderer — its sample
    /// buffers, its ribbons and its camera state, none of which are synchronised.
    /// Now the main thread only leaves the new shape here and the render thread
    /// picks it up, so the renderer is only ever touched from one thread.
    private var pendingAspect: Double?
    private let pendingAspectLock = NSLock()

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
        reframeIfNeeded(immediately: true)
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
    ///
    /// Applied directly only from `init`, before the view can be drawn; after that it
    /// is handed to the render thread. See `pendingAspect`.
    private func reframeIfNeeded(immediately: Bool = false) {
        guard bounds.height > 0 else { return }
        let aspect = Double(bounds.width / bounds.height)
        guard abs(aspect - lastAspect) > 0.001 else { return }
        lastAspect = aspect
        if immediately {
            solarSystem.reframe(aspectRatio: aspect)
        } else {
            pendingAspectLock.lock()
            pendingAspect = aspect
            pendingAspectLock.unlock()
        }
    }

    // MARK: - SCNSceneRendererDelegate

    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        pendingAspectLock.lock()
        let aspect = pendingAspect
        pendingAspect = nil
        pendingAspectLock.unlock()
        if let aspect { solarSystem.reframe(aspectRatio: aspect) }

        elapsed += frameClock.tick().clamped(to: 0...Self.maximumFrameStep)
        solarSystem.update(to: solarSystem.date(forElapsed: elapsed))
    }
}
