---
phase: 57-detailed-tracking-visibility-cross-spell-rules
plan: 01
subsystem: buff-engine
tags: [wow-addon, lua, cross-spell-rules, cast-index, rank-family]

# Dependency graph
requires:
  - phase: 56-detailed-tracking-mode-aura-rules
    provides: "entry.detailed master flag, ns:ResolveRankFamily, ns.CLIENT_HAS_SPELL_RANKS, ns:RebuildCastIndex/RebuildRankIndex, RACE-03's ns:EndTimer precedent for a provider calling into BuffEngine lifecycle"
provides:
  - "ns.endKeysBySpell reverse index (trigger spell ID, rank/override-expanded, to detailed tracker keys)"
  - "ns:RebuildDetailedRuleIndex, called from ns:RebuildCastIndex so every existing rebuild site refreshes it"
  - "ns.endRuleFamilies Forever-only cache, wiped out of combat on SPELLS_CHANGED and at PLAYER_ENTERING_WORLD"
  - "ns:ApplyEndOnCast (BuffEngine.lua), the allocation-free lifecycle loop that ends a buff timer or resets a cooldown"
  - "the cross-spell side effect in UserSpellProviderMixin:OnTrigger, between the cooldown side and the buff side"
affects: ["57-04 (the dialog field that writes entry.endOnCast)", "57-02/57-03 (visibility modes, same rebuild/event plumbing)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Reverse cast-spell index built at rebuild time, read as one table lookup on the cast path (same shape as ns.buffKeyBySpell/ns.cooldownKeyBySpell/ns.rankIndex)"
    - "Retail/Forever split for rank expansion: retail never calls ns:ResolveRankFamily (two guarded base/override lookups only); Forever caches the resolved family per trigger ID and only invalidates it when the spellbook can actually have changed"
    - "Skip rule for cross-spell rules: a rule never ends the key its own cast is (re)starting, computed with the same two lookups the buff side already makes"

key-files:
  created: []
  modified:
    - Core.lua
    - BuffEngine.lua
    - Providers.lua

key-decisions:
  - "ns:RebuildDetailedRuleIndex is called as the last statement of ns:RebuildCastIndex (not RebuildRankIndex), so it also runs from CDMTab.lua's drop handler and every other RebuildCastIndex call site with no new call site added anywhere"
  - "Forever's ns.endRuleFamilies cache is wiped in place (never replaced) so a rebuild triggered mid-scan never observes a half-built cache; wipe happens before ns:RebuildRankIndex() in both the SPELLS_CHANGED (out of combat only) and PLAYER_ENTERING_WORLD branches, matching the plan's documented in-combat-stays-valid rule"
  - "ns:ApplyEndOnCast lives in BuffEngine.lua next to ns:EndTimer (the RACE-03 precedent for a provider calling into BuffEngine lifecycle), not in Providers.lua, keeping lifecycle ownership in one module"

patterns-established:
  - "A rebuild-time reverse index (trigger ID -> owner keys) paired with a single cast-path lookup is now the addon's standard shape for 'event on spell X affects tracker Y' rules"

requirements-completed: [DTRK-05]

# Metrics
duration: 15min
completed: 2026-09-28
---

# Phase 57 Plan 01: Cross-Spell Runtime Summary

**Rebuild-time reverse index (ns.endKeysBySpell) plus an allocation-free OnTrigger side effect (ns:ApplyEndOnCast) so casting spell B ends or resets any detailed tracker whose entry.endOnCast lists B, in combat, including ranks and overrides of B.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-09-28T16:51:33Z
- **Tasks:** 2
- **Files modified:** 3 (Core.lua, BuffEngine.lua, Providers.lua)

## Accomplishments
- `ns.endKeysBySpell` and `ns.endRuleFamilies` declared at file scope in Core.lua, and `ns:RebuildDetailedRuleIndex()` builds the former fresh on every existing `ns:RebuildCastIndex` call site (add, update, remove, migration, world entry, SPELLS_CHANGED, CDM drop) with no new call site.
- Retail never scans the spellbook for cross-spell rules: each trigger ID is expanded to `{ triggerID, base, override }` through the two guarded `RelatedSpellID` lookups only. Forever calls `ns:ResolveRankFamily` once per trigger ID and caches the result in `ns.endRuleFamilies`, wiped out of combat on SPELLS_CHANGED and unconditionally at PLAYER_ENTERING_WORLD.
- `ns:ApplyEndOnCast(endKeys, startingCdKey, startingBuffKey)` (BuffEngine.lua) clears `ns.activeTimers[k]` for a detailed buff tracker or `ns.cooldownStarts[k]`/`ns.cooldownOverrides[k]` for a detailed cooldown tracker, skipping any key the same cast is about to (re)start, redrawing once per kind actually changed. Zero table constructors, zero `pairs(`/`ipairs(`.
- `UserSpellProviderMixin:OnTrigger` (Providers.lua) looks up `ns.endKeysBySpell[spellID]` between the cooldown side and the buff side and calls `ns:ApplyEndOnCast` only on a hit, keeping OnTrigger's zero-`{` allocation gate intact.

## Task Commits

Each task was committed atomically:

1. **Task 1: Rebuild-time reverse index ns.endKeysBySpell (rank/override expanded)** - `6f29443` (feat)
2. **Task 2: ns:ApplyEndOnCast and the cross-spell side effect in OnTrigger** - `3a69209` (feat)

_No plan-metadata commit — the orchestrator owns STATE.md/ROADMAP.md updates for this plan._

## Files Created/Modified
- `Core.lua` - `ns.endKeysBySpell`/`ns.endRuleFamilies` declarations, `ns:RebuildDetailedRuleIndex`, its call from `ns:RebuildCastIndex`, and the two event-handler cache wipes (SPELLS_CHANGED out of combat, PLAYER_ENTERING_WORLD)
- `BuffEngine.lua` - `ns:ApplyEndOnCast`, added directly after `ns:EndTimer`
- `Providers.lua` - the cross-spell lookup and call in `UserSpellProviderMixin:OnTrigger`, between the cooldown side and the buff side

## Decisions Made
- `ns:RebuildDetailedRuleIndex` is invoked from `ns:RebuildCastIndex` rather than `ns:RebuildRankIndex`, per the plan's explicit key-link requirement — this reaches the CDM drop handler and every direct `RebuildCastIndex` caller without adding a new call site.
- The Forever cache wipe order matches the plan exactly: `if not InCombatLockdown() then wipe(ns.endRuleFamilies) end` before `ns:RebuildRankIndex()` in the SPELLS_CHANGED branch; an unconditional `wipe(ns.endRuleFamilies)` before `ns:RebuildRankIndex()` in the PLAYER_ENTERING_WORLD branch.
- No deviations from the plan's documented design choices (skip rule, redraw rule, trigger-expansion cost) were needed — the existing codebase already exposed every helper (`RelatedSpellID`, `ns:ResolveRankFamily`, `ns.CLIENT_HAS_SPELL_RANKS`, `ns.KIND.USER_BUFF`/`USER_CD`) the plan assumed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Verification

Both task automated gates passed in full (Task 1: index shape, retail/Forever branch line-order, event-handler wipe order, OnUpdate-mention scan, stylua, CRLF/EOL checks; Task 2: ns:ApplyEndOnCast shape and zero-allocation scan, OnTrigger line order and zero-`{` scan, aura-read gate PASS plus its 30-case selftest, stylua, CRLF/EOL checks). Plan-level verification also confirmed: `node scripts/migrate-dryrun.js --selftest` reports 7 cases (unchanged).

In-game verification (a cast ending a running detailed buff timer or resetting a detailed cooldown, in and out of combat, including a rank/override cast) requires a live WoW client and Plan 04's dialog field that writes `entry.endOnCast` — both are human/future-plan verification, no WoW client is available in this environment.

## Next Phase Readiness
- The runtime half of DTRK-05 is complete and dormant until Plan 04 adds the `entry.endOnCast` dialog field — no tracker can carry that key yet, so `ns.endKeysBySpell` stays empty on every current save file.
- Plans 02/03 (visibility modes) can reuse the same rebuild/event plumbing (`ns:RebuildRankIndex`'s SPELLS_CHANGED/PLAYER_ENTERING_WORLD call sites) without conflict, since Task 1's cache wipes were added as new statements alongside the existing `ns:RebuildRankIndex()` calls, not by editing them.
- No blockers.

---
*Phase: 57-detailed-tracking-visibility-cross-spell-rules*
*Completed: 2026-09-28*
