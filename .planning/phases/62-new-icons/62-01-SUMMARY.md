---
phase: 62-new-icons
plan: 01
subsystem: cdm-tab-ui
tags: [icons, cdm-tab, side-tabs]
requires: []
provides:
  - "CDM tabs and dialog side tabs draw Media/Textures icons"
affects: [62-02]
key-files:
  modified: [CDMTab.lua]
requirements: [TAB-08, TAB-09]
metrics:
  tasks: 1
  files: 1
  completed: 2026-09-30
---

# Phase 62 Plan 01: New Icons in CDMTab.lua Summary

CDMTab.lua now points TBT Cooldowns/Buffs/Reminders tabs and the General/Advanced dialog side tabs at TBT's own BLP textures under Media/Textures, via plain SetTexture with the icon path passed as a parameter.

## What changed
- `ICON_PATH` removed; five file-level constants added (`TAB_ICON_COOLDOWN/BUFF/REMINDER`, `SIDE_TAB_INFO_ICON`, `SIDE_TAB_ADVANCED_ICON`).
- `SetUpTBTTab(tab, label, category, iconPath)`; SetChecked override kept, re-sets the same icon and still toggles SelectedTexture.
- `ns:CreateDialogSideTab(dialog, tooltipText, iconPath, iconSize, onSelect)` sets the texture at creation.
- Deleted the book icon, `GM-icon-settings` atlas, `Trade_Engineering` fallback, the `C_Texture.GetAtlasInfo` gate and `ns:SetAdvancedSideTabIcon`.
- TBT logo (TOC, Config.lua) untouched.

## Verification
Task gate printed GATE-OK (five texture files exist, stylua clean, CRLF preserved, aura-read gate pass). In-game checks deferred to Phase 66.

## Deviations from Plan
None - plan executed exactly as written. Edits were made through a scratchpad node script (CRLF-safe).

## Commits
- Task 1: see `git log` entry "feat(62-01): draw TBT's own icons on the CDM tabs and the dialog side tabs"

## Self-Check: PASSED
