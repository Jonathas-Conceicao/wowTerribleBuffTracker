---
phase: 84-cleanup
verified: 2026-11-09T11:10:26Z
status: passed
score: 4/4 roadmap criteria verified (10/10 must-haves incl. plan truths)
overrides_applied: 0
---

# Phase 84: Cleanup Verification Report

**Phase Goal:** The milestone's code leaves no dead code, duplication or hot-path cost behind, and the release scripts still hold
**Requirement:** CLEAN-01
**Verified:** 2026-11-09T11:10:26Z
**Status:** passed
**Re-verification:** No (initial verification)

Milestone diff base `5c0001e`; cleanup commit `35b18e1`. `97fdc5a` (Phase 83 review hardening of
`scripts/reminders-doc-check.js`) landed after Phase 84's run; `git diff 35b18e1 HEAD --stat`
shows it touched only that script and `.planning/` files, no Lua. The hardened check was re-run
here and passes.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | No unused code or duplicated behaviour introduced by Phases 80-83 remains; pre-milestone code not refactored | VERIFIED | Read the full `git diff 5c0001e HEAD -- '*.lua'`. Every new symbol has a reader: `PickUseItem` (Flush l.211), `_actionType` (CreateOverlay init + Place), `_spellAttr`/`_itemAttr` (Place compare+store), `ns.reminderItemClickActive` (written Flush l.230, read Core l.2199), `def.useItems` (only `ns:ReminderUseItems`, l.1401). `_castName` has zero remaining references in any `.lua`. No helper duplicated. Pre-milestone code: BuffEngine.lua changed in comments only; MetaReminderRow change is confined to the Phase 81 `useItems` option (absent at 5c0001e). |
| 2 | Hot paths (reminder aura refresh, reminder click flush, bag-update branch) do no new per-frame/per-event allocation | VERIFIED | No `{}` table constructor in any milestone-added non-comment Lua line. Flush: one map read + a boolean; `PickUseItem` returns prebuilt `useItems[i][3]` (string concat moved to load time in 35b18e1); `pcall(C_Item.GetItemCount, id)` creates no closure. Place: on-change compares only. `BAG_UPDATE_DELAYED`: one field read, dirty-mark only while `reminderItemClickActive`. Aura refresh: milestone added data rows/groups only (load-time `MetaReminderRow`/`MetaReminderGroup` calls). |
| 3 | `stylua .` leaves no diff; `git ls-files --eol` shows CRLF for every touched Lua file; release scripts reviewed | VERIFIED | `stylua --check .` exit 0. `git ls-files --eol`: BuffEngine/Core/Providers/ReminderClick all `i/lf w/crlf attr/text eol=crlf`. release.bat still refuses non-main without `TBT_ALLOW_BRANCH=1` (l.22-26); release.yml extracts first CHANGELOG section and runs `BigWigsMods/packager@v2`; `.pkgmeta` ignores `docs` (added this milestone), `scripts`, `tools`, `.planning`, `CLAUDE.md`, `CHANGELOG.md`. No milestone commit touched release.bat, install.ps1 or `.github/`. CHANGELOG.md unchanged since 5c0001e. |
| 4 | The DOC-07 doc-to-code ID check is re-run after cleanup and finds zero mismatches | VERIFIED | `node scripts/reminders-doc-check.js` (hardened 97fdc5a version): `CODE ROWS 39 (forever 28, retail 10, both 1), GROUPS 19` / `REMINDERS-DOC CHECK PASS (132 Forever IDs, 15 retail IDs, 39 rows)`, exit 0. `--selftest`: `REMINDERS-DOC SELFTEST PASS (47 cases)`, exit 0. |

