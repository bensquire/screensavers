---
title: Code Reads Like the Prose Around It
impact: HIGH
impactDescription: The next reader is a person, usually months later, often the author
tags: [quality, readability, naming]
paths: ["Sources/**/*.swift", "Tests/**/*.swift", "Scripts/**"]
---

## Code Reads Like the Prose Around It

**Impact: HIGH**

Names say what a thing is in the words the domain uses — `isParavirtual`,
`firstFrameCapturingView`, `sessionWillStop`, `wrapped(modulo:)`,
`helioPosition(_:terrestrialTimeDays:)` — so a call site reads as a sentence.
Physics keeps its units in the name or the type where a reader could mistake
them (solar masses, AU and years in Three-Body; TT days in the ephemeris).
Short names are right where the convention uses them (`i`, `dt`, `rng`, the
`c`/`p` of a tight maths block) and wrong anywhere else. A function does what
its name says and nothing more; one that needs "and" in its name is two.
Nesting is shallow; the early `guard` says what a function refuses. No
cleverness that needs a comment to decode — if the trick is necessary, the
comment explains why it is, with the measurement.

**Incorrect:**

```swift
func upd(_ s: inout NBodySystem, _ t: Double, _ f: Bool) {
    if f { if t > 0 { /* … forty lines … */ } }
}
```

**Correct:**

```swift
/// Reduced into `0..<modulus`, whatever the sign — a floor modulo, unlike
/// `truncatingRemainder`, whose result keeps the sign of the dividend.
public func wrapped(modulo modulus: Double) -> Double {
    self - modulus * (self / modulus).rounded(.down)
}
```
