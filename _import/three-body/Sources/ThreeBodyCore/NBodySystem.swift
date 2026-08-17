import Foundation

/// A single point mass. The simulation is pure Newtonian gravity between point
/// masses — no softening, no collision merging — so close encounters produce
/// genuine slingshots rather than smoothed-out approximations. The radius is a
/// rendering-only quantity.
public struct Body {
    public var mass: Double
    public var position: Vec2
    public var velocity: Vec2
}

/// The gravitational N-body system.
///
/// Units are dimensionless with G = 1; every scenario is specified in those
/// units, which is the convention used in the literature for the periodic
/// three-body solutions bundled with this screensaver.
public struct NBodySystem {

    /// Constants that describe the physical model rather than any one part of
    /// the program. They live here because several places must agree on them:
    /// the engine detects collisions and escapes with these, scene vetting
    /// pre-checks candidates against the same thresholds, and the tests assert
    /// against them. Three separate literals, each with a comment promising it
    /// matched the others, is how they quietly drift apart.
    public enum Contact {
        /// Radius of a body holding the system's entire mass, as a fraction of
        /// the scene's extent; individual radii scale as the cube root of mass
        /// fraction from there.
        ///
        /// Chosen by measurement. Over 45 multi-hour runs the collision rate
        /// and its victims both move with it:
        ///
        ///     4e-6 → 8.9% of scenes, including Yarn ×22
        ///     2e-6 → 7.7% of scenes, including Yarn ×22
        ///     1e-6 → 3.7% of scenes, only Free Fall and Chaotic Triple
        ///     5e-7 → 2.9% of scenes, only Free Fall and Chaotic Triple
        ///
        /// Yarn is the discriminator. Its published constants carry five
        /// decimals, so after a dozen periods it has drifted off the exact
        /// orbit and starts making genuinely chaotic close passes — at 2e-6
        /// those reach contact and a famous periodic solution ends in a
        /// collision, which misrepresents it. 1e-6 keeps every catalogued orbit
        /// intact while still resolving the singular encounters in the families
        /// where a collision is the honest outcome.
        public static let scale: Double = 1e-6

        /// How far the third body must be, as a multiple of the binary's
        /// separation, before its positive energy counts as a real escape
        /// rather than a wide excursion it will come back from.
        public static let escapeDistanceRatio: Double = 12.0
    }
    public var bodies: [Body]
    public var gravitationalConstant: Double
    /// Elapsed simulated time in system units.
    public var time: Double

    public init(bodies: [Body], gravitationalConstant: Double = 1.0, time: Double = 0.0) {
        self.bodies = bodies
        self.gravitationalConstant = gravitationalConstant
        self.time = time
    }

    // MARK: - Forces

