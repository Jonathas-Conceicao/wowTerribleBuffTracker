---
phase: 37-add-panel-rank-grouping
plan: 02
subsystem: core
tags: [wow-addon, buff-engine, providers, rank-dispatch, cooldown-tracker]

# Dependency graph
requires:
  - phase: 37-add-panel-rank-grouping (Plan 01)
    provides: ns.rankIndex, ns.rankFamilies, ns:RebuildRankIndex, ns.CLIENT_HAS_SPELL_RANKS
provides:
  - "ns:AddTrackedBuff(spellID, duration, label, opts) — trackerType, section, coverAllRanks via opts"
  - "ns:AddTrackedBuff / ns:RemoveTrackedBuff call ns:RebuildRankIndex on success (nil-guarded)"
  - "ns:StartAllPreviewTimers skips trackerType == \"cooldown\" entries"
  - "UserSpellProviderMixin:OnTrigger rank-index fallback on trackedBuffs miss, owner-keyed proc, shared aliveBuffs family, cooldown skip"
affects: [37-03-add-dialog, 38-cooldown-rendering]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "opts trailing-table parameter pattern for backward-compatible signature extension"
    - "Rank fallback as a second table lookup only on the direct-lookup miss path — zero added cost on a hit"
    - "Shared-reference aliveBuffs (ns.rankFamilies[ownerKey]) instead of a per-proc copy, documented as read-only via ipairs"
    - "Two-seam cooldown skip (OnTrigger + StartAllPreviewTimers) naming Phase 38 as the seam owner"

key-files:
  created: []
  modified: [BuffEngine.lua, Providers.lua]

key-decisions:
  - "Committed as two atomic commits split by file (BuffEngine.lua: Tasks 1+3; Providers.lua: Task 2) rather than four commits matching plan task numbers 1:1, since Tasks 1 and 3 land in the same file and each commit is independently loadable and passes stylua --check"
  - "Reworded a code comment from 'no pcall' to 'no protected call' so the literal acceptance grep (pcall|C_SpellBook, expected zero hits inside OnTrigger) is not tripped by the word appearing only in prose — no behavioral difference, same intent documented"

requirements-completed: [ADD-01, ADD-02, RANK-01, RANK-02]

duration: ~10min
completed: 2026-09-21
---

# Phase 37 Plan 02: Tracker Type, Container Choice & Rank Dispatch Summary

**Adds the `opts` table to `ns:AddTrackedBuff` (trackerType/section/coverAllRanks) and wires the cast path in `UserSpellProviderMixin:OnTrigger` to fall back to `ns.rankIndex` on a miss, so any rank of a covered spell drives the one tracker filed under the owner's ID — while cooldown-type trackers are created but deliberately render nothing, per Phase 38's ownership.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-09-21T17:10:22Z
- **Tasks:** 4 (3 code tasks + 1 formatting/verification task)
- **Files modified:** 2 (BuffEngine.lua, Providers.lua)

## Accomplishments
- `ns:AddTrackedBuff(spellID, duration, label, opts)` — four-parameter signature, three-argument callers (the sole existing `CDMTab.lua` call site) remain valid unchanged. `opts.trackerType`, `opts.section` (with the D-05 `"hidden"` fallback preserved), and `opts.coverAllRanks` (stores `true` or nothing, never `false`) are all optional and additive — no `schemaVersion` bump.
- `ns:AddTrackedBuff` and `ns:RemoveTrackedBuff` both call `ns:RebuildRankIndex()` on their success path, nil-guarded behind `if ns.RebuildRankIndex then` — a newly covered tracker works on the very next cast.
- `ns:StartAllPreviewTimers` skips `trackerType == "cooldown"` entries on the same `if` condition as the existing `"hidden"` check.
- `UserSpellProviderMixin:OnTrigger` tries `ns.rankIndex[spellID]` only after the direct `trackedBuffs[spellID]` lookup misses, re-resolves the entry under the owner key, returns a proc whose `key` and `spellID` both derive from the owner (never the cast ID), assigns `aliveBuffs` to the shared `ns.rankFamilies[ownerKey]` reference when one exists, and returns `nil` for `trackerType == "cooldown"` entries.

