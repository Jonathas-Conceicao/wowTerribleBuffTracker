---
phase: 84-cleanup
reviewed: 2026-11-09T12:00:00Z
depth: deep
files_reviewed: 3
files_reviewed_list:
  - Providers.lua
  - ReminderClick.lua
  - BuffEngine.lua
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: issues_found
---

# Phase 84: Code Review Report

**Reviewed:** 2026-11-09T12:00:00Z
**Depth:** deep
**Files Reviewed:** 3 (commit 35b18e1, the Providers.lua / ReminderClick.lua / BuffEngine.lua hunks)
**Status:** issues_found (INFO only)

## Summary

The commit closes 81 IN-01 (cached `"item:<id>"` string), 81 IN-03 (`_castName` renamed to `_spellAttr`) and 80 IN-04 (comment on the editor's ID cap). Behaviour is the same as before. Each focus point was checked:

- **Cache is set before any Flush can read it.** `useItems[i][3]` is written inside `MetaReminderRow` (Providers.lua:1147-1152). That runs at file load, before the def is indexed into `metaReminderDefsBySpellID` (Providers.lua:1164-1165). `ns:ReminderUseItems` (Providers.lua:1396-1402) is the only way `Flush` gets the list (ReminderClick.lua:207), and it reads from that index, so no Flush can see a pair without field 3.
- **Forever only.** The write comes after the client gate (Providers.lua:1143-1146). The one `useItems` row (Providers.lua:1191) has no `client` field, so it defaults to `"forever"`. On retail it returns before the write.
- **Never persisted, never shared with saved data.** The pairs are fresh literals in the call's `opts` table. `def.useItems` is only read by `ns:ReminderUseItems`. `ns:ApplyMetaReminderDef` (Providers.lua:1437-1466) copies `duration`, `coverAllRanks`, `auraID` and `alternatives` (the last through `CopyIDList`) and never touches `useItems`. Nothing writes the list into `ns.db` / `TerribleBuffTrackerDB`.
- **Same output.** Before, the code returned `"item:" .. itemID`. Now it returns the same concatenation, built once at load with the same integer literal. `GetItemCount` still receives `useItems[i][1]`.
- **PickUseItem guards are intact** (ReminderClick.lua:58-76): the missing-API check, the secret/type check on `UnitLevel`, level before count, `pcall` on `GetItemCount`, and the secret/type/`> 0` checks on count are all unchanged.
- **The `_spellAttr` rename is complete.** Repo-wide grep finds no `_castName`. The read and write at ReminderClick.lua:160-162 both use `_spellAttr`. The `castName` local and parameter, and `ResolveCastName`, are meant to keep their names.
- **File-local order.** `PickUseItem` (ReminderClick.lua:58) is declared before `Flush`. `MetaReminderRow` is declared before every call to it. No new upvalue was added.
- **Comment accuracy.** The blessings `MetaReminderGroup` has 19 IDs, so each row gets 18 alternatives. `MAX_CAST_RULE_IDS` is 8 (CDMTab.lua:1353), and `ns:ParseSpellIDList` enforces it (CDMTab.lua:1386). The 80 IN-04 note is correct.
- **Checks.** `stylua --check` on all three files passes. They are CRLF in the working tree (`attr/text eol=crlf`). `node scripts/reminders-doc-check.js` and its `--selftest` pass, as does `node scripts/aura-read-gate.js`.

## Narrative Findings (AI reviewer)

## Info

### IN-01: Reflowed comment line is 191 columns wide

**File:** `Providers.lua:1394`
**Issue:** The `ns:ReminderUseItems` doc comment had the new clause put into the middle of an existing line, which made it a 191-column line. The other comments around it are wrapped at about 100 columns, and stylua does not reflow comments, so it will stay that way.
**Fix:** Re-wrap the comment at about 100 columns:
```lua
-- The ordered { itemID, minLevel } list a click on a reminder picks an item from (CLICK-07), or
-- nil; each pair's third field is its "item:<id>" click attribute, built once by MetaReminderRow.
-- Only a built-in row carries one (the familiar scrolls). Called by ReminderClick.lua's Flush;
-- one map read, no allocation.
```

### IN-02: PickUseItem now depends on a field only MetaReminderRow sets

**File:** `ReminderClick.lua:71`, `Providers.lua:1147-1152`
**Issue:** `PickUseItem` returns `useItems[i][3]`. If a `useItems` list is ever built anywhere other than `MetaReminderRow`, field 3 will be nil. The scroll is then in the bags but the function returns nil, so no overlay is placed, and nothing reports an error. Today `MetaReminderRow` is the only constructor, so nothing is broken. The comments at both ends already describe the contract, so this is a note for later changes, not a defect.
**Fix:** No change is needed now. If a second source of `useItems` is ever added, have it fill field 3 the same way, or use `useItems[i][3] or ("item:" .. useItems[i][1])` as a fallback. That fallback allocates only when field 3 is missing.

---

_Reviewed: 2026-11-09T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
