---
phase: 23-cdmtab-lua-unification
plan: "02"
subsystem: CDMTab / Display / BuffEngine
tags: [cdmtab, tooltip, icon-resolution, suggested-keys, wave-2, disp-02]
dependency_graph:
  requires:
    - "23-01: ns:ShowBuffTooltip(frame, proc, opts) extended signature"
    - "23-01: ns.SUGGESTED_KEYS ordered list"
    - "Phase 20: ns:GetDisplayInfoForKey dispatch helper"
  provides:
    - "CDMTab.lua: all tile icons resolved via ns:GetDisplayInfoForKey (zero shim calls)"
    - "CDMTab.lua: tile tooltip via ns:ShowBuffTooltip(self, proc, opts) with opts (D-04)"
    - "CDMTab.lua: META_DESCRIPTIONS file-level local (D-06/D-07)"
    - "CDMTab.lua: SUGGESTED_KEYS consumed at all 4 former SUGGESTED_BUFFS reader sites (D-12)"
  affects:
    - CDMTab.lua (primary target)
    - Providers.lua (Plan 23-03 demotes CLASS_LUST_SPELL/GetHunterLustSpell after closures gone)
tech_stack:
  added: []
  patterns:
    - "Inline ns:GetDisplayInfoForKey one-liner at each icon resolution site (D-16)"
    - "proc table constructed on-the-fly from ns:GetDisplayInfoForKey result for ShowBuffTooltip"
    - "File-level META_DESCRIPTIONS table read inside OnEnter (not declared there)"
key_files:
  created: []
  modified:
    - CDMTab.lua
decisions:
  - "D-04: CDMTab tile OnEnter calls ns:ShowBuffTooltip(self, proc, opts) with opts populated"
  - "D-06: META_DESCRIPTIONS promoted to file-level local (not inside OnEnter closure)"
  - "D-07: META_DESCRIPTIONS[key] passed as opts.extraLines to ShowBuffTooltip"
  - "D-11: metaBuff field dropped from new trackedBuffs entries (never used as gate)"
  - "D-12: All 4 SUGGESTED_BUFFS reader sites migrated to SUGGESTED_KEYS + GetDisplayInfoForKey"
  - "D-13: item.suggestedIndex holds index into ns.SUGGESTED_KEYS (same semantics, new source)"
  - "D-15: All 3 type-string resolution chains collapsed to inline GetDisplayInfoForKey calls"
  - "D-16: No helper extracted — one-liner inline at each site"
  - "D-17: iconFrame.spellID / self.spellID field naming preserved (no .key rename yet)"
  - "D-29: Drag/drop/reorder/right-click/Add dialog structurally unchanged"
metrics:
  duration_minutes: 20
  completed_date: "2026-04-22"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 1
---

# Phase 23 Plan 02: CDMTab.lua Icon/Tooltip Resolution Unification Summary

**One-liner:** Collapsed all 3 parallel type-string resolution chains and migrated all 4 SUGGESTED_BUFFS reader sites in CDMTab.lua to use `ns:GetDisplayInfoForKey` + `ns:ShowBuffTooltip(frame, proc, opts)`; promoted META_DESCRIPTIONS to file-level local.

## What Was Done

### Task 1 — META_DESCRIPTIONS promoted + tile OnEnter rewritten + 3 of 4 SUGGESTED_BUFFS readers migrated

**Step 1: META_DESCRIPTIONS promoted (D-06/D-07)**

Added `local META_DESCRIPTIONS = { trinket = ..., pot = ..., lust = ... }` immediately after `local ICON_PATH` at the top of CDMTab.lua (line 11). Removed the duplicate declaration inside the OnEnter closure.

**Step 2: Tile OnEnter rewritten (D-04/D-15 Site 1)**

Replaced the old handler (META_DESCRIPTIONS closure local + isMetaString + GetAtRestMetaInfo + ResolveSuggestedSpellID + SUGGESTED_BUFFS lookup + direct GameTooltip AddLine calls) with the new handler:
- `ns:GetDisplayInfoForKey(self.spellID)` for all resolution
- Constructs a `proc` table from `info.spellID`, `info.label`, resolved duration
- Calls `ns:ShowBuffTooltip(self, proc, { showSpellID=..., showDuration=..., extraLines=... })`
- Falls back to bare tooltip for numeric spells with no provider entry

**Step 3: Right-click menu SUGGESTED_BUFFS reader migrated (D-12)**

