---
phase: 29-packaging-distribution
verified: 2026-09-18T21:41:00-03:00
status: human_needed
score: 34/34 gate assertions verified statically; 5 observable outcomes unverifiable without a real tag push
---

# Phase 29: Packaging & Distribution Verification Report

**Phase Goal:** One pushed tag produces two flavor-pure zips — a retail one and a forever one — both published cleanly to the same GitHub release with correct game-version tagging.
**Verified:** 2026-09-18T21:41:00-03:00
**Status:** human_needed

## Goal Achievement

This phase is scoped, by explicit user decision (2026-09-18: *"do the impl and we will test once we close the milestone and add any hotfix straight to main later if needed"*), to **implementation only**. DIST-01, DIST-02, and DIST-08 are built and statically verified here. DIST-03 through DIST-07 require a real tag push and CANNOT be observed from this environment — they are designed against, not proven, and are recorded as OPEN below.

### Observable Truths — 29-01-PLAN.md

Truths drawn from `29-01-PLAN.md`'s `must_haves.truths` frontmatter.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The repo root holds `.pkgmeta-mainline` and `.pkgmeta-camelot`, and no `.pkgmeta` | VERIFIED | `test -f .pkgmeta-mainline && test -f .pkgmeta-camelot && test ! -e .pkgmeta` passed (GATE-1A) |
| 2 | The two pkgmeta files are byte-identical once each one's cross-ignore line is removed | VERIFIED | `diff <(grep -v Camelot .pkgmeta-mainline) <(grep -v Mainline .pkgmeta-camelot)` produced zero diff (GATE-1A) |
| 3 | `scripts/check-toc.ps1` exits 0 and prints no `skip:` line — its third assertion actually executes for both flavors for the first time in the repo's history | VERIFIED | Ran the script directly: exit code 0, output `check-toc: OK (...)`, zero `skip:` lines (GATE-1B) |
| 4 | `release.yml` runs the packager once per flavor, serialised, each job pointing at its own pkgmeta and naming its zip with `{game-type}` | VERIFIED | `max-parallel: 1`, `flavor: [mainline, camelot]`, `-m .pkgmeta-${{ matrix.flavor }}`, `{package-name}-{project-version}-{game-type}` all present (GATE-2A) |
| 5 | The commented-out CurseForge and Wago credentials are still comments | VERIFIED | `^\s*#\s*CF_API_KEY:` and `^\s*#\s*WAGO_API_TOKEN:` matched; uncommented forms absent (GATE-2B) |
| 6 | `CHANGELOG.md`'s first `##` section is the v0.3.0 entry and it names build `1.60.1.69913` and interface `16001` | VERIFIED | `awk` extraction into scratchpad: first line `## v0.3.0 —...`, body contains both strings (GATE-3A) |
| 7 | No Lua file and no `.toc` file changed | VERIFIED | `git diff --name-only HEAD~3..HEAD -- '*.lua' '*.toc'` returned empty |

**Score:** 7/7 truths statically verified.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.pkgmeta-mainline` | Retail-flavor packager config; ignores `TerribleBuffTracker_Camelot.toc`; contains `package-as: TerribleBuffTracker` | VERIFIED — EXISTS + SUBSTANTIVE | Contains `package-as: TerribleBuffTracker`, `manual-changelog` block, shared ignore list, cross-ignore line for `TerribleBuffTracker_Camelot.toc`; does not ignore its own TOC |
| `.pkgmeta-camelot` | Forever-flavor packager config; ignores `TerribleBuffTracker_Mainline.toc`; contains `package-as: TerribleBuffTracker` | VERIFIED — EXISTS + SUBSTANTIVE | Same shape, cross-ignore line for `TerribleBuffTracker_Mainline.toc`; does not ignore its own TOC |
| `.github/workflows/release.yml` | Two-flavor serialised release matrix; contains `max-parallel: 1` | VERIFIED — EXISTS + SUBSTANTIVE | `strategy.max-parallel: 1`, `matrix.flavor: [mainline, camelot]`, packager `args` carries `-m`, `-g`, and `-n` with `{game-type}` |
| `CHANGELOG.md` | v0.3.0 user-facing release notes, consumed verbatim by the awk step; contains `1.60.1.69913` | VERIFIED — EXISTS + SUBSTANTIVE | First `##` section is `## v0.3.0 — WoW Forever Support`, names build `1.60.1.69913` / interface `16001`, `### New Features` and `### Fixes` sections present |

**Artifacts:** 4/4 verified.

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `.github/workflows/release.yml` | `.pkgmeta-mainline` / `.pkgmeta-camelot` | `-m .pkgmeta-${{ matrix.flavor }}` | WIRED | Literal pattern present in packager step args |
| `.github/workflows/release.yml` | `CHANGELOG.md` | awk first-`##` extraction into `RELEASE_NOTES.md` | WIRED | `awk '/^## /{if(found) exit; found=1} found' CHANGELOG.md > RELEASE_NOTES.md` present, unchanged from pre-phase, still inside the matrix job |
| `.pkgmeta-mainline` / `.pkgmeta-camelot` | `scripts/check-toc.ps1` assertion 3 | cross-ignore YAML entry naming the other flavor's TOC | WIRED | Both files present; guard confirmed to read them and pass with zero `skip:` lines |

