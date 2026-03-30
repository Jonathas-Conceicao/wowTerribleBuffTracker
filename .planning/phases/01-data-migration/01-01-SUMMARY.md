---
phase: 01-data-migration
plan: 01
subsystem: database
tags: [lua, savedsvariables, schema-migration, buff-tracking]

# Dependency graph
requires: []
provides:
  - "TerribleBuffTrackerDB schema v1 with section field (bars/buffs/hidden) replacing enabled+displayMode"
  - "Schema migration guard in InitBuffEngine (schemaVersion 0->1)"
  - "All BuffEngine.lua read/write paths use entry.section"
  - "Display.lua filtering uses entry.section and timer.section"
affects:
  - 02-edit-mode
  - 03-cdm-tab-injection
  - 04-static-sections
  - 05-drag-and-drop

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "schemaVersion integer on TerribleBuffTrackerDB root for migration gating"
    - "entry.section single-source-of-truth replacing enabled+displayMode dual fields"

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - Display.lua

key-decisions:
  - "Migration mapping per D-01: enabled=false->hidden, displayMode=buff->buffs, else->bars"
  - "Clean break per D-02: enabled and displayMode fields set to nil after migration"
  - "schemaVersion integer on DB root per D-03/D-04: migration runs only when ver < 1"
  - "New buffs default to section=hidden per D-05: user must explicitly promote"
  - "SetBuffEnabled and SetBuffDisplayMode updated to write entry.section (transitional, ConfigUI stays functional)"

patterns-established:
  - "Schema migration pattern: schemaVersion guard in InitBuffEngine, sequential if ver < N blocks"
  - "Section field is the single source of truth for buff display assignment"

requirements-completed: [MIG-01, MIG-02]

# Metrics
duration: 2min
completed: 2026-03-28
---

# Phase 01 Plan 01: Data Migration Summary

**TerribleBuffTrackerDB migrated from v0 (enabled+displayMode) to v1 (section field) with schemaVersion guard, clean field removal, and all read/write paths updated in BuffEngine.lua and Display.lua**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-28T23:39:02Z
- **Completed:** 2026-03-28T23:41:23Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Schema migration v0->v1 in InitBuffEngine() with correct D-01 mapping (enabled=false->hidden, displayMode=buff->buffs, else->bars)
- deprecated enabled/displayMode fields removed from all entries via entry.enabled=nil / entry.displayMode=nil (D-02)
- schemaVersion guard ensures migration runs exactly once (D-03/D-04)
- All operational read/write paths in BuffEngine.lua and Display.lua use entry.section / timer.section
- SetBuffEnabled and SetBuffDisplayMode updated as transitional shims so ConfigUI remains functional
- Addon deployed to WoW retail addons folder via install.bat

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate BuffEngine.lua — schema migration + all read/write path updates** - `850971d` (feat)
2. **Task 2: Update Display.lua — replace all displayMode/enabled reads with section** - `cf2442e` (feat)

**Plan metadata:** _(see final commit below)_

## Files Created/Modified
- `BuffEngine.lua` - Schema migration v0->v1, updated AddTrackedBuff/OnSpellCastSucceeded/StartAllPreviewTimers/SetBuffEnabled/SetBuffDisplayMode
- `Display.lua` - Section-aware timer split and slot filtering (timer.section, entry.section)

## Decisions Made
- SetBuffEnabled and SetBuffDisplayMode were updated to write entry.section (not removed) because ConfigUI.lua still calls them. This keeps the existing config window functional until it is replaced in Phase 03.
- The migration block in InitBuffEngine necessarily retains entry.enabled and entry.displayMode reads to perform the mapping — these are read-and-remove references within the migration guard, not operational paths.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- The plan's automated verification grep (`grep -c "entry.enabled" BuffEngine.lua | grep "^0$"`) would flag the migration block itself, which necessarily reads entry.enabled to perform the mapping. These are intentional read-then-nil references inside the `ver < 1` guard. All operational code paths outside the migration block use entry.section exclusively.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- section field is now the single source of truth for buff display assignment
- All downstream phases (Edit Mode, CDM Tab, Drag-and-Drop) can depend on entry.section being present on all trackedBuffs entries
- No blockers for Phase 02

---
*Phase: 01-data-migration*
*Completed: 2026-03-28*
