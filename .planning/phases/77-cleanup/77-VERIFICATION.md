---
phase: 77-cleanup
verified: 2026-10-23T00:19:31Z
status: passed
score: 4/4 roadmap success criteria verified (plus 11/11 plan must-have truths)
overrides_applied: 0
deferred_to_phase_78:
  - "Add and Edit a cooldown, buff and reminder: the Duration box shows, prefills, validates and saves as before"
  - "A cooldown's and a bag item's buff Duration box validates ('Enter the buff duration') and saves"
  - "A bag item's buff Aura ID starts empty and never follows (follows = NotItemField)"
  - "Edit chat lines read as before (spell: '(<kind>, ID: <ids>, <n>s).'; bag item: '(item, buff <n>s|off).')"
  - "A user cooldown with its buff on, in an icon container, starts its buff on cast; one in a bar container starts none"
  - "Stale TBT copy in _classic_beta_ (Phase 73 WR-01, declined) is still noted"
---

# Phase 77: Cleanup Verification Report

**Phase Goal:** The milestone's own code is lean before it is tested: no duplication it introduced, no per-tick waste, no dead code.
**Verified:** 2026-10-23T00:19:31Z
**Status:** passed (code-level). In-game checks are deferred to Phase 78 by user decision.
**Re-verification:** No. This is the initial verification.

## Goal Achievement

### Roadmap Success Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Behaviour this milestone repeated (buff field handling, buff timer start/end, icon swipe colour switching) lives in one shared function each; nothing pre-existing is refactored | VERIFIED (see note) | **Buff field handling:** five file-local helpers `BuildDurationRow`, `ResetDurationBox`, `PrefillDurationBox`, `ReadDurationBox` and `ValidateDurationBox` (CDMTab.lua:1920-1968) are declared below `FormatDuration` (1207) and above `TRACKER_FIELDS` (1994). Both the `duration` and `buffDuration` defs use them. `buffAuraID` uses `follows = NotItemField` (2541). Both `opts.follows(state, ctx)` call sites (1643, 1660) match `NotItemField(_, ctx)`. **End of save:** `ns:FinishTrackerEdit` (BuffEngine.lua:1429) is called once from `UpdateTrackedItemBuff` (1395) and once from `UpdateTrackedBuff` (1555). There is a single `Updated \|cff00ff00` print. **Buff timer start:** `ns:StartCooldownBuffFromCast` is called from Providers.lua:360 (userCd) and 1819 (bag item). **Buff timer end:** `ns:ApplyCooldownBuffEdit` has one call, inside FinishTrackerEdit. **Swipe colour:** `ApplySwipeLook` (Display.lua:898) is the only milestone switch. The other `SetSwipeColor` at line 563 predates the milestone (present at 3377a8e). |
| 2 | Every hot path this milestone touched has a written verdict, with no per-tick allocation or redundant work | VERIFIED | 77-AUDIT.md "Hot-path review" has one verdict row for each of the 12 listed paths, plus the not-hot-path row. I checked the code myself. `ns:StartCooldownBuffFromCast` now reads `ns.CONTAINER_BY_KEY[entry.section]` once instead of the `ipairs(ns.CONTAINERS)` walk, and its body has no `{`. The result is unchanged: the old loop set `def.kind ~= "bar"` on a key match and false otherwise, and `RegisterContainerDef` / `UnregisterContainerDef` (Core.lua:280, 288) keep the keyed twin in step. "hidden" and "suggested" are never registered (Core.lua:254). The RenderIconContainer live-timer and cooldown-slot branches (Display.lua ~1725-1765) contain no `{` and no closure. `ApplySwipeLook` is stamped on `_auraLook`. |
| 3 | No unused variable, definition or saved key introduced by this milestone remains; `stylua .` leaves no diff | VERIFIED | `ns:CooldownBuffAuraID`: the tree-wide count is now 0, including comments. Independent sweep of every `function ns:X`, `ns.X =` and `local` name added since 3377a8e: every shipped name has a non-comment count of at least 2. The names with count 0 or 1 all live in `tools/TBTProbe/DurationProbe.lua`, a never-shipped probe harness, and each is used inside it. Saved keys: `buffEnabled`, `buffAuraID` and `buffDuration` are written in BuffEngine.lua:1341-1390 and read in Core.lua:760-777. `stylua --check .` exits 0. Every tracked `.lua` is `w/crlf`, none has `\r\r`, and `git status` is clean. |
| 4 | `install.ps1`, `install.bat` and `release.bat` reviewed and still work against the current file set (release.bat never run) | VERIFIED | I ran my own fixture deploy (`TBT_WOW_ROOT` set to a scratch dir with `_forever_` and `_retail_`). Exit code 0. 23 files went to each folder, both hold the TOC and Core.lua, and `DurationProbe.lua` and `tools/` are absent. The deployed TOC carries `v0.5.2-56-g8a85393-dev`, and the repo TOC still has `@project-version@`. The whole install.ps1 diff since 3377a8e is the swap of `_classic_beta_` for `_forever_`. install.bat still forwards `%*` and the exit code. I read release.bat statically: the main-branch guard, `TBT_ALLOW_BRANCH`, `git tag -a v<ver>` and the push of main plus the tag are all present, and it is unchanged since 3377a8e. `.pkgmeta` ignores `scripts` and `tools`. `.github` and the TOC are unchanged. |

**Score:** 4/4 roadmap criteria verified.

