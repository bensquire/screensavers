# Notes

Working notes for [Solar System](solar-system.md): what is genuinely computed,
what is deliberately distorted and why, and the traps found by measuring rather
than guessing. Kept off that page so it stays about installing and running the
screensaver.

---

## What's actually correct

Every planet's **direction** from the Sun is computed from a real ephemeris and
is accurate to **under 16 arcseconds** against JPL Horizons. Orbital phase,
inclination, the timing of the motion, and the 60.19° tilt of the ecliptic to
the galactic plane are all genuine.

| | Mercury | Venus | Earth | Mars | Jupiter | Saturn | Uranus | Neptune |
|---|---|---|---|---|---|---|---|---|
| error vs Horizons (arcsec) | 8.6 | 2.8 | 1.3 | 2.1 | 2.7 | 9.3 | 5.4 | 15.1 |

Measured at JD 2461259.5 TDB by `swift test`. Fixtures were fetched from the
[Horizons API](https://ssd.jpl.nasa.gov/api/horizons.api) and are baked into
`Tests/SolarSystemCoreTests/HorizonsFixtureTests.swift`.

Distances and sizes are not correct — see below. Note in particular that
because eccentricity is partly a radial quantity, radial compression draws the
ellipses rounder than they are: the perihelion/aphelion excursion is damped to
~0.38 of true, so Mercury's e=0.206 reads as about 0.079. Its *angular*
signature — visibly sweeping faster at perihelion — is exact.

There is also no dynamics simulation anywhere in this: positions come from
astronomy-engine's analytic series, not from integrating gravity.

Coordinates run through `Astronomy_HelioVector` (J2000 equatorial) and
`Astronomy_Rotation_EQJ_GAL`, so nothing about the galactic pole is
hand-rolled. In the resulting frame **+x** points at the galactic centre, **+z**
at the north galactic pole, and **+y** along galactic rotation — which is
exactly the Sun's direction of travel.

## What's deliberately not literal

Two display transforms are applied, both of which preserve every direction
exactly:

**Radial compression.** Scene radius is `r' = r^0.38`, so Neptune sits 3.6×
further out than Earth rather than 30×. Without this, either Mercury is a
sub-pixel dot or Neptune is off-screen.

**Drift rate.** The Sun really moves at ~230 km/s around the galactic centre —
**48.5 AU per year**. Against Earth's 1 AU orbit that makes the true helix so
stretched that Earth's path deviates only 7.5° from a straight line, and
Neptune's only 1.35°. The default drift is 0.32 units/year — about **0.66% of
true**, still heavily compressed, but enough to stretch the helix into a
structure with real depth to fly behind.

**Body sizes.** Radii are compressed as `(R / R_sun)^0.45` from real IAU
values, so the size *ordering* is genuine and the hierarchy is legible. True
scale is impossible — at 1 unit = 1 AU the Sun is 0.0047 units across and Earth
0.00004, both far under a pixel — and flat hand-picked sizes are the other
failure mode, which makes everything look identical. At the default the Sun
renders 8.3× Earth (109× in reality) and Jupiter 2.9×. Its absolute size is
bounded by Mercury's perihelion — the closest any planet actually comes to it —
so its disc can never swallow an orbit. `--sun-radius` and `--body-exponent`
tune it; `--true-scale` uses the real radii.

**Star motion.** The scene is drawn Sun-relative, so the helix of trails is
static in that frame and the Sun never moves on screen — which is exactly what
you'd see flying alongside it. That leaves the star field as the only possible
cue of travel, and real parallax can't supply it: over the 70-year window the
Sun covers ~3,400 AU while the nearest star sits 268,000 AU away, under a
degree. So the star field is scrolled at `--star-parallax` (default 16×) purely
as a visual cue. Set it to 0 for no star motion.

Run `swift run ssverify` to print the real numbers, including the full helix
geometry table. Pass `--true-scale` to the app to see what the honest version
looks like.

### The reference image is wrong about one thing

The popular "vortex" solar system animations draw the orbital plane
**perpendicular** to the Sun's direction of travel — that is, the ecliptic pole
parallel to the velocity vector. In reality the ecliptic pole sits at galactic
**l=96.4°, b=+29.8°**, which is **30.4° off** the direction of travel, so the
Sun's velocity meets the orbital plane at 59.6° rather than 90°.

Don't confuse that with the **60.19°** tilt of the ecliptic to the *galactic
plane* — a different measurement. The two come out near-complementary only
because the ecliptic pole happens to lie close to l=90°. Both are computed from
the rotation matrix rather than hard-coded, and both are asserted in
`GalacticFrameTests`.

The camera basis is derived from this geometry rather than hand-tuned: the
drift axis and the ecliptic pole define the frame the camera orbits in, so the
Sun's track holds a consistent angle on screen whatever point of the sweep the
camera is at.

## Scale modes

**True distances** keeps the drift compressed so the helix still reads, and
bodies are still drawn far oversized (with a minimum size) or Earth and Mercury
would be sub-pixel and their trails would end in nothing.

**Bird's eye** needs two things the others don't: the Sun is halved, because
removing the drift shrinks the scene about sevenfold and the Sun's radius is
absolute in scene units; and the camera fit is computed once and locked, since
re-fitting every frame keeps nudging a camera that is supposed to be
motionless.

Zeroing the drift also freezes the star field, because the field is scrolled by
how far the Sun has travelled. The Sun really is still moving — the orrery has
just chosen not to draw that motion in the planets' paths — so the sky still
slides, at about 2.4 px/s (`idleStarDriftFraction`). That is slower than the
drifting modes' ~6 px/s: enough to be alive without competing with the orbits,
which are the point of the view.

The saver reads the setting **when it starts**, so a preview already on screen
keeps the old mode until the host restarts. `Scripts/scale-mode.sh` writes both
preference stores and restarts the host for you. Each write is logged:

```sh
log show --last 10m --predicate 'subsystem == "com.solarsystem.screensaver"' --style compact
```

There is a fourth preset, **true scale** — everything at 1×, including the real
48.5 AU/yr drift. It is a demonstration rather than something to watch: every
body falls below a pixel and the system flattens to a sliver of near-parallel
streaks. It is not offered in the screensaver, but the app still renders it:

```sh
swift run SolarSystemApp --true-scale
swift run SolarSystemApp --true-distances
swift run SolarSystemApp --birds-eye
```

## The date readout

A very faint simulated date sits in the bottom-right corner — enough to read if
you look for it, easy to miss if you don't. It is a SpriteKit overlay on the
renderer rather than a view laid on top, so it appears in the offscreen
`--render` output as well as on screen, and it is sized as a fraction of the
viewport so it reads the same on any display.

It is deliberately fixed-width. The format is `dd MMM yyyy` — always eleven
characters — in `NSFont.monospacedSystemFont`, right-aligned, so nothing shifts
as the date advances. Note that `SKLabelNode(fontNamed:)` silently falls back to
a proportional face when the name does not resolve, and `"SFMono-Regular"` does
not resolve; the attributed-string route avoids that. Measured across sample
dates: 0.00 px spread monospaced, 2.88 px proportional.

## Camera

The camera follows **its own orbit around the Sun** — effectively an extra
planet. One revolution takes 80 seconds (4.5°/s), on a circle inclined **55°**
to the ecliptic with its ascending node aligned to the Sun's direction of
travel. Only the *direction* comes from the orbit; the radius is whatever the
framing fit needs, so the composition stays right all the way round. The path
carries the camera from ~30° off the travel axis (behind the Sun, looking along
its motion) through side-on and round to ~150° (ahead of it, looking back).

It **revolves rather than oscillates**. An earlier version swung back and forth
between two fixed angles, and every reversal read as a wobble rather than
travel. A closed orbit never reverses.

### Making the orbit visible

The first version of this orbited but was imperceptible, for a reason worth
recording: the up vector was derived from the **drift axis**, which pinned the
Sun's track to a constant screen angle. That acted as a gimbal — it held the
most prominent feature still while the camera moved behind it — and combined
with a fit that re-centres and re-scales every frame, the orbit was stabilised
straight out of view.

Up is now the camera orbit's **own normal**: fixed in world space, and
perpendicular to the view direction by construction, so there is no degenerate
case to guard. That gives a turntable — the system visibly rotates as the
camera goes round. The trade is that the Sun's track swings: it stays pointing
*downwards* throughout (the drift axis keeps a constant component of
0.86·cos 55° = 0.49 along the up vector) but sweeps between the bottom-left and
bottom-right corners over a revolution. The default phase starts it in the
bottom-left; `--roll` biases it further.

The other half of the problem was speed. At the old 0.75 yr/s **Earth lapped
every 1.33 seconds and Mercury every 0.32** — a churn that no slower motion
could be picked out of. 0.35 yr/s gives Earth 2.9 s and Jupiter 34 s, calm
enough for the camera to read. `--star-parallax` was doubled to 16 to keep the
star drift at the same rate.

`--inclination`, `--orbit-period` and `--phase` tune the path; `--elevation`
and `--azimuth` pin a fixed viewpoint for stills (`--elevation 90` is side on,
`--elevation 0` dead astern); `--no-camera-motion` holds it still.

### Why the fit is smoothed

The framing re-fits every frame from where the bodies currently are — and at
the default 0.75 yr/s, **Earth laps every 1.3 seconds**. Raw, that made the
target and distance oscillate at the inner planets' orbital frequency: ~20px of
frame shift and a 4.7% zoom throb, several times a second. It read as the
camera wobbling rather than sweeping.

Both are now low-passed, with different time constants — both well under the
camera's 80 s revolution, so the fit tracks the viewing angle rather than
trailing it. The target needs only to shed the fast orbital jitter (3 s).
Distance gets 7 s: it genuinely has to move, because the helix is long and thin
and its projected extent changes ~25% between end-on and side-on, so the camera
closes in and backs off to hold the *apparent* size constant. The longer
constant is only to suppress the inner planets — at 7 s a 2.9 s Earth cycle is
attenuated ~15×, while an 80 s orbit passes through nearly untouched.

An earlier 25 s constant was tuned for a 4-minute revolution; at 80 s it lagged
the orbit by over 100°, so the content visibly grew and shrank instead of
holding its size.

`--camera-trace` prints orbital phase, camera position, target and distance
over time. It's the quickest way to tell real camera motion from a jittering
fit: while orbiting, the camera coordinates change monotonically and the
distance holds steady.

## Framing

The camera fit projects every drawn sample onto the screen axes and sizes the
frame from them. Three simpler approaches were tried and discarded:

- A bounding **sphere** ignores aspect ratio and over-provisions whichever
  screen axis isn't binding — it left 9% dead at the top and 21% at the bottom.
- A hard bounding **box** is worse than it sounds: its extremes are the tips of
  the faintest trail tails, which are nearly black. Those tips drag the frame
  centre away from the bright mass and open a dead band on the opposite side.
- A **symmetric** window (mean ± k·sigma) fails on this composition too. The
  Sun is the brightest thing and sits at one end with the trails streaming away
  from it, so a symmetric window reserves as much room beyond the Sun as the
  trails need on the other side — and that empty half is a dead band.

The fit now takes weighted **percentiles** (2nd and 98th) of every sample,
weighted by the brightness it will actually be drawn with. That finds the two
ends independently, so the Sun can sit hard against one edge, and clips the
near-black tail without clipping the Sun. `--zoom` crops further if wanted. The
fit is redone on resize, since the optimal camera distance depends on aspect
ratio and each display gets its own saver instance.

## Performance

`SolarSystemRenderer.update(to:)` costs **1.23 ms**: 0.99 ms of ephemeris
(2,320 trail samples rebuilt from scratch), 0.14 ms fitting the camera, 0.07 ms
rebuilding the ribbon geometry, 0.02 ms on the date overlay. It runs on
SceneKit's display link, so the budget is 16.7 ms at 60 Hz — about 7%.
`ssverify` section [6] re-measures the snapshot.

The one substantial saving left is a per-planet ring buffer for the trails: the
window slides ~2 simulated days a frame while Mercury's sample spacing is 1.1
days, so ~8 of the 2,320 evaluations are genuinely new. That would remove
~0.95 ms — worth doing only if the frame budget ever becomes a problem, since
it trades a pure function for a cache.

## Notes on macOS screensavers

- macOS 14+ runs third-party savers inside a sandboxed `legacyScreenSaver`
  helper. Nothing here touches the network or reads files at runtime —
  astronomy-engine is pure computation with no ephemeris data files, which
  sidesteps the sandbox entirely.
- SceneKit drives its own display link, so `animateOneFrame()` is deliberately
  empty; `animationTimeInterval` is set slow so the two loops don't fight.
- System Settings creates a *second* live instance for the preview thumbnail.
  `isPreview` drops trail samples to 72 and disables MSAA.
- The System Settings grid also wants `thumbnail.png` and `thumbnail@2x.png` in
  the bundle, or the saver shows as an easy-to-miss blank tile. They're real
  frames of the real scene, but they live in `Resources/` and are committed —
  see the GPU note below. `make thumbnails` regenerates them.
- SwiftPM cannot emit an `MH_BUNDLE`, which is what `ScreenSaverEngine`
  `dlopen`s. `Scripts/build-saver.sh` therefore drives `swiftc` directly:
  compile each module in dependency order, then link the objects with
  `-bundle`. The `Package.swift` is still what type-checks, tests and formats
  the code.

## Releasing

`Scripts/build-saver.sh` ad-hoc signs the bundle, which is enough to load
locally. Set `CODESIGN_IDENTITY` to a Developer ID and it switches to a
hardened-runtime, timestamped signature — the form notarisation requires, and
one an ad-hoc signature can't carry. That's what `release.yml` does.

The executable is signed before the bundle. Signing the bundle seals its
contents, so the other order invalidates the wrapper the moment the inner
binary is re-signed.

The archive is built with `ditto -c -k --keepParent`, after stapling. Plain
`zip` mangles the bundle directory, its code signature and its extended
attributes — which is where the stapled notarisation ticket lives, and the
ticket is what lets the saver validate offline.

Two ways the signing secrets go wrong, both of which `release.yml` checks for
up front because `security import` reports them identically ("user name or
passphrase is not correct"):

- **The p12 didn't survive base64.** Export the cert *with its private key* and
  encode it with `base64 -i cert.p12 | pbcopy`. The workflow prints the decoded
  byte count and the two-byte magic (`3082` for PKCS#12) and fails early if it
  doesn't look like a p12.
- **The password picked up a newline.** `echo` appends one; use
  `printf '%s' 'your-password' | pbcopy`. The workflow rejects a password that
  differs from itself with newlines stripped.

A tag with a suffix (`v1.1.0-beta.1`) publishes as a prerelease. The plist gets
the numeric part only, since `CFBundleShortVersionString` won't take the
suffix.

For a local unsigned archive — quarantined on download, so only useful for
testing the packaging:

```sh
VERSION=1.0.0 make release SAVER=solar-system   # -> dist/SolarSystem-1.0.0.zip
```

## Traps found the hard way

**Type-checker timeouts.** `cameraDirection(atElapsed:)` built the fixed
viewpoint from four scalar-times-vector terms in one expression. Every `*` and
`+` there is overloaded for scalars as well as SIMD vectors, and the nesting sat
right on the type checker's time limit: it compiled locally and for the arm64
slice on CI, then timed out on the x86_64 slice of the same run. Split into two
annotated statements. Worth remembering that "it compiles here" is not evidence
about a slower machine.

**No offscreen SceneKit on a CI runner.** GitHub's hosted macOS runners are VMs
with a paravirtualised GPU, and `SCNRenderer.snapshot` traps there rather than
returning an error:

```
Assertion failed: (texture.resourceID),
  -[AppleParavirtTexture initWithTexture:pixelFormat:textureType:levels:slices:swizzle:]
```

It aborts the process, so `set -e` can't distinguish it from a build failure. A
probe run tried the full matrix — MSAA on and off, 90×58 up to 1440×900, with
and without the SpriteKit overlay — and every combination failed identically.
This isn't an antialiasing quirk to work around; offscreen rendering is simply
unavailable there. Hence two things: the thumbnails are rendered on a real
machine and committed, and `verify-saver.swift` is called in CI without an
output path, so it performs every check *except* the snapshot. The bundle still
gets loaded, the principal class resolved, both views instantiated and the
scene graph built and counted — which is most of what that script is for.

**Reinstalling over a running saver.** The kernel keeps the old bundle's signed
pages mapped, and rejects the new binary with "Invalid Page" → `SIGKILL`.
`Scripts/install.sh` kills `legacyScreenSaver`, `WallpaperAgent`,
`ScreenSaverEngine` and System Settings first, then re-signs after the copy so
the on-disk mtime matches the signed code directory.