**Wiring:** 3/3 connections verified statically.

## Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|-----------------|
| DIST-01: `.pkgmeta-mainline` / `.pkgmeta-camelot` exist, flavor-pure, original `.pkgmeta` gone | SATISFIED | None — fully verifiable offline, gates passed |
| DIST-02: `release.yml` runs the packager once per flavor via a serialised job matrix | SATISFIED (statically) | None for the static contract; no YAML parser was available offline, so the file was linted structurally, not truly parsed — first genuine parse is GitHub's, at tag time |
| DIST-03: One pushed tag produces two distinctly-named zips | **OPEN** | Requires a real tag push. A trailing-dash or duplicate zip name would indicate `game_type` came out empty — see Deferred Verification below |
| DIST-04: Each zip contains only its own flavor's TOC | **OPEN** | Requires downloading and unzipping both real release assets |
| DIST-05: Both matrix jobs publish to the same release without racing/clobbering | **OPEN** | Requires observing a real release with both assets present simultaneously |
| DIST-06: Each upload's game-version tag is correct (no cross-tagging) | **OPEN** | Requires reading both jobs' CI logs in full at tag time |
| DIST-07: `RELEASE_NOTES.md` generates correctly once per matrix job | **OPEN** | Requires reading both jobs' CI logs / release body at tag time |
| DIST-08: `CHANGELOG.md` documents Forever support, naming build and interface | SATISFIED | None — fully verifiable offline, gates passed |

**Coverage:** 3/8 requirements fully satisfied (DIST-01, DIST-02, DIST-08); 5/8 explicitly OPEN pending a real tag push (DIST-03..07), per the user's own scope decision for this plan.

## Anti-Patterns Found

