---
phase: 46-item-catalogue-suggested-tiles
plan: 03
subsystem: ui
tags: [wow-addon, lua, cooldown-manager, frame-pooling, secret-values]

# Dependency graph
requires:
  - phase: 46-item-catalogue-suggested-tiles
    plan: 01
    provides: ns.ITEM_KEY_PREFIX, the bag-derived catalogue, ns:ItemCatalogue()/ns:ItemCatalogueCount()
  - phase: 46-item-catalogue-suggested-tiles
    plan: 02
    provides: item -- branch in ns:GetDisplayInfoForKey, the CDM-open scan, the BAG_UPDATE dirty flag
provides:
  - "frame.chargeCount / frame.chargeCount.Current on every CreateIconFrame tile (CDMTab.lua)"
  - "the item tile render loop inside ns:RefreshTBTSections's suggested/spells branch"
affects: [47-tracker-creation-from-tile]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "chargeCount clear-and-hide lives in the itemPool reset function, not in per-loop Acquire() call sites -- a single discipline point covers every pooled-frame reuse path"
    - "item tile loop continues the racial loop's suggestedSlot local rather than declaring a new one, so appended tiles never shift earlier tile positions"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "chargeCount added directly to CreateIconFrame's f frame, not layered above a Cooldown/CooldownFrameTemplate widget -- CreateIconFrame has none, so Display.lua's swipe-ordering rationale does not transfer and the new comment says so explicitly rather than silently omitting it"
  - "count written via `if count then ... else ... end` (count is either a number or nil per ns:ItemCatalogueCount's contract) rather than an explicit type() check -- the guard already ran once at catalogue-scan time (Plan 01); the render path's job is only to route a nil to Hide()"

requirements-completed: [ITEM-03, ITEM-10]

# Metrics
duration: 6min
completed: 2026-09-24
---

# Phase 46 Plan 03: Charge-Count Fontstring & Item Tile Render Loop Summary

**Adds a charge-count fontstring to the shared Suggested-tile factory and appends a catalogue-driven item tile loop after the racial cooldown tiles, so every untracked bag consumable renders with its own icon and current count -- zero bag or item-classification API calls on the render path.**

## Performance

- **Duration:** ~6 min (two tasks, each single-pass, no deviations)
- **Started:** 2026-09-24T10:59:00Z (approx, first read)
- **Completed:** 2026-09-24T11:06:36Z
- **Tasks:** 2/2 completed
- **Files modified:** 1

## Accomplishments

- `CreateIconFrame` (`CDMTab.lua`) now builds `f.chargeCount` / `f.chargeCount.Current` on every tile it produces, copied field-for-field from `Display.lua:478-483` (`NumberFontNormal`, `BOTTOMRIGHT -2 2`, hidden on creation) -- the exact style a cooldown icon's charge count already uses
- `section.itemPool`'s `CreateObjectPool` reset function now clears and hides `chargeCount` alongside the existing `spellID`/`sectionName`/`layoutIndex` nils, so a pooled tile recycled from an item slot into a racial or tracked slot never shows a stale count
- The Cooldowns tab's Suggested branch (`ns:RefreshTBTSections`) gained an item tile loop, positioned immediately after the existing racial `ipairs(ns:RacialCooldownKeys())` loop and reusing its `suggestedSlot` local, so item tiles are appended after the racial tiles without shifting their position
- Each item tile: skips already-tracked items (`ns.db.trackedBuffs["item:"..itemID]`), stores the opaque `item:<itemID>` key in the existing `item.spellID` field, resolves icon via `ns:GetDisplayInfoForKey` with a `134400` fallback, and shows/hides `chargeCount` from `ns:ItemCatalogueCount(itemID)` -- a number shows the count, `nil` (scan-time `issecretvalue`/`type` rejection) hides the fontstring rather than erroring or showing a stale value

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the charge-count fontstring to CreateIconFrame and clear it on pool release** - `3b6c326` (feat)
2. **Task 2: Append the item tile loop to the Cooldowns tab's Suggested branch** - `d2d08f5` (feat)

**Plan metadata:** committed alongside this summary.

## Files Created/Modified

