---
phase: 71-cleanup
plan: 02
subsystem: cleanup
tags: [claude-md, scripts-review, deploy]
requires: [71-01]
key-files:
  modified: [CLAUDE.md, .planning/phases/71-cleanup/71-AUDIT.md]
metrics:
  completed: 2026-10-10
---

# Phase 71 Plan 02: CLAUDE.md and scripts review Summary

CLAUDE.md now lists MergeReanchor.lua as Merge Mode's placement engine and the MergeMode.lua line no longer claims it never touches a CDM frame; scripts reviewed with no defect found, all gates pass, build deployed.

## Commits
- 3529a83: docs(71-02) CLAUDE.md Architecture edits (2 added, 1 removed line; still w/crlf, exact-match node replacement)
- docs(71-02) scripts review appended to 71-AUDIT.md (see `git log`)

## Script verdicts
install.ps1, release.bat, .pkgmeta, TOC: all OK, unchanged this milestone; MergeReanchor.lua is in the load list and exists.

## Gate results
- stylua . / --check . clean
- aura-read-gate PASS (1 read, 1 reader); selftest PASS (30); migrate-dryrun selftest PASS (14)
- all .lua w/crlf; no Bin in diff stat; CHANGELOG.md, README.md, TOC untouched
- EndTimer sweep 0; SPELL_CATEGORY_COMBAT_POTION in Providers.lua: 1

## Deployed
Version v0.5.1-109-g3529a83-dev to _retail_, _ptr_, _beta_, _classic_beta_ client folders.

## Deviations from Plan
None. (Edit tool avoided in favor of the plan's sanctioned exact-match node replacement.)

## Phase 72 in-game checks (deferred)
Merge Mode on and off; CDM reorder; Edit Mode preview of a merged entry with a hidden frame; merged buffs appear and disappear. TOC unchanged, so /reload suffices.

## Self-Check: PASSED
