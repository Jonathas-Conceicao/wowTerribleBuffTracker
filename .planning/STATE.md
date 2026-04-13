---
gsd_state_version: 1.0
milestone: v0.2.3
milestone_name: Trinket & Pot Meta-Trackers
status: completed
last_updated: "2026-04-13T09:36:33.984Z"
last_activity: 2026-04-13
progress:
  total_phases: 5
  completed_phases: 5
  total_plans: 8
  completed_plans: 8
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-13)

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.
**Current focus:** v0.2.3 COMPLETE — ready to release

## Current Position

Phase: 16 (cleanup) — COMPLETE
Plan: 1 of 1
Status: All phases complete — v0.2.3 milestone complete
Last activity: 2026-04-13

```
Progress: [##########] 100% (5/5 phases)
```

## Performance Metrics

**Velocity:**

- Total plans completed: 8
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 12. Schema Migration + Data Tables | 2/2 | — | — |
| 13. Timer Functions + Cast Detection | 2/2 | — | — |
| 14. Icon Resolution + Caching | 2/2 | — | — |
| 15. Display Integration + Active Icon Switching | 1/1 | — | — |
| 16. Cleanup | 1/1 | ~20min | ~20min |
| Phase 12-schema-migration-data-tables P01 | 5 | 1 tasks | 1 files |
| Phase 12-schema-migration-data-tables P02 | 10 | 3 tasks | 3 files |
| Phase 13-timer-functions-cast-detection P01 | 7 | 2 tasks | 1 files |
| Phase 13-timer-functions-cast-detection P02 | 5 | 3 tasks | 1 files |
| Phase 14-icon-resolution-caching P01 | 2 | 2 tasks | 2 files |
| Phase 14-icon-resolution-caching P02 | 45min | 3 tasks | 3 files |

## Accumulated Context

### Decisions

- [Lust pattern]: Meta-tracker slots use shared-slot overwrite — newest cast always wins
- [Icon resolution]: CDM and display icons always match, single source of truth. Cast overrides resolved icon during timer, reverts on expiry.
- [Icon scan]: Trinket scans equipped slots 13/14, pot scans bags via C_Item.GetItemCount. Both refresh on CDM settings open when out of combat.
- [Detection]: Both meta-trackers use UNIT_SPELLCAST_SUCCEEDED (cast detection only), no aura fallback.
- [Aura guard]: Trinket and pot timers keyed by actual spellID so existing ScanActiveTimersForCancellation works naturally — no source="meta" needed.
- [Schema]: v3→v4 migration cleans any stale string meta-keys before runtime timer code runs.
- [Combat gate]: All inventory/bag scanning (GetInventoryItemID, C_Item.GetItemCount) gated on not InCombatLockdown(); fallback to cached icon if unavailable.
- [Phase 12-01]: Tables kept local then exposed on ns — local for scoping, ns for Phase 13/14 cross-file access without restructuring
- [Phase 12-01]: No schema migration added — D-05 confirmed, CURRENT_SCHEMA_VERSION stays at 3
- [Phase 12-01]: itemID sets derived at module load, not hand-maintained — single source of truth is the spell table
- [Phase 12-02]: getCDMSpellID returns nil for trinket/pot so CDMTab detects itemID-based entries via truthiness; getCDMIcon=nil is explicit Phase 14 placeholder
- [Phase 12-02]: DATA-03 N/A: no schema migration needed — v3 stays terminal for v0.2.3; ROADMAP success criterion 'schema version reads 4' superseded by D-05
- [Phase 13-01]: D-02: Fan-out runs BEFORE the regular ns.db.trackedBuffs[spellID] path in OnSpellCastSucceeded (first match wins)
- [Phase 13-01]: D-04: Shared-slot overwrite iterates activeTimers and nils any entry with same metaSlot before insert
- [Phase 13-01]: D-06: section and layoutOrder copied from metaEntry at creation time (no per-render DB lookup)
- [Phase 13-01]: Inline implementation chosen over helper extraction — single function is clearer for 3-path routing
- [Phase 13-02]: No spell-ID corrections needed: all tested IDs (Nullsight 1260459, Light's Potential 1236616) matched TRINKET_SPELLS/POT_SPELLS exactly
- [Phase 13-02]: Bars/Buffs icon at rest shows Bloodlust placeholder for trinket/pot: Phase 14 scope (getCDMIcon=nil stub), not a Phase 13 bug
- [Phase 14-01]: ICON-06 N/A: at-rest icon refresh piggybacked on CDM StartPreview only — no equipment/bag event hooks (D-03/D-04)
- [Phase 14-01]: No icon recursion on nil GetItemIconByID: store nil, GetAtRestMetaIcon falls through to 134400 (?-icon) per user preference
- [Phase 14-01]: TRINKET_FALLBACK_ORDER / POT_FALLBACK_ORDER hard-coded in CSV insertion order since pairs() order is undefined in Lua
- [Phase 14-icon-resolution-caching]: D-04 re-enforced: PLAYER_EQUIPMENT_CHANGED/BAG_UPDATE_DELAYED hooks reverted; CDM open is sole refresh trigger
- [Phase 14-icon-resolution-caching]: Spell tooltip over item tooltip: buff spell shows clean name+duration; item tooltip surfaced ilvl/quality clutter
- [Phase 14-icon-resolution-caching]: Dual-index activeTimers: meta-slot entries written at numeric spellID and string metaSlot key for cancellation + display lookups

- [Phase 16]: Stylua and dead-code passes were clean no-ops — all Lua files already compliant from prior phases
- [Phase 16]: RELEASE_NOTES.md not created — auto-generated by GitHub Actions at tag push time
- [Phase 16]: v0.2.3 milestone declared complete after human review and approval

### Pending Todos

- Run `scripts/release.bat v0.2.3` when ready to ship (tags and pushes; GitHub Actions builds package)

### Blockers/Concerns

None yet.
