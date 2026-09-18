---
phase: 25-toc-split-retail-regression-gate
verified: 2026-09-18T11:54:07Z
status: passed
score: 16/16 filesystem-level must-haves verified statically; both in-game gates closed by the ordered run-sheets
---

# Phase 25: TOC Split & Retail Regression Gate Verification Report

**Phase Goal:** Replace the single `TerribleBuffTracker.toc` with two flavor-suffixed TOC files sharing one unforked Lua/XML source set, add a local pre-tag drift guard, document the Forever flavor in `CLAUDE.md`, and prove **in-game** that both a real retail client and a real Forever beta client load the addon from their respective TOC before any downstream phase (26, 27, 29) builds on the split.
**Verified:** 2026-09-18T11:54:07Z
**Status:** passed — superseded 2026-09-19, see Closure Note

## Closure Note

**Closed 2026-09-19 at milestone close.** This report was filed `human_needed` because its two in-game gates (`VER-01`/`TOC-01` retail load, `TOC-02` Forever load) could not be certified from an agent environment. Both were subsequently run by the user and recorded PASS:

- `TOC-02` — `.planning/testing/FOREVER-TEST-PASS.md`, step 1, build `1.60.1.69913`, interface `16001`, 2026-09-18.
- `VER-01` / `TOC-01` — `.planning/testing/RETAIL-REGRESSION-PASS.md`, 2026-09-18, after the stale unsuffixed `TerribleBuffTracker.toc` was deleted from `_retail_` so the load is genuinely from `_Mainline.toc`. That deletion mattered: with the stale TOC still present every check would have passed while proving nothing about the renamed file.

The `human_needed` status was an accurate record of this report's own evidence when it was written. It is superseded, not corrected.

## Goal Achievement

### Observable Truths

Truths drawn from all three plans' `must_haves.truths` frontmatter (25-01, 25-02, 25-03).

**Plan 25-01 — TOC split (filesystem half):**

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Repo contains exactly two TOC files, both flavor-suffixed; no unsuffixed `TerribleBuffTracker.toc` remains tracked | VERIFIED | `git ls-files \| grep -i terriblebufftracker \| grep '\.toc$'` returns exactly `TerribleBuffTracker_Camelot.toc` and `TerribleBuffTracker_Mainline.toc`; `test ! -e TerribleBuffTracker.toc` passes |
| 2 | `TerribleBuffTracker_Mainline.toc` is byte-identical in content to the TOC that shipped v0.2.6 (rename only) | VERIFIED | `git diff v0.2.6:TerribleBuffTracker.toc TerribleBuffTracker_Mainline.toc` produces empty output |
| 3 | `TerribleBuffTracker_Camelot.toc` differs from `_Mainline.toc` on exactly two lines (`## Interface:`, `## Notes:`) | VERIFIED | Full-file diff (CRLF stripped) is exactly 4 changed lines (2 removed, 2 added) — the Interface pair and the Notes pair; body diff excluding those two directives is empty |
| 4 | `git ls-files` reports the Camelot filename with a capital `C` | VERIFIED | `git ls-files \| grep -x 'TerribleBuffTracker_Camelot.toc'` matches; negative grep for lowercase `_camelot.toc` finds nothing |
| 5 | Both TOCs list the same 6 load entries, in the same order | VERIFIED | `Core.lua, BuffEngine.lua, Providers.lua, EditModeFrames.lua, Display.lua, CDMTab.xml` — identical order in both files |

