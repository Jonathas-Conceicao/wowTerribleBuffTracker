---
phase: 38-cooldown-trackers
plan: 01
subsystem: buff-engine
tags: [wow-addon, secret-values, event-driven-invalidation, cooldown-manager]

# Dependency graph
requires:
  - phase: 37-add-panel-rank-grouping
    provides: entry.trackerType field, CDMTab.lua add dialog buff/cooldown choice, rank family resolution
provides:
  - ns.cooldownGeneration / ns.trackerGeneration invalidation counters plus their MarkXDirty setters
  - pcall-guarded SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_CHARGES registration (TryRegisterEvent helper)
  - removal of both Phase 37 "cooldown skip" seams in Providers.lua and BuffEngine.lua
  - the three tracker-mutation choke points (AddTrackedBuff/RemoveTrackedBuff/SetBuffSection) now stamp ns.trackerGeneration
affects: [38-02-display-rendering]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generation counters as invalidation stamps instead of storing secret-derived state"
    - "TryRegisterEvent(frame, eventName) — pcall-wrapped RegisterEvent as a capability check, not a client-identity check"

key-files:
  created: []
  modified:
    - Core.lua
    - BuffEngine.lua
    - Providers.lua

key-decisions:
  - "A cooldown is a slot, never a timer — no cooldown proc enters ns.activeTimers; ns:GetActiveTimers and ScanActiveTimersForCancellation are untouched by construction, not by an added guard."
  - "Two separate generation counters (cooldownGeneration, trackerGeneration) rather than one, because SPELL_UPDATE_COOLDOWN fires at GCD rate while the tracker set only changes on user edits."
  - "PLAYER_REGEN_ENABLED marks cooldowns dirty but is documented as NOT reliably the first readable moment for a secret charge count, given C_Secrets.ShouldCooldownsBeSecret() stacking encounter/challenge-mode/restricted-map restrictions on top of combat — flagged for Phase 44's retail M+ pass."
  - "Cooldown preview reuses the existing entry.duration synthetic-proc path with zero type branching, per the locked decision that preview never reads a real/secret value."

patterns-established:
  - "Invalidation-stamp counters: plain integer increments on ns, read by a future consumer (Display.lua in Plan 02), advanced only from event handlers or mutation choke points — never per-frame."

requirements-completed: [CD-01, CD-04, CD-05, CD-06]

# Metrics
duration: ~25min
completed: 2026-09-21
---

# Phase 38 Plan 01: Cooldown State, Events and the Two Phase 37 Seams Summary

**Two generation counters (cooldownGeneration/trackerGeneration) plus pcall-guarded SPELL_UPDATE_COOLDOWN/SPELL_UPDATE_CHARGES registration replace both Phase 37 cooldown skips, with no cooldown proc ever entering ns.activeTimers.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-09-21T17:46:41Z
- **Tasks:** 5 (4 code tasks + 1 format/confirm task)
- **Files modified:** 3 (Core.lua, BuffEngine.lua, Providers.lua)

## Accomplishments
- `ns.cooldownGeneration` / `ns.trackerGeneration` declared beside `ns.activeTimers` in Core.lua, with `ns:MarkCooldownsDirty()` / `ns:MarkTrackersDirty()` as plain integer-increment setters (no table, no allocation).
- `SPELL_UPDATE_COOLDOWN` and `SPELL_UPDATE_CHARGES` registered only through a new `TryRegisterEvent` pcall helper — never a bare `RegisterEvent` — so a client missing either event degrades silently instead of erroring on load.
- Four `ns:MarkCooldownsDirty()` call sites wired into the `OnEvent` chain: the shared spell-update branch, `SPELLS_CHANGED`, `PLAYER_ENTERING_WORLD` (outside the one-shot guard), and `PLAYER_REGEN_ENABLED`.
- Both Phase 37 seams removed by name: `UserSpellProviderMixin:OnTrigger`'s cooldown skip now calls `ns:MarkCooldownsDirty()` before returning nil; `ns:StartAllPreviewTimers`'s `trackerType ~= "cooldown"` clause is deleted so cooldown entries preview like any other entry.
- `ns:AddTrackedBuff`, `ns:RemoveTrackedBuff` and `ns:SetBuffSection` each nil-guarded-call `ns:MarkTrackersDirty()` at their mutation point.
- `CURRENT_SCHEMA_VERSION` stays at 4, no `ver < 5` migration block added — documented inline why none is needed (CD-06).

