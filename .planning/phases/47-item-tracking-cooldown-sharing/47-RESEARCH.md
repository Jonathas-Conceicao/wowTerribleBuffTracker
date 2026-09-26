# Phase 47: Item Tracking & Cooldown Sharing - Research

**Researched:** 2026-09-24
**Domain:** WoW addon Lua — item-cooldown API integration, cast-driven state machines, existing
Cooldown-widget render path reuse
**Confidence:** HIGH (every load-bearing claim is either a direct read of TBT's own shipped source,
or cross-checked against the local Blizzard API doc / Blizzard's own CDM source)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Detecting a landed use — USER DECISION, front-loaded 2026-09-24**

Build a use-spell → itemID map at catalogue scan time. Use no hooks at all on the production path.

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

**Cooldown reads — USER DECISION, front-loaded 2026-09-24**

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

**Count maintenance — USER DECISION, reaffirmed 2026-09-24**

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

**Tracker creation and the Suggested list**

- `AddSuggestedTracker` (`CDMTab.lua:139`) currently **no-ops** for an `item:` key — it matches
  neither `ns:CooldownKeySpellID` nor `ns.SUGGESTED_KEYS` membership. Phase 46 left that
  deliberately (gate G7). **This phase is what makes the drop real.**
- The created entry is `ns.db.trackedBuffs["item:<itemID>"]` with `trackerType = "item"`, carrying
  `itemID`. **No schema bump** — additive only, same precedent as `userContainers`.
- `ns:GetTrackerCategory` (`Core.lua:99`) returns `"spells"` only for `trackerType == "cooldown"`
  today. An `item:` entry must also read as `"spells"` so it files under the Cooldowns tab. Without
  that, a tracked item would be filtered out of its own tab by the category test at
  `CDMTab.lua:944`.
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

### Deferred Ideas (OUT OF SCOPE)

- Bandages — excluded from the catalogue by Phase 46's `subClassID ~= 7` filter; no bandage
  handling in this phase.
- Engineering-explosive cooldown sharing — left untested by user decision.
- Whether `GetItemCooldown` answers for a zero-count item — gap accepted; the stamp-at-use design
  closes it for free.
- Everything Phase 46 already shipped: catalogue construction, Suggested-tile rendering, icon/count
  display in Suggested.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ITEM-02 | Every catalogued consumable that is not already tracked is offered in Suggested | Already true by construction (`CDMTab.lua:872`, `if not ns.db.trackedBuffs[itemKey] then`) — confirm-only, no new code; verified by direct read |
| ITEM-04 | Dragging a Suggested item creates an ordinary cooldown tracker | `AddSuggestedTracker` (`CDMTab.lua:139-185`) needs a third recognition branch for `item:` keys; exact edit sites and the two silent-failure traps (icon, category) are identified below |
| ITEM-05 | Using any item refreshes every item sharing its cooldown | Confirmed: Blizzard's own CDM does **not** call `C_Item.GetItemCooldown` per item at all — it resolves a spell category to a spellID and calls `C_Spell.GetSpellCooldown` (`CooldownViewerItemData.lua:47-57,380-383`). TBT's locked per-item design is the *right* choice, not merely an alternative — it needs no category table and is measured correct on Forever (999.6) |
| ITEM-06 | Count decreases only on a landed use | Map-based detection is structurally correct (a refused press never fires `UNIT_SPELLCAST_SUCCEEDED`) — confirmed via the doc's payload shape and TBT's own existing `PotProviderMixin` precedent |
| ITEM-07 | Count reconciles against bags on combat end | `PLAYER_REGEN_ENABLED` already registered and dispatched (`Core.lua:831,974-986`); `C_Item.GetItemCount` confirmed `Nilable=false` (`ItemDocumentation.lua:429-446`) — always answers a real number, 0 included, so the reconcile call is safe unconditionally |
| ITEM-09 | Tile and cooldown survive stack reaching zero | The stamp-at-use design plus TBT's existing `ApplyUserCooldown` render path (already plain-number-driven, no bag/game-state re-read per tick) makes this true by construction once the write side stamps correctly — confirmed via direct read of `Display.lua:954-1002` |
</phase_requirements>

## Summary

Every locked mechanism in CONTEXT.md is buildable with existing TBT infrastructure, and the two
biggest risks are not the ones CONTEXT.md names — they are **two silent-failure traps in the
render path** this research found by tracing the exact call graph a dragged `item:` tile goes
through. `C_Item.GetItemCooldown(itemID)` returns exactly `(startTimeSeconds, durationSeconds,
enableCooldownTimer)` with all three `Nilable = false`
[VERIFIED: `ItemDocumentation.lua:412-427`] — confirming CONTEXT.md's summary of the API. Critically,
**Blizzard's own Cooldown Manager never calls this function at all**: `CooldownViewerItemDataMixin`
resolves an item-backed cooldown through `C_Spell.GetLastCategoryCooldownSource(spellCategoryID)`
into a spellID and then calls `C_Spell.GetSpellCooldown(spellID)`
[VERIFIED: `CooldownViewerItemData.lua:47-57,380-383`; confirmed by grep that no
`Blizzard_CooldownViewer` file calls `C_Item.GetItemCooldown` anywhere]. This means the locked
per-item design is not merely "an alternative that also works" — it is the one approach that reads
correctly without Blizzard's own (undocumented, closed) category table, which is exactly why 999.6
measured it giving ITEM-05 "for free."

**The load-bearing rendering question (point 2) resolves cleanly, with a caveat neither CONTEXT.md
nor the phase boundary flags.** TBT's `CooldownFrameTemplate` widget is **already** driven from
plain `(start, duration)` numbers today, via the ordinary widget method
`icon.cooldown:SetCooldown(start, duration)` — not only through the tier-1 duration-object path.
The exact function is `ApplyUserCooldown` (`Display.lua:954-1002`), which every existing `cd:`
cooldown tracker already uses, is generic on `entry.key`/`entry.duration`/`ns.cooldownStarts`, makes
no game API call, and has **zero knowledge of spellID**. An `item:` entry that gets a real
`entry.duration` and a `ns.cooldownStarts["item:"..itemID]` timestamp drives this function
completely unmodified. **However, two other things in the same render pass are spellID-gated and
will silently fail for an item entry unless explicitly widened:**

1. `ApplyCachedIcon(icon, spellID, entry.iconOverride)` (`Display.lua:741-748,1278`) resolves the
   icon texture as `iconOverride or (spellID and GetSpellIcon(spellID)) or 134400`. An item entry's
   `spellID` is always `nil`, so **without setting `entry.iconOverride` at tracker-creation time,
   the tile renders the question-mark placeholder forever**, never the item's own icon — a defect
   that would look identical to "icon read failed" but is actually "nobody wrote the field."
2. `ApplyChargeCount(icon, spellID)` (`Display.lua:912-936`, called at `:1312`) is what currently
   writes `icon.chargeCount` for any `trackerType`-driven cooldown slot, and it is driven by
   `C_Spell.GetSpellCharges(spellID)`. For an item entry `spellID` is `nil`, so this call is a
   guaranteed `icon.chargeCount:Hide()` — **the count Phase 47 needs to show (decremented, not the
   Suggested list's live bag count) has no existing call site and must be added new**, parallel to
   `ApplyChargeCount`, gated on the entry carrying an itemID.

Both gaps are additive, not structural rewrites, and both are cited with exact line numbers below —
`.planning/phases/47-item-tracking-cooldown-sharing/47-PATTERNS.md` (already present in this phase
directory, written by an earlier pattern-mapping pass) independently reaches the same two findings
and the same line numbers, which is strong corroboration rather than duplicated guesswork; this
document treats PATTERNS.md as a verified secondary source and adds the Blizzard-source
cross-checks, the API return-shape verification, and the Validation Architecture PATTERNS.md does
not cover.

**Primary recommendation:** Build a new `ItemProviderMixin` in `Providers.lua`, copying
`PotProviderMixin`'s event-filter shape but **not** its proc-return contract — on a matched landed
use it must stamp `ns.cooldownStarts` and `entry.duration` for every tracked item directly (the same
"cooldown side effect, no proc" shape `UserSpellProviderMixin:OnTrigger` already uses for `cd:`
trackers, `Providers.lua:98-118`) and return `nil` unconditionally, since an item tracker has no
buff/timer side and must never enter `ns.activeTimers`. Extend `AddSuggestedTracker` with a third
`item:` recognition branch that sets `trackerType = "item"`, `itemID`, and — critically —
`iconOverride`. Widen `ns:GetTrackerCategory` and the `Display.lua:1999` dispatch gate to accept
`trackerType == "item"` alongside `"cooldown"`. Add one new count-render call beside
`ApplyChargeCount`'s call site, backed by a new runtime-only `ns.itemTrackedCounts` table
(decrement + reconcile), never `ns:ItemCatalogueCount` (which is the Suggested list's live bag
count and goes absent exactly when ITEM-09 needs the tile to keep showing a number).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Landed-use detection (useSpellID → itemID) | TBT Runtime (Lua, new `ItemProviderMixin`) | Game Client (`UNIT_SPELLCAST_SUCCEEDED`) | TBT owns the map and the match; the client owns the event that proves a use landed |
| Cooldown read (start/duration/enable) | Game Client (`C_Item.GetItemCooldown`) | TBT Runtime (stamp + cache) | The client is the sole authority on the actual cooldown; TBT stamps a copy so it survives the item leaving the bags |
| Count maintenance (decrement + reconcile) | TBT Runtime (Lua, new store) | Game Client (`C_Item.GetItemCount`, reconcile only) | The decrement is TBT's own arithmetic; only the periodic reconcile touches the client |
| Cooldown-sweep rendering | TBT Runtime (`Display.lua`, existing `ApplyUserCooldown`) | — | Fully client-independent once `entry.duration`/`ns.cooldownStarts` are populated — already true for `cd:` trackers, no new tier involved |
| Icon resolution for a tracked item tile | TBT Runtime (Lua, `entry.iconOverride`) | Game Client (`C_Item.GetItemIconByID` / cached from catalogue scan) | Resolved once at creation/scan time, never re-read on the render path (same discipline as every other tile) |
| Tracker persistence (`ns.db.trackedBuffs["item:..."]`) | TBT Runtime (SavedVariables) | — | Same table, same additive-only contract as `cd:` and buff entries |

## Standard Stack

Not applicable in the npm/pip sense. This phase adds no third-party dependency — every call is a
first-party WoW client API (`C_Item.*`, `UNIT_SPELLCAST_SUCCEEDED`) already present in the client
and already exercised elsewhere in this addon or by Phase 46's shipped code.

## Package Legitimacy Audit

**Not applicable.** No external package is installed by this phase. The Package Legitimacy Gate
protocol is skipped — there is nothing to run `slopcheck` or a registry check against.

## Architecture Patterns

### Data Flow Diagram

```
UNIT_SPELLCAST_SUCCEEDED (unit, castGUID, spellID)          UnitDocumentation.lua:4680-4693
        │  dispatched with zero branches from ns:OnSpellCastSucceeded (BuffEngine.lua:239-244)
        ▼
ns:DispatchEventToProviders("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellID)
        │  routes to every registered provider's OnTrigger, including the new ItemProvider
        ▼
[NEW] ItemProviderMixin:OnTrigger(event, unit, _, spellID)
        │  local itemID = itemUseSpellByID[spellID]      -- the locked use-spell map
        │  if not itemID then return nil end               -- not an item's use-spell: not our cast
        │
        │  A LANDED USE for itemID. Side effects only, no proc:
        │    1. Decrement ns.itemTrackedCounts["item:"..itemID], floor 0
        │    2. For EVERY entry in ns.db.trackedBuffs where trackerType=="item":
        │         local start, duration, enable = C_Item.GetItemCooldown(otherItemID)
        │         issecretvalue() guard, THEN type() guard, THEN enable truthiness guard
        │         if readable and enable: entry.duration = duration; ns.cooldownStarts[key] = start
        │         if unreadable: leave the existing stamp untouched (locked degrade rule)
        │    3. ns:MarkCooldownsDirty()   -- same generation bump "cd:" trackers already use
        │  return nil                                      -- never enters ns.activeTimers
        ▼
Render tick (every UPDATE_INTERVAL=0.05s, Display.lua:639-647)
        │
        ▼
RenderIconContainer → elseif entry.trackerType == "cooldown" [WIDEN: or == "item"] (Display.lua:1999)
        │
        ▼
ApplyCooldownSlot(icon, entry, settings, now)                Display.lua:1270-1390
        │  spellID = entry.spellID  -- nil for an item entry
        │  ApplyCachedIcon(icon, spellID, entry.iconOverride)  -- iconOverride MUST be set at creation
        │  userOwned = ApplyUserCooldown(icon, entry, now)     -- UNMODIFIED, generic on key+duration
        │    reads ns.cooldownStarts[entry.key], entry.duration
        │    icon.cooldown:SetCooldown(startedAt, duration)    -- Display.lua:986, plain numbers
        │  [NEW, inside the generation-gated block, ~:1306-1312]
        │    if entry.trackerType == "item" then
        │      ApplyItemCount(icon, entry)  -- new, parallel to ApplyChargeCount, NOT spellID-driven
        │    else
        │      ApplyChargeCount(icon, spellID)  -- existing, unaffected for spell-backed cooldowns
        ▼
Tile shows: item's own icon (iconOverride), running sweep (plain SetCooldown), decremented count
```

### Blizzard's own item-cooldown resolution — why TBT's design correctly diverges

```lua
-- Source: Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua:47-57, 380-383
-- (local retail snapshot, wow-ui-source, branch live, 12.1.0)
function CooldownViewerItemDataMixin:RefreshSpellCategoryData()
	local cooldownInfo = self:GetCooldownInfo()
	if cooldownInfo and cooldownInfo.spellCategoryID then
		local spellID, itemID = C_Spell.GetLastCategoryCooldownSource(cooldownInfo.spellCategoryID)
		if spellID and itemID then
			self:UpdateFromSpellCategory(spellID, nil, cooldownInfo.spellCategoryID, itemID)
		end
	end
end

function CooldownViewerItemDataMixin:GetSpellCooldownInfo()
	local spellID = self:GetSpellID()
	return spellID and C_Spell.GetSpellCooldown(spellID)  -- SecretWhenCooldownsRestricted
end
```
`C_Spell.GetSpellCooldown` is `SecretWhenCooldownsRestricted = true`
[VERIFIED: `SpellDocumentation.lua:268-284`] — it goes secret exactly when a cooldown is running,
which is precisely when a tile needs to draw. `C_Item.GetItemCooldown` carries **no** such secrecy
flag in the local doc [VERIFIED: `ItemDocumentation.lua:412-427`] — only
`SecretArguments = "AllowedWhenUntainted"`, which describes what it *accepts*, not a secrecy
predicate on its *return*. This is consistent with, but does not by itself prove, 999.6's Forever
measurement that item cooldowns read fine in combat; the doc's silence is suggestive, not proof, for
retail's stricter secrecy model (see Open Questions).

`grep -rn "C_Item.GetItemCooldown" Interface/AddOns/Blizzard_CooldownViewer/` in the local snapshot
returns **zero matches** — Blizzard's CDM never reads an item's own cooldown at all, it always goes
through the spell-category resolution above. TBT's locked per-item design is therefore not a
simplification of Blizzard's approach; it is a different, independently-correct approach that reads
directly rather than through an undocumented category table, and it is what lets ITEM-05 work with
zero category data (999.6, `.planning/ROADMAP.md`).

### `C_Item.GetItemCooldown` — exact return shape [VERIFIED]

```lua
-- Source: Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:412-427
-- startTimeSeconds, durationSeconds, enableCooldownTimer = C_Item.GetItemCooldown(itemInfo)
-- All three: Nilable = false. SecretArguments = "AllowedWhenUntainted" (input only).
```
Confirmed by a second, parallel API with an identical three-value shape:
`C_Container.GetItemCooldown(itemID)` returns `startTime, duration, enable` too, but is documented
`MayReturnNothing = true` [VERIFIED: `ContainerDocumentation.lua:337-353`] — a real divergence
between the two APIs the planner should not conflate. **The locked design names `C_Item.GetItemCooldown`
specifically**; do not substitute `C_Container.GetItemCooldown` even though both exist and both are
itemID-keyed (not bag/slot-keyed) — `C_Item`'s is the one whose doc promises it never returns
nothing, which is the more defensible contract for a value being stamped into persistent state.

The third return's documented `Type` differs across the two: `bool` on `C_Item.GetItemCooldown`
(`enableCooldownTimer`), `number` on `C_Container.GetItemCooldown` (`enable`) — almost certainly a
legacy doc-generation artifact from the older `C_Container` alias, but the practical guidance is the
same either way: guard `issecretvalue()` first, then treat the third value as a plain truthiness
test (`if not issecretvalue(enable) and enable then …`) rather than assuming a strict boolean
identity check, so a `1`/`0` legacy convention and a real `true`/`false` both work.

`C_Item.GetItemCount(itemID)` is documented `Nilable = false` on its single `count` return
[VERIFIED: `ItemDocumentation.lua:429-446`] — it **always** answers a real number, `0` included,
never `nil`, regardless of whether the player currently holds any. This directly settles the ITEM-07
reconcile call as safe to make unconditionally (no "item not in bags" branch needed) — it does
*not* settle the deferred `GetItemCooldown`-at-zero-count question, since that is a different call
whose behaviour at zero stock CONTEXT.md explicitly left untested by decision.

### `SetCooldown` — confirms the plain-number render path is a first-class, documented API

```lua
-- Source: Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua:279-291
-- Cooldown:SetCooldown(start, duration, modRate = 1)
-- start, duration: Type = "DurationSeconds", Nilable = false
-- SecretArguments = "AllowedWhenUntainted"
```
This is the exact method `ApplyUserCooldown` already calls (`Display.lua:986`) for every `cd:`
cooldown tracker today. It is not a fallback or a lesser path relative to
`SetCooldownFromDurationObject` — it is Blizzard's own ordinary two-argument cooldown API, and TBT
has been shipping it since Phase 38 (`cd:` trackers) with no defect reported. **No new widget
capability is needed; only new callers of an already-proven method.**

### `UNIT_SPELLCAST_SUCCEEDED` payload — confirmed

```lua
-- Source: Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:4680-4693
-- LiteralName = "UNIT_SPELLCAST_SUCCEEDED", SecretWhenUnitSpellCastRestricted = true
-- Payload: unitTarget (UnitTokenVariant), castGUID (WOWGUID), spellID (number, Nilable=false),
--          castBarID (number, Nilable=true, NeverSecret=true)
```
Matches every existing `OnTrigger(event, unit, _, spellID)` signature in `Providers.lua` exactly
(`TrinketProviderMixin`, `PotProviderMixin`, `RacialProviderMixin`, `UserSpellProviderMixin`). The
new `ItemProviderMixin` should use the identical three-guard shape (`event ~= ... then return nil`,
`unit ~= "player" then return nil`, `type(spellID) ~= "number" then return nil`) before the map
lookup — this is not a new pattern, it is the fourth copy of one already proven four times.

`PotProviderMixin:OnTrigger` (`Providers.lua:497-533`) is the existing, shipped proof that an
item's on-use cast reaches this event with the item's **effect spellID** (not the item's own ID) as
the `spellID` argument — it matches `POT_SPELLS[spellID]` today for exactly this reason. The new
map (`useSpellID -> itemID`) is the same lookup shape against a dynamic table instead of a static
13-entry one.

### The use-spell/effect-spellID identity question (research point 3's "differing IDs" concern)

`C_Item.GetItemSpell(itemID)` returns `spellName, spellID` for the item's on-use effect
[VERIFIED: `ItemDocumentation.lua`, cited in `46-RESEARCH.md`]. This is the **same** spellID that
arrives as `UNIT_SPELLCAST_SUCCEEDED`'s `spellID` argument when that item is used — confirmed not by
new investigation but by the fact that `PotProviderMixin`'s existing, shipped, Forever-measured code
already relies on exactly this identity (`POT_SPELLS` is keyed by the effect spellID, and
`Providers.lua:223-265`'s comment above `POT_SPELLS`/`TRINKET_SPELLS` documents 13 items, each a
1:1 spellID↔itemID pair, working in production since Phase 18). No rank-family or override
divergence has been observed for any of TBT's existing item-triggered spells. The one caveat: TBT's
own rank-family machinery (`ns:ResolveRankFamily`, `Core.lua:614-729`) exists specifically because
spell overrides/ranks CAN diverge a cast's reported spellID from a "base" ID — that machinery is
scoped to player-learned spells via the spellbook scan, not to items, and has never been observed to
apply to an item's use-spell. Treat this as MEDIUM confidence (no counterexample found, but not
exhaustively disproven either) rather than a proven guarantee.

### Recommended new provider — `ItemProviderMixin`

```lua
-- Source: pattern to copy, TerribleBuffTracker/Providers.lua:493-533 (PotProviderMixin shape)
-- and :98-118 (UserSpellProviderMixin's "cooldown side effect, no proc" shape)
local ItemProviderMixin = {}

function ItemProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function ItemProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return nil end
	if unit ~= "player" then return nil end
	if type(spellID) ~= "number" then return nil end

	local itemID = itemUseSpellByID[spellID] -- the locked map, captured in ns:RefreshItemCatalogue
	if not itemID then return nil end

	local usedKey = ns.ITEM_KEY_PREFIX .. itemID
	if ns.db.trackedBuffs[usedKey] then
		local counts = ns.itemTrackedCounts
		counts[usedKey] = math.max(0, (counts[usedKey] or 0) - 1)
	end

	-- ITEM-05: re-read EVERY tracked item, not just the one used.
	for key, entry in pairs(ns.db.trackedBuffs) do
		if entry.trackerType == "item" and entry.itemID then
			local start, duration, enable = C_Item.GetItemCooldown(entry.itemID)
			if not issecretvalue(enable) and enable
				and not issecretvalue(start) and type(start) == "number"
				and not issecretvalue(duration) and type(duration) == "number" and duration > 0
			then
				entry.duration = duration
				ns.cooldownStarts[key] = start
			end
			-- else: leave the existing stamp untouched (locked degrade rule) -- do NOT clear it.
		end
	end

	ns:MarkCooldownsDirty()
	return nil -- never a proc: an item tracker has no buff/timer side
end

ns.ItemProviderMixin = ItemProviderMixin
local ItemProvider = CreateFromMixins(SpellProviderBaseMixin, ItemProviderMixin)
-- Registration: ns.providers = { TrinketProvider, PotProvider, LustProvider, RacialProvider,
--   ItemProvider, UserSpellProvider } -- position before UserSpellProvider, same as every other
--   concrete provider (Providers.lua:1251).
```
This mirrors `.planning/phases/47-item-tracking-cooldown-sharing/47-PATTERNS.md` section 1's
conclusion exactly (independently reached in this research pass by tracing
`ns:DispatchEventToProviders`, `Providers.lua:1345-1362`, which confirms `ns.activeTimers[proc.key]
= proc` is only written `if proc` — so an `OnTrigger` that always returns `nil` costs nothing extra
and correctly never touches `ns.activeTimers`).

### `GetDisplayInfo` for the new provider

The new provider's `GetDisplayInfo` is **not** the dispatch route for `item:` keys — that already
exists and is correct: `ns:GetDisplayInfoForKey` recognises `item:` keys via `ns:ItemKeyItemID(key)`
**before** the `keyToProvider` static-map fallthrough (`Providers.lua:1284-1287`, calling
`ns:ItemDisplayInfo(itemID)`, `:1043-1065`, Phase 46 code, already shipped). `ItemProviderMixin`
should **not** register in `keyToProvider` and does not need a working `GetDisplayInfo` at all for
this phase's requirements — its only job is the `OnTrigger` side effect above. (It still needs the
inherited `SpellProviderBaseMixin:GetDisplayInfo` no-op default so `CreateFromMixins` produces a
valid provider shape; nothing calls it.)

### `AddSuggestedTracker` — the exact edit

```lua
-- Source: TerribleBuffTracker/CDMTab.lua:139-185 (current, to extend)
local function AddSuggestedTracker(key, targetSection)
	if ns.db.trackedBuffs[key] then
		ns:SetBuffSection(key, targetSection)
		return
	end

	local cooldownSpellID = ns:CooldownKeySpellID(key)
	local itemID = ns:ItemKeyItemID(key)              -- NEW: recognise item: keys
	if not cooldownSpellID and not itemID then         -- WIDENED from `if not cooldownSpellID`
		local known = false
		for _, suggestedKey in ipairs(ns.SUGGESTED_KEYS) do
			if suggestedKey == key then known = true break end
		end
		if not known then return end
	end

	local info = ns:GetDisplayInfoForKey(key)
	if not info then return end

	local maxOrder = 0
	for _, e in pairs(ns.db.trackedBuffs) do
		if e.layoutOrder and e.layoutOrder > maxOrder then maxOrder = e.layoutOrder end
	end

	ns.db.trackedBuffs[key] = {
		key = key,
		label = info.label,
		duration = info.duration,     -- 0 at creation for an item entry, see caveat below
		section = targetSection,
		layoutOrder = maxOrder + 1,
		trackerType = itemID and "item" or (cooldownSpellID and "cooldown" or nil),
		spellID = cooldownSpellID or nil,   -- MUST stay nil for an item entry
		itemID = itemID or nil,             -- NEW
		iconOverride = itemID and info.icon or nil,  -- NEW, required -- see rendering section
	}

	-- Recommended: seed a real cooldown immediately if the item happens to already be on
	-- cooldown at drop time, rather than waiting for the next landed use / BAG_UPDATE_COOLDOWN.
	-- Not locked by CONTEXT.md; see Open Questions.
end
```
`info.icon` for an `item:` key comes from `ns:ItemDisplayInfo` (`Providers.lua:1043-1065`, Phase 46,
already shipped), which already resolves `icon or 134400` from the catalogue's cached
`itemCatalogueIcons[itemID]`. Capturing it into `entry.iconOverride` here is the only way
`ApplyCachedIcon` (`Display.lua:741-748`) ever sees it, because that function reads `entry.iconOverride`
directly off the DB entry, never re-derives it from `GetDisplayInfoForKey` on the render path.

### `ns:GetTrackerCategory` — the exact edit

```lua
-- Source: TerribleBuffTracker/Core.lua:99-104
function ns:GetTrackerCategory(entry)
	if entry and (entry.trackerType == "cooldown" or entry.trackerType == "item") then -- WIDENED
		return "spells"
	end
	return "buffs"
end
```
Without this, `CDMTab.lua:944`'s consumer (`if entry.section == def.key and
ns:GetTrackerCategory(entry) == ns.tbtActiveCategory then`) silently files every `item:` tracker
under the Buffs tab, where it never renders while the Cooldowns tab is active — no error, just an
invisible tracker. This is the same failure class the function's own header comment (`Core.lua:94-98`)
was written to prevent for `"cooldown"`.

### `Display.lua:1999` dispatch gate — the exact edit

```lua
-- Source: TerribleBuffTracker/Display.lua:1999 (current)
elseif entry.trackerType == "cooldown" then
	ApplyCooldownSlot(icon, entry, settings, now)
	...
```
```lua
-- WIDENED
elseif entry.trackerType == "cooldown" or entry.trackerType == "item" then
	ApplyCooldownSlot(icon, entry, settings, now)
	...
```
Without this, an `item:` entry never reaches `ApplyCooldownSlot` at all and falls through to the
final placeholder branch (`Display.lua:2025+`), which this research did not trace in full — the
planner should confirm it degrades gracefully (icon-only, no sweep) rather than misbehaving, but
regardless this is the wrong branch for an item tracker and the gate must be widened.

### Also check `RefreshCooldownSlotCounts` (`Display.lua:682-702`)

```lua
for _, entry in pairs(tracked) do
	if entry.trackerType == "cooldown" and entry.section then
		cooldownSlotCounts[entry.section] = (cooldownSlotCounts[entry.section] or 0) + 1
	end
end
```
This count is what makes a container holding *only* cooldown-type entries visible at all under
`hideWhenInactive` (`Display.lua:130-135`'s own comment explains why: a cooldown slot produces no
`ns.activeTimers` entry, so `#timers == 0` and the container would otherwise hide forever). **This
must also be widened** to `entry.trackerType == "cooldown" or entry.trackerType == "item"`, or a
container holding only tracked items (no ordinary cooldowns) would incorrectly hide even while a
sweep is running. Not identified in `47-PATTERNS.md` — new finding from this pass.

### Item-count rendering — the new call, parallel to `ApplyChargeCount`

```lua
-- Source: shape to copy, TerribleBuffTracker/Display.lua:912-936 (ApplyChargeCount) and
-- :1988-1996 (RacialProviderMixin's stack-count precedent, the closest "plain integer TBT itself
-- maintains, shown via chargeCount" example in the codebase)
local function ApplyItemCount(icon, entry)
	local count = ns.itemTrackedCounts[entry.key]
	if count == nil then
		icon.chargeCount:Hide()
		return
	end
	if icon._itemCount ~= count then
		icon._itemCount = count
		icon.chargeCount.Current:SetText(count)
		icon.chargeCount:Show()
	end
end
```
Call site: inside `ApplyCooldownSlot`'s generation-gated block (`Display.lua:1306-1312`, where
`ApplyChargeCount(icon, spellID)` currently sits), branching on `entry.trackerType == "item"`:
```lua
if entry.trackerType == "item" then
	ApplyItemCount(icon, entry)
else
	ApplyChargeCount(icon, spellID)
end
```
**Deliberately not `ns:ItemCatalogueCount(itemID)`** (`Providers.lua:1004-1006`, Phase 46) — that
table is rebuilt from a live bag walk and has **no entry** for an itemID once its stack reaches
zero and it leaves the bags (`Providers.lua:957`, `for itemID in pairs(itemCatalogueSeen) do` — an
absent item is never iterated, so `itemCatalogueCounts[itemID]` is simply never (re)written and the
old value goes stale the moment the catalogue rebuilds without seeing it — actually **worse than
stale**: on the next `RefreshItemCatalogue`, `wipe(itemCatalogueCounts)` clears it outright, so
`ns:ItemCatalogueCount` would return `nil` for a zero-stock item, immediately after any bag-driven
rescan). Wiring the tracked tile's count to that table would silently break ITEM-09 the moment the
Suggested catalogue rescans while the tracked item is at zero stock — this is exactly the pitfall
CONTEXT.md's "Count maintenance" section is implicitly steering the planner away from by specifying
decrement-and-reconcile as a *separate* mechanism from the catalogue.

