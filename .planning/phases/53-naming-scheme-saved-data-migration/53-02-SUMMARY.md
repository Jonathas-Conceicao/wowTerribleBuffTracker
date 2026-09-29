---
phase: 53-naming-scheme-saved-data-migration
plan: 02
subsystem: infra
tags: [saved-variables, schema-migration, lua, wow-addon, naming-scheme]

# Dependency graph
requires:
  - phase: 53-naming-scheme-saved-data-migration
    provides: "plan 53-01's scripts/migrate-dryrun.js --selftest -- the executable spec this plan's Lua migration reconciles against in plan 53-05"
provides:
  - "Core.lua ns.KIND / ns.KEY_SEPARATOR / ns.KEY_PREFIX / ns.META_KEY -- the one table that mints and parses every tracker key"
  - "ns:TrackerKey(kind, id), ns:KeyKind, ns:KeyNumericID and the CooldownKeySpellID/ItemKeyItemID/RacialKeySpellID/SpellKeySpellID parser wrappers"
  - "ns:CooldownKindFor(spellID), ns:IsCooldownSlotEntry(entry), ns:IsBagItemEntry(entry) -- kind-driven predicates replacing the trackerType == \"cooldown\"/\"item\" string tests"
  - "ns:RebuildCastIndex() and ns.buffKeyBySpell/ns.cooldownKeyBySpell -- the spellID -> key index that keeps the cast path a single table lookup"
  - "BuffEngine.lua schema v8 (ns:MigrateKindKeys) -- re-keys a v0.4.1 database onto the canonical scheme after schema v7 has completed, on both ADDON_LOADED and the PLAYER_ENTERING_WORLD retry"
  - "ns:AddTrackedBuff / ns:RemoveTrackedBuff mint and accept canonical keys"
affects: [53-03, 53-04, 53-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One kind table drives minting AND parsing -- ns.KEY_PREFIX/KEY_ID_PATTERNS/KNOWN_KINDS are all built from a single loop over ns.KIND at file load, so a new kind can never add a prefix without a matching parser"
    - "Legacy migration blocks freeze their own literals ("cd:" .. key, "racial:" .. def.spellID, literal schema-version gates/stamps) instead of calling the live helpers those helpers have since been repointed at the new scheme -- the v5->v6 precedent, now also applied to v6->v7"
    - "Cast index rebuilt at every ns:RebuildRankIndex call site (add/remove/migration/world entry/SPELLS_CHANGED) rather than concatenated per-cast -- the hot path stays one table lookup"
    - "Move-not-rebuild schema migration: collect every key into a snapshot array before any key is deleted or written, then move each entry table object (never construct a new one) to its canonical key"

key-files:
  created: []
  modified:
    - "Core.lua - ns.KIND/ns.KEY_PREFIX/ns.META_KEY scheme, key parsers, ns:CooldownKindFor, ns:IsCooldownSlotEntry/IsBagItemEntry, ns:RebuildCastIndex, kind-driven ns:RebuildRankIndex, ns:GetTrackerCategory, ns:MigrateKindKeys wired into PLAYER_ENTERING_WORLD"
    - "BuffEngine.lua - CURRENT_SCHEMA_VERSION = 8, v6/v7 literal-pinned, new ns:MigrateKindKeys, ns:AddTrackedBuff/ns:RemoveTrackedBuff mint/accept canonical keys, ns.SUGGESTED_KEYS canonical"

key-decisions:
  - "trackerType field name kept (not renamed to kind) -- Claude's discretion per 53-CONTEXT, chosen because it is the field every existing read site (Display.lua, Providers.lua, CDMTab.lua -- all untouched by this plan) already names, and because ROADMAP criterion 2 / NAME-02 name it"
  - "ns:CooldownKindFor and the numeric-key/cd:-key branches of ns:MigrateKindKeys call ns:IsRacialSpellID, which plan 53-03 defines in Providers.lua -- Core.lua/BuffEngine.lua consume it by name since the TOC loads Core.lua first and nothing in THIS plan's tasks invokes the function at runtime (nothing is deployed until plan 53-05, per the plan's own objective note)"
  - "RebuildRankIndex's contested-ID check now reads ns.buffKeyBySpell/ns.cooldownKeyBySpell (rebuilt by ns:RebuildCastIndex at the top of the same function) instead of ns.db.trackedBuffs[directKey] -- same semantics (does a direct tracker in this namespace already own this spellID), one indirection cheaper"

requirements-completed: [NAME-01, NAME-02]

# Metrics
duration: 11min
completed: 2026-09-28
---

# Phase 53 Plan 02: Naming Scheme Foundation + Saved-Data Migration Summary

**One ns.KIND table in Core.lua mints and parses every `<kind>:<id>` tracker key, a spellID -> key cast index replaces the per-cast string concat, and BuffEngine.lua's new schema v8 re-keys a v0.4.1 database onto the scheme after a literal-pinned schema v7 completes.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-09-28T11:03:19Z (previous plan's completion commit)
- **Completed:** 2026-09-28T11:14:39Z
- **Tasks:** 2/2 completed
- **Files modified:** 2

