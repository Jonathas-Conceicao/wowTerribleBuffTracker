local _, ns = ...

-- Registry of all SpellProviders in priority order. Populated at end of this file.
-- Phase 19 complete: { TrinketProvider, PotProvider, LustProvider, UserSpellProvider } — PROV-01 satisfied.
ns.providers = {}

-- Dispatch map: event name -> list of providers interested in that event.
-- Built once below after providers are registered. DO NOT rebuild per-event (PITFALL-7 performance trap).
local eventToProviders = {}

-- SpellProviderBaseMixin — defines the contract all providers must implement.
-- Concrete providers are built via CreateFromMixins(SpellProviderBaseMixin, ConcreteMixin).
-- Provider instances are constructed with CreateAndInitFromMixin(proto, ...) when Init is present.
local SpellProviderBaseMixin = {}

-- Returns a list of WoW event names this provider needs routed to it.
-- Override in concrete provider.
function SpellProviderBaseMixin:GetEventInterests()
	return {}
end

-- Called by BuffEngine dispatch when a registered event fires.
-- Returns an ActiveProc table if the event triggers a proc, or nil.
-- ActiveProc shape (Phase 22 normalized): { key, spellID (numeric), duration, expiresAt, startedAt, section, layoutOrder, label, aliveBuffs }
-- Override in concrete provider.
function SpellProviderBaseMixin:OnTrigger(event, ...)
	return nil
end

-- Returns display info for a provider key — unified contract for preview, at-rest, and runtime lookup.
-- Shape: { icon=number, label=string, duration=number, spellID=number }
-- spellID is ALWAYS numeric; for string-keyed providers, the provider resolves to its concrete
-- at-rest spellID (equipped trinket buff / bag pot buff / class-aware lust spell).
-- String-keyed providers (trinket/pot) return a neutral placeholder — spellID nil, duration 0,
-- icon 134400 — when nothing resolves at rest (D-03/D-04, Phase 27). Callers must therefore test
-- duration > 0 rather than assume a real duration.
-- Override in concrete provider. Default returns nil.
function SpellProviderBaseMixin:GetDisplayInfo(key)
	return nil
end

-- Refreshes the provider's at-rest cache (inventory scan, etc.). No-op by default.
-- D-17: Caller (ns:RefreshProvidersAtRest wrapper) combat-gates before calling. Defensive
-- guard at provider level is D-18 — inside concrete providers that touch restricted APIs.
-- D-19 / PITFALL-5: GetDisplayInfo MUST NOT call inventory APIs; only RefreshAtRest does.
function SpellProviderBaseMixin:RefreshAtRest() end

-- META-01 (Phase 27.1, D-09/D-12): answers whether this provider's catalog has anything to show
-- on the current client. Providers that carry no spell catalog are always displayable, so
-- UserSpellProvider and any future provider inherit "always shown" and only providers that
-- deliberately override can be hidden. This mechanism hides tiles whose catalog the *client*
-- cannot resolve; it names no client and no flavor, so a client that later ships those spells
-- makes the tile reappear automatically with no code change.
function SpellProviderBaseMixin:HasResolvableCatalog()
	return true
end

-- Expose on namespace so other providers (future) and tests can reference the base.
ns.SpellProviderBaseMixin = SpellProviderBaseMixin

-- UserSpellProviderMixin — handles user-created buffs keyed by numeric spellID in ns.db.trackedBuffs.
-- String keys ("trinket", "pot", "lust") are ignored -- the meta providers further down this file
-- own those, and have since Phases 18-19.
local UserSpellProviderMixin = {}

function UserSpellProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit (string), castGUID (string), spellID (number)
function UserSpellProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	-- ONE CAST, TWO POSSIBLE TRACKERS. Since cooldown trackers moved to their own key namespace
	-- (ns.COOLDOWN_KEY_PREFIX), the same spell can be tracked as a buff AND as a cooldown, and a
	-- single cast has to start both. The cooldown is handled first, as a side effect, and the
	-- buff decides the return value -- which keeps ns:DispatchEventToProviders' one-proc-per-
	-- provider contract intact, because a cooldown never produced a proc in the first place.
	--
	-- Resolving a tracker means: the direct key, else the rank index for this namespace.
	-- RANK-01/RANK-02: the flat castSpellID -> ownerKey map never contains an ID that is itself
	-- a tracker slot, so the direct hit always wins and the fallback can never shadow a real
	-- tracker. Cost on a cast that matches nothing: two failed table lookups per namespace. No
	-- API call, no protected call, no allocation -- all of that happened at rebuild time.
	local tracked = ns.db and ns.db.trackedBuffs
	if not tracked then
		return nil
	end

	-- --- the cooldown side ---------------------------------------------------------------
	--
	-- A cooldown is a slot, not a timer: it never enters ns.activeTimers and therefore never
	-- reaches ns:ScanActiveTimersForCancellation, which has nothing to cancel for a cooldown.
	-- The cast is still not a timer, but it IS the start of one -- a custom cooldown tracker runs
	-- on the duration the user typed rather than the game's own cooldown, and this is the only
	-- place that start time exists. MarkCooldownsDirty also picks up a fresh charge count without
	-- waiting for SPELL_UPDATE_CHARGES.
	local cdKey = ns.COOLDOWN_KEY_PREFIX .. spellID
	local cdEntry = tracked[cdKey]
	if not cdEntry then
		local mapped = ns.rankIndexCooldown and ns.rankIndexCooldown[spellID]
		if mapped ~= nil then
			cdKey = mapped
			cdEntry = tracked[mapped]
		end
	end
	if cdEntry and cdEntry.section ~= "hidden" then
		ns.cooldownStarts[cdKey] = GetTime()
		ns:MarkCooldownsDirty()
	end

	-- --- the buff side -------------------------------------------------------------------
	local entry = tracked[spellID]
	local ownerKey = spellID
	if not entry then
		local idx = ns.rankIndex
		local mapped = idx and idx[spellID]
		if mapped ~= nil then
			ownerKey = mapped
			entry = tracked[mapped]
		end
	end
	if not entry then
		return nil
	end
	-- Carries over the section="hidden" guard from the branching cast handler BuffEngine used to
	-- have (its "branch 3"), which Phase 17 removed once this dispatcher took the work over.
	if entry.section == "hidden" then
		return nil
	end
	-- Defence in depth: a cooldown entry cannot reach here now that the namespaces are split --
	-- tracked[spellID] is a numeric key and the rank index is per-namespace -- but a stale
	-- database from before the split could still carry one, and it must not become a timer.
	if entry.trackerType == "cooldown" then
		return nil
	end

	local now = GetTime()
	-- RANK-01: aliveBuffs becomes the shared family when one exists. This is a deliberate
	-- shared REFERENCE to Plan 01's ns.rankFamilies[ownerKey] array, not a copy -- safe
	-- because ns:ScanActiveTimersForCancellation only ever reads it with ipairs, and Plan 01
	-- allocates a fresh array per rebuild rather than reusing one, so a live proc's reference
	-- never goes stale. Must not be mutated or wiped here or anywhere downstream.
	local fams = ns.rankFamilies
	-- The shared family when one exists, otherwise the slot's pooled one-element list. Both are
	-- read-only downstream; only the pooled one may be wiped, and only by ns:AcquireAliveBuffs.
	local aliveBuffs = (fams and fams[ownerKey]) or ns:AcquireAliveBuffs(ownerKey, ownerKey)

	-- Pooled, not constructed: a cast allocates nothing. See the proc pool in BuffEngine.lua.
	local proc = ns:AcquireProc(ownerKey)
	-- RANK-02: key stays the stable slot identity, spellID stays derived from it (locked
	-- v0.2.4 decision, not inverted) -- both come from ownerKey, not the cast ID, so whichever
	-- rank the player casts, TBT files the timer under the same ID the CDM holds for that
	-- tracker.
	proc.key = ownerKey -- numeric; 1:1 with DB slot
	proc.spellID = ownerKey -- numeric (D-03): THE spell
	proc.duration = entry.duration
	proc.expiresAt = now + entry.duration
	proc.startedAt = now
	proc.section = entry.section or "bars"
	proc.layoutOrder = entry.layoutOrder
	proc.label = entry.label or ("Spell " .. tostring(ownerKey))
	proc.aliveBuffs = aliveBuffs
	return proc
