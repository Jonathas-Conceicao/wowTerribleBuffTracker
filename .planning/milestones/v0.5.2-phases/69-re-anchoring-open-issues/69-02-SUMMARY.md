---
phase: 69-re-anchoring-open-issues
plan: 02
subsystem: merge-mode
tags: [cdm, reanchor, steal-14, edit-mode]
requires: [69-01]
provides:
  - entry.cdmFrameVisible stamp (true outside preview)
  - TBT-drawn preview placeholder for merged slots whose Blizzard frame is not drawn
affects: [MergeMode.lua, Display.lua]
key-files:
  modified: [MergeMode.lua, Display.lua]
decisions:
  - "While previewing, a merged slot whose Blizzard item frame is not visible gets TBT's own placeholder and is not attached; TBT never shows a Blizzard frame"
metrics:
  completed: 2026-10-10
---

# Phase 69 Plan 02: STEAL-14 Edit Mode merged preview Summary

Merged bars and icons whose Blizzard frame is not drawn in Edit Mode or the settings window now show TBT's own icon-and-name placeholder; slots whose frame is drawn still show Blizzard's frame.

## Changes
- MergeMode.lua: `CollectVisibleCooldownIDs(viewer)` (uses the `IsVisible` C getter, no `ns.mergeItemFrames` write), declared above `RefreshMergeShownSlots`. `previewing` hoisted once per pass. `entry.cdmFrameVisible` stamped per entry (always true outside preview). Permitted-surface comment extended. The accepted-limitation comment records that the stamp is event-driven, so toggling Edit Mode's Cooldown Manager checkbox can lag.
- Display.lua: `ownMergedPreview` in `RenderBarContainer` and `RenderIconContainer`. When it is set and `cdmFrameVisible == false`, the bar is shown as the placeholder and the icon gets the placeholder reset/fill; neither is attached.

## Commits
- df9d4e9: MergeMode.lua
- 0d1a6ae: Display.lua

## Verification
- Comment-proof counts (non-comment lines): `cdmFrameVisible == false` 2, `local ownMergedPreview = reanchorHere and` 2, `mergeItemFrames` inside CollectVisibleCooldownIDs 0.
- `IsVisible()` 1, `previewing` hoist 1, stamp 1.
- Plan 69-01 attach calls still present (2) with the `or _G[def.cdmViewerGlobal]` fallback.
- No RelayMerged/aura API in added Display lines; no SetParent/SetLayoutData/Show/Hide on Blizzard frames added.
- stylua clean, both files `w/crlf`, no Bin. aura-read-gate PASS (+ selftest 30), migrate-dryrun selftest PASS (13).
- install.bat reached `_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`.

## Deviations from Plan
- The plan's literal attach regex ending in `ns\.cdmViewers\[def\.key\])` does not match, because of the 69-01 binding amendment (fallback viewer). Checked with the fallback form instead.

## Deferred to Phase 72 (in-game)
- Merge Mode on, Edit Mode with the Cooldown Manager checkbox ON: merged bars show Blizzard's bars in TBT's bar container at TBT width.
- Same with the checkbox OFF: every merged bar and buff shows as TBT's placeholder, with no empty rows.
- Toggle Edit Mode's Cooldown Manager checkbox while in Edit Mode: placeholder may lag until the next shown-slot pass (accepted limitation).
- A CDM viewer with Visibility In Combat, out of combat in Edit Mode: its merged entries show as placeholders.
- Leave Edit Mode: placeholders disappear, only live merged entries show.

## Self-Check: PASSED
