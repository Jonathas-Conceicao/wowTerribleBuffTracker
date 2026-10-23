---
phase: 69-re-anchoring-open-issues
verified: 2026-10-10T00:00:00Z
status: human_needed
score: 12/12 source-checkable must-haves verified
overrides_applied: 0
human_verification:
  - test: "Open the CDM settings window, reorder an entry within a category, then move a buff to the bar category and back"
    expected: "TBT's preview follows immediately; the entry never appears in the wrong container; bars keep the right width and alignment (STEAL-13)"
    why_human: "Needs the live client and the Blizzard Layout/drag flow"
  - test: "Open Edit Mode with the Cooldown Manager checkbox on, then off, with merged buffs and bars configured"
    expected: "Every merged entry shows, bars included; an entry Blizzard does not draw shows TBT's placeholder, not an empty cell (STEAL-14)"
    why_human: "Depends on Blizzard's Edit Mode viewer state; accepted lag after toggling the checkbox (until the next shown-slot pass)"
  - test: "Set a container to Visibility Hidden, In Combat (out of combat) and enable Hide When Inactive; then show it again"
    expected: "Merged frames vanish with the container and are not hoverable; they return on the same render when it shows (STEAL-15)"
    why_human: "Runtime visual and tooltip behaviour"
  - test: "Set a CDM viewer's own Visibility to Hidden or In Combat while it has merged entries"
    expected: "One chat notice per viewer per session naming the fix; no notice for unknown values"
    why_human: "Live client"
  - test: "Combat, Edit Mode during combat, spec change, M+"
    expected: "No taint errors"
    why_human: "Deferred to Phase 72 by user decision"
---

# Phase 69: Re-anchoring Open Issues Verification Report

**Phase Goal:** Reordering or moving an entry in the CDM settings window updates TBT's preview immediately and correctly; Edit Mode preview shows every merged entry, bars included; a TBT container hidden by its visibility setting hides its merged frames and showing it brings them back.
**Status:** human_needed. All source-checkable items pass. In-game checks are deferred to Phase 72 by user decision.
**Re-verification:** No (initial). I verified the final code after the review-fix round (WR-01..03, IN-01..05, all committed), not only the plans.

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A frame is placed only on a cell of the container mirroring its own viewer (STEAL-13) | VERIFIED | `MergeReanchor.lua` PlaceItem: `if cell and parent ~= viewerByID[id] then cell = nil`. `viewerByID` is set in AttachMergedItem. Both Display call sites pass `ownViewer` (Display.lua:2108, 2327, 2443, 2586). |
| 2 | A buff-to-bar move never leaves a bar CENTER-anchored on an icon cell | VERIFIED | The viewer-ownership check releases the mismatched frame. `kind` comes from `kindByID[id]` per attach. |
| 3 | After a mirror rebuild, TBT renders from the new lists before placing | VERIFIED | `mirrorChangedForPlacement` (MergeMode.lua:152, set at 510, consumed at 1281 by a `UpdateDisplay` call). WR-03: `ReanchorMergeViewers(true)` skips the forced pass, so the first placement goes through the new map. |
| 4 | The cooldownID to cell map is rebuilt whole every render | VERIFIED | `BeginMergedPlacement` bumps `renderGen`. The `attachGen`/`attachedCount`/`mappedCount` stamps drive the prune in `FlushMergedPlacement`, which clears all five per-id maps. |
| 5 | A duplicate attach in one render keeps the first cell, with no flip | VERIFIED | `attachGen[id] == renderGen and cellByID[id] ~= cell` returns early. IN-01 also de-duplicates upstream through `frameOwnerByID` and `claimedIDs`. |
| 6 | STEAL-17 intact: no per-tick re-placement, no steady-state allocation | VERIFIED | The flush is one comparison plus one flag test when clean. `placedOn`/`placedGen`/`placedID` hold the dirty check. The new tables are module-level and `wipe()`d. |
| 7 | Edit Mode shows every merged entry, bars included (STEAL-14) | VERIFIED (source) | `CollectVisibleCooldownIDs` (IsVisible C getter, preview only) feeds `entry.cdmFrameVisible`. Both render functions branch on `cdmFrameVisible == false`: the placeholder is drawn and nothing is attached. Otherwise the frame is attached. |
| 8 | A visible Blizzard frame is still used as-is, with no second copy | VERIFIED | The attach branch hides TBT's own widget (`bar:Hide()` / `icon:Hide()`). |
| 9 | Outside preview nothing changes | VERIFIED | The stamp is `not (previewing and reanchor) or ...`, so it is true outside preview. WR-01 made both renderers use the stamp alone. |
| 10 | A hidden container sends its merged frames back to the parked viewer, not SetAlpha(0) (STEAL-15) | VERIFIED | Every hide path returns before AttachMergedItem (Display.lua:2118, 2455, 2849). The id then loses its cell in the flush prune and PlaceItem calls `ReleaseItem`. No alpha hiding was added. |
| 11 | Showing the container re-attaches the frames on the same render | VERIFIED | A new attach sets `placementPending`, and the flush places in that render. |
| 12 | The STEAL-15 rule is documented and a one-time CDM Visibility notice exists | VERIFIED | The OPEN ITEM rewrite and the flush comment are in MergeReanchor.lua. `ns:CheckMergeViewerVisibility` is at MergeMode.lua:266, pcall'd at 521 and in `FlushMergeVisibility` (IN-02). Only InCombat and Hidden warn (IN-03). |

**Score:** 12/12 source-checkable truths verified.

## Hard boundary re-check

- No SetParent in MergeReanchor.lua. The one grep hit is the "Never:" header comment. The `SetParent` in MergeMode.lua:1844 is on TBT's own container.
- Blizzard frame writes are only the C setters listed in the module header. There is no Show/Hide on Blizzard frames, no mixin calls and no field writes.
- New Blizzard-frame reads from the review fixes: `GetPoint` via `CaptureBlizzardAnchor` (already in the header's getter list), `IsVisible` C getter, and `cooldownID` field reads in pool walks.
- `node scripts/aura-read-gate.js` passes (4 reads in 2 allowlisted readers), and its `--selftest` passes (30 cases). `node scripts/migrate-dryrun.js --selftest` passes (13 cases).
- Line endings: all three Lua files are `w/crlf`, `eol=crlf`. No TBD/FIXME/XXX markers.

## Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|---|---|---|---|
| STEAL-13 | 69-01 | SATISFIED in source, in-game check pending | Truths 1-6 |
| STEAL-14 | 69-02 | SATISFIED in source, in-game check pending | Truths 7-9 |
| STEAL-15 | 69-03 | SATISFIED in source, in-game check pending | Truths 10-12 |

REQUIREMENTS.md maps STEAL-13/14/15 to Phase 69 (still shown as Pending and unticked there). No orphaned requirement IDs. The traceability table and checkboxes should be updated once Phase 72 confirms them in-game.

## Anti-Patterns

None blocking. Known, documented limitations:
- The `cdmFrameVisible` stamp can lag after toggling Edit Mode's Cooldown Manager checkbox until the next shown-slot pass.
- A same-viewer reorder can sit on its old cell until the following render.

## Gaps Summary

No source-level gaps. The behaviour is runtime and visual (Blizzard Layout, Edit Mode and settings-window state), so the in-game items above are recorded as human verification, deferred to Phase 72.

_Verified: 2026-10-10_
_Verifier: Claude (gsd-verifier)_
