---
phase: 53-naming-scheme-saved-data-migration
reviewed: 2026-09-28T11:45:55Z
depth: deep
files_reviewed: 7
files_reviewed_list:
  - Core.lua
  - BuffEngine.lua
  - Providers.lua
  - Display.lua
  - MergeMode.lua
  - CDMTab.lua
  - scripts/migrate-dryrun.js
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: issues_found
fix_status: all_fixed
fixed_at: 2026-09-28
fix_scope: all
findings_fixed: 8
findings_skipped: 0
findings_list:
  - id: WR-01
    severity: warning
    file: Core.lua:563
    scenario: "A future RACIAL_SPELLS addition turns an existing userCd:<X> into a duplicate of a new metaSkillCd:<X>. The cast index keeps only metaSkillCd:<X>, so the user's own cooldown tracker stops starting and nothing reports it."
    fix: "Make one cooldown key per spellID regardless of kind: have CooldownKindFor/AddSuggestedTracker/AddTrackedBuff reuse any existing userCd:/metaSkillCd: entry for that spellID, and hide Suggested racial cooldown tiles whose spellID is already in ns.cooldownKeyBySpell."
    outcome: "fixed (ce0717e), requires human verification: AddTrackedBuff and AddSuggestedTracker reuse an existing userCd:/metaSkillCd: key from ns.cooldownKeyBySpell; RebuildCastIndex prefers userCd over metaSkillCd before the tostring tie-break. Tiles are not hidden -- dragging a racial cooldown tile moves the existing tracker, the pre-Phase-53 cd:X behaviour."
  - id: WR-02
    severity: warning
    file: BuffEngine.lua:277
    scenario: "UnitRace is unreadable, so v7 defers even for a database with no racial/racial2 slot. v8 is gated on v7, so every tracker stays on legacy keys and trackerType values that the Phase 53 runtime no longer reads. No casts start, cooldown slots render as buffs and icons fall back to the question mark. A tracker added in that state later collides with its legacy twin, and v8 drops the older record, taking its placement with it."
    fix: "In MigrateRacialKeys, stamp 7 without reading the race when neither trackedBuffs.racial nor trackedBuffs.racial2 exists. Defer only when there is a legacy slot to resolve."
    outcome: "fixed (bf6e0e5): MigrateRacialKeys stamps 7 without reading the race when neither slot exists; mirrored in migrate-dryrun.js migrateV7; new selftest case F."
  - id: WR-03
    severity: warning
    file: scripts/migrate-dryrun.js:77
    scenario: "The user follows the 53-05 checklist and runs the dry-run against their real SavedVariables. Any saved array (userContainers with one container), any '-- [n]' index comment or any escaped quote in a label makes parse() throw 'expected ['. It also skips v1-v3, so for a pre-v4 file it predicts a metaSkill:lust that v3 would have deleted."
    fix: "Teach parse() implicit array entries, '--' comments and backslash escapes, and mirror v1-v3 (at minimum v3's hidden-lust removal). Or drop the 'predicts the exact re-key' claim from 53-05-SUMMARY."
    outcome: "fixed (54da1dd): parse() handles implicit array entries, -- and --[[ ]] comments, bare identifier keys and backslash escapes; migrate() ports v1-v3; new selftest case G with a client-shaped pre-v4 fixture. Also ran cleanly against the four real SavedVariables files on this machine."
  - id: IN-01
    severity: info
    file: BuffEngine.lua:486
    scenario: "An entry v8 cannot classify (numeric key with an unrecognised trackerType, or an unknown string key) stays on its legacy key, and the schema is still stamped 8. GetDisplayInfoForKey now rejects non-string keys and the cast index skips it, so the tracker is permanently dead with no log line."
    fix: "Print a one-line warning for each unclassified key before stamping 8, or route leftover numeric keys to userBuff."
    outcome: "fixed (8e8eb52): one chat line per unclassified key; data behaviour unchanged (entry left in place, never deleted)."
  - id: IN-02
    severity: info
    file: Providers.lua:2210
    scenario: "Racial placeholders (tracked metaSkill:<id>) are drawn every tick with hideWhenInactive off or the CDM open. Each draw re-parses the key through RacialKeySpellID (a string.match capture). This contradicts the 'parse-free for anything already tracked' claim, though it is fewer parses than before the phase."
    fix: "Pass entry.spellID into the racial provider (or memo by key) so a tracked entry never parses."
    outcome: "fixed (af474ae): GetDisplayInfoForKey passes the tracked entry's spellID into MetaSkillRacialProvider:GetDisplayInfo(key, knownSpellID); allocation-free, so the parse-free claim is now true rather than reworded."
  - id: IN-03
    severity: info
    file: CDMTab.lua:612
    scenario: "The trailing 'or 134400' after ns:GetSpellIcon(...) can never run, because GetSpellIcon already returns 134400 for nil. Same at CDMTab.lua:1088-1089."
    fix: "Drop the trailing 'or 134400'."
    outcome: "fixed (78f99d4)."
  - id: IN-04
    severity: info
    file: Core.lua:99
    scenario: "Stale or contradicted comments. GetTrackerCategory says an entry written by any earlier version answers correctly with no schema bump, which is no longer true. BuffEngine.lua:95-97 still reasons about nil == \"cooldown\". Core.lua:462/491 call ns:TrackerKey the only place that concatenates a key, but Providers.lua concatenates META_SKILL_PREFIX/META_ITEM_PREFIX at six sites. The ns.MetaItem*/MetaSkill*ProviderMixin exports have no readers."
    fix: "Update the comments. Optionally remove the unread ns.*ProviderMixin exports."
    outcome: "fixed (9692b45): comments corrected at all three sites; the four unread ns.Meta*ProviderMixin exports removed (no readers in any .lua/.xml/.js). ns.UserSpellProviderMixin predates the phase and was left."
  - id: IN-05
    severity: info
    file: BuffEngine.lua:815
    scenario: "RemoveTrackedBuff (rewritten this phase) still concatenates entry.label unguarded. An entry with no label (Fixture A's trinket/pot/6673 shapes) throws on delete, after the DB row has already been removed."
    fix: "Use (label or tostring(key)) in both print branches."
    outcome: "fixed (69fa2cb)."
