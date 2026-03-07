local addonName, ns = ...

function ns:InitBuffEngine()
    -- activeTimers is already initialized in Core.lua
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
    if not entry then return end

    local now = GetTime()
    ns.activeTimers[spellID] = {
        spellID = spellID,
        expiresAt = now + entry.duration,
        duration = entry.duration,
        icon = ns:GetSpellIcon(spellID),
        label = entry.label or ("Spell " .. spellID),
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

    ns.db.trackedBuffs[spellID] = {
        spellID = spellID,
        duration = duration,
        label = displayLabel,
    }

    print("|cff00ccffTerribleBuffTracker|r: Now tracking |cff00ff00" .. displayLabel .. "|r (ID: " .. spellID .. ", " .. duration .. "s).")
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
