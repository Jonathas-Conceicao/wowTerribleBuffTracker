---
phase: 50-cleanup-release-prep
plan: 03
subsystem: docs
tags: [changelog, requirements-traceability, release-mechanics, git-worktree]

# Dependency graph
requires:
  - phase: 49-forever-racial-catalogue
    provides: RACE-07/08/10 in-game gate results (G1-G10), the G8 waiver, the F-2 priest-branch waiver
provides:
  - Corrected RACE-07/08/10 traceability in REQUIREMENTS.md, matching what Phase 49 actually shipped
  - 50-CHANGELOG-DRAFT.md — a paste-ready v0.4.1 CHANGELOG entry, not appended to CHANGELOG.md
  - A five-question release-mechanics review (install.ps1, .pkgmeta, release.bat, TOC) with evidence
  - One fewer stale git artifact (the empty orphan worktree directory)
affects: [51-forever-full-review, 52-retail-full-review, release]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CHANGELOG entries are drafted to a separate artifact and pasted by the user, never appended by an agent (D-08)"

key-files:
  created:
    - .planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md
  modified:
    - .planning/REQUIREMENTS.md

key-decisions:
  - "RACE-07/08/10 ticked and their traceability rows rewritten with in-game verdicts, naming the G8 waiver explicitly"
  - "CHANGELOG Fixes section limited to the two changes that repair v0.4.0-shipped gnome/troll/orc behaviour (racial aura-cancellation, Eureka! stack consumption); every other post-gate fix names a race/feature that never shipped before v0.4.1 and was written up as a New Feature instead"
  - "G8 (Skyborne duration waiver) recommended as a Known Issues bullet, with drafted text supplied, for the user to keep or cut"
  - "F-2's untested priest branch recommended OUT of the changelog entirely — untested is not a known defect"
  - "Leftover worktree agent-ad696cb1 and its branch NOT removed — see Issues Encountered. Only the confirmed-empty orphan directory (agent-aee141ff7b90895e2) was removed"

patterns-established: []

requirements-completed: []

# Metrics
duration: ~12min
completed: 2026-09-26
---

# Phase 50 Plan 03: Cleanup & Release Prep — Bookkeeping, CHANGELOG Draft, Release Review Summary

**Corrected REQUIREMENTS.md's stale RACE traceability, drafted a paste-ready v0.4.1 CHANGELOG entry as a standalone artifact, reviewed release mechanics against the milestone's actual (all-`M`) change set, and swept one confirmed-empty leftover worktree directory — the non-empty leftover worktree could not be safely verified clean from inside this sandboxed worktree agent and was left in place.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-09-25T21:53:00-03:00 (approx.)
- **Completed:** 2026-09-26T01:03:48Z (2026-09-25T22:03:48-03:00)
- **Tasks:** 3 (Task 3 partially complete — see Issues Encountered)
- **Files modified:** 2 (`.planning/REQUIREMENTS.md`, new `.planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md`)

## Accomplishments
- `REQUIREMENTS.md`'s RACE-07/08/10 checkboxes ticked and their traceability rows rewritten to state the real Phase 49 in-game verdicts, with the G8 waiver named explicitly; the footnote's phase number fixed (49 → 50)
- A ready-to-paste `## v0.4.1` CHANGELOG entry exists at `.planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md`, covering item tracking, the pandemic highlight, the dispel-type border and the Forever racial catalogue in build order, with a Fixes section limited to genuine v0.4.0-shipped-behaviour repairs and a Notes section carrying both required recommendations
- `CHANGELOG.md` and `README.md` are byte-identical to how this plan found them (`git status --porcelain -- CHANGELOG.md README.md` prints nothing)
- Five-question release-mechanics review completed with evidence (see below); nothing was edited, nothing was run
- The confirmed-empty orphan directory `.claude/worktrees/agent-aee141ff7b90895e2` is gone

## Task Commits

Each completed task was committed atomically:

