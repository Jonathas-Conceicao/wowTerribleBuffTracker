# Requirements: TerribleBuffTracker

**Defined:** 2026-04-04
**Core Value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.

## v0.2.1 Requirements

Requirements for aura-based timer cancellation and lust tracking. Each maps to roadmap phases.

### Aura Detection

- [x] **AURA-01**: Addon registers UNIT_AURA (player-filtered via RegisterUnitEvent) to monitor buff presence
- [x] **AURA-02**: Addon checks C_Secrets.ShouldAurasBeSecret() and sets a blocked flag when aura data is secret
- [x] **AURA-03**: Blocked flag clears on PLAYER_REGEN_ENABLED (combat drop) and ZONE_CHANGED_NEW_AREA; re-checks ShouldAurasBeSecret() on next UNIT_AURA event (in M+ it re-blocks immediately since auras stay secret)
- [x] **AURA-04**: When not blocked, addon scans active timers via GetPlayerAuraBySpellID and silently removes timers for buffs no longer present

### Lust Tracking

- [x] **LUST-01**: Addon detects Sated/Exhaustion/Temporal Displacement/etc. debuffs appearing and auto-starts a lust timer
- [x] **LUST-02**: Lust is represented as a single meta-buff in the CDM tab (one icon for all lust variants)
- [x] **LUST-03**: Meta-buff icon defaults to Shaman Bloodlust; uses class-specific lust icon if player's class has one (Mage, Evoker, etc.)
- [x] **LUST-04**: CDM tab entry shows gray detail text "Matches all Heroism/Bloodlust effects"
- [x] **LUST-05**: Current season drums are supported as a lust source

### Zone Transition Handling

- [x] **ZONE-01**: Addon scans active timers on ZONE_CHANGED_NEW_AREA and PLAYER_ENTERING_WORLD to catch buffs stripped during loading screens
- [x] **ZONE-02**: isFullUpdate events are suppressed to prevent false cancellations from empty aura lists on zone boundaries

## Future Requirements

### Aura Enhancements

- **AURA-F01**: Update timer durations from aura data (not just cancellation)
- **AURA-F02**: Aura-based buff auto-discovery for untracked buffs
- **LUST-F01**: Historical lust variants and non-current-season drums

## Out of Scope

| Feature | Reason |
|---------|--------|
| Cast-to-aura grace period | Aura data is trustworthy when not blocked — unnecessary for now |
| Timer duration updates from aura data | Only cancellation in this milestone |
| Aura-based buff auto-discovery | Only checks already-tracked buffs (except lust meta-buff) |
| Historical lust variants / non-current drums | Only current season supported |
| Display rendering changes | Not in this milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AURA-01 | Phase 7 | Complete |
| AURA-02 | Phase 7 | Complete |
| AURA-03 | Phase 7 | Complete |
| ZONE-02 | Phase 7 | Complete |
| AURA-04 | Phase 8 | Complete |
| ZONE-01 | Phase 9 | Complete |
| LUST-01 | Phase 10 | Complete |
| LUST-02 | Phase 10 | Complete |
| LUST-03 | Phase 10 | Complete |
| LUST-04 | Phase 10 | Complete |
| LUST-05 | Phase 10 | Complete |

**Coverage:**
- v0.2.1 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-04-04*
*Last updated: 2026-04-03 after roadmap creation*
