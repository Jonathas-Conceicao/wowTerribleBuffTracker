# Phase 49: Forever Racial Catalogue - Pattern Map

**Mapped:** 2026-09-24
**Files analyzed (modified, not created — this addon has no per-feature file layout):**
Providers.lua, Core.lua, BuffEngine.lua, CDMTab.lua, Display.lua
**Analogs found:** 7 of 8 requested mappings have a direct, reusable analog already in the
codebase. One (the indefinite/no-countdown tile) has **no analog anywhere** — flagged explicitly
in its own section below, not glossed over.

This phase creates no new files. Every change lands inside five existing modules. The table below
therefore classifies **functional units** (a function or a cohesive block) rather than file paths,
since that is the real grain the planner will cut plans along.

## File Classification

| Unit to add/change | File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|---|
| Racial key mint/parse (`racial:<spellID>`) | Core.lua (new, beside ~489/~515) | utility (key namespace) | transform | `ns:ItemKeyItemID` / `ns:CooldownKeySpellID` (Core.lua:489, 515) | exact |
| `GetDisplayInfoForKey` racial branch | Providers.lua (~1603-1630) | service (dispatch) | request-response | The existing `item:` branch, same function, lines 1609-1618 | exact |
| Per-race dynamic Suggested tiles (buffs tab) | CDMTab.lua (~966-998, replacing the static `SUGGESTED_KEYS` loop for racials) | component (render) | CRUD (list + drop-out-once-tracked) | The item catalogue loop, CDMTab.lua:918-965 | exact |
| `AddSuggestedTracker` racial branch | CDMTab.lua:139-213 | controller (drag→DB write) | CRUD (create tracker entry) | The function's own existing `item:` branch, same file | exact |
| Racial provider rewrite (dynamic per-key dispatch, replacing `RacialProviderMixin`'s two fixed slots) | Providers.lua:1344-1511 | service (event-driven proc factory) | event-driven | `ItemProviderMixin` (dynamic, itemID-keyed) alongside the code being replaced, which is the two-slot precedent to move away from | role-match (item side) / this-is-what's-replaced (racial side) |
| No-duration guard in the proc-start path | Providers.lua:1387-1409 (`StartRacialProc`) | service | event-driven | None needed as a copied pattern — this is a one-line `if not def.duration then ... end` added to existing code; see section 5 below | n/a (trivial addition) |
| Aura-driven proc start (Plainsrunning) | Providers.lua (new provider path, `UNIT_AURA`) | service | event-driven | `LustProviderMixin:OnTrigger` (Providers.lua:674-721) | exact |
| Aura-cancelled buff (Shadowmeld, Find Treasure) | Providers.lua (proc construction, `aliveBuffs` assignment) | service | event-driven | `TrinketProviderMixin:OnTrigger`'s `aliveBuffs` line (Providers.lua:414) and `ScanActiveTimersForCancellation` (BuffEngine.lua:637) | exact |
| Combat-enter instant clear (Shadowmeld only) | new small frame or Core.lua's `eventFrame` | event-driven | event-driven | Display.lua's own `PLAYER_REGEN_DISABLED` combat-tracking frame (Display.lua:900-908) and MergeMode.lua's `TryRegisterMergeEvent(mergeEventFrame, "PLAYER_REGEN_DISABLED")` (MergeMode.lua:2254) | exact |
| Skyborne conditional-duration correction (out-of-combat aura re-read) | Providers.lua (new `RefreshAtRest`-style or `ReadPlayerAura`-driven correction) | service | request-response (read-then-correct) | `TrinketProviderMixin:RefreshAtRest` (Providers.lua:428) for the "only touch this out of combat" shape, `ns:ReadPlayerAura` (BuffEngine.lua:34) for the read itself | role-match |
| Race-gating at render time | CDMTab.lua Suggested loop + tracked-entry loop (~1000-1046) | component (render filter) | transform | `ns:GetTrackerCategory` (Core.lua:105) as the *shape* of a derived, never-stored predicate — no existing race predicate exists | role-match (shape only; no race-specific analog exists) |
| DB migration: `racial`/`racial2` → per-racial keys | BuffEngine.lua `ns:InitBuffEngine` (~100-226) | migration | batch | The v5→v6 `"cd:<spellID>"` re-key block, BuffEngine.lua:188-217 | exact |
| Indefinite buff tile render (no countdown) | Display.lua icon path (~2330-2363) and bar path (~2078-2093) | component (render) | transform | **None** — every render path unconditionally computes a countdown from `expiresAt`/`duration` | **no analog — see "No Analog Found"** |

---

## Pattern Assignments

### 1. Key encode/decode — the `item:`/`cd:` precedent for a `racial:` namespace

**Analog:** `ns.ITEM_KEY_PREFIX` / `ns:ItemKeyItemID` and `ns.COOLDOWN_KEY_PREFIX` / `ns:CooldownKeySpellID`, both in Core.lua.

**The cooldown pair** (Core.lua:477-495):
```lua
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

**The item pair** (Core.lua:511-521), and note the header comment's explicit instruction that only
the *parser* was added in the phase that introduced it — minting was left to the phase that needed
to create keys:
```lua
ns.ITEM_KEY_PREFIX = "item:"

-- The numeric item ID an item key names, or nil for anything else -- a buff's numeric key, a
-- cooldown key, a meta key, or a malformed string.
function ns:ItemKeyItemID(key)
	if type(key) ~= "string" then
		return nil
	end
	local id = key:match("^item:(%d+)$")
	return id and tonumber(id) or nil
end
```

**What a racial's equivalent looks like.** Following the exact shape: a prefix constant, an
anchored-pattern parser returning `nil` on anything else, no constructor function (keys are minted
inline via `prefix .. spellID`, the same way `AddSuggestedTracker`'s item branch does — see
`CDMTab.lua:935`, `local itemKey = ns.ITEM_KEY_PREFIX .. itemID`):
```lua
ns.RACIAL_KEY_PREFIX = "racial:"

function ns:RacialKeySpellID(key)
	if type(key) ~= "string" then
		return nil
	end
	local id = key:match("^racial:(%d+)$")
	return id and tonumber(id) or nil
end
```
Key format is Claude's discretion per CONTEXT.md D-4, but `racial:<spellID>` is the form every
comment in the codebase already anticipates (CONTEXT.md line 36, FOREVER-RACIALS.md D-4).
Spell ID rather than race+slot is right because it is what both `AddSuggestedTracker` and
`GetDisplayInfoForKey` need to resolve display info, and it is stable across the two Skyborne
races that share Walk on Air's ID.

**One divergence from both existing namespaces worth flagging for the planner:** `cd:` and `item:`
keys need no race information at parse time — the numeric ID alone resolves them. A `racial:`
key's owning race is NOT recoverable from the key itself; it can only be recovered by re-resolving
`UnitRace("player")` and walking `RACIAL_SPELLS` for a matching `spellID`, exactly what
`ResolveRacial` already does per slot. This matters for race-gating at render time (item 8 below).

---

### 2. Display dispatch — `GetDisplayInfoForKey`'s key-shape ordering, and why it is load-bearing

**Analog:** `ns:GetDisplayInfoForKey` (Providers.lua:1603-1630).

```lua
function ns:GetDisplayInfoForKey(key)
	if type(key) == "string" then
		local p = keyToProvider[key]
		if p then
			return p:GetDisplayInfo(key)
		end
		-- "item:<itemID>" keys are dynamic per-itemID, so they never belong in the static
		-- keyToProvider map above (that map is for fixed meta keys only). Recognised HERE,
		-- BEFORE the CooldownKeySpellID reject below, for the same reason the "cd:" comment
		-- immediately below this one exists: an "item:" key is not a "cd:" key and must never
		-- fall through to UserSpellProvider, which would treat the itemID as a spellID and
		-- produce a wrong icon and a spell-shaped tooltip (46-RESEARCH.md Pitfall 4).
		local itemID = ns:ItemKeyItemID(key)
		if itemID then
			return ns:ItemDisplayInfo(itemID)
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

**Why the ordering is load-bearing.** There are exactly three string-key shapes checked in a fixed
order: (1) `keyToProvider[key]` for a small set of fixed meta strings (`"trinket"`, `"pot"`,
`"lust"`, `"racial"`, `"racial2"` today), (2) `ns:ItemKeyItemID(key)` for the dynamic `item:`
namespace, (3) `ns:CooldownKeySpellID(key)` as the last-chance reject before falling through to
`UserSpellProvider`, which treats the key as an ordinary spell ID. **A `racial:<spellID>` key must
be recognised at step (1)/(2)'s position — before step (3)'s reject** — for exactly the reason the
comment states for `item:`: if it reached the `CooldownKeySpellID` check first, that check returns
`nil` (a `racial:` key does not match `^cd:(%d+)$`), so `GetDisplayInfoForKey` would return `nil`
entirely rather than falling through to `UserSpellProvider` — the tile would show a permanent
question mark, identically to the item-key bug this comment already documents.

**The two-slot `keyToProvider` map itself is what D-4 replaces** (Providers.lua:1587-1593):
```lua
local keyToProvider = {
	trinket = TrinketProvider,
	pot = PotProvider,
	lust = LustProvider,
	racial = RacialProvider,
	racial2 = RacialProvider,
}
```
`racial` and `racial2` are static fixed-slot entries here. A per-racial key is dynamic (one key per
spellID, ten-plus of them across all races), so it cannot live in this static map — it needs its
own recognition branch inside `GetDisplayInfoForKey`, parsed the same way `item:` is, positioned
before the `CooldownKeySpellID` reject, exactly as `item:` is positioned. `racial` and `racial2`
themselves should be deleted from this map once D-4 lands (they are what D-4 replaces).

---

### 3. Suggested rendering and the drop-out-once-tracked behaviour

**Analog:** the item tile loop, CDMTab.lua:918-965, and `AddSuggestedTracker`'s existing `item:`
branch, CDMTab.lua:139-213 (both quoted above in the File Classification intro; full text below).

**The Suggested-tile loop** (CDMTab.lua:918-965) is the direct model for a per-race dynamic
catalogue rendered in the Buffs tab, replacing today's static `SUGGESTED_KEYS`-driven loop
(CDMTab.lua:968-998) for the racial case specifically:
```lua
-- Dragging an item tile into a container creates a real "item:" tracker entry
-- (ITEM-04, Phase 47) -- AddSuggestedTracker now resolves ns:ItemKeyItemID(key)
-- as a third valid key shape alongside a cd:<spellID> key and a
-- ns.SUGGESTED_KEYS member. Once tracked, the item: itemID entry below is what
-- makes it drop out of this loop (ITEM-02) -- no separate removal code needed.
for _, itemID in ipairs(ns:ItemCatalogue()) do
	local itemKey = ns.ITEM_KEY_PREFIX .. itemID
	if not ns.db.trackedBuffs[itemKey] then
		suggestedSlot = suggestedSlot + 1
		local item = section.itemPool:Acquire()
		local info = ns:GetDisplayInfoForKey(itemKey)
		item.spellID = itemKey
		item.Icon:SetTexture((info and info.icon) or 134400)
		item.Icon:SetDesaturated(false)
		item.sectionName = "suggested"
		local count = ns:ItemCatalogueCount(itemID)
		if count then
			item.chargeCount.Current:SetText(count)
			item.chargeCount:Show()
		else
			item.chargeCount:Hide()
		end
		item.layoutIndex = suggestedSlot
		item:Show()
	end
end
```

**The drop-out-once-tracked mechanism has NO separate removal code** — it is purely
`if not ns.db.trackedBuffs[itemKey] then`. A per-racial tile needs the identical guard:
`if not ns.db.trackedBuffs[racialKey] then`, where `racialKey` is built the same inline way
(`ns.RACIAL_KEY_PREFIX .. def.spellID`) from whichever racials `ResolveRacial`/its replacement
resolves for the current race. The list to iterate is NOT `ns:ItemCatalogue()` (bag-derived); it is
the current character's resolved racial list — one or two entries, from the per-race table.

**`AddSuggestedTracker`'s third branch** (CDMTab.lua:139-213) is the write side of the same
contract:
```lua
local function AddSuggestedTracker(key, targetSection)
	if ns.db.trackedBuffs[key] then
		ns:SetBuffSection(key, targetSection)
		return
	end

	local cooldownSpellID = ns:CooldownKeySpellID(key)
	local itemID = ns:ItemKeyItemID(key)
	if not cooldownSpellID and not itemID then
		local known = false
		for _, suggestedKey in ipairs(ns.SUGGESTED_KEYS) do
			if suggestedKey == key then
				known = true
				break
			end
		end
		if not known then
			return
		end
	end

	local info = ns:GetDisplayInfoForKey(key)
	if not info then
		return
	end
	...
	ns.db.trackedBuffs[key] = {
		key = key,
		label = info.label,
		duration = info.duration,
		section = targetSection,
		layoutOrder = maxOrder + 1,
		trackerType = cooldownSpellID and "cooldown" or (itemID and "item") or nil,
		spellID = cooldownSpellID or nil,
		itemID = itemID or nil,
		iconOverride = itemID and info.icon or nil,
	}

	if itemID then
		ns:SeedItemTracker(key, itemID, ns.db.trackedBuffs[key])
	end
	...
```
A racial-key branch is a fourth recognition alongside `cooldownSpellID`/`itemID`/`SUGGESTED_KEYS`
membership: `local racialSpellID = ns:RacialKeySpellID(key)`, admitted into the same
`if not cooldownSpellID and not itemID and not racialSpellID then` reject, and its own
`trackerType = ... or (racialSpellID and "racial") or nil` branch (or reuse `nil`/`"buff"` if a
racial buff tile should file as an ordinary buff — see item 10, race-gating, for why
`trackerType` matters downstream).

---

### 4. Category routing — `ns:GetTrackerCategory`

**Analog:** Core.lua:94-110.
```lua
-- Phase 47: trackerType == "item" answers "spells" too -- a tracked item is a cooldown in
-- everything but name, rendering icon-only through ApplyCooldownSlot exactly like a "cd:" entry.
-- Without this widening the failure is silent: CDMTab.lua's category filter would file every
-- "item:" entry under Buffs, where it never renders while the Cooldowns tab is active, with no
-- error at all.
function ns:GetTrackerCategory(entry)
	if entry and (entry.trackerType == "cooldown" or entry.trackerType == "item") then
		return "spells"
	end
	return "buffs"
end
```
**What this means for racials.** A racial BUFF tile (Shadowmeld-the-stealth, Berserking-the-haste)
belongs under "buffs" — it is a buff, not a cooldown-shaped tile — so it needs no widening here as
long as its `trackerType` stays `nil` or something other than `"cooldown"`/`"item"`. The racial
COOLDOWN tile is unaffected: it is already an ordinary `"cd:<spellID>"` entry with
`trackerType = "cooldown"`, created through the existing cooldown path, and this function already
routes it to "spells" correctly. **No change to this function is required** unless the planner
decides a racial buff entry should carry `trackerType = "racial"` for some other reason (e.g.
distinguishing it in `ApplyCachedIcon`/tooltip code) — if so, this function's `if` condition needs
`entry.trackerType == "racial"` added to the *buffs* side implicitly (i.e., it must NOT be added to
the "spells" `or` chain, since a racial buff renders in a buff icon/bar container, not a cooldown
slot).

---

### 5. The racial code being replaced

**`RACIAL_SPELLS`, `RACIAL_SLOT_BY_KEY`, `ns.RACIAL_KEYS`, `RACIAL_SUPPORTED_LINES`,
`RACIAL_UNSUPPORTED_LINES`** (Providers.lua:794-819):
```lua
local RACIAL_SPELLS = {
	[2] = {
		{ spellID = 20572, duration = 15, cooldown = 120, race = "Orc", fallbackLabel = "Blood Fury" },
		{ spellID = 1299026, duration = 8, cooldown = 180, race = "Orc", fallbackLabel = "Orc Racial" },
	},
	[7] = {
		{ spellID = 1259817, duration = 15, cooldown = 180, maxStacks = 3, race = "Gnome", fallbackLabel = "Eureka!" },
	},
	[8] = {
		{ spellID = 20554, duration = 10, cooldown = 180, race = "Troll", fallbackLabel = "Berserking" },
	},
}

local RACIAL_SLOT_BY_KEY = { racial = 1, racial2 = 2 }
ns.RACIAL_KEYS = { "racial", "racial2" }

local RACIAL_SUPPORTED_LINES = { "Tracks your racial ability." }
local RACIAL_UNSUPPORTED_LINES = {
	"Your racial is not supported yet.",
	"Orc, gnome and troll racials are implemented in this version.",
	"Use the + button to track it yourself.",
}
```
This is the table the phase must populate with all ten races' data from FOREVER-RACIALS.md's
paste-ready blocks (note the corrected Gnome cooldown, 120 not 180, and the corrected
`fallbackLabel` for Orc's second racial, "Shatter Curse" not "Orc Racial" — both already fixed in
FOREVER-RACIALS.md). `RACIAL_SLOT_BY_KEY` and `ns.RACIAL_KEYS` are the two-slot addressing scheme
D-4 retires outright — a per-racial key needs no slot number at all. `RACIAL_SUPPORTED_LINES`/
`RACIAL_UNSUPPORTED_LINES` are dead per D-7 and should be deleted, not repurposed.

**`ResolveRacial`, `ns:RacialCooldownKeys`, `ns:RacialCooldownSeed`** (Providers.lua:832-898) —
already quoted in full above under "Read the file" context. The part every replacement needs to
keep: the sticky per-slot memoisation shape (`racialResolved[slot]`, `nil` = unresolved, `false` =
resolved-unsupported, table = resolved-supported) generalises cleanly to "per raceID" memoisation
instead of "per slot" — a race cannot change mid-session, so memoising the WHOLE resolved list for
the player's raceID once is the natural replacement, rather than memoising per numbered slot.

**`RacialProviderMixin`, `StartRacialProc`, `ConsumeRacialStack`** (Providers.lua:1344-1511) — full
text already quoted above under "Read the file" context (offset 1344, limit 170). Key structural
facts for the planner:
- `RacialProviderMixin:OnTrigger` loops `for slot = 1, #ns.RACIAL_KEYS do` and matches
  `spellID == def.spellID` — this loop becomes a loop over however many racials the CURRENT race
  has (0, 1, or 2), each keyed by spellID rather than slot number.
- `StartRacialProc(key, def)` already takes an opaque `key` and a `def` table — **its own
  signature needs no change** for the per-key model; only its CALLERS change (from
  `ns.RACIAL_KEYS[slot]` to `ns.RACIAL_KEY_PREFIX .. def.spellID`).
- `ConsumeRacialStack(spellID)` loops `ns.RACIAL_KEYS` to find a live stack-driven proc — same
  shape change as `OnTrigger`.
- `RacialProviderMixin:GetDisplayInfo(key)` uses `RACIAL_SLOT_BY_KEY[key] or 1` to resolve which
  cached display-info table to return — this becomes a direct `ns:RacialKeySpellID(key)` lookup
  into whichever race's racial list matches that spellID, no slot indirection.

---

### 6. Aura-driven cancellation — `ScanActiveTimersForCancellation` and the `aliveBuffs` contract

**Analog:** BuffEngine.lua:637-687 (full text already read above) and the two-line pattern that
feeds it, `TrinketProviderMixin:OnTrigger`'s `aliveBuffs` assignment (Providers.lua:414):
```lua
proc.aliveBuffs = ns:AcquireAliveBuffs("trinket", spellID) -- D-05: cancel when the buff is absent
```
And the scan itself (BuffEngine.lua:637-672):
```lua
function ns:ScanActiveTimersForCancellation()
	...
	for key, timer in pairs(ns.activeTimers) do
		-- D-09/D-11: Data-driven cancellation. aliveBuffs is the list of buff spellIDs to
		-- check — if ANY is present, the proc is alive; if NONE are present, cancel.
		-- Defensive: skip procs with missing or empty aliveBuffs (opaque — never cancel
		-- what we can't verify). No branching on timer.source (D-10).
		if timer.aliveBuffs and #timer.aliveBuffs > 0 then
			local anyPresent = false
			local allReadable = true
			for _, buffID in ipairs(timer.aliveBuffs) do
				local aura, readable = ns:ReadPlayerAura(buffID)
				if not readable then
					allReadable = false
					break
				elseif aura then
					anyPresent = true
					break
				end
			end
			if allReadable and not anyPresent then
				ns.activeTimers[key] = nil
				...
			end
		end
	end
	...
end
```
This runs unconditionally over `ns.activeTimers`, keyed generically — it has **no knowledge of
which provider owns a proc**. Any proc with a populated `aliveBuffs` array is a candidate,
regardless of source. A per-racial key ("racial:20580" for Shadowmeld) needs no new code here at
all: `StartRacialProc` (or its replacement) simply needs to write
`proc.aliveBuffs = ns:AcquireAliveBuffs(key, 20580)` for Shadowmeld's proc and
`ns:AcquireAliveBuffs(key, 2481)` for Find Treasure's — an `aliveBuffs` assignment, exactly as
CONTEXT.md D-1 states, using the exact same `ns:AcquireAliveBuffs(key, spellID)` helper every other
aura-cancelled proc in the codebase already calls.

**`ns:AcquireAliveBuffs`** itself (BuffEngine.lua:306-309 area, confirmed present):
```lua
-- The one-element aliveBuffs list for a slot, reused. Callers that have a shared list to hand must
-- assign it instead of calling this.
function ns:AcquireAliveBuffs(key, spellID)
```
Pooled per key, one-element array — exactly the shape Shadowmeld/Find Treasure need (a single aura
ID each).

**On `StartRacialProc`'s "deliberately carries no aliveBuffs" comment** — read closely
(Providers.lua:1387-1408):
```lua
local function StartRacialProc(key, def)
	...
	local now = GetTime()
	-- Pooled and WIPED, which matters more here than anywhere else: this proc carries "stacks"
	-- and deliberately carries no "aliveBuffs", so a reused table that was not cleared could hand
	-- the cancellation scan a list this tracker never meant to have.
	local proc = ns:AcquireProc(key)
	...
	-- No cancellation-list field on this proc -- see the mixin header above for why.
	return proc
end
```
and `ns:AcquireProc`'s own header (BuffEngine.lua:290-304):
```lua
-- Hands back the slot's proc table, wiped. The wipe is load-bearing rather than hygiene: the
-- racial proc carries "stacks" and no "aliveBuffs", every other proc carries "aliveBuffs" and no
-- "stacks", and a provider that stopped setting a field would otherwise inherit the previous
-- cast's value for it. Keys never cross providers -- "racial", "lust", "trinket", "pot" and the
-- numeric user-spell keys are disjoint -- so this guards against future edits, not present ones.
function ns:AcquireProc(key)
	local proc = procPool[key]
	if proc then
		wipe(proc)
	...
```
**This is a warning about a pooled table leaking a stale field, not a prohibition on ever setting
`aliveBuffs` on a racial proc.** `ns:AcquireProc` wipes on every acquire, so a proc built this
session that deliberately sets `aliveBuffs` will carry exactly that value and nothing stale — the
comment's whole point is that omitting a field on some code paths but not others is what would leak
a previous cast's value, not that setting `aliveBuffs` is forbidden. FOREVER-RACIALS.md's own
research (Night Elf section) reaches the identical conclusion independently. Setting it
intentionally for Shadowmeld, Find Treasure and Plainsrunning is safe and is exactly what
CONTEXT.md D-1/D-6 call for.

---

### 7. Render/expiry assumptions — the indefinite tile has NO analog

**Bar countdown** (Display.lua:2078-2093), reached whenever `timer` is truthy — i.e. whenever a
real or preview proc exists for that slot, unconditionally:
```lua
if timer then
	local remaining = timer.expiresAt - now
	local fraction = remaining / timer.duration

	if bar._lastDuration ~= timer.duration then
		bar._lastDuration = timer.duration
		bar.statusBar:SetMinMaxValues(0, timer.duration)
	end
	bar.statusBar:SetValue(remaining)
	local r, g, b = GetBarColor(fraction)
	...
	bar.time:SetText(FormatTime(remaining))
	...
```

**Icon countdown** (Display.lua:2344-2346), same unconditional shape:
```lua
if icon._lastStart ~= timer.startedAt then
	icon._lastStart = timer.startedAt
	icon.cooldown:SetCooldown(timer.startedAt, timer.duration)
end
```

**There is no branch anywhere in either render path for "this proc has no meaningful duration,
draw it as simply on."** Both paths assume `timer.duration` is a real, finite number and use it
directly: the bar path divides by it (`remaining / timer.duration`) and feeds it to
`SetMinMaxValues`; the icon path feeds it straight to `CooldownFrame:SetCooldown`, which always
draws a radial sweep of that length. Grepped confirmed — every `SetCooldown(` call site in
Display.lua (lines 1163, 1286, 1356, 1458, 1536, 2346, 2434) takes a real duration and draws a
sweep; none has a "no sweep, just show lit" branch.

**This is a genuine gap, not a missed search.** CONTEXT.md's own "Claude's Discretion" section
names this directly: "How an indefinite tile is represented internally (sentinel expiry, a flag, or
a separate path)" is left open precisely because nothing existing decides it. FOREVER-RACIALS.md's
D-6 write-up says the same: "the existing render path does not do this today: a proc with no
duration and no expiry is a new shape." The planner should treat this as new code to design, not
code to copy — the two candidate shapes visible in the codebase's own vocabulary are (a) a very
large backstop `duration`/`expiresAt` so the existing math never divides by zero or produces a
negative `remaining`, with the countdown text/fill suppressed by a new explicit check, or (b) a
`proc.indefinite = true` flag read by both render paths before the existing duration math runs.
Neither exists today; both are equally "new."

