---
phase: 26-install-tooling
plan: 01
subsystem: infra
tags: [batch, windows, deploy-script, wow-toc, multi-flavor]

# Dependency graph
requires:
  - phase: 25-toc-split-retail-regression-gate
    provides: TerribleBuffTracker_Mainline.toc and TerribleBuffTracker_Camelot.toc at repo root
provides:
  - Argument-free scripts/install.bat that deploys the 10-file addon set to every present WoW client folder in one pass
  - TBT_WOW_ROOT environment-variable override for non-default WoW install locations
  - Zero-install loud-failure diagnostic naming the searched root
affects: [28-forever-in-game-verification-pass]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single explicit FILES/FLAVORS list defined once, iterated via nested `for` loops instead of repeated copy lines (D-10)"
    - "%VAR% for loop-invariant values, !VAR! (delayed expansion) for anything mutated or read inside a parenthesized block"
    - "Literal `!` inside an `echo` line under `setlocal enabledelayedexpansion` must be caret-escaped (`^^!`), not doubled (`!!` does not print a literal bang)"

key-files:
  created: []
  modified:
    - scripts/install.bat

key-decisions:
  - "Followed CONTEXT.md D-01 through D-13 as specified — no deviations from the decision set"
  - "Used a path-segment-aware collision check in place of the plan's literal substring-match verification for Task 2 Scenario A, because '_beta_' is a true substring of the present flavor '_classic_beta_' (see Deviations)"

requirements-completed: [INST-01, INST-02, INST-03, INST-04]

# Metrics
duration: 55min
completed: 2026-09-18
---

# Phase 26 Plan 01: Install Tooling Summary

**Argument-free `install.bat` rewrite deploying 10 files (including both post-split TOCs) to all 4 present WoW client folders (`_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`) in one pass, with `TBT_WOW_ROOT` override and a loud zero-install diagnostic.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-09-18T11:08:00Z (approx.)
- **Completed:** 2026-09-18T12:03:52Z
- **Tasks:** 3 completed
- **Files modified:** 1 (`scripts/install.bat`)

## Accomplishments
- `scripts/install.bat` now installs to every present WoW client flavor folder in a single invocation with no arguments, replacing the old hardcoded `_retail_`-only, single-TOC script that would have deployed nothing after Phase 25 deleted `TerribleBuffTracker.toc`
- Both `TerribleBuffTracker_Mainline.toc` and `TerribleBuffTracker_Camelot.toc` now land in every installed client, including `_classic_beta_` — the Forever beta target the user will test first
- Verified against a real, live WoW install (`C:\Program Files (x86)\World of Warcraft`) as well as an isolated sandbox root, covering the happy path, partial-presence, zero-clients, nonexistent-root, and emacs-lock-file-immunity cases

## Task Commits

Each task was committed atomically per the plan's own sequencing (Tasks 1 and 2 write/verify only; the plan places the sole commit at Task 3):

