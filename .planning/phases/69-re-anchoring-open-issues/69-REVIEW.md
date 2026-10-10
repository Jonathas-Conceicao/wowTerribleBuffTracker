---
phase: 69-re-anchoring-open-issues
reviewed: 2026-10-10T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - MergeReanchor.lua
  - Display.lua
  - MergeMode.lua
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: issues_found
---

# Phase 69: Code Review Report

**Reviewed:** 2026-10-10
**Depth:** standard (scope: `git diff 672d509 HEAD` on the three files)
**Files Reviewed:** 3
**Status:** issues_found

## Summary

I reviewed the STEAL-13 changes (viewerByID ownership check, same-render duplicate-attach guard, render before place after a mirror rebuild), the STEAL-14 changes (`CollectVisibleCooldownIDs`, `entry.cdmFrameVisible`, the Display placeholder branches) and the STEAL-15 changes (hide-path comments, `ns:CheckMergeViewerVisibility`, the `/tbt merge` Visibility line). I checked them against Blizzard's `CooldownViewer.lua`. Item frames are pooled with parent `GetItemContainerFrame()`, which returns `self`, so `itemFrame:GetParent() == viewer` holds. `visibleSetting` is a plain field written by the Edit Mode system.

**Taint boundary:** clean. The phase adds no SetParent, no field write on a Blizzard frame, no mixin call, no Show/Hide on a Blizzard frame and no aura read. The only new reads on Blizzard frames are the `IsVisible`/`GetParent` C getters and the `viewer.visibleSetting` field read, and each is guarded with `issecretvalue` and `type`.

**Upvalue order:** clean. `mirrorChangedForPlacement` (MergeMode.lua:150), `mergeVisibilityWarned`, `visibleCooldownIDs` and `CollectVisibleCooldownIDs` are all declared above their users. `ClearCooldownStamps`, `ApplyCachedIcon`, `ClearIconDesaturation` and `ApplyIconStyle` (Display.lua:1001-1208) are declared above `RenderIconContainer` (2355). `viewerByID` is declared at the top of MergeReanchor.lua.

**One frame per cell:** holds. `cellByID` is still id → cell injective. The new `parent ~= viewerByID[id]` test also stops two viewers' frames for the same id from both reaching one cell.

**Chat notice:** fires at most once per viewer per session (keyed by viewer global) and only when `ns.mergeSlots[def.key]` is non-empty.

**Steady-state cost:** no allocation and no new game call per tick. Each merged slot adds two table lookups.

The defects are in how the new pieces fit together. The STEAL-14 placeholder uses a different preview predicate from the stamp it reads. The forced pass after Layout releases mismatched frames onto stale anchors. The STEAL-13 "never placed through the old map" invariant is stated in comments that the code does not uphold.

## Warnings

### WR-01: The STEAL-14 placeholder gate uses a different preview predicate from the stamp it reads, so gaps remain in one preview state

**File:** `Display.lua:2112`, `Display.lua:2317`, `Display.lua:2390`, `Display.lua:2520` (stamp at `MergeMode.lua:1182`)
**Issue:** `entry.cdmFrameVisible` is stamped false only when `ns:IsMergePreviewState()` is true. That covers the CDM settings window being visible, `EditModeManagerFrame:IsShown()`, or `editModeOpen`. Display acts on the stamp only when `ownMergedPreview = reanchorHere and (ns.editModeActive or ns.configOpen)`. The two predicates disagree in reachable states:
- **Edit Mode with TBT's own Edit Mode checkbox off.** EditModeFrames.lua:838 leaves `ns.editModeActive = false`, while `IsMergePreviewState()` is true. The shown pass takes the preview path, so every configured merged entry is published and takes a cell, and entries with no drawn frame are stamped `cdmFrameVisible = false`. Display's `ownMergedPreview` is false, so it hides its own widget and attaches anyway. The cell ends up empty: this is the exact STEAL-14 "missing merged bars" symptom, still present in this state.
- **CDM settings window open.** `ns.configOpen` comes from a 0.5 s polling watcher (CDMTab.lua:3400-3414), and the stamp is set on the OnShow event edge. For up to 0.5 s after opening, cells whose frame is not drawn are attached and empty, then switch to placeholders.

