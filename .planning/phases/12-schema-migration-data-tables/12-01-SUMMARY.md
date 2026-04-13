---
phase: 12-schema-migration-data-tables
plan: 01
subsystem: database
tags: [lua, wow-addon, static-data, trinkets, potions, spellid-lookup]

# Dependency graph
requires: []
provides:
  - "TRINKET_SPELLS: 9-entry spellID-keyed table with {duration, itemID} per trinket"
  - "POT_SPELLS: 4-entry spellID-keyed table with {duration, itemID} per damage potion"
  - "TRINKET_ITEM_IDS: derived itemID -> true set for O(1) equipment scan in Phase 14"
  - "POT_ITEM_IDS: derived itemID -> true set for O(1) bag scan in Phase 14"
affects:
  - 13-timer-functions-cast-detection
  - 14-icon-resolution-caching
  - 15-display-integration-active-icon-switching

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "spellID-keyed static table with {duration, itemID} value (mirrors SATED_DEBUFF_TO_LUST pattern)"
    - "Derived itemID set via module-load loop over parent spell table (D-02, not hand-maintained)"
    - "ns exposure of local tables for cross-file access without file restructuring"

key-files:
  created: []
  modified:
    - BuffEngine.lua

key-decisions:
  - "Tables kept local then exposed on ns — local for scoping, ns for Phase 13/14 cross-file access without restructuring"
  - "No schema migration added — D-05 confirmed, CURRENT_SCHEMA_VERSION stays at 3"
  - "itemID sets derived at module load, not hand-maintained — single source of truth is the spell table"

patterns-established:
  - "Pattern: spellID-keyed lookup with {duration, itemID} struct — same pattern for TRINKET_SPELLS and POT_SPELLS"
  - "Pattern: derived sets via pairs() loop at module load — avoids duplication errors in hand-maintained sets"

requirements-completed: [DATA-01, DATA-02]

# Metrics
duration: 5min
completed: 2026-04-13
---

# Phase 12 Plan 01: Schema Migration + Data Tables Summary

**spellID-keyed TRINKET_SPELLS (9 entries) and POT_SPELLS (4 entries) added to BuffEngine.lua with derived itemID sets, providing the static data layer for Phase 13-15 trinket and pot meta-trackers**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-13T06:24:15Z
- **Completed:** 2026-04-13T06:25:29Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- TRINKET_SPELLS table with 9 entries transcribed verbatim from trinket_info.csv (spellID-keyed, {duration, itemID} values)
- POT_SPELLS table with 4 entries transcribed verbatim from pots_info.csv (spellID-keyed, {duration, itemID} values)
- TRINKET_ITEM_IDS and POT_ITEM_IDS sets derived at module load via pairs() loop (D-02, not hand-maintained)
- All four tables exposed on ns for Phase 13/14 consumption
- Schema version remains 3 (D-05, no migration needed for first-release data)
- stylua clean

## Task Commits

Each task was committed atomically:

1. **Task 1: Add TRINKET_SPELLS, POT_SPELLS, and derived item ID sets to BuffEngine.lua** - `cb8f395` (feat)

**Plan metadata:** (pending final commit)

## Files Created/Modified

- `BuffEngine.lua` - Added TRINKET_SPELLS, POT_SPELLS, TRINKET_ITEM_IDS, POT_ITEM_IDS after CLASS_LUST_SPELL block and before SUGGESTED_BUFFS

## Decisions Made

- Tables declared local then immediately exposed on ns (not directly on ns) to keep module scoping clean while allowing cross-file access without restructuring — Phases 13/14 will access via ns.TRINKET_SPELLS etc.
- No schema migration added per D-05: v0.2.3 is the first release with these features, so there is no stale data to migrate.
- itemID sets derived at module load from parent spell tables: single source of truth, no duplication errors possible.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- TRINKET_SPELLS and POT_SPELLS are ready for Phase 13 OnSpellCastSucceeded fan-out (O(1) spellID lookup)
- TRINKET_ITEM_IDS and POT_ITEM_IDS ready for Phase 14 equipment/bag scan
- No blockers.

---
*Phase: 12-schema-migration-data-tables*
*Completed: 2026-04-13*