None. No `TODO`/`FIXME`/"coming soon" markers introduced. No stub data paths. The `.pkgmeta` → `.pkgmeta-mainline`/`.pkgmeta-camelot` split removes an orphan-risk rather than creating one (D-01a swaps the shared ignore list's `- .pkgmeta` entry for the two new filenames, so no ignore entry references a deleted file). No flavor-detection tokens were introduced in any Lua file (none touched at all — this phase is Lua/TOC-free by construction, confirmed by the empty `git diff --name-only HEAD~3..HEAD -- '*.lua' '*.toc'`).

## Human Verification Required

### 1. DIST-03 — two distinctly-named zips on the release
**Test:** Push the first real `v0.3.0` tag, open the GitHub release, and confirm two assets exist: `TerribleBuffTracker-v0.3.0-retail.zip` and `TerribleBuffTracker-v0.3.0-forever.zip`.
**Expected:** Two distinct names, no trailing dash, no collision.
**Why human:** Requires an actual tag push, which this plan is forbidden from performing (D-15).

### 2. DIST-04 — each zip is flavor-pure
**Test:** Download and unzip both assets. Confirm the retail zip contains `TerribleBuffTracker_Mainline.toc` and NOT `_Camelot.toc`; the forever zip the reverse. Confirm neither contains `scripts/`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `*.png`, or any `.pkgmeta*`.
**Expected:** Full flavor purity per the `ignore` cross-entries built in Task 1.
**Why human:** Requires a real packaged artifact from a real CI run.

### 3. DIST-05 — no same-release clobber
**Test:** Confirm both assets are present simultaneously on the release page after both matrix jobs complete.
**Expected:** `max-parallel: 1` should make the upload order deterministic and collision-free; confirm anyway.
**Why human:** Requires observing the actual release page after a real run.

### 4. DIST-06 — correct per-upload game-version tag
**Test:** Read each matrix job's full CI log. Confirm the mainline job reports game version `12.1.0` only, and the camelot job reports `1.60.1` only.
**Expected:** Neither job reports both versions. The packager omits a game-version tag silently when a store's version list lacks it — a green run is compatible with a mis-tagged upload, so the log must be read in full, not just the pass/fail status.
**Why human:** Requires reading a real workflow run's log.

### 5. DIST-07 — RELEASE_NOTES.md generated correctly per job
**Test:** Confirm each job's `RELEASE_NOTES.md` (visible in its own log, and reflected in the shared release body) is the v0.3.0 section and nothing else — no v0.2.6 content bleeding in.
**Expected:** Both jobs independently produce identical, correct release notes since each runs in its own workspace.
**Why human:** Requires inspecting a real workflow run's artifacts/log.

## Gaps Summary

**No code-level gaps found in the implementation scope this plan owns.** All 7 `must_haves.truths`, all 4 required artifacts, and all 3 key links from `29-01-PLAN.md`'s frontmatter are statically verified. Every task-level gate (1A, 1B, 2A, 2B, 3A, 3B) passed on first execution with zero deviations and zero auto-fixes.

**The five open items (DIST-03..07) are not gaps in this phase's work — they are out of this phase's declared scope**, per the user's explicit 2026-09-18 decision to implement now and verify at real-release time. This report's `human_needed` status reflects that honestly: the phase is not closeable yet, but nothing in the implementation is known or suspected to be broken. The one load-bearing engineering judgment call in this plan — passing `-g ${{ matrix.flavor }}` against CONTEXT.md's original (now struck-through) D-04 — is backed by direct citations against `BigWigsMods/packager`'s `release.sh` (lines 293-296, 1157, 1380-1383, 1401, 1419, 1852-1861) and is flagged for human ratification, not silently assumed correct.

## Recommended Fix Plans

None. No code gaps exist. The remaining work is the release-time verification checklist below, which by design cannot be executed as a "fix plan" — it requires a real tag push and is deferred to milestone close, per the user's own scope decision.

## Deferred Verification — release-time checklist (carried forward verbatim from 29-01-PLAN.md)

**When the first v0.3.0 tag is actually pushed, open the workflow run and read the full log of BOTH matrix jobs — not just the green check.** The packager omits a game-version tag *silently* when a store's version list lacks it; a green run is fully compatible with a mis-tagged upload.

| # | Req | What to look for in the CI log / release page |
|---|---|---|
| 1 | DIST-03 | Two assets on the release, distinctly named. Expect `TerribleBuffTracker-v0.3.0-retail.zip` and `TerribleBuffTracker-v0.3.0-forever.zip`. A trailing-dash or duplicate name means `game_type` came out empty. |
| 2 | DIST-04 | Download and unzip both. The retail zip contains `TerribleBuffTracker_Mainline.toc` and NOT `_Camelot.toc`; the forever zip the reverse. Neither contains `scripts/`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `*.png`, or any `.pkgmeta*`. |
| 3 | DIST-05 | Both assets present simultaneously. The second job did not replace or drop the first job's asset. `max-parallel: 1` should make this boring; confirm it anyway. |
| 4 | DIST-06 | In each job's log, the game version line: the mainline job reports `12.1.0` only, the camelot job `1.60.1` only. Neither should report both. Grep the log for `game version` / `not compatible` / any game-version-match warning. |
| 5 | DIST-07 | Each job's `RELEASE_NOTES.md` is the v0.3.0 section and nothing else. The GitHub release body should read as the v0.3.0 changelog entry, with no v0.2.6 content bleeding in. |

Hotfixes after this first real release go **straight to main**, per the user — not back through a milestone branch.

## Deferred Questions for Human Review (carried from 29-01-SUMMARY.md)

1. **`-g` is passed, overriding D-04 as literally written.** CONTEXT.md's D-04 forbade `-g` on the premise that the `ignore` list leaves each build seeing one TOC. Reading `release.sh` shows the `ignore` list governs only the staged copy, while game-version derivation always reads the full checkout — so both TOCs are always seen and `game_type` is left empty, which collapses `{game-type}` to nothing and collides both zip names. If you disagree, reverting is deleting `-g ${{ matrix.flavor }}` from one line of `release.yml` — but expect DIST-03, DIST-05, and DIST-06 to fail on the first tag if you do.
2. **D-01a: the shared `ignore` list's `- .pkgmeta` entry became `- .pkgmeta-mainline` + `- .pkgmeta-camelot`.** Functionally inert either way — the packager prunes dotfiles before consulting `ignore` — so this is orphan hygiene for a deleted filename, pre-empting Phase 30's cleanup pass. Revert to a literal `- .pkgmeta` if you'd rather the list stay byte-identical to v0.2.6's.
3. **No YAML parse was possible offline.** No `python`, `yq`, or `js-yaml` on this machine, so `release.yml` was linted structurally (no tabs, even indentation, required keys present) rather than parsed. The first genuine parse is GitHub's, at tag time. A workflow-syntax error would surface there as a failed run, not a bad zip.
4. **CurseForge's Forever support is still unverified.** Wago's was confirmed via its live public API; CurseForge only at the public-search-filter level. Moot while the tokens are commented out; becomes real the moment `FTOOL-01` lands.

## Verification Metadata

**Verification approach:** Goal-backward (derived from `29-01-PLAN.md`'s `must_haves` frontmatter and ROADMAP Phase 29's six success criteria)
**Must-haves source:** `29-01-PLAN.md` frontmatter (`must_haves.truths`, `must_haves.artifacts`, `must_haves.key_links`)
**Automated checks:** 6 gate blocks (1A, 1B, 2A, 2B, 3A, 3B) totaling 34 individual assertions across the plan's task-level `<verify>` blocks, all passed on first execution; phase-level scope-fence checks (no `.lua`/`.toc` diff, no stray `RELEASE_NOTES.md`, no `v0.3*` tag, no unpushed-branch tracking issue) re-confirmed after all three commits landed
**Human checks required:** 5 (all require a real tag push; none launchable or simulatable from this environment)
**Total verification time:** ~5 min (shared with plan execution; gates were run inline during Task execution and re-confirmed here)

---
*Verified: 2026-09-18T21:41:00-03:00*
*Verifier: Claude (executor, self-verification against plan gates)*
