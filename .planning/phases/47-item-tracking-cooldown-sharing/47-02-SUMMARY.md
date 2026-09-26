---
phase: 47-item-tracking-cooldown-sharing
plan: 02
subsystem: addon-runtime
tags: [wow-addon, lua, cooldown-manager, item-tracking, drag-drop]

# Dependency graph
requires:
  - phase: 47-item-tracking-cooldown-sharing (Plan 01)
    provides: "ns:SeedItemTracker(key, itemID, entry), ns:RefreshTrackedItemCooldowns(), ns:ReconcileTrackedItemCounts(), ns:TrackedItemCount(key)"
provides:
  - "ns:GetTrackerCategory returns \"spells\" for trackerType == \"item\", not just \"cooldown\""
  - "AddSuggestedTracker recognizes ns:ItemKeyItemID(key) as a third valid drop shape and creates a real ns.db.trackedBuffs[\"item:<itemID>\"] entry"
  - "A dedicated BAG_UPDATE_COOLDOWN dispatch branch calling ns:RefreshTrackedItemCooldowns()"
  - "ns:ReconcileTrackedItemCounts() wired into PLAYER_REGEN_ENABLED and PLAYER_EQUIPMENT_CHANGED/BAG_UPDATE_DELAYED"
affects: [47-03-item-tracker-rendering]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "iconOverride captured at tracker-creation time only, never re-derived on the render path (ApplyCachedIcon reads it straight off the DB entry)"
    - "Category derivation widened rather than re-stored: trackerType == \"item\" reads exactly like trackerType == \"cooldown\" for tab filing purposes, no schema bump"

key-files:
  created: []
  modified:
    - Core.lua
    - CDMTab.lua

key-decisions:
  - "D-05 (seed the cooldown at tracker creation) consumed via one ns:SeedItemTracker call gated on `if itemID then`, immediately after the entry is written"
  - "BAG_UPDATE_DELAYED chosen over adding a reconcile to the plain BAG_UPDATE branch (CONTEXT.md's discretion point), reusing an already-registered event rather than changing BAG_UPDATE's deliberate dirty-flag-only asymmetry"
  - "The Task 2 D-05 comment was reworded mid-task from naming the literal C_Item.GetItemCooldown/GetItemCount API calls to describing them in prose, after the whole-file S4 gate (zero direct C_Item calls in CDMTab.lua) counted the comment's own text as a hit -- no functional change"

patterns-established:
  - "Pattern: an opaque tracker key's third namespace (item:) is admitted into AddSuggestedTracker's rejection test as `not cooldownSpellID and not itemID`, mirroring how CooldownKeySpellID/ItemKeyItemID both fail closed to nil on the wrong shape"

requirements-completed: [ITEM-02, ITEM-04, ITEM-07]

# Metrics
duration: 10min
completed: 2026-09-24
---

# Phase 47 Plan 02: Item Tracker Creation and Event Wiring Summary

**Dragging a Suggested item tile now writes a real `ns.db.trackedBuffs["item:<itemID>"]` entry filed under the Cooldowns tab, carrying its own icon and a seeded cooldown/count, with combat-end and bag-settle reconcile wired to two already-registered events.**

## Performance

- **Duration:** ~10 min (two task commits at 09:14:28 and 09:15:44 local time, 2026-09-24)
- **Tasks:** 2/2 completed
- **Files modified:** 2 (`Core.lua`, `CDMTab.lua`)

## Accomplishments

