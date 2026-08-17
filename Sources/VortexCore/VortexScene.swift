import Foundation
import SaverKit

/// The whole simulation: what time it is for the particles, where the tunnel is
/// pointing, and what lightning is currently alive.
///
/// There is no per-particle work here. The field is static and the shaders
/// evaluate it from the clock, so a frame's CPU cost is a handful of sines
/// regardless of how many particles there are.
public final class VortexScene {

    public let particles: ParticleSet
    public let settings: VortexSettings
    public private(set) var layout: Layout

    /// Real elapsed time. Drives everything ambient — drift, spin, twinkle.
    public private(set) var elapsedMs: Double = 0

    /// The particles' own clock, which runs fast and slow relative to real time.
    ///
    /// Decoupling the two is what lets the tunnel breathe: the flow speeds up and
    /// slows down without the background, the lightning cadence or the colour
    /// drift speeding up with it.
    public private(set) var particleClockMs: Double = 0

    /// Current deviation from normal flow speed, roughly -0.35...+0.55.
    public private(set) var warp: Double = 0

    public private(set) var tubeSpin: Double = 0

    public private(set) var bolts: [Bolt] = []

    /// Live shockwaves packed for the shaders, always four entries — unused
    /// slots are zeroed, which the shaders skip.
    public private(set) var shockUniforms = [SIMD4<Float>](repeating: .zero, count: 4)

    /// Bend target and its eased follower, both in units of `maxBendPixels`.
    private var bendX: Double = 0
    private var bendY: Double = 0

    private var shocks: [Shock] = []
    /// First strike lands shortly after startup, so the scene is not silent for
    /// the first half-minute.
    private var nextBoltAtMs: Double = 1200
    private var rng: SplitMix64

    public init(
        layout: Layout,
        settings: VortexSettings = .default,
        seed: UInt64 = 0x5EED_1234
    ) {
        self.layout = layout
        self.settings = settings
        self.particles = ParticleSet(count: settings.particleCount, seed: seed)
        // A separate stream from the particle field, so changing the density does
        // not also change when the lightning strikes.
        self.rng = SplitMix64(seed: seed &* 31 &+ 7)
    }

    // MARK: - Frame

    /// Advances everything by `deltaTime` seconds.
    public func update(deltaTime: Double, layout: Layout) {
        self.layout = layout

        // A long gap — the display slept, or the saver was paused — must not be
        // integrated as if it really happened, or the tunnel lurches on wake.
        let dt = min(48, max(0, deltaTime * 1000))
        elapsedMs += dt

        // Two sines at incommensurate periods (~22s and ~15s), so the breathing
        // never settles into an audible loop. Biased positive so the tunnel
        // spends more time accelerating than braking.
        warp =
            0.10
            + sin(elapsedMs * 0.00028) * 0.28
            + sin(elapsedMs * 0.00041 + 1.7) * 0.18
        particleClockMs += dt * max(0.5, 1 + warp) * settings.flowSpeed

        advanceShocks(by: dt)
        steer(by: dt)
        advanceBolts(by: dt)
    }

    /// The tunnel flies itself, wandering on a sum of sines and rolling into
    /// whichever direction it is heading.
    private func steer(by dt: Double) {
        let t = elapsedMs
        let targetX =
            0.55 * sin(t * 0.00013)
            + 0.30 * sin(t * 0.00029 + 1.7)
            + 0.12 * sin(t * 0.00047 + 3.1)
        let targetY =
            0.55 * sin(t * 0.00017 + 0.9)
            + 0.30 * sin(t * 0.00023 + 2.3)
            + 0.12 * sin(t * 0.00041 + 0.4)

        // Exponential easing. Expressed per-millisecond rather than per-frame so
        // the tunnel wanders at the same rate on a 60Hz and a 120Hz display.
        let ease = 1 - pow(1 - 0.055, dt / 16.6667)
        bendX += (targetX - bendX) * ease
        bendY += (targetY - bendY) * ease

        // Rotation follows the lean: the tunnel spins one way when bending left
        // and the other when bending right, faster the harder it leans, with a
        // soft deadzone through the middle so it never snaps direction.
        let lean = bendX
        let direction: Double = lean == 0 ? 1 : (lean < 0 ? -1 : 1)
        tubeSpin += 0.00028 * (0.15 + abs(lean) * 1.35) * direction * dt
    }

    // MARK: - Lightning

    private func advanceBolts(by dt: Double) {
        for i in bolts.indices { bolts[i].advance(byMs: dt) }
        bolts.removeAll { $0.isFinished }

        guard settings.lightning, elapsedMs > nextBoltAtMs else { return }
        // Occasionally a double strike, which is what stops the cadence reading
        // as a metronome.
        let strikes = rng.nextDouble() < 0.08 ? 2 : 1
        for _ in 0..<strikes { strike() }
        nextBoltAtMs = elapsedMs + 22_000 + rng.nextDouble() * 16_000
    }

    private func strike() {
        let bend = bendPixels
        guard
            let bolt = Bolt(
                layout: layout,
                bendX: Double(bend.x), bendY: Double(bend.y),
                spin: tubeSpin,
                rng: &rng)
        else { return }

        bolts.append(bolt)
        shocks.append(
            Shock(origin: bolt.origin, lifetimeMs: 900 + rng.nextDouble() * 400))
    }

    private func advanceShocks(by dt: Double) {
        for i in shocks.indices { shocks[i].advance(byMs: dt) }
        shocks.removeAll { $0.isFinished }

        // Four is what the shaders read. Beyond that the extra rings overlap into
        // a wash anyway, so the oldest four win and the rest are simply not drawn.
        for slot in 0..<4 {
            shockUniforms[slot] =
                slot < shocks.count
                ? shocks[slot].packed(maxRadius: layout.maxShockRadius)
                : .zero
        }
    }

    // MARK: - Derived, for the renderer

    /// How far the tunnel's far end is pushed off-centre, in pixels.
    public var bendPixels: SIMD2<Float> {
        SIMD2(
            Float(bendX * layout.maxBendPixels),
            Float(bendY * layout.maxBendPixels))
    }

    /// Where the tunnel appears to converge. Trails the bend rather than
    /// matching it, so the mouth of the tunnel stays partly in view.
    public var vanishingPoint: SIMD2<Float> {
        let bend = bendPixels
        return SIMD2(
            Float(layout.centerX) + bend.x * 0.75,
            Float(layout.centerY) + bend.y * 0.75)
    }

    /// How far back in the particle clock a streak's tail is drawn. Longer when
    /// the flow is fast, so speed reads as motion blur rather than just distance
    /// covered.
    public var streakTailMs: Float {
        Float(140 * (0.85 + warp * 0.4))
    }

    /// A slow drift in the overall colour, kept to a narrow arc so the scene
    /// stays in the blue-cyan family and never wanders warm.
    public var hueShift: Float {
        Float(-0.02 + sin(elapsedMs * 0.00006) * 0.07)
    }

    /// Chromatic aberration strength, growing with both lean and speed.
    public var chromaticAberration: Float {
        let lean = (bendX * bendX + bendY * bendY).squareRoot()
        return Float((2.0 + lean * 12.0 + max(0, warp) * 4.0) * layout.scale)
    }
}