---

# Phase 53: Code Review Report

**Reviewed:** 2026-09-28T11:45:55Z
**Depth:** deep
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed `git diff 103dd82..HEAD` for Core.lua, BuffEngine.lua, Providers.lua, Display.lua, MergeMode.lua, CDMTab.lua and scripts/migrate-dryrun.js, reading the full surrounding code. `node scripts/migrate-dryrun.js --selftest` passes all 5 cases.

What was checked and holds:

- **Saved-data safety.** v8 (`ns:MigrateKindKeys`) moves records rather than rebuilding them. It snapshots keys before mutating, and every legacy shape a real v0.4.1 database can contain maps to a distinct key, so the collision branch cannot be reached from real data. It runs strictly after v7 on both triggers. v7 is pinned to a literal 7 and freezes its `"racial:"` literal. A second run is a one-comparison no-op. A pre-v6 database walks v1-v6, then v7, then v8 correctly.
- **Upvalue trap and load order.** No new trap was found. Providers.lua's key constants are hoisted to line 12, and `KEY_ID_PATTERNS`/`KNOWN_KINDS` sit above every function that reads them. The load-time reads of `ns.META_KEY` (BuffEngine.lua:68, CDMTab.lua:11, Providers.lua:12) all come after Core.lua in TOC order. `ns:IsRacialSpellID` is only called at ADDON_LOADED or later, after Providers.lua has loaded. `ns:UpdateDisplay`, now reached at ADDON_LOADED for almost every upgrading user, is safe before `InitDisplay`: `ns.containers` is nil, so it only hides.
- **Key used as a spellID.** No site passes a key to a spell API or compares a key to a number. The icon, tooltip and label paths resolve for every kind, tracked or Suggested.
- **Hot path and secret values.** The cast path is still one table lookup with no allocation. No new comparison touches a possibly-secret value.

The remaining risks are robustness gaps: the kind is baked into the key from a mutable table (WR-01), v8 depends on v7's race read even when there is nothing racial to migrate (WR-02), and the advertised dry-run cannot read a real SavedVariables file (WR-03).

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Cooldown kind is baked into the key from a mutable catalogue, so a later RACIAL_SPELLS change produces duplicate trackers and one of them silently stops working

**File:** `Core.lua:563-568` (also `Core.lua:881-885`, `CDMTab.lua:924-937`, `BuffEngine.lua:738-757`)

**Issue:** Before Phase 53, a user cooldown and a racial cooldown tile for the same spell were the same key, `cd:<X>`, so they could not coexist. Now `ns:CooldownKindFor` chooses between `userCd` and `metaSkillCd` using the current `racialSpellOwners`, and that choice is written permanently into the key, both at migration and at add time. `RACIAL_SPELLS` is hand-maintained and has already been refilled once (Phase 49 / RACE-07). Suppose a later release adds spell X to it:

1. The user already has `userCd:X`, created while X was not a racial.
2. `ns:RacialCooldownKeys()` now offers `metaSkillCd:X`. The Cooldowns-tab Suggested loop (CDMTab.lua:924) does not check whether X is already tracked. The user drags the tile, and `AddSuggestedTracker` sees no entry at `metaSkillCd:X`, so it creates a second cooldown tracker for X.
3. `ns:RebuildCastIndex` keeps one key per spellID, and the lower `tostring` wins. `"metaSkillCd:X" < "userCd:X"`, so `userCd:X`, with its container, order and duration, never starts again. Nothing logs this.

