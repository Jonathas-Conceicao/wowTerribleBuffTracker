# Phase 46: Item Catalogue & Suggested Tiles - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous), questions front-loaded and answered by the user before work began

<domain>
## Phase Boundary

Opening the Cooldown Manager on either flavour walks the player's bags, builds a catalogue of
likely consumables keyed by **itemID**, and renders every catalogued item that is not already
tracked as a tile in the **Suggested** section of the **Cooldowns** tab, showing the item's own
icon and the number currently held.

**This phase is read-and-render only.** Creating a tracker from a tile, decrementing counts,
reading item cooldowns and reconciling against the bags are all Phase 47. The tiles this phase
produces are draggable in the same sense every other Suggested tile is, but what happens on drop
is Phase 47's work — this phase's success criteria stop at the catalogue and its tiles.

Requirements: ITEM-01, ITEM-03, ITEM-08, ITEM-10.

</domain>

<decisions>
## Implementation Decisions

### Tracker key namespace — USER DECISION, front-loaded 2026-09-24

- A tracked item lives under a **third key namespace, `item:<itemID>`** (`ns.ITEM_KEY_PREFIX`),
  alongside the existing bare-numeric (buff) and `cd:<spellID>` (cooldown) namespaces in the one
  `ns.db.trackedBuffs` table.
- **No schema bump.** This is purely additive — only newly created entries use it, and nothing
  that walks `pairs(ns.db.trackedBuffs)` needs to change. Same precedent as `userContainers`
  (`Core.lua:878`) and `mergeMode` (Phase 35.1), both of which added shape without moving
  `CURRENT_SCHEMA_VERSION` (`BuffEngine.lua:100`, currently 6).
- Rejected: reusing `cd:<useSpellID>`. It loses the itemID that `GetItemCooldown`/`GetItemCount`
  need, and it collides with a plain spell-cooldown tracker for the same spell — the exact class
  of bug the `cd:` namespace was introduced to fix (`Core.lua:455-471`).
- The parser is the twin of `ns:CooldownKeySpellID` (`Core.lua:487`): `key:match("^item:(%d+)$")`,
  returning a number or nil. Name it `ns:ItemKeyItemID`.
- Phase 46 only needs the key **shape** — to answer "is this item already tracked?" when filtering
  the catalogue down to the Suggested list. Entry creation is Phase 47.

### Catalogue construction

- The filter is the one settled in ROADMAP backlog 999.6 section 1 and measured on Forever 1.60.1:
  `classID == 0` (`Enum.ItemClass.Consumable`), **has a use-spell** (`C_Item.GetItemSpell`
  returns a spell), and `subClassID ~= 7` (`Enum.ItemConsumableSubclass.Bandage`).
- `classID`/`subClassID` come from `C_Item.GetItemInfoInstant(itemID)` and are **stable**.
  `IsUsableItem` is explicitly **not** a filter — the probe measured it flipping between an
  out-of-combat and an in-combat scan of the same bag.
- Quest items (`classID 12`), recipes (9), keys (13), trade goods (7) and miscellaneous (15) all
  fall out on `classID` alone — ITEM-08 needs no name matching. Bandages fall out on the real
  `0/7` subclass tag. Craftsman's Writ, a Forever profession quest item that classifies `0/8`,
  falls out for having no use-spell.
- The `0/8` residue the probe found on the test character (glue, campfire kit, lute, crate) is
  **kept**, per 999.6 section 1: "that residue is acceptable in a list the user drags from, and the
  filter is expected to be refined during the milestone". Excluding `0/8` outright is not safe
  without knowing which subclass the healthstone carries on Forever.
- Keyed by **itemID, never by bag and slot** (ITEM-01). Bag/slot is positional and shifts when
  stacks split or bags are sorted. The bag walk is only how items are *discovered*; the itemID is
  the identity.
- A duplicated itemID across several bag slots collapses to **one** catalogue row whose count is
  `C_Item.GetItemCount(itemID)`, not a per-slot sum — the API already aggregates.

### Scan cadence

- Scan on **CDM open**, and re-scan on `BAG_UPDATE` **only while the CDM frame is shown**. A bag
  update with the CDM closed marks the catalogue dirty; the next open rebuilds it.
