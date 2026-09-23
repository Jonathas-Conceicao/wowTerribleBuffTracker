---
phase: 37-add-panel-rank-grouping
plan: 03
subsystem: ui
tags: [wow-addon, lua, cdm-tab, menuutil, add-dialog]

# Dependency graph
requires:
  - phase: 37-add-panel-rank-grouping (plan 01)
    provides: ns.CLIENT_HAS_SPELL_RANKS, ns.rankIndex, ns:RebuildRankIndex
  - phase: 37-add-panel-rank-grouping (plan 02)
    provides: ns:AddTrackedBuff(spellID, duration, label, opts) with trackerType/section/coverAllRanks
provides:
  - Redesigned CreateAddDialog in CDMTab.lua with Buff/Cooldown type picker, a
    MenuUtil-based container picker built from ns.CONTAINERS, and (Forever only) a
    "Cover all ranks" checkbox
  - dialog.ResetFields as the single reset path for the add dialog
affects: [38-cooldown-rendering, 44-retail-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dialog vertical layout driven by a single y-offset cursor anchored to the dialog
      itself, so one SetSize call computes height from whatever controls were actually
      created -- no second flavour branch on a literal height."

key-files:
  created: []
  modified: [CDMTab.lua]

key-decisions:
  - "Buff/Cooldown and the container's Not-Displayed/picked value both anchor directly to
    the dialog (not chained to the previous control), so the y cursor and the single
    SetSize call stay in sync with no duplicated bookkeeping."
  - "Cover-all-ranks' own gap-before-widget is inside the `if ns.CLIENT_HAS_SPELL_RANKS`
    block (not just the widget itself), so retail carries no blank space where the
    checkbox would have been."
  - "Tasks 1 and 2 landed in a single commit -- see Deviations."

requirements-completed: []  # This plan ends on a blocking checkpoint; not yet verified in-game. See Outstanding Checkpoint below.

# Metrics
duration: ~35min
completed: 2026-09-21
---

# Phase 37 Plan 03: The Redesigned Add Dialog Summary

**CreateAddDialog rebuilt with a Buff/Cooldown type pair, a MenuUtil container picker sourced from `ns.CONTAINERS`, and a Forever-only "Cover all ranks" checkbox — gated by `ns.CLIENT_HAS_SPELL_RANKS`, the sole reader of that Core.lua flag.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-21T16:40:00Z (approx)
- **Completed:** 2026-09-21T17:16:46Z
- **Tasks:** 2 of 3 code tasks complete; task 3 (format+deploy) complete; the plan's
  blocking `checkpoint:human-verify` is **outstanding** (this plan is `autonomous: false`)
- **Files modified:** 1 (`CDMTab.lua`)

## Accomplishments

- `CreateAddDialog` rebuilt: title now "Add Tracker", dialog widened to 240px, a single
  `y` cursor anchors every control TOPLEFT-to-dialog and drives one
  `dialog:SetSize(240, math.abs(y) + 46)` call after the last control is placed.
- **ADD-01:** `buffCheck`/`cooldownCheck` mutually-exclusive pair, copied from
  `CreateContainerDialog`'s Icons/Bars idiom (self-recheck included). Buff checked on open.
- **ADD-02:** `containerBtn` opens `MenuUtil.CreateContextMenu`, rebuilt every open from
  `ns.CONTAINERS` (never `SECTION_DEFS`), "Not Displayed" listed first and selected by
  default. `dialog.selectedSection` starts `"hidden"`.
- **ADD-03:** `rankCheck` — and its own preceding layout gap — exist only inside
  `if ns.CLIENT_HAS_SPELL_RANKS then`. Nil on a client without the flag; every later read
  of it is nil-guarded (`rankCheck and rankCheck:GetChecked()`, `if rankCheck then`).
- Add button now calls
  `ns:AddTrackedBuff(spellID, duration, nil, { trackerType = ..., section = dialog.selectedSection, coverAllRanks = ... })`.
- `dialog.ResetFields` is the single reset path; the `addSquare` `OnMouseUp` handler now
  calls it instead of clearing three fields inline.
- `stylua` clean, deployed via `./scripts/install.bat` to all four detected client folders
  including `_classic_beta_` (Forever).

## Task Commits

1. **Task 1 + Task 2 combined: rebuild `CreateAddDialog` and wire the three answers through** — `1532b65` (feat)
2. **Task 3: format + deploy** — no commit (stylua produced no additional diff; install.bat is a deploy step, not a repo change)

**Plan metadata:** not created — this plan stops at a blocking checkpoint; the orchestrator owns STATE.md/ROADMAP.md and the final metadata commit.

## Files Created/Modified

- `CDMTab.lua` — `CreateAddDialog` rebuilt with the three new controls and `ResetFields`;
  `addSquare`'s `OnMouseUp` now calls `dialog.ResetFields()`. No other function touched
  (verified by `git diff` hunk boundaries — only `CreateAddDialog` and the `addSquare`
  handler inside `ns:BuildAllSections` changed).

## Decisions Made

- Buff/Cooldown checkboxes are stacked vertically (Buff above Cooldown), matching
  `CreateContainerDialog`'s Icons/Bars layout literally, since the plan said "copy the
  idiom verbatim" and did not specify a side-by-side arrangement. This is a layout
  question the plan left open in spirit ("we will discuss the new add popup frame") — flag
  for the user if a different arrangement is wanted.
- All dialog controls (including the pre-existing Spell ID / Duration fields) were switched
  from chained relative anchors (`TOPLEFT, prevControl, "BOTTOMLEFT"`) to a single
  dialog-relative `y` cursor. This was necessary to satisfy the plan's literal requirement
  that `y` "starts at the current first control's offset" (`-38`, the original Spell ID
  label offset) and is "advanced by each anchored control" feeding one `SetSize` call —
  that only works cleanly if every control shares the same anchor parent. Visual result is
  unchanged pixel-for-pixel intent (same gaps), except the error label is now centered on
  the dialog's full width instead of centered under the Duration box specifically — a minor
  cosmetic consequence, not a functional one, and within the "keep close to existing
  dialog" scope fence.
- `dialog.selectedSection = "hidden"` is set explicitly *and* via the initial
  `SetContainerChoice` call (redundant but harmless) so the literal plan instruction ("Set
  `dialog.selectedSection = "hidden"`") and the helper's initialization both read
  unambiguously in the diff.

## Deviations from Plan

### Auto-fixed / adjusted during execution

**1. [Task-boundary — commit granularity] Tasks 1 and 2 landed in a single commit, not two**
- **Found during:** writing the `CreateAddDialog` rewrite
- **Issue:** Task 1 (rebuild the dialog) and Task 2 (wire the three answers through
  `ns:AddTrackedBuff` and route the reset) both modify the same function bidirectionally —
  the Add button's `OnClick` and `dialog.ResetFields` are Task 2's content but live inside
  the Task 1 rewrite. Writing Task 1 with the *old* 2-argument `AddTrackedBuff(spellID, duration)`
  call and the old inline-clearing `addSquare` handler, then immediately rewriting both for
  Task 2, would mean committing intentionally-incomplete code as an intermediate step
  (the Add button would silently drop `trackerType`/`section`/`coverAllRanks` for one
  commit) for no benefit — CDMTab.lua has no other caller of these fields between commits.
- **Fix:** Committed the full `CreateAddDialog` rebuild plus the `addSquare` handler change
  together as one `feat(37-03)` commit.
- **Files modified:** `CDMTab.lua`
- **Commit:** `1532b65`

**2. [Rule 1 - Bug, self-caught before commit] Rank-checkbox gap advanced `y` unconditionally**
- **Found during:** self-review of task 1, before running acceptance greps
- **Issue:** the first draft advanced `y` by 32 (the gap reserved for the rank checkbox)
  *before* the `if ns.CLIENT_HAS_SPELL_RANKS` check, so a retail client (no checkbox) would
  still carry that blank vertical gap between the container button and the error label —
  wasted space, not a correctness bug, but it meant the height savings on retail implied by
  "let the rank checkbox advance it only when it exists" (37-03-PLAN.md) weren't real.
- **Fix:** moved the `y = y - 32` line inside the `if` block so the gap, not just the
  widget, is conditional on the flag.
- **Files modified:** `CDMTab.lua`
- **Commit:** `1532b65` (fixed before the single commit was made, not a separate commit)

---

**Total deviations:** 1 commit-granularity note, 1 self-caught layout bug fixed pre-commit.
**Impact on plan:** No scope creep, no architectural changes, no second flavour check
introduced. Both are implementation-detail adjustments within the plan's stated approach.

## Issues Encountered

None beyond the two items above.

## Layout Questions Not Decided

- Whether Buff/Cooldown should be stacked (chosen, matching `CreateContainerDialog`
  verbatim) or side-by-side was not specified by the plan. Left as the more literal
  reading; flag for the user per the phase's deferred add-panel-layout discussion.

## Outstanding Checkpoint (BLOCKING — this plan is `autonomous: false`)

This plan ends on `checkpoint:human-verify` (`gate="blocking"`) in
`37-03-PLAN.md`, to be run on the **Forever beta client**
(`_classic_beta_`, build 1.60.1.69913). It has **not** been run. The 10-step in-game
checklist from the plan (ADD-01/02/03 presence and behaviour, container choice honoured,
Not-Displayed default, RANK-01/RANK-02 headline check with Fireball `133`/`143`/`145`,
the RANK-01 negative case, the cooldown-type entry rendering nothing in-world as expected
for Phase 37, `/reload` persistence, no Lua errors) is recorded as outstanding, not passed.
The orchestrator folds this checklist into Phase 42 per the plan's own note.

`ADD-03`'s retail half (the checkbox is **absent**, not hidden, on retail) is also
unverifiable in-game until Phase 44 — retail is out of scope until then — and rests on the
code-reading confirmation below.

## Self-Check

- `CDMTab.lua` exists and contains the rebuilt `CreateAddDialog`: confirmed by `Read`.
- Commit `1532b65` exists: confirmed by `git log --oneline -1`.
- `stylua --check .` exits 0: confirmed.
- `git diff --name-only` (post-commit, working tree) is empty of `CDMTab.lua`: confirmed —
  fully committed.
- `./scripts/install.bat` deployed to all four detected client folders, including
  `_classic_beta_`: confirmed by command output.

## Self-Check: PASSED

## Next Phase Readiness

- Code side of ADD-01/ADD-02/ADD-03 is complete and matches every grep/read acceptance
  criterion in `37-03-PLAN.md` tasks 1 and 2.
- **Not ready to close Phase 37** until the blocking in-game checkpoint above is run and
  the orchestrator/user confirms "approved" (or reports a failing step).
- Phase 38 (cooldown rendering) can begin once the checkpoint passes; a cooldown tracker
  created through this dialog will appear in its chosen CDM tab section but render nothing
  in the world until Phase 38 lands, by design.

---
*Phase: 37-add-panel-rank-grouping*
*Completed: 2026-09-21 (code); checkpoint outstanding*
