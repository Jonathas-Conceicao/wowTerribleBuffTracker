---
phase: 06-cleanup
plan: 01
subsystem: ui
tags: [lua, cleanup, hot-path, documentation]

# Dependency graph
requires:
  - phase: 05.1-edit-mode-settings-popup
    provides: final feature set complete; cdmWatcher and dead shims identified
provides:
  - Dead code removed (SetBuffEnabled, SetBuffDisplayMode shims)
  - cdmWatcher converted from always-on OnUpdate to event-activated polling
  - CLAUDE.md Architecture accurate (no ConfigUI, includes CDMTab/EditModeFrames)
  - REQUIREMENTS.md Out of Scope row for within-section reordering removed
  - All Lua files stylua-clean
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Event-activated polling: register UI_PANEL_SHOW, start OnUpdate, self-terminate when done"

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - CDMTab.lua
    - CLAUDE.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "cdmWatcher uses UI_PANEL_SHOW to activate polling, then self-terminates when CDM closes — no idle per-frame work"

patterns-established:
  - "Event-activated OnUpdate: use RegisterEvent to start, SetScript(OnUpdate, nil) to stop when condition no longer relevant"

requirements-completed: []

# Metrics
duration: 10min
completed: 2026-03-30
---

# Phase 6 Plan 01: Cleanup Summary

**Dead code removed, cdmWatcher OnUpdate converted from always-running to event-activated self-terminating poll, and all documentation updated to reflect Phase 3-5 changes**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-30T03:14:22Z
- **Completed:** 2026-03-30T03:24:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Removed `ns:SetBuffEnabled()` and `ns:SetBuffDisplayMode()` — dead shims with no callers since ConfigUI.lua was deleted in Phase 3
- Fixed cdmWatcher: was polling `CooldownViewerSettings:IsVisible()` every single frame unconditionally; now activates on `UI_PANEL_SHOW` and self-terminates when CDM closes
- CLAUDE.md Architecture updated: ConfigUI.lua removed, EditModeFrames.lua / CDMTab.xml / CDMTab.lua added; Patterns section container parent corrected
- REQUIREMENTS.md Out of Scope: removed "Within-section reordering" row (feature was implemented in Phase 5)
- All five Lua files pass `stylua --check` with zero changes

## Task Commits

Each task was committed atomically:

1. **Task 1: Dead code removal and cdmWatcher hot-path fix** - `def54c6` (refactor)
2. **Task 2: Documentation cleanup and stylua** - `fbcec8b` (chore)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `BuffEngine.lua` — removed ns:SetBuffEnabled() (lines 160-177) and ns:SetBuffDisplayMode() (lines 224-242)
- `CDMTab.lua` — replaced always-running OnUpdate with UI_PANEL_SHOW event activation + self-terminating poll
- `CLAUDE.md` — Architecture and Patterns sections updated to match actual codebase
- `.planning/REQUIREMENTS.md` — stale Out of Scope row removed

## Decisions Made
- cdmWatcher polling approach: UI_PANEL_SHOW starts polling, self-termination stops it when CDM closes. Satisfies ROADMAP success criterion "No OnUpdate callbacks run when no drag is in progress" without using HookScript on CooldownViewerSettings (taint risk preserved as comment).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 6 cleanup complete — codebase is release-ready
- All ROADMAP Phase 6 success criteria satisfied: no idle OnUpdate, stylua-clean, no stale references

---
*Phase: 06-cleanup*
*Completed: 2026-03-30*

## Self-Check: PASSED

- FOUND: BuffEngine.lua
- FOUND: CDMTab.lua
- FOUND: CLAUDE.md
- FOUND: .planning/REQUIREMENTS.md
- FOUND: .planning/phases/06-cleanup/06-01-SUMMARY.md
- FOUND: commit def54c6 (refactor: dead shims + cdmWatcher fix)
- FOUND: commit fbcec8b (chore: docs + stylua)