- `CDMTab.lua` -- `CreateIconFrame` gained the `chargeCount` construction block; the `section.itemPool` reset function gained the `chargeCount` clear-and-hide pair; `ns:RefreshTBTSections`'s `suggested`/`spells` branch gained the item tile loop, appended after the racial loop and before the `elseif def.key == "suggested" and ns.tbtActiveCategory ~= "buffs"` branch

## Decisions Made

- **No `item.itemID` field.** The itemID is recoverable from the opaque key (`ns.ITEM_KEY_PREFIX .. itemID` / `ns:ItemKeyItemID(key)` if a future reader needs it back out), and every existing tile handler (`OnMouseDown`/`BeginDrag`, `OnEnter` tooltip, `OnMouseUp` right-click) reads `self.spellID` as an opaque string. Storing the key there rather than inventing a parallel field is what makes every existing handler work on an item tile with zero changes to those handlers.
- **No `item.suggestedIndex` on item tiles.** `grep -n suggestedIndex CDMTab.lua` after this plan finds exactly the two pre-existing write sites (racial loop, static `SUGGESTED_KEYS` loop) and no reader anywhere. There is nothing for a bag-derived list to index into, so the field was left unwritten on item tiles per the plan's explicit instruction, rather than added defensively.
- **The racial loop's `-- No ns:IsSuggestedKeyResolvable call` reasoning was not copied verbatim.** The new comment states the item-specific reason instead (a bag-derived, per-character-inventory list has no "does this client support this key at all" question to ask; the catalogue's own taxonomy filter is the equivalent gate) rather than reusing the race-specific rationale, per the plan's explicit warning not to import a reason that does not hold here.

## Deviations from Plan

None - plan executed exactly as written. Every task, acceptance criterion, and threat-model mitigation (T-46-08, T-46-09, T-46-11) was implemented as specified; T-46-10 is an accepted disposition requiring no code change. No Rule 1-4 deviations were needed, and no verify gate proved unsatisfiable.

## Issues Encountered

None. All automated verify gates in both tasks passed as written on the first run, including the `stylua --check .` / `git ls-files --eol CDMTab.lua` pair and the `suggestedSlot` declaration-count and flavour-token-count assertions.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. Both the fontstring and the render loop are fully wired against Plan 01/02's live catalogue and dispatch functions; nothing here renders a placeholder or hardcoded empty value.

## Threat Flags

None. All new read surface (`ns:ItemCatalogue()`, `ns:ItemCatalogueCount(itemID)`, `ns.db.trackedBuffs` membership) was already enumerated in this plan's own `<threat_model>` (T-46-08, T-46-09, T-46-10, T-46-11) and mitigated exactly as specified. No new network endpoint, auth path, file-access pattern, or schema change was introduced -- the `item:` key namespace itself was Plan 01's surface, not this plan's.

## Next Phase Readiness

- **`suggestedSlot` continuation shape confirmed for Phase 47:** the item loop lives inside the same `def.key == "suggested" and ns.tbtActiveCategory == "spells"` branch as the racial loop, reuses its `suggestedSlot` local without resetting it, and the `local suggestedSlot = SUGGESTED_RESERVED_SLOTS` declaration count in `CDMTab.lua` stayed at exactly 2 (one in this branch, one in the static `SUGGESTED_KEYS` branch) -- no third counter was introduced, so racial tile positions are unaffected and item tiles always render last within the spells-tab Suggested section.
- **`AddSuggestedTracker` (`CDMTab.lua:139-160`) is byte-unchanged** -- confirmed both by the plan's own diff-scope (single hunk, entirely inside `ns:RefreshTBTSections`, `git diff --stat` shows 49 insertions and 0 deletions for Task 2) and by direct inspection. An `item:` key still falls through it as a no-op: it matches neither `ns:CooldownKeySpellID` nor any `ns.SUGGESTED_KEYS` entry, so no entry is created on drop. This is the documented Phase 46 boundary (gate G7); Phase 47 (ITEM-04) teaches it about `item:` keys.
- Item tiles are visually and structurally ready for in-game verification (Plan 04's G1-G5/G7 gates): each carries its own icon (with the `134400` fallback), a charge count in the exact `NumberFontNormal`/`BOTTOMRIGHT -2 2` style a cooldown icon uses, and is draggable in the same sense every other Suggested tile is (the drag itself no-ops per the accepted gap above).
- No blockers for Plan 04.

---
*Phase: 46-item-catalogue-suggested-tiles*
*Completed: 2026-09-24*
