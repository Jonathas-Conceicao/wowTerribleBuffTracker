# Phase 76: Buff Duration on Bag Items - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning
**Mode:** Context front-loaded for the autonomous run (73-77)

<domain>
## Phase Boundary

A bag item tracker (kind `metaItem` with a numeric `entry.itemID`, created from a Suggested item tile)
can carry its buff exactly like a spell cooldown (Phase 74) and shows it with the Phase 75 look.
Requirements BUFFCD-05, 06, 07.

</domain>

<decisions>
## Implementation Decisions

### Which trackers
- **Bag items only** — `metaItem` entries with a numeric `itemID` (Core.lua:486-488, 580-594). The
  Trinket and Pot meta-trackers (`metaItem:trinket`, `metaItem:pot`) are buff timers already and are
  **out of scope**; so are Lust, metaReminder and every other kind.

### Edit entry and dialog
- A bag item tracker **moved out of Suggested** gets an **Edit** entry in its right-click menu
  (CDMTab.lua ~405-447). A **Suggested** item tile still has none (BUFFCD-06).
- `ns:IsEditableTracker` (BuffEngine.lua:1036-1042) admits bag items — but only for this limited
  edit; check every other caller of it so nothing else (e.g. a full edit path, duplicate/remove
  behaviour) changes for items by accident.
- The item's edit dialog shows the item's existing fields **with their values, greyed out and not
  editable** — **every** field except the three buff fields, the load rule included (user, kickoff).
  Use the greyed field state built in Phase 74.
- Editable: the "Track buff duration" checkbox (off by default), the **Aura ID (empty by default —
  no pre-fill for items**, user decision), and the Duration. Same save rule as Phase 74: with the
  checkbox on, both must be filled (Aura ID and a positive Duration).
- Title: an "Edit Item" style title via `EDIT_TITLE_BY_KIND` (wording at discretion).

### Timer behaviour
- Using the item starts its buff timer alongside the item cooldown. Item use is recognised by
  `MetaItemBagProviderMixin:OnTrigger` (Providers.lua ~1695-1733) through the `itemUseSpellToID`
  map (use-spell → itemID). Two items can share one use-spell (known, accepted "last writer wins");
  start the buff for the tracker whose item matched.
- Early end, recast, hidden-section and load rules: identical to Phase 74.
- Icon look: identical to Phase 75, item count (`ApplyItemCount`) stays visible.

### Saved data
- Same buff keys as Phase 74 on the item entry. **`entry.duration` on a bag item is overwritten by
  the game's item cooldown on every refresh** (`ns:RefreshTrackedItemCooldowns`, Providers.lua
  ~1518-1540; `ns:SeedItemTracker` ~1474-1511) — the buff duration must live in its own key and the
  refresh must never touch it.
- `AddSuggestedTracker` (CDMTab.lua 150-246) re-adding/moving an item must not wipe its buff keys.
- Missing keys mean off; no schema bump unless genuinely needed.

### Claude's Discretion
- Plan split; how the greyed state is applied per field for items.

</decisions>

<code_context>
## Existing Code Insights

- Item catalogue `ns:RefreshItemCatalogue` (Providers.lua:1295-1402); Suggested tiles
  (CDMTab.lua:983-1034, key `ns:TrackerKey(META_ITEM, itemID)`); `AddSuggestedTracker`
  (CDMTab.lua:150-246); `ns:SeedItemTracker` (Providers.lua:1474-1511);
  `ns:RefreshTrackedItemCooldowns` (:1518-1540); `MetaItemBagProviderMixin:OnTrigger` (:1695-1733).
- Bag items draw through `ApplyCooldownSlot` / `ApplyUserCooldown` like userCd.

</code_context>

<specifics>
## Specific Ideas

- Item aura ID ↔ use-spell parity was never observed live; the empty default and user entry make it
  irrelevant to the implementation.
- In-game checks deferred to Phase 78 (retail only).

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
