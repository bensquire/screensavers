---
name: build
description: Build, verify, test, lint and package the screensavers — the four .saver bundles that Scripts/build-saver.sh compiles, the SwiftPM package that tests and type-checks them, and the standalone preview apps — and what installing and releasing do. Use when building or verifying a saver, running the suite or one test, linting or formatting, benchmarking a renderer, regenerating the System Settings tiles, adding a saver, or asked how a release is cut.
---

# Building the screensavers

Two build systems, on purpose. SwiftPM (`Package.swift`) is for `swift test`,
`swift format`, type-checking and the standalone apps; it cannot emit the
`MH_BUNDLE` that `ScreenSaverEngine` loads, so `Scripts/build-saver.sh` drives
`swiftc` directly for the `.saver` itself. Everything saver-specific is declared
in `savers/<name>/saver.conf`. The `Makefile` is the front door to both, and
picks the saver with `SAVER=<name>` (default `three-body`).

The savers are `gargantua`, `solar-system`, `three-body` and `vortex`
(`make list`).

## Prerequisites

- **Xcode 26** with its Swift 6 toolchain. Measured here with Xcode 26.6 and
  Swift 6.3.3; CI pins Xcode 26.6 on `macos-26`. The package is
  `swift-tools-version:6.0`, in Swift 5 language mode, deploying to macOS 14.
- **The Metal toolchain**, for `gargantua` and `vortex`, which have shaders.
  Xcode 26 ships it as a separate ~700 MB download:
  `xcodebuild -downloadComponent MetalToolchain`. Without it the build stops
  and prints that command.
- **swift-format** comes with the toolchain as `swift format`; there is
  nothing to install. There is no SwiftLint configuration in this repo.
- No package dependencies. The only vendored code is astronomy-engine, in
  `Sources/CAstronomy` (licence in `LICENSES/`).

## Commands

Timings are from an M1 Pro, warm caches unless noted.

| Command | What it does | Time |
|---|---|---|
| `make build SAVER=<name>` | `build/<name>/<Bundle Name>.saver`: release-optimised, universal (arm64 + x86_64), ad-hoc signed | ~8 s |
| `make verify SAVER=<name>` | Builds, then loads the bundle the way the host does: principal class, both instances, the options sheet, a drawn frame, a stop and restart that draws again. Writes `build/<name>/check.png` | 18–24 s |
| `make all-build`, `make all-verify` | The same for every saver | ~1.5 min for all-verify |
| `make test` | `swift test -c release`: 115 tests | ~4 s; ~17 s from cold |
| `make lint` | `swift format lint --strict` over `Sources`, `Tests`, `Package.swift` | <1 s |
| `make format` | The same, rewriting in place | <1 s |
| `make bench SAVER=<name>` | Release build of the standalone app, then `--bench`: per-frame CPU and GPU cost | ~6 s |
| `make thumbnails SAVER=<name>` | Re-renders the System Settings tiles into `savers/<name>/Resources/` | — |
| `make install SAVER=<name>` | Builds and installs into `~/Library/Screen Savers` (see below) | — |
| `make clean` | `swift package clean`, and removes `.build`, `build`, `dist` | — |

- **Tests run in release mode, always.** The three-body tests are million-step
  integrations and convergence measurements; unoptimised they take tens of
  minutes. `swift build -c release --build-tests` does not work as a shortcut
  (the `@testable` imports need testability, which `swift test` turns on), so
  go through `swift test -c release`.
- **One test:** `swift test -c release --filter 'SaverKitTests.SaverLifecycleTests/testSessionEndLeavesThePreviewAlone'`.
  A target or class name alone runs all of it.
- **Build options** for `Scripts/build-saver.sh`, as environment variables:
  `CONFIG=debug` (`-Onone -g`), `ARCHS="arm64"` for one slice, `VERSION` to
  stamp `Info.plist`, `CODESIGN_IDENTITY` (default `-`, ad-hoc).
- **Benchmarks are release-only** for the same reason as the tests: a debug
  build reports physics costs an order of magnitude too high. Extra flags pass
  through `ARGS`, e.g. `make bench SAVER=gargantua ARGS="--width 3840 --height 2160"`.
- **`make thumbnails` rewrites committed files.** The tiles are committed so a
  release stays a pure compile-and-link; regenerate them after a change to how a
  scene looks, and the diff is part of that change.

## The standalone apps

Each saver has an app target (`APP_PRODUCT` in its `saver.conf`) that runs the
same scene in a plain window, so a change can be watched without installing it
and locking the screen:

```sh
swift build -c release --product GargantuaApp && .build/release/GargantuaApp
```

