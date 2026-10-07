---
title: Challenge a Rule When It Is in the Way
impact: CRITICAL
impactDescription: The rules serve the best system; a rule that blocks a better one is a defect to raise, not a wall to work around
tags: [workflow, rules, architecture, standards, judgement]
---

## Challenge a Rule When It Is in the Way

**Impact: CRITICAL**

These rules exist to make the best system, not to be obeyed for their own
sake. When following one would make the code, the architecture, a standard
or the product worse — or when a better way exists that a rule forbids —
raise it with the user, plainly: which rule, what it costs here, what the
alternative is, and what it would take. Then wait. Sometimes the answer is to
rearchitect, change a standard, or rewrite the rule.

Silent compliance and silent breaking both hide the decision, so do neither.
A rule the user has just confirmed stands.

**Incorrect (working around it in silence):**

```
GargantuaCore can't link QuartzCore, so I read the time with Date() inside
DiskEvents instead of CACurrentMediaTime.
```

**Correct (the case made, the decision left with the user):**

```
The Core-has-no-UI-frameworks rule is in the way of the flare timing, which
wants CACurrentMediaTime from QuartzCore. Two ways round it: hand the time in
from GargantuaRender as a Double, which keeps the rule and lets the tests drive
the clock, or let GargantuaCore link QuartzCore. Want the first, or relax the
rule?
```