- `ns:GetTrackerCategory` (`Core.lua:105`) now reads `entry.trackerType == "cooldown" or entry.trackerType == "item"` — an item entry files under Cooldowns instead of silently vanishing from its own tab under Buffs
- `BAG_UPDATE_COOLDOWN` split into its own dispatch branch, immediately before the combined `SPELL_UPDATE_COOLDOWN or SPELL_UPDATE_CHARGES` branch, calling `ns:RefreshTrackedItemCooldowns()` then `ns:MarkCooldownsDirty()` — the two spell events' own behaviour is unchanged
- `ns:ReconcileTrackedItemCounts()` added to `PLAYER_REGEN_ENABLED` (after `ns:RefreshProvidersAtRest()`, beside `ns:MarkCooldownsDirty()`) and to `PLAYER_EQUIPMENT_CHANGED or BAG_UPDATE_DELAYED` (after `ns:RefreshProvidersAtRest()`) — both calls unguarded, matching the file's own precedent for cross-file runtime calls
- `AddSuggestedTracker` (`CDMTab.lua:139`) resolves `ns:ItemKeyItemID(key)` alongside `ns:CooldownKeySpellID(key)`, widening the rejection test to `if not cooldownSpellID and not itemID then`
- The entry constructor writes `trackerType = "item"`, `itemID`, and `iconOverride = info.icon` for an item drop, leaves `spellID = cooldownSpellID or nil` (so an item entry carries no spellID), calls `ns:SeedItemTracker(key, itemID, entry)` once, and bumps `ns:MarkTrackersDirty()` unconditionally at the end of the function
- Confirmed by reading, not editing: the Suggested item-tile loop's `if not ns.db.trackedBuffs[itemKey] then` filter (`CDMTab.lua:897`) needed no change — ITEM-02 is satisfied by construction once the entry exists
- Deployed cleanly via `./scripts/install.bat` to all four detected WoW client folders (retail, PTR, beta, classic beta) with no load errors reported

## Task Commits

Each task was committed atomically:

1. **Task 1: Widen ns:GetTrackerCategory and wire the two already-registered events** - `8aed9bc` (feat)
2. **Task 2: Teach AddSuggestedTracker to create an item tracker** - `16ab0c1` (feat)

**Plan metadata:** commit pending (this summary; STATE.md/ROADMAP.md are NOT touched by this executor per `<do_not_touch>`)

## Files Created/Modified

- `Core.lua` — `ns:GetTrackerCategory` widened at line 105 (was `entry.trackerType == "cooldown"` only), header comment extended to name the silent-failure trap prevented. Dispatch chain: new `elseif event == "BAG_UPDATE_COOLDOWN" then` branch calling `ns:RefreshTrackedItemCooldowns()` + `ns:MarkCooldownsDirty()`, placed immediately before `elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then` (now split from the old three-way combined condition). `ns:ReconcileTrackedItemCounts()` added once in the `PLAYER_REGEN_ENABLED` branch and once in the `PLAYER_EQUIPMENT_CHANGED or BAG_UPDATE_DELAYED` branch. Debug cast/item log block untouched (verified via diff-scoped grep gate, D-06).
- `CDMTab.lua` — `AddSuggestedTracker` (`:139` region): resolves `itemID = ns:ItemKeyItemID(key)`, rejection test widened, entry constructor gains `itemID` and `iconOverride` fields and a widened `trackerType` expression, `ns:SeedItemTracker` call gated on `if itemID then`, `ns:MarkTrackersDirty()` call added unconditionally (nil-guarded) at function end. Suggested item-tile loop's stale "documented Phase 46 no-op" comment (`:893-897`) replaced with a comment describing the now-real creation path; the loop's actual filter logic is byte-unchanged.

## The created item entry, field by field

```lua
ns.db.trackedBuffs["item:" .. itemID] = {
  key = "item:" .. itemID,              -- the opaque drop key itself
  label = info.label,                   -- from ns:GetDisplayInfoForKey -> ns:ItemDisplayInfo (item name, or placeholder)
  duration = info.duration,             -- always 0 from ns:ItemDisplayInfo; overwritten by SeedItemTracker if a real cooldown reads back
  section = targetSection,              -- the container dropped into
  layoutOrder = maxOrder + 1,           -- same max-order-plus-one scheme as every other entry
  trackerType = "item",                 -- new value this task adds
  spellID = nil,                        -- unchanged: cooldownSpellID or nil, always nil for an item drop
  itemID = itemID,                      -- new field this task adds
  iconOverride = info.icon,             -- new field this task adds -- ns:ItemCatalogueIcon(itemID) or 134400, captured at creation, never re-derived
}
-- then, only when itemID is present:
ns:SeedItemTracker(key, itemID, entry) -- may overwrite entry.duration and ns.cooldownStarts[key] from a guarded live read
ns:MarkTrackersDirty()                  -- unconditional, nil-guarded, once per call regardless of trackerType
```

## Decisions Made

