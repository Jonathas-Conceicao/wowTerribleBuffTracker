---
phase: 57-detailed-tracking-visibility-cross-spell-rules
plan: 02
subsystem: buff-engine
tags: [wow-addon, lua, visibility-modes, aura-state-cache, aura-driven-start]

# Dependency graph
requires:
  - phase: 57-detailed-tracking-visibility-cross-spell-rules
    plan: 01
    provides: "ns.endKeysBySpell, ns:RebuildDetailedRuleIndex (called from ns:RebuildCastIndex), ns:ApplyEndOnCast, the rebuild/event plumbing this plan extends"
provides:
  - "ns.auraState / ns.visibilityKeys / ns.visibilityAuraID (Core.lua), the per-tracker aura-state cache and its watch list"
  - "ns:VisibilityGate(key, entry) / ns:VisibilityShowsIn(containerKey) (BuffEngine.lua), the one allocation-free visibility predicate Display will call in Plan 03"
  - "ns:ReadableAuraTiming(aura, now) / ns:StartUserBuffFromAura(key, entry, aura) (BuffEngine.lua), the hybrid aura-driven start for a 'present' buff tracker"
  - "ns:RefreshAuraStates() (BuffEngine.lua), the cache refresh called from Core.lua (world entry, combat end, both ns:RebuildRankIndex exits) and from ns:OnUnitAura"
  - "ns:FillUserBuffProc(ownerKey, entry, now) (Providers.lua), the proc build shared by the cast path and the aura-driven start"
  - "the cast-evidence write in OnTrigger and the cross-spell absent-write in ns:ApplyEndOnCast"
