---
phase: 68-merge-mode-by-re-anchoring
reviewed: 2026-10-10T00:00:00Z
depth: deep
iteration: 2
files_reviewed: 3
files_reviewed_list:
  - MergeReanchor.lua
  - Display.lua
  - MergeMode.lua
findings:
  critical: 0
  warning: 1
  info: 5
  total: 6
status: issues_found
---

# Phase 68: Code Review Report (iteration 2)

**Reviewed:** 2026-10-10
**Depth:** deep
**Files Reviewed:** 3
**Status:** issues_found

## Summary

This pass re-reviewed the iteration-1 fixes in `MergeReanchor.lua`, `Display.lua` and `MergeMode.lua` against Blizzard's `CooldownViewer.lua`, `CooldownViewer.xml`, `LayoutFrame.lua` and `EditModeSystemTemplates.lua`. All six fixes hold up.

- **CR-01, deferred flush over Blizzard's pools.** Correct. `AttachMergedItem` now only records intent. `FlushMergedPlacement` walks `viewer.itemFramePool:EnumerateActive()` for every hooked viewer, so it reaches hidden frames and preview state. It no longer reads `ns.mergeItemFrames`.
- **WR-03, whole-map rebuild.** Correct. Every attached id is in `cellByID`. A cell is used at most once per render, because pools are keyed by container and slot index. So an attached id cannot be evicted later in the same render, and `mappedCount == attachedCount` holds exactly when the two id sets are equal. `idByCell` and `cellByID` stay a bijection through the eviction, move and flush-prune paths. A render with no changes costs one integer compare and one boolean test.
- **WR-01, release ordering and per-frame pcall.** Correct. The bookkeeping is cleared last. The release-all walk wraps each frame in its own pcall. `PlaceItem` registers `placedOn` before its first setter, so a partial failure is retried, and a retry does not re-capture over a good anchor. One ordering consequence is noted in IN-02.
- **WR-02, swipe re-assert.** Correct within the gaps the OPEN ITEM already records. Telling the two icon kinds apart by `Applications` matches the XML: only `CooldownViewerBuffIconItemTemplate` has it.
- **WR-04, emptying synchronously on Merge Mode off.** Correct. The next render does not attach anything. The flush prunes every id, and `PlaceAllMergedItems` walks `placedOn` to release frames, including ones Blizzard has already returned to its pool. The queued mirror's `ReanchorMergeViewers` call releases a second time, as a backstop.
- **IN-01, unplaceable stamp.** Correct. `unplaceableOn` is kept separate, so the `placedOn` walks (release-all, swipe re-assert) never see a frame TBT did not move.

The requested invariants all hold:

- **Taint boundary.** No `SetParent`, no field write on a Blizzard frame, and no item mixin call. `pool:EnumerateActive()` is the already-admitted pool read.
- **One frame per cell and one cell per frame.** Blizzard's pool reset runs `Pool_HideAndClearAnchors`, so a frame Blizzard releases cannot stay visible on a cell.
- **Steady-state render.** No game call on a Blizzard frame and no allocation.
- **Upvalue order.** Every file-local is declared above its first caller.
- **Preview.** Previewing publishes every configured entry (`seen == 0`). The flush still reaches the frames, and Edit Mode's `RefreshLayout` reaches `Layout`, so the hook fires.

One new defect was found. Showing a bar's Name (or Duration) text that Blizzard had hidden reveals stale text, because Blizzard only writes those strings while they are shown (WR-01). The rest are Info-level robustness and bookkeeping notes.

## Warnings

### WR-01: A bar's Name text that TBT shows after Blizzard hid it is stale or empty (the player's CDM bar-content setting leaks into TBT)

**File:** `MergeReanchor.lua:107-128` (`SetBarRegions`), called from `ApplyMergedStyle` at `MergeReanchor.lua:162-164` and from `RestoreBlizzardStyle` at `MergeReanchor.lua:211-227`
**Issue:** `SetBarRegions` copies the shown/hidden half of Blizzard's `SetBarContent` and `SetTimerShown`. It does not copy the text. Blizzard fills the bar strings only while they are already shown:

- `CooldownViewerBuffBarItemMixin:RefreshName` returns early `if not nameFontString:IsShown()` (CooldownViewer.lua:1584-1592).
- `RefreshCooldownInfo` writes the duration text only `if durationFontString:IsShown()` (CooldownViewer.lua:1566, 1576).

Here is how it plays out when the player's CDM Tracked Bars are set to **Icon Only** and the TBT bar container is set to Icon and Name or Name Only:

1. `RefreshLayout` runs `OnAcquireItemFrame` → `SetBarContent(IconOnly)`, which hides the name.
2. `RefreshData` → `RefreshName` then skips it, because the name is hidden.
3. The Layout hook → `ApplyMergedStyle` → `nameText:SetShown(true)` reveals whatever text the pooled frame last held. That is either empty or the name of a different spell from the frame's previous use.

The same thing happens outside Layout. A non-preview merged bar is released whenever it stops being shown, and released frames go back to Blizzard's style, where the name is hidden. When the aura comes back, `OnActiveStateChanged` → `RefreshName` runs while the name is still hidden. TBT places the frame and shows the name only after the shown-slot pass and the next render. So the stale text can last for the whole aura, until some later `RefreshData` happens to run. Edit Mode is affected the same way, because entering it runs `RefreshLayout`.