1. **Task 1: Rewrite install.bat as an argument-free multi-client deploy** — verified structurally (no commit; plan places the commit after Task 3's live-run verification)
2. **Task 2: Prove behavior in an isolated sandbox root** — verified via 4 scenarios against a scratch sandbox (no repo files modified; no commit)
3. **Task 3: Live run against the real WoW root, then commit** — `62d9982` (fix)

**Plan metadata:** this SUMMARY + VERIFICATION.md (docs, committed separately per phase scope constraints — STATE.md/ROADMAP.md/REQUIREMENTS.md intentionally left untouched, see Deviations)

## Files Created/Modified
- `scripts/install.bat` - Rewritten as an argument-free, multi-client deploy script: explicit 10-entry FILES list (includes both post-split TOCs), fixed 7-entry FLAVORS list, `TBT_WOW_ROOT` override, source-file preflight, per-target mkdir + copy loop with per-file error guard, zero-install diagnostic, single `copy /Y` statement inside the nested loop

## Decisions Made
- Followed CONTEXT.md's D-01 through D-13 exactly: fixed 7-flavor list (no glob), explicit 10-file list (no glob, protects against `.#Display.lua` emacs lock files), silent skip of absent flavors, loud zero-install failure naming the searched root, `TBT_WOW_ROOT` override without adding a CLI argument, `release.bat` and `check-toc.ps1` left untouched (D-12/D-13)
- Both batch traps flagged in the task brief were honored: `WOW_ROOT`/`TBT_WOW_ROOT` assignment kept outside any parenthesized block (the literal parens in `%ProgramFiles(x86)%` would otherwise break block parsing), and the post-loop zero-install check uses `!INSTALLED!` (delayed expansion), not `%INSTALLED%`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Literal `!` in the closing echo line was silently stripped**
- **Found during:** Task 2, Scenario A first run
- **Issue:** With `setlocal enabledelayedexpansion` active, a bare `!` in `echo Done! /reload in WoW to load the addon.` is consumed by the delayed-expansion parser (it looks for a matching closing `!` to treat the contents as a variable reference) and is dropped from output entirely, producing "Done /reload..." instead of "Done! /reload...". A first attempted fix using the doubled-bang idiom (`Done!!`) also failed to produce a literal `!` in this context.
- **Fix:** Used the caret-escape form `echo Done^^! /reload in WoW to load the addon.`, verified in isolation via a throwaway test `.bat` before reapplying to the real script. Re-ran Scenario A; output now reads "Done! /reload in WoW to load the addon." exactly as before the rewrite.
- **Files modified:** scripts/install.bat
- **Verification:** Scenario A re-run confirmed exact output match; Task 3's live run also shows the correct closing line.
- **Committed in:** 62d9982 (Task 3 commit — the fix landed before any commit was made, so there is no separate fix commit)

**2. [Verification-script discrepancy, not an install.bat bug] Task 2's literal Scenario A automated check has a substring collision**
- **Found during:** Task 2, Scenario A first run
- **Issue:** The plan's given automated verification for Scenario A tests that none of `_ptr_`, `_beta_`, `_classic_era_`, `_classic_ptr_` appear anywhere in stdout as a raw substring. But the present flavor `_classic_beta_` — which correctly prints an "Installed to ...\_classic_beta_\..." line — contains `_beta_` as a literal substring (`_classic` + `_beta_`). The plan's own check list already excludes `_classic_` from this same test for the identical reason (it is a substring of `_classic_beta_`, `_classic_era_`, and `_classic_ptr_`); `_beta_` was left in and has the same collision against the one present flavor that happens to contain it. This means the literal check as written will always report a false D-05 violation whenever `_classic_beta_` is present and installed correctly — it is not something a correct implementation of install.bat can satisfy.
- **Fix:** Ran a corrected, path-segment-aware version of the same check (matching `\<flavor>\` as a whole path segment rather than a raw substring) to confirm the actual intent of D-05 — that absent flavors produce no output — genuinely holds. Confirmed manually that stdout contains exactly two "Installed to" lines, for `_retail_` and `_classic_beta_` only, with no line referencing `_ptr_`, `_beta_` as its own directory, `_classic_` as its own directory, `_classic_era_`, or `_classic_ptr_`.
- **Files modified:** none (scripts/install.bat is correct as written; only the local verification script used during this execution was adjusted)
- **Verification:** Manual inspection of Scenario A stdout plus the corrected path-segment regex check, both passing. Flagging this here rather than silently reinterpreting the plan's pass/fail criteria without a record.
- **Committed in:** n/a (verification-only finding, no code change required)

**3. [Verification-script discrepancy, not an install.bat bug] Scenario D's git-tree-clean assertion collides with Task 3's not-yet-made commit**
- **Found during:** Task 2, Scenario D
- **Issue:** The plan's Scenario D check asserts `git status --porcelain` is fully empty after the lock-file cleanup. At the point Scenario D runs (before Task 3's commit), `scripts/install.bat` itself is legitimately modified-but-uncommitted, so a literal empty-tree check would always fail regardless of the lock-file behavior being tested.
- **Fix:** Checked specifically that `.#Display.lua` does not appear anywhere in `git status --porcelain` output (i.e., it was never created, staged, or left behind), which is the actual property Scenario D is meant to prove. Full tree cleanliness was confirmed by other means (Task 3's post-commit `git status --short`).
- **Files modified:** none
- **Verification:** `git status --porcelain` after Scenario D contained no reference to `.#Display.lua`; two pre-existing unrelated modified files (`25-INGAME-VERIFICATION.md`, `28-VERIFICATION-CHECKLIST.md`) and untracked `.luarc.json`/`foo.md`/`.planning/testing/` were present both before and after Scenario D ran — confirmed these predate this session and are out of this phase's scope.
- **Committed in:** n/a (verification-only finding, no code change required)

---

**Total deviations:** 3 (1 Rule-1 code fix, 2 verification-script discrepancies documented and worked around without softening the underlying assertion)
**Impact on plan:** The one code fix (caret-escaped `!`) restores exact parity with the pre-rewrite script's friendly closing line. The two verification discrepancies are pre-existing collisions in the plan's own literal check text caused by the flavor-naming scheme (`_classic_beta_` containing `_beta_` as a substring) and by the plan's task ordering (verification-only tasks running before the commit task); neither reflects incorrect behavior in `install.bat` itself.

## Issues Encountered
- Windows path-quoting/escaping friction running `cmd /c "..."` and inline PowerShell one-liners directly through the Bash tool (backslash-in-double-quote collisions, MSYS path conversion on `cmd //c`) repeatedly produced spurious "system cannot find the path specified" and malformed-string errors unrelated to install.bat itself. Resolved by writing throwaway `.ps1` test scripts to the session scratchpad and invoking them with `powershell -NoProfile -File`, which sidesteps quoting ambiguity entirely.

## User Setup Required
None - no external service configuration required. The live run in Task 3 already deployed the addon to all 4 present WoW client folders on this machine; no further action needed before the user's next `/reload`.

## Next Phase Readiness
- `_classic_beta_` (confirmed Forever beta, `wow_classic_beta` / build `1.60.1.x`) now has both TOCs and all 8 shared files deployed, unblocking Phase 28's Forever in-game verification pass, which the sequencing note in this task identified as the user's actual first test target
- `_retail_` also received the full deploy in the same run, so retail regression testing (Phase 25's remaining in-game gate) can proceed from the same install
- No blockers carried forward; the three deferred questions from 26-CONTEXT.md (D-01 env override, D-02 flavor list breadth, planner's source-file preflight) remain open for human review but did not block execution — see Deferred Questions below

## Deferred Questions

Carried forward unresolved from 26-CONTEXT.md / 26-01-PLAN.md; none blocked execution and all are cheap to reverse:

1. **D-02 — flavor folder list breadth.** The script installs to `_ptr_` and `_beta_` (Midnight PTR/beta) in addition to `_retail_` and `_classic_beta_`. Confirmed harmless in the live run (all 4 present clients received a correct install, no errors). Say if only `_retail_` and the Forever folder should ever be touched.
2. **D-01 — `TBT_WOW_ROOT` override.** Implemented and exercised in Task 2 (Scenarios B/C) and works correctly. Trivial to drop if a future review decides the plain default-root-only behavior is preferred.
3. **Planner addition — source-file preflight.** Implemented as specified: the script now aborts with `exit /b 1` before touching any client folder if any of the 10 source files is missing from repo root. Confirmed necessary in practice — without it, a half-complete Phase 25-style TOC split would let the script silently report per-target success while copying an incomplete file set.

---
*Phase: 26-install-tooling*
*Completed: 2026-09-18*

## Self-Check: PASSED

- FOUND: scripts/install.bat
- FOUND: .planning/phases/26-install-tooling/26-01-SUMMARY.md
- FOUND: 62d9982 (commit exists in `git log --all`)
