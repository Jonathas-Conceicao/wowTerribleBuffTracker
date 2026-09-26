---
phase: 42-cleanup
plan: 01
subsystem: release-tooling
tags: [wow-addon, packaging, bigwigs-packager, dead-code, lua]

# Dependency graph
requires:
  - phase: 32-release-automation
    provides: .pkgmeta and the BigWigs Packager release workflow whose ignore list this plan corrects
  - phase: 41-racial-meta-tracker
    provides: RacialProviderMixin, whose namespace export this plan removes
provides:
  - .pkgmeta ignore list covering every non-runtime top-level tracked path
  - Providers.lua with no zero-reader export added by this milestone
affects: [42-02, 42-03, 42-04, 42-05, 42-06, 44-release]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Packaging coverage read: `git ls-files | sed 's|/.*||' | sort -u` checked by eye against
       .pkgmeta's ignore list, since the zip's real contents are only observable in CI."

key-files:
  created: []
  modified:
    - .pkgmeta (ignore list gained .planning, .github, .gitattributes)
    - Providers.lua (deleted `ns.RacialProviderMixin = RacialProviderMixin`)

key-decisions:
  - "Assets/ deliberately left out of the ignore list: it holds only README screenshots, already
     covered by the existing *.png glob. A directory entry would be redundant and would silently
     start excluding a non-png asset added there deliberately."
  - "The three new ignore entries were appended to the end of the list rather than sorted in, so
     the diff is three added lines and nothing else."
  - "The nine other unreferenced ns.* exports in Providers.lua were left untouched — all predate
     v0.4.0 (Phases 17-22), where PROJECT.md's no-refactor decision still stands."

patterns-established:
  - "Line endings are per-path in this repo (.gitattributes pins .pkgmeta to eol=lf, *.lua to
     eol=crlf). Appending to a file with a shell redirect must match that file's pinned ending —
     verify with `git ls-files --eol <path>` (w/ column), not with grep or awk, which this
     Git Bash opens in text mode and which therefore report no CR at all."

requirements-completed: []

# Metrics
duration: 9min
completed: 2026-09-22
---

# Phase 42 Plan 01: Release Payload & Dead Export Summary

**Stopped 334 internal planning files, the CI workflow directory and `.gitattributes` from shipping to players in every release zip, and deleted the one namespace export this milestone added that nothing reads.**

## Performance

- **Duration:** ~9 min
- **Completed:** 2026-09-22
- **Tasks:** 2
- **Files modified:** 2
- **Behaviour changes:** none (one packaging-input change, one dead-line deletion)

## Accomplishments
- `.pkgmeta`'s `ignore:` list gained `.planning`, `.github` and `.gitattributes`. BigWigs Packager ships everything the list does not name, so before this change every release zip carried the full planning tree — roadmaps, requirements, phase plans, contexts and verification reports — straight into players' AddOns folders, alongside the CI workflow and the git attributes file.
- Ran the top-level coverage read (`git ls-files | sed 's|/.*||' | sort -u`) against the corrected ignore list. Every tracked top-level path is now accounted for: runtime files, or named in the ignore list, or covered by the `*.png` glob.
- Deleted `ns.RacialProviderMixin = RacialProviderMixin` from `Providers.lua`. The export had one writer and zero readers — the only consumer of the mixin is the `CreateFromMixins` call on the following line, which reads the file-local upvalue.
- Release tooling read end to end previously (`scripts/install.bat`, `scripts/release.bat`, `.github/workflows/release.yml`); per the plan they were not re-read and needed no change. Success criterion 4's "read end to end" clause is satisfied by that read plus this `.pkgmeta` fix.

## Task Commits

1. **Task 1: `.pkgmeta` — stop shipping the planning directory** - `295c601` (build)
2. **Task 2: `Providers.lua` — drop the unread `RacialProviderMixin` export** - `7b3eb87` (refactor)

**Plan metadata:** this SUMMARY.md is intentionally left uncommitted — phase summaries are committed together in the phase close-out `docs(42):` commit, as Phase 41's were (`dbefb60`).

## Files Created/Modified
- `.pkgmeta` — three lines appended to `ignore:`: `.planning`, `.github`, `.gitattributes`. `package-as:`, `manual-changelog:` and the eleven existing ignore entries untouched and unreordered.
- `Providers.lua` — one line deleted (line 906, `ns.RacialProviderMixin = RacialProviderMixin`). It carried no attached comment, so nothing else moved. The `RacialProviderMixin` table, its four methods and the `CreateFromMixins(SpellProviderBaseMixin, RacialProviderMixin)` call all survive; `grep -c 'RacialProviderMixin' Providers.lua` returns 7.

## Decisions Made
- Left `Assets/` out of the ignore list (plan instruction, reconfirmed by reading: `git ls-files Assets` returns exactly three `.png` screenshots, all covered by the existing glob).
- Appended rather than sorted the new entries, keeping the diff to three added lines.
- Left the nine pre-v0.4.0 unreferenced exports alone; they belong to plan 42-06's audit as an out-of-scope finding, not to this plan.
- Left this SUMMARY uncommitted for the phase close-out commit.

