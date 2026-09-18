---
phase: 24-cleanup
plan: 02
subsystem: performance-audit
tags: [hot-path, allocations, display-cache, unit-aura, dispatch, cancellation-scan, changelog-input]

# Dependency graph
requires:
  - phase: 22-display-lua-unification
    provides: Per-widget cachedSpellID/cachedIcon change-detection pattern (Path 1)
  - phase: 22-display-lua-unification
    provides: timer.aliveBuffs iteration replacing source branching (Path 3)
  - phase: 19-lustprovider-unit-aura-dispatch
    provides: Dispatcher-first UNIT_AURA flow via ns:DispatchEventToProviders (Path 2)
provides:
  - .planning/phases/24-cleanup/24-02-AUDIT.md — three-path hot-path audit findings
  - CHANGELOG Input (note_text) for Plan 24-03 to copy verbatim
  - Architectural confirmation that v0.2.4 refactor has zero per-frame/per-event allocation regressions
affects:
  - Plan 24-03 (CHANGELOG task reads the note_text value to decide whether to include a performance note)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Read-only static-inspection audits as phase artifacts (no code changes)"
    - "CHANGELOG Input section as single-source-of-truth handoff between audit plan and CHANGELOG plan"

key-files:
  created:
    - .planning/phases/24-cleanup/24-02-AUDIT.md
  modified: []

key-decisions:
  - "note_text: NONE — no performance note in v0.2.4 CHANGELOG per D-08 (no measurable improvement or regression across all three paths)"
  - "Two placeholder-proc table allocations in Display.lua (lines 467, 635) are acceptable — gated behind CDM-open/Edit-Mode conditions, not the gameplay hot path, and predate Phase 22 architecturally"
  - "C_UnitAuras.GetPlayerAuraBySpellID transient-table allocation on hit is pre-Phase-22 Blizzard-API behavior — not a regression"

patterns-established:
  - "AUDIT.md format: top-level heading, three Path sections each with Sites/Pattern/Finding subsections, one CHANGELOG Input section with note_text + Rationale"
  - "note_text contract: either 'NONE' literal or a single-sentence string; CHANGELOG-plan executor copies verbatim with zero interpretation"

requirements-completed: [DISP-04]

# Metrics
duration: 4min
completed: 2026-04-22
---

# Phase 24 Plan 02: Hot-Path Audit Summary

**Three-path read-only hot-path audit of v0.2.4's Display per-widget icon cache, UNIT_AURA dispatcher-first flow, and aliveBuffs cancellation scan — conclusion: zero per-frame/per-event allocation regressions vs. pre-refactor baseline; CHANGELOG note_text resolves to "NONE".**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-22T03:48:41Z
- **Completed:** 2026-04-22T03:52:48Z
- **Tasks:** 3
- **Files modified:** 1 (AUDIT.md only — zero Lua changes)

## Key Outputs

**For Plan 24-03 (CHANGELOG task):** Read `.planning/phases/24-cleanup/24-02-AUDIT.md` section `## CHANGELOG Input` and use:

```
note_text: "NONE"
```

This means Plan 24-03 OMITS the performance note entirely from the v0.2.4 CHANGELOG entry and keeps only the one-liner from D-07 ("Internal file reworking — no user-visible changes."). Rationale: all three audited hot paths show zero regression AND zero measurable improvement — the refactor was a code-organization win (DISP-01 / DISP-03) with runtime-equivalent behavior, so per D-08 ("performance note appended only if a measurable improvement or regression") no note is warranted.

## Accomplishments

- Enumerated all 12 `cachedSpellID`/`cachedIcon` sites in Display.lua (lines 478-644) and verified the change-detection pattern is allocation-free on the cache-hit gameplay path
- Verified `eventToProviders` is built exactly once at module load (Providers.lua:569-578) with zero write sites inside the per-event hot path (Providers.lua:590-607)
- Walked `LustProviderMixin:OnTrigger` no-match fast-path (Providers.lua:455-509) line-by-line; confirmed guard-based early returns with no allocations on the ~99% case
- Walked `ns:OnUnitAura` (BuffEngine.lua:329-365) line-by-line; confirmed vararg forwarding of `updateInfo` is heap-free
- Walked `ns:ScanActiveTimersForCancellation` (BuffEngine.lua:284-327) line-by-line; confirmed aliveBuffs iteration pattern performs the same number of Blizzard API calls as pre-Phase-22 source-branching code with no new allocations
- Flagged two placeholder-proc `bar.proc = { ... }` / `icon.proc = { ... }` allocations in Display.lua (lines 467, 635) as cold-path (CDM-open / Edit-Mode only), not a gameplay regression
- Produced `note_text: "NONE"` CHANGELOG Input for Plan 24-03 verbatim copy

## Task Commits

