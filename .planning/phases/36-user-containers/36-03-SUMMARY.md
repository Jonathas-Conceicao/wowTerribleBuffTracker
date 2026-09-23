---
phase: 36-user-containers
plan: 03
subsystem: ui
tags: [wow-addon, edit-mode, lua, cooldown-viewer]

# Dependency graph
requires:
  - phase: 36-user-containers
    provides: "36-01's ns.CONTAINERS registry (RegisterContainerDef/UnregisterContainerDef) and the nil-guarded ns:AttachContainerRuntime / ns:DetachContainerRuntime dispatchers; 36-02's Display.lua per-container pool allocate/release pattern used as the teardown model"
provides:
  - "ns.CreateContainerFrames(def) — post-load container frame creation, called from Core.lua's ns:AttachContainerRuntime; idempotent and a no-op before ns.containers exists"
  - "ns.DestroyContainerFrames(key) — hide-and-orphan teardown, called from Core.lua's ns:DetachContainerRuntime; safe for a key already unregistered from ns.CONTAINERS"
  - "Edit-Mode-is-open creation path: a container created while Edit Mode is active is immediately movable, selectable and shows its handle"
  - "Settings popup 'Copy Blizzard CDM Config' button hidden for containers with no cdmViewerGlobal (user containers)"
affects: [36-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-container loop bodies extracted into named local functions (ApplyContainerPosition, ShowContainerHandle, WireContainerDrag) so ns.CreateContainerFrames composes them instead of duplicating a fifth copy"
    - "Teardown is hide-and-orphan (WoW frames cannot be destroyed): clear scripts, StopMovingOrSizing, Hide, ClearAllPoints, SetParent(nil), then drop the ns.* table entries"

key-files:
  created: []
  modified:
    - EditModeFrames.lua

key-decisions:
  - "Split the plan's Task 1/Task 2 code into two commits by temporarily stripping the Edit-Mode-open tail and ns.DestroyContainerFrames after writing them, committing Task 1's extraction alone, then restoring both for Task 2's commit — keeps commits atomic per plan task despite the two pieces landing in the same contiguous file region"
  - "ns.DestroyContainerFrames uses the guarded 'if selectedContainer == key then ns:ClearSelection() end' form specified by the plan, not a bare ns:DeselectContainer(key), to avoid clearing a different container's selection state"

requirements-completed: [CONT-04, CONT-05, CONT-06]

# Metrics
duration: ~20min
completed: 2026-09-21
---

# Phase 36 Plan 03: Post-Load Container Frames and Teardown Summary

**`ns.CreateContainerFrames(def)` / `ns.DestroyContainerFrames(key)` give user containers a full post-load frame lifecycle in EditModeFrames.lua, including immediate drag/handle wiring when created while Edit Mode is already open.**

## Performance

- **Duration:** ~20 min
- **Tasks:** 3 (2 code tasks + 1 format/verify task, the latter folded into Task 2's commit since it produced no additional diff)
- **Files modified:** 1 (EditModeFrames.lua)

## Accomplishments

- Extracted four previously-duplicated per-container loop bodies (`ApplyContainerPosition`, `ShowContainerHandle`, `WireContainerDrag`, and the frame-construction block) into named functions, so `ns.CreateContainerFrames` composes them instead of adding a fifth copy
- `ns:InitEditModeFrames` now calls `ns.CreateContainerFrames(def)` in its loop rather than holding its own construction code
- `ns.CreateContainerFrames(def)` handles the Edit-Mode-is-open case: a container created while Edit Mode is active is wired for drag and shown its handle immediately
- `ns.DestroyContainerFrames(key)` hides and orphans a deleted container's frame in the plan-specified order, guarding selection/popup state and a possible in-flight drag, and is safe for a key already removed from `ns.CONTAINERS`
- The "Copy Blizzard CDM Config" button is hidden for user containers (no `cdmViewerGlobal`), with a matching early-return in its `OnClick` as belt-and-braces

## Task Commits

1. **Task 1: extract the four per-container bodies** - `1a5d24a` (feat)
2. **Task 2: runtime lifecycle (Edit-Mode-open creation, teardown, CDM button)** - `e45681c` (feat)
3. **Task 3: format and verify** - no separate commit; `stylua` (repo-root, no flags) was run after each of the two commits above and produced no additional diff, and `stylua --check .` exits 0 against the final state

**Plan metadata:** not committed by this agent per objective instructions (orchestrator owns STATE.md/ROADMAP.md and the final metadata commit)

## Files Created/Modified

- `EditModeFrames.lua` - Extracted `ApplyContainerPosition(def)`, `ShowContainerHandle(def)`, `WireContainerDrag(def)`; added `ns.CreateContainerFrames(def)` and `ns.DestroyContainerFrames(key)`; hid the CDM copy button for user containers

## Decisions Made

- Committed Task 1 and Task 2 separately to match the plan's task boundaries, even though the code for both lives in the same contiguous `EditModeFrames.lua` region — done by writing the full implementation, then temporarily removing Task 2's two pieces (the `if ns.editModeActive then ... end` tail and all of `ns.DestroyContainerFrames`) before the first commit, then restoring them for the second.
- Followed the plan's exact guarded-deselect form in `ns.DestroyContainerFrames` (`if selectedContainer == key then ns:ClearSelection() end`) rather than an unconditional `ns:DeselectContainer(key)` call, per the plan's own risk analysis.

## Deviations from Plan

None — plan executed exactly as written. One acceptance-criteria grep count differs from the plan's stated expectation (see below), which is not a code deviation.

## Issues Encountered

**Grep-count mismatch (not a bug, not fixed):** Task 1's acceptance criteria state `grep -c 'ApplyContainerPosition(def)' EditModeFrames.lua` returns `2` ("the positions loop and `ns.CreateContainerFrames`"). The real count is `3`, because the pattern also matches the function's own definition line (`local function ApplyContainerPosition(def)`), which the plan's expected count did not account for. Verified the code shape is correct — one definition, one call from `ApplyEditModePositions`, one call from `ns.CreateContainerFrames` — and did not alter the code to force the number down. All other acceptance-criteria commands returned exactly the plan's expected values.

## User Setup Required

None - no external service configuration required. All in-game verification is deferred to Plan 04's Forever checklist per the plan's own Verification section.

## Next Phase Readiness

`ns.CreateContainerFrames` / `ns.DestroyContainerFrames` are live and dispatched from Core.lua's `ns:AttachContainerRuntime` / `ns:DetachContainerRuntime` (already committed in `b804809`), so container creation/deletion now produces a real Edit Mode frame without a `/reload`. Plan 04 (CDM tab section lifecycle and the config-panel UI that actually calls `ns:CreateUserContainer` / `ns:DeleteUserContainer`) can proceed — this plan does not touch CDMTab.lua.

---
*Phase: 36-user-containers*
*Completed: 2026-09-21*
