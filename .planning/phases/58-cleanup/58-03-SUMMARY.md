---
phase: 58-cleanup
plan: 03
subsystem: rank families, cast path, dialog, config panel
tags: [cleanup, dedup, hot-path, 57.2-IN-02, 57.2-05-IN-03]
requires: [58-01]
provides:
  - "One Forever family cache (ns.endRuleFamilies via ns:CastRuleFamily) for the load rule and the cast rules"
  - "BaseAndOverride (Core.lua file-local) for the milestone's two base/override pairs"
  - "ns:SameIDList / ns:CopyIDList (Core.lua)"
  - "ns:ResolveCastOwner (Providers.lua), allocation-free"
  - "SetupRadioMenu (CDMTab.lua); ROW_BTN_W / ROW_GAP (Config.lua)"
affects: [58-04]
tech-stack:
  added: []
  patterns: ["cross-file helpers on ns; file-locals above their first reader"]
key-files:
  created: []
  modified: [Core.lua, Providers.lua, CDMTab.lua, Config.lua]
decisions:
  - "ns:SpellKnownState reads ns:CastRuleFamily(spellID) or false; ns.loadRankFamilies is deleted"
  - "metaReminderKey now resolves to nil when no entry exists (ResolveCastOwner); proven equivalent below"
metrics:
  duration: "~15 min"
  completed: 2026-09-29
---

# Phase 58 Plan 03: Unify the milestone's duplication Summary

Every duplication the milestone introduced, and that the plan named, now exists once:
- the Forever family cache;
- the base/override pair;
- the ID-list compare and copy;
- the "direct ID, then rank index" cast lookup;
- the radio-menu generator.

The Config reminder-row buttons use named constants. Pre-milestone code is untouched: ResolveRankFamily steps 1 and 4, the tooltip RelatedID, the buff side of OnTrigger, WireExclusivePair, and the RunLoadRefresh/SPELLS_CHANGED rebuild lines.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 230c6f2 | refactor(58-03): one Forever family cache and one base/override pair |
| 2 | 3b44b04 | refactor(58-03): shared ID-list helpers and one cast-owner lookup |
| 3 | 692883e | refactor(58-03): one radio-menu builder and named reminder-row constants |

## Gate results

| Gate | Before | After |
|------|--------|-------|
| T1 | FAIL: ns.loadRankFamilies still exists | ok |
| T2 | FAIL: ns:SameIDList / ns:CopyIDList are not defined in Core.lua | ok (second run, see Deviations) |
| T3 | FAIL: no SetupRadioMenu helper | ok |

Both node scripts pass (aura-read-gate PASS, its selftest 30 cases; migrate-dryrun selftest 12 cases). `stylua --check .` is clean. All touched files are `w/crlf`, with one CR per line and no CRCR.

## Equivalence arguments

**Task 1, one family cache.**
- On Forever, `ns.loadRankFamilies[id]` and `ns.endRuleFamilies[id]` both held `ns:ResolveRankFamily(id) or false`, computed with the same arguments (no pet-book flag).
- Both were wiped at the same three moments: RunLoadRefresh out of combat, PLAYER_ENTERING_WORLD, and SPELLS_CHANGED out of combat.
- SpellKnownState's own guard (not secret, a number, > 0) is a superset of CastRuleFamily's, and `ns:CastRuleFamily(id) or false` maps its `family or nil` return back to the same `false`.
- SpellKnownState only walks the family inside `if ns.CLIENT_HAS_SPELL_RANKS and not noRanks`, so retail never reads the cache from the load rule and retail is unchanged.
- `wipe(ns.endRuleFamilies)` still appears exactly three times.

**Task 1, BaseAndOverride.** It returns the same two `RelatedSpellID(C_Spell and C_Spell.Get{Base,Override}Spell, id)` values, in the same order and through the same pcall/issecretvalue/type screen. CastRuleFamily's retail branch still appends base and then override, each only when non-nil.

**Task 2, ns:SameIDList in RebuildReminderWatch.** The old compare was true for the same reference, or for two non-nil lists of equal length with equal elements, and false otherwise (so nil vs table is false, and nil vs nil is true through `old == list`). SameIDList gives the same answer in every case: `a == b` for any non-table pair, and an element walk until both run out for tables. The two are equal for proper sequences, and every list here is a proper sequence built at rebuild time.

**Task 2, ns:CopyIDList in RebuildReminderWatch.** The old loop appended `list[1..#list]` into a fresh table, and CopyIDList writes `copy[i] = list[i]` for the same range. The else branch is `{ ns.reminderAuraID[key] }`, where it was `{}` then `[1] =`; a nil ID gives an empty table either way. It is one allocation, the same as before, and rebuild-time only.

**Task 2, ns:ResolveCastOwner.**
- **StartCooldownFromCast and the user reminder:** identical results. The old reminder code already cleared the key when no entry was found.
- **metaReminder:** the old code could leave `metaReminderKey` set to a rank-index hit whose `tracked[...]` entry was missing. That key fed only the alternatives skip test `altKey ~= metaReminderKey`. When `altKey` equals such a key, `tracked[altKey]` is nil, and `ns:StartReminderFromCast(key, nil, true)` returns at its first line (`if not (entry and ...) then return end`). So the skip changes nothing: a key with no entry starts nothing either way.
- The helper guards `rankIdx and rankIdx[spellID]`. The old reminder lookups indexed `ns.rankIndexReminder` / `ns.rankIndexMetaReminder` directly, but both are declared as tables at Core.lua file scope, so the guard only adds robustness.
- **Hot path:** two table reads per namespace on a miss. No table, closure or string, which the gate checks statically.

**Task 2, header split (57.2-05 IN-03).** Only comments moved. The user reminder lookup still runs before `ns:ApplyEndOnCast`: the order is now cooldown side, reminder resolution, cross-spell side. The optional "skip the reminder side's redraw" part stays skipped, per the 57.2-05 decision.

**Task 3, SetupRadioMenu.** It holds the same generator body, reading the `choices` parameter where the old code read the LOAD_CHOICES / CONTAINER_CATEGORY_CHOICES upvalue. Each caller still builds IsSelected and SetSelected once, outside the generator. SetupRadioMenu is declared above TRACKER_FIELDS, its first reader, and CreateContainerDialog sits further down the file.

**Task 3, ROW_BTN_W / ROW_GAP.** The offsets `PAD_X + 0/180/360` and the width 170 are the same values, so the layout does not move. BUTTON_W stays, because other buttons use it.

## Deviations from Plan

- **T2 first gate run:** I first wrote `ns:SameIDList(oldWatch[key], list)` and dropped the `old` local. The gate asserts the plan's literal `ns:SameIDList(old, list)`, so I restored `local old = oldWatch[key]` to match the plan text. The gate is unchanged.
- **Tooling:** the Edit tool was available and was used for every edit (the plan assumed node split/join). CRLF was asserted after each task.
- **Scratch folder:** `scratchpad\p58\exec\` (orchestrator instruction).

## Known Stubs

None.