end

-- key: numeric spellID from ns.db.trackedBuffs.
-- Returns { icon, label, duration, spellID } or nil if entry missing (fallback spellID=key, duration=0
-- when entry missing is NOT required — user-spell keys without entries are genuinely unknown).
-- D-04/D-05/D-06/D-07: spellID numeric, duration real, icon/label derived.
function UserSpellProviderMixin:GetDisplayInfo(key)
	-- A cooldown tracker's key is the string "cd:<spellID>" (ns.COOLDOWN_KEY_PREFIX). It belongs
	-- to this provider exactly as the bare numeric buff key does -- same spell, same lookup, a
	-- different namespace -- so the type test resolves the spell rather than rejecting the key.
	local spellID = key
	if type(key) ~= "number" then
		spellID = ns:CooldownKeySpellID(key)
		if not spellID then
			return nil
		end
	end
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
	-- Pooled per key: this is on the render path for every placeholder slot. See
	-- ns:AcquireDisplayInfo in BuffEngine.lua for why sharing is safe here.
	local info = ns:AcquireDisplayInfo(key)
	if not entry then
		-- A racial's cooldown tile is offered in Suggested before any tracker exists, so it has
		-- to answer with the racial's real name and cooldown rather than the generic placeholder
		-- -- the entry created from this info inherits whatever duration it reports, and a 0
		-- would be baked in permanently.
		local racial = ns:RacialCooldownSeed(spellID)
		if racial then
			info.icon = ns:GetSpellIcon(spellID)
			info.label = racial.label
			info.duration = racial.cooldown
			info.spellID = spellID
			return info
		end
		info.icon = 134400
		info.label = "Spell " .. tostring(spellID)
		info.duration = 0
		info.spellID = spellID
		return info
	end
	info.icon = ns:GetSpellIcon(spellID)
	info.label = entry.label or ("Spell " .. tostring(spellID))
	info.duration = entry.duration
	info.spellID = spellID
	return info
end

-- Expose for future extension and testing.
ns.UserSpellProviderMixin = UserSpellProviderMixin

-- Static lookup: spellID -> { duration, itemID } for tracked on-use trinkets (D-08).
local TRINKET_SPELLS = {
	-- Light Company Guidon
	[1259633] = { duration = 15, itemID = 249344 },
	-- Vaelgor's Final Stare
	[1260459] = { duration = 15, itemID = 249346 },
	-- Emberwing Feather
	[1250508] = { duration = 15, itemID = 250144 },
	-- Algeth'ar Puzzle Box
	[383781] = { duration = 20, itemID = 193701 },
	-- Echo of L'ura
	[250768] = { duration = 45, itemID = 151340 },
	-- Radiant Sunstone
	[1254624] = { duration = 20, itemID = 252411 },
	-- Freightrunner's Flask
	[1250533] = { duration = 15, itemID = 250215 },
	-- Seed of Radiant Hope
	[1263644] = { duration = 12, itemID = 250254 },
	-- Void Execution Mandate
	[1250557] = { duration = 20, itemID = 250225 },
}

-- Static lookup: spellID -> { duration, itemID } for tracked damage potions.
local POT_SPELLS = {
	-- Light's Potential
	[1236616] = { duration = 30, itemID = 241308 },
	-- Potion of Recklessness
	[1236994] = { duration = 30, itemID = 241288 },
	-- Draught of Rampant Abandon
	[1236998] = { duration = 30, itemID = 241292 },
	-- Void-Shrouded Tincture
	[1236551] = { duration = 12, itemID = 241302 },
}

-- Derived at module load: itemID -> true sets (D-11).
local TRINKET_ITEM_IDS = {}
for _, def in pairs(TRINKET_SPELLS) do
	TRINKET_ITEM_IDS[def.itemID] = true
end
local POT_ITEM_IDS = {}
for _, def in pairs(POT_SPELLS) do
	POT_ITEM_IDS[def.itemID] = true
end

