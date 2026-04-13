# Phase 12: Schema Migration + Data Tables - Research

**Researched:** 2026-04-13
**Domain:** WoW addon — Lua data table construction, SavedVariables schema migration, SUGGESTED_BUFFS extension
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** TRINKET_SPELLS and POT_SPELLS are keyed by spellID for O(1) lookup in OnSpellCastSucceeded. Format: `TRINKET_SPELLS[spellID] = {duration=N, itemID=N}`
- **D-02:** Item ID lists for icon resolution (TRINKET_ITEM_IDS, POT_ITEM_IDS) are derived by iterating the spellID-keyed tables at init time, not maintained as separate static lists
- **D-03:** No reverse lookup table (itemID→spellID) — iterate the 13-entry spellID tables when scanning equipped/bags; trivial at this scale
- **D-04:** Name field from CSVs is commented in code, not stored in tables or DB
- **D-05:** No schema version bump — stay at v3. No new persistent data structures; trinket/pot data is runtime-only static tables. No stale keys to clean up since v0.2.3 is the first release with these features.
- **D-06:** Add two new entries to ns.SUGGESTED_BUFFS for "trinket" and "pot" meta-trackers, following the lust entry pattern (key, label, duration, metaBuff=true, getCDMSpellID/getCDMItemID)
- **D-07:** `duration = 0` as explicit sentinel — signals "duration varies per spell". Actual timer duration resolved at cast time from spell table, not from DB entry.
- **D-08:** getCDMSpellID/icon resolution for at-rest display — Claude's discretion on plumbing (getCDMItemID field, getCDMIcon, or alternative). Must show equipped trinket / bag pot icon at rest. Callers currently expect spellID for C_Spell.GetSpellInfo; adaptation needed for itemID-based icons.

### Claude's Discretion

- CDM icon resolution plumbing: how to integrate itemID-based icons into the getCDMSpellID pattern (new field, adapter function, or refactor) — just make the icon show the equipped trinket / bag pot at rest
- Data table location in BuffEngine.lua — module-level alongside SATED_DEBUFF_TO_LUST is the natural spot

### Deferred Ideas (OUT OF SCOPE)

- Data storage rework milestone: The trackedBuffs storage model has grown organically (string keys, meta-buff flags, sentinel durations, section-based management) with more exceptions than standard usage. A future milestone should do a general review and rework of how tracked buffs are stored — unify the model, reduce special cases, and establish a cleaner schema. Note for backlog.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DATA-01 | Trinket spell table defines 9 entries with spellID, itemID, and duration from trinket_info.csv | Verified all 9 entries in trinket_info.csv; table structure confirmed via SATED_DEBUFF_TO_LUST pattern |
| DATA-02 | Pot spell table defines 4 entries with spellID, itemID, and duration from pots_info.csv | Verified all 4 entries in pots_info.csv; same structure as trinket table |
| DATA-03 | Schema v4 migration handles any stale meta-tracker keys from prior sessions | SUPERSEDED by D-05 — see DATA-03 Discrepancy section below |
</phase_requirements>

---

## Summary

Phase 12 is a pure data layer phase: define two module-level Lua tables from CSV source data, derive item ID lookup sets, add two SUGGESTED_BUFFS entries, and decide on the at-rest icon plumbing for itemID-based icons. No schema migration is needed because v0.2.3 is the first release with trinket/pot tracking — there are no stale DB keys to clean up.

The work is almost entirely mechanical: transcribe 9 trinket rows and 4 pot rows from the CSVs into Lua table literals, following the exact pattern established by `ns.SATED_DEBUFF_TO_LUST`. The only design decision left open is D-08 — how the SUGGESTED_BUFFS entries expose their at-rest icon to CDMTab.lua's render loop, which currently calls `getCDMSpellID()` and passes that to `ns:GetSpellIcon()`. Since trinket/pot icons come from itemIDs, a new `getCDMIcon` field (returning a texture ID directly) is the cleanest addition without breaking existing callers.

