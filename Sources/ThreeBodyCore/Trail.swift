import Foundation

public struct TrailSample {
    public var position: Vec2
    /// Simulated time at which the body was here.
    public var time: Double
}

/// The path a body has swept out recently, held in world coordinates so it
/// stays correct while the camera pans and zooms.
///
/// Samples are laid down by distance rather than by frame: the goal is roughly
/// constant spacing *on screen*, so a body crawling through apoapsis does not
/// pile up thousands of redundant points while a slingshot leaves gaps.
public struct Trail {
    public private(set) var samples: [TrailSample] = []
    private var lastRecorded: Vec2?

    /// How much simulated time the tail covers.
    public var span: Double = 6.0
    public var maxSamples: Int = 3000

    public mutating func record(position: Vec2, time: Double, minimumSpacing: Double) {
        if let last = lastRecorded, (position - last).length < minimumSpacing {
            return
        }
        samples.append(TrailSample(position: position, time: time))
        lastRecorded = position
        prune(now: time)
    }

    private mutating func prune(now: Double) {
        let cutoff = now - span
        if let firstLive = samples.firstIndex(where: { $0.time >= cutoff }), firstLive > 0 {
            samples.removeFirst(firstLive)
        }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

}
