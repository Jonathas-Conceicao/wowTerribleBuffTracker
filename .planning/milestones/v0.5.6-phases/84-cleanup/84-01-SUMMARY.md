---
phase: 84-cleanup
plan: 01
subsystem: reminders, click overlays
tags: [cleanup, hot-path, review-items, release-tooling]
requires: [80, 81, 82, 83]
provides:
  - "useItems pairs carry a prebuilt \"item:<id>\" click attribute (field 3)"
  - "ReminderClick overlay spell cache field _spellAttr"
affects: [Providers.lua, ReminderClick.lua, BuffEngine.lua]
tech-stack:
  added: []
  patterns: ["load-time string prebuild instead of per-flush concatenation"]
key-files:
  created: [.planning/phases/84-cleanup/84-01-SUMMARY.md]
  modified: [Providers.lua, ReminderClick.lua, BuffEngine.lua]
decisions:
  - "The useItems cache loop sits inside the pre-milestone MetaReminderRow, but only touches the useItems option that Phase 81 added, so it is milestone-owned code and in cleanup scope"
metrics:
  completed: 2026-11-09
  tasks: 2
  files: 3
requirements: [CLEAN-01]
---

# Phase 84 Plan 01: Cleanup Summary

The milestone's three open review items are closed with no behaviour change. The familiar
click's `"item:<id>"` string is now built once at row load, not on every flush. The overlay
cache field is renamed `_spellAttr`. The 8-ID editor cap is recorded at `ns:IsEditableTracker`.
Every hot path has a verdict, all checks pass, and the build is deployed for Phase 85.

## Task 1: Review items (commit 35b18e1)

- **81 IN-01 (closed).** `MetaReminderRow` sets `useItems[i][3] = "item:" .. useItems[i][1]` once
  for each pair after the client gate. `PickUseItem` returns `useItems[i][3]` and builds no string.
  Its guards are unchanged: the `C_Item` check, `issecretvalue` on level and count, the `pcall`, and
  testing the level before the count. The familiar row's call text is byte-identical (the
  `git diff -U0 ... '^-MetaReminderRow(1302303'` count is 0), so `reminders-doc-check.js` still
  parses it. The header comments on `MetaReminderRow`, `ns:ReminderUseItems` and `PickUseItem` now
  describe field 3.
  - **Scope reasoning:** `MetaReminderRow` existed at `5c0001e`, so the function is pre-milestone.
    The `useItems` option did not exist there (`git show 5c0001e:Providers.lua | grep -c useItems`
    returns 0). Phase 81 added it, so a loop over it is milestone code and may be restructured.
    Everything else in the function is untouched apart from `def.useItems` now reading the local.
- **81 IN-03 (closed).** In `Place`, `overlay._castName` is renamed `overlay._spellAttr` at both of
  its uses. The signature, the order of the three on-change writes and every `SetAttribute` call
  are unchanged.
- **80 IN-04 (closed, comment only).** Four comment lines above `ns:IsEditableTracker` record that
  built-in blessings carry up to 18 alternatives while `ParseSpellIDList` caps the dialog at
  `MAX_CAST_RULE_IDS` (8). Nothing but comments changed in BuffEngine.lua.
- **Sweep of `git diff 5c0001e HEAD -- '*.lua'`** (BuffEngine 4, Core 8, Providers 180,
  ReminderClick 62 lines):
  - No unused locals or fields. `_actionType` is initialised in `CreateOverlay` and read in `Place`.
    `_itemAttr` and `_spellAttr` are compared and stored in `Place` only.
  - `ns.reminderItemClickActive` needs no initialiser: it is nil (falsy) until the first Flush.
  - No helper is written twice. `ns:ReminderUseItems` is the only reader of `def.useItems`.
  - The comments match the code, the refreshAuraMemo comment included.
  - The Forever group block is data only.
  - Verdict: nothing further to fix.

## Task 2: Hot-path verdicts

