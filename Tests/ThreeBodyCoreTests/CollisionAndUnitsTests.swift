import XCTest

@testable import ThreeBodyCore

final class CollisionTests: XCTestCase {

    /// A perfectly inelastic merge conserves mass and momentum but must *not*
    /// appear to conserve the other two: kinetic energy goes to heat, and the
    /// pair's orbital angular momentum becomes spin, which a point mass has
    /// nowhere to put. Both losses are physics, not integration error.
    func testMergeConservesMassAndMomentumButShedsSpinAndHeat() {
        var s = NBodySystem(bodies: [
            Body(mass: 2, position: Vec2(-1, 0), velocity: Vec2(3, 1)),
            Body(mass: 5, position: Vec2(1, 0.5), velocity: Vec2(-1, 2)),
            Body(mass: 1, position: Vec2(0, 9), velocity: Vec2(0.25, -0.5)),
        ])
        let massBefore = s.totalMass
        let momentumBefore = s.linearMomentum
        let angularBefore = s.angularMomentum
        let kineticBefore = s.kineticEnergy

        // The pair's angular momentum about its own centre of mass: μ·(r×v).
        let a = s.bodies[0], b = s.bodies[1]
        let reducedMass = a.mass * b.mass / (a.mass + b.mass)
        let spin = reducedMass * (b.position - a.position).cross(b.velocity - a.velocity)

        let result = s.merge(0, 1)

        XCTAssertEqual(s.bodies.count, 2)
        XCTAssertEqual(s.totalMass, massBefore, accuracy: 1e-12)
        XCTAssertLessThan((s.linearMomentum - momentumBefore).length, 1e-12)
        XCTAssertEqual(angularBefore - s.angularMomentum, spin, accuracy: 1e-12)
        XCTAssertLessThan(s.kineticEnergy, kineticBefore)
        XCTAssertEqual(result.kineticEnergyLost, kineticBefore - s.kineticEnergy, accuracy: 1e-12)
        XCTAssertGreaterThan(result.kineticEnergyLost, 0)
    }

    /// The contact radius must be small enough that no published orbit ever
    /// touches, or the catalogue stops reproducing the literature. Yarn is the
    /// tightest at 1.0e-5 of its extent — only about an order of magnitude of
    /// headroom, so this is worth checking rather than assuming.
    func testNoCataloguedOrbitReachesContact() {
        let contactScale = NBodySystem.Contact.scale
        var worst = (name: "", ratio: Double.infinity)
        for scenario in Scenarios.catalogue {
            var s = scenario.system
            let extent = s.maximumSeparation
            let stepper = AdaptiveStepper(order: .sixth, eta: 0.02)
            let end = s.time + scenario.timeScale * 150
            var steps = 0
            while s.time < end && steps < 2_000_000 {
                stepper.advance(&s, by: end - s.time, maxSteps: 1)
                steps += 1
                XCTAssertNil(
                    s.touchingPair(contactScale: contactScale * extent),
                    "\(scenario.name) reached contact")
                let ratio = s.minimumSeparation / extent
                if ratio < worst.ratio { worst = (scenario.name, ratio) }
            }
        }
        print(
            String(
                format: "  closest: %@ at %.2e of its extent (contact at %.2e)",
                worst.name, worst.ratio, 1.39 * contactScale))
        XCTAssertGreaterThan(worst.ratio, 2.0 * 1.39 * contactScale)
    }
}

final class UnitsTests: XCTestCase {

    /// A body circling 1 M☉ at 1 AU takes exactly one year. That single check
    /// pins the whole mapping: fixing the mass and length units leaves no
    /// freedom in the time unit, because G is already 4π² AU³/(M☉·yr²).
    func testOneAstronomicalUnitOrbitTakesOneYear() {
        let orbit = NBodySystem(bodies: [
            Body(mass: 1.0, position: .zero, velocity: .zero),
            // Test particle: circular speed √(GM/r) = 1 in internal units.
            Body(mass: 1e-9, position: Vec2(1, 0), velocity: Vec2(0, 1)),
        ])
        var s = orbit
        let stepper = AdaptiveStepper(order: .eighth, eta: 0.01)
        stepper.advance(&s, by: Units.timeUnits(fromYears: 1.0), maxSteps: 500_000)
        XCTAssertLessThan((s.bodies[1].position - orbit.bodies[1].position).length, 1e-6)
    }

    func testGravitationalConstantAndVelocityUnit() {
        XCTAssertEqual(Units.gravitationalConstant, 4 * .pi * .pi, accuracy: 1e-12)
        // One velocity unit is Earth's orbital speed — a useful sanity anchor.
        XCTAssertEqual(Units.kilometresPerSecond(fromVelocityUnits: 1.0), 29.78, accuracy: 0.05)
    }
}
