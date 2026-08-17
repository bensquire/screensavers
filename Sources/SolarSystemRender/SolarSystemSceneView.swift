import AppKit
import Foundation
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
    /// `cacheDisplay` would capture nothing — `snapshot()` re-renders and gives
    /// back what is actually on screen.
    public func captureSaverFrame() -> NSImage? { snapshot() }

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
