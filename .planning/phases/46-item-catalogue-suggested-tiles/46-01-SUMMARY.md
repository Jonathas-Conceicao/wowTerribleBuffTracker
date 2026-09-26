---
phase: 46-item-catalogue-suggested-tiles
plan: 01
subsystem: ui
tags: [wow-addon, lua, c_item, c_container, cooldown-manager, secret-values]

# Dependency graph
requires:
  - phase: 45-documentation
    provides: v0.4.0 shipped baseline (cooldown trackers, cd:<spellID> key namespace, providers)
provides:
  - "ns.ITEM_KEY_PREFIX and ns:ItemKeyItemID(key) -- the item: key namespace parser"
  - "ns:RefreshItemCatalogue() -- bag-derived consumables catalogue builder"
  - "ns:ItemCatalogue() / ns:ItemCatalogueIcon(itemID) / ns:ItemCatalogueCount(itemID) accessors"
  - "ns:MarkItemCatalogueDirty() / ns:IsItemCatalogueDirty() dirty-flag pair"
affects: [46-02-scan-trigger, 46-03-suggested-tile-render, 47-tracker-creation-from-tile]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "item:<itemID> as a third ns.db.trackedBuffs key namespace, twin of cd:<spellID>"
    - "Two-pass bag scan: discovery (bag walk into a scratch de-dup set) then classification (one C_Item.GetItemInfoInstant/GetItemSpell/GetItemCount pass per distinct itemID)"
    - "issecretvalue(v) textually before type(v)/== on every new C_Item/C_Container read"
    - "Module-level tables wiped with wipe() and refilled, never reallocated, zero table constructors inside loops"

key-files:
  created: []
  modified:
    - Core.lua
    - Providers.lua

key-decisions:
  - "GetItemInfoInstant destructured as 7 bare-call positions (itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID) -- NOT the probe's pcall-shifted 8-slot pattern"
  - "Icon reused from the same GetItemInfoInstant call rather than a second GetItemIconByID call (research-corrected from CONTEXT.md's original naming)"
  - "No key constructor added for item: -- only the parser and constant; minting keys is Phase 47"

patterns-established:
  - "Bag walk over literal bag = 0, 5 (not Enum.BagIndex.*) as the cross-flavour-safe idiom for future bag-derived catalogues"

requirements-completed: [ITEM-01, ITEM-08, ITEM-10]

# Metrics
duration: 4min
completed: 2026-09-24
---

# Phase 46 Plan 01: Item Catalogue Builder Summary

**Bag-derived consumables catalogue keyed by itemID, filtered by taxonomy only (classID/subClassID/use-spell), cached in wiped module-level tables with an `item:<itemID>` key namespace parser -- nothing calls any of it yet.**

## Performance

- **Duration:** ~4 min (two tasks, both single-pass)
- **Started:** 2026-09-24T10:49:52Z
- **Completed:** 2026-09-24T10:53:34Z
- **Tasks:** 2/2 completed
- **Files modified:** 2

## Accomplishments
- `ns.ITEM_KEY_PREFIX` / `ns:ItemKeyItemID` added to `Core.lua`, the structural twin of the existing `cd:` cooldown namespace, with no schema bump and no key constructor
- `ns:RefreshItemCatalogue` added to `Providers.lua`: a two-pass bag scan (discovery via `C_Container.GetContainerNumSlots`/`GetContainerItemID`, then classification via `C_Item.GetItemInfoInstant`/`GetItemSpell`/`GetItemCount`) producing an itemID-keyed, ascending-sorted catalogue with icon and count caches
- Five accessor functions (`ns:ItemCatalogue`, `ns:ItemCatalogueIcon`, `ns:ItemCatalogueCount`, `ns:MarkItemCatalogueDirty`, `ns:IsItemCatalogueDirty`) exposed for Plan 02/03 to consume

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the item: key namespace to Core.lua** - `aff8b82` (feat)
2. **Task 2: Build the bag-derived consumables catalogue in Providers.lua** - `af9ddf8` (feat)

