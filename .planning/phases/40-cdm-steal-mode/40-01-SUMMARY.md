---
phase: 40-cdm-steal-mode
plan: 01
subsystem: ui
tags: [wow-addon, cooldown-viewer, c_cooldownviewer, event-driven-cache]

# Dependency graph
requires:
  - phase: 38-cooldown-trackers-code-complete
    provides: ns.cooldownGeneration / ns:MarkCooldownsDirty event-driven-cache idiom, copied here
  - phase: 35-cdm-tab-four-base-containers
    provides: ns.CONTAINERS registry with cdmViewerGlobal per base container
provides:
  - ns.stealSlots (one array per base container with a cdmCategoryName)
  - ns:RefreshStealMirror() (event-driven mirror rebuild, namespace-API-only)
  - cdmCategoryName field on the four base container defs in Core.lua
affects: [40-02 (Display.lua render of ns.stealSlots), 40-03 (CDM frame hide/restore, STEAL-08 audit)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mirror, not join: read Blizzard config via C_CooldownViewer namespace calls only, never touch a CDM frame"
    - "Event-driven cache rebuild (ns.cooldownGeneration idiom) applied to a second data source"

key-files:
  created: [StealMode.lua]
  modified: [Core.lua, TerribleBuffTracker.toc]

key-decisions:
  - "cdmCategoryName stored as a string name, resolved against Enum.CooldownViewerCategory at runtime, not referenced at file scope in Core.lua"
  - "Mirror entries are read-only, never enter ns.db.trackedBuffs, rebuilt from scratch every refresh"
  - "STEAL-05 recorded as partially met: mirror follows spec/talent/override/hotfix changes but not manual CDM re-categorisation or re-ordering, which needs a forbidden Blizzard mixin call"

patterns-established:
  - "Second file-local pcall-guarded event register helper (TryRegisterStealEvent), marked as a Phase 43 unification candidate with Core.lua's TryRegisterEvent"

requirements-completed: [STEAL-03, STEAL-05, STEAL-06]

# Metrics
duration: 5min
completed: 2026-09-21
---

# Phase 40 Plan 01: Mirror Data Source Summary

**New `StealMode.lua` builds `ns.stealSlots`, a read-only, event-driven mirror of the CDM's configured category sets via `C_CooldownViewer.GetCooldownViewerCategorySet`/`GetCooldownViewerCooldownInfo` only — no CDM frame is looked up, read, or written anywhere in this plan.**

## Performance

- **Duration:** ~5 min (commit span 15:24:36 to 15:27:53 local, plus final verification)
- **Tasks:** 4/4 completed
- **Files modified:** 3 (1 created: `StealMode.lua`; 2 modified: `Core.lua`, `TerribleBuffTracker.toc`)

## Accomplishments

- `Core.lua`'s four base container defs each carry `cdmCategoryName` (`TrackedBuff`/`TrackedBar`/`Essential`/`Utility`), a name resolved against `Enum.CooldownViewerCategory` at runtime, never at file scope.
- `StealMode.lua` builds `ns.stealSlots` (one array per base container with a `cdmCategoryName`) and `ns:RefreshStealMirror()`, which rebuilds those arrays by calling only `C_CooldownViewer.GetCooldownViewerCategorySet`/`GetCooldownViewerCooldownInfo` and `C_Spell.GetSpellInfo`, replicating Blizzard's own `isInvisible`/`isKnown`/`HideByDefault` filters.
- A dedicated event frame refreshes the mirror on `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `PLAYER_SPECIALIZATION_CHANGED`, `TRAIT_CONFIG_UPDATED`, `COOLDOWN_VIEWER_DATA_LOADED`, `COOLDOWN_VIEWER_TABLE_HOTFIXED`, `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED` (each registered through a pcall-guarded helper), plus `EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", ...)` for the "without a reload while the CDM settings window is open" path — never on a per-frame tick.
- `TerribleBuffTracker.toc` loads `StealMode.lua` after `Core.lua`/`Providers.lua` and before `EditModeFrames.lua`. `stylua --check .` exits 0.

## Task Commits

1. **Task 1: `cdmCategoryName` on the four base container defs** - `a4fb6cc` (feat)
2. **Task 2: `StealMode.lua` mirror builder** - `03389e4` (feat)
3. **Task 3: `StealMode.lua` refresh event frame** - `4793461` (feat)
4. **Task 4: register in TOC, run stylua** - `f3e55dd` (chore)

**Plan metadata:** SUMMARY.md not committed by this agent per orchestrator instructions.

## Files Created/Modified

- `StealMode.lua` - New file: `ns.stealSlots`, `ns:RefreshStealMirror()`, the mirror refresh event frame. The only file in the addon that names a CDM category/cooldown-info API for steal purposes.
- `Core.lua` - Added `cdmCategoryName` string field to the four base `ns.CONTAINERS` defs; extended the header comment by one sentence explaining why it's a name, not an enum value.
- `TerribleBuffTracker.toc` - Added `StealMode.lua` to the runtime file set, after `Providers.lua`, before `EditModeFrames.lua`.

## CDM Interaction Audit (STEAL-08 half)

Every CDM-related symbol referenced in this plan, classified:

| Symbol | File | Classification |
|---|---|---|
| `C_CooldownViewer.GetCooldownViewerCategorySet` | StealMode.lua | namespace call |
| `C_CooldownViewer.GetCooldownViewerCooldownInfo` | StealMode.lua | namespace call |
| `C_Spell.GetSpellInfo` | StealMode.lua | namespace call (not CDM-specific; pre-existing idiom from BuffEngine.lua) |
| `Enum.CooldownViewerCategory` / `Enum.CooldownSetSpellFlags` | Core.lua, StealMode.lua | enum table read, not a frame |
| `EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", ...)` | StealMode.lua | event-registry callback registration, not a frame method call or mixin call |
| `C_CooldownViewer.SetLayoutData` | StealMode.lua | named only in the header-comment prohibition list (no trailing `(`); zero call-form (`SetLayoutData(`) occurrences anywhere |

**Zero forbidden interactions. Zero frame-level interactions** (no `_G[...]` lookup, no frame method call, no frame-field read/write, no parenting) anywhere in this plan's diff.

## Mirror Refresh Events

`PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `PLAYER_SPECIALIZATION_CHANGED`, `TRAIT_CONFIG_UPDATED`, `COOLDOWN_VIEWER_DATA_LOADED`, `COOLDOWN_VIEWER_TABLE_HOTFIXED`, `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED` (all pcall-guarded on registration), plus the `CooldownViewerSettings.OnDataChanged` `EventRegistry` callback. No per-tick refresh; `ns:RefreshStealMirror` is never called from `Display.lua`, `ns:UpdateDisplay`, or any `OnUpdate` script.

## Decisions Made

- Kept `cdmCategoryName` as a plain string on the registry (not the enum value) so `Core.lua` never takes a file-scope dependency on `Enum.CooldownViewerCategory`, matching the plan's capability-check requirement.
- Used a sequential `local skip = false` / guarded reassignment pattern instead of `goto continue`, for readability and to avoid a Lua-version assumption about `goto` support.
- Left `CDMTab.lua`'s existing `stealMode` checkbox `OnClick` untouched — it is not in this plan's `files_modified` list; turning steal mode on mid-session will populate the mirror on the next qualifying event rather than instantly. This is consistent with the plan's scope boundary (Plan 03 owns the toggle-to-visibility wiring) and not a functional regression since nothing renders `ns.stealSlots` until Plan 02.

## Deviations from Plan

None functionally — all four tasks and both known-fidelity-limit documentation requirements (Risks text + code comment) were implemented exactly as specified. Two acceptance-criteria wordings in the plan did not match the code once written; both are pre-flagged by the plan's own review notes and `testing_reality` guidance as things to report rather than "fix":

**1. Task 1's `Enum.CooldownViewerCategory` grep criterion.** `grep -n 'Enum\.CooldownViewerCategory' Core.lua` still returns one hit (line 7) because the **pre-existing** Phase 35 header comment already named that enum path before this plan touched the file. Task 1 explicitly forbids rewriting existing header text ("extend... with one sentence"), so that line was left as-is; my added sentence was deliberately phrased to avoid contributing a second hit. Zero `Enum.CooldownViewerCategory` references exist in code (only in comments, one pre-existing).

**2. Task 3's "definition does not match the `RefreshStealMirror()` count" claim.** `grep -c 'RefreshStealMirror()' StealMode.lua` is 3, not 2, because `function ns:RefreshStealMirror()` — the definition line itself — also contains the literal substring `RefreshStealMirror()` (empty-arg Lua function defs always do). The plan's stated sub-claim that the definition "does not match this pattern" is incorrect, but the actual pass condition (`>= 2`) is still satisfied with room to spare, so no code change was needed.

The `SetLayoutData` verification criterion in the plan's "Verification" section was already reconciled by the plan itself (its parenthetical clarifies the real pass condition is the call-form `SetLayoutData(` returning zero hits, which it does — one bare-name hit exists in the header-comment prohibition list, exactly as Task 2 instructed).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `ns.stealSlots` and `ns:RefreshStealMirror()` are ready for Plan 02 to render through `Display.lua`'s existing bar/icon widgets (entries are shaped to match a tracker entry already).
- Plan 03 can build the CDM frame hide/restore work on top of this without touching this file's mirror logic; `StealMode.lua` remains the single file that will also carry the frame-hide code for the single-file `STEAL-08` diff-read.
- No blockers. The documented STEAL-05 partial-fidelity gap (manual CDM re-categorisation/re-ordering not mirrored) is carried forward as an accepted, documented limitation, not a defect to fix in this milestone.

---
*Phase: 40-cdm-steal-mode*
*Completed: 2026-09-21*

## Self-Check: PASSED

All created/modified files found on disk (`StealMode.lua`, `Core.lua`, `TerribleBuffTracker.toc`, this SUMMARY). All four task commits (`a4fb6cc`, `03389e4`, `4793461`, `f3e55dd`) found in `git log --all`.
