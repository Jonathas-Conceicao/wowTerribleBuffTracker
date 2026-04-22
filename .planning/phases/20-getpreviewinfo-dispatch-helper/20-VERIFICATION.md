# Phase 20 Verification: GetDisplayInfo + Dispatch Helper

**Verified:** 2026-04-21
**Status:** APPROVED

## Scope Verified

- ns:GetDisplayInfoForKey dispatch helper (PROV-04 provider-side contract)
- Provider-owned at-rest caches (PROV-F3 pulled forward from future phases)
- Three backwards-compat shims delegating through ns:GetDisplayInfoForKey
- Zero visual regression vs Phase 19 (Display.lua / CDMTab.lua untouched)

## Verification Steps Executed

1. `/reload` — zero Lua errors observed
2. CDM open — trinket/pot/lust icons match equipped/bag/class-appropriate spells (all 4 providers resolve correctly)
3. Trinket cast — bar appears mid-CDM with correct icon and duration; real cast visible while CDM is open
4. Trinket at-rest icon updates correctly after equipment swap when CDM is reopened
5. Pot cast — bar appears with correct icon and duration
6. User-spell cast — bar appears correctly; no regression from Phase 19 behavior
7. Lust detection — regression check passes (Sated debuff path, no-restart guard respected)
8. Preview mode — user-spell and lust preview bars correct; trinket/pot preview still 0-second (expected, Phase 21 scope)
9. Tooltips — trinket/pot/lust icons in CDM Suggested section show correct spell tooltips via shim chain

## Known Deferred Behavior (NOT regressions)

- **Trinket and pot preview bars show 0-second duration.** PITFALL-4 / LIFE-03.
  Reason: StartAllPreviewTimers is UNTOUCHED in Phase 20 per D-22. Phase 21 fixes this via
  additive-preview rewrite where providers run normally during preview and real procs are
  never wiped on CDM open.

- **Real casts made mid-CDM are lost when CDM closes.** PRE-EXISTING bug.
  Root cause: savedPreviewTimers is written once at CDM open (StartAllPreviewTimers) and does
  not refresh mid-preview after a real cast. When CDM closes, active timers restore from
  savedPreviewTimers — the mid-CDM cast proc is overwritten. This predates Phase 20 and is
  NOT a regression from the GetDisplayInfo refactor. Fix lands in Phase 21 (LIFE-03):
  the additive-preview rewrite ensures providers run normally during preview so real procs
  are never clobbered on CDM close.

## Success Criteria Met

- [x] SC-1: ns:GetDisplayInfoForKey(key) returns correct { icon, label, duration, spellID } for any registered provider key
- [x] SC-2: Trinket and pot GetDisplayInfo return non-zero durations at the provider layer (consumer migration in Phase 21)
- [x] SC-3: ns:GetDisplayInfoForKey exported to namespace, callable from Display.lua / CDMTab.lua
- [x] SC-4: RefreshAtRest() on base mixin + meta-providers; ns:RefreshMetaIcons is a thin wrapper iterating ns.providers; CDMTab callsite unchanged

## Requirements Closed

- PROV-04 — complete
- PROV-F3 (Future requirement, pulled forward) — complete

## Next Phase

Phase 21: Preview Mode Migration (LIFE-03) — migrates StartAllPreviewTimers to use provider
GetDisplayInfo, fixing the trinket/pot 0-second preview bars and the mid-CDM cast loss bug
via additive-preview rewrite (providers run normally during preview, real procs never wiped).
