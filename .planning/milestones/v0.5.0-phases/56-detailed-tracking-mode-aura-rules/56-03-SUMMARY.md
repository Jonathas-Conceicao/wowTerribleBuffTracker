---
phase: 56-detailed-tracking-mode-aura-rules
plan: 03
subsystem: ui
tags: [wow-addon, cdm, lua, dialog, tracker-fields]

# Dependency graph
requires:
  - phase: 56-detailed-tracking-mode-aura-rules
    plan: 01
    provides: "ns:DetailedAuraID(entry) / ns:CancelsOnAuraLoss(entry) runtime gates, gated on entry.detailed, that read the entry keys this plan's dialog fields save"
  - phase: 56-detailed-tracking-mode-aura-rules
    plan: 02
    provides: "ns:RefreshIDPreview(state, id) and ns:BuildSecrecyBadge(parent, state) shared helpers, reused as-is by the new aura ID row"
provides:
  - "ns:DetailedModeOffered(ctx) / ns:DetailedChildShown(detailedState, ctx) helpers above TRACKER_FIELDS"
  - "detailed, auraID, keepOnAuraLoss TRACKER_FIELDS entries (in that order) after coverAllRanks"
  - "entry.detailed / entry.auraID / entry.keepOnAuraLoss saved-entry keys, exactly what Plan 01's runtime reads"
