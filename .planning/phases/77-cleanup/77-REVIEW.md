---
phase: 77-cleanup
reviewed: 2026-10-22T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - BuffEngine.lua
  - CDMTab.lua
  - Core.lua
  - Providers.lua
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: issues_found
---

# Phase 77: Code Review Report

**Reviewed:** 2026-10-22
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found (info only)

## Narrative Findings (AI reviewer)

## Summary

Scope: `git diff 0f96e77..HEAD -- '*.lua'` (commits 9591878, 5135667, 439d319, 1d206cb). The main question was whether each refactor keeps behaviour unchanged. I traced every one against the pre-image and found no behavioural regression on any normal path. The three findings are Info: one comment that claims more than the code guarantees, one change in side-effect order that only shows when something throws, and one edge case the registry already had and that this phase now also exposes on the cast path.

Verified points:

- **`ns:FinishTrackerEdit` chat text matches byte for byte.**
  - Spell path, old: `"...Updated |cff00ff00" .. shownLabel .. "|r (" .. kindWord .. ", ID: " .. idText .. ", " .. duration .. "s)."`. New: `"|r (" .. detail .. ")."` with `detail = kindWord .. ", ID: " .. idText .. ", " .. duration .. "s"`. Same string, and `duration` still goes through the same number-to-string concat.
  - Item path, old: `tostring(entry.label or key)` and `"|r (item, buff " .. buffText .. ")."`. New: the same.
  - Return values (`true, newKey` and `true, key`) are unchanged.
  - Moving `ns:CooldownBuffDuration(entry)` ahead of `ns:ApplyCooldownBuffEdit` in the item path is safe. The function is a pure read of `entry`, and ApplyCooldownBuffEdit only changes `ns.activeTimers`.
  - ApplyCooldownBuffEdit still runs after `ns:RebuildRankIndex` in the spell path.
  - The item path changed only in order: the print is now emitted before ApplyCooldownBuffEdit (see IN-02).
- **The five Duration helpers match both original fields.**
  - Build: same label text, size, max letters and autofocus. The x offset is passed in as 16 or 32, and `y - 32` comes back as `nextY`.
  - Reset, prefill and read match the original bodies line for line. The general field still clears `suggestedForID` and `suggestionText` after the shared helper, in the same order relative to `SetText`.
  - Validate: the general field used to return a bare `false` for an empty box and now returns `false, nil`. The only caller (CDMTab.lua:2879, `local ok, msg = def.validate(state, ctx)` and then `if message == "" and msg`) treats the two the same.
  - `read = ReadDurationBox` and `reset = ResetDurationBox` are safe as direct references, because the extra `ctx` and `entry` arguments are ignored.
  - Greying still works: both states return `label` and `editBox`, which is what `ApplyFieldEnabled` touches.
  - Upvalue order is fine: `DURATION_HINT` (1157), `ParseDuration` (1166) and `FormatDuration` (1207) are all declared above the helpers (1920-1959), and the helpers sit above `TRACKER_FIELDS` (1994).
- **`follows = NotItemField` is correct.** Both call sites (CDMTab.lua:1643, 1660) now pass `(state, ctx)`, which matches `NotItemField(_, ctx)` (1990, declared above `TRACKER_FIELDS`). There is no other `follows` provider. Every reset and prefill call site (3075, 3110-3111) passes `ctx`.
- **`ns:CooldownBuffAuraID` has no remaining reference.** A search of `*.lua`, `*.xml`, `*.toc` and `scripts/*.js` (excluding `.planning`) finds nothing. The CDMTab.lua comment now names `CooldownBuffAliveBuffs` and `CooldownBuffTypedAuraID`, both of which exist in Core.lua.
- **`CONTAINER_BY_KEY` stays in sync with `ns.CONTAINERS`.**
  - Base defs are mapped at file load (Core.lua:168-171).
  - The only things that add or remove entries are `ns:RegisterContainerDef` and `ns:UnregisterContainerDef`. They update both structures together, and rehydrate and runtime creation both go through RegisterContainerDef. Nothing else inserts into or removes from `ns.CONTAINERS`.
  - Both structures hold the same def table, so any later change to a def is visible through either one.
  - `"hidden"` is rejected earlier in the function. `"suggested"`, orphaned keys and a nil section all come back nil from the map, just as the old loop fell through to "not found".
  - Indexing with a nil `entry.section` is a legal read in Lua.
