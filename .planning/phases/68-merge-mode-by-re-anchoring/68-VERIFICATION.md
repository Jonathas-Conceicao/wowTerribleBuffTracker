---
phase: 68-merge-mode-by-re-anchoring
verified: 2026-10-10T00:00:00Z
status: human_needed
score: 6/6 source-checkable must-haves verified
overrides_applied: 0
human_verification:
  - test: "Taint: play through combat, Edit Mode, combat with Edit Mode open, a spec change and an M+ key with Merge Mode on"
    expected: "No taint or ADDON_ACTION_BLOCKED error attributed to TBT or Blizzard_CooldownViewer"
    why_human: "Taint only shows in the live client (STEAL-12). Deferred to Phase 72 by user decision."
  - test: "Visual placement and size: merged icons and bars sit on their TBT slots at TBT's icon size, row height and row width, in order, direction, Centered and padding, interleaved with the player's own trackers"
    expected: "Blizzard-drawn frames fill the slots, nothing overlaps, and cooldown, charge, aura timer, glow, pandemic and dispel visuals match the CDM (STEAL-10, STEAL-11)"
    why_human: "Rendering"
  - test: "Change the CDM's size, opacity and settings, then change TBT container scale, opacity, timer, tooltips, bar width and bar content"
    expected: "CDM changes do not alter merged frame size or opacity. TBT changes apply on the next render (STEAL-16)."
    why_human: "Live Blizzard behavior"
  - test: "Turn Merge Mode off with no /reload, including after frames went back to Blizzard's pool"
    expected: "Every moved frame is back in its viewer at its own anchor, scale, alpha, timer, tooltip and bar state (STEAL-18)"
    why_human: "Depends on Blizzard re-layout and pool behavior"
  - test: "Centered container, buff applied that the CDM did not show before"
    expected: "Frame appears about one frame plus UPDATE_INTERVAL late (accepted in review IN-01); confirm this is tolerable"
    why_human: "Feel"
  - test: "Show Timer off on an Essential or Utility container"
    expected: "Swipe stays off. Known gap, per the OPEN ITEM comment in MergeReanchor.lua: a frame can show the swipe briefly before the deferred pass."
    why_human: "Live Blizzard behavior"
---

# Phase 68: Merge Mode by Re-Anchoring Verification Report

