---
phase: 54-edit-trackers
plan: 02
subsystem: ui
tags: [wow-addon, lua, cdm-tab, add-dialog, field-definition, tracker-edit]

# Dependency graph
requires:
  - phase: 54-edit-trackers (plan 01)
    provides: "ns:UpdateTrackedBuff, ns:FindTrackerConflict, ns:ClearTrackerRuntimeState, ns:IsEditableTracker, ns:TrackerKindWord, ns:SpellLabel, and the opts.fields/fields+fieldKeys ENGINE_OWNED contract on ns:AddTrackedBuff"
provides:
  - "FormatDuration(seconds) -- the inverse of ParseDuration, used by edit-mode prefill; never produces exponent notation, always parses back through ParseDuration"
  - "TRACKER_FIELDS -- one ordered array literal (spellID, duration, coverAllRanks) carrying build/reset/prefill/read/validate per field, with the full field-definition contract documented above it for every later phase to build against"
  - "CreateAddDialog rebuilt field-agnostic: dialog.ctx, dialog.GetFieldState, dialog.fieldEntryKeys, dialog.RefreshState, dialog.OpenForAdd -- names no individual field anywhere in its body"
  - "dialog.OpenForAdd replaces ResetFields + Show + spellIdBox:SetFocus as the single entry point that opens the dialog in add mode"
affects: [54-03, 54-04, 55, 56, 57]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Field-definition-driven dialog: TRACKER_FIELDS is the single source of truth for what the Add/Edit dialog builds, resets, prefills, validates, reads and persists -- a new field is one table entry, and the dialog code itself never names a field"
    - "Build-time available() vs runtime visible(): available is evaluated once when the dialog frame is constructed (no row, no space, ever, when false -- used for Cover all ranks / ns.CLIENT_HAS_SPELL_RANKS); visible is evaluated on every RefreshState pass and drives a dirty-checked re-Layout so a field can show/hide while the dialog is open without a full rebuild"
    - "Shared ValidateAll() walk used by both live RefreshState (enables/disables confirm) and the confirm click handler (re-validates before committing) -- one walk, not two copies"

key-files:
  created: []
  modified:
    - "CDMTab.lua - FormatDuration, the field-definition contract comment, TRACKER_FIELDS (spellID/duration/coverAllRanks field defs) inserted between ParseDuration and CreateAddDialog; CreateAddDialog rewritten around ctx/fieldStates/fieldById/fieldEntryKeys/focusRing/values, dialog.GetFieldState, local Layout()/ValidateAll()/RefreshState, dialog.OpenForAdd; ns:BuildAllSections addSquare handler and ns:DismissTBTDialogs' header comment updated to call/describe OpenForAdd instead of ResetFields"

key-decisions:
  - "FormatDuration's own comment states the length rule (SetMaxLetters(6) worst cases) and why prefill raises the box's max letters for a long saved value instead of comparing numbers in read -- exactly as specified, no alternate design considered"
  - "Refactored the confirm-click re-validation into a shared local ValidateAll() rather than duplicating RefreshState's visible-field validate walk inline in the OnClick handler, since the plan's own wording ('same visible-field walk as RefreshState') is satisfied more directly by one function than by two copies of the same loop"
  - "ctx.mode == 'edit' is left as a comment-only branch point inside the confirm handler (no stub code), per the plan's explicit instruction; OpenForEdit does not exist yet so ctx.mode can only ever be 'add' until 54-03"

requirements-completed: [EDIT-03, EDIT-04]

# Metrics
duration: ~7min
completed: 2026-09-28
---

# Phase 54 Plan 02: Edit Trackers - Shared Field Definition and Field-Agnostic Add Dialog Summary

**CDMTab.lua's Add dialog is rebuilt around one ordered field definition, TRACKER_FIELDS, so `CreateAddDialog` builds, resets, validates, reads and commits every field by walking the array and names no individual field anywhere in its body -- and a same-slot duplicate spell ID is now refused in the dialog's error label instead of silently overwriting the existing tracker.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-09-28T09:31:00-03:00 (previous plan-doc commit)
- **Completed:** 2026-09-28T09:38:03-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 1

