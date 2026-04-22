---
phase: 20-getpreviewinfo-dispatch-helper
plan: "01"
subsystem: providers
tags: [providers, display-info, refactor, at-rest-cache, dispatch]
dependency_graph:
  requires: []
  provides:
    - "SpellProviderBaseMixin:GetDisplayInfo (no-op base)"
    - "SpellProviderBaseMixin:RefreshAtRest (no-op base)"
    - "TrinketProviderMixin:GetDisplayInfo — reads atRest cache, derives icon+label"
    - "TrinketProviderMixin:RefreshAtRest — inventory scan, writes {spellID, duration}"
    - "PotProviderMixin:GetDisplayInfo — reads atRest cache, derives icon+label"
    - "PotProviderMixin:RefreshAtRest — bag scan, writes {spellID, duration}"
    - "LustProviderMixin:GetDisplayInfo — class-aware fresh resolution"
    - "UserSpellProviderMixin:GetDisplayInfo — reads trackedBuffs entry"
    - "module-local FindSpellByItemID helper in Providers.lua"
    - "local keyToProvider dispatch table"
    - "ns:GetDisplayInfoForKey(key) export"
  affects:
    - "Plan 20-02 (BuffEngine thin-wrapper rewrite)"
    - "Plan 20-03 (backwards-compat shims)"
    - "Phases 21-23 (consumer migration)"
tech_stack:
  added: []
  patterns:
    - "Provider-owned at-rest cache: minimal {spellID, duration} — icon/label derived on-demand"
    - "Module-local keyToProvider table for O(1) string-key dispatch"
    - "Defensive InCombatLockdown() double-guard in RefreshAtRest (caller+callee)"
    - "Inventory APIs isolated to RefreshAtRest; never in GetDisplayInfo (PITFALL-5)"
key_files:
  modified:
    - path: Providers.lua
      changes: "Base mixin contract updated; GetDisplayInfo+RefreshAtRest on all 4 providers; atRest cache on Trinket/Pot; FindSpellByItemID relocated; keyToProvider+GetDisplayInfoForKey added"
decisions:
  - "D-01/D-02: Collapsed GetPreviewInfo+GetAtRestInfo into single GetDisplayInfo — one method, one contract, duration always present"
  - "D-13: Minimal at-rest cache {spellID, duration} only — icon/label are derivations via ns:GetSpellIcon and C_Spell.GetSpellInfo, not cached"
  - "D-12: FindSpellByItemID is module-local in Providers.lua (NOT exported on ns) — shared by TrinketProvider and PotProvider only"
  - "D-09/D-11: keyToProvider is module-local (not on ns); no OwnsKey method on base mixin"
metrics:
  duration_minutes: 20
  completed_date: "2026-04-21"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 1
---

# Phase 20 Plan 01: GetDisplayInfo + Dispatch Helper Summary

**One-liner:** Collapsed two-method provider display contract into unified GetDisplayInfo returning {icon, label, duration, spellID}; relocated FindSpellByItemID; added provider-owned atRest caches and ns:GetDisplayInfoForKey dispatch helper.

## What Was Built

Plan 20-01 extends `Providers.lua` with the full provider-side PROV-04 implementation:

1. **Base mixin contract updated** — `SpellProviderBaseMixin` now exposes exactly 4 methods: `GetEventInterests`, `OnTrigger`, `GetDisplayInfo` (no-op), `RefreshAtRest` (no-op). The old `GetPreviewInfo` and `GetAtRestInfo` methods are gone.

2. **Module-local `FindSpellByItemID`** added after the ns.* data exports — shared by TrinketProvider and PotProvider RefreshAtRest methods. Not exported on ns (D-12).

3. **All 4 providers implement `GetDisplayInfo`** returning `{ icon, label, duration, spellID }`:
   - `UserSpellProviderMixin:GetDisplayInfo` — reads `ns.db.trackedBuffs[key]`, returns real duration
   - `TrinketProviderMixin:GetDisplayInfo` — reads `self.atRest.{spellID,duration}` cache; first-call fallback to CSV entry 1
   - `PotProviderMixin:GetDisplayInfo` — same pattern using POT tables
   - `LustProviderMixin:GetDisplayInfo` — class-aware fresh resolution via `ns.CLASS_LUST_SPELL` / `ns.GetHunterLustSpell()`; duration=40 constant

4. **TrinketProvider and PotProvider own at-rest caches** (`mixin.atRest = { spellID = nil, duration = nil }`) written by their respective `RefreshAtRest` methods. Icon and label are NOT cached — derived on-demand in GetDisplayInfo.

5. **`ns:GetDisplayInfoForKey(key)`** exported using module-local `keyToProvider` table: string keys ("trinket"/"pot"/"lust") route O(1) via table; numeric keys route to UserSpellProvider. No OwnsKey method, no iteration.

## Commits

| Hash | Task | Description |
|------|------|-------------|
| f82da62 | Task 1 | rename base mixin to GetDisplayInfo+RefreshAtRest, add module-local FindSpellByItemID |
| 4b3da3d | Task 2 | implement GetDisplayInfo on all 4 providers, add atRest cache + RefreshAtRest on Trinket/Pot |
| df7a0e2 | Task 3 | add local keyToProvider dispatch table and ns:GetDisplayInfoForKey export |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All GetDisplayInfo implementations return real data (icon, label, duration, spellID). The atRest cache starts as `{ spellID = nil, duration = nil }` until `RefreshAtRest` is called, but GetDisplayInfo has a first-call fallback to CSV entry 1 so it never returns nil in normal operation. BuffEngine's `ns:RefreshMetaIcons` still calls the old path — the thin-wrapper migration is Plan 20-02.

## Self-Check: PASSED

Files verified:
- `Providers.lua` — exists and contains all 4 GetDisplayInfo, 2 RefreshAtRest, FindSpellByItemID, keyToProvider, GetDisplayInfoForKey
- Task commits f82da62, 4b3da3d, df7a0e2 — all present in git log
- `BuffEngine.lua` — untouched (git status clean)
- stylua --check passes
