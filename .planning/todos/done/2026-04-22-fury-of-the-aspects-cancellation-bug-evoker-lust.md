---
created: 2026-04-22T00:29:22.248Z
title: Fury of the Aspects cancellation not working (Evoker/Dracthyr lust)
area: providers
phase_hint: 24
files:
  - Providers.lua
---

## Closed: 2026-04-22 — Resolved

User confirmed in-game on 2026-04-22 that Fury of the Aspects cancellation works correctly; the original bug is not reproducing. No code change required. Closed as solved per Phase 24 D-05 (CONTEXT.md). User quote: "we can ignore the need to fix evoker lust, it seems to be working correctly now".

---

## Problem

When an Evoker/Dracthyr casts **Fury of the Aspects** (Evoker's version of Bloodlust/Heroism), the TBT timer bar appears correctly when the buff fires, but does NOT cancel when the buff drops naturally. Timer continues counting down past the actual aura expiry.

Bug surfaced during Phase 22 in-game verification (2026-04-21).

## Current data (in Providers.lua)

- `SATED_DEBUFF_TO_LUST[390435] = 390386` — Exhaustion (Evoker) → Fury of the Aspects
- `SHARED_LUST_BUFFS_LOCAL[390386] = { 390386 }` — single-element aliveBuffs group
- `CLASS_LUST_SPELL.EVOKER = 390386`

Detection works (buff triggers from the 390435 debuff), so the mapping is correct on the incoming side. The failure is on the outgoing cancellation scan — `C_UnitAuras.GetPlayerAuraBySpellID(390386)` is likely returning nil even while the buff is active.

## Possible causes

- **(a) Wrong spellID for Fury of the Aspects in current retail.** Midnight may have changed the buff spellID; 390386 could be stale from Dragonflight. Verify by running `/run for i=1,40 do local a = C_UnitAuras.GetBuffDataByIndex("player", i); if a then print(a.spellId, a.name) end end` while the buff is active on an Evoker.
- **(b) Multiple spellIDs for the buff** — Fury of the Aspects may have a base spellID and a separate "in-game applied" aura spellID (common for some class spells). If so, add the applied spellID to `aliveBuffs`.
- **(c) Exhaustion debuff ID mismatch** — If (a) is wrong, (b) of Evoker's Exhaustion may also need verification.
- **(d) `GetPlayerAuraBySpellID` API edge case** — possible but unlikely; Sated/Exhaustion debuffs work for Shaman/Mage/Hunter so the API itself is fine.

## Solution (for Phase 24 cleanup)

1. Have an Evoker cast Fury of the Aspects, dump live aura data with the snippet above to capture the actual buff spellID and name.
2. Verify the Exhaustion debuff spellID similarly (check `GetDebuffDataByIndex`).
3. Correct `SATED_DEBUFF_TO_LUST` and `SHARED_LUST_BUFFS_LOCAL` entries in Providers.lua.
4. If a variant aura exists (e.g., buff fires one spellID, aura applied is another), add both to `aliveBuffs`.
5. While testing, verify all other class lusts too: Shaman Bloodlust (2825), Mage Time Warp (80353), Hunter Primal Rage (264667) + Harrier's Cry (466904), Heroism (32182), Drums of Fury (1243972). Any that are stale should be corrected in the same cleanup pass.

## Verification

After fix: Evoker casts Fury → bar appears. Buff drops naturally → bar disappears within 1 UNIT_AURA cycle. Same smoke test against all other classes.
