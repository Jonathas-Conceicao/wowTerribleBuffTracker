---
phase: 25-toc-split-retail-regression-gate
plan: 02
subsystem: build/packaging
tags: [powershell, toc, drift-guard, release-tooling, wow-addon]

# Dependency graph
requires:
  - phase: 25-toc-split-retail-regression-gate (plan 01)
    provides: "TerribleBuffTracker_Mainline.toc and TerribleBuffTracker_Camelot.toc to validate"
provides:
  - "scripts/check-toc.ps1 — standalone, -Root-parameterised, no git/network calls, exits 0/1"
  - "scripts/release.bat aborts before tagging on TOC drift"
  - "CLAUDE.md Forever flavor reference, interface numbers, install paths"
affects: [25-03, 26-install-tooling, 29-pkgmeta-split]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PowerShell pre-tag guard, standalone and -Root-parameterised so a future CI step can call it unchanged"
    - "Line-ending-insensitive body comparison via [regex]::Split(raw, '\\r?\\n') instead of byte comparison"
    - "Accumulate-then-report failure pattern (report every problem in one run, not fail-fast on the first)"

key-files:
  created: [scripts/check-toc.ps1]
  modified: [scripts/release.bat, CLAUDE.md]

key-decisions:
  - "D-12: guard lives in release.bat before the tag, not in install.bat (declined per hard_constraints — install.bat is Phase 26's file)"
  - "D-13: guard implemented in PowerShell, not batch, since batch cannot diff two bodies excluding allowlisted lines cleanly"
  - "D-14: exactly three assertions — interface range, body parity (CRLF-insensitive), forward-looking .pkgmeta-<flavor> cross-ignore that skips cleanly when absent"

patterns-established:
  - "Guard failure messages name the file, the value found, and the expected pattern — never rely on packager's generic stderr"
  - "Where-Object filter scriptblocks must reference $_, not a param()-bound name, or the filter silently becomes a no-op"

requirements-completed: [TOC-03, TOC-05, DOC-01]

# Metrics
duration: 18min
completed: 2026-09-18
---

# Phase 25 Plan 02: TOC Drift Guard & Release Wiring Summary

**`scripts/check-toc.ps1` PowerShell guard enforcing D-14's three TOC-pair assertions, wired into `scripts/release.bat` before `git tag`, plus Forever flavor facts recorded in `CLAUDE.md`.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-09-18 (executor session, continued from plan 25-01)
- **Completed:** 2026-09-18
- **Tasks:** 3 completed
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- `scripts/check-toc.ps1` created implementing all three D-14 assertions: interface-range check, CRLF-insensitive body-parity check, forward-looking `.pkgmeta-<flavor>` cross-ignore check that skips cleanly when those files don't exist (they arrive in Phase 29).
- Guard proven to actually fail via 4 independent negative tests run in a scratch directory outside the repo, plus proven to pass on both the real repo and an LF-normalized copy (line-ending insensitivity).
- `scripts/release.bat` now runs the guard immediately after the banner and before `git tag`, aborting with `exit /b 1` using the file's existing errorlevel idiom. The script was never executed — verified entirely by reading and grepping.
- `CLAUDE.md` updated: `## Style Reference` gains the `BigWigsMods/WoWUI` `forever-beta` reference (and a read-only note on the existing Midnight-only `wow-ui-source` checkout); `## Key Constraints` gains both flavors' TOC filenames, interface numbers, install paths, and the two-line divergence rule; `## Architecture` gains a one-line entry for the new guard script.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write scripts/check-toc.ps1 implementing D-14's three assertions** - `ecc8f6f` (feat)
2. **Task 2: Invoke the guard from release.bat before the tag is created** - `7cfe0a7` (feat)
3. **Task 3: Record the Forever flavor facts in CLAUDE.md (DOC-01)** - `f5f6b66` (docs)

