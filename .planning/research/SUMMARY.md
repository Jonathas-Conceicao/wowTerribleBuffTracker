# Research Summary: v0.2.3 Trinket & Pot Meta-Trackers

**Project:** TerribleBuffTracker v0.2.3
**Researched:** 2026-04-12
**Confidence:** HIGH

## Executive Summary

TBT v0.2.3 extends the proven lust meta-tracker pattern to two new shared-slot trackers: on-use trinkets (9 entries) and damage potions (4 entries). The architecture is already validated — `UNIT_SPELLCAST_SUCCEEDED` with `GetTime()` + known duration is the detection method, and the string-keyed shared-slot overwrite model is in production for lust. Primary changes in `BuffEngine.lua`; minor nil-guards in `CDMTab.lua` and `Display.lua`. No new files needed.

The key new challenge is dynamic icon resolution: at-rest icons reflect equipped gear (trinkets) and bag contents (pots) via out-of-combat inventory scanning, cached and refreshed on equipment/bag change events. Active timer icons show the specific cast spell.

## Stack Additions

- `GetInventoryItemID("player", INVSLOT_TRINKET1/2)` — equipped trinket detection (no secret-return annotation)
- `C_Item.GetItemCount(itemID)` — bag presence check for pots
- `C_Item.GetItemIconByID(itemID)` — icon resolution from item ID (may return nil for uncached items)
- `PLAYER_EQUIPMENT_CHANGED` event — trinket icon refresh (filter slots 13/14)
- `BAG_UPDATE_DELAYED` event — pot icon refresh (debounced, once per transaction)
- `GET_ITEM_INFO_RECEIVED` event — async icon fallback for uncached items

## Feature Table Stakes

- Shared-slot overwrite (newest cast always wins)
- Active timer shows cast spell icon; at-rest shows equipped/bag item icon
- Icon refresh on equipment/bag change events (out of combat only)
- `source = "meta"` marker to prevent false aura scan cancellation
- Schema v4 migration for new `"trinket"` / `"pot"` string keys

## Top Pitfalls

1. **Missing `source = "meta"`** — timer cancelled on first UNIT_AURA because `GetPlayerAuraBySpellID("trinket")` returns nil
2. **Inventory API in combat** — `GetInventoryItemID` may return secret values in M+; gate on `InCombatLockdown()` + `issecretvalue()` guard
3. **Wrong spell IDs in allowlist** — on-use ability spell ID differs from item ID and proc buff spell ID; verify in-game
4. **Schema collision** — new string keys need schema v4 migration before runtime code
5. **Nil icon for uncached items** — `C_Item.GetItemIconByID` returns nil; use fallback icon (134400); retry via `GET_ITEM_INFO_RECEIVED`

## Architecture

**Data tables:** `TRINKET_SPELLS` and `POT_SPELLS` map spellID → {duration, itemID, metaKey}. `POT_ITEM_IDS` and trinket item IDs for bag/inventory scanning.

**Timer functions:** `StartTrinketTimer` / `StartPotTimer` mirror `StartLustTimer`. `OnSpellCastSucceeded` gets pre-DB fan-out checking meta tables before `ns.db.trackedBuffs`.

**Aura scan guard:** `ScanActiveTimersForCancellation` skips string-keyed timers or timers with `source = "meta"`.

**Icon resolution:** `ResolveTrinketIcon` scans equipped slots 13/14. `ResolvePotIcon` scans bags via `C_Item.GetItemCount`. Both gated on `not InCombatLockdown()`. Cached in `ns.metaIcons`. Refreshed on equipment/bag events and CDM settings open.

**Display:** At-rest reads `ns.metaIcons[key]`; active timer reads `timer.icon` (spell icon from cast).

## Suggested Phases (4)

1. **Schema Migration + Data Tables** — v3→v4 migration, TRINKET_SPELLS/POT_SPELLS/item ID tables
2. **Timer Functions + Cast Detection** — StartTrinketTimer/StartPotTimer, OnSpellCastSucceeded fan-out, source="meta" guard, SUGGESTED_BUFFS entries
3. **Icon Resolution + Caching** — ResolveTrinketIcon/ResolvePotIcon, ns.metaIcons, PLAYER_EQUIPMENT_CHANGED/BAG_UPDATE_DELAYED hooks, InCombatLockdown gate, async fallback
4. **Display Integration + Cleanup** — nil-spellID guards in CDMTab/Display, at-rest icon path, preview mode, stylua, hot-path review

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Stack APIs | HIGH | Verified against wow-ui-source; no secret-return annotations on inventory APIs |
| Lust pattern extension | HIGH | In production; trinket/pot are direct structural analogs |
| Architecture integration | HIGH | Code read directly; integration points identified with file:function references |
| Pitfalls | MEDIUM-HIGH | Pitfalls 1-4 confirmed from codebase; 5 from API docs |

---
*Research completed: 2026-04-12*
*Ready for requirements: yes*
