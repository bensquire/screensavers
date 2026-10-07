---
title: Hand Work Over for the User to Try
impact: CRITICAL
impactDescription: The user judges a screensaver on their own screen, not in a report
tags: [workflow, handover, install, system-settings]
---

## Hand Work Over for the User to Try

**Impact: CRITICAL**

When a change the user can see is done and checked, put it on their screen.
A change to the tests, the scripts, the rules or the docs is handed over as
what it is: the command to run, the suite's result, the file to read.

1. `make verify SAVER=<name>`, so the bundle being handed over is one the host
   can load and draw.
2. `make install SAVER=<name>`. It quits System Settings and the screensaver
   host processes so the new bundle replaces the old one, then installs to
   `~/Library/Screen Savers/`. Say that System Settings was closed.
3. Point the user at it: System Settings › Screen Saver, the saver's name,
   Preview. The Options button works only for the first saver selected after
   System Settings opens, so for a change to the options, say to quit System
   Settings and reopen it with that saver selected first. The saver's settings
   persist across installs (`SaverPreferences`), so say which the trial
   assumes; Solar System's scale preset can be set with `Scripts/scale-mode.sh`.
   For a change to how a scene looks or moves, the standalone app is quicker to
   watch: `swift build -c release --product <Name>App && .build/release/<Name>App`.
4. Say what to look at and what the figures were.
5. Stop.

**Incorrect (declaring done from the command line):**

```
The suite passes and check.png has the new lightning. Done.
```

**Correct (installed, the eye pointed):**

```
Installed Sliders Vortex (System Settings was closed to load it). Pick it in
System Settings › Screen Saver and press Preview: the lightning should now
reach the far end of the tunnel. GPU cost is 1.12 ms of the 33 ms frame at
2560x1600, as before.
```
