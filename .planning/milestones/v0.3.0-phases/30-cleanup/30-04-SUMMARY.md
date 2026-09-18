---
phase: 30-cleanup
plan: 04
subsystem: packaging
tags: [pkgmeta, release-bat, release-yml, duplication-audit, phase-29-review]

requires:
  - phase: 30-01
    provides: stylua.toml (the new root file both pkgmeta configs must ignore)
  - phase: 29-packaging-distribution
    provides: .pkgmeta-mainline, .pkgmeta-camelot, the release.yml two-flavor matrix, CHANGELOG v0.3 entry
provides:
  - v0.3 duplication audit (install.bat confirmed already-unified; .pkgmeta-* duplication confirmed structurally irreducible against the pinned packager source)
  - stylua.toml ignored by both packaging configs
  - Three deferred-finding todos capturing irreducible/out-of-scope duplication
  - End-to-end read-only review of release.bat and release.yml against the two-flavor flow
  - Phase 29 Validated entry and corrected .pkgmeta doc references
  - Phase 30 exit gates confirmed green
affects: []

tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/todos/pending/2026-09-18-pkgmeta-shared-ignore-list-can-drift.md
    - .planning/todos/pending/2026-09-18-runtime-file-set-enumerated-three-places.md
    - .planning/todos/pending/2026-09-18-release-bat-pushes-main-with-no-branch-guard.md
  modified: [.pkgmeta-mainline, .pkgmeta-camelot, CLAUDE.md, .planning/PROJECT.md]

key-decisions:
  - "install.bat needed no edit — Phase 26 already built it as a single data-driven FILES x FLAVORS loop with no per-client branch"
  - "The two .pkgmeta-* files' shared content is structurally irreducible: the BigWigs packager's YAML-lite parser (verified against the pinned release.sh source) has no include/inherit/extends/merge directive"
  - "Three findings captured as deferred todos rather than fixed: shared ignore-list drift, three-place file-set enumeration, release.bat's unguarded push origin main"
  - "Phase 29's two-zip outcome (DIST-03...DIST-07) recorded as configured and guard-verified, not yet exercised by a real tag push"

patterns-established: []

requirements-completed: []

duration: 35min
completed: 2026-09-18
---

# Phase 30 Plan 04: Packaging duplication audit + release-script review + phase close Summary

Confirmed `install.bat` is already unified (no edit needed), proved the two `.pkgmeta-*` files' shared content is structurally irreducible against the packager's own accepted-directive list, added `stylua.toml` to both ignore lists, reviewed `release.bat`/`release.yml` end-to-end without executing either, and closed the phase with all five ROADMAP Phase 30 success criteria evidenced.

## Performance

- **Duration:** ~35 min
- **Tasks:** 3/3 completed
- **Files modified:** 5 (.pkgmeta-mainline, .pkgmeta-camelot, CLAUDE.md, PROJECT.md, plus 3 new todo files)

## Accomplishments

- Precondition confirmed: `.pkgmeta-mainline` and `.pkgmeta-camelot` both exist, `.pkgmeta` is gone
- `install.bat`'s control flow audited and confirmed already-unified (Phase 26); no restructuring performed
- The two `.pkgmeta-*` files' reducibility question answered against the pinned `BigWigsMods/packager` `release.sh` source — no include/inherit/extends/merge directive exists in its accepted key set
- `stylua.toml` added to both configs' ignore lists so it does not ship in a release zip
- Three irreducible/deferred findings captured as todos, each stating why Phase 30 did not fix it
- `release.bat` and `release.yml` reviewed statement-by-statement without execution; guard ordering (`check-toc.ps1` before `git tag`) proven by line number; the unguarded `push origin main` recorded as a finding + todo
- `check-toc.ps1` assertion 3 observed live for the first time — zero `skip:` lines
- `CHANGELOG.md`'s v0.3 entry verified present, first in file, naming build `1.60.1.69913` / interface `16001`
- `CLAUDE.md` and `PROJECT.md` no longer describe a single `.pkgmeta`; `PROJECT.md` carries a Phase 29 Validated entry that does not overclaim an unobserved CI run
- All five ROADMAP Phase 30 success criteria hold with evidence (table below)

