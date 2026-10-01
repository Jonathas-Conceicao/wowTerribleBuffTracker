---
phase: 53-naming-scheme-saved-data-migration
verified: 2026-09-28T00:00:00Z
status: human_needed
score: 5/5 roadmap truths statically verified (runtime proof pending in-game)
overrides_applied: 0
human_verification:
  - test: "Back up WTF/Account/<account>/SavedVariables/TerribleBuffTracker.lua from v0.4.1 (schemaVersion = 7) that has at least one user buff, one user cooldown, Lust, trinket, pot, a racial buff, a racial cooldown and a bag item. Deploy this build and do a REAL logout -> login (full client restart if the TOC changed; never /reload)"
    expected: "Every tracker appears in the same container, in the same order, with the same duration, label, coverAllRanks and icon override as before. No Lua error on login (MigrateKindKeys runs at ADDON_LOADED and calls ns:UpdateDisplay before InitDisplay; the v7 precedent says this is safe, but only the client can prove it)"
    why_human: "The migration only runs inside the WoW client against a real SavedVariables file"
  - test: "Log out a second time and open TerribleBuffTracker.lua in a text editor. Log in again, log out again, and diff the two copies"
    expected: "Every trackedBuffs key has the form userBuff:<id> / userCd:<id> / metaSkill:lust / metaSkill:<id> / metaSkillCd:<id> / metaItem:trinket / metaItem:pot / metaItem:<itemID>. Every trackerType is one of those kinds, every entry.key matches its table key, schemaVersion = 8. No cd:, item:, racial:, bare numeric, lust, trinket or pot keys remain. The two copies are identical (the second login is a no-op, nothing is duplicated)"
    why_human: "Proves the saved file on disk, which only the client writes"
  - test: "Cast a spell tracked as a user buff, a spell tracked as a user cooldown, trigger Lust, use a tracked trinket, drink a tracked pot, use a racial buff and a racial cooldown, and use a tracked bag item"
    expected: "The buff timer starts; the cooldown tile greys and sweeps; Lust, trinket, pot, racial buff, racial cooldown and bag item trackers all fire (the bag item count drops by one). No Lua errors"
    why_human: "The cast path now goes through ns.buffKeyBySpell / ns.cooldownKeyBySpell. The rebuild sites are wired, but only a real UNIT_SPELLCAST_SUCCEEDED proves it end to end"
  - test: "Tooltip and icon check for every kind (user's explicit condition). Look at each of the 8 trackers above in its container (active and inactive/placeholder, with hideWhenInactive off), on its tracked tile in the TBT tab, on the matching Suggested tile (Lust, trinket, pot, racial buff, racial cooldown, bag item), and on the drag ghost while you drag a Suggested tile. Hover each one"
    expected: "Each shows its real icon (never a 134400 question mark unless it already did so in v0.4.1) and a correct tooltip: a spell tooltip with the spell ID for spells, an item tooltip with the In bags count for bag items, and the description line for Lust/trinket/pot"
    why_human: "Rendering and GameTooltip content can only be seen in the client"
  - test: "Drag a racial cooldown Suggested tile into a cooldown container, then cast that racial right away without /reload"
    expected: "The new tile starts its cooldown on that very cast (AddSuggestedTracker rebuilds the cast index)"
    why_human: "Runtime cast behaviour"
  - test: "Add a new user buff and a new user cooldown through the Add dialog, then do a real logout/login and inspect the SavedVariables file"
    expected: "They are saved as userBuff:<id> / userCd:<id> with trackerType userBuff / userCd, and both still render and fire after the login"
    why_human: "Saved file and persistence across a real login"
  - test: "With Merge Mode on, open the containers holding mirrored CDM entries"
    expected: "Mirrored buff bars and cooldown icons render exactly as in v0.4.1 (they carry userBuff / userCd kinds now)"
    why_human: "Visual parity with the CDM"
---

# Phase 53: Naming Scheme & Saved-Data Migration Verification Report

