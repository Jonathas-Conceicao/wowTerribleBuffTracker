---
phase: 62-new-icons
verified: 2026-09-30T00:00:00Z
status: human_needed
score: 9/9 must-haves verified in source (in-game appearance deferred to Phase 66)
overrides_applied: 0
human_verification:
  - test: "Restart the WoW client fully, open the CDM settings window, select each TBT tab; open the tracker dialog and switch General/Advanced"
    expected: "TBT Cooldowns/Buffs/Reminders show icon_cooldown/icon_buff/icon_reminder at 30x30 and keep the icon when selected; General/Advanced side tabs show icon_info/icon_advanced; no green/missing squares"
    why_human: "Texture rendering and selected/hover states are only observable in game (deferred to Phase 66 by design)"
  - test: "Inspect a packaged release zip (or BigWigs packager dry run)"
    expected: "Contains Media/Textures/*.blp, does not contain Media/Source"
    why_human: "Packager not run locally; verified only by .pkgmeta contents and release.yml enumerating no files"
---

# Phase 62: New Icons Verification Report

**Phase Goal:** TBT's tabs draw TBT's own icons, and those textures reach every client and every release.
**Status:** human_needed (no gaps; only game-visible checks remain)
**Re-verification:** No, initial

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | CDM tabs draw icon_cooldown/buff/reminder at 30x30, SetChecked override keeps icon, SelectedTexture toggles | VERIFIED | CDMTab.lua:3391-3404 `SetUpTBTTab(..., iconPath)`, `SetSize(30,30)`, override sets `iconPath` and toggles SelectedTexture; calls at 3432-3434 pass TAB_ICON_COOLDOWN/BUFF/REMINDER |
| 2 | Dialog General/Advanced side tabs draw icon_info/icon_advanced | VERIFIED | CDMTab.lua:2555-2559 `CreateDialogSideTab(dialog, tooltipText, iconPath, ...)` with `SetTexture(iconPath)`; callers 2831/2833 |
| 3 | Old book/GM-icon/Trade_Engineering/atlas gate/SetAdvancedSideTabIcon/ICON_PATH gone | VERIFIED | grep of those tokens in CDMTab.lua returns nothing |
| 4 | TBT logo unchanged | VERIFIED | `git diff 15ae927 -- Config.lua TerribleBuffTracker.toc tbt_icon_64x64.blp` empty; TOC IconTexture and Config.lua:186 still use tbt_icon_64x64; CDMTab.lua does not reference it |
| 5 | BLPs, PNGs, png2blp.js committed with right eol | VERIFIED | `git ls-files --eol`: 10 media files `i/-text`, png2blp.js `i/lf` |
| 6 | png2blp.js rebuilds all BLPs byte-identically (final, post-review state) | VERIFIED | Deleted BLPs in a scratchpad copy, re-ran the converter, `cmp` identical for all 5; `node --check` OK |
| 7 | Zip ships Media/Textures, not Media/Source | VERIFIED (source) | .pkgmeta has `  - Media/Source`; nothing ignores Media, Media/Textures or *.blp (only `"*.png"`, which does not match .blp); release.yml has no file list |
| 8 | install deploys every Media/Textures blp to every client, byte-identical | VERIFIED | Read-only inspection of _retail_, _ptr_, _beta_, _classic_beta_ deployed folders: all 5 BLPs `cmp` identical; only `Media/Textures` exists (no Media/Source). install.ps1:62-89 adds the fourth file-set source using `Substring($source.Length).TrimStart('\')`, the same form as the prune loop at 137 |
| 9 | Texture removed from repo is pruned next install | VERIFIED (code) | Prune loop (136-143) removes any file not in `$files`; texture entries are in the same backslash form. SUMMARY reports a probe run; I did not re-run install (instructed not to) |

**Score:** 9/9

## Requirements Coverage

| Requirement | Plan | Status | Evidence |
|---|---|---|---|
| TAB-08 | 62-01 | SATISFIED (source) | Truth 1 |
| TAB-09 | 62-01 | SATISFIED (source) | Truth 2, 3 |
| INST-10 | 62-02 | SATISFIED | Truths 8, 9 |
| DIST-13 | 62-02 | SATISFIED (source) | Truths 5-7 |

No orphaned requirements: REQUIREMENTS.md maps exactly these four to Phase 62. (Checkboxes and the traceability table still read Pending/unchecked; that is bookkeeping for the orchestrator, not a code gap.)

## Post-review state

Review fixes (99e483c, b441cfb, c4f0d67, cbddcd7) are in place. install.ps1 now also warns on untracked textures (harmless, git failure is swallowed and skipped); the missing-file message no longer blames the TOC. No debt markers found in the reviewed changes. Unfixed IN-02 (empty dirs not pruned) and IN-03 (converter edge cases) are non-goal robustness notes, not blockers.

## Anti-Patterns

None blocking. Note that the untracked `ReminderClick.lua` in the tree belongs to Phase 63.

## Gaps Summary

No gaps. Remaining items are in-game visual confirmation (Phase 66) and an actual packaged-zip check.
