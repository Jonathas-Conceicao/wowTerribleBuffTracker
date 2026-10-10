---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
plan: 01
subsystem: display
tags: [merge-mode, display, deletion, cdm]
requires: []
provides:
  - Display.lua render path with no merged redraw branches
affects: [70-03 MergeMode.lua engine aura deletion]
tech-stack:
  added: []
  patterns: [fail-closed hide arm for merged entries, preview-only placeholder]
key-files:
  modified: [Display.lua]
decisions:
  - "Merged entries are placed (re-anchor branch), previewed (sweep-less placeholder) or hidden (fail-closed arm); TBT never draws their cooldown, aura, charge or FX"
metrics:
  completed: 2026-10-10
---

# Phase 70 Plan 01: Display redraw path removed Summary

Display.lua no longer draws anything for a merged slot beyond the preview placeholder: the merged cooldown chain, pandemic and dispel FX, bar and countdown relays and every `engineDrawsHere` branch are gone (about 1090 lines deleted, 47 added).

## Commits

- 58deaba: Task 1, merged cooldown chain removed from ApplyCooldownSlot (now four arguments)
- d87a505: Task 2, merged FX, relays and engine-drawn branches removed

## What changed

- ApplyCooldownSlot keeps only the user-duration arm, the `ApplyCooldownHandle(icon, spellID, chargeCapable[spellID] == true)` arm and the clear-and-ungrey terminus. ApplyChargeCount, ApplyItemCount and the chargeCapable cache stay for custom cooldown trackers.
- RenderIconContainer: re-anchor branch, then a single fail-closed `elseif entry.isMerged then icon:Hide()`, then timer, cooldown-slot, placeholder. RenderBarContainer has the matching three-way show/hide.
- ShowMergedPlaceholderIcon is now icon and style only (no SetCooldown, relay or aura read).
- SlotDraws takes four arguments; a merged entry counts from `entry.cdmShown == true` alone (STEAL-23).
- Deleted: pandemic FX section, ApplyDispelBorder and dispelBorder widgets, mergedTime and its font matcher, RelayMergedBar, MERGED_BAR_COLOR, CHARGE_OVER_AURA_LEVEL (the file-load read of `ns.MERGE_AURA_CONTAINER_LEVEL`, so MergeMode.lua may now delete that constant).

## Acceptance results

- Task 1 code-only gate: 0 (baseline 52 whole file); comment hygiene 0; five-argument form 0; four-argument form 3; survival counts 1/2/2/2/1/1/1 as specified.
- Task 2 code-only gate: 0; whole-file identifier gate: 0. SlotDraws counts 1/2/1. `elseif entry.isMerged then` 1, `elseif slot.isMerged then` 2, fail-closed code-only 1. ShowMergedPlaceholderIcon calls 2; preview body forbidden-term count 0; survival 7. Survival greps for AttachMergedItem (2), ownViewer (2/2/2), cdmFrameVisible (2), Begin/FlushMergedPlacement (1/1), CenteredSlotPlacement (1), cdmShown (1) all as specified.
- No added SetParent, SetLayoutData or hooksecurefunc. `stylua --check .` clean, Display.lua stays w/crlf, no Bin in diff.
- aura-read-gate PASS, its selftest PASS (30), migrate-dryrun selftest PASS (13). Deployed with `./scripts/install.bat`.
- MergeMode.lua `ns:PrintMergeDiagnostics` reads `ns.itemCooldownSeen`, `ns.categorySpellID` and `ns.mergeRelayState` behind `ns.x and ns.x[...]` guards, so it cannot raise; plan 70-03 should trim those lines.

## Deviations from Plan

None. Gate baselines were re-measured as the plan allowed; the code-only baseline for Task 2 was not recorded separately.

## Deferred to Phase 72 (in game)

- A custom cooldown tracker still shows sweep, grey and charge count.
- Merge Mode: merged slot shows only Blizzard's moved frame; preview placeholder shows icon and name with no sweep; no TBT FX over merged cells.
- Centered container with merged-only entries closes gaps and re-centres from cdmShown.

## Known Stubs

None.

## Self-Check: PASSED

Display.lua modified and commits 58deaba and d87a505 exist.
