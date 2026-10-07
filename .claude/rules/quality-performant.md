---
title: A Screensaver Runs All Night; Its Duty Cycle Is the Budget
impact: HIGH
impactDescription: Gargantua once held an M1 Pro's GPU at 68% all night; the host once kept 22.8 GB of leaked views alive for 21 days
tags: [quality, performance, energy, gpu, measurement]
paths: ["Sources/**/*.swift"]
---

## A Screensaver Runs All Night; Its Duty Cycle Is the Budget

**Impact: HIGH**

Nobody is watching most of the hours a screensaver runs, so the cost that
matters is the fraction of every frame it keeps the processor and GPU busy, not
its peak frame rate. A screensaver that runs hot is a worse screensaver than a
softer one. The measured choices that follow from that:

- **A budget, not a maximum.** Gargantua's adaptive resolution aims at a
  quarter of each 33 ms frame. At two thirds it settled at 22.7 ms of every
  33 ms on a 3456x2234 panel — the GPU busy 68% of the time, with the fans to
  match. Resolution is what gives.
- **Nothing drawn when nothing is seen.** `SaverLifecycle` stops the view at
  session end, draws nothing while the displays sleep and drops the timer to
  one tick every five seconds, and halves the frame rate in Low Power Mode.
  Stopping releases the Metal or SceneKit view, so a host that leaks the view
  (`NOTES.md`) keeps something small and idle.
- **Pixels a viewer can see.** `MetalLayerView.maximumBackingScale` caps the
  backing scale at 2x.
- **Work done once, not per frame.** Solar System's trail evaluated the
  ephemeris 2,320 times a frame; sampling it on a grid and interpolating took
  the scene update from ~1.2 ms to 0.23 ms.

Which code is hot is decided by measuring, with `make bench SAVER=<name>`, in
release: a debug build reports three-body physics an order of magnitude too
slow. A fast path carries its before and after in a comment. Everything else
is written for the reader.

**Incorrect (a fixed scale and a full frame rate, whoever is looking):**

```swift
let scale = 1.0                                   // whatever the display costs
view.animationTimeInterval = 1.0 / 60             // also while the panel is asleep
```

**Correct (a budget, with the measurement that set it):**

```swift
/// It was two thirds of the frame, and on an M1 Pro's own 3456x2234 panel
/// that settled at 22.7 ms of every 33 ms — the GPU busy 68% of the time …
public static let defaultBudget = 0.25 * FrameClock.frameInterval
```
