---
phase: 35-four-base-containers
plan: 02
subsystem: ui
tags: [edit-mode, lua, cooldown-viewer]

# Dependency graph
requires:
  - phase: 35-four-base-containers plan 01
    provides: "ns.CONTAINERS / ns.CONTAINER_BY_KEY registry, editModePositions v4 migration"
provides:
  - "Four registry-driven Edit Mode containers (Tracked Buffs, Tracked Bars, Essential Cooldowns, Utility Cooldowns) each independently selectable, draggable and persisted"
  - "ns.containers / ns.containerOverlays / ns.containerSelectedOverlays keyed tables replacing the six paired bar/icon fields"
  - "Settings popup and Copy Blizzard CDM Config generalised to branch on def.kind and resolve viewers via _G[def.cdmViewerGlobal]"
affects: [35-four-base-containers plan 03 (CDM tab sections), plan 04 (Display.lua alias removal), Phase 36 per-container settings, Phase 38 cooldown rendering]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Every Edit Mode consumer (selection, handles, hit test, lifecycle, popup) loops ipairs(ns.CONTAINERS) or indexes ns.containers[def.key] instead of a bars/buffs literal pair"
    - "ns.barContainer / ns.iconContainer kept as explicit temporary aliases to ns.containers.bars / .buffs, documented at their assignment site as Plan 04's removal point"

key-files:
  created: []
  modified: [EditModeFrames.lua]

key-decisions:
  - "Copy Blizzard CDM Config resolves _G[def.cdmViewerGlobal] lazily at click time rather than caching a viewer reference, matching PROJECT.md's capability-check-over-flavour-check rule; the existing nil-viewer guard already handles Forever"
  - "ShowEditModeHandles' bar-width floor keeps reading containerSettings[def.key].barWidth as a raw pixel width exactly as it did before this plan (pre-existing percentage-vs-pixel unit mismatch, out of scope per CLAUDE.md's no-refactor-beyond-task-scope rule)"

patterns-established:
  - "Registry loop replaces paired-field ternary: `ns.containerSelectedOverlays[which]` with a nil guard, not `which == \"bars\" and X or Y`"

requirements-completed: [CONT-01, CONT-02, CONT-03]

# Metrics
duration: ~35min
completed: 2026-09-21
---

# Phase 35 Plan 02: Four Edit Mode Containers Summary

**EditModeFrames.lua now creates, positions, selects, drags and configures all four `ns.CONTAINERS` entries from one registry loop instead of two hardcoded bar/icon container names.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-21
- **Tasks:** 5 (4 code tasks + 1 format/verify task, no separate commit for task 5 since stylua produced no diff)
- **Files modified:** 1 (EditModeFrames.lua)

## Accomplishments
- `ns:InitEditModeFrames` builds one `CreateFrame` + `CreateEditModeOverlay` + `CreateSelectedOverlay` triple per `ns.CONTAINERS` entry, keyed into `ns.containers` / `ns.containerOverlays` / `ns.containerSelectedOverlays`; overlay labels carry a `"TBT "` prefix so they read distinctly from Blizzard's own four CDM systems in the same Edit Mode panel
- `ApplyEditModePositions` and `ns:SaveEditModePositions` read/write `ns.db.editModePositions[def.key]` per registry entry, seeding missing keys from `def.defaultX`/`def.defaultY` idempotently — this is what gives an upgraded database its new `essential`/`utility` positions
- Selection, drag handles, the global click hit test, and Edit Mode enter/exit/checkbox lifecycle all loop the registry instead of hardcoding two names; `WireSelectableDrag` itself needed no change since it was already per-key
- The settings popup and Copy Blizzard CDM Config branch on `def.kind` instead of `containerKey == "bars"`, and resolve the CDM viewer via `_G[def.cdmViewerGlobal]` at click time instead of reading `Display.lua`'s `ns.cdmBarViewer`/`ns.cdmIconViewer`

## Task Commits

Each task was committed atomically:

1. **Task 1: Create the four containers and their overlays from the registry** - `eee776a` (feat)
2. **Task 2: Apply and save positions per registry key** - `c2578a2` (feat)
3. **Task 3: Generalise selection, handles, lifecycle and the hit test** - `6d7689c` (feat)
4. **Task 4: Generalise the settings popup and Copy CDM Config** - `a3efcd3` (feat)

Task 5 (stylua format + syntax check + install.bat) produced no diff beyond what tasks 1-4 already committed, so it has no separate commit.

## Files Created/Modified
- `EditModeFrames.lua` - Registry-driven container/overlay creation, position apply/save, selection, drag handles, hit test, Edit Mode lifecycle, settings popup and Copy CDM Config; `ns.barContainer`/`ns.iconContainer` kept as temporary aliases to `ns.containers.bars`/`.buffs`

## Decisions Made
- Kept the bar-kind width floor's pre-existing unit mismatch (`containerSettings[def.key].barWidth` read as a raw pixel width, even though `Core.lua`'s comment documents it as a percentage) exactly as it behaved before this plan — CLAUDE.md's "no refactors beyond the plan's tasks" rule and the plan's own instruction to keep `ShowEditModeHandles`' floors unchanged both apply; not in this plan's scope to fix
- `_G[def.cdmViewerGlobal]` resolved lazily inside the click handler rather than cached at init, per the plan's explicit instruction and PROJECT.md's capability-check guidance

## Deviations from Plan

None - plan executed exactly as written. All four code tasks' acceptance-criteria greps passed on the first attempt with no follow-up fixes needed.

## Issues Encountered

None. `luac` is not on PATH on this machine, so task 5's syntax check used `stylua --check .` (exits 0 only on parseable Lua) per the plan's testing-reality fallback. `stylua` (no flags, repo root) produced an empty diff, confirming the four task commits already matched the repo's `stylua.toml` formatting.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `ns.containers` / `ns.containerOverlays` / `ns.containerSelectedOverlays` are ready for Plan 03 (CDM tab sections) and Plan 04 (Display.lua alias removal) to build on
- `Display.lua` still reads only `ns.barContainer` and `ns.iconContainer`, so `essential` and `utility` containers exist, are positionable and draggable (satisfying `CONT-02`), but render nothing until Plan 04 wires `Display.lua` to all four keys
- In-game verification (Edit Mode entry, four-container drag, persistence across Edit Mode exit/re-entry, no Lua errors) from the plan's Verification section was not performed by this automated run — flagged for the user's short in-game pass mentioned in `35-02-PLAN.md`

---
*Phase: 35-four-base-containers*
*Completed: 2026-09-21*

## Self-Check: PASSED

- FOUND: eee776a
- FOUND: c2578a2
- FOUND: 6d7689c
- FOUND: a3efcd3
- FOUND: EditModeFrames.lua
- FOUND: .planning/phases/35-four-base-containers/35-02-SUMMARY.md
