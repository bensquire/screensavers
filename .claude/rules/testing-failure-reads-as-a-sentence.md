---
title: A Failure Reads as a Sentence
impact: MEDIUM
impactDescription: A bare comparison fails as a pair of numbers with no story
tags: [testing, assertions, messages, xctest]
paths: ["Tests/**/*.swift"]
---

## A Failure Reads as a Sentence

**Impact: MEDIUM**

An `XCTAssert…` carries a message that says what was measured and what it
was, unless the expression already says it (`XCTAssertTrue(lifecycle.isSuspended)`,
an orthonormality check written as `dot(c.right, c.up)`). In a loop the message
names the input — the planet, the integrator order, the scene. `XCTUnwrap`
for the thing the rest of the test cannot run without, with a message saying
what was missing; a `return XCTFail("…")` where setting up the GPU fails. A
helper that asserts on the caller's behalf takes `file: StaticString = #filePath`
and `line: UInt = #line` and passes them on, so the failure lands on the test,
not the helper.

**Incorrect:**

```swift
XCTAssertGreaterThan(nearest, p.diskOuterRadius * 1.5)
XCTAssertEqual(w.reduce(0, +), 1.0, accuracy: 1e-12)          // inside a loop over orders
```

**Correct:**

```swift
XCTAssertGreaterThan(
    nearest, p.diskOuterRadius * 1.5, "the camera came within \(nearest) of the disk")
XCTAssertEqual(w.reduce(0, +), 1.0, accuracy: 1e-12, "order \(order.rawValue): Σw")
```
