---
phase: 55-id-preview-suggested-cooldown-secrecy
plan: 02
subsystem: ui
tags: [wow-addon, lua, cdm-tab, add-dialog, field-definition, tooltip, secrecy]

# Dependency graph
requires:
  - phase: 55-01
    provides: ns:SpellPreview, ns:SpellAuraSecrecy, ns:SecrecyWarns, ns:SecrecyLine, ns:SecrecyExplanation -- the guarded ns helpers this plan's two fields call
  - phase: 54-02
    provides: the TRACKER_FIELDS field-definition contract and CreateAddDialog's field-agnostic walker (build/reset/prefill/update/visible/validate, dialog.GetFieldState)
provides:
  - "spellPreview TRACKER_FIELDS entry -- live icon + name row under the Spell ID box, game tooltip on hover, retries an unresolved ID on every later dialog change (ADD-04)"
  - "secrecyBadge TRACKER_FIELDS entry -- warning badge beside the preview on both tabs when the typed ID's aura secrecy is above never-secret, with an explanatory hover tooltip (SECR-03)"
affects: [55-03, 56, 57]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Display-only TRACKER_FIELDS entries (no entryKey, no editBox key) that anchor to an earlier sibling's build-time state via dialog.GetFieldState and may return the unchanged y cursor to take zero row height"
    - "Hover closures declare their state table before any SetScript call in the same build, so OnEnter/OnLeave always close over the field's own local instead of risking a nil global"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "None -- plan executed exactly as written, including the closure-declaration-order hazard both fields exist to satisfy"

patterns-established:
  - "A field's build may read an earlier sibling's returned state via dialog.GetFieldState to anchor widgets or reuse its EditBox, without CreateAddDialog naming either field"

requirements-completed: [ADD-04, SECR-01, SECR-03]

# Metrics
duration: ~3min
completed: 2026-09-28
---

# Phase 55 Plan 02: ID Preview, Suggested Cooldown & Secrecy - Dialog Preview and Secrecy Badge Summary

**Added spellPreview (live icon/name row with game-tooltip hover and unknown-ID retry) and secrecyBadge (warning badge with explanatory tooltip on both tabs) as two new TRACKER_FIELDS entries, with zero lines changed in CreateAddDialog.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-09-28T10:27:44-03:00
- **Completed:** 2026-09-28T10:30:31-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 1 (CDMTab.lua)

## Accomplishments

- `spellPreview` (display-only, no entryKey): reads the `spellID` field's box through `dialog.GetFieldState("spellID")` at build, shows an 18x18 icon plus name under the Spell ID box on every keystroke, falls back to the 134400 question-mark icon and "Unknown spell" for an ID the client does not know, and re-queries that still-unknown ID on every later dialog change (for example a Duration keystroke) so a spell the client had not cached when typed resolves instead of sticking. Hovering it calls `ns:ShowBuffTooltip` with a reused `tooltipProc`/`tooltipOpts` pair, showing the game's own tooltip (with TOOL-01's ID and secrecy lines from Plan 01, or the unresolved-ID branch's own "Spell ID: N" plus secrecy line).
- `secrecyBadge` (display-only, no entryKey): anchored off `spellPreview`'s hover frame, decides once at build whether the `transmog-icon-warning-small` atlas resolves and falls back to a `"(secret?)"` FontString when it does not, reads `ns:SpellAuraSecrecy` on every ID change, and is visible (via `ns:SecrecyWarns`) whenever the level is `AlwaysSecret` or `ContextuallySecret` -- on **both** tabs, by CONTEXT's explicit scope decision, so the entry never branches on `ctx.kind`. Hovering shows `ns:SecrecyLine` plus `ns:SecrecyExplanation` as a wrapped second line. It returns the build-time `y` cursor unchanged, so it takes no row height of its own and never moves any other row when it toggles.
- Both fields' `build` declares `local state = { ... }` before either `SetScript("OnEnter"/"OnLeave")` call, so the hover closures close over that same table -- not an undeclared global -- per the hazard this plan was revised to guard against (T-55-15).
- The field-definition contract comment above `TRACKER_FIELDS` gained one paragraph describing the display-only field shape (no entryKey, reads a sibling via `dialog.GetFieldState` at build, no `editBox` key, may return the unchanged cursor for zero height), so a later phase has the pattern documented once rather than re-derived from these two fields.
- `CreateAddDialog`'s body hash is unchanged (`64e38633612791cb7e1ea41902b75ae45c18167b`) after both tasks -- every behaviour lives in the two new TRACKER_FIELDS entries, confirming EDIT-03 a second time.

## Task Commits

Each task was committed atomically:

1. **Task 1: spellPreview field (icon + name row, game tooltip on hover)** - `1f128e7` (feat)
2. **Task 2: secrecyBadge field (warning badge with explanatory tooltip, both tabs)** - `a71422c` (feat)

