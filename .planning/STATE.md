---
gsd_state_version: 1.0
milestone: v0.2.1
milestone_name: Aura-Based Timer Cancellation
status: completed
last_updated: "2026-04-04T19:29:46.931Z"
last_activity: 2026-04-04
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 6
  completed_plans: 6
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-03)

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.
**Current focus:** Phase 11 — cleanup

## Current Position

Phase: 11
Plan: Not started
Status: All phases complete — ready for squash-merge to main and release.bat v0.2.1
Last activity: 2026-04-04

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

*Updated after each plan completion*
| Phase 07-safety-infrastructure P01 | 2min | 2 tasks | 2 files |
| Phase 08-aura-scan-and-cancellation P01 | 15 | 1 tasks | 1 files |
| Phase 08-aura-scan-and-cancellation P01 | 15 | 2 tasks | 1 files |
| Phase 10-lust-tracking P01 | 2 | 2 tasks | 1 files |
| Phase 11-cleanup P01 | 20 | 2 tasks | 3 files |
| Phase 11-cleanup P02 | 10min | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Safety infrastructure (grace period, blocked flag, reset triggers) must be wired before scan logic — writing scan first creates a correctness window in M+/PvP
- [Roadmap]: Full per-spell-ID scan chosen over spellID→auraInstanceID reverse map — simpler, no cache-staleness risk, negligible perf difference at 5-15 buffs
- [Roadmap]: PLAYER_REGEN_ENABLED omitted as unblock trigger — fires between M+ pulls, causing re-block on next UNIT_AURA; use ZONE_CHANGED_NEW_AREA + PLAYER_ENTERING_WORLD only
- [Phase 07-safety-infrastructure]: Extended existing eventFrame (D-03) for UNIT_AURA routing — keeps event dispatch as a thin router to ns: methods, consistent with established pattern
- [Phase 07-safety-infrastructure]: Guard ordering in OnUnitAura is the critical safety contract for Phase 8: secret -> isFullUpdate -> previewActive -> scan
- [Phase 08-aura-scan-and-cancellation]: source = cast marker on cast-originated timers enables Phase 10 lust timers to coexist without false cancellation
- [Phase 08-aura-scan-and-cancellation]: cancelledLabels only allocated when debugLogging is true — zero-allocation hot path in ScanActiveTimersForCancellation
- [Phase 10-lust-tracking]: SATED_DEBUFF_TO_LUST maps debuff IDs because Sated-family debuffs are the reliable signal; lust buff itself may be secret
- [Phase 10-lust-tracking]: source=debuff on lust timer prevents false cancellation by ScanActiveTimersForCancellation (which only scans source=cast)
- [Phase 10-lust-tracking]: issecretvalue per-entry guard before SATED_DEBUFF_TO_LUST lookup — indexing Lua table with secret value causes error in M+
- [Phase 10-02]: Copy-on-drag from Suggested: if already tracked moves to target, if absent creates entry from SUGGESTED_BUFFS; icon always stays in Suggested (D-05, D-07)
- [Phase 10-02]: SetBuffSection now guards nil and non-string/non-number inputs per Pitfall 4; tostring() tiebreak in sort handles mixed-type spellID keys
- [Phase 11-cleanup]: ResolveSuggestedSpellID returns only spellID — single-purpose helper, callers call GetSpellInfo for label independently
- [Phase 11-cleanup]: savedPreviewTimers is module-local not ns.* — internal to BuffEngine preview state machine only
- [Phase 11-02]: CHANGELOG v0.2.1 section added; LUST-02/03/04 and ZONE-01 marked complete; branch release-ready for squash-merge + release.bat v0.2.1

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 7]: ns.previewActive flag existence in BuffEngine.lua needs verification during implementation — ARCHITECTURE.md says it is "implied" but not confirmed in source
- [Phase 8]: Cast/aura event ordering (UNIT_SPELLCAST_SUCCEEDED fires before UNIT_AURA) is convention not contract — 0.5s grace period absorbs this but may need tuning for instant-application buffs; validate in-game
- [Phase 8]: Exact moment M+ aura restriction activates relative to first UNIT_AURA event is unconfirmed — post-cast probe detection covers this conservatively