    /// Newtonian accelerations: a_i = Σ_{j≠i} G·m_j·(r_j − r_i)/|r_j − r_i|³
    ///
    /// Written as a symmetric pair loop so each separation is computed once and
    /// the equal-and-opposite forces stay exactly consistent (this matters:
    /// asymmetry here leaks momentum).
    ///
    /// Writes into a caller-owned buffer: this is the innermost loop of the
    /// whole program — tens of thousands of calls per second during a close
    /// encounter — and allocating a fresh array for each one is pure waste.
    public func accelerations(into acc: inout [Vec2]) {
        if acc.count != bodies.count {
            acc = [Vec2](repeating: .zero, count: bodies.count)
        } else {
            for i in acc.indices { acc[i] = .zero }
        }
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let d = bodies[j].position - bodies[i].position
                let r2 = d.lengthSquared
                guard r2 > 0 else { continue }
                let invR3 = 1.0 / (r2 * r2.squareRoot())
                let f = d * (gravitationalConstant * invR3)
                acc[i] += f * bodies[j].mass
                acc[j] -= f * bodies[i].mass
            }
        }
    }

    /// Allocating convenience form, for tests and one-off inspection.
    public func accelerations() -> [Vec2] {
        var acc = [Vec2](repeating: .zero, count: bodies.count)
        accelerations(into: &acc)
        return acc
    }

    // MARK: - Conserved quantities
    //
    // These are the honest check on the integrator: for an isolated system all
    // three are exact constants of motion, so any drift is purely numerical.

    public var kineticEnergy: Double {
        bodies.reduce(0) { $0 + 0.5 * $1.mass * $1.velocity.lengthSquared }
    }

    public var potentialEnergy: Double {
        var u = 0.0
        forEachPair { i, j, r in
            if r > 0 { u -= gravitationalConstant * bodies[i].mass * bodies[j].mass / r }
            return true
        }
        return u
    }

    public var totalEnergy: Double { kineticEnergy + potentialEnergy }

    public var linearMomentum: Vec2 {
        bodies.reduce(Vec2.zero) { $0 + $1.velocity * $1.mass }
    }

    /// Total angular momentum about the origin (z-component).
    public var angularMomentum: Double {
        bodies.reduce(0) { $0 + $1.mass * $1.position.cross($1.velocity) }
    }

    public var totalMass: Double { bodies.reduce(0) { $0 + $1.mass } }

    public var centerOfMass: Vec2 {
        let m = totalMass
        guard m > 0 else { return .zero }
        return bodies.reduce(Vec2.zero) { $0 + $1.position * $1.mass } / m
    }

    public var centerOfMassVelocity: Vec2 {
        let m = totalMass
        guard m > 0 else { return .zero }
        return linearMomentum / m
    }

    /// Merge two bodies in a perfectly inelastic collision, conserving mass and
    /// momentum. The merged body is placed at the pair's centre of mass and
    /// takes its velocity, which is the only outcome momentum conservation
    /// allows once the two are required to move together.
    ///
    /// Kinetic energy is *not* conserved — that is what "inelastic" means, and
    /// the loss is real physics (it goes to heat and debris in the real thing),
    /// not integration error. Neither is angular momentum: the pair's orbital
    /// angular momentum about its own centre of mass, μ·(r_rel × v_rel), would
    /// become spin of the merged object, and a point mass has nowhere to put
    /// it. Both are genuine consequences of the model, so the caller has to
    /// re-baseline its conservation bookkeeping afterwards or the merge will
    /// look like the integrator failed.
    ///
    /// Returns the index the merged body occupies, and the kinetic energy the
    /// impact shed.
    ///
    /// Kinetic, specifically, not total: merging also deletes the pair's mutual
    /// potential well, which at contact separation is enormous and negative, so
    /// the total energy of the system actually jumps *up*. The quantity with
    /// physical meaning — the energy that goes to heat and debris — is the
    /// kinetic energy in the pair's own centre-of-mass frame, ½·μ·|v_rel|².
    @discardableResult
    public mutating func merge(_ i: Int, _ j: Int) -> (index: Int, kineticEnergyLost: Double) {
        precondition(i != j && bodies.indices.contains(i) && bodies.indices.contains(j))

        let a = bodies[i]
        let b = bodies[j]
        let combined = NBodySystem.combined(a, b)
        let mass = combined.mass
        let reducedMass = a.mass * b.mass / mass
        let kineticEnergyLost = 0.5 * reducedMass * (b.velocity - a.velocity).lengthSquared
        let merged = Body(
            mass: mass,
            position: combined.position,
            velocity: combined.velocity)

        let keep = Swift.min(i, j)
        let drop = Swift.max(i, j)
        bodies[keep] = merged
        bodies.remove(at: drop)

        return (keep, kineticEnergyLost)
    }

    /// Move to the centre-of-mass frame. Removes the uniform drift that would
    /// otherwise slide the whole scene off screen, without altering the
    /// internal dynamics (Galilean invariance).
    public mutating func moveToCenterOfMassFrame() {
        let r = centerOfMass
        let v = centerOfMassVelocity
        for i in 0..<bodies.count {
            bodies[i].position -= r
            bodies[i].velocity -= v
        }
    }

    // MARK: - Geometry helpers

    /// Smallest pairwise separation — the quantity that governs both the
    /// required timestep and how violent the scene currently looks.
    public var minimumSeparation: Double { closestPair().separation }

    /// Visit each unordered pair once, with its separation. Return `false` to
    /// stop early.
    ///
    /// The `j > i` convention is deliberate and is stated once here rather than
    /// re-derived by every scan that needs it.
    @inline(__always)
    public func forEachPair(_ visit: (Int, Int, Double) -> Bool) {
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let separation = (bodies[j].position - bodies[i].position).length
                if !visit(i, j, separation) { return }
            }
        }
    }

    /// Mass, position and velocity of two bodies treated as one — used often
    /// enough, and in hot enough paths, to be worth not building a throwaway
    /// two-body `NBodySystem` for.
    public static func combined(_ a: Body, _ b: Body)
        -> (mass: Double, position: Vec2, velocity: Vec2)
    {
        let mass = a.mass + b.mass
        guard mass > 0 else { return (0, a.position, a.velocity) }
        return (
            mass,
            (a.position * a.mass + b.position * b.mass) / mass,
            (a.velocity * a.mass + b.velocity * b.mass) / mass
        )
    }

    /// Index of a body that has come unbound from the other two: positive
    /// orbital energy relative to their centre of mass, receding, and further
    /// away than `distanceRatio` times their separation.
    ///
    /// The engine retires scenes on this and vetting rejects candidates on it,
    /// so it is written once. Keeping two copies in step by hand is exactly how
    /// a pre-flight check ends up disagreeing with the thing it is checking.
    public func unboundBody(distanceRatio: Double = Contact.escapeDistanceRatio) -> Int? {
        guard bodies.count == 3 else { return nil }

        let pair = closestPair()
        let third = 3 - pair.i - pair.j
        let binary = NBodySystem.combined(bodies[pair.i], bodies[pair.j])
        let body = bodies[third]

        let dr = body.position - binary.position
        let dv = body.velocity - binary.velocity
        let distance = dr.length
        guard distance > 0 else { return nil }

        let specificEnergy =
            0.5 * dv.lengthSquared
            - gravitationalConstant * (binary.mass + body.mass) / distance
        let unbound =
            specificEnergy > 0
            && dr.dot(dv) > 0
            && distance > distanceRatio * pair.separation
        return unbound ? third : nil
    }

    /// Physical size of a body, for deciding when two of them touch.
    ///
    /// Point masses have no radius, so one has to be chosen. `scale` sets the
    /// size of a body holding the whole system's mass; individual bodies get
    /// the cube root of their mass fraction, which is what constant density
    /// gives you. See `SimulationEngine.contactScale` for how `scale` is
    /// picked — it is deliberately far smaller than a real star's, so that the
    /// published periodic orbits (some of which pass within 1e-5 of their own
    /// extent) play out exactly as published.
    public func contactRadius(of index: Int, scale: Double) -> Double {
        let fraction = bodies[index].mass / Swift.max(totalMass, 1e-12)
        return scale * pow(fraction, 1.0 / 3.0)
    }

    /// The first pair found in contact, if any.
    public func touchingPair(contactScale scale: Double) -> (i: Int, j: Int)? {
        var found: (i: Int, j: Int)?
        forEachPair { i, j, separation in
            if separation < contactRadius(of: i, scale: scale)
                + contactRadius(of: j, scale: scale)
            {
                found = (i, j)
                return false
            }
            return true
        }
        return found
    }

    /// Indices and separation of the closest pair — in a triple this is the
    /// binary, and the remaining body is the one being thrown around.
    public func closestPair() -> (i: Int, j: Int, separation: Double) {
        var best = (i: 0, j: min(1, bodies.count - 1), separation: Double.infinity)
        forEachPair { i, j, r in
            if r < best.separation { best = (i, j, r) }
            return true
        }
        return best
    }

    public var maximumSeparation: Double {
        var m = 0.0
        forEachPair { _, _, r in
            m = Swift.max(m, r)
            return true
        }
        return m
    }
}
