import Foundation
import SaverKit

/// Where a set of initial conditions came from, which is also roughly how it
/// will behave on screen.
public enum ScenarioFamily: String, CaseIterable {
    /// Known closed-orbit solutions — they retrace the same figure forever
    /// (until chaos amplifies the truncation in the published constants).
    case periodic
    /// Textbook analytic configurations: Lagrange, Euler, Burrau.
    case classical
    /// Binary plus a distant companion; the only long-term-stable arrangement
    /// a real triple system tends to survive in.
    case hierarchical
    /// Randomised bound systems that mix, exchange partners and eventually
    /// eject a body.
    case chaotic
    /// A binary meeting an intruder arriving from outside the system.
    case flyby

    public var displayName: String {
        switch self {
        case .periodic: return "Periodic orbits"
        case .classical: return "Classical solutions"
        case .hierarchical: return "Hierarchical triples"
        case .chaotic: return "Chaotic / free-fall"
        case .flyby: return "Flyby encounters"
        }
    }
}

/// A complete, ready-to-integrate initial condition.
public struct Scenario {
    public let name: String
    /// Provenance or a one-line description, shown in the HUD.
    public let credit: String
    public let family: ScenarioFamily
    public let bodies: [Body]
    /// Simulated time units per real second — tuned per scenario so the motion
    /// reads well rather than crawling or blurring.
    public let timeScale: Double
    /// Known period in system units, where the solution has one.
    public let period: Double?

    public var system: NBodySystem {
        var s = NBodySystem(bodies: bodies)
        s.moveToCenterOfMassFrame()
        return s
    }
}

public enum Scenarios {

    // MARK: - Catalogue of known solutions

    /// The Šuvakov–Dmitrašinović families all share the same setup: three unit
    /// masses with G = 1, two of them at (∓1, 0) and one at the origin, with
    /// velocities (p₁, p₂), (p₁, p₂) and (−2p₁, −2p₂) so that the total
    /// momentum vanishes. Only the pair (p₁, p₂) distinguishes them.
    private static func suvakov(
        _ name: String,
        _ p1: Double,
        _ p2: Double,
        period: Double
    ) -> Scenario {
        let v = Vec2(p1, p2)
        return Scenario(
            name: name,
            credit: "Šuvakov & Dmitrašinović 2013 · period \(Units.formatTime(period))",
            family: .periodic,
            bodies: [
                Body(mass: 1, position: Vec2(-1, 0), velocity: v),
                Body(mass: 1, position: Vec2(1, 0), velocity: v),
                Body(mass: 1, position: .zero, velocity: -2 * v),
            ],
            // Aim for roughly a dozen seconds per revolution.
            timeScale: period / 12.0,
            period: period
        )
    }

    /// Period of the figure-eight for exactly these initial conditions, found
    /// by minimising the return distance in phase space (Tests/main.swift
    /// re-checks it). The orbit closes on itself to ~2e-9 here, so the eight
    /// digits in the positions and velocities below are doing their job.
    public static let figureEightPeriod = 6.325914012

    public static let figureEight: Scenario = {
        // Chenciner & Montgomery's figure-eight: three equal masses chasing
        // each other around the same closed curve, 120° apart in phase.
        let v3 = Vec2(-0.93240737, -0.86473146)
        let r1 = Vec2(0.97000436, -0.24308753)
        return Scenario(
            name: "Figure Eight",
            credit: "Moore 1993 · Chenciner & Montgomery 2000 · period "
                + Units.formatTime(figureEightPeriod),
            family: .periodic,
            bodies: [
                Body(mass: 1, position: r1, velocity: -0.5 * v3),
                Body(mass: 1, position: -r1, velocity: -0.5 * v3),
                Body(mass: 1, position: .zero, velocity: v3),
            ],
            timeScale: figureEightPeriod / 11.0,
            period: figureEightPeriod
        )
    }()

    /// Lagrange's L4/L5 solution: an equilateral triangle rotating rigidly.
    ///
    /// Exact for any masses; with equal masses at circumradius r = a/√3 the
    /// balance of the two mutual attractions against the centripetal
    /// requirement gives ω² = 3Gm/a³, hence ω = √3 and orbital speed 1 for
    /// a = m = G = 1.
    public static let lagrange: Scenario = {
        let a = 1.0
        let r = a / 3.0.squareRoot()
        let omega = (3.0 / (a * a * a)).squareRoot()
        var bodies: [Body] = []
        for k in 0..<3 {
            let theta = Double(k) * 2.0 * Double.pi / 3.0
            let p = Vec2(cos(theta), sin(theta)) * r
            // v = ω × r, i.e. perpendicular to the radius.
            let v = Vec2(-p.y, p.x) * omega
            bodies.append(Body(mass: 1, position: p, velocity: v))
        }
        let period = 2.0 * Double.pi / omega
        return Scenario(
            name: "Lagrange Triangle",
            credit: "Lagrange 1772 · equilateral, rigidly rotating · period "
                + Units.formatTime(period),
            family: .classical,
            bodies: bodies,
            timeScale: period / 9.0,
            period: period
        )
    }()

    /// Euler's collinear solution: three masses on a rotating straight line.
    ///
    /// For equal masses the middle one sits at the centre with the two pulls
    /// cancelling, and each outer body feels Gm²/d² from the centre plus
    /// Gm²/(2d)² from its opposite number, giving ω² = 1.25·Gm/d³.
    ///
    /// It is an exact solution and it is linearly unstable, so the tiniest
    /// rounding error grows until the line collapses into a chaotic scramble —
    /// which is the point of showing it. (So is the equal-mass Lagrange
    /// triangle above: 27·Σm_i m_j / (Σm)² = 9 > 1 puts it well outside the
    /// Gascheau stability limit, and it survives about eight revolutions before
    /// round-off tears it apart.)
    public static let euler: Scenario = {
        let d = 1.0
        let omega = (1.25 / (d * d * d)).squareRoot()
        let period = 2.0 * Double.pi / omega
        return Scenario(
            name: "Euler Collinear",
            credit: "Euler 1767 · exact, and unstable — watch it break · period "
                + Units.formatTime(period),
            family: .classical,
            bodies: [
                Body(mass: 1, position: Vec2(-d, 0), velocity: Vec2(0, -omega * d)),
                Body(mass: 1, position: .zero, velocity: .zero),
                Body(mass: 1, position: Vec2(d, 0), velocity: Vec2(0, omega * d)),
            ],
            timeScale: period / 9.0,
            period: period
        )
    }()

    /// Burrau's problem (1913): masses 3, 4, 5 released from rest at the
    /// vertices of a 3-4-5 right triangle, each mass opposite the side of the
    /// same length. It plunges through a long series of near-collisions before
    /// ejecting the lightest body around t ≈ 60 — the canonical demonstration
    /// that a generic triple system does not last.
    public static let pythagorean = Scenario(
        name: "Pythagorean Problem",
        credit: "Burrau 1913 · released from rest · ejection near "
            + Units.formatTime(60),
        family: .classical,
        bodies: [
            Body(mass: 3, position: Vec2(1, 3), velocity: .zero),
            Body(mass: 4, position: Vec2(-2, -1), velocity: .zero),
            Body(mass: 5, position: Vec2(1, -1), velocity: .zero),
        ],
        timeScale: 1.6,
        period: nil
    )

    /// The Šuvakov–Dmitrašinović zoo. Published to five or six figures, which
    /// is enough for many periods before Lyapunov growth pulls them apart.
    public static let periodicFamilies: [Scenario] = [
        figureEight,
        suvakov("Butterfly I", 0.30689, 0.12551, period: 6.2356),
        suvakov("Butterfly II", 0.39295, 0.09758, period: 7.0039),
        suvakov("Bumblebee", 0.18428, 0.58719, period: 63.5345),
        suvakov("Moth I", 0.46444, 0.39606, period: 14.8939),
        suvakov("Moth II", 0.43917, 0.45297, period: 28.6703),
        suvakov("Moth III", 0.38344, 0.37736, period: 25.8406),
        suvakov("Goggles", 0.08330, 0.12789, period: 10.4668),
        suvakov("Dragonfly", 0.08058, 0.58884, period: 21.2710),
        suvakov("Yarn", 0.55906, 0.34919, period: 55.5018),
        suvakov("Yin-Yang I", 0.51394, 0.30474, period: 17.3284),
    ]

    public static let classicalFamilies: [Scenario] = [
        lagrange,
        euler,
        pythagorean,
    ]

    public static var catalogue: [Scenario] { periodicFamilies + classicalFamilies }

    // MARK: - Generated scenarios

