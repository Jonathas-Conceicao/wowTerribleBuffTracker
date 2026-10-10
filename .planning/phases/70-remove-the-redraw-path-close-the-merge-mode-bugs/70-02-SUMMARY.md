---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
plan: 02
subsystem: core
tags: [merge-mode, slash-command, saved-variables, migration-dryrun]
requires: []
provides:
  - /tbt reanchor removed; saved prototype flag cleared silently on every load
affects: [70-03]
key-files:
  modified: [Core.lua, MergeReanchor.lua, scripts/migrate-dryrun.js]
decisions:
  - "Dead flag cleared by an ADDON_LOADED defaults line next to dialogStyle, no schema bump"
metrics:
  completed: 2026-10-10
---

# Phase 70 Plan 02: Remove /tbt reanchor and clear the saved flag Summary

`/tbt reanchor` is gone (it now falls to the default branch and opens settings), ns:ToggleMergeReanchorExperiment is deleted, and ADDON_LOADED clears `ns.db.mergeReanchorExperiment` silently; the dry-run mirrors it with selftest case N.

## Commits

- 4dbf758: Task 1, command, toggle function and EXPERIMENT marker removed; clear added after `ns.db.dialogStyle = nil`
- Task 2 commit: dry-run mirror and selftest case N (see git log, "test(70-02)")

## Acceptance results

- Clear line count 1, ordered after `ns.db = TerribleBuffTrackerDB`; `"reanchor"` in Core.lua 0; ToggleMergeReanchorExperiment across *.lua 0; EXPERIMENT across lua/xml/toc 0.
- stylua --check clean; Core.lua, MergeReanchor.lua, migrate-dryrun.js stay w/crlf; no Bin in diff.
- migrate-dryrun selftest: PASS (14 cases). `mergeReanchorExperiment` appears 5 times in the script; `function caseN(expect)` 1.
- Vacuity check done: with the `db.delete` removed (scratch copy), case N reported SELFTEST FAIL (1/14); restored source passes 14.
- aura-read-gate PASS, its selftest PASS (30). Deployed with `./scripts/install.bat`.

## Deviations from Plan

None.

## Deferred to Phase 72 (in game)

- `/tbt reanchor` opens TBT settings; a database that carried the flag loads without it and without chat output (a /reload is enough, no TOC change).

## Known Stubs

None.

## Self-Check: PASSED
