---
phase: 23-cdmtab-lua-unification
plan: "01"
subsystem: Display / BuffEngine
tags: [tooltip, suggested-keys, api-surface, wave-1]
dependency_graph:
  requires: []
  provides:
    - "ns:ShowBuffTooltip(frame, proc, opts) — extended signature (D-01/D-02)"
    - "ns.SUGGESTED_KEYS = { lust, trinket, pot } — ordered key list (D-10)"
  affects:
    - CDMTab.lua (Plan 23-02 consumes SUGGESTED_KEYS and extended tooltip)
    - Providers.lua (Plan 23-03 demotes CLASS_LUST_SPELL/GetHunterLustSpell after closures gone)
tech_stack:
  added: []
  patterns:
    - "Optional opts table pattern for backward-compatible API extension"
    - "Ordered key list replacing closure-heavy table"
key_files:
  created: []
  modified:
    - Display.lua
    - BuffEngine.lua
decisions:
  - "D-01: Extended ns:ShowBuffTooltip to (frame, proc, opts)"
  - "D-02: opts.showSpellID / opts.showDuration / opts.extraLines all handled"
  - "D-03/D-22: Bar/icon OnEnter call sites pass 2 args (nil opts) — unchanged"
  - "D-05: nil opts falls through cleanly — current Display behavior preserved"
  - "D-09: ns.SUGGESTED_BUFFS table deleted from BuffEngine.lua"
  - "D-10: ns.SUGGESTED_KEYS = { lust, trinket, pot } replaces it"
  - "D-11: All getCDMSpellID / getCDMIcon closures and metaBuff flags deleted"
metrics:
  duration_minutes: 15
  completed_date: "2026-04-22"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 2
---

# Phase 23 Plan 01: API Surface Preparation Summary

**One-liner:** Extended `ns:ShowBuffTooltip` with backward-compatible `opts` table and replaced `ns.SUGGESTED_BUFFS` closure table with `ns.SUGGESTED_KEYS = { "lust", "trinket", "pot" }` ordered list.

## What Was Done

### Task 1 — Display.lua: Extended ns:ShowBuffTooltip (D-01/D-02/D-03/D-05/D-22)

Signature extended from `(frame, proc)` to `(frame, proc, opts)`. When `opts` is nil the function behaves exactly as in Phase 22 (D-05). When opts is provided:

- `opts.showSpellID` — appends "Spell ID: N" line in gray (0.8, 0.8, 0.8)
- `opts.showDuration` — appends "TBT Duration: Xs" line in gray
- `opts.extraLines` — appends each string in gray (0.5, 0.5, 0.5) at the bottom

The fallback `SetText` now uses `(proc and proc.label) or "Unknown"` — minor improvement for label-bearing procs without a numeric spellID.

Bar OnEnter (line 193) and icon OnEnter (line 242) still call `ns:ShowBuffTooltip(self, self.proc)` — two args, nil opts, D-22 preserved.

### Task 2 — BuffEngine.lua: SUGGESTED_BUFFS → SUGGESTED_KEYS (D-09/D-10/D-11)

Deleted the entire `ns.SUGGESTED_BUFFS` block (~45 lines):
- lust entry with `getCDMSpellID` closure reading `ns.CLASS_LUST_SPELL` / `ns.GetHunterLustSpell`
- trinket entry with `getCDMSpellID` (returns nil) + `getCDMIcon` closure
- pot entry with same closure pattern as trinket

Replaced with:
```lua
-- Ordered list of meta-buff keys for CDM tab Suggested section.
-- Per-key display data (icon, label, duration, spellID) comes from ns:GetDisplayInfoForKey;
-- description text is CDMTab-local (META_DESCRIPTIONS in CDMTab.lua).
-- D-09 / D-10 / D-11 (Phase 23): replaces ns.SUGGESTED_BUFFS table of closures.
ns.SUGGESTED_KEYS = { "lust", "trinket", "pot" }
```

Updated line-17 note comment: `CLASS_LUST_SPELL` / `GetHunterLustSpell` still on `ns.*` pending Plan 23-03 demotion (D-20 grep-gate).

## Acceptance Criteria Verification

| Check | Result |
|---|---|
| `function ns:ShowBuffTooltip(frame, proc, opts)` — 1 match in Display.lua | PASS (line 73) |
| `ns:ShowBuffTooltip(self, self.proc)` — exactly 2 matches | PASS (lines 193, 242) |
| `opts.showSpellID`, `opts.showDuration`, `opts.extraLines` present | PASS |
| `stylua --check Display.lua` exits 0 | PASS |
| `ns.SUGGESTED_BUFFS` — 0 table definitions/assignments in BuffEngine.lua | PASS (comment only) |
| `ns.SUGGESTED_KEYS = { "lust", "trinket", "pot" }` present | PASS (line 60) |
| `getCDMSpellID`, `getCDMIcon`, `metaBuff` — 0 matches in BuffEngine.lua | PASS |
| `ns.GetHunterLustSpell`, `ns.CLASS_LUST_SPELL` — 0 matches in BuffEngine.lua | PASS |
| `stylua --check BuffEngine.lua` exits 0 | PASS |
| CDMTab.lua UNTOUCHED | PASS |
| Providers.lua UNTOUCHED | PASS |
| Core.lua UNTOUCHED | PASS |

## Commits

| Task | Commit | Message |
|---|---|---|
| Task 1 | e28fa7f | feat(23-01): extend ns:ShowBuffTooltip with optional opts param (D-01/D-02/D-03) |
| Task 2 | 4e3c4fb | feat(23-01): replace ns.SUGGESTED_BUFFS with ns.SUGGESTED_KEYS in BuffEngine.lua (D-09/D-10/D-11) |

## Deviations from Plan

None — plan executed exactly as written.

## Notes for Plan 23-02

CDMTab.lua still references `ns.SUGGESTED_BUFFS` at 4 reader sites (lines 105, 160, 549, 749). Plan 23-02 migrates those to `ns.SUGGESTED_KEYS` + `ns:GetDisplayInfoForKey`. CDMTab.lua also has 3 resolution chain sites (tile tooltip, drag ghost icon, section rebuild) that will be collapsed in Plan 23-02 using the extended `ns:ShowBuffTooltip(frame, info, opts)` signature established here.

## Known Stubs

None.

## Self-Check: PASSED

- Display.lua modified and committed: e28fa7f confirmed
- BuffEngine.lua modified and committed: 4e3c4fb confirmed
- SUMMARY.md written to `.planning/phases/23-cdmtab-lua-unification/23-01-SUMMARY.md`