    /// Place two masses on a Keplerian two-body orbit about their common
    /// centre of mass, starting at apoapsis.
    ///
    /// Vis-viva gives the relative speed: v² = G·M·(2/r − 1/a). At apoapsis
    /// r = a(1 + e) and the velocity is perpendicular to the separation, so the
    /// whole orbit follows from (a, e) and a phase angle.
    /// `sense` is +1 for a counter-clockwise orbit and −1 for a clockwise one.
    /// Without it every generated system rotated the same way, which is a
    /// symmetry real systems do not have.
    private static func keplerPair(
        m1: Double,
        m2: Double,
        semiMajorAxis a: Double,
        eccentricity e: Double,
        phase: Double,
        sense: Double = 1,
        gravitationalConstant: Double = 1.0
    ) -> (r1: Vec2, v1: Vec2, r2: Vec2, v2: Vec2) {
        let totalMass = m1 + m2
        let r = a * (1 + e)
        let speed = (gravitationalConstant * totalMass * (2.0 / r - 1.0 / a)).squareRoot()
        let sep = Vec2(cos(phase), sin(phase)) * r
        let vel = Vec2(-sin(phase), cos(phase)) * (speed * sense)
        // Split the relative vector about the centre of mass.
        return (
            r1: sep * (m2 / totalMass), v1: vel * (m2 / totalMass),
            r2: sep * (-m1 / totalMass), v2: vel * (-m1 / totalMass)
        )
    }

    /// Screen pacing derived from the system's own dynamical time.
    ///
    /// A hard-coded rate cannot survive a change of physical scale: widening
    /// the generated systems from a couple of AU to a couple of dozen makes
    /// their natural timescale over ten times longer, and a fixed rate would
    /// leave them looking frozen. The crossing time √(r³/GM) is the only
    /// sensible reference.
    private static func pacing(
        extent: Double,
        totalMass: Double,
        secondsPerCrossing: Double
    ) -> Double {
        let crossing = (extent * extent * extent / Swift.max(totalMass, 1e-9)).squareRoot()
        return crossing / secondsPerCrossing
    }

    /// A tight binary orbited by a distant third body — the arrangement that
    /// real triple stars settle into, because anything less hierarchical
    /// disrupts itself. The outer orbit is deliberately kept close enough for
    /// the perturbation to be visible in the inner pair's precession.
    public static func randomHierarchical(using rng: inout SplitMix64) -> Scenario {
        // Log-uniform masses across the stellar range, in solar masses: a red
        // dwarf paired with a B star is as likely as two suns.
        let m1 = rng.logUniform(0.3, 25.0)
        let m2 = rng.logUniform(0.3, 25.0)
        let m3 = rng.logUniform(0.2, 20.0)

        // Inner separation in AU, spanning close binaries to wide pairs.
        let innerA = rng.logUniform(1.5, 12.0)
        let innerE = rng.double(0.0, 0.55)
        let ratio = rng.logUniform(3.2, 14.0)
        let outerA = innerA * ratio
        let outerE = rng.double(0.0, 0.45)

        // Inner and outer orbits get independent senses: a counter-rotating
        // triple precesses quite differently from a co-rotating one.
        let innerSense: Double = rng.bool(0.5) ? 1 : -1
        let outerSense: Double = rng.bool(0.5) ? 1 : -1

        let inner = keplerPair(
            m1: m1, m2: m2,
            semiMajorAxis: innerA, eccentricity: innerE,
            phase: rng.double(0, 2 * .pi), sense: innerSense)
        let outer = keplerPair(
            m1: m1 + m2, m2: m3,
            semiMajorAxis: outerA, eccentricity: outerE,
            phase: rng.double(0, 2 * .pi), sense: outerSense)

        let bodies = [
            Body(mass: m1, position: inner.r1 + outer.r1, velocity: inner.v1 + outer.v1),
            Body(mass: m2, position: inner.r2 + outer.r1, velocity: inner.v2 + outer.v1),
            Body(mass: m3, position: outer.r2, velocity: outer.v2),
        ]

        let outerPeriod = 2.0 * Double.pi * (outerA * outerA * outerA / (m1 + m2 + m3)).squareRoot()
        return Scenario(
            name: "Hierarchical Triple",
            credit: String(
                format: "%@ + %@ · e_in = %.2f · %@ · %@ + %@ + %@",
                Units.formatDistance(innerA), Units.formatDistance(outerA), innerE,
                innerSense == outerSense ? "co-rotating" : "counter-rotating",
                Units.formatMass(m1), Units.formatMass(m2), Units.formatMass(m3)),
            family: .hierarchical,
            bodies: bodies,
            timeScale: outerPeriod / 20.0,
            period: nil
        )
    }