The same binary takes `--bench` and `--render <png> --width --height --at`,
which is what `make bench` and `make thumbnails` call. Each app's flags and
keys are in its `Sources/<Name>App/`.

## Installing

`make install SAVER=<name>` builds, then quits `legacyScreenSaver`,
`WallpaperAgent`, `ScreenSaverEngine` and System Settings. Any of them still
holding the old bundle would make the kernel reject the new one. It then copies
the bundle to `~/Library/Screen Savers/`, re-signs it ad-hoc, and quits the
pickers again so they reread it. It changes the user's machine and closes
System Settings, so say so when it has been run.

After installing, the Options button in System Settings works only for the
first screensaver selected after System Settings opens. To try an options
change, quit System Settings and reopen it with that saver selected first
(`NOTES.md`, "The Options button").

## What CI runs

`.github/workflows/ci.yml`, on every push to `main` and every pull request:

1. `make lint` and `make test`, once.
2. For each saver in parallel: a check that every `savers/*` directory is in
   the CI matrix; the Metal toolchain if the saver has shaders; `make build`;
   a check of the bundle (executable, `Info.plist`, both tiles, the
   `.metallib` where there are shaders, both architecture slices via
   `lipo -archs`, `codesign --verify --strict`); `make verify`, with
   `check.png` uploaded.

`make lint && make test && make all-verify` covers the same ground locally,
apart from the `lipo` and `codesign` checks, which are worth running by hand
after a change to `Scripts/` or a `saver.conf`.

`.githooks/pre-commit` runs `make lint` and `make test`. It is active only
after `git config core.hooksPath .githooks`, which this checkout has not set.

## Adding a saver

A new saver is a directory, not an edit to the scripts:
`savers/<name>/saver.conf` (modules, frameworks, bundle name, shaders),
`Info.plist`, and `Resources/thumbnail.png` + `thumbnail@2x.png` (from
`make thumbnails`), plus its `<Name>Core`, `Render`, `Saver` and `App`
targets in `Package.swift`. CI fails until the saver is added to the matrix in
`ci.yml`.

## Releasing

Run this only when the user asks; it publishes.

Each saver versions on its own. A tag names the saver and the version,
`<saver>-v<version>` (e.g. `three-body-v1.2.0`). Two rules from `NOTES.md`,
because both fail silently:

- Push one tag at a time, by its ref: `git push origin refs/tags/three-body-v1.2.0`.
  GitHub drops the push event when several tags arrive together.
  `release.yml`'s header comment still shows `git push --tags`; follow
  `NOTES.md`.
- Tag after the workflow you need is on `main`: a tag runs `release.yml` as it
  was at the tagged commit.

`.github/workflows/release.yml` then:
- lints and tests;
- imports the Developer ID certificate into a throwaway keychain;
- builds with `CODESIGN_IDENTITY="Developer ID Application"`, which adds the
  hardened runtime and a secure timestamp, and stamps the version into
  `Info.plist`;
- verifies that exact bundle by running `Scripts/verify-saver.swift` directly,
  not `make verify`, which would rebuild and re-sign it ad-hoc;
- checks the architectures, signature, runtime flag, timestamp and version;
- notarises, staples, zips with `Scripts/make-zip.sh`, and publishes a GitHub
  Release. A version with a suffix (`1.1.0-beta.1`) becomes a prerelease.

It needs five repository secrets: `SIGNING_CERTIFICATE_P12_BASE64`,
`SIGNING_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`
and `APPLE_API_ISSUER_ID`.

`make release SAVER=<name>` (with `VERSION=`) is the local equivalent up to the
zip: an ad-hoc signed, un-notarised `dist/<Prefix>-<version>.zip`, which macOS
quarantines on download.

## When it fails

- **`unable to find utility "metal"`, or the build script's "needs the Metal
  compiler"** — install the Metal toolchain (above).
- **`savers/<name>/Resources/thumbnail.png is missing`** — run
  `make thumbnails SAVER=<name>`.
- **`make verify`: "rendered frame is black"** — the bundle loaded but drew
  nothing. For a Metal saver, check the `.metallib` is in
  `Contents/Resources` and named as `ShaderLibrary` expects; `PackagingTests`
  pins that pairing.
- **`make verify`: "render: declined"** — this GPU cannot render the saver
  offscreen (SceneKit on a paravirtual GPU, as on CI runners). Loading and the
  options sheet were still checked; the frame and restart checks were skipped
  for that instance.
- **The Options button does nothing** — System Settings, not the bundle (see
  Installing).
- **A reinstalled saver is killed on load ("Invalid Page")** — a host process
  still had the old bundle mapped. `make install` quits them for this reason;
  copying the bundle by hand skips that.
