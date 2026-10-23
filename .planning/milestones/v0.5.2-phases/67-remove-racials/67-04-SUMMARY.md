---
phase: 67-remove-racials
plan: 04
subsystem: provider-runtime
tags: [racials, providers, lua]
requires: ["67-02", "67-03"]
provides:
  - "Provider registry with five providers, none racial"
  - "No combat-entry handler, cooldown override table or indefinite backstop"
affects: [67-05]
key-files:
  modified:
    - Providers.lua
    - Core.lua
    - BuffEngine.lua
key-decisions:
  - "ns:RacialDefsAll / ns:RacialDefForSpellID and the RACIAL_SPELLS comment block left for Plan 05"
requirements-completed: [RACE-11, RACE-12]
duration: 20min
completed: 2026-10-10
---

# Phase 67 Plan 04: Racial runtime removal Summary

MetaSkillRacialProvider and everything it drove (StartRacialProc, Eureka stack spending, the racial UNIT_AURA trigger, the combat-entry clear, the one-cast conditional cooldown, the indefinite backstop) are gone; ns:CooldownDuration now simply returns entry.duration.

## Tasks

| Task | Commit | Notes |
| ---- | ------ | ----- |
| 1. Providers.lua runtime and dispatch | see git log (feat(67-04) Providers) | 503 lines removed |
| 2. Core.lua / BuffEngine.lua hooks | see git log (feat(67-04) Core/BuffEngine) | |

## What changed

- Providers.lua: deleted the racial provider block (mixin, harmful/priest predicates, StartRacialProc, ConsumeRacialStack, AuraStackCount, RacialAuraTrigger, racialDisplayInfo), the registry row and comment lines, the two racial branches in ns:GetDisplayInfoForKey, ns.racialDefsActive with ns:RebuildRacialLoadLists, ns:EndCombatClearedRacials and ns:ConditionalCooldown. ns:StartCooldownFromCast now only stamps cooldownStarts and marks dirty. Survival checks passed: ns:ItemDisplayInfo, UserSpellProvider construction, MetaSkillLustProvider and the class-buff section header are intact.
- Core.lua: removed PLAYER_REGEN_DISABLED registration and branch, ns.cooldownOverrides, the RebuildRacialLoadLists call; reworded two comments.
- BuffEngine.lua: removed the three cooldownOverrides writes (plus the one in ns:EndTrackerRuntime), ns.INDEFINITE_DURATION and related comment mentions.

## Acceptance criteria

Met: tree-wide grep for cooldownOverrides, INDEFINITE_DURATION, EndCombatClearedRacials, ConditionalCooldown, RebuildRacialLoadLists, racialDefsActive, ConsumeRacialStack, RacialAuraTrigger, AuraStackCount, PlayerIsPriest prints nothing in shipped Lua; PLAYER_REGEN_DISABLED in Core.lua is 0 (Display.lua and MergeMode.lua untouched); five other providers still registered; aura-read-gate PASS (4 reads, 2 readers) and --selftest PASS (30); migrate-dryrun --selftest PASS (13); stylua exit 0; all three files `w/crlf`.

## Deviations from Plan

Plan-vs-reality mismatch, not a bug: the Task 1 criterion "grep for MetaSkillRacialProvider|StartRacialProc|ConditionalCooldown|maxStacks|Eureka outputs 0" cannot hold yet. The RACIAL_SPELLS catalogue (a data row `maxStacks = 3 ... Eureka!`, `def.maxStacks` copy in ns:RacialDefsAll, and its documentation comment naming MetaSkillRacialProviderMixin, StartRacialProc and ns:ConditionalCooldown) is explicitly Plan 05 scope, so those hits remain as comments/data only; no code path references a deleted symbol. The only other hits are in tools/TBTProbe (unshipped, uses C_Spell.IsSpellHarmful directly).

## Deferred to Phase 72 (human, in-game)

On Forever: cast a racial (Shadowmeld, Berserking) and see no TBT bar or icon start; enter and leave combat with no Lua error; a user cooldown still starts on its cast and runs its typed duration.

## Known Stubs

None.

## Self-Check: PASSED

Both task commits exist; STATE.md and ROADMAP.md untouched.
