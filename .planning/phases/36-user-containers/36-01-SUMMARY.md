---
phase: 36-user-containers
plan: 01
subsystem: ui
tags: [lua, wow-addon, cdm, edit-mode, savedvariables]

requires:
  - phase: 35-container-registry
    provides: "ns.CONTAINERS single ordered registry, ns.CONTAINER_BY_KEY, kind-branched consumers"
  - phase: 35.1-config-panel
    provides: "ns.db.containerSettings per-container settings table, ns.tbtConfigContainerSection seam, no-schemaVersion-bump precedent"
provides:
  - "ns.db.userContainers / ns.db.nextContainerId persistence, seeded idempotently, no schemaVersion bump"
  - "ns:GenerateContainerKey with three collision guards (user-prefix, monotonic counter, live re-check)"
  - "ns:RegisterContainerDef / ns:UnregisterContainerDef mutating ns.CONTAINERS and ns.CONTAINER_BY_KEY"
  - "ns:RehydrateUserContainers called from ADDON_LOADED before the containerSettings registry pass"
  - "ns:AttachContainerRuntime / ns:DetachContainerRuntime nil-guarded hook dispatch (inert until Plans 02-04)"
  - "ns:CreateUserContainer / ns:DeleteUserContainer / ns:CountContainerTrackers public API"
  - "ns.EnsureContainerSettings(def) extracted from the ADDON_LOADED loop, single settings-defaults constructor"
affects: [36-02-display-runtime, 36-03-editmode-runtime, 36-04-cdmtab-ui-and-hooks]

tech-stack:
  added: []
  patterns:
    - "Registry mutation via table.insert/table.remove on ns.CONTAINERS + mirrored ns.CONTAINER_BY_KEY writes, never one without the other"
    - "Nil-guarded cross-file hook dispatch (ns:AttachContainerRuntime/ns:DetachContainerRuntime) as the sole Core -> Display/EditModeFrames/CDMTab seam, so Wave 1 lands standalone"
    - "Rehydration and runtime creation share one attach path (ns:AttachContainerRuntime) -- one code path to get wrong, not two"

key-files:
  created: []
  modified:
    - Core.lua

key-decisions:
  - "ns.EnsureContainerSettings(def) extracted verbatim from the existing ADDON_LOADED loop so the defaults-table constructor appears exactly once in the file, guaranteeing a runtime-created container never aliases another container's settings table."
  - "ns:RehydrateUserContainers() placed between the ns.db.containerSettings guard and the ipairs(ns.CONTAINERS) settings pass, per the plan's load-bearing ordering requirement -- verified by line-number comparison, not just visual inspection."
  - "ns:AttachContainerRuntime/ns:DetachContainerRuntime hook dispatch left as duplicate per-call if-guards (not collapsed into a shared local wrapper) to match the plan's literal per-function call sequence; this makes the RebuildContainerSectionDefs grep-count acceptance criterion read 4 instead of 2 after stylua's mandatory multi-line if formatting -- documented as a deviation below, not a functional gap."

patterns-established:
  - "Pattern: container def mutation always touches ns.CONTAINERS (ordered array, order is user-visible) and ns.CONTAINER_BY_KEY (lookup) together, in RegisterContainerDef/UnregisterContainerDef only."
  - "Pattern: every subsystem hook Core calls into is double-guarded -- once on the hook function existing (subsystem file loaded), and each hook is independently required to no-op if its own runtime state hasn't initialised yet."

requirements-completed: [CONT-04, CONT-05, CONT-06]

duration: 35min
completed: 2026-09-21
---

# Phase 36 Plan 01: Dynamic Registry, Key Generation and Rehydration Summary

**Made `ns.CONTAINERS` dynamic: `ns.db.userContainers` persists user-created container records, `ns:GenerateContainerKey` issues collision-proof `"user" .. id` keys off a never-decrementing counter, and `ns:RehydrateUserContainers()` rebuilds the registry's user-container tail at `ADDON_LOADED` before any consumer loops it.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-21T15:56:00Z (approx, from conversation start)
- **Completed:** 2026-09-21T16:14:09Z (commit timestamp)
- **Tasks:** 3 (registry/persistence/key-gen, create/delete API + hook dispatch, format/verify)
- **Files modified:** 1

