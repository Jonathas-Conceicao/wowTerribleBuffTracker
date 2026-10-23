---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
plan: 03
subsystem: merge-mode
tags: [merge-mode, deletion, aura-read-gate, cdm]
requires: [70-01]
provides:
  - MergeMode.lua with no aura read and no engine aura container
  - aura-read-gate with ns:ReadPlayerAura as its only allowlisted reader
affects: [70-04 diagnostics trim]
key-files:
  modified: [MergeMode.lua, scripts/aura-read-gate.js]
decisions:
  - "Tracked Buffs publishes its whole configured set (publishWhole); each entry's cdmShown stamp says which ones Blizzard draws"
requirements: [STEAL-19, STEAL-21, STEAL-22]
metrics:
  completed: 2026-10-10
---

# Phase 70 Plan 03: Engine aura containers and merged aura reads removed Summary

MergeMode.lua lost about 1560 lines: the merged aura timing and pandemic/dispel reads, and the whole engine aura container layer. TBT now reads no aura in Merge Mode and creates no aura object, so the target lookup (999.22/999.23) and the unfiltered engine slot (999.24) no longer exist.

## Commits

- f093158: Task 1, merged aura timing and pandemic/dispel reads deleted, gate allowlist row dropped
- 48f1415: Task 2, engine aura containers, filters, placement, target refresh and their diagnostics deleted

## What changed

- ns:RefreshMergeShownSlots reads only CDM item-frame shown flags: `publishWhole` replaces `engineOwns`, `cdmFrameVisible = not previewing or ...`, publish body is `shown[#shown + 1] = entry`.
- Survivors kept: `editModeOpen` (declared above ns:IsMergePreviewState and the EventRegistry callbacks), ns:IsMergePreviewState, ns:SetMergeCDMSettingsOpen, the PLAYER_TARGET_CHANGED registration (shown-slot pass still needs it).
- ns:RefreshMergeMirror lost both RefreshMergeAuraGroups calls; both ReanchorMergeViewers calls and the visibility check are untouched.
- /tbt merge diagnostics lost the aura=, pandemic/dispel dump, target-slot and filter= lines. The itemCD / catSpell / relay bits remain for 70-04 (they read `ns.itemCooldownSeen`, `ns.categorySpellID`, `ns.mergeRelayState` behind nil guards, so they cannot raise).
- aura-read-gate: allowlist row and header text for MergeMode.lua removed; reports "1 reads in 1 allowlisted readers".

## Acceptance results

- Code-only and comment-hygiene identifier gates: 0 for both tasks (one stale SyncEntryContainers comment in the mirror build was reworded). Whole-file `AuraContainer`/`pandemic`/`dispel` code-only: 0. No `"AuraContainer"` string in any .lua.
- Survival counts all as specified (ReanchorMergeViewers pcall 2, CheckMergeViewerVisibility 2, others 1); editModeOpen awk order check passes.
- No added SetParent / SetLayoutData / hooksecurefunc / SetAlpha in the diff.
- `stylua --check .` clean; aura-read-gate PASS, selftest PASS (30); migrate-dryrun selftest PASS (14). Deployed with install.bat after Task 2 only.
- Note: no Lua compiler is installed here, so load-correctness rests on the identifier greps and survival counts; the first in-game load is the real syntax check.

## Deviations from Plan

None - plan executed as written. Task 2 also reworded one comment at the mirror build that named a deleted function (comment hygiene gate).

## Deferred to Phase 72 (in game)

- Merge Mode places and previews; no Lua error on load, on target change, on spec change.
- Another mage's Touch of the Magi / another Frost Mage's Freezing never lights the player's entry (999.22/23).
- No single debuff fills every merged cell, including on a mind-controlled or friendly target (999.24).
- Centered container with merged-only entries re-centres from cdmShown (999.25).

## Known Stubs

None.

## Self-Check: PASSED

Commits f093158 and 48f1415 exist; MergeMode.lua and scripts/aura-read-gate.js modified.
