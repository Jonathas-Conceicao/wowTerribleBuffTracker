# Roadmap: TerribleBuffTracker

## Milestones

- [x] **v0.2.0 Config & Edit Mode Rework** - Phases 1-6 (shipped 2026-03-30)
- [x] **v0.2.1 Aura-Based Timer Cancellation** - Phases 7-11 (ready for release 2026-04-04)

## Phases

<details>
<summary>v0.2.0 Config & Edit Mode Rework (Phases 1-6) — SHIPPED 2026-03-30</summary>

- [x] **Phase 1: Data Migration** - Expand SavedVariables schema and backfill existing entries (completed 2026-03-28)
- [x] **Phase 2: Edit Mode Containers** - Two independently movable containers registered with Edit Mode
- [x] **Phase 3: CDM Tab Shell** - Tab button injection and content panel frame; old config UI removed
- [x] **Phase 4: CDM Tab Sections** - Four sections rendered from DB state with Add button and delete drop zone (static)
- [x] **Phase 5: Drag-and-Drop** - Buff drag between sections with ghost frame, drop zone highlighting, and delete zone
- [x] **Phase 6: Cleanup** - Dead code removal, hot-path audit, stylua, release prep (completed 2026-03-30)

</details>

### v0.2.1 Aura-Based Timer Cancellation (In Progress)

**Milestone Goal:** Timers stop automatically when tracked buffs are no longer present. Handles M+ secret value restrictions, zone transitions, and lust/heroism variants.

- [x] **Phase 7: Safety Infrastructure** - Grace period, blocked flag, reset triggers, and preview guard wired before any scan logic (completed 2026-04-04)
- [x] **Phase 8: Aura Scan and Cancellation** - UNIT_AURA handler and scan function that silently cancel timers for absent buffs (completed 2026-04-04)
- [ ] **Phase 9: Zone Transition Handling** - Post-login and zone-exit scans to catch buffs stripped by loading screens
- [x] **Phase 10: Lust Tracking** - Sated-family debuff detection auto-starts lust timer; class-aware meta-buff icon in CDM tab (completed 2026-04-04)
- [x] **Phase 11: Cleanup** - Hot-path audit, stylua, recentlyCast table growth check, release prep (completed 2026-04-04)

## Phase Details

### Phase 7: Safety Infrastructure
**Goal**: All prerequisite guards are in place before any aura scan logic is written
**Depends on**: Phase 6
**Requirements**: AURA-01, AURA-02, AURA-03, ZONE-02
**Success Criteria** (what must be TRUE):
  1. The addon registers UNIT_AURA only for the "player" unit — no party or raid aura events are received
  2. After casting a tracked spell, the newly created timer survives for at least 0.5 seconds regardless of what UNIT_AURA fires next
  3. ns.auraCheckBlocked becomes true the first time auras are detected as secret, and no scan runs while it is true
  4. ns.auraCheckBlocked resets to false after leaving a zone or combat encounter, allowing the next UNIT_AURA event to re-check
  5. Preview mode timers are not cancelled by any aura event while preview is active
**Plans:** 1 plan

Plans:
- [x] 07-01-PLAN.md — Event registration, guard flags, OnUnitAura stub, ClearAuraBlock, preview wiring, debug toggle

### Phase 8: Aura Scan and Cancellation
**Goal**: Active timers for tracked buffs no longer present are silently removed on every relevant UNIT_AURA event
**Depends on**: Phase 7
**Requirements**: AURA-04
**Success Criteria** (what must be TRUE):
  1. When a tracked buff is manually cancelled by the player, its timer disappears from the display without any user action in the addon
  2. When a tracked buff falls off early (trinket proc, dispel, wipe), the timer is removed before it would have expired naturally
  3. A timer created immediately before an isFullUpdate event is not incorrectly cancelled by that event
  4. Display is refreshed exactly once when one or more timers are cancelled by a single scan pass
**Plans:** 1/1 plans complete

Plans:
- [x] 08-01-PLAN.md — ScanActiveTimersForCancellation function, source="cast" origin marker, placeholder replacement

