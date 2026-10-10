---
phase: 68-merge-mode-by-re-anchoring
fixed_at: 2026-10-10T00:00:00Z
review_path: .planning/phases/68-merge-mode-by-re-anchoring/68-REVIEW.md
iteration: 2
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

<!-- Frontmatter reflects the latest iteration (2). Iteration 1 was: 8 in scope, 7 fixed, 1 skipped, partial. -->


# Phase 68: Code Review Fix Report

**Fixed at:** 2026-10-10
**Source review:** .planning/phases/68-merge-mode-by-re-anchoring/68-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (CR-01, WR-01..04, IN-01, IN-02, plus the optional IN-05)
- Fixed: 7
- Skipped: 1 (IN-05, optional)
- Out of scope by orchestrator decision: IN-03 (Phase 69, STEAL-15), IN-04 (Phase 70)

Work was done directly on `milestone/v0.5.2-improved-merge-mode` (no worktree, per orchestrator).
Every commit was followed by `stylua .`. All three `.lua` files stay `w/crlf`, and no `git diff --stat` showed `Bin`.
After the last fix, `node scripts/aura-read-gate.js` passed (4 reads in 2 allowlisted readers), as did its `--selftest` and `node scripts/migrate-dryrun.js --selftest`.
The build was deployed with `./scripts/install.bat` (v0.5.1-47-gcae051d-dev).
No Lua interpreter is installed, so stylua's parser served as the Tier 2 syntax check.

All fixes need an in-game check (Phase 72). Every one except IN-02 changes runtime logic, so those are marked "requires human verification".

## Fixed Issues

### CR-01: In Edit Mode and the CDM settings window, AttachMergedItem never moves or restyles a frame

**Files modified:** `MergeReanchor.lua`, `Display.lua`
**Commit:** 46ed589
**Status:** fixed: requires human verification
**Applied fix:**
- `ns:AttachMergedItem` now records the cooldownID-to-cell, kind and settings intent only, with no game call. It sets a module `placementPending` flag when anything changed.
- `ns:MarkMergedPlacementDirty`, which the dirty-event frame now calls, bumps the generation and also sets the flag.
- New `ns:FlushMergedPlacement()` runs once at the end of `ns:UpdateDisplay`, after every cell is laid out. When the flag is set it runs `PlaceAllMergedItems(false)`, which enumerates Blizzard's pools directly. It therefore reaches hidden frames and preview state, where `ns.mergeItemFrames` is empty.
- The eviction branch no longer looks frames up in `ns.mergeItemFrames`; the pool walk returns an evicted frame to its viewer.
- Steady state is one boolean test, with no game call and no allocation.

### WR-03: The id-to-cell map is still patched rather than rebuilt, and eviction only releases shown frames