## Deviations from Plan

**1. [Rule 3 - Blocking issue] Appended `.pkgmeta` lines had to be rewritten from CRLF to LF**
- **Found during:** Task 1
- **Issue:** The shell append wrote the three new lines with CRLF. `.gitattributes` pins `.pkgmeta text eol=lf`, so the file became mixed (`git ls-files --eol` reported `w/mixed`). This is exactly the class of line-ending churn the plan's constraints forbid, and it would have been committed invisibly — `grep -c $'\r'` reported **0** on the same file, because this Git Bash opens files in text mode and strips CR before the pattern is matched.
- **Fix:** `perl -i -pe 's/\r\n$/\n/' .pkgmeta`, re-verified with `git ls-files --eol .pkgmeta` → `i/lf w/lf attr/text eol=lf`.
- **Files modified:** `.pkgmeta` (pre-commit; the committed diff is clean)
- **Committed in:** `295c601` (the correction was made before staging, so it is not a separate commit)

---

**Total deviations:** 1 (a self-inflicted line-ending slip, caught and corrected before staging)
**Impact on plan:** None. Both commits contain exactly the diffs the plan specifies.

## Discrepancies Between Plan and Code

- The plan's Task 1 verify block describes the addon's runtime file set as "the six `.lua` files, `CDMTab.xml`, `TerribleBuffTracker.toc`, `tbt_icon_64x64.blp`". There are **seven** tracked `.lua` files at top level. Six are listed in `TerribleBuffTracker.toc`; the seventh, `CDMTab.lua`, is loaded by `CDMTab.xml` via `<Script file="CDMTab.lua"/>` and is equally a runtime file. The count in the plan's prose is wrong; the coverage read itself still passes, since `CDMTab.lua` is a runtime file either way and must not be ignored. No action taken.
- The plan gives the export's location as "around line 906" — it was exactly line 906. No other mismatch.
- `Display.lua:1466` mentions `RacialProviderMixin` in a comment. This is a prose reference to the mixin, not a read of the deleted namespace field, and was correctly left in place.

## Issues Encountered
None beyond the line-ending slip recorded above.

## Verification Performed
- `stylua .` (no flags, repo root) ran clean and changed nothing; `stylua --check .` exits 0.
- `git diff` across both commits: `.pkgmeta` +3 lines, `Providers.lua` -1 line. No whitespace-only or line-ending-only hunks.
- `git ls-files --eol` on all `.lua` files: every one still `w/crlf`, matching `.gitattributes`. `.pkgmeta` is `w/lf`, matching its pin.
- `cat *.lua *.xml | grep -c 'ns[.:]RacialProviderMixin'` → `0`. `grep -c 'RacialProviderMixin' Providers.lua` → `7` (≥4 required).
- All nine pre-v0.4.0 `ns.*` exports still present (one `^ns\.<name> = ` match each).
- `git diff --diff-filter=D --name-only HEAD~2 HEAD` → empty; no file deletions.
- `CHANGELOG.md` untouched — `git diff --name-only HEAD~2 HEAD` lists only `.pkgmeta` and `Providers.lua`.
- Branch unchanged: `milestone/v0.4.0-cooldown-tracking-cdm-view`. No branch created, renamed or switched.

**Not verifiable here, by design:** the `.pkgmeta` fix cannot be confirmed locally. BigWigs Packager only runs in CI against a real tag, so the zip's contents are not observable from the working tree. Real confirmation belongs to the first release and is already tracked in `STATE.md`'s "two things to watch at that first release". No local packaging run was invented to fake it.

## User Setup Required
None.

## Next Phase Readiness
- Plans 42-02 through 42-06 are unblocked; this plan touched no code either reads (one packaging file, one deleted dead line).
- Plan 42-06's audit inherits one recorded out-of-scope finding: nine unreferenced `ns.*` exports in `Providers.lua` (`ns.SpellProviderBaseMixin`, `ns.TrinketProviderMixin`, `ns.PotProviderMixin`, `ns.LustProviderMixin`, `ns.UserSpellProviderMixin`, `ns.TRINKET_SPELLS`, `ns.POT_SPELLS`, `ns.TRINKET_ITEM_IDS`, `ns.POT_ITEM_IDS`), all pre-v0.4.0 and therefore protected by `PROJECT.md`.
- Phase 44 (release) should watch the first tag push to confirm the zip no longer carries `.planning`.

---
*Phase: 42-cleanup*
*Completed: 2026-09-22*

## Self-Check: PASSED

- `.planning/phases/42-cleanup/42-01-SUMMARY.md` exists.
- Commits `295c601` and `7b3eb87` exist in `git log`.
- Working tree otherwise clean; only this SUMMARY is untracked, by design.
