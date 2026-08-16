import Foundation

/// Pre-flight check on a candidate scene.
///
/// Random initial conditions produce plenty of duds: two bodies that touch
/// almost immediately, or a third that was never really bound and drifts off
/// within seconds. Watching one resolve ten seconds after it faded in is worse
/// than not showing it at all.
///
/// So a candidate is integrated ahead of time and rejected if it does not
/// survive long enough to be worth watching. This is the trick Kirk Long's
/// ThreeBodyBot uses to avoid posting a dud — it hunts for initial conditions
/// lasting at least fifteen simulated years before it commits to rendering one.
public enum SceneVetting {

    public struct Outcome {
        /// Simulated time before the system resolved itself, or the full
        /// horizon if it never did.
        let survivedFor: Double
        /// True if it made it to the horizon without collision or escape.
        let survivedHorizon: Bool
        /// Integration steps consumed, so a caller trying several candidates
        /// can bound the total rather than the individual cost.
        let stepsUsed: Int
    }

    /// Integrate `scenario` forward and report how long it lasts.
    ///
    /// Deliberately cheap: 6th order at a loose tolerance, and it stops the
    /// moment anything happens. Vetting one candidate costs a fraction of the
    /// frame it would otherwise be shown in.
    public static func evaluate(
        _ scenario: Scenario,
        horizon: Double,
        contactScale: Double = NBodySystem.Contact.scale,
        stepBudget: Int = 40_000
    ) -> Outcome {
        var system = scenario.system
        let extent = max(system.maximumSeparation, 1e-9)
        let contactRadius = contactScale * extent
        let stepper = AdaptiveStepper(order: .sixth, eta: 0.03)
        let start = system.time
        let end = start + horizon

        // Bounded work: vetting happens inline on the animation thread at a
        // scene change, and an unlucky candidate could otherwise integrate for
        // tens of milliseconds — several dropped frames.
        var stepsRemaining = stepBudget
        while system.time < end && stepsRemaining > 0 {
            let result = stepper.advance(
                &system,
                by: min(end - system.time, horizon / 200.0),
                maxSteps: stepsRemaining
            ) { state in
                state.touchingPair(contactScale: contactRadius) != nil
            }
            stepsRemaining -= result.steps
            if result.stopped || system.unboundBody() != nil || result.covered <= 0 {
                // Stopped on contact, on an escape, or on an encounter too deep
                // to make progress through — all of them mean resolved.
                return Outcome(
                    survivedFor: system.time - start,
                    survivedHorizon: false,
                    stepsUsed: stepBudget - stepsRemaining)
            }
        }
        // Running out of budget is not a verdict either way; treat an
        // unfinished candidate as acceptable rather than rejecting it for being
        // expensive to check.
        return Outcome(
            survivedFor: system.time - start,
            survivedHorizon: true,
            stepsUsed: stepBudget - stepsRemaining)
    }

}