affects: ["57-03 (Display wiring: SlotDraws, the icon/bar placeholder conditions, container activity all call ns:VisibilityGate/ns:VisibilityShowsIn)", "57-04 (already landed the entry.visibility dialog field this plan's runtime reads)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Runtime cache refreshed only at named event/rebuild boundaries (never per frame), explicit present/absent/unknown decision via if-branches (never an and/or chain) so an unreadable read cannot be misread as absence"
    - "A shared proc-build helper (ns:FillUserBuffProc) extracted from a provider's OnTrigger so the cast path and a second, aura-driven start path build identical procs with zero duplicated logic"
    - "Hybrid start trigger: an edge-to-present OR a readable real aura expiration, so a typed-duration fallback can restart once but a readable timing keeps re-arming correctly forever"

key-files:
  created: []
  modified:
    - Core.lua
    - Providers.lua
    - BuffEngine.lua

key-decisions:
  - "The visibility watch-list build (keys/auraIDs) was folded into ns:RebuildDetailedRuleIndex's existing pairs(ns.db.trackedBuffs) walk rather than a second walk, per the plan's explicit 'same walk' instruction -- one rebuild pass now produces both the DTRK-05 reverse index and the DTRK-03 watch list"
  - "ns.auraState invalidation on a changed watched ID runs in both directions (old ID differs from new, and new ID differs from old) before the tables are published, so an edited aura ID never keeps the old aura's cached state"
  - "ns:RefreshAuraStates' hybrid start writes ns.auraState[key] = present as a single statement, then performs the aura-driven start as a SEPARATE sibling statement after that block closes -- never nested inside it -- matching the plan's explicit ordering requirement"

patterns-established:
  - "A cached true/false/nil runtime state, refreshed only at named events and read through one allocation-free predicate, is now the addon's standard shape for 'show only while X' conditions"

requirements-completed: [DTRK-03]

# Metrics
duration: ~20min
completed: 2026-09-28
---

# Phase 57 Plan 02: Visibility Engine Summary

**Per-tracker aura-state cache (present/absent/unknown) refreshed only at world entry, combat end and rebuild boundaries; one allocation-free ns:VisibilityGate predicate; and a hybrid aura-driven start that lets a "present" buff tracker begin its timer from an aura sighting, including one cast by someone else, out of combat.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-28T17:03:59Z
- **Tasks:** 3
- **Files modified:** 3 (Core.lua, Providers.lua, BuffEngine.lua)

## Accomplishments
- `ns.auraState` (runtime `[key] = true|false`, nil = unknown), `ns.visibilityKeys` and `ns.visibilityAuraID` declared at file scope in Core.lua, alongside Plan 01's `ns.endKeysBySpell`.
- `ns:RebuildDetailedRuleIndex` now builds and publishes the visibility watch list in the same walk as the cross-spell reverse index, watching `ns:DetailedAuraID(entry) or entry.spellID` for every detailed USER_BUFF/USER_CD entry with `entry.visibility == "present"` or `"absent"`, and invalidates `ns.auraState` for any key whose watched ID changed (in either direction) before publishing.
- `ns:RebuildRankIndex` refreshes the cache at both its exits (the early `#rebuildOwners == 0` return and the natural end), each gated on `ns.displayInitialized`, after `ns.detailedRankFamilies` is final.
- `PLAYER_ENTERING_WORLD` reads the cache once after `InitDisplay`; `PLAYER_REGEN_ENABLED` thaws it before the existing cancellation scan -- combat end is the first readable moment.
- `ns:FillUserBuffProc(ownerKey, entry, now)` (Providers.lua) holds the unchanged aliveBuffs decision and proc build extracted from `OnTrigger`, now shared by the cast path and the aura-driven start. `OnTrigger` calls it and, for a visibility-gated key, writes `ns.auraState[ownerKey] = true` -- the tracker's own cast is evidence its aura went up.
- Five new BuffEngine.lua methods: `ns:VisibilityGate(key, entry)` (the one predicate: nil/true/false), `ns:VisibilityShowsIn(containerKey)`, `ns:ReadableAuraTiming(aura, now)` (issecretvalue-gated aura timing extraction, no read of its own), `ns:StartUserBuffFromAura(key, entry, aura)` (InCombatLockdown-guarded, builds via `ns:FillUserBuffProc`), and `ns:RefreshAuraStates()` -- the refresh itself: frozen in combat and while secret, WR-04 "check both" for a cover-all-ranks aura-ID tracker's `ns.detailedRankFamilies[key]` list, and the hybrid start gate (edge-to-present OR readable real timing).
- `ns:OnUnitAura` calls the refresh after the isFullUpdate suppression and before the cancellation scan. `ns:ClearTrackerRuntimeState` clears the cached state per key. `ns:ApplyEndOnCast`'s USER_BUFF branch now also marks every visibility-gated buff a cross-spell rule lists as absent, whether or not its timer was running, as a sibling statement after the existing timer-clear block.
- All five new BuffEngine.lua functions, `ns:FillUserBuffProc`, and the extended `ns:RebuildDetailedRuleIndex` are allocation-free on the hot paths: zero `{`, zero `pairs(`/`ipairs(` in the render/cast/event paths (numeric loops only; the rebuild-time walk in `ns:RebuildDetailedRuleIndex` is the one place `pairs()` runs, and only at rebuild time, matching the existing DTRK-05 convention).

## Task Commits

Each task was committed atomically:

1. **Task 1: Visibility index, the aura-state cache table and the refresh call sites (Core.lua)** - `d392774` (feat)
2. **Task 2: Extract ns:FillUserBuffProc from OnTrigger; the cast-evidence write** - `c0a2ec9` (feat)
3. **Task 3: The aura-state refresh, the visibility predicate and the aura-driven start (BuffEngine.lua)** - `627a4c5` (feat)

_No plan-metadata commit -- the orchestrator owns STATE.md/ROADMAP.md updates for this plan._

## Files Created/Modified
- `Core.lua` - `ns.auraState`/`ns.visibilityKeys`/`ns.visibilityAuraID` declarations; `ns:RebuildDetailedRuleIndex` extended to build and publish the visibility watch list with cache invalidation; `ns:RebuildRankIndex`'s two exits each call `ns:RefreshAuraStates()` behind `ns.displayInitialized`; `PLAYER_ENTERING_WORLD`/`PLAYER_REGEN_ENABLED` event-handler refresh calls
- `Providers.lua` - `ns:FillUserBuffProc(ownerKey, entry, now)` extracted above `OnTrigger`; `OnTrigger` calls it and writes the cast-evidence `ns.auraState[ownerKey] = true`
- `BuffEngine.lua` - `ns:VisibilityGate`, `ns:VisibilityShowsIn`, `ns:ReadableAuraTiming`, `ns:StartUserBuffFromAura`, `ns:RefreshAuraStates` added between `ns:ScanActiveTimersForCancellation` and `ns:OnUnitAura`; `ns:OnUnitAura` calls the refresh; `ns:ClearTrackerRuntimeState` clears `ns.auraState[key]`; `ns:ApplyEndOnCast`'s USER_BUFF branch marks visibility-gated buffs absent

## Decisions Made
- The visibility-watch-list build was folded into `ns:RebuildDetailedRuleIndex`'s existing walk (per the plan's explicit instruction), rather than a second `pairs()` pass over `ns.db.trackedBuffs` -- one rebuild now produces both DTRK-05's reverse index and DTRK-03's watch list.
- `ns.auraState` invalidation on a changed watched ID checks both directions (old map vs new, new map vs old) before the tables are published, exactly matching the plan's "in both directions" wording -- an edited aura ID cannot keep the old aura's cached state.
- No deviations from the plan's documented design choices (cache shape, frozen-in-combat rule, cast-evidence write, hybrid aura-driven start gate, the predicate's nil/true/false contract) were needed -- every helper and precedent the plan referenced (`ns:ReadPlayerAura`, `ns:DetailedAuraID`, `ns.detailedRankFamilies`, Plainsrunning's `RacialAuraTrigger`/`GetAuraAppliedAt`) already existed in the current tree.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
The `Edit` tool's exact-string match failed once on `ns:ApplyEndOnCast` (a tab-vs-space mismatch introduced when the plan text was copied through the Read tool's line-numbered output). Recovered by matching and replacing the exact byte sequence (tabs, CRLF) with a small Node script instead, then re-verified the result against the file on disk before continuing. No behavioral impact; not a plan deviation, a tooling workaround.

