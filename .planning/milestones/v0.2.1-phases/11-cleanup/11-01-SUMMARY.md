---
phase: 11-cleanup
plan: 01
subsystem: ui
tags: [lua, wow-addon, refactor, cleanup, buff-engine]

# Dependency graph
requires:
  - phase: 10-lust-tracking
    provides: SUGGESTED_BUFFS table with string key meta-buff pattern, lust timer with string spellID keys
provides:
  - ns:ResolveSuggestedSpellID(key) shared helper in BuffEngine.lua
  - Preview save/restore using savedPreviewTimers (D-07 fix)
  - All inline SUGGESTED_BUFFS loops replaced with single helper calls
  - ns.tbtTabActive dead code removed
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ns:ResolveSuggestedSpellID(key) — DRY helper for resolving string meta-buff key to numeric CDM spellID"
    - "wipe(savedPreviewTimers) save/restore pattern — module-level table, never reassigned, preserves real timers across preview"

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - CDMTab.lua
    - Display.lua

key-decisions:
  - "ResolveSuggestedSpellID returns only spellID (not label) — call sites that need a label use C_Spell.GetSpellInfo independently"
  - "savedPreviewTimers is module-local (not ns.*) — internal to preview state machine in BuffEngine.lua"
  - "StartAllPreviewTimers re-entry guard (not ns.previewActive) prevents mid-preview save from overwriting real savedPreviewTimers"

patterns-established:
  - "Single helper eliminates 10 inline SUGGESTED_BUFFS iteration loops across 3 files"

requirements-completed: []

# Metrics
duration: 20min
completed: 2026-04-04
---

# Phase 11 Plan 01: Cleanup — DRY Refactor and Preview Fix Summary

**Extracted ns:ResolveSuggestedSpellID helper from 10 duplicate loops, fixed preview overwriting active timers (D-07), removed ns.tbtTabActive dead code**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-04-04T19:17:00Z
- **Completed:** 2026-04-04T19:37:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added `ns:ResolveSuggestedSpellID(key)` helper to BuffEngine.lua — single source of truth for string key→spellID resolution
- Replaced all 10 inline `for _, suggested in ipairs(ns.SUGGESTED_BUFFS)` loops across 3 files with the new helper
- Fixed D-07 bug: `StartAllPreviewTimers` no longer destroys in-flight timers when CDM settings is opened; `ClearAllTimers` restores real timers on close
- Removed `ns.tbtTabActive = true/false` dead code from `ShowTBTPanel`/`HideTBTPanel`
- Deployed to WoW addons folder via `scripts/install.bat`

## Task Commits

1. **Task 1: Extract ResolveSuggestedSpellID helper and fix preview save/restore** - `c64c3d7` (feat)
2. **Task 2: Replace inline loops in CDMTab.lua and Display.lua, remove dead code, deploy** - `39dcd36` (refactor)

## Files Created/Modified
- `BuffEngine.lua` — Added `ns:ResolveSuggestedSpellID`, module-level `savedPreviewTimers`, rewrote `StartAllPreviewTimers` and `ClearAllTimers`
- `CDMTab.lua` — Replaced 3 pure spellID-resolution loops with helper calls; removed `ns.tbtTabActive` assignments
- `Display.lua` — Replaced all 4 inline loops with helper calls

## Decisions Made
- `ResolveSuggestedSpellID` returns only spellID (not label) — keeps helper single-purpose; callers needing a label call `C_Spell.GetSpellInfo` independently
- `savedPreviewTimers` declared as `local` (not `ns.*`) — only needed within BuffEngine.lua preview state machine
- Re-entry guard on `StartAllPreviewTimers` (`not ns.previewActive`) prevents mid-preview refreshes from overwriting the original real timers with preview-mixed state

## Deviations from Plan

None — plan executed exactly as written. The plan correctly identified which loops to replace (pure spellID-only resolution) and which to preserve (multi-field loops reading label/duration/metaBuff).

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- Phase 11-02 (CHANGELOG and release prep) is unblocked
- All modified files pass `stylua --check`
- Addon deployed to WoW for in-game smoke testing of D-07 fix

---
*Phase: 11-cleanup*
*Completed: 2026-04-04*
