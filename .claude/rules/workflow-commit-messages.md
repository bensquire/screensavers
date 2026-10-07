---
title: Commit Messages Are Prose With the Measurements
impact: HIGH
impactDescription: The history is where the reasoning is kept
tags: [workflow, git, commits, history]
---

## Commit Messages Are Prose With the Measurements

**Impact: HIGH**

When told to commit, the message says what changed and why, in prose, with the
measurements that justified it — the saver and display, the figure before, the
figure after — and what was tried and taken out, if anything was. The subject
says what the change does for the saver, in a sentence. One commit per change
of meaning: work that was already in the tree and is not part of the change
goes in its own commit, described honestly. End with the attribution lines the
session prescribes.

**Incorrect:**

```
Fix stars and cleanup
```

**Correct:**

```
Wrap the Solar System's stars one at a time, so the sky never resets

The star field was three copies of one slab, moved as a whole and snapped back
by a slab length every couple of minutes; at its far end a whole slab of stars
popped in and out at once. Now each star wraps on its own in a geometry shader
modifier, fading over the last fifth of the way to the face.

StarFieldTests checks sixty points across the period for a step that changes
the frame more than a hundredth of a quarter-period's travel. Run against the
old field it fails at exactly the three points where it snapped, by 86 times
the threshold.
```
