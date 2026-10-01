---
phase: 53-naming-scheme-saved-data-migration
plan: 03
subsystem: infra
tags: [naming-scheme, providers, wow-addon, lua, key-scheme]

# Dependency graph
requires:
  - phase: 53-naming-scheme-saved-data-migration
    provides: "plan 53-02's Core.lua scheme (ns.KIND/ns.KEY_PREFIX/ns.META_KEY/ns:TrackerKey/key parsers/ns.buffKeyBySpell/ns.cooldownKeyBySpell/ns:RebuildCastIndex) and BuffEngine.lua schema v8, which call ns:IsRacialSpellID by name before this plan defines it"
provides:
  - "ns:IsRacialSpellID(spellID) -- racialSpellOwners membership test, consumed by Core.lua's ns:CooldownKindFor and BuffEngine.lua's ns:MigrateKindKeys"
  - "UserSpellProviderMixin:OnTrigger resolving both cooldown and buff sides through ns.cooldownKeyBySpell/ns.buffKeyBySpell -- one table lookup, no per-cast concat"
  - "ns:GetDisplayInfoForKey dispatching a tracked entry on entry.trackerType before any key parse, falling back to the kind parsers only for untracked Suggested/drag-ghost keys"
  - "Every provider on the naming scheme: MetaItemTrinketProvider, MetaItemPotProvider, MetaItemBagProvider, MetaSkillLustProvider, MetaSkillRacialProvider, UserSpellProvider (kept, serves three kinds)"