- D-05 consumed exactly as specified: one `ns:SeedItemTracker` call, gated on `itemID` truthiness, placed after the entry table is written (so `ns.db.trackedBuffs[key]` exists for the function to mutate by reference).
- `BAG_UPDATE_DELAYED` reused rather than adding a reconcile to the plain `BAG_UPDATE` branch — per `CONTEXT.md`'s discretion note, preferring an already-registered event whose own comment already documents it firing once per burst.
- Mid-task self-correction: Task 2's D-05 comment first named the literal `C_Item.GetItemCooldown`/`C_Item.GetItemCount` API calls in prose, which tripped the task's own S4 gate (`grep -cE 'C_Item\.GetItemCooldown|C_Item\.GetItemCount' CDMTab.lua` = 0) because that gate is a blunt whole-file grep with no comment/code distinction — the same pattern 47-01's summary documented for `Providers.lua`. Reworded to "the one guarded cooldown-and-count read" with no functional change; caught and fixed before commit, not a runtime bug.

## Deviations from Plan

None affecting shipped behavior. One gate observation worth recording:

**Gate S3 (whole-file zero flavour-detection tokens in `Core.lua`) is unsatisfiable as literally written, and was reported rather than weakened.**

- **Found during:** Task 1, running the plan's own `<automated>` verify command.
- **What was found:** `Core.lua:565-576` (pre-existing, unrelated to this plan) contains `local buildInterfaceVersion = select(4, GetBuildInfo())` and the `isForeverBuild` range check it feeds. Its own header comment identifies it as "the milestones one sanctioned runtime flavour check, licensed by explicit user decision 2026-09-20" (Phase 37, `RANK-01`/`RANK-02`/`ADD-03`), predating this phase entirely and explicitly locked — "No second flavour check may be added anywhere in this addon," which this plan does not.
- **Why it is unsatisfiable, not a bug:** confirmed via `git show HEAD:Core.lua` before any Task 1 edit — the three matching lines were already present, byte-identical, before this plan touched the file. `47-VALIDATION.md`'s own S3 row scopes the check to "`<changed files>`" (i.e., the diff), but this plan's literal embedded gate command runs an unscoped `grep -cE ... Core.lua` against the whole file. A whole-file scan of `Core.lua` can never return 0 for this token set without deleting Phase 37's locked, sanctioned exception — which is out of this plan's scope (`<do_not_touch>` boundary: this plan touches only `ns:GetTrackerCategory` and the dispatch branches) and would violate a separate locked decision.
- **Action taken:** did not weaken or remove the check; verified every other clause of Task 1's compound gate independently (all passed), ran `stylua .` / `stylua --check .` / `git ls-files --eol` separately (all passed), and am reporting this here per the plan's own instruction: *"If you believe a gate is unsatisfiable by any correct implementation, stop and report it — do not weaken it and do not bend the code to match."*
- **CDMTab.lua's equivalent gate (S3, Task 2) passed cleanly** — that file has no pre-existing flavour check, so no analogous issue exists there.
- **Committed in:** not applicable — no code change resulted from this finding; `8aed9bc` is otherwise unaffected.

## Issues Encountered

None beyond the gate observation above. Both tasks' remaining `<automated>` verify clauses passed on the first post-fix run.

## User Setup Required

None — no external service configuration required. `./scripts/install.bat` deployed cleanly to all four detected WoW client folders with no Lua load errors.

## Next Phase Readiness

- Plan 03 (rendering) can now rely on a real `item:` entry existing in `ns.db.trackedBuffs` after a drop, filed under the Cooldowns category, carrying `trackerType`, `itemID`, `iconOverride`, a seeded `duration`, and a seeded `ns.cooldownStarts[key]` when the item was already on cooldown at drop time.
- **The tile still does not render after this plan**, exactly as scoped — `Display.lua`'s dispatch gate is Plan 03's, per this plan's own `<objective>`. A created-but-invisible tracker is the expected state, not a failure, until Plan 03 lands.
- Positive evidence beyond the source-level gates: log out and back in and inspect `TerribleBuffTrackerDB` for an `item:` key, per this plan's own `<verification>` note — not performed here since it requires a live client session, consistent with the plan's own suggested verification path.
- No blockers. Phase 46's carry-over in-game verification risk (noted in `47-CONTEXT.md`) still applies unchanged by this plan.

---
*Phase: 47-item-tracking-cooldown-sharing*
*Completed: 2026-09-24*
