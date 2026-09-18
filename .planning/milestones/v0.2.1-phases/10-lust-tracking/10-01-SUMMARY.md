---
phase: 10-lust-tracking
plan: 01
subsystem: buff-engine
tags: [lua, wow-addon, lust, heroism, aura-detection, schema-migration]

# Dependency graph
requires:
  - phase: 08-aura-scan-and-cancellation
    provides: source="cast" marker on timers and ScanActiveTimersForCancellation that skips non-cast sources
provides:
  - ns.SATED_DEBUFF_TO_LUST mapping 4 Sated-family debuff IDs to lust spell IDs
  - ns.CLASS_LUST_SPELL mapping player class to class-specific lust spell
  - ns.SUGGESTED_BUFFS registry with lust meta-buff entry and getCDMSpellID
  - Schema v3 migration seeding trackedBuffs["lust"] with metaBuff=true
  - ns:StartLustTimer creating timer with source="debuff" and actual lust spell icon
  - Sated-family debuff detection in OnUnitAura via addedAuras with issecretvalue guard
affects: [10-02-plan, 11-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - issecretvalue per-entry guard before SATED_DEBUFF_TO_LUST table index in addedAuras loop
    - source="debuff" marker prevents ScanActiveTimersForCancellation from cancelling lust timers
    - SUGGESTED_BUFFS getCDMSpellID function for class-aware icon resolution without per-frame allocation
    - String key safety in StartAllPreviewTimers via SUGGESTED_BUFFS lookup for meta-buffs

key-files:
  created: []
  modified:
    - BuffEngine.lua

key-decisions:
  - "SATED_DEBUFF_TO_LUST maps debuff IDs (not buff IDs) because Sated-family debuffs are the reliable signal — the buff itself may be a secret value"
  - "source=debuff on lust timer prevents false cancellation by ScanActiveTimersForCancellation (which only touches source=cast)"
  - "issecretvalue(aura.spellId) checked per-entry before table lookup — indexing with a secret value causes Lua error in M+"
  - "getCDMSpellID is a function closure (not cached value) so class detection runs at call time, not module load"

patterns-established:
  - "Meta-buff pattern: string key in trackedBuffs with metaBuff=true, seeded by schema migration, started by event (not cast)"
  - "SUGGESTED_BUFFS registry: array of buff definitions with getCDMSpellID for Plan 02 CDM tab consumption"

requirements-completed: [LUST-01, LUST-05]

# Metrics
duration: 2min
completed: 2026-04-04
---

# Phase 10 Plan 01: Lust Tracking Summary

**Sated-family debuff detection engine wired into BuffEngine.lua: data tables, schema v3 migration seeding the lust meta-buff, addedAuras scanning with issecretvalue guard, and StartLustTimer with source=debuff to survive cancellation scans**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-04T06:17:19Z
- **Completed:** 2026-04-04T06:19:29Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Added `ns.SATED_DEBUFF_TO_LUST` table mapping all 4 Sated-family debuff IDs to their corresponding lust spell IDs (Bloodlust, Heroism, Time Warp, Fury of the Aspects)
- Schema v3 migration seeds `trackedBuffs["lust"]` with `metaBuff=true`, `section="hidden"`, `duration=40` on first load
- `OnUnitAura` now detects Sated-family debuffs from `addedAuras` with per-entry `issecretvalue` guard before table lookup
- `StartLustTimer` creates a 40s timer with `source="debuff"` so it is never falsely cancelled by `ScanActiveTimersForCancellation`
- `StartAllPreviewTimers` handles the string key "lust" by resolving icon via `SUGGESTED_BUFFS.getCDMSpellID()`
- `SUGGESTED_BUFFS` and `CLASS_LUST_SPELL` registries ready for Plan 02 CDM tab consumption

## Task Commits

Each task was committed atomically:

1. **Task 1: Add lust data tables, schema migration, and string-key safety** - `7004d85` (feat)
2. **Task 2: Add lust debuff detection in OnUnitAura and StartLustTimer function** - `f692724` (feat)

**Plan metadata:** (docs: complete plan — added in final commit)

## Files Created/Modified

- `BuffEngine.lua` - Added SATED_DEBUFF_TO_LUST, CLASS_LUST_SPELL, SUGGESTED_BUFFS; bumped schema to v3 with lust seeding; string-key safety in StartAllPreviewTimers; StartLustTimer function; addedAuras detection in OnUnitAura

## Decisions Made

- `issecretvalue(aura.spellId)` is called per-entry before the SATED_DEBUFF_TO_LUST lookup because indexing a Lua table with a secret value raises a Lua error in restricted content (M+/PvP). This is the critical safety constraint documented in the plan.
- `source="debuff"` on lust timer ensures `ScanActiveTimersForCancellation` (which only scans `source="cast"`) never cancels the lust timer, allowing it to run its full 40s duration.
- `getCDMSpellID` is a function closure on the SUGGESTED_BUFFS entry so class detection (`UnitClass("player")`) runs at call time rather than module load, correctly reflecting the current character.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Lust detection engine complete; `ns.SUGGESTED_BUFFS`, `ns.CLASS_LUST_SPELL`, and `ns:StartLustTimer` are ready for Plan 02 CDM tab Suggested section activation
- Plan 02 needs to: activate Suggested section in CDM tab, implement copy-on-drag from Suggested to a real section, add class-aware icon and "Matches all Heroism/Bloodlust effects" tooltip subtext

---
*Phase: 10-lust-tracking*
*Completed: 2026-04-04*
