---
phase: 83-reminder-review-doc
plan: 01
subsystem: docs
tags: [forever, retail, metaReminder, review-doc, check-script]
requires:
  - phase: 82 (final reminder table for v0.5.6, HEAD c86be51)
provides:
  - docs/REMINDERS.md, the human-review list of every built-in reminder (DOC-06)
  - scripts/reminders-doc-check.js with --selftest, the doc-to-code ID check (DOC-07)
affects: [Phase 84 cleanup re-runs the check]
tech-stack:
  added: []
  patterns: [plain-Node check script with embedded --selftest fixtures, same style as aura-read-gate.js]
key-files:
  created: [scripts/reminders-doc-check.js, docs/REMINDERS.md]
  modified: [Providers.lua (comment only), .pkgmeta, CLAUDE.md]
key-decisions:
  - "The check also requires each row's table line to have the right class, Spell link, Duration and Verified cells, not only matching IDs"
  - "Large Forever groups (Amplify/Dampen, Blessings, Paladin auras) are listed once, on a line under the class table, instead of in every row cell"
  - "Not included has no Wowhead links, so it can never trip the row-ID rule"
requirements-completed: [DOC-06, DOC-07]
metrics:
  duration: ~25 min
  completed: 2026-11-09
  tasks: 3
  files: 5
---

# Phase 83 Plan 01: Reminder Review Doc Summary

`docs/REMINDERS.md` lists all 39 built-in reminder rows: 28 Forever-only, 10 retail-only and 1
on both clients. Each row has its linked alternatives, duration and comment-derived verified
status, and a Not included table follows. `scripts/reminders-doc-check.js` proves the doc and
`Providers.lua` agree ID for ID, per client and overall: 132 Forever IDs, 15 retail IDs, zero
mismatches.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Doc-to-code check with --selftest (DOC-07) | 06f984c | scripts/reminders-doc-check.js |
| 2 | Built-in reminders review list (DOC-06) | 0455dc0 | docs/REMINDERS.md |
| 3 | Pointer comment, .pkgmeta, CLAUDE.md | 87a1bd5 | Providers.lua, .pkgmeta, CLAUDE.md |

## Check output

```
$ node scripts/reminders-doc-check.js
CODE ROWS 39 (forever 28, retail 10, both 1), GROUPS 19
REMINDERS-DOC CHECK PASS (132 Forever IDs, 15 retail IDs, 39 rows)

$ node scripts/reminders-doc-check.js --selftest | tail -1
REMINDERS-DOC SELFTEST PASS (27 cases)
```

`node scripts/aura-read-gate.js` passes, `stylua --check .` is clean, and `./scripts/install.bat`
deployed `v0.5.5-41-g87a1bd5-dev` to every client folder.

## TDD

Task 1 was written test-first. The 27 selftest cases ran against stub parsers and 25 failed (RED).
The two that passed only assert "zero problems", which is what a stub returns. With the
implementation in place, 26 passed on the first run. The last failure was a message-format
mismatch ("group 55555 (line 16) names no row"), fixed by moving the line number to the end of the
message. 27/27 then passed (GREEN). The plan asked for a single `feat` commit for the task, so
there is no separate `test` commit.

## What the check covers

- Code side: comments are stripped, but the lexer keeps strings intact, so the retired-blessings
  note and a commented-out row are never collected. Only the first number of each useItems pair is
  collected (minimum levels 25/16/5 are not). The Forever block is found by keyword depth. The two
  `local function` definitions are skipped.
- Doc side: links are collected per `## Forever` / `## Retail` section, and the path is checked
  for its client (`/forever/` versus retail). Any other Wowhead path (classic and the like) fails.
  A link in the intro fails, and so does a Not included link to a row ID. The three required
  headings must exist, with Not included last.
- Per row: a table line in each section of its client, under its `### <Class>`, with its own ID
  linked in the Spell cell, Duration `<n> min` or `permanent`, and Verified equal to the row
  comment.

## Deviations from Plan

Additions beyond the plan's rule list, each with a selftest case:
- The check fails if `## Not included` is not the last `## ` section. The acceptance criteria said
  "(last)", so this enforces it.
- A Wowhead link in an unknown `## ` section fails. Without this, the link would be neither
  checked nor collected.

Otherwise the plan was executed as written. No script bug turned up while writing the doc: the
check passed on its first run.

## Verification gates

- Task 1, 2 and 3 automated verify commands: all printed PASS.
- `git ls-files --eol`: CLAUDE.md `i/lf w/crlf`, Providers.lua `i/lf w/crlf`, .pkgmeta `i/lf w/lf`.
  All three are unchanged from before the plan.
- The Providers.lua diff adds four `--` lines and removes nothing. The CLAUDE.md diff adds exactly
  two list lines. CHANGELOG.md is untouched.
- The doc has no Salvation, Revoker or Blessing of Light, no 1038/19979/25895/25890, and no
  Classic link.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: scripts/reminders-doc-check.js, docs/REMINDERS.md
- FOUND commits: 06f984c, 0455dc0, 87a1bd5
