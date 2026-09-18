---
phase: 19-lustprovider-unit-aura-dispatch
plan: 01
subsystem: providers
tags: [lua, wow-addon, provider-pattern, lust-detection, unit-aura]

# Dependency graph
requires:
  - phase: 18-trinketprovider-potprovider-buffengine-dispatch
    provides: SpellProviderBaseMixin, eventToProviders build loop, ns.providers registration pattern, DispatchEventToProviders dispatcher

provides:
  - LustProviderMixin with GetEventInterests(UNIT_AURA) and OnTrigger (no-restart guard, issecretvalue per-entry check)
  - ns.SATED_DEBUFF_TO_LUST relocated to Providers.lua (re-export)
  - ns.SHARED_LUST_BUFFS as NEW namespace export (was local in BuffEngine.lua)
  - ns.CLASS_LUST_SPELL relocated to Providers.lua (re-export)
  - ns.GetHunterLustSpell as NEW namespace function (dot-syntax, no self)
  - ns.providers updated to four providers in locked order { TrinketProvider, PotProvider, LustProvider, UserSpellProvider }
  - eventToProviders["UNIT_AURA"] auto-populated at module load pointing at LustProvider

affects:
  - 19-02 (cutover: delete StartLustTimer, replace LUST-01 block with dispatcher call, read ns.SHARED_LUST_BUFFS, rename flags)
  - 19-03 (in-game verification: group lust, M+, preview regression)
  - 20 (GetPreviewInfo / GetAtRestInfo for LustProvider)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - LustProvider as fourth independent concrete mixin — follows Phase 18 separate-mixins pattern
    - Hybrid data move: lust tables colocated with LustProvider in Providers.lua, namespace-exported for external readers
    - No-restart guard provider-internal (D-12): dispatcher remains dumb and uniform
    - issecretvalue per-entry check without top-level ShouldAurasBeSecret gate (D-09/D-10)
    - ns.GetHunterLustSpell as dot-syntax function (no self) for SUGGESTED_BUFFS closure compat

key-files:
  created: []
  modified:
    - Providers.lua

key-decisions:
  - "LustProvider is additive-only in Plan 19-01: registered in ns.providers and eventToProviders but BuffEngine.OnUnitAura does not yet call DispatchEventToProviders for UNIT_AURA — no behavioral change until 19-02"
  - "ns.SHARED_LUST_BUFFS is a new namespace export (was local in BuffEngine.lua) — enables ScanActiveTimersForCancellation to read it after 19-02 removes the local"
  - "ns.GetHunterLustSpell uses dot-syntax (function ns.GetHunterLustSpell()) so BuffEngine SUGGESTED_BUFFS closure resolves it after 19-02 removes the local"
  - "No previewActive check in LustProvider:OnTrigger (D-11) — intentional prep for Phase 21 additive preview rewrite"

patterns-established:
  - "Provider-internal no-restart guard: check ns.activeTimers[key].expiresAt > GetTime() before returning proc"
  - "Lust proc shape: key=lust, lustBuffID=numeric, source=debuff, spellID=lust (Display coexistence), startedAt+section+layoutOrder for v0.2.3 field compat"

requirements-completed:
  - PROV-01

# Metrics
duration: 8min
completed: 2026-04-21
---

# Phase 19 Plan 01: LustProviderMixin + Lust Data Tables Summary

**LustProviderMixin added to Providers.lua with UNIT_AURA interest, no-restart guard, and per-entry issecretvalue check; lust data tables (SATED_DEBUFF_TO_LUST, SHARED_LUST_BUFFS NEW, CLASS_LUST_SPELL, GetHunterLustSpell NEW) colocated and namespace-exported; ns.providers now lists all four providers completing PROV-01**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-21T06:22:00Z
- **Completed:** 2026-04-21T06:30:37Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- LustProviderMixin defined with all four SpellProviderBaseMixin interface methods (GetEventInterests, OnTrigger, GetPreviewInfo/GetAtRestInfo inherited as base no-ops until Phase 20)
- eventToProviders["UNIT_AURA"] now points at LustProvider automatically via the module-load registry build loop
- Lust data tables (4 items) relocated from BuffEngine.lua to Providers.lua with all ns.* exports preserved and ns.SHARED_LUST_BUFFS added as a new export
- ns.providers updated to final four-provider order { TrinketProvider, PotProvider, LustProvider, UserSpellProvider } — PROV-01 architecturally satisfied
- BuffEngine.lua and Core.lua completely untouched — zero behavioral change until Plan 19-02

## Task Commits

1. **Task 1: Add lust data tables + LustProviderMixin to Providers.lua, update ns.providers order** - `f02b8ee` (feat)

**Plan metadata:** (see final commit below)

## Files Created/Modified

- `Providers.lua` — Added lust data tables (lines 183-224), LustProviderMixin (lines 328-419), updated ns.providers to four-provider order (line 426), updated header comment (line 4)

## Decisions Made

Followed plan as specified. All D-01 through D-22 decisions from 19-CONTEXT.md applied:
- D-09: No top-level ShouldAurasBeSecret check in LustProvider
- D-10: Per-entry issecretvalue(aura.spellId) check preserved
- D-11: No ns.previewActive check (intentional prep for Phase 21)
- D-12: No-restart guard provider-internal
- D-13: lustBuffID field in proc for ScanActiveTimersForCancellation
- D-18: Hybrid data move — lust tables colocated with provider, namespace-exported

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 19-02 can proceed immediately: LustProvider is wired and correct
- 19-02 scope: delete ns:StartLustTimer, replace inline LUST-01 block in OnUnitAura with ns:DispatchEventToProviders("UNIT_AURA", ...), update ScanActiveTimersForCancellation to read ns.SHARED_LUST_BUFFS, rename ns.auraCheckBlocked -> ns.secretGateLogged, rename ns:ClearAuraBlock -> ns:ClearSecretGateLog
- Known stub: none — LustProvider:OnTrigger will not be invoked until 19-02 routes UNIT_AURA through the dispatcher. This is intentional (additive-only plan design)

---
*Phase: 19-lustprovider-unit-aura-dispatch*
*Completed: 2026-04-21*
