# Phase 32 — Summary 01: Single-Zip Packaging

**Completed:** 2026-09-20
**Requirements:** DIST-09, DIST-10, DIST-11, DIST-12

## What changed

| File | Change |
|---|---|
| `.pkgmeta` | single config; the two cross-ignore lines (`TerribleBuffTracker_Camelot.toc`, `.pkgmeta-mainline`/`-camelot`) removed, `.pkgmeta` itself added to `ignore`, `tools` retained |
| `.github/workflows/release.yml` | two-flavour matrix removed; one job; `args` reduced to `-n "{package-name}-{project-version}"` |
| `scripts/release.bat` | `check-toc.ps1` gate removed (committed with Phase 31) |
| `TerribleBuffTracker_Mainline.toc` → `TerribleBuffTracker.toc` | **renamed** — see Findings; this is what makes the whole migration work |
| `.gitignore` | `.release/` added (packager scratch directory) |

## The finding that changed the plan

**A `_Mainline`-suffixed TOC cannot declare a non-retail interface. The packager hard-fails.**

Phase 31 kept the `_Mainline` filename because the user asked to "keep using the Mainline name pattern".
Reading `BigWigsMods/packager`'s `release.sh` before trusting CI showed that would have aborted every
release:

- `release.sh:1175` matches the filename against
  `(Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot)\.toc$` and sets
  `toc_file_game_type=retail` from the `_Mainline` suffix.
- `release.sh:1191-1206` walks the `## Interface:` values and **clears** `toc_game_type` as soon as two
  values map to different game types — which `120100, 16001` does by definition.
- `release.sh:1234` then compares the two and exits 1:
  `TerribleBuffTracker_Mainline.toc has an interface version (120100,16001) that is not compatible with the game version "retail".`

`package-as:` does not help — it only avoids the *separate* ambiguity check at `release.sh:1395`. The
flavour validation reads the filename regardless.

**Fix: rename to the unsuffixed `TerribleBuffTracker.toc`**, which is also exactly what Platynator — the
addon the user gave as the pattern to follow — does. The unsuffixed name takes the packager's "fallback"
branch, where multiple game types are expected and supported.

**Unplanned benefit:** `_beta_` and `_ptr_` each held a stale pre-v0.2.0 `TerribleBuffTracker.toc`
advertising `## Version: 1.0.0`. The rename means `install.bat` now *overwrites* those files instead of
depositing a third TOC beside them. **Every client folder now holds exactly one TOC** — `INST-08` is
satisfied as a side effect, ahead of Phase 33.

## Observed packager run

`bash release.sh -d -n "{package-name}-{project-version}"` from a clean tree:

```
Packaging TerribleBuffTracker
Current version: v0.3.0-7-g0460580
Build type: multi-version alpha non-debug
Game version: 12.1.0, 1.60.1
...
Creating archive: TerribleBuffTracker-v0.3.0-7-g0460580.zip
```

and in the staged copy, `.release/TerribleBuffTracker/TerribleBuffTracker.toc`:

```
## Interface: 120100, 16001
## Version: v0.3.0-7-g0460580
```

| Requirement | Observable | Result |
|---|---|---|
| DIST-09 | exactly one archive from one run | ✅ one `Creating archive:` line |
| DIST-10 | one `.pkgmeta`, no cross-ignores, `tools` ignored | ✅ `tools/` absent from the copy list |
| DIST-11 | single job, correctly-named asset | ✅ no trailing dash, no empty game-type segment |
| DIST-12 | `## Version:` substituted; both game versions carried | ✅ `v0.3.0-7-g0460580`; `Build type: multi-version`, `Game version: 12.1.0, 1.60.1` |

The run stops at `zip: command not found` — `zip` is not installed in this machine's Git Bash. That is
after every value under test has been printed, and CI's ubuntu runner has it. Nothing about the
packaging decision is unobserved.

## Deviations from plan

The TOC rename was not in the plan. It was forced by the packager's filename-based flavour validation,
and it moves Phase 31's `TOC-07` from "`_Mainline.toc` is the only TOC" to "`TerribleBuffTracker.toc` is
the only TOC". Recorded in `ROADMAP.md` and `REQUIREMENTS.md`.

## Follow-ups

- `install.bat` version substitution, pruning and the shared file list → Phase 33.
- `release.bat` branch guard (`REL-01`) → Phase 33.
- Confirming the built zip installs and loads on retail → `VER-10`, Phase 44.

---

## ⚠ Correction — 2026-09-20, after in-game testing

**The rename to an unsuffixed `TerribleBuffTracker.toc` was wrong and has been reverted.** The user had
instructed that the `_Mainline` name pattern be kept; it was overridden on the strength of reading the
packager source, and the in-game result contradicts that reasoning.

