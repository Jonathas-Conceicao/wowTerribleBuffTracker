---
phase: 45-documentation-release-prep
plan: 01
subsystem: docs
tags: [readme, wow-addon, store-copy, release-prep]

# Dependency graph
requires:
  - phase: 44-retail-validation-pass
    provides: the Merge Mode rework, migration confirmation, and the "Predicted, NOT bugs" table that Known Issues entries 2 and 3 are drawn from
provides:
  - A README.md rewritten to describe the v0.4.0 addon (cooldown trackers, four base containers, user containers, Merge Mode, Centered growth, the Options > AddOns settings panel, gnome/troll/orc racial trackers)
  - The single source the user pastes into CurseForge and Wago by hand, carrying the Forever SavedVariables caveat (D-08, closes DOC-03)
  - Known Issues reduced to exactly the three D-10-approved public entries
affects: [45-02-changelog-and-project-correction]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "README is the single source for store copy (D-08) — no separate store-description file"
    - "No comparative claims about Blizzard's CDM in public copy (DOC-05) — describe what TBT does and stop"

key-files:
  created: []
  modified:
    - README.md

key-decisions:
  - "Followed D-06 exactly: AI Usage, Showcase and License sections were not touched — verified byte-identical via git diff checks on 'Assets/', 'WTFPL' and 'Claude AI' after every task"
  - "Followed D-12: Racial trackers described as gnome/troll/orc, never 'Eureka! alone' or 'Eureka! only', correcting PROJECT.md's stale v0.4.0-kickoff claim in the public copy"
  - "CRLF preservation verified explicitly (CLAUDE.md's recorded grep/awk CR-stripping trap): probed the Edit tool on a throwaway CRLF file before touching README.md, confirmed it preserves and even normalizes inserted lines to CRLF, then re-checked 'git ls-files --eol README.md' after every task"

patterns-established:
  - "Any future README/store-copy edit in this repo should re-probe the Edit tool's CRLF behavior once (or trust this record) rather than assume grep/awk-based verification is safe — both silently strip CR in Git Bash on this repo"

requirements-completed: [DOC-02, DOC-03, DOC-05]

# Metrics
duration: ~20min
completed: 2026-09-23
---

# Phase 45 Plan 01: Rewrite README.md for v0.4.0 Summary

**Full rewrite of README.md's intro, Features, Usage, Lust/Heroism Tracking and Known Issues to describe the v0.4.0 addon (cooldown trackers, four base containers, Merge Mode, racial trackers) while leaving AI Usage/Showcase/License byte-identical and making zero comparative claims about Blizzard's Cooldown Manager.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-23T06:33:04Z
- **Tasks:** 3
- **Files modified:** 1 (README.md)

## Accomplishments
- Intro now states TBT is one download running on both Midnight retail (interface `120100`) and the WoW Forever beta (interface `16001`), with no separate builds, and drops the stale "that Blizzard's Cooldown Manager doesn't support" comparative claim (DOC-05)
- Features section rewritten to cover cooldown trackers, the four built-in containers (Tracked Bars, Tracked Buffs, Essential Cooldowns, Utility Cooldowns), user-created containers, Merge Mode, Centered growth, the Options > AddOns settings panel, the CDM tab's Buffs/Cooldowns split, the kept Lust/Trinket/Damage Potion meta-trackers, and gnome/troll/orc racial trackers (never "Eureka! alone")
- Usage rewritten for the tab-driven add dialog (`30s`/`2m` durations, Not Displayed/Suggested dragging), container create/delete, the Merge Mode switch, Edit Mode's Copy Blizzard CDM Config, and right-click quick actions — with no repo-relative links, keeping the section paste-ready for CurseForge/Wago (D-08)
- Lust / Heroism Tracking body corrected: names all five Sated-family debuffs and drops the stale "into Tracked Bars or Tracked Buffs" phrasing now that more containers exist
- Known Issues reduced to exactly the three D-10-approved entries (Forever SavedVariables persistence, restricted-content buff overhang, blank charge counts), with the "Only Active Buffs can be tracked" bullet removed and none of D-11's excluded items (hostile target, potion-in-key, equipped-item) added

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite the intro and the Features section** - `89fda35` (docs)
2. **Task 2: Rewrite the Usage and Lust / Heroism Tracking sections** - `a8e6140` (docs)
3. **Task 3: Reduce Known Issues to the three approved public entries** - `4ebe1d1` (docs)

**Plan metadata:** committed as part of this SUMMARY.md commit (worktree mode — STATE.md/ROADMAP.md updates deferred to orchestrator)

## Files Created/Modified
- `README.md` - Intro, Features, Usage, Lust/Heroism Tracking and Known Issues fully rewritten for v0.4.0; AI Usage, Showcase and License sections untouched

## Decisions Made
- Kept the DOC-05 "Claude's Discretion" reading from 45-CONTEXT.md: no statement anywhere in the README says what Blizzard's Cooldown Manager does or does not track natively. Verified with `grep -ci` for "doesn't support", "does not support", "natively" and "already tracks" — all zero.
- Drafted every rewritten bullet for prunability rather than polish, per 45-CONTEXT.md's "Claude's Discretion" note that the user will rewrite the wording in their own voice.

## Deviations from Plan

None - plan executed exactly as written. All three tasks' automated verification and acceptance criteria passed on the first attempt; no auto-fixes were needed.

## Issues Encountered

None. One pre-emptive check is worth recording since CLAUDE.md flags this exact repo pattern as having bitten it twice before: before editing README.md, I created a throwaway CRLF-line-ended test file inside the worktree, used the Edit tool on it, and confirmed with `od -c` that the Edit tool both preserves existing CRLF line endings and normalizes newly-inserted lines to CRLF (not LF). This confirmed the Edit tool was safe to use for this plan's multi-line replacements without risking the silent LF-reflow bug the project's CLAUDE.md describes for `stylua`. The test file was deleted before any real edit. `git ls-files --eol README.md` was re-checked after every task and reported `i/lf w/crlf` throughout, matching the plan's `<verification>` requirement.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- README.md is fully rewritten and ready to be pasted into CurseForge and Wago by the user (D-08); no separate store-copy file was created and no store copy was emitted in this response
- DOC-02, DOC-03 (README half) and DOC-05 are closed by this plan
- 45-02-PLAN.md (CHANGELOG append and PROJECT.md racial-line correction) has no dependency on this plan's specific wording and can run independently in the same wave
- No `.lua` file was modified; `.pkgmeta` was not touched (D-09); `git status --porcelain` shows only `README.md` (plus this SUMMARY.md once committed) as changed

---
*Phase: 45-documentation-release-prep*
*Completed: 2026-09-23*

## Self-Check: PASSED

- FOUND: README.md
- FOUND: .planning/phases/45-documentation-release-prep/45-01-SUMMARY.md
- FOUND commit: 89fda35 (Task 1)
- FOUND commit: a8e6140 (Task 2)
- FOUND commit: 4ebe1d1 (Task 3)
- FOUND commit: 3fdb287 (this SUMMARY.md)
