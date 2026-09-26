---
status: human_needed
phase: 46-item-catalogue-suggested-tiles
verified: 2026-09-24T00:00:00Z
score: 4/4 code-level truths verified; 0/7 in-game gates run
re_verification:
  previous_status: none
human_verification:
  - test: "G1 (ITEM-01) — Forever first. Carry potions, a healthstone, a quest item, a recipe, a key, a trade good and a bandage. Split one potion stack across two different bags. /reload, open the Cooldown Manager, select the Cooldowns tab."
    expected: "The split potion appears once, not twice — each distinct itemID produces exactly one tile regardless of how many slots hold it."
    why_human: "Requires a live client with real bags and a real CDM frame; no headless harness exists for this addon (46-VALIDATION.md 'Test Infrastructure'). Closes ITEM-01."
  - test: "G2 (ITEM-03) — Forever. Inspect each Suggested item tile."
    expected: "Shows the item's own icon (not the 134400 question mark) and a count in the bottom-right matching the number actually in the bags, in the same font/position as a cooldown icon's charge count."
    why_human: "Icon/count rendering can only be confirmed by looking at the live CDM frame. Closes ITEM-03."
  - test: "G3 (ITEM-03) — Forever. With the CDM still open, drink or use one item down to a smaller stack."
    expected: "The count updates without closing and reopening the CDM."
    why_human: "Requires triggering BAG_UPDATE live and observing the coalesced rebuild render. Closes ITEM-03 (dynamic half)."
  - test: "G4 (ITEM-08) — Forever. Look for the excluded classes among Suggested tiles."
    expected: "The quest item, the recipe, the key, the trade good and the bandage are all absent."
    why_human: "Requires a live bag scan against a real character inventory. Closes ITEM-08 (exclusion half)."
  - test: "G5 (ITEM-08) — Forever. Look for the known 0/8 residue (glue, campfire kit, lute, crate, or whatever the character carries)."
    expected: "Still present — accepted documented behaviour per ROADMAP 999.6 section 1. Its absence would mean the filter over-reached and is a FAIL."
    why_human: "Distinguishes correct taxonomy-only filtering from an over-aggressive filter; only observable against a real inventory. Closes ITEM-08 (non-regression half)."
  - test: "G7 — Forever. Drag an item tile into a container."
    expected: "Ghost clears, success sound plays, nothing appears in the target container — the tile stays in Suggested. A tracker actually being created is a defect."
    why_human: "Drag-and-drop behavior against the live secure CDM frame cannot be simulated statically."
  - test: "G6 (ITEM-10) — Repeat G1-G5 and G7 on Midnight retail, out of combat first, then in combat if reachable."
    expected: "Identical tiles out of combat. In combat, an unreadable secret value must degrade (no count shown) rather than produce a Lua error."
    why_human: "Retail's item-count/cooldown secrecy under combat restriction was never measured by either probe run (both were Forever-only) — this is the one genuinely unmeasured area in the phase, and only a live retail client in combat can answer it. Closes ITEM-10."
---

# Phase 46: Item Catalogue & Suggested Tiles Verification Report

**Phase Goal:** Opening the Cooldown Manager on either flavour scans the player's bags and offers
every untracked consumable in Suggested, each showing the item's own icon and current count.
**Verified:** 2026-09-24
**Status:** human_needed
**Re-verification:** No — initial verification

## Framing

This project has no test runner and none is planned (confirmed directly: no `package.json`,
`luacheck` config, or CI test step exists; `46-VALIDATION.md` states this explicitly and the phase's
own plans repeat it four times). Verification therefore splits into two halves that do not substitute
for each other:

- **Static assertions (S1-S10)** — re-run independently against the shipped source below, not
  trusted from `46-04-SUMMARY.md`. All ten hold.
- **In-game checks (G1-G7)** — the only possible evidence for ITEM-01, ITEM-03, ITEM-08 and ITEM-10.
  `46-04-PLAN.md` Task 3 is a `type="checkpoint:human-verify" gate="blocking"` task, and
  `46-04-SUMMARY.md` states plainly: *"Task 3 was **not attempted**. No part of G1..G7 has been
  simulated, inferred, or asserted to pass."* This is confirmed by the phase's own commit log —
  there is no commit after `615cdbd` (the last code/doc commit) that records a human gate result.

