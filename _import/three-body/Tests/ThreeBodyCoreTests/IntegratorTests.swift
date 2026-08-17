import XCTest

@testable import ThreeBodyCore

/// These are measurements, not smoke tests. The composition coefficients, the
/// adaptive stepping and the published initial conditions all have failure
/// modes that look perfectly plausible on screen — a wrong 8th-order weight set
/// still produces pretty orbits. The only way to know the maths is right is to
/// measure the convergence slope and the conserved quantities.
final class IntegratorTests: XCTestCase {

    private func integrateFixed(
        _ system: NBodySystem, order: IntegratorOrder, to time: Double, steps: Int
    ) -> NBodySystem {
        var s = system
        let dt = time / Double(steps)
        let integrator = SymplecticIntegrator(order: order)
        for _ in 0..<steps { integrator.step(&s, dt: dt) }
        return s
    }

    private func stateDistance(_ a: NBodySystem, _ b: NBodySystem) -> Double {
        var sum = 0.0
        for i in 0..<a.bodies.count {
            sum += (a.bodies[i].position - b.bodies[i].position).lengthSquared
            sum += (a.bodies[i].velocity - b.bodies[i].velocity).lengthSquared
        }
        return sum.squareRoot()
    }

    /// Weights must sum to 1, or the composed map advances the wrong amount of
    /// time, and be palindromic, which is what makes the method time-symmetric
    /// and cancels every odd-order error term.
    func testCompositionWeights() {
        for order in IntegratorOrder.allCases {
            let w = order.weights
            XCTAssertEqual(w.reduce(0, +), 1.0, accuracy: 1e-12, "order \(order.rawValue): Σw")
            let palindromic = zip(w, w.reversed()).allSatisfy { abs($0 - $1) < 1e-12 }
            XCTAssertTrue(palindromic, "order \(order.rawValue) weights are not palindromic")
        }
    }

    /// Measure the convergence slope against a reference solution. This is the
    /// check that caught a transcribed-from-memory 8th-order coefficient set
    /// that measured a slope of 1.85 instead of 8.
    func testConvergenceOrder() {
        let target = 2.0
        // Reference: a step so small its own truncation error sits far below
        // the errors being measured.
        let reference = integrateFixed(
            Scenarios.figureEight.system, order: .sixth, to: target, steps: 400_000)

        // Step counts per order land the error between the round-off floor and
        // the non-linear regime; outside that window the slope means nothing.
        let stepPairs: [IntegratorOrder: (Int, Int)] = [
            .second: (200, 400), .fourth: (100, 200), .sixth: (40, 80), .eighth: (10, 15),
        ]

        for order in IntegratorOrder.allCases {
            guard let (coarse, fine) = stepPairs[order] else { continue }
            let e1 = stateDistance(
                integrateFixed(
                    Scenarios.figureEight.system, order: order, to: target, steps: coarse),
                reference)
            let e2 = stateDistance(
                integrateFixed(Scenarios.figureEight.system, order: order, to: target, steps: fine),
                reference)
            let measured = log(e1 / e2) / log(Double(fine) / Double(coarse))
            print(
                String(
                    format: "  order %d: slope %.2f (err %.2e → %.2e)",
                    order.rawValue, measured, e1, e2))
            XCTAssertEqual(
                measured, Double(order.rawValue), accuracy: 0.75,
                "order \(order.rawValue) convergence slope")
        }
    }

    /// A symplectic integrator keeps the energy error bounded and oscillatory
    /// rather than letting it grow with time, and conserves momentum exactly.
    func testConservationOverLongRun() {
        var s = Scenarios.figureEight.system
        let e0 = s.totalEnergy
        let l0 = s.angularMomentum
        let p0 = s.linearMomentum
        let integrator = SymplecticIntegrator(order: .sixth)
        var maxEnergyError = 0.0
        for _ in 0..<40_000 {  // t = 200, ≈ 32 periods
            integrator.step(&s, dt: 0.005)
            maxEnergyError = max(maxEnergyError, abs((s.totalEnergy - e0) / e0))
        }
        print(String(format: "  6th order, t=200: max |ΔE/E| = %.2e", maxEnergyError))
        XCTAssertLessThan(maxEnergyError, 1e-10)
        XCTAssertLessThan(abs(s.angularMomentum - l0), 1e-10)
        XCTAssertLessThan((s.linearMomentum - p0).length, 1e-10)
    }

    /// The adaptive, time-symmetric driver has to hold that bounded error while
    /// the step size varies by orders of magnitude through Burrau's
    /// near-collisions — the hardest thing this screensaver ever integrates.
    func testAdaptiveSteppingThroughBurrau() {
        for accuracy in Accuracy.allCases {
            var s = Scenarios.pythagorean.system
            let e0 = s.totalEnergy
            let stepper = AdaptiveStepper(order: accuracy.order, eta: accuracy.eta)
            var maxError = 0.0
            var steps = 0
            for _ in 0..<40 {  // to t = 40
                let r = stepper.advance(&s, by: 1.0, maxSteps: 5_000_000)
                steps += r.steps
                maxError = max(maxError, abs((s.totalEnergy - e0) / e0))
            }
            print(
                String(
                    format: "  %@: max |ΔE/E| = %.2e over %d steps",
                    accuracy.rawValue, maxError, steps))
            // Past 6th order the error stops tracking the step size: it is set
            // by however deep the closest encounter on that particular chaotic
            // path happened to be, so the bar is held flat rather than tightened.
            XCTAssertLessThan(maxError, accuracy == .standard ? 1e-5 : 1e-7)
        }
    }

    /// Cost effectiveness — the number that decides which order is worth using,
    /// since a high-order step costs many force evaluations. Reported rather
    /// than asserted; it is how the accuracy tiers were chosen.
    func testCostEffectivenessReport() {
        let target = 2.0
        let reference = integrateFixed(
            Scenarios.figureEight.system, order: .sixth, to: target, steps: 400_000)
        for budget in [630, 2100] {
            var line: [String] = []
            for order in IntegratorOrder.allCases {
                let steps = max(1, budget / order.forceEvaluationsPerStep)
                let err = stateDistance(
                    integrateFixed(
                        Scenarios.figureEight.system, order: order, to: target,
                        steps: steps),
                    reference)
                line.append(String(format: "%d: %.1e", order.rawValue, err))
            }
            print("  \(budget) evals →  " + line.joined(separator: "   "))
        }
    }
}