The duration has the same problem when the CDM's Show Timer is off and the TBT container's is on. It heals on the next bar `OnUpdate` while the bar is active, but an inactive bar shown in preview keeps the stale text. The reverse direction, `RestoreBlizzardStyle` showing a name that TBT had hidden, has the same issue.

This is a CDM setting leaking into TBT's styling, which STEAL-16 forbids. The Phase 68 CONTEXT requires that a setting which cannot be fully reproduced is recorded rather than half-applied.

**Fix:** Write the text yourself through the plain FontString setter, which CONTEXT allows ("font/texture setters on child regions"). The label TBT already holds is the right text. One way is to record it at attach time and set it whenever the name is revealed:

```lua
-- AttachMergedItem: also remember the label (no allocation; entry.label is a string)
labelByID[id] = entry.label

-- SetBarRegions gains a label argument; reveal and fill together
if nameText then
	local showName = content ~= 1
	nameText:SetShown(showName)
	if showName and label and not issecretvalue(label) then
		nameText:SetText(label)
	end
end
```

For the duration, clear the text when revealing it on an inactive frame (`durationText:SetText("")`). Blizzard's own `RefreshCooldownInfo` fills it on the next active `OnUpdate`. If writing text on a Blizzard region is judged out of bounds, record both cases in the OPEN ITEM block (lines 130-146) next to the swipe gaps instead of leaving them silent.

## Info

### IN-01: In a Centered container, a merged buff's frame is anchored to a cell with no points, so it appears a few frames late

**File:** `Display.lua:2447-2462`, `Display.lua:2492-2498`
**Issue:** In a Centered layout, a merged entry with `cdmShown == false` gets `icon:ClearAllPoints()` and no `SetPoint`. `AttachMergedItem` still maps its cooldownID to that unanchored cell, because Tracked Buffs publish the whole configured set. Blizzard shows the frame the moment the aura lands. Until then the frame has no rect. It stays invisible until the deferred shown-slot pass stamps `cdmShown` and the next render, up to `UPDATE_INTERVAL` = 0.05 s later, gives the cell an anchor. That is one frame plus up to 50 ms, every time the buff is applied. This is not a correctness break: once the cell is anchored, the frame follows it.
**Fix:** Accept it and say so in the comment above the reanchor branch, or anchor undrawn cells to the container's TOPLEFT so the frame is at least drawn at the run's start until the re-centre.

### IN-02: Restoring style before the anchor means a raise leaves the frame on a cell another id may now own

**File:** `MergeReanchor.lua:263-282`
**Issue:** `ReleaseItem` runs `RestoreBlizzardStyle` first and the anchor restore second. If anything in `RestoreBlizzardStyle` raises (for example a non-finite `viewer.iconScale` getting past `ViewerNumber`, since NaN fails `<= 0`), the frame stays anchored to its old TBT cell. On the eviction path that cell already belongs to another id, so two frames sit on one cell until a retry succeeds. A deterministic raise means the retry never succeeds. The anchor restore cannot realistically raise: it is pcall'd and has a fallback. Doing it first would protect the one-frame-per-cell invariant better than protecting the style.
**Fix:** Swap the order: `ClearAllPoints` / restore anchor, then `RestoreBlizzardStyle`, then the bookkeeping. Optionally reject non-finite scales with `scale ~= scale`.

### IN-03: An evicted id's `kindByID` / `settingsByID` entries are never cleared

**File:** `MergeReanchor.lua:419-423`
**Issue:** When a cell's previous id is evicted, only `cellByID[previous]` is cleared. The prune walk in `FlushMergedPlacement` (lines 467-477) iterates `cellByID`, so it never reaches that id's `kindByID` / `settingsByID` entries. They stay until Merge Mode is turned off. `ReassertMergedSwipe` can then read stale settings for a frame still in `placedOn` under that id, such as one Blizzard has returned to its pool. Today this is harmless, but it means the three maps no longer describe the same set of ids.
**Fix:** In the eviction branch, also set `kindByID[previous], settingsByID[previous] = nil, nil`.

### IN-04: An error anywhere in the render loop skips the flush for that render

**File:** `Display.lua:2792`, `Display.lua:2836`
**Issue:** `BeginMergedPlacement` and `FlushMergedPlacement` bracket the container loop with no protection. A raise in any render function aborts `UpdateDisplay` before the flush. If the raise repeats every tick, no frame is placed, and none is released after Merge Mode is turned off. The release would then depend on the queued mirror's `ReanchorMergeViewers` backstop. This is the same failure that would already break the display, but now it also strands Blizzard's frames.
**Fix:** Optional. Run the flush even when a render fails, for example by pcall-ing the container loop body and always reaching `ns:FlushMergedPlacement()`. At minimum, note in a comment that the flush depends on the loop finishing.

### IN-05: The unplaceable stamp only clears on a generation, cell or id change

**File:** `MergeReanchor.lua:298-305`, `MergeReanchor.lua:324-328`
**Issue:** A frame stamped unplaceable is retried only when `placeGeneration`, its cell or its id changes, or when a Layout hook forces it. If the size later becomes readable with none of those changing, the non-forced passes (the flush and the shown-slot pass) skip the frame until the next Blizzard Layout. With today's fixed XML and pooled-widget sizes this path is effectively unreachable, so this is only a note.
**Fix:** None needed now. If the path ever proves reachable, bump `placeGeneration` on `DISPLAY_SIZE_CHANGED` (already registered) or drop the stamp after one pass.

---

_Reviewed: 2026-10-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