- **Hot path and secret values.** `ns:StartCooldownBuffFromCast` swaps an `ipairs` loop for a single hash read and allocates nothing. No new code reads an aura or a secret value. `stylua --check .` is clean, and every tracked `.lua` file is `w/crlf`.

## Info

### IN-01: `ns:FinishTrackerEdit` header claims an invariant neither caller meets

**File:** `BuffEngine.lua:1426-1427` (callers at `1393-1395` and `1544`)
**Issue:** The header says "label and detail are plain strings the caller resolved before its first write, so nothing here can throw after a commit". Neither part is true as written:
1. Both callers build their strings after they write. `UpdateTrackedItemBuff` computes `savedDuration`, `buffText`, `tostring(entry.label or key)` and the detail string after writing `entry.buff*` (1383-1395). `UpdateTrackedBuff` builds `detail` after the move and the fieldKeys write (1544).
2. Only the `print` is guaranteed not to throw. `ApplyCooldownBuffEdit` (through `CooldownBuffAliveBuffs` and `AcquireAliveBuffs`) and `UpdateDisplay` both run after the commit and are not throw-proof.

The same applies to the comment at 1542-1543, "Every piece was resolved before the first write, so this cannot throw", which now sits above a `local detail =` line instead of the print. A maintainer who trusts the header could add a fallible call inside FinishTrackerEdit believing the commit is protected.
**Fix:** Narrow the wording to what is true, for example: "label and detail are built only from values validated before the first write (strings and checked numbers), so the chat line cannot throw; the rebuild and redraw steps after it are not covered by that guarantee."

### IN-02: Chat line moved relative to `RebuildRankIndex` (spell path) and `ApplyCooldownBuffEdit` (item path)

**File:** `BuffEngine.lua:1430-1431`, `1548-1555`
**Issue:** Before this phase, `UpdateTrackedBuff` printed before `ns:RebuildRankIndex`, and `UpdateTrackedItemBuff` printed after `ns:ApplyCooldownBuffEdit`. Now both print inside FinishTrackerEdit: after the rebuild, and before ApplyCooldownBuffEdit. On a normal run the output and final state are identical. The difference only shows when one of those calls throws. In the spell path, a rebuild error now means the user sees no "Updated" line even though the edit is already saved. In the item path, an ApplyCooldownBuffEdit error now comes after an "Updated" line instead of with none. Neither case is reachable with well-formed data, and this is not a regression in the success path.
**Fix:** No code change needed. Add a line to the FinishTrackerEdit header recording that the print now follows the rank rebuild, so the order is a documented choice and not an accident.

### IN-03: Duplicate container keys resolve differently through `CONTAINER_BY_KEY` than through the old walk

**File:** `Providers.lua:231`; registry at `Core.lua:279-280, 284-292, 297-302`
**Issue:** `RehydrateUserContainers` registers every record in `ns.db.userContainers` without checking for duplicate keys. `GenerateContainerKey`'s collision loop covers only newly created keys. If a hand-edited SavedVariables file holds two records with the same `key`, the two lookups disagree:
- `ns.CONTAINERS` ends up with two defs.
- `CONTAINER_BY_KEY` keeps the last one, while the old `ipairs` walk found the first. With differing `kind` values, the cast path would now pick the other one.
- `UnregisterContainerDef` removes only the first from `ns.CONTAINERS` but sets the map entry to nil, so the remaining twin can no longer be looked up by key.

This problem existed before the phase, and Config.lua, EditModeFrames.lua and Core.lua already rely on the map. The cast path now shares it. It requires corrupt saved data.
**Fix:** Optional. In `RehydrateUserContainers`, skip any record whose key is already in `ns.CONTAINER_BY_KEY` (`if not ns.CONTAINER_BY_KEY[record.key] then ... end`). That keeps the map and the array one-to-one for every consumer. It is a guard on pre-existing code, so it belongs in a later phase, not this cleanup.

---

_Reviewed: 2026-10-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