## Accomplishments
- `FormatDuration(seconds)` is the inverse of `ParseDuration`, producing at most 6 characters for every value the duration box itself can create and never exponent notation; every result parses back through `ParseDuration`.
- The field-definition contract (EDIT-03) is written as a comment block directly above `TRACKER_FIELDS`, stating `id`/`entryKey`/`available`/`visible`/`build`/`reset`/`prefill`/`update`/`read`/`validate`, the `ctx` shape, the Layout paragraph and the declaration-order hazard -- so 54-03 (edit mode) and every later phase (live preview, suggested cooldown, secrecy badge, detailed tracking) can add a field as one table entry with no dialog-code edit.
- `TRACKER_FIELDS` holds the three fields the Add dialog already had -- `spellID`, `duration`, `coverAllRanks` -- each carrying its widgets, add-mode reset, edit-mode prefill (ready for 54-03), read and validate. The `spellID` field's `validate` calls `ns:FindTrackerConflict(ctx.kind, spellID, ctx.editingKey)` live on every keystroke and returns `"Already tracked as a buff"` / `"Already tracked as a cooldown"` on collision (EDIT-04, 54-CONTEXT "Duplicate rejection").
- `CreateAddDialog` is rewritten around `ctx`, `fieldStates`/`fieldById`/`fieldEntryKeys`/`focusRing`/`values`, `dialog.GetFieldState` (declared before the build loop so a field can anchor to an earlier sibling), a `Layout()` walker that anchors only the shown rows and always places the error label after the last visible one (fixing retail's label-over-Duration-box overlap), a shared `ValidateAll()` walk, and `RefreshState(forceLayout)` which updates live-derived fields, dirty-checks visibility changes before re-`Layout`-ing, then re-validates and enables/disables the confirm button.
- `dialog.OpenForAdd()` replaces `ResetFields` + `Show` + `spellIdBox:SetFocus`: it reads the active tab once, sets the title and confirm-button text, resets every field, forces a layout (`RefreshState(true)`), shows the dialog and focuses the first shown field in the Tab/Enter ring. The confirm click handler re-validates, builds `values` from every visible field's `read`, and for `ctx.mode == "add"` calls `ns:AddTrackedBuff(values.spellID, values.duration, nil, { trackerType = ctx.kind, section = "hidden", fields = values })` -- a refusal (same-slot duplicate) shows the reason in the error label and leaves the dialog open with the existing tracker untouched.
- `ns:BuildAllSections`'s addSquare `OnMouseUp` now calls `ns.tbtAddDialog.OpenForAdd()`; `ns:DismissTBTDialogs`'s header comment no longer mentions `ResetFields`.

## Task Commits

Each task was committed atomically:

1. **Task 1: FormatDuration and the TRACKER_FIELDS shared field definition** - `2c41740` (feat)
2. **Task 2: CreateAddDialog becomes field-agnostic (ctx, RefreshState, OpenForAdd)** - `92182de` (feat)

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified
- `CDMTab.lua` - `FormatDuration`, the field-definition contract comment, `TRACKER_FIELDS` (three field defs); `CreateAddDialog` rewritten field-agnostic (`ctx`, `GetFieldState`, `Layout`, `ValidateAll`, `RefreshState`, `OpenForAdd`); addSquare handler and `ns:DismissTBTDialogs` comment updated

## Decisions Made
- Length-rule and truncation-avoidance design for `FormatDuration`/duration prefill implemented exactly as specified (raise `SetMaxLetters` on prefill rather than comparing numbers in `read`).
- Shared `ValidateAll()` used by both the live `RefreshState` pass and the confirm click handler, rather than two copies of the same visible-field validate walk -- satisfies the plan's "same visible-field walk as RefreshState" instruction directly.
- `ctx.mode == "edit"` left as a comment-only branch point in the confirm handler; no stub code, since `OpenForEdit` does not exist until 54-03 and `ctx.mode` can currently only ever be `"add"`.

## Deviations from Plan

None - plan executed exactly as written, including every checker advisory in this plan's `<project_hazards>`: the four contract phrases each appear exactly once, each on a single (unwrapped) line, above `TRACKER_FIELDS`; the title comment inside `CreateAddDialog` was reworded from `dialog.ResetFields` to `dialog.OpenForAdd` even though Task 2's action text didn't list it, per advisory (b); `y - 32` appears exactly twice inside `TRACKER_FIELDS` with no comment containing that string; `FormatDuration` / `TRACKER_FIELDS` / `CreateAddDialog` declaration order was preserved.

## Issues Encountered

None. `stylua --check CDMTab.lua` passed after the bare `stylua CDMTab.lua` run on both tasks; every automated verify gate and every acceptance-criteria grep in the plan passed on first run; `git ls-files --eol CDMTab.lua` reports `w/crlf` and the CRCRLF node check reports clean after each task.

## Verification Results (plan `<verification>` block)

- Every `CreateAddDialog` gate in Task 1 and Task 2's `<verify>` blocks passes (all commands run and confirmed above; see Task Commits).
- `stylua --check CDMTab.lua` exits 0.
- CRLF preserved end to end: `git ls-files --eol CDMTab.lua` = `w/crlf`; the `\r\r\n` node check found nothing after either commit.
- `git status --porcelain -- '*.lua' '*.xml' '*.toc'` lists only `CDMTab.lua` (the pre-existing ` M .gitignore` working-tree edit was never staged or touched).
- In-game checks (empty fields disable Add, malformed duration shows the hint, Tab/Enter behaviour, Cover all ranks default/absence, retail's error label no longer overlapping Duration, live duplicate rejection) are human verification, deferred to 54-04 per this plan's own note -- no WoW client is available in this environment.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`TRACKER_FIELDS`, its full contract comment, `dialog.GetFieldState`, `dialog.ctx`, `dialog.fieldEntryKeys` and `dialog.RefreshState` are all in place exactly as this plan's `<interfaces>`/`<must_haves>` specify, ready for 54-03 to add `ctx.mode = "edit"`, `OpenForEdit` (prefilling from a saved entry via each field's `prefill`), and the "Save" confirm branch calling `ns:UpdateTrackedBuff` -- with zero edits to `TRACKER_FIELDS` or the walker. Nothing is deployed to a WoW client yet; 54-04 wires the Edit context-menu entry and deploys. No blockers. In-game behaviour is human verification, deferred to 54-04.

## Self-Check: PASSED

- FOUND: CDMTab.lua
- FOUND: .planning/phases/54-edit-trackers/54-02-SUMMARY.md
- FOUND commit: 2c41740 (Task 1)
- FOUND commit: 92182de (Task 2)

---
*Phase: 54-edit-trackers*
*Completed: 2026-09-28*
