---
title: Dependencies and Settings Are Handed In as Values
impact: HIGH
impactDescription: Code that reaches for a global cannot be tested, varied or reused without it — and here the global can be a notification that stops every screensaver on the machine
tags: [quality, dependency-injection, values, testability]
paths: ["Sources/**/*.swift", "Tests/**/*.swift"]
---

## Dependencies and Settings Are Handed In as Values

**Impact: HIGH**

A type takes its collaborators and its settings as values, and whoever calls
it hands them in:

- `VortexSettingsStore(defaults:)` takes a `SaverPreferences`, which takes its
  module identifier and the `UserDefaults` it mirrors into, so a test can hand
  in its own suite.
- `SaverLifecycle(view:frameInterval:sessionCenter:onSessionEnd:)` takes the
  notification centre it listens on (the distributed one by default), so a
  test posts the session-end notification to a local centre instead of to the
  whole machine.
- A scene that uses randomness takes a seeded `SplitMix64`, so a run can be
  reproduced exactly.
- `FrameClock(nominalInterval:)` takes its interval; `AdaptiveResolution`'s
  `budget` is a property a test can set.

The settings are a value type (`VortexSettings`, `GargantuaSettings`) built by
the store and handed to the renderer, rather than read from defaults inside
it. Launch arguments are read only in the standalone app's `main.swift`. When
a knob is added, it is added once — on the type that uses it — and reached
through the value that carries that type, not mirrored as a second flag on
every caller.

**Incorrect (a setting read from defaults inside the renderer; a centre reached for globally):**

```swift
let speed = ScreenSaverDefaults(forModuleWithName: id)?.double(forKey: "flowSpeed") ?? 1
DistributedNotificationCenter.default().addObserver(…)   // a test cannot post to this safely
```

**Correct:**

```swift
let store = VortexSettingsStore(defaults: SaverPreferences(moduleIdentifier: identifier))
let lifecycle = SaverLifecycle(view: view, frameInterval: frameInterval, sessionCenter: center) { … }
```
