---
phase: 22-display-lua-unification
plan: 01
subsystem: Providers + BuffEngine
tags: [proc-shape, cancellation, aliveBuffs, provider-cleanup]
dependency_graph:
  requires: [21-02]
  provides: [22-02]
  affects: [Providers.lua, BuffEngine.lua]
tech_stack:
  added: []
  patterns: [aliveBuffs data-driven cancellation, SHARED_LUST_BUFFS_LOCAL module-local]
key_files:
  created: []
  modified:
    - Providers.lua
    - BuffEngine.lua
decisions:
  - "proc.spellID is always numeric after Phase 22 (D-03) — no string coexistence remains"
  - "aliveBuffs field drives cancellation; strategy baked into proc at creation (D-09/D-10)"
  - "SHARED_LUST_BUFFS demoted to Providers.lua module-local SHARED_LUST_BUFFS_LOCAL (D-12)"
  - "Preview procs carry no icon field — Display derives icon from proc.spellID (D-32/D-33)"
metrics:
  duration: "~3 minutes"
  completed: "2026-04-21T21:40:46Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 22 Plan 01: Proc Shape Normalization + Unified Cancellation Summary

Collapse castSpellID/lustBuffID/string-spellID coexistence into a single numeric proc.spellID, add unified proc.aliveBuffs cancellation list that eliminates the two-branch scan, drop icon/source fields from procs, and demote SHARED_LUST_BUFFS to a Providers-local.

## What Was Done

### Task 1: Providers.lua — 4 OnTrigger methods + SHARED_LUST_BUFFS demotion

**Proc shape before → after (11 fields → 9 fields):**

| Field          | Before (v0.2.3)                        | After (Phase 22)                              |
|----------------|----------------------------------------|-----------------------------------------------|
| `key`          | spellID / "trinket" / "pot" / "lust"  | UNCHANGED                                     |
| `spellID`      | numeric OR `"lust"` string             | ALWAYS numeric (D-03)                         |
| `duration`     | number                                 | UNCHANGED                                     |
| `expiresAt`    | number                                 | UNCHANGED                                     |
| `startedAt`    | number                                 | UNCHANGED                                     |
| `section`      | string                                 | UNCHANGED                                     |
| `layoutOrder`  | number                                 | UNCHANGED                                     |
| `label`        | string                                 | UNCHANGED                                     |
| `aliveBuffs`   | (absent)                               | ADDED — `{ spellID }` for User/Trinket/Pot; `SHARED_LUST_BUFFS_LOCAL[lustSpellID]` for Lust |
| `icon`         | number (texture ID)                    | REMOVED (D-02/D-35 — Display derives it)     |
| `source`       | `"cast"` or `"debuff"`                 | REMOVED (D-02 — no longer needed)             |
| `castSpellID`  | numeric (redundant with spellID)       | REMOVED (D-02)                                |
| `lustBuffID`   | numeric (lust-specific)                | REMOVED (D-02 — replaced by aliveBuffs)       |

Per-provider aliveBuffs content (D-04 to D-07):
- UserSpellProvider: `{ spellID }` — single element, the user's tracked spell
- TrinketProvider: `{ spellID }` — single element, the cast trinket's spell
- PotProvider: `{ spellID }` — single element, the cast pot's spell
- LustProvider: `SHARED_LUST_BUFFS_LOCAL[lustSpellID] or { lustSpellID }` — multi-element for lust group (e.g., `{ 32182, 1243972 }` for Heroism + Drums)

**SHARED_LUST_BUFFS demotion (D-12):**
- Was: `ns.SHARED_LUST_BUFFS = { ... }` — exported on namespace, read by BuffEngine
- Now: `local SHARED_LUST_BUFFS_LOCAL = { ... }` — module-local in Providers.lua, read only by LustProvider:OnTrigger at proc creation time

### Task 2: BuffEngine.lua — Cancellation scan + preview proc update

**ScanActiveTimersForCancellation diff (two-branch → single-branch):**

Before (~68 lines):
```
for spellID, timer in pairs(ns.activeTimers) do
    local shouldCancel = false
    if timer.source == "cast" then
        local lookupID = timer.castSpellID or spellID
        -- single aura check
        shouldCancel = aura == nil
    elseif timer.source == "debuff" and timer.lustBuffID then
        local buffsToCheck = ns.SHARED_LUST_BUFFS[timer.lustBuffID]
        -- multi-check loop OR fallback direct check
        shouldCancel = not anyPresent
    end
    if shouldCancel then ns.activeTimers[spellID] = nil ... end
end
```

After (~35 lines, D-09 exact code):
```
for key, timer in pairs(ns.activeTimers) do
    if timer.aliveBuffs and #timer.aliveBuffs > 0 then
        -- single loop, no source branching
        if not anyPresent then ns.activeTimers[key] = nil ... end
    end
    -- No aliveBuffs = opaque, skip (defensive D-11)
end
```

Removed from scan: `timer.source`, `timer.castSpellID`, `timer.lustBuffID`, `ns.SHARED_LUST_BUFFS` lookup.

**StartAllPreviewTimers update:**
- Removed `icon = info.icon` line from preview proc table (D-32/D-33)
- `wipe(ns.previewTimers)` preserved (PITFALL-7 GC discipline)
- `ns:GetDisplayInfoForKey(key)` call preserved

## Downstream Impact

Display.lua is now STALE — it still reads `timer.icon` (which no longer exists on procs). Plan 22-02 fixes Display. Do NOT run the game between these plans — this is an intentional transient intermediate state within the same phase. The two plans are sequential and designed to be landed together.

## Deviations from Plan

None — plan executed exactly as written. Comment updates to the base mixin (`SpellProviderBaseMixin:OnTrigger`) and TrinketProvider/PotProvider class headers were done to remove stale `castSpellID`/`lustBuffID` references from comments (defensive cleanup, not functional changes).

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | d69dc0d | feat(22-01): normalize all 4 provider OnTrigger methods to 9-field proc shape |
| 2 | 572ca1e | feat(22-01): unified cancellation scan + icon-free preview procs in BuffEngine |

## Self-Check: PASSED

- Providers.lua passes `stylua --check`: verified
- BuffEngine.lua passes `stylua --check`: verified
- Zero `castSpellID` in Providers.lua or BuffEngine.lua: verified (grep = 0)
- Zero `lustBuffID` in Providers.lua or BuffEngine.lua: verified (grep = 0)
- Zero `ns.SHARED_LUST_BUFFS` in any .lua file: verified (grep = 0)
- `local SHARED_LUST_BUFFS_LOCAL` present in Providers.lua: verified
- `aliveBuffs` hits in Providers.lua >= 4: verified (8 hits)
- `timer.aliveBuffs` in BuffEngine.lua: verified (2 hits — guard + loop)
- `if timer.aliveBuffs and #timer.aliveBuffs > 0` defensive guard: verified
- `wipe(ns.previewTimers)` preserved: verified (2 hits)
- `C_Secrets.ShouldAurasBeSecret` preserved: verified (2 hits)
- `ns:DispatchEventToProviders` preserved: verified (2 hits)
- `CURRENT_SCHEMA_VERSION = 3`: verified
- `ns.CLASS_LUST_SPELL`, `ns.GetHunterLustSpell`, `ns.SATED_DEBUFF_TO_LUST` still exported: verified
- `ns.providers = { TrinketProvider, PotProvider, LustProvider, UserSpellProvider }`: verified
- Core.lua, CDMTab.lua, Display.lua untouched: verified (git diff empty)
