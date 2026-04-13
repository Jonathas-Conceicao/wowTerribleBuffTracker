# Phase 12: Schema Migration + Data Tables - Context

**Gathered:** 2026-04-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Create spell/item data tables for 9 trinkets and 4 pots, and add SUGGESTED_BUFFS entries for both meta-trackers. No schema version bump needed (no new persistent structures). This phase delivers the data layer that Phases 13-15 consume.

</domain>

<decisions>
## Implementation Decisions

### Data table structure
- **D-01:** TRINKET_SPELLS and POT_SPELLS are keyed by spellID for O(1) lookup in OnSpellCastSucceeded. Format: `TRINKET_SPELLS[spellID] = {duration=N, itemID=N}`
- **D-02:** Item ID lists for icon resolution (TRINKET_ITEM_IDS, POT_ITEM_IDS) are derived by iterating the spellID-keyed tables at init time, not maintained as separate static lists
- **D-03:** No reverse lookup table (itemID→spellID) — iterate the 13-entry spellID tables when scanning equipped/bags; trivial at this scale
- **D-04:** Name field from CSVs is commented in code, not stored in tables or DB

### Schema migration
- **D-05:** No schema version bump — stay at v3. No new persistent data structures; trinket/pot data is runtime-only static tables. No stale keys to clean up since v0.2.3 is the first release with these features.

### SUGGESTED_BUFFS entries
- **D-06:** Add two new entries to ns.SUGGESTED_BUFFS for "trinket" and "pot" meta-trackers, following the lust entry pattern (key, label, duration, metaBuff=true, getCDMSpellID/getCDMItemID)
- **D-07:** `duration = 0` as explicit sentinel — signals "duration varies per spell". Actual timer duration resolved at cast time from spell table, not from DB entry.
- **D-08:** getCDMSpellID/icon resolution for at-rest display — Claude's discretion on plumbing (getCDMItemID field, getCDMIcon, or alternative). Must show equipped trinket / bag pot icon at rest. Callers currently expect spellID for C_Spell.GetSpellInfo; adaptation needed for itemID-based icons.

### Claude's Discretion
- CDM icon resolution plumbing: how to integrate itemID-based icons into the getCDMSpellID pattern (new field, adapter function, or refactor) — just make the icon show the equipped trinket / bag pot at rest
- Data table location in BuffEngine.lua — module-level alongside SATED_DEBUFF_TO_LUST is the natural spot

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data sources
- `trinket_info.csv` — 9 trinket entries: name, itemID, spellID, duration (semicolon-delimited)
- `pots_info.csv` — 4 pot entries: name, itemID, spellID, duration (semicolon-delimited)

### Existing patterns
- `BuffEngine.lua` lines 12-64 — SATED_DEBUFF_TO_LUST, SHARED_LUST_BUFFS, CLASS_LUST_SPELL, and SUGGESTED_BUFFS definitions (the template for new data tables)
- `BuffEngine.lua` lines 66-110 — Schema migration ladder (InitBuffEngine) — no new migration needed but understand the pattern
- `BuffEngine.lua` lines 123-135 — ResolveSuggestedSpellID — may need adaptation for itemID-based entries
- `CDMTab.lua` lines 125-155 — Copy-on-drag from Suggested to Bars/Buffs (reads suggested.duration, suggested.key, suggested.label)

### WoW API
- `C_Item.GetItemIconByID(itemID)` — icon resolution from item ID (may return nil for uncached)
- `GetInventoryItemID("player", slotIndex)` — equipped trinket detection (slots 13/14)
- `C_Item.GetItemCount(itemID)` — bag presence check for pots

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns.SATED_DEBUFF_TO_LUST` pattern: spellID-keyed static table — direct template for TRINKET_SPELLS/POT_SPELLS
- `ns.SUGGESTED_BUFFS` registry: array of meta-buff definitions with getCDMSpellID() — extend with trinket/pot entries
- `ns:GetSpellIcon(spellID)`: handles nil/string keys with 134400 fallback — may need itemID variant
- `ns:ResolveSuggestedSpellID(key)`: resolves string keys to numeric CDM spellID — may need adaptation

### Established Patterns
- Module-level static tables (not persisted, not inside functions)
- SUGGESTED_BUFFS entries have: key (string), label, duration, metaBuff (bool), getCDMSpellID (function)
- Copy-on-drag creates DB entry from SUGGESTED_BUFFS fields (line 143-149 CDMTab.lua)

### Integration Points
- `OnSpellCastSucceeded` (BuffEngine.lua:137) — Phase 13 will add pre-DB lookup against TRINKET_SPELLS/POT_SPELLS
- CDMTab Suggested section (CDMTab.lua:716-725) — populates from ns.SUGGESTED_BUFFS
- ResolveSuggestedSpellID (BuffEngine.lua:125) — resolves string key → spellID for display

</code_context>

<specifics>
## Specific Ideas

- Names from CSV should be commented in code for reference but not stored in tables or DB
- The data tables are the foundation — Phases 13-15 build on these without modifying the table structure

</specifics>

<deferred>
## Deferred Ideas

- **Data storage rework milestone**: The trackedBuffs storage model has grown organically (string keys, meta-buff flags, sentinel durations, section-based management) with more exceptions than standard usage. A future milestone should do a general review and rework of how tracked buffs are stored — unify the model, reduce special cases, and establish a cleaner schema. Note for backlog.

</deferred>

---

*Phase: 12-schema-migration-data-tables*
*Context gathered: 2026-04-12*
