---
phase: 69-re-anchoring-open-issues
fixed_at: 2026-10-10T00:00:00Z
review_path: .planning/phases/69-re-anchoring-open-issues/69-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 69: Code Review Fix Report

**Fixed at:** 2026-10-10
**Source review:** .planning/phases/69-re-anchoring-open-issues/69-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (WR-01..03, IN-01..05)
- Fixed: 8
- Skipped: 0

The work was done directly on `milestone/v0.5.2-improved-merge-mode`, with no worktree, as the orchestrator asked. Every commit was preceded by `stylua .`. All three `.lua` files stay `w/crlf`, and no `git diff --stat` showed `Bin`.

After the last fix these all passed:
- `node scripts/aura-read-gate.js` (4 reads in 2 allowlisted readers)
- its `--selftest` (30 cases)
- `node scripts/migrate-dryrun.js --selftest` (13 cases)

The build was deployed with `./scripts/install.bat` (v0.5.1-75-gd2fe5be-dev). No Lua interpreter is installed, so stylua's parser served as the Tier 2 syntax check.

**Hard boundary:** still holds. There is no SetParent, no field write on a Blizzard frame, no Blizzard mixin call, no Show/Hide on a Blizzard frame and no aura read. The only new reads on Blizzard frames are:
- `GetPoint` in `ReleaseItem`, through the existing `CaptureBlizzardAnchor`. It is already in the module header's getter list.
- A pool walk that reads `cooldownID` in `CollectFrameOwners`. This has the same shape as `BuildViewerIDs`, is event-driven, and runs only on a mirror rebuild.

The steady-state render gains no game call and no allocation. IN-05 removes one lookup per merged slot.

No public `ns:` method was renamed. `ns:ReanchorMergeViewers` gained an optional `skipPlace` argument.

Every fix except IN-03 and IN-05 changes runtime logic and is marked "requires human verification" (in-game, Phase 72).

## Fixed Issues

### WR-01: The STEAL-14 placeholder gate uses a different preview predicate from the stamp it reads

**Files modified:** `Display.lua`
**Commit:** 95dea57
**Status:** fixed: requires human verification
**Applied fix:**
- `ownMergedPreview` is gone from both render functions. Both now branch on `cdmFrameVisible == false` alone.
- Live play cannot reach the placeholder. Outside preview the shown-slot pass stamps `true` on every pass. Freshly rebuilt entries carry `nil`, which is not `false`. With Merge Mode off, `reanchorHere` is false.
- A comment records why only one predicate is used.

### WR-02: A frame released by the forced pass after Layout is put back on its stale captured anchor

**Files modified:** `MergeReanchor.lua`
**Commit:** 2b26963
**Status:** fixed: requires human verification
**Applied fix:**
- This takes the orchestrator's "re-capture before releasing" option rather than a `keepAnchor` parameter. `ReleaseItem` now calls `CaptureBlizzardAnchor(itemFrame)` first.
- A frame the Layout post-hook releases on a viewer mismatch was just put on its new grid position by Blizzard. That fresh anchor is captured, and the restore re-applies it, so the frame does not move.
- A frame still on a TBT cell (hidden, so Layout did not touch it) is skipped by the capture's `isCell` test and keeps the older capture as its fallback.
- This applies on every release path, so the stale `origPoint` the reviewer wanted cleared is overwritten whenever a fresher Blizzard anchor exists.

### WR-03: The STEAL-13 "render before place" invariant is broken by the forced placement inside RefreshMergeMirror