The stamp already encodes "previewing and not drawn". Outside preview it is always true, and a mirror rebuild on every preview edge replaces the entry tables. A second predicate in Display only creates a way for the two to disagree.
**Fix:** Gate on the stamp alone and drop `ownMergedPreview` in both render functions:
```lua
if reanchorHere and slot.isMerged then
	if slot.cdmFrameVisible == false then
		bar:Show()
	else
		bar:Hide()
		ns:AttachMergedItem(slot, bar, settings, "bar", viewer)
	end
```
and the same in the icon path (`if entry.cdmFrameVisible == false then ... placeholder ... else ... attach end`).

### WR-02: A frame released by the forced pass after Layout is put back on its stale captured anchor, overriding Blizzard's fresh Layout

**File:** `MergeReanchor.lua:347-356` (new mismatch release), `MergeReanchor.lua:580` (forced `PlaceViewer` in the Layout post-hook), `MergeReanchor.lua:313-333` (`ReleaseItem`)
**Issue:** The Layout hook runs after Blizzard's `Layout` has just re-anchored every item frame to its new grid position. `PlaceViewer(viewer, true)` then calls `PlaceItem`. Phase 69 added a new way for that call to reach `ReleaseItem`: a viewer mismatch (`parent ~= viewerByID[id]`), which is exactly the STEAL-13 move/reorder case in the settings window. `ReleaseItem` runs `ClearAllPoints()` and re-applies `origPoint/origRel/origX/origY`. Those values were captured when the frame was first placed, often for a different `cooldownID` and `layoutIndex`, so they overwrite the position Blizzard assigned a moment earlier. In Edit Mode the viewers are un-suppressed and on-screen. A frame released this way then sits at its old grid offset, overlapping a neighbour, until Blizzard's next Layout. The STEAL-14 not-drawn releases are invisible, so they do not show the problem. The mismatch releases happen while the frame is drawn.
**Fix:** In the post-Layout path the frame's current anchor already belongs to Blizzard. Release the style and bookkeeping only, and leave the anchor alone, for example by giving `ReleaseItem` a `keepAnchor` parameter that `PlaceItem` passes when `force` comes from the Layout hook:
```lua
local function ReleaseItem(itemFrame, keepAnchor)
	if not placedOn[itemFrame] then return end
	local viewer = itemFrame:GetParent()
	if not keepAnchor then
		itemFrame:ClearAllPoints()
		-- restore captured anchor / fallback as now
	end
	RestoreBlizzardStyle(itemFrame, viewer)
	-- clear bookkeeping as now
end
```
Also clear the stale `origPoint` in the forced path so a later non-forced release does not bring it back.

### WR-03: The STEAL-13 "render before place" invariant is broken by the forced placement inside `RefreshMergeMirror`

**File:** `MergeMode.lua:464-471`, with the comments at `MergeMode.lua:147-150`, `MergeMode.lua:1228-1230` and `MergeReanchor.lua:581-585`
**Issue:** The new comments say that after a mirror rebuild "the frames are never placed through the cooldownID -> cell map the previous configuration built". Yet `RefreshMergeMirror` sets the flag and then synchronously calls `pcall(ns.ReanchorMergeViewers, ns)`, which ends in `ns:PlaceAllMergedItems(true)`. That is a forced placement of every frame in every hooked viewer through the previous render's `cellByID`/`kindByID`/`settingsByID`, made before the queued shown pass and its render. The viewer check blocks the cross-container case. After a same-viewer reorder (the same-count path re-assigns `cooldownID` in place), every frame is still moved to its id's old cell, and every frame is fully re-captured and re-styled (`force` skips the dirty check). While previewing, every Blizzard Layout queues a rebuild, so this full forced pass repeats on every Layout. The fix works by luck of ordering, not by the guarantee the comments describe.
**Fix:** Install the hooks without forcing placement on the Merge-on rebuild path, and let the render that `mirrorChangedForPlacement` triggers do the placing:
```lua
function ns:ReanchorMergeViewers(skipPlace)
	-- install hooks as now
	if not skipPlace then
		ns:PlaceAllMergedItems(true)
	end
end
-- RefreshMergeMirror, Merge-on path:
pcall(ns.ReanchorMergeViewers, ns, true)
```
If you keep the current code, correct the three comments so they do not claim an ordering the code does not enforce.

