---
status: partial
phase: 62-new-icons
source: [62-VERIFICATION.md]
started: 2026-09-30
updated: 2026-09-30
---

## Current Test

[awaiting human testing — deferred to Phase 66, the milestone's single human testing pass (user decision at kickoff)]

## Tests

### 1. The CDM tabs and the dialog side tabs draw the new icons (TAB-08, TAB-09)
expected: After a FULL client restart (new files on disk are not seen by /reload): the TBT Cooldowns / Buffs / Reminders tabs in the CDM settings window show the stopwatch, bolt and bell icons; the tracker dialog's General / Advanced side tabs show the book and gear icons. Normal, selected and hover states all draw; no green/missing-texture square. The addon-list icon and the /tbt settings panel logo are unchanged.
result: pass — user-tested 2026-09-30 (faction-themed set)

### 2. The first real release zip carries Media/Textures and not Media/Source (DIST-13)
expected: At the v0.5.1 release, the packaged zip contains `TerribleBuffTracker/Media/Textures/*.blp` (10 files: the `_ally` / `_horde` pairs, TAB-10) and no `Media/Source`. Checked statically from `.pkgmeta` only; the packager was not run locally.
result: [pending]

## Summary

total: 2
passed: 1
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