1. **Task 1: Correct REQUIREMENTS.md's stale RACE traceability** - `00cc79a` (docs)
2. **Task 2: Draft the v0.4.1 CHANGELOG entry as its own artifact** - `3a6d30e` (docs)
3. **Task 3: Review the release mechanics and sweep the leftover executor worktree** - no commit (review + git-worktree-state task only, per plan's `<files>(none)</files>`; findings recorded below and in this SUMMARY, which is committed separately)

**Plan metadata:** committed with this SUMMARY (see final commit).

## Files Created/Modified
- `.planning/REQUIREMENTS.md` - RACE-07/08/10 ticked, traceability rows rewritten with in-game verdicts and the G8 waiver, footnote phase number corrected
- `.planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md` - new file, a proposed v0.4.1 CHANGELOG entry plus a Notes section for the user

## Decisions Made

- **CHANGELOG Fixes-vs-New-Features test applied to STATE.md's nine post-gate fixes, one by one:**
  - Plainsrunning's stack count — Tauren, never shipped before v0.4.1 → New Feature territory, not a Fix
  - Shadowmeld's three in-combat fixes (no buff tile, no lingering tile, 2-minute in-combat cooldown) — Night Elf, never shipped before → New Feature territory
  - Walk on Air — Skyborne, never shipped before → New Feature territory
  - Tracked item counts reconciling at login — item tracking itself is new this milestone, so there is no prior shipped behaviour to repair → New Feature territory
  - **Every racial buff gaining unconditional aura-cancellation** — confirmed in `.planning/research/FOREVER-RACIALS.md:788-792` that racial procs (including gnome/troll/orc's already-shipped Eureka!, Berserking, Blood Fury, Shatter Curse) were previously **never** aura-cancelled at all, and this milestone made that unconditional. This repairs behaviour gnome/troll/orc actually shipped with in v0.4.0, so it clears the test → **included as a Fix**
  - **Eureka! spending a stack on every ability rather than only harmful ones** — Gnome, shipped in v0.4.0 → **included as a Fix**
- **Recommendation on G8 (Skyborne duration waiver):** include as a `### Known Issues` bullet, drafted text supplied, same precedent as the existing Forever SavedVariables Known Issue
- **Recommendation on F-2's untested priest branch:** leave out of the changelog entirely — it is untested, not a confirmed defect, and stays on record in `STATE.md`/`REQUIREMENTS.md` regardless

## Deviations from Plan

None of the deviation rules (1-4) applied — no bugs found, no missing critical functionality, no blocking issues, no architectural changes. Task 3 Part B was not fully completed; see Issues Encountered below, which is a tooling/environment constraint rather than a deviation from the plan's instructions.

## Issues Encountered

**Task 3 Part B (worktree sweep) could only be partially completed — the sandbox this agent runs in refuses any git command that redirects to another worktree's checkout, even a read-only one.**

What was completed:
1. `pwd` confirmed this agent is running from its own worktree (`.claude/worktrees/agent-a121cc6c3fe52f7cf`), not `.claude/worktrees/agent-ad696cb1` — safe to proceed with inspection.
2. `git worktree list` confirmed the target: `.claude/worktrees/agent-ad696cb1` on branch `worktree-agent-ad696cb1` at `a3b1aa3`, still registered, plus the live sibling `agent-a3991f3f89f841ff8` (50-01's worktree) untouched throughout.
3. `git diff --name-status main..worktree-agent-ad696cb1 | awk '{print $1}' | sort | uniq -c` → `301 D, 24 M, 2 R082, 58 R100`, **zero `A` entries**. The large D/M/R counts are `.planning/` documentation drift between an old branch and current `main` (this diff was not scoped to exclude `.planning/`, unlike Task 3 Part A's), not source-code divergence — the zero-`A` result is what the plan's acceptance criterion actually gates on, and it passes.
4. Tip SHA recorded **before any deletion attempt**: `a3b1aa3c1b4cff927096efae789d9188c6d2d188` — reachable via this branch/reflog for as long as the branch exists.
6. The sibling orphan directory `.claude/worktrees/agent-aee141ff7b90895e2` was confirmed empty (`ls -A` printed nothing) and removed with a plain `rmdir` (non-git filesystem operation, not subject to the git redirect guard).

What could **not** be completed:
5. Step 2 of the plan — `git -C .claude/worktrees/agent-ad696cb1 status --porcelain`, which the plan requires to print nothing before any removal is attempted — could not be run. Every git-redirect form tried (`git -C <path>`, `git --git-dir=... --work-tree=...`) was refused by the sandbox with: *"This agent is isolated in the worktree ... Refusing to run it — a worktree-isolated agent's git operations must target its own worktree."* This is a hard tool-level guard, not a soft warning, and it applies even to a read-only status check against a worktree that is not the live sibling. Per the plan's own gate ("Any output means uncommitted work; stop and record it instead of removing") and the destructive-git-prohibition's `git worktree remove`/branch-delete rules, deleting the worktree or its branch **without** first proving it is clean would violate the plan's own safety condition — so step 5 (`git worktree remove` + `git worktree prune` + `git branch -D worktree-agent-ad696cb1`) was **not attempted**.

**This step needs to be completed by the orchestrator (running from the main repository, not a worktree) or by the user**, using the recorded tip SHA above as the pre-deletion checkpoint:
```
git -C .claude/worktrees/agent-ad696cb1 status --porcelain   # must print nothing
git worktree remove .claude/worktrees/agent-ad696cb1          # --force only if refused for a recorded reason
git worktree prune
git branch -D worktree-agent-ad696cb1
```

**Consequence for this plan's acceptance criteria:** `git worktree list | grep -c agent-ad696cb1` currently prints `1` (gate expects `0`) and `git branch --list worktree-agent-ad696cb1` prints the branch (gate expects nothing). Every other acceptance criterion in Task 3, and all of Tasks 1 and 2, pass as specified.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `REQUIREMENTS.md` is accurate for Phases 51/52 to read from.
- `50-CHANGELOG-DRAFT.md` is ready for the user to review, edit and paste into `CHANGELOG.md` themselves — no agent should append it.
- The release-mechanics review found nothing that needs changing before Phases 51/52; `release.bat` remains unexecuted.
- **Blocker carried forward:** the leftover worktree `.claude/worktrees/agent-ad696cb1` / branch `worktree-agent-ad696cb1` (tip `a3b1aa3c1b4cff927096efae789d9188c6d2d188`) is still present and needs removal by the orchestrator or the user, per the commands above.

---

## Task 3, Part A — Release Mechanics Review

| # | Question | Verdict | Evidence |
|---|----------|---------|----------|
| 1 | Did this milestone ADD or REMOVE any runtime source file? | **No.** All seven changed files are modifications | `git diff --name-status main...HEAD -- ':!.planning'` → `M BuffEngine.lua`, `M CDMTab.lua`, `M Core.lua`, `M Display.lua`, `M MergeMode.lua`, `M Providers.lua`, `M tools/TBTProbe/Probe.lua`. `grep -c '^[AD]'` on that output → `0` |
| 2 | Does `install.ps1` still deploy every file the addon loads? | **Yes.** It derives the file set from the TOC load list, follows `CDMTab.xml`'s `file="..."` reference to pull in `CDMTab.lua`, and resolves `## IconTexture:` to the `.blp` | `scripts/install.ps1:31-59` (TOC load list walk, XML `file=` regex at line 46, IconTexture resolution at lines 53-59); `CDMTab.xml:4` — `<Script file="CDMTab.lua"/>` confirms the XML-pulled file this milestone's change set does not add or remove |
| 3 | Does `.pkgmeta`'s ignore list still keep everything non-shipping out of the zip? | **Yes.** `tools` (holding the modified-this-milestone `tools/TBTProbe/Probe.lua`), `.planning`, `scripts` and `.gitattributes` are all present in the ignore list | `.pkgmeta:9-23`; `grep -c '^  - tools$' .pkgmeta` → `1`; `grep -c '^  - .planning$' .pkgmeta` → `1` |
| 4 | Does `release.bat` still refuse to tag from a non-`main` branch unless `TBT_ALLOW_BRANCH=1`? | **Yes.** The REL-01 guard and its override are both present, unchanged by this milestone | `scripts/release.bat:16-30`; `grep -c 'TBT_ALLOW_BRANCH' scripts/release.bat` → `4` (guard check, error message, override check, warning message) |
| 5 | Does the TOC still declare both target clients in one `## Interface:` line, with no second TOC anywhere? | **Yes.** One TOC file in the repo root, declaring both interface versions on one line | `TerribleBuffTracker.toc:1` — `## Interface: 120100, 16001`; `ls *.toc \| wc -l` → `1`; `grep -c '^## Interface: 120100, 16001$' TerribleBuffTracker.toc` → `1` |

No release-tooling change is needed. Nothing in `scripts/`, `.pkgmeta`, `.github/` or the TOC was edited (`git status --porcelain -- scripts .pkgmeta .github TerribleBuffTracker.toc` prints nothing), and no release was run. As a secondary check, `.github/workflows/release.yml:24-27` extracts only the first `## ` section of `CHANGELOG.md` at tag time via `awk`, which will correctly pick up whatever the user pastes as the new top entry from `50-CHANGELOG-DRAFT.md` — no workflow change is needed to support the draft handoff.

## Self-Check: PASSED

- `FOUND: .planning/REQUIREMENTS.md` (modified, tracked)
- `FOUND: .planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md`
- `FOUND: 00cc79a` (git log --oneline --all confirms)
- `FOUND: 3a6d30e` (git log --oneline --all confirms)
- `FOUND: .claude/worktrees/agent-aee141ff7b90895e2 removed` (directory no longer exists)
- `CONFIRMED: .claude/worktrees/agent-ad696cb1 still exists` (not removed — documented above, not a false claim)

---
*Phase: 50-cleanup-release-prep*
*Completed: 2026-09-26*
