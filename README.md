<div align="center">

# Three-Body Problem

**A macOS screensaver that integrates the gravitational three-body problem in
real time — no canned animation, no fudged orbits.**

[![CI](https://img.shields.io/github/actions/workflow/status/bensquire/three-body-problem/ci.yml?branch=main&label=ci&logo=github&cacheSeconds=300)](https://github.com/bensquire/three-body-problem/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/actions/workflow/status/bensquire/three-body-problem/release.yml?label=release&logo=github&cacheSeconds=300)](https://github.com/bensquire/three-body-problem/actions/workflows/release.yml)
[![Latest](https://img.shields.io/github/v/release/bensquire/three-body-problem?include_prereleases&label=latest&logo=apple&cacheSeconds=300)](https://github.com/bensquire/three-body-problem/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-007aff?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/github/license/bensquire/three-body-problem?label=license&cacheSeconds=300)](LICENSE)

[**Download latest &rarr;**](https://github.com/bensquire/three-body-problem/releases/latest)

<br/>

<img src="docs/screenshot.png" alt="Three equal masses tracing the figure-eight orbit: three glowing bodies chasing each other around a single closed curve against a starfield" width="900"/>

<sub>The figure-eight orbit, drawn by the thing itself.</sub>

</div>

Every frame comes out of Newton's law of gravitation and a symplectic
integrator, and the readout in the corner shows exactly how far the integration
has drifted — usually one part in 10¹³. Everything is shown in real
astrophysical units: solar masses, astronomical units and years.

## Install

Download the latest release, unzip, and double-click the `.saver` — or move it
to `~/Library/Screen Savers/`. Then pick **Three-Body Problem** in
System Settings → Screen Saver.

The release is signed with a Developer ID and notarized by Apple, so it installs
without a Gatekeeper warning. Universal (Apple Silicon + Intel), macOS 14+.

## Scenes

The options sheet offers three choices:

- **Known orbits** — the catalogue. The figure-eight, ten Šuvakov–Dmitrašinović
  families, Lagrange, Euler and Burrau. Fixed initial conditions, so each
  replays identically; the figure-eight is only the figure-eight for one exact
  set of numbers.
- **Random systems** — never repeats. Hierarchical triples, chaotic and
  free-fall systems, and flyby encounters, generated fresh every scene.
- **Both** — alternates between them. The default.

Along with pace, trail length, scene length, integrator accuracy, and whether to
show the readout, the glow, and the stars.

## Building it yourself

```sh
make test       # the physics measurements
make build      # build/Three-Body Problem.saver, ad-hoc signed
make verify     # load the built bundle for real and draw a frame
make install    # build and install to ~/Library/Screen Savers
make run        # watch it in a window (MODE=known|random|both)
```

Releases are cut by pushing a tag: `git tag v1.0.0 && git push --tags`. That
runs `.github/workflows/release.yml`, which signs with a Developer ID,
notarizes, staples the ticket, and publishes a GitHub Release. It needs five
repository secrets — `SIGNING_CERTIFICATE_P12_BASE64`,
`SIGNING_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID` and
`APPLE_API_ISSUER_ID`.

SwiftPM can't emit the `MH_BUNDLE` that ScreenSaverEngine `dlopen`s, so
`Scripts/build-saver.sh` drives `swiftc` directly: compile each module in
dependency order, then link with `-bundle`. `Package.swift` still exists, and is
what `swift test` and `swift format` work against.

## The physics

**Units.** The integrator works with G = 1, the convention the periodic-orbit
literature states its solutions in. Everything shown on screen is converted to
solar masses, AU and years, which is not a cosmetic relabelling: fixing
1 mass unit = 1 M☉ and 1 length unit = 1 AU determines the time unit completely,
because G = 4π² AU³ M☉⁻¹ yr⁻² is then no longer free. One internal time unit is
1/(2π) years, and one velocity unit is 29.79 km/s — Earth's orbital speed. The
test suite verifies the mapping by integration: a body circling 1 M☉ at 1 AU
closes its orbit after exactly one year, to 2 × 10⁻⁸ AU.

So the figure-eight is three suns on a 1.01-year orbit, and Burrau's problem
ejects a body after 9.6 years. The bodies are true point masses: no softening
length, no artificial speed limits, and nothing smoothing the 1/r² singularity.
Close encounters are therefore real slingshots, and they are exactly where the
numerical difficulty lives.

**Integrator.** Gravity's Hamiltonian separates as H = T(p) + V(q), which admits
symplectic integrators — methods that preserve phase-space volume exactly and
keep the energy error bounded and oscillatory instead of letting it grow
secularly the way a generic Runge–Kutta method does. The base method is
drift–kick–drift leapfrog; higher orders come from symmetric composition
(Yoshida 1990). Orders 4 and 6 use Yoshida's coefficients; order 8 is built by
Suzuki's five-fold composition of the 6th-order method, which measures better
per force evaluation than the usual triple-jump construction.

**Adaptive steps.** A three-body system is scale-free — a wide slow triple and a
hard binary grazing at 100× the speed can both happen in the same run. The step
is set from the shortest local dynamical timescale over all pairs: the free-fall
time √(r³/GM) and the fly-by time r/v. Plain adaptivity would destroy the
time-symmetry that makes symplectic methods well behaved, so the step is
symmetrised (Hut, Makino & McMillan 1995) by taking the harmonic mean of the
estimates at the start and the provisional end of each step. That restores
reversibility, and with it the bounded energy error.

**Collisions.** Point masses have no size, so one is chosen: a body holding the
whole system's mass would have a radius of 1e-6 of the scene's initial extent,
and individual radii scale as the cube root of mass fraction from there. When two
bodies touch they merge perfectly inelastically, conserving mass and momentum;
the kinetic energy and the pair's internal angular momentum are shed, which is
what "inelastic" means and not integration error.

That constant is measured, not chosen by taste. Raise it to 2e-6 and Yarn — a
published periodic orbit whose five-decimal constants drift into chaos after a
dozen periods — starts ending in collisions, which misrepresents it. At 1e-6 no
catalogued orbit ever touches, while the genuinely singular encounters still do.
Contact is tested inside the integrator loop rather than per frame, because two
bodies cross a radius that small in far less than a frame.

**Playback speed.** A three-body scene has no single natural pace — the same
system can spend a minute in a lazy wide orbit and resolve everything in a
fraction of a second. Played at one fixed rate, either the quiet stretches crawl
or the interesting part is a blur.

The clock is therefore driven by **apparent speed**: how fast the bodies
actually cross the screen, held near 210 points per second. An earlier version
paced from dynamical timescales instead, which sounds more principled and is the
wrong quantity — a timescale knows nothing about how big the system looks, so a
wide cold triple was slowed to 60% while visibly barely moving. Screen speed
folds in both how fast the bodies move and how far the camera has had to pull
back, so a sprawling system speeds up and a violent encounter slows down for the
same reason. The measurement is smoothed first: a periodic orbit's brief speed
peak at its crossing is about four times its typical speed, and pacing to that
moment slowed whole orbits fourfold to accommodate an instant of it.

The correction is large, because the hand-tuned rates it replaced were far
apart: generated systems run 5.9–6.7× faster than before, while the catalogue
orbits keep roughly the pace they were designed at (the figure-eight takes 12.7
seconds a revolution against 11 before). The readout shows the multiplier when
it is not 1.

**Vetting.** Random initial conditions produce plenty of duds — two bodies that
touch almost at once, or a third that was never really bound. Each generated
candidate is integrated ahead of time and discarded if it does not survive 25
seconds of screen time, so a scene never dies moments after fading in. (Borrowed
from ThreeBodyBot, which hunts for conditions lasting 15 simulated years before
committing to a render.)

**What the readout means.** `ΔE/E` and `ΔL` are the relative drift in total
energy and angular momentum — both are exact constants of the true motion, so
anything non-zero is purely numerical. `step` is the current timestep in system
units; watch it collapse by several orders of magnitude as two bodies swing past
each other. A scene is retired early if the drift ever exceeds 5 × 10⁻³.

## The scenes

**Periodic orbits.** The figure-eight (Moore 1993; Chenciner & Montgomery 2000)
and ten of the Šuvakov–Dmitrašinović (2013) families — Butterfly, Moth,
Bumblebee, Goggles, Dragonfly, Yarn, Yin-Yang. Each is a genuinely closed orbit;
the test harness integrates every one of them for a full period and checks that
it returns to its starting state.

**Classical solutions.** Lagrange's rotating equilateral triangle and Euler's
rotating collinear configuration, both exact — and both linearly unstable at
equal masses, so round-off alone is enough to tear them apart after several
revolutions. That is not a bug in the integrator; suppressing it would be.
Plus Burrau's Pythagorean problem (1913): masses 3, 4 and 5 released from rest
at the vertices of a 3-4-5 triangle, which plunges through a long series of
near-collisions before ejecting a body around t ≈ 60.

**Hierarchical triples.** A tight binary with a distant companion on Keplerian
orbits — the only arrangement real triple stars survive in long-term. Separation
ratios span 3.2–14×, eccentricities up to 0.55, and the inner and outer orbits
get independent rotation senses, so counter-rotating systems occur as often as
co-rotating ones.

**Chaotic and free-fall.** Randomised bound systems at a chosen virial ratio
(0.15–0.95), and random masses either dropped from exact rest or released with a
fraction of circular speed — a pure radial plunge and a slow tumble look quite
different.

**Flyby encounters.** A bound binary meeting an intruder that arrives from
outside on an unbound hyperbolic trajectory, with a random impact parameter and
approach speed. This is the encounter that actually builds and breaks triple
systems in a star cluster, and it resolves as a clean flyby, an exchange, or a
chaotic tangle before somebody leaves.

### Two modes

The options sheet offers **Known orbits**, **Random systems**, or **Both**
(the default). The distinction is real, not cosmetic: the catalogue replays from
fixed initial conditions, because the figure-eight is only the figure-eight for
one exact set of numbers, while generated systems are drawn fresh and never
repeat. Measured over 3000 scene draws:

| | known orbits | random systems | both |
|---|---|---|---|
| fixed initial conditions | 100% | 0% | 47% |
| freshly generated | 0% | 100% | 53% |

Catalogue entries are drawn individually rather than by family, so all fourteen
come up equally often (~7.2% each in *Known orbits*). Drawing by family instead
made each of the three classical solutions four times as likely as each of the
eleven periodic ones.

Generated masses are log-uniform across the stellar range, so lopsided systems
are as likely as balanced ones. Measured over 300 draws: **0.21–29 M☉** (median
2.7), separations **9.7–214 AU** (median 41), peak speeds up to **79 km/s**.

Body colour follows mass *rank* rather than array position, so the heaviest body
is the same colour in every scene and the hierarchy reads at a glance.

## Framing

The camera has to follow a system with no fixed scale, and two things make that
hard. Both fixes are lifted from Kirk Long's ThreeBodyBot, whose camera is
noticeably smoother than a naive one.

A tight binary orbits fast, so a frame fitted to all three bodies wobbles at the
binary's own orbital frequency. When a pair is bound tightly relative to the
third body it is therefore collapsed to its **centre of mass** and framed as a
single point, with hysteresis so a system sitting near the threshold cannot
chatter between modes.

When the framing set does change, the target moves discontinuously. Easing
towards it would both lag in steady state and take seconds to absorb the jump.
Instead the jump is measured once and parked in an **offset that decays
geometrically to zero**, so the camera tracks its target exactly while the
discontinuity melts away underneath it. A short low-pass filter on top absorbs
the per-frame steps that trail pruning puts into the bounding box.

A third mechanism sits under both: a **hard limit on the output**, capping how
far the view may zoom or pan in one second whatever the rest of it asks for.
That is what makes smoothness a property of the camera rather than something
that has to be re-established every time an input is tuned — it was the
offset decay, which bypassed every earlier limit, that turned out to be doing
most of the damage.

The right thing to measure is not per-frame jerk but **oscillation**: how often
the view reverses direction, and how far it swings. Median across 14 generated
scenes per family, measured within a single scene:

| family | zoom reversals/min | pan reversals/min | zoom swing per 10 s |
|---|---|---|---|
| periodic | 0.0 | 0.0 | 43% |
| classical | 0.0 | 0.0 | 143% |
| hierarchical | 0.0 | 0.0 | 15% |
| chaotic | 1.8 | 0.0 | 110% |
| free fall | 2.8 | 0.7 | 108% |
| flyby | 0.0 | 0.0 | 67% |

For comparison, before this work a chaotic scene reversed direction 17–20 times
a minute, swung its zoom by 510% and panned 1830 points — well over a screen
width, and Burrau's problem reversed 49 times a minute. Panning is now
essentially eliminated, and four of the six families never reverse the zoom at
all. What swing remains is mostly one-way reframing rather than oscillation:
these systems genuinely expand and collapse by large factors.

The camera and the pacing pull against each other — running the scenes 6× faster
means the framing has to change 6× faster too — so the two were balanced against
each other rather than tuned separately.

## The backdrop

The star field drifts, each star at a rate set by its own brightness, so the
bright ones near the front slide visibly while the faint ones behind lag and the
field reads as having depth. The median star covers about 7 points a second —
69 points in ten seconds, a little over three minutes to cross a 1440-point
window.

The first attempt used a nominal 2.4 points a second, which sounds
slow-and-tasteful and was in practice invisible. Brightness is distributed as
b², so the *typical* star sat near the far end of the depth range and crawled
at under one point per second. The figure worth tuning is the median star's
speed, not the nearest layer's. The drift is ambient, not physical:
parallaxing it against the camera would be the "honest" alternative and looks
terrible, because the simulation's zoom spans orders of magnitude and the stars
would either sit motionless or tear across the screen. They do not twinkle
either — there is no atmosphere out here to make them.

Drawing them live rather than baking them into the cached backdrop costs
0.04 ms a frame, but only because the rectangles are snapped to whole device
pixels. Fractional coordinates force Core Graphics into an antialiased
rasterisation that measures **forty times slower** — 1.67 ms against 0.04 ms for
three hundred stars, which was very nearly enough to sink the whole idea.

## How scenes end

Most simply run out their clock and cross-fade. Two endings are the system
actually resolving itself, and both are marked before the lights go down:

- **Ejection** (~25% of scenes in *Both* mode). A body is unbound from the remaining pair,
  receding, and more than twelve binary separations away — held for three and a
  half seconds before it counts, so a long excursion isn't mistaken for an
  escape. The camera stops chasing the departing body from the moment the escape
  is *detected*, so it has settled on the surviving binary by the time the
  send-off plays; a slow ring then spreads from the pair as it lets go.
- **Collision** (~4% of scenes in *Both* mode). Two bodies touch and merge: a white impact
  flash, then two shockwave rings at different speeds, in the blended colours of
  the bodies that made it. The readout gives the kinetic energy shed as a
  multiple of the scene's own energy.

Catching contact also fixed an accuracy problem. The deepest encounters used to
drive the relative energy error as high as 2.5e-3 before the scene was retired
for numerical trouble; merging resolves them instead, and the worst drift over a
90-minute run is now 1.1e-5.

## Verifying it

`./build.sh test` runs the harness in `Tests/main.swift`, which takes a few
seconds and measures rather than assumes:

- composition weights sum to 1 and are palindromic (time-symmetric);
- convergence order measured against a reference solution — 2.00, 3.99, 5.98 and
  8.03 against the nominal 2, 4, 6, 8;
- error per force evaluation for each order, so the accuracy tiers can be chosen
  on evidence;
- bounded energy error over 32 periods of the figure-eight, and conservation of
  linear and angular momentum;
- adaptive stepping driven through Burrau's near-collisions at every accuracy
  tier;
- every catalogued periodic orbit actually closing after its stated period;
- the Lagrange triangle holding to 1e-12 over two revolutions *and* breaking up
  by twelve, as its instability requires;
- inelastic merges conserving mass and momentum, shedding exactly the pair's
  internal angular momentum μ·(r×v), and reporting exactly the kinetic energy
  they actually lose;
- every catalogued orbit staying clear of the contact radius for a whole scene;
- flyby intruders genuinely starting unbound and inbound.

## Layout

```
Sources/ThreeBodyCore/    physics, scenarios, camera, units — Foundation only
Sources/ThreeBodyRender/  Core Graphics renderer, settings, options sheet
Sources/ThreeBodySaver/   the ScreenSaverView subclass
Sources/ThreeBodyApp/     standalone window, and the thumbnail renderer
Tests/ThreeBodyCoreTests/ the physics measurements
Scripts/                  build, sign, install, package, verify
```

`ThreeBodyCore` imports nothing but Foundation. That is what lets the physics be
measured headlessly, and it is enforced by the module boundary rather than by
good intentions.

## References

- Yoshida, H. (1990). *Construction of higher order symplectic integrators.*
  Physics Letters A 150.
- Suzuki, M. (1990). *Fractal decomposition of exponential operators.*
  Physics Letters A 146.
- Hut, P., Makino, J. & McMillan, S. (1995). *Building a better leapfrog.*
  ApJ 443, L93.
- Chenciner, A. & Montgomery, R. (2000). *A remarkable periodic solution of the
  three-body problem in the case of equal masses.* Annals of Mathematics 152.
- Šuvakov, M. & Dmitrašinović, V. (2013). *Three classes of Newtonian three-body
  planar periodic orbits.* Physical Review Letters 110, 114301.
- Long, K. *ThreeBodyBot* — https://github.com/kirklong/ThreeBodyBot. Source of
  the centre-of-mass framing trick, the decaying-offset camera, and the practice
  of vetting random initial conditions before showing them.
- Szebehely, V. & Peters, C. F. (1967). *Complete solution of a general problem
  of three bodies.* Astronomical Journal 72 (Burrau's problem).