    /// Three masses in a random triangle, released either from rest or with a
    /// small random drift.
    ///
    /// From exact rest there is no angular momentum at all, so they fall
    /// straight through each other's paths and produce the violent
    /// near-collisions the three-body problem is famous for — Burrau's problem
    /// is the case that made it into print. Giving them a slight push instead
    /// adds just enough angular momentum to turn the plunge into a tumble,
    /// which looks quite different and is just as legitimate a starting state.
    public static func randomFreeFall(using rng: inout SplitMix64) -> Scenario {
        var positions: [Vec2] = []
        var attempts = 0
        while positions.count < 3 && attempts < 400 {
            attempts += 1
            let p = Vec2(rng.double(-30, 30), rng.double(-30, 30))
            if positions.allSatisfy({ ($0 - p).length > 14.0 }) {
                positions.append(p)
            }
        }
        while positions.count < 3 {
            let theta = Double(positions.count) * 2.1
            positions.append(Vec2(cos(theta), sin(theta)) * 25.0)
        }
        let masses = (0..<3).map { _ in rng.logUniform(0.4, 30.0) }

        // Two thirds of the time, start truly cold; otherwise give each body a
        // fraction of the speed it would need to circle the system's centre.
        let drift = rng.bool(0.34) ? rng.double(0.08, 0.45) : 0.0
        let totalMass = masses.reduce(0, +)
        var bodies = zip(masses, positions).map { mass, position -> Body in
            guard drift > 0 else { return Body(mass: mass, position: position, velocity: .zero) }
            let radius = max(position.length, 3.0)
            let circularSpeed = (totalMass / radius).squareRoot()
            let velocity =
                Vec2(rng.double(-1, 1), rng.double(-1, 1)).normalized
                * (circularSpeed * drift)
            return Body(mass: mass, position: position, velocity: velocity)
        }

        // Any net drift would just slide the whole scene sideways.
        var system = NBodySystem(bodies: bodies)
        system.moveToCenterOfMassFrame()
        bodies = system.bodies

        let extent = NBodySystem(bodies: bodies).maximumSeparation
        return Scenario(
            name: drift > 0 ? "Cold Collapse" : "Free Fall",
            credit: drift > 0
                ? String(
                    format: "released at %.0f%% of circular speed · %@ + %@ + %@",
                    drift * 100, Units.formatMass(masses[0]),
                    Units.formatMass(masses[1]), Units.formatMass(masses[2]))
                : String(
                    format: "released from rest · %@ + %@ + %@",
                    Units.formatMass(masses[0]), Units.formatMass(masses[1]),
                    Units.formatMass(masses[2])),
            family: .chaotic,
            bodies: bodies,
            timeScale: pacing(
                extent: extent,
                totalMass: masses.reduce(0, +),
                secondsPerCrossing: 11.0),
            period: nil
        )
    }

    /// A bound but thoroughly chaotic triple: random positions and velocities,
    /// rescaled to a chosen virial ratio 2T/|U|. Below 1 the system is bound;
    /// near 1 it is marginally so and tends to eject a body quickly.
    public static func randomChaotic(using rng: inout SplitMix64) -> Scenario {
        for _ in 0..<200 {
            var positions: [Vec2] = []
            var ok = true
            for _ in 0..<3 {
                var placed = false
                for _ in 0..<60 {
                    let p = Vec2(rng.double(-25, 25), rng.double(-25, 25))
                    if positions.allSatisfy({ ($0 - p).length > 11.0 }) {
                        positions.append(p)
                        placed = true
                        break
                    }
                }
                if !placed {
                    ok = false
                    break
                }
            }
            guard ok else { continue }

            let masses = (0..<3).map { _ in rng.logUniform(0.4, 25.0) }
            var bodies = zip(masses, positions).map {
                Body(
                    mass: $0, position: $1,
                    velocity: Vec2(rng.double(-1, 1), rng.double(-1, 1)))
            }
            var system = NBodySystem(bodies: bodies)
            system.moveToCenterOfMassFrame()
            bodies = system.bodies

            // Rescale velocities so 2T/|U| hits the target ratio exactly.
            let u = abs(system.potentialEnergy)
            let t = system.kineticEnergy
            guard t > 1e-9, u > 1e-9 else { continue }
            let targetRatio = rng.double(0.15, 0.95)
            let scale = (targetRatio * u / (2.0 * t)).squareRoot()
            for i in 0..<bodies.count { bodies[i].velocity *= scale }

            var scaled = NBodySystem(bodies: bodies)
            scaled.moveToCenterOfMassFrame()
            guard scaled.totalEnergy < 0 else { continue }

            return Scenario(
                name: "Chaotic Triple",
                credit: String(
                    format: "virial ratio 2T/|U| = %.2f · %@ + %@ + %@",
                    targetRatio, Units.formatMass(masses[0]),
                    Units.formatMass(masses[1]), Units.formatMass(masses[2])),
                family: .chaotic,
                bodies: scaled.bodies,
                timeScale: pacing(
                    extent: scaled.maximumSeparation,
                    totalMass: scaled.totalMass,
                    secondsPerCrossing: 13.0),
                period: nil
            )
        }
        // Fall back to something known-good rather than returning nothing.
        return pythagorean
    }