## Accomplishments
- `ns.db.userContainers` (array, creation order) and `ns.db.nextContainerId` (monotonic, never decremented) persist user containers with no `schemaVersion` bump, following the Phase 35.1 `stealMode` precedent.
- `ns:GenerateContainerKey` implements all three collision guards from the plan: `"user"` prefix can never collide with a base or CDM-tab-section key, the counter never reissues a deleted container's key, and a live re-check loop survives a hand-edited SavedVariables file.
- `ns:RegisterContainerDef` / `ns:UnregisterContainerDef` are the only place `ns.CONTAINERS` and `ns.CONTAINER_BY_KEY` are mutated at runtime; `isUser = true` is set in exactly one place, giving `ns:DeleteUserContainer` a reliable base-container guard.
- `ns:RehydrateUserContainers()` is wired into `ADDON_LOADED` at the exact load-bearing position the plan specifies (see below), and shares its attach path with runtime creation via `ns:AttachContainerRuntime`.
- `ns:AttachContainerRuntime` / `ns:DetachContainerRuntime` give Core one nil-guarded seam into `Display.lua` / `EditModeFrames.lua` / `CDMTab.lua`, all inert (no-op) until Plans 02-04 land, so Wave 1 loads cleanly on its own.
- `ns:CreateUserContainer` / `ns:DeleteUserContainer` / `ns:CountContainerTrackers` complete the public registry API: create rejects invalid `kind`, stacks default positions downward, and reuses `ns.EnsureContainerSettings`; delete refuses non-user containers, moves trackers to `"hidden"` before unregistering, unregisters before detaching runtime, and re-seeds preview timers when the config panel is open.

## Task Commits

All three tasks (registry/persistence/key-gen, create/delete API + hook dispatch, format/verify) were implemented as one continuous, interdependent edit pass against `Core.lua` — Task 2's functions call Task 1's directly, and Task 3 (stylua) was run against the combined result before the single commit below. Splitting after the fact would have required reconstructing intermediate states via patch surgery, which risked corrupting the CRLF line endings this repo has previously lost silently (see `CLAUDE.md`'s stylua history). One atomic commit was made instead:

1. **Tasks 1-3: registry, key generation, rehydration, create/delete API, hook dispatch, format** - `b804809` (feat)

**Plan metadata:** not committed per orchestrator instruction (SUMMARY.md is written but not committed by this executor).

## Files Created/Modified
- `Core.lua` - Extracted `ns.EnsureContainerSettings`; added `ns.db.userContainers`/`ns.db.nextContainerId` seeding, `ns:GenerateContainerKey`, `ns:RegisterContainerDef`/`ns:UnregisterContainerDef`, `ns:RehydrateUserContainers`, `ns:AttachContainerRuntime`/`ns:DetachContainerRuntime`, `ns:CountContainerTrackers`, `ns:CreateUserContainer`, `ns:DeleteUserContainer`; wired `ns:RehydrateUserContainers()` into `ADDON_LOADED` at the required position.

## Decisions Made
- Extracted the containerSettings defaults/backfill loop into `ns.EnsureContainerSettings(def)` verbatim, per Task 1a, so the constructor appears exactly once and a runtime-created container's settings table is guaranteed fresh.
- Kept `ns:AttachContainerRuntime`/`ns:DetachContainerRuntime`'s `RebuildContainerSectionDefs` guard as two independent per-function `if ns.X then ... end` blocks (matching the plan's literal call-order wording) rather than factoring them into a shared local helper — see Deviations below for the one acceptance-criterion count this affects.

## Deviations from Plan

### Verification-criterion mismatch (not a functional deviation)