**Files modified:** `MergeReanchor.lua`, `MergeMode.lua`
**Commit:** ac3f8c1
**Status:** fixed: requires human verification
**Applied fix:**
- `ns:ReanchorMergeViewers(skipPlace)`: with `skipPlace` and Merge Mode on, it only installs the Layout hooks. `RefreshMergeMirror`'s Merge-on path passes `true`. The Merge-off path still force-releases.
- After a rebuild, the first placement through the new map is the flush of the render that `mirrorChangedForPlacement` triggers, followed by the shown pass's unforced pass.
- While previewing, a Blizzard Layout now costs one forced `PlaceViewer` for that viewer, then a rebuild that places nothing. Before, it was that plus a full forced pass over every hooked viewer.
- The viewer's own forced pass is kept, because Blizzard has just moved its shown frames off TBT's cells. Without it they would show at Blizzard's positions for a frame.
- The three comments, plus `ReanchorMergeViewers`' header, now describe what the code enforces. The only placement through the old map is a viewer's own Layout post-hook, for that viewer alone, kept on the right container by the viewer check. A same-viewer reorder can sit on its old cell until the render that follows.

### IN-01: The duplicate-attach guard picks its winner by ns.CONTAINERS order

**Files modified:** `MergeMode.lua`
**Commit:** 157093a
**Status:** fixed: requires human verification
**Applied fix:** `RefreshMergeMirror` de-duplicates ids across containers in three steps:
1. Before filling any list, it walks each eligible container's viewer pool (`CollectFrameOwners`) into a module-level, wiped `frameOwnerByID`. An eligible container has a list and a resolved category.
2. A list then takes an id only when no other list has claimed it and no other container's viewer owns its frame. An unclaimable id gets no info lookup, so it is skipped.
3. `claimedIDs[cooldownID]` is set when an entry is inserted.

Display therefore never sees an id twice, and the guard in `AttachMergedItem` is now a pure safety net. Secret ids are never used as keys.

### IN-02: The CDM Visibility notice is evaluated only on a mirror rebuild

**Files modified:** `MergeMode.lua`
**Commit:** a89a5a6
**Status:** fixed: requires human verification
**Applied fix:**
- `FlushMergeVisibility` now also calls `pcall(ns.CheckMergeViewerVisibility, ns)` when Merge Mode is on.
- That flush runs on `EDIT_MODE_LAYOUTS_UPDATED` and on the Edit Mode Exit edge, so the check now runs after Edit Mode applies a layout or the player leaves it.
- The once-per-viewer-per-session flag is unchanged. The cost per flush is a few field reads and nothing at all once warned.

### IN-03: Unknown visibleSetting values are reported as "is hidden"

**Files modified:** `MergeMode.lua`
**Commit:** 3443374
**Status:** fixed
**Applied fix:**
- The notice now compares explicitly against `InCombat` and `Hidden`. Any other value, including a future one, prints nothing and does not set the warned flag.
- This matches `/tbt merge`, which labels such a value "unknown" rather than calling it hidden.

### IN-04: The placeholder reset in the STEAL-14 icon branch duplicates the generic merged-placeholder branch

**Files modified:** `Display.lua`
**Commit:** c1c4ac8
**Status:** fixed: requires human verification
**Applied fix:**
- New file-local `ShowMergedPlaceholderIcon(icon, entry, settings)`, declared above `RenderIconContainer` and after every helper it uses.
- The STEAL-14 branch calls it.
- The generic placeholder's merged half moved into a new `elseif entry.isMerged then` branch, at the same position in the chain, which also calls it. The generic branch now handles only TBT's own entries, and its condition no longer lists `entry.isMerged`.
- **One deliberate behaviour change:** the helper clears `_lastStart` (and `_mergedExpiry`) before it issues the merged sweep. The old generic order cleared the timer stamp after the sweep, so a pooled widget that last drew a live timer could `Clear()` the merged sweep it had just set. With Merge Mode on, the aura timing is never resolved, so today this is effectively unreachable.
- The `ClearCooldownStamps` header comment now names the helper as the owner of `_mergedExpiry`.

### IN-05: The viewer lookup is repeated for every merged slot on every tick

**Files modified:** `Display.lua`
**Commit:** d2fe5be
**Status:** fixed
**Applied fix:** Both render functions resolve `local ownViewer = reanchorHere and (ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal])` once, next to `reanchorHere`, and pass it to every `AttachMergedItem` call.

---

_Fixed: 2026-10-10_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
