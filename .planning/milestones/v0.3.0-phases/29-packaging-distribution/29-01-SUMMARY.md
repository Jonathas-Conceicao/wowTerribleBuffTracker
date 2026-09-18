---
phase: 29-packaging-distribution
plan: 01
subsystem: infra
tags: [github-actions, bigwigs-packager, pkgmeta, changelog, release-workflow]

# Dependency graph
requires:
  - phase: 25 (TOC drift guard)
    provides: scripts/check-toc.ps1 with a dormant third assertion written against
      .pkgmeta-<flavor> files that did not yet exist
provides:
  - .pkgmeta-mainline and .pkgmeta-camelot (flavor-pure packager configs, .pkgmeta deleted)
  - a serialised two-entry job matrix in release.yml that packages each flavor separately
  - a v0.3.0 CHANGELOG.md entry naming the tested Forever build
  - a release-time verification checklist for DIST-03..07 (see Deferred Verification below)
affects: [30-cleanup, FTOOL-01]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "flavor-pure packager configs: one .pkgmeta-<flavor> per client, differing only in
      a single cross-ignore line naming the other flavor's TOC"
    - "-g <flavor> passed explicitly to BigWigsMods/packager because game-type
      auto-derivation reads the full checkout (both TOCs), not the staged/ignored copy"

key-files:
  created: [.pkgmeta-mainline, .pkgmeta-camelot]
  modified: [.github/workflows/release.yml, CHANGELOG.md]

key-decisions:
  - "D-04 overridden: -g ${{ matrix.flavor }} IS passed, contradicting CONTEXT.md's original
    text, because release.sh's TOC discovery and game-type derivation read the checkout
    unconditionally (both TOCs always found), not the ignore-filtered staged copy."
  - "D-01a: shared ignore list's '- .pkgmeta' entry replaced with '- .pkgmeta-mainline' and
    '- .pkgmeta-camelot' in both files identically (functionally inert; dotfiles are pruned
    before ignore is consulted, per release.sh:1829)."

requirements-completed: [DIST-01, DIST-02, DIST-08]

# Metrics
duration: ~15min
completed: 2026-09-18
---

# Phase 29 Plan 01: Packaging & Distribution Summary

**Split .pkgmeta into flavor-pure .pkgmeta-mainline/.pkgmeta-camelot, converted release.yml into a serialised two-flavor packager matrix with an explicit `-g` override, and wrote the v0.3.0 CHANGELOG entry — all statically verified, none of it proven against a real tag.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-09-18T21:39:00-03:00 (approx, first commit 21:39:28)
- **Completed:** 2026-09-18T21:40:31-03:00 (last commit)
- **Tasks:** 3/3 completed
- **Files modified:** 4 (`.pkgmeta` deleted, `.pkgmeta-mainline` created, `.pkgmeta-camelot` created, `.github/workflows/release.yml` modified, `CHANGELOG.md` modified)

## Accomplishments
- `.pkgmeta` replaced by two flavor-pure configs that agree everywhere except each one's single cross-ignore line naming the *other* flavor's TOC
- `scripts/check-toc.ps1`'s third assertion fired for the first time in the repo's history — exit 0, `check-toc: OK`, zero `skip:` lines
- `release.yml`'s single job became a `max-parallel: 1` matrix over `[mainline, camelot]`, each invoking `BigWigsMods/packager@v2` with its own `-m`, an explicit `-g`, and a `{game-type}`-templated zip name
- `CHANGELOG.md` gained a v0.3.0 entry as the first `##` section, naming build `1.60.1.69913` / interface `16001`, in user-facing voice matching the v0.2.x entries

## Task Commits

Each task was committed atomically on branch `v0.3-wow-forever-compatibility`:

1. **Task 1: Split .pkgmeta into flavor-pure configs, light up check-toc's third assertion** - `7f7a299` (build)
2. **Task 2: Turn release.yml into a serialised two-flavor matrix** - `33512d1` (ci)
3. **Task 3: Write the v0.3.0 CHANGELOG entry** - `08fd95b` (docs)

No separate plan-metadata commit was made as part of task execution; this SUMMARY and STATE/ROADMAP updates are committed as the final phase-metadata commit per the executor workflow.

_Note: No TDD tasks in this plan; no test → feat → refactor sequences._

