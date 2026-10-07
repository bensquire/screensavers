---
title: A Comment Is Short, and Says Why
impact: HIGH
impactDescription: A comment costs every reader time and every token money; it earns that or it goes
tags: [quality, comments, documentation, measurements, brevity]
paths: ["Sources/**/*.swift", "Tests/**/*.swift", "Scripts/**"]
---

## A Comment Is Short, and Says Why

**Impact: HIGH**

A comment adds what the code cannot say — why this, what was measured, what
was rejected — in as few plain words as will still read. It never restates a
method or property name. A claim carries its measurement: the saver, the
display, before, after. A constant carries the measurement or the reason that
set it. A platform fact carries the doc path it came from, or says it was
measured here. No flourish, no anecdote told twice, no comment about code that
has gone.

The same goes for a test's doc comment, which in this repository says what
failure the test guards against.

**Incorrect (restates the name; no reason; no number):**

```swift
/// The maximum backing scale.
public static let maximumBackingScale: CGFloat = 2
```

**Correct (the why, then stop):**

```swift
/// Beyond 2x the extra pixels cost real time and buy nothing a screensaver's
/// viewer will lean in to see — and for a saver that adapts its resolution
/// to hold a frame rate, the pixels would only be handed straight back.
public static let maximumBackingScale: CGFloat = 2
```
