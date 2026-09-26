# Phase 46: Item Catalogue & Suggested Tiles - Pattern Map

**Mapped:** 2026-09-24
**Files analyzed:** 6 (Core.lua x2 concerns, Providers.lua x2 concerns, CDMTab.lua, Display.lua)
**Analogs found:** 5 exact/role-match, 1 partial (bag-walk enumeration has no full analog)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `Core.lua` (key namespace) | utility / config | transform (key parse) | `Core.lua:456-489` (`COOLDOWN_KEY_PREFIX` / `CooldownKeySpellID`) | exact |
| Bag catalogue builder (new code) | service | batch (bag scan → cached table) | `Providers.lua:862-880` (`RacialCooldownKeys`, cached array) + `Providers.lua:538-556` (`PotProviderMixin:RefreshAtRest`, count-read + combat gate) | role-match (cache shape exact; bag-slot enumeration itself has no analog — see "No Analog Found") |
| `CDMTab.lua` (tile render loop) | component (render) | transform (catalogue → pooled frames) | `CDMTab.lua:766-791` (racial tile loop) | exact |
| `CDMTab.lua` (`CreateIconFrame`) | component (factory) | event-driven (drag/tooltip handlers) | `CDMTab.lua:149-230` | exact — extend in place, don't duplicate |
| `Display.lua` (count fontstring source) | component (style source only, not modified) | n/a | `Display.lua:462-483` (`frame.chargeCount`) | exact |
| `Providers.lua` (`GetDisplayInfoForKey`) | service (dispatch) | request-response | `Providers.lua:1101-1122` | exact |
| `Core.lua` (event registration/routing) | event router | event-driven | `Core.lua:829-841` (`BAG_UPDATE_COOLDOWN`/`PLAYER_EQUIPMENT_CHANGED` registration) + `Core.lua:959-964` (dispatch branches) | exact |

---

## Pattern Assignments

### 1. `Core.lua` — `ns.ITEM_KEY_PREFIX` and `ns:ItemKeyItemID`

**Analog:** `ns.COOLDOWN_KEY_PREFIX` / `ns:CooldownKeySpellID`, `Core.lua:456-489`

**Full block to read as the twin (copy header-comment style, not the words):**
```lua
-- A tracker's DB key namespace.
--
-- ns.db.trackedBuffs was keyed by spell ID alone, which made "Frostbolt the buff" and "Frostbolt
-- the cooldown" the SAME RECORD -- adding one silently replaced the other. Reported 2026-09-22,
-- and it is a design bug rather than a regression: tracking a spell's buff and its cooldown at
-- once is an ordinary thing to want, and the schema could not express it.
--
-- Cooldown trackers therefore live under "cd:<spellID>" and buffs keep the bare numeric ID. One
-- table, two namespaces, chosen over two tables because every consumer that walks
-- pairs(ns.db.trackedBuffs) -- six of them -- keeps working untouched, and because the UI already
-- treats a tracker's key as opaque: CDMTab's item.spellID has held the strings "lust", "trinket"
-- and "pot" since Phase 23.
--
-- entry.spellID still holds the real numeric ID on every entry, so nothing that needs the spell
-- has to parse a key.
ns.COOLDOWN_KEY_PREFIX = "cd:"

function ns:TrackerKey(spellID, trackerType)
	if trackerType == "cooldown" then
		return ns.COOLDOWN_KEY_PREFIX .. spellID
	end
	return spellID
end

-- The numeric spell ID a cooldown key names, or nil for anything else -- a buff's numeric key, a
-- meta key, or a malformed string. Callers that want "the spell this key is about" regardless of
-- namespace should read entry.spellID instead.
function ns:CooldownKeySpellID(key)
	if type(key) ~= "string" then
		return nil
	end
	local id = key:match("^cd:(%d+)$")
	return id and tonumber(id) or nil
end
```

**What to copy:** the two-function shape (constant + parser), the `type(key) ~= "string"` guard
before `:match`, the `id and tonumber(id) or nil` idiom, and the header-comment convention of
recording WHY the namespace exists and what bug it fixes (CONTEXT.md already supplies the "why"
for `item:` — the `cd:<useSpellID>` collision risk — so the new comment can cite that instead of
inventing one).

