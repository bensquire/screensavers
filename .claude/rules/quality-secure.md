---
title: Nothing Leaves the Machine, Preferences Are Untrusted, Releases Are Signed
impact: HIGH
impactDescription: A screensaver runs unattended inside a system process; one that phones home, trusts a plist or ships unsigned has broken trust
tags: [quality, security, privacy, signing, notarization, input]
paths: ["Sources/**/*.swift", "Scripts/**", "savers/**", ".github/workflows/**"]
---

## Nothing Leaves the Machine, Preferences Are Untrusted, Releases Are Signed

**Impact: HIGH**

- **No network, no child processes, no files but its own preferences.** A
  saver runs inside the system's sandboxed `legacyScreenSaver` host. None of
  the four makes a request, spawns a process or reads a user file, and a
  feature that needs one is a decision for the user, raised before it is
  built.
- **Preferences are input.** A hand-edited or stale plist can hold anything,
  including NaN, which `min`/`max` pass straight through into a uniform, where
  it blacks out a whole frame. Every stored number passes through its settings
  type's clamp on the way in (`VortexSettings.init`, `GargantuaSettings.init`,
  `SimulationSettings.clamped()`, all built on `clamped(to:)`), and a stored
  name that matches no case is ignored (`ScalePreset(rawValue:)`), so the scene
  can only be put into a state the options sheet could have produced.
- **Vendored code is named and licensed.** astronomy-engine (MIT) is the only
  third-party code; its licence is in `LICENSES/` and ships inside the Solar
  System bundle (`EXTRA_RESOURCES`).
- **Releases are signed, hardened and notarised.** Local builds are ad-hoc
  signed. `release.yml` signs with a Developer ID, the hardened runtime and a
  secure timestamp, checks all three on the exact bundle it will ship, then
  notarises and staples it. The certificate and API key exist only as
  repository secrets, decoded into the runner's temporary directory and a
  throwaway keychain that is deleted at the end; nothing in the workflow
  prints a secret.

**Incorrect (a stored value straight into the scene):**

```swift
let density = defaults.double(forKey: Key.density)   // NaN or 40.0 from a hand-edited plist
let count = Int(Double(Tunnel.particleCount) * density)
```

**Correct (through the initialiser that clamps):**

```swift
VortexSettings(
    flowSpeed: defaults.double(forKey: Key.flowSpeed),
    lightning: defaults.bool(forKey: Key.lightning),
    density: defaults.double(forKey: Key.density))
```
