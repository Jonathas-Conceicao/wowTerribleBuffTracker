---
phase: 14-icon-resolution-caching
plan: 01
subsystem: ui
tags: [lua, wow-addon, icon-resolution, inventory-scan, c-item, in-combat-lockdown]

# Dependency graph
requires:
  - phase: 12-schema-migration-data-tables
    provides: TRINKET_ITEM_IDS, POT_ITEM_IDS, TRINKET_SPELLS, POT_SPELLS, SUGGESTED_BUFFS getCDMIcon placeholder
  - phase: 13-timer-functions-cast-detection
    provides: metaSlot pattern, OnSpellCastSucceeded fan-out

provides:
  - ns.metaIcons = { trinket, pot } module-level cache
  - ns:RefreshMetaIcons() — combat-gated, CSV-ordered inventory/bag scan with fallback
  - ns:GetAtRestMetaIcon(key) — single read accessor returning cache[key] or 134400
  - SUGGESTED_BUFFS trinket/pot getCDMIcon closures wired to GetAtRestMetaIcon
  - TRINKET_FALLBACK_ORDER / POT_FALLBACK_ORDER ordered fallback arrays

affects:
  - 14-02 (CDMTab: call ns:RefreshMetaIcons from StartPreview, D-14)
  - Phase 15 (Display.lua: use GetAtRestMetaIcon for bar/icon placeholder paths, D-12)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ns.metaIcons eager cache: module-level table, never persisted, mutated only by RefreshMetaIcons"
    - "InCombatLockdown guard: skip scan entirely, leave cache stale-or-nil rather than blanking"
    - "CSV-order fallback arrays: local TRINKET_FALLBACK_ORDER / POT_FALLBACK_ORDER mirror insertion order of spell tables"
    - "nil-on-miss storage: if chosen itemID icon is nil, store nil; GetAtRestMetaIcon returns 134400 (?-icon)"

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - .planning/REQUIREMENTS.md

key-decisions:
  - "ICON-06 N/A: refresh piggybacked on CDM StartPreview only — no PLAYER_EQUIPMENT_CHANGED/BAG_UPDATE_DELAYED event hooks"
  - "No icon recursion on nil: if GetItemIconByID returns nil for chosen itemID, store nil; display resolves via GetAtRestMetaIcon fallback to 134400"
  - "TRINKET_FALLBACK_ORDER / POT_FALLBACK_ORDER hard-coded in insertion order matching CSV source — pairs() not reliable"

patterns-established:
  - "GetAtRestMetaIcon pattern: mirrors GetSpellIcon fallback style — returns 134400 for nil, single call site"
  - "Single scan entry point: all inventory/bag scanning in RefreshMetaIcons, Display/CDMTab are pure readers"

requirements-completed:
  - ICON-01
  - ICON-02
  - ICON-06
  - ICON-07

# Metrics
duration: 2min
completed: 2026-04-13
---

# Phase 14 Plan 01: Icon Resolution Caching Summary

**ns.metaIcons eager cache with combat-gated CSV-ordered scan via GetInventoryItemID + C_Item.GetItemCount, and GetAtRestMetaIcon wired into SUGGESTED_BUFFS trinket/pot getCDMIcon closures**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-13T07:50:41Z
- **Completed:** 2026-04-13T07:52:18Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `TRINKET_FALLBACK_ORDER` / `POT_FALLBACK_ORDER` local arrays preserving CSV insertion order for deterministic fallback (pairs() not ordered)
- Implemented `ns:RefreshMetaIcons()` — InCombatLockdown-gated, scans equipped trinket slots 13/14 and bag counts via C_Item.GetItemCount, falls back to first CSV icon that resolves via C_Item.GetItemIconByID, stores nil without recursion
- Implemented `ns:GetAtRestMetaIcon(key)` — single public accessor returning `ns.metaIcons[key] or 134400`
- Wired both `SUGGESTED_BUFFS` trinket and pot `getCDMIcon` fields from `nil` placeholders to closures calling `GetAtRestMetaIcon`
- Marked ICON-06 N/A in REQUIREMENTS.md with rationale (refresh on StartPreview only per D-03/D-04)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add ordered fallback arrays, ns.metaIcons cache, RefreshMetaIcons, GetAtRestMetaIcon** - `5497747` (feat)
2. **Task 2: Reconcile ICON-06 as N/A in REQUIREMENTS.md** - `7196f37` (docs)
3. **Cleanup: Update stale trinket comment** - `ff4fece` (refactor)

## Files Created/Modified

- `BuffEngine.lua` — Added TRINKET_FALLBACK_ORDER, POT_FALLBACK_ORDER, ns.metaIcons, ns:RefreshMetaIcons, ns:GetAtRestMetaIcon; wired SUGGESTED_BUFFS getCDMIcon closures
- `.planning/REQUIREMENTS.md` — ICON-06 marked N/A in checklist and traceability table

## Decisions Made

- ICON-06 N/A: event-based refresh on PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED dropped — player only sees CDM preview when settings open, refreshing on every equipment/bag change wastes work (D-03/D-04)
- No icon recursion on nil GetItemIconByID return: store nil, display resolves to 134400 via GetAtRestMetaIcon. Matches user preference for ?-icon fallback, not Bloodlust
- TRINKET_FALLBACK_ORDER hard-coded in CSV order to ensure deterministic first-match behavior (pairs() order is undefined in Lua)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated stale trinket meta-tracker docblock comment**
- **Found during:** Stub scan before SUMMARY creation
- **Issue:** Comment above trinket SUGGESTED_BUFFS entry still referenced "Phase 12 leaves it nil" and `ns:ResolveTrinketIcon()` — both no longer accurate after Task 1 wired the closure
- **Fix:** Updated comment to reflect getCDMIcon now calls ns:GetAtRestMetaIcon
- **Files modified:** BuffEngine.lua
- **Verification:** Comment accurately describes current state; stylua check passes
- **Committed in:** ff4fece (standalone refactor commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - stale comment)
**Impact on plan:** Minor documentation accuracy fix. No scope creep.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `ns:RefreshMetaIcons()` is ready to be called from CDMTab.lua `StartPreview` (Phase 14 Plan 02, D-14)
- `ns:GetAtRestMetaIcon(key)` is ready for Display.lua bar/icon placeholder path fixes (Phase 15, D-12/D-13)
- No blockers.

---
*Phase: 14-icon-resolution-caching*
*Completed: 2026-04-13*
