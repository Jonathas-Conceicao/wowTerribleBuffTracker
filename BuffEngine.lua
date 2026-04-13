local _, ns = ...

-- Runtime-only guard flags (not persisted to SavedVariables)
ns.auraCheckBlocked = false
ns.previewActive = false
ns.debugLogging = false

-- Preview save/restore: stores real active timers while preview is running (D-07)
local savedPreviewTimers = {}

-- Maps Sated-family debuff spellID -> corresponding lust buff spellID (D-13)
ns.SATED_DEBUFF_TO_LUST = {
	[57724] = 2825, -- Sated -> Bloodlust
	[57723] = 32182, -- Exhaustion -> Heroism (covers Heroism + Drums)
	[80354] = 80353, -- Temporal Displacement -> Time Warp
	[390435] = 390386, -- Exhaustion (Evoker) -> Fury of the Aspects
	[264689] = 264667, -- Fatigued -> Primal Rage (Hunter pet)
}

-- Lust buffs that share a Sated debuff — ALL must be absent before cancelling the timer.
-- Keyed by the "display" lustBuffID stored in the timer; value is a list of buff spellIDs to check.
local SHARED_LUST_BUFFS = {
	[32182] = { 32182, 1243972 }, -- Heroism + Void-touched Drums share Exhaustion (57723)
	[2825] = { 2825 }, -- Bloodlust
	[264667] = { 264667, 466904 }, -- Primal Rage + Harrier's Cry (MM Hunter) share Fatigued
	[80353] = { 80353 }, -- Time Warp
	[390386] = { 390386 }, -- Fury of the Aspects
}

-- Maps classFilename -> class-specific lust spellID (D-14)
-- Hunter uses Primal Rage by default; MM Hunter (spec ID 254) uses Harrier's Cry
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

ns.CLASS_LUST_SPELL = {
	SHAMAN = 2825, -- Bloodlust
	MAGE = 80353, -- Time Warp
	EVOKER = 390386, -- Fury of the Aspects
}

-- Static lookup: spellID -> { duration, itemID } for tracked on-use trinkets (D-01).
-- Names are comments only (D-04); labels come from C_Spell.GetSpellInfo at cast time.
-- Source: trinket_info.csv. Duration is used at cast time; SUGGESTED_BUFFS.duration=0 is a sentinel (D-07).
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

-- Static lookup: spellID -> { duration, itemID } for tracked damage potions (D-01).
-- Source: pots_info.csv.
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

-- Derived at module load (D-02): itemID -> true sets for O(1) equipment/bag lookup in Phase 14.
-- Do NOT hand-maintain; regenerate by iterating the parent spell tables.
local TRINKET_ITEM_IDS = {}
for _, def in pairs(TRINKET_SPELLS) do
	TRINKET_ITEM_IDS[def.itemID] = true
end

local POT_ITEM_IDS = {}
for _, def in pairs(POT_SPELLS) do
	POT_ITEM_IDS[def.itemID] = true
end

ns.TRINKET_SPELLS = TRINKET_SPELLS
ns.POT_SPELLS = POT_SPELLS
ns.TRINKET_ITEM_IDS = TRINKET_ITEM_IDS
ns.POT_ITEM_IDS = POT_ITEM_IDS

-- D-08: Ordered fallback iteration in CSV order. pairs() doesn't guarantee order
-- so we hard-code the insertion order matching trinket_info.csv / pots_info.csv.
-- If TRINKET_SPELLS / POT_SPELLS gain entries, keep these arrays in sync.
local TRINKET_FALLBACK_ORDER = { 249344, 249346, 250144, 193701, 151340, 252411, 250215, 250254, 250225 }
local POT_FALLBACK_ORDER = { 241308, 241288, 241292, 241302 }

-- D-01: Eager-cached at-rest resolution for meta-slots. Populated by ns:RefreshMetaIcons.
-- Detection scans items (equipped trinkets / bag pots), but icon and tooltip resolve
-- to the matching buff SPELL (via reverse lookup itemID → spellID). This keeps the
-- visual coherent across ilvl/quality differences of the source item.
ns.metaIcons = { trinket = nil, pot = nil } -- texture only (back-compat)
ns.metaAtRest = {
	trinket = { icon = nil, spellID = nil, duration = nil },
	pot = { icon = nil, spellID = nil, duration = nil },
}

