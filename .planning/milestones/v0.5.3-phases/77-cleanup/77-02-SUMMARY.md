---
phase: 77-cleanup
plan: 02
subsystem: cleanup
tags: [cleanup, unify, scripts-review]
requires: [77-01]
provides:
  - ns:FinishTrackerEdit, the one end-of-save sequence of both edit commits
  - five file-local Duration box helpers shared by the duration and buffDuration fields
  - 77-AUDIT.md Scripts review and Deferred to Phase 78 sections
affects: [BuffEngine.lua, CDMTab.lua]
tech-stack:
  added: []
  patterns: [shared ns end-of-save helper, file-local field helpers above TRACKER_FIELDS]
key-files:
  created: []
  modified:
    - BuffEngine.lua
    - CDMTab.lua
    - .planning/phases/77-cleanup/77-AUDIT.md
decisions:
  - "ns:FinishTrackerEdit prints first, then ns:ApplyCooldownBuffEdit and the dirty/redraw trio; the item path used to apply before printing, but neither step reads the other's output, so the order change is invisible"
  - "The duration field's validate is a wrapper calling ValidateDurationBox(state, nil): validate is called as (state, ctx), so passing the helper directly would turn ctx into the message"
  - "opts.follows now takes (state, ctx) like every other hook, so buffAuraID passes NotItemField directly"
  - "No script changed: the review found no defect the milestone introduced"
metrics:
  duration: ~15min
  completed: 2026-10-22
  tasks: 3
  files: 3
---

# Phase 77 Plan 02: Unify the milestone's duplicates and review the scripts Summary

Both edit commits now end through one `ns:FinishTrackerEdit(key, entry, label, detail)`, which closes Phase 76 review IN-03. The chat lines print the same text as before. The Duration and buff Duration boxes share five file-local helpers (`BuildDurationRow`, `ResetDurationBox`, `PrefillDurationBox`, `ReadDurationBox`, `ValidateDurationBox`). The buff Aura ID's never-follows rule for a bag item is now `NotItemField`. The scripts review found nothing to change.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | One ns:FinishTrackerEdit for both edit commits (IN-03) | 439d319 | BuffEngine.lua |
| 2 | Shared Duration box helpers; follows = NotItemField | 1d206cb | CDMTab.lua |
| 3 | Scripts review, Architecture check, phase-wide gates | b2e1c86 | .planning/phases/77-cleanup/77-AUDIT.md |

## Verification

- All three task gates printed PASS, each run after `stylua .`.
- `stylua --check .` is clean. Every tracked `.lua` is `w/crlf` with no `\r\r`, and `git diff --stat` showed no `Bin`.
- `node scripts/aura-read-gate.js` passes. Its `--selftest` passes 30 cases and `node scripts/migrate-dryrun.js --selftest` passes 13. `CURRENT_SCHEMA_VERSION` is 12 both at 3377a8e and now.
- Fixture deploy: install.ps1 deployed the 23 files derived from the TOC to both `_forever_` and `_retail_`. `DurationProbe.lua` was not deployed. The version was substituted only in the deployed TOC.
- `./scripts/install.bat` was run for real. It deployed to `_retail_`, `_ptr_`, `_beta_`, `_forever_` and `_classic_era_`.
- This plan touched only BuffEngine.lua and CDMTab.lua among the Lua files. It made no TOC change and no schema change. STATE.md, ROADMAP.md and CHANGELOG.md were not touched.
- Post-commit performance review: every changed function runs at edit time or dialog time, so none of them is on a hot path. No per-frame work was added.

## Deviations from Plan

None. The plan ran as written.

## Deferred to Phase 78 (in game)

These are listed in 77-AUDIT.md:
- The Duration box works as before on Add and Edit.
- The buff Duration box validates and saves.
- A bag item's Aura ID never follows the Spell ID.
- The chat lines are unchanged.
- A cooldown buff still starts on cast in an icon container.
- The stale `_classic_beta_` copy (Phase 73 WR-01, declined) is still on the checklist.

## Known Stubs

None.

## Threat Flags

None. T-77-04 is covered because the validate wrappers pass an explicit message. T-77-05 is covered because label and detail are resolved before the first write. T-77-06 is covered because the fixture shows DurationProbe.lua is never deployed and .pkgmeta ignores `tools`. T-77-07 is covered because release.bat was reviewed statically only.

## Self-Check: PASSED

- FOUND: BuffEngine.lua (`function ns:FinishTrackerEdit(key, entry, label, detail)`)
- FOUND: CDMTab.lua (`local function ReadDurationBox(state)`)
- FOUND: .planning/phases/77-cleanup/77-AUDIT.md (`## Scripts review`)
- FOUND: 439d319, 1d206cb, b2e1c86
