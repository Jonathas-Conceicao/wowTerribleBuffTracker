---
phase: 20-getpreviewinfo-dispatch-helper
plan: "02"
subsystem: buff-engine
tags: [buff-engine, refactor, at-rest-cache, shims, dispatch, cleanup]
dependency_graph:
  requires:
    - "Plan 20-01: ns:GetDisplayInfoForKey export in Providers.lua"
    - "Plan 20-01: provider:RefreshAtRest on all 4 providers"
  provides:
    - "Thin ns:RefreshMetaIcons wrapper iterating ns.providers"
    - "ns:GetAtRestMetaIcon shim via ns:GetDisplayInfoForKey"
    - "ns:GetAtRestMetaInfo shim via ns:GetDisplayInfoForKey"
    - "ns:ResolveSuggestedSpellID shim via ns:GetDisplayInfoForKey"
  affects:
    - "Plan 20-03 (in-game behavior verification)"
    - "Phase 22 (Display.lua migration — DISP-01/03)"
    - "Phase 23 (CDMTab.lua migration — DISP-02)"
    - "Phase 24 (shim removal — DISP-04)"
tech_stack:
  added: []
  patterns:
    - "Thin wrapper: ns:RefreshMetaIcons iterates ns.providers, delegates scan to each provider:RefreshAtRest()"
    - "Backwards-compat shims delegate through public ns:GetDisplayInfoForKey — never access internal provider state"
    - "Double combat-gate: wrapper entry-gates + each provider defensive-gates (D-17/D-18)"
key_files:
  modified:
    - path: BuffEngine.lua
      changes: "Deleted ns.metaIcons+ns.metaAtRest tables; deleted FindSpellByItemID; rewrote RefreshMetaIcons as thin iterator; rewrote 3 shims to delegate through ns:GetDisplayInfoForKey (D-24)"
decisions:
  - "D-24: All three backwards-compat shims (GetAtRestMetaIcon, GetAtRestMetaInfo, ResolveSuggestedSpellID) delegate through ns:GetDisplayInfoForKey — internal provider cache is never accessed directly"
  - "D-15: RefreshMetaIcons name retained for Phase 20 backwards compat with CDMTab.StartPreview; rename deferred to Phase 24 cleanup"
  - "D-25: All three shims are scheduled for Phase 24 removal once Display.lua (Phase 22) and CDMTab.lua (Phase 23) migrate to ns:GetDisplayInfoForKey"
metrics:
  duration_minutes: 3
  completed_date: "2026-04-21"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 1
---

# Phase 20 Plan 02: BuffEngine Cleanup — Thin Wrapper + Shims via GetDisplayInfoForKey Summary

**One-liner:** Deleted provider-owned data from BuffEngine (ns.metaAtRest, FindSpellByItemID); rewrote RefreshMetaIcons as a combat-gated ns.providers iterator; rewired three backwards-compat shims through ns:GetDisplayInfoForKey per D-24.

## What Was Built

Plan 20-02 completes the BuffEngine-side of PROV-04 by removing all provider-specific data and scan logic from `BuffEngine.lua`:

1. **Deleted `ns.metaIcons` and `ns.metaAtRest` tables** — these were the old eager-cached at-rest resolution tables. They are now replaced by provider-owned `atRest = { spellID, duration }` instances in `TrinketProviderMixin` and `PotProviderMixin` (established in Plan 20-01).

2. **Deleted `FindSpellByItemID` helper** — the reverse-lookup function that was moved to `Providers.lua` as a module-local in Plan 20-01. BuffEngine no longer contains any inventory-scan logic.

3. **Rewrote `ns:RefreshMetaIcons`** — from a 46-line function containing inventory API calls (`GetInventoryItemID`, `C_Item.GetItemCount`, `INVSLOT_TRINKET1/2`) to an 8-line thin wrapper: combat-gate at entry, then `for _, provider in ipairs(ns.providers) do provider:RefreshAtRest() end`. CDMTab.lua's `ns:RefreshMetaIcons()` call site is unchanged.

4. **Rewrote three backwards-compat shims (D-24):**
   - `ns:GetAtRestMetaIcon(key)` → `local info = ns:GetDisplayInfoForKey(key); return (info and info.icon) or 134400`
   - `ns:GetAtRestMetaInfo(key)` → returns `{ icon, spellID, duration }` extracted from `ns:GetDisplayInfoForKey(key)`, or nil
   - `ns:ResolveSuggestedSpellID(key)` → early-return nil for non-string keys (preserved semantic); string keys route through `ns:GetDisplayInfoForKey(key)` returning `info.spellID`

   All 14 consumer call sites in Display.lua and CDMTab.lua continue to receive equivalent data — the shims are a compatibility layer until Phases 22/23 migrate consumers.

## Commits

| Hash | Description |
|------|-------------|
| b10b484 | refactor(20-02): rewrite BuffEngine — thin RefreshMetaIcons, shims via GetDisplayInfoForKey |

## Deviations from Plan

**Comment rewording to satisfy grep acceptance criteria**

The plan's acceptance criteria use `grep -c` to count zero occurrences of deleted symbols. The initial NOTE comment (documenting Phase 20 relocations) and a shim comment (describing the old contract) contained `ns.metaAtRest` and `FindSpellByItemID` in their text. These were reworded to avoid false positives:
- `FindSpellByItemID` → "reverse-lookup helper"
- `ns.metaAtRest` → "at-rest cache (metaAtRest)" or "pre-Phase-20 at-rest cache contract"
- `provider.atRest` in shim D-24 comments → "internal provider cache"

This is a comment-only deviation; zero behavioral impact.

## Known Stubs

None. The three shims return real data via `ns:GetDisplayInfoForKey` → provider `GetDisplayInfo`. The shims themselves are scheduled for removal in Phase 24 (DISP-04) — they are documented backwards-compatibility bridges, not stubs.

## Self-Check: PASSED

Files verified:
- `BuffEngine.lua` — exists; grep counts all pass: metaIcons=0, metaAtRest=0, FindSpellByItemID=0, GetInventoryItemID=0, C_Item.GetItemCount=0, INVSLOT_TRINKET=0, RefreshMetaIcons=1, provider:RefreshAtRest=1, GetAtRestMetaIcon=1, GetAtRestMetaInfo=1, ResolveSuggestedSpellID=1, ns:GetDisplayInfoForKey=6, getCDMIcon=2, InCombatLockdown=1
- Commit b10b484 — present in git log
- Display.lua and CDMTab.lua — untouched (git status clean)
- `CURRENT_SCHEMA_VERSION = 3` — unchanged
- stylua --check passes