-- Still the pot scan's real iteration order (Providers.lua PotProviderMixin:RefreshAtRest below).
local POT_FALLBACK_ORDER = { 241308, 241288, 241292, 241302 }

-- Namespace exports for the data tables (consumed by tests and future provider extensions).
ns.TRINKET_SPELLS = TRINKET_SPELLS
ns.POT_SPELLS = POT_SPELLS
ns.TRINKET_ITEM_IDS = TRINKET_ITEM_IDS
ns.POT_ITEM_IDS = POT_ITEM_IDS

-- Reverse lookup: given an itemID, find the matching buff spellID in a spell table.
-- Used by TrinketProvider:RefreshAtRest and PotProvider:RefreshAtRest to resolve
-- equipped-item/bag-item -> buff-spell. Returns (spellID, duration) on match or (nil, nil) on miss.
local function FindSpellByItemID(spellTable, itemID)
	if not itemID then
		return nil, nil
	end
	for spellID, def in pairs(spellTable) do
		if def.itemID == itemID then
			return spellID, def.duration
		end
	end
	return nil, nil
end

-- META-01 (Phase 27.1, D-09): answers "does this client know any spell in this catalog?" for a
-- spellID-keyed table. Deliberately NOT an inventory or equipment test — the catalogs below
-- resolve via C_Spell.GetSpellInfo on retail even with nothing equipped or bagged, so this must
-- stay a pure client-capability check. A false result means the catalog is unusable on this
-- client, not that the player happens to own nothing.
local function AnyCatalogSpellResolves(catalog)
	for spellID in pairs(catalog) do
		if C_Spell.GetSpellInfo(spellID) then
			return true
		end
	end
	return false
end

-- Phase 27 / D-03/D-04: Shared neutral placeholder for string-keyed providers when nothing
-- resolves at rest. Returns a non-nil table so the `if info then` gates at CDMTab.lua:137 and
-- CDMTab.lua:518 still fire and both Suggested tiles stay draggable — a literal nil would make
-- them permanently un-addable. duration is 0, not nil, because BuffEngine.lua:283 computes
-- `expiresAt = now + info.duration` unconditionally inside its own `if info then`; a nil
-- duration would throw there. 0 is the codebase's existing unresolved-duration sentinel
-- (see the no-entry branch of the numeric-key provider's GetDisplayInfo above; CDMTab.lua:98's
-- duration > 0 check).
-- fallbackIcon (Phase 43.1) replaces the question mark where the caller has something more
-- useful to draw. It changes the PICTURE only: spellID stays nil and duration stays 0, so
-- "unresolved" still means unresolved everywhere that tests it, and D-05's rule against guessing
-- a spell from an unmatched item is untouched.
local function UnresolvedDisplayInfo(key, label, fallbackIcon)
	local info = ns:AcquireDisplayInfo(key)
	info.icon = fallbackIcon or 134400
	info.label = label
	info.duration = 0
	info.spellID = nil
	return info
end

-- Lust data tables. Consumed by LustProvider:OnTrigger (below) and ScanActiveTimersForCancellation
-- (via proc.aliveBuffs).

-- Maps Sated-family debuff spellID -> corresponding lust buff spellID.
ns.SATED_DEBUFF_TO_LUST = {
	[57724] = 2825, -- Sated -> Bloodlust
	[57723] = 32182, -- Exhaustion -> Heroism (covers Heroism + Drums)
	[80354] = 80353, -- Temporal Displacement -> Time Warp
	[390435] = 390386, -- Exhaustion (Evoker) -> Fury of the Aspects
	[264689] = 264667, -- Fatigued -> Primal Rage (Hunter pet)
}

-- D-12: Demoted from ns.* export to module-local. Only LustProvider reads it at OnTrigger time
-- to populate proc.aliveBuffs. BuffEngine no longer consumes it (cancellation reads proc.aliveBuffs
-- directly — no SHARED_LUST_BUFFS lookup from BuffEngine after Phase 22).
local SHARED_LUST_BUFFS_LOCAL = {
	[32182] = { 32182, 1243972 }, -- Heroism + Void-touched Drums share Exhaustion (57723)
	[2825] = { 2825 }, -- Bloodlust
	[264667] = { 264667, 466904 }, -- Primal Rage + Harrier's Cry (MM Hunter) share Fatigued
	[80353] = { 80353 }, -- Time Warp
	[390386] = { 390386 }, -- Fury of the Aspects
}

-- Provider-local class -> lust spellID map (D-18 Phase 23).
-- Previously ns.* exported for CDMTab's Suggested section; CDMTab migrated to
-- ns:GetDisplayInfoForKey("lust") in Phase 23 Plan 23-02 — no external readers remain.
local CLASS_LUST_SPELL = {
	SHAMAN = 2825, -- Bloodlust
	MAGE = 80353, -- Time Warp
	EVOKER = 390386, -- Fury of the Aspects
}

-- Hunter uses Primal Rage by default; MM Hunter (spec ID 254) uses Harrier's Cry.
local function GetHunterLustSpell()
	local specIndex = GetSpecialization()
	if specIndex then
		local specID = GetSpecializationInfo(specIndex)
		if specID == 254 then -- Marksmanship
			return 466904 -- Harrier's Cry
		end
	end
	return 264667 -- Primal Rage (BM/Survival)
end

-- TrinketProviderMixin (Phase 18, D-05) — handles trinket on-use cast detection.
-- Keyed by stable string slot key "trinket" (D-01); proc.aliveBuffs drives cancellation scan (Phase 22).
-- Does NOT read equipment or inventory APIs (PITFALL-5) — icons come from C_Spell.GetSpellInfo via ns:GetSpellIcon.
local TrinketProviderMixin = {}

function TrinketProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit, castGUID, spellID
function TrinketProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	local trinketDef = TRINKET_SPELLS[spellID]
	if not trinketDef then
		return nil
	end

	local metaEntry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs["trinket"]
	if not metaEntry or metaEntry.section == "hidden" then
		return nil
	end

	local now = GetTime()
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local label = (spellInfo and spellInfo.name) or metaEntry.label or "Trinket"

	local proc = ns:AcquireProc("trinket")
	proc.key = "trinket" -- D-01 string slot key
	proc.spellID = spellID -- numeric cast spell (D-03)
	proc.duration = trinketDef.duration
	proc.expiresAt = now + trinketDef.duration
	proc.startedAt = now
	proc.section = metaEntry.section or "bars"
	proc.layoutOrder = metaEntry.layoutOrder
	proc.label = label
	proc.aliveBuffs = ns:AcquireAliveBuffs("trinket", spellID) -- D-05: cancel when the buff is absent
	return proc
