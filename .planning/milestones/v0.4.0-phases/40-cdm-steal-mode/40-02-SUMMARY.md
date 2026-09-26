---
phase: 40-cdm-steal-mode
plan: 02
subsystem: ui
tags: [wow-addon, cooldown-manager, display-rendering, lua]

# Dependency graph
requires:
  - phase: 40-cdm-steal-mode (plan 01)
    provides: ns.stealSlots mirror table (StealMode.lua), cdmCategoryName on the four base
      container defs, ns:RefreshStealMirror event-driven rebuild
provides:
  - RenderIconContainer appends ns.stealSlots[def.key] after the layout-order sort and renders
    mirrored essential/utility slots through the existing Phase 38 ApplyCooldownSlot cooldown
    branch, and mirrored buff slots through the existing placeholder branch (forced visible via
    entry.isStolen)
  - RenderBarContainer appends ns.stealSlots[def.key] after the showPlaceholders sort/no-sort
    branches, before the EXAMPLE_BAR_SLOT insertion, and renders mirrored bars via a new
    slot.isStolen branch feeding the existing no-timer placeholder rendering
  - hasActiveIcons / hasActiveTimers both fold in the mirrored count, so a container holding only
    mirrored CDM items stays visible under hideWhenInactive
affects: [40-03 (hide/restore + toggle wiring, touches different files but depends on this render
  path existing), 43-cleanup (the two pre-existing proc = { ... } placeholder constructors this
  plan deliberately left untouched)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mirror entries reuse existing tracker-shaped render branches (trackerType == \"cooldown\"
      for essential/utility, the placeholder branch for buffs/bars) instead of a fourth render
      kind, gated on an isStolen/entry.isStolen/slot.isStolen read."
    - "Mirror append happens after table.sort, never sorted into it, preserving both the user's
      own layoutOrder and the CDM's insertion order with no second table.sort per tick."

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "Gated the bar mirror branch on slot.isStolen, not slot.spellID, per the plan's explicit
    warning: every DB entry also carries a spellID, and branching on that would have silently
    rerouted the Trinket/Pot meta-tracker resolution Phase 27 protects."
  - "Reworded three comments (originally containing the literal strings ns.stealSlots,
    ns:RefreshStealMirror, and 'gate on isStolen') because they were inflating the plan's exact-
    count acceptance greps for those identifiers. Code was already correct; only comment prose
    needed to change to stop matching a grep meant to count code sites."

patterns-established:
  - "A read-only mirror slot never gets its own render path -- it is shaped to fit whichever
    existing branch its trackerType already selects, with a single isStolen boolean deciding
    where its icon/label/tooltip payload comes from."

requirements-completed: [STEAL-03, STEAL-04]

# Metrics
duration: ~20min
completed: 2026-09-21
---

# Phase 40 Plan 02: Render the Mirror Summary

**Mirrored CDM slots (`ns.stealSlots`) now render as first-class TBT icons and bars in
`RenderIconContainer`/`RenderBarContainer`, reusing the Phase 38 cooldown branch and the existing
placeholder branch instead of adding a fourth render kind, with zero new table constructors on the
hot path.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-21T18:32:41Z
- **Tasks:** 3
- **Files modified:** 1 (`Display.lua`)

## Accomplishments
- `RenderIconContainer` appends `ns.stealSlots[def.key]` after `table.sort(slots, ByLayoutOrder)`;
  `hasActiveIcons` folds in the mirrored count; the placeholder branch condition now includes
  `entry.isStolen` and resolves mirrored entries directly (`icon.proc = entry`) instead of calling
  `ns:GetDisplayInfoForKey`. Mirrored essential/utility entries need no new code at all — they
  already carry `trackerType == "cooldown"` and land in the existing `ApplyCooldownSlot` branch.
