---
title: Rule Title Here
impact: MEDIUM
impactDescription: Optional description of the impact
tags: [tag1, tag2]
paths: [".claude/rules/*.md"]
---

## Rule Title Here

**Impact: MEDIUM (optional impact description)**

Brief explanation of the rule and why it matters, with the measurement or the
incident that set it where the rule has one.

**Incorrect (description of what is wrong):**

```swift
// Bad example here
```

**Correct (description of what is right):**

```swift
// Good example here
```

Reference: where this came from, if anywhere.

Notes on the frontmatter: `paths` is read by Claude Code and scopes the rule to
files matching the globs; leave it out for a rule that always applies. Arrays are
written inline, `[like, this]`. The source directories here are `Sources/`
(one `Core`, `Render`, `Saver` and `App` module per saver, plus `SaverCore` and
`SaverKit`), `Tests/`, `Scripts/` and `savers/`.
