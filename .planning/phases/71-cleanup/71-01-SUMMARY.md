---
phase: 71-cleanup
plan: 01
subsystem: cleanup
tags: [cleanup, dead-code, dedup, hot-path-review]
requires: []
provides:
  - 71-AUDIT.md findings and hot-path review
affects: [BuffEngine.lua, Display.lua, MergeMode.lua, MergeReanchor.lua]
key-files:
  created: [.planning/phases/71-cleanup/71-AUDIT.md]
  modified: [BuffEngine.lua, Display.lua, MergeMode.lua, MergeReanchor.lua]
decisions:
  - ns.SPELL_CATEGORY_COMBAT_POTION and ns.POT_SPELLS kept (reader in Providers.lua; export predates the milestone)
metrics:
  completed: 2026-10-10
---

# Phase 71 Plan 01: Cleanup Summary

Removed the dead `ns:EndTimer`, fixed three stale comments, and unified the two pieces of duplication this milestone introduced (`ForgetID` in MergeReanchor.lua, `CollectFrameCooldownIDs` in MergeMode.lua), with a written audit and hot-path review. No behaviour change.

## Commits
- f87ccdb: docs(71-01) audit with findings and hot-path review
- 2958d4a: chore(71-01) remove ns:EndTimer, fix stale comments
- (Task 3) refactor(71-01) ForgetID and CollectFrameCooldownIDs; see `git log`

## Findings and outcomes
1. `ns:EndTimer`: removed (grep count 1 = definition; callers deleted in Phase 67).
2. Display.lua D2 comment: reworded.
3. MergeMode.lua header: now names the viewer block and MergeReanchor.lua as the two CDM-frame writers.
4. Per-id forget: unified in `ForgetID`, declared above both callers.
5. `CollectShownCooldownIDs`/`CollectVisibleCooldownIDs`: unified in `CollectFrameCooldownIDs(viewer, into, readVisible)`.
Kept: `ns.SPELL_CATEGORY_COMBAT_POTION`, `ns.POT_SPELLS`, `ResolveItemIdentity` extra returns. The fresh sweep of 241 ns names found nothing else milestone-introduced.

## Gate results
All Task 2 and Task 3 grep gates pass; line-order gates pass; added non-comment lines containing frame calls: 0; `stylua --check .` pass; aura-read-gate PASS (1 read), selftest PASS (30); migrate-dryrun selftest PASS (14); touched .lua files `w/crlf`, no `Bin` in diff stat; CHANGELOG.md, README.md, TOC untouched.

## Deviations from Plan
Amendments applied: Task 3 frame-call gate excludes comment lines; the D2 reword keeps the "Wiping and reusing" line start and moves "the engine still owns." to its own line. Otherwise none.

## Phase 72 in-game checks (deferred)
Merge Mode on and off; a CDM reorder; Edit Mode preview of a merged entry whose frame is hidden; merged buffs still appear and disappear.

## Self-Check: PASSED
