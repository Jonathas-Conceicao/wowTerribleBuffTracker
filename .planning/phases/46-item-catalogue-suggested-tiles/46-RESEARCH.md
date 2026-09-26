# Phase 46: Item Catalogue & Suggested Tiles - Research

**Researched:** 2026-09-24
**Domain:** WoW addon Lua — bag enumeration, `C_Item`/`C_Container` API, CDM Suggested-tile rendering
**Confidence:** HIGH (every load-bearing call is either cited from local Blizzard source or already
exercised and measured by TBT's own probe on Forever 1.60.1)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Phase Boundary:** Opening the Cooldown Manager on either flavour walks the player's bags, builds a
catalogue of likely consumables keyed by **itemID**, and renders every catalogued item that is not
already tracked as a tile in the **Suggested** section of the **Cooldowns** tab, showing the item's own
icon and the number currently held.

This phase is read-and-render only. Creating a tracker from a tile, decrementing counts, reading item
cooldowns and reconciling against the bags are all Phase 47. The tiles this phase produces are draggable
in the same sense every other Suggested tile is, but what happens on drop is Phase 47's work — this
phase's success criteria stop at the catalogue and its tiles.

Requirements: ITEM-01, ITEM-03, ITEM-08, ITEM-10.

**Tracker key namespace — USER DECISION, front-loaded 2026-09-24**

- A tracked item lives under a third key namespace, `item:<itemID>` (`ns.ITEM_KEY_PREFIX`), alongside
  the existing bare-numeric (buff) and `cd:<spellID>` (cooldown) namespaces in the one
  `ns.db.trackedBuffs` table.
- No schema bump. This is purely additive — only newly created entries use it, and nothing that walks
  `pairs(ns.db.trackedBuffs)` needs to change. Same precedent as `userContainers` (`Core.lua:878`) and
  `mergeMode` (Phase 35.1), both of which added shape without moving `CURRENT_SCHEMA_VERSION`
  (`BuffEngine.lua:100`, currently 6).
- Rejected: reusing `cd:<useSpellID>`. It loses the itemID that `GetItemCooldown`/`GetItemCount` need,
  and it collides with a plain spell-cooldown tracker for the same spell — the exact class of bug the
  `cd:` namespace was introduced to fix (`Core.lua:455-471`).
- The parser is the twin of `ns:CooldownKeySpellID` (`Core.lua:487`): `key:match("^item:(%d+)$")`,
  returning a number or nil. Name it `ns:ItemKeyItemID`.
- Phase 46 only needs the key shape — to answer "is this item already tracked?" when filtering the
  catalogue down to the Suggested list. Entry creation is Phase 47.

**Catalogue construction**

- The filter is the one settled in ROADMAP backlog 999.6 section 1 and measured on Forever 1.60.1:
  `classID == 0` (`Enum.ItemClass.Consumable`), has a use-spell (`C_Item.GetItemSpell` returns a spell),
  and `subClassID ~= 7` (`Enum.ItemConsumableSubclass.Bandage`).
- `classID`/`subClassID` come from `C_Item.GetItemInfoInstant(itemID)` and are stable. `IsUsableItem` is
  explicitly not a filter — the probe measured it flipping between an out-of-combat and an in-combat
  scan of the same bag.
- Quest items (`classID 12`), recipes (9), keys (13), trade goods (7) and miscellaneous (15) all fall
  out on `classID` alone — ITEM-08 needs no name matching. Bandages fall out on the real `0/7` subclass
  tag. Craftsman's Writ, a Forever profession quest item that classifies `0/8`, falls out for having no
  use-spell.
- The `0/8` residue the probe found on the test character (glue, campfire kit, lute, crate) is kept, per
  999.6 section 1: "that residue is acceptable in a list the user drags from, and the filter is expected
  to be refined during the milestone". Excluding `0/8` outright is not safe without knowing which
  subclass the healthstone carries on Forever.
- Keyed by itemID, never by bag and slot (ITEM-01). Bag/slot is positional and shifts when stacks split
  or bags are sorted. The bag walk is only how items are discovered; the itemID is the identity.
- A duplicated itemID across several bag slots collapses to one catalogue row whose count is
  `C_Item.GetItemCount(itemID)`, not a per-slot sum — the API already aggregates.

**Scan cadence**

- Scan on CDM open, and re-scan on `BAG_UPDATE` only while the CDM frame is shown. A bag update with the
  CDM closed marks the catalogue dirty; the next open rebuilds it.
- The catalogue is cached in a reusable module-level table wiped with `wipe()`, per CLAUDE.md's hot-path
  pattern — `ns:RefreshTBTSections` has eleven call sites and redraws Suggested on every open and after
  every drag, add, move and delete. The render path must read the cache and never walk the bags itself.
  This is the same lesson `ns:IsSuggestedKeyResolvable`'s memo (`Providers.lua:1097-1121`) records.
- `BAG_UPDATE` fires in bursts; coalesce to at most one rebuild per frame.

**Tile rendering**

- Tiles go in the Cooldowns tab's Suggested section — the branch at `CDMTab.lua:773`, where
  `ns:RacialCooldownKeys()` is rendered today. Item tiles are appended after the racial cooldown tiles
  so the racial tiles keep their current position.
- Icon from `C_Item.GetItemIconByID(itemID)` — the one call in 999.6's plan never yet exercised. Fall
  back to the existing `134400` question-mark default when it yields nothing.
- Count rendered in the same display slot cooldown icons already use for charges:
  `frame.chargeCount.Current` (`Display.lua:478-483`, `NumberFontNormal`, anchored `BOTTOMRIGHT, -2, 2`),
  copied field-for-field from Blizzard's `CooldownViewerEssentialItemTemplate`. A Suggested tile is a
  plain `CreateIconFrame` (`CDMTab.lua:148`) and has no such fontstring today, so this phase adds one to
  that frame using the identical font/anchor, rather than inventing a second count style.
- Pooled frames carry state. `section.itemPool:ReleaseAll()` recycles tiles across renders, so the count
  fontstring must be written or hidden on every tile every pass — the same trap the existing code
  documents for `SetDesaturated` at `CDMTab.lua:788` and `:818`.
- Already-tracked items are absent from Suggested (ITEM-02's "not already tracked"), checked against
  `ns.db.trackedBuffs["item:"..itemID]`.

**Both flavours — USER DECISION, front-loaded 2026-09-24**

- Flavour-agnostic, one code path, no build check. ITEM-10. The v0.4.0 `buildInterfaceVersion` check
  (`Core.lua:~530`) is explicitly a one-off licensed by a recorded user decision and its comment states
  "No second flavour check may be added anywhere in this addon". This phase adds none.
- Every read of an API value is guarded `issecretvalue()` first, then `type()` — the locked ordering,
  because `type()` reports `"number"` for a secret number and passes on its own. Retail's item-cooldown
  secrecy in combat is unmeasured (both probe runs were Forever-only), so the guard is what makes the
  retail offer safe rather than a measurement.
- Where a value is unreadable, the tile renders without that detail rather than erroring — no icon
  falls back to 134400, no count hides the fontstring. Degradation, never a stuck or wrong value.
- Retail gets its verification in Phase 52's retail review pass, as the roadmap already schedules.

### Claude's Discretion

- Tile ordering within the item block. Recommend itemID ascending: deterministic, locale-free, and
  stable across bag sorts, where bag-walk order is not. Name-sorting is friendlier but
  `C_Item.GetItemNameByID` can return nothing before the item is cached.
- No cap on the number of item tiles. The filter is expected to keep the list small (nine rows on the
  probe's test character); a cap can be added if a real bag proves otherwise.
- Exact placement of the catalogue builder — `Providers.lua` beside the other catalogues, or its own
  file. Providers.lua is already 1185 lines and holds every other catalogue; a new `ItemCatalogue.lua`
  would need a TOC entry and must load before CDMTab.

### Deferred Ideas (OUT OF SCOPE)

- Bandages — deferred with findings recorded (999.6). The gate is a debuff (Recently Bandaged, spell
  11196, 60s) with no item cooldown; auras cannot be read in combat on Forever; and the debuff lands on
  the recipient, not the caster. Excluded from the catalogue by the `0/7` subclass filter, which is this
  phase's only bandage handling.
- Refining the `0/8` residue out of the catalogue. Explicitly left for later in the milestone per 999.6
  section 1.
- Everything in Phase 47: tracker creation from a tile, count decrement, cooldown reads, shared cooldown
  display, zero-count persistence, out-of-combat reconcile.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ITEM-01 | Opening the Cooldown Manager produces a catalogue of the usable consumables in the player's bags, keyed by itemID rather than by bag and slot | Bag-walk idiom (`bag = 0, 5`) VERIFIED by TBT's own Forever probe (`Probe.lua:2407-2424`); `GetItemCount(itemID)` de-duplicates automatically, matching the "keyed by itemID, one row per duplicate" requirement |
| ITEM-03 | A Suggested consumable tile shows the item's own icon and the number the player currently holds | Icon-source comparison (`GetItemIconByID` vs. reused `GetItemInfoInstant` icon) with a HIGH-confidence recommendation; `chargeCount.Current` fontstring confirmed to match CONTEXT.md's citation exactly (`Display.lua:478-483`), and confirmed absent from the Suggested tile frame today (`CDMTab.lua:149-160`), so adding it is additive |
| ITEM-08 | Quest items, recipes, keys, trade goods and bandages are absent from the catalogue | `Enum.ItemClass`/`Enum.ItemConsumableSubclass` values VERIFIED against local retail source (`ItemConstantsDocumentation.lua:198-251`); `GetItemInfoInstant`/`GetItemSpell` exact return signatures VERIFIED, with a documented pitfall on pcall-shifted return positions when transcribing from the probe |
| ITEM-10 | The consumables catalogue is offered on both retail and Forever | Bag range (`0..5`) and every API name confirmed cross-flavour-safe by construction (data-absence, not identity-check) and Forever-measured by the probe; Secret Values section enumerates every new API read that needs the locked `issecretvalue()`-first guard for retail's unmeasured combat behaviour |
</phase_requirements>

## Summary

Phase 46 adds one new read-only subsystem (a cached bag→consumables catalogue) and extends two
existing dispatch points (`ns:GetDisplayInfoForKey`, the Suggested-section render branch in
`CDMTab.lua`) to recognise a third key namespace, `item:<itemID>`. Every API the settled design
(ROADMAP 999.6) calls for is confirmed present and working: `C_Container.GetContainerNumSlots` /
`GetContainerItemID` walking bags `0..5` (TBT's own probe, Forever-verified), `C_Item.GetItemInfoInstant`
returning `itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID` (7 values, confirmed
against local retail source and against the probe's own destructuring), and `C_Item.GetItemSpell`
returning `spellName, spellID` or nothing at all for an item with no on-use effect.

The single open technical question CONTEXT.md flagged — `C_Item.GetItemIconByID` versus reusing the
`icon` value already returned by the filter's own `GetItemInfoInstant` call — resolves in favour of
**reusing the already-fetched value**: Blizzard's own doc marks `GetItemInfoInstant`'s `icon` return
`Nilable = false` (once the call succeeds at all) versus `GetItemIconByID`'s `Nilable = true`, and reuse
costs zero extra API calls per catalogue item. See "Icon Source" below for the full argument and the
recommended fallback shape that still satisfies CONTEXT.md's "no icon falls back to 134400" language.

The scan-trigger and count-display integration points both have exact existing precedents already in
the codebase: `StartPreview()` (`CDMTab.lua:27-32`) is the real "CDM opened" hook (driven by a 0.5s
`CooldownViewerSettings:IsVisible()` poll, not a script hook, to avoid the documented CDM-taint risk),
and `ns:RacialCooldownKeys()` (`Providers.lua:871-880`) is the byte-for-byte template for a dynamic,
cached, `wipe()`-based Suggested-tile provider. A genuinely useful discovery: `AddSuggestedTracker`
(`CDMTab.lua:101-122`) already **no-ops** for any key that is neither a `cd:<spellID>` key nor a member
of the static `SUGGESTED_KEYS` list — meaning an `item:<itemID>` tile rendered this phase is
automatically inert against the existing drag/right-click commit path with **zero extra guard code**,
which is exactly the "draggable in the same sense, but drop is Phase 47's work" boundary CONTEXT.md
describes. The one rough edge this produces (a drop plays the success sound and hides the ghost frame
even though nothing was created) is flagged below as an accepted, in-scope-for-Phase-47 UX gap, not a
Phase 46 bug.

**Primary recommendation:** Build the catalogue as a new small file or a new section of `Providers.lua`
following `ns:RacialCooldownKeys()`'s exact shape (module-level table, `wipe()` + rebuild, itemID keys
ascending), call it from `StartPreview()` alongside the existing `ns:RefreshProvidersAtRest()` call,
gate re-scans on `BAG_UPDATE_DELAYED` (already registered, `Core.lua:841`) behind a
`CooldownViewerSettings:IsVisible()` check, extend `ns:GetDisplayInfoForKey` with an `item:` branch that
does **not** route through `UserSpellProvider` (itemID is not a spellID), and reuse the icon captured
during the classID/subClassID filter pass rather than calling `GetItemIconByID` a second time.

**Housekeeping note (verify before planning a task for it):** CONTEXT.md's Specifics section states
"PROJECT.md is stale on one point" and still says generic item tracking is Forever-only. A direct read
of `.planning/PROJECT.md:21-32` (current file, 2026-09-24) shows this is **already corrected** — it
reads "Generic item tracking (backlog 999.6), **both flavours**" and explicitly documents the
Forever-only→both-flavours change with the `ITEM-10` citation. No PROJECT.md edit is needed for this
phase; CONTEXT.md's note appears to predate a PROJECT.md update made the same day.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Bag enumeration (itemIDs present) | TBT Runtime (Lua) | Game Client (`C_Container`) | TBT calls the client API each scan; the client owns the actual bag data |
| Consumable classification (classID/subClassID/use-spell filter) | TBT Runtime (Lua) | Game Client (`C_Item`) | Filter logic is TBT's; the classification data itself is client-owned and stable |
| Catalogue caching (itemID → {icon, count}) | TBT Runtime (Lua) | — | Module-level cache, wiped and rebuilt on scan, per CLAUDE.md's hot-path pattern |
| Icon/count resolution for a tile | TBT Runtime (Lua) | Game Client (`C_Item`) | TBT reads once per scan and caches; render path never calls the client API |
| Suggested-tile rendering | CDM UI (`CooldownViewerSettings` host frame) | TBT Runtime (Lua) | Tile frames are TBT-owned (`CreateIconFrame`), but parented into the CDM's settings panel, matching every other TBT tile |
| Tracked-key lookup (`item:` already tracked?) | TBT Runtime (Lua) | SavedVariables (`ns.db.trackedBuffs`) | Read-only membership test against the persisted table; no write this phase |
| Scan-trigger detection ("CDM opened") | CDM UI (`CooldownViewerSettings:IsVisible()`) | TBT Runtime (poll, not hook) | A script hook on this frame is a documented taint vector in instances; TBT already polls instead |

## Standard Stack

Not applicable in the npm/pip sense — this phase adds no third-party dependency. Every call used is a
Blizzard client API (`C_Item.*`, `C_Container.*`, `Enum.BagIndex`) already present in the client and
already exercised by this addon (cooldown trackers, Phase 38) or by TBT's own probe (999.6). No install
step, no version pin, nothing for `npm view`/`pip index` to check.

## Package Legitimacy Audit

**Not applicable.** This phase installs no external package of any kind — it is Lua source calling
first-party WoW client APIs. The Package Legitimacy Gate protocol is skipped; there is nothing to run
`slopcheck` against.

## Architecture Patterns

### Data Flow Diagram

```
CDM opened (CooldownViewerSettings becomes visible)
        │  detected by cdmWatcher OnUpdate poll (0.5s), CDMTab.lua:1665-1697
        ▼
StartPreview()                                   CDMTab.lua:27-32
        │  ns:RefreshProvidersAtRest()  (existing: trinket/pot at-rest scan)
        ▼
  [NEW] ns:RefreshItemCatalogue()  ◄──────────────────────────────┐
        │  wipe(itemCatalogue); for bag = 0,5 do                  │
        │    GetContainerNumSlots(bag) → GetContainerItemID(bag,slot)│  re-entry on
        │  for each distinct itemID:                              │  BAG_UPDATE_DELAYED
        │    GetItemInfoInstant(itemID) → classID, subClassID, icon│  IF CDM is shown
        │    GetItemSpell(itemID) → has a use-spell?               │  (gate this phase adds)
        │    classID==0 and subClassID~=7 and has-use-spell        │
        │      → itemCatalogue[itemID] = { icon, count }           │
        ▼                                                          │
ns:RefreshTBTSections()  (existing, CDMTab.lua:717)  ───────────────┘
        │  reads the CACHE only — never re-walks bags (locked pattern)
        ▼
  Suggested-section branch, def.key=="suggested" and tbtActiveCategory=="spells"
  (CDMTab.lua:766, alongside the existing racial-tiles loop)
        │  for itemID ascending in itemCatalogue:
        │    if not ns.db.trackedBuffs["item:"..itemID] then
        │      acquire pooled tile, set icon + chargeCount.Current, Show()
        ▼
Suggested tile visible: item's own icon, item's own count, question-mark fallback on unreadable icon
```

### Recommended file placement

CONTEXT.md leaves this to discretion. `Providers.lua` is already 1185 lines and holds every other
catalogue (`RACIAL_SPELLS`, `TRINKET_SPELLS`, `POT_SPELLS`, `ns:RacialCooldownKeys`). Given the bag-walk
and filter logic (~60-80 lines by the probe's own line count) is a distinct concern from the provider
mixins, and Phase 47 will need to add a real `ItemProvider` mixin here too, **a new file
`ItemCatalogue.lua`** is the cleaner seam — it needs one `.toc` entry and must load after `Core.lua`
(for `ns.ITEM_KEY_PREFIX`/`ns:ItemKeyItemID`) and before `CDMTab.lua` (which calls into it). Either
placement is workable; this is not a locked decision.

### Pattern: dynamic Suggested catalogue (copy `ns:RacialCooldownKeys`)

```lua
-- Source: TerribleBuffTracker/Providers.lua:871-880 (existing pattern to copy)
function ns:RacialCooldownKeys()
	wipe(racialCooldownKeys)
	for slot = 1, #ns.RACIAL_KEYS do
		local def = ResolveRacial(slot)
		if def and def.spellID and def.cooldown then
			racialCooldownKeys[#racialCooldownKeys + 1] = ns:TrackerKey(def.spellID, "cooldown")
		end
	end
	return racialCooldownKeys
end
```

The item catalogue builder is the same shape: a module-level table, `wipe()`'d and rebuilt on scan,
never rebuilt on the render path. The render path (`CDMTab.lua:766`'s branch) should read this cache the
same way it reads `ns:RacialCooldownKeys()` today — no bag call anywhere in `ns:RefreshTBTSections`.

### Pattern: bag walk (VERIFIED on Forever 1.60.1 by TBT's own probe)

```lua
-- Source: TerribleBuffTracker/tools/TBTProbe/Probe.lua:2407-2424 (measured working on Forever 1.60.1)
-- Distinct itemIDs across every bag the client admits to having. Bag 5 is the
-- retail reagent bag and simply returns nothing on a client without one.
local function ConsumBagItems()
	local items, seen = {}, {}
	for bag = 0, 5 do
		local ok, slots = ConsumCall("GetContainerNumSlots", bag)
		local count = ok and CNum(slots) or 0
		for slot = 1, (count or 0) do
			local ok2, itemID = ConsumCall("GetContainerItemID", bag, slot)
			local id = ok2 and CNum(itemID)
			if id and not seen[id] then
				seen[id] = true
				items[#items + 1] = id
			end
		end
	end
	return items
end
```

`bag = 0, 5` is `Enum.BagIndex.Backpack` (0) through `Enum.BagIndex.ReagentBag` (5)
[VERIFIED: `Interface/AddOns/Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua:28-33`,
local retail source]. This range is expressible with **no flavour check**: an absent reagent bag (a
character with none purchased, or in principle a client without the slot) makes
`GetContainerNumSlots(5)` return `0`, which the loop above already treats as "nothing to walk" — a
data-absence condition, not a branch on client identity, matching CLAUDE.md's capability-check rule.
The probe's own comment states this was run and measured on Forever 1.60.1, so the range is
`[VERIFIED: TerribleBuffTracker/tools/TBTProbe/Probe.lua, Forever 1.60.1 probe run]`, not inferred.

**On the literal `0, 5` versus `Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag`:** the named constants
read better, but their presence on the Forever client is **unverified** — `wow-ui-source` is a
Midnight-only (retail) snapshot and cannot prove anything about Forever's `Enum` table, and the probe
that ran successfully on Forever used the literal integers, not the enum. Recommend keeping the literal
`0, 5` (already proven on both flavours) rather than swapping in `Enum.BagIndex.*` sight-unseen on
Forever. If the planner prefers the named form for readability, guard it:
`local firstBag = (Enum.BagIndex and Enum.BagIndex.Backpack) or 0` — the same capability-check idiom
`TryRegisterEvent` already uses for events (`Core.lua:817-820`). `[ASSUMED: Enum.BagIndex presence on
Forever — not proven either way; the safer literal-integer path sidesteps the question entirely]`.

### Pattern: `GetItemInfoInstant` filter + `GetItemSpell` (VERIFIED signature, `[CITED]` filter values)

```lua
-- Signature confirmed: Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:637-657
-- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemInfo)
-- Cross-checked against two real call sites in local retail source that destructure the same 7 values:
--   Interface/AddOns/Blizzard_UIPanels_Game/Mainline/GameDialogDefs.lua:445
--   Interface/AddOns/Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua:730
-- And against TBT's own probe, run and measured on Forever 1.60.1:
--   TerribleBuffTracker/tools/TBTProbe/Probe.lua:2436
local okI, _, itemType, itemSubType, icon, classID, subClassID = ConsumCall("GetItemInfoInstant", itemID)
--                                          ^ NOTE: the probe's own destructuring skips a slot (see caveat below)

-- Filter, settled design (ROADMAP 999.6, CONTEXT.md, user decision 2026-09-24):
local isConsumable = classID == Enum.ItemClass.Consumable            -- 0, VERIFIED
local isBandage = subClassID == Enum.ItemConsumableSubclass.Bandage  -- 7, VERIFIED
local _, useSpellID = C_Item.GetItemSpell(itemID)                    -- nil, nil if no use-spell
local passesFilter = isConsumable and not isBandage and useSpellID ~= nil
```

**Return order caveat, worth a second look before coding:** `GetItemInfoInstant` returns SEVEN values —
`itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID` — but the probe's own line
(`Probe.lua:2436`) reads `local okI, _, itemType, itemSubType, _, _, classID, subClassID =
ConsumCall(...)`, which is `ok, <wrapped-by-pcall-so-shifted-by-one>` — `ConsumCall` returns
`pcall(fn, ...)`, so its own first return is pcall's own `ok`, and everything after is the real
function's returns starting at position 1 (`itemID`). Position-count it out before copying: the probe
skips `itemID` (`_`) then reads `itemType, itemSubType`, skips `itemEquipLoc` and `icon` (`_, _`), then
reads `classID, subClassID` — seven slots consumed, matching the doc exactly. **A direct (non-pcall)
call is one position to the left of the probe's own indices.** Confidence: HIGH on the doc-verified
7-value order; MEDIUM on transcribing it correctly into non-pcall'd production code — recommend the
planner have the implementer count positions against the doc table above rather than copy the probe's
indices verbatim.

`Enum.ItemClass.Consumable = 0` and `Enum.ItemConsumableSubclass.Bandage = 7`
`[VERIFIED: Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua:206,
237-249]`. Also confirmed from the same table: `Enum.ItemConsumableSubclass.Other = 8` — this is the
literal Blizzard name for the `"0/8"` residue (glue, campfire kit, lute, crate) CONTEXT.md/999.6 already
measured and decided to keep; it is not a mystery subclass, it is Blizzard's own catch-all bucket.

`GetItemSpell` signature confirmed: `spellName, spellID = C_Item.GetItemSpell(itemInfo)`, `MayReturnNothing
= true` `[VERIFIED: ItemDocumentation.lua:948-963]` — for an item with no on-use effect the call returns
nothing at all (both values nil), which is exactly the truthy/falsy test 999.6's filter already assumes.

### Icon Source — recommendation, not a locked CONTEXT.md decision

CONTEXT.md names `C_Item.GetItemIconByID(itemID)` as the icon call, with a 134400 fallback, and flags it
as "the one call in 999.6's plan never yet exercised." Both routes are real Blizzard APIs, both used
pervasively in local retail source (`GetItemIconByID`: 15+ call sites across `Blizzard_HousingMarketCart`,
`Blizzard_PerksProgram`, `Blizzard_SharedXML/FormattingUtil.lua:205`, etc. — always called with a bare
itemID, never behind a cache guard). The choice is between:

| | `C_Item.GetItemIconByID(itemID)` | Reuse `icon` from `GetItemInfoInstant(itemID)` |
|---|---|---|
| Extra API call per catalogue item | Yes, one more | No — already called for classID/subClassID |
| Doc's own `Nilable` on the return | `true` (`ItemDocumentation.lua:600`) | `false` (`ItemDocumentation.lua:653`) |
| Exercised by the 999.6 probe | No | Yes — the filter call itself |
| Exercised elsewhere in TBT | No | No, but same underlying data source as the working filter call |

**Recommendation: reuse the `icon` value already captured during the classID/subClassID filter pass**,
falling back to `134400` only if that value is falsy — this satisfies CONTEXT.md's stated intent
("the item's own icon... fall back to 134400") while costing nothing extra and resting on the
already-measured-working call rather than the never-yet-exercised one. This is a **recommendation, not a
relitigation** of a locked decision — CONTEXT.md's own <what_to_research> section explicitly asked for
this comparison and a recommendation with evidence. If the planner or user prefers to keep
`GetItemIconByID` as CONTEXT.md wrote it (e.g. for symmetry with how tracked-cooldown icons are resolved
elsewhere), that is also safe — both are `SecretArguments = "AllowedWhenUntainted"` and neither doc entry
states the *return* can be secret, though per the locked project rule (see Secret Values below) both
should still be read through `issecretvalue()` first regardless of which is chosen.

### `chargeCount.Current` — confirmed match, no mismatch found

```lua
-- Source: TerribleBuffTracker/Display.lua:478-483 (Phase 38, CD-03)
frame.chargeCount = CreateFrame("Frame", nil, frame)
frame.chargeCount:SetAllPoints()
frame.chargeCount.Current = frame.chargeCount:CreateFontString(nil, "OVERLAY")
frame.chargeCount.Current:SetFontObject(NumberFontNormal)
frame.chargeCount.Current:SetPoint("BOTTOMRIGHT", -2, 2)
frame.chargeCount:Hide()
```

CONTEXT.md's citation (`NumberFontNormal`, anchored `BOTTOMRIGHT, -2, 2`) is exact — `[VERIFIED]` against
the live file, no mismatch. This construction lives in **Display.lua's** cooldown-icon builder, which
CDM's Suggested tiles do **not** use — Suggested tiles come from `CreateIconFrame`
(`CDMTab.lua:149-160`), confirmed by direct read to hold only `f.Icon` (a `Texture`) and a `HIGHLIGHT`
texture, no fontstring of any kind. CONTEXT.md's plan to add an equivalent fontstring to
`CreateIconFrame`'s frame, copying the same font object and anchor, is therefore additive and does not
collide with anything that frame already draws.

**Pooled-frame discipline, confirmed real (not hypothetical):** `SetDesaturated` is written
unconditionally on every tile every render pass at both `CDMTab.lua:786` (racial branch, `false` always)
and `:818` (static branch, `(info and info.unsupported) == true`) — because `section.itemPool:ReleaseAll()`
(`CDMTab.lua:726`) recycles frames across renders and a value not re-written this pass is whatever the
previous tile at that pool slot left behind. The item count fontstring needs the identical discipline:
`SetText(...)` **and** `:Show()`/`:Hide()` on every tile, every pass — never only on the tiles that have a
count to show.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "Is this item a consumable, not a quest item/recipe/key/trade good?" | Name substring matching | `classID == Enum.ItemClass.Consumable` from `GetItemInfoInstant` | `classID` is a stable server-assigned tag; 999.6 already measured name-matching unnecessary — quest items, recipes, keys, trade goods all fall out on `classID` alone |
| "Is this a bandage?" | A hardcoded item-name/ID blacklist | `subClassID == Enum.ItemConsumableSubclass.Bandage` (7) | Real Blizzard tag, no maintenance burden as new bandage items ship |
| "Does this item do anything when used?" | Heuristics on item description text | `C_Item.GetItemSpell(itemID)` returning non-nil | Direct, stable, and already the second half of the locked ITEM-08 filter |
| Bag-slot magic numbers | Ad hoc `for bag = 0, 4` (missing the reagent bag) or a flavour-conditional range | `for bag = 0, 5` — literal, proven cross-flavour by the probe | A narrower range silently drops reagent-bag items; a flavour-conditional range reintroduces the banned runtime check |
| Catalogue de-duplication | Summing per-slot counts across duplicate stacks | `C_Item.GetItemCount(itemID)` once per distinct itemID | The API already aggregates across bags; CONTEXT.md's decision states this explicitly and it matches the doc's own default-args shape |

**Key insight:** every filter and lookup this phase needs already exists as a single, direct client API
call. The only genuinely new code is the bag-walk loop, the cache table, and the dispatch-map extension
— there is no library-shaped problem here to accidentally reinvent.

## Common Pitfalls

### Pitfall 1: `GetItemInfoInstant`'s pcall-shifted return positions
**What goes wrong:** Copying the probe's destructuring pattern (`local okI, _, itemType, ... =
ConsumCall(...)`) directly into non-pcall'd production code silently reads one field to the right of
where the value actually is.
**Why it happens:** `ConsumCall` wraps every API call in `pcall`, which prepends its own `ok` boolean to
the return list — the probe's indices are correct for `pcall(fn, ...)` but wrong for a bare `fn(...)`.
**How to avoid:** Count positions against the doc table (`ItemDocumentation.lua:647-656`) directly:
`itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID`, seven values, zero-indexed
from position 1 for a bare call.
**Warning signs:** `classID`/`subClassID` come back as strings (they'd actually be `itemEquipLoc`/`icon`
shifted) or as `nil` when the item clearly has a valid class.

### Pitfall 2: catalogue scan run from the render path
**What goes wrong:** Calling the bag-walk from inside `ns:RefreshTBTSections` (or any of its 11 call
sites) instead of only from the scan trigger re-walks the bags on every drag, add, move and delete —
exactly the mistake `ns:IsSuggestedKeyResolvable`'s memo already exists to prevent for the racial
catalogue.
**Why it happens:** `ns:RefreshTBTSections` is the obvious place to reach for "current" data, since it's
already where every other Suggested source is read.
**How to avoid:** The scan function and the render function must be two different functions; the render
function's only bag-catalogue-shaped call should be a table read (`for itemID, row in pairs(itemCatalogue)
do`), never a `C_Container`/`C_Item` call.
**Warning signs:** Frame-time hitches while dragging in the CDM tab; `C_Item`/`C_Container` calls showing
up in a profile taken during a drag rather than during a CDM open.

### Pitfall 3: `AddSuggestedTracker`'s silent no-op looks like success on drop
**What goes wrong:** Dropping an `item:` Suggested tile into a container plays
`SOUNDKIT.UI_CURSOR_DROP_OBJECT`, hides the drag ghost, and calls `ns:RefreshTBTSections()` — all the
same positive feedback a successful drop gets — but `AddSuggestedTracker` (`CDMTab.lua:101-122`) returns
early with no tracker created, because an `item:` key is neither a `cd:<spellID>` key nor a member of
`ns.SUGGESTED_KEYS`.
**Why it happens:** `EndDrag` (`CDMTab.lua:545` region, specifically the `isFromSuggested` branch around
`:573-583`) calls `AddSuggestedTracker` unconditionally and always plays the success sound/refresh
afterward, regardless of whether anything was actually added.
**How to avoid:** This is in-scope, accepted behaviour for Phase 46 per CONTEXT.md's own boundary
("draggable in the same sense... what happens on drop is Phase 47's work") — not a bug to fix this
phase. Flagging it here so it is not mistaken for a regression during Phase 46 verification, and so
Phase 47's plan explicitly includes teaching `AddSuggestedTracker` about `item:` keys (it is the natural
place `ITEM-04`'s "dragging creates a tracker" lands).
**Warning signs:** A human verification pass for Phase 46 that tries dragging an item tile and reports
"nothing happened, but no error either" — expected, not a defect, this phase.

### Pitfall 4: `ns:GetDisplayInfoForKey` routing an `item:` key into `UserSpellProvider`
**What goes wrong:** `UserSpellProvider:GetDisplayInfo(key)` (`Providers.lua:179-218`) treats any
non-numeric key it doesn't reject as a **spellID** source (`ns:CooldownKeySpellID`, then
`ns:GetSpellIcon(spellID)`). Routing an `item:<itemID>` key here would call spell-icon resolution on a
number that is actually an itemID, producing either a wrong icon or a hard failure.
**Why it happens:** `ns:GetDisplayInfoForKey`'s existing string-key fall-through
(`Providers.lua:1105-1121`) currently only recognises two shapes: an exact match in `keyToProvider`
(`trinket`/`pot`/`lust`/`racial`/`racial2`), or anything `ns:CooldownKeySpellID` can parse — everything
else falls through to `UserSpellProvider` on the (previously correct) assumption that the only other
string shape in play is a `cd:` key.
**How to avoid:** Add an explicit `item:` branch **before** the `ns:CooldownKeySpellID` fallback check,
returning a dedicated item-display helper (reading the catalogue cache, not calling `UserSpellProvider`)
rather than falling through.
**Warning signs:** An item Suggested tile whose tooltip shows a spell name/spellID line instead of an
item name, or whose icon is a spell icon rather than the item's own icon.

## Secret Values

Every relevant `C_Item`/`C_Container` call in the local API doc carries `SecretArguments =
"AllowedWhenUntainted"` — this describes what the call **accepts** as an argument (it tolerates a secret
itemInfo/itemLink without raising), not a guarantee about what it **returns**. None of the doc entries
for `GetContainerNumSlots`, `GetContainerItemID`, `GetItemInfoInstant`, `GetItemSpell`, `GetItemCount`,
or `GetItemIconByID` carry an explicit secrecy predicate the way cooldowns do
(`C_Secrets.ShouldCooldownsBeSecret` — `[VERIFIED:
Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua:129-137]`, and
already cited by ROADMAP 999.6 as measured `false` in combat on Forever). That is an absence of evidence,
not evidence of absence — the local snapshot cannot prove these seven calls are never secret in some
restricted context this phase hasn't tested (encounter/challenge-mode secrecy stacks on top of plain
combat per the existing `Core.lua` comment at line ~965).

**The locked project rule applies to every one of these seven calls, unconditionally:**
`issecretvalue(v)` first, then `type(v)`, exactly as `Core.lua:1130-1141`, `Core.lua:1038-1074`, and the
probe's own `CNum`/`CStr` helpers (`Probe.lua:2385-2397`) already do. Concretely, for this phase:

- `GetContainerItemID`'s returned itemID — guard before using it as a table key or comparing it.
- `GetItemInfoInstant`'s `classID`/`subClassID` — guard before the `==` filter comparisons.
- `GetItemSpell`'s `spellID` — guard before using truthiness as the filter's second half (a secret
  non-nil value would still be "truthy" in a naive `if spellID then`, which is exactly the trap
  `issecretvalue()`-first exists to catch — `type()` alone reports `"number"` for a secret number and
  passes silently).
- `GetItemCount`'s `count` — guard before writing it into the fontstring's `SetText`.
- Whichever icon source is chosen — guard before `SetTexture`.

Where a guard fails (value is secret or the wrong type), CONTEXT.md's own degrade-not-error rule applies:
render the tile without that detail (icon falls back to `134400`, count fontstring stays hidden) rather
than erroring or skipping the whole tile.

## Code Examples

### Parser twin for `ns:ItemKeyItemID` (copy of `ns:CooldownKeySpellID`)

```lua
-- Source: TerribleBuffTracker/Core.lua:471-480 (pattern to copy, locked shape per CONTEXT.md)
ns.COOLDOWN_KEY_PREFIX = "cd:"

function ns:TrackerKey(spellID, trackerType)
	if trackerType == "cooldown" then
		return ns.COOLDOWN_KEY_PREFIX .. spellID
	end
	return spellID
end

function ns:CooldownKeySpellID(key)
	if type(key) ~= "string" then
		return nil
	end
	local id = key:match("^cd:(%d+)$")
	return id and tonumber(id) or nil
end
```

`ns.ITEM_KEY_PREFIX = "item:"` and `ns:ItemKeyItemID(key)` (using `key:match("^item:(%d+)$")`) are the
direct analogues — CONTEXT.md already specifies this exact shape and it is locked.

### Dispatch extension point (recommendation, HIGH confidence — direct code read)

```lua
-- Source: TerribleBuffTracker/Providers.lua:1105-1121 (current code, to be extended)
function ns:GetDisplayInfoForKey(key)
	if type(key) == "string" then
		local p = keyToProvider[key]
		if p then
			return p:GetDisplayInfo(key)
		end
		-- NEW: item: keys are dynamic per-itemID, so they never belong in the static
		-- keyToProvider map (that map is for fixed meta keys only). Recognise them here,
		-- BEFORE the CooldownKeySpellID fallback -- an item: key is not a cd: key and must
		-- not fall through to UserSpellProvider, which would treat the itemID as a spellID.
		local itemID = ns:ItemKeyItemID(key)
		if itemID then
			return ns:ItemDisplayInfo(itemID) -- reads the catalogue cache; new this phase
		end
		if not ns:CooldownKeySpellID(key) then
			return nil
		end
	end
	return UserSpellProvider:GetDisplayInfo(key)
end
```

This is the mechanism that makes tooltips work for free: `CreateIconFrame`'s `OnEnter` handler
(`CDMTab.lua:176`, `local info = ns:GetDisplayInfoForKey(self.spellID)`) is identical for every tile
type — a tracked buff, a `cd:` cooldown, a meta tile, and (once this branch exists) an `item:` tile. No
new tooltip code is needed if this dispatch branch resolves correctly.

## Validation Architecture

No test runner exists or is planned for a WoW addon — `.planning/ROADMAP.md`'s own backlog record states
this plainly ("No test suite exists. No build manifest, no `luacheck`, no automated regression gate.
Every claim in v0.4.0 rests on in-game observation.") This phase does not change that; verification here
is **static assertion** (things a script or a source grep can prove before ever loading the client) plus
**in-game human checks** (things only a running client can prove). Being honest about the split matters
more than pretending either half substitutes for the other.

### Static assertions (provable without WoW running)

| Check | Command / Method | Proves |
|-------|-------------------|--------|
| stylua clean | `stylua .` from repo root (no flags — `stylua.toml` pins CRLF) | No formatting drift, no invisible CRLF→LF reflow (per CLAUDE.md's documented incident) |
| No flavour check introduced | `grep -n "buildInterfaceVersion\|GetBuildInfo\|classicVersion\|wow_classic" <new files>` | ITEM-10's "one code path" constraint held |
| `issecretvalue` precedes every `type()` on a new API read | `grep -B1 "type(.*) ==" <new files>` manually checked against the surrounding `issecretvalue` | Locked project ordering rule held for every new guard |
| TOC still declares both interface versions if a new file is added | `grep "Interface:" TerribleBuffTracker.toc` unchanged, new file listed once | No flavour-forked file, one TOC still covers both clients (CLAUDE.md) |
| New file (if any) loads before `CDMTab.lua`, after `Core.lua` | Read `TerribleBuffTracker.toc` load order | `ns.ITEM_KEY_PREFIX`/`ns:ItemKeyItemID` are upvalues available when `CDMTab.lua` needs them |
| `AddSuggestedTracker` still no-ops for `item:` keys (until Phase 47 changes it) | Source read: `item:` matches neither `ns:CooldownKeySpellID` nor `ns.SUGGESTED_KEYS` membership | Phase 46 does not accidentally let a drop create a malformed tracker |

### In-game human checks (the only route to ITEM-01/03/08/10)

There is no automated way to open a real CDM, populate real bags, and confirm a tile renders — these
must be run by the user on both clients, matching v0.4.0 Phase 43/44's precedent of testing-pass phases
with no automated substitute.

1. **ITEM-01 (catalogue built from bags, keyed by itemID):** Open the CDM with a mixed bag (potions,
   a healthstone, a quest item, a recipe, a key, a trade good, a bandage) present. Confirm the same
   itemID does not produce two tiles even if split across two stacks/bags.
2. **ITEM-03 (icon + count):** Confirm each Suggested item tile shows the item's own icon (not the
   134400 placeholder, unless the item is genuinely uncached) and a count fontstring matching the
   in-game bag count. Drink/use one to a lower stack size, reopen the CDM (or trigger the
   `BAG_UPDATE_DELAYED` re-scan while it's open), confirm the count updates.
3. **ITEM-08 (exclusions):** Confirm a quest item, a recipe, a key, a trade good, and a bandage are
   **absent**. Confirm the known `0/8` residue (glue, campfire kit, lute, crate, or whatever the test
   character carries) is still **present** — this is the accepted-and-documented behaviour, not a bug.
4. **ITEM-10 (both flavours identically):** Repeat checks 1-3 on Midnight retail. Since retail's
   item-cooldown/count secrecy in combat is unmeasured (999.6's probes were Forever-only), specifically
   check this scan **out of combat first**, then, if reachable, once in combat — confirm a degrade (no
   count shown) rather than an error if a value comes back secret.
5. **Pitfall 3 sanity check:** drag an item tile into a container and confirm the documented no-op
   (ghost disappears, sound plays, no tile appears in the target container, item tile remains in
   Suggested) — expected this phase, would be a regression if a tracker actually got created with a
   wrong shape.

### Sampling cadence

- **Per task:** static assertions above, run after each plan/task that touches a new file.
- **Per phase gate:** the five in-game checks above, run once the phase's plans are all complete, before
  `/gsd-verify-work`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| stylua | Post-task formatting (CLAUDE.md mandate) | ✓ | present at `~/.cargo/bin/stylua` | — |
| Midnight retail client | ITEM-10 both-flavours verification | ✓ | `World of Warcraft\_retail_` present | — |
| WoW Forever beta client | ITEM-10 both-flavours verification, and the source of every measured fact in this document | ✓ | `World of Warcraft\_classic_beta_` present | — |
| `wow-ui-source` (local retail snapshot) | Citation source for this research | ✓ | branch `live`, 12.1.0 | — (read-only, never modified) |

No missing dependency, no fallback needed. This phase introduces no new tool, library, or service.

## Security Domain

`security_enforcement` is absent from `.planning/config.json`, so the default (enabled) applies, but the
ASVS categories are written for network/web applications and mostly do not map onto a single-player
client addon with no network surface, no authentication, and no server-side trust boundary of its own —
TBT reads client-local data and writes to `TerribleBuffTrackerDB` (local SavedVariables), nothing else.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | No auth surface — addon runs in the player's own client session |
| V3 Session Management | No | No sessions — SavedVariables persist per-account, no network session |
| V4 Access Control | No | No multi-user boundary inside the addon |
| V5 Input Validation | Yes (narrow) | `issecretvalue()`-then-`type()` on every value read from a Blizzard API — the addon's actual trust boundary is "is this value the shape I expect," not user input in the web sense |
| V6 Cryptography | No | No cryptographic operation anywhere in this phase or the addon |

### Known threat patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secret-value type confusion (a secret number passes `type(v)=="number"`) | Tampering (of TBT's own logic, not an external attacker) | `issecretvalue()` first, always — the locked project rule, applied to every new `C_Item`/`C_Container` read this phase adds |
| CDM frame taint from a script hook on a secure Blizzard frame | Tampering (taint propagation) | Poll `CooldownViewerSettings:IsVisible()` from a separate watcher frame (`cdmWatcher`, `CDMTab.lua:1665`), never `HookScript` on `CooldownViewerSettings` itself — already the established pattern, no new risk introduced if the scan hooks into `StartPreview()` as recommended |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Enum.BagIndex.Backpack`/`.ReagentBag` exist with the same values (0, 5) on the Forever client | Architecture Patterns — bag walk | Low: the recommendation is to use literal `0, 5` (Forever-proven by the probe) rather than the enum, specifically to sidestep this being load-bearing |
| A2 | Neither `GetItemCount`, `GetItemInfoInstant`, nor `GetItemIconByID` can return a secret value in any context | Secret Values | Low: the universal `issecretvalue()`-first guard is recommended regardless, so a wrong assumption here degrades to a hidden tile detail, not a crash |
| A3 | spellID→itemID is effectively 1:1 for on-use consumables (no two catalogue items share one `GetItemSpell` result) | Open Questions | Medium for Phase 47 specifically: if wrong, a spellID-keyed "which item was used" map (needed for count-decrement) would misattribute a use to the wrong item; not a Phase 46 risk, since Phase 46 does not build that map |

## Open Questions

1. **Can two catalogue items ever share one `GetItemSpell` result?**
   - What we know: every currently hand-maintained spellID→itemID map in this codebase
     (`TRINKET_SPELLS`, `POT_SPELLS`, `Providers.lua:223-256`, 13 entries) is 1:1 — no observed
     collision. 999.6's measured "shared cooldown" finding is about the item's **cooldown category**,
     not its use-spell; each potion in that measurement kept its own distinct effect spellID.
   - What's unclear: whether some older, Forever-era item pair could share a literal on-use spellID
     (a pattern that existed in original Classic-era item design for some low-level consumables). This
     document found no evidence either way and did not exhaustively search for it.
   - Recommendation: not a Phase 46 concern — Phase 46 builds no spellID→itemID map at all (CONTEXT.md's
     "Entry creation is Phase 47" boundary). Phase 47's research should re-open this question
     specifically when it designs the use→item attribution map, since that is where a collision would
     actually bite (ITEM-06's "count decreases only on a landed use").

2. **Retail's secrecy behaviour for `GetItemCount`/`GetItemInfoInstant` in combat/M+/raid.**
   - What we know: `ShouldCooldownsBeSecret()` was measured `false` on Forever (999.6); no retail
     measurement exists for any of this milestone's item APIs (both probe runs were Forever-only, per
     `PROJECT.md:30` and CONTEXT.md).
   - What's unclear: whether Midnight retail's stricter secrecy model (already documented elsewhere in
     this project as stacking encounter/challenge-mode/restricted-map restrictions on top of combat)
     extends to plain item count/classification reads, not just cooldowns and auras.
   - Recommendation: the `issecretvalue()`-first guard on every new read already makes this safe to
     ship without knowing the answer — a secret value degrades the tile (icon/count missing) rather than
     erroring. Phase 52's retail review pass is the already-scheduled place to observe the real answer.

## Sources

### Primary (HIGH confidence)

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua` (local retail source,
  `wow-ui-source`, branch `live`, 12.1.0) — `GetItemInfoInstant` (:637-657), `GetItemIconByID` (:589-602),
  `GetItemSpell` (:948-963), `GetItemCount` (:429-446), `GetItemCooldown` (:412-427), `IsUsableItem`
  (:1590-1604)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua` — `GetContainerNumSlots`
  (:313-326), `GetContainerItemID` (:175-190)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua:28-33` —
  `Enum.BagIndex.Backpack = 0`, `.ReagentBag = 5`
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua:198-251` —
  `Enum.ItemClass` (21 values), `Enum.ItemConsumableSubclass` (13 values)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua:119-137` —
  `ShouldAurasBeSecret`, `ShouldCooldownsBeSecret`
- `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:62-79, 359-371` — bag-range
  constants (`NUM_TOTAL_EQUIPPED_BAG_SLOTS`) and enumeration idiom, local retail source
- `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:185-186` — `NUM_REAGENTBAG_SLOTS`,
  `NUM_TOTAL_EQUIPPED_BAG_SLOTS` definitions
- `TerribleBuffTracker/tools/TBTProbe/Probe.lua:2338-2470` — TBT's own probe, **measured working on
  Forever 1.60.1**, the strongest evidence in this document for anything Forever-specific
- `TerribleBuffTracker/Core.lua`, `Providers.lua`, `CDMTab.lua`, `Display.lua` — read directly, all
  citations line-numbered above
- `.planning/ROADMAP.md` backlog 999.6 — settled design and measured findings
- `.planning/PROJECT.md:11-32` — current milestone/feature description, confirms the ITEM-10
  both-flavours correction already landed
- `.planning/phases/46-item-catalogue-suggested-tiles/46-CONTEXT.md` — locked user decisions

### Secondary (MEDIUM confidence)

- The `TRINKET_SPELLS`/`POT_SPELLS` hand-maintained maps (`Providers.lua:223-256`) as evidence that
  spellID→itemID is 1:1 for every on-use item currently tracked — 13 items, 13 distinct spellIDs, no
  observed collision. Not proof no collision can ever occur (see Open Questions).

### Tertiary (LOW confidence / flagged for validation)

- `Enum.BagIndex` presence and identical values on the Forever client — never directly confirmed;
  the probe's literal-integer bag range sidesteps needing this, so the recommendation above avoids
  relying on it.
- Whether `GetItemCount`/`GetItemInfoInstant`/`GetItemIconByID` can ever return a secret value in some
  restricted context — no explicit secrecy predicate found for these three calls in the local doc,
  unlike cooldowns; absence of a documented predicate is not proof of absence of the behaviour.

## Metadata

**Confidence breakdown:**
- Standard stack / API signatures: HIGH — every signature cross-checked against the official generated
  doc and against a real call site in local source, and the bag-walk range is additionally
  Forever-measured by TBT's own probe.
- Architecture / integration points: HIGH — every citation is a direct read of the current file, not
  inferred; the `AddSuggestedTracker` no-op finding and the `StartPreview()` scan-trigger finding are
  both derived from tracing actual call graphs, not assumed.
- Pitfalls: HIGH for pitfalls 1, 2, 4 (derived directly from source); MEDIUM for pitfall 3 (the UX
  consequence is derived correctly from the code, but its acceptability is a judgment call CONTEXT.md
  already made, not something this research can independently verify without a human running it).

**Research date:** 2026-09-24
**Valid until:** Should remain valid for the life of this milestone (WoW Midnight/Forever API surface is
not expected to churn week-to-week); re-verify signatures if a client patch lands before Phase 46's
plans are executed.
