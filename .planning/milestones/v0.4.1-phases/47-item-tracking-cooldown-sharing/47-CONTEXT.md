# Phase 47: Item Tracking & Cooldown Sharing - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous), questions front-loaded and answered by the user before work began

<domain>
## Phase Boundary

Dragging a Suggested item tile into a container creates a real cooldown tracker for that item. Its
displayed cooldown and its count stay correct through use, looting and combat: any item use
refreshes every tracked item's cooldown (so shared cooldowns show up for free), the count decreases
only when a use actually lands, the count reconciles against the bags when combat ends, and a
tracked item keeps its tile and its running cooldown after the stack hits zero and the item leaves
the bags.

Requirements: ITEM-02, ITEM-04, ITEM-05, ITEM-06, ITEM-07, ITEM-09.

**Depends on Phase 46**, which is code-complete but **not yet verified in game**. See the carry-over
note at the end of `<code_context>` — it changes what "done" can mean for this phase too.

</domain>

<decisions>
## Implementation Decisions

### Detecting a landed use — USER DECISION, front-loaded 2026-09-24

**Build a use-spell → itemID map at catalogue scan time. Use no hooks at all on the production
path.**

- The probe measured that the four item-use hooks (`UseAction`, `C_Container.UseContainerItem`,
  `UseInventoryItem`, `C_Item.UseItemByName`) fire on the **button press, not a successful use**: a
  healthstone press produced no cooldown and no count change, and the same item worked 20s later.
  Never infer a use from a hook.
- `UNIT_SPELLCAST_SUCCEEDED` is what says the use landed. `PotProviderMixin` already proves the
  event reaches item-triggered casts (`Providers.lua:508` matches `POT_SPELLS[spellID]`).
- So: record `useSpellID -> itemID` while scanning, and an arriving `UNIT_SPELLCAST_SUCCEEDED`
  whose spellID is in that map **is** the landed use for that item.
- **This costs no extra API call.** `ns:RefreshItemCatalogue` already calls
  `C_Item.GetItemSpell(itemID)` as half of the ITEM-08 filter (`Providers.lua:969`) and currently
  discards the spellID. Capture it into one more itemID-keyed side table alongside
  `itemCatalogueIcons` / `itemCatalogueCounts`, wiped with the rest.
- Rejected: promoting `Core.lua`'s debug `pendingItemCasts` bridge (hook stamps the effect spellID,
  the arriving cast claims it within a 1s window) into production. It would keep four hooks live in
  a hot path to solve a problem the map already solves. **The debug log keeps its own hooks —
  do not touch, move, or generalise `Core.lua`'s debug cast/item log.** It is a separate feature
  the user asked for and it works.
- Known gap, accepted: two catalogued items sharing one use-spell would make the map ambiguous. The
  Phase 46 research looked and found no evidence either way. Last writer would win. If the planner
  can make the map detect a collision cheaply (a second write to an occupied key) it should log it
  under the existing debug flag rather than guess; it must not add a user-facing error.

### Cooldown reads — USER DECISION, front-loaded 2026-09-24

- **Per-item `C_Item.GetItemCooldown(itemID)`, keyed by itemID, never by bag/slot.** Bag/slot is
  positional and shifts when stacks split or bags are sorted.
- **Spell categories are not used.** Dropped by user decision. A per-item read already reflects a
  shared cooldown — drinking a health potion reports the shared cooldown on the mana potion too —
  so ITEM-05 comes for free from re-reading every tracked item, with no category table.
- On a landed use, re-read the cooldown for **every tracked item**, not just the one used. That is
  the whole mechanism behind ITEM-05.
- Also refresh on `BAG_UPDATE_COOLDOWN`, already registered at `Core.lua:859`. It covers use paths
  the map does not catch and is the event Blizzard's own cooldown item listens to.
- **Stamp `start + duration` at the moment of the landed use.** This is what closes ITEM-09 for
  free: that is the last moment the value is certainly readable, so a tracked item whose stack has
  hit zero and left the bags keeps its running cooldown from the stamp even if `GetItemCooldown`
  stops answering. Whether it still answers at zero count was left untested by explicit user
  decision — the stamp makes the answer unnecessary.