- The catalogue is cached in a **reusable module-level table wiped with `wipe()`**, per CLAUDE.md's
  hot-path pattern — `ns:RefreshTBTSections` has eleven call sites and redraws Suggested on every
  open and after every drag, add, move and delete. The render path must read the cache and never
  walk the bags itself. This is the same lesson `ns:IsSuggestedKeyResolvable`'s memo
  (`Providers.lua:1097-1121`) records.
- `BAG_UPDATE` fires in bursts; coalesce to at most one rebuild per frame.

### Tile rendering

- Tiles go in the **Cooldowns** tab's Suggested section — the branch at `CDMTab.lua:773`, where
  `ns:RacialCooldownKeys()` is rendered today. Item tiles are appended **after** the racial
  cooldown tiles so the racial tiles keep their current position.
- Icon from `C_Item.GetItemIconByID(itemID)` — the one call in 999.6's plan never yet exercised.
  Fall back to the existing `134400` question-mark default when it yields nothing.
- Count rendered in the **same display slot cooldown icons already use for charges**:
  `frame.chargeCount.Current` (`Display.lua:478-483`, `NumberFontNormal`, anchored
  `BOTTOMRIGHT, -2, 2`), copied field-for-field from Blizzard's `CooldownViewerEssentialItemTemplate`.
  A Suggested tile is a plain `CreateIconFrame` (`CDMTab.lua:148`) and has no such fontstring
  today, so this phase adds one to that frame using the identical font/anchor, rather than
  inventing a second count style.
- **Pooled frames carry state.** `section.itemPool:ReleaseAll()` recycles tiles across renders, so
  the count fontstring must be written or hidden on **every** tile every pass — the same trap the
  existing code documents for `SetDesaturated` at `CDMTab.lua:788` and `:818`.