The DATA-03 requirement ("Schema v4 migration") conflicts with D-05 ("no schema version bump"). D-05 is correct: no stale keys can exist because no prior TBT release created trinket/pot DB entries. REQUIREMENTS.md should be updated to mark DATA-03 as N/A for Phase 12.

**Primary recommendation:** Write TRINKET_SPELLS, POT_SPELLS, derive TRINKET_ITEM_IDS/POT_ITEM_IDS at module level, append trinket/pot entries to SUGGESTED_BUFFS with `getCDMIcon` returning nil (Phase 14 fills it in), and update the CDMTab Suggested render to fall through to `getCDMIcon` when `getCDMSpellID` returns nil. No schema migration code needed.

---

## DATA-03 Discrepancy: Requirement vs. Decision

**The conflict:** REQUIREMENTS.md DATA-03 says "Schema v4 migration handles any stale meta-tracker keys from prior sessions." CONTEXT.md D-05 says "No schema version bump — stay at v3."

**Why D-05 is correct:** v0.2.3 is the first TBT release that introduces trinket/pot tracking. No prior release created `"trinket"` or `"pot"` keys in `ns.db.trackedBuffs`. There are no stale keys to migrate. A schema bump would be a no-op migration that increments the version counter with zero data changes.

**Recommendation for REQUIREMENTS.md:** Mark DATA-03 as N/A or update text to "No schema migration needed — v0.2.3 is first release with trinket/pot tracking; no stale keys possible." The traceability table should move DATA-03 out of Phase 12 or remove it entirely.

**Impact on planning:** The planner should NOT generate a migration task or bump CURRENT_SCHEMA_VERSION. The existing `if ver < 3` ladder in `InitBuffEngine` stays as-is.

---

## Standard Stack

### Core (no new dependencies)

All work uses existing WoW Lua APIs and TBT patterns. No new libraries or packages.

| API | Purpose | Confidence |
|-----|---------|------------|
| `ns.SATED_DEBUFF_TO_LUST` pattern | Template for TRINKET_SPELLS / POT_SPELLS table structure | HIGH — in production |
| `ns.SUGGESTED_BUFFS` array | Registry for CDM tab Suggested section entries | HIGH — in production |
| `C_Item.GetItemIconByID(itemID)` | Icon texture from item ID (used by Phases 14-15, referenced here for plumbing design) | HIGH — verified warcraft.wiki.gg |
| `GetInventoryItemID("player", slot)` | Equipped trinket detection (used by Phases 14-15, informs D-08 design) | HIGH — verified warcraft.wiki.gg |

### No New Installation Needed

This phase makes no new external dependencies. All changes are Lua table definitions and minor SUGGESTED_BUFFS registration.

---

## Architecture Patterns

### Recommended Structure for New Tables

All new definitions go in `BuffEngine.lua` at module level, grouped after the existing `ns.SATED_DEBUFF_TO_LUST` / `SHARED_LUST_BUFFS` block and before `ns.InitBuffEngine`. Ordering:

```
BuffEngine.lua (module level)
├── ns.SATED_DEBUFF_TO_LUST        (existing)
├── SHARED_LUST_BUFFS              (existing)
├── GetHunterLustSpell()           (existing)
├── ns.CLASS_LUST_SPELL            (existing)
├── [NEW] local TRINKET_SPELLS     (Phase 12)
├── [NEW] local POT_SPELLS         (Phase 12)
├── [NEW] local TRINKET_ITEM_IDS   (Phase 12, derived from TRINKET_SPELLS)
├── [NEW] local POT_ITEM_IDS       (Phase 12, derived from POT_SPELLS)
└── ns.SUGGESTED_BUFFS             (existing + 2 new entries appended)
```

### Pattern 1: spellID-Keyed Static Data Table

Direct analog to `ns.SATED_DEBUFF_TO_LUST`. Module-level local, never persisted, never wiped.