**What NOT to copy:** `ns:TrackerKey`'s `trackerType == "cooldown"` branching — CONTEXT.md is
explicit that entry creation (and therefore any `TrackerKey`-style constructor for `item:`) is
Phase 47's work. Phase 46 only needs the parser (`ns:ItemKeyItemID`) and the constant
(`ns.ITEM_KEY_PREFIX`), used to test membership (`ns.db.trackedBuffs["item:"..itemID]`), not to
mint new keys.

**Naming to match:** `item:(%d+)` mirrors `cd:(%d+)` exactly per CONTEXT.md's decision — place the
new block immediately after `CooldownKeySpellID` (line 489) so the two namespaces read as a pair.

---

### 2. Bag catalogue builder (new code — placement undecided, see below)

**Analog A — cached module-level array, rebuilt on demand:** `ns:RacialCooldownKeys()`,
`Providers.lua:862-880`
```lua
-- The cooldown-tracker keys for whichever racials this character actually has, as ordinary
-- "cd:<spellID>" strings. Empty for an unsupported race, so the Cooldowns tab simply shows no
-- racial tiles rather than a greyed placeholder -- unlike the buff tile, which stays visible and
-- desaturated because RACE-01 requires it to appear on both clients.
--
-- Rebuilt into a module-level array rather than a fresh table: the Suggested section redraws on
-- every CDM open and after every drag.
local racialCooldownKeys = {}

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
**What to copy:** module-level table declared once, `wipe()`'d and refilled on each call, returned
by reference — never reallocated. This is the exact shape CONTEXT.md's "Scan cadence" section asks
for: "The catalogue is cached in a reusable module-level table wiped with `wipe()`". The render
path (CDMTab.lua) calls the builder function and iterates the returned array; it never touches bag
APIs itself.

**What NOT to copy:** the *trigger* for rebuild. `RacialCooldownKeys` rebuilds unconditionally on
every call (cheap — one race, a handful of racials). The item catalogue must NOT rebuild on every
render call; CONTEXT.md's cadence is "scan on CDM open, re-scan on `BAG_UPDATE` only while shown,
coalesced to one rebuild per frame." That means the builder needs a dirty flag the render path
checks, not a bare `wipe()`-and-rebuild every call like the racial one. `ns:IsSuggestedKeyResolvable`
(below) is the closer analog for "compute once, cache, let the render path only read."

**Analog B — combat-gated at-rest scan with honest-nil, count-read:** `PotProviderMixin:RefreshAtRest`,
`Providers.lua:538-556`
```lua
function PotProviderMixin:RefreshAtRest()
	if InCombatLockdown() then
		return
	end
	local potItemID
	for _, itemID in ipairs(POT_FALLBACK_ORDER) do
		if (C_Item.GetItemCount(itemID) or 0) > 0 then
			potItemID = itemID
			break
		end
	end
	local spellID, duration = FindSpellByItemID(POT_SPELLS, potItemID)
	self.atRest.spellID = spellID
	self.atRest.duration = duration
end
```
**What to copy:** `C_Item.GetItemCount(itemID)` as the source of truth for count (CONTEXT.md
confirms: "count is `C_Item.GetItemCount(itemID)`, not a per-slot sum"). Note this provider does
**not** combat-gate its bag reads for a hard reason to reject — see "No Analog Found" below,
`RefreshProvidersAtRest`'s wrapper gate is a `InCombatLockdown()` check, which CONTEXT.md's own
"Scan cadence" section does not mention. Do not silently import a combat gate the phase never
asked for; if one is wanted, it must be an explicit decision, not a copy-paste reflex.

**What NOT to copy:** `PotProviderMixin` scans a **known, fixed item-ID list**
(`POT_FALLBACK_ORDER`) — it never walks bag slots. This phase's catalogue must enumerate
**every held item** via `C_Container.GetContainerNumSlots` / `GetContainerItemID` and classify
each with `C_Item.GetItemInfoInstant`. No existing provider in this codebase does that. Flag this
as new ground — see "No Analog Found."

**Memo pattern (the "render path never walks a catalogue" rule):** `catalogResolvable` memo,
`Providers.lua:1097-1099, 1131-1143`
```lua
-- META-01 (D-10): memoises ns:IsSuggestedKeyResolvable answers per key, for the lifetime of the
-- session. Module-local — never exported.
local catalogResolvable = {}
...
function ns:IsSuggestedKeyResolvable(key)
	local cached = catalogResolvable[key]
	if cached ~= nil then
		return cached
	end
	local p = keyToProvider[key]
	if not p then
		return true
	end
	local result = (p:HasResolvableCatalog() and true) or false
	catalogResolvable[key] = result
	return result
