---
phase: 57-detailed-tracking-visibility-cross-spell-rules
plan: 03
subsystem: ui
tags: [wow-addon, lua, visibility-modes, display, cdm]

# Dependency graph
requires:
  - phase: 57-detailed-tracking-visibility-cross-spell-rules
    plan: 02
    provides: "ns:VisibilityGate(key, entry) / ns:VisibilityShowsIn(containerKey) / ns.visibilityKeys, the allocation-free visibility predicate and watch list this plan calls"
provides:
  - "SlotDraws (Display.lua) gating a slot's draw decision through ns:VisibilityGate at the same position as RenderIconContainer's own hide branch"
  - "RenderIconContainer wired: a hide branch for gate == false between the engine-merged branch and the timer branch, gate == true added to the placeholder condition (the 'absent' reminder icon), and ns:VisibilityShowsIn(def.key) added to hasActiveIcons"
  - "RenderBarContainer wired: the showPlaceholders walk and the timers-only loop both gate on ns:VisibilityGate, a reminder-append block loops ns.visibilityKeys to draw idle 'present'/'absent' bars as the existing placeholder bar, and ns:VisibilityShowsIn(def.key) added to hasActiveTimers"
affects: ["57-04 (already landed the entry.visibility dialog field this plan makes visually meaningful)", "any future Display change to SlotDraws / RenderIconContainer / RenderBarContainer must keep the gate call in the documented position"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One allocation-free predicate call per render-loop slot, held in a local named `gate`, read identically at all four call sites (SlotDraws, the icon hide/placeholder branches, the bar showPlaceholders/timers-only/reminder-append blocks)"
    - "A gated-off tracker only disappears when both ns.configOpen and Edit Mode are closed, so a hidden tracker can always be found and moved -- the same escape hatch the plan's cooldown-slot precedent already used"

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "The bar-path reminder append is a second small loop over ns.visibilityKeys placed after the timers-only loop, not a merge into the showPlaceholders walk -- the plan's instruction ('append the ones with no timer running... after that loop') keeps the timers-only branch's existing unsorted ordering (live bars first, reminders after) intact"
  - "No new Lua table constructor ({) was introduced in any of the three edited functions -- the reminder-append block reuses ns.visibilityKeys and ns.db.trackedBuffs, matching the plan's brace-count gate against commit 0459903"

patterns-established:
  - "Visibility-gate wiring at a render call site: `local gate = ns:VisibilityGate(key, entry)` once per slot, then `gate == false` as an early hide (bypassed by ns.configOpen/Edit Mode) and `gate == true` as a forced-draw override, matching the shape both the icon and bar paths now share"

requirements-completed: [DTRK-03]

# Metrics
duration: ~15min
completed: 2026-09-28
---

# Phase 57 Plan 03: Display Wiring Summary

**Wired Plan 02's single `ns:VisibilityGate`/`ns:VisibilityShowsIn` predicate into the four Display.lua call sites named in 57-CONTEXT (SlotDraws, the icon hide/placeholder branch chain, and the bar showPlaceholders/timers-only/reminder-append blocks), so "present" and "absent" visibility modes now actually change what icons and bars draw, with the "absent" reminder beating `hideWhenInactive`.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-09-28T17:30:00Z
- **Tasks:** 2
- **Files modified:** 1 (Display.lua)

## Accomplishments
- `SlotDraws` calls `ns:VisibilityGate(entry.key, entry)` right after its merged early return: `gate == false` (outside `ns.configOpen`/Edit Mode) returns `false`, `gate == true` returns `true`, and a `nil` gate falls through to the unchanged existing return expression -- so "always" mode is a byte-for-byte no-op.
- `RenderIconContainer`'s per-slot branch chain gained one new branch, `elseif gate == false and not (ns.configOpen or iconEditing) then icon:Hide() end`, placed between the engine-merged branch and `elseif timer then` so a gated-off tracker hides even with a live timer or as a cooldown slot. The existing placeholder branch's condition now starts `gate == true or entry.isMerged or ...`, so an "absent" tracker draws the placeholder's full-colour, no-sweep, no-timer look -- the reminder -- even when `hideWhenInactive` would otherwise hide an idle icon.
- `hasActiveIcons` and `hasActiveTimers` (icon and bar containers respectively) each gained `or ns:VisibilityShowsIn(def.key)`, so a container holding only a gated reminder or a "present" tracker is not hidden by `hideWhenInactive`.
- `RenderBarContainer`'s `showPlaceholders` walk (the `pairs(ns.db.trackedBuffs)` branch) now skips a gated-off entry unless `ns.configOpen or barEditing`. Its timers-only branch (the `hideWhenInactive`-active path) drops a gated-off live timer the same way, then appends every idle "present"/"absent" tracker filed in this container (`ns.visibilityKeys`, `activeByKey[key] == nil`, `ns:VisibilityGate(key, entry) == true`) as a no-timer slot -- the existing empty placeholder bar branch draws it, giving bars the same reminder look icons get.
- Both render functions remain allocation-free versus commit `0459903`: brace count (`{`) unchanged in `SlotDraws`, `RenderIconContainer` and `RenderBarContainer`; no new line mentions `OnUpdate`; `node scripts/aura-read-gate.js` still reports PASS (Display.lua reads no aura -- the predicate is the only source of state).

## Task Commits

Each task was committed atomically:

1. **Task 1: Icon path -- SlotDraws, the icon branch chain and icon container activity** - `40d9115` (feat)
2. **Task 2: Bar path -- the bar slot filter and bar container activity** - `2412cb7` (feat)

_No plan-metadata commit -- the orchestrator owns STATE.md/ROADMAP.md updates for this plan._

## Files Created/Modified
- `Display.lua` - `SlotDraws` gated through `ns:VisibilityGate`; `RenderIconContainer`'s per-slot chain gained a hide branch and an "absent" reminder placeholder condition, plus `ns:VisibilityShowsIn(def.key)` in `hasActiveIcons`; `RenderBarContainer`'s `showPlaceholders` walk and timers-only loop both gate on `ns:VisibilityGate`, a new reminder-append block loops `ns.visibilityKeys`, plus `ns:VisibilityShowsIn(def.key)` in `hasActiveTimers`

## Decisions Made
- The bar-path reminder append is a second loop over `ns.visibilityKeys`, placed after the timers-only loop and before `AppendMergedSlots`, rather than folded into the `showPlaceholders` walk -- it only needs to run in the branch that already drops idle bars, and appending (rather than sorting into) the reminder keeps the timers-only branch's existing unsorted live-bars-first ordering.
- No new Lua table constructor was introduced in any of the three edited functions, keeping each function's `{` count identical to commit `0459903` per the plan's allocation gate.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Verification

Both task automated gates passed in full on first run:
- Task 1: `SlotDraws`'s `ns:VisibilityGate`/`gate == false`/`gate == true` shape and ordering (merged return, then the gate, then the `ns:IsCooldownSlotEntry` term); `RenderIconContainer`'s `ns:VisibilityShowsIn(def.key)`, per-slot `local gate = ns:VisibilityGate(entry.key, entry)`, the new hide branch in the correct chain position, and the placeholder condition's `gate == true or entry.isMerged` prefix; zero new `{` in either function versus `0459903`; no added `OnUpdate` mention; stylua clean; CRLF/EOL gates.
- Task 2: `RenderBarContainer`'s `ns:VisibilityShowsIn(def.key)` in `hasActiveTimers`; at least three `ns:VisibilityGate(` calls (showPlaceholders walk, timers-only loop, reminder-append condition); the reminder-append block's `ns.visibilityKeys`/`activeByKey[key] == nil`/`ns:VisibilityGate(key, entry) == true` shape sitting after `local showPlaceholders = ` and before `AppendMergedSlots(merged, mergedCount)`; zero new `{` versus `0459903`; no added `OnUpdate` mention; stylua clean; CRLF/EOL gates.

Plan-level verification also confirmed: `node scripts/aura-read-gate.js` reports PASS (10 reads, 3 allowlisted readers -- unchanged, Display.lua contributes none); `node scripts/migrate-dryrun.js --selftest` reports 7 cases (unchanged).

In-game verification -- a "present" tracker's icon/bar actually appearing when its aura is sighted (including from another player's cast) and disappearing when it drops; an "absent" tracker drawing the full-colour reminder icon or the empty placeholder bar the instant a cross-spell rule marks it absent, beating `hideWhenInactive`; Edit Mode and the open CDM settings still showing every hidden tracker so it can be found and moved -- requires a live WoW client and is human verification; no WoW client is available in this environment.

## Next Phase Readiness
- DTRK-03 is now complete end to end: Plan 02's engine (the aura-state cache, the predicate, the aura-driven start) and this plan's Display wiring together make "always"/"present"/"absent" all draw correctly, with "always" unchanged from pre-Phase-57 behaviour.
- No blockers. The next phase-57 work (if any) is cross-spell rules (DTRK-05) and the cooldown-tracker "Reset + visibility" work, both independent of this plan's Display changes.

## Self-Check: PASSED

Commits `40d9115` and `2412cb7` found in `git log --oneline -4`. `Display.lua` modifications confirmed on disk via both task automated verify gates re-run to completion with `echo ok` as the final line. `node scripts/aura-read-gate.js` reports PASS; `node scripts/migrate-dryrun.js --selftest` reports 7 cases.

---
*Phase: 57-detailed-tracking-visibility-cross-spell-rules*
*Completed: 2026-09-28*
