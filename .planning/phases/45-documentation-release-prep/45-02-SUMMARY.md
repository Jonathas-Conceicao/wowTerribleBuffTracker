---
phase: 45-documentation-release-prep
plan: 02
subsystem: docs
tags: [changelog, project-md, release-prep, wow-addon]

# Dependency graph
requires:
  - phase: 45-01
    provides: the rewritten README.md whose Features list and three Known Issues are the canonical wording this plan's CHANGELOG entry agrees with
provides:
  - "CHANGELOG.md v0.4.0 entry, appended above v0.3.0, title matching the ROADMAP milestone name"
  - "PROJECT.md's racial statement corrected in all three locations (D-12), no longer claiming v0.4.0 ships Eureka! alone"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CHANGELOG.md edits use a targeted Edit-tool replacement of the unique next-heading string (prepend new content, keep the heading's own text unchanged) so git records the change as pure insertion with zero deletions, satisfying D-02's byte-identical-pre-existing-content proof"
    - "PROJECT.md line-level corrections keep untouched context lines byte-identical rather than rewrapping full paragraphs -- rewrapping for prose smoothness inflates the diff footprint against a numeric acceptance gate (first attempt at Task 2 produced 24 changed lines against a <15 budget; the surgical rewrite that touched only the 2-3 lines actually needing new words produced 8)"

key-files:
  created: []
  modified:
    - CHANGELOG.md
    - .planning/PROJECT.md

key-decisions:
  - "D-01 override applied exactly as scoped: this is the one CHANGELOG.md entry CLAUDE.md's hands-off rule does not cover; every other file in the repo remains subject to the normal rule"
  - "Followed the plan's priority-ordered feature list literally: took the first 8 of 10 listed New Features candidates (dropped 'cover all ranks' and the duration-typing-format bullet) and the first 4 of 6 listed Fixes candidates, landing at exactly 15 total bullets -- the top of the 12-15 budget -- rather than trimming further, since the user explicitly plans to prune"
  - "Known Issues copied to match README's exact three D-10-approved entries (Forever persistence, restricted-content buff overhang, blank charge counts) in substance; wording adapted to the terser CHANGELOG bullet style already used by prior entries rather than the README's longer prose"
  - "PROJECT.md Key Decisions table: per the plan's explicit instruction, the Decision and Rationale cells were left untouched as a historical record (the 2026-09-20 decision genuinely was Eureka!-only); only the Status cell was appended with a dated widening note"

patterns-established:
  - "When a plan's acceptance criterion caps total diff size numerically (e.g. '<15 changed lines'), draft the edit as a full rewrap first only to measure it, then redo as the smallest edit that changes the specific words needed -- confirmed by this plan's Task 2, which had to be reverted and redone once after the first attempt produced 24 changed lines against a 15-line budget"

requirements-completed: [DOC-04, DOC-05]

# Metrics
duration: ~25min
completed: 2026-09-23
---

# Phase 45 Plan 02: CHANGELOG v0.4.0 Entry and PROJECT.md Racial Correction Summary

**Appended a v0.4.0 CHANGELOG.md entry (append-only, zero deletions, 15 bullets across the standard New Features/Fixes/Known Issues trio) and corrected all three stale "Eureka! only" claims in PROJECT.md to name gnome, troll and orc plus racial cooldown tiles (D-12), while keeping the diff to 8 changed lines total.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-09-23T06:42:31Z
- **Tasks:** 2
- **Files modified:** 2 (CHANGELOG.md, .planning/PROJECT.md)

## Accomplishments
- Pre-flight on CHANGELOG.md confirmed all four D-02 conditions before any edit: clean git status, exactly 109 lines, line 1 `# Changelog`, line 3 `## v0.3.0 — WoW Forever Support`, and `git ls-files --eol` reporting `i/lf w/crlf`
- Inserted `## v0.4.0 — Cooldown Tracking and Full CDM View` at line 3 via an Edit-tool replacement of the unique next-heading string, so git recorded the change as pure insertion (33 additions, 0 deletions) rather than a rewrite of any pre-existing line
- New entry carries the standard `### New Features` / `### Fixes` / `### Known Issues` trio with 8/4/3 bullets (15 total, the top of the plan's 12-15 budget), naming cooldown trackers, the two new cooldown containers, user containers, Merge Mode, centered growth, the settings panel, and the three racial trackers plus cooldown tiles -- never "Eureka! only"
- Known Issues section matches README's exact three D-10-approved public entries (Forever persistence, restricted-content buff overhang, blank charge counts); none of D-11's excluded items (hostile target, potion-in-key, equipped-item) leaked in
- No comparative claims about Blizzard's Cooldown Manager anywhere in the new entry (DOC-05) -- grep-verified absent for "doesn't support", "does not support", "natively"
- Corrected PROJECT.md's stale racial claim in all three locations: the Current Milestone bullet, the Deferred Past v0.4.0 item (now naming `RACE-06`/`RACE-07`), and the Key Decisions table's Status cell (Decision/Rationale cells left untouched as historical record, per the plan's explicit instruction)

## Task Commits

Each task was committed atomically:

1. **Task 1: Pre-flight the CHANGELOG, then append the v0.4.0 entry above v0.3.0** - `e0f21fb` (docs)
2. **Task 2: Correct PROJECT.md's stale racial statement** - `d6310f9` (docs)

**Plan metadata:** committed as part of this SUMMARY.md commit (worktree mode — STATE.md/ROADMAP.md updates deferred to orchestrator)

## Files Created/Modified
- `CHANGELOG.md` - v0.4.0 entry appended above v0.3.0; every pre-existing line byte-identical (`git diff --numstat` shows 33/0)
- `.planning/PROJECT.md` - three racial-statement locations corrected; `git diff --numstat` shows 4/4 (8 total changed lines)

## Decisions Made
- Selected New Features bullets by taking the plan's priority-ordered list literally (first 8 of the 10 candidates listed), rather than re-ranking by my own judgment of importance, since the plan explicitly ordered them by priority for this purpose
- Adapted the Known Issues wording to the CHANGELOG's existing terser bullet style (matching v0.3.0's bolded-lead-in, wrapped-continuation format) rather than copying README's longer prose verbatim, since the two files serve different registers
- After Task 2's first attempt produced a 24-line diff against PROJECT.md (exceeding the plan's `<15 changed lines` acceptance gate), reverted with `git checkout -- .planning/PROJECT.md` (specific file, not a blanket reset) and rewrote as the minimal edit that changes only the words that needed to change, landing at 8 changed lines

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Task 2's first draft exceeded the plan's own diff-size acceptance criterion**
- **Found during:** Task 2, immediately after the first edit and before committing
- **Issue:** The plan's action text asked for a "targeted correction, not a rewrite" but gave prose-level guidance without emphasizing line-count discipline; a full rewrap of the three affected paragraphs (matching the surrounding prose style) produced `git diff --numstat` of `13 11` (24 total changed lines), failing the acceptance criterion's `< 15 changed lines in total` bar
- **Fix:** Reverted PROJECT.md to its pre-edit state with `git checkout -- .planning/PROJECT.md` (a specific tracked file, not a blanket reset — permitted under the destructive-git-prohibition's sanctioned exception) and rewrote as the smallest edit that changes only the 2-3 lines whose wording actually needed to differ, leaving all surrounding lines byte-identical
- **Files modified:** `.planning/PROJECT.md`
- **Commit:** `d6310f9` (the corrected version; the over-sized draft was never committed)

## Issues Encountered

None beyond the diff-size deviation documented above. The pre-flight gate held on the first check (no need to stop and ask the user) and both files' `git ls-files --eol` reported `i/lf w/crlf` unchanged after every edit.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- DOC-04 is closed. DOC-05's CHANGELOG half is closed alongside README's half (closed by 45-01) -- no comparative CDM claims exist anywhere in the public copy
- D-12's correction is applied: `grep -c 'Eureka! alone' .planning/PROJECT.md` and `grep -c 'implements Eureka! only' .planning/PROJECT.md` both equal 0
- Both files are committed before any release tag is cut, satisfying the plan's `<success_criteria>`
- `git status --porcelain -- '*.lua'` is empty in this plan's commits -- no addon behaviour changed, so `stylua` was correctly not run
- This is the last plan in Phase 45 (2/2). Once the orchestrator merges this wave and updates STATE.md/ROADMAP.md, Phase 45 and the v0.4.0 milestone's documentation work is complete, pending the user's own review-and-rewrite pass over both the CHANGELOG (D-01) and README (D-05) wording

---
*Phase: 45-documentation-release-prep*
*Completed: 2026-09-23*

## Self-Check: PASSED

- FOUND: .planning/phases/45-documentation-release-prep/45-02-SUMMARY.md
- FOUND commit: e0f21fb (Task 1)
- FOUND commit: d6310f9 (Task 2)