**Plan metadata:** commit pending (docs: complete plan)

## Files Created/Modified

- `CDMTab.lua` - one new paragraph in the TRACKER_FIELDS contract comment; `SECRECY_BADGE_ATLAS` constant declared above `TRACKER_FIELDS`; two new TRACKER_FIELDS entries (`spellPreview` between `spellID` and `duration`; `secrecyBadge` between `spellPreview` and `duration`); `CreateAddDialog` itself untouched

## Decisions Made

Followed the plan's exact field shapes (widget sizes/anchors, reused tooltip tables, compare-before-write update guards, the unknown-ID retry, the atlas-vs-text fallback decided once at build) with no deviation. The plan's own closure-ordering instruction (declare `local state` before any `SetScript`) was followed literally in both fields, verified by the gate checking line order of `local state = {` against `SetScript("OnEnter"`.

## Deviations from Plan

None - plan executed exactly as written. Both task verification gates (stylua, field-order, entryKey/editBox-absence, ns-helper-call presence, closure-declaration-order, CreateAddDialog hash, CRLF/CRCRLF checks) passed on the first attempt with no auto-fixes needed.

## Known Stubs

None. Both fields are fully wired to the Plan 01 helpers and to `ns:ShowBuffTooltip`; nothing renders a hardcoded empty value or placeholder text beyond the intentional "Unknown spell" / "(secret?)" fallback strings the plan specifies.

## Verification Results

- `stylua --check CDMTab.lua` exits 0 after both tasks
- TRACKER_FIELDS contains `id = "spellPreview"` and `id = "secrecyBadge"` exactly once each, ordered spellID < spellPreview < secrecyBadge < duration
- Neither new entry contains `entryKey =` or `editBox =`; the secrecyBadge entry contains no non-comment `ctx.kind`
- spellPreview calls `ns:SpellPreview(`, `ns:ShowBuffTooltip(`, contains `"Unknown spell"`, and reads `GetFieldState("spellID")`; references `state.resolved` on 4+ non-comment lines
- secrecyBadge calls `ns:SpellAuraSecrecy(`, `ns:SecrecyWarns(`, `ns:SecrecyExplanation(`, `C_Texture.GetAtlasInfo`, and contains the `"(secret?)"` fallback
- In both entries, the first non-comment `local state = {` line precedes the first non-comment `SetScript("OnEnter"` line, and a `return state,` line exists
- `local SECRECY_BADGE_ATLAS = "transmog-icon-warning-small"` is declared above `local TRACKER_FIELDS`
- `CreateAddDialog`'s body hashes to `64e38633612791cb7e1ea41902b75ae45c18167b` after both tasks (unchanged from the phase base)
- `git ls-files --eol CDMTab.lua` reports `w/crlf`; `git diff --numstat CDMTab.lua` shows real byte counts; the CRCRLF (`\r\r\n`) node check exits 0 after each task
- `git status --porcelain -- '*.lua' '*.xml' '*.toc'` lists only `CDMTab.lua`; `.gitignore`'s pre-existing working-tree edit was never staged
- **Human verification still required** (deferred to Plan 03's checklist, no WoW client available here): preview updates live as an ID is typed on both the Add and Edit dialog; an ID the client does not know shows the question-mark icon and "Unknown spell", then resolves once cached without a further keystroke on that field itself (only on a later dialog change, per the retry design); hovering the preview shows the game's own tooltip with the TOOL-01 ID and secrecy lines; the badge appears on both the Buffs and Cooldowns tab for an Always/Contextually secret ID and stays hidden for NeverSecret, empty, or a client without the secrecy API; the `transmog-icon-warning-small` atlas actually resolves on Forever (CONTEXT flagged this as unconfirmed) and the text fallback only triggers where it does not

## Issues Encountered

None.

## User Setup Required

None - this plan's output is code only, consumed in-dialog with no new configuration, migration or manual step.

## Next Phase Readiness

`spellPreview` and `secrecyBadge` are in place exactly as this plan's `<must_haves>` specify, both reachable from Add and Edit with zero `CreateAddDialog` edits. Plan 03 (per Plan 01's Next Steps) covers ADD-05's suggested-cooldown wiring on the duration field and carries the phase's full human-verification checklist, including every item listed above plus Plan 01's own deferred checks. No blockers.

## Self-Check: PASSED

- FOUND: CDMTab.lua
- FOUND: .planning/phases/55-id-preview-suggested-cooldown-secrecy/55-02-SUMMARY.md
- FOUND commit: 1f128e7 (Task 1)
- FOUND commit: a71422c (Task 2)

---
*Phase: 55-id-preview-suggested-cooldown-secrecy*
*Completed: 2026-09-28*
