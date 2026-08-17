import Foundation
import SaverCore

/// One mote on the tunnel wall.
///
/// Nothing here changes after generation: a particle's position at any moment is
/// a pure function of these constants and the clock, so the whole field lives in
/// one immutable GPU buffer and the CPU never touches it again. That is the
/// reason 5400 particles cost nothing per frame.
///
/// The field order and `Float` width are load-bearing — `Vortex.metal` declares
/// the same struct and the buffer is handed to the GPU as raw memory.
/// `ParticleLayoutTests` checks the two have not drifted.
public struct Particle: Equatable {
    public var angle: Float
    public var radius: Float
    /// Position along the tunnel at clock zero.
    public var z0: Float
    public var speed: Float
    /// Index into the shaders' four-colour palette, coldest to hottest.
    public var hue: Float
    public var brightness: Float
    /// Rotation around the tunnel axis, per unit clock.
    public var swirl: Float
    public var wobbleAmplitude: Float
    public var wobbleFrequency: Float
    public var wobblePhase: Float
    /// Phase offset so particles do not all twinkle in step.
    public var twinklePhase: Float
    /// 0 for a streak, 1 for a glint, 2 for a haze puff. Unused by the streak
    /// shader, but kept in the shared struct so both buffers have one layout.
    public var kind: Float
}

public enum ParticleKind {
    public static let streak: Float = 0
    public static let glint: Float = 1
    public static let haze: Float = 2
}

/// The particle field, split by how it is drawn.
///
/// Streaks are stretched quads and sprites are round points — different
/// primitives and different shaders — so they are partitioned once at
/// generation rather than being sorted every frame.
public struct ParticleSet {
    public let streaks: [Particle]
    public let sprites: [Particle]

    /// Generates the field. Seeded, so a given seed always produces the same
    /// tunnel — which is what makes a rendered frame worth asserting on.
    public init(count: Int = Tunnel.particleCount, seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var streaks: [Particle] = []
        var sprites: [Particle] = []
        streaks.reserveCapacity(count)
        sprites.reserveCapacity(count / 4)

        for _ in 0..<count {
            // Weighted toward the cool end: the rare near-white particles read as
            // highlights only because most of the field is dimmer and bluer.
            let roll = rng.nextDouble()
            let hue: Float = roll < 0.07 ? 3 : (roll < 0.32 ? 2 : (roll < 0.75 ? 1 : 0))

            var particle = Particle(
                angle: Float(rng.nextDouble() * 2 * .pi),
                // Clustered just outside the nominal radius so the wall has
                // thickness rather than being a perfect cylinder.
                radius: Float(Tunnel.radius * (0.85 + rng.nextDouble() * 0.25)),
                z0: Float(Tunnel.zNear + rng.nextDouble() * Tunnel.zRange),
                speed: Float(0.0014 + rng.nextDouble() * 0.0020),
                hue: hue,
                brightness: Float(0.5 + rng.nextDouble() * 0.9),
                swirl: Float((rng.nextDouble() - 0.5) * 0.00035),
                wobbleAmplitude: Float(0.02 + rng.nextDouble() * 0.05),
                wobbleFrequency: Float(0.0008 + rng.nextDouble() * 0.0014),
                wobblePhase: Float(rng.nextDouble() * 2 * .pi),
                twinklePhase: Float(rng.nextDouble() * 2 * .pi),
                kind: ParticleKind.streak)

            let role = rng.nextDouble()
            if role < 0.10 {
                particle.kind = ParticleKind.glint
                sprites.append(particle)
            } else if role < 0.22 {
                particle.kind = ParticleKind.haze
                sprites.append(particle)
            } else {
                streaks.append(particle)
            }
        }

        self.streaks = streaks
        self.sprites = sprites
    }
}
