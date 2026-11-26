---
phase: 90-headmaster-s-charge-reminder
reviewed: 2026-11-26T18:20:18Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - Providers.lua
  - ReminderClick.lua
  - Core.lua
  - scripts/reminders-doc-check.js
  - docs/REMINDERS.md
findings:
  critical: 0
  warning: 0
  info: 4
  total: 4
status: issues_found
---

# Phase 90: Code Review Report

**Reviewed:** 2026-11-26T18:20:18Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found (Info only)

## Summary

Scope: `git diff aafbafb..HEAD` for the five files above. I checked each focus area against the
code and against Blizzard's secure-action source.

- **Secure click.** `item = "16"` takes this path: `SECURE_ACTIONS.item` (wow-ui-source
  `SecureTemplates.lua:418-439`) → `SecureCmdItemParse("16")` matches `^(%d+)$` and returns
  `GetInventoryItemLink("player", 16)` with slot `"16"` (`ChatFrameUtil.lua:1197-1211`). That link
  points at an equipped item, so `IsEquippedItem` is true, the `EquipItemByName` branch is skipped,
  and the click reaches `UseInventoryItem("16", "player")`. No string `item:13937` exists anywhere
  in the code. The overlay is placed only while `GetInventoryItemID("player", 16) == 13937`
  (`Providers.lua:1477-1489`), so a click can never equip the staff from the bags.
- **Combat.** `Flush` returns early under `InCombatLockdown()` and marks itself dirty.
  `MarkReminderClicksDirty` does not schedule anything in combat. `PLAYER_REGEN_ENABLED` always
  runs `Flush`. Overlays are hidden in combat by the `[combat] hide` state driver, so a weapon swap
  during combat cannot leave a usable stale `"16"` overlay. Nothing protected is written in combat.
- **PLAYER_EQUIPMENT_CHANGED.** `local slot = ...` reads the event's first payload value (the
  equipment slot) from the OnEvent vararg. `IsMetaReminderOfferSlot` checks `issecretvalue` and the
  type before the lookup. On retail the row returns at the client gate before
  `metaReminderOfferSlots` is written, so the set is empty and the branch costs one table read.
  The `BAG_UPDATE_DELAYED` path is unchanged.
- **Offer and overlay follow equip and unequip.**
  - The Suggested offer: `MetaReminderSuggestionKeys` reads the equipped slot again on every
    `RefreshTBTSections`. Slot 16 changes reach that through `MarkItemCatalogueDirty` →
    `RequestItemCatalogueRebuild`, which runs only while the CDM is open, at most once per frame.
  - The click overlay: `ReminderEquippedUse` returns `usesSlot = true` even when the staff is not
    equipped. So whenever a Headmaster's Charge icon is shown, `reminderItemClickActive` is true
    and an equip or unequip marks the overlay dirty.
- **Regressions.** The familiar and Well-Rested rows behave as before:
  - `ReminderEquippedUse` returns `nil, false` for them.
  - `useItems and PickUseItem(useItems) or slotAttr` gives the same result as before when
    `slotAttr` is nil.
  - `MetaReminderSuggestionKeys` still takes the `ItemInBags` branch for Well-Rested.
  - Well-Rested's `offerItem` 211527 is now collected twice by the doc check (once from
    `useItems`, once from `offerItem`); the Map absorbs the duplicate.
- **Doc check.** `node scripts/reminders-doc-check.js` reports PASS (144 Forever IDs, 15 retail
  IDs, 52 rows). `--selftest` reports PASS (48 cases). All five files are `w/crlf`.

I found no correctness or security defects. The four Info items below are about fragility and how
strong the tests are.

## Narrative Findings (AI reviewer)

## Info

### IN-01: Suggested redraw piggybacks on the consumables-catalogue dirty flag

**File:** `Core.lua:2230-2231`
**Issue:** The change in slot 16 has nothing to do with the bag-consumables catalogue. The code
calls `ns:MarkItemCatalogueDirty()` only because `RequestItemCatalogueRebuild` happens to finish
with `ns:RefreshTBTSections()` (`CDMTab.lua:78-80`). This makes the reminder offer depend on an
implementation detail of the item catalogue. If that consumer is ever changed to redraw only when
the catalogue's contents change, the Headmaster's Charge tile will stop following equip and
unequip, and nothing will fail to show it. It also runs a full bag walk for an event that touches
no bag.
**Fix:** Expose a sections-only coalesced redraw (for example `ns:RequestSectionsRefresh()`, with
the same `configOpen` and once-per-frame gate) and call it here. Otherwise, add a comment at
`CDMTab.lua:78` saying the trailing `RefreshTBTSections` is relied on by the HCHG-02 equip redraw.

### IN-02: Forever's secure item path was verified against the retail FrameXML only

**Resolved 2026-11-26 (orchestrator):** WoWUI `forever-beta` has the same code:
`Blizzard_FrameXML/SecureTemplates.lua:418-438` (`SECURE_ACTIONS.item`) and
`Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:1197-1211` (`SecureCmdItemParse`) match retail line for
line, so `"16"` resolves to the equipped item's link and `UseInventoryItem(16)` on Forever too.

**File:** `ReminderClick.lua:6-9`, `Providers.lua:1472-1476`
**Issue:** The reasoning that `"16"` leads to `UseInventoryItem` and never to an equip cites
wow-ui-source (retail 12.x) `SecureTemplates.lua:418` and `ChatFrameUtil.lua:1197`. The row exists
only on Forever, whose FrameXML is the `forever-beta` branch of BigWigsMods/WoWUI. Classic-era
clients have historically used the same `SecureCmdItemParse`, so the risk is low, but this has not
been checked against the client that runs the code.
**Fix:** Check `SECURE_ACTIONS.item` and `SecureCmdItemParse` on WoWUI `forever-beta` and cite
them. Include it in the Phase 92 in-game verification together with the row's existing
`(unverified in game)` flag.

### IN-03: Doc check does not validate `offerSlot`

**File:** `scripts/reminders-doc-check.js:343-350`
**Issue:** The check requires `offerItem` to be an integer literal but never looks at `offerSlot`.
Two mistakes would pass the doc check and fail silently at runtime:
- `offerSlot = SLOT` (not a literal). Note that a string such as `"16"` would also make
  `metaReminderOfferSlots` miss the numeric event payload.
- `offerSlot` without `offerItem`. `ItemEquippedInSlot(nil, 16)` is always false, so the row would
  never be offered.

**Fix:** Where `optsBlank` matches `\bofferSlot\s*=`, require `/\bofferSlot\s*=\s*(\d+)\s*(?=[,;}])/`
and require `row.offerItem !== null`, and push a problem otherwise. Add the matching selftest
cases.

### IN-04: The `offerSlot` selftest assertion passes without the code under test

**File:** `scripts/reminders-doc-check.js:1138-1141`
**Issue:** The test checks `!sets[c].has('item:16') && !sets[c].has('spell:16')`. Nothing in the
parser could ever produce those keys from `offerSlot`, so the assertion passes whether or not the
implementation is right. It proves nothing beyond what the first half of the case already proves.
**Fix:** Drop it, or replace it with the IN-03 cases, which do exercise `offerSlot` parsing.

---

_Reviewed: 2026-11-26T18:20:18Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