## Task Commits

Each task was committed atomically:

1. **Tasks 1+2: Core.lua generation counters, dirty markers, event registration/wiring** - `7bd1f27` (feat)
2. **Task 3: Providers.lua — remove UserSpellProviderMixin:OnTrigger seam** - `ad6dc5c` (fix)
3. **Task 4: BuffEngine.lua — remove preview seam, stamp the three tracker mutations** - `ba9a163` (fix)
4. **Task 5: stylua format/check** — no additional commit; formatting was already compliant on all three files (`stylua --check .` exits 0 with zero diff produced by the format pass)

_SUMMARY.md is written but intentionally NOT committed per orchestrator instructions — the orchestrator owns STATE.md/ROADMAP.md and the final metadata commit for this plan._

## Files Created/Modified
- `Core.lua` - Two generation counters + marker functions after `ns.activeTimers = {}`; `TryRegisterEvent` helper; `SPELL_UPDATE_COOLDOWN`/`SPELL_UPDATE_CHARGES` registration; four `MarkCooldownsDirty()` call sites in `OnEvent`
- `Providers.lua` - `UserSpellProviderMixin:OnTrigger`'s cooldown branch now calls `ns:MarkCooldownsDirty()` before `return nil`; Phase-38-as-future-owner comment replaced with a permanent explanatory comment
- `BuffEngine.lua` - `ns:StartAllPreviewTimers` preview seam removed; `ns:AddTrackedBuff`/`ns:RemoveTrackedBuff`/`ns:SetBuffSection` each call `ns:MarkTrackersDirty()`; one-line comment beside `CURRENT_SCHEMA_VERSION` recording why no migration is needed

## Decisions Made
- Combined plan Tasks 1 and 2 (both Core.lua, both purely additive to the same event-frame block) into a single commit rather than two, since splitting them would have left an intermediate commit with dead/unregistered dirty-marker functions and no event source to drive them — judged not to be a meaningful atomic checkpoint. All other task boundaries match the plan's file-level split exactly.
- No deviation from the plan's design decisions (slot-not-timer, two counters, no seam left half-removed, no schemaVersion bump).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reworded the CURRENT_SCHEMA_VERSION comment to avoid the literal substring the plan's own acceptance grep forbids**
- **Found during:** Task 4 (BuffEngine.lua migration comment)
- **Issue:** The plan's suggested comment content, written naturally, produced the literal substring `ver < 5` (e.g. "so a buff-only database is already correct with no ver < 5 block needed"), which the plan's own Task 4 acceptance criterion (`grep -n 'ver < 5' BuffEngine.lua` returns nothing) explicitly forbids. This is a case of a correct intent producing a self-defeating literal string, not a code bug — see `<testing_reality>` guidance on criteria vs. code correctness.
- **Fix:** Reworded the comment to convey the same meaning ("adds no migration block at all... the schema version below stays unbumped") without spelling out the forbidden comparison operator sequence.
- **Files modified:** BuffEngine.lua
- **Verification:** `grep -n 'ver < 5' BuffEngine.lua` now returns nothing (exit 1); `grep -n 'CURRENT_SCHEMA_VERSION = 4' BuffEngine.lua` still matches.
- **Committed in:** ba9a163 (Task 4 commit)

---

**Total deviations:** 1 auto-fixed (1 bug-adjacent wording fix, Rule 1)
**Impact on plan:** No scope creep. The fix is textual only — the migration behavior (no `ver < 5` block, `CURRENT_SCHEMA_VERSION` stays 4) is exactly as the plan specified.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both invalidation counters exist and are wired to real events; Plan 02 (`Display.lua`) can now read `ns.cooldownGeneration` / `ns.trackerGeneration` to decide when to re-fetch a duration handle or rebuild a container's slot count.
- Nothing in this plan is visible in-game by design — no bars, no icons render cooldowns yet. That is Plan 02's job.
- `entry.trackerType == "cooldown"` reaching `UserSpellProviderMixin:OnTrigger` and `ns:StartAllPreviewTimers` now behaves exactly as CD-01/CD-04/CD-05/CD-06 require; Plan 02 can build on both counters without needing any further Core.lua/BuffEngine.lua/Providers.lua changes for this milestone's cooldown-rendering scope.
- No blockers.

---
*Phase: 38-cooldown-trackers*
*Completed: 2026-09-21*
