---
title: Match the Code Around You
impact: HIGH
impactDescription: Four savers in one repository drift apart one second spelling at a time — the reason they were moved into one
tags: [quality, consistency, idioms, reuse, saverkit]
paths: ["Sources/**/*.swift", "Tests/**/*.swift", "Scripts/**"]
---

## Match the Code Around You

**Impact: HIGH**

New code reads like the file it lands in: the same naming, comment density,
error style, and idioms. The savers were brought into one repository because
the machinery around them had been duplicated per project and was drifting, so
before writing a helper, look in `SaverCore` and `SaverKit` for the one that
exists and call it:

- `clamped(to:)` for any value that came from preferences or a division —
  unlike `min`/`max`, it turns NaN into the range's lower bound;
  `wrapped(modulo:)` for angles and anything else that wraps.
- `SplitMix64` for randomness, `FrameClock` for frame timing,
  `SaverLifecycle` for start, stop, display sleep and Low Power Mode.
- `SaverPreferences` for settings, behind a per-saver settings store.
- `OptionsSheet`, `SliderGrid` and `SliderSpec` for an options sheet. Three
  of the four sheets are built from them, which keeps them at a width System
  Settings can present; Solar System's still builds its own window.
- `MetalLayerView` and `MetalShaders` for a Metal saver; `Benchmark` for
  `--bench`.
- In tests: `CGImage.bgraBytes` to read a rendered frame,
  `firstFrameCapturingView()` to find what drew it, `MTLDevice.isParavirtual`
  to skip SceneKit offscreen rendering where it cannot run.

When two savers need the same thing and it is not shared yet, it moves into
`SaverKit` (or `SaverCore`, if a Core needs it) rather than being written a
second time.

**Incorrect (a fresh spelling of an existing helper, without its NaN guard):**

```swift
let speed = min(max(defaults.double(forKey: Key.flowSpeed), 0.3), 2.5)
```

**Correct:**

```swift
self.flowSpeed = flowSpeed.clamped(to: Limits.flowSpeed)
```
