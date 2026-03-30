local _, ns = ...

function ns:InitBuffEngine()
	local CURRENT_SCHEMA_VERSION = 2
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
end

function ns:GetSpellIcon(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	if info and info.iconID then
		return info.iconID
	end
	return 134400 -- Question mark icon fallback
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
	local now = GetTime()
	ns.activeTimers = {}
	for spellID, entry in pairs(ns.db.trackedBuffs) do
		if entry.section ~= "hidden" then
			ns.activeTimers[spellID] = {
				spellID = spellID,
				expiresAt = now + entry.duration,
				startedAt = now,
				duration = entry.duration,
				icon = ns:GetSpellIcon(spellID),
				label = entry.label or ("Spell " .. spellID),
				section = entry.section or "bars",
			}
		end
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:ClearAllTimers()
	ns.activeTimers = {}
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end
