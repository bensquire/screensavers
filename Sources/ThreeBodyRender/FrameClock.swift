import QuartzCore
import ThreeBodyCore

/// Turns "this callback fired" into "this much real time passed".
///
/// Both hosts — `ScreenSaverView`'s own animation timer and the preview app's
/// `Timer` — need exactly this and nothing else from each other, so it lives
/// here rather than being written out twice.
public struct FrameClock {
    private var lastFrameTime: CFTimeInterval = 0
    /// Assumed elapsed time for the first frame, when there is no previous one.
    private let nominalInterval: Double

    public init(nominalInterval: Double = 1.0 / 60.0) {
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
