---
phase: 46-item-catalogue-suggested-tiles
plan: 04
subsystem: ui
tags: [wow-addon, lua, validation, stylua, git-eol, cooldown-manager]

# Dependency graph
requires:
  - phase: 46-item-catalogue-suggested-tiles
    plan: 01
    provides: ns.ITEM_KEY_PREFIX, ns:ItemKeyItemID, the bag-derived catalogue and its accessors
  - phase: 46-item-catalogue-suggested-tiles
    plan: 02
    provides: item -- branch dispatch, BAG_UPDATE dirty flag, CDM-open scan trigger
  - phase: 46-item-catalogue-suggested-tiles
    plan: 03
    provides: chargeCount fontstring, the item tile render loop in ns:RefreshTBTSections
provides:
  - "S1..S10 static assertion sweep results, each recorded with command output or the specific line read"
  - "Cleanup review findings for the milestone's render/scan hot paths"
  - "Filled Per-Task Verification Map in 46-VALIDATION.md, one row per task across Plans 01-04"
  - "Deployment to all four WoW client folders present on the machine"
affects: [47-tracker-creation-from-tile, 52-retail-review-pass]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - .planning/phases/46-item-catalogue-suggested-tiles/46-VALIDATION.md

key-decisions:
  - "The S2 discrepancy found on 46-01/02/03-SUMMARY.md (w/lf instead of w/crlf) was recorded in 46-VALIDATION.md and left unedited rather than fixed -- those three files are outside this plan's files_modified scope (only 46-VALIDATION.md is declared), and CLAUDE.md's own incident history argues for reporting a .md diff rather than silently correcting one."
  - "Front matter nyquist_compliant and wave_0_complete were left false, with an explanatory note added under the table, rather than set true on completing the static sweep alone -- the in-game gate (Task 3) is the only route to ITEM-01/03/08/10 and has not run yet."
  - "status: complete was set per the plan's explicit Task 2 instruction; this describes the validation document being finalized (placeholder replaced with real per-task results), not that the phase's requirements are proven -- that distinction is spelled out in the note under the table so it cannot be misread as Task 3 having passed."

requirements-completed: []

# Metrics
duration: 24min
completed: 2026-09-24
---

# Phase 46 Plan 04: Static Sweep, Cleanup Review & Deploy Summary

**Ran all ten static assertions (S1..S10) against the shipped source with recorded evidence, performed the CLAUDE.md cleanup review over the milestone's new hot paths, filled 46-VALIDATION.md's Per-Task Verification Map, deployed to all four present WoW client folders, and stopped at the blocking in-game checkpoint (Task 3) without attempting it.**

## Performance

- **Duration:** ~24 min (Task 1 sweep + cleanup review, Task 2 doc edit + deploy)
- **Started:** 2026-09-24T10:49:00Z (approx, first read)
- **Completed:** 2026-09-24T11:13:05Z
- **Tasks:** 2/3 completed (Task 3 is a blocking human-verify checkpoint, correctly not attempted)
- **Files modified:** 1

## Accomplishments

- All ten static assertions (S1..S10) run against the final shipped source, each with command output or a specific line reference recorded below
- CLAUDE.md's post-commit performance-and-cleanup review completed over this milestone's four real risk points: render-loop allocation, `RefreshTBTSections` bag/item-API reachability, the `BAG_UPDATE` coalescing flag, and dead-code callers
- `46-VALIDATION.md`'s Per-Task Verification Map filled with 10 real rows (one per task across Plans 01-04), replacing the `_(planner fills)_` placeholder
- Deployed to all four WoW client folders present on the machine, including both clients the in-game gate needs: `_retail_` (Midnight) and `_classic_beta_` (Forever)
- Found and recorded (not silently fixed) a live instance of the CRLF->LF blind spot CLAUDE.md documents, on three prior-wave `.md` files outside this plan's scope

## Task Commits

1. **Task 1: Run the S1..S10 static assertion sweep and the cleanup review** - no commit (pure verification; zero files changed, confirmed by `git status --short` before and after)
2. **Task 2: Fill the Per-Task Verification Map and deploy to both clients** - `615cdbd` (docs)

**Plan metadata:** committed alongside this summary.

## Files Created/Modified

- `.planning/phases/46-item-catalogue-suggested-tiles/46-VALIDATION.md` - Per-Task Verification Map filled with 10 rows; front matter `status` set to `complete`; `nyquist_compliant`/`wave_0_complete` left `false` with an explanatory note; the S2 discrepancy on the three prior-wave summaries recorded

## Static Assertion Sweep (S1..S10) -- Evidence

