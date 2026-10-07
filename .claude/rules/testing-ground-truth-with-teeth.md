---
title: Ground Truth Comes From Outside the Code, and the Bar Has Teeth
impact: HIGH
impactDescription: A wrong 8th-order weight set still drew pretty orbits; only a measured convergence slope (1.85, not 8) showed it
tags: [testing, ground-truth, physics, rendering, fixtures]
paths: ["Tests/**/*.swift", "Scripts/verify-saver.swift"]
---

## Ground Truth Comes From Outside the Code, and the Bar Has Teeth

**Impact: HIGH**

A screensaver that is wrong usually still looks plausible on screen, so a
result is judged against something the code did not produce:

- **A published source.** Planet positions against JPL Horizons vectors,
  within the angular error astronomy-engine documents.
- **A measured property of the maths.** An integrator's convergence slope
  against a reference solution, and its weights summing to one and being
  palindromic. That slope is what caught a transcribed-from-memory 8th-order
  coefficient set that measured 1.85.
- **The other side of a contract.** The shader is asked what it thinks the
  buffer layout is, and that is compared with Swift's; the metallib the build
  names is compared with the one `ShaderLibrary` loads.
- **The frame itself.** What was drawn, read back with `bgraBytes` — not that
  a frame exists, but that it has lit pixels, and that it does not jump where
  it should be continuous.

When a test says a result is good, it also says, where it can, what the
failure would have measured, so the bar cannot be cleared by accident:
`StarFieldTests`, run against the old star field, fails at exactly the three
points where it snapped, by 86 times its threshold. A tolerance carries the
reason for its size. When a bug is fixed, a test pins it, with the measurement
that showed it.

**Incorrect (a bar with no teeth — passes on a scene that drew nothing, or drew the wrong thing):**

```swift
XCTAssertNotNil(image)
XCTAssertFalse(system.bodies.isEmpty)
```

**Correct (an outside source, and a tolerance with its reason):**

```swift
/// astronomy-engine documents ~1 arcminute worst case.
XCTAssertLessThan(
    arcmin, toleranceArcmin,
    "\(planet.name): angular error \(arcmin) arcmin exceeds \(toleranceArcmin)")
```