## User Setup Required
None - no external service configuration required.

## Verification

All three task automated gates passed in full on first re-run after the fix above:
- Task 1: `ns.auraState`/`ns.visibilityKeys`/`ns.visibilityAuraID` declarations, `ns:RebuildDetailedRuleIndex`'s publish/invalidate shape, `ns:RebuildRankIndex`'s two `ns:RefreshAuraStates()` calls each behind `ns.displayInitialized`, event-handler call-site ordering (`PLAYER_ENTERING_WORLD` after `InitDisplay`, `PLAYER_REGEN_ENABLED` before the cancellation scan), no added `OnUpdate` mention, stylua clean, CRLF/EOL gates.
- Task 2: `ns:FillUserBuffProc` shape (unchanged aliveBuffs decision, zero `{`), `OnTrigger`'s call/cast-evidence-write/zero-`{`/no-direct-`AcquireProc` shape, Plan 01's `ns:ApplyEndOnCast` call preserved, aura-read gate PASS, stylua clean, CRLF/EOL gates.
- Task 3: all five function signatures declared once; `ns:ReadableAuraTiming`'s issecretvalue-before-comparison order; `ns:VisibilityGate`'s gating and zero aura reads; `ns:VisibilityShowsIn`'s numeric loop; `ns:StartUserBuffFromAura`'s InCombatLockdown guard and proc build; `ns:RefreshAuraStates`' combat/secret early returns, WR-04 cover-all-ranks branch, single `ns.auraState[key] = present` write followed by the hybrid start as a separate sibling statement, `ns:UpdateDisplay()` call; `ns:OnUnitAura`'s call ordering; `ns:ClearTrackerRuntimeState`'s per-key clear; `ns:ApplyEndOnCast`'s sibling `ns.auraState[k] = false` write at matching indentation; zero `{`/`pairs(` throughout; no added `OnUpdate` mention; aura-read gate PASS plus its 30-case selftest; stylua clean; CRLF/EOL gates.

Plan-level verification also confirmed: `node scripts/migrate-dryrun.js --selftest` reports 7 cases (unchanged).

In-game verification (a "present"/"absent" tracker actually showing/hiding correctly across combat, world entry and an aura sighting from another player's cast; the aura-driven start firing exactly once per edge and re-arming correctly from readable real timing; a cross-spell rule's absent-write showing an "absent" reminder at once in combat) requires a live WoW client and Plan 03's Display wiring -- both are human/future-plan verification, no WoW client is available in this environment.

## Next Phase Readiness
- The engine half of DTRK-03 is complete: `ns.auraState`, `ns:VisibilityGate`, `ns:VisibilityShowsIn` and the aura-driven start are all in place and dormant from Display's perspective until Plan 03 wires them into `SlotDraws`, the icon/bar placeholder conditions and container activity.
- Plan 04 already landed the `entry.visibility` dialog field (57-04, prior to this plan in commit order) -- this plan's runtime is what makes that field's save meaningful; no tracker drew a "present"/"absent" state differently before this plan, and none will visibly change until Plan 03 lands the Display side.
- No blockers.

## Self-Check: PASSED

Commits `d392774`, `c0a2ec9`, `627a4c5` found in `git log --oneline -5`. `Core.lua`, `Providers.lua`, `BuffEngine.lua` modifications confirmed on disk via the automated verify gates run above (every `grep -q`/`awk` assertion checked directly against the current file content, all three task gates re-run to completion with `echo ok` as the final line). `node scripts/aura-read-gate.js --selftest` reports 30 cases; `node scripts/migrate-dryrun.js --selftest` reports 7 cases.

---
*Phase: 57-detailed-tracking-visibility-cross-spell-rules*
*Completed: 2026-09-28*
