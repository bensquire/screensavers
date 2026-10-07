---
title: Every Run Gives the Same Answer
impact: HIGH
impactDescription: A flaky test is a test nobody trusts; a careless one can stop every screensaver on the machine
tags: [testing, determinism, fixtures, gpu, isolation]
paths: ["Tests/**/*.swift"]
---

## Every Run Gives the Same Answer

**Impact: HIGH**

- **Randomness is seeded.** A scene that draws random numbers takes a
  `SplitMix64` seed, and `SplitMix64` spells out its own bits-to-Double
  mapping so seeded output survives a standard-library change.
- **Fixtures are committed, never fetched.** The Horizons vectors live in
  `HorizonsFixtureTests`, with the query that produced them and the date it was
  run in the doc comment. No test touches the network.
- **Nothing outside the test is touched.** `SaverLifecycleTests` posts the
  session-end notification to a local `NotificationCenter`: posting the real
  `com.apple.screensaver.willstop` would stop every screensaver running on the
  machine. Preference tests use their own fixed domain and empty it in
  `setUp` and `tearDown`.
- **Machine state is read, not assumed.** Where an expectation depends on the
  machine — Low Power Mode halving the frame rate — the test reads the state
  and states its expectation from it.
- **No waiting for luck.** The lifecycle tests post and check synchronously;
  a test never sleeps hoping work has finished.
- **A missing GPU is a skip, not a failure.** A Metal test throws `XCTSkip`
  when there is no device or no frame comes back; a SceneKit render test skips
  on a paravirtual GPU (`isParavirtual`), where SceneKit aborts the process
  rather than returning an error. The skip message says why, so CI stays
  green and honest.

**Incorrect:**

```swift
DistributedNotificationCenter.default().post(name: SaverLifecycle.sessionWillStop, object: nil)
var rng = SystemRandomNumberGenerator()
```

**Correct:**

```swift
let center = NotificationCenter()
center.post(name: SaverLifecycle.sessionWillStop, object: nil)
var rng = SplitMix64(seed: 42)
```
