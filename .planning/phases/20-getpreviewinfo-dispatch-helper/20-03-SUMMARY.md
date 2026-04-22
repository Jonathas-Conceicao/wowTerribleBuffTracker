---
phase: 20-getpreviewinfo-dispatch-helper
plan: "03"
subsystem: verification
tags: [verification, providers, display-info, shims, dispatch]
dependency_graph:
  requires:
    - "Plan 20-01: ns:GetDisplayInfoForKey export; GetDisplayInfo on all 4 providers; atRest cache + RefreshAtRest on Trinket/Pot"
    - "Plan 20-02: Thin ns:RefreshMetaIcons wrapper; three backwards-compat shims via ns:GetDisplayInfoForKey"
  provides:
    - "20-VERIFICATION.md — APPROVED in-game record for Phase 20 (PROV-04 + PROV-F3)"
    - "PROV-04 closed: provider-side GetDisplayInfo + ns:GetDisplayInfoForKey dispatch confirmed correct in-game"
    - "PROV-F3 closed: provider-owned RefreshAtRest confirmed correct in-game"
  affects:
    - "Phase 21 (StartAllPreviewTimers migration / LIFE-03 — deferred 0s preview fix)"
tech_stack:
  added: []
  patterns:
    - "Human verification gate: deploy + in-game approval before closing requirements"
key_files:
  created:
    - path: .planning/phases/20-getpreviewinfo-dispatch-helper/20-VERIFICATION.md
      changes: "APPROVED in-game verification record covering all 9 test steps and documenting 2 known-deferred behaviors"
  modified: []
key_decisions:
  - "Mid-CDM cast loss is PRE-EXISTING (savedPreviewTimers not refreshed mid-preview); not a Phase 20 regression; fix deferred to Phase 21 / LIFE-03 additive-preview rewrite"
  - "PROV-F3 marked complete: provider-owned atRest cache and RefreshAtRest absorption into Phase 20 confirmed correct in-game"
patterns-established: []
requirements-completed: [PROV-04]
duration: 10min
completed: "2026-04-21"
---

# Phase 20 Plan 03: Deploy + Human Verify Summary

**In-game verification APPROVED: all 4 providers dispatch correctly through ns:GetDisplayInfoForKey shim chain; zero visual regression vs Phase 19; PROV-04 and PROV-F3 closed.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-04-21
- **Tasks:** 3 (Task 1: preflight + deploy; Task 2: human-verify checkpoint [APPROVED]; Task 3: write 20-VERIFICATION.md)
- **Files modified:** 1 (20-VERIFICATION.md created)

## Accomplishments

- Deployed Phase 20 code via install.bat; zero Lua errors on reload
- All 9 human-verify steps passed (user: "ok, phase 20 looks good then")
- 20-VERIFICATION.md written with APPROVED status covering all 4 success criteria
- PROV-04 closed — ns:GetDisplayInfoForKey dispatch confirmed correct in production
- PROV-F3 closed — provider-owned RefreshAtRest confirmed correct; ns:RefreshMetaIcons thin wrapper confirmed in-game

## Task Commits

1. **Task 1: Deploy Phase 20 changes to WoW** — `0c02e18` (preceding plan metadata commit; install.bat ran successfully)
2. **Task 2: Human verification checkpoint** — APPROVED by user (no commit — human gate)
3. **Task 3: Write 20-VERIFICATION.md** — documented in this plan metadata commit

## Files Created/Modified

- `.planning/phases/20-getpreviewinfo-dispatch-helper/20-VERIFICATION.md` — APPROVED in-game verification record

## Decisions Made

None new — followed plan as specified. Two notable findings documented:

1. **PROV-04 marked complete after Wave 1 linter acceptance** — the plan notes "PROV-04 marked complete (already marked by linter after Wave 1)" which is consistent with the structural grep acceptance criteria all passing.

2. **PROV-F3 absorbed into Phase 20 scope** — PROV-F3 (provider-owned RefreshAtRest) was pulled forward from future phases and completed in Plan 20-01. In-game verification confirms it is correct. Both PROV-04 and PROV-F3 are now closed.

## Deviations from Plan

None — plan executed exactly as written. The verification checkpoint was approved without regressions.

## Known Deferred Behaviors (NOT regressions)

### 1. Trinket/pot preview bars show 0-second duration

PITFALL-4 / LIFE-03. StartAllPreviewTimers is untouched in Phase 20 per decision D-22. Fix lands in Phase 21 (additive-preview rewrite). Confirmed pre-existing, consistent with Phase 17-18 verification records.

### 2. Real casts made mid-CDM are lost when CDM closes (PRE-EXISTING)

Discovered during in-game verification. Root cause: `savedPreviewTimers` is written once when CDM opens (StartAllPreviewTimers) and is NOT refreshed mid-preview after a real cast. When CDM closes, active timers restore from `savedPreviewTimers`, overwriting the mid-CDM cast proc with the preview snapshot.

**This is NOT a Phase 20 regression.** The GetDisplayInfo refactor does not touch StartAllPreviewTimers or the preview save/restore path. The bug predates Phase 20.

**Fix scope:** Phase 21 / LIFE-03 — the additive-preview rewrite ensures providers run normally during preview (no savedPreviewTimers snapshot), so real procs are never clobbered when CDM closes.

## Issues Encountered

None during code execution. The pre-existing mid-CDM cast loss bug was discovered during verification but confirmed out of scope for Phase 20.

## Next Phase Readiness

Phase 21: Preview Mode Migration (LIFE-03) is unblocked.

- Provider layer is complete: all 4 providers have correct GetDisplayInfo returning non-zero durations
- ns:GetDisplayInfoForKey dispatch helper is exported and verified
- StartAllPreviewTimers is the only remaining consumer using the old at-rest resolution path
- Phase 21 will rewrite StartAllPreviewTimers to call providers directly, fixing both the 0-second preview bars (PITFALL-4) and the mid-CDM cast loss bug (LIFE-03)

---
*Phase: 20-getpreviewinfo-dispatch-helper*
*Completed: 2026-04-21*
