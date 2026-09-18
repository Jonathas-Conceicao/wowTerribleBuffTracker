---
phase: 19-lustprovider-unit-aura-dispatch
plan: 02
subsystem: providers
tags: [lua, wow-addon, provider-pattern, lust-detection, unit-aura, dispatch]

# Dependency graph
requires:
  - phase: 19-lustprovider-unit-aura-dispatch
    provides: LustProviderMixin, ns.SHARED_LUST_BUFFS, ns.SATED_DEBUFF_TO_LUST, ns.CLASS_LUST_SPELL, ns.GetHunterLustSpell — all exported from Providers.lua in Plan 19-01

provides:
  - BuffEngine.OnUnitAura wired to ns:DispatchEventToProviders("UNIT_AURA", ...) as first call (no more inline LUST-01 block)
  - ScanActiveTimersForCancellation reads ns.SHARED_LUST_BUFFS (namespace, not local)
  - ns:StartLustTimer deleted — lust proc production now solely in LustProvider:OnTrigger
  - ns.secretGateLogged flag and ns:ClearSecretGateLog function (renamed from auraCheckBlocked/ClearAuraBlock)
  - Core.lua call sites updated to ns:ClearSecretGateLog()

affects:
  - 19-03 (in-game verification: group lust, M+, preview regression, cancel-on-buff-drop)
  - 20 (GetPreviewInfo / GetAtRestInfo for LustProvider)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Dispatcher-first OnUnitAura shape (D-14): unconditional dispatch, then scan-only post-dispatch gates
    - LUST-01 ordering preserved by architecture (D-04): LustProvider:OnTrigger runs before ShouldAurasBeSecret gate
    - One-shot debug-log flag (secretGateLogged) cleared on combat-end and zone-change

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - Core.lua

key-decisions:
  - "OnUnitAura rewritten to dispatcher-first shape (D-14): ns:DispatchEventToProviders unconditional, three post-dispatch gates guard ScanActiveTimersForCancellation only"
  - "ns.auraCheckBlocked renamed to ns.secretGateLogged (D-15) — name now reflects its true purpose as a one-shot debug-log suppressor"
  - "ns:ClearAuraBlock renamed to ns:ClearSecretGateLog (D-16) — behavior unchanged, naming clarified"
  - "BuffEngine is now zero lust-specific beyond ScanActiveTimersForCancellation debuff branch (D-21)"

patterns-established:
  - "Dispatcher-first event handler: provider dispatch unconditional, infrastructure scan gates post-dispatch"
  - "Namespace flag rename pattern: old name removed repo-wide, new name defined once at init, all call sites updated atomically"

requirements-completed:
  - PROV-01
  - LIFE-02

# Metrics
duration: 15min
completed: 2026-04-21
---

# Phase 19 Plan 02: LustProvider Cutover — BuffEngine Cleanup Summary

**BuffEngine.OnUnitAura rewritten to dispatcher-first shape (D-14); lust data locals, StartLustTimer, and inline LUST-01 block deleted; ScanActiveTimersForCancellation reads ns.SHARED_LUST_BUFFS; auraCheckBlocked/ClearAuraBlock renamed to secretGateLogged/ClearSecretGateLog with Core.lua call sites updated**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-21T06:35:00Z
- **Completed:** 2026-04-21T06:50:00Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- BuffEngine.lua purged of all lust-specific data (SATED_DEBUFF_TO_LUST, SHARED_LUST_BUFFS local, CLASS_LUST_SPELL, GetHunterLustSpell local) and the now-redundant ns:StartLustTimer function
- OnUnitAura replaced with dispatcher-first implementation — ns:DispatchEventToProviders("UNIT_AURA", "player", updateInfo) runs unconditionally before any gate, preserving LUST-01 ordering (PITFALL-6) by architecture
- ScanActiveTimersForCancellation now reads ns.SHARED_LUST_BUFFS (Providers.lua export) instead of the deleted local — satisfies LIFE-02
- Flag and function rename (auraCheckBlocked → secretGateLogged, ClearAuraBlock → ClearSecretGateLog) completed repo-wide; Core.lua's two call sites updated atomically
- All preservation invariants confirmed: StartAllPreviewTimers, ClearAllTimers, CURRENT_SCHEMA_VERSION = 3, Core.lua event registration block — all byte-for-byte unchanged

## Task Commits

1. **Task 1: Delete lust data locals and StartLustTimer from BuffEngine.lua, update SUGGESTED_BUFFS closure** - `efe7216` (feat)
2. **Task 2: Replace OnUnitAura inline LUST-01 block with dispatcher call; update ScanActiveTimersForCancellation to read ns.SHARED_LUST_BUFFS** - `7fc3d99` (feat)
3. **Task 3: Rename ns.auraCheckBlocked → ns.secretGateLogged and ns:ClearAuraBlock → ns:ClearSecretGateLog; update Core.lua call sites** - `3a7b981` (feat)

**Plan metadata:** (see final commit below)

## Files Created/Modified