end

-- D-13: Minimal at-rest cache — only { spellID, duration }. Icon/label DERIVED in GetDisplayInfo
-- via ns:GetSpellIcon + C_Spell.GetSpellInfo. Single source of truth: spellID is the key.
TrinketProviderMixin.atRest = { spellID = nil, duration = nil }

-- D-14: Scans equipped INVSLOT_TRINKET1/2; reverse-looks up to buff spellID. Writes ONLY
-- { spellID, duration } to cache; leaves it honestly nil when no equipped trinket matches
-- TRINKET_ITEM_IDS (Phase 27 / D-05 — no unconditional hardcoded fallback assignment).
-- D-17/D-18: ns:RefreshProvidersAtRest wrapper combat-gates; defensive double-gate here for any
-- future caller that invokes RefreshAtRest directly.
-- PITFALL-5: inventory APIs here, NEVER in GetDisplayInfo.
function TrinketProviderMixin:RefreshAtRest()
	if InCombatLockdown() then
		return
	end
	local trinketItemID
	-- Phase 43.1: the first equipped trinket, whether or not the catalog knows it, purely so the
	-- unresolved tile has something better than a question mark to draw. It is NOT a guess about
	-- which buff the trinket procs -- spellID and duration below are still left honestly nil when
	-- the catalog cannot answer, which is D-05's rule and stays intact. Showing the equipped
	-- item's icon for an item-backed tile is what the CDM does too (ItemUtil.GetEquipSlotTexture,
	-- used by GetSpellTexture for an equipSlot entry).
	local fallbackIcon
	for _, slot in ipairs({ INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) do
		local equipped = GetInventoryItemID("player", slot)
		if equipped and not fallbackIcon and GetInventoryItemTexture then
			local texture = GetInventoryItemTexture("player", slot)
			if not issecretvalue(texture) and texture then
				fallbackIcon = texture
			end
		end
		if equipped and TRINKET_ITEM_IDS[equipped] then
			trinketItemID = equipped
			break
		end
	end
	local spellID, duration = FindSpellByItemID(TRINKET_SPELLS, trinketItemID)
	self.atRest.spellID = spellID
	self.atRest.duration = duration
	self.atRest.fallbackIcon = fallbackIcon
end

-- D-04/D-05/D-06/D-07/D-16: Read cache; derive icon + label from spellID; return real duration.
-- Phase 27 / D-03/D-04: if the cache is unpopulated (no equipped trinket resolved), returns the
-- neutral placeholder below — never a CSV-order guess, and still never nil.
function TrinketProviderMixin:GetDisplayInfo(key)
	local spellID = self.atRest.spellID
	local duration = self.atRest.duration
	if not spellID then
		-- The equipped trinket's own icon when there is one, resolved at rest -- never an
		-- inventory call from here (PITFALL-5). Falls back to the question mark when nothing is
		-- equipped at all, which is then the honest answer rather than a gap.
		return UnresolvedDisplayInfo("trinket", "Trinket", self.atRest.fallbackIcon)
	end
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local info = ns:AcquireDisplayInfo("trinket")
	info.icon = ns:GetSpellIcon(spellID)
	info.label = (spellInfo and spellInfo.name) or "Trinket"
	info.duration = duration
	info.spellID = spellID
	return info
end

-- META-01: trinket tiles stay visible whenever any spell in TRINKET_SPELLS resolves on this
-- client, regardless of whether a matching trinket is actually equipped (D-09).
function TrinketProviderMixin:HasResolvableCatalog()
	return AnyCatalogSpellResolves(TRINKET_SPELLS)
end

ns.TrinketProviderMixin = TrinketProviderMixin
local TrinketProvider = CreateFromMixins(SpellProviderBaseMixin, TrinketProviderMixin)

-- PotProviderMixin (Phase 18, D-05) — handles damage pot cast detection.
-- Keyed by stable string slot key "pot" (D-01); proc.aliveBuffs drives cancellation scan (Phase 22).
local PotProviderMixin = {}

function PotProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function PotProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	local potDef = POT_SPELLS[spellID]
	if not potDef then
		return nil
	end

	local metaEntry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs["pot"]
	if not metaEntry or metaEntry.section == "hidden" then
		return nil
	end

	local now = GetTime()
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local label = (spellInfo and spellInfo.name) or metaEntry.label or "Damage Pot"

	local proc = ns:AcquireProc("pot")
	proc.key = "pot"
	proc.spellID = spellID -- numeric cast spell
	proc.duration = potDef.duration
	proc.expiresAt = now + potDef.duration
	proc.startedAt = now
	proc.section = metaEntry.section or "bars"
	proc.layoutOrder = metaEntry.layoutOrder
	proc.label = label
	proc.aliveBuffs = ns:AcquireAliveBuffs("pot", spellID) -- D-06
	return proc
end

-- D-13: Minimal at-rest cache.
PotProviderMixin.atRest = { spellID = nil, duration = nil }

-- D-14: Scans bags via C_Item.GetItemCount in CSV order; first count>0 wins. Leaves the cache
-- honestly nil when no bagged potion matches (Phase 27 / D-05 — no unconditional hardcoded
-- fallback assignment).
-- D-17/D-18: combat-gated.
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

-- D-04/D-05/D-06/D-07/D-16. Phase 27 / D-03/D-04: unpopulated cache returns the neutral
-- placeholder below — never a CSV-order guess, and still never nil.
function PotProviderMixin:GetDisplayInfo(key)
	local spellID = self.atRest.spellID
	local duration = self.atRest.duration
	if not spellID then
		-- The CDM's own combat-potion icon rather than a question mark. A constant, not a scan:
		-- generic item cooldowns are identified by spell category and the CDM shows one fixed
		-- icon per category without naming the item, so this IS the right picture even when no
		-- specific potion has been resolved.
		return UnresolvedDisplayInfo("pot", "Damage Pot", ns.SPELL_CATEGORY_ICON[ns.SPELL_CATEGORY_COMBAT_POTION])
	end
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local info = ns:AcquireDisplayInfo("pot")
	info.icon = ns:GetSpellIcon(spellID)
	info.label = (spellInfo and spellInfo.name) or "Damage Pot"
	info.duration = duration
	info.spellID = spellID
	return info
end

-- META-01: pot tiles stay visible whenever any spell in POT_SPELLS resolves on this client,
-- regardless of whether a matching potion is actually bagged (D-09).
function PotProviderMixin:HasResolvableCatalog()
	return AnyCatalogSpellResolves(POT_SPELLS)
end

ns.PotProviderMixin = PotProviderMixin
local PotProvider = CreateFromMixins(SpellProviderBaseMixin, PotProviderMixin)

-- LustProviderMixin (Phase 19, D-01) — handles lust debuff detection via UNIT_AURA.
-- Independent concrete mixin extending SpellProviderBaseMixin; NOT shared with other providers.
-- Registered at position 3 in ns.providers (before UserSpellProvider) — satisfies PROV-01.
--
-- Gate handling (D-09/D-10/D-11):
--   * NO top-level C_Secrets.ShouldAurasBeSecret() check — Sated debuff spellIDs are Blizzard-allowlisted
--     as safe to read even when secrets are active. This is the original LUST-01 rationale.
--   * addedAuras is iterated ONLY when readable — the whole UNIT_AURA payload is secret while aura
--     restrictions are active, so OnTrigger falls back to reading the Sated debuffs by spell ID.
--   * Per-entry issecretvalue(aura.spellId) defensive check IS preserved on the readable path —
--     required in case the individual aura spellId itself is a secret-value opaque handle.
--   * No preview gate at all — providers run normally while preview is up. In v0.2.3 the caller
--     guarded StartLustTimer behind a global preview flag; no such flag exists any more. Phase 21
--     (LIFE-03) made preview ADDITIVE instead: ns:StartAllPreviewTimers writes to its own
--     ns.previewTimers table and skips any key a real proc already owns, so a provider firing
--     during preview needs no gate to win — it simply wins.
--
-- No-restart guard (D-12): provider-internal. If ns.activeTimers["lust"] exists and has not expired,
-- return nil without writing a new proc. Dispatcher remains dumb — no "no-refresh" mode.
local LustProviderMixin = {}

local LUST_DURATION = 40

-- Shared ActiveProc builder for both detection paths (D-08 shape).
-- startedAt is when the lust buff went out: GetTime() for a freshly added Sated debuff, or the
-- Sated debuff's derived application time on the fallback path.
local function BuildLustProc(entry, lustSpellID, startedAt)
	local lustInfo = C_Spell.GetSpellInfo(lustSpellID)
	local lustLabel = (lustInfo and lustInfo.name) or "Lust / Heroism"
	if ns.debugLogging then
		print("|cff00ccffTBT Debug|r: Lust detected (spellID " .. lustSpellID .. "), timer started.")
	end
	local proc = ns:AcquireProc("lust")
	proc.key = "lust"
	proc.spellID = lustSpellID -- numeric (D-03); was "lust" string
	proc.duration = LUST_DURATION
	proc.expiresAt = startedAt + LUST_DURATION
	proc.startedAt = startedAt
	proc.section = entry.section or "bars"
	proc.layoutOrder = entry.layoutOrder
	proc.label = lustLabel
	-- D-07. SHARED_LUST_BUFFS_LOCAL's lists are module constants shared across every cast, so
	-- they are assigned by reference and never wiped; only the fallback is pooled.
	proc.aliveBuffs = SHARED_LUST_BUFFS_LOCAL[lustSpellID] or ns:AcquireAliveBuffs("lust", lustSpellID)
	return proc
end

-- Derives when an aura was applied from its own duration/expirationTime. Returns nil when either
-- field is secret or the aura carries no duration (permanent auras).
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

-- Fallback used when the UNIT_AURA payload is secret: read the Sated debuffs by spell ID, which
-- stays legal for the never-secret spells (ns:ReadPlayerAura asks first). Presence alone is not
-- enough — Sated lingers ~600s after a 40s lust, so the aura's own application time decides whether
-- the lust it came from is still up: no phantom timers off the Sated tail, and a lust that landed
-- before we could read it still gets the correct remaining time.
local function ScanSatedBySpellID(entry, now)
	for satedID, lustSpellID in pairs(ns.SATED_DEBUFF_TO_LUST) do
		local aura, readable = ns:ReadPlayerAura(satedID)
		if readable and aura then
			local appliedAt = GetAuraAppliedAt(aura)
			if appliedAt and appliedAt + LUST_DURATION > now then
				return BuildLustProc(entry, lustSpellID, appliedAt)
			end
		end
	end
	return nil
end

function LustProviderMixin:GetEventInterests()
	return { "UNIT_AURA" }
end

-- Args from UNIT_AURA: unit (string), updateInfo (table with addedAuras field)
-- Scans updateInfo.addedAuras when readable, otherwise reads the Sated debuffs by spell ID.
-- Returns the first Sated-matching proc (single proc, not a list per D-08), or nil if no match /
-- no-restart guard trips / entry hidden / aura data unreadable.
function LustProviderMixin:OnTrigger(event, unit, updateInfo)
	if event ~= "UNIT_AURA" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if not updateInfo then
		return nil
	end

	-- Entry guard: require a user-configured "lust" entry not in hidden section.
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs["lust"]
	if not entry or entry.section == "hidden" then
		return nil
	end

	-- No-restart guard (D-12): don't overwrite an already-running lust proc.
	local existing = ns.activeTimers and ns.activeTimers["lust"]
	if existing and existing.expiresAt and existing.expiresAt > GetTime() then
		return nil
	end

	-- Fast path: scan addedAuras for a Sated-family debuff. First match wins.
	-- Readability is checked on the LIST, not per entry — ipairs on a secret table errors before
	-- any per-entry guard could run.
	local addedAuras = updateInfo.addedAuras
	if ns:CanReadTable(addedAuras) then
		for _, aura in ipairs(addedAuras) do
			-- D-10: per-entry secret check; table index with aura.spellId only if safe.
			if not issecretvalue(aura.spellId) then
				local lustSpellID = ns.SATED_DEBUFF_TO_LUST[aura.spellId]
				if lustSpellID then
					return BuildLustProc(entry, lustSpellID, GetTime())
				end
			end
		end
		return nil
	end

	-- Readable payload carrying no additions: nothing could have been applied, skip the poll.
	if not issecretvalue(addedAuras) and addedAuras == nil then
		return nil
	end

	-- Payload is secret (in combat): fall back to the by-spell-ID Sated read.
	return ScanSatedBySpellID(entry, GetTime())
end

-- D-04/D-05/D-06/D-07: Class-aware fresh resolution — no cache needed. Hunter uses MM-spec-aware
-- helper; others use static class map; default 2825 (Bloodlust) if class unknown.
-- RefreshAtRest stays as base no-op (D-14) — this method is always cheap.
function LustProviderMixin:GetDisplayInfo(key)
	local _, classFilename = UnitClass("player")
	local lustSpellID
	if classFilename == "HUNTER" then
		lustSpellID = GetHunterLustSpell()
	else
		lustSpellID = CLASS_LUST_SPELL[classFilename] or 2825
	end
	if not lustSpellID then
		return nil
	end
	local spellInfo = C_Spell.GetSpellInfo(lustSpellID)
	local info = ns:AcquireDisplayInfo("lust")
	info.icon = ns:GetSpellIcon(lustSpellID)
	info.label = (spellInfo and spellInfo.name) or "Lust / Heroism"
	info.duration = LUST_DURATION
	info.spellID = lustSpellID
	return info
end

-- META-01: cannot reuse AnyCatalogSpellResolves — SHARED_LUST_BUFFS_LOCAL's values are variant
-- arrays, not definition tables, so this walks primaries and variants directly. The MM-Hunter
-- variant 466904 is a spell GetDisplayInfo can actually name, so it must be part of the test.
function LustProviderMixin:HasResolvableCatalog()
	for primarySpellID, variants in pairs(SHARED_LUST_BUFFS_LOCAL) do
		if C_Spell.GetSpellInfo(primarySpellID) then
			return true
		end
		for _, variantSpellID in ipairs(variants) do
			if C_Spell.GetSpellInfo(variantSpellID) then
				return true
			end
		end
	end
	return false
end

ns.LustProviderMixin = LustProviderMixin
local LustProvider = CreateFromMixins(SpellProviderBaseMixin, LustProviderMixin)

-- RacialProviderMixin (Phase 41, RACE-02/RACE-03) — a meta tile resolved to the player's own
-- racial ability, following LustProviderMixin's shape. For a stack-driven racial the proc itself
-- carries mutable state (proc.stacks), because the aura APIs cannot be read under restriction and
-- UNIT_SPELLCAST_SUCCEEDED casts are the only signal available while restricted. A racial with no
-- maxStacks skips all of that and is just a duration tracker.

-- RACIAL_SPELLS: numeric raceID (third return of UnitRace("player")) -> racial definition.
-- Keyed numerically, not by raceFile, because a wrong-cased string token would fail silently —
-- a miss here would mean the racial never fires and nothing would error, so the key must not be
-- defeatable by a capitalisation assumption. Absence from this table IS the "not yet supported"
-- state: there is no supported=false flag. RACE-06 / RACE-07 add the remaining races in the next
-- minor milestone.
--
-- `maxStacks` is OPTIONAL and is what makes a racial stack-driven. With it, qualifying casts
-- spend stacks and the tracker ends early when the last one goes (RACE-03). Without it the racial
-- is a plain duration tracker: the granting cast starts it, the nominal duration ends it, and no
-- cast is ever inspected — `OnTrigger`'s consuming path returns on `proc.stacks == nil` before
-- reaching either `C_Spell` call, so a stackless racial costs nothing per cast.
--
-- Phase 44.1: each race maps to a LIST of racials, not one. Forever gives most classes two, and
-- the second is tracked exactly like the first -- its own Suggested tile, empty by default, and
-- nothing auto-added. A race with one racial simply has a one-entry list, so the shape is uniform
-- and no caller branches on how many there are.
--
-- `cooldown` is new alongside `duration`, and the two are different things: duration is how long
-- the buff lasts, cooldown is how long until it can be used again. The cooldown feeds the
-- Suggested tiles on the Cooldowns tab, which create ordinary "cd:<spellID>" trackers -- the same
-- machinery any hand-added cooldown uses, with the number filled in.
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

-- The Suggested keys this provider owns, in slot order. "racial" is slot 1 and keeps its name so
-- an existing database entry is untouched; "racial2" is slot 2.
local RACIAL_SLOT_BY_KEY = { racial = 1, racial2 = 2 }
ns.RACIAL_KEYS = { "racial", "racial2" }

-- Module-level constant line arrays for the CDM-preview tooltip. Referenced by name and never
-- rebuilt per hover.
local RACIAL_SUPPORTED_LINES = { "Tracks your racial ability." }
local RACIAL_UNSUPPORTED_LINES = {
	"Your racial is not supported yet.",
	"Orc, gnome and troll racials are implemented in this version.",
	"Use the + button to track it yourself.",
}

-- Sticky, session-long memoisation of the player's resolved racial definition. Same rationale as
-- ns:IsSuggestedKeyResolvable's one-shot cache: a character's race cannot change, and the first
-- call can only arrive from a cast or a CDM open, long after PLAYER_ENTERING_WORLD, so spell
-- data is already loaded by then.
-- Per SLOT: nil = not yet resolved; false = resolved, unsupported; table = resolved, supported.
-- A race with one racial resolves slot 2 to false, which is the same "not supported" state a race
-- with no mapping at all produces, so nothing downstream needs a third case.
local racialResolved = {}
-- Guarded by issecretvalue before any concatenation; feeds the unsupported label in GetDisplayInfo.
local racialRaceName

local function ResolveRacial(slot)
	slot = slot or 1
	if racialResolved[slot] ~= nil then
		return racialResolved[slot]
	end
	local raceName, _, raceID = UnitRace("player")
	if not issecretvalue(raceName) then
		racialRaceName = raceName
	end
	if issecretvalue(raceID) or type(raceID) ~= "number" then
		racialResolved[slot] = false
		return racialResolved[slot]
	end
	local byRace = RACIAL_SPELLS[raceID]
	local def = byRace and byRace[slot]
	local spellInfo = def and C_Spell.GetSpellInfo(def.spellID)
	if def and spellInfo then
		racialResolved[slot] = {
			spellID = def.spellID,
			duration = def.duration,
			cooldown = def.cooldown,
			maxStacks = def.maxStacks,
			label = spellInfo.name or def.fallbackLabel,
		}
	else
		racialResolved[slot] = false
	end
	return racialResolved[slot]
end

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

-- spellID -> { label, cooldown } for the resolved racials, so a "cd:<spellID>" tile can show a
-- real name and a real duration BEFORE the tracker exists. Without it UserSpellProvider's
-- no-entry branch would offer "Spell 20572" with duration 0, and the entry created from it would
-- carry that 0 forever.
-- On ns rather than a file-local, because its only caller -- UserSpellProviderMixin:GetDisplayInfo
-- -- is defined hundreds of lines ABOVE this point. A file-local is an upvalue only to functions
-- declared after it, and this project has produced that bug four times; resolving through ns
-- happens at call time, so declaration order stops mattering.
function ns:RacialCooldownSeed(spellID)
	for slot = 1, #ns.RACIAL_KEYS do
		local def = ResolveRacial(slot)
		if def and def.spellID == spellID and def.cooldown then
			return def
		end
	end
	return nil
end

-- Granting-cast procs deliberately carry no cancellation-list field: the Eureka! aura is
-- unreadable under restriction, and ns:ScanActiveTimersForCancellation skips any proc whose
-- cancellation list is absent or empty, so this proc is excluded from cancellation by
-- construction rather than by a guard. Do not add one "for consistency" with Trinket/Pot/Lust.
--
-- The nominal duration is the backstop, not a fallback: expiresAt is written once at grant time
-- and never touched again, so ns:GetActiveTimers' existing lazy-expiry loop always closes the
-- window even if not a single cast ever spends a stack. Early expiry (RACE-03) is a removal via
-- ns:EndTimer, never a shortening of expiresAt — neither ending knows about the other.
local RacialProviderMixin = {}

function RacialProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

-- Module-level aliases taken once at load. Nil on a client lacking them, which the qualifying
-- test below treats as "unknown".
local IsSpellHarmful = C_Spell.IsSpellHarmful
local IsAutoAttackSpell = C_Spell.IsAutoAttackSpell

-- Accepted over-consumption, recorded here so it is never re-opened (user accepted 2026-09-20):
-- IsSpellHarmful means "can target an enemy", not "deals damage" — Frost Nova and Polymorph will
-- spend a stack the game did not. Unknown (missing API, secret result) deliberately qualifies
-- too: under-consuming would leave a stale buff on screen, which is the worse failure mode. Do
-- not add a damage-spell allow-list, a school check, or any other narrowing.
local function CastSpendsStack(spellID)
	if IsSpellHarmful then
		local harmful = IsSpellHarmful(spellID)
		if not issecretvalue(harmful) and harmful == false then
			return false
		end
	end
	if IsAutoAttackSpell then
		local autoAttack = IsAutoAttackSpell(spellID)
		if not issecretvalue(autoAttack) and autoAttack == true then
			return false
		end
	end
	return true
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit (string), castGUID (string), spellID (number).
-- Hot-path budget: on a character with no mapped racial, or on the common cast where no racial
-- window is open, this returns after a memoised local read, a nil test and a table index — zero
-- API calls. The two C_Spell calls above happen only while a live racial proc WITH STACKS exists
-- and the cast is not the granting cast, so a stackless racial (Berserking) never reaches them.
-- Starts a fresh racial proc for one slot, at the def's duration and -- when it has one -- its
-- stack count. Returns nil when that racial has no tracker, or its tracker is hidden.
--
-- Split out of OnTrigger when the second slot arrived: the granting path is identical for every
-- racial and differs only in which key and def it is handed, so writing it once is what keeps a
-- second racial from being a second copy of it.
local function StartRacialProc(key, def)
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
	if not entry or entry.section == "hidden" then
		return nil
	end

	local now = GetTime()
	-- Pooled and WIPED, which matters more here than anywhere else: this proc carries "stacks"
	-- and deliberately carries no "aliveBuffs", so a reused table that was not cleared could hand
	-- the cancellation scan a list this tracker never meant to have.
	local proc = ns:AcquireProc(key)
	proc.key = key
	proc.spellID = def.spellID
	proc.duration = def.duration
	proc.startedAt = now
	proc.expiresAt = now + def.duration -- backstop: written once, never touched again.
	proc.section = entry.section or "bars"
	proc.layoutOrder = entry.layoutOrder
	proc.label = def.label
	proc.stacks = def.maxStacks
	-- No cancellation-list field on this proc -- see the mixin header above for why.
	return proc
end

-- Spends a stack on whichever racial is live, if this cast qualifies. Reads the proc from
-- ns.activeTimers directly; the granting path does not write it -- the dispatcher's existing
-- re-assign does that.
local function ConsumeRacialStack(spellID)
	for slot = 1, #ns.RACIAL_KEYS do
		local key = ns.RACIAL_KEYS[slot]
		local proc = ns.activeTimers and ns.activeTimers[key]
		if proc and proc.stacks ~= nil and proc.expiresAt > GetTime() then
			if CastSpendsStack(spellID) then
				-- proc.stacks is TBT's own cast-derived integer, never a game value -- it needs
				-- no issecretvalue guard, unlike every WoW API value elsewhere in this file. Do
				-- not add one "for consistency".
				proc.stacks = proc.stacks - 1
				if proc.stacks <= 0 then
					ns:EndTimer(key)
					return nil
				end
				-- Return the proc itself so the dispatcher's existing
				-- ns.activeTimers[proc.key] = proc re-assign and ns:UpdateDisplay() run with no
				-- new dispatcher branch.
				return proc
			end
		end
	end
	return nil
end

function RacialProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	-- Granting cast first, across both slots: a race with one racial resolves slot 2 to false and
	-- the loop skips it, so nothing branches on how many racials a character has.
	for slot = 1, #ns.RACIAL_KEYS do
		local def = ResolveRacial(slot)
		if def and spellID == def.spellID then
			-- The same cast cannot also be the other racial, and a racial cast never spends a
			-- stack on itself, so this is terminal either way.
			return StartRacialProc(ns.RACIAL_KEYS[slot], def)
		end
	end

	-- Otherwise it may be a consuming cast for a live stack-driven racial.
	return ConsumeRacialStack(spellID)
end
-- Memoised display-info table, built at most once per session, never a fresh table.
-- RenderIconContainer/RenderBarContainer call ns:GetDisplayInfoForKey on the placeholder path
-- every frame (CLAUDE.md forbids hot-path allocation). The returned table is shared and must not
-- be mutated by callers.
-- One table per SLOT, since the two racials have different names, icons and durations.
local racialDisplayInfo = {}

function RacialProviderMixin:GetDisplayInfo(key)
	local slot = RACIAL_SLOT_BY_KEY[key] or 1
	if racialDisplayInfo[slot] then
		return racialDisplayInfo[slot]
	end
	local def = ResolveRacial(slot)
	if def then
		racialDisplayInfo[slot] = {
			icon = ns:GetSpellIcon(def.spellID),
			label = def.label,
			duration = def.duration,
			spellID = def.spellID,
			stacks = def.maxStacks,
			descriptionLines = RACIAL_SUPPORTED_LINES,
		}
	else
		-- duration = 0 and spellID = nil are the codebase's existing unresolved sentinels (see
		-- UnresolvedDisplayInfo above), which keep the tile draggable and addable while
		-- producing no timer.
		local raceLabel = racialRaceName and (racialRaceName .. " Racial") or "Racial"
		if slot > 1 then
			raceLabel = raceLabel .. " " .. slot
		end
		racialDisplayInfo[slot] = {
			icon = 134400,
			label = raceLabel,
			duration = 0,
			spellID = nil,
			unsupported = true,
			descriptionLines = RACIAL_UNSUPPORTED_LINES,
		}
	end
	return racialDisplayInfo[slot]