### Plan Must-Have Truths

| Plan | Truth | Status |
|------|-------|--------|
| 77-01 | Findings in 77-AUDIT.md with proof command and verdict | VERIFIED. Seven findings and five keeps, each with a command and its result |
| 77-01 | Hot-path verdict per listed path | VERIFIED |
| 77-01 | `ns:CooldownBuffAuraID` gone, no comment names it | VERIFIED (count 0) |
| 77-01 | IsBagItemEntry comment corrected | VERIFIED (Core.lua:593-594; the old phrase count is 0) |
| 77-01 | Providers header names `ns:ApplyCooldownBuffEdit` | VERIFIED (the old phrase count is 0) |
| 77-01 | One `ns.CONTAINER_BY_KEY` read on the cast path | VERIFIED |
| 77-02 | `ns:FinishTrackerEdit` called once by each edit commit | VERIFIED |
| 77-02 | Chat line text byte-identical | VERIFIED by code reading. The concatenations give the same strings. The item path now computes `savedDuration` before `ApplyCooldownBuffEdit` runs, which is harmless because that function never writes `entry` (it only touches `ns.activeTimers`). |
| 77-02 | Duration boxes share helpers | VERIFIED. `SetMaxLetters(6)` appears twice (the build and reset helpers) and the label once |
| 77-02 | buffAuraID follows = NotItemField | VERIFIED |
| 77-02 | Scripts deploy to `_forever_` and `_retail_`; self-tests pass | VERIFIED |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| Providers.lua `ns:StartCooldownBuffFromCast` | Core.lua `ns.CONTAINER_BY_KEY` (Register/Unregister upkeep) | WIRED |
| BuffEngine.lua `UpdateTrackedItemBuff` and `UpdateTrackedBuff` | `ns:FinishTrackerEdit` (on `ns`, so not exposed to the upvalue-order trap) | WIRED |
| CDMTab.lua `duration` and `buffDuration` defs | the five duration-box helpers (file-locals declared above TRACKER_FIELDS) | WIRED |
| `BuildFollowSpellIDField` | `opts.follows(state, ctx)`, which receives `NotItemField(_, ctx)` | WIRED |

### Behavioural Spot-Checks and Gates (run by the verifier)

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Aura-read gate | `node scripts/aura-read-gate.js` | `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)` | PASS |
| Aura-read selftest | `node scripts/aura-read-gate.js --selftest` | `AURA-READ SELFTEST PASS (30 cases)` | PASS |
| Migration selftest | `node scripts/migrate-dryrun.js --selftest` | `SELFTEST PASS (13 cases)` | PASS |
| Formatting | `stylua --check .` | exit 0 | PASS |
| Line endings | `git ls-files --eol '*.lua' \| grep -v w/crlf`; `grep -l $'\r\r' *.lua` | both empty | PASS |
| Fixture deploy | `install.ps1` with `TBT_WOW_ROOT` set to a scratch dir | 23 files to `_forever_` and `_retail_`, no probe, version substituted only in the deployed TOC | PASS |
| Overlong comments | 105-column awk over milestone-added lines | one line, which is stylua-formatted code (`local placeholder = ...`), not a comment | PASS |
| Debt markers | TBD/FIXME/XXX/TODO/HACK in milestone-added lines | none | PASS |

### Probe Execution

No probe declared. `tools/TBTProbe` is an in-game harness and is not a `scripts/*/tests/probe-*.sh`. Skipped.

### Requirements Coverage

None. This is a process phase, and no requirement IDs are declared or orphaned.

### Anti-Patterns and Notes

| File | Item | Severity | Note |
|------|------|----------|------|
| CDMTab.lua `duration` def | A pre-existing field body was replaced by calls to the new shared helpers | Info | Read literally, SC1's "nothing pre-existing is refactored" conflicts with this. It is the only way to unify the milestone-introduced `buffDuration` copy, it is behaviour-identical (same calls and values, and `return false` vs `return false, nil` is the same for the `local ok, msg` caller at CDMTab.lua:2879), and it matches the CLAUDE.md / PROJECT.md reading settled 2026-09-18. 77-02-PLAN declared it explicitly. Not a gap. Phase 78 exercises the dialog in game. |
| BuffEngine.lua `UpdateTrackedBuff` | The chat line now prints after `RebuildRankIndex` instead of before it | Info | The strings are resolved before the first write, so the print cannot throw after the commit. The text is unchanged. |

### Deferred to Phase 78 (in game, Midnight retail)

1. Add and Edit a cooldown, a buff and a reminder: the Duration box shows, prefills, validates and saves as before.
2. A cooldown's and a bag item's buff Duration box validates ("Enter the buff duration") and saves.
3. A bag item's buff Aura ID starts empty and never follows the Spell ID.
4. The edit chat lines read as before: "Updated <label> (<kind>, ID: <ids>, <n>s)." and "Updated <label> (item, buff <n>s|off)."
5. A user cooldown with its buff on, in an icon container, starts its buff on cast. One in a bar container starts none.
6. The stale TBT copy in `_classic_beta_` (Phase 73 WR-01, declined) is still noted.

### Gaps Summary

None. All four roadmap criteria hold in the codebase, and every gate passes when run by the verifier. The only open items are behavioural checks that need the game client, and those are deferred to Phase 78 by user decision.

---

_Verified: 2026-10-23T00:19:31Z_
_Verifier: Claude (gsd-verifier)_