## Files Created/Modified
- `.pkgmeta-mainline` - retail-flavor packager config; ignores `TerribleBuffTracker_Camelot.toc`
- `.pkgmeta-camelot` - forever-flavor packager config; ignores `TerribleBuffTracker_Mainline.toc`
- `.pkgmeta` - deleted (git rm, tracked as a rename to `.pkgmeta-mainline` by git's similarity heuristic, but content diverges by the added cross-ignore line and the `.pkgmeta` ignore-list swap)
- `.github/workflows/release.yml` - single job converted to a `strategy.matrix.flavor: [mainline, camelot]` job with `max-parallel: 1`; packager step's `args` now `-m .pkgmeta-${{ matrix.flavor }} -g ${{ matrix.flavor }} -n "{package-name}-{project-version}-{game-type}"`
- `CHANGELOG.md` - new first `## v0.3.0 — WoW Forever Support` section ahead of `## v0.2.6`

## Decisions Made

- **`-g ${{ matrix.flavor }}` is passed, overriding D-04 as originally (and incorrectly) written in `29-CONTEXT.md`.** CONTEXT.md's struck-through D-04 claimed `-g` was unnecessary because each build sees exactly one TOC. That premise is false: `release.sh`'s TOC discovery (`release.sh:1401`, `1419`) globs the checkout unconditionally with no ignore filtering, so both flavor TOCs are always found regardless of what any `.pkgmeta-<flavor>`'s `ignore` list says — the `ignore` list governs only `copy_directory_tree`'s staged-copy skip logic (`release.sh:1157`, `1852-1861`), not TOC discovery or `set_build_version`. With two TOCs always discovered, `set_build_version` always populates two keys in `game_type_version`, and `game_type` auto-derives only when exactly one key exists (`release.sh:1380-1383`) — so without `-g`, `game_type` stays empty, `{game-type}` collapses to the empty string, and **both jobs would emit the identically-named `TerribleBuffTracker-v0.3.0-.zip`**, colliding on one release (DIST-03, DIST-05 failure) while each upload gets tagged for both game versions (DIST-06 failure). `-g mainline` / `-g camelot` (`release.sh:293-296`) is the only mechanism that reaches `game_type` at all. This is flagged, not silent, and is recorded as **Deferred Question 1** below — reverting is a one-line deletion in `release.yml` if the user disagrees after reading the citations, but doing so is expected to fail DIST-03/05/06 at the first real tag.
- **D-01a — the shared `ignore` list's `- .pkgmeta` entry became `- .pkgmeta-mainline` + `- .pkgmeta-camelot`** in both files identically. This is functionally inert: the packager prunes dotfiles from the copy tree before consulting the `ignore` list at all (`release.sh:1829`), so no packaged output changes either way. The edit exists purely to avoid leaving an orphan `ignore` entry naming a file this phase deletes — exactly the kind of leftover Phase 30's cleanup pass would otherwise have to catch. Recorded as **Deferred Question 2** below; reverting to a literal `- .pkgmeta` changes nothing in the zips.
- **No YAML parser was available offline** (no `python`, `yq`, `js-yaml` on this machine). `release.yml` was linted structurally — zero tabs, all leading-space counts even, every required key/value pattern present via `grep`/`awk` — rather than truly parsed. The first genuine YAML parse of this file happens at GitHub's ingestion when the first `v0.3*` tag is pushed. This is **Deferred Question 3**.

## Deviations from Plan

None — plan executed exactly as written. No Rule 1/2/3 auto-fixes were needed; both `.pkgmeta` files, the `release.yml` matrix, and the CHANGELOG entry matched the plan's literal specification on the first pass, and every gate (1A, 1B, 2A, 2B, 3A, 3B) passed without rework.

## Issues Encountered

None. All six task-level gates and both phase-level scope-fence checks passed on the first run.

## User Setup Required

None - no external service configuration required. `CF_API_KEY` and `WAGO_API_TOKEN` remain commented out, unchanged.

## Deferred Verification — carried forward verbatim

**DIST-01, DIST-02, and DIST-08 are built and statically verified by this plan. DIST-03 through DIST-07 are OPEN — they require a real tag push, which this plan is forbidden from doing, and nothing in this plan proves the CI actually produces two correctly-tagged zips.**

When the first `v0.3.0` tag is actually pushed, open the workflow run and read the full log of **both** matrix jobs — not just the green check. The packager omits a game-version tag *silently* when a store's version list lacks it; a green run is fully compatible with a mis-tagged upload.

| # | Req | What to look for in the CI log / release page |
|---|---|---|
| 1 | DIST-03 | Two assets on the release, distinctly named. Expect `TerribleBuffTracker-v0.3.0-retail.zip` and `TerribleBuffTracker-v0.3.0-forever.zip`. **A trailing-dash or duplicate name means `game_type` came out empty.** |
| 2 | DIST-04 | Download and unzip both. The retail zip contains `TerribleBuffTracker_Mainline.toc` and NOT `_Camelot.toc`; the forever zip the reverse. Neither contains `scripts/`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `*.png`, or any `.pkgmeta*`. |
| 3 | DIST-05 | Both assets present simultaneously. The second job did not replace or drop the first job's asset. `max-parallel: 1` should make this boring; confirm it anyway. |
| 4 | DIST-06 | In each job's log, the game version line: the mainline job reports `12.1.0` only, the camelot job `1.60.1` only. **Neither should report both.** Grep the log for `game version` / `not compatible` / any game-version-match warning. |
| 5 | DIST-07 | Each job's `RELEASE_NOTES.md` is the v0.3.0 section and nothing else. The GitHub release body should read as the v0.3.0 changelog entry, with no v0.2.6 content bleeding in. |

Hotfixes after this first real release go **straight to main**, per the user's decision — not back through a milestone branch.

## Deferred Questions for Human Review

1. **`-g` is passed, overriding D-04 as literally written.** See "Decisions Made" above for the full citation chain (`release.sh:1401`, `1419`, `1157`, `1852-1861`, `1380-1383`, `293-296`). If you disagree, reverting is deleting `-g ${{ matrix.flavor }}` from one line of `release.yml` — but expect DIST-03, DIST-05, and DIST-06 to fail on the first real tag if you do.
2. **D-01a: the shared `ignore` list's `- .pkgmeta` entry became `- .pkgmeta-mainline` + `- .pkgmeta-camelot`.** Functionally inert either way (packager prunes dotfiles before consulting `ignore`); pre-empts Phase 30's orphan-config cleanup. Revert to a literal `- .pkgmeta` if you'd rather the list stay byte-identical to v0.2.6's — nothing in the zips changes.
3. **No YAML parse was possible offline.** `release.yml` was linted structurally, not parsed. The first genuine parse is GitHub's, at tag time. A workflow-syntax error would surface there as a failed run, not a bad zip.
4. **CurseForge's Forever support is still unverified.** Wago's was confirmed via its live public API; CurseForge only at the public-search-filter level. Moot while the tokens are commented out; becomes real the moment `FTOOL-01` lands.

## Traceability Note

| Requirement | Status |
|---|---|
| DIST-01 | Complete — `.pkgmeta-mainline`/`.pkgmeta-camelot` exist, `.pkgmeta` deleted, gates 1A/1B pass |
| DIST-02 | Complete (statically) — matrix, `max-parallel: 1`, `-m`/`-g`/`-n` args, gates 2A/2B pass |
| DIST-03 | **OPEN** — needs a real tag; see Deferred Verification row 1 |
| DIST-04 | **OPEN** — needs a real tag; see Deferred Verification row 2 |
| DIST-05 | **OPEN** — needs a real tag; see Deferred Verification row 3 |
| DIST-06 | **OPEN** — needs a real tag; see Deferred Verification row 4 |
| DIST-07 | **OPEN** — needs a real tag; see Deferred Verification row 5 |
| DIST-08 | Complete — v0.3.0 is the first `##` section, gates 3A/3B pass |

## Next Phase Readiness

- Packaging machinery is correct by construction and by static gate; ready for a real `v0.3.0` tag whenever the milestone is closed.
- Phase 30 (cleanup) should audit that no leftover `.pkgmeta` references remain anywhere else in the repo (docs, scripts) beyond what this plan touched.
- FTOOL-01 (re-enabling CF/Wago tokens) remains explicitly out of scope and untouched.
- Blocker for full requirement closure: DIST-03..07 cannot close until the first real tag push and manual log review per the checklist above.

---
*Phase: 29-packaging-distribution*
*Completed: 2026-09-18*

## Self-Check: PASSED

All claimed files found on disk: `.pkgmeta-mainline`, `.pkgmeta-camelot`, `.github/workflows/release.yml`, `CHANGELOG.md`, this SUMMARY.
All claimed commit hashes found in `git log --oneline --all`: `7f7a299`, `33512d1`, `08fd95b`.