## Task Commits

Each task was committed atomically, grouped by file since Tasks 1 and 3 share `BuffEngine.lua`:

1. **Tasks 1+3: `BuffEngine.lua` — opts on AddTrackedBuff, rank-index invalidation, cooldown preview skip** - `2eab66f` (feat)
2. **Task 2: `Providers.lua` — rank fallback and cooldown skip in `UserSpellProviderMixin:OnTrigger`** - `84a5d57` (feat)
3. **Task 4: format** - no separate commit; `stylua` (no flags, repo-root config) produced zero additional diff after both edits, so `stylua --check .` exiting 0 is folded into commit `84a5d57`.

**Plan metadata:** not committed per orchestrator instruction (SUMMARY.md left uncommitted).

## Files Created/Modified
- `BuffEngine.lua` — `ns:AddTrackedBuff` gains the `opts` parameter, writes `trackerType`/`section`/`coverAllRanks`, extends the confirmation print with the tracker type, and calls `ns:RebuildRankIndex()` (nil-guarded) on success; `ns:RemoveTrackedBuff` calls the same nil-guarded rebuild; `ns:StartAllPreviewTimers` adds the cooldown skip to its existing `"hidden"` condition.
- `Providers.lua` — `UserSpellProviderMixin:OnTrigger` adds the rank-index fallback, the cooldown skip, owner-keyed `key`/`spellID`, and the shared-reference `aliveBuffs` family. `GetDisplayInfo` untouched.

## Decisions Made
- Split commits by file rather than by the plan's four task numbers, since Tasks 1 and 3 are both edits inside `ns:AddTrackedBuff`'s neighborhood of `BuffEngine.lua` and Task 4 (format) produced no incremental diff to commit separately — each of the two resulting commits is a real, independently loadable, `stylua --check`-clean state.
- Reworded a comment to avoid the literal substring `pcall` (used only in prose, meaning "no protected call is made here") after noticing it tripped the acceptance grep `pcall|C_SpellBook` meant to catch an actual protected call or spellbook API call inside `OnTrigger`. No behavioral change — same intent, different wording, confirmed the reworded grep now returns zero hits.

## Deviations from Plan

None that changed behavior. Commit granularity (by file, not by the plan's task numbers) is a mechanical grouping choice, documented above — the plan's per-task acceptance criteria were still verified individually before either commit.

One acceptance criterion needed a wording tweak, not a code change: the plan's literal `grep -n 'pcall\|C_SpellBook' Providers.lua` acceptance check would have matched a comment containing the word "pcall" in prose ("No API call, no pcall, no allocation"), even though no actual `pcall` or `C_SpellBook` call exists in `OnTrigger`. Reworded the comment rather than treat the false-positive grep hit as a code defect.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 03 (`CDMTab.lua`, the add dialog) can now call `ns:AddTrackedBuff(spellID, duration, label, { trackerType = ..., section = ..., coverAllRanks = ... })` to wire its three new controls (buff/cooldown, container, cover-all-ranks checkbox) directly to persisted state, with no further engine changes required.
- Phase 38 (cooldown rendering) has both of its stated seams already in place and commented: the `OnTrigger` cooldown skip in `Providers.lua` and the `StartAllPreviewTimers` cooldown skip in `BuffEngine.lua`, each naming Phase 38 as the owner of the removal.
- In-game verification of `opts`-less backward compatibility (add a spell via the existing dialog, `/reload`, confirm it still lands in Not Displayed) is available to a human on the Forever client now; rank and cooldown-type behavior have no user-reachable entry point until Plan 03 lands, per the plan's own verification section.
- `luac` is not on this machine's PATH; `stylua --check .` (exit 0) was the syntax gate used, confirmed after both commits.

---
*Phase: 37-add-panel-rank-grouping*
*Completed: 2026-09-21*