    /// A bound binary with a third body arriving from outside on an unbound
    /// hyperbolic trajectory.
    ///
    /// This is the encounter that actually builds and breaks triple systems in
    /// a star cluster, and it resolves in one of three ways depending on the
    /// impact parameter: a clean flyby, an exchange where the newcomer takes a
    /// partner and the old one is thrown out, or a temporary chaotic tangle
    /// before somebody leaves. None of the other generators produce anything
    /// that looks like it.
    public static func randomFlyby(using rng: inout SplitMix64) -> Scenario {
        let m1 = rng.logUniform(0.5, 20.0)
        let m2 = rng.logUniform(0.5, 20.0)
        let m3 = rng.logUniform(0.3, 25.0)

        let binaryA = rng.logUniform(2.0, 10.0)
        let binary = keplerPair(
            m1: m1, m2: m2,
            semiMajorAxis: binaryA,
            eccentricity: rng.double(0.0, 0.4),
            phase: rng.double(0, 2 * .pi),
            sense: rng.sign())

        // Aim the intruder at the binary from a distance, offset by an impact
        // parameter of a few binary separations — near zero is a head-on
        // disruption, a few times the separation is a distant flyby.
        let startDistance = binaryA * rng.double(9.0, 16.0)
        let impactParameter = rng.double(0.0, 3.0) * binaryA
        let approach = rng.double(0, 2 * .pi)
        let inbound = Vec2(cos(approach), sin(approach))
        let sideways = Vec2(-inbound.y, inbound.x)

        // Speed at infinity, as a fraction of the binary's own orbital speed:
        // slow encounters are the ones that tangle rather than pass through.
        let binarySpeed = ((m1 + m2) / binaryA).squareRoot()
        let speedAtInfinity = binarySpeed * rng.double(0.12, 0.55)
        let totalMass = m1 + m2 + m3
        // Energy conservation from infinity down to the starting distance.
        let arrivalSpeed =
            (speedAtInfinity * speedAtInfinity
            + 2.0 * totalMass / startDistance).squareRoot()

        let intruderPosition = inbound * startDistance + sideways * impactParameter
        let intruderVelocity = -inbound * arrivalSpeed

        var system = NBodySystem(bodies: [
            Body(mass: m1, position: binary.r1, velocity: binary.v1),
            Body(mass: m2, position: binary.r2, velocity: binary.v2),
            Body(mass: m3, position: intruderPosition, velocity: intruderVelocity),
        ])
        system.moveToCenterOfMassFrame()

        // Pace it so the approach takes a leisurely ten seconds or so: the
        // encounter itself resolves quickly once it arrives, and rushing the
        // run-in leaves nothing to watch.
        let crossingTime = startDistance / max(arrivalSpeed, 1e-6)
        return Scenario(
            name: "Flyby Encounter",
            credit: String(
                format: "%@ intruder at %@ · impact parameter %@ · binary %@ + %@ at %@",
                Units.formatMass(m3),
                Units.formatSpeed(speedAtInfinity),
                Units.formatDistance(impactParameter),
                Units.formatMass(m1), Units.formatMass(m2),
                Units.formatDistance(binaryA)),
            family: .flyby,
            bodies: system.bodies,
            timeScale: crossingTime / 13.0,
            period: nil
        )
    }

    /// Families whose scenes are made up fresh each time, rather than replayed
    /// from fixed initial conditions.
    public static let generativeFamilies: [ScenarioFamily] = [.hierarchical, .chaotic, .flyby]

