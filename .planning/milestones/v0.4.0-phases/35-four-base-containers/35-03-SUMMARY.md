---
phase: 35-four-base-containers
plan: 03
subsystem: ui
tags: [cdm-tab, lua, cooldown-viewer]

# Dependency graph
requires:
  - phase: 35-four-base-containers plan 01
    provides: "ns.CONTAINERS / ns.CONTAINER_BY_KEY registry"
provides:
  - "SECTION_DEFS and VALID_DROP_SECTIONS built from ns.CONTAINERS at file load, so the TBT tab lists one section per registry entry plus Not Displayed and Suggested"
  - "Registry-driven right-click context menu: one 'Move to <title>' button per other container, one 'Add to <title>' button per container for Suggested items"
affects: [35-four-base-containers plan 04 (Display.lua UpdateDisplay generalisation), Phase 36 per-container settings, Phase 40 steal mode]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SECTION_DEFS/VALID_DROP_SECTIONS built once at file load by iterating ns.CONTAINERS then appending hidden/suggested — same module-level-constant-built-once shape as EditModeFrames.lua's Plan 02 loops, preserving the no-per-frame-allocation comment on VALID_DROP_SECTIONS since SectionHitTest/marker still read it every frame during a drag"
    - "Context menu loops ipairs(ns.CONTAINERS) and skips def.key == sectionName instead of an if/elseif chain over hardcoded section names"

key-files:
  created: []
  modified: [CDMTab.lua]

key-decisions:
  - "Section order follows ns.CONTAINERS (Tracked Buffs, Tracked Bars, Essential Cooldowns, Utility Cooldowns) per 35-CONTEXT.md, swapping the prior Bars-before-Buffs order intentionally"
  - "Section headers use the bare def.title (no 'TBT ' prefix) since the tab is already TBT's own tab; only Edit Mode overlays need the prefix to disambiguate from Blizzard's own four CDM systems"
  - "No entry.section rewriting — bars/buffs keys are unchanged from v0.3.0, so CONT-03's tracker-placement half stayed a no-op as the plan specified"

patterns-established:
  - "Move-to menu skips the current section by comparing def.key ~= sectionName inside the registry loop, rather than special-casing each container name"

requirements-completed: [CONT-01, CONT-03]

# Metrics
duration: ~10min
completed: 2026-09-21
---

# Phase 35 Plan 03: One CDM Tab Section Per Container Summary

**CDMTab.lua's SECTION_DEFS, VALID_DROP_SECTIONS and right-click context menus are now derived from `ns.CONTAINERS`, extending the TBT tab from two tracker sections to four with no change to the drag/drop, layout or refresh mechanism.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-09-21
- **Tasks:** 3 (2 code tasks + 1 format/verify task, no separate commit for task 3 since stylua produced no diff)
- **Files modified:** 1 (CDMTab.lua)

## Accomplishments
- `SECTION_DEFS` and `VALID_DROP_SECTIONS` are built once at file load by iterating `ns.CONTAINERS`, then appending `hidden`/`suggested` (`SECTION_DEFS`) or just `hidden` (`VALID_DROP_SECTIONS`) — the existing `SectionHitTest`, reorder marker, `UpdateScrollChildHeight`, `RefreshTBTSections` and `BuildAllSections` code needed zero changes since they already looped these two lists
- The tracked-item right-click menu replaced its three-way `if sectionName == "bars" … elseif "buffs" … elseif "hidden"` chain with a loop over `ns.CONTAINERS` producing one `"Move to " .. def.title` button per container other than the current section, followed by a conditional `"Hide"` button (only when not already in `hidden`) and the unchanged divider + `"Remove"` button
- The Suggested-item menu replaced the two hardcoded `"Add to Bars"` / `"Add to Buffs"` buttons with one `"Add to " .. def.title` button per registry def, all still calling the unchanged `addSuggestedToSection` local
- No `entry.section` value was read, iterated or rewritten — `bars`/`buffs` keys are untouched, keeping `CONT-03`'s placement half a no-op exactly as the plan required

## Task Commits

Each task was committed atomically:

1. **Task 1: Derive SECTION_DEFS and VALID_DROP_SECTIONS from the registry** - `583ada9` (feat)
2. **Task 2: Generalise the right-click context menus** - `7c22a95` (feat)

Task 3 (stylua format + syntax check + install.bat) produced no diff beyond what tasks 1-2 already committed, so it has no separate commit.

## Files Created/Modified
- `CDMTab.lua` - `SECTION_DEFS`/`VALID_DROP_SECTIONS` built from `ns.CONTAINERS` at file load; tracked-item and suggested-item right-click context menus loop the registry instead of hardcoding `bars`/`buffs` section names

## Decisions Made
- Kept `VALID_DROP_SECTIONS`'s existing "avoids per-frame table allocation" comment and its build-once-at-load shape, since `SectionHitTest` and the reorder marker's `OnDragUpdate` still read it every frame of every drag
- Left the `if def.key == "hidden"` delete-zone block and `if def.key == "suggested"` catalog block in `RefreshTBTSections` completely untouched — the plan's task 1 explicitly called these out as already correct

## Deviations from Plan

None - plan executed exactly as written. Both code tasks' acceptance-criteria greps passed on the first attempt with no follow-up fixes needed.

## Issues Encountered

None. `luac` is not on PATH on this machine, so task 3's syntax check used `stylua --check .` (exits 0 only on parseable Lua) per the plan's testing-reality fallback, matching Plan 02's precedent. `stylua` (no flags, repo root) produced an empty diff after the task commits, confirming both already matched the repo's `stylua.toml` formatting. `install.bat` exited 0 and deployed to all four detected WoW client folders (retail, ptr, beta, classic_beta).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `SECTION_DEFS` and `VALID_DROP_SECTIONS` are ready for Plan 04 (`Display.lua UpdateDisplay` generalisation) to build on; the CDM tab already shows all four containers as drop targets even though Essential/Utility trackers render as bars until Plan 04 lands (documented as an accepted, in-phase-fixed risk in the plan)
- In-game verification (six sections in order, drag into Essential Cooldowns surviving `/reload`, right-click Move-to/Hide/Remove menu contents, no rename/delete affordance on any header) from the plan's Verification section is explicitly folded into Plan 04's in-game pass per the plan text, not performed by this automated run

---
*Phase: 35-four-base-containers*
*Completed: 2026-09-21*

## Self-Check: PASSED

- FOUND: 583ada9
- FOUND: 7c22a95
- FOUND: CDMTab.lua
- FOUND: .planning/phases/35-four-base-containers/35-03-SUMMARY.md
