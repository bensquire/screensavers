---
title: Fast, but Not Over Accuracy
impact: MEDIUM
impactDescription: A test that is quick because it cannot see the defect is not a test; a slow suite is one nobody runs
tags: [testing, performance, accuracy, release]
paths: ["Tests/**/*.swift", "Makefile"]
---

## Fast, but Not Over Accuracy

**Impact: MEDIUM**

A test is first for what it proves, then as cheap as that allows — never the
other way round. The suite is 115 tests, about three seconds of test time and
four seconds warm through `make test` on an M1 Pro (seventeen from a cold
build). It runs in release mode because the numerical tests — million-step
integrations and convergence measurements — take tens of minutes
unoptimised; the speed comes from the optimiser, not from doing less.

Beyond that, speed is bought by not paying for what the test does not need: a
rule about one unit is pinned on that unit (the integrator's weights on their
own in `testCompositionWeights`, the lifecycle on a 64x40 view) rather than on
a whole scene; a render test draws a small frame where the property holds at
any size (`StarFieldTests` renders 320x200).

Speed is never bought by making the test see less. The convergence test's step
counts are chosen to land the error between the round-off floor and the
non-linear regime, because outside that window the slope means nothing, and
its reference solution takes 400,000 steps so its own error sits far below
the errors being measured. A reference shrunk until it runs quickly, or a
tolerance loosened so a cheap fixture clears it, is a faster test that no
longer tests.

**Incorrect (fast because it cannot see):**

```swift
let reference = integrateFixed(system, order: .sixth, to: target, steps: 4_000)  // its error now swamps the 8th-order one
XCTAssertEqual(measured, Double(order.rawValue), accuracy: 3)                     // loosened until it passes
```

**Correct (exact where it counts, with the reason stated):**

```swift
// Reference: a step so small its own truncation error sits far below
// the errors being measured.
let reference = integrateFixed(
    Scenarios.figureEight.system, order: .sixth, to: target, steps: 400_000)
```
