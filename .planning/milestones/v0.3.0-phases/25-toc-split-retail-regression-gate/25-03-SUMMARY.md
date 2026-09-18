---
phase: 25-toc-split-retail-regression-gate
plan: 03
subsystem: verification/release-process
tags: [in-game-verification, wow-addon, blocking-checkpoint, wow-forever]

# Dependency graph
requires:
  - phase: 25-toc-split-retail-regression-gate (plan 01)
    provides: "TerribleBuffTracker_Mainline.toc and TerribleBuffTracker_Camelot.toc to load-test"
  - phase: 25-toc-split-retail-regression-gate (plan 02)
    provides: "TOC drift guard and CLAUDE.md documentation (unrelated to the in-game gate itself, but completes the phase's filesystem work)"
provides:
  - "25-INGAME-VERIFICATION.md — human-run checklist covering both Phase 25 in-game gates, with an empty results table"
affects: [26-install-tooling, 27-providers-at-rest, 29-pkgmeta-split]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Blocking human-verify checkpoint artifact: status ships NOT RUN, every result cell empty, automated grep gate fails the task if any agent-authored PASS/FAIL marking appears"

key-files:
  created: [.planning/phases/25-toc-split-retail-regression-gate/25-INGAME-VERIFICATION.md]
  modified: []

key-decisions:
  - "D-06: true dual gate — retail load (VER-01/TOC-01) and Forever load (TOC-02) both block Phases 26/27/29"
  - "D-08: Forever smoke-test bar deliberately narrow — appears in AddOns list + loads with no Lua error at login, nothing more"
  - "D-11: on Forever load failure, stop and report with four named diagnostics; never auto-try another suffix"

patterns-established: []

requirements-completed: []

# Metrics
duration: 12min
completed: 2026-09-18
---

# Phase 25 Plan 03: In-Game Verification Checklist Summary

**Wrote the human-run checklist for Phase 25's dual in-game load gate and stopped at the blocking checkpoint — no client was launched, no verdict was recorded, and none may be by an agent.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-18 (executor session, continued from plan 25-02)
- **Completed:** 2026-09-18 (Task 1 only; Task 2 is the blocking checkpoint)
- **Tasks:** 1 of 2 completed (Task 2 is `checkpoint:human-verify`, by design not completable by an agent)
- **Files modified:** 1 (created)

## Accomplishments
- `25-INGAME-VERIFICATION.md` written covering: manual deploy of all ten shared files into both clients' AddOns folders (working around `install.bat`'s known-broken `.toc` copy line per D-10), the stale-TOC false-pass trap with an explicit deletion instruction, Gate 1 (retail, VER-01/TOC-01) steps and expected results per D-15, Gate 2 (Forever, TOC-02) with its deliberately narrow D-08 pass bar, the D-09 explicit non-failures list, the full D-11 failure protocol with all four diagnostics and the pitfall-3 triage table reproduced inline, and five research observations to capture opportunistically (Section E).
- Every result cell in Section F's table ships empty; the sign-off block's verdict fields are blank underscores. No `PASS`/`FAIL` marking of any kind exists anywhere in the artifact — verified by the plan's own negative grep gate before commit.
- Task 1 committed in isolation (`8c5173e`); Task 2 is the mandatory blocking checkpoint and has not been attempted.

## Task Commits

1. **Task 1: Write the in-game verification checklist artifact** - `8c5173e` (docs)

Task 2 (`checkpoint:human-verify`, gate="blocking") is intentionally not committed — it produces no file changes, only a stop.

## Files Created/Modified
- `.planning/phases/25-toc-split-retail-regression-gate/25-INGAME-VERIFICATION.md` - Human-run checklist: deploy steps, Gate 1 (retail) steps, Gate 2 (Forever) steps, D-09 non-failures, D-11 failure protocol with four diagnostics and a symptom-triage table, Section E research observations, and an empty Section F results table with sign-off block.

