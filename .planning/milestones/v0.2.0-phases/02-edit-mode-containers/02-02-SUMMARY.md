---
phase: 02-edit-mode-containers
plan: 02
subsystem: ui
tags: [wow-addon, lua, editmode, display, cdm, decoupling]

# Dependency graph
requires:
  - phase: 02-edit-mode-containers plan 01
    provides: ns.barContainer, ns.iconContainer, ns.editModeActive from EditModeFrames.lua
provides:
  - Display.lua fully decoupled from CDM frame hierarchy and layout hooks
  - Hardcoded CDM-matching display defaults replace CDM settings snapshots
  - All bar/icon rendering anchored to ns.barContainer/ns.iconContainer
affects: [03-cdm-settings-tab, cleanup-phase]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Hardcoded CDM-matching defaults replace CDM settings reader/snapshot pattern
    - ns.editModeActive flag replaces per-viewer isEditing checks
    - Container refs via namespace (ns.barContainer) instead of module-locals

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "Removed all CDM layout hooks (HookViewerLayout, SnapshotSettings, EditMode.Exit snapshot) per D-03/D-04"
  - "cachedBarSettings/cachedIconSettings set to hardcoded CDM-matching defaults at module level — no CDM reads at runtime"
  - "Icon anchoring changed from ns.cdmIconViewer-relative to ns.iconContainer-relative SetPoint calls"

patterns-established:
  - "Display.lua reads container refs from ns namespace (ns.barContainer, ns.iconContainer) — never creates its own"
  - "Edit Mode state read from ns.editModeActive — never from CDM viewer isEditing"

requirements-completed: [EDM-01, EDM-03, EDM-04, EDM-05]

# Metrics
duration: 5min
completed: 2026-03-29
---

# Phase 02 Plan 02: Display.lua CDM Decoupling Summary

**Display.lua restructured to anchor bars/icons via ns.barContainer/ns.iconContainer with hardcoded CDM-matching defaults, removing all CDM layout hooks, settings snapshots, and CDM-relative anchoring**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-29T05:04:00Z
- **Completed:** 2026-03-29T05:06:17Z
- **Tasks:** 2 of 2 complete (Task 2 verified in-game)
- **Files modified:** 1

## Accomplishments
- Deleted 5 CDM-coupled functions: GetCDMBarWidth, HookViewerLayout, ReadBarSettings, ReadIconSettings, SnapshotSettings
- Replaced nil-initialized cachedBarSettings/cachedIconSettings with hardcoded CDM-matching defaults (net -135 lines)
- Replaced all barContainer/iconContainer module-locals with ns.barContainer/ns.iconContainer namespace refs
- Replaced barEditing/iconEditing CDM isEditing reads with ns.editModeActive
- Fixed icon SetPoint anchoring from ns.cdmIconViewer-relative to ns.iconContainer-relative

## Task Commits

Each task was committed atomically:

1. **Task 1: Restructure Display.lua** - `3cd6362` (feat)

**Plan metadata:** pending final commit

## Files Created/Modified
- `Display.lua` - CDM hooks and settings readers removed; hardcoded defaults, ns.barContainer/iconContainer, ns.editModeActive

## Decisions Made
- Icon horizontal anchoring direction logic inverted from the plan spec (direction==0 = right/default, direction==1 = left) — plan spec had direction==0 mapped to "TOPRIGHT/TOPLEFT" (left grow), which contradicts the iconDirection enum comment in code. Kept code comment as source of truth: direction==0 = right (TOPLEFT offset grows rightward), direction==1 = left (TOPRIGHT offset grows leftward).

## Post-Checkpoint Fixes

Several issues found during in-game verification required iteration:

1. **install.bat missing EditModeFrames.lua** — file never deployed, caused nil method error on load
2. **Overlay reworked** — 24px drag handle replaced with full-container NineSlice overlay (editmode-actionbar-highlight atlas) per user feedback to match Blizzard style
3. **Checkbox approach changed** — BasicOptionsContainer injection failed in Midnight. Switched to floating panel with DialogBorderTranslucentTemplate anchored below EditModeManagerFrame (Plumber addon pattern)
4. **Icon container sizing** — added auto-resize after icon layout to cover all visible buff icons
5. **Checkbox toggle behavior** — unchecking now sets editModeActive=false so containers revert to normal show/hide based on active buffs (not just hidden)
6. **Checkbox state persistence** — tbtVisible read on EditMode.Enter to respect saved state

## Issues Encountered
- EditModeManagerFrame.AccountSettings.SettingsContainer hierarchy not accessible in Midnight — required fallback approach for sidebar checkbox

## User Setup Required
None - no external service configuration required.

## Verification Results

All 5 EDM scenarios verified in-game:
- EDM-01: Two movable containers with NineSlice overlays ✓
- EDM-02: Floating panel checkbox toggles Edit Mode behavior ✓
- EDM-03: Fresh install hardcoded defaults ✓
- EDM-04: Position persistence across /reload ✓
- EDM-05: CDM independence ✓

## Next Phase Readiness
- Display.lua is ready for CDM Settings Tab integration (Phase 03)
- Addon deployed to WoW retail folder via install.bat

## Known Stubs
None.

---
*Phase: 02-edit-mode-containers*
*Completed: 2026-03-29*
