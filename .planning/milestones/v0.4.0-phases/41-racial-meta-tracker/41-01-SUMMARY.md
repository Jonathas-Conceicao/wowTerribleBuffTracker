---
phase: 41-racial-meta-tracker
plan: 01
subsystem: buff-tracking
tags: [wow-addon, lua, secret-values, cast-driven-tracking, cooldown-manager]

# Dependency graph
requires:
  - phase: 19-lust-provider
    provides: LustProviderMixin shape (meta tile, per-character resolution, provider registration)
  - phase: 27.1-meta-catalog-resolution
    provides: HasResolvableCatalog / UnresolvedDisplayInfo pattern for "greyed, not hidden" tiles
provides:
  - RacialProviderMixin with cast-driven 3-stack Eureka! tracker (spell 1259817, gnome raceID 7)
  - ns:EndTimer(key) — the general early-expiry lifecycle primitive
  - "racial" registered in ns.providers, keyToProvider, and ns.SUGGESTED_KEYS
affects: [41-02-display-stack-widget, 41-03-cdm-suggested-tile]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cast-driven mutable-proc tracking: proc.stacks mutated in place inside ns.activeTimers,
       the only mutable proc field in the codebase, safe because ns:GetActiveTimers copies
       references and nothing else writes the field."
    - "Dual-ended timer lifecycle: expiresAt backstop (never touched after grant) and
       ns:EndTimer early-removal coexist without either knowing about the other."

key-files:
  created: []
  modified:
    - Providers.lua (RacialProviderMixin, RACIAL_SPELLS, ResolveRacial, registration/dispatch)
    - BuffEngine.lua (ns:EndTimer, SUGGESTED_KEYS, preview stacks passthrough)

key-decisions:
  - "RACIAL_SPELLS keyed by numeric raceID (UnitRace's third return), not raceFile string, so a
     capitalisation miss cannot silently defeat resolution."
  - "Racial proc carries no cancellation-list field by construction, not by a guard, so
     ScanActiveTimersForCancellation can never touch an aura the addon isn't allowed to read."
  - "CastSpendsStack accepts the user's 2026-09-20 over-consumption decision verbatim: unknown
     and harmful-but-harmless casts (Frost Nova, Polymorph) both qualify. No narrowing added."
  - "GetDisplayInfo memoises its return table after first build (departs from LustProvider's
     always-fresh style) because the placeholder render path calls it every frame."

patterns-established:
  - "Comments documenting a field's deliberate absence are placed in the mixin's header block,
     not inline in the function body, when a plan's acceptance grep forbids the literal field
     name inside that function — keeps the design rationale documented without gaming the check."

requirements-completed: [RACE-02, RACE-03]

# Metrics
duration: 7min
completed: 2026-09-21
---

# Phase 41 Plan 01: Racial Provider & Eureka! Stack Engine Summary

**Cast-driven Eureka! stack tracker (spell 1259817, gnome raceID 7) with a 15s backstop timer and early-expiry removal via a new `ns:EndTimer` lifecycle primitive — invisible until Plan 03 renders the tile.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-09-21T16:05:00-03:00 (approx)
- **Completed:** 2026-09-21T16:06:08-03:00
- **Tasks:** 4 (3 code tasks + 1 format/check task, folded into the two code commits)
- **Files modified:** 2

## Accomplishments
- `RacialProviderMixin` added to `Providers.lua`: one meta tile resolved per-character by numeric `raceID`, following `LustProviderMixin`'s shape, with `RACIAL_SPELLS` carrying exactly the one Eureka! entry this milestone ships
- Cast-driven stack engine productionised from the validated `tools/TBTProbe/Probe.lua` prototype: granting cast starts a 3-stack/15s proc, each qualifying cast decrements it, hitting zero calls the new `ns:EndTimer("racial")`
- `ns:EndTimer(key)` added to `BuffEngine.lua` as a general lifecycle primitive alongside the existing `ns:GetActiveTimers` backstop expiry — the two endings never reference each other
- `"racial"` wired into `ns.providers`, `keyToProvider`, and `ns.SUGGESTED_KEYS`; preview procs now carry `stacks` so a supported racial previews at full stack count in the CDM tab

## Task Commits

1. **Task 1+2: `Providers.lua` — catalogue, resolution, `RacialProviderMixin`, registration/dispatch** - `a417f20` (feat)
2. **Task 3: `BuffEngine.lua` — `ns:EndTimer`, `SUGGESTED_KEYS`, preview stacks passthrough** - `2f901b5` (feat)

