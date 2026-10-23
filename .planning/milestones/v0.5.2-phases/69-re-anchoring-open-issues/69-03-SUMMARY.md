---
phase: 69-re-anchoring-open-issues
plan: 03
subsystem: merge-mode
tags: [steal-15, visibility, reanchor]
requires: ["69-02"]
provides: ["STEAL-15 rule stated in code", "ns:CheckMergeViewerVisibility notice"]
key-files:
  modified: [MergeReanchor.lua, Display.lua, MergeMode.lua]
requirements-completed: [STEAL-15]
metrics:
  completed: 2026-10-10
---

# Phase 69 Plan 03: Container visibility (STEAL-15) Summary

A TBT container hidden by any render path already sent its merged frames back to the parked viewer through the whole-map rebuild. This plan states that rule in the code and adds a one-time chat notice for the case TBT cannot fix: the CDM's own Visibility hiding the viewer.

## Commits
- 80fcf94: docs(69-03): hidden-container rule written at both Display.lua hide branches, the RenderContainers no-frame branch and the FlushMergedPlacement prune. The OPEN ITEM in MergeReanchor.lua now reads RESOLVED.
- 01c84d6: feat(69-03): `ns:CheckMergeViewerVisibility` and a per-viewer CDM Visibility line in `/tbt merge`.

## Task 1 container hide audit
`grep 'container:Hide()'` found these sites, all accounted for. The result is no gap, so there is no runtime change.
- Display.lua RenderBarContainer hide branch: a render branch, so it skips the attach and the flush returns the frames.
- Display.lua RenderIconContainer hide branch: a render branch, same result.
- Display.lua RenderContainers no-frame/no-settings branch: a render branch, same result.
- EditModeFrames.lua:48 (`tbtVisible` false in ApplyEditModePositions): the next render overrides it.
- EditModeFrames.lua:633 (HideEditModeHandles): the next render overrides it.
- EditModeFrames.lua:960: container deletion, which unregisters the def.

## Task 2
- `mergeVisibilityWarned` is declared above `ns:RefreshMergeMirror`. `ns:CheckMergeViewerVisibility` only reads `viewer.visibleSetting`, behind `issecretvalue` and `type` guards, and prints one line per viewer per session. It runs only for a viewer that has merged entries.
- It is called through `pcall` once at the end of the Merge-on path of `ns:RefreshMergeMirror`.
- `/tbt merge` prints a CDM Visibility line per viewer.
- No viewer Show/Hide/SetShown and no viewer field write was added.

## Deviations from Plan
None. One small choice: the notice resolves the viewer with `_G[def.cdmViewerGlobal]`, as the plan wrote it, not `ns.cdmViewers[def.key] or _G[...]`. Both give the same frame.

## Verification
- Task gates passed: the grep counts, the `mergeVisibilityWarned` line order, and the diff gate for viewer writes returning 0.
- `stylua .` ran, all three files are `w/crlf`, and `git diff --stat` shows no `Bin`.
- `aura-read-gate.js`, `aura-read-gate.js --selftest` and `migrate-dryrun.js --selftest` pass.
- The invariant grep for SetParent/SetLayoutData/SetAlpha(0) in added lines returns one hit, which is a comment line saying "not SetAlpha(0)".
- No CHANGELOG or README change.
- `./scripts/install.bat` deployed to these client folders: `_retail_`, `_ptr_`, `_beta_` and `_classic_beta_`.

## Deferred to Phase 72 (in-game)
- With a merged container on Visibility In Combat, out of combat both the container and its merged frames are gone and hovering shows no tooltip. Entering combat brings them back at once.
- The same with Visibility Hidden, and with Hide When Inactive on a container with nothing active.
- Set a CDM section's own Visibility to In Combat with Merge Mode off, then turn Merge Mode on. One chat line names the section and the fix, and `/tbt merge` lists its Visibility.

## Self-Check: PASSED
Commits 80fcf94 and 01c84d6 exist. The three modified files are present.