- `BuffEngine.lua` — Deleted lust data tables (lines 11-47), deleted ns:StartLustTimer (~35 lines), rewrote OnUnitAura to dispatcher-first shape (~40 lines), updated ScanActiveTimersForCancellation SHARED_LUST_BUFFS reference, renamed flag/function; updated SUGGESTED_BUFFS closure
- `Core.lua` — Two call sites updated: PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA now call ns:ClearSecretGateLog()

## OnUnitAura New Shape (D-14 Final Form)

```lua
function ns:OnUnitAura(updateInfo)
    -- Phase 19 (D-14): Provider dispatch runs FIRST — unconditional. LustProvider reads addedAuras
    -- internally, performs per-entry issecretvalue(aura.spellId) checks (D-10), and applies the
    -- provider-internal no-restart guard (D-12). The dispatcher has NO gate logic (D-04) so
    -- LUST-01 pre-gate ordering is preserved by architecture: Sated-detection runs before the
    -- ShouldAurasBeSecret() scan gate below, satisfying PITFALL-6.
    ns:DispatchEventToProviders("UNIT_AURA", "player", updateInfo)

    -- AURA-02 / D-14: Gate the cancellation SCAN on secret restriction. The dispatch above
    -- already completed — these gates apply only to ScanActiveTimersForCancellation.
    -- secretGateLogged (D-15) is a one-shot debug-log flag; cleared by ns:ClearSecretGateLog
    -- from Core.lua's PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA handlers.
    if C_Secrets.ShouldAurasBeSecret() then
        if not ns.secretGateLogged then
            ns.secretGateLogged = true
            if ns.debugLogging then
                print("|cff00ccffTBT Debug|r: aura scan blocked — ShouldAurasBeSecret() returned true")
            end
        end
        return
    end

    -- ZONE-02: Suppress on isFullUpdate (zone boundary / loading screen transient)
    if updateInfo and updateInfo.isFullUpdate then
        if ns.debugLogging then
            print("|cff00ccffTBT Debug|r: UNIT_AURA isFullUpdate suppressed")
        end
        return
    end

    -- D-02: Skip scan while preview timers are active.
    -- Note (D-11): Providers run normally during preview; only the scan is preview-gated.
    if ns.previewActive then
        return
    end

    ns:ScanActiveTimersForCancellation()
end
```

## ScanActiveTimersForCancellation Change

One-line change in the `timer.source == "debuff"` branch:

```lua
-- Before:
local buffsToCheck = SHARED_LUST_BUFFS[timer.lustBuffID]

-- After:
local buffsToCheck = ns.SHARED_LUST_BUFFS[timer.lustBuffID]
```

## Core.lua Call Sites Updated

```lua
-- Before (both handlers):
ns:ClearAuraBlock()

-- After (both handlers):
ns:ClearSecretGateLog()
```

## Preservation Audit

- `git diff --stat Providers.lua` — no output (Providers.lua untouched in all three tasks)
- `grep -c "^function ns:StartAllPreviewTimers()" BuffEngine.lua` — 1 (PITFALL-4 preserved)
- `grep -c "^function ns:ClearAllTimers()" BuffEngine.lua` — 1
- `grep -c "CURRENT_SCHEMA_VERSION = 3" BuffEngine.lua` — 1 (PITFALL-1 preserved)
- `grep -c 'eventFrame:RegisterEvent' Core.lua` — 5
- `grep -c 'eventFrame:RegisterUnitEvent' Core.lua` — 1
- `~/.cargo/bin/stylua --check Providers.lua BuffEngine.lua Core.lua` — exit 0

## Decisions Made

Followed plan as specified. All D-14 through D-21 decisions from 19-CONTEXT.md applied:
- D-14: Dispatcher-first OnUnitAura with three post-dispatch scan gates
- D-15: ns.auraCheckBlocked → ns.secretGateLogged (one-shot debug-log flag)
- D-16: ns:ClearAuraBlock → ns:ClearSecretGateLog (behavior unchanged)
- D-17: Core.lua two call sites updated atomically with BuffEngine rename
- D-18: Lust data tables confirmed deleted from BuffEngine (per Providers.lua re-exports)
- D-19: ScanActiveTimersForCancellation retained in BuffEngine, reads ns.SHARED_LUST_BUFFS
- D-21: BuffEngine now zero lust-specific data and no StartLustTimer

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None — LustProvider:OnTrigger (Plan 19-01) is fully wired and will be invoked on every UNIT_AURA event from this plan onward. All data tables resolve via ns.* at call time (load-order safe).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 19-03 can proceed immediately: in-game verification of lust proc, M+ secret-gate behavior, preview regression, and cancel-on-buff-drop
- Phase 19 code changes are complete — 19-03 is verification only
- Known blocker: LUST-01 pre-gate ordering (PITFALL-6) can only be fully verified in Mythic+ where ShouldAurasBeSecret() returns true

---
*Phase: 19-lustprovider-unit-aura-dispatch*
*Completed: 2026-04-21*
