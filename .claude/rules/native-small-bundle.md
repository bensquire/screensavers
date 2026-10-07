---
title: Small, Because the System Is the Library
impact: MEDIUM
impactDescription: Each saver is 0.75–1.2 MB with both architectures; growth is a signal the wrong path was taken
tags: [native, macos, bundle, dependencies, size]
paths: ["Package.swift", "savers/**", "Scripts/build-saver.sh", "Sources/**/*.swift"]
---

## Small, Because the System Is the Library

**Impact: MEDIUM**

Measured with `du -sh build/*/*.saver` after `make build`, release,
arm64 + x86_64 (6 October 2026):

| Saver | Bundle |
|---|---|
| Gargantua | 856 KB |
| Sliders Vortex | 776 KB |
| Three-Body Problem | 1.0 MB |
| Solar System | 1.2 MB |

Nearly all of each is its own executable. The rest is the two System Settings
tiles, a `.metallib` for the Metal savers, and astronomy-engine's licence for
Solar System. A saver links only the system frameworks its `saver.conf` names,
embeds no framework, and takes the Swift runtime from the OS. The package has
no dependencies; the only third-party code is the vendored astronomy-engine.

That is a consequence of using the system's features and a check on it: a
feature that arrives with a package dependency, an embedded framework or a
second binary is a sign the wrong path was taken. Check the bundle's size
after a change that adds to `FRAMEWORKS`, `EXTRA_RESOURCES` or a module, and
give growth a reason.

**Incorrect:**

```swift
// Package.swift
.package(url: "https://github.com/…/SomeNoise", from: "1.0.0")   // for noise Metal can compute
```

**Correct:**

```swift
import simd   // already on every Mac
```
