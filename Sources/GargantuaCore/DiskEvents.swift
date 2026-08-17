import Foundation
import SaverCore

/// A clump of hot gas going round.
///
/// The fastest legible motion in the frame: the disk is axisymmetric, so
/// without something to follow, a whole revolution reads as almost nothing.
struct HotSpot {
    let radius: Double
    let phase: Double
    let born: Double
    let life: Double
    /// Bright enough to notice, not so bright it becomes the subject.
    let peak: Double
}

/// The transient events on top of the steady disk: orbiting hot spots, and
/// occasional whole-disk flares.
///
/// Spot angles are turned here rather than in the shader for two reasons. The
/// angle grows without bound, and a float32 that large eventually cannot resolve
/// one frame's worth of motion. It also lifts a square root, a divide and two
/// transcendentals out of a loop running per sample per spot.
public struct DiskEvents {

    /// Three at once is the ceiling: wider or more numerous and they merge into
    /// one bright swathe, so the disk reads as lopsided rather than as clumps
    /// going round. Must match `SPOT_COUNT` in the shader.
    public static let maxSpots = 3

    /// Packed for the shader as (radius, cos(angle), sin(angle), strength).
    public private(set) var spots = [SIMD4<Float>](repeating: .zero, count: maxSpots)
    /// Packed as (arc width in radians of sigma, 1 / radial width, 0, 0).
    public private(set) var spotShapes = [SIMD4<Float>](repeating: .zero, count: maxSpots)
    /// Whole-disk brightness multiplier, normally 1.
    public private(set) var flare: Double = 1

    private var live: [HotSpot] = []
    private var nextSpotAt: Double = 6
    private var flareUntil: Double = -1
    private var flarePeak: Double = 1
    private var nextFlareAt: Double = 40
    private var rng: SplitMix64

    public init(seed: UInt64 = 0x6A56_1E01) {
        self.rng = SplitMix64(seed: seed)
    }

    /// How far the gas has turned, as an argument for omegaK. Held in double
    /// precision and never handed over raw — everything the shader receives is
    /// folded into something bounded first.
    public static func churn(time t: Double, parameters p: SceneParameters) -> Double {
        p.spinSign * p.turbSpeed * p.pace * t
    }

    public mutating func update(time t: Double, parameters p: SceneParameters) {
        let rate = 1 / max(p.pace, 0.05)

        if t > nextSpotAt && live.count < Self.maxSpots {
            // Placed just outside the ISCO, where the orbital period is
            // shortest. The life is a fraction of one lap at that radius,
            // computed from the same omegaK and churn rate the shader sweeps it
            // with, so a spot still dies about where its tail says it should
            // when spin or churn change.
            let radius = p.diskInnerRadius * (1.02 + rng.nextDouble() * 1.15)
            let lapRate =
                p.turbSpeed * p.pace
                * abs(KerrGeometry.omega(radius: radius, spin: p.signedSpin))
            let life = (0.37 + rng.nextDouble() * 0.59) * 2 * .pi / max(lapRate, 1e-3)
            live.append(
                HotSpot(
                    radius: radius,
                    phase: rng.nextDouble() * 2 * .pi,
                    born: t,
                    life: life,
                    peak: 0.10 + rng.nextDouble() * 0.30))
            nextSpotAt = t + (6 + rng.nextDouble() * 17) * rate
        }
        live.removeAll { t - $0.born > $0.life }

        // Overwritten in place: replacing them would be two heap allocations a
        // frame to express "mostly zeroes".
        for i in 0..<Self.maxSpots {
            spots[i] = .zero
            spotShapes[i] = .zero
        }
        guard !live.isEmpty else {
            updateFlare(time: t, rate: rate)
            return
        }

        let churn = Self.churn(time: t, parameters: p)
        let half = p.diskHalfCoefficients
        for (i, spot) in live.enumerated() where i < Self.maxSpots {
            let age = (t - spot.born) / spot.life
            // Fades up and back down over its life, so a spot never appears or
            // vanishes at full brightness.
            let envelope = sin(min(max(age, 0), 1) * .pi)
            let angle =
                spot.phase
                + churn * KerrGeometry.omega(radius: spot.radius, spin: p.signedSpin)
            spots[i] = SIMD4(
                Float(spot.radius),
                Float(cos(angle)),
                Float(sin(angle)),
                Float(spot.peak * envelope * envelope))
            let thickness = max(half.a * spot.radius + half.b, half.min)
            spotShapes[i] = SIMD4(
                Float(0.40 + age * 0.60),
                Float(1 / (thickness * 1.5 + 0.25)),
                0, 0)
        }

        updateFlare(time: t, rate: rate)
    }

    private mutating func updateFlare(time t: Double, rate: Double) {
        if t > nextFlareAt {
            flareUntil = t + (4 + rng.nextDouble() * 6) * rate
            // Stacks with the hot spots, so it stays modest.
            flarePeak = 1.20 + rng.nextDouble() * 0.45
            nextFlareAt = flareUntil + (28 + rng.nextDouble() * 70) * rate
        }
        if t < flareUntil {
            let k = 1 - (flareUntil - t) / 12
            flare = 1 + (flarePeak - 1) * sin(min(max(k, 0), 1) * .pi)
        } else {
            flare = 1
        }
    }
}

/// The differential winding phase handed to the shader.
///
/// The disk pattern needs a finite memory. Winding neighbouring radii apart
/// forever destroys it: the shear grows without bound, and after a few minutes
/// the pattern is finer than a pixel, so the prefilter averages it into smooth
/// axisymmetric rings. Real disks avoid this because their eddies regenerate on
/// roughly an orbital timescale.
///
/// So the winding is a rigid carrier — folded to one turn here, which is exact
/// since rotation is 2pi-periodic, and keeps the angle resolvable in float32
/// however long it has run — plus a differential sawtooth of unit slope. Unit
/// slope is the point: the instantaneous rate at every radius is still exactly
/// Omega(r), so the differential rotation is as correct as it ever was. Only the
/// accumulated history is discarded, and it is discarded under a cross-fade with
/// a second copy half a cycle out of phase, so the reset is never visible.
public struct WindPhase {
    /// The rigid carrier angle, within one turn.
    public let rigid: Double
    /// Phase A, phase B, and the blend between them.
    public let differential: SIMD3<Float>

    public init(time t: Double, parameters p: SceneParameters) {
        let churn = DiskEvents.churn(time: t, parameters: p)
        rigid = (churn * p.omegaReference).truncatingRemainder(dividingBy: 2 * .pi)

        let period = p.windPeriod
        let x = churn / period - (churn / period).rounded(.down)
        // Hands over from one phase to the other while the one about to reset is
        // invisible, and rests on a single layer for the 60% of the cycle in the
        // middle — so the second pattern evaluation is only paid for while it is
        // actually being seen.
        let u = abs(x - 0.5)
        let s = min(max((u - 0.15) / 0.20, 0), 1)
        differential = SIMD3(
            Float((x - 0.5) * period),
            Float(((x + 0.5).truncatingRemainder(dividingBy: 1) - 0.5) * period),
            Float(s * s * (3 - 2 * s)))
    }
}
