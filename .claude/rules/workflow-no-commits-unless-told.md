---
title: Never Commit or Push Unless Told To
impact: CRITICAL
impactDescription: A committed feature the user did not want costs a revert and trust; a pushed tag publishes a release
tags: [workflow, git, commits, tags, handover]
---

## Never Commit or Push Unless Told To

**Impact: CRITICAL**

Commit, push or tag only when the user has said to in this conversation.
"Make it work", "fix it" and "finish it" are not that instruction. "Commit",
"commit and push", or a reply that says the work stays, are. When told to
commit on `main`, branch first and say so.

The user tries a saver before deciding whether a change stays. A working
change is not the same as a wanted one, and only they can tell the difference.

A tag is a push with consequences of its own: pushing `<saver>-v<version>`
runs `release.yml`, which signs, notarises and publishes that saver as a
GitHub Release. Creating or pushing one waits for the same instruction, and
then follows the release steps in the `build` skill.

This is about product decisions, not about editing: change files without
asking permission.

**Incorrect (committing because the work is done):**

```
Tests pass and all four savers verify, so I've committed and pushed.
```

**Correct (handing over and waiting):**

```
Tests pass and all four savers verify. Gargantua is installed — pick it in
System Settings › Screen Saver and press Preview. Nothing is committed; say if
it stays.
```