## Task Commits

1. **Task 1a: Ignore stylua.toml in both packaging configs (D-02)** - `eebde2e` (chore)
2. **Task 1b: Capture duplication findings deferred out of cleanup scope** - `5a9678f` (docs)
3. **Task 2: End-to-end read-only review of release.bat, release.yml and the live assertion 3 (D-19, D-20)** — no commit (read-only)
4. **Task 3: Packaging-facing doc corrections, Phase 29's Validated entry, and the phase-exit gates** - `5c0ec6b` (docs)

## Precondition Check

```
test -f .pkgmeta-mainline   -> true
test -f .pkgmeta-camelot    -> true
test ! -f .pkgmeta          -> true (absent)
```
Phase 29 confirmed landed. Proceeded with the plan.

## install.bat Duplication Verdict

**No change needed.** Read end to end: one `FILES` variable (10 entries), one `FLAVORS` variable (7 client folder names), one preflight loop over `FILES`, one outer loop over `FLAVORS` containing one inner copy loop over `FILES`, and one `INSTALLED` counter driving the zero-clients error. Zero per-client or per-flavor branches (`grep -c 'for %%L in (%FLAVORS%) do' scripts/install.bat` → `1`). ROADMAP criterion 2's `install.bat` half is satisfied by construction. No restructuring performed, per the plan's explicit instruction not to manufacture a cosmetic diff.

## .pkgmeta-* Duplication Verdict

