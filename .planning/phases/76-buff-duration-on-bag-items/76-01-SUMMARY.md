---
phase: 76-buff-duration-on-bag-items
plan: 01
subsystem: engine
tags: [bag-items, cooldown-buff, edit, providers, display]
requires:
  - Phase 74 cooldown-buff engine (ns:StartCooldownBuffFromCast, ns:CooldownBuffDuration, ns:CooldownBuffAliveBuffs)
  - Phase 75 buff look (slotEntry local in RenderIconContainer)
provides:
  - ns:UpdateTrackedItemBuff(key, fields) buff-only commit for a bag item
  - ns:ApplyCooldownBuffEdit(key, entry) shared running-buff edit rule
  - ns:IsEditableTracker admits bag items
  - item use starts the item's buff (MetaItemBagProviderMixin:OnTrigger)
affects:
  - plan 76-02 (dialog: greyed fields, buff fields for items, title)
tech-stack:
  added: []
  patterns: [side-effect activeTimers write from a provider, explicit-key buff-only commit]
key-files:
  created: []
  modified:
    - BuffEngine.lua
    - Providers.lua
    - Display.lua
decisions:
  - Option A from 76-PATTERNS 1a: widen ns:IsEditableTracker and route bag items inside ns:UpdateTrackedBuff, so the CDMTab confirm handler needs no branch
  - The two Phase 74 edit-time blocks merged into ns:ApplyCooldownBuffEdit, run once after ns:RebuildRankIndex (buff off ends it, changed Duration ends it, unchanged Duration repoints aliveBuffs)
  - Engine guard rejects buffEnabled == true without a positive Aura ID or Duration on an item
metrics:
  duration: ~15 min
  completed: 2026-10-22
  tasks: 2
  files: 3
---

# Phase 76 Plan 01: Buff duration on bag items (engine and runtime) Summary

A bag item (metaItem with a numeric itemID) now passes the edit gate and saves only its three buff keys through `ns:UpdateTrackedItemBuff`. Using the item starts its buff timer alongside the item cooldown refresh. The running buff draws the item's own icon and item tooltip.

## Tasks

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Bag items are editable for their buff only | 058acc3 | BuffEngine.lua |
| 2 | Using a bag item starts its buff, drawn with the item's icon | b2fd938 | Providers.lua, Display.lua |

## What changed

- **BuffEngine.lua**
  - `ns:IsEditableTracker` adds `or ns:IsBagItemEntry(entry)`. Its header now names the three callers.
  - New `ns:UpdateTrackedItemBuff(key, fields)`:
    - It writes exactly `buffEnabled`, `buffAuraID` and `buffDuration`.
    - It never writes `entry.duration`, never re-keys and never rebuilds the rank index.
    - It refuses `buffEnabled == true` when the Aura ID or Duration is missing.
    - It prints a chat line keyed on the item name.
  - New `ns:ApplyCooldownBuffEdit(key, entry)` replaces both Phase 74 blocks in `ns:UpdateTrackedBuff` with one call, made after `ns:RebuildRankIndex`.
  - `ns:UpdateTrackedBuff` returns `ns:UpdateTrackedItemBuff(oldKey, fields)` for a bag item, before the spell ID check.
  - The `ns:StartAllPreviewTimers` preview proc gains `itemID` for a bag item.
- **Providers.lua**
  - `MetaItemBagProviderMixin:OnTrigger` reuses one entry lookup. After `ns:RefreshTrackedItemCooldowns()` and `ns:MarkCooldownsDirty()` it calls `ns:StartCooldownBuffFromCast(key, entry)`. Every path still returns nil.
  - `ns:StartCooldownBuffFromCast` sets `proc.itemID = entry.itemID`.
  - Updated comments:
    - the header block above `ns:StartCooldownBuffFromCast`
    - the OnTrigger header (the "has no buff side" sentence is gone)
    - the DESIGN NOTE, which now names both callers
- **Display.lua**: in the `RenderIconContainer` live-timer branch, a cooldown-slot entry now goes through `ApplyCachedIcon(icon, timer.spellID, entry.iconOverride)`. Every other proc keeps the original cache block unchanged. This closes Phase 75 review WR-01, which had been deferred here.

## Verification

- Both task gates printed PASS.
- `node scripts/aura-read-gate.js` passes, as does `--selftest` (30 cases). The gate script is unchanged.
- `stylua --check .` is clean.
- BuffEngine.lua, Providers.lua and Display.lua are all `w/crlf` with no `\r\r`.
- `./scripts/install.bat` deployed to every client folder.
- `CURRENT_SCHEMA_VERSION` stays 12, and ENGINE_OWNED is unchanged.
- In-game checks are deferred to Phase 78, by user decision.

## Deviations from Plan

None. The plan was executed as written.

## Known Stubs

None. The dialog side (greyed fields, item buff fields, "Edit Item" title, an Aura ID that never follows) is plan 76-02. Until it lands, the right-click Edit on a bag item opens the existing dialog, and any save goes through the buff-only engine path, so no field other than the three buff keys can be written.

## Self-Check: PASSED

- FOUND: BuffEngine.lua, Providers.lua, Display.lua modifications
- FOUND: 058acc3, b2fd938