end

-- RACE-01: the tile must appear on both retail and Forever, so this must never consult the
-- client's spell data -- an unsupported racial is shown greyed, not hidden.
function RacialProviderMixin:HasResolvableCatalog()
	return true
end

local RacialProvider = CreateFromMixins(SpellProviderBaseMixin, RacialProviderMixin)

-- Build the concrete UserSpellProvider by merging base + concrete mixins.
-- CreateFromMixins produces a flat copy; no metatable, no shared state between instances (PITFALL-7 GC-safe).
local UserSpellProvider = CreateFromMixins(SpellProviderBaseMixin, UserSpellProviderMixin)

-- Phase 19 registry: four providers complete. LustProvider at position 3 (before UserSpellProvider). PROV-01 satisfied.
-- Phase 41: RacialProvider added at position 4 (before UserSpellProvider) -- five providers now.
ns.providers = { TrinketProvider, PotProvider, LustProvider, RacialProvider, UserSpellProvider }

-- D-08/D-09/D-10/D-11: Key-to-provider dispatch map for ns:GetDisplayInfoForKey.
-- LOCAL to Providers.lua by design (D-09) — future meta-providers update the map here,
-- not at call sites. O(1) lookup, no iteration (D-10). No OwnsKey method on base mixin (D-11).
local keyToProvider = {
	trinket = TrinketProvider,
	pot = PotProvider,
	lust = LustProvider,
	racial = RacialProvider,
	racial2 = RacialProvider,
}

