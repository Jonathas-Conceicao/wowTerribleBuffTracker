---
phase: 82-other-class-rows
reviewed: 2026-11-09T00:00:00Z
depth: deep
files_reviewed: 1
files_reviewed_list:
  - Providers.lua
findings:
  critical: 0
  warning: 0
  info: 5
  total: 5
status: issues_found
---

# Phase 82: Code Review Report

**Reviewed:** 2026-11-09
**Depth:** deep (diff `7451564..eed9197 -- Providers.lua`, traced through Core.lua, BuffEngine.lua and ReminderClick.lua)
**Files Reviewed:** 1
**Status:** issues_found (comment accuracy only; no behaviour defect)

## Narrative Findings (AI reviewer)

## Summary

Phase 82 adds 13 Forever rows (Providers.lua:1193-1212), 7 group calls inside the
`if ns.CLIENT_IS_FOREVER` block (Providers.lua:1291-1330), and a header note (1079-1082). I checked
each focus item against the code and the research. None of them shows a behaviour defect.

- **IDs vs research.** Every row ID matches §5 or §12.2: 11735, 696, 10432, 408510, 10952, 15473,
  10293, 25296, 18788 with aura 18789, 19312, 10958, 10170 and 10174. Every group member matches
  §12.2/§12.3 exactly, including:
  - Devotion 465/10290/643/10291/1032/10292
  - Retribution 7294/10298-10301
  - Concentration 19746
  - Shadow 19876/19895/19896, Frost 19888/19897/19898 and Fire 19891/19899/19900
  - Monkey 13163, Cheetah 5118, Pack 13159, Wild 20043/20190 and Beast 13161
  - Amplify 1008/8455/10169, Dampen 604/8450/8451/10173
  - Shadow Protection 976/10957, Prayer 27683
  - Demonic Sacrifice alternatives 18790-18792

  No Viper (34074), Falcon (469145), Sanctity (20218), Soul Link or SoD/NPC ID appears.
- **No row ID in two group calls.** I read the 22 calls in the block by hand: every row ID
  appears in exactly one call. The rows with no group (25780, 10952, 15473, 19312) are in none.
  `82-check-rows.js` agrees. On Forever, the ungated `MetaReminderGroup(465, 317920, 32223)` at
  :1232 does nothing, because 465 has no row there.
- **One-way vs mutual.** These pairs are mutual, because both IDs are rows:
  - 11735/696
  - 10432/408510
  - 10170/10174

  Rank IDs and the "any" members are one-way, because they have no row. A cast of a mutual
  partner starts both rows: the cast index resolves its own row, and `alternativeKeysBySpell`
  starts the other one. The `altKey == metaReminderKey` skip prevents a double start.
- **Permanent rows.** 15473, 10293 and 25296 get `duration = nil`, the same shape as the retail
  465 row. `StartReminderFromCast` sets only `auraState` and queues the post-cast re-check. There
  is no timer.
- **Demonic Sacrifice `auraID`.** The `opts.auraID` shape is the same as on the Phase 64 rows
  (474750 and 364342). `ApplyMetaReminderDef` copies it at :1437. On Forever,
  `RebuildRankIndex` builds `detailedRankFamilies` = {18789} plus the family of 18788
  (Core.lua:1824-1838). `RebuildReminderWatch` then appends 18790-18792. `FillUserBuffProc`
  prefers `satisfiedByWatch`, so a timer started by sacrificing a voidwalker or succubus stays
  alive on 18790/18791/18792. `castID` defaults to 18788. A metaReminder on Forever had never
  used `auraID` with rank coverage before. The path it takes is the existing user-buff WR-04
  path, so no new code is involved.
- **Clicks.** No new row sets `allyCast` or `castID`. `ReminderCastID` returns the row's own ID,
  `ResolveCastName` casts it by name (highest known rank), and `ReminderCastUnit` returns
  `"player"`. A click shows only while the reminder is visible, so the Shadowform click always
  enters the form.
- **Retail.** Every new row defaults to the `forever` client and returns early at :1139. Every
  new group call is inside the gated block. On retail, the only change in Providers.lua is
  comments.

## Info

### IN-01: The "Priest self buffs" banner also covers Shadow Protection, which is not self-only

**File:** `Providers.lua:1199`
**Issue:** Shadow Protection can be cast on other players. That is why research §12.2 lists its
ranks and Prayer as alternatives (`:1296`). Calling it a "self buff" contradicts the reason the
group exists.
**Fix:** Change the banner to `-- Priest buffs (Phase 82, MREM-10/14/16): Inner Fire, Shadowform and Shadowguard (self only), Shadow Protection (others can apply it).`

### IN-02: The Devotion row says "the retail row's ID is never used here", but 465 is in the Forever block

**File:** `Providers.lua:1205` (compare `:1298-1302`)
**Issue:** 465 is the second member of the paladin aura group. The comment means that 465 is
never used as a row key, but it reads as "465 never appears on Forever".
**Fix:** `... (MREM-11; permanent; keyed on 10293, never on the retail row's 465, which is only an alternative here) ...`

### IN-03: "IDs are from research §12.3" is now incomplete

**File:** `Providers.lua:1088` and `Providers.lua:1240`
**Issue:** The Shadow Protection and Amplify/Dampen groups (`:1296`, `:1328`) come from §12.2's
"If ever added" rows. §12.3 has no call for either group. Someone checking these lists against
§12.3 would find two calls that are not there.
**Fix:** Change both lines to say "§12.2/§12.3".

### IN-04: The in-game-verification header is out of date for Mage, Paladin and Warlock

**File:** `Providers.lua:1095-1098`
**Issue:** The header says the Mage, Paladin and Warlock rows were tested in game, and that "the
other classes" keep "(unverified in game)". Phase 81 and Phase 82 added unverified rows to those
three classes:
- Mage: 10220, 22783, 10170, 10174
- Paladin: 10293
- Warlock: 11735, 696, 18788

Each row's trailing comment is correct. Only the header's rule no longer holds.
**Fix:** Change the header to say that the rows tested in 57.4-HUMAN-UAT are the ones without
"(unverified in game)", and that every row added later keeps the tag until it is reported.

### IN-05: Amplify/Dampen mutual group depends on a LOW-confidence non-stacking claim

**File:** `Providers.lua:1328`
**Issue:** Research §6 rates "Amplify and Dampen do not stack on Forever" as LOW confidence,
because the Forever tooltip does not say so. If they do stack, a mage who places both tiles never
sees the missing one while the other is up. The user chose this behaviour ("any one up hides
both", CONTEXT), so this is not a defect. It is still an assumption.
**Fix:** No code change. Add the stacking question to Phase 85's in-game checklist next to the
"(unverified in game)" tags. If they do stack, split the call into two one-way calls, each with
only its own ranks.

---

_Reviewed: 2026-11-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
