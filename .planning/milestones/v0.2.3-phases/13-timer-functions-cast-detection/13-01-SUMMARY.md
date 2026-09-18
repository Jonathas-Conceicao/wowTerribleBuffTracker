---
phase: 13-timer-functions-cast-detection
plan: 01
subsystem: timer-engine
tags: [lua, wow-addon, cast-detection, meta-slot, trinket, pot, timer]

# Dependency graph
requires:
  - "Phase 12: TRINKET_SPELLS and POT_SPELLS tables in BuffEngine.lua"
  - "CDMTab copy-on-drag: ns.db.trackedBuffs['trinket'] and ['pot'] entries"
provides:
  - "OnSpellCastSucceeded meta-slot fan-out: trinket/pot casts create keyed activeTimers"
  - "Shared-slot overwrite: only one metaSlot='trinket' and one metaSlot='pot' timer active at a time"
  - "Timer shape extended with metaSlot + layoutOrder fields for Display compatibility"
affects:
  - 14-icon-resolution-caching
  - 15-display-integration-active-icon-switching

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Meta-slot fan-out: TRINKET_SPELLS[spellID] / POT_SPELLS[spellID] O(1) lookup before regular trackedBuffs[spellID] path"
    - "Shared-slot overwrite via metaSlot field iteration before insert (D-04)"
    - "Timer shape extension: metaSlot + layoutOrder added; non-meta timers leave metaSlot nil"
    - "Label resolution: C_Spell.GetSpellInfo(spellID).name with fallback to metaEntry.label (D-08)"
    - "source='cast' preserved on meta-timers so ScanActiveTimersForCancellation works unchanged (TMR-04)"

key-files:
  created: []
  modified:
    - BuffEngine.lua

key-decisions:
  - "D-02: Fan-out runs BEFORE the regular ns.db.trackedBuffs[spellID] path (first match wins)"
  - "D-04: Shared-slot overwrite iterates activeTimers and nils any entry with same metaSlot before insert"
  - "D-06: section and layoutOrder copied from metaEntry at creation time (no per-render DB lookup)"
  - "D-08: label = C_Spell.GetSpellInfo(spellID).name, fallback to metaEntry.label"
  - "Inline implementation chosen (no helper extraction) per plan guidance — single function is clearer"

# Metrics
duration: 7min
completed: 2026-04-13
---

# Phase 13 Plan 01: Timer Functions + Cast Detection Summary

**OnSpellCastSucceeded extended with trinket/pot meta-slot fan-out: casting any TRINKET_SPELLS or POT_SPELLS entry creates a keyed activeTimer with metaSlot, shared-slot overwrite, and source='cast' for aura-scan cancellation compatibility**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-04-13T07:00:00Z
- **Completed:** 2026-04-13T07:01:14Z
- **Tasks:** 2 (1 code + 1 deploy)
- **Files modified:** 1

## Accomplishments

- OnSpellCastSucceeded rewritten with three mutually exclusive paths: trinket fan-out → pot fan-out → existing regular-buff path
- Trinket fan-out: O(1) TRINKET_SPELLS[spellID] lookup, guard on ns.db.trackedBuffs["trinket"] existence and section != "hidden" (D-01, D-03)
- Pot fan-out: identical pattern with ns.POT_SPELLS and ns.db.trackedBuffs["pot"]
- Shared-slot overwrite (D-04, TMR-03): iterates activeTimers before insert, nils any timer where metaSlot matches the new cast's metaSlot
- Timer shape extended with metaSlot and layoutOrder; section/layoutOrder copied from metaEntry at creation (D-06)
- Label from C_Spell.GetSpellInfo(spellID).name with fallback to metaEntry.label (D-08)
- source="cast" preserved on all meta-timers — ScanActiveTimersForCancellation aura-scan path unchanged (TMR-04)
- Regular-buff path (ns.db.trackedBuffs[spellID]) preserved verbatim below fan-out blocks
- Non-meta timers leave metaSlot nil — Display.lua has zero metaSlot reads (D-05 verified)
- stylua clean
- Deployed to WoW retail AddOns folder via install.bat (all 8 files copied)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add meta-slot fan-out to OnSpellCastSucceeded** - `70ba3f1` (feat)
2. **Task 2: Deploy addon via install.bat** - no commit (deployment action only)

## Files Created/Modified

- `BuffEngine.lua` - OnSpellCastSucceeded replaced with trinket/pot fan-out before regular path

## Decisions Made

- Inline implementation (no helper extraction): single function is clearer for this 3-path routing pattern
- Regular-buff path left untouched below fan-out — regression safety for existing user-added spells
- metaSlot=nil for regular timers (not explicitly set) — Display.lua tolerates absent fields

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

Run `/reload` in-game to load the updated addon before Plan 02 in-game verification.

## Known Stubs

None — meta-timer creation is fully wired. Icon resolution (Phase 14) and display-side active icon switching (Phase 15) are deferred per plan scope.

## Next Phase Readiness

- Plan 02 (in-game verification) can now proceed: casting any of the 9 trinket or 4 pot spellIDs will create activeTimers with correct metaSlot, duration, section, and source fields
- Phase 14 (icon resolution) will consume ns.TRINKET_ITEM_IDS and ns.POT_ITEM_IDS set up in Phase 12; no changes needed to the timer shape from this plan

## Self-Check: PASSED

- `BuffEngine.lua` present and modified (confirmed via git commit 70ba3f1)
- Commit 70ba3f1 exists: confirmed via git log above
- stylua --check passes: confirmed
- All grep acceptance criteria verified: TRINKET_SPELLS[spellID], POT_SPELLS[spellID], metaSlot="trinket", metaSlot="pot", existingTimer.metaSlot=="trinket", existingTimer.metaSlot=="pot", source="cast"
- install.bat exited 0, all 8 files copied to WoW retail AddOns folder

---
*Phase: 13-timer-functions-cast-detection*
*Completed: 2026-04-13*