- `RenderBarContainer` appends the mirror after the `showPlaceholders` sort/no-sort branches and
  before the `EXAMPLE_BAR_SLOT` insertion (so a mirror-only bar container never shows the "Example
  Buff Name" placeholder); `hasActiveTimers` folds in the mirrored count; a new
  `elseif slot.isStolen` branch in the bar resolution block sets `bar.proc`, `resolvedSpellID`,
  `resolvedLabel` from the slot directly, falling through to the existing no-timer placeholder
  rendering (no fill, no countdown).
- Confirmed the hot-path budget held: table-constructor count in `ns:UpdateDisplay`,
  `RenderBarContainer`, `RenderIconContainer` combined is unchanged at 2 (both pre-existing
  `proc = { spellID = ..., label = ..., key = ... }` placeholder lines, filed for Phase 43). No
  `C_CooldownViewer` call and no mirror-rebuild call anywhere in `Display.lua`.

## Task Commits

1. **Task 1: render mirrored slots in `RenderIconContainer`** - `e1e8a9a` (feat)
2. **Task 2: render mirrored slots in `RenderBarContainer`** - `a17749a` (feat)
3. **Task 3: hot-path audit and format** - `93542b4` (chore)

**Plan metadata:** not committed by this agent — orchestrator owns STATE.md/ROADMAP.md and the
final metadata commit.

## Files Created/Modified
- `Display.lua` - mirror-slot append and `isStolen` resolution branches in both render functions;
  `hasActiveIcons`/`hasActiveTimers` visibility folds; three comment wording fixes so acceptance
  greps count only code, not prose.

## Decisions Made
- Mirrored essential/utility slots need zero new cooldown-handling code — `trackerType ==
  "cooldown"` alone routes them into the existing Phase 38 `ApplyCooldownSlot` branch, exactly as
  the plan's Approach table specified. Verified `ApplyCooldownSlot` grep count is unchanged (one
  definition, one call site) both before and after this plan.
- Bar mirror gate uses `slot.isStolen`, not `slot.spellID`, to avoid rerouting the Trinket/Pot
  meta-tracker resolution path (Phase 27) that every DB entry's `spellID` field would otherwise
  collide with.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Comment prose matched the plan's own exact-count acceptance greps**
- **Found during:** Task 1, recurring in Tasks 2 and 3
- **Issue:** Three comments I wrote contained the literal strings `ns.stealSlots`,
  `ns:RefreshStealMirror`, and `gate on isStolen`. The plan's acceptance criteria use `grep -c`
  and `grep -n` on those exact identifiers expecting a precise count of *code* sites (2 for
  `stealSlots`, 3 for `isStolen`, 0 for `RefreshStealMirror`). My prose inflated each count by one,
  which would have failed the plan's own verification greps even though the code was correct.
- **Fix:** Reworded the three comments to describe the same thing without repeating the literal
  identifier text (e.g., "StealMode.lua's event-driven mirror refresh" instead of
  "`ns:RefreshStealMirror`", "gate on this mirror flag" instead of "gate on isStolen").
- **Files modified:** `Display.lua`
- **Verification:** Re-ran every acceptance grep from the plan after each fix; all match the
  plan's stated exact counts.
- **Committed in:** `93542b4` (bundled into Task 3's audit commit, since it's exactly the kind of
  thing a hot-path/acceptance audit exists to catch)

---

**Total deviations:** 1 auto-fixed (1 bug — self-inflicted comment wording, not a plan defect)
**Impact on plan:** No scope creep. The render-path code itself matched the plan exactly on first
write; only comment text needed adjustment to stop shadowing the plan's own grep-based
verification.

## Issues Encountered
None beyond the comment-wording self-correction above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `Display.lua` now reads `ns.stealSlots` unconditionally in both render functions; with steal
  mode off (the only state reachable before Plan 03), every array is empty and the visible
  behaviour of the addon is unchanged — `/tbt` still shows the four containers exactly as before.
- Plan 03 (hide/restore + the toggle) can turn `ns.db.stealMode` on without touching `Display.lua`
  at all — the render path already handles a populated `ns.stealSlots` correctly.
- No Blizzard CDM frame was read, written, parented into, or had a method called on it anywhere in
  this plan's diff — `Display.lua`'s only new reads are of `ns.stealSlots`, a plain TBT table.

---
*Phase: 40-cdm-steal-mode*
*Completed: 2026-09-21*
