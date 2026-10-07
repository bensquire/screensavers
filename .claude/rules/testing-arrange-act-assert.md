---
title: Every Test Arranges, Acts and Asserts
impact: HIGH
impactDescription: A test with a step missing tests something other than it claims
tags: [testing, aaa, structure, xctest]
paths: ["Tests/**/*.swift"]
---

## Every Test Arranges, Acts and Asserts

**Impact: HIGH**

Every test has three steps, in this order, each present and identifiable:

1. **Arrange** — build the input: a view from the test's `makeView`, a
   seeded scene, a local `NotificationCenter`, a fixture table.
2. **Act** — the one call under test: a notification posted, a scene
   stepped, a frame rendered. One act per test where the design allows; a test
   that acts twice is two tests, or a test of the pair.
3. **Assert** — `XCTAssert…` against what the act produced; `XCTUnwrap` for
   the thing the rest cannot run without.

This suite does not mark the steps with comments, and they need not be on
separate lines, but a reader should be able to point at the input, the call
and the check. A blank line between the steps is usually enough.

**Incorrect (the act hidden inside the assert; no act at all):**

```swift
XCTAssertEqual(VortexSettings(flowSpeed: .nan, lightning: true, density: 1).flowSpeed, 0.3)

func testThereAreFourOrders() { XCTAssertEqual(IntegratorOrder.allCases.count, 4) }
```

**Correct:**

```swift
func testSessionEndStopsAFullScreenInstance() {
    let center = NotificationCenter()
    var ended = 0
    let lifecycle = SaverLifecycle(
        view: makeView(), frameInterval: frameInterval, sessionCenter: center
    ) { ended += 1 }

    center.post(name: SaverLifecycle.sessionWillStop, object: nil)

    XCTAssertEqual(ended, 1)
    withExtendedLifetime(lifecycle) {}
}
```
