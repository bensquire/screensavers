import QuartzCore
@_exported import SaverCore

/// Turns "this callback fired" into "this much real time passed".
///
/// Both hosts — `ScreenSaverView`'s own animation timer and the preview app's
/// `Timer` — need exactly this and nothing else from each other, so it lives
/// here rather than being written out twice.
public struct FrameClock {

    /// Frames per second, for every saver here.
    ///
    /// 30, and it is a policy rather than a per-saver tuning decision. Cost is
    /// very nearly proportional to frames drawn whether the drawing is done by
    /// Core Graphics on the CPU, by SceneKit, or by a per-pixel raymarcher — so
    /// the frame rate is the one dial that halves the load of all of them at
    /// once. These run unattended for hours on a laptop that is usually on
    /// battery, and nothing here moves fast enough for 60 to be worth twice the
    /// power: the fastest thing on screen is a vortex streak, which is drawn as
    /// its own motion blur and so does not judder when frames are further apart.
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
