# Phase 47: Item Tracking & Cooldown Sharing - Pattern Map

**Mapped:** 2026-09-24
**Touch points analyzed:** 8 (all modifications to existing flat files — this project has no new-file convention; see CLAUDE.md Architecture)
**Analogs found:** 8 / 8

## File Classification

All work lands in existing files. TerribleBuffTracker is a flat-file Lua addon (`Core.lua`,
`BuffEngine.lua`, `Providers.lua`, `CDMTab.lua`, `Display.lua`, `EditModeFrames.lua`,
`MergeMode.lua`, `Config.lua`) — there is no per-feature file to create. Each row below is a
touch point inside an existing file, classified as if it were its own unit.

| Touch point | Role | Data Flow | Closest analog | Match quality |
|---|---|---|---|---|
| New `ItemProviderMixin` in `Providers.lua` | event-driven provider | event-driven (cast→proc) | `PotProviderMixin` (`Providers.lua:491-585`) for shape; `RacialProviderMixin:OnTrigger` (`:1170-1194`) for house style | role-match, semantics differ (flag below) |
| Use-spell capture in `ns:RefreshItemCatalogue` | batch/scan | batch (bag walk → side tables) | Same function, adjacent lines (`Providers.lua:957-990`) | exact — literally extending the loop that's already there |
| `AddSuggestedTracker` item branch (`CDMTab.lua:139-185`) | controller (drag/drop → DB write) | CRUD (create tracker entry) | Same function's existing `cd:` branch, in-file | exact |
| `ns:GetTrackerCategory` (`Core.lua:99-104`) | utility/classifier | transform (entry → tab label) | Same function, in-file | exact |
| Cooldown render for `item:` entries | component (render) | request-response (per-tick draw) | `ApplyUserCooldown` + `ApplyCooldownSlot` (`Display.lua:954-1002`, `1270-`) | exact — see finding below |
| `ns.cooldownStarts` / `ns:IsCooldownRunning` reuse | store | CRUD (key→timestamp) | Same table/function, in-file (`Core.lua:517-532`) | exact, generic by key already |
| Count display on a tracked item tile | component (render) | request-response | `frame.chargeCount` (`Display.lua:462-483`) + Suggested-tile copy (`CDMTab.lua:200-213`, usage `:888-897`) | role-match, needs a new call site |
| Combat-end / bag event wiring | event router | event-driven | `Core.lua` registration (`:826-874`) + dispatch (`:961-1007`) | exact, mostly already registered |

---

## Pattern Assignments

### 1. New `ItemProviderMixin` (`Providers.lua`, new mixin near the other providers)

**Analogs:** `PotProviderMixin` (`Providers.lua:489-586`) for the event-matching shape,
`SpellProviderBaseMixin` (`:14-59`) for the required method contract, `RacialProviderMixin`
(`:766-1243`, specifically `:OnTrigger` at `:1170-1194`) as the most recently written provider —
current house style.

**Required method shape** (`Providers.lua:14-59`):
```lua
function SpellProviderBaseMixin:GetEventInterests()   return {} end
function SpellProviderBaseMixin:OnTrigger(event, ...) return nil end
function SpellProviderBaseMixin:GetDisplayInfo(key)    return nil end
function SpellProviderBaseMixin:RefreshAtRest() end
function SpellProviderBaseMixin:HasResolvableCatalog() return true end
```

**Event-matching shape to copy** (`Providers.lua:493-511`):
```lua
function PotProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function PotProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return nil end
	if unit ~= "player" then return nil end
	if type(spellID) ~= "number" then return nil end

	local potDef = POT_SPELLS[spellID]
	if not potDef then return nil end
	...
```
This is structurally exactly the use-spell→itemID map lookup: `OnTrigger` should do
`local itemID = itemUseSpellMap[spellID]` in place of `POT_SPELLS[spellID]`.