### Phase 9: Zone Transition Handling
**Goal**: Timers for buffs stripped during loading screens are cancelled when the player enters the new zone
**Depends on**: Phase 8
**Requirements**: ZONE-01
**Success Criteria** (what must be TRUE):
  1. After a zone transition (dungeon entry, world travel), timers for buffs that were removed during the loading screen are gone within the first second of the new area loading
  2. Timers for buffs that survived the zone transition continue running normally
  3. On /reload or fresh login, any timer whose buff is not currently active is cancelled before the first game frame renders
**Plans**: TBD

### Phase 10: Lust Tracking
**Goal**: Bloodlust/Heroism and all current-season equivalents are trackable as a single meta-buff entry with a class-aware icon
**Depends on**: Phase 9
**Requirements**: LUST-01, LUST-02, LUST-03, LUST-04, LUST-05
**Success Criteria** (what must be TRUE):
  1. When any Sated-family debuff (Sated, Exhaustion, Temporal Displacement, etc.) appears on the player, a lust timer starts automatically without the player casting anything
  2. The CDM tab shows exactly one "Lust / Heroism" entry regardless of which lust variant is active or what class the player is
  3. A Shaman sees the Bloodlust icon; a Mage sees the Time Warp icon; a class with no personal lust sees the Bloodlust icon as default
  4. The CDM tab entry shows gray subtext reading "Matches all Heroism/Bloodlust effects"
  5. Using Drums of... (current season) also triggers the lust timer
**Plans:** 2/2 plans complete

Plans:
- [x] 10-01-PLAN.md — Lust data tables, schema migration v3, debuff detection in OnUnitAura, StartLustTimer
- [x] 10-02-PLAN.md — CDM tab Suggested section activation, copy-on-drag, right-click menu, class-aware icon, tooltip
**UI hint**: yes

### Phase 11: Cleanup
**Goal**: Codebase is lean, correct, and ready for v0.2.1 release
**Depends on**: Phase 10
**Requirements**: none (GSD workflow cleanup phase per CLAUDE.md)
**Success Criteria** (what must be TRUE):
  1. ns.recentlyCast entries are cleaned up on expiry and do not grow unbounded across a session
  2. ScanActiveTimersForCancellation does not allocate any new tables per call
  3. All modified Lua files pass stylua with no changes
  4. Release script produces a clean package and changelog entry reflects v0.2.1 features
**Plans:** 2/2 plans complete

Plans:
- [x] 11-01-PLAN.md — ResolveSuggestedSpellID helper extraction, preview save/restore fix, dead code removal
- [x] 11-02-PLAN.md — stylua pass, CHANGELOG.md v0.2.1 entry, REQUIREMENTS.md status update

## Progress

**Execution Order:** 7 -> 8 -> 9 -> 10 -> 11

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Data Migration | v0.2.0 | 1/1 | Complete | 2026-03-28 |
| 2. Edit Mode Containers | v0.2.0 | 2/2 | Complete | — |
| 3. CDM Tab Shell | v0.2.0 | 1/1 | Complete | — |
| 4. CDM Tab Sections | v0.2.0 | 2/2 | Complete | — |
| 5. Drag-and-Drop | v0.2.0 | 1/1 | Complete | — |
| 5.1. Edit Mode Settings Popup | v0.2.0 | 2/2 | Complete | — |
| 6. Cleanup | v0.2.0 | 1/1 | Complete | 2026-03-30 |
| 7. Safety Infrastructure | v0.2.1 | 1/1 | Complete | 2026-04-04 |
| 8. Aura Scan and Cancellation | v0.2.1 | 1/1 | Complete   | 2026-04-04 |
| 9. Zone Transition Handling | v0.2.1 | 1/1 | Complete | 2026-04-04 |
| 10. Lust Tracking | v0.2.1 | 2/2 | Complete    | 2026-04-04 |
| 11. Cleanup | v0.2.1 | 2/2 | Complete    | 2026-04-04 |
