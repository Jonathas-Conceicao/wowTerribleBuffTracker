---
status: passed
phase: 33
verified: 2026-09-20
must_haves_verified: 5
must_haves_total: 5
---

# Phase 33 Verification — Install & Release Tooling

All verified by running the scripts, not by reading them.

| Requirement | Observable | Result |
|---|---|---|
| INST-05 | deployed TOC reports a real, unmistakably-dev version | PASS — `## Version: v0.3.0-8-ge16acbc-dirty-dev` |
| INST-06 | repo TOC keeps `@project-version@` | PASS — unchanged after the deploy |
| INST-07 | stale files pruned | PASS — `ConfigUI.lua` (deleted in v0.2.0) removed from `_retail_`, `_ptr_`, `_beta_`; `tbt_icon_64x64.png` from two |
| INST-08 | exactly one TOC per client folder | PASS — all four folders hold one `TerribleBuffTracker.toc` |
| INST-09 | file set defined in one place | PASS — derived from the TOC, XML includes and `## IconTexture:`; produces the same nine files the old hardcoded list held |
| REL-01 | `release.bat` refuses the wrong branch | PASS — refused on the milestone branch, `git tag -l v9.9.9` empty afterwards |

## Human verification

None required. Every criterion is observable from the scripts' own output and from disk.

The deployed addon's version string is visible in-game in the character-select AddOns list; that is
worth an eye during the Phase 42 Forever pass, but it has already been confirmed on disk, which is the
same file the client reads.