**Plan metadata:** committed alongside this summary.

## Files Created/Modified
- `Core.lua` - Added `ns.ITEM_KEY_PREFIX = "item:"` and `ns:ItemKeyItemID(key)` immediately after `ns:CooldownKeySpellID`
- `Providers.lua` - Added the item catalogue section (four module-level tables, `ns:RefreshItemCatalogue`, and five accessor functions) immediately after `ns:RacialCooldownSeed`

## Decisions Made

- **`GetItemInfoInstant` destructuring position count.** The research flagged a pcall-shift trap in the probe's own transcription. The bare-call destructure here consumes exactly seven positions (`_, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)`), counted directly against the doc's return order rather than copied from `tools/TBTProbe/Probe.lua`.
- **Icon source: reuse, not a second call.** `GetItemInfoInstant`'s own `icon` return (captured during the classification pass) is stored directly, guarded `issecretvalue()` then `type()`. No `C_Item.GetItemIconByID` call exists anywhere in the new code -- verified by the grep gate.
- **Discovery/classification split as two passes over the bag walk**, rather than classifying inline per-slot: this keeps the de-dup set (`itemCatalogueSeen`) as the sole per-slot write, and the classification (7-value destructure, three API calls) runs exactly once per distinct itemID rather than once per slot -- fewer redundant `C_Item.*` calls when a stack is split across bags.
- **No `InCombatLockdown()` gate added.** CONTEXT.md's Scan Cadence section specifies none, and ROADMAP 999.6 measured item counts readable in combat on Forever.

## Deviations from Plan

None - plan executed exactly as written. Every task, acceptance criterion and threat-model mitigation (T-46-01, T-46-02, T-46-03) was implemented as specified; no Rule 1-4 deviations were needed.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. Both new subsystems (`Core.lua`'s key namespace, `Providers.lua`'s catalogue builder) are fully implemented per spec; the plan's own scope boundary is that nothing calls them yet (Plan 02 wires the trigger, Plan 03 renders), which is a documented "not yet wired" state rather than a stub.

## Threat Flags

None. All new API-read surface (`GetContainerItemID`, `GetItemInfoInstant`'s `classID`/`subClassID`/`icon`, `GetItemSpell`'s spellID, `GetItemCount`'s count) was already enumerated in the plan's `<threat_model>` (T-46-01, T-46-02) and mitigated as specified -- no new surface outside that register was introduced.

## Next Phase Readiness

- `ns.ITEM_KEY_PREFIX`, `ns:ItemKeyItemID`, and all five catalogue accessors exist with the exact names and shapes Plan 02/03 are contracted to consume (see this plan's `<interfaces>` block).
- The final `GetItemInfoInstant` destructuring line, for Plan 02/Phase 47 readers to confirm the position count:
  ```lua
  local _, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
  ```
- Exported function names, final and unrenamed: `ns:RefreshItemCatalogue`, `ns:ItemCatalogue`, `ns:ItemCatalogueIcon`, `ns:ItemCatalogueCount`, `ns:MarkItemCatalogueDirty`, `ns:IsItemCatalogueDirty`, plus `ns.ITEM_KEY_PREFIX` and `ns:ItemKeyItemID`.
- No blockers. The addon still loads and behaves identically to before this plan -- nothing calls the new code yet, confirmed by a repo-wide grep finding zero references outside `Core.lua`/`Providers.lua`.

---
*Phase: 46-item-catalogue-suggested-tiles*
*Completed: 2026-09-24*

## Self-Check: PASSED

- FOUND: `Core.lua`
- FOUND: `Providers.lua`
- FOUND: `.planning/phases/46-item-catalogue-suggested-tiles/46-01-SUMMARY.md`
- FOUND: commit `aff8b82` (Task 1)
- FOUND: commit `af9ddf8` (Task 2)
- FOUND: commit `58cf6c7` (docs: SUMMARY.md)
