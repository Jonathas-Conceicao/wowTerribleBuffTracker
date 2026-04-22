---
created: 2026-04-22T00:29:22.248Z
title: M+ Lua errors during lust — likely secret-value access violations
area: providers
phase_hint: 24
files:
  - Providers.lua
  - BuffEngine.lua
---

## Closed: 2026-04-22 — Resolved (not a TBT bug)

User reported on 2026-04-22 that the M+ Lua errors were caused by an integration issue with an unrelated addon, not TerribleBuffTracker. Closed as solved per Phase 24 D-06 (CONTEXT.md). User quote: M+ Lua errors were "related to integration with other addons, can be marked as solved".

---

## Problem

During Mythic+ keystone runs, the addon triggers **many Lua errors** related to secret values. Errors appear to occur during lust (Heroism/Bloodlust/etc.) detection or cancellation. User is still investigating — needs more detail (exact error text, stack trace).

Reported during Phase 22 verification (2026-04-21). Not caught by Phase 19 verification because M+ testing was skipped.

## Suspected causes

In M+, `C_Secrets.ShouldAurasBeSecret()` returns `true` — individual aura spellIDs can be opaque "secret values" instead of numbers. Any code path that reads an aura field without an `issecretvalue()` guard will throw.

Known safe paths (guarded):
- **LustProvider:OnTrigger** already has `if not issecretvalue(aura.spellId)` guard before indexing `SATED_DEBUFF_TO_LUST[aura.spellId]` — should be safe.

Suspected unsafe paths:
- **`ScanActiveTimersForCancellation`** — iterates `timer.aliveBuffs` and calls `C_UnitAuras.GetPlayerAuraBySpellID(buffID)`. If the aura object returned contains secret fields that Lua tries to read (e.g., in debug logging or field access), it could error. Less likely since we only check for nil return.
- **`OnUnitAura`** — after Phase 19, dispatches unconditionally then checks secret gate. Dispatch to LustProvider happens BEFORE the gate. Per-entry guard should protect, BUT: scanning through `updateInfo.addedAuras` may expose fields that error when read. Need to verify ALL aura fields accessed in LustProvider (only `aura.spellId`? or more?).
- **Tooltip rendering** (`ns:ShowBuffTooltip`) — calls `GameTooltip:SetSpellByID(proc.spellID)`. If `proc.spellID` were ever set from a secret value (unlikely post-Phase 22 since providers resolve numerics at OnTrigger time), tooltip would fail in M+.
- **`updateInfo` fields other than `addedAuras`** — `updatedAuras`, `removedAuraInstanceIDs`, `isFullUpdate` may behave differently under secret-aura mode.
- **Any print() / debug log** that stringifies an aura field without secret-gate protection.

## Information needed

User is investigating. Needs to capture:
1. Exact error text (copy/paste from BugSack or similar)
2. Stack trace (file:line)
3. Frequency — during lust trigger only? continuously? on specific M+ pull types?
4. Whether disabling TBT's lust detection (removing "lust" from tracked buffs) eliminates the errors

## Solution (for Phase 24 cleanup)

Blocked on user investigation. Once error text is available:
1. Identify the exact spellId / field access that faults
2. Add `issecretvalue()` guards at every aura-field read path
3. Consider whether `ShouldAurasBeSecret` should also gate LustProvider's dispatch entry (not just per-entry) as a belt-and-suspenders approach
4. Test in actual M+ with debug logging to confirm fix

## Verification

Run a M+ key with TBT enabled. Lust during a pull. Confirm zero Lua errors. Confirm lust timer still starts and cancels correctly (LUST-01 ordering preserved).

## Related

- Phase 19 D-09/D-10: LustProvider per-entry `issecretvalue` guard (partial protection)
- Phase 19 D-14: OnUnitAura dispatcher-first pattern (LUST-01 preserved by architecture)
- Known pre-existing: Phase 19 verification skipped Test 7 (M+ secret gate) — this is the regression the skip concealed
