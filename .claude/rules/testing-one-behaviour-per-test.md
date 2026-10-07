---
title: One Behaviour Per Test, Named as a Sentence
impact: HIGH
impactDescription: A test of several things fails for one and hides the rest
tags: [testing, naming, scope, xctest]
paths: ["Tests/**/*.swift"]
---

## One Behaviour Per Test, Named as a Sentence

**Impact: HIGH**

A test pins one behaviour, and its name says which, as an XCTest
`test…` method that reads as a sentence in the report:
`testSessionEndLeavesThePreviewAlone`,
`testTheBuildCompilesTheShaderTheLoaderLooksFor`,
`testSwiftAndMetalAgreeOnBufferLayout`,
`testHeliocentricPositionsMatchHorizons`. A name with "and" in it that lists
unrelated checks is usually two tests; one with "and" that describes a single
observable outcome is fine. Above the test, a `///` comment says what failure
it guards against — the case that would otherwise go unnoticed — as the
existing tests do.

When the same behaviour is asked of several inputs, loop over a table inside
one test, with the input in every message (the eight planets against Horizons,
every `IntegratorOrder`), rather than copy the test.

Test the behaviour, not the implementation: what the frame shows, the measured
convergence slope, what the lifecycle did to the view — not which private
function ran. `@testable` is for reaching a real internal seam, such as
`ShaderLibrary.compileFromSource` or `SceneUniforms`, not for asserting on
scaffolding.

**Incorrect:**

```swift
func testVortex() {
    // checks the settings, the shader, the buffer layout and a frame in one go
}
```

**Correct:**

```swift
/// A mismatch between what the build writes and what ShaderLibrary looks
/// for would leave the built saver drawing nothing, while every other test passed.
func testTheBuildCompilesTheShaderTheLoaderLooksFor() throws { … }
func testSwiftAndMetalAgreeOnBufferLayout() throws { … }
```
