---
phase: 36-user-containers
plan: 05
subsystem: display/settings
tags: [icon-layout, edit-mode, cdm-copy]
dependency-graph:
  requires: [36-01, 36-02, 36-03]
  provides: [itemsPerRow-per-container-setting, icon-grid-wrapping]
  affects: [Core.lua, Display.lua, EditModeFrames.lua]
tech-stack:
  added: []
  patterns:
    - "major/minor axis grid arithmetic (modulo + floor-division) in place of a single unbounded offset"
key-files:
  created: []
  modified:
    - Core.lua
    - Display.lua
    - EditModeFrames.lua
decisions:
  - "itemsPerRow defaults to 12, documented as the highest of Blizzard's three factory IconLimit presets (Essential 12, Utility 7, BuffIcon 1), NOT a claim of matching the CDM"
  - "icon-kind only; RenderBarContainer and the bar-kind settings branch are untouched, per CONT-06 and the phase's own reasoning that CDM bar viewers are single-column by design"
metrics:
  duration: "~25 min"
  completed: 2026-09-21
---

# Phase 36 Plan 05: Per-Container Items Per Row Summary

Icon-kind containers (buffs, essential, utility, and any user-created icon container) now carry a
per-container `itemsPerRow` setting that wraps the icon grid onto multiple rows or columns instead of
laying out a single unbounded line, closing the gap that made CONT-06's success criterion 3
unverifiable.

## What Was Built

**Core.lua** — `ns.EnsureContainerSettings` gained `itemsPerRow = 12` in the non-bar side of the
defaults constructor, plus an idempotent backfill (`if def.kind ~= "bar" and cs.itemsPerRow == nil
then cs.itemsPerRow = 12 end`) in the same shape as the existing `hideWhenInactive`/`showTimer`
backfills. No `schemaVersion` bump; `BuffEngine.lua` untouched.

**Display.lua** — `RefreshContainerSettings`'s icon branch caches `dst.itemsPerRow = math.max(1,
src.itemsPerRow or 12)`, floor-guarded against a zero/negative value reaching the render loop.
`RenderIconContainer` replaced its single `(slotIndex - 1) * step` offset with two-axis arithmetic:
`major = ((slotIndex - 1) % perRow) * step` and `minor = math.floor((slotIndex - 1) / perRow) *
step`. All four orientation/direction anchor branches were rewritten to apply major along the flow
axis and minor along the wrap axis (horizontal wraps downward, vertical wraps rightward, matching
`GridLayoutFrame`'s defaults already used by the CDM tab's own grids). The container-sizing block at
the end now derives `majorCount`/`minorCount` from `perRow` and sizes the frame to the actual grid
shape instead of one flat run. `RenderBarContainer` was not touched.

**EditModeFrames.lua** — an `AddSlider("Items Per Row", "itemsPerRow", 1, 20, 1, ShowAsInteger)` was
inserted into the icon-kind branch of `ns:ShowSettingsPopup`, immediately after Icon Padding, using
the slider template's existing per-container write-through (`ns.db.containerSettings[key][settingKey]`
→ `RefreshContainerSettings()` → `UpdateDisplay()`). The Copy Blizzard CDM Config button's `OnClick`
gained an icon-kind `else` branch mirroring the existing bar-kind block: `if S.IconLimit then
cs.itemsPerRow = viewer:GetSettingValue(S.IconLimit) or cs.itemsPerRow end`, guarded on `S.IconLimit`
existing exactly as `S.BarContent` already is.

## Deviations from Plan

None — plan executed exactly as written, including the pre-applied correction that `12` is described
as "the highest of Blizzard's three factory IconLimit presets," never as "matching the CDM."

One acceptance-criteria command in Task 2 did not literally match, and per the plan's own testing-reality
guidance this was verified rather than bent to fit:
- `grep -n 'math.ceil(n / perRow)' Display.lua` — no match, because the container-sizing block reuses
  the pre-existing `visibleCount` variable (already `local visibleCount = #slots` at that exact spot in
  the original code) rather than introducing a second variable named `n` for the same value. The
  literal-text grep in Task 2's acceptance list assumed variable name `n`; the actual code shape —
  `local majorCount = math.min(visibleCount, perRow)` and `local minorCount =
  math.ceil(visibleCount / perRow)` — is functionally identical to the plan's described maths. Confirmed
  by reading the block directly (Display.lua:747-750).

## Self-Check: PASSED

- `grep -c 'itemsPerRow' Core.lua` → `3` (matches plan)
- `sed -n '/^function ns.EnsureContainerSettings/,/^end$/p' Core.lua | grep -c 'itemsPerRow'` → `3`
  (same as whole-file count — single definition site)
- `grep -c 'CURRENT_SCHEMA_VERSION = 4' BuffEngine.lua` → `1` (unchanged)
- `grep -c 'dst.itemsPerRow' Display.lua` → `1`, inside `RefreshContainerSettings`'s icon branch
- `sed -n '/^local function RenderIconContainer/,/^end$/p' Display.lua | grep -c 'perRow'` → `6`
  (at least 5, satisfied)
- `sed -n '/^local function RenderIconContainer/,/^end$/p' Display.lua | grep -c '(slotIndex - 1) \* step'`
  → `0` (single-axis offset gone)
- `sed -n '/^local function RenderBarContainer/,$p' Display.lua | grep -c '{}'` → `0`
- `sed -n '/^local function RenderIconContainer/,/^end$/p' Display.lua | grep -c 'function('` → `0`
  (no per-tick closure)
- `grep -c '"Items Per Row"' EditModeFrames.lua` → `1`
- `sed -n '/kind == "bar" then/,/^\telse$/p' EditModeFrames.lua | grep -c 'Items Per Row'` → `0`
  (not in the bar branch)
- `grep -n 'S.IconLimit' EditModeFrames.lua` → matches, guarded by `if S.IconLimit then`
- `stylua --check .` → exit `0`
- `git diff --stat b804809 HEAD -- Core.lua Display.lua EditModeFrames.lua` → only these three files
  touched across the whole plan
- `git diff b804809 HEAD -- Display.lua | grep -c '^@@.*RenderBarContainer'` → `0` — zero diff hunks
  land inside `RenderBarContainer`, confirming bar-kind layout is byte-for-byte unchanged
- Commits `e744b4b`, `9a6308a`, `6156b7f` all found in `git log --oneline`
- `./scripts/install.bat` ran clean, deployed `v0.3.0-50-g6156b7f-dev` to all four detected client
  folders

No missing items.