**Files modified:** `MergeReanchor.lua`, `Display.lua`
**Commit:** dce83b1
**Status:** fixed: requires human verification
**Applied fix:**
- The map is now rebuilt whole on every render, as STEAL-13 decides. `ns:BeginMergedPlacement()` at the start of `UpdateDisplay` bumps `renderGen` and resets `attachedCount`.
- `AttachMergedItem` stamps `attachGen[id]` and keeps `mappedCount` (ids holding a cell) up to date.
- At the flush, `mappedCount ~= attachedCount` means some id was not attached this render. Those ids lose their cell, and the pool walk sends their frames back to the viewer, shown or hidden.
- A render that changes nothing costs one integer comparison: no walk, no wipe, no allocation.
- Side effect: a merged frame whose TBT container is hidden by `ShouldShow` is no longer attached, so it now goes back to the parked viewer. That is the STEAL-15 rule Phase 69 locked. The other direction of IN-03 (the CDM's own visibility hiding moved frames) is untouched and stays with Phase 69.

### WR-01: The release-all walk has no per-item pcall, and ReleaseItem clears bookkeeping before it restores anything

**Files modified:** `MergeReanchor.lua`
**Commit:** 2e69260
**Status:** fixed: requires human verification
**Applied fix:**
- `ReleaseItem` now restores style first (`RestoreBlizzardStyle`), then the anchor. It re-applies the captured anchor through `pcall(itemFrame.SetPoint, ...)` and falls back to the viewer's TOPLEFT. It clears `orig*` and `placedOn/placedGen/placedID` last.
- The release-all walk calls `pcall(ReleaseItem, itemFrame)` per frame again.
- `PlaceItem` sets `placedOn[itemFrame] = cell` with a nil generation and id right after `CaptureBlizzardAnchor`, before the first setter. A partial failure is therefore still tracked, retried and released. The full stamp is still set at the end.
- **Gate expectation change:** the Plan 68-01 note that the release-all walk calls `ReleaseItem(itemFrame)` bare to satisfy a `ReleaseItem(` count gate no longer holds. The walk is `pcall(ReleaseItem, itemFrame)` again, as the reviewer asked. Any gate that requires a bare call in the walk should be changed; the safety stays. The `ReleaseItem(` token still appears at least 3 times: the definition, the two `PlaceItem` call sites, and the pcall.

### WR-02: Show Timer = off does not stick on Essential/Utility icons; Blizzard re-enables the swipe on every cooldown refresh

**Files modified:** `MergeReanchor.lua`, `MergeMode.lua`
**Commit:** ad22375
**Status:** fixed: requires human verification
**Applied fix:**
- **Style rule.** `ApplyMergedStyle` handles the swipe by icon type, told apart by a field read of `itemFrame.Applications`, which only `CooldownViewerBuffIconItemTemplate` has:
  - Buff icons get `SetDrawSwipe(timerShown)` as before. Blizzard never sets their swipe.
  - Cooldown icons get `SetDrawSwipe(false)` only when Show Timer is off. With Show Timer on, TBT never touches their swipe. Blizzard sets `cooldownShowSwipe = false` on purpose while a charge spell recharges with charges left (CooldownViewer.lua:923), so forcing it on was wrong.
- **Re-assert.** New `ns:ReassertMergedSwipe()` walks TBT's own `placedOn` table and turns the swipe back off on placed cooldown icons whose container has Show Timer off. It is called pcall'd at the end of `ns:RefreshMergeShownSlots`. That pass runs deferred (`C_Timer.After(0)`) on the events Blizzard refreshes cooldown items on: SPELL_UPDATE_COOLDOWN/CHARGES, UNIT_AURA, BAG_UPDATE_COOLDOWN, PLAYER_TOTEM_UPDATE and PLAYER_TARGET_CHANGED. So it runs after Blizzard's `RefreshSpellCooldownInfo`.
- No method on a Blizzard frame or child is hooked.
- **Remaining gaps, recorded as an OPEN ITEM in MergeReanchor.lua:**
  - The frame Blizzard's refresh renders in, before the deferred pass, can show the swipe.
  - A refresh TBT has no event for, such as Blizzard's own charge-gain timer, shows the swipe until the next shown-slot pass.
  - Turning Show Timer back on leaves a cooldown icon's swipe off until Blizzard's next refresh (the next GCD at the latest).
- `RestoreBlizzardStyle`'s `SetDrawSwipe(true)` is unchanged; the reviewer judged it harmless and self-healing.

### WR-04: Merge Mode off restores frames to Blizzard's anchor, but nothing tells TBT the viewer moved back

**Files modified:** `MergeMode.lua`
**Commit:** 5feec99
**Status:** fixed: requires human verification
**Applied fix:**
- `ns:SetMergeMode(false)` now wipes every `ns.mergeShownSlots` list and `ns.mergeItemFrames` inline, before queueing the mirror. This touches no frame, so it is safe inline. Display's old redraw path then has no merged slots to draw over the parked Blizzard frames, and the old relays have no frame cache to read.
- It also calls `ns:MarkMergedPlacementDirty()`. The next render's flush (from Display's own OnUpdate) then reaches `PlaceAllMergedItems` with Merge Mode off and releases every moved frame. The frames are not released synchronously inside the toggle's click handler.

### IN-01: PlaceItem's early returns do not stamp, so a degenerate cell costs four game calls per render

