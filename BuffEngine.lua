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

function ns:InitBuffEngine()
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
	-- D-07: Save real timers before preview overwrites them (only on FIRST call)
	-- Re-entry guard: if previewActive is already true, savedPreviewTimers already holds real timers.
	if not ns.previewActive then
		wipe(savedPreviewTimers)
		for k, v in pairs(ns.activeTimers) do
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
			ns.activeTimers[spellID] = {
				spellID = spellID,
				expiresAt = now + entry.duration,
				startedAt = now,
				duration = entry.duration,
				icon = ns:GetSpellIcon(resolvedID),
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
