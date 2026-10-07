---
title: Formatting Is Decided by the Tool
impact: MEDIUM
impactDescription: No formatting diffs, no style arguments in review, no drift between a laptop and CI
tags: [quality, formatting, lint, swift-format]
paths: ["Sources/**/*.swift", "Tests/**/*.swift", "Package.swift", "Scripts/**/*.swift", ".swift-format"]
---

## Formatting Is Decided by the Tool

**Impact: MEDIUM**

Apple's swift-format, with `.swift-format`, is the style: 110 columns,
4-space indents, ordered imports, `//` comments rather than `/* */`, shorthand
type names. It also refuses `!` force unwraps, `try!` and implicitly unwrapped
optionals (`NeverForceUnwrap`, `NeverUseForceTry`,
`NeverUseImplicitlyUnwrappedOptionals`), because a saver that traps takes the
screensaver host down with it: handle the nil, and where a value truly cannot be
nil, put `// swift-format-ignore: <Rule>` on the line above with the reason.
Files that import XCTest are exempt from the first two. `make lint` checks
`Sources`, `Tests` and `Package.swift` strictly; `make format` rewrites them in
place. CI runs `make lint` on every push, and the pre-commit hook runs it too
once enabled with `git config core.hooksPath .githooks`. There is no SwiftLint
here.

swift-format ships with the toolchain (`swift format --version`; 6.3.0 with
Xcode 26.6), and CI pins Xcode 26.6, so a local Xcode 26.6 lints exactly as
CI does. A lint that passes on one machine and fails on the other is most
likely a version difference: compare versions before changing code to suit
one of them.

`Scripts/verify-saver.swift` is outside `make lint`'s paths, so it is
formatted to match by hand. Hand-formatting anything the tool covers, or
arguing with it in code, only creates the next diff.

**Incorrect:**

```swift
import XCTest
import Metal
/* the probe reports byte offsets */
```

**Correct:**

```swift
import Metal
import XCTest

// The probe reports byte offsets.
```
