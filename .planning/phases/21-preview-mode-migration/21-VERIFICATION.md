---
phase: 21-preview-mode-migration
verified: 2026-04-21T00:00:00Z
status: passed
score: 4/4 must-haves verified
re_verification:
  previous_status: APPROVED
  previous_score: 4/4
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 21: Preview Mode Migration Verification Report

**Phase Goal:** Rewrite StartAllPreviewTimers and ClearAllTimers to additive-preview pattern with separate ns.previewTimers table. Fixes trinket/pot 0-second preview (LIFE-03) AND mid-CDM real cast loss (bug from Phase 20 verify).
**Verified:** 2026-04-21
**Status:** passed
**Re-verification:** Yes — goal-backward verification layered on top of Plan 21-02 APPROVED in-game record

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | StartAllPreviewTimers produces preview procs for trinket/pot/lust with non-zero durations | VERIFIED | ns:GetDisplayInfoForKey is the sole data source; provider returns real durations post-Phase-20; user 9-test matrix step 2 confirmed |
| 2 | Preview count equals or exceeds old behavior for user-created buffs (no regression) | VERIFIED | Function iterates ns.db.trackedBuffs for all non-hidden keys; user step 8 confirmed no regression |
| 3 | Exiting preview clears preview procs correctly — no ghost bars | VERIFIED | ClearAllTimers wipes only ns.previewTimers; ns.activeTimers untouched; user step 3 confirmed |
| 4 | Mid-CDM real casts persist after CDM close (architectural fix) | VERIFIED | ClearAllTimers does not touch ns.activeTimers; user steps 5-7 confirmed |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BuffEngine.lua` | Rewritten additive-preview lifecycle | VERIFIED | ns.previewTimers = {} declared (count=1); wipe(ns.previewTimers) in 2 locations; functions rewritten |
| `CDMTab.lua` | 3 call sites updated to drop ns.previewActive disjunct | VERIFIED | ns.previewActive count=0; if ns.configOpen then count=3; ns:StartAllPreviewTimers() count=5 |
| `.planning/phases/21-preview-mode-migration/21-VERIFICATION.md` | In-game verification record | VERIFIED | File exists; 56 lines; APPROVED status; all 4 SC marked |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| StartPreview -> ns:StartAllPreviewTimers | ns.previewTimers populated via ns:GetDisplayInfoForKey | unchanged call site; additive internal | WIRED | awk confirms 1 call to ns:GetDisplayInfoForKey(key) in function body; 1 write to ns.previewTimers[key] |
| Mid-CDM cast -> provider OnTrigger -> ns.activeTimers[key] | Display sees real proc via GetActiveTimers merge | real-priority merge overrides preview for same key | WIRED | GetActiveTimers iterates both tables; real loop overwrites preview for same key; pairs(ns.previewTimers)=1, pairs(ns.activeTimers)=1 |
| StopPreview -> ns:ClearAllTimers | only ns.previewTimers wiped; ns.activeTimers untouched | preview-scoped wipe | WIRED | ClearAllTimers body: wipe(ns.previewTimers)=1, wipe(ns.activeTimers)=0, no savedPreviewTimers ref |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| BuffEngine.lua ns:StartAllPreviewTimers | ns.previewTimers[key] | ns:GetDisplayInfoForKey(key) — delegates to provider (TrinketProvider, PotProvider, LustProvider, user spells) | Yes — Phase 20 established providers return real durations | FLOWING |
| BuffEngine.lua ns:GetActiveTimers | merged result | ns.previewTimers + ns.activeTimers | Yes — real procs from OnTrigger handlers win same-key collisions | FLOWING |

### Behavioral Spot-Checks

Skipped — requires running WoW client. Covered by human verification matrix (Plan 21-02 Task 2, 9-step matrix, all PASSED per user report 2026-04-21).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| LIFE-03 | 21-01-PLAN.md, 21-02-PLAN.md | Preview mode produces correct non-zero duration preview procs for all buff types including trinket/pot | SATISFIED | REQUIREMENTS.md line 62: "LIFE-03 \| Phase 21 \| Complete"; structural grep + user in-game confirmation |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Providers.lua | 447-448 | Historical comment references ns.previewActive | Info | Comments only; grep -E "^[^-].*ns\.previewActive" Providers.lua returns 0 — no live code reads the deleted flag |

No blockers or warnings. The worktree at `.claude/worktrees/agent-ad696cb1/` contains old code with ns.previewActive but that is an archived agent workspace, not the working tree.

### Human Verification Required

None — all automated checks passed and the 9-step in-game matrix was executed and approved by user on 2026-04-21. Full matrix record preserved in Plan 21-02 Task 2 `<how-to-verify>` block.

### Gaps Summary

No gaps. All 4 success criteria satisfied. LIFE-03 closed. PITFALL-4 (0-second trinket/pot preview) retired.

## Structural Check Results (goal-backward)

All checks match expected values from Plan 21-01 verification block:

| Check | Expected | Actual | Pass |
|-------|----------|--------|------|
| `ns.previewTimers = {}` in BuffEngine.lua | 1 | 1 | YES |
| `ns.previewActive` in BuffEngine.lua | 0 | 0 | YES |
| `savedPreviewTimers` in BuffEngine.lua | 0 | 0 | YES |
| `wipe(ns.previewTimers)` in BuffEngine.lua | 2 | 2 | YES |
| `function ns:StartAllPreviewTimers` in BuffEngine.lua | 1 | 1 | YES |
| `function ns:ClearAllTimers` in BuffEngine.lua | 1 | 1 | YES |
| `function ns:GetActiveTimers` in BuffEngine.lua | 1 | 1 | YES |
| `function ns:OnUnitAura` in BuffEngine.lua | 1 | 1 | YES |
| `if ns.previewActive then` in BuffEngine.lua | 0 | 0 | YES |
| `CURRENT_SCHEMA_VERSION = 3` in BuffEngine.lua | 1 | 1 | YES |
| `ns.previewActive` in CDMTab.lua | 0 | 0 | YES |
| `if ns.configOpen then` in CDMTab.lua | >=3 | 3 | YES |
| `ns:StartAllPreviewTimers()` in CDMTab.lua | 5 | 5 | YES |
| `ns.configOpen = true` in CDMTab.lua | 1 | 1 | YES |
| `ns.configOpen = false` in CDMTab.lua | 1 | 1 | YES |
| Providers.lua git status clean | clean | clean | YES |
| Core.lua git status clean | clean | clean | YES |
| Display.lua git status clean | clean | clean | YES |
| stylua --check BuffEngine.lua CDMTab.lua | exit 0 | exit 0 | YES |
| GetActiveTimers iterates ns.previewTimers | 1 | 1 | YES |
| GetActiveTimers iterates ns.activeTimers | 1 | 1 | YES |
| GetActiveTimers lazy-nil ns.previewTimers[key] | 1 | 1 | YES |
| GetActiveTimers lazy-nil ns.activeTimers[key] | 1 | 1 | YES |
| GetActiveTimers returns sorted list ascending | 1 | 1 | YES |
| ScanActiveTimersForCancellation does NOT iterate ns.previewTimers | 0 | 0 | YES |
| LIFE-03 status in REQUIREMENTS.md | Complete | Complete | YES |

## Phase Outcomes

- LIFE-03 — CLOSED (complete)
- PITFALL-4 (preview regression / 0-second trinket/pot bars) — RESOLVED
- Phase 20 mid-CDM real-cast-loss bug — FIXED as architectural side-effect of separate-tables design

## Next Phase

Phase 22: Display.lua Unification (DISP-01, DISP-03) — zero type-specific branches; single shared tooltip handler; wipe() accumulator pattern preserved.

---

_Verified: 2026-04-21_
_Verifier: Claude (gsd-verifier) — goal-backward pass layered on Plan 21-02 APPROVED in-game record_
