import SaverCore
import XCTest

@testable import ThreeBodyCore

final class ScenarioTests: XCTestCase {

    private func stateDistance(_ a: NBodySystem, _ b: NBodySystem) -> Double {
        var sum = 0.0
        for i in 0..<a.bodies.count {
            sum += (a.bodies[i].position - b.bodies[i].position).lengthSquared
            sum += (a.bodies[i].velocity - b.bodies[i].velocity).lengthSquared
        }
        return sum.squareRoot()
    }

    /// Every catalogued solution is quoted in the centre-of-mass frame; a
    /// non-zero net momentum would mean a transcription error.
    func testCatalogueStartsInCentreOfMassFrame() {
        for scenario in Scenarios.catalogue {
            let raw = NBodySystem(bodies: scenario.bodies)
            XCTAssertLessThan(
                raw.linearMomentum.length, 1e-9,
                "\(scenario.name): net momentum \(raw.linearMomentum.length)")
        }
    }

    /// Every catalogued periodic orbit must actually be periodic. This is the
    /// check that catches a mistyped digit in the Šuvakov–Dmitrašinović
    /// constants: a wrong (p₁, p₂) gives an O(1) residual, while correct
    /// five-decimal values close the orbit to between 1e-6 and 1e-3.
    func testPeriodicOrbitsClose() {
        for scenario in Scenarios.periodicFamilies {
            guard let period = scenario.period else { continue }
            var s = scenario.system
            let start = s
            let stepper = AdaptiveStepper(order: .eighth, eta: 0.01)
            stepper.advance(&s, by: period, maxSteps: 5_000_000)
            let residual = stateDistance(s, start)
            print(String(format: "  %@: |Δstate| = %.2e", scenario.name, residual))
            XCTAssertLessThan(
                residual, 1e-2, "\(scenario.name): |Δstate| \(residual) after one period")
        }
    }

    /// The figure-eight's period was determined by minimising the return
    /// distance, not taken from memory — the commonly quoted 6.32449 is wrong
    /// for these initial conditions and leaves a residual 6 orders larger.
    func testFigureEightPeriod() {
        var s = Scenarios.figureEight.system
        let start = s
        let stepper = AdaptiveStepper(order: .eighth, eta: 0.01)
        stepper.advance(&s, by: Scenarios.figureEightPeriod, maxSteps: 500_000)
        let residual = stateDistance(s, start)
        XCTAssertLessThan(residual, 1e-6, "|Δstate| \(residual) after one period")
    }

    private func lagrangeSideError(after periods: Int) -> Double {
        var s = Scenarios.lagrange.system
        let stepper = AdaptiveStepper(order: .eighth, eta: 0.01)
        stepper.advance(
            &s, by: (Scenarios.lagrange.period ?? 0) * Double(periods),
            maxSteps: 5_000_000)
        var worst = 0.0
        s.forEachPair { _, _, separation in
            worst = max(worst, abs(separation - 1.0))
            return true
        }
        return worst
    }

    /// Lagrange's triangle rotates rigidly, so the sides stay at 1 — but equal
    /// masses put it far outside the Gascheau stability limit, so round-off
    /// alone must destroy it. Both halves are asserted: an integrator that kept
    /// the triangle intact would be suppressing real physics.
    func testLagrangeTriangleIsExactThenUnstable() {
        let early = lagrangeSideError(after: 2)
        XCTAssertLessThan(early, 1e-9, "after 2 periods a side is \(early) from 1")
        let late = lagrangeSideError(after: 12)
        XCTAssertGreaterThan(late, 1e-2, "after 12 periods the triangle still holds, to \(late)")
    }

    /// Euler's middle mass sits at a force balance point, so its acceleration
    /// must vanish exactly.
    func testEulerMiddleBodyIsInEquilibrium() throws {
        let acc = Scenarios.euler.system.accelerations()
        let smallest = try XCTUnwrap(acc.min { $0.length < $1.length }, "Euler's system has no bodies")
        XCTAssertLessThan(
            smallest.length, 1e-12, "the middle body accelerates at \(smallest.length)")
    }

    /// A flyby's premise is an intruder arriving from outside, so it must start
    /// unbound and inbound.
    func testFlybyIntrudersStartUnboundAndInbound() {
        var rng = SplitMix64(seed: 4242)
        for flyby in 0..<200 {
            let s = Scenarios.randomFlyby(using: &rng).system
            let pair = s.closestPair()
            let k = 3 - pair.i - pair.j
            let binary = NBodySystem.combined(s.bodies[pair.i], s.bodies[pair.j])
            let dr = s.bodies[k].position - binary.position
            let dv = s.bodies[k].velocity - binary.velocity
            let specificEnergy =
                0.5 * dv.lengthSquared
                - (binary.mass + s.bodies[k].mass) / dr.length
            XCTAssertGreaterThan(
                specificEnergy, 0, "flyby \(flyby): the intruder is bound, at energy \(specificEnergy)")
            XCTAssertLessThan(dr.dot(dv), 0, "flyby \(flyby): the intruder is heading outward")
        }
    }

    /// A generated scene is drawn as soon as it is made: it must have three
    /// bodies, finite energy, no two bodies on top of each other, and start in
    /// the centre-of-mass frame, or the whole scene slides off screen.
    func testGeneratedScenariosAreWellFormed() {
        var rng = SplitMix64(seed: 12345)
        var worstMomentum = 0.0
        for _ in 0..<120 {
            let scenario = Scenarios.random(
                families: Set(ScenarioFamily.allCases),
                excluding: [], using: &rng)
            let s = scenario.system
            XCTAssertEqual(s.bodies.count, 3, "\(scenario.name) has \(s.bodies.count) bodies")
            XCTAssertTrue(s.totalEnergy.isFinite, "\(scenario.name)'s energy is \(s.totalEnergy)")
            XCTAssertGreaterThan(
                s.minimumSeparation, 1e-3,
                "\(scenario.name) starts with two bodies \(s.minimumSeparation) apart")
            worstMomentum = max(worstMomentum, s.linearMomentum.length)
        }
        XCTAssertLessThan(worstMomentum, 1e-12, "a generated scene starts with momentum \(worstMomentum)")
    }

    /// Scene modes have to stay distinct: the catalogue replays fixed initial
    /// conditions, random systems never repeat.
    func testSceneModesDrawFromTheRightPools() {
        let fixedNames = Set(Scenarios.catalogue.map(\.name))
        for (mode, expectFixed) in [(SceneMode.knownOrbits, true), (.randomSystems, false)] {
            var rng = SplitMix64(seed: 7)
            for _ in 0..<60 {
                let name = Scenarios.random(
                    families: mode.families,
                    excluding: [], using: &rng
                ).name
                XCTAssertEqual(
                    fixedNames.contains(name), expectFixed,
                    "\(mode.rawValue) produced \(name)")
            }
        }
    }
}