```lua
-- BuffEngine.lua — after CLASS_LUST_SPELL block
local TRINKET_SPELLS = {
    -- Light Company Guidon
    [1259633] = { duration = 15, itemID = 249344 },
    -- Vaelgor's Final Stare
    [1260459] = { duration = 15, itemID = 249346 },
    -- Emberwing Feather
    [1250508] = { duration = 15, itemID = 250144 },
    -- Algeth'ar Puzzle Box
    [383781]  = { duration = 20, itemID = 193701 },
    -- Echo of L'ura
    [250768]  = { duration = 45, itemID = 151340 },
    -- Radiant Sunstone
    [1254624] = { duration = 20, itemID = 252411 },
    -- Freightrunner's Flask
    [1250533] = { duration = 15, itemID = 250215 },
    -- Seed of Radiant Hope
    [1263644] = { duration = 12, itemID = 250254 },
    -- Void Execution Mandate
    [1250557] = { duration = 20, itemID = 250225 },
}

local POT_SPELLS = {
    -- Light's Potential
    [1236616] = { duration = 30, itemID = 241308 },
    -- Potion of Recklessness
    [1236994] = { duration = 30, itemID = 241288 },
    -- Draught of Rampant Abandon
    [1236998] = { duration = 30, itemID = 241292 },
    -- Void-Shrouded Tincture
    [1236551] = { duration = 12, itemID = 241302 },
}
```

**Source:** `trinket_info.csv` and `pots_info.csv` (read directly — HIGH confidence).

### Pattern 2: Derived Item ID Lookup Set (D-02)

Build the item ID sets immediately after their parent spell table, before any function that might use them. This satisfies D-02 (derived at init, not static) while keeping them at module scope:

```lua
-- Derived at module load — no function call overhead at runtime
local TRINKET_ITEM_IDS = {}
for _, def in pairs(TRINKET_SPELLS) do
    TRINKET_ITEM_IDS[def.itemID] = true
end

local POT_ITEM_IDS = {}
for _, def in pairs(POT_SPELLS) do
    POT_ITEM_IDS[def.itemID] = true
end
```

**Why module-level (not inside InitBuffEngine):** These tables are used by functions called before or outside of InitBuffEngine (Phases 13-14). Module-level assignment runs at file load time, which is before ADDON_LOADED and before any function calls.

### Pattern 3: SUGGESTED_BUFFS Entry for itemID-Based Icons (D-08 resolution)

The existing CDMTab.lua Suggested render at line 721 does:
```lua
local cdmSpellID = suggested.getCDMSpellID and suggested.getCDMSpellID() or 2825
item.Icon:SetTexture(ns:GetSpellIcon(cdmSpellID))
```

For trinket/pot entries, `getCDMSpellID()` must return nil (no fixed spell). The render then falls through to a new `getCDMIcon` field that returns a texture ID directly.

**Recommended approach for D-08:** Add a `getCDMIcon` optional field to SUGGESTED_BUFFS entries. CDMTab.lua gets a one-line nil guard: if `cdmSpellID` is nil, check `suggested.getCDMIcon`. Phase 12 registers the entries with `getCDMIcon = nil` (placeholder); Phase 14 fills in the actual icon resolution functions. This keeps Phase 12 self-contained.

```lua
-- BuffEngine.lua — append to ns.SUGGESTED_BUFFS after the lust entry
ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = {
    key          = "trinket",
    label        = "Trinket",
    duration     = 0,         -- D-07: sentinel; actual duration from TRINKET_SPELLS at cast time
    metaBuff     = true,
    getCDMSpellID = function() return nil end,  -- no fixed spell; icon from equipped gear
    getCDMIcon   = nil,       -- Phase 14 fills in: function() return ns:ResolveTrinketIcon() end
}

ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = {
    key          = "pot",
    label        = "Damage Pot",
    duration     = 0,         -- D-07: sentinel
    metaBuff     = true,
    getCDMSpellID = function() return nil end,  -- no fixed spell; icon from bag scan
    getCDMIcon   = nil,       -- Phase 14 fills in: function() return ns:ResolvePotIcon() end
}
```