**Phase Goal:** Every tracker kind (user buff, user cooldown, meta skill for Lust and racials, meta item for trinket, pot and bag consumables, with user item reserved) is named by one scheme in code and in saved data, and a player upgrading from v0.4.1 loses nothing.
**Verified:** 2026-09-28
**Status:** human_needed
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A v0.4.1 DB shows every tracker in the same container, order and settings after a real logout/login | STATIC VERIFIED, runtime needs a human | `ns:MigrateKindKeys` (BuffEngine.lua:356-497) collects keys first, then moves the same entry table to its new key (`trackedBuffs[newKey] = entry`). It never rebuilds a record, so section, layoutOrder, coverAllRanks, iconOverride, duration and label all survive. The selftest's "v0.4.1 -> v8" case asserts object identity and unchanged fields. |
| 2 | A second login leaves only canonical trackerType values and keys plus schemaVersion 8; no re-run, no duplicates | STATIC VERIFIED, runtime needs a human | v8 gates on `ver >= CURRENT_SCHEMA_VERSION (8)` and v7 is pinned to the literal `>= 7` (BuffEngine.lua:268, 361). The InitBuffEngine chain uses literal stamps for v1-v6. Selftest "second login is a no-op" passes. |
| 3 | Every kind still behaves as in v0.4.1 (casts start buff timers and cooldown tiles; Lust, trinket, pot, racial and bag item fire) | STATIC VERIFIED, runtime needs a human | Cast path (Providers.lua:121-195) does one index lookup per namespace. The index is rebuilt at InitBuffEngine, MigrateKindKeys, RebuildRankIndex (PEW, SPELLS_CHANGED, add, remove) and AddSuggestedTracker. Meta providers read `trackedBuffs[META_KEY.*]` / `META_SKILL_PREFIX..spellID` / `META_ITEM_PREFIX..itemID`, which are the exact keys the migration writes. |
| 4 | A user buff and a user cooldown added after migration are saved under canonical names | STATIC VERIFIED, runtime needs a human | `ns:AddTrackedBuff` mints `ns:TrackerKey(kind, spellID)` with `trackerType = kind` (BuffEngine.lua:739-755). Its only caller (CDMTab.lua:1320-1324) passes `ns.KIND.USER_CD` / `USER_BUFF`. |
| 5 | One canonical kind list drives identifiers, provider names and constants; old identifiers survive only in the migration step | VERIFIED | `ns.KIND` (Core.lua:466-473) generates `KEY_PREFIX`, `KEY_ID_PATTERNS` and `KNOWN_KINDS` in a loop. A grep for `"cd:` / `"item:` / `"racial:` / `^cd:` / `"lust"` / `"trinket"` / `"pot"` / `== "cooldown"` / `== "item"` / `*_KEY_PREFIX` across *.lua finds them only in BuffEngine.lua's v3/v6/v7/v8 blocks, in comments, in the chat word "buff"/"cooldown" (BuffEngine.lua:766), and in MergeMode's unrelated `relay == "item"` debug state. Providers are renamed MetaItemTrinket/MetaItemPot/MetaSkillLust/MetaSkillRacial/MetaItemBag/UserSpell. The JS KIND strings are identical to Lua's. |

**Score:** 5/5 statically verified. Truths 1-4 need in-game proof by design (NAME-02 requires a real logout/login).

### Plan must-haves (merged, beyond the ROADMAP truths)

| Plan | Must-have | Status |
|------|-----------|--------|
| 53-01 | Selftest covers every kind, move-not-rebuild, pre-v7 ordering, unreadable-race deferral, no-op second pass, non-vacuous comparator; RACIAL_SPELLS parsed live | VERIFIED: `node scripts/migrate-dryrun.js --selftest` passes 5/5 cases, exit 0. `extractRacialSpells` brace-scans Providers.lua |
| 53-02 | v8 runs after v7 on both triggers | VERIFIED: BuffEngine.lua:222-225 (ADDON_LOADED) and Core.lua:1121-1125 (PEW), both before PreallocateProc and RebuildRankIndex. v8 also refuses to run while `ver < 7` |
| 53-02 | Cast index, no per-cast concat | VERIFIED: the `ns.COOLDOWN_KEY_PREFIX .. spellID` concat has been removed from OnTrigger |
| 53-03 | User-buff proc carries the numeric entry.spellID | VERIFIED: Providers.lua:185; AcquireAliveBuffs uses entry.spellID too |
| 53-03 | GetDisplayInfoForKey resolves every kind, tracked and untracked | VERIFIED: see the backward trace below |
| 53-04 | Cooldown-slot and bag-item predicates replace string tests; trinket and pot stay buff-rendered | VERIFIED: IsBagItemEntry needs a numeric itemID, and only CDMTab (from ItemKeyItemID, nil for trinket/pot) and the v8 backfill (numeric id only) ever write entry.itemID |
| 53-04 | Suggested minting is canonical and rebuilds the cast index | VERIFIED: CDMTab.lua:187 `trackerType = ns:KeyKind(key)`, :224 `ns:RebuildCastIndex()` |
| 53-05 | stylua clean, CRLF, text diff | VERIFIED: `stylua --check` is clean on all 6 files; `git ls-files --eol` shows `i/lf w/crlf` for all |

### Backward trace: icon, label and tooltip (the user's explicit condition)

Each resolution path was traced back to what feeds it, checking that its input table is actually filled:

