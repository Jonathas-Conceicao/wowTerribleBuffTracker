# Phase 1: Data Migration - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Expand TerribleBuffTrackerDB schema to support the new section-based buff management model. Add a `section` field to every tracked buff entry, backfill from existing `displayMode`/`enabled` values, add a `schemaVersion` guard at the DB root, and clean up deprecated fields. No UI changes in this phase.

</domain>

<decisions>
## Implementation Decisions

### Migration mapping
- **D-01:** Direct mapping from old fields to new section field:
  - `displayMode="bar"` + `enabled=true` → `section="bars"`
  - `displayMode="buff"` + `enabled=true` → `section="buffs"`
  - `enabled=false` (any displayMode) → `section="hidden"`
- **D-02:** Old `displayMode` and `enabled` fields are removed after migration. `section` is the single source of truth — clean break, no backwards compatibility shim.

### Schema versioning
- **D-03:** Add a `schemaVersion` number field to TerribleBuffTrackerDB root (not per-entry). Bump on each migration. Current (pre-migration) data is implicitly version 0; after this migration, version is 1.
- **D-04:** Migration runs only when `schemaVersion` is nil or less than the target version. This replaces the current field-presence check pattern in `InitBuffEngine()`.

### New buff defaults
- **D-05:** Newly added buffs default to `section="hidden"` (Not Displayed). User must explicitly drag them to "Tracked Bars" or "Tracked Buffs" in the CDM tab to make them visible.

### Claude's Discretion
- Migration function placement (inline in InitBuffEngine vs separate function)
- Whether to log migration activity to chat
- Error handling for unexpected field values

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

No external specs — requirements are fully captured in decisions above.

### Existing code
- `BuffEngine.lua` — Contains `InitBuffEngine()` with existing migration pattern (backfill `enabled`/`displayMode`). This is the integration point for the new migration.
- `Core.lua` — Contains `ADDON_LOADED` handler where `TerribleBuffTrackerDB` is initialized and `InitBuffEngine()` is called.

### Research
- `.planning/research/ARCHITECTURE.md` — DB schema change details, migration safety notes
- `.planning/research/PITFALLS.md` — Pitfall about migration ordering (must complete before any UI changes)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `InitBuffEngine()` in BuffEngine.lua: Already implements field-level backfill migration (lines 4-12). The new schema migration should follow this same pattern but add the schemaVersion guard.

### Established Patterns
- Namespace pattern: `local _, ns = ...` — all files share the `ns` namespace
- DB init in Core.lua: `TerribleBuffTrackerDB` is created if nil in `ADDON_LOADED`, then assigned to `ns.db`
- Tracked buffs keyed by spellID: `ns.db.trackedBuffs[spellID] = { spellID, duration, label, enabled, displayMode }`

### Integration Points
- `Core.lua:ADDON_LOADED` — Where `ns.db` is initialized and `InitBuffEngine()` is called. schemaVersion check belongs here or at the start of InitBuffEngine.
- `BuffEngine.lua:AddTrackedBuff()` — Currently sets `displayMode = "bar"` and `enabled = true` for new entries. Must be updated to set `section = "hidden"` instead.
- `BuffEngine.lua:SetBuffEnabled()` and `SetBuffDisplayMode()` — These write to the old fields. Must be updated or removed to use section.
- `BuffEngine.lua:OnSpellCastSucceeded()` — Reads `entry.enabled` to skip disabled buffs. Must read `entry.section` instead (skip if section is "hidden").

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-data-migration*
*Context gathered: 2026-03-28*