| Hot path | Verdict |
|----------|---------|
| Reminder aura refresh (`ns:RefreshAuraStates`) | The milestone added data only: more rows and longer "Also satisfied by" lists, read through the per-call `refreshAuraMemo` (wiped, not reallocated). No new code path, no allocation. Research §12.4's costs are noted, not optimised (locked): more spellbook scans after a spellbook change, and longer alternative rows |
| ReminderClick `Flush` | Per icon: one `ns:ReminderUseItems` map read and one boolean (`sawItemReminder`). It calls `PickUseItem` for the familiar row only. No allocation |
| `PickUseItem` | One `UnitLevel` call, then at most three `pcall(C_Item.GetItemCount, id)` calls (a function value plus args creates no closure). Returns the prebuilt string. No allocation (81 IN-01 closed) |
| `Place` | Three on-change compares and writes (`_actionType`, `_spellAttr`, `_itemAttr`) plus the existing `_unit` one. No allocation |
| Core `BAG_UPDATE_DELAYED` branch | One field read (`ns.reminderItemClickActive`). It marks dirty only while the familiar reminder shows (81 WR-01), and `MarkReminderClicksDirty` coalesces |
| Load-time row and group code | `MetaReminderRow` (including the new field-3 loop) and the `MetaReminderGroup` calls allocate at file load only. `ApplyMetaReminderDef`'s alternatives copy predates the milestone and runs per rebuild, not per event |

Reading the code contradicted none of these verdicts.

## Check outputs

- `stylua .`: exit 0, then `git status --short` was empty (stylua changed nothing). `stylua --check .` passes.
- `git ls-files --eol Providers.lua ReminderClick.lua BuffEngine.lua Core.lua`: all four are
  `i/lf w/crlf attr/text eol=crlf`, and none is `w/mixed`.
- `node scripts/aura-read-gate.js`: `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)`
- `node scripts/aura-read-gate.js --selftest`: `AURA-READ SELFTEST PASS (30 cases)`
- `node scripts/reminders-doc-check.js`: `CODE ROWS 39 (forever 28, retail 10, both 1), GROUPS 19`
  / `REMINDERS-DOC CHECK PASS (132 Forever IDs, 15 retail IDs, 39 rows)`
- `node scripts/reminders-doc-check.js --selftest`: `REMINDERS-DOC SELFTEST PASS (27 cases)`
- Task 1 gate: `TASK1_OK`. Task 2 gate: `TASK2_OK`.
- `./scripts/install.bat`: exit 0, `Deployed version: v0.5.5-49-g35b18e1-dev`. It installed to
  `_retail_`, `_ptr_`, `_beta_`, `_forever_` and `_classic_era_`, so both retail and Forever are covered.
- `git diff --quiet CHANGELOG.md`: untouched.

## Review item status

| Item | Status |
|------|--------|
| 80 IN-01, IN-02, IN-03 | Fixed in d62021a |
| 80 IN-04 | Closed here, as a comment (35b18e1) |
| 81 WR-01 | Fixed in c08500a (`ns.reminderItemClickActive`) |
| 81 IN-01 | Closed here (35b18e1) |
| 81 IN-02 | Accepted by 81-CONTEXT (no PLAYER_LEVEL_UP hook); left as is |
| 81 IN-03 | Closed here (35b18e1) |
| 82 IN-01..IN-04 | Fixed in 92b6309 / 0e0adfe |
| 82 IN-05 (Amplify/Dampen stacking) | A Phase 85 checklist item, not cleanup |

## Release tooling verdict

- `scripts/release.bat` still refuses any branch other than `main` unless `TBT_ALLOW_BRANCH=1`
  (REL-01). It tags HEAD and pushes `main` plus the tag.
- `.github/workflows/release.yml` triggers on any tag push. It extracts the first `## ` section of
  CHANGELOG.md into RELEASE_NOTES.md and runs `BigWigsMods/packager@v2`.
- `.pkgmeta` ignores `CHANGELOG.md`, `CLAUDE.md`, `scripts`, `docs`, `tools`, `.planning`,
  `.github`, `Media/Source` and `*.png`, so docs/, scripts/ and .planning/ stay out of the package
  (T-84-03).
- The phase gate scripts under `.planning` (80-check-groups.js, 81-check.js, 82-check-rows.js) are
  never shipped and stay as history. Task 1 supersedes 81-check.js's `_castName` and `"item:"`
  assertions, so it was not re-run.

## Deviations from Plan

- The plan's Task 2 `<automated>` gate is split across the file: its command is cut off after
  `grep -q '^  - .planning` and continues after the `</output>` block. I ran the reassembled
  command, and it printed TASK2_OK. The plan file is not edited.

Otherwise the plan ran exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- Providers.lua, ReminderClick.lua and BuffEngine.lua are modified in 35b18e1 (found in git log).
- .planning/phases/84-cleanup/84-01-SUMMARY.md exists.
