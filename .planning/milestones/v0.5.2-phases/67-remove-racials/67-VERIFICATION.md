---
phase: 67-remove-racials
verified: 2026-10-10T00:00:00Z
status: human_needed
score: 4/4 must-haves verified from source (in-game confirmation deferred to Phase 72)
overrides_applied: 0
human_verification:
  - test: "On retail and on Forever, open the Buffs and Cooldowns tabs"
    expected: "No racial Suggested tile; casting a racial starts no meta tracker"
    why_human: "Needs a live client; source shows no racial catalogue, provider or tile"
  - test: "Log in with a SavedVariables file holding racial buff and cooldown trackers (v0.4.x and v0.5.1 shapes)"
    expected: "No Lua error, racial trackers gone, every other tracker keeps container, order and settings, no chat message"
    why_human: "Real client load; the dry-run mirror passes but the Lua itself only runs in game"
  - test: "Look for orphan tiles or stale timers after the migration"
    expected: "Display refreshes cleanly, no ghost icons"
    why_human: "Visual check"
---

# Phase 67: Remove Racials Verification Report

**Phase Goal:** Racials are gone from TBT on every client, and saved racial trackers are removed by a silent schema migration that leaves every other tracker untouched.
**Status:** human_needed (all source-checkable items pass; in-game checks deferred to Phase 72 by user decision)

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | No racial Suggested tile or racial meta-tracker start on either client | VERIFIED (source) | `git grep -i racial` in shipped Lua/XML/TOC finds only BuffEngine.lua migration code. Providers.lua holds only Trinket, Pot, Lust and User providers. The only `metaSkill` keys left are `metaSkill:lust`. |
| 2 | No racial catalogue, provider, tracker kind, Suggested entry or stack-count display in shipped source | VERIFIED | `metaSkillCd` appears only as a function-local frozen pattern in `MigrateDropRacials`. No `.stacks` hits in Display, Core or Providers. No race lookup anywhere. The aura-read gate has no racial row. |
| 3 | Saved racial trackers are removed silently and others are untouched | VERIFIED (source), game load deferred | `ns:MigrateDropRacials` (BuffEngine.lua ~722) matches by key shape (`^metaSkill:%d+$`, `^metaSkillCd:%d+$`, `racial`, `racial2`), collects keys before deleting, keeps `metaSkill:lust`, prints nothing and sets the schema version. v7 drops the legacy slots. v8 drops legacy racial cooldowns through the frozen `LEGACY_RACIAL_CD` list (WR-01 fix), so none survive as userCd. Chain order is correct, and v11 is pinned to the literal 11. |
| 4 | `migrate-dryrun.js` shows racials removed with everything else unchanged, and `--selftest` passes | VERIFIED | `node scripts/migrate-dryrun.js --selftest` gives 13/13 PASS, including "client-written file with racial trackers -> v12" and "v11 -> v12: racial trackers dropped, every other tracker untouched". `aura-read-gate.js` PASS (4 reads in 2 readers), and its selftest PASS (30 cases). |

**Score:** 4/4

## Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| RACE-11 (no racial trackers or tiles on any client) | SATISFIED in source (in-game pending) | Truths 1 and 2 |
| RACE-12 (nothing racial left in code) | SATISFIED | Truth 2. Remaining mentions are migration code and comments, which are required by MIG-03. |
| MIG-03 (schema migration removes saved racial trackers) | SATISFIED | Truths 3 and 4 |

No orphaned requirements: REQUIREMENTS.md maps only these three IDs to Phase 67. The checkboxes and the traceability table still read Pending and need updating at phase close.

## Anti-Patterns and Warnings

| Item | Severity | Note |
|------|----------|------|
| `README.md` lines 12, 19 and 45, plus `Assets/forever_racial.png` | Warning | The user-facing README still advertises racial trackers. This is documentation, not shipped code, so it does not fail RACE-12. Needs a docs or changelog cleanup, probably in the milestone cleanup phase. |
| `CLAUDE.md` line 19 | Info | The Providers.lua description still lists "racial" meta trackers. |
| Debt markers | None | No TBD, FIXME or XXX hits from the greps run. |
| Line endings | OK | BuffEngine.lua is `w/crlf`. |

## Human Verification Required

See the frontmatter. All three items are in-game checks deferred to Phase 72.

## Gaps Summary

No source-level gaps. The checkboxes in REQUIREMENTS.md and ROADMAP.md are not yet ticked. The README racial references are a documentation follow-up.

_Verifier: Claude (gsd-verifier)_