## Files Created/Modified
- `scripts/check-toc.ps1` - New standalone PowerShell guard; `param([string]$Root = (Split-Path -Parent $PSScriptRoot))`, three assertions, no git/network calls, no writes to disk, exits 0/1.
- `scripts/release.bat` - Guard invocation inserted between the banner and `git tag -a`, using `%~dp0check-toc.ps1` and the file's existing `if errorlevel 1 ( ... exit /b 1 )` idiom. Tag/push lines byte-unchanged.
- `CLAUDE.md` - Forever UI source reference in Style Reference; flavor/interface/install-path facts in Key Constraints; `check-toc.ps1` line in Architecture.

## Verification Evidence

**Guard pass output against the real repo (with clean `.pkgmeta` skip):**
```
skip: .pkgmeta-mainline not present (Phase 29)
skip: .pkgmeta-camelot not present (Phase 29)
check-toc: OK (C:\Users\jonat\Repositories\TerribleBuffTracker)
```
Exit code: 0

**Negative test exit codes (all run against scratch copies in a `mktemp -d` directory outside the repo, never inside the working tree):**

| Test | Scenario | Output | Exit code |
|---|---|---|---|
| neg1 | Camelot carries a retail-range interface (`120100`) | `FAIL: TerribleBuffTracker_Camelot.toc: Interface value '120100' does not match expected pattern ^16\d{3}$ (WoW Forever range)` | 1 |
| neg2 | Camelot body gains an extra line (`Extra.lua`) | `FAIL: Body line count differs...` + `FAIL: Body drift at line 17...` | 1 |
| neg3 | `.pkgmeta-mainline` ignores the wrong TOC (its own) | `FAIL: .pkgmeta-mainline: does not ignore TerribleBuffTracker_Camelot.toc...` + `FAIL: .pkgmeta-mainline: incorrectly ignores its own TOC...` | 1 |
| neg4 | Camelot TOC file missing entirely | `FAIL: Missing required file: ...\neg4\TerribleBuffTracker_Camelot.toc` | 1 |
| pos1 | Correct `.pkgmeta-<flavor>` pair present, Camelot TOC copy stripped to LF-only | `check-toc: OK (...\pos1)` | 0 |

**Inserted `release.bat` lines relative to the `git tag` line** (guard block at lines 16-21, `git tag -a` at line 23 in the committed file):
```
16: echo === Checking flavor TOC drift ===
17: powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-toc.ps1"
18: if errorlevel 1 (
19:     echo ERROR: check-toc.ps1 reported TOC drift. Aborting before tag.
20:     exit /b 1
21: )
22: (blank)
23: git -C "%SOURCE%" tag -a "%TAG%" -m "Release %VERSION%"
```
Guard block (lines 16-21) precedes both the tag line (23) and the push line (29) — confirmed via `grep -n` ordering assertions in the automated verify block, all of which passed.

**`git log --oneline -3`:**
```
f5f6b66 docs(25): record Forever flavor references and constraints in CLAUDE.md (DOC-01, D-16)
7cfe0a7 feat(25): run TOC drift guard before tagging in release.bat (TOC-05, D-12)
ecc8f6f feat(25): add scripts/check-toc.ps1 TOC drift guard (TOC-05, D-13/D-14)
```

**`git status --porcelain` scoped to protected files:** empty for `*.toc`, `scripts/install.bat`, `.pkgmeta`, `.github/workflows/release.yml`.

**`git tag --list`:** unchanged (`v0.1.0` … `v0.2.6`, plus legacy `0.1.0`) — no new tag created; `release.bat` was never executed.