- **Flavour-agnostic with secret guards**, per the same front-loaded decision as Phase 46: every
  read `issecretvalue()` first, then `type()`. Where a value is unreadable, fall back to the
  stamped value; where there is no stamp either, render the tile with no sweep rather than erroring.

### Count maintenance — USER DECISION, reaffirmed 2026-09-24

- **Decrement by 1 on the landed use.** The user considered reading `GetItemCount` live instead and
  chose the decrement explicitly: *"Decreasing item by 1 will cover 99% of the cases and no overhad
  so this IS how we're gonna handle this."* I noted once that `GetItemCount` is an indexed lookup
  rather than a bag scan; the user's decision stands and is not to be relitigated.
- **Reconcile against `C_Item.GetItemCount(itemID)` when combat ends** (`PLAYER_REGEN_ENABLED`),
  and out of combat on bag changes. This absorbs the residual drift the decrement cannot track:
  looting more mid-fight, several items consumed at once, a stack traded away.
- ITEM-06 is specifically "never when a press is refused". The map-based detection satisfies this
  by construction — a refused press produces no `UNIT_SPELLCAST_SUCCEEDED`.
- A count must never go below zero.

### Tracker creation and the Suggested list

- `AddSuggestedTracker` (`CDMTab.lua:101`) currently **no-ops** for an `item:` key — it matches
  neither `ns:CooldownKeySpellID` nor `ns.SUGGESTED_KEYS` membership. Phase 46 left that
  deliberately (gate G7). **This phase is what makes the drop real.**
- The created entry is `ns.db.trackedBuffs["item:<itemID>"]` with `trackerType = "item"`, carrying
  `itemID`. **No schema bump** — additive only, same precedent as `userContainers`.
- `ns:GetTrackerCategory` (`Core.lua:99`) returns `"spells"` only for `trackerType == "cooldown"`
  today. An `item:` entry must also read as `"spells"` so it files under the Cooldowns tab. Without
  that, a tracked item would be filtered out of its own tab by the category test at
  `CDMTab.lua:834`.
- **A tracked item drops out of Suggested** (ITEM-02). Phase 46's render loop already filters on
  `ns.db.trackedBuffs["item:"..itemID]`, so this should follow with no new code — confirm it does.
- Item trackers render **icon-only with a count**, matching the v0.4.0 decision that cooldowns
  render as icons only. Not bars.

### Claude's Discretion

- Where the tracked-item state lives (`ns.cooldownStarts` is keyed by tracker key already, and an
  `item:` key is just another key — reuse it if it fits rather than adding a parallel table).
- Whether the reconcile listens to `BAG_UPDATE` out of combat or only to `PLAYER_REGEN_ENABLED`
  plus the existing `BAG_UPDATE_DELAYED`. Prefer reusing an event already registered.
- Exact shape of the collision detection on the use-spell map, if it is cheap.

</decisions>

<code_context>
## Existing Code Insights

### What Phase 46 shipped that this phase builds on

All in `Providers.lua` unless noted. Verified against the shipped source, not from a summary:

- `ns.ITEM_KEY_PREFIX = "item:"` and `ns:ItemKeyItemID(key)` — `Core.lua:505,509-514`
- `ns:RefreshItemCatalogue()` — `Providers.lua:923`. Wipes and refills four module-level tables:
  `itemCatalogueIDs` (ascending admitted list), `itemCatalogueIcons`, `itemCatalogueCounts`
  (both itemID-keyed), `itemCatalogueSeen` (scratch). Never reallocated.
- `ns:ItemCatalogue()`, `ns:ItemCatalogueCount(itemID)`, `ns:ItemCatalogueIcon(itemID)`
- `ns:MarkItemCatalogueDirty()`, `ns:IsItemCatalogueDirty()`, `ns.RequestItemCatalogueRebuild`
- `ns:ItemDisplayInfo` and the `item:` branch in `ns:GetDisplayInfoForKey` (`:1275-1278`), placed
  before the `cd:` reject at `:1285` — an `item:` key must never fall through to
  `UserSpellProvider`, which treats any resolved key as a spellID.
