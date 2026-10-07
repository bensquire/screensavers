---
title: Check Apple's Documentation Before Using Its API
impact: HIGH
impactDescription: A guessed lifecycle call compiles and quietly never runs; an asserted platform fact goes unchecked
tags: [native, documentation, scrapple, apple, screensaver, wwdc]
paths: ["Sources/**/*.swift", "Scripts/**", "savers/**"]
---

## Check Apple's Documentation Before Using Its API

**Impact: HIGH**

Before using a system API you are not certain of, before building anything the
system might already provide, and before stating a platform fact in a comment,
look it up. `scrapple` holds Apple's framework documentation, WWDC transcripts
and sample code offline; the `apple-docs` skill says how to ask it. A symbol
name is the best query. This matters most around the ScreenSaver framework
(`ScreenSaverView`'s lifecycle, `ScreenSaverDefaults`), `CAMetalLayer` and
Metal, SceneKit's offscreen rendering, and code signing.

Some of what matters here is in no document: how the `legacyScreenSaver` host
manages a saver's lifecycle, and how System Settings binds the Options button.
`NOTES.md` records what was measured about both; a claim about either cites
that, or a fresh measurement.

A decision that rests on what a page says carries the page's path in a
one-line comment, so the next reader can check it too. A doc that contradicts a
rule here is raised with the user, not followed or ignored in silence.

**Incorrect (a platform fact, asserted without a source):**

```swift
// The host calls stopAnimation() when the screensaver is dismissed.
```

**Correct (looked up, measured where the docs are silent, and cited):**

```sh
scrapple search "animationTimeInterval" --type doc --limit 3 --human
```

```swift
// The host's timer follows animationTimeInterval, even mid-animation
// (/documentation/screensaver/screensaverview/animationtimeinterval). It does
// not call stopAnimation() at session end — measured on 26.6, see NOTES.md.
```

Reference: `scrapple` (github.com/searlsco/scrapple); Apple Developer Documentation.