**1. `grep -c 'ns.RebuildContainerSectionDefs' Core.lua` returns 4, not the plan's expected 2**
- **Found during:** Task 3 (format and verify)
- **Issue:** The plan's acceptance criterion expects this grep to return 2 ("attach and detach"). `RebuildContainerSectionDefs` is called once from `ns:AttachContainerRuntime` and once from `ns:DetachContainerRuntime`, each behind its own `if ns.RebuildContainerSectionDefs then ... end` guard. I initially wrote both guards single-line (`if ns.RebuildContainerSectionDefs then ns.RebuildContainerSectionDefs() end`), which would satisfy the count (1 matching line per call site = 2 total), but running the mandatory `stylua .` (CLAUDE.md hard rule, no flags, repo-root config) expanded both back to the standard multi-line `if...then / body / end` form used everywhere else in this file. That gives 2 matching lines per call site (the `if` line and the call line) x 2 call sites = 4.
- **Resolution:** Left stylua's canonical multi-line formatting in place rather than fighting the formatter, since CLAUDE.md's stylua rule is a hard constraint and this repo has a documented history (stylua.toml's own comment) of silent CRLF/LF corruption from working around it. All *functional* acceptance criteria pass: `ns.RebuildContainerSectionDefs` is called exactly twice in the file (once per hook-dispatch function, in the documented order), every one of the other five hooks (`AllocateContainerRuntime`, `CreateContainerFrames`, `AddContainerSection`, `RemoveContainerSection`, `DestroyContainerFrames`, `ReleaseContainerRuntime`) is guarded exactly once as its own `if ns.X then` line, and `ns:UnregisterContainerDef(key)` runs strictly before `ns:DetachContainerRuntime(key)` in `ns:DeleteUserContainer`.
- **Files modified:** Core.lua (no additional change beyond the already-committed implementation)
- **Verification:** `grep -c 'ns.RebuildContainerSectionDefs' Core.lua` → `4` (documented mismatch); all other Task 1/2/3 acceptance commands pass as specified.
- **Committed in:** `b804809` (part of the single task commit)

### Self-inflicted check trap avoided

**2. Reworded a comment that would have falsely tripped `grep -c 'isUser = true'`**
- **Found during:** Task 1 (writing `ns:RegisterContainerDef`)
- **Issue:** My explanatory comment above `ns:RegisterContainerDef` originally read `` `isUser = true` is set HERE AND NOWHERE ELSE ``, which is itself a second textual match for the literal string the plan's acceptance grep searches for (`grep -c 'isUser = true' Core.lua` expects exactly `1`, matching the `<testing_reality>` warning about writing the searched-for literal into comments).
- **Fix:** Reworded to "The isUser flag below is set HERE AND NOWHERE ELSE" so the comment no longer contains the literal `isUser = true` string.
- **Files modified:** Core.lua
- **Verification:** `grep -c 'isUser = true' Core.lua` → `1`.
- **Committed in:** `b804809`

---

**Total deviations:** 1 verification-criterion mismatch documented (no functional impact), 1 self-inflicted check trap caught and fixed before commit.
**Impact on plan:** No scope creep, no architectural changes. All `must_haves.truths`, all artifact/key_link requirements, and every acceptance command except the one documented grep-count mismatch pass exactly as specified.

## Issues Encountered

**Edit tool old_string matching required 2-tab indentation, not 3.** When reading the `ADDON_LOADED` branch via the `Read` tool's `cat -n`-style line-numbered output, the visual tab depth was easy to miscount by one level against the function's actual nesting (the branch body inside `eventFrame:SetScript("OnEvent", function(...) if event == "ADDON_LOADED" then` is 2 tabs deep, not 3). Two `Edit` calls failed silently with "String to replace not found" before I re-derived the exact byte content via `od -c` and matched on 2 tabs. No file corruption resulted — the failed `Edit` calls made no changes.

## User Setup Required

None - no external service configuration required. No in-game verification applies to this plan (per the plan's own Verification section: "No in-game check in this plan").

## Next Phase Readiness

- `Core.lua`'s registry API (`ns:CreateUserContainer`, `ns:DeleteUserContainer`, `ns:CountContainerTrackers`, `ns:AttachContainerRuntime`/`ns:DetachContainerRuntime`) is in place and inert — no consumer calls it yet, and the addon loads cleanly with zero user containers (fresh `ns.db.userContainers = {}`).
- Plans 02 (Display.lua), 03 (EditModeFrames.lua) and 04 (CDMTab.lua) each need to: (a) convert their file-scope registry loops into callable functions matching the hook names this plan already dispatches to (`ns.AllocateContainerRuntime`, `ns.CreateContainerFrames`, `ns.RebuildContainerSectionDefs`, `ns.AddContainerSection`, `ns.RemoveContainerSection`, `ns.DestroyContainerFrames`, `ns.ReleaseContainerRuntime`), and (b) be safe to call before their own subsystem has initialised (Core's guards only check the hook exists, not that the subsystem is ready).
- No blockers identified.

---
*Phase: 36-user-containers*
*Completed: 2026-09-21*
