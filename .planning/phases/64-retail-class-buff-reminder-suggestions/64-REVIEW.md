---
phase: 64-retail-class-buff-reminder-suggestions
reviewed: 2026-10-01T02:15:05Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - Providers.lua
  - ReminderClick.lua
  - Core.lua
  - CDMTab.lua
findings:
  critical: 1
  warning: 1
  info: 3
  total: 5
status: fixed
fixed_at: 2026-09-30
resolution:
  CR-01: fixed (0bbee3e)
  WR-01: fixed (0bbee3e)
  IN-01: fixed (b5330c2)
  IN-02: skipped (accepted, see Resolution)
  IN-03: skipped (raised with the user, no ID changed)
---

# Phase 64: Code Review Report

**Reviewed:** 2026-10-01T02:15:05Z
**Depth:** standard (cross-file where the diff reaches: Core.lua rank index / reminder watch / load rule, BuffEngine.lua aura refresh, SecureTemplates.lua)
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Reviewed `git diff d9c7faf` for Providers.lua, ReminderClick.lua, Core.lua and CDMTab.lua, then traced how the change reaches the rest of the code.

**These parts are correct:**
- **Client tag.** `MetaReminderRow` reads `ns.CLIENT_IS_FOREVER` once. Core.lua loads before Providers.lua, so the value is set by the time the rows are built. An unregistered row is handled the same way everywhere: not offered, not loaded (`IsOrphanMetaReminder`), skipped by `ApplyMetaReminderDef` and absent from the cast index.
- **Devotion Aura group on Forever.** `MetaReminderGroup(465, ...)` does nothing on Forever because 465 has no row there.
- **Existing Forever rows.** These keep `auraID = nil`, so `ApplyMetaReminderDef` writes nothing new and no aura state is invalidated.
- **Overlay `unit` attribute.** It is written out of combat only (Flush's `InCombatLockdown` guard) and only on change. Pooled overlays are handled correctly: `_unit` is nil on a new overlay, and `SetAttribute("unit", nil)` clears the attribute on a reused one. `SECURE_ACTIONS.spell` passes a nil unit to `CastSpellByName`, which gives the game's default targeting as intended.
- **IDs.** Every ID matches 64-CONTEXT.md's table.

**Main defect:** `ApplyMetaReminderDef` still forces `coverAllRanks = true` on every metaReminder. Retail never had a rank-covering entry before, so this phase turns on the name-matched spellbook family scan on retail for the first time. That has two effects:
1. The Arcane Familiar row's watch list picks up its own talent 205022 (CR-01).
2. On retail, rank families are now rebuilt uncached on every `SPELLS_CHANGED`, including in combat, which the 57.5 WR-04 cache was built to prevent (WR-01).

Two Core.lua comments that say this can never happen on retail are now false.

## Critical Issues

### CR-01: Arcane Familiar's watch list includes talent 205022, which can keep the reminder from ever showing

**File:** `Providers.lua:1616`, `Providers.lua:1712-1714`; reached through `Core.lua:1834-1858` (`RebuildRankIndex`), `Core.lua:930-990` (`ResolveRankFamily` step 3), `Core.lua:1683-1686` (`RebuildReminderWatch`), `BuffEngine.lua:1846-1879` (`RefreshAuraStates`)

**Issue:**
1. `ApplyMetaReminderDef` sets `coverAllRanks = true` on `metaReminder:210126`.
2. `RebuildRankIndex` therefore calls `ResolveRankFamily(210126)`.
3. Step 2 of that function takes the spell name of 210126, "Arcane Familiar".
4. Step 3 adds every Spell-type player spellbook item with that name. Retail's spellbook lists passive talents, so the talent 205022 "Arcane Familiar" (the row's `knownID`) joins the family.
5. The row has no `auraID`, so `RebuildReminderWatch` uses `ns.rankFamilies[key]` as the watch list: `{210126, 205022, ...}`.