**Diff** (`diff .pkgmeta-mainline .pkgmeta-camelot`, before this plan's edit):
```
20c20
<   - TerribleBuffTracker_Camelot.toc
---
>   - TerribleBuffTracker_Mainline.toc
```
Exactly one line differs; everything else — the `RELEASE_NOTES.md` comment block, `package-as`, the `manual-changelog` block, and the nine-entry shared `ignore` list — is byte-identical.

**Reducibility, checked against the pinned source** (`https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh`, fetched 2026-09-18): the pkgmeta parser (`release.sh` lines ~995-1145) is a hand-rolled line-by-line YAML-lite reader with a fixed `case` statement recognizing exactly: `package-as`, `externals`, `ignore`, `plain-copy`, `move-folders`, `required-dependencies`, `optional-dependencies`, `embedded-libraries`, `tools-used`, `manual-changelog` (+ `filename`/`markup-type` sub-keys), `license-output`, `enable-nolib-creation`, `enable-toc-creation`, `changelog-title`, and the three `wowi-*` toggles. A repo-wide search for `include`/`inherit`/`extends`/`merge` in `release.sh` turns up zero directive-parsing matches (only unrelated prose comments). **No include mechanism exists.** The shared content is therefore structurally irreducible without inventing a new build-time templating step — new behaviour, out of scope. `stylua.toml` was added to both ignore lists (the one edit this plan makes to either file); nothing else changed.

**Gap noted, not fixed:** `check-toc.ps1` assertion 3 only checks each file's cross-ignore line, never the shared nine-line block — `29-CONTEXT.md` itself calls this "the same class of bug as TOC drift." Captured as a todo.

## Todos Created and Why Each Was Deferred

| Todo | Reason deferred |
|---|---|
| `2026-09-18-pkgmeta-shared-ignore-list-can-drift.md` | Fix is a new `check-toc.ps1` assertion — new guard behaviour, not cleanup |
| `2026-09-18-runtime-file-set-enumerated-three-places.md` | Fix requires `install.bat` to parse a TOC at runtime, or a new guard — new behaviour |
| `2026-09-18-release-bat-pushes-main-with-no-branch-guard.md` | Fix is a new branch-guard in `release.bat` — D-19 scopes this plan to review, not modification |

## release.bat Review (D-19)

Statement-by-statement, line numbers confirmed live:
- **Version arg + tag derivation:** lines 4-11, unchanged from pre-v0.3, still correct.
- **`check-toc.ps1` guard ordering:** invocation at line 17, `if errorlevel 1` abort at line 18 ("Aborting before tag" printed at line 19), `git tag -a` at line 23. Confirmed `17 < 18 < 23` — a drifted TOC or a mis-ignored pkgmeta cannot reach a tag.
- **`git tag -a` / `git push origin main "%TAG%"` pair (lines 23, 29):** the tag is created on whatever `HEAD` the script runs from; the push always targets `main`. Nothing in the script asserts which branch is checked out. The project's own rule (squash-merge to `main` before running `release.bat`, never tag from the milestone branch) makes correct use possible but unenforced — and this repo is currently on `v0.3-wow-forever-compatibility`, exactly the branch where a mistake would land. Recorded as a finding and a todo; **no guard added**.
- **Two-flavor readiness:** nothing in `release.bat` needed to change for two flavors — the packaging fan-out happens entirely in CI (`release.yml`'s matrix). Confirmed by inspection; no work invented.

## release.yml Review (D-19)

Checked against `DIST-02`…`DIST-07`:
- **Matrix:** `strategy.matrix.flavor: [mainline, camelot]`, `max-parallel: 1` (serialises uploads to the same GitHub release, per D-07's DIST-05 race concern) — present.
- **Per-job args:** `-m .pkgmeta-${{ matrix.flavor }} -g ${{ matrix.flavor }} -n "{package-name}-{project-version}-{game-type}"`. Verified against the packager source that `-g mainline` / `-g camelot` are recognized aliases that resolve to `game_type=retail` / `game_type=forever` respectively (`release.sh`'s `-g` case block) — so `{game-type}` in the name template resolves to a real, non-colliding value, not the flavor string itself.
- **`RELEASE_NOTES.md` regenerated per job:** present inside the `steps:` list before the packager step, confirmed necessary since each matrix job checks out fresh (`fetch-depth: 0` present).
- **Upload tokens:** `CF_API_KEY` and `WAGO_API_TOKEN` confirmed still commented out under `FTOOL-01` — not enabled.
- **No `DIST-0x` gap found.** All matrix elements match the `29-CONTEXT.md` D-06…D-10 spec.
- **Not claimed:** the two-zip outcome itself (`DIST-03`…`DIST-07`) requires a real tag push and a CI log read, neither of which this plan performs. Recorded in `PROJECT.md`'s Phase 29 entry as "configured and guard-verified, not yet exercised by a real tag push."

## check-toc.ps1 — Assertion 3 Live (D-20)

Full stdout, captured twice (Task 1 post-edit and Task 3 phase-exit):
```
check-toc: OK (C:\Users\jonat\Repositories\TerribleBuffTracker)
```
Zero `skip:` lines in either capture — before Phase 29 the script printed `skip: .pkgmeta-mainline not present (Phase 29)` and the camelot equivalent; assertion 3 has never executed until this repo state. Read the assertion body (`check-toc.ps1:117-147`): for each flavor it checks the pkgmeta file has a YAML `ignore` entry matching the *other* flavor's TOC filename and does **not** have one matching its own. It does not compare the two files' shared `ignore` lines against each other — the gap captured in the first todo above.

## CHANGELOG.md Verification

`grep -m1 '^## ' CHANGELOG.md` → `## v0.3.0 — WoW Forever Support`, confirmed first section (the `awk` step in `release.yml` extracts exactly this). Names `1.60.1.69913` and interface `16001` in its opening line. This is Phase 29's `DIST-08` deliverable — verified, not authored, per the plan's hard constraint.

Plan 30-03's hot-path verdict was `NONE` (see `30-03-SUMMARY.md`), so per the v0.2.4 Phase 24 precedent no performance note was added to `CHANGELOG.md`.

## Phase-Exit Gates — Criterion-by-Criterion Evidence

| Criterion | Evidence |
|---|---|
| 1. Dead code removed | `cat *.lua \| grep -c TRINKET_FALLBACK_ORDER` → `0`; `grep -c POT_FALLBACK_ORDER Providers.lua` → `2` |
| 2. Duplication unified/audited | `install.bat` confirmed already-unified (no edit); `.pkgmeta-*` duplication confirmed structurally irreducible against the pinned packager source; 3 todos capture what's deferred |
| 3. Hot paths reviewed | Plan 30-03's five-site audit, verdict `NONE` (restated from `30-03-SUMMARY.md`) |
| 4. Release scripts reviewed | `release.bat`/`release.yml` reviewed end-to-end, neither executed; guard ordering proven by line number (17<18<23); assertion 3 observed live, zero `skip:` lines |
| 5. Lua files stylua-clean | `git ls-files --eol '*.lua'` → 6/6 `w/crlf`; flagless `stylua --check` clean on all six; `CHANGELOG.md` v0.3 entry verified present and first |

Phase hygiene: exactly one commit per task-with-changes (Task 2 was read-only, correctly produced none); every commit carries the two required trailer lines (`git log --format=%B -8 | grep -c 'Co-Authored-By: Claude Opus 5 (1M context)'` → ≥6); nothing tagged (`git tag --points-at HEAD` empty, `git tag --list 'v0.3*'` empty); nothing pushed; branch still `v0.3-wow-forever-compatibility`.

## v0.3's Two Retail Verification Items — Still Open

Restated explicitly, not this phase's to close: (1) the retail regression pass ran with a stale unsuffixed `TerribleBuffTracker.toc` still present in the deployed folder, and the retail load gate (`TOC-01`/`VER-01`) plus Phase 27's retail draggability half remain open in `ROADMAP.md`; (2) META-01's retail behaviour (tiles present and draggable) was never explicitly confirmed. Both are named "still open" / "not explicitly confirmed" in `PROJECT.md`'s Validated entries (plan 30-02) and the Phase 29 entry added by this plan does not touch or imply resolution of either. `PROJECT.md`'s `Last shipped` still reads v0.2.6.

## Planner Findings — Confirmed

1. **Confirmed.** The packager's accepted-directive list has no include/inherit/extends/merge mechanism, verified against the pinned source rather than assumed. The shared `ignore` drift gap was noted exactly as the planner anticipated and captured as a todo, not fixed.
2. **Confirmed.** `install.bat` needed no edit — Phase 26's data-driven loop already satisfies the criterion. The three-place file-set enumeration (install.bat FILES + both TOCs) was captured as a todo, not fixed.
3. **Confirmed.** `stylua.toml` added to both ignore lists; nothing else in either file changed; `check-toc.ps1` still passes.
4. **Confirmed.** The guard ordering is correct by line number; the unguarded `push origin main` is a real finding, recorded as a todo, not fixed.
5. **Confirmed, with one refinement.** `release.yml`'s matrix was already present at review time (Phase 29 had landed) — it matches the D-06…D-10 spec exactly, including a detail the planner findings did not spell out: `-g mainline` / `-g camelot` are packager-recognized aliases for `retail`/`forever` respectively, confirmed by reading `release.sh`'s `-g` option parser, so `{game-type}` resolves correctly rather than to the literal flavor string.

## Deviations from Plan

None — plan executed exactly as written. Task 2 correctly produced zero commits, as its own success criteria specify.

## Self-Check: PASSED

- FOUND: .pkgmeta-mainline (contains `stylua.toml`)
- FOUND: .pkgmeta-camelot (contains `stylua.toml`)
- FOUND: .planning/todos/pending/2026-09-18-pkgmeta-shared-ignore-list-can-drift.md
- FOUND: .planning/todos/pending/2026-09-18-runtime-file-set-enumerated-three-places.md
- FOUND: .planning/todos/pending/2026-09-18-release-bat-pushes-main-with-no-branch-guard.md
- FOUND commit eebde2e
- FOUND commit 5a9678f
- FOUND commit 5c0ec6b

<deferred_questions>
None.
</deferred_questions>
