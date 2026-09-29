---
phase: 57-detailed-tracking-visibility-cross-spell-rules
plan: 04
subsystem: ui
tags: [wow-addon, cdm, lua, dialog, tracker-fields, visibility, cross-spell-rules]

# Dependency graph
requires:
  - phase: 56-detailed-tracking-mode-aura-rules
    plan: 03
    provides: "ns:DetailedModeOffered/ns:DetailedChildShown gates, detailed/auraID/keepOnAuraLoss TRACKER_FIELDS entries and the field-definition contract this plan extends"
  - phase: 57-detailed-tracking-visibility-cross-spell-rules
    plan: 01
    provides: "the runtime that reads entry.endOnCast (ns:RebuildDetailedRuleIndex, ns:ApplyEndOnCast), dormant until this plan writes the key"
provides:
  - "ns:DetailedModeOffered widened to ns.KIND.USER_BUFF or ns.KIND.USER_CD, so both tabs offer detailed mode"
  - "ns:SyncVisibilityChecks, keeping the three visibility CheckButtons mutually exclusive"
  - "ns:ParseSpellIDList and MAX_CAST_RULE_IDS, the cast-rule text parser and its 8-ID cap"
  - "visibility and endOnCast TRACKER_FIELDS entries (in that order, after keepOnAuraLoss), saving entry.visibility and entry.endOnCast"
  - "the Phase 57 contract paragraph above TRACKER_FIELDS"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A field with no editBox key (visibility) stays out of the Tab/Enter ring while still driving three CheckButtons through one shared state table, mirroring the master checkbox's own pattern but exclusive across three widgets instead of one"
    - "Cast-rule text parsing lives entirely in the dialog layer (ns:ParseSpellIDList): validate and read both call the same parser, so the error message shown to the user and the array actually saved can never disagree"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "visibility has no editBox key and returns state.mode directly from read/prefill, matching the plan's nil = always contract exactly rather than introducing a fourth sentinel value"
  - "endOnCast's icon row re-renders unconditionally whenever the text changes or any icon is still unknown (state.pendingUnknown), the same retry shape ns:RefreshIDPreview already uses for the aura ID row, rather than a separate timer"
  - "validate and read both call ns:ParseSpellIDList independently (not cached), since the parser is pure and cheap (one gmatch loop, at most 8 iterations) and dialog validation already runs on every keystroke"

patterns-established: []

requirements-completed: [DTRK-03, DTRK-05]

# Metrics
duration: ~12min
completed: 2026-09-28
---

# Phase 57 Plan 04: Detailed-Mode Dialog Fields (Visibility & Cross-Spell Rules) Summary

**Widened `ns:DetailedModeOffered` to the Cooldowns tab and added two new TRACKER_FIELDS children after `keepOnAuraLoss` -- a three-way exclusive "Show this tracker:" visibility selector and an 8-ID cast-rule box with a live icon preview row -- saving `entry.visibility` and `entry.endOnCast`, the exact keys Plans 01-03's runtime already reads.**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-09-28T13:56:04-03:00
- **Tasks:** 2 completed
- **Files modified:** 1 (CDMTab.lua)

## Accomplishments
- `ns:DetailedModeOffered(ctx)` now returns true for `ns.KIND.USER_BUFF` or `ns.KIND.USER_CD`; its comment documents that a cooldown's children are the aura ID (visibility only, reused unchanged from Phase 56), the visibility selector, and "Resets when you cast:", while `keepOnAuraLoss` stays buff-only through its own kind check.
- `ns:SyncVisibilityChecks(state)` added directly after `ns:DetailedChildShown`: sets the three visibility CheckButtons from `state.mode` (nil/"present"/"absent"); `SetChecked` fires no `OnClick`, so it never recurses.
- `visibility` TRACKER_FIELDS entry after `keepOnAuraLoss`: a "Show this tracker:" heading with three exclusive `UICheckButtonTemplate` boxes ("Always" / "Only while the aura is up" / "Only while the aura is missing"), `local state = {` declared before any of the three `OnClick` scripts, defaulting to Always, saved as `entry.visibility` ("present"/"absent"/nothing), visible on both tabs via `ns:DetailedChildShown(state.detailed, ctx)`.
- `MAX_CAST_RULE_IDS = 8` and `ns:ParseSpellIDList(text)` added above TRACKER_FIELDS: strips whitespace, splits on commas, rejects non-digit tokens and out-of-range IDs (1..2147483647), drops duplicates silently, and caps at 8 distinct IDs -- returning nil for blank, a fresh array for valid input, or `false, message` otherwise.
- `endOnCast` TRACKER_FIELDS entry as the last array element: a not-numeric 180x22 EditBox (`SetMaxLetters(96)`) labelled "Ends when you cast:" on buffs / "Resets when you cast:" on cooldowns (`ctx.kind == ns.KIND.USER_CD`), an 8-icon 16x16 preview row using `ns:SpellPreview` with the 134400 question mark tinted red (`SetVertexColor(1, 0.3, 0.3)`) for unknown IDs, prefilled via `table.concat(entry.endOnCast, ", ")` (a joined copy, never the saved table), `read` returning a fresh array from `ns:ParseSpellIDList` or nil, and `validate` blocking Save when the list is malformed or contains the tracker's own spell ID (`state.spell.editBox:GetNumber()`).
- The Phase 57 contract paragraph added above TRACKER_FIELDS (after the Phase 56 one, whose "(Buffs only in Phase 56)" now reads "(both user tabs since Phase 57)"), documenting the child order (`detailed`, `auraID`, `keepOnAuraLoss`, `visibility`, `endOnCast`) and the runtime readers; the hazard paragraph's declared-above list now also names `ns:SyncVisibilityChecks`, `ns:ParseSpellIDList`, and `MAX_CAST_RULE_IDS`.
- `CreateAddDialog` untouched: hash gate `64e38633612791cb7e1ea41902b75ae45c18167b` verified unchanged after both tasks.