**Plan 25-02 — drift guard, release.bat wiring, CLAUDE.md:**

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 6 | Running the guard against the repo's current TOC pair exits 0 and prints a pass line | VERIFIED | `check-toc: OK (...)`, exit code 0, plus two `skip:` lines for absent `.pkgmeta-<flavor>` files |
| 7 | The guard exits nonzero when a flavor's Interface value falls outside its range | VERIFIED | neg1 scratch test: Camelot given `120100` → `FAIL: ... does not match expected pattern ^16\d{3}$`, exit 1 |
| 8 | The guard exits nonzero when the two TOC bodies drift apart, regardless of line endings | VERIFIED | neg2 scratch test: extra line appended → `FAIL: Body line count differs...`, exit 1; pos1 scratch test: LF-only Camelot copy still exits 0 (CRLF-insensitivity proven positively) |
| 9 | The guard skips its `.pkgmeta` assertion cleanly while no `.pkgmeta-<flavor>` file exists | VERIFIED | Real-repo run prints `skip: .pkgmeta-mainline not present (Phase 29)` / `skip: .pkgmeta-camelot not present (Phase 29)`, exit 0 |
| 10 | `release.bat` aborts before creating a tag when the guard fails | VERIFIED | Guard block (lines 16-21) precedes `git tag -a` (line 23) and `push origin` (line 29); uses the file's existing `if errorlevel 1 ( ... exit /b 1 )` idiom. Never executed — verified by reading and grepping only |
| 11 | `CLAUDE.md` names `BigWigsMods/WoWUI` `forever-beta` as a style reference and records both flavors' interface numbers and install paths | VERIFIED | Style Reference section contains `BigWigsMods/WoWUI` and `forever-beta`; Key Constraints section contains both TOC filenames, `120100`, `16001`, and `_classic_beta_` |

**Plan 25-03 — in-game checklist (filesystem half only; the gate itself is unverifiable here):**

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 12 | A written checklist exists that a human can follow end-to-end without asking any follow-up questions | VERIFIED (structurally) | `25-INGAME-VERIFICATION.md` (175 non-blank lines) contains explicit deploy paths, step-by-step gate instructions, exact commands/console strings, and a full failure-diagnosis protocol — no placeholder "ask the user X" gaps found on read-through |
| 13 | The checklist covers both gates of D-06: retail loads from `_Mainline.toc`, Forever loads from `_Camelot.toc` | VERIFIED | Section A (Gate 1, retail) and Section B (Gate 2, Forever) both present with distinct, gate-appropriate steps |
| 14 | The checklist names the stale-TOC false-pass trap and instructs deleting it before the retail test | VERIFIED | "The false-pass trap — read this before launching anything" subsection, with an explicit bolded delete instruction |
| 15 | The checklist states the D-09 non-failures and the D-11 failure protocol verbatim enough to follow under pressure | VERIFIED | Section C lists all three D-09 non-failures with rationale; Section D reproduces all four D-11 diagnostics plus the PITFALLS.md pitfall-3 triage table inline |
| 16 | No agent-authored PASS mark exists anywhere in the artifact; every result cell starts empty | VERIFIED | `! grep -qE '(Gate 1\|Gate 2)[^|]{0,24}(PASS\|FAIL)'` passes; Section F's table and sign-off block are all blank cells/underscores |

**Score:** 16/16 filesystem-level/documentation-level truths verified. **Not covered by this table, and not coverable from this environment:** the *observable* in-game behavior — does a real retail client actually load TBT from `_Mainline.toc`, and does a real Forever beta client actually load TBT from `_Camelot.toc`. This is exactly the phase's own stated purpose (D-06's true dual gate) and is owned entirely by a human running `25-INGAME-VERIFICATION.md`. See "Human Verification Required" below.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `TerribleBuffTracker_Mainline.toc` | Midnight retail TOC at Interface 120100 | VERIFIED — EXISTS + SUBSTANTIVE | 18 lines, `## Interface: 120100` on line 1, all 6 load entries present |
| `TerribleBuffTracker_Camelot.toc` | WoW Forever TOC at Interface 16001 | VERIFIED — EXISTS + SUBSTANTIVE | 18 lines, `## Interface: 16001` on line 1, `WoW Forever` in Notes, all 6 load entries present |
| `scripts/check-toc.ps1` | Pre-tag TOC drift guard implementing D-14's three assertions | VERIFIED — EXISTS + SUBSTANTIVE | 158 lines (>= 60 min); contains `TerribleBuffTracker_Camelot.toc`; all three assertions present and independently exercised by 4 negative + 2 positive scratch tests |
| `scripts/release.bat` | Release script that runs the guard before tagging | VERIFIED — EXISTS + SUBSTANTIVE | Contains `check-toc.ps1` invocation strictly before `tag -a` and `push origin`; never executed |
| `CLAUDE.md` | Forever API reference, interface numbers, install paths | VERIFIED — EXISTS + SUBSTANTIVE | Contains `forever-beta`, both flavor filenames, both interface numbers, both install-path fragments |
| `.planning/phases/25-toc-split-retail-regression-gate/25-INGAME-VERIFICATION.md` | Human-run checklist and result record for VER-01 and TOC-02 | VERIFIED — EXISTS + SUBSTANTIVE | 175 non-blank lines (>= 80 min); contains `NOT RUN`; every result cell empty |