Each task was committed atomically with `--no-verify` per parallel-execution requirement:

1. **Task 1: Path 1 (Display per-widget icon cache)** — `0ceeb66` (docs)
2. **Task 2: Path 2 (UNIT_AURA dispatch flow)** — `c851754` (docs)
3. **Task 3: Path 3 (ScanActiveTimersForCancellation) + CHANGELOG Input** — `f03fc78` (docs)

Note: Task commits use `docs` type rather than `feat`/`refactor` because the plan is strictly read-only documentation — no Lua behavior changes.

## Files Created/Modified

- `.planning/phases/24-cleanup/24-02-AUDIT.md` — three-path audit findings + CHANGELOG Input section (created; grown across three commits)

## Decisions Made

- **note_text: "NONE"** — after auditing all three paths, no measurable improvement or regression was found. Per D-08 ("performance note appended only if a measurable improvement or regression"), the correct CHANGELOG action is to omit the performance note entirely. Plan 24-03's CHANGELOG entry for v0.2.4 remains the D-07 one-liner.
- **Placeholder-proc allocations (Display.lua:467, 635) classified as out-of-scope for regression reporting** — the two `bar.proc = { ... }` / `icon.proc = { ... }` table constructors only fire on the placeholder-render path (gated by `ns.configOpen` or `ns.editModeActive` or `not settings.hideWhenInactive`). This is NOT the gameplay hot path — it runs only when the CDM settings window is open or Edit Mode is active, both transient, out-of-combat UI states. The pattern is also architecturally present in pre-Phase-22 code (the placeholder-proc shim pattern predates the Phase 22 normalization). Not a v0.2.4 regression.
- **`C_UnitAuras.GetPlayerAuraBySpellID` return-table allocation classified as Blizzard-API-induced, not a TBT regression** — the API returns a NEW AuraData table on hit, which we discard immediately (used only as a truthy test). Pre-Phase-22 code performed the same API calls through source-branched code paths; Phase 22's aliveBuffs unification changed the dispatch shape but not the API call count.

## Deviations from Plan

None — plan executed exactly as written. All three tasks followed their `<action>` steps, all six acceptance criteria per task were met, and the plan-level verification grep counts all returned 1 (except `grep -c "## CHANGELOG Input"` which returned 2 because the intro paragraph references the section name in backticks; anchored-regex `grep -c "^## CHANGELOG Input$"` correctly returns 1, matching the plan's intent).

## Issues Encountered

- **Line-number drift from parallel agent 24-01:** At the time of execution, Plan 24-01 was running in parallel and had already modified BuffEngine.lua, CDMTab.lua, and Providers.lua (commit `f772010` dropped `ns.TRINKET_FALLBACK_ORDER`/`ns.POT_FALLBACK_ORDER` exports and renamed `ns:RefreshMetaIcons` → `ns:RefreshProvidersAtRest`). The line numbers quoted in the PLAN's `<interfaces>` block (e.g., "Providers.lua:592 DispatchEventToProviders", "BuffEngine.lua:367 OnUnitAura") were pre-24-01 snapshots. The audit uses CURRENT line numbers from a consistent snapshot taken at the start of this plan (post-24-01 Task 1 but before any further 24-01 work). Current line numbers: `ns:DispatchEventToProviders` at Providers.lua:590-607; `LustProviderMixin:OnTrigger` at Providers.lua:455-509; `ns:OnUnitAura` at BuffEngine.lua:329-365; `ns:ScanActiveTimersForCancellation` at BuffEngine.lua:284-327. All audit conclusions (dispatcher shape, per-widget caches, aliveBuffs loop) are architectural and survive 24-01's deletion-only edits.

## User Setup Required

None — this plan is purely an analysis artifact with no external service configuration.

## Next Phase Readiness

- **Plan 24-03 unblocked:** can read `.planning/phases/24-cleanup/24-02-AUDIT.md` `## CHANGELOG Input` section and copy `note_text: "NONE"` verbatim (meaning: no performance note added).
- **DISP-04 traceability:** one of the three plans for this requirement is complete; the other two (24-01 shim deletion, 24-03 CHANGELOG + release prep) handle the remaining cleanup scope.
- **No blockers for Plan 24-03 or milestone close.**

## Self-Check: PASSED

- FOUND: `.planning/phases/24-cleanup/24-02-AUDIT.md`
- FOUND: `.planning/phases/24-cleanup/24-02-SUMMARY.md`
- FOUND: commit `0ceeb66` (Task 1)
- FOUND: commit `c851754` (Task 2)
- FOUND: commit `f03fc78` (Task 3)
- VERIFIED: all three task commits contain zero Lua file changes (per parallel-execution coordination constraint)

---
*Phase: 24-cleanup*
*Completed: 2026-04-22*
