---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
plan: 04
subsystem: merge-mode
tags: [merge-mode, cleanup, diagnostics]
requires: ["70-02", "70-03"]
provides: ["ns:GetMergedPlacementKind", "trimmed /tbt merge"]
key-files:
  modified: [MergeMode.lua, MergeReanchor.lua]
metrics:
  completed: 2026-10-10
---

# Phase 70 Plan 04: Item-frame cache removal and diagnostics trim Summary

Removed `ns.mergeItemFrames` (no readers left), trimmed `/tbt merge` to mirror identity, shown/visible stamps and placement-map cell kind, reworded the re-anchoring markers, and swept the tree for deleted names (0 hits).

## Commits
- 034ab83: refactor(70-04): drop item-frame cache, trim /tbt merge (Tasks 1 and 2 share one commit; the marker rewording touched the same files)

## What changed
- MergeMode.lua: deleted the cache declaration, its write in CollectShownCooldownIDs, the wipes in RefreshMergeShownSlots and SetMergeMode; rewrote the SetMergeMode and CollectVisibleCooldownIDs comments; per-entry diagnostics lost itemCD/catSpell/relay bits and gained `shown=`, `visible=`, `cell=icon|bar|none`. Three "Merge Mode re-anchoring (MergeReanchor.lua):" markers became plain comments.
- MergeReanchor.lua: added `ns:GetMergedPlacementKind(cooldownID)` (TBT tables only, no game call); rewrote the placementPending comment.

## Sweep result
`cat *.lua *.xml *.toc scripts/*.js | grep -cE "<deleted names>"` printed 0. `mergeReanchorExperiment` count in *.lua is 1 (Core.lua clear). `categorySpellID` count is 0.

## Gates
stylua --check passes; both files w/crlf; no Bin in diff; aura-read-gate PASS (1 read, 1 reader), selftest PASS (30), migrate-dryrun selftest PASS (14). TOC untouched by this phase (last TOC commit predates it): no file left or joined the load list, so a /reload is enough for testing. Deployed with install.bat.

## Deviations
None. MergeReanchor.lua header already read as present-tense; left as is (its "experiment" is lowercase and outside the sweep).

## Deferred to cleanup phase
- None. (Corrected after the 70 code review, WR-01: this entry used to say `ns.SPELL_CATEGORY_COMBAT_POTION` (Core.lua) lost its only reader with the engine aura containers. That was wrong. `Providers.lua:783` still reads it for the Pot meta-tracker's unresolved icon, so it must be kept and is not a cleanup candidate.)

## Deferred to Phase 72 (in-game)
- `/tbt merge` with Merge Mode on and off: confirm shown/visible/cell bits print and no errors.

## Self-Check: PASSED