**CDMTab.lua nil guard (minor change, also Phase 12 scope):**
```lua
-- CDMTab.lua ~line 721 — in Suggested section render
local cdmSpellID = suggested.getCDMSpellID and suggested.getCDMSpellID()
local icon
if cdmSpellID then
    icon = ns:GetSpellIcon(cdmSpellID)
elseif suggested.getCDMIcon then
    icon = suggested.getCDMIcon()
else
    icon = 134400  -- question mark fallback
end
item.Icon:SetTexture(icon or 134400)
```

This nil guard is Phase 12 scope because it is required to prevent a nil-icon error the moment the trinket/pot entries appear in the Suggested section. Without it, `ns:GetSpellIcon(nil)` returns 134400 anyway (see `GetSpellIcon` guard at BuffEngine.lua:113) — so technically safe, but the explicit guard is cleaner and ready for Phase 14.

### Anti-Patterns to Avoid

- **Storing names in the table:** D-04 is explicit — names are comments only. Do not add a `label` field to TRINKET_SPELLS/POT_SPELLS. Labels for CDM display come from `ns.SUGGESTED_BUFFS` entries or from `C_Spell.GetSpellInfo` at cast time.
- **Separate static item ID lists:** D-02 prohibits maintaining `TRINKET_ITEM_IDS` as a hand-written table. It must be derived from TRINKET_SPELLS to keep the two sources in sync.
- **Schema migration code:** D-05 prohibits a version bump. Do not add `if ver < 4` block or increment `CURRENT_SCHEMA_VERSION`.
- **Storing `getCDMIcon` result in SavedVariables:** Functions are not serializable. Resolved icons should never be persisted.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Spell name lookup | Store names in TRINKET_SPELLS table | Comment names in code; resolve labels from C_Spell.GetSpellInfo at runtime | Localization, D-04 compliance |
| Item ID set | Maintain parallel static list | Derive with `for _, def in pairs(TRINKET_SPELLS)` | D-02; stays in sync automatically |
| Icon fallback | Custom nil-check logic per call site | `ns:GetSpellIcon()` already returns 134400 for nil | Already handles nil/string keys (BuffEngine.lua:113) |

---

## Common Pitfalls

### Pitfall 1: nil icon in CDMTab Suggested render

**What goes wrong:** `getCDMSpellID()` returns nil for trinket/pot. Existing render code passes nil to `ns:GetSpellIcon(nil)`, which returns 134400 (question mark). The entry shows a question mark icon instead of a trinket/pot icon.

**Why it happens:** The Suggested section render (CDMTab.lua:721) assumes every SUGGESTED_BUFFS entry has a resolvable spellID. Trinket/pot entries intentionally return nil.

**How to avoid:** Add the `getCDMIcon` nil guard in CDMTab.lua as part of Phase 12. Phase 12 leaves `getCDMIcon = nil` (so question mark is shown until Phase 14), but the guard code is in place so Phase 14 only needs to fill in the function — no CDMTab changes needed in that phase.

**Warning signs:** Trinket/pot entries show question mark icon in CDM Suggested section even after Phase 14 is complete. Means `getCDMIcon` was not wired up.

### Pitfall 2: Module-load ordering for derived tables

**What goes wrong:** POT_ITEM_IDS or TRINKET_ITEM_IDS is referenced before it is populated. In Lua, module-level code executes in order, so a function defined before the derivation loop can capture an empty table if called at load time.

**How to avoid:** Place the derivation loops immediately after the parent spell table definitions, before any function that references the derived sets. No function in Phase 12 calls these during module load — they are only used by Phase 13+ functions — so ordering is safe as long as the derivation follows the table definition.

### Pitfall 3: duration = 0 misread as "no duration"

**What goes wrong:** Phase 13 timer start code reads `def.duration` from TRINKET_SPELLS/POT_SPELLS and checks `if def.duration then` — succeeds. But if it checks `if def.duration > 0 then` as a sanity guard, it skips the timer start.

