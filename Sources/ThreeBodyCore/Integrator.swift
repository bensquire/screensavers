import Foundation

/// Symplectic integrators built by symmetric composition of the leapfrog
/// (drift–kick–drift) map.
///
/// Symplectic methods are the right family for gravitational dynamics: they
/// conserve phase-space volume exactly and keep the energy error bounded and
/// oscillatory rather than letting it grow secularly the way a generic
/// Runge–Kutta method does. Yoshida (1990) showed that composing the 2nd-order
/// leapfrog with the right weights `w_k` yields methods of arbitrary even
/// order:
///
///   S_{2n+2}(dt) = S_{2n}(w_m dt) ∘ … ∘ S_{2n}(w_1 dt) ∘ S_{2n}(w_0 dt) ∘ … ∘ S_{2n}(w_m dt)
///
/// Orders 4 and 6 use Yoshida's own coefficients; order 8 is built by Suzuki's
/// five-fold composition of the 6th-order method. Each weight costs one force
/// evaluation, so a step costs 3, 7 and 35 evaluations respectively — the test
/// harness measures the resulting convergence slopes directly.
public enum IntegratorOrder: Int, CaseIterable {
    case second = 2
    case fourth = 4
    case sixth = 6
    case eighth = 8

    /// Composition weights, in application order. They sum to 1 (so the
    /// composed map advances time by exactly `dt`) and are palindromic (so the
    /// map is time-symmetric, which is what kills all odd error terms).
    public var weights: [Double] {
        switch self {
        case .second:
            return [1.0]

        case .fourth:
            // Yoshida (1990), the classic triple-jump. The negative middle
            // step is unavoidable for order > 2 with this construction.
            let cbrt2 = pow(2.0, 1.0 / 3.0)
            let w1 = 1.0 / (2.0 - cbrt2)
            let w0 = -cbrt2 / (2.0 - cbrt2)
            return [w1, w0, w1]

        case .sixth:
            // Yoshida (1990) "Solution A" for the 6th-order method.
            let w1 = -0.117767998417887e1
            let w2 = 0.235573213359357e0
            let w3 = 0.784513610477560e0
            let w0 = 1.0 - 2.0 * (w1 + w2 + w3)
            return [w3, w2, w1, w0, w1, w2, w3]

        case .eighth:
            // Suzuki's (1990) five-fold composition, applied to the 6th-order
            // method above:
            //
            //   S₈(dt) = S₆(p·dt)² ∘ S₆((1−4p)·dt) ∘ S₆(p·dt)²,   p = 1/(4 − 4^(1/7))
            //
            // Derived rather than tabulated, so there is no transcription to
            // get wrong, and measured convergence confirms the eighth-order
            // slope (see Tests/main.swift). It costs 35 force evaluations per
            // step against Yoshida's optimised 15, but it beats both the
            // three-fold "triple jump" construction and the 6th-order method
            // on error per force evaluation, which is what actually matters.
            let base = IntegratorOrder.sixth.weights
            let p = 1.0 / (4.0 - pow(4.0, 1.0 / 7.0))
            let q = 1.0 - 4.0 * p
            return base.map { $0 * p } + base.map { $0 * p }
                + base.map { $0 * q }
                + base.map { $0 * p } + base.map { $0 * p }
        }
    }

    public var forceEvaluationsPerStep: Int { weights.count }

    public var displayName: String {
        switch self {
        case .second: return "leapfrog"
        case .fourth: return "Yoshida 4th"
        case .sixth: return "Yoshida 6th"
        case .eighth: return "Suzuki 8th"
        }
    }
}

/// Fixed-step symplectic integrator.
public struct SymplecticIntegrator {
    public let order: IntegratorOrder
    private let weights: [Double]

    public init(order: IntegratorOrder) {
        self.order = order
        self.weights = order.weights
    }

    /// Advance the system by exactly `dt`.
    ///
    /// `scratch` is the caller-owned acceleration buffer; it carries no state
    /// between steps, it just saves an allocation per force evaluation.
    public func step(_ system: inout NBodySystem, dt: Double, scratch: inout [Vec2]) {
        for w in weights {
            leapfrog(&system, h: w * dt, scratch: &scratch)
        }
    }

    /// Allocating convenience form, for tests and one-off integrations.
    public func step(_ system: inout NBodySystem, dt: Double) {
        var scratch = [Vec2](repeating: .zero, count: system.bodies.count)
        step(&system, dt: dt, scratch: &scratch)
    }

    /// One drift–kick–drift step. Explicitly separable because gravity's
    /// Hamiltonian splits as H = T(p) + V(q), which is precisely why a
    /// symplectic method is available at all.
    private func leapfrog(_ system: inout NBodySystem, h: Double, scratch acc: inout [Vec2]) {
        let half = 0.5 * h
        for i in 0..<system.bodies.count {
            system.bodies[i].position += system.bodies[i].velocity * half
        }
        system.accelerations(into: &acc)
        for i in 0..<system.bodies.count {
            system.bodies[i].velocity += acc[i] * h
        }
        for i in 0..<system.bodies.count {
            system.bodies[i].position += system.bodies[i].velocity * half
        }
        system.time += h
    }
}