### Plan must-haves (84-01-PLAN frontmatter)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 5 | No behaviour change: same rows, groups, alternatives, click targets, timers | VERIFIED | 35b18e1 touches no row/group call (the familiar row text at Providers.lua l.1191 is unchanged); doc check still 39 rows / 19 groups / 132+15 IDs. |
| 6 | Familiar click picks the same scroll; no string built per flush (81 IN-01) | VERIFIED | Loop order, the `level >= minLevel` test before the count, the C_Item guard, `issecretvalue` checks and `pcall` are unchanged. `useItems[i][3] = "item:" .. useItems[i][1]` is the identical expression the old `return "item:" .. itemID` evaluated (same numeric operand, same Lua number-to-string conversion), so the returned string is equal. Field 3 is filled before `def` is built and the table is not persisted to SavedVariables (only reader is `ns:ReminderUseItems`). On retail the row returns before the loop, and nothing reads it. |
| 7 | Cache field named `_spellAttr` (81 IN-03) | VERIFIED | `_spellAttr` at ReminderClick.lua l.160 and l.162 only; `_castName` count 0 across the repo's Lua. Like `_castName` before it, the field starts nil and the first Place writes it. |
| 8 | Hot-path verdicts written in SUMMARY | VERIFIED | 84-01-SUMMARY "Task 2: Hot-path verdicts" table covers aura refresh, Flush, PickUseItem, Place, BAG_UPDATE_DELAYED and load-time code; independently confirmed above. |
| 9 | stylua, CRLF, aura-read gate and doc check (+selftests) pass | VERIFIED | `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)`; `AURA-READ SELFTEST PASS (30 cases)`; doc check results as in #4. |
| 10 | Release tooling reviewed; docs/scripts/.planning out of the package | VERIFIED | See #3. |

**Score:** 4/4 roadmap criteria, 10/10 total.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Providers.lua` | MetaReminderRow prebuilds `"item:<id>"` per useItems pair | VERIFIED | l.1147-1152; wired to `def.useItems` l.1156 |
| `ReminderClick.lua` | PickUseItem returns cached string; Place uses `_spellAttr` | VERIFIED | l.71 `return useItems[i][3]`; l.160/162 |
| `BuffEngine.lua` | Comment recording the 8-ID cap vs 18 alternatives (80 IN-04) | VERIFIED | 4 comment lines above `ns:IsEditableTracker`; comment-only diff |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Providers.lua MetaReminderRow | ReminderClick.lua PickUseItem | `def.useItems` -> `ns:ReminderUseItems(entry)` (Flush l.207) -> `PickUseItem(useItems)` (l.211) -> `useItems[i][3]` | WIRED | Same table object flows from row load to the click attribute; `Place(..., itemAttr, ...)` writes it on change |

### Data-Flow Trace (Level 4)

Not applicable beyond the key link above: the phase renders no new dynamic data.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Formatting clean | `stylua --check .` | exit 0 | PASS |
| Line endings | `git ls-files --eol Providers.lua ReminderClick.lua BuffEngine.lua Core.lua` | 4x `w/crlf attr/text eol=crlf` | PASS |
| Aura-read gate | `node scripts/aura-read-gate.js` (+ `--selftest`) | PASS (1 read) / SELFTEST PASS (30 cases) | PASS |
| Doc-to-code check | `node scripts/reminders-doc-check.js` (+ `--selftest`) | PASS 132 Forever / 15 retail / 39 rows; SELFTEST PASS (47 cases) | PASS |
| Working tree after checks | `git status --short` | empty | PASS |

No Lua interpreter on the machine, so the string equality in #6 was established by reading the code, not by running it.

### Probe Execution

None declared; the project has no `scripts/*/tests/probe-*.sh`. Step 7c: SKIPPED.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CLEAN-01 | 84-01 | Cleanup per CLAUDE.md: unused code and duplication this milestone introduced, hot paths the new rows and groups touch, `stylua .`, and the release scripts | SATISFIED | Truths 1-4 |

No orphaned requirements: REQUIREMENTS.md maps only CLEAN-01 to Phase 84.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (milestone-added lines) | - | TBD/FIXME/XXX/TODO/HACK | none found | - |
| Providers.lua | 1394 | The `ns:ReminderUseItems` comment line edited in 35b18e1 is not rewrapped (~190 chars) | Info | Cosmetic; stylua does not reflow comments |
| Providers.lua | ~1096 | A Phase 80-83 header comment line (`rows added later (v0.5.6 included) ...`) is not rewrapped either | Info | Cosmetic |

### Human Verification Required

None for this phase. In-game checks of the new rows and the familiar click are Phase 85 (VER-15).

### Gaps Summary

No gaps. The cleanup commit 35b18e1 is behaviour-preserving: the prebuilt `"item:<id>"` string
is the same expression moved from flush time to load time, and the `_castName` -> `_spellAttr`
rename is complete. The milestone's Lua adds no dead code, duplication or per-event allocation.
Every check passes, including the later-hardened doc check. The release tooling is intact and
`.pkgmeta` keeps `docs/` out of the package.

---

_Verified: 2026-11-09T11:10:26Z_
_Verifier: Claude (gsd-verifier)_