## Accomplishments
- `ns.KIND` names all six canonical kinds (`userBuff`, `userCd`, `metaSkill`, `metaSkillCd`, `metaItem`, `userItem`); `ns.KEY_PREFIX`, a file-local `KEY_ID_PATTERNS` and a file-local `KNOWN_KINDS` are all built from one module-scope loop over `ns.KIND`, so no key prefix can ever exist without a matching parser pattern.
- `ns:TrackerKey(kind, id)` is the only place in the addon that concatenates a key; `ns.META_KEY.LUST/TRINKET/POT` are minted through it and match plan 53-01's `scripts/migrate-dryrun.js` constants byte-for-byte.
- `ns:KeyKind`/`ns:KeyNumericID` plus the four wrapper parsers (`CooldownKeySpellID`, `ItemKeyItemID`, `RacialKeySpellID`, `SpellKeySpellID`) replace three hand-written `"^prefix:(%d+)$"` patterns with parsers derived from the same table that mints keys.
- `ns:IsCooldownSlotEntry`/`ns:IsBagItemEntry` replace the `entry.trackerType == "cooldown"/"item"` string tests; `ns:GetTrackerCategory` now derives through the first of those instead of its own literal comparison.
- `ns:RebuildCastIndex` (`ns.buffKeyBySpell`/`ns.cooldownKeyBySpell`) is called from `ns:RebuildRankIndex` (every existing call site: add, remove, migration, world entry, SPELLS_CHANGED) and once more at the end of `ns:InitBuffEngine`, so the cast path stays a single table lookup now that no key equals a spellID.
- `ns:RebuildRankIndex`'s owner collection and contested-ID check are rewritten to read `entry.trackerType`/`entry.spellID` and the cast index instead of the key's own shape, reproducing the old sort order exactly (sorted by owner spellID, tied by key).
- BuffEngine.lua's schema chain: `CURRENT_SCHEMA_VERSION = 8`; the v6 block freezes `"cd:" .. key` instead of calling `ns:TrackerKey`; `ns:MigrateRacialKeys` (v7) is pinned to the literal `7` on both its gate and its stamp, and freezes `"racial:" .. def.spellID`; the new `ns:MigrateKindKeys` (v8) runs only once v7 has completed, moves every tracker (never rebuilds one) onto its canonical key, rewrites `entry.key`/`entry.trackerType`, backfills `spellID`/`itemID` only where absent, and follows a moved record's runtime proc/timer/cooldown-override slots to the new key.
- `ns:AddTrackedBuff` mints through `ns:CooldownKindFor`/`ns:TrackerKey`; its chat print still says "buff"/"cooldown" even though `trackerType` now stores a kind string. `ns:RemoveTrackedBuff` takes a canonical `key`, resolves an unrecognised key's spell/item id for its "not tracked" print, and only appends `(ID: ...)` to its "Stopped tracking" print when the tracker has one (a meta tracker does not).

## Task Commits

Each task was committed atomically:

1. **Task 1: Core.lua -- the kind table, key minting/parsing, slot predicates, cast index, kind-driven rank index** - `f3b8a31` (feat)
2. **Task 2: BuffEngine.lua -- pin v6/v7, add schema v8 ns:MigrateKindKeys, canonical add/remove** - `759f28f` (feat)

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified
- `Core.lua` - `ns.KIND`/`ns.KEY_SEPARATOR`/`ns.KEY_PREFIX`/`ns.META_KEY`, `ns:TrackerKey`, `ns:KeyKind`, `ns:KeyNumericID`, the four spell/item parser wrappers, `ns:CooldownKindFor`, `ns:IsCooldownSlotEntry`, `ns:IsBagItemEntry`, `ns:GetTrackerCategory` (rewritten to derive through `IsCooldownSlotEntry`), `ns.buffKeyBySpell`/`ns.cooldownKeyBySpell`/`ns:RebuildCastIndex`, `ns:RebuildRankIndex` (kind-driven owner collection, spellID-first sort, cast-index contested-ID check), `ns:MigrateKindKeys()` wired into the `PLAYER_ENTERING_WORLD` branch directly after `ns:MigrateRacialKeys()`
- `BuffEngine.lua` - `CURRENT_SCHEMA_VERSION = 8`; v6 block's re-key literal frozen to `"cd:" .. key`; `ns:MigrateRacialKeys` pinned to literal `7` (gate and stamp) and its `"racial:" .. def.spellID` literal; new `function ns:MigrateKindKeys()`; `ns:InitBuffEngine` calls `ns:MigrateKindKeys()` after `ns:MigrateRacialKeys()` and `ns:RebuildCastIndex()` after the `PreallocateProc` loop; `ns.SUGGESTED_KEYS` built from `ns.META_KEY`; `ns:AddTrackedBuff`/`ns:RemoveTrackedBuff` rewritten for canonical keys

