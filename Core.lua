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
			}
		end
		ns.db = TerribleBuffTrackerDB

		if not ns.db.trackedBuffs then
			ns.db.trackedBuffs = {}
		end

		if ns.db.tbtVisible == nil then
			ns.db.tbtVisible = true
		end

		if not ns.db.containerSettings then
			ns.db.containerSettings = {
				bars = {
					orientation = 1, -- 1=Vertical (bars stack vertically)
					growthDirection = 0, -- 0=Down
					scale = 100, -- percentage (100 = 1.0x), divided by 100 at read time
					padding = 5,
					barWidth = 100, -- percentage (100 = BAR_WIDTH default of 220px)
					opacity = 100, -- percentage (100 = fully opaque)
					visibility = 0, -- 0=Always Visible (show whenever buff is up)
					hideWhenInactive = true,
					showTimer = true,
					showTooltips = true,
				},
				buffs = {
					orientation = 0, -- 0=Horizontal
					growthDirection = 0, -- 0=Right
					scale = 100,
					padding = 5,
					opacity = 100,
					visibility = 0, -- 0=Always Visible
					hideWhenInactive = true,
					showTimer = true,
					showTooltips = true,
				},
			}
		end
		-- Backfill new fields on existing DBs
		for _, key in ipairs({ "bars", "buffs" }) do
			local cs = ns.db.containerSettings[key]
			if cs then
				if cs.hideWhenInactive == nil then
					cs.hideWhenInactive = true
				end
				if cs.showTimer == nil then
					cs.showTimer = true
				end
				if cs.showTooltips == nil then
					cs.showTooltips = true
				end
				if cs.opacity == nil then
					cs.opacity = 100
				end
			end
		end

		ns:InitBuffEngine()

		print(
			"|cff00ccffTerribleBuffTracker|r loaded. Type |cff00ff00/tbt|r or |cff00ff00/terriblebufftracker|r to open settings."
		)
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not ns.displayInitialized then
			ns.displayInitialized = true
			ns:InitEditModeFrames()
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
SLASH_TERRIBLEBUFFTRACKER2 = "/terriblebufftracker"
SlashCmdList["TERRIBLEBUFFTRACKER"] = function()
	ns:SelectTBTTab()
end
