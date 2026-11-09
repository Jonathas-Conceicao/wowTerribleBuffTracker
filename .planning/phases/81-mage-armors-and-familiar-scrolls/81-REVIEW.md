---
phase: 81-mage-armors-and-familiar-scrolls
reviewed: 2026-11-09T00:00:00Z
depth: deep
diff: 22e4371..227430b
files_reviewed: 3
files_reviewed_list:
  - Providers.lua
  - ReminderClick.lua
  - Core.lua
findings:
  critical: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# Phase 81: Code Review Report

**Reviewed:** 2026-11-09
**Depth:** deep (diff `22e4371..227430b`, traced into Display.lua `CollectReminderClickIcons`, Core.lua `RebuildCastIndex`/cast dispatch, and Blizzard `SecureTemplates.lua` / `ChatFrameUtil.lua`)
**Files Reviewed:** 3
**Status:** issues_found

## Summary

No blockers. Everything the focus list asked about checks out:

- **Secure attributes:** `SECURE_ACTIONS.item` (wow-ui-source `Blizzard_FrameXML/SecureTemplates.lua:418-439`) reads the `item` attribute. `SecureCmdItemParse("item:277493")` matches neither the bag/slot pattern nor the slot pattern, so the string is passed unchanged to `C_Item.UseItemByName(name, "player")`, which is valid. When a pooled overlay switches between item and spell, it rewrites `type1` and clears the attribute it no longer uses (`spell` to nil for an item overlay, `item` to nil for a spell overlay). Every write is behind a change check. `Place` is only reached from `Flush` after its `InCombatLockdown()` return (ReminderClick.lua:183), so nothing is written in combat.
- **Non-familiar clicks are byte-identical:** `CreateOverlay` sets `_actionType = "spell"` to match the `type1` it writes (ReminderClick.lua:97-98). With `itemAttr == nil`, `actionType == "spell"` (no write), `spellAttr == castName` (the same check-then-write as before), and `_itemAttr == nil == itemAttr` (no write). `if castName or itemAttr` reduces to the old `if castName`. On retail no def has `useItems`, because the rows return early at `client` "forever".
- **Item pick:** a missing `C_Item.GetItemCount` returns nil. A secret or non-number level returns nil. The count read is pcall'd and secret-checked. The level is compared before the count. The list is walked in data order, never sorted. There is no new retry skip.
- **Combat deferral:** in combat `MarkReminderClicksDirty` only sets `dirty`, and `PLAYER_REGEN_ENABLED` runs `Flush` (ReminderClick.lua:246, 263-264).
- **Declaration order:** `PickUseItem` is defined (line 57) above its only caller `Flush` (line 182). `ns:ReminderUseItems` is on `ns`. There is no new upvalue-order risk.
- **Data:** the item and level pairs (277493/25, 277483/16, 275069/5) and the aura IDs match research §11.1. The cast index is keyed on `entry.spellID`, not `castID` (Core.lua:1436-1452), so with `castID = false` a Cat use still starts the row, and Frog/Rat start it through `alternativeKeysBySpell` (Providers.lua:431). Both group calls sit inside the Forever block, and `MetaReminderGroup` skips the row-less IDs 1302285 and 1296202 on purpose, which makes them one-way alternatives.

The one warning is a side effect of the new `BAG_UPDATE_DELAYED` mark. It applies to every character on every client, not only the familiar, and it re-arms the WR-03 retry.

## Warnings

### WR-01: The BAG_UPDATE_DELAYED mark runs for every character and re-arms the WR-03 retry on every bag change

**File:** `Core.lua:2197-2198` (with `ReminderClick.lua:243-251`, `ReminderClick.lua:223-227`, `Display.lua:308-312`)

**Issue:**
- `ns:MarkReminderClicksDirty()` now runs on every `BAG_UPDATE_DELAYED`: on retail, for every class, and on Forever characters with no familiar reminder placed. Only one Forever mage row can use it.
- `MarkReminderClicksDirty` also sets `retrySpent = false`. While any stamped reminder icon is not visible, `CollectReminderClickIcons` counts it as `hidden`, and `Flush` treats it as a skip. That happens for an icon in a hidden container or section, or with the UI hidden.
- So every bag change (looting, vendoring, a consumable use, mail) now runs a full flush and then a second flush `RETRY_DELAY` (1 s) later.
- The WR-03 bound ("a permanent skip costs one extra flush per dirty edge") assumed dirty edges were rare (layout, spellbook, Edit Mode). This change turns a very frequent event into a dirty edge.
- This is the only change in the phase that affects non-familiar reminders. Their attributes stay identical, but their flush cadence does not.

**Fix:** mark only when a placed reminder has an item click. Record that in `Flush`, which already resolves `useItems` per icon, and gate the Core call on it:

```lua
-- ReminderClick.lua, Flush: before the icon loop
local sawItemClick = false
-- ... in the loop, after useItems is resolved:
if useItems then sawItemClick = true end
-- ... after the loop (inside the editModeOpen/db guard, so a closed Edit Mode keeps the last value):
ns.reminderItemClickActive = sawItemClick

-- Core.lua BAG_UPDATE_DELAYED branch
if ns.reminderItemClickActive then
	ns:MarkReminderClicksDirty()
end
```

An alternative is a separate `ns:MarkReminderItemClicksDirty()` that sets `dirty` and schedules the flush without resetting `retrySpent`. Either one brings retail and non-mage characters back to their pre-phase flush cadence.

## Info

### IN-01: `"item:" .. itemID` is rebuilt on every flush

**File:** `ReminderClick.lua:70`
**Issue:** each flush that shows the familiar icon converts the number to a string and concatenates it. The result is interned, so after the first flush it creates no lasting garbage. It still costs a number-to-string conversion, a hash and an intern lookup per flush, and it contradicts the "no per-call string" goal for the Flush/Place path.
**Fix:** build the attribute string once at row load. For example, `MetaReminderRow` could add a third field (`useItems[i][3] = "item:" .. useItems[i][1]`), and `PickUseItem` would return `useItems[i][3]`.

### IN-02: A level-up does not re-pick the tier (accepted per CONTEXT)

**File:** `ReminderClick.lua:61-67`, `Core.lua:2195-2199`
**Issue:**
- A mage holding Frog and Cat scrolls who reaches 25 keeps clicking Frog until the next bag change, zone or reload.
- A mage holding only the Cat scroll gets no overlay until then.
- CONTEXT chose this ("No `PLAYER_LEVEL_UP` hook"), so this is recorded, not flagged.
**Fix (if ever wanted):** register `PLAYER_LEVEL_UP` on ReminderClick.lua's `eventFrame`. Its `OnEvent` else-branch already routes any event to `ns:MarkReminderClicksDirty()`, so the fix is one line.

### IN-03: The `_castName` cache field now holds the `spell` attribute, not the cast name

**File:** `ReminderClick.lua:159-161`
**Issue:** for an item overlay, `_castName` is now nil even when `castName` is non-nil. The code is correct, because `spellAttr` is what gets written, but the field name no longer says what it caches.
**Fix:** rename the field to `_spellAttr`, matching `_itemAttr` and `_actionType`. It appears only in this function.

---

_Reviewed: 2026-11-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