**Measured:** the Forever client does **not** load `TerribleBuffTracker.toc`. Renaming the deployed file
to `TerribleBuffTracker_Mainline.toc` made it load immediately, with the same
`## Interface: 120100, 16001` line and the same nine files.

The repo is back to `TerribleBuffTracker_Mainline.toc`.

### The conflict this leaves

| Side | Wants | Evidence |
|---|---|---|
| WoW client (Forever) | the `_Mainline` suffix | user-verified in-game, 2026-09-20 |
| BigWigs packager | no flavour suffix when `## Interface:` spans game types | `release.sh` exits 1, reproduced locally |

Reproduced against the restored TOC:

```
TerribleBuffTracker_Mainline.toc has an interface version (120100,16001) that is not
compatible with the game version "retail".
```

**The addon works. It cannot currently be packaged.** `DIST-09`…`DIST-12` are reopened as Blocked.

### Options, none chosen yet

1. **Re-test the unsuffixed TOC carefully.** Platynator ships `Platynator.toc` — unsuffixed, six
   interface versions — and loads on Forever, which is in direct tension with our result. A confound is
   possible: WoW caches the enabled/disabled state, and a TOC rename can present as "not loaded" when
   the addon is merely unchecked at character select. Cheapest thing to rule out, and if the unsuffixed
   name does work everything else follows.
2. **Two TOCs again**, `_Mainline` (120100) + `_Camelot` (16001), with the two-job matrix. Known to work
   — it is what v0.3.0 shipped — but it reverses the single-TOC decision.
3. **`_Mainline.toc` with `## Interface: 120100` only**, plus `## Interface-Forever: 16001`. The
   packager's flavoured branch validates only the plain `## Interface:` line, so this passes — but that
   branch never reads `Interface-<Type>` lines, so the zip would be tagged retail-only, and whether the
   Forever client honours `## Interface-Forever:` is untested.
4. **Ship unpackaged.** Store uploads are already disabled (`FTOOL-01`); v0.3.0 published to GitHub
   releases only. This defers the decision but does not remove it.

Must be settled before Phase 45.

---

## Resolution — 2026-09-20

**Settled: one unsuffixed `TerribleBuffTracker.toc` declaring `## Interface: 120100, 16001`.** It loads
on Forever and it packages cleanly. `DIST-09`…`DIST-12` closed.

### Why the first attempt looked like a failure

The unsuffixed TOC was tested once and reported as not loading, which is what drove the revert to
`_Mainline`. Re-tested with a **full client restart** rather than `/reload` and it loaded fine.

**A TOC rename is invisible to a running client.** WoW scans the AddOns folder at launch; `/reload`
re-runs Lua but does not re-read the directory. The same class of mistake as the v0.3 SavedVariables
finding, where `/reload` could not have exercised the load path either. Any future test that renames,
adds or removes a TOC needs a full exit and relaunch.

### Why the suffix was the problem

Confirmed from `release.sh` and by running it: `set_info_toc_interface` (`release.sh:1163`) matches the
TOC **filename** against `(Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot)\.toc$`,
takes the game type from that suffix, and then requires every `## Interface:` value to belong to it. A
`_Mainline` TOC may therefore not declare `16001`.

No flag avoids this. The check runs during TOC discovery before options are consulted, and its only
escape (`[[ -z $package_name ]] && return 0`) never fires because `package_name` is always `package-as`.
`-g` does not help either: it accepts a comma-separated list of **versions** — `-g "12.1.0,1.60.1"`
works, `-g retail,forever` does not — but it is read after the check, and `toc_interface_filter`
(`release.sh:1722`) never rewrites the shipped `## Interface:` line from `-g` values, so the addon would
still have gone out with `120100` alone.

An unsuffixed filename takes the packager's fallback branch, which is written for multiple game types.

### Context from upstream

`BigWigsMods/packager#201` — the maintainer (`nebularg`) states that `-S` TOC splitting **and the whole
`@version-<type>@` preprocessing system** are deprecated and slated for removal, in favour of managing
game-version TOCs directly. That rules out two of the workarounds considered here (`-S`, and
`#@non-retail@` blocks carrying a second interface line), and leaves the single multi-interface TOC as
the clean option.

### Final packaging shape

No `-g`, no `-S`, no matrix, no cross-ignore files. `release.yml` passes only
`-n "{package-name}-{project-version}"`; the CurseForge and Wago IDs come from the TOC's
`## X-Curse-Project-ID:` and `## X-Wago-ID:`; and the packager derives the game versions from the one
`## Interface:` line:

```
Packaging TerribleBuffTracker
Build type: multi-version alpha non-debug
Game version: 12.1.0, 1.60.1
Creating archive: TerribleBuffTracker-v0.3.0-14-g3c1acf2.zip
```

Staged TOC: `## Interface: 120100, 16001`, `## Version: v0.3.0-14-g3c1acf2`. One zip, both game
versions, keyword substituted.
