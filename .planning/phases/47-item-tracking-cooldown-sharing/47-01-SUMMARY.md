---
phase: 47-item-tracking-cooldown-sharing
plan: 01
subsystem: addon-runtime
tags: [wow-addon, lua, cooldown-manager, item-tracking, secret-values]

# Dependency graph
requires:
  - phase: 46-item-catalogue-suggested-tiles
    provides: "ns.ITEM_KEY_PREFIX, ns:ItemKeyItemID, ns:RefreshItemCatalogue, ns:ItemDisplayInfo, the item catalogue's four module-level tables and its already-guarded C_Item.GetItemSpell call"
provides:
  - "itemUseSpellToID -- module-local useSpellID -> itemID map, captured at catalogue-scan time"
  - "itemTrackedCounts -- module-local runtime-only \"item:<itemID>\" -> count store"
  - "ns:TrackedItemCount(key), ns:SeedItemTracker(key, itemID, entry), ns:RefreshTrackedItemCooldowns(), ns:ReconcileTrackedItemCounts() -- four exported functions"
  - "ItemProviderMixin -- registered in ns.providers, ties a landed UNIT_SPELLCAST_SUCCEEDED to the above, returns nil on every path"
affects: [47-02-item-tracker-creation-and-events, 47-03-item-tracker-rendering]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "issecretvalue(v) before type(v) before any truthiness test, on every new C_Item.* read (T-47-01)"
    - "Provider OnTrigger returns nil unconditionally when the tracker type has no buff/timer side, so DispatchEventToProviders' unvalidated ns.activeTimers write can never see a phantom entry"
    - "Combat-gate the reconcile (count truth), never combat-gate the cooldown re-read (D-02/D-04 stamp)"

key-files:
  created: []
  modified:
    - Providers.lua

key-decisions:
  - "D-01 use-spell -> itemID map, no hooks on the production path (locked, user decision 2026-09-24)"
  - "D-02 per-item C_Item.GetItemCooldown(itemID), no spell-category table (locked)"
  - "D-03 decrement by 1 on a landed use, reconcile against GetItemCount at combat end, count never negative (locked)"
  - "D-04 stamp start+duration at the landed use (locked)"
  - "D-05 seed the cooldown at tracker creation -- the one place the degrade rule does not apply (locked, from 47-VALIDATION.md)"
  - "Collision on itemUseSpellToID: last writer wins, logged under the existing ns.debugLogging flag only, via a new self-contained print -- Core.lua's protected debug log is untouched (D-06)"

patterns-established:
  - "Pattern: any provider whose tracker type has no buff/timer side must document and mechanically guarantee 'return nil on every statement-leading path' -- DispatchEventToProviders performs no validation of its own"

requirements-completed: [ITEM-05, ITEM-06, ITEM-07, ITEM-09]

# Metrics
duration: 15min
completed: 2026-09-24
---

# Phase 47 Plan 01: Item Tracking Runtime State Layer Summary

**Runtime state layer for tracked items in `Providers.lua`: a use-spell->itemID map captured at no extra API cost, a runtime-only tracked-count store kept separate from the Suggested catalogue's bag-walk cache, a combat-gated reconcile plus an always-on per-item cooldown re-read, and an `ItemProviderMixin` that recognizes a landed item use from `UNIT_SPELLCAST_SUCCEEDED` alone and writes nothing into `ns.activeTimers`.**

## Performance

- **Duration:** ~15 min (three task commits between 09:07:30 and 09:10:19 local time, 2026-09-24)
- **Tasks:** 3/3 completed
- **Files modified:** 1 (`Providers.lua`)

## Accomplishments

- `itemUseSpellToID` (`Providers.lua:926`) captured inside `ns:RefreshItemCatalogue`'s existing guarded `C_Item.GetItemSpell` branch, at zero extra API cost, with a debug-flag-gated collision log
- `itemTrackedCounts` (`Providers.lua:937`) — a runtime-only store, deliberately never `wipe()`d by the catalogue rebuild and deliberately not `itemCatalogueCounts`, so a zero-stock tracked item keeps its count (ITEM-09)
- Four exported functions with the exact interface contract Plans 02/03 depend on: `ns:TrackedItemCount`, `ns:SeedItemTracker`, `ns:RefreshTrackedItemCooldowns`, `ns:ReconcileTrackedItemCounts`
- `ItemProviderMixin` registered in `ns.providers` immediately before `UserSpellProvider`, matching a landed use through the map before any table walk, decrementing with a zero floor, re-reading every tracked item's cooldown, and returning `nil` on all five statement-leading return paths
- `Core.lua` is byte-unchanged (`git diff --name-only -- Core.lua` empty at every gate) — D-06 held mechanically, not just by discipline

## Task Commits

Each task was committed atomically:

1. **Task 1: Capture the use-spell to itemID map in ns:RefreshItemCatalogue** - `5ec6b51` (feat)
2. **Task 2: Add the tracked-item runtime store and its four exported functions** - `7391a2f` (feat)
3. **Task 3: Add ItemProviderMixin and register it, returning nil on every path** - `1e44be5` (feat)