## Verification Evidence

All of the plan's automated `<verify>` assertions for Task 1 passed:
- File exists, has ≥80 non-blank lines (175 counted).
- Contains `NOT RUN`, both TOC filenames, `_classic_beta_`, `_retail_`, `scriptErrors 1`, `GetAddOnInfo`, `.flavor.info`, `tbt_icon_64x64.blp`, `CDMTab.lua`.
- Contains both a "do not" instruction and a reference to `_Vanilla` (the forbidden-fallback-suffix warning in Section D).
- The negative grep `! grep -qE '(Gate 1|Gate 2)[^|]{0,24}(PASS|FAIL)'` passed — no agent-authored verdict exists anywhere in the file.
- `git diff --name-only HEAD~1 HEAD` confirms the artifact is the sole file in its commit.

## Decisions Made
- Followed D-06 through D-11 and D-15 exactly as locked in `25-CONTEXT.md` — no reinterpretation of the gate's scope, the Forever pass bar, or the failure protocol.
- Did not attempt to fix `scripts/install.bat`'s broken `.toc` copy line — that is explicitly Phase 26's INST-04 work; the checklist works around it with a manual copy per D-10, exactly as the plan specifies.

## Deviations from Plan

None - plan executed exactly as written for Task 1. Task 2 is executed exactly as specified: stopped, no simulation, no partial credit, no verdict written.

## Issues Encountered

None.

## User Setup Required

None in the traditional sense — the "setup required" here is the entire point of this plan: a human must physically deploy the addon to two real WoW clients and observe them, which is described step-by-step in `25-INGAME-VERIFICATION.md`.

## Deferred Questions

Carried forward verbatim per plan 25-03's `<deferred_questions>`:

1. **D-03 / research question 1** — if Forever rejects `## Category: Buffs & Debuffs, Combat`, adding a third allowlisted divergence line is the user's decision. Section E of the checklist captures the observation; no fix is applied on the spot.
2. **Research question 4** — if `_classic_beta_\.build.info` no longer derives to 16001, the TOC value is stale. The guard (from plan 25-02) asserts the `16xxx` range, so a bump would not fail it, but the exact value is a user decision.
3. **Retail deploy is broken until Phase 26** — `install.bat` cannot copy either TOC (INST-04). The checklist works around it manually per D-10; confirm this is acceptable rather than pulling INST-04 forward.
4. **Forever deploy target at GA** — `_classic_beta_` is the beta piggyback path; `FTOOL-02` covers a dedicated `_forever_` folder if one appears.

## Gate Status — OPEN, BLOCKING

**The in-game gate is OPEN. VER-01, TOC-01's in-game half, and TOC-02 are NOT verified. No game
client was launched by this agent — none can be.** `25-INGAME-VERIFICATION.md` is the handoff
artifact; a human must run both gates and fill in Section F themselves.

**Phases 26, 27, and 29 remain blocked** until both verdicts in Section F read PASS (D-06). Phase
27's code-level work (`Providers.lua` PAR-01 fix) is already code-complete and statically
verified per STATE.md's accumulated context, but its live-verified status still depends on this
gate resolving.

## Next Phase Readiness
- Filesystem work for Phase 25 (plans 01 and 02) is complete, committed, and self-checked.
- The phase cannot be marked complete. It stays open pending a human running
  `25-INGAME-VERIFICATION.md` end to end and recording both verdicts.
- No further agent action is possible or appropriate on this phase until the human responds with
  the two verdicts (or a Gate 2 failure report with its four required diagnostics).

---
*Phase: 25-toc-split-retail-regression-gate*
*Completed: 2026-09-18 (Task 1 only — phase remains open at the blocking checkpoint)*

## Self-Check: PASSED

- FOUND: .planning/phases/25-toc-split-retail-regression-gate/25-INGAME-VERIFICATION.md
- FOUND: 8c5173e
