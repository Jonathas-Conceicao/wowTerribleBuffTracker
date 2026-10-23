---
phase: 76-buff-duration-on-bag-items
reviewed: 2026-10-22T23:58:05Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - BuffEngine.lua
  - Providers.lua
  - Display.lua
  - CDMTab.lua
findings:
  critical: 0
  warning: 1
  info: 5
  total: 6
status: issues_found
---

# Phase 76: Code Review Report

**Reviewed:** 2026-10-22T23:58:05Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Scope: `git diff 0c1e44e..HEAD -- '*.lua'`, commits 058acc3, b2fd938, c95049d and 7b4a30f. I checked the changed functions against the code they call: Core.lua's `IsCooldownSlotEntry`, `IsBagItemEntry`, `TrackerLoad`, `CooldownBuff*`, the `RebuildRankIndex` family build, BuffEngine's proc and aliveBuffs pools, `GetActiveTimers`, `ScanActiveTimersForCancellation`, `SetBuffSection`, `EndTrackerRuntime`, Display's `ApplyCachedIcon` and `ShowBuffTooltip`, and the CDMTab dialog walker (`RefreshState`, `ValidateAll`, the confirm handler, `OpenForAdd` and `OpenForEdit`).

Each focus point, verified:

- **Buff-only save path.** `ns:UpdateTrackedBuff` sends a bag item to `ns:UpdateTrackedItemBuff`. That happens right after the `IsEditableTracker` gate and before the spell-ID, duration, re-key and `fieldKeys` code. `UpdateTrackedItemBuff` writes only `buffEnabled`, `buffAuraID` and `buffDuration`. It never writes `entry.duration`, `spellID`, `key` or `load`, and never calls `RebuildRankIndex`. Holds.
- **Widening `ns:IsEditableTracker`.** It has exactly three callers: the CDMTab.lua:440 menu, CDMTab.lua:3094 `OpenForEdit`, and BuffEngine.lua:1414. No other path (Remove, duplicate check, cast, render) reads it. Trinket and Pot have no numeric `itemID`, so they stay excluded. Merge Mode `cdm:` entries are runtime-only and never reach the TBT tab menu. Holds.
- **Suggested tiles.** Every Suggested tile sets `sectionName = "suggested"` (CDMTab.lua:931, 1020, 1073), and that branch builds its own menu and returns before the Edit button. Holds.
- **Item Aura ID cannot be saved empty while the buff is on.** In the dialog, `follows` is false for META_ITEM, so `requiredMessage` applies while the box is ticked. In the engine, `UpdateTrackedItemBuff` refuses `buffEnabled == true` without a positive `buffAuraID` and `buffDuration`. Holds.
- **Greyed fields.** On a bag item, `NotItemField` greys only `spellID`, `duration`, `coverAllRanks` and `load`. `auraID` and `endOnCast` are hidden; `keepOnAuraLoss`, `alternatives` and `castID` were already hidden for this kind. For user kinds the hook always returns true, so `ApplyFieldEnabled(true)` only re-asserts defaults (white GameFontHighlightSmall labels, InputBoxTemplate text, an enabled dropdown). The `load` prefill now goes through `ns:TrackerLoad`, which maps user kinds exactly as the old inline code did. Cooldown, buff and reminder dialogs are unchanged.
- **Item cast path.**
  - The buff starts after `RefreshTrackedItemCooldowns`.
  - `StartCooldownBuffFromCast` refuses a hidden section, a bar container and a buff that is off.
  - The proc is pooled, and `itemID` is cleared by `AcquireProc`'s wipe.
  - The early-out for non-item casts is unchanged.
  - Two items sharing a use-spell: see IN-01.
- **Allocation.** No new allocation per tick or per cast. `ipairs`, pooled procs, pooled aliveBuffs and `C_Timer.After` with a named function allocate nothing. The preview table literal and the edit-time print are not hot paths.
- **Secret values and aura reads.** `ShowBuffTooltip` runs `issecretvalue(itemID)` before the type test. No new aura API call: `node scripts/aura-read-gate.js` passes.
- **Upvalue order.** `NotItemField` and `CarriesCooldownBuff` are declared above `TRACKER_FIELDS`. `SelectTab` (line 2978) comes before `OpenForEdit` (line 3092). Every cross-file call goes through `ns`.
- **Taint.** No secure frame, protected call or CDM frame is touched.
- **Formatting.** `stylua --check .` is clean, and all four files are `w/crlf` with no `\r\r`.

There are no blockers. One warning: the item commit breaks the dialog's "not read means not written" contract. The info items are a stale comment, a misleading comment about shared use-spells, duplicated post-commit code, a looser engine guard and a placeholder item name in the portrait.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: `ns:UpdateTrackedItemBuff` ignores `fieldKeys`, breaking the WR-02 "not read means not written" contract

**File:** `BuffEngine.lua:1344-1346` (call site `BuffEngine.lua:1421`)
**Issue:** The dialog contract (CDMTab.lua:1798-1805) says a field hidden by its own `visible()` is not read, so a save must leave its saved value alone. `UpdateTrackedBuff` keeps that contract by writing only the keys listed in `fieldKeys`. `UpdateTrackedItemBuff` is never passed `fieldKeys` (line 1421 forwards only `fields`), and it writes all three keys unconditionally:

