---
title: Rule Sections
impact: LOW
impactDescription: About the rules themselves; loads only when a rule is being written
tags: [meta, rules]
paths: [".claude/rules/*.md"]
---

# Sections

This file defines all sections, their ordering, impact levels, and descriptions.
The section ID (in parentheses) is the filename prefix used to group rules.

---

## 1. Workflow (workflow)

**Impact:** CRITICAL
**Description:** How work is checked, handed over and committed, and how a rule
that is in the way gets challenged. The rules that decide whether anything else
matters.

## 2. Quality (quality)

**Impact:** HIGH
**Description:** How the Swift is written: separation of concerns, dependency
injection, readability, consistency, extensibility, performance, security,
comments that add value, formatting left to the tool, and images kept small.

## 3. Testing (testing)

**Impact:** HIGH
**Description:** What a test is for and what keeps the suite worth running:
shape, scope, determinism, speed, and ground truth from a published source or a
measured property rather than from the code's own output.

## 4. Native (native)

**Impact:** HIGH
**Description:** The savers behave like part of macOS, by using what the
ScreenSaver framework and the system provide — and stay small because of it.

## 5. Communication (communication)

**Impact:** MEDIUM
**Description:** How messages to the user are written.
