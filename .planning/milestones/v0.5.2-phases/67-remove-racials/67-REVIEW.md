---
phase: 67-remove-racials
reviewed: 2026-10-10T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - BuffEngine.lua
  - CDMTab.lua
  - Core.lua
  - Display.lua
  - Providers.lua
  - scripts/aura-read-gate.js
  - scripts/migrate-dryrun.js
findings:
  critical: 0
  warning: 1
  info: 5
  total: 6
status: issues_found
---

# Phase 67: Code Review Report

**Reviewed:** 2026-10-10
**Depth:** standard (diff `8d64c7e..HEAD`)
**Files Reviewed:** 7
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

The removal is clean in the places the brief named as highest risk:

- **Deleted symbols.** A repo-wide grep over `*.lua`, `*.xml` and `*.js` (excluding `tools/`) for every removed name (`RACIAL_SPELLS`, `ns:Racial*`, `IsRacialSpellID`, `CooldownKindFor`, `CooldownKeySpellID`, `RacialKeySpellID`, `ConditionalCooldown`, `EndCombatClearedRacials`, `LogPlayerRace`, `BaselinePlayerAuras`, `RebuildRacialLoadLists`, `knownRacialDefs`, `racialDefsActive`, `spellKnownHeldNoRanks`, `SINGLE_RANK_KINDS`, `META_SKILL_CD`, `metaCooldownKeyBySpell`, `rankIndexMetaCooldown`, `cooldownOverrides`, `INDEFINITE_DURATION`, `.indefinite`, `.stacks`, `_stacks`, `META_SKILL_PREFIX`, `CollectPlayerBuffs`, `IsSpellHarmful`) finds no live reference. Every helper that is still called (`SafeNumber`, `SafeString`, `SpellName`, `ReleaseProc`, `MarkTrackersDirty`, `UpdateDisplay`, `RebuildCastIndex`) is either reached through `ns` or is declared above all its callers, so the upvalue-order trap does not apply.
- **Migration chain.** v7 no longer reads the race and always stamps 7. v8 maps every legacy cooldown to `userCd`. v11 is now pinned to the literal 11. v12 drops only `^metaSkill:%d+$`, `^metaSkillCd:%d+$`, `racial` and `racial2`, so `metaSkill:lust` is kept. Gating is `[11, 12)`. Keys are collected before they are deleted. Removing the PLAYER_ENTERING_WORLD retry is safe now that nothing defers. `migrate-dryrun.js` matches the Lua on gates, patterns and v8 classification. `--selftest` passes all 13 cases, and `aura-read-gate.js` plus its selftest pass.
- **Hot paths.** The changes only make them cheaper: one fewer `StartCooldownFromCast` per cast, no per-frame stack or indefinite branches in the bar and icon renderers, no `PLAYER_REGEN_DISABLED` handler, and no racial provider in the `UNIT_SPELLCAST_SUCCEEDED`/`UNIT_AURA` dispatch lists. No new allocation was added.

One correctness gap remains: a v0.4.x racial cooldown tile still survives the upgrade, as a user cooldown (WR-01). The other findings are stale comments and robustness or maintainability items.

## Warnings

### WR-01: v0.4.x racial cooldown tiles survive the upgrade as user cooldowns, breaking MIG-03

**File:** `BuffEngine.lua:326-338` (v8 cooldown branches), mirrored in `scripts/migrate-dryrun.js:210-221`. The selftest locks this in at `scripts/migrate-dryrun.js:771-780` (`cd:20572 -> userCd:20572`, `cd:20554 -> userCd:20554`).

**Issue:** v0.4.1 (`c30084a`) shipped Forever racial cooldown Suggested tiles, and those tiles saved their trackers as `"cd:<spellID>"`. Until this phase, v8 sent such a key through `ns:CooldownKindFor` and gave it `metaSkillCd:<id>`, and v12 would now drop that key. Phase 67 rewrote v8 to classify every `cd:<N>` as `userCd`. A database still below schema 8, meaning a Forever player who tracked a racial cooldown on v0.4.x and is upgrading straight to this build, therefore keeps that racial tracker. It becomes a user-editable `userCd:<racialSpellID>`, and v12 never matches it.

MIG-03 says "loading saved data that holds racial trackers removes them", and RACE-11 says "no racial trackers on any client". The surviving tile is functional and the player can delete it, so no data is corrupted. It is still a racial tracker that came from the racial Suggested tile and outlives the feature. 67-01-PLAN records this as a "deliberate consequence", but that trade-off contradicts the phase's own requirement. It was also unnecessary, because the decision being honoured was "never read the (deleted) catalogue", not "never use a frozen literal".

