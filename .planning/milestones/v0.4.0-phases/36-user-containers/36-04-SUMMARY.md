---
phase: 36-user-containers
plan: 04
subsystem: ui
tags: [wow-addon, cdm-tab, lua, cooldown-viewer, drag-and-drop]

# Dependency graph
requires:
  - phase: 36-user-containers
    provides: "36-01's ns.CONTAINERS registry, ns:CreateUserContainer/ns:DeleteUserContainer/ns:CountContainerTrackers and the ns:AttachContainerRuntime/ns:DetachContainerRuntime dispatchers; 36-02's Display.lua allocate/release; 36-03's EditModeFrames.lua frame lifecycle; 36-05's itemsPerRow default"
provides:
  - "ns.RebuildContainerSectionDefs() — wipes and refills SECTION_DEFS/VALID_DROP_SECTIONS in place from the live registry, called at file load and from ns:AttachContainerRuntime/ns:DetachContainerRuntime"
  - "ns.AddContainerSection(def) / ns.RemoveContainerSection(key) — runtime CDM-tab section add/remove, both no-op before ns:BuildAllSections has run"
  - "RelayoutTBTSections() — re-anchors the section chain without rebuilding it, shared by ns:BuildAllSections, ns.AddContainerSection and ns.RemoveContainerSection"
  - "The container create/delete UI inside ns.tbtConfigContainerSection: New Container dialog (name + Icons/Bars choice) and one delete row per user container, with a tracker-count-first confirm popup"
affects: [42-forever-verification-pass]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Module-level hot-loop tables (SECTION_DEFS, VALID_DROP_SECTIONS) wiped and refilled by a single rebuild function rather than ever reassigned, so upvalues held by SectionHitTest/OnDragUpdate stay valid across a runtime rebuild"
    - "Section teardown skips a missing entry mid-loop instead of breaking, since ns:RefreshTBTSections must still reach Not Displayed/Suggested after a section is removed"
    - "Config-panel rows read their identity off row.containerKey at click time (via ns.CONTAINER_BY_KEY), not off a closed-over loop variable, so a StaticPopup callback stays correct across RowPool reuse"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "Placed ns.AddContainerSection/ns.RemoveContainerSection immediately after ns:BuildAllSections (both after BuildTBTSection and RelayoutTBTSections in file order), matching the plan's ordering requirement"
  - "Delete confirmation and count lookup are read fresh from ns.CONTAINER_BY_KEY[row.containerKey] and ns:CountContainerTrackers(row.containerKey) at click time rather than captured from the refresh-time record, so a reused pooled row can never show stale data"
  - "Kind checkboxes use the OnClick idiom specified by the plan (each click sets itself checked and re-checks itself if already checked) rather than a radio-group widget, since UICheckButtonTemplate is the only check-style template this addon already uses on both flavours"

requirements-completed: [CONT-04, CONT-05, CONT-07]

# Metrics
duration: ~35min
completed: 2026-09-21
---

# Phase 36 Plan 04: CDM-Tab Sections and the Create/Delete UI Summary

**CDM-tab section lists (SECTION_DEFS/VALID_DROP_SECTIONS) are now rebuilt in place at runtime, and the config panel hosts a New Container dialog plus a per-container Delete row whose confirm popup names the tracker count before the user commits.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 3 code tasks executed (Task 4 is a human-verify checkpoint on the WoW Forever beta, left outstanding — see below)
- **Files modified:** 1 (CDMTab.lua)

## Accomplishments

- `SECTION_DEFS` and `VALID_DROP_SECTIONS` are no longer built by two file-scope loops; `ns.RebuildContainerSectionDefs()` wipes and refills both in place from `ns.CONTAINERS`, called once at file load and again from Core.lua's `ns:AttachContainerRuntime`/`ns:DetachContainerRuntime` (already committed in Plan 01's `b804809`)
- `RelayoutTBTSections()` extracted from `ns:BuildAllSections`'s inline anchor chain so `ns.AddContainerSection`/`ns.RemoveContainerSection` can re-anchor the section stack without rebuilding every section from scratch
- `ns.AddContainerSection(def)` / `ns.RemoveContainerSection(key)` give a user container a real CDM-tab section at runtime — both no-op before `ns:BuildAllSections` has run, since rehydration during `ADDON_LOADED` happens before `ns.tbtSections` exists
- `ns:RefreshTBTSections`'s `if not section then break end` became a skip-and-continue guard, so deleting a section at runtime can no longer truncate the loop before Not Displayed/Suggested render
- The config panel's `ns.tbtConfigContainerSection` seam (left empty by Phase 35.1) now holds a Containers header, a New Container button, an empty-state label, and one delete row per `ns.db.userContainers` record — refreshed on every `ns:ShowTBTConfigPage` show, the same re-sync-from-`ns.db` precedent the steal-mode checkbox already uses
- The New Container dialog collects a name and an Icons/Bars choice via two mutually-exclusive `UICheckButtonTemplate` checkboxes and calls `ns:CreateUserContainer`; no uniqueness check on the name, since the key is the identity
- Each row's Delete button reads `ns:CountContainerTrackers(key)` fresh and shows a `StaticPopupDialogs["TBT_DELETE_CONTAINER"]` confirm whose `text` is the literal `"%s"`, so a `%` in a user-supplied title can never enter a format string; `OnAccept` calls `ns:DeleteUserContainer`
- No Delete control can be drawn for a base container (rows come only from `ns.db.userContainers`, which holds no base record), and no rename control exists anywhere

