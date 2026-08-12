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
-- duration is REAL — never 0 sentinel.
-- Override in concrete provider. Default returns nil.
function SpellProviderBaseMixin:GetDisplayInfo(key)
	return nil
end

-- Refreshes the provider's at-rest cache (inventory scan, etc.). No-op by default.
-- D-17: Caller (ns:RefreshProvidersAtRest wrapper) combat-gates before calling. Defensive
-- guard at provider level is D-18 — inside concrete providers that touch restricted APIs.
-- D-19 / PITFALL-5: GetDisplayInfo MUST NOT call inventory APIs; only RefreshAtRest does.
function SpellProviderBaseMixin:RefreshAtRest() end

-- Expose on namespace so other providers (future) and tests can reference the base.
ns.SpellProviderBaseMixin = SpellProviderBaseMixin

-- UserSpellProviderMixin — handles user-created buffs keyed by numeric spellID in ns.db.trackedBuffs.
-- String keys ("trinket", "pot", "lust") are ignored; those will be handled by meta providers in Phase 18-19.
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

	-- PITFALL-1: read ns.db.trackedBuffs keys as-is — do not rename, do not remap.
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[spellID]
	if not entry then
		return nil
	end
	-- Preserve section="hidden" guard from BuffEngine OnSpellCastSucceeded branch 3.
	if entry.section == "hidden" then
		return nil
	end

	local now = GetTime()
	return {
		key = spellID, -- numeric; 1:1 with DB slot
		spellID = spellID, -- numeric (D-03): THE spell
		duration = entry.duration,
		expiresAt = now + entry.duration,
		startedAt = now,
		section = entry.section or "bars",
		layoutOrder = entry.layoutOrder,
		label = entry.label or ("Spell " .. tostring(spellID)),
		aliveBuffs = { spellID }, -- D-04: single-element, the user's tracked spell
	}
end

-- key: numeric spellID from ns.db.trackedBuffs.
-- Returns { icon, label, duration, spellID } or nil if entry missing (fallback spellID=key, duration=0
-- when entry missing is NOT required — user-spell keys without entries are genuinely unknown).
-- D-04/D-05/D-06/D-07: spellID numeric, duration real, icon/label derived.
function UserSpellProviderMixin:GetDisplayInfo(key)
	if type(key) ~= "number" then
		return nil
	end
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
	if not entry then
		return { icon = 134400, label = "Spell " .. tostring(key), duration = 0, spellID = key }
	end
	return {
		icon = ns:GetSpellIcon(key),
		label = entry.label or ("Spell " .. tostring(key)),
		duration = entry.duration,
		spellID = key,
	}
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

-- Ordered fallback iteration in CSV order (consumed by TrinketProvider:RefreshAtRest / PotProvider:RefreshAtRest below).
local TRINKET_FALLBACK_ORDER = { 249344, 249346, 250144, 193701, 151340, 252411, 250215, 250254, 250225 }
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

	return {
		key = "trinket", -- D-01 string slot key
		spellID = spellID, -- numeric cast spell (D-03)
		duration = trinketDef.duration,
		expiresAt = now + trinketDef.duration,
		startedAt = now,
		section = metaEntry.section or "bars",
		layoutOrder = metaEntry.layoutOrder,
		label = label,
		aliveBuffs = { spellID }, -- D-05: cancel when trinket's buff is absent
	}
end

-- D-13: Minimal at-rest cache — only { spellID, duration }. Icon/label DERIVED in GetDisplayInfo
-- via ns:GetSpellIcon + C_Spell.GetSpellInfo. Single source of truth: spellID is the key.
TrinketProviderMixin.atRest = { spellID = nil, duration = nil }