The `addSuggestedToSection` function's loop replaced: `for _, suggested in ipairs(ns.SUGGESTED_BUFFS)` → `for _, suggestedKey in ipairs(ns.SUGGESTED_KEYS)`. Uses `ns:GetDisplayInfoForKey(suggestedKey)` for label/duration. Drops `metaBuff` field (D-11).

**Step 4: EndDrag copy-on-drag SUGGESTED_BUFFS reader migrated (D-12)**

Same replacement in the `EndDrag` not-yet-tracked branch: iterates `ns.SUGGESTED_KEYS` + `GetDisplayInfoForKey`. Drops `metaBuff` field.

### Task 2 — Drag ghost icon + section rebuild collapsed (Sites 2 & 3)

**Site 2: BeginDrag ghost icon (D-15 Site 2)**

Replaced the `if type(iconFrame.spellID) == "string" then ... GetAtRestMetaIcon ... ResolveSuggestedSpellID ... else ... GetSpellIcon ... end` block with:
```lua
local ghostInfo = ns:GetDisplayInfoForKey(iconFrame.spellID)
local ghostIconID = (ghostInfo and ghostInfo.icon) or ns:GetSpellIcon(iconFrame.spellID) or 134400
```

**Site 3a: Section rebuild Suggested loop (D-12/D-13)**

Replaced `for i, suggested in ipairs(ns.SUGGESTED_BUFFS)` with `for i, suggestedKey in ipairs(ns.SUGGESTED_KEYS)`. Uses `ns:GetDisplayInfoForKey(suggestedKey).icon` for tile icon. `item.suggestedIndex = i` now indexes into SUGGESTED_KEYS (D-13).

**Site 3b: Section rebuild per-entry icon (D-15 Site 3)**

Replaced `if type(info.spellID) == "string" then ... GetAtRestMetaIcon ... ResolveSuggestedSpellID ... else ... GetSpellIcon ... end` with:
```lua
local displayInfo = ns:GetDisplayInfoForKey(info.spellID)
local iconID = (displayInfo and displayInfo.icon) or ns:GetSpellIcon(info.spellID) or 134400
```

## Acceptance Criteria Verification

| Check | Result |
|---|---|
| `ns.SUGGESTED_BUFFS` — 0 matches in CDMTab.lua | PASS (count=0) |
| `ns:GetAtRestMetaIcon\|ns:GetAtRestMetaInfo\|ns:ResolveSuggestedSpellID` — 0 matches | PASS (count=0) |
| `type(.*spellID) == "string"` — 0 matches | PASS (count=0) |
| `ns:GetDisplayInfoForKey` — 6 matches (>=5 required) | PASS |
| `^local META_DESCRIPTIONS` — 1 match at file level | PASS (line 11) |
| `META_DESCRIPTIONS` — 2 total matches (declaration + 1 read) | PASS (lines 11, 111) |
| `metaBuff` — 0 matches | PASS |
| `stylua --check CDMTab.lua` exits 0 | PASS |
| Core.lua UNTOUCHED | PASS (git diff confirms) |
| Display.lua UNTOUCHED | PASS (git diff confirms) |
| BuffEngine.lua UNTOUCHED | PASS (git diff confirms) |
| Providers.lua UNTOUCHED | PASS (git diff confirms) |

## Decision IDs Implemented

D-04, D-06, D-07, D-11, D-12, D-13, D-15, D-16, D-17, D-29

## Commits

| Task | Commit | Message |
|---|---|---|
| Task 1 | 76d81be | feat(23-02): promote META_DESCRIPTIONS, rewrite tile OnEnter, migrate 3 of 4 SUGGESTED_BUFFS readers |
| Task 2 | 6b5bdbb | feat(23-02): collapse drag ghost + section rebuild resolution chains, migrate final SUGGESTED_BUFFS reader |

## Deviations from Plan

None — plan executed exactly as written.

## Notes for Plan 23-03

CDMTab.lua now has zero shim calls and zero SUGGESTED_BUFFS references. The shim functions themselves (`ns:GetAtRestMetaInfo`, `ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`) still exist in Providers.lua. Plan 23-03 demotes `ns.CLASS_LUST_SPELL` and `ns.GetHunterLustSpell` to Providers.lua module-local (D-18/D-19/D-20/D-21) — unblocked now that the SUGGESTED_BUFFS closures that read them are deleted.

Plan 23-04 is deploy + human-verify.

## Known Stubs

None.

## Self-Check: PASSED

- CDMTab.lua modified and committed: 76d81be + 6b5bdbb confirmed
- SUMMARY.md written to `.planning/phases/23-cdmtab-lua-unification/23-02-SUMMARY.md`
- All grep checks verified in terminal before commit