## Info

### IN-01: The duplicate-attach guard picks its winner by `ns.CONTAINERS` order, not by which viewer owns the frame

**File:** `MergeReanchor.lua:469-471`
**Issue:** When two lists publish the same id in one render, the first container in registry order keeps the id, along with its `viewerByID`. If that is the container whose viewer no longer holds a frame for the id, the frame owned by the other viewer fails the `parent ~= viewerByID[id]` test and goes back to the parked viewer. Both cells then stay empty, the loser was already `Hide()`n by Display, and this lasts as long as both lists carry the id. When the lists come from each viewer's own pool this is transient. With the spec-default fallback lists (`GetCooldownViewerCategorySet`) it can last until the next rebuild.
**Fix:** De-duplicate ids across containers in `RefreshMergeMirror`, which is event-driven so allocation is acceptable. Prefer the container whose `BuildViewerIDs` result contained the id, so Display never sees a duplicate and the guard becomes a pure safety net.

### IN-02: The CDM Visibility notice is evaluated only on a mirror rebuild

**File:** `MergeMode.lua:473`
**Issue:** `visibleSetting` is written by the Edit Mode system when a layout is applied (`EditModeSystemTemplates.lua:2842`). If the login rebuild runs before that, the field is nil and the check silently does nothing. The notice then waits for the next mirror rebuild, which `EDIT_MODE_LAYOUTS_UPDATED` alone does not trigger. If the player changes a viewer's Visibility in Edit Mode, the check runs again only because the Exit edge happens to queue a rebuild.
**Fix:** Also call `pcall(ns.CheckMergeViewerVisibility, ns)` from the existing `EDIT_MODE_LAYOUTS_UPDATED` re-assert path, or from `QueueMergeVisibility`'s flush. It is a few field reads, and the once-per-viewer table keeps it quiet.

### IN-03: Unknown `visibleSetting` values are reported as "is hidden"

**File:** `MergeMode.lua:259-260`
**Issue:** Any value other than `Always` that is also not `InCombat` produces "is hidden", including a value added in a future client. `/tbt merge` labels the same case "unknown", so the two outputs disagree.
**Fix:** Compare explicitly against `Enum.CooldownViewerVisibleSetting.Hidden` and skip, or print a neutral wording, for anything else.

### IN-04: The placeholder reset in the STEAL-14 icon branch duplicates the generic merged-placeholder branch

**File:** `Display.lua:2520-2537` vs `Display.lua:2646-2711`
**Issue:** The new branch repeats the generic branch's sequence: the `_cdKey`/`_mergedExpiry`/`_lastStart` resets, `mergedTime:Hide()`, `icon.proc = entry`, `ApplyCachedIcon`, `ClearIconDesaturation`, `ApplyIconStyle` and `Show`. It also differs in small ways: it clears `_mergedExpiry` independently of `_cdKey`. CLAUDE.md's cleanup mandate covers duplication a milestone introduces.
**Fix:** Factor a `ShowMergedPlaceholderIcon(icon, entry, settings)` file-local declared above `RenderIconContainer`, and call it from both branches.

### IN-05: The viewer lookup is repeated for every merged slot on every tick

**File:** `Display.lua:2321`, `Display.lua:2541`
**Issue:** `ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal]` is evaluated once for each merged slot on every render. Its value is constant for the container.
**Fix:** Resolve it once next to `reanchorHere` (`local ownViewer = reanchorHere and (ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal])`) and pass `ownViewer` to both attach calls.

---

_Reviewed: 2026-10-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