`RefreshAuraStates` reads every ID on that list with `C_UnitAuras.GetPlayerAuraBySpellID`, and a talented passive is normally present on the player as a permanent hidden aura. If that read returns it:
- `present = true` permanently.
- `openEnded = true` (no readable expiry), so no timer is ever started or synced from the real familiar aura 210126.
- The Arcane Familiar reminder never shows: not when the familiar is gone, and never in a lead window.

The same family also writes `rankIndexMetaReminder[205022]` (harmless, since a passive is never cast).

This is the one new row whose watched aura shares a name with its load spell. Blood Pact's `knownID` is Summon Imp, a different name, so Forever never hit this. Whether the passive aura is returned can only be confirmed in game (Phase 66). The family membership itself follows from the code as written.

**Fix:** Do not force rank coverage where ranks do not exist. Use the existing named answer, so no new flavour comparison is added:
```lua
-- ApplyMetaReminderDef
local covers = ns.CLIENT_HAS_SPELL_RANKS == true or nil
if entry.coverAllRanks ~= covers then
	entry.coverAllRanks = covers
end
```
A retail metaReminder then watches its single aura ID (`def.auraID or spellID`), the same as a retail userReminder. This also fixes WR-01. If coverage must stay, exclude `def.knownID` from the family when it differs from `def.spellID`, or give the Arcane Familiar row an explicit `auraID = 210126`. That second option alone does not help, because `detailedRankFamilies` still appends the family.

## Warnings

### WR-01: Retail now rebuilds metaReminder rank families uncached on every SPELLS_CHANGED, including in combat

**File:** `Providers.lua:1712-1714`; `Core.lua:1777-1797` (the early-out that used to cost retail nothing), `Core.lua:1837` (`ResolveRankFamily`, not `CastRuleFamily`), `Core.lua:2190-2198` (SPELLS_CHANGED calls `RebuildRankIndex` even in combat), `Core.lua:1702-1707`

**Issue:** Before this phase, `rebuildOwners` was always empty on retail, and the comment at Core.lua 1781-1783 relied on "a metaReminder ... is only ever offered on Forever". Every retail metaReminder is now an owner, so each retail `SPELLS_CHANGED` runs `ResolveRankFamily` directly. That means base/override lookups plus a full spellbook walk, with no `ns.endRuleFamilies` cache. Retail fires `SPELLS_CHANGED` often in combat (talent overrides, proc replacements).

The 57.5 review WR-04 note (Core.lua 1494-1500) explains why retail families must not be re-read in combat. An in-combat `GetBaseSpell`/`GetOverrideSpell` answer that differs, or is secret and so dropped by `AddFamilyID`, changes the family's contents. Then:
1. `RebuildReminderWatch` sees a different list and sets `ns.auraState[key] = nil`.
2. A nil state hides the reminder.
3. In combat on Midnight, `RefreshAuraStates` usually cannot re-read the aura (`ShouldAurasBeSecret`), so the reminder stays hidden until combat ends.
4. The running proc's `aliveBuffs` is also re-pointed mid-fight.

That is a correctness regression for a reminder meant to fire mid-combat (57.2-05). It also makes the comments at Core.lua:930 ("This never actually runs on retail") and Core.lua:1781-1783 false.

**Fix:** Use the CR-01 fix: no forced `coverAllRanks` on a client without spell ranks. If coverage must stay on retail, resolve retail families through `ns:CastRuleFamily` (cached, wiped only out of combat) rather than `ResolveRankFamily`. Either way, update the two Core.lua comments.

## Info

### IN-01: Stale comments now contradict the code

**File:** `Providers.lua:1512`, `Providers.lua:1521-1522`, `Core.lua:930-933`, `Core.lua:1781-1783`

**Issue:**
- Providers.lua 1512 still says "Each aura ID is assumed equal to its spell ID". Rows can now carry `opts.auraID` (474750 maps to 474754, 364342 maps to 381748).
- Providers.lua 1521-1522 describes rank families as universal.
- The two Core.lua comments state that retail never has a `coverAllRanks` entry. With this phase that is false (see WR-01).

**Fix:** Reword them to match whichever behaviour the CR-01/WR-01 fix settles on, for example: "the aura ID is the row's `auraID`, else the spell ID".

### IN-02: An unreadable build number now registers the wrong client's rows instead of failing closed

