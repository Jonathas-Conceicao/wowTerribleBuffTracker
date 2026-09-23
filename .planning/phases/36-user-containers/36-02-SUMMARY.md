---
phase: 36-user-containers
plan: 02
subsystem: ui
tags: [lua, wow-addon, cdm, display, hot-path]

requires:
  - phase: 36-01-registry-and-hooks
    provides: "ns.CONTAINERS dynamic registry, ns:AttachContainerRuntime/ns:DetachContainerRuntime nil-guarded dispatch calling ns.AllocateContainerRuntime(def)/ns.ReleaseContainerRuntime(key) by convention"
provides:
  - "ns.AllocateContainerRuntime(def) — single allocation site for pools/timersByContainer/cachedSettings per container key, idempotent, calls RefreshContainerSettings"
  - "ns.ReleaseContainerRuntime(key) — single release site, hides+unparents pooled frames then drops all four per-key tables, safe on an already-unregistered key"
  - "ns:InitDisplay nil-guard on def.cdmViewerGlobal so a user container without a CDM viewer never indexes _G[nil]"
  - "ns:UpdateDisplay fallback branch nil-guard on pools[def.key] as defence in depth against reordering"
affects: [36-03-editmode-runtime, 36-04-cdmtab-ui-and-hooks]

tech-stack:
  added: []
  patterns:
    - "Single allocation/release site pattern for per-key hot-path state: file-scope load and runtime creation both funnel through the same idempotent allocator, deletion through the same releaser, so UpdateDisplay/RenderBarContainer/RenderIconContainer never construct a table"
    - "Frames are hidden + unparented on release, not destroyed (WoW API constraint) — the pool table becomes unreachable, not the frames themselves"

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "ns.AllocateContainerRuntime and ns.ReleaseContainerRuntime placed immediately after RefreshContainerSettings/its export and before the pool getters (GetBar/GetIcon), per the plan's explicit ordering — the file-scope allocation loop for the four base containers now lives directly below both function definitions instead of at the top of the file."
  - "ReleaseContainerRuntime looks up pools[key]/etc. directly by key rather than walking ns.CONTAINERS, matching Core.lua's deletion ordering (unregister def, then detach runtime) so a call for an already-unregistered key is a normal case, not an error path."

patterns-established:
  - "Pattern: any future per-container hot-path table follows the same shape — declared once at module scope as an empty table, keys added only inside ns.AllocateContainerRuntime, keys dropped only inside ns.ReleaseContainerRuntime, never inside a render/update function."

requirements-completed: [CONT-04, CONT-06]

duration: 25min
completed: 2026-09-21
---

# Phase 36 Plan 02: Per-Container Runtime Table Lifecycle Summary

**Single allocation/release site (`ns.AllocateContainerRuntime`/`ns.ReleaseContainerRuntime`) for `pools`, `timersByContainer`, `cachedSettings` and `ns.containerTooltipsShown`, replacing the file-scope-only loop so runtime-created user containers get their per-key hot-path state without any table constructor in the render path.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-21T13:00Z (approx, first file read)
- **Completed:** 2026-09-21T16:17:56Z
- **Tasks:** 3 (allocation/release functions, nil-safety guards, format+verify)
- **Files modified:** 1

## Accomplishments
- `ns.AllocateContainerRuntime(def)` is now the only place `pools[key]` and `timersByContainer[key]` are constructed — idempotent via `or {}`, called once per base container at file-scope load and once per user container from Core.lua's `ns:AttachContainerRuntime` at rehydration/creation.
- `ns.ReleaseContainerRuntime(key)` hides and unparents every pooled frame (WoW frames cannot be destroyed) then drops all four per-key tables, and is safe to call for a key already removed from `ns.CONTAINERS`.
- `ns:InitDisplay`'s CDM viewer lookup now guards on `def.cdmViewerGlobal` existing, so a user container (which has none) never indexes `_G[nil]`.
- `ns:UpdateDisplay`'s no-frame/no-settings fallback branch guards a possibly-nil `pools[def.key]` — defence in depth, since Core.lua's deletion ordering already prevents this in practice.
- Confirmed zero table constructors remain in `ns:UpdateDisplay`, `RenderBarContainer`, and `RenderIconContainer` after the edit (baseline was already 0; the new allocation code lives entirely outside the render path, before `GetBar`/`GetIcon`).

## Task Commits

Each task was committed atomically:

1. **Task 1+2: Allocation/release functions + nil-safety guards** - `4ee325b` (feat) — both tasks landed in one commit since they are one coherent, small, testable unit (task 3 was format/verify only, no separate diff).

_No separate commit for Task 3 ("Format and verify") — `stylua` was run before the Task 1+2 commit was created, so there was nothing left to format afterward._

## Files Created/Modified
- `Display.lua` - Added `ns.AllocateContainerRuntime`/`ns.ReleaseContainerRuntime`, moved the file-scope base-container loop below them, added nil-guards in `ns:InitDisplay` and `ns:UpdateDisplay`

## Decisions Made
- Combined the plan's Task 1 and Task 2 into a single commit rather than two, because both are small, tightly related changes to the same lifecycle concern (allocation/release + the nil-safety it makes necessary) and splitting them would have produced an intermediate commit where `ns:UpdateDisplay` and `ns:InitDisplay` were still relying on assumptions the plan itself says are no longer safe once the registry is unbounded. Task 3 (format+verify) is not a separate code change, so it has no commit of its own — `stylua` ran as part of finishing Task 1+2's diff.

## Deviations from Plan

None - plan executed exactly as written. All six Task 1 acceptance-criteria commands, all four Task 2 acceptance-criteria commands, and all four plan-level Verification commands were run literally and returned exactly the values the plan predicted (including the `ipairs(ns.CONTAINERS)` count staying at `5` and the `{}`-below-`RenderBarContainer` count staying at `0`).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Display.lua's half of the CONT-04/CONT-06 hook contract is complete and matches the exact `(def)` / `(key)` call signatures Core.lua's `ns:AttachContainerRuntime`/`ns:DetachContainerRuntime` already dispatch to.
- Plan 03 (EditModeFrames runtime) and Plan 04 (CDMTab UI and hooks) can now rely on `ns.AllocateContainerRuntime`/`ns.ReleaseContainerRuntime` as the established pattern for their own per-container hot-path tables.
- No in-game verification was possible or attempted in this plan (correct per the plan's own Verification section — nothing calls these functions end-to-end until Plan 04 pairs the hook dispatch with UI).

---
*Phase: 36-user-containers*
*Completed: 2026-09-21*
