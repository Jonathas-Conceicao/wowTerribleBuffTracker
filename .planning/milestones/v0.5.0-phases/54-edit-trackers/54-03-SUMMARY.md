---
phase: 54-edit-trackers
plan: 03
subsystem: ui
tags: [wow-addon, lua, cdm-tab, add-dialog, edit-dialog, context-menu, tracker-edit]

# Dependency graph
requires:
  - phase: 54-edit-trackers (plan 01)
    provides: "ns:UpdateTrackedBuff, ns:IsEditableTracker, ns:FindTrackerConflict, ns:ClearTrackerRuntimeState (BuffEngine.lua)"
  - phase: 54-edit-trackers (plan 02)
    provides: "TRACKER_FIELDS field-definition contract, CreateAddDialog rebuilt field-agnostic (ctx, GetFieldState, fieldEntryKeys, RefreshState, OpenForAdd), each field's prefill(state, entry, ctx) already written for edit mode"
provides:
  - "dialog.OpenForEdit(key) -- opens the shared Add/Edit dialog in edit mode, re-checking ns:IsEditableTracker, reading kind off the saved entry, resetting then prefilling every field, titling itself Edit Buff Tracker / Edit Cooldown Tracker with a Save button"
  - "confirm handler's ctx.mode == \"edit\" branch -- commits through ns:UpdateTrackedBuff(ctx.editingKey, values.spellID, values.duration, values, dialog.fieldEntryKeys), showing an engine refusal in the error label and leaving the tracker unchanged"
  - "dialog OnHide wipes ctx on every close (Cancel, Escape, ns:DismissTBTDialogs, or a successful commit), so no stale editingKey survives to the next open"
  - "An \"Edit\" entry in a userBuff/userCd tile's right-click menu, just above the Remove divider, gated on ns:IsEditableTracker(entry); no built-in tile (Lust, trinket, pot, racial buff, racial cooldown/metaSkillCd, bag item) gets one"