**How to avoid:** Phase 13 must know that duration comes from the spell table entry, not from the SUGGESTED_BUFFS entry. The SUGGESTED_BUFFS `duration = 0` is the sentinel (D-07) visible in the DB and used for CDM preview; the actual timer duration is `TRINKET_SPELLS[spellID].duration`. Phase 12 should note this explicitly in code comments.

### Pitfall 4: Appending to ns.SUGGESTED_BUFFS before it exists

**What goes wrong:** SUGGESTED_BUFFS entries are added using `ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = ...` but if another file loads before BuffEngine.lua and reads `ns.SUGGESTED_BUFFS`, it may get a table without the trinket/pot entries.

**How to avoid:** All SUGGESTED_BUFFS mutations stay in BuffEngine.lua. The lust entry and new trinket/pot entries all live in the same file. CDMTab.lua only reads the table (never writes). Ordering is safe as long as BuffEngine.lua is loaded before CDMTab.lua, which is guaranteed by the .toc file load order (unchanged).

---

## Full Data Tables (from CSV sources)

### trinket_info.csv — 9 entries verified

| Name | itemID | spellID | duration |
|------|--------|---------|----------|
| Light Company Guidon | 249344 | 1259633 | 15 |
| Vaelgor's Final Stare | 249346 | 1260459 | 15 |
| Emberwing Feather | 250144 | 1250508 | 15 |
| Algeth'ar Puzzle Box | 193701 | 383781 | 20 |
| Echo of L'ura | 151340 | 250768 | 45 |
| Radiant Sunstone | 252411 | 1254624 | 20 |
| Freightrunner's Flask | 250215 | 1250533 | 15 |
| Seed of Radiant Hope | 250254 | 1263644 | 12 |
| Void Execution Mandate | 250225 | 1250557 | 20 |

### pots_info.csv — 4 entries verified

| Name | itemID | spellID | duration |
|------|--------|---------|----------|
| Light's Potential | 241308 | 1236616 | 30 |
| Potion of Recklessness | 241288 | 1236994 | 30 |
| Draught of Rampant Abandon | 241292 | 1236998 | 30 |
| Void-Shrouded Tincture | 241302 | 1236551 | 12 |

**Verification note:** Spell IDs in both CSVs appear to be on-use ability IDs (not proc buff IDs or item IDs). The pending todo from STATE.md — "Verify in-game spell IDs before Phase 13 implementation" — is the right gate. Phase 12 encodes the CSV values as-is; Phase 13 should include an in-game verification step before wiring cast detection.

---

## Validation Architecture

### Test Framework

Phase 12 produces Lua definitions only. There is no automated test framework for WoW addon Lua. Validation is manual in-game.

| Property | Value |
|----------|-------|
| Framework | Manual in-game — `/tbt` toggle, CDM settings open |
| Quick run | Open CDM settings: trinket + pot icons appear in Suggested section |
| Full suite | See Phase Validation below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Command | Notes |
|--------|----------|-----------|---------|-------|
| DATA-01 | TRINKET_SPELLS has 9 entries | manual | Verify table literal in code (count rows) | Code review |
| DATA-02 | POT_SPELLS has 4 entries | manual | Verify table literal in code (count rows) | Code review |
| DATA-03 | N/A — no migration needed | — | — | See discrepancy section |
| D-06 | Trinket + pot appear in CDM Suggested | manual | Open CDM settings, check Suggested section | In-game |
| D-07 | `duration = 0` in SUGGESTED_BUFFS entries | manual | Inspect DB after drag-to-section: `duration` field is 0 | In-game |
| D-08 | Suggested icons don't error | manual | No Lua error on CDM open | In-game |

### Wave 0 Gaps

None — no automated tests exist for this addon and none are expected. The validation protocol is manual in-game verification throughout.

---

## Project Constraints (from CLAUDE.md)