-- D-14: Scans equipped INVSLOT_TRINKET1/2; reverse-looks up to buff spellID; falls back to
-- first CSV entry. Writes ONLY { spellID, duration } to cache.
-- D-17/D-18: ns:RefreshProvidersAtRest wrapper combat-gates; defensive double-gate here for any
-- future caller that invokes RefreshAtRest directly.
-- PITFALL-5: inventory APIs here, NEVER in GetDisplayInfo.
function TrinketProviderMixin:RefreshAtRest()
	if InCombatLockdown() then
		return
	end
	local trinketItemID
	for _, slot in ipairs({ INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) do
		local equipped = GetInventoryItemID("player", slot)
		if equipped and TRINKET_ITEM_IDS[equipped] then
			trinketItemID = equipped
			break
		end
	end
	if not trinketItemID then
		trinketItemID = TRINKET_FALLBACK_ORDER[1]
	end
	local spellID, duration = FindSpellByItemID(TRINKET_SPELLS, trinketItemID)
	self.atRest.spellID = spellID
	self.atRest.duration = duration
end

-- D-04/D-05/D-06/D-07/D-16: Read cache; derive icon + label from spellID; return real duration.
-- First-call fallback (D-16 step 5): if cache unpopulated, resolve from first CSV entry so the
-- method never returns nil in normal operation.
function TrinketProviderMixin:GetDisplayInfo(key)
	local spellID = self.atRest.spellID
	local duration = self.atRest.duration
	if not spellID then
		spellID, duration = FindSpellByItemID(TRINKET_SPELLS, TRINKET_FALLBACK_ORDER[1])
	end
	if not spellID then
		return nil
	end
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local label = (spellInfo and spellInfo.name) or "Trinket"
	return {
		icon = ns:GetSpellIcon(spellID),
		label = label,
		duration = duration,
		spellID = spellID,
	}
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

	return {
		key = "pot",
		spellID = spellID, -- numeric cast spell
		duration = potDef.duration,
		expiresAt = now + potDef.duration,
		startedAt = now,
		section = metaEntry.section or "bars",
		layoutOrder = metaEntry.layoutOrder,
		label = label,
		aliveBuffs = { spellID }, -- D-06
	}
end

-- D-13: Minimal at-rest cache.
PotProviderMixin.atRest = { spellID = nil, duration = nil }

-- D-14: Scans bags via C_Item.GetItemCount in CSV order; first count>0 wins.
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
	if not potItemID then
		potItemID = POT_FALLBACK_ORDER[1]
	end
	local spellID, duration = FindSpellByItemID(POT_SPELLS, potItemID)
	self.atRest.spellID = spellID
	self.atRest.duration = duration
end

-- D-04/D-05/D-06/D-07/D-16.
function PotProviderMixin:GetDisplayInfo(key)
	local spellID = self.atRest.spellID
	local duration = self.atRest.duration
	if not spellID then
		spellID, duration = FindSpellByItemID(POT_SPELLS, POT_FALLBACK_ORDER[1])
	end
	if not spellID then
		return nil
	end
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local label = (spellInfo and spellInfo.name) or "Damage Pot"
	return {
		icon = ns:GetSpellIcon(spellID),
		label = label,
		duration = duration,
		spellID = spellID,
	}
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
--   * NO ns.previewActive check — providers run normally during preview. This is a behavior change
--     from v0.2.3 (old StartLustTimer was guarded by `not ns.previewActive` in the caller).
--     Intentional prep for Phase 21 / LIFE-03 (additive preview rewrite).
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
	return {
		key = "lust",
		spellID = lustSpellID, -- numeric (D-03); was "lust" string
		duration = LUST_DURATION,
		expiresAt = startedAt + LUST_DURATION,
		startedAt = startedAt,
		section = entry.section or "bars",
		layoutOrder = entry.layoutOrder,
		label = lustLabel,
		aliveBuffs = SHARED_LUST_BUFFS_LOCAL[lustSpellID] or { lustSpellID }, -- D-07
	}
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
	local label = (spellInfo and spellInfo.name) or "Lust / Heroism"
	return {
		icon = ns:GetSpellIcon(lustSpellID),
		label = label,
		duration = LUST_DURATION,
		spellID = lustSpellID,
	}
end

ns.LustProviderMixin = LustProviderMixin
local LustProvider = CreateFromMixins(SpellProviderBaseMixin, LustProviderMixin)

-- Build the concrete UserSpellProvider by merging base + concrete mixins.
-- CreateFromMixins produces a flat copy; no metatable, no shared state between instances (PITFALL-7 GC-safe).
local UserSpellProvider = CreateFromMixins(SpellProviderBaseMixin, UserSpellProviderMixin)

-- Phase 19 registry: four providers complete. LustProvider at position 3 (before UserSpellProvider). PROV-01 satisfied.
ns.providers = { TrinketProvider, PotProvider, LustProvider, UserSpellProvider }

-- D-08/D-09/D-10/D-11: Key-to-provider dispatch map for ns:GetDisplayInfoForKey.
-- LOCAL to Providers.lua by design (D-09) — future meta-providers update the map here,
-- not at call sites. O(1) lookup, no iteration (D-10). No OwnsKey method on base mixin (D-11).
local keyToProvider = {
	trinket = TrinketProvider,
	pot = PotProvider,
	lust = LustProvider,
}

-- ns:GetDisplayInfoForKey(key)
-- Returns { icon, label, duration, spellID } for any provider key, or nil if unresolvable.
-- String keys ("trinket"/"pot"/"lust") route via keyToProvider; numeric keys route to UserSpellProvider.
-- Callers read the subset of fields they need; the full shape is returned unconditionally.
function ns:GetDisplayInfoForKey(key)
	if type(key) == "string" then
		local p = keyToProvider[key]
		return p and p:GetDisplayInfo(key) or nil
	end
	return UserSpellProvider:GetDisplayInfo(key)
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
-- DESIGN NOTE (coexistence with BuffEngine in Phase 17):
-- ns.activeTimers is shared with BuffEngine.OnSpellCastSucceeded during migration. UserSpellProvider
-- will be the only writer for numeric-keyed user-spell timers once Plan 17-02 removes BuffEngine's
-- branch 3; meta providers (trinket/pot/lust) continue to be written by BuffEngine directly until
-- Phases 18-19. Both paths write to the SAME table — no duplicate entries because BuffEngine will
-- early-return before branch 3 after Plan 17-02 reroutes through this dispatcher.
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
