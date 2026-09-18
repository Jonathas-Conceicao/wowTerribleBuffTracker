---
phase: 25-toc-split-retail-regression-gate
plan: 01
subsystem: build/packaging
tags: [toc, wow-addon, packager, flavor-split]

# Dependency graph
requires: []
provides:
  - "TerribleBuffTracker_Mainline.toc (Interface 120100, content-identical rename of the former TerribleBuffTracker.toc)"
  - "TerribleBuffTracker_Camelot.toc (Interface 16001, WoW Forever Notes string, otherwise byte-identical body to _Mainline)"
  - "Two isolated, revertable commits proving the split on the filesystem"
affects: [25-02, 25-03, 26-install-tooling, 29-pkgmeta-split]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Flavor-suffixed TOC split: one shared Lua/XML file list, two TOC files differing only on ## Interface: and ## Notes:"
    - "git mv for content-free renames to preserve history; cp (never hand-typed filenames) for flavor forks, verified via git ls-files exact-match, never a file browser"

key-files:
  created: [TerribleBuffTracker_Camelot.toc]
  modified: [TerribleBuffTracker_Mainline.toc (renamed from TerribleBuffTracker.toc, zero content change)]

key-decisions:
  - "No rollback/unsuffixed TerribleBuffTracker.toc kept, per REQUIREMENTS.md Out of Scope overriding PITFALLS.md's rollback-net recommendation"
  - "Camelot TOC created by cp + sed line-addressed edits only, never retyped, to avoid the lowercase-suffix trap NTFS would hide"

patterns-established:
  - "Full-file diff between the two TOCs must stay at exactly 4 changed lines (2 removed, 2 added) — Interface and Notes only"

requirements-completed: [TOC-01, TOC-02, TOC-03, TOC-04]

# Metrics
duration: 6min
completed: 2026-09-18
---

# Phase 25 Plan 01: TOC Split (Filesystem Half) Summary

**Split the single retail TOC into two flavor-suffixed TOCs — `TerribleBuffTracker_Mainline.toc` (Interface 120100) and `TerribleBuffTracker_Camelot.toc` (Interface 16001) — via `git mv` + `cp` with a two-line allowlisted edit, each in its own commit.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-09-18T00:00:00Z (approx, executor session)
- **Completed:** 2026-09-18
- **Tasks:** 2 completed
- **Files modified:** 2 (1 renamed, 1 created)

## Accomplishments
- `TerribleBuffTracker.toc` renamed to `TerribleBuffTracker_Mainline.toc` via `git mv`, zero content change, committed alone.
- `TerribleBuffTracker_Camelot.toc` created by `cp` of the Mainline file plus exactly two `sed` line-addressed edits (Interface 16001, Notes → WoW Forever), committed alone.
- Both filenames' exact capitalization proven via `git ls-files` (not Explorer/`dir`), including a negative grep proving no lowercase `_camelot.toc` spelling exists.
- Full-file diff between the two TOCs confirmed at exactly 4 changed lines; body diff excluding `## Interface:`/`## Notes:` confirmed empty.

## Task Commits

Each task was committed atomically:

1. **Task 1: Rename the TOC to the _Mainline flavor suffix** - `9054dd7` (refactor)
2. **Task 2: Create TerribleBuffTracker_Camelot.toc by copy and a two-line edit** - `a31ced4` (feat)

## Files Created/Modified
- `TerribleBuffTracker_Mainline.toc` - Renamed from `TerribleBuffTracker.toc`; Interface 120100, WoW Midnight retail; zero content change.
- `TerribleBuffTracker_Camelot.toc` - New file, copied from `_Mainline.toc`; Interface 16001, Notes says "WoW Forever"; otherwise byte-identical body.

## Verification Evidence

**`git ls-files` proof of both filenames and capitalization:**
```
TerribleBuffTracker_Camelot.toc
TerribleBuffTracker_Mainline.toc
```

**Negative grep for lowercase spelling** (`git ls-files | grep -q 'TerribleBuffTracker_camelot.toc'`): no match, confirmed absent.

**`git log --oneline -2`:**
```
a31ced4 feat(25): add TerribleBuffTracker_Camelot.toc for WoW Forever at Interface 16001 (TOC-02, TOC-03, TOC-04, D-01/D-02)
9054dd7 refactor(25): rename TOC to TerribleBuffTracker_Mainline.toc (TOC-01, D-04)
```

**Full 4-line diff between the two TOCs (CRLF stripped for readability):**
```
1c1
< ## Interface: 120100
---
> ## Interface: 16001
3c3
< ## Notes: Manual buff/cooldown timer tracking for WoW Midnight
---
> ## Notes: Manual buff/cooldown timer tracking for WoW Forever
```

**Body diff excluding the two allowlisted directive lines:** empty (confirmed via `diff` returning zero exit / no output).

**`git status --porcelain` after both commits:** no `.toc` changes remain uncommitted; only pre-existing untracked `.luarc.json` and `foo.md` (unrelated to this plan, left untouched).

## Decisions Made
- Followed D-01 through D-05 exactly as locked in `25-CONTEXT.md`: two-line-only divergence, `git mv` then `cp`+`sed`, CRLF preserved, no `.gitattributes` added.
- Did not restore an unsuffixed `TerribleBuffTracker.toc` as a rollback net (PITFALLS.md suggestion overridden by REQUIREMENTS.md Out of Scope and the user's locked D-04 decision).

## Deviations from Plan

None - plan executed exactly as written. Both tasks' automated verification blocks passed in full on first attempt.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Deferred Questions

Carried forward per plan 25-01's `<output>` spec:

1. **`scripts/install.bat` now fails its `.toc` copy line.** Its `copy /Y "%SOURCE%TerribleBuffTracker.toc"` line targets a file that no longer exists post-rename, so it will print one "The system cannot find the file specified" line and copy no TOC. This is expected and owned by Phase 26 (INST-04). Plan 25-03's in-game checklist works around it with a manual file copy per D-10.
2. **D-03 / research question 1 — does WoW Forever accept `## Category: Buffs & Debuffs, Combat`?** Both TOCs currently carry the identical retail category string (per D-03, deliberately not diverged pending research). Still unanswered; if Forever rejects it, adding a third allowlisted divergence line is a decision for the user, not this plan or the planner.

## Next Phase Readiness
- Filesystem half of TOC-01/TOC-02/TOC-03/TOC-04 is complete and machine-verified. The in-game half of TOC-01 and all of TOC-02 remain open, owned by plan 25-03's blocking human checkpoint.
- Plan 25-02 (drift guard + release.bat wiring + CLAUDE.md) can proceed immediately — it only reads these two TOC files, never writes them.
- No blockers for Phase 26/27/29 filesystem work, but their live-verified status still depends on Phase 25's in-game gate per STATE.md's accumulated context.

---
*Phase: 25-toc-split-retail-regression-gate*
*Completed: 2026-09-18*

## Self-Check: PASSED

- FOUND: TerribleBuffTracker_Mainline.toc
- FOUND: TerribleBuffTracker_Camelot.toc
- FOUND: 9054dd7
- FOUND: a31ced4
