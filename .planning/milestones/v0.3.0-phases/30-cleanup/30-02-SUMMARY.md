---
phase: 30-cleanup
plan: 02
subsystem: docs
tags: [claude-md, project-md, rule-conflict, validated-list, forever-findings]

requires:
  - phase: 30-01
    provides: stylua.toml (referenced by the amended stylua rule)
provides:
  - CLAUDE.md/PROJECT.md rule conflict resolved in both documents
  - PROJECT.md's false parity-only claim retired
  - Six v0.3 Validated entries recorded, retail-open items marked open
  - Milestone's three substantive Forever findings recorded with citations
affects: [30-04]

tech-stack:
  added: []
  patterns: ["complementary-scope documentation pattern for standing-rule conflicts"]

key-files:
  created: []
  modified: [CLAUDE.md, .planning/PROJECT.md]

key-decisions:
  - "CLAUDE.md's unify clause now scopes to milestone-introduced duplication; PROJECT.md's no-refactor decision now states it protects pre-existing code — each names the other"
  - "PROJECT.md's parity-only constraint replaced: narrow-defensive-reads/no-flavor-branch half still binds, TOOL-01/META-01 named as the 2026-09-18 approved widening"
  - "Two of six v0.3 Validated entries explicitly flag their retail half as still open (Phase 25, Phase 27) or not explicitly confirmed (Phase 27.1 META-01)"

patterns-established: []

requirements-completed: []

duration: 25min
completed: 2026-09-18
---

# Phase 30 Plan 02: Documentation correction — rule conflict, stylua rule, v0.3 scope Summary

Resolved the CLAUDE.md/PROJECT.md "unify vs no-refactor" rule conflict in both documents, corrected the stylua rule to reflect the new `stylua.toml`, retired PROJECT.md's now-false "v0.3 adds no user-facing features" claim, added six v0.3 Validated entries with retail-open caveats intact, and recorded the milestone's three substantive Forever findings.

## Performance

- **Duration:** ~25 min
- **Tasks:** 3/3 completed
- **Files modified:** 2 (CLAUDE.md, .planning/PROJECT.md — 3 commits, PROJECT.md touched twice)

## Accomplishments

- The rule conflict is resolved in both documents, each naming the other — CLAUDE.md's cleanup mandate scopes "unify" to milestone-introduced duplication; PROJECT.md's "No refactors during cleanup phases" decision now states it protects pre-existing code
- CLAUDE.md's stylua rule no longer describes the invocation that caused the LF drift; it names `stylua.toml` and the `autocrlf`/`i-lf` reason the rule changed
- PROJECT.md no longer asserts a constraint the shipped code violates (TOOL-01, META-01 are real user-facing additions)
- Six v0.3 Validated entries added in the established format; every entry whose retail half is unproven says so explicitly
- Three substantive Forever findings recorded in Context, each cited to `FOREVER-TEST-PASS.md`

## Task Commits

1. **Task 1: Amend CLAUDE.md — scope the cleanup mandate, fix the stylua rule, correct two stale facts (D-01, D-03, D-09)** - `eb66bb6` (docs)
2. **Task 2: PROJECT.md — retire the false parity claim and move v0.3's work into Validated (D-12, D-13)** - `ff14cca` (docs)
3. **Task 3: PROJECT.md — scope the no-refactor decision and record the milestone's findings (D-01, D-03, D-14)** - `ba66d18` (docs)

## Files Created/Modified

- `CLAUDE.md` - Cleanup mandate scoped to milestone-introduced duplication with a complementary bullet naming PROJECT.md; stylua rule names `stylua.toml`; `install.bat` Architecture bullet corrected (planner discretion); Forever build bumped 69893 -> 69913 (planner discretion).
- `.planning/PROJECT.md` - Milestone goal, target-features bullet, and Constraints no longer claim zero user-facing features; six v0.3 Validated entries added; no-refactor Key Decision scoped; three `⏳ v0.3` outcome cells qualified, one superseded, one new widening-decision row added; three D-14 findings added to Context; Current State records v0.3 as functional-but-unshipped with both retail items provisional; `Last updated` bumped to Phase 30 cleanup.

## Before/After: The Rule Conflict (D-01, D-03)

**CLAUDE.md, before:**
> "Always run a cleanup phase at the end of new milestones: clean up unused variables, definitions, unify repeated behavior into shared functions, review hot paths (especially game loop tick functions), and check release scripts"