## Decisions Made
- Followed D-12/D-13/D-14/D-16 exactly as locked (Claude's-discretion defaults) — guard in `release.bat` (not `install.bat`), PowerShell language, exactly three assertions, terse `CLAUDE.md` placement.
- Declined the D-12 "optional warn-only invocation from `install.bat`" — `install.bat` is Phase 26's file and already broken by the Plan 25-01 rename until INST-04 lands; editing it now would collide with that phase's ownership.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed PowerShell drive-syntax parse error in an interpolated string**
- **Found during:** Task 1 (initial guard run against the real repo)
- **Issue:** `"$FileLabel: missing or unparseable...` inside a double-quoted string was parsed by PowerShell as a scope/drive reference (`$FileLabel:`), causing a hard parse error (`InvalidVariableReferenceWithDrive`) before any assertion could run.
- **Fix:** Changed to `"${FileLabel}: missing or unparseable...` using the `${}` delimiter form, which PowerShell's own error message explicitly recommends.
- **Files modified:** `scripts/check-toc.ps1`
- **Verification:** Re-ran the guard against the real repo; parse error gone.
- **Committed in:** `ecc8f6f` (part of Task 1 commit — caught before the first commit, not a follow-up fix)

**2. [Rule 1 - Bug] Fixed a silently-no-op `Where-Object` filter for the body-parity assertion**
- **Found during:** Task 1 (first real run after the parse-error fix)
- **Issue:** The directive-line filter was written as `{ param($l) $l -notmatch '...' }` and passed to `Where-Object`. `Where-Object` binds `$_`, not a scriptblock's own `param()`-declared name, so `$l` was always `$null` inside the filter, `$null -notmatch pattern` evaluated `$true` for every line, and the filter silently included every line instead of excluding the two directive lines — causing a false-positive body-drift failure on the real (correct) repo pair.
- **Fix:** Rewrote the filter to reference `$_` directly: `{ $_ -notmatch '^##\s*(Interface|Notes):' }`.
- **Files modified:** `scripts/check-toc.ps1`
- **Verification:** Re-ran the guard against the real repo — passed cleanly; re-ran all 5 negative/positive scratch tests — all produced the expected exit codes and messages.
- **Committed in:** `ecc8f6f` (part of Task 1 commit — caught before the first commit, not a follow-up fix)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - bugs found and fixed during the plan's own mandated verification loop, before the task's commit was made)
**Impact on plan:** Both fixes were necessary for the guard to function at all — an unfixed guard would either crash on every invocation or false-positive on the correct TOC pair, defeating TOC-05's entire purpose. No scope creep; both fixes stayed inside `scripts/check-toc.ps1`.

## Issues Encountered

None beyond the two auto-fixed bugs above, both caught and resolved during the plan's own verification loop before any commit was made.

## User Setup Required

None - no external service configuration required.

## Deferred Questions

Carried forward verbatim per plan 25-02's `<deferred_questions>`:

1. **Warn-only guard call from `install.bat`** — D-12 offers it as optional. Declined here: `install.bat` is Phase 26's file and is already broken by the rename until INST-04 lands, so editing it now would collide. Revisit during Phase 26.
2. **Guard invocation from CI** — deferred to Phase 29 per `25-CONTEXT.md` Deferred Ideas. `check-toc.ps1` is standalone and `-Root`-parameterised so a future workflow step can call it unchanged (a `pwsh` step works on `ubuntu-latest`).
3. **Interface drift past 16001** (research question 4) — the guard asserts the *range* `16xxx`, deliberately not the exact value, so a future Forever beta build bump does not fail the guard spuriously. Whether to pin the exact value is a user decision.

## Next Phase Readiness
- TOC-05 is satisfied and demonstrated by 4 passing negative tests plus 2 passing positive tests (real repo + LF-normalized copy), not by assertion alone.
- DOC-01 is satisfied in `CLAUDE.md`.
- `release.bat` fails closed before tagging; it was never executed during this plan.
- Plan 25-03 (in-game verification checklist) can proceed — it depends only on both TOCs existing (plan 25-01) and does not depend on this plan's guard.

---
*Phase: 25-toc-split-retail-regression-gate*
*Completed: 2026-09-18*

## Self-Check: PASSED

- FOUND: scripts/check-toc.ps1
- FOUND: ecc8f6f
- FOUND: 7cfe0a7
- FOUND: f5f6b66