- `COMBAT_LOG_EVENT_UNFILTERED` is disabled — do not use it (not relevant to Phase 12, but affects Phases 13+)
- Secret values: guard API calls behind fail-safe calls when possible (C_Item.GetItemIconByID can return nil — guard always)
- Spell IDs from `UNIT_SPELLCAST_SUCCEEDED` are always safe (not secret values) — the CSV spellIDs are on-use ability IDs, safe to use
- Run `stylua` on all Lua files after editing
- Run `scripts/install.bat` to deploy after each change
- No SUGGESTED_BUFFS entries should store icon data in SavedVariables
- Active timers are runtime-only (not persisted) — this phase adds no persisted structures, consistent with CLAUDE.md

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| Hardcoded lust spell IDs inline | spellID-keyed table (SATED_DEBUFF_TO_LUST) | Template for TRINKET_SPELLS/POT_SPELLS |
| schema v3 migration cleans auto-seeded lust entry | No auto-seeding of meta-buff entries; user drags from Suggested | No migration needed for trinket/pot in v0.2.3 |

---

## Open Questions

1. **Spell ID accuracy (spellID vs. proc buff ID)**
   - What we know: CSV spellIDs look like on-use ability IDs (high values like 1259633 match Midnight-era spells). STATE.md explicitly notes this needs in-game verification before Phase 13.
   - What's unclear: Whether any CSV spellID is actually a proc buff ID or item ID rather than the cast ability ID.
   - Recommendation: Phase 12 encodes CSV values as-is. Phase 13 PLAN must include an in-game verification step (cast each trinket, confirm UNIT_SPELLCAST_SUCCEEDED fires with the expected spellID). Data corrections go back to TRINKET_SPELLS at that point — no Phase 12 rework needed since the table structure is correct.

2. **getCDMIcon phase split**
   - What we know: Phase 12 adds `getCDMIcon = nil` placeholder. Phase 14 fills it in.
   - What's unclear: Whether CDMTab.lua's nil guard should also be Phase 12 scope or deferred to Phase 14.
   - Recommendation: Include the CDMTab nil guard in Phase 12. It is a two-line change that prevents a question-mark regression if someone opens CDM settings between Phase 12 and Phase 14 completion. It is also the kind of small defensive guard that belongs with the data definition, not with the icon resolution logic.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 12 is purely Lua data table additions. No external tools, CLIs, runtimes, or services beyond the standard WoW addon development workflow (already verified operational in prior phases).

---

## Sources

### Primary (HIGH confidence)
- `trinket_info.csv` and `pots_info.csv` — read directly; all 13 entries transcribed and verified
- `BuffEngine.lua` lines 1-140 — existing patterns read directly (SATED_DEBUFF_TO_LUST, SUGGESTED_BUFFS, InitBuffEngine, GetSpellIcon, ResolveSuggestedSpellID)
- `CDMTab.lua` lines 125-155, 710-728 — Suggested section render and copy-on-drag read directly
- `.planning/phases/12-schema-migration-data-tables/12-CONTEXT.md` — locked decisions D-01 through D-08

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` — milestone-level architecture for TRINKET_SPELLS/POT_SPELLS patterns; verified against codebase
- `.planning/research/SUMMARY.md` — feature table stakes and pitfall catalog for this milestone
- `.planning/research/PITFALLS.md` — meta-tracker pitfalls 1-2 (source marker, overwrite behavior)

### Tertiary
- None for this phase — all critical decisions have HIGH confidence sources.

---

## Metadata

**Confidence breakdown:**
- Data tables (DATA-01, DATA-02): HIGH — CSVs read directly, 13 entries transcribed verbatim
- SUGGESTED_BUFFS entries: HIGH — existing lust entry pattern read directly, new entries mirror it exactly
- Schema migration decision (DATA-03): HIGH — D-05 confirmed correct; v0.2.3 is first release with these features
- getCDMIcon plumbing (D-08): MEDIUM — design recommendation, not yet validated in-game; straightforward nil guard

**Research date:** 2026-04-13
**Valid until:** Stable — data tables don't change unless CSV sources are updated. getCDMIcon design valid until Phase 14 implementation reveals any integration issues.