**Registration to copy** (`Providers.lua:1251` and `:1256-1262`):
```lua
ns.providers = { TrinketProvider, PotProvider, LustProvider, RacialProvider, UserSpellProvider }
...
local keyToProvider = {
	trinket = TrinketProvider,
	pot = PotProvider,
	lust = LustProvider,
	racial = RacialProvider,
	racial2 = RacialProvider,
}
```
`item:<id>` keys are **not** static and must **not** be added to `keyToProvider` — they already
route through `ns:GetDisplayInfoForKey`'s dedicated `ns:ItemKeyItemID(key)` branch
(`:1284-1287`), ahead of the `keyToProvider` lookup. Do not duplicate that routing inside the new
provider's `GetDisplayInfo`.

**Dispatch to copy — and its warning** (`Providers.lua:1345-1362`):
```lua
function ns:DispatchEventToProviders(event, ...)
	local interested = eventToProviders[event]
	if not interested then return 0 end
	local handled = 0
	for _, provider in ipairs(interested) do
		local proc = provider:OnTrigger(event, ...)
		if proc then
			ns.activeTimers[proc.key] = proc
			handled = handled + 1
			if ns.UpdateDisplay then ns:UpdateDisplay() end
		end
	end
	return handled
end
```
The file's own design note (`:1339-1344`) states this loop is **the only writer of
`ns.activeTimers` for cast-triggered procs**.