-- META-01 (D-10): memoises ns:IsSuggestedKeyResolvable answers per key, for the lifetime of the
-- session. Module-local — never exported.
local catalogResolvable = {}

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

-- ns:IsSuggestedKeyResolvable(key)
-- META-01 (D-09/D-10): answers whether a Suggested-section key is worth rendering on this
-- client. ns:RefreshTBTSections has eleven call sites and redraws the Suggested section on
-- every CDM open and after every drag, so the catalog walk must happen once per key for the
-- session and the render path must only read this cache. The first call can only arrive from
-- a user-triggered CDM open, long after PLAYER_ENTERING_WORLD, so the client's spell data is
-- fully loaded by then and a sticky one-shot answer is safe — no invalidation hook is added.
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

-- Build eventToProviders map once after ns.providers is populated.
-- PITFALL-7 performance trap: do NOT rebuild this per event.
for _, provider in ipairs(ns.providers) do
	for _, event in ipairs(provider:GetEventInterests()) do
		if not eventToProviders[event] then
			eventToProviders[event] = {}
		end
		table.insert(eventToProviders[event], provider)
	end
end

-- ns:DispatchEventToProviders(event, ...)
-- Routes the event to all providers that declared interest via GetEventInterests().
-- Each interested provider's OnTrigger is called; if it returns a proc, the proc is stored
-- in ns.activeTimers keyed by proc.key (replace-on-reproc).
-- Returns the number of procs handled (0 if no match).
--
-- DESIGN NOTE (the migration that finished in Phases 17-19):
-- This loop is now the ONLY writer of ns.activeTimers for cast-triggered procs. The coexistence
-- period is over: BuffEngine's own branching cast handler is gone, and ns:OnSpellCastSucceeded
-- does nothing but call straight into here (BuffEngine.lua, "zero branches"). User-spell,
-- trinket, pot and lust procs all arrive through a provider's OnTrigger, so there is one writer
-- and no way to get a duplicate entry for a key.
function ns:DispatchEventToProviders(event, ...)
	local interested = eventToProviders[event]
	if not interested then
		return 0
	end
	local handled = 0
	for _, provider in ipairs(interested) do
		local proc = provider:OnTrigger(event, ...)
		if proc then
			ns.activeTimers[proc.key] = proc
			handled = handled + 1
			if ns.UpdateDisplay then
				ns:UpdateDisplay()
			end
		end
	end
	return handled
end