affects: [54-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One dialog, two modes: OpenForAdd and OpenForEdit are the same ns.tbtAddDialog singleton, distinguished only by ctx.mode -- neither the confirm handler nor either Open function names an individual TRACKER_FIELDS field, so 55/56/57's new fields need no edit to either path"
    - "Re-check at the boundary: ns:IsEditableTracker gates both the context-menu button (build time) and OpenForEdit itself (open time), so a tracker removed between the right-click and the click on Edit cannot open the dialog -- mirrors ns:UpdateTrackedBuff's own re-check in BuffEngine.lua"
    - "Pooled-tile key capture: CreateIconFrame's OnMouseUp reads self.spellID into a local trackerKey once, at menu-build time, so a later click on a menu button always acts on the tile the menu was opened for, not whatever the pooled frame holds by then"

key-files:
  created: []
  modified:
    - "CDMTab.lua - dialog.OpenForEdit added to CreateAddDialog; confirm handler gains an elseif ctx.mode == \"edit\" branch; dialog:SetScript(\"OnHide\", ...) wipes ctx; ns:DismissTBTDialogs header comment notes the add/edit dialog is one frame; CreateIconFrame's OnMouseUp non-Suggested menu builder captures trackerKey/entry and adds a CreateButton(\"Edit\", ...) gated on ns:IsEditableTracker(entry) directly above the file's one CreateDivider()"

key-decisions:
  - "OpenForEdit's field loop destructures local def, state = field.def, field.state before calling def.reset/def.prefill, matching the idiom already used by ValidateAll/RefreshState elsewhere in CreateAddDialog, rather than calling field.def.prefill(field.state, ...) directly -- same behaviour, consistent style"
  - "focusRing's loop variable in OpenForEdit is named ringEntry rather than entry (which OpenForAdd uses), because OpenForEdit already binds entry to the tracked-buff record being edited; avoids a shadowing local with a different meaning in the same function"

requirements-completed: [EDIT-01, EDIT-02, EDIT-03, EDIT-04]

# Metrics
duration: ~3min
completed: 2026-09-28
---

# Phase 54 Plan 03: Edit Trackers - Dialog Edit Mode and Context-Menu Entry Point Summary

**CDMTab.lua's shared Add/Edit dialog gains `dialog.OpenForEdit`, a Save-mode confirm branch that commits through `ns:UpdateTrackedBuff`, and an OnHide that wipes edit context on every close, reached by a new "Edit" entry above Remove on every `userBuff`/`userCd` tile's right-click menu.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-09-28T09:39:15-03:00 (previous plan-doc commit)
- **Completed:** 2026-09-28T09:42:30-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 1

## Accomplishments
- `dialog.OpenForEdit(key)` re-checks `ns:IsEditableTracker(entry)` (returning without showing for a built-in or vanished tracker), reads `ctx.kind` off the saved entry's own `trackerType` (never the active tab or key shape), titles itself "Edit Cooldown Tracker" or "Edit Buff Tracker", sets the confirm button to "Save", resets then prefills every `TRACKER_FIELDS` field from the entry through each field's own `reset`/`prefill`, forces a layout (`RefreshState(true)`), shows the dialog, and focuses the first shown field -- naming no individual field anywhere in its body.
- The confirm click handler's `elseif ctx.mode == "edit"` branch calls `ns:UpdateTrackedBuff(ctx.editingKey, values.spellID, values.duration, values, dialog.fieldEntryKeys)`; a refusal (same-slot duplicate, or the tracker having vanished under the open dialog) shows the engine's reason in the error label and leaves the dialog open with the tracker unchanged, exactly mirroring the add branch's shape; success calls the same `ns:RefreshTBTSections()` / `ns:StartAllPreviewTimers()` / `dialog:Hide()` as add.
- `dialog:SetScript("OnHide", function() wipe(ctx) end)` clears edit context on every close path -- Cancel, Escape (`UISpecialFrames`), `ns:DismissTBTDialogs` (tab switch, CDM close), or a successful commit -- so no stale `editingKey` can reach the next open. `ns:DismissTBTDialogs`'s header comment now states the add and edit dialog are the same `ns.tbtAddDialog` frame, so its one `Hide()` dismisses both modes, and that cancelling in edit mode commits nothing.
- `CreateIconFrame`'s `OnMouseUp` non-Suggested context-menu builder now captures `local trackerKey = self.spellID` and `local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[trackerKey]` once at menu-build time (tiles are pooled, so a later click must act on the key the menu was opened for), and adds `rootDescription:CreateButton("Edit", function() ns.tbtAddDialog.OpenForEdit(trackerKey) end)` directly above the file's one `CreateDivider()`, gated on `ns:IsEditableTracker(entry)`. Reached through the `ns.tbtAddDialog` field rather than a file-local, since `CreateIconFrame` is declared above `CreateAddDialog` in the file (a file-local would be `nil` at this point). The Suggested menu, "Move to", "Hide" and "Remove" buttons are untouched.

## Task Commits

Each task was committed atomically:

1. **Task 1: Edit mode in the shared dialog (OpenForEdit, Save branch, OnHide)** - `d98f20e` (feat)
2. **Task 2: "Edit" entry in the tracked tile's context menu** - `9064840` (feat)

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified
- `CDMTab.lua` - `dialog.OpenForEdit`; confirm handler's `ctx.mode == "edit"` branch; dialog `OnHide` (`wipe(ctx)`); `ns:DismissTBTDialogs` header comment; `CreateIconFrame`'s `OnMouseUp` `trackerKey`/`entry` capture and `CreateButton("Edit", ...)`

## Decisions Made
- `OpenForEdit`'s prefill loop uses the same `local def, state = field.def, field.state` destructuring idiom as `ValidateAll`/`RefreshState` rather than calling through `field.def.prefill(field.state, ...)` directly -- consistent style, identical behaviour.
- `OpenForEdit`'s focus-ring loop variable is named `ringEntry` (not `entry`, which `OpenForAdd` uses) because `OpenForEdit` already binds `entry` to the tracked-buff record being edited -- avoids a same-function shadow with a different meaning.

## Deviations from Plan

None - plan executed exactly as written. Every acceptance-criteria grep in both tasks (including the `awk`-scoped `CreateAddDialog`-body checks and the `OnMouseUp`-scoped `ns:IsEditableTracker(entry)` count) passed on first run; `stylua --check CDMTab.lua` was clean after both bare `stylua CDMTab.lua` runs; no exact-string Edit-tool mismatch occurred, so the plan's node-script CRLF-preserving fallback was never needed.

## Issues Encountered

None.

## Verification Results (plan `<verification>` block)

- All Task 1 and Task 2 `<verify>` gates pass (`stylua --check CDMTab.lua` exits 0; every `awk`/`grep` count matches the plan's expected values; CRCRLF node check clean; `git ls-files --eol CDMTab.lua` = `w/crlf`; `git diff --numstat CDMTab.lua` shows numbers after each task).
- `git status --porcelain -- '*.lua' '*.xml' '*.toc'` lists only `CDMTab.lua` after both commits -- the pre-existing ` M .gitignore` working-tree edit was never staged or touched.
- No `InCombatLockdown` guard was added (`grep -c "InCombatLockdown" CDMTab.lua` = `0`), matching 54-CONTEXT's "Combat" decision.
- In-game checks (right-click Edit on each tile kind, prefilled values, Save through the engine, duplicate rejection message, ID-change move keeping container/position, Escape/tab-switch/CDM-close dismissal) are human verification -- no WoW client is available in this environment, deferred to 54-04 per this plan's own `<verification>` note.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`dialog.OpenForEdit`, the confirm handler's edit branch, `OnHide`'s `wipe(ctx)`, and the context-menu "Edit" entry are all in place exactly as this plan's `<must_haves>`/`<interfaces>` specify. Nothing is deployed to a WoW client yet -- 54-04 deploys and runs the human-verification checklist for EDIT-01 through EDIT-04's full UI behaviour, including 54-01's noted "Known inconsistency" (an edited `userCd` tracker keeps kind `userCd` even for a racial spell ID, while `ns:AddTrackedBuff` still mints `metaSkillCd` for the same spell added fresh) for the user to decide. No blockers.

## Self-Check: PASSED

- FOUND: CDMTab.lua
- FOUND: .planning/phases/54-edit-trackers/54-03-SUMMARY.md
- FOUND commit: d98f20e (Task 1)
- FOUND commit: 9064840 (Task 2)

---
*Phase: 54-edit-trackers*
*Completed: 2026-09-28*