---

### 8. Existing database migration structure

**Analog:** `ns:InitBuffEngine`'s migration chain, BuffEngine.lua:100-217 (full text already read
above). The pattern is a strictly-ordered `if ver < N then ... ns.db.schemaVersion = N end` chain,
called once from `ADDON_LOADED` (Core.lua:944, `ns:InitBuffEngine()`), run before any tracker or
display code touches `ns.db.trackedBuffs`. The most directly analogous block — a straight re-key of
existing entries into a new key namespace — is the v5→v6 step:
```lua
if ver < 6 then
	-- v5 -> v6: cooldown trackers move to their own key namespace, "cd:<spellID>".
	--
	-- Until now ns.db.trackedBuffs was keyed by spell ID alone, so a buff tracker and a
	-- cooldown tracker for the same spell were the SAME RECORD and adding one silently
	-- replaced the other. Re-keying the cooldowns is what lets both exist.
	--
	-- Collected before mutating: adding and removing keys while iterating the table being
	-- iterated is undefined in Lua, and this loop does both.
	local rekey = {}
	for key, entry in pairs(ns.db.trackedBuffs) do
		if type(key) == "number" and entry.trackerType == "cooldown" then
			rekey[#rekey + 1] = key
		end
	end
	for _, key in ipairs(rekey) do
		local entry = ns.db.trackedBuffs[key]
		ns.db.trackedBuffs[key] = nil
		ns.db.trackedBuffs[ns:TrackerKey(key, "cooldown")] = entry
	end
	ns.db.schemaVersion = CURRENT_SCHEMA_VERSION
end
```
**What the racial migration needs to copy exactly:**
1. Collect matching keys into a scratch array BEFORE mutating (`ns.db.trackedBuffs["racial"]` and
   `["racial2"]` — at most two keys, trivial compared to the cooldown re-key's open-ended scan).
2. Re-key each into the new namespace, preserving the record.
3. Bump `CURRENT_SCHEMA_VERSION` to 7 and gate the whole block on `if ver < 7 then`.

**One real divergence from the v5→v6 precedent, flagged for the planner:** the cooldown re-key
knows the new key deterministically from the OLD key alone (`ns:TrackerKey(key, "cooldown")` needs
only the spell ID, which the entry already carries as a plain numeric key). A `"racial"`/`"racial2"`
entry carries NO spell ID of its own — the old two-slot model never stored one, because
`ResolveRacial(slot)` derived it fresh from `UnitRace("player")` every session. **The migration
must call `UnitRace("player")` (or the phase's replacement resolver) to learn which spellID
`"racial"` and `"racial2"` resolve to for the migrating character, before it can build the new key**
— unlike every previous migration in this chain, which transforms data already present in the
record. If `UnitRace` returns a secret or unresolvable race at migration time (unlikely at
`ADDON_LOADED`, since no previous migration in this file has needed to guard for it, but the
codebase's own `ResolveRacial` does guard for exactly this), the safe fallback is to leave the old
key in place rather than lose the entry — losing a placement is the exact failure CONTEXT.md's
"Migration is required" clause exists to prevent.

---

## Shared Patterns

### Secret-safe aura reads
**Source:** `ns:ReadPlayerAura` (BuffEngine.lua:34-50).
**Apply to:** Shadowmeld's and Find Treasure's cancellation checks (already covered by
`ScanActiveTimersForCancellation` calling this internally — no new call site needed), and the
Skyborne conditional-duration read (D-3), which DOES need a fresh direct call:
```lua
function ns:ReadPlayerAura(spellID)
	if C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return nil, false
	end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	if issecretvalue(aura) then
		return nil, false
	end
	if aura == nil then
		return nil, true
	end
	if not ns:CanReadTable(aura) then
		return nil, false
	end
	return aura, true
end
```
Returns `aura, true` / `nil, true` (readable-absent) / `nil, false` (unreadable — never treat as
absent). The Skyborne correction reads `aura.duration` off the returned table once readable —
`LustProviderMixin`'s `GetAuraAppliedAt` (Providers.lua:637-646) is the existing model for pulling
a real numeric field off an aura table with the same `issecretvalue` guards:
```lua
local function GetAuraAppliedAt(aura)
	local duration, expirationTime = aura.duration, aura.expirationTime
	if issecretvalue(duration) or issecretvalue(expirationTime) then
		return nil
	end
	if not duration or duration <= 0 or not expirationTime or expirationTime <= 0 then
		return nil
	end
	return expirationTime - duration
end
```

### Aura-driven proc start (no cast to key off)
**Source:** `LustProviderMixin` in full (Providers.lua:588-761).
**Apply to:** Plainsrunning (D-2), which has no cast at all — it must start from `UNIT_AURA`
exactly as Lust detection does, not from `UNIT_SPELLCAST_SUCCEEDED`.
```lua
function LustProviderMixin:GetEventInterests()
	return { "UNIT_AURA" }
end

function LustProviderMixin:OnTrigger(event, unit, updateInfo)
	if event ~= "UNIT_AURA" then return nil end
	if unit ~= "player" then return nil end
	if not updateInfo then return nil end

	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs["lust"]
	if not entry or entry.section == "hidden" then return nil end

	-- No-restart guard: don't overwrite an already-running proc.
	local existing = ns.activeTimers and ns.activeTimers["lust"]
	if existing and existing.expiresAt and existing.expiresAt > GetTime() then return nil end

	local addedAuras = updateInfo.addedAuras
	if ns:CanReadTable(addedAuras) then
		for _, aura in ipairs(addedAuras) do
			if not issecretvalue(aura.spellId) then
				local lustSpellID = ns.SATED_DEBUFF_TO_LUST[aura.spellId]
				if lustSpellID then
					return BuildLustProc(entry, lustSpellID, GetTime())
				end
			end
		end
		return nil
	end
	if not issecretvalue(addedAuras) and addedAuras == nil then return nil end
	-- Payload secret (in combat): fall back to a by-spell-ID read via ns:ReadPlayerAura.
	return ScanSatedBySpellID(entry, GetTime())
end
```
This dispatches through `ns:OnUnitAura` (BuffEngine.lua:689-729), which already calls
`ns:DispatchEventToProviders("UNIT_AURA", "player", updateInfo)` unconditionally, before any
secret-gate check — so a new racial provider that lists `"UNIT_AURA"` in `GetEventInterests` needs
no new wiring in `Core.lua` or `BuffEngine.lua` at all; it plugs into the existing dispatch exactly
as `LustProviderMixin` does today.

### Combat-enter event registration
**Source:** two independent existing precedents, both defensible to copy from:
1. Display.lua:900-908, a small dedicated frame:
```lua
inCombat = InCombatLockdown()
local combatFrame = CreateFrame("Frame", nil, UIParent)
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
	inCombat = (event == "PLAYER_REGEN_DISABLED")
	ns:UpdateDisplay()
end)
```
2. MergeMode.lua's pcall-guarded registration on a shared frame (MergeMode.lua:2206-2254):
```lua
local function TryRegisterMergeEvent(frame, eventName)
	return pcall(frame.RegisterEvent, frame, eventName)
end
...
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_REGEN_DISABLED")
```
**Apply to:** Shadowmeld's D-1 combat-enter clear. Core.lua's own `eventFrame` (Core.lua:832-1039)
does NOT currently register `PLAYER_REGEN_DISABLED` — this is the one piece of wiring in this phase
that is a genuine addition, not a rename or a widened branch. Both precedents above show it is a
safe, ordinary addition (`RegisterEvent`, no capability guard needed — `PLAYER_REGEN_DISABLED` is a
long-standing event name per MergeMode.lua's own comment, "certain to exist on both clients").
Whether it belongs on Core.lua's shared `eventFrame` (simplest — one more `elseif event ==` branch)
or its own small frame (Display.lua's precedent) is Claude's Discretion; either copies an existing
pattern faithfully.

### CRUD entry-point for a new dynamically-keyed tracker
**Source:** `AddSuggestedTracker` (CDMTab.lua:139-213), in full above under item 3.
**Apply to:** every racial buff/cooldown tile creation path. The function already recognises three
key shapes (`cd:`, meta, `item:`) and rejects anything else; a fourth shape (`racial:`) slots into
the same `if not X and not Y and not Z then reject end` chain with no structural change to the
function's control flow.

---

## No Analog Found

| Unit | Role | Data Flow | Reason |
|---|---|---|---|
| Indefinite/no-countdown tile render (Shadowmeld, Find Treasure) | component (render) | transform | Every render path (Display.lua bar loop ~2078-2093, icon loop ~2344-2346) unconditionally computes a countdown from `timer.duration`/`timer.expiresAt`. No branch for "no meaningful duration" exists anywhere in the codebase. CONTEXT.md and FOREVER-RACIALS.md both independently confirm this is new design surface, not an oversight in this search. |

Everything else requested in the mapping brief (key encode/decode, display dispatch ordering,
Suggested rendering + drop-out, category routing, the racial code being replaced, aura-cancellation
plumbing, and the migration structure) has a direct, quoted, line-numbered analog above.

## Metadata

**Analog search scope:** Core.lua, Providers.lua, BuffEngine.lua, CDMTab.lua, Display.lua,
MergeMode.lua (full-file reads and targeted greps; no file over 2,600 lines required more than
two non-overlapping reads).
**Files scanned:** 6 source files + `.planning/research/FOREVER-RACIALS.md` +
`.planning/phases/49-forever-racial-catalogue/49-CONTEXT.md` + prior-phase pattern docs
(`47-PATTERNS.md`, `47-RESEARCH.md`) consulted for cross-checking the `item:` precedent's own
history.
**Pattern extraction date:** 2026-09-24