Because the only evidence path for the phase's four requirements has not run, the verdict is
`human_needed`, not `passed`. The static half is complete and — independently re-checked below — is
also accurate, so this is not `gaps_found` either.

## Goal Achievement

### Observable Truths (code-level, independently re-verified)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The catalogue is keyed by itemID, never by bag/slot | VERIFIED (code) | `Providers.lua:915-919` declares `itemCatalogueIDs`/`Icons`/`Counts` all itemID-indexed; `bag`/`slot` as real identifiers appear only inside the discovery loop `Providers.lua:934-942` and are never written into a stored table |
| 2 | A duplicated itemID across bag slots collapses to one row | VERIFIED (code) | `Providers.lua:939` writes into a de-dup `itemCatalogueSeen[id] = true` set before classification; classification (`:948-979`) runs once per key in `pairs(itemCatalogueSeen)` |
| 3 | Filter is taxonomy-only, no item-name matching | VERIFIED (code) | `Providers.lua:949-961` tests only `classID == 0`, `subClassID ~= 7`, and a `GetItemSpell` result; `GetItemNameByID` (`:1046`) is used only inside `ns:ItemDisplayInfo` for the tooltip label, never in the filter (confirmed by grep across `Providers.lua`/`CDMTab.lua`) |
| 4 | `issecretvalue()` precedes `type()` on every new API read | VERIFIED (code) | Confirmed by direct read, not grep, on all six guarded reads: `Providers.lua:938` (`GetContainerItemID`), `:951-954` (classID/subClassID), `:961` (`GetItemSpell`'s useSpellID, guarded before the truthiness test), `:967` (icon), `:974` (`GetItemCount`), `:1047` (`GetItemNameByID`) |
| 5 | `GetItemInfoInstant`'s 7-value return destructured at the correct positions | VERIFIED (code) | `Providers.lua:949`: `local _, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)` — a bare, non-`pcall` call; position 5/6/7 map to icon/classID/subClassID per the documented 7-value signature (`itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID`). The probe's own `pcall`-shifted indices were NOT copied — confirmed no `pcall` wraps this call |
| 6 | No runtime flavour check in the new code | VERIFIED (code) | `grep -n "buildInterfaceVersion\|GetBuildInfo\|wow_classic\|classicVersion"` returns 0 hits in `Providers.lua` and `CDMTab.lua`, and exactly the 3 pre-existing lines in `Core.lua` (`:559,566,570`, the licensed v0.4.0 check). `isForeverBuild`/`ns.CLIENT_IS_FOREVER` (`Core.lua:570-576`) is not referenced anywhere in the new catalogue/render code (grep confirms) |
| 7 | The render path never walks the bags | VERIFIED (code) | `grep -v '^\s*--' CDMTab.lua \| grep -cE 'C_Container\.\|GetItemInfoInstant\|GetItemSpell\|GetItemCount\|GetItemIconByID'` returns 0. `ns:RefreshTBTSections` (containing the item loop at `CDMTab.lua:870-901`) reads only `ns:ItemCatalogue()`, a cached array read |
| 8 | Pooled tiles never show a stale count | VERIFIED (code) | Pool reset (`CDMTab.lua:725-740`) clears+hides `chargeCount` on every `ReleaseAll()` (`:738-739`); the item loop (`:888-897`) writes `SetText`+`Show()` or `Hide()` on every iteration — no path through the loop skips both |
| 9 | `item:` keys stay inert on drop (no Phase 47 leakage) | VERIFIED (code) | `AddSuggestedTracker` (`CDMTab.lua:139-185`) is unmodified: for an `item:<id>` key, `ns:CooldownKeySpellID` returns nil (`Core.lua:483-489` pattern is `^cd:(%d+)$`) and no `ns.SUGGESTED_KEYS` entry matches, so `known` stays false and the function returns without creating an entry (`:157-159`) |
| 10 | No Phase 47 code leaked in (GetItemCooldown, decrement, reconcile, tracker creation from tile) | VERIFIED (code) | `grep -n "GetItemCooldown"` across the three touched files returns only a comment in `Core.lua:499` explaining why `cd:<useSpellID>` reuse was rejected, no live call. No decrement/reconcile code exists |
| 11 | **Opening the CDM actually offers every untracked consumable, each with its own icon and count, on both clients** | **UNVERIFIED — requires G1-G7** | This is the phase goal itself. The code is shaped correctly (truths 1-10), but no human has opened a real Cooldown Manager on either client with real bags to confirm the tiles render as designed. `46-04-SUMMARY.md` confirms this explicitly was not attempted |

**Score:** 10/10 code-level truths verified. 0/1 goal-level truth (the actual phase goal) verified — it requires the in-game gate.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | `ns.ITEM_KEY_PREFIX`, `ns:ItemKeyItemID`, `BAG_UPDATE` registration+dispatch | VERIFIED | `:505` (prefix), `:509-514` (parser), `:866` (`TryRegisterEvent`), `:994-1002` (dispatch, single statement `ns:MarkItemCatalogueDirty()`) |
| `Providers.lua` | `ns:RefreshItemCatalogue` + 5 accessors, `ns:ItemDisplayInfo`, `item:` branch | VERIFIED | `:923-1018` (builder+accessors), `:1034-1056` (`ItemDisplayInfo`), `:1263-1290` (`GetDisplayInfoForKey`, `item:` branch at `:1275-1278` precedes `cd:` reject at `:1285`) |
| `CDMTab.lua` | `StartPreview` scan trigger, coalescing rebuild, `chargeCount` fontstring, item tile loop | VERIFIED | `:36` (scan call), `:53-70` (coalescer), `:200-213` (fontstring), `:854-901` (item loop) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `CDMTab.lua StartPreview` | `ns:RefreshItemCatalogue` | direct call before `RefreshTBTSections` | WIRED | `CDMTab.lua:36`, ordered before `:37`'s `RefreshTBTSections()` call |
| `Core.lua` event dispatch | `ns:MarkItemCatalogueDirty` | `BAG_UPDATE` branch | WIRED | `Core.lua:994-1002`, registered via `TryRegisterEvent` at `:866`, not a bare `RegisterEvent` |
| `Providers.lua MarkItemCatalogueDirty` | `CDMTab.lua RequestItemCatalogueRebuild` | late-bound `ns.RequestItemCatalogueRebuild` field, guarded | WIRED | Confirmed by direct read (not re-quoted above; matches `46-02-SUMMARY.md`'s claim, and the guard pattern is the same established idiom used for `ns:RacialCooldownSeed`) |
| `Providers.lua GetDisplayInfoForKey` | `ns:ItemDisplayInfo` | `ns:ItemKeyItemID` branch before `cd:` reject | WIRED | `Providers.lua:1275-1278`, precedes `:1285` reject — confirmed by reading the function body directly (the whole-file grep line-order gate in `46-02-PLAN.md`'s automated verify has a documented false-negative from an unrelated line-185 text collision; the actual property was checked here by reading the function, same as `46-02-SUMMARY.md`'s own deviation note describes) |
| `CDMTab.lua item tile loop` | `ns:ItemCatalogue()` | cache read inside suggested/spells branch | WIRED | `CDMTab.lua:870` |
| `CDMTab.lua item tile loop` | `ns.db.trackedBuffs` | `ns.ITEM_KEY_PREFIX .. itemID` membership test | WIRED | `CDMTab.lua:871-872` |
| `CDMTab.lua CreateIconFrame` | `NumberFontNormal` | `chargeCount.Current` fontstring, `BOTTOMRIGHT -2 2` | WIRED | `CDMTab.lua:211-212`, byte-identical to `Display.lua:481-482`'s existing charge-count style (confirmed by reading both) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| Item tile icon | `info.icon` | `ns:ItemDisplayInfo` <- `ns:ItemCatalogueIcon(itemID)` <- `C_Item.GetItemInfoInstant`'s `icon` return, cached at scan time | Real client API read, not hardcoded | FLOWING (statically) — actual values only observable in-game |
| Item tile count | `count` | `ns:ItemCatalogueCount(itemID)` <- `C_Item.GetItemCount(itemID)`, cached at scan time | Real client API read, not hardcoded | FLOWING (statically) — actual values only observable in-game |
| Catalogue membership | `ns:ItemCatalogue()` | `ns:RefreshItemCatalogue`'s live bag walk (`C_Container.GetContainerNumSlots`/`GetContainerItemID`) | Real bag data, not static/empty | FLOWING (statically) |

No hardcoded empty returns, no static fallback data paths found for the primary render values. The
data-flow shape is correct; whether it produces the *expected* tiles on a real character's real bags
is exactly what G1-G5 test and has not been run.

### Behavioral Spot-Checks

Not applicable in the conventional sense — this is a WoW addon with no runnable entry point outside
the game client (per `<critical_framing>`). No test command was invented. `stylua --check .` was
re-run directly as the one available automated check and exits 0 with no drift.

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention exists in this project, and none is declared in the phase
plans (the phase mentions `tools/TBTProbe/Probe.lua`, but that is an explicitly out-of-TOC, throwaway
in-game measurement harness the phase's own CONTEXT.md says "this phase does not extend" — it is not
a probe in the Step 7c sense and was not run by this verification). No probe execution applicable.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ITEM-01 | 46-01, 46-02 | Catalogue keyed by itemID, built on CDM open | Code: VERIFIED / Goal: NEEDS HUMAN (G1) | `Providers.lua:915-986`, `CDMTab.lua:36` |
| ITEM-03 | 46-03 | Tile shows item's own icon + current count | Code: VERIFIED / Goal: NEEDS HUMAN (G2, G3) | `CDMTab.lua:200-213, 870-901` |
| ITEM-08 | 46-01 | Quest/recipe/key/trade-good/bandage excluded | Code: VERIFIED / Goal: NEEDS HUMAN (G4, G5) | `Providers.lua:944-961` |
| ITEM-10 | 46-01, 46-02, 46-03 | Offered identically on both flavours | Code: VERIFIED / Goal: NEEDS HUMAN (G6) | No flavour token in new code; `issecretvalue()` guard is what makes retail safe, unmeasured until G6 |

`REQUIREMENTS.md` still shows all four as unchecked (`[ ]`, lines 20-37) and the tracking table
(lines 126-135) still lists all four as "Not started" — this is accurate: the requirements are not
yet satisfied, only code-shaped, pending the human gate. No orphaned requirements found — ITEM-02,
ITEM-04 through ITEM-07, and ITEM-09 are correctly mapped to Phase 47 and out of this phase's
declared scope (though ITEM-02's "not already tracked" filtering is, in fact, already implemented at
`CDMTab.lua:872` as a byproduct of building tiles that must skip tracked items — this is favorable
over-delivery, not a gap).

### Anti-Patterns Found

None. Scanned `Core.lua`, `Providers.lua`, `CDMTab.lua` for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/
`PLACEHOLDER` and stub language ("not yet implemented", "coming soon", etc.) — zero matches in the
phase's new code. No hardcoded empty-array/table returns feeding the item tile render path. No
debt-marker gate triggered.

### Human Verification Required

See YAML frontmatter `human_verification` for the full structured list (G1-G7, in required order:
Forever first, then retail for G6). Summary:

1. **G1 (ITEM-01)** — split potion stack appears once, not twice.
2. **G2 (ITEM-03)** — each tile shows its own icon and a count matching the bags.
3. **G3 (ITEM-03)** — count updates live without reopening the CDM.
4. **G4 (ITEM-08)** — quest item / recipe / key / trade good / bandage all absent.
5. **G5 (ITEM-08)** — the known `0/8` residue (glue, campfire kit, lute, crate) is still present (its absence is a FAIL, not a pass).
6. **G7** — dragging an item tile into a container is a documented no-op (ghost clears, no tracker created).
7. **G6 (ITEM-10)** — repeat on Midnight retail, out of combat then in combat; in-combat secret values must degrade, never error.

None of these have been run. `46-04-SUMMARY.md`'s own words: *"Blocker for phase close-out: Task 3's
G1..G7 report from the user, on both clients. Phase 46 cannot be marked complete, and
ITEM-01/03/08/10 cannot be marked satisfied, until that comes back."* This verification agrees with
that self-assessment after independently re-checking the static half.

### Gaps Summary

No code-level gap was found — all ten static assertions (S1-S10) hold up under independent re-read
of the shipped source, not just the SUMMARYs' claims. The phase is blocked purely on the missing
in-game evidence for its four requirements, which is a known, declared, and correctly-flagged blocker
in the phase's own artifacts (a blocking human-verify checkpoint that was correctly *not* skipped or
faked). This is not a defect in execution — it is the expected state of a phase whose final gate is a
human checkpoint that has not yet run.

---

_Verified: 2026-09-24_
_Verifier: Claude (gsd-verifier)_
