local addonName, ns = ...

ns.activeTimers = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= addonName then
			return
		end

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

		print("|cff00ccffTerribleBuffTracker|r loaded. Type |cff00ff00/tbt|r to configure.")
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not ns.displayInitialized then
			ns.displayInitialized = true
			ns:InitDisplay()
		end
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if unit == "player" then
			ns:OnSpellCastSucceeded(spellID)
		end
	end
end)

SLASH_TERRIBLEBUFFTRACKER1 = "/tbt"
SlashCmdList["TERRIBLEBUFFTRACKER"] = function()
	ns:ToggleConfigUI()
end
