<div align="center">

# Screensavers

**Native macOS screensavers, sharing one build, signing and release pipeline.**

[![CI](https://img.shields.io/github/actions/workflow/status/bensquire/screensavers/ci.yml?branch=main&label=ci&logo=github&cacheSeconds=300)](https://github.com/bensquire/screensavers/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-007aff?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/github/license/bensquire/screensavers?label=license&cacheSeconds=300)](LICENSE)

</div>

| | | |
|---|---|---|
| **[Solar System](docs/solar-system.md)** | SceneKit | The solar system travelling through the galaxy, every planet in its real position for today's date. |
| **[Three-Body Problem](docs/three-body.md)** | Core Graphics | The gravitational three-body problem integrated in real time, in solar masses, AU and years. |

Each is downloaded and installed separately — see its page, or the
[releases](https://github.com/bensquire/screensavers/releases).

## Why one repository

Not for shared rendering: one draws with SceneKit and one with Core Graphics,
and they have almost no drawing code in common. What they share is everything
around it — compiling a loadable `MH_BUNDLE`, signing it with a Developer ID,
notarising, stapling, packaging, and verifying that the result is something
`ScreenSaverEngine` can actually load. That machinery is fiddly, easy to get
subtly wrong, and was previously duplicated per project and already drifting.

Two WebView-based screensavers ([SlidersVortex](https://github.com/bensquire/SlidersVortex),
[Gargantua](https://github.com/bensquire/gargantua)) are deliberately *not* here.
They host HTML and JavaScript in a `WKWebView`, run on macOS 11, and have no
Swift logic to test — so they would share the release job and nothing else,
while forcing this package's platform floor up.

## Working on them

```sh
make list                          # which savers exist
make build   SAVER=three-body      # build/<saver>/<Name>.saver, ad-hoc signed
make verify  SAVER=three-body      # load the built bundle for real and draw a frame
make install SAVER=three-body      # build and install to ~/Library/Screen Savers
make test                          # every saver's tests
make lint
make all-build                     # every saver
```

Adding a screensaver means adding `savers/<name>/` — a `saver.conf` declaring its
modules, frameworks and bundle name, an `Info.plist`, and the two System Settings
tiles. Nothing in `Scripts/` or the `Makefile` needs editing, and CI fails if a
new saver is missing from its matrix.

## Releasing

Each screensaver versions independently, so a tag names which one:

```sh
git tag three-body-v1.0.0 && git push --tags
```

That runs `.github/workflows/release.yml`, which signs with a Developer ID,
notarises, staples the ticket, and publishes a GitHub Release containing just
that saver. It needs five repository secrets — `SIGNING_CERTIFICATE_P12_BASE64`,
`SIGNING_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID` and
`APPLE_API_ISSUER_ID`.

## Layout

```
Sources/SaverKit/          the little that is genuinely common to hosting a saver
Sources/<Saver>Core/       physics and model — Foundation only, so it is testable headlessly
Sources/<Saver>Render/     drawing
Sources/<Saver>Saver/      the ScreenSaverView subclass
Sources/<Saver>App/        standalone window, and the thumbnail renderer
savers/<name>/             saver.conf, Info.plist, System Settings tiles
Scripts/                   build, sign, install, package, verify — shared by all savers
```

SwiftPM is here for `swift test`, `swift format` and type-checking. It cannot
emit the `MH_BUNDLE` that `ScreenSaverEngine` `dlopen`s, so `Scripts/build-saver.sh`
drives `swiftc` directly: compile each module in dependency order, then link
with `-bundle`.
