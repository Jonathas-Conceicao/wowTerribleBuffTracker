# Phase 13: Timer Functions + Cast Detection - Context

**Gathered:** 2026-04-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire cast detection so that casting a tracked trinket or pot spell creates a keyed timer in the correct meta-slot when the user has added that slot to Bars/Buffs. Timers are keyed by actual spellID (not meta-key string) so existing aura-scan cancellation works naturally. Suggested section entries are already in place from Phase 12.

</domain>

<decisions>
## Implementation Decisions

### Cast routing
- **D-01:** Meta-timer is created ONLY if the user has added the meta-slot to trackedBuffs (i.e., `ns.db.trackedBuffs["trinket"]` or `["pot"]` exists via copy-on-drag from Suggested). No user DB entry → no timer. Matches lust pattern.
- **D-02:** Fan-out check happens in `OnSpellCastSucceeded` BEFORE the existing `ns.db.trackedBuffs[spellID]` lookup. Order: TRINKET_SPELLS lookup → POT_SPELLS lookup → fallback to existing trackedBuffs[spellID] path. First match wins (trinket/pot spellIDs never collide with regular tracked buffs).
- **D-03:** If meta-slot DB entry has `section == "hidden"`, skip timer creation (same as existing behavior for non-meta buffs).

### Shared-slot overwrite
- **D-04:** Each timer carries a `metaSlot` field ("trinket" or "pot", or nil for regular buffs). On new cast, iterate `activeTimers` and delete any entry where `timer.metaSlot == new_cast.metaSlot` before inserting the new one. Enforces TMR-03 (newest cast wins, only one active per meta-slot).
- **D-05:** Display code must ignore `metaSlot` field when not set (nil = regular buff, existing behavior preserved).

### DB entry ↔ timer linking (display resolution)
- **D-06:** Timer carries DB ref at creation time — copy `section`, `layoutOrder`, and DB `label` from `ns.db.trackedBuffs[metaSlot]` onto the timer. Display reads these fields directly from the timer, no per-render DB lookup.
- **D-07:** Consequence: if user moves the meta-slot (e.g., Bars → Buffs) while a timer is running, the active timer keeps its original position until it expires. Acceptable — users don't reorganize mid-combat.

### Timer label / tooltip
- **D-08:** Timer `label` (bar text) = spell name from `C_Spell.GetSpellInfo(spellID).name` — the actual proc name ("Blood-Soaked Trophy" etc.). Falls back to `entry.label` ("Trinket"/"Pot") if spell info unavailable.
- **D-09:** Timer tooltip on hover = spellID's native tooltip (matches active icon behavior per ICON-03 from Phase 15). No special handling needed — default tooltip resolution from spell icon covers it.

### Claude's Discretion
- Exact code placement inside `OnSpellCastSucceeded` (helper function vs inline lookup)
- Field ordering on the timer object
- Naming of the meta-fan-out helper (if extracted)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 12 artifacts
- `.planning/phases/12-schema-migration-data-tables/12-CONTEXT.md` — Phase 12 decisions (data tables, SUGGESTED_BUFFS entries)
- `.planning/phases/12-schema-migration-data-tables/12-01-SUMMARY.md` — TRINKET_SPELLS, POT_SPELLS, item ID sets shipped
- `.planning/phases/12-schema-migration-data-tables/12-02-SUMMARY.md` — SUGGESTED_BUFFS trinket/pot entries shipped, CDMTab nil-fallback in place

### Existing code
- `BuffEngine.lua` lines 227-251 — `OnSpellCastSucceeded` (the function to extend)
- `BuffEngine.lua` lines 85-146 — TRINKET_SPELLS, POT_SPELLS, TRINKET_ITEM_IDS, POT_ITEM_IDS, SUGGESTED_BUFFS
- `BuffEngine.lua` lines 202-225 — GetSpellIcon, ResolveSuggestedSpellID helpers
- `BuffEngine.lua` (lust pattern) — `StartLustTimer` and aura-scan `source = "debuff"` guard as reference for meta-timer behavior
- `CDMTab.lua` lines 125-155 — copy-on-drag creates `ns.db.trackedBuffs[key]` with section/layoutOrder/label/metaBuff

### Milestone research
- `.planning/research/SUMMARY.md` — Cast detection via UNIT_SPELLCAST_SUCCEEDED, no new APIs needed for this phase
- `.planning/research/ARCHITECTURE.md` — OnSpellCastSucceeded fan-out pattern
- `.planning/research/PITFALLS.md` — Spell ID accuracy risk (verify in-game with debug logging)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:GetSpellIcon(spellID)` — icon resolution with 134400 fallback
- `ns.TRINKET_SPELLS`, `ns.POT_SPELLS` — O(1) spellID lookup tables with {duration, itemID}
- Existing timer shape: `{spellID, expiresAt, startedAt, duration, icon, label, section, source}` — extend with `metaSlot`

### Established Patterns
- Timer creation in `OnSpellCastSucceeded` — `now = GetTime()`, `expiresAt = now + duration`
- `source = "cast"` marker (existing). Keep this for meta-timers since timer is keyed by real spellID (aura scan works naturally).
- Meta-buffs in DB have `key` (string), `section`, `layoutOrder`, `label`, `metaBuff = true`

### Integration Points
- `OnSpellCastSucceeded` entry point for all cast events
- `ns.activeTimers[spellID]` — where timers live, keyed by numeric spellID
- Display.lua reads active timers — must tolerate new `metaSlot` field (ignore when nil)
- `UpdateDisplay` callback — already invoked after timer creation

</code_context>

<specifics>
## Specific Ideas

- "Timer keyed by actual spellID so existing aura scan cancellation works naturally" — user's explicit design per milestone discussion
- In-game spell ID verification is a Phase 13 implementation concern (research pitfall) — include debug logging output for testing the 13 spell IDs against real casts

</specifics>

<deferred>
## Deferred Ideas

- Icon resolution for at-rest CDM display (Phase 14) — this phase's scope is timer creation only; icon work is next
- Active timer icon switching (Phase 15) — display-side, not this phase
- Data storage rework milestone (noted in Phase 12 CONTEXT) — still deferred

</deferred>

---

*Phase: 13-timer-functions-cast-detection*
*Context gathered: 2026-04-13*
