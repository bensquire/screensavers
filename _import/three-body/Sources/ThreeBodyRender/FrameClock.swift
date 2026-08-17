import QuartzCore
import ThreeBodyCore

/// Turns "this callback fired" into "this much real time passed".
///
/// Both hosts — `ScreenSaverView`'s own animation timer and the preview app's
/// `Timer` — need exactly this and nothing else from each other, so it lives
/// here rather than being written out twice.
public struct FrameClock {

    /// Frames per second the scene is drawn at.
    ///
    /// 30 rather than 60: the drawing is done in software by Core Graphics, so
    /// the frame rate is very nearly the whole CPU cost, and at the pace the
    /// bodies actually move — a median of a few screen points per frame — the
    /// halved rate is not visible. Both hosts read this so they cannot drift.
    public static let framesPerSecond: Double = 30.0
    public static let frameInterval: Double = 1.0 / framesPerSecond

    private var lastFrameTime: CFTimeInterval = 0
    /// Assumed elapsed time for the first frame, when there is no previous one.
    private let nominalInterval: Double

    public init(nominalInterval: Double = FrameClock.frameInterval) {
        self.nominalInterval = nominalInterval
    }

    /// Seconds since the previous tick. The engine does its own clamping for
    /// pathological gaps (display sleep, a paused screensaver); this only has
    /// to answer the question honestly.
    public mutating func tick() -> Double {
        let now = CACurrentMediaTime()
        defer { lastFrameTime = now }
        guard lastFrameTime > 0 else { return nominalInterval }
        return now - lastFrameTime
    }

    /// Forget the previous frame, so the next tick starts a fresh interval
    /// rather than reporting however long the view sat idle.
    public mutating func reset() {
        lastFrameTime = 0
    }
}