    private static func generateOnce(
        _ family: ScenarioFamily,
        using rng: inout SplitMix64
    ) -> Scenario {
        switch family {
        case .hierarchical:
            return randomHierarchical(using: &rng)
        case .chaotic:
            return rng.bool(0.5) ? randomFreeFall(using: &rng) : randomChaotic(using: &rng)
        case .flyby:
            return randomFlyby(using: &rng)
        case .periodic, .classical:
            return figureEight  // not generative; never reached
        }
    }

    /// Minimum simulated time a generated system must survive, expressed in
    /// the seconds of screen time it corresponds to. A scene that resolves
    /// itself in the first few seconds is a dud, however valid its physics.
    public static let minimumScreenSeconds: Double = 25.0
    /// Generate a scene of the given family, discarding ones that die young.
    ///
    /// Flybys are exempt: resolving quickly is the entire point of an
    /// encounter, and the interesting part is the approach and the exchange,
    /// not what happens afterwards.
    private static func generate(
        _ family: ScenarioFamily,
        using rng: inout SplitMix64
    ) -> Scenario {
        guard family != .flyby else { return generateOnce(family, using: &rng) }

        // Vetting runs inline on the animation thread at a scene change, so the
        // budget is shared across all attempts rather than granted per attempt:
        // twelve expensive candidates in a row would otherwise stall for tens
        // of milliseconds — several dropped frames.
        // 8,000 steps is about eight milliseconds of integration at the tier
        // vetting uses — half a frame, and enough for roughly six typical
        // candidates.
        var stepsRemaining = 8_000
        var best: (scenario: Scenario, survived: Double)?
        for _ in 0..<12 {
            let candidate = generateOnce(family, using: &rng)
            let horizon = candidate.timeScale * minimumScreenSeconds
            let outcome = SceneVetting.evaluate(
                candidate,
                horizon: horizon,
                stepBudget: stepsRemaining)
            if outcome.survivedHorizon { return candidate }
            stepsRemaining -= outcome.stepsUsed
            if stepsRemaining <= 0 { break }
            // Keep the best of a bad lot rather than falling back to something
            // arbitrary if every attempt is short-lived.
            let relative = outcome.survivedFor / max(horizon, 1e-12)
            if best == nil || relative > best!.survived {
                best = (candidate, relative)
            }
        }
        return best?.scenario ?? generateOnce(family, using: &rng)
    }

    /// Pick a scenario from the enabled families, avoiding immediate repeats.
    ///
    /// Catalogue entries are drawn *individually* rather than by family, so the
    /// three classical solutions don't each turn up four times as often as each
    /// of the eleven periodic ones. The generated families are then weighted so
    /// that, with everything enabled, the fixed and generated pools get equal
    /// overall share instead of the catalogue's sheer count swamping them.
    public static func random(
        families: Set<ScenarioFamily>,
        excluding recent: [String],
        using rng: inout SplitMix64
    ) -> Scenario {
        let enabled = families.isEmpty ? Set(ScenarioFamily.allCases) : families

        // Stably ordered: a Set's storage order depends on Swift's per-process
        // hash seed, so drawing from one directly would make a seeded run
        // unreproducible between launches.
        let fixedPool = catalogue.filter { enabled.contains($0.family) }
        let generativePool = generativeFamilies.filter(enabled.contains)

        guard !generativePool.isEmpty else {
            // Catalogue only.
            for _ in 0..<40 {
                guard let candidate = fixedPool.randomElement(using: &rng) else { break }
                if !recent.contains(candidate.name) { return candidate }
            }
            return fixedPool.randomElement(using: &rng) ?? figureEight
        }
        guard !fixedPool.isEmpty else {
            // Generated only.
            guard let family = generativePool.randomElement(using: &rng) else { return figureEight }
            return generate(family, using: &rng)
        }

        // Both pools: give each half the same total weight.
        let generativeWeight = Double(fixedPool.count) / Double(generativePool.count)
        let total = Double(fixedPool.count) + generativeWeight * Double(generativePool.count)

        for _ in 0..<40 {
            let draw = rng.double(0, total)
            if draw < Double(fixedPool.count) {
                let candidate = fixedPool[min(Int(draw), fixedPool.count - 1)]
                // Only the fixed entries can actually repeat.
                if !recent.contains(candidate.name) { return candidate }
            } else {
                let index = Int((draw - Double(fixedPool.count)) / generativeWeight)
                return generate(generativePool[min(index, generativePool.count - 1)], using: &rng)
            }
        }
        return generate(generativePool[0], using: &rng)
    }
}