Task 4 (format and static check) ran as part of both commits — `stylua` (no flags) formatted the working tree before each commit, `stylua --check .` confirmed clean.

**Plan metadata:** not committed — this SUMMARY.md is intentionally left uncommitted per orchestrator instructions.

## Files Created/Modified
- `Providers.lua` - `RACIAL_SPELLS`, `RACIAL_SUPPORTED_LINES`/`RACIAL_UNSUPPORTED_LINES`, `ResolveRacial()`, `RacialProviderMixin` (`GetEventInterests`, `CastSpendsStack`, `OnTrigger`, `GetDisplayInfo`, `HasResolvableCatalog`), `RacialProvider` registered in `ns.providers` (position 4, before `UserSpellProvider`) and `keyToProvider.racial`
- `BuffEngine.lua` - `ns.SUGGESTED_KEYS` gained `"racial"`; new `ns:EndTimer(key)`; `ns:StartAllPreviewTimers` preview proc gained `stacks = info.stacks`

## Decisions Made
- Placed the "no cancellation-list field" design comment in the `RacialProviderMixin` header block rather than inline inside `OnTrigger`, because the plan's own acceptance criterion (`grep -n 'aliveBuffs' Providers.lua` shows no occurrence inside `OnTrigger`) would otherwise be broken by literally documenting the field's absence at the point of absence. The design rationale is preserved in full; only its physical location moved to stay outside the function's line range. See "Deviations" below — this is a criterion-vs-code reconciliation, not a content change.
- No other deviations — plan executed as specified for RACIAL_SPELLS, ResolveRacial, OnTrigger, GetDisplayInfo, HasResolvableCatalog, ns:EndTimer, and the preview stacks passthrough.

## Deviations from Plan

**1. [Criterion reconciliation, not a Rule 1-4 fix] `aliveBuffs`-absence comment moved out of `OnTrigger`'s body**
- **Found during:** Task 2 (`RacialProviderMixin:OnTrigger`)
- **Issue:** The plan's task narrative says to "add a comment saying its absence is deliberate" for `aliveBuffs` at the granting-cast return, but the plan's own acceptance criteria says `grep -n 'aliveBuffs' Providers.lua` must show **no** occurrence inside `RacialProviderMixin:OnTrigger`. Writing the literal word "aliveBuffs" in a comment inside the function would satisfy the narrative but fail the criterion.
- **Fix:** Wrote the full design rationale (aura unreadable under restriction, proc excluded from cancellation by construction) in the `RacialProviderMixin` header block, above the mixin and function definitions, using the phrase "cancellation-list field" instead of the literal string "aliveBuffs". `OnTrigger` itself carries only a short pointer comment ("see the mixin header above for why") with no occurrence of the literal string. `grep -n 'aliveBuffs' Providers.lua` returns 8 hits, all in pre-existing Trinket/Pot/Lust code (lines 24-542), none inside `RacialProviderMixin:OnTrigger`.
- **Files modified:** `Providers.lua`
- **Verification:** `grep -n 'aliveBuffs' Providers.lua` — confirmed zero hits within `OnTrigger`'s line range (784-843).
- **Committed in:** `a417f20`

---

**Total deviations:** 1 (criterion reconciliation — not a bug fix, not scope creep; both the intent of the narrative and the letter of the acceptance criterion are satisfied)
**Impact on plan:** None on behavior. Design rationale is fully documented; only its location shifted by a few lines to satisfy an acceptance grep that the task narrative and the acceptance criteria would otherwise contradict.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `Providers.lua` and `BuffEngine.lua` are addon-load-clean; nothing in this plan is rendered yet by design (`41-03` renders the Suggested tile).
- Plan `41-02` (Display.lua, stack display) can proceed independently — it reads `proc.stacks` off the same `ns.activeTimers`/`ns.previewTimers` shape this plan writes.
- Plan `41-03` (CDMTab.lua Suggested tile) can consume `ns:GetDisplayInfoForKey("racial")` and `ns:IsSuggestedKeyResolvable("racial")` as-is — both already route through the new provider.
- No in-game verification was possible or attempted in this plan (by design — see plan's Verification section for the Phase 42 checklist this plan defers to, including the Forever gnome headline check).

---
*Phase: 41-racial-meta-tracker*
*Completed: 2026-09-21*