-- Reverse lookup: given an itemID, find the matching buff spellID in a spell table.
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

-- D-02/D-03: Single scan entry point. Called from CDMTab StartPreview only.
-- D-07: Combat-gated. If locked down, leave cache as-is.
-- Resolution: scan finds itemID → reverse-lookup to spellID → icon/tooltip/duration
-- all derive from the buff spell (not the item).
function ns:RefreshMetaIcons()
	if InCombatLockdown() then
		return
	end

	-- Trinket scan (D-05): equipped slots 13/14, first match wins
	local trinketItemID
	for _, slot in ipairs({ INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) do
		local equipped = GetInventoryItemID("player", slot)
		if equipped and TRINKET_ITEM_IDS[equipped] then
			trinketItemID = equipped
			break
		end
	end
	-- D-08: Fallback to first CSV entry whose buff spell icon resolves
	if not trinketItemID then
		for _, itemID in ipairs(TRINKET_FALLBACK_ORDER) do
			trinketItemID = itemID
			break -- first entry is the fallback; spell icon resolution happens below
		end
	end
	local trinketSpellID, trinketDuration = FindSpellByItemID(TRINKET_SPELLS, trinketItemID)
	local trinketIcon = trinketSpellID and ns:GetSpellIcon(trinketSpellID) or nil
	ns.metaIcons.trinket = trinketIcon
	ns.metaAtRest.trinket.icon = trinketIcon
	ns.metaAtRest.trinket.spellID = trinketSpellID
	ns.metaAtRest.trinket.duration = trinketDuration

	-- Pot scan (D-06): bag iteration over POT_ITEM_IDS in CSV order, first count>0 wins
	local potItemID
	for _, itemID in ipairs(POT_FALLBACK_ORDER) do
		if (C_Item.GetItemCount(itemID) or 0) > 0 then
			potItemID = itemID
			break
		end
	end
	if not potItemID then
		potItemID = POT_FALLBACK_ORDER[1] -- D-08 fallback: first CSV entry
	end
	local potSpellID, potDuration = FindSpellByItemID(POT_SPELLS, potItemID)
	local potIcon = potSpellID and ns:GetSpellIcon(potSpellID) or nil
	ns.metaIcons.pot = potIcon
	ns.metaAtRest.pot.icon = potIcon
	ns.metaAtRest.pot.spellID = potSpellID
	ns.metaAtRest.pot.duration = potDuration
end

-- D-10: Public read accessor. Returns 134400 (?-icon) when cache is nil.
function ns:GetAtRestMetaIcon(key)
	return ns.metaIcons[key] or 134400
end

-- Return resolved at-rest spellID and duration for tooltip/display.
function ns:GetAtRestMetaInfo(key)
	return ns.metaAtRest[key]
end

-- Registry of suggested buff definitions for CDM tab Suggested section (D-04, D-09)
ns.SUGGESTED_BUFFS = {
	{
		key = "lust",
		label = "Lust / Heroism",
		duration = 40,
		metaBuff = true,
		getCDMSpellID = function()
			local _, classFilename = UnitClass("player")
			if classFilename == "HUNTER" then
				return GetHunterLustSpell()
			end
			return ns.CLASS_LUST_SPELL[classFilename] or 2825
		end,
	},
}

-- Trinket meta-tracker (D-06). getCDMIcon calls ns:GetAtRestMetaIcon (Phase 14).
-- duration=0 is a sentinel (D-07) — real duration comes from ns.TRINKET_SPELLS[spellID].duration at cast time.
ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = {
	key = "trinket",
	label = "Trinket",
	duration = 0,
	metaBuff = true,
	getCDMSpellID = function()
		return nil
	end,
	getCDMIcon = function()
		return ns:GetAtRestMetaIcon("trinket")
	end,
}

-- Damage pot meta-tracker (D-06). Same plumbing as trinket; itemID scanning is bag-based
-- in Phase 14 (C_Item.GetItemCount against ns.POT_ITEM_IDS).
ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = {
	key = "pot",
	label = "Damage Pot",
	duration = 0,
	metaBuff = true,
	getCDMSpellID = function()
		return nil
	end,
	getCDMIcon = function()
		return ns:GetAtRestMetaIcon("pot")
	end,
}

function ns:InitBuffEngine()
	-- Schema v3 is terminal for v0.2.3 (DATA-03 reconciliation).
	-- v0.2.3 introduces trinket/pot meta-trackers but creates NO new persistent SavedVariables
	-- structures — TRINKET_SPELLS and POT_SPELLS are runtime-only static tables. The SUGGESTED_BUFFS
	-- entries for "trinket"/"pot" land in ns.db.trackedBuffs only via copy-on-drag (user action),
	-- and follow the existing string-keyed lust pattern that v3 already supports. Therefore no
	-- v3->v4 migration is needed: v0.2.3 is the first release with these features, so no stale
	-- "trinket"/"pot" keys can exist in pre-upgrade SavedVariables. D-05 (CONTEXT.md) supersedes
	-- REQUIREMENTS.md DATA-03; DATA-03 is marked N/A in REQUIREMENTS.md traceability.
	local CURRENT_SCHEMA_VERSION = 3
	local ver = ns.db.schemaVersion or 0

	if ver < 1 then
		-- v0 -> v1: Replace enabled/displayMode with section (D-01)
		for _, entry in pairs(ns.db.trackedBuffs) do
			if not entry.section then
				if entry.enabled == false then
					entry.section = "hidden"
				elseif entry.displayMode == "buff" then
					entry.section = "buffs"
				else
					entry.section = "bars"
				end
			end
			entry.enabled = nil
			entry.displayMode = nil
		end
		ns.db.schemaVersion = 1
		print("|cff00ccffTerribleBuffTracker|r: DB migrated to v1.")
	end

	if ver < 2 then
		-- v1 -> v2: Backfill layoutOrder for within-section reordering
		local order = 1
		for _, entry in pairs(ns.db.trackedBuffs) do
			if not entry.layoutOrder then
				entry.layoutOrder = order
				order = order + 1
			end
		end
		ns.db.schemaVersion = 2
	end

	if ver < 3 then
		-- v2 -> v3: Remove pre-seeded lust entry if it was added by earlier migration
		-- Lust meta-buff is now only created when user drags from Suggested (D-04/D-05)
		if ns.db.trackedBuffs["lust"] and ns.db.trackedBuffs["lust"].section == "hidden" then
			-- Only remove if user hasn't moved it (still in hidden = auto-seeded)
			ns.db.trackedBuffs["lust"] = nil
		end
		ns.db.schemaVersion = 3
	end
end

function ns:GetSpellIcon(spellID)
	if not spellID or type(spellID) ~= "number" then
		return 134400 -- Question mark icon fallback for nil/string keys
	end
	local info = C_Spell.GetSpellInfo(spellID)
	if info and info.iconID then
		return info.iconID
	end
	return 134400 -- Question mark icon fallback
end

-- D-06: Shared helper — returns numeric CDM spellID for a string key, or nil.
-- For non-string keys (numeric spellIDs), returns nil (caller uses key as-is).
function ns:ResolveSuggestedSpellID(key)
	if type(key) ~= "string" then
		return nil
	end
	for _, suggested in ipairs(ns.SUGGESTED_BUFFS) do
		if suggested.key == key and suggested.getCDMSpellID then
			return suggested.getCDMSpellID()
		end
	end
	return nil
end

function ns:OnSpellCastSucceeded(spellID)
	-- D-02: Meta-slot fan-out happens FIRST, before the regular trackedBuffs[spellID] path.
	-- Trinket/pot spellIDs never collide with regular tracked buffs; first match wins.

	-- Trinket fan-out (D-01, D-03, D-04, D-06, D-08)
	local trinketDef = ns.TRINKET_SPELLS[spellID]
	if trinketDef then
		local metaEntry = ns.db.trackedBuffs["trinket"]
		if not metaEntry or metaEntry.section == "hidden" then
			return
		end
		-- D-04: Remove any existing timer occupying the same meta-slot
		for existingID, existingTimer in pairs(ns.activeTimers) do
			if existingTimer.metaSlot == "trinket" then
				ns.activeTimers[existingID] = nil
			end
		end
		local now = GetTime()
		local spellInfo = C_Spell.GetSpellInfo(spellID)
		local label = (spellInfo and spellInfo.name) or metaEntry.label or "Trinket"
		ns.activeTimers[spellID] = {
			spellID = spellID,
			expiresAt = now + trinketDef.duration,
			startedAt = now,
			duration = trinketDef.duration,
			icon = ns:GetSpellIcon(spellID),
			label = label,
			section = metaEntry.section or "bars",
			layoutOrder = metaEntry.layoutOrder,
			source = "cast",
			metaSlot = "trinket",
		}
		if ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
		return
	end

	-- Pot fan-out (same shape as trinket, metaSlot = "pot")
	local potDef = ns.POT_SPELLS[spellID]
	if potDef then
		local metaEntry = ns.db.trackedBuffs["pot"]
		if not metaEntry or metaEntry.section == "hidden" then
			return
		end
		-- D-04: Remove any existing timer occupying the same meta-slot
		for existingID, existingTimer in pairs(ns.activeTimers) do
			if existingTimer.metaSlot == "pot" then
				ns.activeTimers[existingID] = nil
			end
		end
		local now = GetTime()
		local spellInfo = C_Spell.GetSpellInfo(spellID)
		local label = (spellInfo and spellInfo.name) or metaEntry.label or "Damage Pot"
		ns.activeTimers[spellID] = {
			spellID = spellID,
			expiresAt = now + potDef.duration,
			startedAt = now,
			duration = potDef.duration,
			icon = ns:GetSpellIcon(spellID),
			label = label,
			section = metaEntry.section or "bars",
			layoutOrder = metaEntry.layoutOrder,
			source = "cast",
			metaSlot = "pot",
		}
		if ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
		return
	end

	-- Existing regular-buff path (preserved verbatim)
	local entry = ns.db.trackedBuffs[spellID]
	if not entry then
		return
	end
	if entry.section == "hidden" then
		return
	end

	local now = GetTime()
	ns.activeTimers[spellID] = {
		spellID = spellID,
		expiresAt = now + entry.duration,
		startedAt = now,
		duration = entry.duration,
		icon = ns:GetSpellIcon(spellID),
		label = entry.label or ("Spell " .. spellID),
		section = entry.section or "bars",
		source = "cast",
	}

	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:GetActiveTimers()
	local now = GetTime()
	local result = {}

	-- Clean up expired and collect active
	for spellID, timer in pairs(ns.activeTimers) do
		if timer.expiresAt <= now then
			ns.activeTimers[spellID] = nil
		else
			table.insert(result, timer)
		end
	end

	-- Sort by remaining time, shortest first
	table.sort(result, function(a, b)
		return a.expiresAt < b.expiresAt
	end)

	return result
end

function ns:AddTrackedBuff(spellID, duration, label)
	if not spellID or spellID <= 0 then
		print("|cff00ccffTerribleBuffTracker|r: Invalid spell ID.")
		return false
	end
	if not duration or duration <= 0 then
		print("|cff00ccffTerribleBuffTracker|r: Invalid duration.")
		return false
	end

	local displayLabel = label
	if not displayLabel or displayLabel == "" then
		local info = C_Spell.GetSpellInfo(spellID)
		if info and info.name then
			displayLabel = info.name
		else
			displayLabel = "Spell " .. spellID
		end
	end

	-- Assign next layoutOrder (max existing + 1)
	local maxOrder = 0
	for _, e in pairs(ns.db.trackedBuffs) do
		if e.layoutOrder and e.layoutOrder > maxOrder then
			maxOrder = e.layoutOrder
		end
	end

	ns.db.trackedBuffs[spellID] = {
		spellID = spellID,
		duration = duration,
		label = displayLabel,
		section = "hidden", -- D-05: new buffs land in Not Displayed
		layoutOrder = maxOrder + 1,
	}

	print(
		"|cff00ccffTerribleBuffTracker|r: Now tracking |cff00ff00"
			.. displayLabel
			.. "|r (ID: "
			.. spellID
			.. ", "
			.. duration
			.. "s)."
	)
	return true
end

function ns:RemoveTrackedBuff(spellID)
	local entry = ns.db.trackedBuffs[spellID]
	if not entry then
		print("|cff00ccffTerribleBuffTracker|r: Spell ID " .. spellID .. " is not tracked.")
		return false
	end

	local label = entry.label
	ns.db.trackedBuffs[spellID] = nil
	ns.activeTimers[spellID] = nil

	print("|cff00ccffTerribleBuffTracker|r: Stopped tracking |cffff6600" .. label .. "|r (ID: " .. spellID .. ").")

	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
	return true
end

function ns:SetBuffSection(spellID, section)
	if not spellID then
		return
	end
	if type(spellID) ~= "number" and type(spellID) ~= "string" then
		return
	end
	local entry = ns.db.trackedBuffs[spellID]
	if not entry then
		return
	end
	entry.section = section
	if ns.activeTimers[spellID] then
		ns.activeTimers[spellID].section = section
	end
	if section == "hidden" then
		ns.activeTimers[spellID] = nil
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:StartAllPreviewTimers()
	-- D-07: Save real timers before preview overwrites them. Capture on EVERY call —
	-- real cast timers can be added between preview rebuilds (e.g. user casts a
	-- trinket while CDM is open and a section rebuild fires). Real timers have
	-- source="cast" (trinket/pot/regular) or source="debuff" (lust); preview timers
	-- have no source field.
	wipe(savedPreviewTimers)
	for k, v in pairs(ns.activeTimers) do
		if v.source then
			savedPreviewTimers[k] = v
		end
	end

	ns.previewActive = true
	local now = GetTime()
	wipe(ns.activeTimers)

	for spellID, entry in pairs(ns.db.trackedBuffs) do
		if entry.section ~= "hidden" then
			-- D-06: Use shared helper to resolve icon and label for meta-buff string keys
			local resolvedID = ns:ResolveSuggestedSpellID(spellID) or spellID
			local timerLabel = entry.label or ("Spell " .. tostring(spellID))
			if type(resolvedID) == "number" then
				local info = C_Spell.GetSpellInfo(resolvedID)
				if info and info.name then
					timerLabel = info.name
				end
			end
			-- Phase 14: meta-slots with at-rest icon cache (trinket/pot) use GetAtRestMetaIcon.
			-- Lust falls through to GetSpellIcon via the resolved class-aware spellID.
			local previewIcon
			if type(spellID) == "string" then
				local metaIcon = ns:GetAtRestMetaIcon(spellID)
				if metaIcon and metaIcon ~= 134400 then
					previewIcon = metaIcon
				else
					previewIcon = ns:GetSpellIcon(resolvedID)
					if (not previewIcon or previewIcon == 134400) and metaIcon then
						previewIcon = metaIcon
					end
				end
			else
				previewIcon = ns:GetSpellIcon(resolvedID)
			end
			ns.activeTimers[spellID] = {
				spellID = spellID,
				expiresAt = now + entry.duration,
				startedAt = now,
				duration = entry.duration,
				icon = previewIcon,
				label = timerLabel,
				section = entry.section or "bars",
			}
		end
	end

	-- D-07: Merge real timers back on top (real timers visible and override preview for same key)
	for k, v in pairs(savedPreviewTimers) do
		if v.expiresAt > now then
			ns.activeTimers[k] = v
		end
	end

	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:ClearAllTimers()
	ns.previewActive = false

	-- D-07: Restore real timers instead of wiping everything
	wipe(ns.activeTimers)
	local now = GetTime()
	for k, v in pairs(savedPreviewTimers) do
		if v.expiresAt > now then
			ns.activeTimers[k] = v
		end
	end
	wipe(savedPreviewTimers)

	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:ScanActiveTimersForCancellation()
	local cancelledCount = 0
	local cancelledLabels

	for spellID, timer in pairs(ns.activeTimers) do
		local shouldCancel = false

		if timer.source == "cast" then
			-- Cast-originated: check if buff aura is still present
			local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
			if aura == nil then
				shouldCancel = true
			end
		elseif timer.source == "debuff" and timer.lustBuffID then
			-- Lust meta-buff: check ALL buffs that share the same Sated debuff.
			-- E.g., Heroism and Drums both trigger Exhaustion — only cancel if BOTH are absent.
			local buffsToCheck = SHARED_LUST_BUFFS[timer.lustBuffID]
			if buffsToCheck then
				local anyPresent = false
				for _, buffID in ipairs(buffsToCheck) do
					if C_UnitAuras.GetPlayerAuraBySpellID(buffID) then
						anyPresent = true
						break
					end
				end
				if not anyPresent then
					shouldCancel = true
				end
			else
				-- Fallback: unknown lustBuffID, check directly
				if not C_UnitAuras.GetPlayerAuraBySpellID(timer.lustBuffID) then
					shouldCancel = true
				end
			end
		end

		if shouldCancel then
			ns.activeTimers[spellID] = nil
			cancelledCount = cancelledCount + 1
			if ns.debugLogging then
				if not cancelledLabels then
					cancelledLabels = {}
				end
				table.insert(cancelledLabels, timer.label or tostring(spellID))
			end
		end
	end

	if cancelledCount > 0 then
		if ns.debugLogging and cancelledLabels then
			print(
				"|cff00ccffTBT Debug|r: Cancelled "
					.. cancelledCount
					.. " timer(s): "
					.. table.concat(cancelledLabels, ", ")
			)
		end
		if ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
	end
end

function ns:StartLustTimer(lustSpellID)
	local entry = ns.db.trackedBuffs["lust"]
	if not entry or entry.section == "hidden" then
		return
	end
	-- Don't restart if lust timer already running
	local existing = ns.activeTimers["lust"]
	if existing and existing.expiresAt > GetTime() then
		return
	end
	local now = GetTime()
	-- D-16: Use actual detected lust spell's icon and name
	local lustLabel = "Lust / Heroism"
	local lustInfo = C_Spell.GetSpellInfo(lustSpellID)
	if lustInfo and lustInfo.name then
		lustLabel = lustInfo.name
	end
	ns.activeTimers["lust"] = {
		spellID = "lust",
		lustBuffID = lustSpellID, -- actual lust buff spellID for cancellation check
		expiresAt = now + 40,
		startedAt = now,
		duration = 40,
		icon = ns:GetSpellIcon(lustSpellID),
		label = lustLabel,
		section = entry.section or "bars",
		source = "debuff",
	}
	if ns.debugLogging then
		print("|cff00ccffTBT Debug|r: Lust detected (spellID " .. lustSpellID .. "), timer started.")
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:OnUnitAura(updateInfo)
	-- LUST-01: Detect Sated-family debuffs BEFORE secret gate.
	-- Sated debuffs are allowlisted (never secret) so this is safe even in combat/M+.
	-- Must run before the ShouldAurasBeSecret() return to detect lust in restricted contexts.
	if updateInfo and updateInfo.addedAuras and not ns.previewActive then
		for _, aura in ipairs(updateInfo.addedAuras) do
			-- D-11: Per-entry secret check before table index with spellId
			if not issecretvalue(aura.spellId) then
				local lustSpellID = ns.SATED_DEBUFF_TO_LUST[aura.spellId]
				if lustSpellID then
					ns:StartLustTimer(lustSpellID)
				end
			end
		end
	end

	-- AURA-02: Gate on secret restriction (must be FIRST check for scan logic)
	if C_Secrets.ShouldAurasBeSecret() then
		if not ns.auraCheckBlocked then
			ns.auraCheckBlocked = true
			if ns.debugLogging then
				print("|cff00ccffTBT Debug|r: aura check blocked — ShouldAurasBeSecret() returned true")
			end
		end
		return
	end

	-- ZONE-02 / D-05: Suppress on isFullUpdate (zone boundary / loading screen transient)
	if updateInfo and updateInfo.isFullUpdate then
		if ns.debugLogging then
			print("|cff00ccffTBT Debug|r: UNIT_AURA isFullUpdate suppressed")
		end
		return
	end

	-- D-02: Skip scan while preview timers are active
	if ns.previewActive then
		return
	end

	ns:ScanActiveTimersForCancellation()
end

function ns:ClearAuraBlock()
	local wasBlocked = ns.auraCheckBlocked
	ns.auraCheckBlocked = false
	if ns.debugLogging and wasBlocked then
		print("|cff00ccffTBT Debug|r: aura check unblocked")
	end
end
