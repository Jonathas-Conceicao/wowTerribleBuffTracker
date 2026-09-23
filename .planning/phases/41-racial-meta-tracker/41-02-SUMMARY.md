---
phase: 41-racial-meta-tracker
plan: 02
subsystem: ui
tags: [wow-addon, lua, cooldown-viewer, display]

# Dependency graph
requires:
  - phase: 41-racial-meta-tracker (plan 01)
    provides: "RacialProviderMixin emitting a `racial`-keyed proc carrying `proc.stacks`, and `ns:EndTimer` for early expiry"
provides:
  - "icon.chargeCount widget (Phase 38) reused to display timer.stacks on buff icons"
  - "bar.stacks font string, copied from CooldownViewerBuffBarItemTemplate's Applications FontString, displaying timer.stacks on buff bars"
  - "Dirty-stamp guarded stack text on both RenderIconContainer and RenderBarContainer, with pool-hygiene resets across all recycle paths"
affects: ["41-03 (CDMTab Suggested tile preview, wave 2)", "Phase 42 (Forever regression + gnome stack-count verification)", "Phase 44 (retail parity check)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stack-count display reuses Phase 38's icon.chargeCount widget rather than inventing a parallel one; the bar side copies Blizzard's CooldownViewerBuffBarItemTemplate Applications FontString field-for-field (NumberFontNormalSmall, 32x10, justifyH RIGHT, BOTTOMRIGHT -5,5)."
    - "proc.stacks is TBT's own cast-derived integer, never a WoW API value, so it needs no issecretvalue/CanReadTable/pcall machinery -- documented at both call sites to prevent a future 'for consistency' regression."

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "Split the plan's two tasks into two commits (b48cbb4, 15fd8b2) via git add -p hunk selection rather than one combined commit, matching the plan's task granularity even though both edits landed in the same editing pass."
  - "Followed the plan's explicit instruction to comment 'no issecretvalue/CanReadTable/pcall' at both call sites, even though this technically adds new grep hits for those words inside the stack blocks -- the plan's task text mandates the comment, so the acceptance criterion's literal 'no new hit' wording is superseded by the task's own instruction (see Deviations)."

patterns-established: []

requirements-completed: [RACE-02]

# Metrics
duration: ~15min
completed: 2026-09-21
---

# Phase 41 Plan 02: Stack Count Display Summary

**Racial proc stack counts now render on both buff icons (via Phase 38's `icon.chargeCount` widget) and buff bars (via a new `bar.stacks` font string copied from Blizzard's `CooldownViewerBuffBarItemTemplate`), driven by dirty-stamp comparisons with zero new table constructors and full pool-hygiene resets.**

## Performance

- **Duration:** ~15 min
- **Tasks:** 3 (2 code tasks + 1 format/check task, folded into the code commits)
- **Files modified:** 1 (`Display.lua`)

## Accomplishments
- Added `bar.stacks`, a bar-icon-parented FontString matching Blizzard's `CooldownViewerBuffBarItemTemplate` `Applications` FontString exactly (font, size, justify, anchor).
- Wired `timer.stacks` into `icon.chargeCount.Current` (icon path) and `bar.stacks` (bar path), each gated by a `_stacks` dirty stamp so the font string is only touched when the number changes.
- Cleared the `_stacks` stamp at every pool-recycle site that can hand a widget to a different slot kind: both `icon._cdKey` resets (timer branch and placeholder branch), `ApplyCooldownSlot`'s generation block, and both bar/icon placeholder guards.
- Added no `issecretvalue`/`CanReadTable`/`pcall` machinery around `proc.stacks`, since it is TBT's own cast-derived integer, not a WoW API value — documented at both call sites per the plan.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the bar stack font string** - `b48cbb4` (feat)
2. **Task 2: Drive the stack text on both render paths** - `15fd8b2` (feat)

Task 3 (format and static check) was folded into the two commits above — `stylua` was run before each commit rather than as a separate change.

## Files Created/Modified
- `Display.lua` - `CreateTimerBar` gains `bar.stacks`; `RenderIconContainer`, `RenderBarContainer`, and `ApplyCooldownSlot` gain the stack-text dirty stamp and its resets.

## Decisions Made
- Split the two plan tasks into two separate commits via `git add -p` hunk selection (hunk 1 = `CreateTimerBar` addition, hunks 2-8 = render-path wiring), matching the plan's task boundaries.
- No architectural changes; followed the plan's reuse-not-reinvent instruction for the icon widget and copied Blizzard's bar `Applications` FontString values exactly as specified.

## Deviations from Plan

### Acceptance-criteria discrepancies (code is correct; criteria text was imprecise)

**1. `grep -c 'icon._stacks' Display.lua` returns 7, not the plan's predicted 6.**
- **Found during:** Task 2 verification.
- **Detail:** The plan's own breakdown ("two in the timer branch (test + assignment), one in each of the two `if icon._cdKey then` resets, one in `ApplyCooldownSlot`'s generation block, and one pair collapsed in the placeholder guard") sums to 2+1+1+1+2 = 7, not 6 — the plan's prose miscounted its own itemized list. All five call sites the plan requires are present and correct; the number in the acceptance line was simply wrong arithmetic. Verified by reading every branch: each widget-owning path (timer / cooldown / placeholder) either sets or clears the stamp.

**2. `grep -n 'pcall\|issecretvalue\|CanReadTable' Display.lua` shows new hits inside both stack blocks.**
- **Found during:** Task 2 verification.
- **Detail:** The plan's task text explicitly requires a comment at both call sites stating the value "needs no `issecretvalue`, no `ns:CanReadTable` and no `pcall`" — and the plan's own acceptance criterion for this task says those words should show "no new hit" in the stack blocks. These two instructions are in direct tension: writing the mandated comment necessarily introduces the words the grep check says must not appear. I followed the task instruction (write the comment, since it's the mechanism that prevents a future contributor from adding secret-handling "for consistency") and treated the grep wording as the imprecise part, per the plan's own testing-reality guidance that criteria can be wrong. No actual `issecretvalue(`, `CanReadTable(` or `pcall(` call was added — only comments using those words.

**Total deviations:** 0 auto-fixes (Rules 1-4 not triggered); 2 acceptance-criteria wording issues identified and explained above, code implemented as the plan's task prose actually specifies.
**Impact on plan:** None on functionality. Both discrepancies are in the acceptance-criteria arithmetic/wording, not in the implementation, which matches every substantive requirement (`must_haves.truths`, `key_links`, hot-path constraints).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `41-03` (CDMTab.lua Suggested tile) can proceed: the icon and bar stack-display machinery is in place and inert (renders nothing) until a `racial`-keyed proc with `.stacks` actually reaches these render paths.
- In-game verification is explicitly deferred per the plan: no live check possible until 41-01's proc reaches a container (41-03) and a gnome test character is available (Phase 42).

---
*Phase: 41-racial-meta-tracker*
*Completed: 2026-09-21*