**Plan metadata:** commit pending (this summary + STATE.md, if `commit_docs` allows — see `<do_not_touch>` in this plan's own instructions: STATE.md/ROADMAP.md are NOT touched by this executor)

## Files Created/Modified

- `Providers.lua` — five module-level tables now (was four): `itemUseSpellToID` at line 926, `itemTrackedCounts` at line 937 (header comment corrected from "Four module-level tables" to "Five"); `ns:TrackedItemCount` at 1063, `ns:SeedItemTracker` at 1070, `ns:RefreshTrackedItemCooldowns` at 1110, `ns:ReconcileTrackedItemCounts` at 1137; `ItemProviderMixin` at 1412 (`GetEventInterests` 1414, `OnTrigger` 1426), `ItemProvider` built at 1467, registered into `ns.providers` at 1472 immediately before `UserSpellProvider`. `keyToProvider` unchanged — no `item` entry added, by design.

## Decisions Made

- Collision detection on `itemUseSpellToID` implemented per CONTEXT.md's discretion note: cheap read-before-write, logged only under `ns.debugLogging`, last writer wins, no user-facing error.
- Reused `ns.cooldownStarts` for the item-key stamp rather than a parallel table, per CONTEXT.md's discretion note — `ns:IsCooldownRunning` and `ApplyUserCooldown` (`Display.lua`) needed no changes.
- `ns:SeedItemTracker` is the one place the degrade rule is inverted: on an unreadable/disabled/zero-duration cooldown read at creation time, `ns.cooldownStarts[key]` is explicitly cleared to `nil` (not left alone), because a freshly created tracker has no prior stamp worth preserving and a stale leftover from a deleted tracker of the same itemID would be a phantom sweep. `ns:RefreshTrackedItemCooldowns`, by contrast, never clears on a failed read.

## Deviations from Plan

None — plan executed exactly as written. Two self-correction cycles happened during drafting, not after the fact:

- The first draft of Task 1's collision-log comment named `ns:LogPlayerCast` / `ns:LogItemUse` in prose (read-only reference, per the task's own `<read_first>` instruction), which tripped the task's own D-06 gate (`grep -cE 'LogItemUse|LogPlayerCast|pendingItemCasts' Providers.lua` = 0) because that gate is a blunt whole-file grep with no comment/code distinction. Reworded to describe "Core.lua's protected debug cast/item log" without naming the identifiers. No functional change; caught by the gate itself before commit.
- The first draft of Task 3's `OnTrigger` comment used the literal string `math.max` in a code comment, which double-counted against the gate's `= 1` occurrence check (the gate cannot distinguish a comment mention from the real call). Reworded to "clamped at zero below" and left the one actual `math.max(0, current - 1)` call. No functional change; caught by the gate itself before commit.

Neither counts as a Rule 1-4 deviation — both were drafting-time gate failures caught and fixed before any commit, not runtime bugs or scope changes.

## Issues Encountered

None. All twelve `<automated>` verify blocks (Tasks 1-3) passed as written on the first post-fix run — no gate was weakened or reinterpreted.

## Reading vs. plan line numbers

The plan's `<read_first>` line citations (e.g. `Providers.lua:905-919`, `:920-995`, `:996-1010`, `:1043-1065`, `:1243-1262`, `:1268-1299`) all matched the pre-Task-1 source at the point each task started reading. No `<read_first>` citation was stale. Final line numbers moved as each task inserted code — see "Files Created/Modified" above for the landed locations Plans 02/03 should cite instead.

## User Setup Required

None — no external service configuration required. This plan adds no new call sites; `./scripts/install.bat` was run as the plan's own load-safety smoke check and deployed cleanly to all four detected WoW client folders with no Lua load errors reported by the deploy step.

## Next Phase Readiness

- Plan 02 (tracker creation and event wiring) can now call `ns:SeedItemTracker` from `AddSuggestedTracker` and reconcile via `ns:ReconcileTrackedItemCounts` from an already-registered event — both exist with the exact signatures this summary's frontmatter `provides` list documents.
- Plan 03 (rendering) can now read `ns:TrackedItemCount(key)` — confirmed to never alias `ns:ItemCatalogueCount`.
- Nothing in this plan calls any of the four new functions or reaches `ItemProviderMixin:OnTrigger` from a live event yet (it is registered, so it dispatches, but every path returns `nil` and no caller in `CDMTab.lua`/`Core.lua` invokes the new `ns:` functions) — the addon's behavior is unchanged for a player who has not dragged an item tile, matching this plan's own "Output" contract.
- No blockers. Phase 46's carry-over in-game verification risk (noted in `47-CONTEXT.md`) still applies to the catalogue this plan builds on, unchanged by this plan.

---
*Phase: 47-item-tracking-cooldown-sharing*
*Completed: 2026-09-24*

## Self-Check: PASSED

- FOUND: `Providers.lua`
- FOUND: `.planning/phases/47-item-tracking-cooldown-sharing/47-01-SUMMARY.md`
- FOUND: `5ec6b51` (Task 1 commit)
- FOUND: `7391a2f` (Task 2 commit)
- FOUND: `1e44be5` (Task 3 commit)
