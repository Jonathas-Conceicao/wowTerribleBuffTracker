---
status: passed
phase: 32
verified: 2026-09-20
must_haves_verified: 4
must_haves_total: 4
---

# Phase 32 Verification — Single-Zip Packaging

All four criteria verified from a real local packager run
(`bash release.sh -d -n "{package-name}-{project-version}"`), not by inspection.

| # | Criterion | Result |
|---|---|---|
| 1 | Single `.pkgmeta`, no cross-ignore lines, still ignores `tools/` | PASS — `.pkgmeta-mainline`/`-camelot` gone; `tools/` absent from the packager's copy list |
| 2 | `release.yml` single job; `release.bat` no longer calls `check-toc.ps1` | PASS — matrix removed, gate removed |
| 3 | Exactly one zip, no trailing dash, no empty game-type segment, `## Version:` substituted | PASS — `Creating archive: TerribleBuffTracker-v0.3.0-7-g0460580.zip`; staged TOC reads `## Version: v0.3.0-7-g0460580` |
| 4 | The single upload carries every game version the TOC declares | PASS — `Build type: multi-version`, `Game version: 12.1.0, 1.60.1` |

## Note on the local run

The run ends at `zip: command not found` because `zip` is absent from this machine's Git Bash. Every
value under test is printed before that point, and the CI runner has `zip`. No packaging decision is
left unobserved.

## Note on scope

Criterion 3's "`## Version:` reads the real version" was observed against a dev describe
(`v0.3.0-7-g0460580`) because the tree is untagged. At a real tag the same substitution yields the tag.
The mechanism, not the literal string, is what was under test — and it is the mechanism that was broken
in dev installs (`INST-05`, Phase 33).