**File:** `Providers.lua:1555-1559`, `Core.lua:829-844`

**Issue:** `isForeverBuild` is false when `GetBuildInfo` is unreadable. Before this phase, false only withheld Forever-only offers, which was safe. With per-row tags, false actively does two things:
- It registers the retail rows. On Forever, 6673, 465 and 21562 have other meanings, the exact leak the user decision exists to prevent.
- It unregisters every Forever row, so each placed Forever class-buff reminder becomes an orphan whose tooltip says "Remove it".

This is very unlikely in practice (`GetBuildInfo` is not a secret API), but the documented "absent the ability to tell, do not offer" stance no longer holds for this consumer.

**Fix:** If wanted, register `retail` rows only when the build is positively known to be retail. Reusing `buildVersionIsNumber` (already computed in the same Core.lua block) as a second named field keeps it to one range comparison. Otherwise, document the accepted direction in the MetaReminderRow comment.

### IN-03: Retail Mark of the Wild ID 102046. Check it in game.

**File:** `Providers.lua:1618`

**Issue:** The row matches 64-CONTEXT.md's table (102046), so this is not a transcription error. However, the widely published retail Mark of the Wild spell/aura ID is 1126. If 102046 is not the player-castable spell, the row is never offered (`ResolveSpellKnown` false), with no error.

**Fix:** Confirm with TBT's ID tooltip during Phase 66. If the cast ID is 1126, change the row before anyone places it: the key `metaReminder:<spellID>` is saved, so a later change orphans placed copies.

## Resolution

Fixed 2026-09-30 by gsd-code-fixer.

### CR-01 and WR-01: fixed in `0bbee3e`

One change resolves both. `ns:ApplyMetaReminderDef` now sets `coverAllRanks` to `ns.CLIENT_HAS_SPELL_RANKS == true or nil`, writing only when the value changes. This reuses the existing named answer, so no flavour comparison is added.
- **Forever:** the value stays `true`, so behaviour is unchanged.
- **Retail:** the value is `nil`. A built-in class-buff reminder is no longer a rank owner and watches its single aura ID (the row's `auraID`, else its spell ID), exactly like a retail userReminder.
- **Effect on retail:** Arcane Familiar watches only 210126, with no 205022 in its list. `rebuildOwners` is empty again on retail, so `SPELLS_CHANGED` never runs `ResolveRankFamily` there.
- **Entries from the earlier Phase 64 build:** a retail entry saved with `coverAllRanks = true` is cleared on its next rebuild. `ApplyMetaReminderDef` runs inside `RebuildCastIndex`, which comes before the owner scan in `RebuildRankIndex`, so that same rebuild already treats the entry as uncovered.
- **Checks:** `node scripts/aura-read-gate.js` passes, and so does `node scripts/migrate-dryrun.js --selftest`.

### IN-01: fixed in `b5330c2`

Providers.lua comments:
- The aura ID is now described as the row's `auraID`, else its spell ID.
- Rank families are now described as counting on Forever only.

The two Core.lua comments (`ResolveRankFamily` step 3, `RebuildRankIndex` early-out) are true again after the CR-01 fix. They now also give the reason for metaReminders.

### IN-02: skipped

Accepted risk; no code change. `GetBuildInfo` is not a secret API, and an unreadable build number is not a realistic state. Making retail rows depend on a positively identified retail build would add a second named consumer for an edge case nobody has observed. Failing closed would also hide every retail row if it ever fired. Revisit only if an unreadable build is seen in game.

### IN-03: skipped (raised with the user)

The row matches the user's own data table in 64-CONTEXT.md (102046). No ID was changed. The user has been asked to confirm the castable Mark of the Wild ID with TBT's ID tooltip during Phase 66, before anyone places the row.

**Update 2026-10-01 (Phase 65):** The user's in-game check showed 102046 is a same-named spell no druid knows; the row was changed to the druid's spell 1126 in `f2d4209` before anyone placed it. Lightning Shield (Shaman, 192106, 60 minutes, retail) was added after this review in `a793fe9`.

---

_Reviewed: 2026-10-01T02:15:05Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
