---
phase: 08-aura-scan-and-cancellation
plan: 01
subsystem: buff-engine
tags: [lua, unit-aura, timer-cancellation, aura-scan, wow-addon]

# Dependency graph
requires:
  - phase: 07-safety-infrastructure
    provides: OnUnitAura guard chain (ShouldAurasBeSecret, isFullUpdate, previewActive), auraCheckBlocked flag, ns.debugLogging, ClearAuraBlock
provides:
  - ScanActiveTimersForCancellation function that queries C_UnitAuras.GetPlayerAuraBySpellID and nils absent cast-originated timers
  - source="cast" origin marker on all cast-originated timers enabling future Phase 10 lust timers to coexist safely
  - Active timer auto-cancellation when underlying buff falls off early (dispel, manual cancel, wipe)
affects: [09-display-cleanup, 10-lust-timer, future phases reading timer.source]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "source marker pattern: timer.source = 'cast' filters cast-originated timers from preview/future timers"
    - "zero-allocation scan: cancelledCount is a plain integer; cancelledLabels only allocated when debugLogging is true AND a cancel occurs"
    - "batch-then-display: all removals in one pairs pass, single UpdateDisplay call at end"

key-files:
  created: []
  modified:
    - BuffEngine.lua

key-decisions:
  - "source = cast marker on cast-originated timers ensures Phase 10 lust timers (source = debuff) are not touched by the UNIT_AURA scan"
  - "No grace period on cancellation — GetPlayerAuraBySpellID returning nil means the buff is absent, cancel immediately (D-05 locked)"
  - "cancelledLabels table only allocated when debugLogging is true to avoid GC pressure in hot path (D-03)"
  - "Single UpdateDisplay call after batch removal pass — not per-removal (D-02)"

patterns-established:
  - "source filter pattern: timer.source == 'cast' uses Lua nil-safety (nil ~= 'cast') to skip timers without the field"
  - "batch-cancel pattern: iterate pairs, nil entries, count removals, call UpdateDisplay once at end"

requirements-completed:
  - AURA-04

# Metrics
duration: 15min
completed: 2026-04-04
---

# Phase 8 Plan 01: Aura Scan and Cancellation Summary

**Aura scan function that auto-cancels cast-originated timers when GetPlayerAuraBySpellID returns nil, with zero-allocation hot path and single batched UpdateDisplay call**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-04T04:59:52Z
- **Completed:** 2026-04-04T05:15:00Z
- **Tasks:** 2 of 2
- **Files modified:** 1

## Accomplishments
- Added `source = "cast"` origin marker to cast-originated timers in `OnSpellCastSucceeded`
- Implemented `ns:ScanActiveTimersForCancellation()` with zero-allocation hot path, batch removals, and single summary debug line
- Replaced Phase 8 placeholder stub in `OnUnitAura` with actual scan call
- Deployed to WoW via `scripts/install.bat` for in-game verification

## Task Commits

Each task was committed atomically:

1. **Task 1: Add source marker and implement ScanActiveTimersForCancellation** - `d195a97` (feat)
2. **Task 2: In-game verification checkpoint** - Approved by user. Timer auto-cancellation confirmed working in-game.

## Files Created/Modified
- `BuffEngine.lua` - Added source marker to cast timers, added ScanActiveTimersForCancellation function, replaced Phase 8 placeholder with scan call

## Decisions Made
- Followed all locked decisions D-01 through D-05 from CONTEXT.md without deviation
- `cancelledLabels` table uses lazy allocation pattern (only created when `ns.debugLogging` is true AND at least one timer is cancelled) to avoid GC pressure

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

The worktree `agent-a3a6168d` was on `main` branch which lacked Phase 7 changes. Implementation was correctly performed in the main worktree at `/c/Users/jonat/Repositories/TerribleBuffTracker` on branch `v0.2.1-aura-cancellation` which had the Phase 7 guard chain infrastructure.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Task 2 (checkpoint:human-verify) requires in-game verification: enable `/tbt debug`, cast a tracked buff, right-click to cancel, confirm timer disappears and single debug line appears in chat
- After verification, phase 08 is complete and phase 09 can begin
- Phase 7 guard chain is intact — ShouldAurasBeSecret, isFullUpdate, previewActive guards unchanged

## Known Stubs

None — `ScanActiveTimersForCancellation` is fully wired to `OnUnitAura`. The scan calls `C_UnitAuras.GetPlayerAuraBySpellID` with real data and removes timers. No placeholder behavior remains.

## Self-Check: PASSED

- Commit d195a97 verified in git log
- 08-01-SUMMARY.md exists at .planning/phases/08-aura-scan-and-cancellation/
- Task 2 checkpoint verified as approved by user

---
*Phase: 08-aura-scan-and-cancellation*
*Completed: 2026-04-04*
