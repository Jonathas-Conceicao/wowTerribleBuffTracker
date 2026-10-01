---
phase: 61-bug-fixes
plan: 01
subsystem: edit-mode
tags: [edit-mode, taint, EDM-08]
requires: []
provides:
  - "ns:SelectContainer with no Blizzard Edit Mode method call"
affects: [63]
key-files:
  modified: [EditModeFrames.lua]
decisions:
  - "999.9: delete the clear-selection call with no replacement; accept Blizzard highlight lingering"
requirements-completed: [EDM-08]
completed: 2026-09-30
---

# Phase 61 Plan 01: Edit Mode taint fix Summary

Deleted the pcall'd `EditModeManagerFrame.ClearSelectedSystem` call from `ns:SelectContainer`, replaced by an explanatory comment (999.9); selection, overlay and popup behaviour unchanged.

## Tasks

1. Delete the call and rewrite the idempotency comment. Commit 56fee40.
2. Scan, stylua, aura gate, deploy. No source change (no class (a) hit found).

## Edit Mode reference scan (999.9)

| file:line | Expression | Class | Reason |
|---|---|---|---|
| Config.lua:410,415 | `ShowUIPanel(EditModeManagerFrame)` in pcall | (b) | Global panel function taking the frame, not a mixin method |
| MergeMode.lua:1302 | `EditModeManagerFrame:IsShown()` | (b) | Plain widget getter |
| EditModeFrames.lua:671,679 | `owner = EditModeManagerFrame`, `owner:GetFrameLevel()` | (b) | Plain widget getter |
| EditModeFrames.lua:729,735 | `self.owner:IsShown()` | (b) | Plain widget getter |
| EditModeFrames.lua:741 | `SetPoint("TOPLEFT", self.owner, ...)` on TBT's own panel | (b) | Anchor target only |
| EditModeFrames.lua:156, 199, 634, 660, 728 | mentions of EditModeSystemMixin / dialog / manager | (c) | Comments |
| Core.lua:30 | `Enum.EditModeSystem.CooldownViewer` | (c) | Comment |
| MergeMode.lua:12, 1892-2148 | EditModeSystem(Mixin/Template) mentions | (c) | Comments |

No class (a) hit remains. Nothing else changed.

## Verification

- Task 1 gate: pass. `stylua --check`: pass. `node scripts/aura-read-gate.js`: AURA-READ GATE PASS (10 reads in 3 readers).
- `git ls-files --eol EditModeFrames.lua`: w/crlf.
- `./scripts/install.bat` deployed to retail, ptr, beta, classic_beta.
- In-game checks deferred to Phase 66.

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED
