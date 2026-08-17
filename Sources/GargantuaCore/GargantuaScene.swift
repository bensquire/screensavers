import Foundation

/// What a viewer can change.
public struct GargantuaSettings: Equatable {

    /// Master motion rate, multiplying every clock in the scene at once.
    public var pace: Double

    /// Doppler beaming, 0...1 — the bright-limb/dim-limb asymmetry Double
    /// Negative dropped because it broke the shot. Off matches the film; on is
    /// what the physics actually does.
    public var beaming: Double

    /// Brightness of the lensed starfield behind the hole.
    public var stars: Double

    /// Whether the renderer is allowed to trade resolution for frame rate.
    public var adaptiveResolution: Bool

    /// Fixed render scale used when `adaptiveResolution` is off.
    public var renderScale: Double

    public enum Limits {
        public static let pace: ClosedRange<Double> = 0.1...3.0
        public static let beaming: ClosedRange<Double> = 0...1
        public static let stars: ClosedRange<Double> = 0...1
        public static let renderScale: ClosedRange<Double> = 0.30...1.0
    }

    public static let `default` = GargantuaSettings(
        pace: 1.0, beaming: 0.0, stars: 0.110,
        adaptiveResolution: true, renderScale: 0.55)

    public init(
        pace: Double, beaming: Double, stars: Double,
        adaptiveResolution: Bool, renderScale: Double
    ) {
        self.pace = pace.clamped(to: Limits.pace)
        self.beaming = beaming.clamped(to: Limits.beaming)
        self.stars = stars.clamped(to: Limits.stars)
        self.adaptiveResolution = adaptiveResolution
        self.renderScale = renderScale.clamped(to: Limits.renderScale)
    }

    /// The shipped look with these choices applied.
    public func applied(to base: SceneParameters) -> SceneParameters {
        var p = base
        p.pace = pace
        p.beaming = beaming
        p.stars = stars
        return p
    }
}

extension Double {
    public func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// The simulation: what time it is, where the camera is, and what the disk is
/// doing.
///
/// No rendering, no Metal — so the camera's drift, the hot spots' lifetimes and
/// the winding's reset cycle can all be tested without a GPU.
public final class GargantuaScene {

    public private(set) var parameters: SceneParameters
    public private(set) var camera = OrbitCamera()
    public private(set) var events: DiskEvents
    public private(set) var time: Double = 0
    public private(set) var frameIndex: Int = 0

    public var settings: GargantuaSettings {
        didSet {
            guard settings != oldValue else { return }
            parameters = settings.applied(to: base)
        }
    }

    private let base: SceneParameters

    public init(settings: GargantuaSettings = .default, seed: UInt64 = 0x6A56_1E01) {
        let base = SceneParameters()
        self.base = base
        self.settings = settings
        self.parameters = settings.applied(to: base)
        self.events = DiskEvents(seed: seed)
        camera.update(time: 0, parameters: parameters)
        camera.resetHistory()
    }

    /// The current differential winding phase.
    public var wind: WindPhase { WindPhase(time: time, parameters: parameters) }

    /// Sub-pixel jitter for this frame, from a Halton (2,3) sequence — low
    /// discrepancy, so successive frames fill the pixel evenly rather than
    /// clumping the way random offsets do.
    public var jitter: SIMD2<Float> { Self.halton[frameIndex % Self.halton.count] }

    /// A golden-ratio walk over the frame index, which the marcher uses to
    /// stratify its per-pixel sample offsets across frames.
    public var frameSequence: Float {
        Float((Double(frameIndex) * 0.6180339887).truncatingRemainder(dividingBy: 1))
    }

    public func update(deltaTime: Double) {
        // A long gap — the display slept, or the saver was paused — must not be
        // integrated as if it really happened.
        time += min(max(0, deltaTime), 0.1)
        events.update(time: time, parameters: parameters)
        camera.update(time: time, parameters: parameters)
        frameIndex += 1
    }

    /// Blend weight for this frame's accumulation.
    ///
    /// Fixed in seconds rather than frames: a frame-count window means the
    /// effective exposure stretches as the frame rate drops — exactly when the
    /// disk has had time to shear underneath it, which turns accumulation into
    /// smearing instead of convergence.
    public func accumulationAlpha(deltaTime: Double) -> Float {
        let dt = min(max(0, deltaTime), 0.1)
        return Float((1 - exp(-dt / max(parameters.taaTau, 1e-3))).clamped(to: 0.02...1))
    }

    private static let halton: [SIMD2<Float>] = {
        func value(_ index: Int, base: Int) -> Double {
            var i = index, f = 1.0, r = 0.0
            while i > 0 {
                f /= Double(base)
                r += f * Double(i % base)
                i /= base
            }
            return r
        }
        return (0..<16).map {
            SIMD2(Float(value($0 + 1, base: 2) - 0.5), Float(value($0 + 1, base: 3) - 0.5))
        }
    }()
}
