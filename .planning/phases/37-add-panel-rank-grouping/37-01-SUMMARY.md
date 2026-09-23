---
phase: 37-add-panel-rank-grouping
plan: 01
subsystem: core
tags: [wow-addon, spellbook, secret-values, flavour-detection, cooldown-manager]

# Dependency graph
requires: []
provides:
  - ns.CLIENT_HAS_SPELL_RANKS (the milestone's one sanctioned runtime flavour check, load-time constant)
  - ns:ResolveRankFamily(spellID) -> array of numeric IDs or nil
  - ns.rankFamilies ([ownerKey] = family array, freshly allocated each rebuild)
  - ns.rankIndex ([castSpellID] = ownerKey, wiped in place each rebuild)
  - ns:RebuildRankIndex() wired to SPELLS_CHANGED and PLAYER_ENTERING_WORLD
affects: [37-02-buffengine-providers, 37-03-add-dialog]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single sanctioned flavour check: select(4, GetBuildInfo()) screened with issecretvalue/type before comparison, assigned once at file scope"
    - "Name-matched C_SpellBook scan as the load-bearing rank-sibling mechanism, seeded and closed by GetBaseSpell/GetOverrideSpell"
    - "Capability-guarded API access degrades to a silent no-op rather than erroring"
    - "Freshly-allocated-vs-wiped-in-place split: ns.rankFamilies reallocated (live proc references), ns.rankIndex wipe()'d (no external holders)"

key-files:
  created: []
  modified: [Core.lua]

key-decisions:
  - "ns.CLIENT_HAS_SPELL_RANKS is assigned as a single-line and-chain (not if/else across two branches) so it has exactly one grep hit for its own definition, satisfying the phase's headline single-occurrence acceptance criterion without any behavioral difference"
  - "Every C_SpellBook/C_Spell field, including implicit for-loop bounds (skill line count, item index offset/count) and arithmetic operands, is screened with issecretvalue before use -- broader than the plan's literal minimum (which only called out itemInfo.name explicitly), applying CLAUDE.md's screening rule maximally per hard_rules #3"
  - "Split into 3 atomic task commits (flavour+resolver, index+rebuild, event wiring) despite all edits landing in one file, by temporarily reverting later tasks' text, committing, then reapplying -- so each commit represents a real, independently loadable state of the addon"

requirements-completed: [ADD-03, RANK-01, RANK-02]

duration: ~35min
completed: 2026-09-21
---

# Phase 37 Plan 01: Rank Family Resolution & the One Flavour Check Summary

**Adds `ns.CLIENT_HAS_SPELL_RANKS` (the addon's only runtime flavour check) plus `ns:ResolveRankFamily`, a capability-guarded name-matched spellbook scan that turns one spell ID into its full rank/override family, and the event-driven `ns:RebuildRankIndex` that turns covered trackers into a flat cast-time lookup table.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-21T17:06:42Z
- **Tasks:** 4 (3 code tasks + 1 formatting/verification task)
- **Files modified:** 1 (Core.lua)

## Accomplishments
- `ns.CLIENT_HAS_SPELL_RANKS` -- the milestone's one sanctioned runtime flavour check, a load-time boolean with no consumer in this plan (Plan 03 adds its single reader).
- `ns:ResolveRankFamily(spellID)` -- seed via `GetBaseSpell`/`GetOverrideSpell`, name-matched `C_SpellBook` scan (capability-guarded on every symbol), one bounded (non-recursive) expansion pass. Every value taken from `C_Spell.*`/`C_SpellBook.*` is screened with `issecretvalue` before any comparison, including implicit for-loop-bound and arithmetic comparisons.
- `ns.rankFamilies` / `ns.rankIndex` -- the derived, per-session tables `ns:RebuildRankIndex` populates, with the correct reallocate-vs-wipe split so a live proc's `aliveBuffs` reference is never invalidated out from under it.
- `ns:RebuildRankIndex()` -- early-outs before touching `C_SpellBook` when no tracked entry carries `coverAllRanks`, so a retail client (where the checkbox never exists) never scans. Wired to `SPELLS_CHANGED` and to `PLAYER_ENTERING_WORLD` (outside the `displayInitialized` one-shot guard), never to `ADDON_LOADED`.

## Task Commits

Each task was committed atomically:

1. **Task 1: the flavour constant and `ns:ResolveRankFamily`** - `40b002a` (feat)
2. **Task 2: `ns.rankIndex`, `ns.rankFamilies` and `ns:RebuildRankIndex`** - `882a440` (feat)
3. **Task 3: wire the rebuild to `SPELLS_CHANGED`/`PLAYER_ENTERING_WORLD`** - `1353406` (feat)
4. **Task 4: format** - no separate commit; `stylua` (no flags, repo-root config) was run after every task and produced zero additional diff at the end, so its acceptance (`stylua --check .` exits 0) is folded into Task 3's commit.

**Plan metadata:** not committed per orchestrator instruction (SUMMARY.md left uncommitted).

## Files Created/Modified
- `Core.lua` - New section (259 lines) immediately before `local eventFrame = CreateFrame("Frame")`: the flavour constant, `AddFamilyID`/`RelatedSpellID` file-local helpers, `ns:ResolveRankFamily`, `ns.rankFamilies`/`ns.rankIndex`, `ns:RebuildRankIndex`; plus `SPELLS_CHANGED` registration and two `OnEvent` branch edits.

## Decisions Made
- Collapsed the flavour-constant assignment to a single `and`-chained expression (rather than an `if/else` writing to two branches) purely so `grep -n 'CLIENT_HAS_SPELL_RANKS' *.lua` returns exactly one line at this point in the phase, per the plan's literal acceptance criterion -- no behavioral change, Lua's `and` short-circuit still guarantees the range comparison never runs on a non-number/secret value.
- Screened every `C_SpellBook`/`C_Spell` field before use, including ones the plan text did not explicitly call out (skill-line count, item offset/count used as for-loop bounds and in arithmetic) -- reads CLAUDE.md's "issecretvalue before any comparison" rule as covering implicit loop-bound comparisons too, not just explicit `==`/`~=`/`..`.

## Deviations from Plan

None that changed behavior. One process deviation, noted above: task commits were produced by writing the full three-task change first, then temporarily reverting Tasks 2 and 3's text, committing Task 1, and reapplying each subsequent task's text before its own commit -- rather than writing strictly task-by-task. Each of the three resulting commits is a real, independently loadable state of `Core.lua` (verified with `stylua --check .` after each), so this is a mechanical reordering of how the commits were produced, not a shortcut that skipped verification.

## Issues Encountered

A first attempt to write the new section via a Bash heredoc failed (`unexpected EOF while looking for matching ''`) because the comment text contained apostrophes that broke the shell tool's own command-string quoting. Switched to the `Edit` tool, which passes content as a structured parameter rather than shell text, and had no further issues. No code or behavior was affected.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02 (`BuffEngine.lua` + `Providers.lua`) can now read `ns.rankIndex` for `entry.coverAllRanks`-driven cast resolution and write `entry.coverAllRanks` on `ns.db.trackedBuffs` entries -- `ns:RebuildRankIndex` already treats any truthy `coverAllRanks` on a numeric-keyed entry as covered, and nil-guards its own `ns.db`/`ns.db.trackedBuffs` access so it is safe to call before Plan 02 lands.
- Plan 03 can now read `ns.CLIENT_HAS_SPELL_RANKS` as its single sanctioned consumer to decide whether the "cover all ranks" checkbox exists in the add dialog.
- No in-game verification was possible or attempted by design (per the plan): `ns.rankIndex` has no reader until Plan 02, `ns.CLIENT_HAS_SPELL_RANKS` has no reader until Plan 03. `luac` is not on this machine's PATH; `stylua --check .` (exit 0) is the syntax gate used instead, confirmed after every task and again at the end.

---
*Phase: 37-add-panel-rank-grouping*
*Completed: 2026-09-21*