**CLAUDE.md, after:**
> "Always run a cleanup phase at the end of new milestones: clean up unused variables and definitions, unify repeated behavior **the milestone itself introduced** into shared functions, review hot paths (especially game loop tick functions), and check release scripts"
> "Code that predates the milestone is protected instead by `PROJECT.md`'s "No refactors during cleanup phases" Key Decision — read together the two rules are complementary, not contradictory: this mandate covers duplication a milestone introduces, `PROJECT.md`'s decision protects everything pre-existing. Settled by user decision, 2026-09-18 (Phase 30)"

**PROJECT.md Key Decision row "No refactors during cleanup phases", before:**
> Rationale: "Keeps release-prep phases narrow and predictable; prevents last-mile scope creep" / Outcome: "✓ Good — Phase 16 + Phase 24 honored this"

**PROJECT.md Key Decision row, after:**
> Rationale: "...Protects code that **predates the milestone**; `CLAUDE.md`'s GSD Workflow cleanup mandate separately covers duplication the milestone itself introduces — complementary, not contradictory (settled 2026-09-18)" / Outcome: "✓ Good — Phase 16 + Phase 24 honored this. Phase 30 is where the two rules first collided...; the reading above was settled by user decision on 2026-09-18"

## v0.3 Validated Entries Added

| Phase | Retail caveat |
|---|---|
| Phase 25 (split flavor TOCs) | "retail load gate (TOC-01/VER-01) is **still open**" |
| Phase 26 (install.bat multi-client) | none needed — no retail-specific claim made |
| Phase 27 (provider at-rest defensive fix) | "retail draggability half is **still open**" |
| Phase 27.1 (TOOL-01 tooltip) | none needed — tooltip mechanism is flavor-agnostic |
| Phase 27.1 (META-01 meta-tile hide) | "retail behaviour...is **not explicitly confirmed**" |
| Phase 28 (Forever in-game verification pass) | none needed — Forever-only claim, correctly scoped |

## The Three D-14 Findings (all cited to `.planning/testing/FOREVER-TEST-PASS.md`)

1. **Forever ships no retail spell data.** Lust Suggested tile rendered the `134400` question-mark icon (`C_Spell.GetSpellInfo(2825)` returns nil) — the discriminator META-01 relies on.
2. **`GetScaledCursorPositionForFrame` is absent from Forever's engine.** 53 errors in one session from `CDMTab.lua`'s ghost-frame `OnUpdate`; fixed in `9e32f92`; pre-existing since v0.2.0, not a v0.3 regression.
3. **SavedVariables do persist on build `1.60.1.69913`.** Edit Mode positions survived `/reload`, contradicting the third-party report filed against `69893`. Recorded with the hedge intact — single-build observation, not a platform guarantee.

## Planner Findings — Confirmed

1. **Confirmed.** Both halves of the rule conflict matched `30-CONTEXT.md`'s verbatim quotes exactly — no discrepancy.
2. **Confirmed, applied as planner discretion.** `install.bat`'s Architecture bullet and the pinned Forever build (`69893`) were both stale and corrected in the same commit as the stylua rule fix, per the plan's explicit invitation to exercise discretion here.
3. **Confirmed.** All three findings' citable sources in `FOREVER-TEST-PASS.md` were used verbatim (the `134400`/`2825` discriminator, the `9e32f92` fix table row, and Step 6's SavedVariables observation with its `69893`-vs-`69913` hedge preserved).
4. **Confirmed.** The Validated list's `description — milestone Phase N` format was matched exactly; the pre-existing `ns.TRINKET_FALLBACK_ORDER` / `ns.POT_FALLBACK_ORDER` entry under v0.2.4 Phase 24 was left untouched (it refers to the `ns.*` exports, not plan 30-01's file-local deletion).

## Deviations from Plan

**1. [Planner discretion, disclosed per plan instructions] `install.bat` Architecture bullet and Forever-build-number correction bundled into Task 1's commit.** The plan explicitly names this as planner discretion exercised in service of the phase goal, not an unplanned deviation — recorded here per the plan's own instruction to make the widening visible.

## Self-Check: PASSED

- FOUND: CLAUDE.md (contains `stylua.toml`, `pre-existing`, no `1.60.1.69893`)
- FOUND: .planning/PROJECT.md (contains `TOOL-01`, `META-01`, six `— v0.3 Phase` entries, three D-14 findings)
- FOUND commit eb66bb6
- FOUND commit ff14cca
- FOUND commit ba66d18

<deferred_questions>
None.
</deferred_questions>
