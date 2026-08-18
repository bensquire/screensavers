# Notes

How the repository is put together, and the things about building, signing and
releasing a macOS screensaver that turned out to be worth writing down.

For what each screensaver *is*, see its page: [Gargantua](docs/gargantua.md),
[Sliders Vortex](docs/vortex.md), [Solar System](docs/solar-system.md),
[Three-Body Problem](docs/three-body.md).

## Why one repository

Not for shared rendering: they draw with SceneKit, Core Graphics and Metal
respectively, and have almost no drawing code in common. What they share is
everything around it — compiling a loadable `MH_BUNDLE`, signing it with a
Developer ID, notarising, stapling, packaging, and verifying that the result is
something `ScreenSaverEngine` can actually load. That machinery is fiddly, easy
to get subtly wrong, and was previously duplicated per project and already
drifting.

A little more turned out to be genuinely common than expected. It is split in
two so the "Core is Foundation-only" rule below stays true rather than merely
intended: `SaverCore` holds what a physics module may use — a seedable PRNG, a
NaN-safe clamp — and `SaverKit` holds the rest, which links AppKit and Metal.
That is preferences which survive being written from a sandboxed host, the
options-sheet layout (got wrong once by building it from intrinsic widths, when
System Settings presents the sheet wider than that), a `CAMetalLayer` view
base, shader loading, and the frame-capture hook `make verify` uses.

Every saver is verified the same way: the built bundle is loaded for real, both
view instances are animated, and the frame they actually drew is asserted on. A
saver drawing on the GPU hands its frame back through `SaverFrameCapturing`,
because its backing store is empty and `cacheDisplay` would capture nothing —
which is what a missing or stale `.metallib` used to look like.

## Working on them

```sh
make list                      # which savers exist
make build   SAVER=three-body  # build/<saver>/<Name>.saver, ad-hoc signed
make verify  SAVER=three-body  # load the built bundle for real and draw a frame
make bench   SAVER=three-body  # time the renderer (release build, fixed seed)
make install SAVER=three-body  # build and install to ~/Library/Screen Savers
make test                      # every saver's tests
make lint
make all-build                 # every saver
```

Adding a screensaver means adding `savers/<name>/` — a `saver.conf` declaring
its modules, frameworks and bundle name, an `Info.plist`, and the two System
Settings tiles. Nothing in `Scripts/` or the `Makefile` needs editing, and CI
fails if a new saver is missing from its matrix.

## Releasing

Each screensaver versions independently, so a tag names which one:

```sh
git tag three-body-v1.0.0
git push origin refs/tags/three-body-v1.0.0
```

Two things about that, both of which fail silently:

- **Push tags one at a time**, and push the ref explicitly rather than using
  `--tags`. GitHub drops the `push` event when several arrive together: four
  tags pushed at once produced no release runs at all, and re-pushing a single
  tag on its own started one immediately.
- **Tag after the workflow you need is on `main`.** A tag build runs
  `release.yml` *as it was at the tagged commit*, not as it is now — so a tag
  created before a pipeline fix will keep failing in the way that fix repaired.
  Move the tag (`git tag -d`, delete the remote ref, re-tag, push) and it picks
  up the current workflow.

That runs `.github/workflows/release.yml`, which signs with a Developer ID,
notarises, staples the ticket, and publishes a GitHub Release containing just
that saver. It needs five repository secrets —
`SIGNING_CERTIFICATE_P12_BASE64`, `SIGNING_CERTIFICATE_PASSWORD`,
`APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID` and `APPLE_API_ISSUER_ID`.

The release verifies the artefact it is about to ship rather than a rebuild of
it. That distinction is not pedantic: `make verify` depends on `build`, so
calling it from the pipeline quietly re-signed the bundle ad-hoc *after* the
signature check had passed, and Apple rejected the result for having no
Developer ID and no secure timestamp.

## The Options button

System Settings binds a screensaver's Options button to whichever screensaver
was loaded when the pane first appeared, and picking another one in the grid
never rebinds it. So Options works for the first screensaver selected after
System Settings launches and silently does nothing for every one after that.

This is worth knowing before debugging a configure sheet that appears broken.
It is ordinal rather than saver-specific — two of these savers share their
sheet code line for line and behaved differently purely on selection order —
and there is nothing a `.saver` bundle can do about it. Quitting System
Settings (&#8984;Q) and reopening with the target screensaver selected first is
the only workaround.

## Layout

```
Sources/SaverCore/      Foundation-only shared code, usable from a Core
Sources/SaverKit/       the rest of the shared hosting code (AppKit, Metal)
Sources/<Saver>Core/    physics and model — Foundation only, testable headlessly
Sources/<Saver>Render/  drawing
Sources/<Saver>Saver/   the ScreenSaverView subclass
Sources/<Saver>App/     standalone window, and the thumbnail renderer
savers/<name>/          saver.conf, Info.plist, System Settings tiles
Scripts/                build, sign, install, package, verify — one copy for all
```

SwiftPM is here for `swift test`, `swift format` and type-checking. It cannot
emit the `MH_BUNDLE` that `ScreenSaverEngine` `dlopen`s, so
`Scripts/build-saver.sh` drives `swiftc` directly: compile each module in
dependency order, then link with `-bundle`.
