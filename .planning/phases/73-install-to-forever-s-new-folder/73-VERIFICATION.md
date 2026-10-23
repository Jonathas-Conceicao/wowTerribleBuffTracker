---
phase: 73-install-to-forever-s-new-folder
verified: 2026-10-22T20:30:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 73: Install to Forever's New Folder Verification Report

**Phase Goal:** `./scripts/install.bat` deploys TBT to every client the machine has, now including Forever's own `_forever_` folder, and the project docs name it.
**Verified:** 2026-10-22
**Status:** passed
**Re-verification:** No (initial verification)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `./scripts/install.bat` deploys the shipped file set to `World of Warcraft\_forever_`, puts the dev version only in the deployed TOC, and prunes files the repo no longer has | VERIFIED | `scripts/install.ps1:29` lists `'_forever_'`. The real `_forever_\Interface\AddOns\TerribleBuffTracker` has all 23 TOC-derived files and each is byte-identical (`cmp`) to the repo. The only TOC difference is `## Version: v0.5.2-4-g11a619b-dirty-dev`. I ran a fresh install against a temporary fixture root with `TBT_WOW_ROOT` set. It deployed to `_forever_` and `_retail_` and pruned a planted `Stale.lua` from `_forever_` ("1 stale file(s) pruned"). The repo TOC still has `@project-version@`. |
| 2 | install.ps1 no longer names or deploys to `_classic_beta_`, and `_retail_` deploys exactly as before | VERIFIED | `grep _classic_beta_ scripts/install.ps1` finds nothing. The fixture run created nothing under `_classic_beta_` (empty dir). The real `_classic_beta_` deployment is untouched: it still dates from Oct 10 and has version `v0.5.1-117-g3668e75-dev`, so nothing was deleted, as decided. The real `_retail_` has the same files and version as `_forever_`. The commit diff changes 1 line in install.ps1, and only the flavor list. |
| 3 | CLAUDE.md names `_forever_` and Forever's product `wowf` (1.60.1.70532, interface 16001) | VERIFIED | `CLAUDE.md:13` reads "WoW Forever (`World of Warcraft\_forever_`, product `wowf`, build 1.60.1.70532, interface 16001)". The Platynator sentence and the "Superseded the two-TOC split on 2026-09-20" sentence are kept. No leftover `_classic_beta_`, `wow_classic_beta` or `1.60.1.69913`. `_forever_\.flavor.info` on disk reads `wowf`, which confirms the fact. |
| 4 | TerribleBuffTracker.toc is unchanged | VERIFIED | `git diff 11a619b HEAD -- TerribleBuffTracker.toc` is empty. The last commit to touch it is the v0.5.2 release (89a9987). `## Interface: 120100, 16001` is kept. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/install.ps1` | Flavor list has `'_forever_'` instead of `'_classic_beta_'` | VERIFIED | Line 29: `$flavors = @('_retail_', '_ptr_', '_beta_', '_forever_', '_classic_', '_classic_era_', '_classic_ptr_')`. Line endings are `w/crlf` (`eol=crlf`). |
| `CLAUDE.md` | Contains `wowf` | VERIFIED | Line 13. Line endings are `w/crlf`, with no LF reflow. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scripts/install.ps1 $flavors` | `World of Warcraft\_forever_\Interface\AddOns\TerribleBuffTracker` | `foreach ($flavor in $flavors)` deploy loop | WIRED | The fixture run printed "Installed to ...\_forever_\Interface\AddOns\TerribleBuffTracker". The real folder holds the current deployment. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Deploy plus prune to `_forever_`, skipping `_classic_beta_` | `TBT_WOW_ROOT=<scratch fixture> powershell -File scripts/install.ps1` | Exit 0. Installed to `_retail_` and `_forever_`, pruned `Stale.lua`, `_classic_beta_` left empty, `Deployed version: v0.5.2-7-gbd18523-dev` | PASS |
| Real deployment matches repo | `cmp` for each TOC file, repo vs `_forever_` | All 23 files the same, except the TOC Version line | PASS |
| Repo TOC placeholder kept | `grep -c @project-version@ TerribleBuffTracker.toc` | 1 | PASS |
| Working tree untouched by the checks | `git status --short` | Only the pre-existing untracked `74-PATTERNS.md` | PASS |

### Probe Execution

No probes are declared or applicable. This is a script/docs phase with no `scripts/*/tests/probe-*.sh`.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INST-11 | 73-01 | install.ps1 deploys to `_forever_` and no longer to `_classic_beta_`, CLAUDE.md names `_forever_` and `wowf` (1.60.1.70532, interface 16001), and the TOC does not change | SATISFIED | Truths 1 to 4 |

No requirements are orphaned. REQUIREMENTS.md maps only INST-11 to Phase 73. Its checkbox and traceability row still say Pending, and the orchestrator updates those, not this verifier.

### Anti-Patterns Found

None. The two changed lines contain no TBD/FIXME/XXX/TODO markers, and no Lua changed.

### Notes (informational)

- The real deployment's version string (`v0.5.2-4-g11a619b-dirty-dev`) shows `install.bat` ran with the edit uncommitted, before commit 14b8736. The deployed content is still byte-identical to HEAD, so this does not matter.
- README.md names no install folder (grep: 0 hits), so leaving it alone is correct.

### Human Verification Required

None for this phase. In-game load checks are deferred to the Phase 78 retail testing pass by user decision, and Forever servers are down.

### Gaps Summary

No gaps. The phase goal is achieved: install.ps1 targets `_forever_`, the real `_forever_` folder holds a current, prune-managed deployment, and CLAUDE.md documents the new folder and product.

---

_Verified: 2026-10-22_
_Verifier: Claude (gsd-verifier)_
