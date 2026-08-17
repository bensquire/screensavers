import Foundation
import SaverCore

/// What the options sheet can change.
public struct VortexSettings: Equatable {

    /// Multiplier on the particles' clock. The tunnel's own breathing rides on
    /// top of this, so it changes the average pace rather than flattening it.
    public var flowSpeed: Double

    /// Whether lightning strikes at all. With it off, the shockwaves that ride
    /// on each strike go too — they exist only as its aftermath.
    public var lightning: Bool

    /// Scales the particle count. The whole field is one GPU buffer evaluated in
    /// the vertex shader, so this trades fill rate for density rather than CPU.
    public var density: Double

    public enum Limits {
        public static let flowSpeed: ClosedRange<Double> = 0.3...2.5
        public static let density: ClosedRange<Double> = 0.25...1.5
    }

    public static let `default` = VortexSettings(
        flowSpeed: 1.0, lightning: true, density: 1.0)

    public init(flowSpeed: Double, lightning: Bool, density: Double) {
        self.flowSpeed = flowSpeed.clamped(to: Limits.flowSpeed)
        self.lightning = lightning
        self.density = density.clamped(to: Limits.density)
    }

    /// How many particles this density asks for.
    public var particleCount: Int {
        max(1, Int((Double(Tunnel.particleCount) * density).rounded()))
    }
}