| Consumer | Reads | Filled by | Status |
|----------|-------|-----------|--------|
| ApplyCooldownSlot icon (userCd, metaSkillCd, bag item) | `entry.spellID`, `entry.iconOverride` | userCd from v0.4.1 v6 (already had spellID), plus the v8 backfill `entry.spellID = id` when nil. Bag-item iconOverride was written by v0.4.1 CDMTab and is preserved by the move | FLOWING |
| User buff proc / tooltip | `entry.spellID` | v0.4.1 numeric-key user buffs may lack `spellID`. v8 backfills it (BuffEngine.lua:465-476) before any cast is possible | FLOWING |
| `ns.buffKeyBySpell` / `ns.cooldownKeyBySpell` (cast path) | `entry.trackerType` and `entry.spellID` | v8 stamps trackerType on every recognised entry and calls RebuildCastIndex. InitBuffEngine calls it again at the end, and so do PEW, add, remove and Suggested | FLOWING |
| GetDisplayInfoForKey, tracked metaSkill (racial) | `ns:RacialKeySpellID(key)` on `metaSkill:<N>` | The key the migration writes | FLOWING |
| GetDisplayInfoForKey, tracked bag item | `IsBagItemEntry(entry)` then `entry.itemID` | v0.4.1 item entries carried itemID, plus the v8 backfill | FLOWING |
| GetDisplayInfoForKey, Lust/trinket/pot | `keyToProvider[META_KEY.*]` | Same constants the migration and Suggested use | FLOWING |
| CDMTab tile/ghost fallback and OnEnter fallback | `ns:SpellKeySpellID(key)` | Parses all four spell-shaped kinds; `GetSpellIcon(nil)` returns 134400 rather than erroring | FLOWING |
| CDMTab item tooltip | `ns:ItemKeyItemID(self.spellID)` | `metaItem:<N>` keys; returns nil for trinket/pot, which fall through to their providers | FLOWING |
| META_DESCRIPTIONS | keyed by `ns.META_KEY.*` | Same keys as Suggested tiles | FLOWING |
| Racial race gate `IsRacialKeyVisible` | `RacialKeySpellID` or `CooldownKeySpellID` | Parses metaSkill, userCd and metaSkillCd | FLOWING |
| `ns:CooldownKindFor` at ADDON_LOADED | `ns:IsRacialSpellID` then `racialSpellOwners` | Built at Providers.lua file load (TOC loads it before ADDON_LOADED fires) | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Migration mirror selftest | `node scripts/migrate-dryrun.js --selftest` | 5 cases PASS, exit 0 | PASS |
| Formatting | `stylua --check` on 6 Lua files | clean | PASS |
| Line endings | `git ls-files --eol` | all `w/crlf` | PASS |

### Probe Execution

No probes are declared and there are no `scripts/*/tests/probe-*.sh`. The phase's runnable check is the selftest above.

### Requirements Coverage

| Requirement | Source Plans | Status | Evidence |
|-------------|--------------|--------|----------|
| NAME-01 | 53-02, 53-03, 53-04, 53-05 | SATISFIED (static) | Truth 5 |
| NAME-02 | 53-01, 53-02, 53-04, 53-05 | NEEDS HUMAN | Static truths 1-4 hold. The requirement text itself demands "verified by a real logout/login" |

No orphaned requirements. REQUIREMENTS.md maps only NAME-01 and NAME-02 to Phase 53.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (phase diff) | none | TBD/FIXME/XXX/TODO/HACK | none | None found in added lines |
| BuffEngine.lua | 488-495 | `ns:UpdateDisplay()` is reachable at ADDON_LOADED, before InitDisplay, whenever v8 moves a record (every v0.4.1 upgrade) | Info | Base-container runtime is allocated at Display.lua file load and user containers during RehydrateUserContainers, and UpdateDisplay hides containers with no frame or settings. v7 used the identical pattern and shipped in v0.4.1. The first human check covers this with "no Lua error on login" |

### Human Verification Required

See the `human_verification` frontmatter: seven in-game checks covering the real logout/login migration, the saved file after a second login, casts for every kind, icon and tooltip for every kind on every surface, the racial cooldown firing on the next cast after a Suggested drop, persistence of newly added trackers, and Merge Mode parity.

### Gaps Summary

No code defects found. The code has one kind table that mints and parses every key. The v7-then-v8 chain is gated correctly on both triggers. The migration moves records rather than rebuilding them and backfills the spellID and itemID the new resolution paths depend on. Every icon, label and tooltip consumer traces back to a field the migration or the minting sites actually fill. What remains is the in-game proof NAME-02 requires by definition.

---

_Verified: 2026-09-28_
_Verifier: Claude (gsd-verifier)_