**Phase Goal:** Merge Mode draws every merged CDM entry with Blizzard's own CDM item frame, placed on its TBT slot and styled by TBT's container settings, touching Blizzard's frames only through plain C widget setters on item frames and their child regions plus one Layout post-hook per viewer, with no per-tick re-placement. Turning Merge Mode off restores the viewers without /reload.
**Status:** human_needed. All source-checkable items pass. In-game checks are deferred to Phase 72 by user decision.
**Re-verification:** No, initial verification.

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | STEAL-10: Blizzard's item frame draws each merged slot; TBT's own widget stays hidden | VERIFIED (static) | `Display.lua` 2308-2310 and 2492-2504 hide the pooled `bar` or `icon` and call `ns:AttachMergedItem`. `MergeReanchor.lua` `PlaceItem` anchors the item frame to the cell with `SetScale`, `SetWidth` for bars, `ClearAllPoints` and `SetPoint`. Old redraw paths are gated with `not reanchorHere` at 2198, 2212, 2293, 2473 and 2488. `MergeMode.lua` 1001-1094 gates the engine and merged reads on `reanchor`. Real rendering needs a human. |
| 2 | STEAL-11: TBT's grid keeps order, direction, Centered and padding, and shares containers with the player's trackers | VERIFIED (static) | The layout code is unchanged. The merged slot still goes through the normal layout and style, and the render only hides the cell and attaches. `SlotDraws(..., engineDrawsHere or reanchorHere)` keeps the merged entry in the grid. Visuals need a human. |
| 3 | STEAL-12: plain C setters and one Layout post-hook per viewer only | VERIFIED | `git grep` for `SetParent`, `GetCooldownFrame`, `SetTimerShown`, `SetTooltipsShown`, `SetBarContent` and `RefreshLayout` in `MergeReanchor.lua` matches comments only (lines 27, 31, 115, 197). The only `hooksecurefunc` is on `viewer, "Layout"` (line 543), guarded by `hookedViewers`. All state is held in TBT-owned weak tables, with no writes to Blizzard frame fields. Setters used: `SetScale`, `SetWidth`, `SetPoint`, `ClearAllPoints`, `SetAlpha`, `SetIgnoreParentAlpha`, `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `SetHideCountdownNumbers`, `SetDrawSwipe`, `SetShown`, `SetText`. All are on item frames or their child regions, which matches the widened 2026-10-10 REQUIREMENTS.md text. The `Bar` `SetPoint` and the `Name` and `Duration` `SetText` are child-region setters. No-taint-in-play is human-only. |
| 4 | STEAL-16: the CDM's size and opacity do not change merged frame size or opacity | VERIFIED (static) | Scale is computed from the cell's effective height over the viewer's effective scale and the frame height. Bar width is taken from the cell. Alpha is set from `settings.alpha` with `SetIgnoreParentAlpha(true)`. |
| 5 | STEAL-17: re-place only on a slot or size change or a viewer Layout; no per-tick re-placement | VERIFIED (static) | The `PlaceItem` dirty check uses `placedOn`, `placedGen` and `placedID` stamps. The Layout hook forces placement. `AttachMergedItem` only records intent. `FlushMergedPlacement` is one counter comparison plus a boolean test in the steady state. `Display.lua` 251 bumps the generation from `RefreshContainerSettings`. `MergeMode.lua` 2274 and the UI scale and Edit Mode events also bump it. |
| 6 | STEAL-18: Merge Mode off returns frames to the viewers without /reload | VERIFIED (static) | `PlaceAllMergedItems` with Merge Mode off wipes the maps and runs `ReleaseItem` over every frame in `placedOn`, active or pooled, each under its own pcall. `ReleaseItem` restores the captured Blizzard anchor, with a TOPLEFT fallback, then calls `RestoreBlizzardStyle` (scale, alpha, mouse, bar width, bar content, timer, swipe). `MergeMode.lua` 246 and 418 call `ReanchorMergeViewers` on both the on and off paths. Live restore needs a human. |

**Score:** 6/6 verified statically. Live behavior is human-only.

## Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| STEAL-10 | 68-01, 68-02 | SATISFIED (static) | Truth 1 |
| STEAL-11 | 68-02 | SATISFIED (static) | Truth 2 |
| STEAL-12 | 68-01, 68-02 | SATISFIED (static) | Truth 3. Checked against the current widened REQUIREMENTS.md text. |
| STEAL-16 | 68-01, 68-02 | SATISFIED (static) | Truth 4 |
| STEAL-17 | 68-01, 68-02 | SATISFIED (static) | Truth 5 |
| STEAL-18 | 68-01 | SATISFIED (static) | Truth 6 |

- All six IDs are claimed by the plans and are mapped to Phase 68 in the REQUIREMENTS.md traceability table. No orphaned IDs.
- The REQUIREMENTS.md checkboxes are still `[ ]` and the traceability status is still "Pending". Tick them after Phase 72 confirms the live behavior.
- STEAL-13/14/15 belong to Phase 69 and STEAL-19 to Phase 70, so they are out of scope here.

## Wiring

- `MergeReanchor.lua` is in the TOC at line 17.
- `Display.lua` calls `BeginMergedPlacement` (2832) and `FlushMergedPlacement` (2858). `FlushMergedPlacement` runs after `xpcall(RenderContainers, ...)`, so it is reached even if a render raises (review IN-04).
- `MergeMode.lua` calls `PlaceAllMergedItems` and `ReassertMergedSwipe` after the shown-slot pass. `ReanchorMergeViewers` is called on both Merge Mode transitions.
- `/tbt reanchor` is now a no-op print (Core.lua 2135). Removing it is Phase 70.

## Behavioral Spot-Checks and Probes

| Check | Result |
|-------|--------|
| `node scripts/aura-read-gate.js` | PASS (4 reads in 2 allowlisted readers) |
| `node scripts/migrate-dryrun.js --selftest` | PASS (13 cases) |
| Phase-declared probes | None |

## Anti-Patterns

No TBD, FIXME or XXX markers were found in the files I read. The accepted limitations are documented in comments: the Centered first-frame delay (IN-01), the Show Timer swipe gaps, bar name revealed on release, and Hide When Inactive and Visibility (Phase 69). IN-05 was deliberately not attempted by the reviewer.

## Gaps Summary

No source-level gaps. The remaining risk is live behavior (taint, visuals, restore on Merge Mode off), which is deferred to Phase 72 and listed in the human verification items above.

_Verifier: Claude (gsd-verifier)_
