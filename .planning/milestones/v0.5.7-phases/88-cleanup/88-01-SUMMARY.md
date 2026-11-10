---
phase: 88
plan: 01
requirements: [CLEAN-02]
mode: inline (orchestrator)
---

# Phase 88: Cleanup — Summary

Reviewed `git diff main -- '*.lua'` (Phases 86-87: Core.lua, Providers.lua, ReminderClick.lua).

## Changes

- **Duplication unified:** Phase 86's file-local `OfferItemInBags` repeated the guarded
  `C_Item.GetItemCount` read inside `ReminderClick.lua`'s `PickUseItem`. Both now call one
  `ns:ItemInBags(itemID)` in Providers.lua (missing API, failed pcall, secret or non-number count all
  mean no). Behaviour identical: `PickUseItem` still reads the level first and returns the same
  attribute. On `ns`, so no upvalue-order trap.

## Checked, no change needed

- No unused locals or dead branches in the milestone diff.
- Hot paths: the load-refresh branch adds one map read per reminder per rebuild (event-driven, not
  per frame); the `BAG_UPDATE_DELAYED` re-mark is unchanged code (comment only); the bag read runs
  only when Suggested is drawn and when the click overlay flushes. No table or string is built.
- Release files: `git diff main --stat -- scripts .pkgmeta .github TerribleBuffTracker.toc` is
  empty.
- `stylua .` and `stylua --check .` clean; Providers.lua and ReminderClick.lua `w/crlf`.
- `reminders-doc-check.js` PASS, `--selftest` PASS, `aura-read-gate.js` and `--selftest` PASS.
- Phase 86's own gate `86-check.js` now reports the Phase 87 rows and this rename as diffs from its
  Phase 86 baseline; it is a phase-scoped gate and is not rerun after its phase.
