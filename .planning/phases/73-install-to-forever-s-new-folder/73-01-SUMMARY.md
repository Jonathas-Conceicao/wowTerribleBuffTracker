---
phase: 73-install-to-forever-s-new-folder
plan: 01
subsystem: tooling
tags: [install, forever, docs]
requires: []
provides:
  - "install.ps1 deploys to World of Warcraft\\_forever_"
affects: [scripts/install.ps1, CLAUDE.md]
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - scripts/install.ps1
    - CLAUDE.md
decisions:
  - "_classic_beta_ dropped from the deploy list; nothing already deployed there was deleted"
  - "README.md not touched: it names no install folder"
requirements: [INST-11]
metrics:
  duration: ~5 min
  completed: 2026-10-22
  tasks: 2
  files: 2
---

# Phase 73 Plan 01: Install to Forever's New Folder Summary

`scripts/install.ps1` now deploys to `_forever_` (product `wowf`) in place of `_classic_beta_`, and CLAUDE.md's "One TOC, all flavours" bullet names `_forever_`, `wowf`, build 1.60.1.70532, interface 16001.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace `_classic_beta_` with `_forever_` in `$flavors` | 14b8736 | scripts/install.ps1 |
| 2 | Rewrite CLAUDE.md "One TOC, all flavours" parenthetical | 2711028 | CLAUDE.md |

## Verification

- Task 1 gate: PASS. A fixture root holding `_forever_`, `_retail_`, `_classic_beta_` got a TOC with the dev version substituted in `_forever_` and `_retail_`, and nothing under `_classic_beta_`. The repo TOC still holds `@project-version@`.
- Real `./scripts/install.bat` run: "Installed to" for `_retail_`, `_ptr_`, `_beta_`, `_forever_`, `_classic_era_`; no `_classic_beta_` line.
- Task 2 gate: PASS. TOC, README and CHANGELOG are unchanged.
- `git ls-files --eol`: both files `w/crlf`. Each diff is 1 insertion and 1 deletion.
- `stylua .`: no diff.

## Deviations from Plan

None. The plan ran exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- scripts/install.ps1, CLAUDE.md modified; commits 14b8736 and 2711028 present in `git log`.