affects: [57-detailed-tracking-visibility-cross-spell-rules]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A child field under a master checkbox captures dialog.GetFieldState(\"detailed\") at BUILD time (visible receives no dialog) and shows through ns:DetailedChildShown, which itself calls ns:DetailedModeOffered so a per-kind restriction (keepOnAuraLoss's ns.KIND.USER_BUFF check) composes on top rather than duplicating the master-checkbox read"
    - "A field's own preview/badge widgets (auraID) reuse Plan 02's ns:RefreshIDPreview/ns:BuildSecrecyBadge exactly as a TRACKER_FIELDS entry-level display field would, just driven from that field's own update() instead of a separate visible() hook, since the badge is a child widget of the row rather than its own array entry"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "keepOnAuraLoss adds its own ctx.kind == ns.KIND.USER_BUFF check on top of ns:DetailedChildShown, since aura-loss cancellation never applies to cooldowns, while auraID's visibility depends only on ns:DetailedChildShown so Phase 57's cooldown aura-ID-for-visibility can reuse the field unchanged once ns:DetailedModeOffered is widened"
  - "auraID's badge is shown/hidden by SetShown inside its own update() (compare-before-write keyed on id+generation, same pattern as secrecyBadge), not by a separate visible() hook, because the badge is a child widget positioned relative to the row's hover frame rather than an independent TRACKER_FIELDS array entry"

patterns-established:
  - "ns:DetailedModeOffered/ns:DetailedChildShown as the single pair of gates every Phase 57 detailed-mode child field (visibility selector, cross-spell triggers, cooldown aura-ID) will reuse without re-deriving the master-checkbox read"

requirements-completed: [DTRK-01, DTRK-02, DTRK-04]

# Metrics
duration: 5min
completed: 2026-09-28
---

# Phase 56 Plan 03: Detailed-Mode Dialog Fields Summary

**Added the "Detailed tracking" master checkbox, an aura ID row with its own live preview and secrecy badge (default = same as spell), and a default-ON "End when the aura is lost" opt-out to the Buffs-tab Add/Edit dialog, saved as `entry.detailed` / `entry.auraID` / `entry.keepOnAuraLoss` -- exactly the keys Plan 01's runtime already gates on.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-09-28T12:48:00-03:00 (approx, first commit 12:50:23-03:00)
- **Completed:** 2026-09-28T12:51:58-03:00
- **Tasks:** 2 completed
- **Files modified:** 1 (CDMTab.lua)

## Accomplishments
- `ns:DetailedModeOffered(ctx)` (Buffs tab only, `ctx.kind == ns.KIND.USER_BUFF`) and `ns:DetailedChildShown(detailedState, ctx)` (composes the above with the master checkbox's own `GetChecked()`) added above `TRACKER_FIELDS`, between Plan 02's helpers and the field-definition contract comment.
- `detailed` TRACKER_FIELDS entry: inline `UICheckButtonTemplate` copy of `coverAllRanks`' pattern, unchecked by default, `entryKey = "detailed"`, visible only via `ns:DetailedModeOffered(ctx)` so the Cooldowns tab never shows it this phase.
- `auraID` TRACKER_FIELDS entry, inserted between `detailed` and `keepOnAuraLoss`: a 10-digit numeric box labelled "Aura ID (blank = same as spell):", its own 18px icon + name preview and secrecy badge reusing `ns:RefreshIDPreview`/`ns:BuildSecrecyBadge` from Plan 02, driven by the AURA ID's own `ns:SpellAuraSecrecy`/`ns:SecrecyWarns` (independent of the portrait's badge). A blank box previews the spell ID's own aura (`state.spell.editBox:GetNumber()` fallback). `read` stores nothing when blank or equal to the typed spell ID, per D-02.
- `keepOnAuraLoss` TRACKER_FIELDS entry: checked (cancellation ON) by default, indented under Detailed, `entryKey = "keepOnAuraLoss"`, saved as `true` only when unchecked so a missing key always means cancellation stays on; visible via `ns:DetailedChildShown(state.detailed, ctx) and ctx.kind == ns.KIND.USER_BUFF` since a cooldown has no aura behind it.
- "Detailed mode (Phase 56)" paragraph added to the contract comment above `TRACKER_FIELDS`, containing the required literal sentence "The runtime gates on entry.detailed, never on whether a child key exists," and the hazard paragraph's declared-above helper list now also names `ns:DetailedModeOffered` / `ns:DetailedChildShown`.
- `CreateAddDialog` untouched: hash gate `64e38633612791cb7e1ea41902b75ae45c18167b` verified unchanged after both tasks.

## Task Commits

Each task was committed atomically:

1. **Task 1: Detailed-mode helpers, the Detailed checkbox and the "End when the aura is lost" opt-out** - `eb372fd` (feat)
2. **Task 2: Aura ID field with its own preview and secret badge; detailed-mode contract paragraph** - `fcbbbda` (feat)

_Plan metadata commit intentionally NOT made by this executor -- the orchestrator owns STATE.md/ROADMAP.md per its instructions._

## Files Created/Modified
- `CDMTab.lua` - `ns:DetailedModeOffered`/`ns:DetailedChildShown` helpers; `detailed`, `auraID`, `keepOnAuraLoss` TRACKER_FIELDS entries after `coverAllRanks`; "Detailed mode (Phase 56)" contract paragraph; hazard paragraph's declared-above list extended

## Verification / Acceptance Criteria

All items below were run against the tree after both tasks; every automated verify gate in 56-03-PLAN.md passed on the first attempt for both tasks (no auto-fixes needed).

- [x] `ns:DetailedModeOffered(ctx)` and `ns:DetailedChildShown(detailedState, ctx)` declared once each above `TRACKER_FIELDS`
- [x] `TRACKER_FIELDS` has `id = "detailed"`, `id = "auraID"`, `id = "keepOnAuraLoss"` once each, ordered `coverAllRanks < detailed < auraID < keepOnAuraLoss`
- [x] `detailed`: `entryKey = "detailed"`, label "Detailed tracking", unchecked on reset, prefilled from `entry.detailed == true`, visible via `ns:DetailedModeOffered(ctx)`
- [x] `auraID`: captures `detailed` and `spellID` states at build, "blank = same as spell" label, numeric 10-letter box, reuses `ns:RefreshIDPreview`/`ns:BuildSecrecyBadge(row, state)`, drives its badge from `ns:SpellAuraSecrecy`/`ns:SecrecyWarns`, visible via `ns:DetailedChildShown(state.detailed, ctx)`, no `USER_BUFF` anywhere in the entry, validates the 2147483647 bound, prefills from `entry.auraID`
- [x] `local state = {` precedes both the `auraID` row's `OnEnter` `SetScript` and its `ns:BuildSecrecyBadge` call
- [x] `keepOnAuraLoss`: `entryKey = "keepOnAuraLoss"`, label "End when the aura is lost", checked on reset, prefill `not entry.keepOnAuraLoss`, read stores `true` only when unchecked, visible via `ns:DetailedChildShown(state.detailed, ctx)` and `ns.KIND.USER_BUFF`
- [x] No `AddExclusiveCheck` anywhere in `TRACKER_FIELDS` (not even a comment)
- [x] Contract block contains the exact sentence "The runtime gates on entry.detailed, never on whether a child key exists"
- [x] `CreateAddDialog` hash unchanged (`64e38633612791cb7e1ea41902b75ae45c18167b`); `Display.lua` unchanged; CRLF gates pass (`git ls-files --eol` shows `w/crlf`, no CRCRLF); `stylua --check` clean
- [ ] **Human-only (no WoW client in this environment):** the Buffs-tab dialog visually toggles the detailed section and shrinks/grows correctly; the aura ID row's icon/name preview and secret badge render and update live; Add and Edit round-trip `detailed`/`auraID`/`keepOnAuraLoss` correctly, including switching back to simple and confirming the hidden children's saved values survive (WR-02) with no runtime effect

## Decisions Made
- `keepOnAuraLoss` layers its own `ctx.kind == ns.KIND.USER_BUFF` check on top of `ns:DetailedChildShown`, since cancellation never applies to cooldowns, while `auraID`'s `visible` depends only on `ns:DetailedChildShown` with no kind check of its own -- per the plan's design note, this lets Phase 57 reuse the `auraID` field unchanged for cooldown visibility once `ns:DetailedModeOffered` is widened to accept `ns.KIND.USER_CD`.
- `auraID`'s secrecy badge is shown/hidden via `SetShown` inside the field's own `update()` (compare-before-write on `id`/`generation`, mirroring `secrecyBadge`'s pattern) rather than a separate `visible()` hook, because the badge is a child widget of the row (anchored to `hover`), not its own `TRACKER_FIELDS` array entry the walker manages.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' automated verify gates passed on the first attempt after one self-caught fix during drafting (see below), with no further auto-fixes required.

**Self-caught during Task 1 drafting (not a deviation from the plan's required behavior, just an implementation slip caught by the task's own verify gate):** the first draft of the `detailed` entry's build comment mentioned `AddExclusiveCheck` by name to explain why it is not called, which the plan's gate hygiene rule explicitly forbids ("do not write `AddExclusiveCheck` anywhere inside TRACKER_FIELDS, not even a comment"). Reworded the comment to describe the same fact without naming the identifier, re-ran `stylua`, and the gate passed.

## Issues Encountered
None beyond the self-caught comment wording above.

## Performance/Cleanup Review (CLAUDE.md workflow)

Reviewed both commits for hot-path allocations, redundant per-frame work, dirty-check opportunities, and dead code, per the project's post-commit standing instruction. This plan only extends `CreateAddDialog`'s field-definition table (`TRACKER_FIELDS`), which runs on dialog build/open/keystroke, never on the addon's per-frame `OnUpdate` game loop. The `auraID` field's `update()` follows the same compare-before-write shape as `secrecyBadge`'s (`checkedID`/`checkedGen` keyed on the preview's `generation`, same as `secrecyBadge` reads `preview.generation`), so a resolved ID's badge/preview logic is not re-run on every keystroke of an unrelated field. `detailed` and `keepOnAuraLoss` are copies of the existing `coverAllRanks` CheckButton pattern with no new allocation shape. No dead code was left behind. Nothing to flag.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 57's visibility selector, cross-spell triggers box, and cooldown aura-ID-for-visibility can widen `ns:DetailedModeOffered` to accept `ns.KIND.USER_CD` and append further children after `keepOnAuraLoss`; `ns:DetailedChildShown` needs no change for a display-only cooldown child since `auraID`'s own `visible` already has no kind restriction.
- `ns:RefreshIDPreview` and `ns:BuildSecrecyBadge` have now been reused by three call sites (portrait, secrecyBadge, auraID) with no forking of their logic.
- No blockers. In-game verification of the dialog's visual toggle behavior, the aura ID preview/badge, and the Add/Edit round-trip (including the WR-02 hidden-value-survives-a-mode-switch case) remains human-only -- no WoW client is available in this execution environment. That verification belongs to Plan 04's whole-phase checklist per the 56-01 summary's stated deferral.

## Self-Check: PASSED

All commits (`eb372fd`, `fcbbbda`) found in `git log`; `CDMTab.lua` modifications confirmed on disk via the automated verify gates run above (every `grep -q`/`awk` assertion checked directly against the current file content, not asserted from memory).

---
*Phase: 56-detailed-tracking-mode-aura-rules*
*Completed: 2026-09-28*
