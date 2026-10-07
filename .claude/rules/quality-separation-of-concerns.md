---
title: Each Part Does One Job, and Knows Only Its Neighbours
impact: HIGH
impactDescription: A saver's physics is testable headlessly, and its build is one script for all four, because nothing in a Core knows about a window
tags: [quality, architecture, separation-of-concerns, layers, modules]
paths: ["Sources/**/*.swift", "Package.swift", "Scripts/**", "savers/**"]
---

## Each Part Does One Job, and Knows Only Its Neighbours

**Impact: HIGH**

The layers are the SwiftPM targets, and `Package.swift` makes the dependencies
run one way. Each saver has four:

- **`<Name>Core`** — the physics and the model: Foundation, `simd`, `SaverCore`
  and, for Solar System, the vendored astronomy-engine. No AppKit, ScreenSaver,
  Metal, SceneKit or QuartzCore, which is what lets the tests drive a scene with
  no window and no GPU.
- **`<Name>Render`** — the drawing (Core Graphics, SceneKit or Metal), the
  options sheet and the settings store.
- **`<Name>Saver`** — the `ScreenSaverView` subclass: it wires the lifecycle,
  the settings and the renderer together, and computes nothing of its own.
- **`<Name>App`** — the standalone window, the thumbnail renderer and the
  benchmark. Never part of the shipped bundle.

Shared code is split the same way: `SaverCore` holds what a Core may use (the
seeded `SplitMix64`, `clamped(to:)`, `wrapped(modulo:)`); `SaverKit` holds the
hosting code that needs AppKit, ScreenSaver and Metal (`SaverPreferences`,
`SaverLifecycle`, `OptionsSheet`, `MetalLayerView`, `MetalShaders`,
`FrameClock`, `Benchmark`, `SaverFrameCapturing`). `SaverKit` knows no
particular scene. Building, signing, packaging and verifying live once, in
`Scripts/`, driven by each saver's `saver.conf`.

A change that needs a Core to import a UI or GPU framework, a Saver view to
step the simulation, `SaverKit` to know which saver it is hosting, or a
script to special-case one saver, is at the wrong layer.

**Incorrect (a UI type in the physics):**

```swift
// ThreeBodyCore
import AppKit
extension Body { var color: NSColor { … } }
```

**Correct (the Core carries an index; Render turns it into a colour):**

```swift
// ThreeBodyCore
public var colorIndex: Int
// ThreeBodyRender
let color = Renderer.color(at: colorIndex)
```
