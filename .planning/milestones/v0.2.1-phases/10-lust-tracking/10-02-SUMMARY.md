---
phase: 10-lust-tracking
plan: 02
subsystem: ui
tags: [lua, wow-addon, cdm-tab, suggested-section, drag-and-drop, lust, heroism, meta-buff]

# Dependency graph
requires:
  - phase: 10-01
    provides: ns.SUGGESTED_BUFFS registry, ns.CLASS_LUST_SPELL, schema v3 with trackedBuffs["lust"]
provides:
  - CDMTab.lua Suggested section populated from ns.SUGGESTED_BUFFS with class-aware icon
  - Copy-on-drag from Suggested creates trackedBuffs entry; icon stays in Suggested
  - Right-click on Suggested items shows Add to Bars / Add to Buffs (no Remove)
  - Tooltip gray text "Matches all Heroism/Bloodlust effects" for metaBuff entries
  - String-key safe icon resolution in non-suggested sections (type check + SUGGESTED_BUFFS lookup)
  - BuffEngine.lua:SetBuffSection type guard accepting number and string keys
affects: [11-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Copy-on-drag from catalog: isFromSuggested flag in tbtDragState; EndDrag creates entry if absent, moves if present
    - addSuggestedToSection local closure in context menu handler for DRY add-to-section logic
    - String key safety: type(spellID) == "string" guard before SUGGESTED_BUFFS icon lookup throughout CDMTab
    - tostring() tiebreak in sort comparators for mixed numeric/string spellID keys

key-files:
  created: []
  modified:
    - CDMTab.lua
    - BuffEngine.lua

key-decisions:
  - "Copy-on-drag from Suggested: if already tracked, moves to target; if not, creates new entry from SUGGESTED_BUFFS definition — icon always stays in Suggested (D-05, D-07)"
  - "addSuggestedToSection local function inside CreateContextMenu handler deduplicates Add to Bars / Add to Buffs logic"
  - "tostring() tiebreak in layoutOrder sort handles mixed-type spellID keys safely without performance impact"
  - "SetBuffSection now explicitly guards nil and non-string/non-number inputs per RESEARCH.md Pitfall 4"

patterns-established:
  - "Suggested catalog pattern: iterate ns.SUGGESTED_BUFFS to populate, getCDMSpellID() for icon, isFromSuggested flag for drag copy semantics"
  - "String-key icon resolution: if type(spellID) == 'string' then look up SUGGESTED_BUFFS for cdmSpellID, fallback 2825"

requirements-completed: [LUST-02, LUST-03, LUST-04]

# Metrics
duration: 15min
completed: 2026-04-04
---

# Phase 10 Plan 02: Lust Tracking CDM Tab Summary

**CDM Suggested section activated with class-aware lust icon, copy-on-drag, right-click Add to Bars/Buffs menu, and gray "Matches all Heroism/Bloodlust effects" tooltip text**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-04T06:23:16Z
- **Completed:** 2026-04-04T06:38:00Z
- **Tasks:** 1 of 2 (Task 2 is a human-verify checkpoint)
- **Files modified:** 2

## Accomplishments

- Suggested section now populates from `ns.SUGGESTED_BUFFS` with class-aware icon via `getCDMSpellID()`
- Drag from Suggested to bars/buffs/hidden: creates `trackedBuffs` entry if absent, moves if already tracked; icon always stays in Suggested (D-05, D-07)
- Right-click context menu on Suggested shows "Add to Bars" / "Add to Buffs" only — no "Remove" (D-08)
- OnEnter tooltip appends gray `"Matches all Heroism/Bloodlust effects"` line for `metaBuff=true` entries
- String-key safe icon resolution in bars/buffs/hidden sections via SUGGESTED_BUFFS lookup when `type(spellID) == "string"`
- `BuffEngine.lua:SetBuffSection` now guards against `nil` and non-string/non-number inputs (Pitfall 4)
- Add square `layoutIndex = #ns.SUGGESTED_BUFFS + 1` (after all catalog icons)
- Sort tiebreak uses `tostring()` for mixed string/number key stability
- `SECTION_DEFS` title changed from `"Suggested (WIP)"` to `"Suggested"`

## Task Commits

Each task was committed atomically:

1. **Task 1: Activate Suggested section with catalog population, drag, right-click, tooltip, and SetBuffSection string-key guard** - `6275cf6` (feat)

Task 2 (human-verify checkpoint) pending in-game verification.

## Files Created/Modified

- `CDMTab.lua` - Suggested section population from SUGGESTED_BUFFS; copy-on-drag with isFromSuggested flag; Suggested right-click menu; metaBuff tooltip gray text; string-key icon resolution in non-suggested sections; tostring tiebreak; Add square layoutIndex; removed sectionName drag guard
- `BuffEngine.lua` - SetBuffSection type guard for nil/non-string/non-number keys

## Decisions Made

- `addSuggestedToSection` is a local function inside the `CreateContextMenu` closure to deduplicate the "Add to Bars" and "Add to Buffs" logic without a module-level function.
- EndDrag `isFromSuggested` branch checks `existing` before creating a new entry — prevents duplicate creation if user had already added lust to a section and is now dragging from Suggested again.
- `tostring()` tiebreak in the layoutOrder sort handles the mixed-type case where some `spellID` keys are numbers and `"lust"` is a string — avoids a Lua runtime error on `<` comparison between incompatible types.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Task 1 complete and deployed via `install.bat`
- Awaiting in-game verification (Task 2 checkpoint): Suggested section icon, tooltip, drag, right-click, and timer auto-start on lust detection
- Once verified, Phase 10 is complete and Phase 11 (cleanup) can begin

---
*Phase: 10-lust-tracking*
*Completed: 2026-04-04*
