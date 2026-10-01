---
phase: 58-cleanup
plan: 02
subsystem: docs
tags: [cleanup, docs, claude-md, requirements, in-combat]
requires: [58-01]
provides:
  - "CLAUDE.md: `stylua .` rule and the current Architecture file list"
  - "REQUIREMENTS.md: General/Advanced wording and dated superseded/revised notes"
  - "57.2 records and STATE.md agree with the 2026-09-29 decisions (In Combat kept, release wiring declined)"
affects: [58-04]
tech-stack:
  added: []
  patterns: ["dated in-place correction notes; history never deleted"]
key-files:
  created: []
  modified:
    - CLAUDE.md
    - .planning/REQUIREMENTS.md
    - .planning/phases/57.2-buff-reminders-category/57.2-04-SUMMARY.md
    - .planning/phases/57.2-buff-reminders-category/57.2-REVIEW.md
    - .planning/phases/57.2-buff-reminders-category/57.2-VERIFICATION.md
    - .planning/STATE.md
decisions:
  - "Architecture list gains a tools/TBTProbe/ line (optional per plan; its header says it is a never-shipped probe harness)"
  - "The ADD heading is reworded to General and Advanced; the DTRK heading keeps its backlog name"
metrics:
  duration: "~10 min"
  completed: 2026-09-29
---

# Phase 58 Plan 02: Docs corrections Summary

CLAUDE.md now gives the stylua command that works (`stylua .` from the repo root) and lists every file in the repo's current set. REQUIREMENTS.md describes the General/Advanced dialog and marks the text later decisions superseded. The 57.2 records and STATE.md no longer say a reminders container on "In Combat" can never show anything, and they record the release wiring as declined.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | b5609e4 | docs(58-02): CLAUDE.md stylua rule and current file list |
| 2 | 92e10e8 | docs(58-02): REQUIREMENTS wording, General/Advanced and superseded notes |
| 3 | 30b16cf | docs(58-02): correct stale In Combat notes and the declined release target |

## Gate results

| Gate | Before | After |
|------|--------|-------|
| T1 | FAIL: the stylua rule does not say stylua . from the repo root | ok |
| T2 | FAIL: ADD-07 does not name the General and Advanced tabs | ok (on the second run, see Deviations) |
| T3 | FAIL: 57.2-04 SUMMARY still says reminders never show in combat | ok |

Every touched file is `w/crlf`, with one CR per line and no CRCR. CHANGELOG.md and README.md are unchanged since be7ca11.

## What changed

- **CLAUDE.md stylua bullet:** the bullet now says "Run `stylua .` from the repo root" and records that a bare `stylua` exits with "error: no files provided". The clause "so the bare invocation (no flags) is now correct" is removed. The history sentence from "This rule previously read" onward is unchanged.
- **CLAUDE.md Architecture list:** new lines for Providers.lua, MergeMode.lua, Config.lua, TerribleBuffTracker.toc, scripts/install.ps1, scripts/aura-read-gate.js, scripts/migrate-dryrun.js and tools/TBTProbe/. Each description comes from the file's own header comment. The install.bat line now describes the wrapper and no longer mentions "both flavor TOCs". The other existing lines are unchanged.
- **REQUIREMENTS.md:**
  - ADD-07 says **General** and **Advanced**, with a `**Superseded 2026-09-29**` note for the visibility default and dropdown (removed by REM-04).
  - DTRK-01 describes General/Advanced settings, with a `**Superseded 2026-09-29**` note: there is no switch and no saved mode flag.
  - REM-02 gains a `_Revised 2026-09-29 (Phase 58)_` line covering "Also satisfied by" (RALT-01, v11) and the readable-expiry timer (57.2-05 review WR-05, confirmed against the review's fix outcome).
  - The ADD heading is reworded.
  - Requirement IDs, checkboxes and the traceability table are unchanged.
- **57.2 records:**
  - Both stale "Known behaviour" bullets in the 57.2-04 SUMMARY are rewritten with a "Corrected 2026-09-29" note.
  - 57.2 REVIEW IN-05 gains a correction line, and its Skipped bullet an appended note.
  - The IN-05 row in 57.2 VERIFICATION is corrected and stays one table line.
  - 57.2-05-SUMMARY and 57.2-HUMAN-UAT make no such claim, so they are unchanged.
  - No 57.2 PLAN.md was edited.
- **STATE.md:** both lines that mention "into release" now say "declined 2026-09-29 by user decision". The IN-05 line (~51) already said KEPT and is unchanged.

## Deviations from Plan

- **T2 first run failed on my own wrapping:** "**Superseded" and "2026-09-29**" landed on two lines, so the gate's line grep missed the note. Rewrapped so that `**Superseded 2026-09-29**` sits on one line. The gate was not changed.
- **Tooling:** the Edit tool was available, so all edits used it (the plan assumed a node split/join). CRLF was asserted afterwards on every file.
- **Scratch folder:** `scratchpad\p58\exec\` (orchestrator instruction), not `exec-58-02\`.

## Known Stubs

None.
