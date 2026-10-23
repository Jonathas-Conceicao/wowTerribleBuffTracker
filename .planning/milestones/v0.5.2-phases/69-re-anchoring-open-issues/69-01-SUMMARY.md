---
phase: 69-re-anchoring-open-issues
plan: 01
subsystem: merge-mode
tags: [cdm, reanchor, steal-13]
requires: []
provides:
  - viewer ownership check in placement
  - render-before-place after mirror rebuild
affects: [MergeReanchor.lua, Display.lua, MergeMode.lua]
key-files:
  modified: [MergeReanchor.lua, Display.lua, MergeMode.lua]
decisions:
  - "A frame whose parent is not the attaching container's viewer is treated as having no cell"
metrics:
  completed: 2026-10-10
---

# Phase 69 Plan 01: STEAL-13 settings-window reorder Summary

Viewer-ownership check in PlaceItem plus render-before-place after a mirror rebuild, so a moved CDM entry never sits on another container's cell.

## Changes
- MergeReanchor.lua: `viewerByID` map (cleared with the other per-id maps), 5-argument `AttachMergedItem(entry, cell, settings, kind, viewer)`, same-render duplicate-attach guard, `PlaceItem` releases a frame whose parent is not `viewerByID[id]`, Layout-hook comment rewritten.
- Display.lua: both attach calls pass `ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal]` (orchestrator amendment: never a nil viewer).
- MergeMode.lua: `mirrorChangedForPlacement` flag (declared above RefreshMergeMirror), set on the Merge-on rebuild path, consumed in `RefreshMergeShownSlots` by `pcall(ns.UpdateDisplay, ns)` before `PlaceAllMergedItems`; STEAL-13 finding recorded above `BuildViewerIDs`.

## Commits
- 5fe7f6b: MergeReanchor.lua
- 765e804: Display.lua, MergeMode.lua

## Verification
- viewerByID count 7, `viewerByID[id]` count 4, stylua clean, all three files `w/crlf`, no Bin in diff.
- aura-read-gate PASS, its selftest PASS (30), migrate-dryrun selftest PASS (13).
- No added SetParent/SetLayoutData. install.bat deployed.
- Amendment gate: fallback `_G[def.cdmViewerGlobal]` present at both attach sites.

## Deviations from Plan
- [Amendment] The Display attach call sites use the `or _G[def.cdmViewerGlobal]` fallback, so they do not match the plan's literal `ns.cdmViewers[def.key])` pattern; the amendment is binding.

## Deferred to Phase 72 (in-game)
- Drag a Tracked Buff within its category with Merge Mode on and the CDM window open: the container reorders, nothing shows in another container.
- Drag a buff into Tracked Bars and back: bar appears at TBT bar width, left-aligned, never in the buff container.
- Reorder in Essential/Utility (same-count path): order follows immediately.

## Self-Check: PASSED