**Artifacts:** 6/6 verified as existing and substantive. All are static/filesystem artifacts — none of them, individually or together, constitute proof that either game client actually loads the addon.

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `TerribleBuffTracker_Mainline.toc` | `TerribleBuffTracker_Camelot.toc` | identical body outside the two allowlisted directive lines | WIRED | `diff` of both files excluding `## Interface:`/`## Notes:` lines is empty |
| `scripts/release.bat` | `scripts/check-toc.ps1` | powershell invocation guarded by `if errorlevel 1 ... exit /b 1`, placed before `git tag` | WIRED | Confirmed by line-number ordering: guard block at lines 16-21, `tag -a` at line 23, `push origin` at line 29 |
| `scripts/check-toc.ps1` | `TerribleBuffTracker_Mainline.toc` / `TerribleBuffTracker_Camelot.toc` | reads both files relative to `-Root` (defaults to repo root) | WIRED | Guard reads both files by name under `$Root`; verified against both the real repo (pass) and 5 scratch-directory scenarios (4 fail, 1 pass) |
| `25-INGAME-VERIFICATION.md` | `TerribleBuffTracker_Mainline.toc` / `TerribleBuffTracker_Camelot.toc` | manual deploy step listing every file to copy into each client | WIRED | Section 0 lists both TOC filenames by exact name among the ten files to copy |

**Wiring:** 4/4 connections verified statically. Runtime confirmation that the wiring actually produces a loaded addon in a live client is the phase's own open gate, not claimed here.

## Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|-----------------|
| TOC-01: existing retail install continues to load TBT after the TOC rename | PARTIAL — filesystem half complete and statically verified; **in-game half not performed** | Requires a real retail Midnight client to observe the AddOns list, the load chat print, and `/tbt` opening the CDM tab. This environment cannot launch WoW. |
| TOC-02: WoW Forever beta client loads TBT from `TerribleBuffTracker_Camelot.toc` | NOT VERIFIED — checklist exists and is committed; **zero in-game execution performed** | Requires a real Forever beta client (`_classic_beta_`). This environment cannot launch WoW. TOC-02 stays owned by Phase 25 per D-07, not deferred to Phase 28. |
| TOC-03: one shared Lua/XML source set, no flavor-forked files | FULLY SATISFIED | Body-diff assertion (both manual and guard-automated) confirms zero divergence outside the two allowlisted directive lines; no `.lua`/`.xml` file was touched by any plan in this phase |
| TOC-04: committed filenames survive a case-sensitive checkout | FULLY SATISFIED | `git ls-files` exact-match and negative-lowercase-match both confirmed; this is an index-level guarantee, not something an in-game test can add to |
| TOC-05: local pre-tag guard prevents the two TOCs from silently diverging before a release tag | FULLY SATISFIED | `scripts/check-toc.ps1` implements and passes all three D-14 assertions; wired into `scripts/release.bat` before the tag step; demonstrated failing on 4 independent negative scenarios |
| VER-01: retail regression gate — a real client proves the rename didn't break anything | NOT VERIFIED — checklist exists; **zero in-game execution performed** | Same blocker as TOC-01's in-game half: requires a live retail client, which this environment cannot provide. |
| DOC-01: `CLAUDE.md` documents the Forever flavor reference and constraints | FULLY SATISFIED | All required strings and sections present, verified above |