```lua
entry.buffEnabled = fields.buffEnabled
entry.buffAuraID = fields.buffAuraID
entry.buffDuration = fields.buffDuration
```

Today all three buff fields are relevant for META_ITEM, so nothing is lost yet. But if `CarriesCooldownBuff` or any of the three `visible` hooks ever hides one of them for an item, or another caller passes a partial `fields` table, a save silently sets the saved Aura ID and Duration to nil. The header comment ("ignores fieldKeys and writes an explicit three-key list") makes this a deliberate design choice, but it breaks the documented contract.

**Fix:** Pass `fieldKeys` through and write only the buff keys that were read:

```lua
-- BuffEngine.lua:1421
return ns:UpdateTrackedItemBuff(oldKey, fields, fieldKeys)

-- in ns:UpdateTrackedItemBuff(key, fields, fieldKeys)
local ITEM_BUFF_KEYS = { buffEnabled = true, buffAuraID = true, buffDuration = true } -- file-level
...
if type(fieldKeys) == "table" then
	for _, k in ipairs(fieldKeys) do
		if ITEM_BUFF_KEYS[k] then
			entry[k] = fields[k]
		end
	end
end
```

Run the engine guard against the effective post-write values: the read value when the key was read, otherwise the saved one.

## Info

### IN-01: The shared use-spell comment says more than the code can know; the buff goes to whichever item registered last

**File:** `Providers.lua:1814-1820` (map writer `Providers.lua:1531-1533`, `1541-1550`)
**Issue:** The comment says "the buff starts for the tracker whose item matched". In fact `itemUseSpellToID[useSpellID]` holds whichever item `RegisterAllTrackedItemUseSpells` wrote last, and that function iterates `pairs(ns.db.trackedBuffs)`, whose order can change between sessions. With two tracked items sharing a use-spell (for example quality ranks of the same potion), using item A can start item B's buff and decrement B's count, while A's buff never starts. 76-CONTEXT accepts "last writer wins", so this is a documentation issue, not a behaviour defect.
**Fix:** Reword the comment to "starts the buff for the item the use-spell map currently names (last registered; which item that is depends on iteration order)". Optionally, record the limitation in the Phase 78 in-game checklist.

### IN-02: Stale comment says the timer branch never uses `ApplyCachedIcon`

**File:** `Display.lua:831-832`
**Issue:** The comment says "RenderIconContainer's TIMER branch deliberately does not come through here; see the comment on its own cache block for why." Since b2fd938, the timer branch does call `ApplyCachedIcon` for every cooldown-slot entry (Display.lua:1757-1758), and the old explanation it points to was deleted.
**Fix:** Change it to: "RenderIconContainer's TIMER branch uses this for cooldown-slot entries (Phase 76) and keeps its own spellID-only cache for every other proc."

### IN-03: The post-commit tail is duplicated between `UpdateTrackedItemBuff` and `UpdateTrackedBuff`

**File:** `BuffEngine.lua:1358-1367` and `BuffEngine.lua:1518-1527`
**Issue:** The nil-guarded `MarkTrackersDirty`, `MarkCooldownsDirty` and `UpdateDisplay` sequence is copied. This milestone introduced the copy, so CLAUDE.md's cleanup-phase mandate covers it.
**Fix:** Move the sequence into a small `ns:AfterTrackerEdit()` helper (or similar), called by both functions, during the milestone cleanup phase.

### IN-04: The engine guard is looser than the dialog's Aura ID validation

**File:** `BuffEngine.lua:1335-1342`
**Issue:** With the buff on, the guard accepts any positive number as `buffAuraID`, including non-integers and values above 2147483647. The dialog's `tooLarge` check rejects those, but only while the field is enabled. The guard is described as a defence-in-depth twin of the dialog rule, yet it enforces a weaker rule. The dialog's `GetNumber()` makes this unreachable today.
**Fix:** Add `and fields.buffAuraID <= 2147483647 and fields.buffAuraID == math.floor(fields.buffAuraID)`, or leave it and say in the comment that the guard checks presence only.

### IN-05: The item portrait shows the saved label, which can be the "Item <id>" placeholder

**File:** `CDMTab.lua:2034-2044`
**Issue:** `state.itemName = entry.label`. `AddSuggestedTracker` saves `info.label`, and that falls back to `"Item " .. itemID` when `C_Item.GetItemNameByID` had no cached name at track time. That placeholder is never re-resolved, so the Edit Item Tracker portrait can show "Item 212265" for good, even though the same prefill already calls `ns:ItemDisplayInfo` for the icon fallback.
**Fix:** In prefill (edit-time only), prefer the live name: `local info = ns:ItemDisplayInfo(entry.itemID); state.itemName = (info and info.label) or entry.label`. The placeholder then only appears when the client still has no name.

---

_Reviewed: 2026-10-22T23:58:05Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