**S1 -- stylua clean.** `stylua .` (bare, repo root) ran clean; `git diff --stat` was empty (no reflow); `stylua --check .` exited 0.
```
$ stylua . && git diff --stat && stylua --check .
(no output from stylua; no output from git diff --stat; exit 0)
```

**S2 -- line endings held.** `git ls-files --eol Core.lua Providers.lua CDMTab.lua` reports `w/crlf` for all three touched Lua files:
```
i/lf    w/crlf  attr/text eol=crlf    CDMTab.lua
i/lf    w/crlf  attr/text eol=crlf    Core.lua
i/lf    w/crlf  attr/text eol=crlf    Providers.lua
```
Extending the check to every `.md` in the phase directory found a genuine discrepancy: `46-01-SUMMARY.md`, `46-02-SUMMARY.md` and `46-03-SUMMARY.md` report `w/lf`, not `w/crlf`, while every other `.md` in the directory (including this plan's own `46-04-PLAN.md`) correctly reports `w/crlf`. Root cause: `core.autocrlf` is `true` and `.gitattributes` pins `eol=crlf` for `*.lua`/`*.xml`/`*.toc`/`*.bat`/`*.ps1` only -- `.md` falls under the bare `* text=auto`, so the LF->CRLF conversion only happens on checkout. These three files were written directly to disk by the prior-wave executors and committed as-is without an intervening checkout, so they never picked up the conversion. This is a live instance of the exact blind spot T-46-12 and CLAUDE.md's `.gitattributes` note describe. **Not fixed by this plan** -- these three files are outside the `files_modified` scope declared in this plan's front matter (only `46-VALIDATION.md` is), and CLAUDE.md's own incident history is explicit that a `.md` diff found unexpectedly should be reported, not silently corrected. Recorded in `46-VALIDATION.md`'s Per-Task Verification Map note for the user to decide on a follow-up.

**S3 -- no flavour check introduced.**
```
Providers.lua: 0
CDMTab.lua: 0
Core.lua: 3 (matches the pre-edit baseline of 3 recorded in 46-02-SUMMARY.md -- no increase)
```

**S4 -- secret guard ordering.** Source read of every new `C_Item.*`/`C_Container.*` value confirmed `issecretvalue(v)` evaluated textually before any `type(v)` or `==` on that value, by name:
- `GetContainerItemID`'s `id` (`Providers.lua:937-939`) -- guarded before being written into `itemCatalogueSeen`.
- `GetItemInfoInstant`'s `classID`/`subClassID` (`Providers.lua:949-957`) -- both guarded before the `== 0`/`~= 7` comparisons.
- `GetItemInfoInstant`'s `icon` (`Providers.lua:967`) -- guarded before caching.
- `GetItemSpell`'s `useSpellID` (`Providers.lua:958-961`) -- guarded before the truthiness test, with a comment explicitly calling out why (a secret non-nil value is truthy under a naive `if useSpellID then`).
- `GetItemCount`'s `count` (`Providers.lua:973-974`) -- guarded before caching.
- `GetItemNameByID`'s `name` (`Providers.lua:1046-1047`) -- guarded before the label assignment, degrading to `"Item " .. tostring(itemID)`.

**S5 -- one TOC, both interfaces.**
```
$ grep "^## Interface:" TerribleBuffTracker.toc
## Interface: 120100, 16001
$ git diff --name-only -- TerribleBuffTracker.toc CHANGELOG.md .planning/PROJECT.md
(empty)
```

**S6 -- load order / phase diff scope.** `git diff --name-only aff8b82^ HEAD` (the commit before Plan 01's first commit, through the current HEAD) lists only `CDMTab.lua`, `Core.lua`, `Providers.lua` and `.planning/` paths (`46-01-SUMMARY.md`, `46-02-PLAN.md`, `46-02-SUMMARY.md`, `46-03-SUMMARY.md`) -- no new `.lua` file, so load order is trivially unchanged.

**S7 -- `item:` keys stay inert.** Source read of `AddSuggestedTracker` (`CDMTab.lua:139-160`, the function `CDMTab.lua:101` in the phase's own line numbering shifted to as edits landed): for an `item:<itemID>` key, `ns.db.trackedBuffs[key]` is nil (untracked), `ns:CooldownKeySpellID(key)` returns nil (not a `cd:` key), and the key matches no entry in `ns.SUGGESTED_KEYS`, so `known` stays false and the function returns at its guard clause without creating an entry. Confirmed byte-unchanged across the whole phase diff: `git diff aff8b82^ HEAD -- CDMTab.lua | grep AddSuggestedTracker` shows only one comment line added elsewhere in the file (near the drag handler, describing gate G7) -- zero hunks inside the function body itself.

**S8 -- catalogue is itemID-keyed.** Source read of `Providers.lua:900-1002`: `itemCatalogueIDs`, `itemCatalogueIcons` and `itemCatalogueCounts` are all indexed by itemID. `bag` and `slot` as real (non-comment) identifiers appear only inside the discovery walk (`Providers.lua:934-937`, the `for bag = 0, 5 do` / `for slot = 1, numSlots do` loop) -- confirmed by `awk` isolating the catalogue block and grepping for `\bbag\b|\bslot\b`; every other hit was a comment.

**S9 -- exclusions are taxonomy-driven.** Source read of `Providers.lua:944-961`: the filter tests only `classID == 0`, `subClassID ~= 7` (both from `GetItemInfoInstant`) and the presence of a `GetItemSpell` result. `grep -n "GetItemNameByID|itemName|\.name ==" Providers.lua CDMTab.lua` found exactly one real hit -- `GetItemNameByID` at `Providers.lua:1046`, used only for the tooltip label in `ns:ItemDisplayInfo`, never in the filter.

**S10 -- pooled tile state rewritten.** Source read of `CDMTab.lua`: the `section.itemPool` `CreateObjectPool` reset function (`CDMTab.lua:725-740`) calls `frame.chargeCount.Current:SetText("")` then `frame.chargeCount:Hide()` on every release. The item tile loop (`CDMTab.lua:870-901`) writes `item.chargeCount.Current:SetText(count)` + `item.chargeCount:Show()` when `ns:ItemCatalogueCount(itemID)` is a number, or `item.chargeCount:Hide()` when it is nil -- every path through the loop body reaches one or the other, on every render pass.

## Cleanup Review (CLAUDE.md post-commit mandate, scoped to this milestone's new code)

- **Hot-path allocations:** none found. `sed -n '870,901p' CDMTab.lua | grep '{'` returns nothing -- the item tile loop has zero table constructors. The catalogue scan (`ns:RefreshItemCatalogue`) allocates nothing per scan either; its four tables are declared once at module level and `wipe()`'d, never reallocated.
- **Redundant per-frame work:** none found. Isolating `ns:RefreshTBTSections`'s function body and grepping for `C_Container\.|C_Item\.` returns nothing -- no bag or item-classification call is reachable from the render function or any of its (now fifteen, up from the eleven recorded pre-phase) call sites.
- **Dirty-check correctness:** `itemCatalogueRebuildScheduled` (`CDMTab.lua:51-70`) is reset to `false` as the very first statement inside the `C_Timer.After(0, ...)` callback, before either `RefreshItemCatalogue` or `RefreshTBTSections` runs -- there is no path that leaves it stuck `true`, including if a rebuild's own body were to error.
- **Dead code:** `ns:ItemCatalogueIcon` has exactly one caller (`ns:ItemDisplayInfo`, `Providers.lua:1035`); `ns:IsItemCatalogueDirty` has exactly one caller (the coalescing consumer, `CDMTab.lua:65`). Both confirmed by grepping every `.lua` file for the call site minus the definition line. No unused local or uncalled function found in this milestone's new code.

## Per-Task Verification Map

Filled in `46-VALIDATION.md` with 10 rows (one per task across Plans 01-04). See that file for the full table; every row's Static gate cites the actual `S`-numbers the task's own `<acceptance_criteria>` names, and every row whose task only answers an in-game gate is marked accordingly. Row 46-04-T3 (this plan's checkpoint) is the only row not marked PASS -- it reads **NOT STARTED -- awaiting human verification**.

## Deploy

`./scripts/install.bat` ran successfully and copied the 11-file TOC-derived set to all four WoW client folders present on this machine:
```
Installed to C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_beta_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker
```
No file this phase added or renamed changes `TerribleBuffTracker.toc` (confirmed by S5/S6 above), so `/reload` is sufficient in-client for both required clients (`_retail_` for Midnight, `_classic_beta_` for Forever) -- a full client restart is not required.

## Decisions Made

See `key-decisions` in the frontmatter above.

## Deviations from Plan

### Documented, not auto-fixed

**1. [Reported, not Rule-1-fixed] S2 CRLF blind-spot instance on three prior-wave SUMMARY.md files**
- **Found during:** Task 1, running S2 against every `.md` in the phase directory (a broader check than the plan's own literal automated `<verify>` command, which only checks the three touched `.lua` files).
- **Issue:** `46-01-SUMMARY.md`, `46-02-SUMMARY.md`, `46-03-SUMMARY.md` report `w/lf` instead of `w/crlf`.
- **Why not auto-fixed:** these three files are not in this plan's `files_modified` list (only `46-VALIDATION.md` is), and CLAUDE.md's own incident history is explicit that an unexpected `.md` diff should be reported to the user, not silently corrected by the executor.
- **Action taken:** recorded in `46-VALIDATION.md`'s Per-Task Verification Map note, with root cause, and left unedited.
- **Files affected:** none (report-only).

No other deviations. Every other static assertion, the cleanup review, and the deploy ran exactly as the plan specified.

## Issues Encountered

None beyond the S2 discrepancy documented above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. This plan performs verification and documentation only; it introduces no new runtime code.

## Threat Flags

None. This plan reads and verifies existing code and touches only `46-VALIDATION.md`; it introduces no new network endpoint, auth path, file-access pattern, or schema change.

## Task 3: In-Game Gate G1..G7 -- NOT STARTED, Awaiting Human Verification

Per this plan's blocking checkpoint (`type="checkpoint:human-verify" gate="blocking"`), Task 3 was
**not attempted**. No part of G1..G7 has been simulated, inferred, or asserted to pass. None of
ITEM-01, ITEM-03, ITEM-08 or ITEM-10 are being claimed as met by this summary -- they remain
provable only by a human running the checklist below.

**Setup (once, before the first check):** carry potions, a healthstone, a quest item, a recipe, a
key, a trade good and a bandage. Split one potion stack across two different bags. `/reload`, then
open the Cooldown Manager and select the **Cooldowns** tab.

Run on the **WoW Forever beta first** (`_classic_beta_`, every measured fact behind this design came
from there), in this order, then repeat on **Midnight retail** (`_retail_`):

1. **G1 (ITEM-01):** the split potion appears **once**, not twice. Each distinct itemID produces
   exactly one tile regardless of how many slots hold it.
2. **G2 (ITEM-03):** each item tile shows the item's own icon (not the 134400 question mark) and a
   count in the bottom-right matching the number in your bags, in the same font/position as a
   cooldown icon's charge count.
3. **G3 (ITEM-03):** with the CDM still open, drink or use one item down to a smaller stack. The
   count updates **without** closing and reopening the CDM.
4. **G4 (ITEM-08):** the quest item, the recipe, the key, the trade good and the **bandage** are all
   absent.
5. **G5 (ITEM-08):** the known `0/8` residue (glue, campfire kit, lute, crate, or whatever this
   character carries) is still **present** -- accepted documented behaviour per ROADMAP 999.6 section
   1, not a bug. Its absence would mean the filter over-reached and is a **fail**.
6. **G7:** drag an item tile into a container. Expected: the ghost clears, the success sound plays,
   and **nothing appears** in the target container -- the tile stays in Suggested. This is the
   documented Phase 46 no-op; a tracker actually being created here is a defect.
7. **G6 (ITEM-10):** repeat steps 1-6 on **Midnight retail**, out of combat first. Then, if reachable,
   reopen the CDM in combat. Expected in combat: identical tiles, or a **degrade** (a tile with no
   count shown) -- never a Lua error.

Report which of G1..G7 passed on each client. If anything errored, paste the Lua error text
verbatim. `46-VALIDATION.md`'s front matter `nyquist_compliant`/`wave_0_complete` and this phase's
four requirements stay unresolved until this report comes back.

## Next Phase Readiness

- All ten static assertions pass with recorded evidence; the cleanup review found nothing to fix.
- `46-VALIDATION.md`'s Per-Task Verification Map is filled with real results and still reports
  `w/crlf` after the Edit-tool-only change.
- The addon is deployed and ready for the human gate on both required clients.
- `CHANGELOG.md`, `.planning/PROJECT.md` and `TerribleBuffTracker.toc` are provably untouched by this
  phase (git diff assertion above).
- **Blocker for phase close-out:** Task 3's G1..G7 report from the user, on both clients. Phase 46
  cannot be marked complete, and ITEM-01/03/08/10 cannot be marked satisfied, until that comes back.
- Phase 52's retail review pass will need G6's in-combat result as its baseline once it exists.

---
*Phase: 46-item-catalogue-suggested-tiles*
*Completed: 2026-09-24 (Tasks 1-2 only; Task 3 pending human verification)*

## Self-Check: PASSED

- FOUND: `.planning/phases/46-item-catalogue-suggested-tiles/46-04-SUMMARY.md`
- FOUND: `.planning/phases/46-item-catalogue-suggested-tiles/46-VALIDATION.md`
- FOUND: `.planning/phases/46-item-catalogue-suggested-tiles/deferred-items.md`
- FOUND: commit `615cdbd` (Task 2: Per-Task Verification Map + deploy)
- FOUND: commit `ae006f1` (SUMMARY.md)
- FOUND: commit `200a3ec` (deferred-items.md)