### `ns.itemTrackedCounts` — new runtime-only store

Not persisted, matching the existing precedent for both `ns.activeTimers` and `ns.cooldownStarts`
(`Core.lua:438-455`'s own comment: *"Persisting it would restore a cooldown that the game finished
while the player was logged out, and there is no way to check"* — the same reasoning applies to a
count, which can drift while logged out from mailbox/guild-bank/alt activity the addon never saw).
Seed it at tracker-creation time from a live `C_Item.GetItemCount(itemID)` read (not from the
catalogue cache, which may be stale by the time of the drop), and thereafter maintain it by
decrement (landed use) and reconcile (combat end / bag settle), per the locked design.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "Which item did this cast come from?" | A four-hook production bridge (`UseAction`/`UseContainerItem`/`UseInventoryItem`/`UseItemByName`) | The locked `useSpellID -> itemID` map, matched on `UNIT_SPELLCAST_SUCCEEDED` | Explicitly measured and rejected by the user: hooks fire on the press, not the landed use, and the map costs nothing extra since `GetItemSpell` is already called |
| "Is this item's cooldown shared with another?" | A hand-maintained spell-category table (à la Blizzard's `spellCategoryMetadataLookup`) | Per-item `C_Item.GetItemCooldown(itemID)`, re-read for every tracked item on any landed use | Locked decision; also independently confirmed correct by this research — Blizzard's own category table is not even readable from an addon in the way TBT would need |
| "Show a running cooldown from a start/duration pair" | A new Cooldown-widget wrapper or `SetCooldownFromDurationObject`-shaped adapter | The existing `ApplyUserCooldown` (`Display.lua:954-1002`) — already generic, already proven, already shipped for `cd:` trackers | Zero new render machinery needed; the function has no spellID dependency at all |
| "Show the item's count on its tile" | Reuse `ns:ItemCatalogueCount` (Phase 46's Suggested-list cache) | A new, separate, runtime-only decremented/reconciled store (`ns.itemTrackedCounts`) | The catalogue cache is wiped/rebuilt from a live bag walk and has no entry for a zero-stock item — reusing it breaks ITEM-09 |

**Key insight:** every mechanism CONTEXT.md locked already has a working, shipped analog somewhere
in this codebase (`PotProviderMixin` for cast matching, `UserSpellProviderMixin`'s cooldown side
effect for the stamp, `ApplyUserCooldown` for the render). The actual new work is: one new provider
mixin following an existing shape, one new module-level count table following an existing
runtime-only-state precedent, and three small widenings of `trackerType == "cooldown"` checks to
also accept `"item"`. Nothing here is a novel WoW-addon-API problem.

## Common Pitfalls

### Pitfall 1: icon silently stays the question mark
**What goes wrong:** A dragged item tile shows `134400` forever, with no error, no log line, and no
obvious cause.
**Why it happens:** `ApplyCachedIcon` (`Display.lua:741-748`) resolves texture as `iconOverride or
(spellID and GetSpellIcon(spellID)) or 134400`. An item entry's `spellID` is always `nil`
(deliberately — see the `AddSuggestedTracker` edit above), so the ONLY way this ever shows the
item's own icon is `entry.iconOverride` being set at creation time. It is easy to extend
`AddSuggestedTracker`'s table constructor with `itemID`/`trackerType` and forget the parallel
`iconOverride` field, because the `cd:` sibling entry never needed one.
**How to avoid:** Set `iconOverride = info.icon` in the same table constructor, sourced from
`ns:GetDisplayInfoForKey(key)`'s already-resolved `info.icon` (Phase 46's `ns:ItemDisplayInfo`).
**Warning signs:** In-game, every dragged item tile looks identical (grey question mark) regardless
of which item was dragged.

### Pitfall 2: count silently never appears
**What goes wrong:** The tracked item's tile shows a correct sweep but never a number.
**Why it happens:** `ApplyChargeCount(icon, spellID)` (`Display.lua:912-936`) is the only existing
call that writes `icon.chargeCount`, and it is driven by `C_Spell.GetSpellCharges(spellID)`. An item
entry's `spellID` is `nil`, so this call always hits its `if not spellID … then icon.chargeCount:Hide()
… end` guard.
**How to avoid:** Add the new `ApplyItemCount` call (above), gated on `entry.trackerType == "item"`,
inside the same generation-gated block `ApplyChargeCount` already lives in (`Display.lua:1306-1312`).
**Warning signs:** A tracked item tile with a correct sweep and grey/full-colour cycling, but a
permanently blank bottom-right corner.

### Pitfall 3: an item tracker silently invisible under the Cooldowns tab
**What goes wrong:** A tile is created successfully (`ns.db.trackedBuffs["item:..."]` exists,
confirmable by `/reload` and re-checking SavedVariables) but never renders anywhere.
**Why it happens:** `ns:GetTrackerCategory` (`Core.lua:99-104`) returns `"buffs"` for any
`trackerType` other than `"cooldown"` — including the locked `"item"` value. `CDMTab.lua:944`'s
category filter then files the entry under the Buffs tab, where the Cooldowns-tab-active player
never sees it, and vice versa.
**How to avoid:** Widen `ns:GetTrackerCategory` to treat `"item"` the same as `"cooldown"` (exact
edit above).
**Warning signs:** A container that should hold the new tracker looks empty under one tab and (if
the player happens to switch tabs) suddenly shows a tile that "used to not be there."

### Pitfall 4: reusing `ns:ItemCatalogueCount` breaks ITEM-09 specifically
**What goes wrong:** ITEM-09 verification looks fine right up until the item's stack actually hits
zero and the next Suggested-tab rescan runs — at which point the tracked tile's count vanishes or
reads `0` even though the design intends the *tracked* count (independently decremented) to be the
source of truth, which need not be zero the instant the bag count is.
**Why it happens:** `ns:RefreshItemCatalogue` (`Providers.lua:923-995`) `wipe()`s
`itemCatalogueCounts` on every rescan and only repopulates entries for itemIDs the current bag walk
actually finds (`Providers.lua:957`, `for itemID in pairs(itemCatalogueSeen) do`) — a zero-stock item
is never in that set, so its cached count is gone, not merely stale.
**How to avoid:** The tracked tile's count must read from the new, separate
`ns.itemTrackedCounts` store (decrement + reconcile), never from the catalogue cache. The catalogue
cache is Suggested-list-only, by Phase 46's own design.
**Warning signs:** Count display works correctly during manual testing (item still in bags) and only
breaks once a specific, easy-to-miss sequence (drink to zero, then trigger any `BAG_UPDATE`-driven
rescan) is exercised.

### Pitfall 5: an item's use-spell colliding with another item's (accepted gap, not a defect to fix)
**What goes wrong:** Two catalogued items sharing one `GetItemSpell` result would make the
`useSpellID -> itemID` map ambiguous; the second write wins, and the other item's uses would be
mis-attributed.
**Why it happens:** The map is keyed by spellID, and nothing in `C_Item.GetItemSpell`'s contract
guarantees uniqueness across different items.
**How to avoid:** CONTEXT.md accepts this gap explicitly. If detection is cheap (a second write to
an occupied key during the capture loop in `ns:RefreshItemCatalogue`), log it under the existing
`ns.debugLogging` flag using a **new** print statement in the same visual idiom as `Core.lua`'s
existing debug log (`"|cff00ccffTBT Debug|r: ..."`, colour-coded labels) — do **not** touch, extend,
or repurpose `Core.lua`'s `LogItemUse`/`LogPlayerCast`/`pendingItemCasts` machinery, which CONTEXT.md
explicitly protects as a separate, working feature.
**Warning signs:** None expected in normal play — this is a theoretical collision no probe run has
observed among TBT's known items (`TRINKET_SPELLS`/`POT_SPELLS`, 13 entries, all 1:1).

## Secret Values

Every new API read this phase adds must follow the locked, project-wide rule: `issecretvalue()`
**before** any truthiness or `type()` test, because `type()` reports `"number"` (or `"boolean"`) for
a secret value and passes silently (`Providers.lua:970`'s own worked example, already the pattern
Phase 46 shipped).

Reads that need the guard, and where:

- `C_Item.GetItemCooldown(itemID)`'s three returns — `start`, `duration` (both `type() == "number"`
  once confirmed not secret) and `enable` (documented `bool` for `C_Item`'s version, `number` for
  `C_Container`'s — guard then treat as a plain truthy test, not a strict `== true`).
- `C_Item.GetItemCount(itemID)`'s `count`, in the reconcile path.
- The `useSpellID` capture in `ns:RefreshItemCatalogue` — already guarded correctly at
  `Providers.lua:970`; this phase's new capture line must sit inside that same guarded branch, not
  duplicate the guard incorrectly.

**Degrade rule (locked):** where a read is unreadable (secret or wrong type), the correct behaviour
is to leave the existing stamp (`entry.duration`, `ns.cooldownStarts[key]`) exactly as it was — never
clear it, never zero it, never error. A stale-but-present stamp is what makes ITEM-09's "keeps its
running cooldown" true even through a moment where a read happens to be unreadable; clearing on a
failed read would actively break that guarantee rather than merely fail to update it.

**Retail's secrecy behaviour for these specific calls is unmeasured.** Both 999.6 probe runs were
Forever-only. The doc's absence of a `SecretWhenCooldownsRestricted`-equivalent flag on
`C_Item.GetItemCooldown` (unlike `C_Spell.GetSpellCooldown`, which explicitly carries it) is
suggestive that item cooldowns may not be gated the same way spell cooldowns are, but this is an
inference from documentation structure, not a retail measurement — flag for Phase 52's retail
review pass, same as Phase 46 did for its own item reads.

## Code Examples

### Verified: `C_Item.GetItemCooldown` return shape
```lua
-- Source: Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:412-427
local startTimeSeconds, durationSeconds, enableCooldownTimer = C_Item.GetItemCooldown(itemID)
-- All three Nilable = false per the doc -- but still guard with issecretvalue() first;
-- Nilable=false is not the same guarantee as "never secret".
```

### Verified: plain-number cooldown render, already shipped
```lua
-- Source: TerribleBuffTracker/Display.lua:954-1002 (ApplyUserCooldown, unmodified for item use)
local function ApplyUserCooldown(icon, entry, now)
	local duration = entry.duration
	if type(duration) ~= "number" or duration <= 0 then
		return false
	end
	if icon._lastStart ~= nil then
		icon._lastStart = nil
		icon._userCdState = nil
	end
	local startedAt = ns.cooldownStarts[entry.key]
	local running = startedAt ~= nil and (now - startedAt) < duration
	local want = running and startedAt or false
	if icon._userCdState ~= want then
		icon._userCdState = want
		if running then
			icon.cooldown:SetCooldown(startedAt, duration)
		else
			icon.cooldown:Clear()
		end
	end
	if icon._userCdGrey ~= running then
		icon._userCdGrey = running
		icon._desat = nil
		icon.icon:SetDesaturated(running)
	end
	return true
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Hand-maintained `TRINKET_SPELLS`/`POT_SPELLS` tables (13 items) | Dynamic `useSpellID -> itemID` map built from the bag-derived catalogue | This phase | Generalises item tracking to any catalogued consumable, not just the 13 hardcoded ones — the two mechanisms coexist, they are not being merged |
| Spell-category cooldown grouping (Blizzard's own CDM approach) | Per-item `C_Item.GetItemCooldown` re-read on every tracked item | Locked by user decision, ROADMAP 999.6 | Cooldown sharing (ITEM-05) works with zero category data and is measured correct on both known Forever category groups (potions, healthstone) without naming either |

**Deprecated/outdated:** N/A — no TBT-internal API is being retired by this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | An item's use-spell (`GetItemSpell`) is always the same spellID `UNIT_SPELLCAST_SUCCEEDED` reports for that item's use, with no rank/override divergence | Architecture Patterns — use-spell identity | Medium: if wrong for some item, that item's landed uses would never match the map and its count/cooldown would never update. No counterexample found among TBT's 13 existing hardcoded item↔spell pairs, all shipped and working |
| A2 | Neither `C_Item.GetItemCooldown` nor `C_Item.GetItemCount` can return a secret value on retail in any context this phase reaches | Secret Values | Low: the universal `issecretvalue()`-first guard plus the locked degrade-to-stamp rule means a wrong assumption here degrades to a stale-but-present tile, not a crash |
| A3 | `GetItemCooldown`'s behaviour at zero item count is irrelevant because the stamp is taken at the moment of use, while the item is still definitely present | Common Pitfalls / User Constraints | Low, by explicit user decision — this is the documented reason the question was left untested |
| A4 | No existing `RemoveTrackedBuff`/`SetBuffSection` code path assumes a numeric or `cd:`-shaped key in a way that would break for an `item:` key | Architecture Patterns (implicit, via direct source read of `BuffEngine.lua:502-559`) | Low: both functions are already generic on `type(key) == "number" or "string"`; verified by direct read, not inferred |

**If this table is empty:** N/A — see rows above.

## Open Questions

1. **Should a freshly dragged item tracker seed its cooldown immediately if the item is already on
   cooldown at drop time?**
   - What we know: `AddSuggestedTracker` currently sets `duration = info.duration`, and
     `ns:ItemDisplayInfo` (Phase 46) always returns `duration = 0` (it reads no item cooldowns by
     design). With `entry.duration == 0` at creation, `ApplyUserCooldown` returns `false`
     immediately (`Display.lua:955-958`) and the tile shows no sweep until the next landed use or
     `BAG_UPDATE_COOLDOWN` refresh populates a real value.
   - What's unclear: whether a player dragging an item that happens to already be on cooldown
     (e.g., just used a potion, then opens the CDM and tracks the other potion in the same shared
     group) should see the correct sweep immediately, or whether waiting for the next qualifying
     event is acceptable.
   - Recommendation: have `AddSuggestedTracker`'s `item:` branch call the same
     `C_Item.GetItemCooldown`-and-stamp logic the new provider uses, once, synchronously, at
     creation — this is a few extra lines reusing the exact same guarded read, not a new mechanism,
     and it closes what would otherwise look like a bug ("I dragged a potion that's on cooldown and
     it shows no timer until I drink something else"). Not locked by CONTEXT.md; flag for the
     planner/user to confirm.

2. **Does `C_Item.GetItemCooldown` answer for an itemID the player owns zero of?**
   - What we know: explicitly left untested by user decision (CONTEXT.md, ROADMAP 999.6). The
     stamp-at-use design makes the answer unnecessary for ITEM-09 specifically.
   - What's unclear: whether `BAG_UPDATE_COOLDOWN`-triggered refreshes (which re-read every tracked
     item, including ones currently at zero stock) will find the read degrades gracefully (per the
     locked "leave the stamp untouched" rule) or actually still succeeds.
   - Recommendation: no action needed — the guard-and-degrade design already handles either outcome
     correctly. Worth an in-game observation note during Phase 51/52's review passes, not a blocker.

3. **Retail's secrecy behaviour for `GetItemCooldown`/`GetItemCount` in combat, M+, and raid.**
   - What we know: 999.6's probes were Forever-only; the doc's structural silence on a secrecy flag
     for these two calls (vs. the explicit flag on `GetSpellCooldown`) is suggestive but not proof.
   - What's unclear: whether Midnight retail's stricter secrecy model extends to these reads.
   - Recommendation: the `issecretvalue()`-first guard plus the degrade-to-stamp rule already makes
     this safe to ship without knowing the answer. Phase 52's retail review pass is the scheduled
     place to observe it directly.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| stylua | Post-task formatting (CLAUDE.md mandate) | present at `~/.cargo/bin/stylua` per project memory | — | — |
| Midnight retail client | ITEM-\* retail verification (Phase 52) | present per Phase 46 research | `World of Warcraft\_retail_` | — |
| WoW Forever beta client | Primary verification target for this phase | present per Phase 46 research | `World of Warcraft\_classic_beta_`, `1.60.1.69913` | — |
| `wow-ui-source` (local retail snapshot) | Citation source for this research | present, branch `live`, 12.1.0 | — | read-only, never modified |
| Two consumables sharing one cooldown group (e.g. two potions on Forever) | ITEM-05 in-game verification | confirmed present on the 999.6 test character (three potions + healthstone) | — | — |

No missing dependency, no fallback needed.

## Security Domain

`security_enforcement` is absent from `.planning/config.json`, so the default (enabled) applies. As
with Phase 46, the ASVS categories are written for network/web applications and mostly do not map
onto a single-player client addon with no network surface and no server-side trust boundary of its
own.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | No auth surface |
| V3 Session Management | No | No network session |
| V4 Access Control | No | No multi-user boundary |
| V5 Input Validation | Yes (narrow) | `issecretvalue()`-then-`type()` on every new `C_Item` read this phase adds, plus the locked degrade-not-error rule |
| V6 Cryptography | No | None in this phase |

### Known threat patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secret-value type confusion (a secret number/bool passes `type(v)` checks) | Tampering (of TBT's own logic) | `issecretvalue()` first, always — applied to every new `C_Item.GetItemCooldown`/`GetItemCount` read |
| Stamp-clearing on a transient unreadable read (would regress ITEM-09) | Tampering (of TBT's own persisted state) | The locked degrade rule: never clear `entry.duration`/`ns.cooldownStarts` on a failed read, only skip the update |

## Validation Architecture

No test runner exists or is planned for this WoW addon (`.planning/ROADMAP.md`'s own backlog record:
*"No test suite exists. No build manifest, no `luacheck`, no automated regression gate. Every claim
in v0.4.0 rests on in-game observation."*). This phase does not change that. Verification here is
**static assertion** (source greps, provable before the client ever loads) plus **in-game human
checks** (things only a running client can prove) — matching Phase 46's own precedent exactly.

### Static assertions (provable without WoW running)

| Check | Command / Method | Proves |
|-------|-------------------|--------|
| stylua clean | `stylua .` from repo root (no flags) | No formatting drift, no invisible CRLF→LF reflow |
| No flavour check introduced | `grep -n "buildInterfaceVersion\|GetBuildInfo\|classicVersion\|wow_classic" <changed files>` | ITEM-04/05/06/07/09's "one code path" constraint held |
| `issecretvalue` precedes every new `type()`/truthiness test | Manual read of every new `C_Item.GetItemCooldown`/`GetItemCount` call site | Locked project ordering rule held |
| `ItemProviderMixin:OnTrigger` never returns a truthy value | Source read of the new function | Confirms it can never write into `ns.activeTimers` (would silently create a phantom buff timer if it did) |
| `AddSuggestedTracker`'s `item:` branch sets `iconOverride` | Source read | Prevents Pitfall 1 (permanent question-mark icon) |
| `Display.lua`'s three `trackerType == "cooldown"` gates (`:999-ish` dispatch, `RefreshCooldownSlotCounts`, `ApplyCooldownSlot`'s own internals) are each checked for whether they need the `"item"` widening | Grep `trackerType ==` across `Display.lua`, cross-check each hit against this document's three identified edit sites | Confirms no fourth silent gate was missed |
| Debug cast log (`Core.lua`'s `LogItemUse`/`LogPlayerCast`/`pendingItemCasts`) is untouched | `git diff Core.lua` reviewed for any edit inside that block | CONTEXT.md's explicit protection of that feature held |

### In-game human checks (the only route to ITEM-02/04/05/06/07/09)

1. **ITEM-02/04 (drag creates a tracker, drops out of Suggested):** Drag a Suggested consumable
   tile into a container. Confirm: (a) a new tile appears in the target container showing the
   item's own icon, not a question mark; (b) the same item no longer appears in Suggested; (c) it
   appears under the Cooldowns tab, not Buffs.
2. **ITEM-05 (shared cooldown, the hardest one to observe passively):** Track **two** potions known
   to share a cooldown group (Forever: any two of Minor Healing/Mana/Rejuvenation Potion — measured
   sharing one 120s group in 999.6). Drink one. Confirm the **other tracked potion's tile** starts
   its sweep at the same moment, with the same remaining time, even though it was never used. This
   is the one behaviour that cannot be inferred from a static read — it requires two actual tracked
   tiles and one actual drink.
3. **ITEM-06 (refused press never decrements):** With a tracked item already on cooldown (from
   check 2), press/use it again (a refused press — the game will not let the cast through). Confirm
   the count does **not** decrease. Then use a *different*, off-cooldown tracked item and confirm
   its count *does* decrease by exactly 1.
4. **ITEM-07 (combat-end reconcile):** Enter combat, drink a tracked potion (count decrements by 1
   locally), then loot or otherwise acquire more of the same item mid-fight (real bag count now
   higher than the local decremented count would suggest). Leave combat. Confirm the displayed
   count corrects to match the true bag count.
5. **ITEM-09 (survives zero stock):** Drink a tracked item down to its last one, then drink the
   last one so the stack leaves the bags entirely (verify in the normal Blizzard bag UI that the
   item is genuinely gone). Confirm the TBT tile **remains visible**, still shows the running
   cooldown sweep correctly through to expiry, and shows a count of `0` rather than disappearing or
   erroring.
6. **Retail parity (Phase 52, scheduled separately):** Repeat checks 1–5 on Midnight retail,
   specifically noting whether `C_Item.GetItemCooldown`/`GetItemCount` ever come back secret in
   combat/M+/raid, and confirming the tile degrades (keeps last stamp, no error) rather than breaking
   if so.

### Sampling cadence

- **Per task:** static assertions above, run after each plan/task touching a new or edited file.
- **Per phase gate:** the six in-game checks above, run once all this phase's plans are complete,
  before `/gsd-verify-work`. Checks 2 and 5 specifically require sequencing across two or more real
  game actions and cannot be shortened or skipped — they are the two requirements this research
  identified as observable only through an actual play sequence, not through a single glance at the
  UI.

## Sources

### Primary (HIGH confidence)

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:412-446` (local retail
  snapshot, `wow-ui-source`, branch `live`, 12.1.0) — `GetItemCooldown` (:412-427), `GetItemCount`
  (:429-446)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua:337-353` —
  `C_Container.GetItemCooldown`, confirming the `MayReturnNothing` divergence from `C_Item`'s version
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua:279-291` —
  `Cooldown:SetCooldown(start, duration, modRate)`
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:4680-4693` —
  `UNIT_SPELLCAST_SUCCEEDED` payload
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:268-284` —
  `C_Spell.GetSpellCooldown`, confirming its `SecretWhenCooldownsRestricted` flag (absent on
  `C_Item.GetItemCooldown`)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua:1-70,370-449` — Blizzard's
  own item-cooldown resolution via spell category, read directly and grepped to confirm zero calls
  to `C_Item.GetItemCooldown` anywhere in that addon
- `TerribleBuffTracker/Providers.lua` (read in full, 1363 lines) — `PotProviderMixin` (:489-586),
  `UserSpellProviderMixin`'s cooldown side effect (:82-118), `ns:RefreshItemCatalogue` (:900-1065),
  `ns:GetDisplayInfoForKey` (:1268-1299), `ns:DispatchEventToProviders` (:1333-1362)
- `TerribleBuffTracker/Core.lua` (read in full, 1332 lines) — `ns:GetTrackerCategory` (:99-104),
  `ns.ITEM_KEY_PREFIX`/`ns:ItemKeyItemID` (:491-515), `ns.cooldownStarts`/`ns:IsCooldownRunning`
  (:517-532), event registration (:826-874) and dispatch (:876-1008), the debug cast log
  (:1136-1332)
- `TerribleBuffTracker/CDMTab.lua` (read through line 1233 of 1970) — `StartPreview`/item-catalogue
  warming (:27-77), `AddSuggestedTracker` (:139-185), `CreateIconFrame`'s `chargeCount` (:200-213),
  the Suggested item-tile loop (:870-901), the category filter consumer (:944)
- `TerribleBuffTracker/Display.lua` (read through line 1074 of 2199, plus targeted reads to line
  2060) — `ApplyCachedIcon` (:741-748), `ApplyChargeCount` (:912-936), `ApplyCooldownSlot`
  (:1270-1390), `ApplyUserCooldown` (:954-1002), the `trackerType == "cooldown"` dispatch gate
  (:1999-2024), `RefreshCooldownSlotCounts` (:682-702)
- `TerribleBuffTracker/BuffEngine.lua` (targeted read) — `ns:OnSpellCastSucceeded`'s zero-branch
  dispatch (:239-244), `ns:AddTrackedBuff`/`ns:RemoveTrackedBuff`/`ns:SetBuffSection` (:422-559)
- `.planning/phases/47-item-tracking-cooldown-sharing/47-CONTEXT.md` — locked user decisions
- `.planning/phases/47-item-tracking-cooldown-sharing/47-PATTERNS.md` — independent pattern-mapping
  pass, read in full and cross-checked; used as a corroborating secondary source, not copied
  uncritically (this research adds the Blizzard-source verification, the API return-shape
  confirmation, the `RefreshCooldownSlotCounts` gap it did not identify, and the Validation
  Architecture section it does not cover)
- `.planning/ROADMAP.md` backlog 999.6 — settled design and measured Forever findings
- `.planning/phases/46-item-catalogue-suggested-tiles/46-RESEARCH.md` — prior phase's findings and
  Open Questions (the use-spell collision question this phase re-opens)
- `.planning/REQUIREMENTS.md` — ITEM-02/04/05/06/07/09 definitions

### Secondary (MEDIUM confidence)

- The claim that an item's `GetItemSpell` spellID always equals the `UNIT_SPELLCAST_SUCCEEDED`
  spellID for that item's use — inferred from `PotProviderMixin`'s working, shipped 13-item table
  rather than independently proven for the general case (see Assumptions Log A1).

### Tertiary (LOW confidence / flagged for validation)

- Whether `C_Item.GetItemCooldown`/`GetItemCount` can ever return a secret value on retail in
  combat/M+/raid — no explicit secrecy predicate found for either in the local doc, but the local
  snapshot is 12.1.0 and cannot prove behaviour on a live, patched client. Flagged for Phase 52.

## Metadata

**Confidence breakdown:**
- API signatures (`GetItemCooldown`, `GetItemCount`, `SetCooldown`, `UNIT_SPELLCAST_SUCCEEDED`):
  HIGH — every one cross-checked against the official generated doc, not inferred from training data.
- Blizzard's own item-cooldown resolution NOT using `C_Item.GetItemCooldown`: HIGH — confirmed by
  both direct source read and a repo-wide grep returning zero matches.
- Render-path integration (`ApplyUserCooldown` reuse, the two silent-failure traps): HIGH — every
  citation is a direct read of TBT's current shipped source, independently corroborated by
  `47-PATTERNS.md`'s separate pass reaching the same two findings.
- Use-spell/effect-spellID identity (research point 3): MEDIUM — strong existing-code evidence
  (13 working examples), no exhaustive proof for the general case.
- Retail secrecy behaviour for the new API calls: LOW — unmeasured, explicitly flagged for Phase 52.

**Research date:** 2026-09-24
**Valid until:** Should remain valid for the life of this milestone; re-verify signatures if a
client patch lands before this phase's plans are executed.