end
```
**What to copy:** the "cached ~= nil → return early" short-circuit shape for the *dirty-flag*
version the item catalogue needs (module-level `bool itemCatalogueDirty`, set true by the
`BAG_UPDATE` handler, read-and-cleared by the rebuild call made on CDM open / next render while
shown).

**What NOT to copy:** this memo is a **sticky, one-shot, session-long** cache (comment at
`Providers.lua:1124-1130`: "a sticky one-shot answer is safe — no invalidation hook is added").
The item catalogue is the opposite: it must invalidate on `BAG_UPDATE`. Do not reuse this memo's
"never invalidated" property; only its early-return shape.

**Placement decision (Claude's Discretion in CONTEXT.md) — findings to hand to the planner:**
- `Providers.lua` is 1185 lines and holds every existing catalogue (`ns.providers`,
  `RacialCooldownKeys`, `catalogResolvable`). Adding the bag catalogue here keeps one file as
  the single home for "things that answer what's available to suggest," and needs **zero** TOC
  change since `Providers.lua` already loads at `TerribleBuffTracker.toc:15`.
- A new `ItemCatalogue.lua` would need: (a) a new line in `TerribleBuffTracker.toc` (currently
  `Core.lua, BuffEngine.lua, Providers.lua, MergeMode.lua, EditModeFrames.lua, Config.lua,
  Display.lua, CDMTab.xml` — `CDMTab.xml` loads `CDMTab.lua` via its own `<Script>` include, so
  the new file must be inserted **before** `CDMTab.xml` in the `.toc`, most naturally right after
  `Providers.lua` since the catalogue is conceptually a provider-adjacent concern), and (b) a
  `.pkgmeta`/packager check — but CLAUDE.md confirms `.pkgmeta` covers "every interface version
  the TOC declares" with no per-file listing, so adding a Lua file needs no `.pkgmeta` edit, only
  the `.toc` line.
- Recommendation for the planner: **`Providers.lua`**, immediately after the `RacialCooldownKeys`
  /`RacialCooldownSeed` block (~line 898) and before `RacialProviderMixin` begins (~line 909), or
  as a new section near the bottom beside `ns.providers` assembly (~line 1084) if the builder is
  meant to read as catalogue-only, not provider-shaped. Either placement costs zero TOC edits.

---

### 3. `CDMTab.lua` — item tile render loop

**Analog:** racial-cooldown tile loop, `CDMTab.lua:766-791` (full branch, read together with the
comment above it)
```lua
-- The catalogue tiles are all buff meta-trackers (lust, trinket, pot, racial), so
-- they belong to the Buffs tab. The + and settings squares are NOT part of this --
-- they occupy the reserved slots and are built once in ns:BuildAllSections, so they
-- stay put under either tab, which is what the user asked for.
if def.key == "suggested" and ns.tbtActiveCategory == "spells" then
	-- The Cooldowns tab gets the racial COOLDOWN tiles, and nothing else: every other
	-- catalogue entry is a buff meta-tracker. Keys are ordinary "cd:<spellID>"
	-- strings, so adding one creates a normal cooldown tracker -- the only thing
	-- special about them is that the spell and its duration are filled in for a
	-- character who would otherwise have to look both up.
	--
	-- No ns:IsSuggestedKeyResolvable call: ns:RacialCooldownKeys only returns keys
	-- for a racial that actually resolved, so an unsupported race yields an empty
	-- list and no tiles rather than a greyed placeholder. That differs from the buff
	-- tile on purpose -- RACE-01 requires THAT one to appear on both clients.
	local suggestedSlot = SUGGESTED_RESERVED_SLOTS
	for i, cooldownKey in ipairs(ns:RacialCooldownKeys()) do
		suggestedSlot = suggestedSlot + 1
		local item = section.itemPool:Acquire()
		local info = ns:GetDisplayInfoForKey(cooldownKey)
		item.spellID = cooldownKey
		item.Icon:SetTexture((info and info.icon) or 134400)
		-- Pooled frames keep a previous tile's desaturation; these are always
		-- supported, so it is cleared rather than left.
		item.Icon:SetDesaturated(false)
		item.sectionName = "suggested"
		item.suggestedIndex = i
		item.layoutIndex = suggestedSlot
		item:Show()
	end