**Fix:** Recreate the old v8 classification with a frozen, function-local literal. The migration chain already does this (see the `"cd:"` and `"racial:"` literals in v6, v7 and v8). The list is the union of every racial cooldown spellID the v0.4.x/v0.5.x catalogue carried (`git show 9aa91d7:Providers.lua`). Then drop those keys in v8 itself, or send them to `metaSkillCd:<id>` so v12 drops them:

```lua
-- inside ns:MigrateKindKeys, next to the other frozen literals
-- Frozen: every spellID the pre-Phase-67 catalogue offered as a racial cooldown tile.
-- History, not a catalogue -- this list must never grow.
local LEGACY_RACIAL_CD = {
	[20600] = true, [1259718] = true, [20572] = true, [1299026] = true, [20594] = true,
	[20580] = true, [1259799] = true, [20577] = true, [7744] = true, [20549] = true,
	[20552] = true, [1259817] = true, [20589] = true, [20554] = true, [1260270] = true,
	[1259416] = true, [1259705] = true, [1259686] = true,
}
...
local n = oldKey:match(COOLDOWN_PATTERN)
if n then
	id = tonumber(n)
	kind = LEGACY_RACIAL_CD[id] and "metaSkillCd" or ns.KIND.USER_CD
	newKey = kind .. ":" .. id  -- ns:TrackerKey no longer knows metaSkillCd
```

Apply the same change in `migrateV8`. Update Fixture A so that `cd:20572` and `cd:20554` are expected to be gone after v12, not kept as `userCd`. If the user really wants the current behaviour, record it as an amendment to MIG-03 rather than leaving the requirement and the code in disagreement.

## Info

### IN-01: A schema-12 database written by an older build can bring racial trackers back permanently

**File:** `BuffEngine.lua:684-694`

**Issue:** v12 runs only once, while `schemaVersion` is in `[11, 12)`. v0.5.1 never lowers `schemaVersion`; its last block returns on `ver >= 11`. So a player who downgrades after this upgrade can create `metaSkill:<id>` or `metaSkillCd:<id>` trackers from the old racial tiles, and on upgrading again v12 will not run. In this build those entries have no provider and no branch in `ns:GetDisplayInfoForKey` (returns nil, so they draw as a blank placeholder). A `metaSkillCd` entry has no known kind at all (`ns:KeyKind` returns nil, and `IsCooldownSlotEntry` is false, so it files as a buff). This is uncommon and caused by the user.

**Fix:** Accept it and document it, or make the v12 drop a cheap, unconditional, idempotent sweep at load, outside the version gate. Any one of the key-shape matches it does only ever finds orphans.

### IN-02: Stale comment still describes the removed one-cast cooldown override

**File:** `Display.lua:1413-1418`

**Issue:** `ApplyUserCooldown` still says "a cast whose circumstances earned a different cooldown left a one-cast override beside its start time, and ns:CooldownDuration is the single place the two are reconciled". `ns.cooldownOverrides` is gone, and `ns:CooldownDuration` now returns `entry.duration` only. 67-CONTEXT requires comments that describe removed racial behaviour to go with that behaviour.

**Fix:** Reword it to "Read through ns:CooldownDuration, the one entry point for a cooldown's length (Core.lua)", or simply read `entry.duration`.

### IN-03: Stale v7 call-site comment says v7 still re-keys

**File:** `BuffEngine.lua:213-215`

**Issue:** "...BEFORE the ns:PreallocateProc loop below, so a freshly re-keyed entry gets its buffers in the same pass". v7 now only deletes `racial` and `racial2`; it re-keys nothing.

**Fix:** "Schema v7 (49-03): drops the legacy "racial"/"racial2" slots (Phase 67). Runs before v8."

### IN-04: v12 clears runtime state piecemeal instead of using the shared helper

**File:** `BuffEngine.lua:710-715`

**Issue:** `ns:MigrateDropRacials` clears `ReleaseProc`, `activeTimers` and `cooldownStarts` by hand. The shared helper `ns:ClearTrackerRuntimeState` (`BuffEngine.lua:1060`) exists so that a removal clears everything, including `previewTimers` and `auraState`. There is no bug today, because all of those are empty at ADDON_LOADED, the only caller. But this is a third copy of the list the helper's own comment describes as "the single list", and it has already drifted.

**Fix:** Replace the four lines with `ns:ClearTrackerRuntimeState(key)`.

### IN-05: Redundant disjunct in the case D field assertion

**File:** `scripts/migrate-dryrun.js:922`

**Issue:** `after.get(field) === before[field] || (after.get(field) instanceof Map && after.get(field) === before[field])` has a second clause that is fully covered by the first, so it tests nothing extra. It looks as if it was meant to allow a nested table (e.g. `alternatives`) to stay the same object, but the first clause already does that.

**Fix:** Keep only `after.get(field) === before[field]`.

---

_Reviewed: 2026-10-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
