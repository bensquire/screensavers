---
title: A Change Is Checked, Not Believed
impact: CRITICAL
impactDescription: A saver whose shader library was missing passed every test and drew nothing; only loading the built bundle shows that
tags: [workflow, verification, tests, lint, build, verify]
paths: ["Sources/**", "Tests/**", "Scripts/**", "savers/**", "Package.swift", "Makefile"]
---

## A Change Is Checked, Not Believed

**Impact: CRITICAL**

The tests compile the shaders from source and drive the scenes headlessly, so
they cannot see whether the bundle the build script makes is one the host can
load and draw. Before saying a change is done:

1. **`make lint`** — swift-format over `Sources`, `Tests` and `Package.swift`.
2. **`make test`**, the whole suite, in release mode: 115 tests, about four
   seconds warm. Release because the numerical tests take tens of minutes
   unoptimised.
3. **`make verify SAVER=<name>`** for each saver the change touches, and
   `make all-verify` when it touches `SaverCore`, `SaverKit`, `Scripts/` or
   the `Makefile`, which every saver goes through. It builds
   the bundle, loads it the way the host does, and checks that both instances
   animate, the options sheet opens, a frame draws, and the saver draws again
   after a stop and restart. Look at `build/<name>/check.png` as well as the
   PASS line.
4. **`make bench SAVER=<name>`** for anything that could change what a frame
   costs; compare with the figure before the change.
5. **`make thumbnails SAVER=<name>`** after a change to how a scene looks, so
   the System Settings tile matches.

Report what was run and what it showed. Name a skipped check as skipped
rather than leaving it out.

**Incorrect (one class, no lint, no bundle):**

```
Ran VortexTests; passes. Done.
```

**Correct:**

```
lint clean; 115 tests in 3.0 s; vortex verifies (81,000 lit samples, draws
again after a restart); bench at 2560x1600: 1.12 ms GPU per frame at 100%
density, unchanged.
```