affects: [53-04, 53-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "File-local meta-key/prefix constants (LUST_KEY, TRINKET_KEY, POT_KEY, META_SKILL_PREFIX, META_ITEM_PREFIX) hoisted above every function definition in Providers.lua, resolved once from Core.lua's ns.META_KEY/ns.KEY_PREFIX at file load (Core.lua loads first per the TOC)"
    - "Tracked-entry-first dispatch: ns:GetDisplayInfoForKey reads entry.trackerType before parsing the key string at all, so the render path (called every tick) is parse-free for anything already tracked; only Suggested/drag-ghost keys fall through to the kind parsers"
    - "Cast-index-first resolution: the hot UNIT_SPELLCAST_SUCCEEDED path indexes ns.buffKeyBySpell/ns.cooldownKeyBySpell before falling back to the rank index, replacing the old ns.COOLDOWN_KEY_PREFIX per-cast concat with a rebuilt-at-migration-time table lookup"

key-files:
  created: []
  modified:
    - "Providers.lua - ns:IsRacialSpellID added; UserSpellProviderMixin:OnTrigger/:GetDisplayInfo rewritten onto the cast index and entry.spellID; ns:GetDisplayInfoForKey rewritten to dispatch tracked entries on kind first; meta keys/prefixes replaced by constants; provider Mixins and instances renamed onto the naming scheme; every comment quoting an old key shape updated"

key-decisions:
  - "UserSpellProvider keeps its descriptive name rather than a kind-shaped rename (53-CONTEXT leaves this to discretion) because it serves THREE kinds at once -- userBuff, userCd, and metaSkillCd racial cooldown tiles -- documented in its header comment"
  - "Provider rename order (Item, then Trinket, Pot, Lust, Racial) followed exactly as the plan specified to avoid substring collisions during the whole-file replace_all passes; verified after each pass that no double-prefixed identifier (e.g. MetaItemMetaItem...) was produced"
  - "ns:GetDisplayInfoForKey's five-step order (non-string reject, fixed meta keys, tracked-entry-by-kind, untracked-key-by-parse, nil) implements 53-CONTEXT's 'tooltip/icon resolution must not break' condition and the 46-RESEARCH Pitfall 4 guard (a bag item's itemID is never treated as a spellID) explicitly in both code and its header comment"

requirements-completed: [NAME-01]

# Metrics
duration: 9min
completed: 2026-09-28
---

# Phase 53 Plan 03: Providers.lua on the Naming Scheme Summary

**Every provider in Providers.lua moved onto the `<kind>:<id>` key scheme: the cast path resolves through `ns.buffKeyBySpell`/`ns.cooldownKeyBySpell` instead of a per-cast concat, `ns:GetDisplayInfoForKey` dispatches a tracked entry on its kind before any key parse, and every provider Mixin/instance is renamed to match the kind it serves (`MetaItemTrinketProvider`, `MetaItemPotProvider`, `MetaItemBagProvider`, `MetaSkillLustProvider`, `MetaSkillRacialProvider`; `UserSpellProvider` keeps its name, documented as serving three kinds).**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-09-28T08:16:01-03:00 (previous plan's completion commit)
- **Completed:** 2026-09-28T08:25:27-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 1

## Accomplishments
- `ns:IsRacialSpellID(spellID)` added directly after the `racialSpellOwners` loop, satisfying the call Core.lua's `ns:CooldownKindFor` and BuffEngine.lua's `ns:MigrateKindKeys` (plan 53-02) already make by name.
- `UserSpellProviderMixin:OnTrigger` resolves the cooldown side through `ns.cooldownKeyBySpell[spellID]` and the buff side through `ns.buffKeyBySpell[spellID]` -- both with the existing rank-index fallback preserved -- instead of concatenating `ns.COOLDOWN_KEY_PREFIX .. spellID` per cast. Procs now carry `entry.spellID` (numeric) rather than the string slot key; the stale defensive check `entry.trackerType == "cooldown"` became `entry.trackerType ~= ns.KIND.USER_BUFF`.
- `UserSpellProviderMixin:GetDisplayInfo` reads a tracked entry's own `entry.spellID` first and falls back to `ns:SpellKeySpellID(key)` for untracked keys (Suggested tiles, racial cooldown seeds) -- the old `type(key) ~= "number"` branch is gone, since every key is a string now.
- `ns:GetDisplayInfoForKey` rewritten to a five-step order: reject non-strings, route the three fixed meta keys via `keyToProvider` (now keyed by `ns.META_KEY.TRINKET/POT/LUST`), dispatch a **tracked** entry on `entry.trackerType` with no parse at all, fall back to parsing an **untracked** key's kind (item/racial/spell), and return nil for anything else (the runtime-only `cdm:`/`__tbt_example__` keys, left unrenamed per 53-CONTEXT discretion).
- Every `"trinket"`/`"pot"`/`"lust"` string-literal key replaced by `TRINKET_KEY`/`POT_KEY`/`LUST_KEY` (file-local constants resolved from `ns.META_KEY` at load); every `ns.RACIAL_KEY_PREFIX .. def.spellID` replaced by `META_SKILL_PREFIX .. def.spellID`; every `ns.ITEM_KEY_PREFIX .. itemID` replaced by `META_ITEM_PREFIX .. itemID`; `ns:RacialCooldownKeys` now mints through `ns:TrackerKey(ns.KIND.META_SKILL_CD, def.spellID)`.
- The three `entry.trackerType == "item"` tests (`ns:RegisterAllTrackedItemUseSpells`, `ns:RefreshTrackedItemCooldowns`, `ns:ReconcileTrackedItemCounts`) replaced by `ns:IsBagItemEntry(entry)`, which subsumes the redundant `type(entry.itemID) == "number"` clause the latter two also carried.
- Provider Mixins and instances renamed onto the scheme (`<Kind><Source>`): `ItemProvider` -> `MetaItemBagProvider`, `TrinketProvider` -> `MetaItemTrinketProvider`, `PotProvider` -> `MetaItemPotProvider`, `LustProvider` -> `MetaSkillLustProvider`, `RacialProvider` -> `MetaSkillRacialProvider`, applied to both the Mixin and the instance identifier in code and comments. `UserSpellProvider` was deliberately left unrenamed with an expanded header comment explaining it serves `userBuff`, `userCd` and starts `metaSkillCd` tiles.
- Every remaining comment quoting an old key shape (`"cd:<spellID>"`, `"item:<itemID>"`, `` `racial:<spellID>` ``) updated to the canonical `metaSkillCd:`/`metaItem:`/`metaSkill:` shape, so no line in the file names a pre-scheme key any more.

## Task Commits

Each task was committed atomically:

1. **Task 1: Cast path through the index, ns:IsRacialSpellID, and kind-dispatched display info** - `8ff6840` (feat)
2. **Task 2: Canonical meta keys, kind-minted dynamic keys, bag-item predicate, scheme-named providers** - `1a5a4af` (feat)

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified
- `Providers.lua` - `ns:IsRacialSpellID`; cast-index-driven `UserSpellProviderMixin:OnTrigger`/`:GetDisplayInfo`; kind-dispatched `ns:GetDisplayInfoForKey`; file-local `LUST_KEY`/`TRINKET_KEY`/`POT_KEY`/`META_SKILL_PREFIX`/`META_ITEM_PREFIX`; `ns:IsBagItemEntry`-driven item predicates; provider renames onto the naming scheme; registry and key-shape comments updated throughout

## Decisions Made
- `UserSpellProvider` keeps its descriptive name (Claude's discretion per 53-CONTEXT "Parsers and constants") because it is the one provider that serves three kinds at once (`userBuff`, `userCd`, and `metaSkillCd` racial cooldown tiles) rather than a single kind a `<Kind><Source>` name could name accurately -- documented in its header comment rather than left implicit.
- Provider renames applied in the plan's specified order (Item first, then Trinket, Pot, Lust, Racial) to avoid substring collisions between the whole-file `replace_all` passes; verified with `grep -nE 'MetaItemMeta|MetaSkillMeta|ProviderProvider'` after every pass that no identifier was double-prefixed.
- `ns:GetDisplayInfoForKey`'s new step order puts the tracked-entry dispatch (by `entry.trackerType`) before any key parse, and puts `ns:IsBagItemEntry(entry)` ahead of the fallback item/racial/spell parsers -- both choices implement 53-CONTEXT's "tooltip/icon resolution must not break" condition and keep the 46-RESEARCH Pitfall 4 guard (an itemID is never treated as a spellID) intact and explicit.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance-criteria greps (the full set specified in the plan: identifier counts, `stylua --check`, `git ls-files --eol`, `git diff --numstat`, the `awk`-scoped `GetDisplayInfoForKey` check, and the cross-file leftover-identifier check) passed on the first implementation; no auto-fixes were needed.

## Issues Encountered

None. `stylua --check Providers.lua` passed on the first formatting pass for both tasks; `node scripts/migrate-dryrun.js --selftest` (plan 53-01's spec, which reads `RACIAL_SPELLS` live off this file) still prints `SELFTEST PASS (5 cases)` unchanged after both commits, confirming the rename and re-key work did not touch anything that script depends on structurally.

## Human Verification Needed

None for this plan. Both tasks are pure Lua source edits verified by `stylua --check`, `git ls-files --eol`, `git diff --numstat`, and the full set of structural grep/awk acceptance criteria specified in the plan -- no WoW client is available in this environment. Real in-game verification of casts, tooltips, icons and labels for every kind (user buff, user cooldown, and every meta kind) is plan 53-05's responsibility, once plan 53-04 (CDMTab.lua/Display.lua/MergeMode.lua callers) has also landed -- those files still reference the removed `ns.ITEM_KEY_PREFIX`/`ns.RACIAL_KEY_PREFIX` constants and old `trackerType` string values, which is expected per 53-02's summary ("the addon is intentionally inconsistent until [53-03 and 53-04] land") and out of this plan's file scope (`Providers.lua` only).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`Providers.lua` is fully on the naming scheme: every provider Mixin/instance is named for the kind it serves, every meta key and dynamic key is minted from `ns.KIND`/`ns.META_KEY`/`ns:TrackerKey`, the cast path is a single table lookup through the plan 53-02 cast index, and `ns:GetDisplayInfoForKey` answers for every kind (tracked or Suggested) without ever treating an itemID as a spellID. Ready for plan 53-04 (CDMTab.lua/Display.lua/MergeMode.lua, which still reference `ns.ITEM_KEY_PREFIX`/`ns.RACIAL_KEY_PREFIX` and old `trackerType` string literals) and plan 53-05 (the reconciliation against plan 53-01's `scripts/migrate-dryrun.js --selftest` spec plus the real in-game logout/login verification, NAME-02). No blockers.

---
*Phase: 53-naming-scheme-saved-data-migration*
*Completed: 2026-09-28*