**Files modified:** `MergeReanchor.lua`
**Commit:** 801ad47
**Status:** fixed: requires human verification
**Applied fix:**
- On a zero or unreadable size, `PlaceItem` now calls `ReleaseItem`, because the frame may sit on a cell another id now owns. It then stamps a new weak `unplaceableOn[itemFrame] = cell` together with `placedGen` and `placedID`.
- The dirty check accepts `placedOn == cell or unplaceableOn == cell`, so later passes skip the frame until the generation, cell or id changes.
- A separate table is used so that release-all and the swipe re-assert, which walk `placedOn`, never see a frame TBT did not move.
- `height`, `viewerScale` and `cellHeight` are now `issecretvalue`-guarded.
- The per-render cost the reviewer described was already removed by CR-01, which no longer places from the render. The stamp still matters for the event-driven `PlaceAllMergedItems` call in the shown-slot pass.

### IN-02: The taint-boundary comments in MergeMode.lua are now false

**Files modified:** `MergeMode.lua`
**Commit:** cae051d
**Status:** fixed
**Applied fix:**
- The viewer-suppression block header no longer claims to be the "ENTIRE surface". It now says it is one of exactly two write surfaces and names MergeReanchor.lua's header as the item-frame baseline.
- The `ApplyMergeVisibility` comment no longer says "TBT never touches one". It now points at MergeReanchor.lua.
- No hook API name was added, so the STEAL-08 audit grep stays a true negative.

## Skipped Issues

### IN-05: The Layout hook force-restyles every frame on every Blizzard Layout

**File:** `MergeReanchor.lua` (Layout hook, `PlaceViewer(viewer, true)`)
**Reason:** Optional per orchestrator, and not trivial to keep correct. The suggested test compares `itemFrame:GetScale()` to the stamped scale, which fails in two ways:
1. `OnAcquireItemFrame` sets `SetScale(viewer.iconScale)`. A re-acquired frame whose CDM scale happens to equal TBT's computed scale would skip the restyle, so Blizzard's timer, tooltip and bar-content reset would win.
2. `GetScale()` is not guaranteed to return the exact double passed to `SetScale` (float storage). The comparison could then miss every time, or need an epsilon that widens case 1.

Correctness of the Layout hook outranks the saving, so it still restyles on every Layout.
**Original issue:** `PlaceViewer(viewer, true)` re-runs CaptureBlizzardAnchor, SetScale, SetWidth and all of ApplyMergedStyle for every active frame on every Layout. The restyle is only needed after RefreshLayout/OnAcquireItemFrame.

---

_Fixed: 2026-10-10_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

---

# Iteration 2

**Fixed at:** 2026-10-10
**Source review:** .planning/phases/68-merge-mode-by-re-anchoring/68-REVIEW.md (iteration 2)
**Iteration:** 2

**Summary:**
- Findings in scope: 5 (WR-01, IN-02, IN-03, IN-04, plus IN-01, whose comment-only fix carries no risk)
- Fixed: 5
- Skipped: 0
- Not attempted: IN-05 (the reviewer says no fix is needed now)

As in iteration 1, the work was done directly on `milestone/v0.5.2-improved-merge-mode` with no worktree.
Every commit was followed by `stylua .`. `MergeReanchor.lua` and `Display.lua` stay `w/crlf`, and no `git diff --stat` showed `Bin`.
After the last fix these all passed:
- `node scripts/aura-read-gate.js` (4 reads in 2 allowlisted readers)
- its `--selftest` (30 cases)
- `node scripts/migrate-dryrun.js --selftest` (13 cases)

The build was deployed with `./scripts/install.bat` (v0.5.1-54-g1629261-dev).
No Lua interpreter is installed, so stylua's parser served as the Tier 2 syntax check.

The hard boundary still holds: no `SetParent`, no field write on a Blizzard frame, and no Blizzard mixin call. The only new calls on Blizzard regions are `IsShown` (a C getter) and `SetText` (the plain FontString setter CONTEXT allows), both on the bar's Name and Duration strings, and only inside placement or release, never in the steady-state render. The module header lists both.

## Fixed Issues

### WR-01: A bar's Name text that TBT shows after Blizzard hid it is stale or empty

