# Phase 9: Zone Transition Handling - Context

**Gathered:** 2026-04-04
**Status:** Covered by Phases 7+8

<domain>
## Phase Boundary

Zone-transition scanning for buffs stripped during loading screens. After analysis, this is already covered by the existing UNIT_AURA pipeline from Phases 7 and 8.

</domain>

<decisions>
## Implementation Decisions

### Phase Skipped — Already Covered
- **D-01:** Combat drop (PLAYER_REGEN_ENABLED) clears the blocked flag. The next UNIT_AURA event triggers ScanActiveTimersForCancellation, catching any buffs removed during the encounter. This handles boss wipes, lust lost on reset, trinket procs, etc.
- **D-02:** Zone change (ZONE_CHANGED_NEW_AREA) clears the blocked flag. The isFullUpdate suppression skips the first UNIT_AURA event on zone entry, but the second event (within a few seconds) catches any stripped buffs. User confirmed this delay is acceptable.
- **D-03:** Login/reload: ns.activeTimers is runtime-only (not persisted to DB), so after reload/login the table is empty. No scan needed.
- **D-04:** No additional code changes required. ZONE-01 requirement is satisfied by existing infrastructure.

</decisions>

<canonical_refs>
## Canonical References

No external specs — requirements fully captured in decisions above.

### Existing Implementation
- `Core.lua:103-106` — PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA handlers call ClearAuraBlock
- `BuffEngine.lua:212-241` — OnUnitAura with guard chain + ScanActiveTimersForCancellation

</canonical_refs>

<code_context>
## Existing Code Insights

No code changes needed. Existing pipeline covers the requirement.

</code_context>

<specifics>
## Specific Ideas

None — phase is covered by existing infrastructure.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 09-zone-transition-handling*
*Context gathered: 2026-04-04*
