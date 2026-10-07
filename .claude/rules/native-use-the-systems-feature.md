---
title: Use the System's Feature, Not a Copy of It
impact: HIGH
impactDescription: The host, System Settings and the OS already provide the timer, the sheet, the preferences and the energy signals; a copy has to be kept in step by hand
tags: [native, macos, screensaver, appkit, metal, scenekit]
paths: ["Sources/**/*.swift"]
---

## Use the System's Feature, Not a Copy of It

**Impact: HIGH**

A saver should behave like part of macOS: it runs when the system says, stops
when the system says, and is configured the way every other screensaver is.
Before writing a timer, a window, a preferences file or a control, ask whether
the ScreenSaver framework or AppKit has one. It usually does.

- **Frames** come from the host's timer: `animateOneFrame`, at the rate set by
  `animationTimeInterval`, which the host follows even mid-animation. Only the
  standalone apps, which have no host, run a timer of their own.
- **Preview or full screen** is `isPreview`, given at init.
- **Options** are the window returned from `configureSheet`, presented by
  System Settings, built from AppKit's standard controls (`NSSlider`,
  `NSGridView`, `NSStackView`) with system fonts and semantic colours —
  through `OptionsSheet` in three of the four; Solar System builds its own.
- **Preferences** are `ScreenSaverDefaults`, through `SaverPreferences`.
- **Energy** follows the system's own signals: display sleep from
  `NSWorkspace`, Low Power Mode from `ProcessInfo`, session end from the
  `com.apple.screensaver.willstop` notification.
- **Drawing** is Core Graphics, SceneKit or Metal through a `CAMetalLayer`;
  maths that SIMD types express is `simd`.

Where the system falls short, the workaround lives once, in `SaverKit`, and
`NOTES.md` says what was measured: the host neither stops nor releases a
saver (`SaverLifecycle`), and a write from the sandboxed host's sheet can be
refused (`SaverPreferences` mirrors it). Read those notes before working
around the host again.

Native is not generic: the scenes — the Kerr geodesics, the integrator, the
tunnel — are the savers' own work, built on the system's parts.

**Incorrect (a timer of our own, beside the host's):**

```swift
timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in self.step() }
```

**Correct (the host's timer and the system's sheet):**

```swift
override func animateOneFrame() { … }
override var hasConfigureSheet: Bool { true }
override var configureSheet: NSWindow? { configController.window }
```