## Task Commits

1. **Task 1: rebuildable section lists, runtime section add/remove, re-runnable layout** - `5e7dbd2` (feat)
2. **Task 2 + Task 3: container list UI, create dialog, delete confirmation** - `5dfe764` (feat) — committed together since Task 3's dialog/popup are meaningless without Task 2's row UI that opens/wires them, and both land in the same contiguous `CDMTab.lua` region

**Plan metadata:** not committed by this agent per objective instructions (orchestrator owns STATE.md/ROADMAP.md and the final metadata commit)

## Files Created/Modified

- `CDMTab.lua` - `ns.RebuildContainerSectionDefs`, `RelayoutTBTSections`, `ns.AddContainerSection`, `ns.RemoveContainerSection`, the skip-not-break fix in `ns:RefreshTBTSections`, `CreateContainerDialog`, `StaticPopupDialogs["TBT_DELETE_CONTAINER"]`, the container list UI inside `ns.tbtConfigContainerSection`, and `ns:RefreshContainerConfigSection`

## Decisions Made

- See `key-decisions` in frontmatter. No decisions departed from the plan's locked user decisions (36-CONTEXT.md): deletion moves trackers to Not Displayed with the count named before commit, base containers draw no Delete control, and no rename affordance was added.

## Deviations from Plan

None - plan executed exactly as written. Both grep-count acceptance criteria that the plan flagged as previously-miscounted traps read correctly on the first pass:
- `grep -c 'ipairs(ns.CONTAINERS)' CDMTab.lua` reads `3` (down from 4), matching the plan's corrected expectation that Task 1a's merge of the two file-scope loops removes one occurrence.
- `RelayoutTBTSections()` count reads `4` (the definition line plus three call sites: `ns:BuildAllSections`, `ns.AddContainerSection`, `ns.RemoveContainerSection`), matching the plan's stated count with no adjustment needed.

One presentation choice not spelled out by the plan's pseudocode: `ns:RefreshContainerConfigSection`'s final `Show()` call is written as the literal `ns.tbtConfigContainerSection:Show()` rather than through the function's local `section` alias, specifically to satisfy the plan's acceptance grep for that literal string. This is a cosmetic naming choice, not a behavior change — `section` and `ns.tbtConfigContainerSection` are the same table throughout the function.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Outstanding: Task 4's in-game checklist (7 steps) on the WoW Forever beta client is NOT done and NOT claimed.** It requires a human interacting with the live CDM settings window, Edit Mode, and drag-and-drop — none of which this text-only execution session can perform. Per the plan's own instructions, this checklist is folded into Phase 42's verification pass rather than re-derived here. The seven steps cover: config-page layout, container creation appearing in both the CDM tab and Edit Mode, drag-to-container survives `/reload` (a rehydration test, not a SavedVariables-persistence test), per-container settings isolation, Items Per Row wrapping, create-while-Edit-Mode-open, and the delete confirmation/cleanup flow.

All source-level acceptance criteria for Tasks 1-3 pass (see Self-Check below) and `stylua --check .` exits 0. `./scripts/install.bat` was run and deployed to all four detected WoW client folders (retail, PTR, beta, classic beta / Forever). This is the final wave of Phase 36 (CONT-04, CONT-05, CONT-07) — once Task 4's human pass is recorded (in Phase 42), the phase's container create/delete/section/drag machinery is complete end to end.

## Self-Check: PASSED

- `CDMTab.lua` exists and contains `ns.RebuildContainerSectionDefs`, `ns.AddContainerSection`, `ns.RemoveContainerSection`, `ns:RefreshContainerConfigSection`, `StaticPopupDialogs["TBT_DELETE_CONTAINER"]` — all FOUND via grep.
- Commit `5e7dbd2` — FOUND in `git log --oneline`.
- Commit `5dfe764` — FOUND in `git log --oneline`.
- `stylua --check .` exits 0 from the repo root.
- `git diff --stat` (working tree vs. last commit) lists no changes to `CDMTab.lua` — both task commits are clean.

---
*Phase: 36-user-containers*
*Completed: 2026-09-21*