The same happens through the Add dialog (`AddTrackedBuff`), which mints `metaSkillCd:X` next to an existing `userCd:X` rather than overwriting it, as the old code did with `cd:X`. It also happens in reverse when a spell is removed from the table.

**Fix:** Keep the cooldown namespace one key per spellID whatever the kind. Before minting, look up `ns.cooldownKeyBySpell[spellID]` and reuse or move the existing entry. Filter the Suggested racial cooldown tiles the same way the buff and item loops do:
```lua
-- CDMTab.lua, racial cooldown loop
local spellID = ns:CooldownKeySpellID(cooldownKey)
if not ns.db.trackedBuffs[cooldownKey] and not ns.cooldownKeyBySpell[spellID] then
	-- offer tile
end
-- BuffEngine.lua AddTrackedBuff / CDMTab AddSuggestedTracker
local existing = ns.cooldownKeyBySpell[spellID]
if existing then dbKey = existing end
```

### WR-02: v8 is gated on v7's race read even when there is no legacy racial slot, and the deferred state breaks the whole runtime

**File:** `BuffEngine.lua:277-279` (gate at `BuffEngine.lua:364-368`)

**Issue:** `ns:MigrateRacialKeys` returns before stamping 7 whenever `UnitRace` is unreadable, including for the large majority of databases that have no `racial`/`racial2` key and so nothing that needs a race. `ns:MigrateKindKeys` refuses to run below 7. Before Phase 53, a deferred v7 only affected the two racial slots. Now a deferred v7 holds back every tracker, because the runtime reads only the new kinds:

- `ns:RebuildCastIndex` indexes only `userBuff`/`userCd`/`metaSkillCd`, so no user buff or cooldown starts.
- `ns:IsCooldownSlotEntry` does not recognise `"cooldown"`/`"item"`, so cooldown and item slots render as buff placeholders or bars.
- `ns:GetDisplayInfoForKey` rejects numeric keys and cannot parse `cd:`/`item:`/`racial:`, so icons show the 134400 question mark and tooltips are empty.

The Core.lua comment calls PLAYER_ENTERING_WORLD a "guaranteed-readable" moment, which limits how long this can last. If the race is still unreadable there, the session runs broken until a later PLAYER_ENTERING_WORLD. Any tracker added in that window is minted canonically next to its legacy twin, and the eventual v8 run hits the drop-rather-than-clobber branch (BuffEngine.lua:456-460), which deletes the older record and its placement. That branch is described as unreachable, and this is the path that reaches it.

**Fix:** Defer only when there is something to resolve:
```lua
function ns:MigrateRacialKeys()
	...
	if (ns.db.schemaVersion or 0) >= 7 then return end
	local tb = ns.db.trackedBuffs
	if tb.racial == nil and tb.racial2 == nil then
		ns.db.schemaVersion = 7   -- nothing race-dependent to migrate
		return
	end
	local defs, raceID = ns:RacialDefsRaw()
	if raceID == nil then return end
	...
```
Mirror the change in `migrateV7` in scripts/migrate-dryrun.js, and adjust selftest case C, whose fixture does contain legacy slots and so still defers.

### WR-03: The dry-run the phase tells the user to run cannot parse a real SavedVariables file

**File:** `scripts/migrate-dryrun.js:77` (also `:363-395`)

**Issue:** 53-05-SUMMARY's checklist says `node scripts/migrate-dryrun.js --race <raceID> "<path>"` "predicts the exact re-key the real logout/login will perform". I checked this against a WoW-shaped file:
- WoW writes array tables such as `userContainers` as bare `{ ... }, -- [1]` entries. `parse()` requires `[` before every entry, so it throws `expected [` for any user with at least one user container. The `-- [n]` comment trips the same check.
- Quoted strings stop at the first `"` and ignore `\"` escapes, so a label containing a quote corrupts the rest of the parse.
- `migrate()` implements v4-v8 only. For a pre-v4 file it skips v3, which deletes a hidden `lust` entry, so it predicts a `metaSkill:lust` the Lua will never create.

The parser predates this phase, but this phase extended the script, made it the NAME-02 spec, and pointed the user at it for their real file. Running it that way fails with `FAILED: expected [`.

