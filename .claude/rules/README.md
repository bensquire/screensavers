---
title: Screensavers Rules Index
impact: LOW
impactDescription: About the rules themselves; loads only when a rule is being written
tags: [meta, rules]
paths: [".claude/rules/*.md"]
---

# Screensavers Rules

Modular, machine-readable rules for working on the screensavers. Each file is
one rule, named `{section}-{rule-name}.md`, with YAML frontmatter Claude Code
reads: a rule with `paths` loads only when a matching file is in play; one
without applies always. `_sections.md` defines the sections and their order;
`_template.md` is the shape of a new rule. How to build, verify, test and
release is the `build` skill.

## Rules Index

### Workflow

- [workflow-challenge-the-rules](workflow-challenge-the-rules.md) - A rule in the way is raised with the user, not obeyed or broken in silence
- [workflow-no-commits-unless-told](workflow-no-commits-unless-told.md) - Never commit, push or tag unless told to
- [workflow-hand-over-for-trial](workflow-hand-over-for-trial.md) - Verify, install, point at System Settings, stop
- [workflow-checking-work](workflow-checking-work.md) - Lint, the whole suite, then load and draw the built saver
- [workflow-commit-messages](workflow-commit-messages.md) - Prose, with the measurements
- [workflow-diagnostics](workflow-diagnostics.md) - A flag on the standalone app or `os_log` to keep, a separate file to throw away

### Quality

- [quality-separation-of-concerns](quality-separation-of-concerns.md) - Core, Render, Saver, App; the Core links no UI or GPU framework
- [quality-dependency-injection](quality-dependency-injection.md) - Preferences, notification centres, seeds and clocks handed in
- [quality-readability](quality-readability.md) - Code reads like the prose around it
- [quality-consistency](quality-consistency.md) - Reuse SaverCore and SaverKit before writing a second spelling
- [quality-extensible](quality-extensible.md) - A new saver is a directory; a new mode is a case
- [quality-performant](quality-performant.md) - The duty cycle is the budget, measured with `make bench`
- [quality-secure](quality-secure.md) - Offline, preferences clamped, releases signed and notarised
- [quality-comments-carry-measurements](quality-comments-carry-measurements.md) - Short, says why, carries the number; never restates a name
- [quality-formatting-is-the-tools](quality-formatting-is-the-tools.md) - swift-format and `.swift-format` decide
- [quality-images-minified](quality-images-minified.md) - Docs images and tiles, lossless first, judged at 1:1

### Testing

- [testing-arrange-act-assert](testing-arrange-act-assert.md) - Each step present, in order
- [testing-one-behaviour-per-test](testing-one-behaviour-per-test.md) - One behaviour, named as a sentence, with the failure it guards against
- [testing-ground-truth-with-teeth](testing-ground-truth-with-teeth.md) - Published ephemerides, measured slopes, the shader's own layout, the drawn frame
- [testing-deterministic](testing-deterministic.md) - Seeded, committed, local notification centres, a skip without a GPU
- [testing-fast](testing-fast.md) - Release mode and the unit, never by seeing less
- [testing-failure-reads-as-a-sentence](testing-failure-reads-as-a-sentence.md) - A message where the expression alone doesn't tell the story

### Native

- [native-use-the-systems-feature](native-use-the-systems-feature.md) - The host's timer, the system's sheet, ScreenSaverDefaults, the energy signals
- [native-small-bundle](native-small-bundle.md) - Under 1.2 MB each, system frameworks only
- [native-check-apples-documentation](native-check-apples-documentation.md) - Look it up in `scrapple` before using, copying or asserting

### Communication

- [communication-plain-language](communication-plain-language.md) - ISO 24495-1: relevant, findable, understandable, usable
