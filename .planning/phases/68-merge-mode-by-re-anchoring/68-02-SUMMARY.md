---
phase: 68-merge-mode-by-re-anchoring
plan: 02
subsystem: merge-mode
tags: [cdm, re-anchor, merge-mode, display]
requires: [68-01]
provides:
  - "Display render passes hand every merged slot to ns:AttachMergedItem(entry, cell, settings, kind)"
  - "RefreshContainerSettings bumps the placement generation"
affects: [69, 70]
key-files:
  modified:
    - Display.lua
    - MergeMode.lua
key-decisions:
  - "Old redraw code stays but is unreachable under Merge Mode; deletion is Phase 70"
metrics:
  completed: 2026-10-10
---

# Phase 68 Plan 02: Wire Display and MergeMode to the re-anchor engine Summary

With Merge Mode on, Display places every merged icon and bar slot through the re-anchor engine with the container's settings, and the TBT-drawn redraw path (dispel border, bar relay, merged pandemic/dispel reads) is unreachable.

## What changed
- Display.lua: `AttachMergedItem(slot, bar, settings, "bar")` and `(entry, icon, settings, "icon")`; `RefreshContainerSettings` ends with a guarded `ns:MarkMergedPlacementDirty()`; dispel border and `RelayMergedBar` gated on `not reanchorHere`; prototype markers replaced.
- MergeMode.lua: `ReadPandemicState` / `ReadDispelBorder` wrapped in `if not reanchor then`; all six prototype markers replaced. `entry.cdmShown` stamping untouched (Centered).
- Core.lua untouched (`/tbt reanchor` removed in Phase 70).

## Commits
- d9b76c4: Display wiring
- (next commit): MergeMode reads and markers

## Deviations from Plan
- The two long `ApplyDispelBorder(...)` calls were reflowed to multi-line form (stylua formatting); the gate greps still match. Otherwise none.

## Verification
Both tasks' gate chains print GATES-PASS: stylua clean, all three files `w/crlf`, no `Bin` in diff, aura-read-gate (plain and --selftest) and migrate-dryrun --selftest pass, `install.bat` deployed. Zero `EXPERIMENT (MergeReanchor.lua)` markers remain in Display.lua or MergeMode.lua.

## Deferred in-game checks (Phase 72)
- Every merged icon and bar is Blizzard's own frame on its TBT slot at TBT's size; cooldowns, charges, aura timers, glows, pandemic and dispel borders look as on the CDM.
- Order, direction, Centered, padding follow TBT and interleave with own trackers without overlap.
- CDM resize/config does not change merged sizes; TBT Icon Size / Bar Width / Opacity / Show Timer / Show Tooltips / Display Mode do.
- No taint error through combat, Edit Mode, combat with Edit Mode open, and spec change (M+).
- Merge Mode off without /reload returns every frame to its viewer and restores viewer positions.

## Known, outside this phase
STEAL-13/14/15 (Phase 69); Hide When Inactive per merged item (open item in MergeReanchor.lua).

## Self-Check: PASSED
