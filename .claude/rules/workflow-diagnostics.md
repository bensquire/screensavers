---
title: Diagnostics Are a Flag to Keep, a Separate File to Throw Away
impact: MEDIUM
impactDescription: A debug print woven into a renderer has to be edited out of the renderer, and inside the host nobody sees it anyway
tags: [workflow, diagnostics, logging, bench]
paths: ["Sources/**/*.swift", "Scripts/**"]
---

## Diagnostics Are a Flag to Keep, a Separate File to Throw Away

**Impact: MEDIUM**

A saver runs inside the system's `legacyScreenSaver` host, where its standard
output goes nowhere anyone looks, so a `print` in a saver is not a diagnostic.
Diagnostics worth keeping take one of two shapes:

- **A flag on the standalone app**, read once in `Sources/<Name>App/`:
  `--bench`, `--render`, `--width`, `--frames`, `--mode` (`Benchmark.argument`
  reads the numeric ones). Core, Render and Saver modules leave the command
  line and the environment alone; what they need is handed in.
- **`os_log` for a failure the user would otherwise see as a black screen**,
  under the saver's own subsystem, as the savers do when a renderer cannot be
  created: `OSLog(subsystem: "com.bensquire.Gargantua", category: "screensaver")`,
  read with `log stream --predicate 'subsystem == "com.bensquire.Gargantua"'`.

Diagnostics for one investigation go in a separate file, marked temporary,
and are deleted before handover, rather than being woven into a renderer or a
scene, where removing them means editing the renderer.

**Incorrect (a dump inline in the frame loop):**

```swift
// in the renderer's per-frame update
print("scale \(adaptive.renderScale) cost \(adaptive.smoothedCost)")
```

**Correct (its own file, one call, one deletion; or a kept flag read at the edge):**

```swift
// Sources/GargantuaApp/Debug.swift — TEMPORARY, not for commit
func dumpScale(_ adaptive: AdaptiveResolution) { … }

// Sources/<Name>App/main.swift
let frames = Benchmark.argument("--frames", default: 300)
```
