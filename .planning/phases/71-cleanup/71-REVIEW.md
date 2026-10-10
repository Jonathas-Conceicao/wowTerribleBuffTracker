---
phase: 71-cleanup
reviewed: 2026-10-10T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - MergeReanchor.lua
  - MergeMode.lua
  - BuffEngine.lua
  - Display.lua
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 71: Code Review Report

**Reviewed:** 2026-10-10
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

Scope: `git diff 73d7330 HEAD` for MergeReanchor.lua, MergeMode.lua, BuffEngine.lua and Display.lua.

Behaviour checks, all of which pass:

- **`ForgetID` (MergeReanchor.lua:96-104).** It clears the same six maps as both old inline blocks. The prune path (l.578) is exactly what it was before: it re-reads `cellByID[id]`, which is the same value as the loop's `cell`, and assigning nil to an existing key during `pairs` is legal in Lua 5.1. The eviction path (l.516) now also clears `idByCell[cellByID[previous]]` when it equals `previous`. Under the map invariant that cell is `cell` itself, and l.520 overwrites `idByCell[cell] = id` two lines later, so nothing observable changes. If the maps had drifted apart, the extra clear is the more correct behaviour. `mappedCount` bookkeeping is unchanged at both sites.
- **Upvalue order.** `cellByID`, `idByCell`, `kindByID`, `settingsByID`, `labelByID` and `viewerByID` are declared at l.43-48, above `ForgetID` (l.96). `ForgetID` is declared above both callers (l.516 and l.578). In MergeMode.lua, `shownCooldownIDs`, `visibleCooldownIDs` and `CollectFrameCooldownIDs` (l.529-571) all sit above `ns:RefreshMergeShownSlots`.
- **`CollectFrameCooldownIDs`.**
  - The preview call (l.606) passes `visibleCooldownIDs, true` and reads `IsVisible`.
  - The live call (l.636) passes `shownCooldownIDs, false` and reads `IsShown`.
  - The `issecretvalue` guards on both `cooldownID` and the flag are kept.
  - The pool capability check and the `seen` count are identical.
  - Both pcall sites keep the same `ok`/`issecretvalue(count)`/`type(count)` handling.
- **`ns:EndTimer`.** There are no references in any `.lua`, `.xml`, `.toc` or `scripts/` file. The only hits are in `.planning/`.
- **Per-tick cost.** There are no new frame calls. `ForgetID` adds one Lua call only on the eviction and prune paths, which already only run when something changed. The steady-state `FlushMergedPlacement` is still one comparison plus one boolean test. `RefreshMergeShownSlots` is event-driven and now adds one extra argument and one branch per item frame.
- **EOL.** All four files are `w/crlf`.

The defects are all in the comments this phase reworded. The new MergeMode.lua header now says MergeReanchor.lua writes to CDM item frames, but the "admission" block below it still says no item frame is ever written. The header's "never, anywhere" mixin rule is also still contradicted by another file.

## Warnings

### WR-01: Admission block still states "No item frame is written to", contradicting the reworded header

**File:** `MergeMode.lua:506-510`
**Issue:** Phase 71 rewrote the header (l.8-15) to say TBT writes to CDM frames in two places, one of them being MergeReanchor.lua "moving and styling the item frames". The `WHY THIS EXTENDS THE PERMITTED CDM SURFACE` block still ends with: "the item frames themselves are touched only through itemFrame.cooldownID ... and itemFrame:IsShown() ... No item frame is written to, parented, or has a mixin method called on it." That is false today. MergeReanchor.lua calls ClearAllPoints, SetPoint, SetScale, SetWidth, SetAlpha, SetIgnoreParentAlpha and SetMouse*Enabled on item frames, plus SetDrawSwipe, SetShown and SetText on their children. The audit's stated purpose for this item (71-AUDIT.md row 3) was to remove exactly this kind of contradiction, and the taint-boundary audit is done by reading these comments. As things stand, the file now contradicts itself across ~500 lines.
**Fix:** Scope the sentence to this file and point to the real write surface:
```lua
-- Everything else stays as it was IN THIS FILE: the item frames are touched here only through
-- itemFrame.cooldownID (a raw field read) and the IsShown/IsVisible C widget getters. The item-frame
-- WRITES Merge Mode makes (C setters only) are listed in MergeReanchor.lua's header; no item frame
-- is parented or has a mixin method called on it anywhere.
```
The separate sentence at l.512-513 about IsVisible can then be merged into this one.

### WR-02: Reworded header re-asserts "TBT must never, anywhere: call a Blizzard MIXIN method on a CDM frame", which EditModeFrames.lua breaks

**File:** `MergeMode.lua:11-13` (contradicted by `EditModeFrames.lua:283-299`)
**Issue:** The reworded header still says "TBT must never, anywhere" and lists `EditModeSystemMixin` by name. EditModeFrames.lua resolves `_G[def.cdmViewerGlobal]` and calls `viewer:GetSettingValue(...)` and `viewer:GetSettingValueBool(...)`. Both are `EditModeSystemMixin` methods (wow-ui-source `EditModeSystemTemplates.lua:483` and `:504`). The contradiction predates this phase, but Phase 71 rewrote this paragraph specifically to make it accurate tree-wide ("anywhere", replacing "this file alone"), and it still is not. A future reviewer who trusts the header will miss a real mixin call on a CDM viewer.
**Fix:** Either list the exception in the header, for example:
```lua
--   1. call a Blizzard MIXIN method on a CDM frame ... (sole exception: EditModeFrames.lua's
--      settings import reads viewer:GetSettingValue/GetSettingValueBool, user-initiated, out of
--      the render path)
```
or narrow the rule's scope to Merge Mode. Do not change the code; this is a documentation fix.

## Info

### IN-01: Mixed "wiped per viewer" / "wiped per def" on the join sets

**File:** `MergeMode.lua:526-530`
**Issue:** The merged comment says `shownCooldownIDs` is "wiped per viewer" and `visibleCooldownIDs` is "wiped per def". Both are wiped together, once per def, in the `RefreshMergeShownSlots` loop body.
**Fix:** Say "Both reused across refreshes and wiped per def".

### IN-02: Stale line reference `Display.lua:489`

**File:** `MergeMode.lua:504`
**Issue:** The `itemFramePool` capability check is now at Display.lua:701-712 (`ns:InitDisplay`). This sits inside a block this phase edited nearby, and the phase's job included fixing stale comments.
**Fix:** Refer to it by name ("the capability check in ns:InitDisplay") instead of by line number.

### IN-03: Rewrapped header line runs to 126 columns

**File:** `MergeMode.lua:15`
**Issue:** The reword left `--      MergeReanchor.lua's header lists them; so is exactly one generic-container call, viewer.itemFramePool:EnumerateActive,` far wider than the surrounding ~100-column block. stylua does not reflow comments.
**Fix:** Rewrap it by hand to match l.11-14.

### IN-04: `ForgetID`'s rationale is now duplicated at the call site

**File:** `MergeReanchor.lua:514-515`
**Issue:** The comment above `ForgetID(previous)` repeats the doc comment on `ForgetID` (l.94-95) almost word for word. It no longer describes anything that is local to the call site.
**Fix:** Drop it or shorten it to `-- Evict the previous id wholesale (see ForgetID).`

---

_Reviewed: 2026-10-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