## Decisions Made
- Kept `trackerType` as the field name rather than renaming to `kind` (Claude's discretion per 53-CONTEXT) -- every existing read site outside this plan's two files (Display.lua, Providers.lua, CDMTab.lua) already names it `trackerType`, and NAME-02/ROADMAP criterion 2 name that field explicitly.
- `ns:CooldownKindFor` and two branches of `ns:MigrateKindKeys` call `ns:IsRacialSpellID`, which does not exist until plan 53-03 (Providers.lua). This matches the plan's own objective note -- "between this plan and plans 53-03/53-04 the addon is intentionally inconsistent... Nothing is deployed until plan 53-05" -- and is not a defect of this plan; no task in this plan invokes either function at runtime.
- `ns:RebuildRankIndex`'s contested-ID check now reads `ns.buffKeyBySpell`/`ns.cooldownKeyBySpell` (freshly rebuilt by the `ns:RebuildCastIndex()` call at the top of the same function) instead of `ns.db.trackedBuffs[directKey]` -- same "does a direct tracker in this namespace already own this spellID" semantics, without reconstructing a namespaced key string per family member.

## Deviations from Plan

None - plan executed exactly as written. All Task 1 and Task 2 acceptance-criteria greps (`stylua --check`, `git ls-files --eol`, `git diff --numstat`, and every structural grep/awk assertion listed in the plan) passed on the first implementation; no auto-fixes were needed. One self-inflicted issue was caught and fixed during verification, not counted as a plan deviation: an early draft of a Core.lua comment referenced the literal string `_KEY_PREFIX` (describing the removed `ns.COOLDOWN_KEY_PREFIX` constant in prose) and tripped the plan's own "0 occurrences of `_KEY_PREFIX`" acceptance grep -- reworded before committing, verified with the same grep, no functional code was affected.

## Issues Encountered

None. `stylua --check Core.lua BuffEngine.lua` passed on the first formatting pass for both files; `node scripts/migrate-dryrun.js --selftest` (plan 53-01's spec) still prints `SELFTEST PASS (5 cases)` unchanged, confirming this plan touched nothing that script depends on (it reads `Providers.lua`'s `RACIAL_SPELLS` table directly, which this plan did not modify).

## Human Verification Needed

None for this plan. Both tasks are pure Lua source edits verified by `stylua --check`, `git ls-files --eol`, `git diff --numstat`, and the full set of structural grep/awk acceptance criteria specified in the plan -- no WoW client is available in this environment. Real in-game logout/login verification of the migration is plan 53-05's responsibility (NAME-02), once plans 53-03 (Providers.lua, including `ns:IsRacialSpellID`) and 53-04 (CDMTab/Display/MergeMode callers) have brought every caller back into agreement with the scheme this plan defines.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Core.lua's `ns.KIND`/`ns.KEY_PREFIX`/`ns.META_KEY`/`ns:TrackerKey`/parser/predicate/cast-index API and BuffEngine.lua's schema v8 are in place exactly as the plan's `<interfaces>` block specifies, ready for plan 53-03 (Providers.lua, which must define `ns:IsRacialSpellID` that this plan's `ns:CooldownKindFor` and `ns:MigrateKindKeys` already call by name) and plan 53-04 (CDMTab.lua/Display.lua/MergeMode.lua callers, which still reference the removed prefix constants and old `trackerType` string values until then). No blockers. The addon is intentionally inconsistent until those two plans land -- exactly as this plan's objective states -- and nothing is deployed to a WoW client until plan 53-05 reconciles this Lua migration against plan 53-01's `scripts/migrate-dryrun.js --selftest` spec and runs the real logout/login verification.

---
*Phase: 53-naming-scheme-saved-data-migration*
*Completed: 2026-09-28*
