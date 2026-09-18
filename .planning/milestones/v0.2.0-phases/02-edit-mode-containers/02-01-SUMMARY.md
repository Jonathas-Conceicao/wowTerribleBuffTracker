---
phase: 02-edit-mode-containers
plan: 01
subsystem: ui
tags: [wow-addon, edit-mode, draggable-frames, position-persistence, sidebar-checkbox]

# Dependency graph
requires:
  - phase: 01-data-migration
    provides: TerribleBuffTrackerDB with section field and schemaVersion

provides:
  - TBTBarContainer and TBTBuffContainer as UIParent-parented globally named frames
  - Edit Mode enter/exit lifecycle with drag handles and position save/load
  - EditMode sidebar checkbox (InjectSidebarCheckbox) controlling both container visibility
  - ns.db.editModePositions DB schema (bars and icons sub-tables with point/relativeTo/relativePoint/x/y)
  - ns.db.tbtVisible boolean default initialized in ADDON_LOADED

affects:
  - 02-02 (Display.lua restructure — must anchor to ns.barContainer / ns.iconContainer)
  - 03-cdm-settings-tab (may reference ns.tbtVisible or tbtSidebarCheckbox)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "EditModeFrames.lua module — ns:InitEditModeFrames() wires containers and EventRegistry callbacks"
    - "ApplyEditModePositions reads ns.db.editModePositions or writes defaults on nil (fresh install)"
    - "InjectSidebarCheckbox injects EditModeManagerSettingCheckButtonTemplate once, guarded by ns.tbtCheckboxInjected"
    - "Drag handles are child frames hidden at init, shown only during Edit Mode"

key-files:
  created:
    - EditModeFrames.lua
  modified:
    - Core.lua
    - TerribleBuffTracker.toc

key-decisions:
  - "TBTBarContainer and TBTBuffContainer are UIParent-parented named frames; ns.barContainer/ns.iconContainer are the Lua handles — global names exist for WoW's frame system, Lua code uses ns handles"
  - "Positions saved only on EditMode.Exit (not OnMouseUp) — user may drag multiple times before saving"
  - "Fresh install defaults: bars at CENTER+300,0; icons at CENTER+300,-80 (hardcoded, no CDM copy per D-06)"
  - "tbtVisible DB default init in Core.lua ADDON_LOADED; editModePositions nil-to-default handled by ApplyEditModePositions"

patterns-established:
  - "EditMode.Enter/Exit via EventRegistry:RegisterCallback — not EditModeSystemMixin (off-limits for addons)"
  - "Drag handles are child frames SetHeight(24) with BackdropTemplate border and GameFontNormal label"
  - "DB write on EditMode.Exit, not on drag end — matches Blizzard pattern"

requirements-completed: [EDM-01, EDM-02, EDM-03, EDM-04, EDM-05]

# Metrics
duration: 15min
completed: 2026-03-29
---

# Phase 2 Plan 01: Edit Mode Container Frames Summary

**UIParent-parented TBTBarContainer/TBTBuffContainer with drag handles, EventRegistry Edit Mode lifecycle, sidebar checkbox injection, and DB-backed position persistence**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-29T05:00:00Z
- **Completed:** 2026-03-29T05:02:19Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created EditModeFrames.lua (263 lines) with all Edit Mode infrastructure
- Two UIParent containers with global names, 24px drag handles matching CDM blue accent colors
- Edit Mode enter/exit lifecycle with SetMovable, drag scripts, handle show/hide, and position save on Exit
- Sidebar checkbox injected into BasicOptionsContainer using EditModeManagerSettingCheckButtonTemplate
- Position persistence via ns.db.editModePositions with fresh install defaults
- Core.lua updated with tbtVisible DB default and InitEditModeFrames called before InitDisplay
- TOC updated with EditModeFrames.lua in correct load order

## Task Commits

1. **Task 1: Create EditModeFrames.lua** - `36782dc` (feat)
2. **Task 2: Update Core.lua and TOC** - `a531540` (feat)

## Files Created/Modified

- `EditModeFrames.lua` — Container creation, drag handles, Edit Mode enter/exit, sidebar checkbox, position persistence
- `Core.lua` — Added tbtVisible DB default, ns:InitEditModeFrames() call before ns:InitDisplay()
- `TerribleBuffTracker.toc` — EditModeFrames.lua added between BuffEngine.lua and Display.lua

## Decisions Made

- Used ns.barContainer/ns.iconContainer as Lua handles, with global frame names TBTBarContainer/TBTBuffContainer only in CreateFrame call — this is the correct WoW pattern
- Positions saved exclusively on EditMode.Exit callback, not on OnMouseUp, matching Blizzard's save trigger pattern
- Show containers during Edit Mode regardless of tbtVisible state so empty containers can still be positioned

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None — no hardcoded placeholder values flow to the UI. Display.lua still uses its local barContainer/iconContainer (not yet wired to ns.barContainer/ns.iconContainer); that is the scope of Plan 02-02.

## Next Phase Readiness

- ns.barContainer and ns.iconContainer are ready for Display.lua to use as parent frames
- Edit Mode positions will be set by InitEditModeFrames before InitDisplay runs
- Plan 02-02 must update Display.lua to use ns.barContainer/ns.iconContainer instead of creating local container frames anchored to CDM

## Self-Check: PASSED

- EditModeFrames.lua exists: FOUND
- Core.lua updated: FOUND (InitEditModeFrames on line 41)
- TerribleBuffTracker.toc updated: FOUND
- Commit 36782dc exists: FOUND
- Commit a531540 exists: FOUND

---
*Phase: 02-edit-mode-containers*
*Completed: 2026-03-29*
