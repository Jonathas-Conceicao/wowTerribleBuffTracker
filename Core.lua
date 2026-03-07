local addonName, ns = ...

ns.activeTimers = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end

        if not TerribleBuffTrackerDB then
            TerribleBuffTrackerDB = {
                trackedBuffs = {},
                displayPoint = nil,
            }
        end
        ns.db = TerribleBuffTrackerDB

        if not ns.db.trackedBuffs then
            ns.db.trackedBuffs = {}
        end

        ns:InitBuffEngine()
        ns:InitDisplay()

        print("|cff00ccffTerribleBuffTracker|r loaded. Type |cff00ff00/tbt|r to configure.")
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            ns:OnSpellCastSucceeded(spellID)
        end
    end
end)

SLASH_TERRIBLEBUFFTRACKER1 = "/tbt"
SlashCmdList["TERRIBLEBUFFTRACKER"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "reset" then
        ns.db.displayPoint = nil
        if ns.anchorFrame then
            ns.anchorFrame:ClearAllPoints()
            ns.anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end
        print("|cff00ccffTerribleBuffTracker|r: Display position reset.")
    else
        ns:ToggleConfigUI()
    end
end