**Coverage:** 5/7 requirements fully satisfied at the filesystem/documentation level (TOC-03, TOC-04, TOC-05, DOC-01, plus TOC-01's filesystem half already folded into the TOC-01 row above being PARTIAL not FULL). 2 requirements (TOC-02, VER-01) and one requirement's in-game half (TOC-01) remain entirely unverified pending a human running the game clients.

## Anti-Patterns Found

None. No stub values, no hardcoded empty placeholders, no "coming soon" markers, no `TODO`/`FIXME` introduced by any of the three plans. The one file with intentionally empty content — `25-INGAME-VERIFICATION.md`'s Section F results table — is empty **by design and by explicit hard constraint**, not a stub: it is the correct, required state for an unrun human checklist, and an automated grep gate in plan 25-03 actively fails the task if an agent fills it in. This is the opposite of a stub — it is a deliberately preserved gap that must not be closed by this agent.

## Human Verification Required

### 1. Retail load gate (VER-01, TOC-01's in-game half)
**Test:** Deploy the addon (per `25-INGAME-VERIFICATION.md` Section 0, including deleting the stale unsuffixed `TerribleBuffTracker.toc`) to a real retail Midnight client. Launch it, confirm the AddOns list shows TBT enabled, confirm the `ADDON_LOADED` chat print fires, confirm `/tbt` opens the CDM tab, and glance at previously-tracked buffs.
**Expected:** All five checks pass exactly as described in `25-INGAME-VERIFICATION.md` Section A.
**Why human:** Requires a live retail WoW client and a logged-in character. Not launchable from this execution environment.

### 2. Forever load gate (TOC-02)
**Test:** Deploy the addon to a real Forever beta client (`_classic_beta_`), with `/console scriptErrors 1` set before reload. Confirm TBT appears in the AddOns list and loads with no Lua error at login.
**Expected:** Both checks pass exactly as described in `25-INGAME-VERIFICATION.md` Section B. If this gate fails, follow Section D's mandatory diagnostic-collection protocol before reporting back — do not try another TOC suffix.
**Why human:** Requires a live Forever beta client. Not launchable from this execution environment. This is the phase's single most important open question — everything else in Phase 25 exists to make this gate possible to run.

## Gaps Summary

**No code-level or filesystem-level gaps found.** All 16 `must_haves.truths` across the three plans are statically verified: the TOC split is a clean rename plus a targeted two-line copy, the drift guard correctly passes the real repo and correctly fails on four independent negative scenarios (bad interface, drifted body, wrong-flavor `.pkgmeta` ignore, missing file) while remaining CRLF-insensitive, `release.bat` is wired but never executed, `CLAUDE.md` documents the flavor facts, and the in-game checklist is complete, self-contained, and carries zero agent-authored verdicts.

**The two open items are not gaps in this phase's completed work — they are the phase's own explicitly-designed stopping point.** ROADMAP Phase 25's actual purpose is a true dual in-game gate (D-06): a real retail client and a real Forever beta client each loading the addon from their respective TOC. Neither can be exercised from this environment, by design — no agent can launch WoW, log in, or read a live AddOns list. This report's `human_needed` status reflects that honestly. It is not a defect to fix; it is the reason plan 25-03 ends at a blocking `checkpoint:human-verify` rather than a normal task completion.

## Recommended Fix Plans

None. No code or filesystem gaps exist. The only remaining work is the live verification pass, which is already the explicit, intentional next step: a human runs `.planning/phases/25-toc-split-retail-regression-gate/25-INGAME-VERIFICATION.md` end to end and records both verdicts in its Section F. No new plan is needed inside Phase 25 — the phase stays open until that happens.

## Verification Metadata

**Verification approach:** Goal-backward (derived from all three plans' `must_haves` frontmatter plus ROADMAP Phase 25's stated dual-gate goal)
**Must-haves source:** `25-01-PLAN.md`, `25-02-PLAN.md`, `25-03-PLAN.md` frontmatter (`must_haves.truths`, `must_haves.artifacts`, `must_haves.key_links`)
**Automated checks:** 10 (plan 25-01 Task 1) + 14 (plan 25-01 Task 2) + guard pass/fail across 6 scenarios (plan 25-02) + 10 ordering/content assertions (plan 25-02 Tasks 2-3) + 14 (plan 25-03 Task 1) = 54+ individual assertions, all passed, 0 failed
**Human checks required:** 2 (both game-client-dependent; both the phase's own central purpose, not deferred elsewhere)
**Total verification time:** ~40 min (shared with plan execution across all three plans)

---
*Verified: 2026-09-18T11:54:07Z*
*Verifier: Claude (executor, same session as plan execution)*
