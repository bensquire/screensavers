import Foundation

/// The geometry every part of the scene agrees on: a cylinder of radius
/// `radius` extending from `zNear` to `zFar`, viewed down its axis.
///
/// Particles are placed on the wall and drift toward the camera; when one passes
/// `zNear` it wraps back to `zFar`, so the tunnel is endless without ever
/// allocating anything.
public enum Tunnel {

    /// Nearest and furthest z a particle occupies. `zNear` is deliberately small
    /// rather than zero — projection divides by z, so a particle reaching the eye
    /// plane would scale to infinity.
    public static let zNear = 0.05
    public static let zFar = 6.0
    public static let radius = 1.0

    /// Total particles, split into streaks and sprites by `ParticleSet`.
    public static let particleCount = 5400

    public static var zRange: Double { zFar - zNear }
}

/// Everything derived from the drawable's size, computed once per resize.
///
/// These formulas were previously spread across the frame loop, the bolt
/// generator and the uniform upload; keeping them together is what stops the
/// three from disagreeing about where the middle of the screen is.
public struct Layout: Equatable {

    /// Drawable size in device pixels, and the backing scale that produced it.
    public let width: Double
    public let height: Double
    public let scale: Double

    public let minDimension: Double
    /// Focal length in pixels. Larger means a narrower field of view.
    public let focal: Double
    /// How far the tunnel's far end can be pushed off-centre.
    public let maxBendPixels: Double
    public let centerX: Double
    public let centerY: Double
    /// Radius at which an expanding shockwave has left the screen.
    public let maxShockRadius: Double

    public init(pointWidth: Double, pointHeight: Double, backingScale: Double) {
        // Capped at 2: beyond that the extra pixels cost real time and buy nothing
        // a screensaver's viewer will ever lean in to see.
        let scale = min(max(backingScale, 1), 2)
        self.scale = scale
        self.width = max(1, (pointWidth * scale).rounded(.down))
        self.height = max(1, (pointHeight * scale).rounded(.down))
        self.minDimension = min(width, height)
        self.focal = minDimension * 0.55
        self.maxBendPixels = minDimension * 0.9
        self.centerX = width / 2
        self.centerY = height / 2
        self.maxShockRadius = (width * width + height * height).squareRoot() * 0.55
    }

    /// Where a point on the tunnel wall lands on screen.
    ///
    /// The vertex shaders do this same projection per particle; this copy exists
    /// for the CPU-side geometry (lightning) so a bolt wraps around the cylinder
    /// exactly the way the particles beside it do.
    public func project(
        z: Double, angle: Double, radius: Double, bendX: Double, bendY: Double
    ) -> SIMD2<Double> {
        let zf = (z - Tunnel.zNear) / Tunnel.zRange
        let bend = zf * zf
        let scale = focal / z
        return SIMD2(
            centerX + bendX * bend + cos(angle) * radius * scale,
            centerY + bendY * bend + sin(angle) * radius * scale)
    }
}