**Files modified:** `MergeReanchor.lua`
**Commit:** 704cbff
**Status:** fixed: requires human verification
**Applied fix:**
- `AttachMergedItem` records `labelByID[id] = entry.label`. This is a string reference, so there is no allocation and no game call. A changed label alone does not set `placementPending`. `labelByID` is cleared wherever `kindByID` and `settingsByID` are: the Merge-off wipe, the flush prune, and (from IN-03) eviction.
- `SetBarRegions(itemFrame, content, durationShown, label)` fills a string only on the hidden-to-shown edge. That is checked by a new `RegionHidden` helper (`IsShown`, with a secret-value guard; a secret answer counts as shown, so nothing is written).
  - **Name:** revealed with `nameText:SetText(label)` when the label is a non-secret, non-empty string.
  - **Duration:** revealed with `durationText:SetText("")`. While the bar is active, Blizzard's per-OnUpdate `RefreshCooldownInfo` refills it. An inactive bar in preview now shows an empty duration instead of stale text.
  - A string that was already shown is never written, so the text Blizzard maintains (for example an override spell's name from `GetNameText`) wins.
- `RestoreBlizzardStyle` passes no label, so on release the name is never written. Where the CDM's content hides the name, the release still hides it, so TBT's text never stays visible on a released frame.
- **OPEN ITEM added:** on release, a name that TBT had hidden and the CDM shows is revealed with the text it last held. That lasts until Blizzard's next `RefreshName` (its next `RefreshData`). TBT has no label for a frame it is handing back.

### IN-02: Restoring style before the anchor means a raise leaves the frame on a cell another id may now own

**Files modified:** `MergeReanchor.lua`
**Commit:** 885f4c7
**Status:** fixed: requires human verification
**Applied fix:**
- `ReleaseItem` now runs in this order:
  1. `ClearAllPoints`
  2. the pcall'd restore of the captured anchor, falling back to the viewer's TOPLEFT
  3. `RestoreBlizzardStyle`
  4. bookkeeping last
- A raise in the restyle still leaves the frame tracked, so it is retried, but it is already off the TBT cell.
- `RestoreBlizzardStyle` rejects a NaN or infinite `viewer.iconScale` with `not (scale > 0 and scale < math.huge)`.

### IN-03: An evicted id's `kindByID` / `settingsByID` entries are never cleared

**Files modified:** `MergeReanchor.lua`
**Commit:** 3c36740
**Status:** fixed
**Applied fix:**
- The eviction branch in `AttachMergedItem` now clears `kindByID`, `settingsByID` and `labelByID` for the evicted id, together with `cellByID`.
- An evicted id that is re-attached later in the same render re-sets them, and the changed kind/settings sets `placementPending` as usual.

### IN-04: An error anywhere in the render loop skips the flush for that render

**Files modified:** `Display.lua`
**Commit:** fdf651b
**Status:** fixed: requires human verification
**Applied fix:**
- The container loop moved, unchanged, into a file-local `RenderContainers(now)`.
- `ns:UpdateDisplay` runs it as `xpcall(RenderContainers, ReportRenderError, now)` and then always calls `ns:FlushMergedPlacement()`.
- `ReportRenderError` is a file-local that forwards to `geterrorhandler()(err)` at the point of the raise. The error is therefore still reported with its original stack (BugSack and similar addons see the same report), and the containers after the failing one are still skipped, as before.
- There is no closure and no per-tick allocation. `geterrorhandler` is only called on error.
- **Consequence to check in game:** if a render raises partway through, the flush now sees an incomplete attach set. The ids in the skipped containers lose their cells, and their frames go back to the parked viewer for that render. This matches what was actually laid out.

### IN-01: In a Centered container, a merged buff's frame is anchored to a cell with no points, so it appears a few frames late

**Files modified:** `Display.lua`
**Commit:** 1629261
**Status:** fixed
**Applied fix:** This is a comment only, taking the reviewer's first option ("accept it and say so"). The comment above the re-anchor branch in `RenderIconContainer` records the delay as accepted: one frame plus up to `UPDATE_INTERVAL`, each time the buff is applied. It also records why the frame follows the cell once the cell is anchored. There is no runtime change.

## Not Attempted

### IN-05: The unplaceable stamp only clears on a generation, cell or id change

**File:** `MergeReanchor.lua:298-305`, `MergeReanchor.lua:324-328`
**Reason:** The reviewer says "None needed now", and the path is effectively unreachable with today's fixed XML and pooled-widget sizes. The orchestrator also excluded it.
**Original issue:** A frame stamped unplaceable is retried only when `placeGeneration`, its cell or its id changes, or when a Layout hook forces it.

---

_Fixed: 2026-10-10_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
