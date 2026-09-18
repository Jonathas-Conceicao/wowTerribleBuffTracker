# Phase 26 Plan 01: Install Tooling — Verification

**Verdict: PASSED**

Unlike phases 25/27/28, this phase's verification is entirely filesystem-based — no WoW game client launch is required, and none was claimed. Every assertion below was executed against either a real filesystem sandbox or the live WoW installation on this machine.

## Gate Summary

| Requirement | Method | Result |
|---|---|---|
| INST-01 (argument-free, installs to every present client in one pass) | Task 3 live run, no arguments, no `TBT_WOW_ROOT` | PASS |
| INST-02 (absent flavor silently skipped) | Task 2 Scenario A | PASS |
| INST-03 (zero clients → loud diagnostic naming root, exit 1) | Task 2 Scenarios B & C | PASS |
| INST-04 (both TOCs land in every target) | Task 2 Scenario A, Task 3 live run | PASS |
| D-10 structural check (single `copy /Y`, not repeated lines) | Task 1 automated verify | PASS |
| Out-of-scope guard (only `scripts/install.bat` touched/committed) | Task 3 commit inspection | PASS |

## Task 1 — Structural Verification

- Prerequisite gate: `git ls-files *.toc` confirmed `TerribleBuffTracker_Camelot.toc` and `TerribleBuffTracker_Mainline.toc` both tracked at repo root before any rewrite began.
- `findstr`/grep confirmed all four required strings present in the new script: `TerribleBuffTracker_Camelot.toc`, `TerribleBuffTracker_Mainline.toc`, `TBT_WOW_ROOT`, `_classic_beta_`.
- Regex scan confirmed zero `*.lua`/`*.toc` glob patterns anywhere in the script (D-08).
- Regex scan confirmed exactly one `copy /Y` statement exists in the file, inside the nested per-target loop (D-10).
- A syntax sanity run against an empty sandbox root produced the expected zero-install diagnostic with exit code 1, confirming the script parses and runs without batch syntax errors.

**Result: PASS**

## Task 2 — Sandbox Scenario Verification

All four scenarios ran against a throwaway sandbox directory under the system temp folder (`%TEMP%\tbt-sbx` / `%TEMP%\tbt-sbx-d`), never against the live WoW install.

### Scenario A — Partial presence
- Sandbox: `_retail_` and `_classic_beta_` directories only.
- Result: exit 0. Exactly two "Installed to ..." lines, one per present flavor. Closing `Done! /reload in WoW to load the addon.` line present and correct (see Deviation #1 in SUMMARY — required a caret-escape fix for the literal `!`).
- Each of the two destination folders contained exactly 10 files, including both `TerribleBuffTracker_Mainline.toc` and `TerribleBuffTracker_Camelot.toc`.
- Absent-flavor silence: verified with a path-segment-aware check (`\<flavor>\` as a whole segment) rather than the plan's literal raw-substring check, because `_beta_` is a true substring of the present flavor `_classic_beta_` and the literal check would false-positive on correct behavior (see SUMMARY Deviation #2). No absent flavor (`_ptr_`, `_beta_`, `_classic_`, `_classic_era_`, `_classic_ptr_`) appeared as its own path segment anywhere in stdout.

**Result: PASS**

### Scenario B — Empty root
- Sandbox: empty directory, `TBT_WOW_ROOT` pointed at it.
- Result: exit 1. Diagnostic named the exact sandbox path searched and referenced `TBT_WOW_ROOT` as the way to redirect.

**Result: PASS**

### Scenario C — Nonexistent root
- `TBT_WOW_ROOT` pointed at a path that does not exist at all (`<sandbox>\does-not-exist`).
- Result: exit 1, identical behavior to Scenario B — diagnostic named the exact (nonexistent) path searched. Confirms the zero-count branch handles a bad override without crashing.

**Result: PASS**

### Scenario D — Emacs lock-file immunity
- Created `.#Display.lua` at repo root, re-ran Scenario A's sandbox install.
- `.#Display.lua` was confirmed absent from the destination folder (`Test-Path` false).
- Lock file deleted after the test; confirmed via `git status --porcelain` that `.#Display.lua` does not appear anywhere in the working tree status (not created, not staged, not left behind).
- Note: a literal full-tree-clean assertion was not used because `scripts/install.bat` was legitimately modified-but-uncommitted at this point in the sequence (Task 3 makes the commit) — see SUMMARY Deviation #3. Two pre-existing unrelated modified files and three pre-existing untracked files (present before this session's work began, per the git status snapshot at conversation start) were also visible in `git status --porcelain` output at this point; confirmed out of scope for this phase and left untouched.

**Result: PASS**

## Task 3 — Live Run Verification

- Ran `scripts\install.bat` with no arguments and no `TBT_WOW_ROOT` set, against the real machine install at `C:\Program Files (x86)\World of Warcraft`.
- Exit code 0.
- Exactly 4 "Installed to ..." lines, one each for `_retail_`, `_ptr_`, `_beta_`, `_classic_beta_` (the 4 flavors confirmed present on this machine).
- Closing `/reload` line present.
- For all 4 installed clients: all 10 files from the FILES list present at the destination, with byte-for-byte length match against the repo-root originals (`Get-Item .Length` comparison).
- Confirmed no folder was created under the WoW root for any of the 3 absent flavors (`_classic_`, `_classic_era_`, `_classic_ptr_`).
- `_classic_beta_` — the confirmed Forever beta target (`wow_classic_beta`, build `1.60.1.x`) — received both TOCs and all shared files. This is the single most load-bearing outcome of the phase per the sequencing note: the user tests Forever first.

**Result: PASS**

## Commit Verification

- `git log -1 --name-only` on commit `62d9982` shows exactly one file changed: `scripts/install.bat`.
- `git status --porcelain` after the commit shows `scripts/install.bat` no longer modified; only pre-existing, out-of-scope changes remain (`25-INGAME-VERIFICATION.md`, `28-VERIFICATION-CHECKLIST.md`, `.luarc.json`, `foo.md`, `.planning/testing/` — all predate this session, none touched).
- No `git push`, no `git tag`, and `scripts/release.bat` was never executed or modified during this phase.
- Branch remained `v0.3-wow-forever-compatibility` throughout.

**Result: PASS**

## Constraints Compliance

- No `AskUserQuestion` calls made; all decisions resolved from PLAN.md/CONTEXT.md; genuinely open items recorded in SUMMARY.md under "Deferred Questions".
- No push, no tag, no release script executed. Local commit only, on the correct branch.
- Only `scripts/install.bat` plus this phase's own planning artifacts (`26-01-SUMMARY.md`, `26-01-VERIFICATION.md`) were touched. `Providers.lua`, both `.toc` files, `scripts/check-toc.ps1`, `scripts/release.bat`, and `CLAUDE.md` were not modified.
- No in-game claims made anywhere in this verification or the SUMMARY — all assertions are filesystem-based (file existence, byte-length match, directory creation/non-creation, stdout/exit-code inspection).

## Overall Verdict

**PASSED.** All plan-defined verification gates hold, both as literally specified (Task 1 structural checks, Task 3 live-run checks, Scenarios B/C) and — where the plan's own literal check text collided with the flavor-naming scheme or task ordering (Scenario A's substring check, Scenario D's full-tree-clean check) — via a corrected assertion that preserves the actual intent of D-05 and the lock-file-immunity requirement without softening either. Both discrepancies are documented in `26-01-SUMMARY.md` under Deviations for human review; neither reflects a defect in `scripts/install.bat`.

---
*Phase: 26-install-tooling*
*Verified: 2026-09-18*