- `CDMTab.lua`: `chargeCount` fontstring on `CreateIconFrame` (`:208-213`), cleared on pool release
  (`:725-740`), item tile loop in `ns:RefreshTBTSections` (`:870-901`), scan warmed from
  `StartPreview` (`:36-37`), `BAG_UPDATE` coalescer (`:53-70`).

**The use-spell is resolved but discarded.** `Providers.lua:969` does
`local _, useSpellID = C_Item.GetItemSpell(itemID)` purely as a filter test. Capturing it is the
single cheapest change in this phase.

### Established patterns

- `issecretvalue()` **before** `type()`, always — and before a truthiness test too. Phase 46 has a
  worked example at `Providers.lua:970`: a secret non-nil spellID is truthy under a naive
  `if useSpellID then`, which would admit an item on false evidence.
- Providers own event routing: `GetEventInterests()` / `OnTrigger()` via
  `ns:DispatchEventToProviders` (`Providers.lua:1168`), which is the single writer of
  `ns.activeTimers` for cast-triggered procs. An item provider follows `SpellProviderBaseMixin`
  (`:14-59`) and registers in `ns.providers` (`:1084`).
- `ns.cooldownStarts` + `ns:IsCooldownRunning(key, entry, now)` (`Core.lua:~500`) — the existing
  single answer for "is this cooldown running", shared by the render path and the preview builder.
- Reusable module-level tables wiped with `wipe()`. No per-frame allocation in hot paths.
- One code path for both flavours. No runtime flavour check.
- `stylua` bare from repo root; `.gitattributes` pins `*.lua` to `eol=crlf`.

### Carry-over risk from Phase 46 — read this before planning

**Phase 46 is code-complete but NOT verified in game.** Its four requirements (ITEM-01, 03, 08, 10)
are still open, pending the G1..G7 gate in
`.planning/phases/46-item-catalogue-suggested-tiles/46-VERIFICATION.md`. This project has no test
runner, so nothing short of opening a real Cooldown Manager confirms the catalogue and its tiles
actually work.

Phase 47 builds on Phase 46's **interfaces**, which are statically verified and stable. That is why
proceeding is reasonable. But if the in-game gate later fails — say the filter over-reaches, or a
tile renders without its count — the fix lands in Phase 46's code and this phase's work sits on top
of it. Plan so that this phase's additions are separable from the catalogue's own correctness:
depend on the documented function contracts above, not on incidental details of how the catalogue
fills its tables.

</code_context>

<specifics>
## Specific Ideas

- The settled design is ROADMAP backlog entry **999.6**, points 3, 4 and 5 specifically. Read it
  before planning — it is measured, agreed shape, not a proposal.
- Measured on Forever 1.60.1: **all potions share one 120s cooldown** (a Lesser Healing Potion put
  both a Minor Mana Potion and a Minor Rejuvenation Potion on 120s), and the **healthstone is
  independent**, also 120s. This differs from retail, where combat and health potions are separate
  categories. It is also exactly why the per-item read beats a category table: the per-item read is
  correct on both clients without knowing any of this.
- At count 0 the item vanishes from the bag walk entirely while its cooldown still runs. ITEM-09 is
  precisely about that case.
- Engineering-explosive cooldown sharing was left untested by user decision — the per-item read
  makes the answer unnecessary.
- **Bandages are out of scope entirely** and are already excluded from the catalogue by Phase 46's
  `subClassID ~= 7` filter. They are blocked by the platform, not by design: the gate is a debuff
  (Recently Bandaged, spell 11196, 60s) with no item cooldown at all, auras cannot be read in
  combat on Forever, and the debuff lands on the recipient rather than the caster.

</specifics>

<deferred>
## Deferred Ideas

- **Bandage tracking** — blocked by the platform, findings recorded in ROADMAP 999.6 and in
  REQUIREMENTS.md's Future Requirements. Revisit only if that debuff becomes readable in combat.
- **Whether `GetItemCooldown` answers for a zero-count item** — gap accepted by user decision. The
  stamp-at-use design closes it for free, which is why it stays untested.
- **Engineering-explosive cooldown sharing** — left untested by user decision.
- Refining the `0/8` catalogue residue (glue, campfire kit, lute, crate). Explicitly left for later
  in the milestone per 999.6 section 1. It is Phase 46's filter, not this phase's.

</deferred>
