---
phase: 21-preview-mode-migration
plan: 01
subsystem: BuffEngine
tags: [preview, timers, refactor, bug-fix]
dependency_graph:
  requires: [20-01]
  provides: [additive-preview-lifecycle]
  affects: [Display.lua (consumer of GetActiveTimers), CDMTab.lua (StartPreview/StopPreview lifecycle)]
tech_stack:
  added: []
  patterns: [separate-table-identity, real-priority-merge, lazy-expiry-cleanup]
key_files:
  created: []
  modified:
    - BuffEngine.lua
    - CDMTab.lua
decisions:
  - "D-01/D-02/D-03: ns.previewTimers is separate from ns.activeTimers; table identity replaces flag/source field"
  - "D-05/D-06: real-priority merge — real proc wins same-key in GetActiveTimers; also enforced at StartAllPreviewTimers insertion time"
  - "D-07/D-08/D-09: StartAllPreviewTimers uses ns:GetDisplayInfoForKey as sole data source — provider owns all field resolution"
  - "D-11/D-12: ClearAllTimers wipes ns.previewTimers only; ns.activeTimers untouched — eliminates mid-CDM cast-loss bug"
  - "D-13/D-14: savedPreviewTimers local and ns.previewActive flag fully deleted; CDMTab disjuncts collapsed to ns.configOpen"
  - "D-15/D-19/D-20: OnUnitAura preview guard removed; ScanActiveTimersForCancellation unchanged — preview procs invisible by construction"
metrics:
  duration_minutes: 10
  completed_date: "2026-04-21"
  tasks_completed: 6
  tasks_total: 6
  files_modified: 2
---

# Phase 21 Plan 01: Additive Preview Lifecycle Migration Summary

**One-liner:** Additive preview using separate ns.previewTimers table with real-priority merge in GetActiveTimers — eliminates trinket/pot 0-second preview bug (LIFE-03) and mid-CDM cast-loss bug.

## What Was Built

Rewrote BuffEngine.lua's preview lifecycle from the old snapshot/restore wipe-and-replace pattern to an additive-preview pattern. Preview procs now live in `ns.previewTimers`; real procs remain in `ns.activeTimers`. `ns:GetActiveTimers` merges both tables with real-priority. Three CDMTab.lua disjuncts collapsed after deleting the now-obsolete `ns.previewActive` flag.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add ns.previewTimers; delete savedPreviewTimers and ns.previewActive | df68327 | BuffEngine.lua |
| 2 | Rewrite StartAllPreviewTimers as additive (D-09 verbatim) | fb9bded | BuffEngine.lua |
| 3 | Rewrite ClearAllTimers as preview-scoped wipe (D-11 verbatim) | 3a796cb | BuffEngine.lua |
| 4 | Rewrite GetActiveTimers with merge + real-priority (D-17 verbatim) | 8036574 | BuffEngine.lua |
| 5 | Delete ns.previewActive guard from OnUnitAura (D-15) | fa01ee9 | BuffEngine.lua |
| 6 | Collapse 3 CDMTab.lua previewActive disjuncts to ns.configOpen | a62150b | CDMTab.lua |

## Architecture Change

**Before (snapshot/restore):**
- StartAllPreviewTimers saved real timers to `savedPreviewTimers`, wiped `ns.activeTimers`, wrote preview procs into `ns.activeTimers`
- ClearAllTimers restored from `savedPreviewTimers` back into `ns.activeTimers`
- Bug: any real cast mid-preview was lost on CDM close (snapshotted at open time)
- Bug: trinket/pot preview showed 0-second duration (entry.duration was the 0-sentinel)

**After (additive-preview):**
- `ns.previewTimers` holds preview procs exclusively (no source field)
- `ns.activeTimers` holds real procs exclusively (source="cast" or "debuff")
- `ns:GetActiveTimers` merges both with real-priority per key
- `ns:ClearAllTimers` wipes only `ns.previewTimers`; real procs continue naturally
- `ns:StartAllPreviewTimers` skips keys with a live real proc; sources all data from `ns:GetDisplayInfoForKey(key)` — durations are now real (LIFE-03 fixed)

## Deviations from Plan

None — plan executed exactly as written. All 6 tasks completed per the verbatim D-09, D-11, D-17 implementations. The three CDMTab.lua comment references to `ns.previewActive` in Providers.lua (historical comments at lines 447-448) were correctly identified as acceptable — they are comments, not code reads.

## Known Stubs

None. All data paths are wired. `ns:GetDisplayInfoForKey(key)` returns real durations (>0) for all four providers post-Phase 20. Preview bars will display correct durations in-game. Human verification is deferred to Plan 21-02.

## Self-Check

### Files verified exist
- BuffEngine.lua: FOUND
- CDMTab.lua: FOUND
- .planning/phases/21-preview-mode-migration/21-01-SUMMARY.md: this file

### Commits verified
- df68327: Task 1 - FOUND
- fb9bded: Task 2 - FOUND
- 3a796cb: Task 3 - FOUND
- 8036574: Task 4 - FOUND
- fa01ee9: Task 5 - FOUND
- a62150b: Task 6 - FOUND

### Structural invariants
- `grep -c "ns.previewTimers = {}" BuffEngine.lua` = 1 (PASS)
- `grep -c "ns.previewActive" BuffEngine.lua` = 0 (PASS)
- `grep -c "savedPreviewTimers" BuffEngine.lua` = 0 (PASS)
- `grep -c "wipe(ns.previewTimers)" BuffEngine.lua` = 2 (PASS)
- `grep -c "ns.previewActive" CDMTab.lua` = 0 (PASS)
- `grep -c "if ns.configOpen then" CDMTab.lua` = 3 (PASS)
- `grep -c "ns:StartAllPreviewTimers()" CDMTab.lua` = 5 (PASS)
- Providers.lua, Core.lua, Display.lua: git status clean (PASS)
- `stylua --check BuffEngine.lua CDMTab.lua` = 0 (PASS)

## Self-Check: PASSED