elseif def.key == "suggested" and ns.tbtActiveCategory ~= "buffs" then
	-- Nothing to add beyond the reserved squares.
```

**What to copy:**
- The `suggestedSlot` counter **continues** from where the racial loop leaves it — do not reset it
  to `SUGGESTED_RESERVED_SLOTS`. Item tiles are appended after racials (CONTEXT.md: "Item tiles
  are appended after the racial cooldown tiles"), so the item loop must sit **inside the same
  `if def.key == "suggested" and ns.tbtActiveCategory == "spells" then` branch**, after the
  existing `for i, cooldownKey in ipairs(...) do ... end`, reusing the same `suggestedSlot` local
  rather than declaring a new one.
- `section.itemPool:Acquire()` / `item:Show()` pooling calls, identical shape.
- `item.Icon:SetTexture(...)` with the `134400` fallback — matches CONTEXT.md's icon fallback
  decision exactly (`C_Item.GetItemIconByID(itemID)` falling back to `134400`).
- `item.sectionName = "suggested"` — required for drag/hit-test and the right-click menu
  (`CreateIconFrame`'s `OnMouseUp` reads `self.sectionName`).
- Writing a field every pass on a pooled frame, unconditionally, even to a "no-op" value — see
  `item.Icon:SetDesaturated(false)` below.

**What NOT to copy — and the one place the analog would actively mislead:**
- `-- No ns:IsSuggestedKeyResolvable call: ns:RacialCooldownKeys only returns keys for a racial
  that actually resolved.` **Item tiles must NOT follow this.** `IsSuggestedKeyResolvable` is a
  static per-key membership test ("does this provider's catalog exist on this client at all") —
  it has no meaning for a bag-derived, per-item, per-character-inventory list. The item builder's
  own filter (classID/subClassID/use-spell, per CONTEXT.md) is the correct equivalent gate, and it
  is already baked into what the catalogue table *contains* — so the render loop should iterate
  the catalogue array with **no additional resolvability check**, the same *end state*
  (`racialCooldownKeys` already only holds valid entries) reached by a different mechanism. Do not
  call `ns:IsSuggestedKeyResolvable` on an `item:` key — `keyToProvider` has no entry for it and
  the function's `not p then return true` fallback would make every item vacuously "resolvable,"
  which is harmless but pointless and misleading to a future reader who assumes the call does
  something.
- `item.suggestedIndex = i` — the racial loop uses this as an index into nothing external (just
  loop position); confirm with the planner whether item tiles need an equivalent index field for
  drag-reorder purposes, or whether `itemID` itself is what a Phase 47 drop-handler will want
  stashed on the frame (e.g. `item.itemID = itemID`, a new field, not a repurposing of `spellID`).
  This phase should at minimum decide and record what field carries the itemID for the tile's
  tooltip/click handlers to read.
- `item.Icon:SetDesaturated(false)` — copy the *pattern* (write a known value every pass), but the
  reasoning differs: the racial comment says "these are always supported," so it is a constant.
  Item tiles have no unsupported state either (CONTEXT.md never describes a desaturated item
  tile), so `SetDesaturated(false)` unconditionally is correct here too — but see the
  `SetDesaturated` sibling case below for the trap this phase's **new** fontstring write falls
  into.

**Pooling trap — the count fontstring (CONTEXT.md's own citation):** `CDMTab.lua:727` and the two
`SetDesaturated` comments at `:786` and `:818` both exist because `section.itemPool:ReleaseAll()`
(`CDMTab.lua:726`) recycles frames across renders without clearing per-tile fields. Concretely:
```lua
-- :726
section.itemPool:ReleaseAll()
...
-- :786 (racial branch)
-- Pooled frames keep a previous tile's desaturation; these are always
-- supported, so it is cleared rather than left.
item.Icon:SetDesaturated(false)
...
-- :818 (static SUGGESTED_KEYS branch)
-- RACE-01 requires the tile to appear on both clients, so an unimplemented
-- racial is greyed rather than hidden; written on every tile because item
-- frames are pooled and a previous tile's desaturation must not persist.
item.Icon:SetDesaturated((info and info.unsupported) == true)
```
**What this means for the new count fontstring:** every item tile must call
`item.chargeCount.Current:SetText(count)` **and** `item.chargeCount:Show()` (or `:Hide()` when the
count is unreadable per CONTEXT.md's secret-value degrade rule) on **every** acquire — never
conditionally skip the write assuming the field is already blank. A tile recycled from a previous
render (racial tile, or another item tile with a different count) will still show the old count
text if the new pass does not overwrite it. Also: non-item tiles (racial cooldowns, static
suggested keys, tracked entries) must explicitly `item.chargeCount:Hide()` if `chargeCount` is
added directly onto the shared `CreateIconFrame` template (see next section) — otherwise a tile
recycled from an item slot into a racial slot keeps showing a stale count.

**`CreateIconFrame`, the frame item tiles are built from:** `CDMTab.lua:149-230` (full factory +
handlers)
```lua
local function CreateIconFrame(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(38, 38)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(f)
	f.Icon = icon

	local highlight = f:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(f)
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	highlight:SetBlendMode("ADD")

	f:EnableMouse(true)

	f:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and self.spellID then
			-- Don't drag from collapsed sections (Suggested is never collapsed)
			local section = ns.tbtSections and ns.tbtSections[self.sectionName]
			if section and section.collapsed then
				return
			end
			BeginDrag(self)
		end
	end)

	f:SetScript("OnEnter", function(self)
		if not self.spellID then
			return
		end
		local info = ns:GetDisplayInfoForKey(self.spellID)
		...
```
**What to copy:** this is the single shared factory for **every** Suggested/tracked tile
(`section.itemPool = CreateObjectPool(function(pool) return CreateIconFrame(section.container) end)`,
`CDMTab.lua:672-673`) — item tiles use this **same pool**, not a new one. This is where
`frame.chargeCount` (Display.lua's pattern, see below) gets added, once, at frame-construction
time — not per-render.

**What NOT to copy:** `self.spellID` is the field every existing handler (`OnMouseDown`,
`OnEnter`, drag, right-click menu) reads to identify the tile's tracker key. An `item:<itemID>`
key can be stored in this **same** `item.spellID` field (it is already documented as opaque: "CDMTab's
item.spellID has held the strings 'lust', 'trinket' and 'pot' since Phase 23," `Core.lua:466-467`)
— so set `item.spellID = "item:" .. itemID` (or `ns.ITEM_KEY_PREFIX .. itemID`) rather than adding
a parallel `item.itemID` field that the shared `OnEnter`/`OnMouseDown` handlers would not know to
read. This keeps every existing handler working unmodified, which is the whole reason the codebase
treats tracker keys as opaque strings.

---

### 4. `Display.lua` — count fontstring source (read-only reference, not modified)

**Analog:** `frame.chargeCount` construction, `Display.lua:462-483`
```lua
-- Phase 38 (CD-03): charge count, copied field-for-field from Blizzard's own source in
-- Blizzard_CooldownViewer/CooldownViewer.xml. Both CooldownViewerBuffIconItemTemplate
-- (its `Applications` frame) and CooldownViewerEssentialItemTemplate (its `ChargeCount`
-- frame) use the identical construction: a setAllPoints child *Frame* holding one
-- OVERLAY FontString inheriting NumberFontNormal anchored BOTTOMRIGHT (-2, 2).
-- Three details are load-bearing, not taste:
--   * the child Frame is created AFTER the Cooldown, in the same <Frames> block, so it
--     draws above the swipe -- an OVERLAY font string parented straight to the icon
--     would sit under it;
--   * NumberFontNormal, not the 30x30 CooldownViewerUtilityItemTemplate's
--     NumberFontNormalSmall -- TBT's icon is 40x40, the BuffIcon size, so NumberFontNormal
--     is the matching pair;
--   * hidden on creation, because a freshly pooled icon has no charge answer yet and the
--     sticky chargeCapable cache only populates once a readable value arrives.
frame.chargeCount = CreateFrame("Frame", nil, frame)
frame.chargeCount:SetAllPoints()
frame.chargeCount.Current = frame.chargeCount:CreateFontString(nil, "OVERLAY")
frame.chargeCount.Current:SetFontObject(NumberFontNormal)
frame.chargeCount.Current:SetPoint("BOTTOMRIGHT", -2, 2)
frame.chargeCount:Hide()
```
**What to copy:** field-for-field — `CreateFrame("Frame", nil, frame)` → `SetAllPoints()` →
`CreateFontString(nil, "OVERLAY")` → `SetFontObject(NumberFontNormal)` →
`SetPoint("BOTTOMRIGHT", -2, 2)` → `:Hide()` on creation. CONTEXT.md's decision explicitly names
this construction as the one to copy "field-for-field."

**What NOT to copy:** this is a `Display.lua` frame (the CDM-facing live timer/cooldown icon), a
different frame type from `CDMTab.lua`'s `CreateIconFrame` (the config-window Suggested tile). Do
not import Display.lua's `frame.cooldown` (`CooldownFrameTemplate`, swipe) machinery alongside it —
`CreateIconFrame` in CDMTab.lua has no `Cooldown` widget at all (it is a plain icon + highlight),
so the count fontstring is the **only** piece being borrowed, added directly onto the `f` frame
`CreateIconFrame` builds, not layered above a cooldown swipe that does not exist there.
`Display.lua` itself is not modified by this phase — it is excerpted for style only.

---

### 5. `Providers.lua` — `ns:GetDisplayInfoForKey` learns the `item:` key

**Analog:** `Providers.lua:1101-1122`, with its header comment (the exact bug record CONTEXT.md
points to)
```lua
-- ns:GetDisplayInfoForKey(key)
-- Returns { icon, label, duration, spellID } for any provider key, or nil if unresolvable.
-- String keys ("trinket"/"pot"/"lust") route via keyToProvider; numeric keys route to UserSpellProvider.
-- Callers read the subset of fields they need; the full shape is returned unconditionally.
function ns:GetDisplayInfoForKey(key)
	if type(key) == "string" then
		local p = keyToProvider[key]
		if p then
			return p:GetDisplayInfo(key)
		end
		-- NOT every string key is a meta key any more. A cooldown tracker is keyed
		-- "cd:<spellID>" (ns.COOLDOWN_KEY_PREFIX), which is a string but is an ordinary USER
		-- SPELL -- so it falls through to UserSpellProvider below rather than being rejected
		-- for missing from the meta map. Returning nil here is what left a freshly added
		-- cooldown tracker with a question-mark icon and no tooltip: the caller falls back to
		-- ns:GetSpellIcon(key), and a "cd:" key is not a number either, so that yields 134400.
		if not ns:CooldownKeySpellID(key) then
			return nil
		end
	end
	return UserSpellProvider:GetDisplayInfo(key)
end
```
**What to copy:** the exact bug this comment documents — a string key that matches neither
`keyToProvider` nor `ns:CooldownKeySpellID` returns `nil`, and every caller's fallback path
(`ns:GetSpellIcon(key)`) then fails on a non-numeric key, landing on the `134400` question mark
with no tooltip. An `item:<itemID>` key hits this exact trap today (it is a string, not in
`keyToProvider`, and `ns:CooldownKeySpellID` returns `nil` for it) — so it must be recognised
**before** the final `if not ns:CooldownKeySpellID(key) then return nil end` guard, structured as
a sibling check:
```lua
if not ns:CooldownKeySpellID(key) and not ns:ItemKeyItemID(key) then
	return nil
end
```
**What NOT to copy:** falling through to `UserSpellProvider:GetDisplayInfo(key)` at the bottom —
`UserSpellProvider` resolves a **spell** from a numeric or `cd:`-prefixed key; it has no notion of
an item. An `item:` key needs its own resolution (icon via `C_Item.GetItemIconByID`, from the
catalogue cache or a fresh call — CONTEXT.md's decision) **before** falling through, not by
routing to `UserSpellProvider` at all. This is new branching logic, not a copy of the existing
fall-through target — only the *shape* (recognise the namespace before the generic reject) is
reusable.

---

### 6. Event registration — where `BAG_UPDATE` joins

**Analog A — registration block:** `Core.lua:829-841`
```lua
-- Phase 43.1: item cooldowns do not fire the spell events. Blizzard's own cooldown item listens
-- to BAG_UPDATE_COOLDOWN for exactly this (CooldownViewerItemMixin:OnBagUpdateCooldownEvent,
-- CooldownViewer.lua:230), and without it a trinket used in combat kept its old sweep until some
-- unrelated spell event happened to move the generation.
TryRegisterEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

-- Phase 43.1: what the trinket and pot meta-trackers resolve from. Their at-rest scan used to
-- run from exactly one place -- the CDM tab being built -- so opening the Cooldown Manager in
-- combat found the scan combat-gated and the tile drew a question mark, while opening it out of
-- combat did not. That is the "sometimes" in the report. These are the three moments the answer
-- can actually change, plus combat ending, which is the first moment the gated scan can run.
TryRegisterEvent(eventFrame, "PLAYER_EQUIPMENT_CHANGED")
TryRegisterEvent(eventFrame, "BAG_UPDATE_DELAYED")
```
**What to copy:** `TryRegisterEvent(eventFrame, "BAG_UPDATE")` — same `pcall`-wrapped helper
(`Core.lua:818-820`, `local function TryRegisterEvent(frame, eventName) return
pcall(frame.RegisterEvent, frame, eventName) end`), same reasoning (a client without the event
gets no live rebuild rather than a load error, per the Phase 38 comment at `Core.lua:812-817`).
Use `TryRegisterEvent`, **not** the plain `eventFrame:RegisterEvent(...)` used for
`ADDON_LOADED`/`PLAYER_ENTERING_WORLD`/etc. — CONTEXT.md's "both flavours, no build check" rule
means `BAG_UPDATE`'s presence must be treated as a capability question the same way
`BAG_UPDATE_COOLDOWN` already is, not assumed. Note: `BAG_UPDATE` is in practice a universal
Classic/Retail event and very likely does not need the guard, but matching the existing pattern
for every bag-family event in this file costs nothing and keeps the file internally consistent.

**Analog B — dispatch branch:** `Core.lua:959-964`
```lua
elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_COOLDOWN" then
	ns:MarkCooldownsDirty()
elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
	-- Combat-gated inside the wrapper, so this is safe to call unconditionally; a change made
	-- in combat is picked up by the PLAYER_REGEN_ENABLED call above.
	ns:RefreshProvidersAtRest()
end
```
**What to copy:** the `elseif event == "X" then ns:SomeMarkDirty()` shape — a new branch:
```lua
elseif event == "BAG_UPDATE" then
	ns:MarkItemCatalogueDirty()
```
mirrors `MarkCooldownsDirty`'s role exactly: set a flag, do no work in the handler itself. This
matches CONTEXT.md's cadence decision ("`BAG_UPDATE` fires in bursts; coalesce to at most one
rebuild per frame" — a dirty flag read once by the next render, not a rebuild inside the event
handler, achieves that coalescing for free).

**What NOT to copy:** the `PLAYER_EQUIPMENT_CHANGED`/`BAG_UPDATE_DELAYED` branch calls
`ns:RefreshProvidersAtRest()` **directly from the event handler**, unconditionally, every time —
appropriate there because that function is itself combat-gated and cheap (a handful of
`GetInventoryItemID`/`GetItemCount` calls). CONTEXT.md's cadence rule for the item catalogue is
stricter: **only rebuild while the CDM frame is shown**, and coalesce bursts. Do not call the
catalogue rebuild directly from this branch — dirty-flag it, and let the render path (or a
`C_Timer.After(0, ...)`-style next-frame check, if the planner chooses that route for the
"coalesce to one rebuild per frame" requirement) decide whether to act, gated on CDM visibility.

**Where "CDM frame is shown" is answered elsewhere:** `ns.configOpen` (`CDMTab.lua:32`, set by
`StartPreview`) is the existing flag for "the CDM/config surface is open." The dirty-flag consumer
should check this same flag rather than inventing a second one — worth flagging to the planner as
the integration point, though it was not in the required-reading list.

---

## Shared Patterns

### `issecretvalue()` before `type()`
**Source:** `Providers.lua:444` (`if not issecretvalue(texture) and texture then`),
`Providers.lua:838-841` (`if not issecretvalue(raceName) then ... if issecretvalue(raceID) or
type(raceID) ~= "number" then`)
**Apply to:** every read of `C_Item.GetItemCooldown`, `GetItemCount`, `GetItemSpell`,
`GetItemInfoInstant` results the catalogue builder performs, and any tile-render read of a
count/cooldown value. CONTEXT.md locks this ordering explicitly. The `raceID` example is the
better template than the `texture` one — it shows the "secret OR wrong type" combined guard,
which is what a Secret Value integer read (e.g. a possibly-secret `GetItemCount` in some future
combat context) needs.

### Module-level table wiped with `wipe()`, never reallocated
**Source:** `Providers.lua:869` (`racialCooldownKeys`), `Providers.lua:1099`
(`catalogResolvable`)
**Apply to:** the item catalogue cache table itself — CONTEXT.md names this pattern directly.

### Pooled frame — write every field every pass, never conditionally skip
**Source:** `CDMTab.lua:786, 818` (`SetDesaturated` comments)
**Apply to:** the new `chargeCount` write in the item tile loop, and any other new per-tile field
this phase adds to `CreateIconFrame`'s output.

### Opaque string tracker key stored in the one existing field
**Source:** `Core.lua:466-467` comment (`item.spellID` has held `"lust"`/`"trinket"`/`"pot"`
since Phase 23), `CDMTab.lua:813` (`item.spellID = suggestedKey -- string key "lust" / "trinket" /
"pot"`)
**Apply to:** storing `"item:" .. itemID` in `item.spellID` rather than a new field, so every
existing tile handler (drag, tooltip, right-click) keeps working with zero changes.

### Combat-gate wrapper for at-rest scans
**Source:** `BuffEngine.lua:56-63` (`ns:RefreshProvidersAtRest`), `Providers.lua:428-431`,
`Providers.lua:542-545`
**Apply to:** only if the planner decides the catalogue rebuild needs a combat gate — CONTEXT.md's
cadence section does not mention one, unlike its explicit `issecretvalue` mandate. Flagged, not
assumed.

---

## No Analog Found

| File / Concern | Role | Data Flow | Reason |
|---|---|---|---|
| Bag-slot enumeration (`C_Container.GetContainerNumSlots` / `GetContainerItemID` over every bag) | service | batch | No existing provider walks bag slots. `TrinketProviderMixin` scans two fixed equipment slots; `PotProviderMixin` checks a fixed, small item-ID list via `C_Item.GetItemCount`. Neither iterates *every* item a player holds and classifies it by `classID`/`subClassID`. This is genuinely new code — CONTEXT.md's own probe harness (`tools/TBTProbe/Probe.lua`) is the only prior art, and it is explicitly a throwaway, not shippable code to copy structurally (though its filter logic — classID 0, subClassID ~= 7, has-use-spell — is the settled filter to reimplement). |
| Dirty-flag-driven cache invalidated by a burst event, coalesced to one rebuild per frame | utility | event-driven | `ns:MarkCooldownsDirty()`/cooldown-dirty-counter pattern exists (`Core.lua:440-446` header comment references it) but was not in the required-reading excerpts and its consumer is Display.lua's per-frame cooldown sweep, a continuously-ticking path — a different cadence shape than "rebuild once, next time the CDM is open." Recommend the planner look at `ns:MarkCooldownsDirty` directly (not excerpted here per the read-list) if a closer analog is wanted before inventing the item-catalogue's dirty flag from scratch. |

---

## Metadata

**Analog search scope:** Core.lua, Providers.lua, CDMTab.lua, Display.lua, BuffEngine.lua,
TerribleBuffTracker.toc — all read via targeted `Grep`+`Read` (offset/limit), no full-file loads
except where files were already short enough to read once in range.
**Files scanned:** 6
**Pattern extraction date:** 2026-09-24
