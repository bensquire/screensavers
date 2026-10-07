---
title: Add a Directory or a Case, Not an `if`
impact: HIGH
impactDescription: A special case in shared machinery is a band-aid the next saver tears off
tags: [quality, extensibility, altitude, design]
paths: ["Sources/**/*.swift", "Scripts/**", "savers/**", "Makefile"]
---

## Add a Directory or a Case, Not an `if`

**Impact: HIGH**

The repository grows in two places, and each has one mechanism behind it:

- **A new saver is a directory.** `savers/<name>/saver.conf` declares its
  modules, frameworks, bundle name, shaders and extra resources, and
  `Scripts/build-saver.sh`, `install.sh`, `release.sh`, the `Makefile` and
  `verify-saver.swift` read it. Nothing in them names a saver. CI's matrix is
  the one list kept by hand, and a check fails the build when it falls behind
  `savers/`.
- **A new mode is a case.** `IntegratorOrder`, `ScenarioFamily`, `SceneMode`,
  `Accuracy` and `ScalePreset` are enumerations whose cases carry their own
  behaviour, and `CaseIterable` lets the tests and the options sheets list
  every case without being told (`IntegratorTests` loops over
  `IntegratorOrder.allCases`; Three-Body's sheet builds its mode buttons from
  `SceneMode.allCases`). `ScalePreset`'s raw value is the stored preference,
  so a new case is also a new stored value.

When a change wants a special case in shared code — a script that checks for
one saver's name, a `SaverKit` type that asks which scene it is hosting — the
fix is usually one level deeper: give the shared mechanism the field the case
needs, the way `METAL_SOURCES` lets the build compile shaders for the savers
that have them.

**Incorrect (the build script learns about one saver):**

```bash
if [ "$SAVER" = "gargantua" ] || [ "$SAVER" = "vortex" ]; then
  xcrun -sdk macosx metal -c …
fi
```

**Correct (the saver declares what it needs; the script reads it):**

```bash
# savers/gargantua/saver.conf
METAL_SOURCES="Sources/GargantuaRender/Gargantua.metal"
# Scripts/build-saver.sh
if [ -n "${METAL_SOURCES:-}" ]; then …
```