**CRITICAL — do not copy the wrong half.** `PotProviderMixin:OnTrigger` returns an `ActiveProc`
table (`key, spellID, duration, expiresAt, startedAt, section, ...`) that gets written into
`ns.activeTimers` and rendered as a **buff bar/icon with a sweep timer keyed to a hand-maintained
duration table** (`POT_SPELLS[spellID].duration`, a constant TBT already knows). An item tracker
is the opposite: it has no buff duration to hand-maintain, no `ns.activeTimers` entry, and no
bar. It tracks the **item's own cooldown**, read live from `C_Item.GetItemCooldown(itemID)` (per
locked decision in 47-CONTEXT.md), and renders through the **cooldown-tracker path**
(`ns.cooldownStarts` + `ApplyCooldownSlot`/`ApplyUserCooldown` in `Display.lua`, see §5), exactly
like the existing `cd:` cooldown trackers do — never through `ns.activeTimers`/`DispatchEventToProviders`'s
proc-return contract. So: copy `OnTrigger`'s *event-filter shape* (three early-return guards, then
a table lookup on `spellID`) but do **not** make it `return proc`. On a match it should instead do
the Providers.lua:106-118 "cooldown side" thing — see the existing dual-write at
`Providers.lua:82-118` inside `UserSpellProviderMixin:OnTrigger`, which already shows exactly this
split ("ONE CAST, TWO POSSIBLE TRACKERS... the cooldown is handled first, as a side effect"):
```lua
local cdKey = ns.COOLDOWN_KEY_PREFIX .. spellID
local cdEntry = tracked[cdKey]
...
if cdEntry and cdEntry.section ~= "hidden" then
	ns.cooldownStarts[cdKey] = GetTime()
	ns:MarkCooldownsDirty()
end
```
The item provider's `OnTrigger` on a landed use should stamp `ns.cooldownStarts["item:"..itemID]`
(and every other tracked item's key, per the "re-read every tracked item" decision) rather than
constructing and returning a proc. It can legitimately `return nil` unconditionally, since there
is no buff/timer side to this cast the way `UserSpellProviderMixin` has both a cooldown side and
a buff side.

---

### 2. Use-spell capture (`Providers.lua:915-990`, inside `ns:RefreshItemCatalogue`)

**Analog:** the function's own existing four module-level tables and loop.

**Tables to extend, same idiom** (`Providers.lua:915-919`):
```lua
local itemCatalogueIDs = {}
local itemCatalogueIcons = {}
local itemCatalogueCounts = {}
local itemCatalogueSeen = {}
local itemCatalogueDirty = true
```
Add one sibling, e.g. `local itemUseSpellByID = {}` (itemID-keyed) — wiped alongside the other
three inside `ns:RefreshItemCatalogue` (`:924-927`), never reallocated.

**The exact discard site to stop discarding** (`Providers.lua:967-970`):
```lua
local _, useSpellID = C_Item.GetItemSpell(itemID)
-- issecretvalue() BEFORE the truthiness test: a secret non-nil spellID is truthy
-- under a naive "if useSpellID then", which would admit an item on false evidence.
if not issecretvalue(useSpellID) and useSpellID then
	itemCatalogueIDs[#itemCatalogueIDs + 1] = itemID
	...
```
Capture `itemUseSpellByID[itemID] = useSpellID` inside this same guarded branch — the
`issecretvalue()`-then-truthiness ordering is already proven correct here and must not be
re-derived. This costs no extra API call, exactly as 47-CONTEXT.md states.

**What NOT to copy:** the bag-walk/classification loop above it (`:934-966`) is Phase 46's
catalogue membership logic and is out of scope — do not touch its filter (`classID == 0`,
`subClassID ~= 7`) per the "No refactors" / "Phase 46 code-complete" boundary in CLAUDE.md and
47-CONTEXT.md's carry-over note.

**Collision handling (Claude's Discretion in 47-CONTEXT.md):** if two itemIDs share one
useSpellID, log under the existing debug flag rather than error. The nearest logging precedent is
`ns:LogPlayerCast` (`Core.lua:967`, referenced from the dispatch handler) — read it for the debug
log's existing idiom before adding a new one; 47-CONTEXT.md explicitly forbids generalizing or
touching that log, so any collision log must be a **new, separate** call, not a repurposing of it.

---

### 3. `AddSuggestedTracker` item branch (`CDMTab.lua:139-185`)

**Full existing function, to be extended, not replaced:**
```lua
local function AddSuggestedTracker(key, targetSection)
	if ns.db.trackedBuffs[key] then
		ns:SetBuffSection(key, targetSection)
		return
	end

	-- A cooldown tile carries its spell in the key; a meta tile IS its key. Either way the
	-- display info is what fills the entry, which is why a racial cooldown's seed duration
	-- matters -- see ns:RacialCooldownSeed.
	local cooldownSpellID = ns:CooldownKeySpellID(key)
	if not cooldownSpellID then
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

	local maxOrder = 0
	for _, e in pairs(ns.db.trackedBuffs) do
		if e.layoutOrder and e.layoutOrder > maxOrder then
			maxOrder = e.layoutOrder
		end
	end

	ns.db.trackedBuffs[key] = {
		key = key,
		label = info.label,
		duration = info.duration,
		section = targetSection,
		layoutOrder = maxOrder + 1,
		-- Only a cooldown tile sets this. A meta buff entry leaves it nil, which
		-- ns:GetTrackerCategory already reads as "buffs".
		trackerType = cooldownSpellID and "cooldown" or nil,
		spellID = cooldownSpellID or nil,
	}
end
```

**Exactly which branch currently rejects an `item:` key:** the `if not cooldownSpellID then`
block (`:149-160`) — `ns:CooldownKeySpellID(key)` returns `nil` for an `item:` key
(`Core.lua:483-489`, pattern is `^cd:(%d+)$`), so it falls into the `known` search over
`ns.SUGGESTED_KEYS` (`= { "lust", "trinket", "pot" }`, `BuffEngine.lua:68`), which an `item:` key
is never a member of, so `known` stays `false` and the function returns having created nothing.
This is exactly the documented Phase 46 gate-G7 no-op (`CDMTab.lua:865-868`).

**What the sibling `item:` entry needs, by comparison with the `cd:` entry above:**
- Add a third recognition branch (`ns:ItemKeyItemID(key)`, same function used at
  `Providers.lua:1284`) before/alongside the `cooldownSpellID` check.
- The created table is the `cd:` entry's shape **plus an `itemID` field** and
  `trackerType = "item"` (not `"cooldown"` — locked in 47-CONTEXT.md: *"The created entry is
  `ns.db.trackedBuffs["item:<itemID>"]` with `trackerType = "item"`, carrying `itemID`"*).
  `spellID` must stay `nil` — an item has no spellID, and setting one would misroute
  `ApplyCooldownSlot`'s spellID branch (see §5).
- `duration = info.duration` inherits `ns:ItemDisplayInfo`'s `info.duration`, which Phase 46 always
  returns as **`0`** (`Providers.lua:1062`, `-- spellID is always nil and duration is always 0`).
  Flag for the planner: with `entry.duration == 0` at creation, `ApplyUserCooldown` will *not* take
  ownership of the icon (`Display.lua:955-958`, `if duration <= 0 then return false end`) until
  the first landed use or cooldown read populates a real duration on the entry. This is very
  likely fine (a freshly tracked, never-used item legitimately has no sweep to show) but the
  planner should decide explicitly whether the entry needs a seed read
  (`C_Item.GetItemCooldown(itemID)`) at creation time rather than leaving `duration` at 0 until
  the next use.

---

### 4. `ns:GetTrackerCategory` (`Core.lua:99-104`)

**Full function:**
```lua
function ns:GetTrackerCategory(entry)
	if entry and entry.trackerType == "cooldown" then
		return "spells"
	end
	return "buffs"
end
```

**Consumer** (`CDMTab.lua:944`):
```lua
if entry.section == def.key and ns:GetTrackerCategory(entry) == ns.tbtActiveCategory then
	table.insert(sorted, { spellID = spellID, order = entry.layoutOrder or 0 })
end
```
**What breaks if the category is wrong:** this is the filter that decides whether a tracked
entry is drawn at all under the currently active CDM tab (`ns.tbtActiveCategory`, `"buffs"` or
`"spells"`). If an `item:` entry's `GetTrackerCategory` keeps returning `"buffs"` (the `else`
default), the entry is filed under the Buffs tab and **silently never appears** while the
Cooldowns tab is open — not an error, just an invisible tracker, exactly the class of bug the
function's own header comment describes deriving-not-storing as preventing. Fix: widen the test to
`entry.trackerType == "cooldown" or entry.trackerType == "item"`.

---

### 5. Cooldown rendering from plain start/duration numbers — the load-bearing integration

**Finding stated plainly first: the existing path is NOT duration-object-only.** Plain
`(start, duration)` numbers already drive `CooldownFrameTemplate` today, in multiple places,
via the ordinary Cooldown widget method `icon.cooldown:SetCooldown(start, duration)`
(`Display.lua:986`, `:1056`, `:1158`, `:1236`, `:1979`, `:2062`). `SetCooldownFromDurationObject`
(`ApplyCooldownHandle`, `:862-889`) is a **separate, parallel** path used only when driving off
`C_Spell.GetSpellCooldownDuration`'s secret-safe duration-object handle for a real game spell
cooldown — it is not a prerequisite for the widget, just one of several ways to feed it. **No
second path needs to be invented; the item tracker should use the plain-numbers path that
already exists for exactly this purpose.**

**The direct analog, in full** (`Display.lua:954-1002`, `ApplyUserCooldown`):
```lua
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
This is generic on `entry.key` and `entry.duration` already — it has **no knowledge of spellID**
and makes no game API call. An `item:<id>` entry with a numeric `duration` and a
`ns.cooldownStarts["item:"..id]` timestamp drives this function **completely unmodified**.

**The gate that currently excludes it** (`Display.lua:1999`, inside `ApplyCooldownSlot`'s caller):
```lua
elseif entry.trackerType == "cooldown" then
	-- Phase 38 (CD-02/CD-03/CD-04): placed BELOW the timer branch and ABOVE the
	-- placeholder branch...
	ApplyCooldownSlot(icon, entry, settings, now)
	icon.mergedTime:Hide()
	icon._mergedExpiry = nil
	icon:Show()
```
This is a **required, concrete edit**: an `item:` entry (`trackerType == "item"` per §3) will
never reach `ApplyCooldownSlot` at all unless this condition is widened, e.g.
`entry.trackerType == "cooldown" or entry.trackerType == "item"`. Without it, an item tracker
falls through to whatever the final placeholder branch does (untested by this mapping pass —
worth the planner confirming it degrades gracefully rather than erroring).

**Icon texture, a second required piece:** inside `ApplyCooldownSlot` (`Display.lua:1273-1278`),
`spellID` is forced to `nil` for any entry without a numeric `spellID` (which an `item:` entry
never has), and the icon texture comes from `entry.iconOverride`:
```lua
local spellID = entry.spellID
if type(spellID) ~= "number" then
	spellID = nil
end

ApplyCachedIcon(icon, spellID, entry.iconOverride)
```
`ApplyCachedIcon` (`Display.lua:741-746`) resolves texture as
`iconOverride or (spellID and ns:GetSpellIcon(spellID)) or 134400` — its own header comment
(`:736-740`) already names this exact case: *"an item-backed CDM entry -- a trinket or a
potion -- has no spell [...] iconOverride carries its icon instead."* The `item:` entry needs an
`iconOverride` field set at creation time (§3) from `ns:ItemCatalogueIcon(itemID)`, or the tile
renders the `134400` question-mark placeholder forever.

**Fallthrough after `ApplyUserCooldown`, for context (do not need to touch):** when `userOwned`
is `false` (duration not yet populated), `ApplyCooldownSlot` tries `entry.equipSlot`, then
`spellID`, then `RelayMergedCooldown`, then a category-spell fallback (`:1345-1390`) — none of
these branches apply to an `item:` entry (no `equipSlot`, no `spellID`, no `spellCategoryID`), so
until `entry.duration` is first populated by a real read, the item tile shows icon-only with no
sweep. That degradation looks intentional and safe, not a bug, but flag it for the planner as the
direct consequence of §3's `duration = 0` seed.

---

### 6. `ns.cooldownStarts` / `ns:IsCooldownRunning` (`Core.lua:517-532`)

**Full excerpt:**
```lua
ns.cooldownStarts = {}

function ns:IsCooldownRunning(key, entry, now)
	local startedAt = ns.cooldownStarts[key]
	if startedAt == nil then
		return false
	end
	local duration = entry and entry.duration
	if type(duration) ~= "number" or duration <= 0 then
		return false
	end
	return (now - startedAt) < duration
end
```
**Can an `item:` key reuse this as-is?** Yes, with no changes. Both the table and the function are
keyed generically by `key` (any string) and read `entry.duration` from whatever DB entry is
passed in — there is nothing `cd:`-specific about either. This matches 47-CONTEXT.md's own
"Claude's Discretion" note: *"`ns.cooldownStarts` is keyed by tracker key already, and an `item:`
key is just another key — reuse it if it fits rather than adding a parallel table."* Confirmed:
it fits. The only write site today is `Providers.lua:116`
(`ns.cooldownStarts[cdKey] = GetTime()`, inside `UserSpellProviderMixin:OnTrigger`'s cooldown
side) — the new item provider's `OnTrigger` (§1) should write this same table with `"item:"..itemID`
keys, for every tracked item, on a landed use.

**One divergence to flag:** the *duration* half of `IsCooldownRunning`'s contract
(`entry.duration`) is, for `cd:` entries, a number the **user typed** by hand
(`Display.lua:941-949` calls this out explicitly as a locked, deliberate reversal — "Drive a
custom cooldown tracker from the duration the USER typed"). For an `item:` entry, `duration` must
instead be the **API-read** value from `C_Item.GetItemCooldown(itemID)`, refreshed on every landed
use and (per discretion) possibly on `BAG_UPDATE_COOLDOWN`. Mechanically `IsCooldownRunning` and
`ApplyUserCooldown` don't care where the number came from — but whatever writes `entry.duration`
for an item tracker needs its own logic; it cannot reuse the "typed by the user" input path the
`cd:` namespace uses, because there is no typed-duration UI for items.

---

### 7. Count display on a tracked-item tile

**Widget construction to copy, already used twice in the codebase for the identical purpose**
(`Display.lua:462-483`, real tracked-icon frames; `CDMTab.lua:200-213`, Suggested tiles):
```lua
frame.chargeCount = CreateFrame("Frame", nil, frame)
frame.chargeCount:SetAllPoints()
frame.chargeCount.Current = frame.chargeCount:CreateFontString(nil, "OVERLAY")
frame.chargeCount.Current:SetFontObject(NumberFontNormal)
frame.chargeCount.Current:SetPoint("BOTTOMRIGHT", -2, 2)
frame.chargeCount:Hide()
```
This widget already exists on every real tracked-icon frame (`Display.lua`'s icon pool) — no new
widget needs constructing for the *tracked* tile, only a new call site that sets it.

**The Suggested-tile usage to mirror** (`CDMTab.lua:888-897`):
```lua
local count = ns:ItemCatalogueCount(itemID)
if count then
	item.chargeCount.Current:SetText(count)
	item.chargeCount:Show()
else
	-- The scan-time issecretvalue()/type() guard rejected this count at
	-- catalogue build time; degrade the tile rather than show a stale or
	-- wrong value (D-03/S10).
	item.chargeCount:Hide()
end
```
**Where the tracked-item tile needs the same treatment:** nowhere in the current
`trackerType == "cooldown"` render branch (`Display.lua:1999-2011`) or inside `ApplyCooldownSlot`
does anything set `icon.chargeCount` for a cooldown-category entry — the nearest existing call,
`ApplyChargeCount(icon, spellID)` (`:1312`, inside `ApplyCooldownSlot`), is driven by
`C_Spell.GetSpellCharges(spellID)` and is unreachable for an item (`spellID` is `nil`). The
planner needs a **new, explicit** call for `item:` entries, reading the phase's own decremented
count store (not `ns:ItemCatalogueCount`, which is the Suggested-list's live bag count — Phase 47
decided to decrement-and-reconcile instead, see 47-CONTEXT.md "Count maintenance"). The closest
in-render-path precedent for "a plain integer this addon itself maintains, shown via
`chargeCount`" is `RacialProviderMixin`'s stack count (`Display.lua:1988-1996`):
```lua
if icon._stacks ~= timer.stacks then
	icon._stacks = timer.stacks
	if timer.stacks ~= nil then
		icon.chargeCount.Current:SetText(timer.stacks)
		icon.chargeCount:Show()
	else
		icon.chargeCount:Hide()
	end
end
```
Note this lives in the `timer` branch (`ns.activeTimers`-driven), which item trackers do not use
(§1) — so this is a **shape** to copy (stamp-compare then `SetText`/`Show`/`Hide`), not a branch
the planner can literally extend. It should land as new code inside the widened
`trackerType == "item"` handling from §5, alongside `ApplyCooldownSlot`.

---

### 8. Combat-end / bag events

**Registration, already largely done** (`Core.lua:826-874`):
```lua
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- already registered, :831
...
TryRegisterEvent(eventFrame, "BAG_UPDATE_COOLDOWN") -- already registered, :859
TryRegisterEvent(eventFrame, "BAG_UPDATE")          -- already registered, :866
TryRegisterEvent(eventFrame, "BAG_UPDATE_DELAYED")  -- already registered, :874
```
**All four events this phase needs are already registered.** No new `RegisterEvent`/
`TryRegisterEvent` call is needed — this touch point is dispatch-branch work only.

**Existing dispatch branches to extend** (`Core.lua:974-1007`):
```lua
elseif event == "PLAYER_REGEN_ENABLED" then
	ns:ClearSecretGateLog()
	ns:RefreshProvidersAtRest()
	ns:MarkCooldownsDirty()
...
elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_COOLDOWN" then
	ns:MarkCooldownsDirty()
elseif event == "BAG_UPDATE" then
	-- Phase 46: set the dirty flag only ... rebuild only while the CDM is shown, coalesced ...
	ns:MarkItemCatalogueDirty()
elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
	ns:RefreshProvidersAtRest()
end
```
**What exists vs. what needs adding, per branch:**
- `PLAYER_REGEN_ENABLED` (`:974-986`) — exists, and already calls `ns:RefreshProvidersAtRest()`
  and `ns:MarkCooldownsDirty()`. Per 47-CONTEXT.md's "reconcile against
  `C_Item.GetItemCount(itemID)` when combat ends," this branch needs a **new call** to whatever
  reconciliation function the planner adds — it does not exist yet under any name in this file.
- `BAG_UPDATE_COOLDOWN` (`:992`) — exists, currently only bumps the generation counter
  (`ns:MarkCooldownsDirty()`). This is the event Blizzard's own cooldown item listens to
  (comment at `Core.lua:855-858`, also cited in 47-CONTEXT.md). It does **not** currently trigger
  any per-item `C_Item.GetItemCooldown` re-read — that would be new work if the planner wants
  drift correction beyond the landed-use re-read.
- `BAG_UPDATE` (`:994-1002`) — exists, currently only sets `ns:MarkItemCatalogueDirty()` (Phase
  46's catalogue dirty flag, unrelated to item cooldown/count tracking). 47-CONTEXT.md's
  discretion note asks whether reconcile should also listen here out of combat, or only to
  `PLAYER_REGEN_ENABLED` + `BAG_UPDATE_DELAYED` — both paths already reach this handler, so no new
  `RegisterEvent` is needed either way, only a new call inside whichever branch(es) are chosen.
- `BAG_UPDATE_DELAYED` (`:1003-1006`) — exists, already calls `ns:RefreshProvidersAtRest()`
  (combat-gated internally, per `BuffEngine.lua:56-59`). Per discretion, reconciliation could piggy-back
  here since it already fires out of combat on bag settling.

**Combat-gate idiom to copy for any new reconcile function**
(`BuffEngine.lua:56-63`, `ns:RefreshProvidersAtRest`):
```lua
function ns:RefreshProvidersAtRest()
	if InCombatLockdown() then
		return
	end
	for _, provider in ipairs(ns.providers) do
		provider:RefreshAtRest()
	end
end
```
Note 47-CONTEXT.md does **not** ask for the per-item cooldown *read* itself to be combat-gated —
only the count reconciliation is scoped to "when combat ends" / "out of combat." Do not
over-apply this `InCombatLockdown()` guard to the cooldown re-read path; it is shown here purely
as the existing idiom for the reconcile function, which the decision *does* combat-gate.

---

## Shared Patterns

### Secret-value guard ordering
**Source:** `Providers.lua:970` (comment) and `:942-943`, `:947`, `:960-966`, `:976`, `:983`
**Apply to:** every new API read this phase adds — `C_Item.GetItemCooldown`,
`C_Item.GetItemCount` (reconcile), and the use-spell capture.
```lua
if not issecretvalue(useSpellID) and useSpellID then
```
`issecretvalue()` always before the truthiness/type test — locked, repeated project-wide rule,
restated in 47-CONTEXT.md's own "Flavour-agnostic with secret guards" decision.

### Module-level table wiped with `wipe()`, never reallocated
**Source:** `Providers.lua:915-919`, `CLAUDE.md` Patterns section
**Apply to:** any new itemID-keyed side table (use-spell map, decrement counts if kept in a
module table rather than on the DB entry).

### One writer per shared state
**Source:** `Providers.lua:1340-1344` (`ns.activeTimers`), `Providers.lua:82-118`
(`ns.cooldownStarts`)
**Apply to:** the new item provider must not create a second writer of `ns.cooldownStarts` —
route every stamp through the same table, same key convention (`"item:"..itemID`, matching
`ns.ITEM_KEY_PREFIX`).

### Category-derivation over stored category
**Source:** `Core.lua:94-104` (`ns:GetTrackerCategory` header comment)
**Apply to:** any future per-entry-type branching — derive from `trackerType`, never store a
redundant `category` field on the entry.

---

## No Analog Found

None. Every touch point in this phase has at least a role-match analog already in the codebase,
which is expected — 47-CONTEXT.md is explicit that this phase is built entirely on Phase 46
interfaces plus the existing `cd:` cooldown-tracker machinery.

---

## Metadata

**Files read (read-only):** `Providers.lua` (multiple ranges: 1-60, 485-1362),
`CDMTab.lua` (85-220, 815-955), `Core.lua` (90-110, 470-533, 815-1010), `Display.lua`
(437-500, 736-746, 862-1300, 1900-2020), `BuffEngine.lua` (56-63, 65-80)
**Files NOT modified:** all — this agent is read-only; PATTERNS.md is the only file written.
**Pattern extraction date:** 2026-09-24
