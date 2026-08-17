import Foundation
import VortexCore

/// The per-frame constants every shader reads.
///
/// This is the Swift half of a struct `Vortex.metal` also declares. The buffer is
/// handed to the GPU as raw memory, so the field order and types must match
/// exactly — `UniformLayoutTests` asks the compiled shader for its own sizes and
/// offsets and compares them with these, which is the only way to find out that
/// an innocuous-looking edit has silently shifted every field along by four bytes.
struct SceneUniforms {
    /// Four slots, each (x, y, radius, intensity). Intensity zero means empty.
    var shocks: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var resolution: SIMD2<Float>
    var bendPixels: SIMD2<Float>
    var vanishingPoint: SIMD2<Float>
    var focal: Float
    var time: Float
    var particleTime: Float
    var tubeSpin: Float
    var zNear: Float
    var zFar: Float
    var tailMs: Float
    var streakScale: Float
    var spriteScale: Float
    var hueShift: Float
    var chromaticAberration: Float

    init(scene: VortexScene, sceneScale: Double) {
        let layout = scene.layout
        let shocks = scene.shockUniforms
        self.shocks = (shocks[0], shocks[1], shocks[2], shocks[3])
        self.resolution = SIMD2(Float(layout.width), Float(layout.height))
        // Resolved once — the vanishing point is derived from it.
        let bend = scene.bendPixels
        self.bendPixels = bend
        self.vanishingPoint = scene.vanishingPoint(bendPixels: bend)
        self.focal = Float(layout.focal)
        self.time = Float(scene.elapsedMs)
        self.particleTime = Float(scene.particleClockMs)
        self.tubeSpin = Float(scene.tubeSpin)
        self.zNear = Float(Tunnel.zNear)
        self.zFar = Float(Tunnel.zFar)
        self.tailMs = scene.streakTailMs
        // Streaks are sized in device pixels and sprites are not. That asymmetry
        // is inherited: it means sprites keep the same size in points while
        // streaks keep the same size in pixels, so on a Retina display the haze
        // is half the physical size the streaks are drawn against. It is what the
        // scene has always looked like, so changing it is a visual decision
        // rather than a tidy-up — don't unify these without looking at the result.
        self.streakScale = Float(layout.scale * sceneScale)
        self.spriteScale = Float(sceneScale)
        self.hueShift = scene.hueShift
        self.chromaticAberration = scene.chromaticAberration
    }
}

struct BoltUniforms {
    /// rgb is the bolt's colour, a its current intensity.
    var color: SIMD4<Float>
}