- Already-tracked items are **absent** from Suggested (ITEM-02's "not already tracked"), checked
  against `ns.db.trackedBuffs["item:"..itemID]`.

### Both flavours — USER DECISION, front-loaded 2026-09-24

- **Flavour-agnostic, one code path, no build check.** ITEM-10. The v0.4.0 `buildInterfaceVersion`
  check (`Core.lua:~530`) is explicitly a one-off licensed by a recorded user decision and its
  comment states "No second flavour check may be added anywhere in this addon". This phase adds
  none.
- Every read of an API value is guarded `issecretvalue()` **first, then `type()`** — the locked
  ordering, because `type()` reports `"number"` for a secret number and passes on its own.
  Retail's item-cooldown secrecy in combat is unmeasured (both probe runs were Forever-only), so
  the guard is what makes the retail offer safe rather than a measurement.
- Where a value is unreadable, the tile renders **without** that detail rather than erroring — no
  icon falls back to 134400, no count hides the fontstring. Degradation, never a stuck or wrong
  value.
- Retail gets its verification in Phase 52's retail review pass, as the roadmap already schedules.

### Claude's Discretion

- Tile ordering within the item block. Recommend itemID ascending: deterministic, locale-free, and
  stable across bag sorts, where bag-walk order is not. Name-sorting is friendlier but
  `C_Item.GetItemNameByID` can return nothing before the item is cached.
- No cap on the number of item tiles. The filter is expected to keep the list small (nine rows on
  the probe's test character); a cap can be added if a real bag proves otherwise.
- Exact placement of the catalogue builder — `Providers.lua` beside the other catalogues, or its
  own file. Providers.lua is already 1185 lines and holds every other catalogue; a new
  `ItemCatalogue.lua` would need a TOC entry and must load before CDMTab.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`CDMTab.lua:773-790`** — the Cooldowns-tab Suggested branch. Renders `ns:RacialCooldownKeys()`
  as dynamic `cd:<spellID>` tiles today. This is the exact analog for a dynamic item catalogue and
  the closest existing pattern: it already proves a Suggested tile does not have to come from the
  static `ns.SUGGESTED_KEYS` list.
- **`SUGGESTED_RESERVED_SLOTS = 2`** (`CDMTab.lua:21`) — the add and gear squares occupy
  `layoutIndex` 1..2; every catalogue tile counts up from there. Item tiles continue the same
  `suggestedSlot` counter the racial loop uses.
- **`ns:GetDisplayInfoForKey(key)`** (`Providers.lua:1105`) — the single entry point every tile's
  icon/label/duration comes from. It already handles a string key that is *not* a meta key by
  falling through to `UserSpellProvider` when `ns:CooldownKeySpellID` matches. An `item:` key needs
  the same courtesy: recognise it before the fall-through, or it returns nil and the tile gets a
  question mark and no tooltip — the precise bug the comment at `:1114-1120` records for `cd:`.
- **`ns:CooldownKeySpellID`** (`Core.lua:487`) — the parser to copy for `ns:ItemKeyItemID`.
- **`frame.chargeCount.Current`** (`Display.lua:478-483`) — the count display to match.
- **`ns:IsSuggestedKeyResolvable`** (`Providers.lua:1131`) + `catalogResolvable` memo (`:1097`) —
  the established answer to "the render path must not walk a catalogue". Item tiles do not use
  this memo (a bag catalogue is not sticky-per-session the way a race is), but they must honour
  the same rule: the render path reads a cache.
- **`ns.providers`** (`Providers.lua:1084`) and `SpellProviderBaseMixin` (`:14-59`) — the mixin
  shape a future `ItemProvider` follows. Phase 46 does not need one; Phase 47 does.

### Established Patterns

- Namespace `local addonName, ns = ...` across all files; Core.lua loads first so others can take
  upvalues from it.
- `issecretvalue()` **before** `type()`, always — locked project constraint.
- Reusable module-level tables wiped with `wipe()` each cycle, never reallocated in hot paths.
- Capability/data-absence checks instead of flavour checks.
- Derived, never stored: `ns:GetTrackerCategory(entry)` (`Core.lua:99`) reads
  `entry.trackerType == "cooldown"` produces `"spells"`. An `item:` entry must also read as
  `"spells"` so it files under the Cooldowns tab — Phase 47's concern, but the reason this phase
  puts the tiles on that tab.
- `stylua` from the repo root after finishing (repo-root `stylua.toml` pins Windows line endings).
- `.gitattributes` pins `*.lua` to `eol=crlf`.

### Integration Points

- `CDMTab.lua` `ns:RefreshTBTSections` — where the tiles render.
- `Core.lua` — where `ns.ITEM_KEY_PREFIX` and `ns:ItemKeyItemID` belong, beside
  `ns.COOLDOWN_KEY_PREFIX` and `ns:CooldownKeySpellID`.
- `Core.lua:832` already registers `BAG_UPDATE_COOLDOWN`; the event router is where `BAG_UPDATE`
  joins it.
- `Providers.lua:1105` `ns:GetDisplayInfoForKey` — must learn the `item:` key.

</code_context>

<specifics>
## Specific Ideas

- The settled design is ROADMAP backlog entry **999.6**, reshaped 2026-09-24 after two in-game
  probe runs on Forever 1.60.1 via `/tbtp consum` (`tools/TBTProbe/Probe.lua`). It is an agreed
  shape, not a proposal — read it before planning.
- **Spell categories are not used.** Dropped by user decision 2026-09-24. A per-item
  `C_Item.GetItemCooldown(itemID)` read already reflects a shared cooldown, so a category table
  buys nothing, and Forever's categories were measured to differ from retail's anyway.
- Every modern API name was measured to resolve on Forever 1.60.1 — `C_Item.GetItemCount /
  GetItemCooldown / GetItemSpell / GetItemInfoInstant / GetItemNameByID / IsUsableItem /
  GetItemQualityByID`, `C_Container.GetContainerNumSlots / GetContainerItemID`. **No legacy-global
  fallback is needed.**
- `tools/TBTProbe/Probe.lua` is a throwaway harness, not in the TOC or `.pkgmeta`. It is not part
  of the shipped addon and this phase does not extend it.
- **PROJECT.md is stale on one point**: its v0.4.1 section still says generic item tracking is
  "Forever-only". ITEM-10 records the user's 2026-09-24 decision to offer it on both flavours.
  Correct PROJECT.md during this phase.

</specifics>

<deferred>
## Deferred Ideas

- **Bandages** — deferred with findings recorded (999.6). The gate is a debuff (Recently Bandaged,
  spell 11196, 60s) with no item cooldown; auras cannot be read in combat on Forever; and the
  debuff lands on the recipient, not the caster. Excluded from the catalogue by the `0/7` subclass
  filter, which is this phase's only bandage handling.
- **Refining the `0/8` residue** out of the catalogue. Explicitly left for later in the milestone
  per 999.6 section 1.
- Everything in Phase 47: tracker creation from a tile, count decrement, cooldown reads, shared
  cooldown display, zero-count persistence, out-of-combat reconcile.

</deferred>
