# Phase 14: Icon Resolution + Caching - Discussion Log

> **Audit trail only.**

**Date:** 2026-04-13
**Phase:** 14-icon-resolution-caching
**Areas discussed:** Cache + scan timing, Fallback priority, Display integration, CDM open detection

---

## Cache + Scan Timing

User rejected event-based refresh: "The aim is to update ONLY by the time the player opens CDM and will actually see this."

**Decided:** Eager cache `ns.metaIcons[key]`, refresh only on CDM preview trigger. ICON-06 dropped as N/A.

---

## Fallback Priority

**Decided:** ?-icon (134400) when nothing resolves. Never fall back to Bloodlust.

---

## Display Integration

**Decided:** Claude's discretion. Plan to add `ns:GetAtRestMetaIcon(key)` helper; wire into Display.lua placeholder paths and SUGGESTED_BUFFS.getCDMIcon.

---

## CDM Open Detection

User clarified: "we already have a logic that runs when cdm is open for the previews. We should hookup the equipment and bag scan alongside that."

**Decided:** Call `ns:RefreshMetaIcons()` at start of `StartPreview` in CDMTab.lua. Single call site.

## Claude's Discretion

- Function naming
- Helper placement
- Split vs combined trinket/pot resolution

## Deferred Ideas

- Async icon retry (GET_ITEM_INFO_RECEIVED) — future milestone
- Event-based refresh (PLAYER_EQUIPMENT_CHANGED, BAG_UPDATE_DELAYED) — N/A per user
