---
phase: 77-cleanup
plan: 01
subsystem: cleanup
tags: [cleanup, dead-code, comments, hot-path]
requires: []
provides:
  - 77-AUDIT.md findings and hot-path review (plan 77-02 appends the Scripts review)
affects: [Core.lua, Providers.lua, CDMTab.lua]
tech-stack:
  added: []
  patterns: [keyed registry lookup on the cast path]
key-files:
  created:
    - .planning/phases/77-cleanup/77-AUDIT.md
  modified:
    - Core.lua
    - Providers.lua
    - CDMTab.lua
decisions:
  - "ns:CooldownBuffAuraID deleted: tree-wide non-comment count was 1 (definition only), absent at 3377a8e"
  - "ns:StartCooldownBuffFromCast reads ns.CONTAINER_BY_KEY[entry.section]; hidden/suggested are never registered, so a nil def refuses as the old loop did"
  - "The only >105-column milestone line left is stylua-formatted code in CDMTab.lua (placeholder label), not a comment; out of finding 4"
metrics:
  duration: ~20min
  completed: 2026-10-22
  tasks: 3
  files: 4
---

# Phase 77 Plan 01: Cleanup audit, dead code and cast-path lookup Summary

Wrote the milestone cleanup audit (five re-verified findings, five keeps, two unify rows for 77-02, and a verdict for each hot path). Then deleted the unused `ns:CooldownBuffAuraID`, fixed three stale or wrong comments, re-wrapped three comment lines that were too long, and replaced the per-cast `ipairs(ns.CONTAINERS)` walk with a single `ns.CONTAINER_BY_KEY` read.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Re-verify findings, sweep, write 77-AUDIT.md | 9ea2e40 | .planning/phases/77-cleanup/77-AUDIT.md |
| 2 | Remove dead ns:CooldownBuffAuraID, fix stale and overlong comments | 9591878 | Core.lua, Providers.lua, CDMTab.lua |
| 3 | One CONTAINER_BY_KEY read in ns:StartCooldownBuffFromCast | 5135667 | Providers.lua |

## Verification

- All three task gates printed PASS.
- `stylua --check .` is clean. `node scripts/aura-read-gate.js` passes, and so does its `--selftest` (30 cases).
- Core.lua, Providers.lua and CDMTab.lua are `w/crlf`, with no `\r\r`.
- This plan made no TOC change. The only TOC diff since 3377a8e is `tools/TBTProbe/TBTProbe.toc`, from an earlier phase. CURRENT_SCHEMA_VERSION is untouched.
- `./scripts/install.bat` deployed to every client folder.
- The tree-wide sweep of milestone-added names, saved keys (`buffEnabled`, `buffAuraID`, `buffDuration`) and proc/icon fields found no unused name other than `ns:CooldownBuffAuraID`.
- Deferred to Phase 78, in game: with its buff on, a user cooldown in an icon container still starts its buff on cast, and one in a bar container still starts none.

## Deviations from Plan

None. The plan ran as written.

## Known Stubs

None.

## Threat Flags

None. T-77-01 is covered because a nil def refuses, T-77-02 because the gate asserts no `{` in the cast function, and T-77-03 because the tree-wide grep was recorded before the deletion and shows 0 after it.

## Self-Check: PASSED

- FOUND: .planning/phases/77-cleanup/77-AUDIT.md
- FOUND: 9ea2e40, 9591878, 5135667
