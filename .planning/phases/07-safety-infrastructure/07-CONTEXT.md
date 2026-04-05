# Phase 7: Safety Infrastructure - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire all prerequisite guards before any aura scan logic: UNIT_AURA event registration (player-filtered), secret-value blocked flag with correct reset triggers, isFullUpdate suppression, preview mode guard, and debug logging infrastructure.

</domain>

<decisions>
## Implementation Decisions

### Debug Logging
- **D-01:** Add a `/tbt debug` toggle that enables verbose logging of aura blocking state changes (blocked/unblocked), scan results, and secret value detection. Silent by default. Store debug flag as runtime-only (not persisted to SavedVariables).

### Preview Mode Guard
- **D-02:** Add `ns.previewActive` boolean flag. Set to `true` in `StartAllPreviewTimers`, cleared in `ClearAllTimers`. Aura scan must skip entirely when this flag is true — preview timers must remain visible regardless of real aura state.

### Event Handler Structure
- **D-03:** Claude's Discretion — choose between extending the existing `eventFrame` in Core.lua or creating a separate aura-focused frame in BuffEngine.lua. Decision should follow whichever pattern keeps the code cleanest given the 3 new events (UNIT_AURA, PLAYER_REGEN_ENABLED, ZONE_CHANGED_NEW_AREA) plus making PLAYER_ENTERING_WORLD persistent instead of one-shot.

### Blocked Flag Behavior (from requirements)
- **D-04:** `ns.auraCheckBlocked` set to `true` when `C_Secrets.ShouldAurasBeSecret()` returns true. Cleared on `PLAYER_REGEN_ENABLED` (combat drop) and `ZONE_CHANGED_NEW_AREA`. On next `UNIT_AURA` event after clear, re-check `ShouldAurasBeSecret()` — in M+ this re-blocks immediately since auras stay secret between pulls.
- **D-05:** When `isFullUpdate` is true in the UNIT_AURA payload, suppress any cancellation logic to prevent false cancellations from temporarily empty aura lists on zone boundaries.

### Claude's Discretion
- Event handler organization (D-03) — Claude picks based on codebase patterns and separation of concerns

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### WoW API (Blizzard Source)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\AuraUtil.lua` — Blizzard's own aura cache clearing pattern (uses PLAYER_REGEN_ENABLED)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerItemData.lua` — CDM's use of GetPlayerAuraBySpellID, aura.spellId field name (lowercase d)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewer.lua` — CDM's UNIT_AURA handling pattern

### Project Research
- `.planning/research/STACK.md` — UNIT_AURA event payload structure, C_Secrets API, GetPlayerAuraBySpellID signature
- `.planning/research/ARCHITECTURE.md` — Integration architecture, data flow, new/modified function list
- `.planning/research/PITFALLS.md` — Secret value edge cases, isFullUpdate zone transition behavior, race conditions

### Existing Code
- `Core.lua` — Current event registration and handler (lines 5-97)
- `BuffEngine.lua` — Timer management, StartAllPreviewTimers/ClearAllTimers (lines 177-203)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns.activeTimers` (keyed by spellID) — maps directly to `GetPlayerAuraBySpellID(spellID)` calls, no data model changes needed
- `ns:OnSpellCastSucceeded` — existing timer creation pattern to follow
- `ns:GetActiveTimers` — already cleans expired timers, aura cancellation follows same removal pattern (`ns.activeTimers[spellID] = nil`)

### Established Patterns
- Single `eventFrame` in Core.lua handles all events via if/elseif chain
- `RegisterUnitEvent` needed for UNIT_AURA (different from `RegisterEvent`)
- Namespace (`ns`) holds all runtime state — `ns.auraCheckBlocked`, `ns.previewActive` follow this pattern
- `ns.UpdateDisplay` called after timer state changes

### Integration Points
- `Core.lua:8` — `PLAYER_ENTERING_WORLD` currently unregistered after init (line 90); needs to stay registered
- `BuffEngine.lua:177` — `StartAllPreviewTimers` needs `ns.previewActive = true`
- `BuffEngine.lua:198` — `ClearAllTimers` needs `ns.previewActive = false`
- New events route to new handler functions in BuffEngine.lua

</code_context>

<specifics>
## Specific Ideas

- Debug toggle via `/tbt debug` — matches existing `/tbt` slash command pattern
- Preview mode must keep timers showing even when real auras are absent — user explicitly stated this

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-safety-infrastructure*
*Context gathered: 2026-04-04*
