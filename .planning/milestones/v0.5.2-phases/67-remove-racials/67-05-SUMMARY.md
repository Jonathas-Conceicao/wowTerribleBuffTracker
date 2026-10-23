---
phase: 67-remove-racials
plan: 05
subsystem: catalogue-and-kind-removal
tags: [racials, providers, core, lua]
requires: ["67-01", "67-04"]
provides:
  - "No racial catalogue, helper, tracker kind or load rule in shipped Lua"
  - "ns.KIND with seven kinds; metaSkill survives for Lust"
affects: []
key-files:
  modified:
    - Providers.lua
    - Core.lua
    - BuffEngine.lua
    - CDMTab.lua
key-decisions:
  - "ns.spellKnownHeld is the single known-spell memo; the noRanks parameter and its second table are gone"
requirements-completed: [RACE-11, RACE-12, MIG-03]
duration: 25min
completed: 2026-10-10
---

# Phase 67 Plan 05: Racial catalogue and kind removal Summary

RACIAL_SPELLS, every ns:Racial* reader, the metaSkillCd kind and its cast/rank namespaces, the racial key parsers and the noRanks plumbing are deleted; the only racial wording left in shipped Lua is BuffEngine.lua's migration chain (v7, v8, v12).

## Commits

- 16cccc9: Providers.lua, catalogue region (~337 lines) and metaSkillCd dispatch removed, META_SKILL_PREFIX gone
- c42d053: Core.lua, BuffEngine.lua, CDMTab.lua, kind, parsers, FIXED_LOAD rows, SINGLE_RANK_KINDS, noRanks, metaCooldown indexes, FindTrackerConflict branch

## Deviations from Plan

**[Rule 3 - Blocking] CDMTab.lua touched.** A comment there named ns.metaCooldownKeyBySpell and would have failed the tree-wide identifier gate; reworded to ns.cooldownKeyBySpell. No code change.

## Gate output

- Both `git grep` shipped-source searches (racial words; deleted identifiers): no output.
- BuffEngine awk gate (text after ns:MigrateDropRacials): no output.
- `stylua .`: exit 0, no stray changes.
- `git ls-files --eol`: BuffEngine, CDMTab, Core, Display, Providers, migrate-dryrun.js, aura-read-gate.js all `w/crlf`.
- `node scripts/migrate-dryrun.js --selftest`: SELFTEST PASS (13 cases).
- `node scripts/aura-read-gate.js`: AURA-READ GATE PASS (4 reads in 2 allowlisted readers); `--selftest`: PASS (30 cases), exit 0.
- Real-file dry run (classic_beta SavedVariables): schemaVersion in 11, out 12; 26 `v12: ... dropped (racial)` lines; 25 trackers kept (userBuff, userCd, userReminder, metaReminder, metaItem), none metaSkill:<digits> or metaSkillCd.
- `git diff --stat HEAD -- TerribleBuffTracker.toc CHANGELOG.md README.md`: empty.
- `./scripts/install.bat`: exit 0, deployed to retail, ptr, beta and classic_beta (v0.5.1-24-gc42d053-dev).

## Performance and cleanup review

- UserSpellProviderMixin:OnTrigger lost one StartCooldownFromCast call (two lookups per cast); nothing added.
- Display.lua not edited; no new per-frame work.
- ns:SpellKnownState and ns:ResolveSpellKnown lost a parameter and a second held table; all callers (Core, Providers, ReminderClick) already passed two arguments.
- Orphaned locals: none found for the removed identifiers (tree-wide greps clean).

## Deferred to Phase 72 (in-game)

1. Retail and Forever: Buffs and Cooldowns tabs show no racial Suggested tile; casting a racial starts no TBT tracker.
2. Forever: logging in with the current SavedVariables (racial trackers present) raises no Lua error, racial trackers are gone, other trackers keep container, order and settings.
3. User cooldown, user buff, reminder, class-buff reminder, Lust, trinket, pot and bag item still start, draw and load/unload as before.
4. `/tbt debug` prints SPELL and ITEM lines only.
No TOC change: `/reload` suffices.

## Known Stubs

None.

## Self-Check: PASSED

Commits 16cccc9 and c42d053 exist; STATE.md and ROADMAP.md untouched.