## Task Commits

Each task was committed atomically:

1. **Task 1: Detailed mode on the Cooldowns tab and the visibility selector** - `42a8e6b` (feat)
2. **Task 2: The cross-spell ID box with its icon row; the Phase 57 contract paragraph** - `c511b87` (feat)

_No plan-metadata commit -- the orchestrator owns STATE.md/ROADMAP.md updates for this plan._

## Files Created/Modified
- `CDMTab.lua` - `ns:DetailedModeOffered` widened; `ns:SyncVisibilityChecks`, `MAX_CAST_RULE_IDS`, `ns:ParseSpellIDList` added above TRACKER_FIELDS; `visibility` and `endOnCast` TRACKER_FIELDS entries appended after `keepOnAuraLoss`; the Phase 57 contract paragraph and extended hazard paragraph

## Decisions Made
- `visibility`'s `read`/`prefill` operate directly on `state.mode` with no intermediate widget query, since the three CheckButtons are already kept in sync by `ns:SyncVisibilityChecks` and the field's own state is the single source of truth between renders.
- `endOnCast`'s icon-row retry (`state.pendingUnknown`) mirrors `ns:RefreshIDPreview`'s existing retry shape exactly, so a spell the client has not yet cached resolves on the next unrelated keystroke instead of staying stuck on the red question mark.
- No deviations from the plan's documented design choices (field order, label text, parser bounds, skip-own-ID validation) were needed -- every helper and pattern the plan referenced (`ns:SpellPreview`, `ns:RefreshIDPreview`'s retry shape, the `keepOnAuraLoss`/`auraID` CheckButton/EditBox patterns) already existed in the current tree.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## Performance/Cleanup Review (CLAUDE.md workflow)

Reviewed both commits for hot-path allocations, redundant per-frame work, dirty-check opportunities, and dead code, per the project's post-commit standing instruction. This plan only extends `CreateAddDialog`'s field-definition table (`TRACKER_FIELDS`), which runs on dialog build/open/keystroke, never on the addon's per-frame `OnUpdate` game loop (confirmed: no new line in the diff contains the text `OnUpdate`, verified with `git diff 0459903 -- CDMTab.lua | grep OnUpdate`, no output). `endOnCast`'s `update()` compares `state.editBox:GetText()` against `state.shownText` before doing any work, only re-rendering the 8 icons when the text actually changed or an icon is still unknown -- the same compare-before-write shape as `auraID`'s badge cache. `ns:ParseSpellIDList` allocates one table and one `seen` set per call, but only runs on dialog keystrokes/validation, never on the render path. No dead code was left behind. Nothing to flag.

## User Setup Required

None - no external service configuration required.

## Verification

Both task automated gates passed in full on the first attempt (Task 1: `ns:DetailedModeOffered` USER_CD/USER_BUFF, `ns:SyncVisibilityChecks` placement, `visibility` entry shape/order/closure-binding, no `AddExclusiveCheck`, hash/stylua/CRLF gates; Task 2: `MAX_CAST_RULE_IDS`/`ns:ParseSpellIDList` placement and body shape, `endOnCast` entry shape/order/labels/validation, contract and hazard paragraph text, hash/stylua/CRLF gates). `node scripts/aura-read-gate.js` reports `AURA-READ GATE PASS (10 reads in 3 allowlisted readers)` -- unchanged from before this plan, confirming neither new field reads a secret aura value directly.

In-game verification (the Cooldowns-tab dialog visually offering Detailed tracking; the three visibility checkboxes rendering exclusive and toggling correctly; the cast-rule box's icon row rendering and updating live, including the red unknown-ID marker and the retry on a late-resolving ID; Add and Edit round-tripping `visibility`/`endOnCast` correctly including the WR-02 hidden-value-survives-a-mode-switch case) requires a live WoW client -- no WoW client is available in this execution environment, per the plan's stated human-only deferral.

## Next Phase Readiness
- DTRK-03 and DTRK-05's dialog halves are both complete. `entry.visibility` and `entry.endOnCast` can now be written from either tab's Add/Edit dialog, which activates the previously-dormant runtime built in Plans 01-03 (57-01-SUMMARY.md noted `ns.endKeysBySpell` stayed empty on every save file until this plan existed).
- No blockers. In-game verification of the visual dialog behavior and the full Add/Edit round-trip (including WR-02) remains human-only, consistent with every prior CDMTab.lua dialog plan in this milestone (56-03, 57-01).

## Self-Check: PASSED

Commits `42a8e6b` and `c511b87` found in `git log --oneline -5`. `CDMTab.lua` modifications confirmed on disk via the automated verify gates run above (every `grep -q`/`awk` assertion checked directly against the current file content). CreateAddDialog hash gate (`64e38633612791cb7e1ea41902b75ae45c18167b`) confirmed unchanged after both tasks.

---
*Phase: 57-detailed-tracking-visibility-cross-spell-rules*
*Completed: 2026-09-28*