/// Adaptive-timestep driver.
///
/// Three-body motion is scale-free: a wide, slow triple and a hard binary
/// grazing at 100× the speed can both occur in the same run. A fixed step
/// sized for the encounters would be absurdly slow the rest of the time, so the
/// step is derived from the local dynamical timescales of the closest pair.
///
/// Naive adaptivity destroys the time-symmetry that makes symplectic methods
/// well behaved, and the energy error starts to drift. The fix (Hut, Makino &
/// McMillan 1995) is to symmetrise: choose the step from the harmonic mean of
/// the estimate at the start of the step and the estimate at the (provisional)
/// end, which restores reversibility and with it the bounded energy error.
public struct AdaptiveStepper {
    public var integrator: SymplecticIntegrator
    /// Accuracy parameter — step size as a fraction of the shortest local
    /// dynamical timescale. Smaller is more accurate and slower.
    public var eta: Double
    public var minStep: Double
    /// Absolute ceiling on a step, for callers that want one.
    ///
    /// Defaults to no ceiling, because an absolute constant is the wrong shape
    /// for this: the step should be governed by the system's own dynamical
    /// timescale, and `candidateStep` already is. The previous default of 0.05
    /// was chosen when scenes had separations of order 1; in astronomical units
    /// they span 10–200 AU, so the timescales grew by orders of magnitude and
    /// the cap bound 72% of the time — forcing steps far smaller than accuracy
    /// required, for no benefit but the cost.
    ///
    /// Removing it is safe because the shortest pairwise timescale already
    /// accounts for every pair: two bodies closing fast give a small `r/v_rel`
    /// and pull the step down on their own. The requested interval bounds it
    /// from above in any case.
    public var maxStep: Double

    public init(
        order: IntegratorOrder = .sixth,
        eta: Double = 0.02,
        minStep: Double = 1e-12,
        maxStep: Double = .infinity
    ) {
        self.integrator = SymplecticIntegrator(order: order)
        self.eta = eta
        self.minStep = minStep
        self.maxStep = maxStep
    }

    /// Candidate step from the pairwise free-fall and fly-by timescales:
    ///
    ///   t_ff  = sqrt(r³ / (G·(m_i + m_j)))   — time to fall together
    ///   t_fly = r / |v_rel|                  — time to traverse the separation
    ///
    /// Taking the minimum over pairs and scaling by `eta` keeps the step small
    /// during a close encounter and lets it open out again afterwards.
    public func candidateStep(for system: NBodySystem) -> Double {
        var shortest = Double.infinity
        let bodies = system.bodies
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let d = bodies[j].position - bodies[i].position
                let r = d.length
                guard r > 0 else { return minStep }
                let mu = system.gravitationalConstant * (bodies[i].mass + bodies[j].mass)
                let freeFall = (r * r * r / mu).squareRoot()
                shortest = Swift.min(shortest, freeFall)

                let vRel = (bodies[j].velocity - bodies[i].velocity).length
                if vRel > 0 {
                    shortest = Swift.min(shortest, r / vRel)
                }
            }
        }
        guard shortest.isFinite else { return maxStep }
        return Swift.min(Swift.max(eta * shortest, minStep), maxStep)
    }

    /// Integrate forward by `interval` of simulated time.
    ///
    /// Returns how many steps were taken and how much time was actually
    /// covered — during a deep encounter the step budget can run out, in which
    /// case the simulation legitimately runs in slow motion rather than
    /// silently losing accuracy.
    ///
    /// `stopWhen` is evaluated after every step and halts the advance when it
    /// returns true. It exists so that events defined on the state — two bodies
    /// touching, above all — are detected at the integrator's time resolution
    /// rather than the caller's. A frame is far too coarse: the adaptive step
    /// shrinks to ~1e-6 during a close encounter precisely because the geometry
    /// is changing that fast, so a pair can enter and leave contact several
    /// thousand steps before the next frame boundary.
    @discardableResult
    public func advance(
        _ system: inout NBodySystem,
        by interval: Double,
        maxSteps: Int = 20_000,
        stopWhen shouldStop: ((NBodySystem) -> Bool)? = nil
    )
        -> (steps: Int, covered: Double, lastStep: Double, stopped: Bool)
    {
        guard interval > 0 else { return (0, 0, 0, false) }
        let target = system.time + interval
        let start = system.time
        var steps = 0
        var lastStep = 0.0

        // Stop once the remainder is down at the resolution of the time
        // variable itself. Without this the loop can never satisfy
        // `time < target` — adding a 1e-16 step to a time of order 10 leaves it
        // unchanged — and it spins until the step budget is gone.
        let closeEnough = Swift.max(abs(target), 1.0) * 1e-13

        // Acceleration buffer, allocated once per advance rather than once per
        // force evaluation — of which there can be tens of thousands here.
        var scratch = [Vec2](repeating: .zero, count: system.bodies.count)

        while steps < maxSteps {
            let remaining = target - system.time
            if remaining <= closeEnough { break }

            let raw = candidateStep(for: system)

            var trial = system
            integrator.step(&trial, dt: Swift.min(raw, remaining), scratch: &scratch)
            let rawEnd = candidateStep(for: trial)
            // Harmonic mean of the two endpoint estimates: symmetric under
            // time reversal, so the step sequence forwards and backwards
            // agree and the method stays reversible.
            let symmetric = 2.0 / (1.0 / raw + 1.0 / rawEnd)
            let h = Swift.min(Swift.max(symmetric, minStep), remaining)

            integrator.step(&system, dt: h, scratch: &scratch)
            lastStep = h
            steps += 1

            if shouldStop?(system) == true {
                return (steps, system.time - start, lastStep, true)
            }
        }

        // Floating-point step accumulation leaves `time` a few ulps off the
        // target; pin it so simulated time stays exactly reproducible. Only
        // when the interval was actually completed — a budget-exhausted step
        // really has not covered the requested span.
        if steps < maxSteps { system.time = target }
        return (steps, system.time - start, lastStep, false)
    }
}