**Fix:** In `table()`, accept an implicit-index value when the next character is not `[` (assign `nextIndex++`), skip `--` comments in `ws()`, and honour `\` escapes in string scanning. Port v1-v3 into `migrate()`. Add a fixture with a `userContainers` array entry to `--selftest` so this stays covered.

## Info

### IN-01: v8 stamps schema 8 even when it leaves entries unclassified, and those entries become permanently unreachable

**File:** `BuffEngine.lua:388-400, 439, 486`

**Issue:** A numeric key with a trackerType other than nil/`"buff"`/`"cooldown"`, or any unrecognised string key, is left in place and the schema is still stamped 8. Before this phase a numeric key still resolved through `UserSpellProvider`. Now `GetDisplayInfoForKey` returns nil for non-string keys and the cast index skips it, so the tracker becomes a dead question-mark tile with no diagnostic. No real v0.4.1 shape reaches this branch, so this is defensive only.

**Fix:** Print a one-line `TerribleBuffTracker: could not migrate tracker <key>` for each leftover key, or route every remaining numeric key to `userBuff`.

### IN-02: Tracked racial placeholders re-parse their key on every render tick

**File:** `Providers.lua:2210-2211` and `Providers.lua:2049-2050`

**Issue:** The tracked-entry dispatch is documented as "parse-free for anything already tracked". For `metaSkill:<id>` it still calls `MetaSkillRacialProvider:GetDisplayInfo(key)`, which runs `ns:RacialKeySpellID(key)`, a `string.match` with a `(%d+)` capture, on every placeholder draw. `entry.spellID` is already on the record. This is fewer parses than before the phase (one instead of two), so it is not a regression, but the claim in the comment and in the 53-05 hot-path audit is inaccurate.

**Fix:** Pass `entry.spellID` into the racial provider, for example via a `GetDisplayInfoForSpell(key, spellID)` variant, or memo the parse per key the way `racialGateKeyIDs` does.

### IN-03: Unreachable `or 134400` fallbacks

**File:** `CDMTab.lua:612-614`, `CDMTab.lua:1087-1089`

**Issue:** `ns:GetSpellIcon(nil)` already returns 134400, so the trailing `or 134400` can never run.

**Fix:** Remove the trailing `or 134400`.

### IN-04: Stale or contradicted comments and unread exports

**File:** `Core.lua:99-101`, `BuffEngine.lua:95-97`, `Core.lua:462, 491`, `Providers.lua:505, 604, 782, 2148`

**Issue:**
- `GetTrackerCategory`'s comment says "an entry written by any earlier version answers correctly with no schema bump". It no longer does: a pre-v8 `"cooldown"` entry answers `"buffs"` until v8 runs.
- BuffEngine.lua:95-97 still reasons about `nil == "cooldown"`.
- Core.lua says `ns:TrackerKey` is "the only place in the addon that concatenates a kind and an id". Providers.lua concatenates `META_SKILL_PREFIX`/`META_ITEM_PREFIX` directly at six sites.
- The renamed `ns.MetaItemTrinketProviderMixin`, `ns.MetaItemPotProviderMixin`, `ns.MetaSkillLustProviderMixin` and `ns.MetaItemBagProviderMixin` exports have no readers anywhere in the addon.

**Fix:** Update the comments. Optionally drop the unread exports.

### IN-05: `RemoveTrackedBuff` can throw after deleting the row

**File:** `BuffEngine.lua:804-817`

**Issue:** This function was rewritten in this phase and still concatenates `label` unguarded. For an entry without a label, the print throws after `ns.db.trackedBuffs[key] = nil`, so `UpdateDisplay`, `RebuildRankIndex` (which also rebuilds the cast index) and `MarkTrackersDirty` never run. The Fixture A shapes `trinket`, `pot` and `6673` carry no label. The bug predates the phase.

**Fix:** `local label = entry.label or tostring(key)`.

## Fix Outcomes

Applied 2026-09-28 by gsd-code-fixer (`--auto`, scope: all). All 8 findings were fixed, one atomic commit each. After the fixes, `node scripts/migrate-dryrun.js --selftest` passes 7 cases (F and G are new), `stylua --check` is clean on Core.lua, BuffEngine.lua, CDMTab.lua and Providers.lua, every touched file is `w/crlf`, and `scripts/install.bat` redeployed the addon.

| ID | Outcome | Commit |
|----|---------|--------|
| WR-01 | Fixed, needs human verification (logic change). Adding a cooldown reuses any existing cooldown key for that spellID. The cast index prefers `userCd` over `metaSkillCd`. | ce0717e |
| WR-02 | Fixed. v7 stamps immediately when neither legacy slot exists. The dry-run mirrors this, covered by selftest case F. | bf6e0e5 |
| WR-03 | Fixed. The parser handles real SavedVariables files, and v1-v3 are ported. Covered by selftest case G. | 54da1dd |
| IN-01 | Fixed. v8 now prints one chat line for each key it cannot classify. No data behaviour changes. | 8e8eb52 |
| IN-02 | Fixed. A tracked racial passes its own spellID, so the key is no longer parsed on every tick. | af474ae |
| IN-03 | Fixed. | 78f99d4 |
| IN-04 | Fixed. Comments corrected, and the four unread mixin exports removed. | 9692b45 |
| IN-05 | Fixed. | 69fa2cb |

---

_Reviewed: 2026-09-28T11:45:55Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
