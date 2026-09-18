local addonName, ns = ...

ns.activeTimers = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

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
					displayMode = 0, -- 0=Icon And Name, 1=Icon Only, 2=Name Only
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
				if key == "bars" and cs.displayMode == nil then
					cs.displayMode = 0
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
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if unit == "player" then
			ns:OnSpellCastSucceeded(spellID)
		end
	elseif event == "UNIT_AURA" then
		local unit, updateInfo = ...
		if unit == "player" then
			ns:OnUnitAura(updateInfo)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns:ClearSecretGateLog()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		ns:ClearSecretGateLog()
	end
end)

SLASH_TERRIBLEBUFFTRACKER1 = "/tbt"
SLASH_TERRIBLEBUFFTRACKER2 = "/terriblebufftracker"
SlashCmdList["TERRIBLEBUFFTRACKER"] = function(msg)
	local cmd = msg and msg:lower():match("^(%S+)") or ""
	if cmd == "debug" then
		ns.debugLogging = not ns.debugLogging
		local state = ns.debugLogging and "|cff00ff00ON|r" or "|cffff6600OFF|r"
		print("|cff00ccffTBT|r: Debug logging " .. state)
	else
		ns:SelectTBTTab()
	end
end

---------------------------------------------------------------------
-- TOOL-01 (Phase 27.1) — append the hovered spell's numeric ID to every
-- spell tooltip in the game UI. The API is verified present on both
-- flavors at Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua
-- (Forever on the forever-beta branch of BigWigsMods/WoWUI, retail 12.1
-- in the local wow-ui-source clone), so one shared implementation serves
-- both with no branch (D-01). The guard below is an existence check on
-- the API symbol itself — a capability check, not a client-identity
-- check — so a future client lacking it degrades to a silent no-op
-- rather than a load error (D-05). No tooltip:Show() call is needed
-- here: ProcessInfo shows the tooltip on the line right after it runs
-- the post-calls.
--
-- Scope (user request, 2026-09-18): spells AND auras/buffs, never items.
-- Enum.TooltipDataType is an engine-side enum with no generated-doc entry
-- on either flavour, so a given member may simply not exist on Forever.
-- Registering per-member would then error at load, so instead we register
-- once for AllTypes and filter on tooltipData.type against an allow-set
-- built defensively — a member that does not exist contributes nothing
-- and costs nothing, and items are excluded by never being added.
--
-- Spell and aura IDs are labelled differently on purpose. TBT detects
-- casts via UNIT_SPELLCAST_SUCCEEDED, so the ID that belongs in the Add
-- dialog is the CAST spell's ID. A buff's own aura ID is frequently a
-- different number, and printing both under one label would invite adding
-- the wrong one and then wondering why the timer never fires.
---------------------------------------------------------------------

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local SPELL_TYPE = Enum.TooltipDataType.Spell
	local AURA_TYPES = {}
	for _, member in ipairs({ "UnitAura", "UnitBuff", "UnitDebuff" }) do
		local value = Enum.TooltipDataType[member]
		if value ~= nil then
			AURA_TYPES[value] = true
		end
	end

	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes or "ALL", function(tooltip, tooltipData)
		if not (tooltip and tooltip.AddLine and tooltipData) then
			return
		end
		local dataType = tooltipData.type
		local isSpell = SPELL_TYPE ~= nil and dataType == SPELL_TYPE
		local isAura = AURA_TYPES[dataType] == true
		if not (isSpell or isAura) then
			return
		end
		local id = tooltipData.id
		-- issecretvalue() FIRST, before any comparison or concatenation — it is safe on nil
		-- and on secrets, unlike everything below (same rule as BuffEngine.lua's aura read).
		-- In combat an aura tooltip's id arrives as a SECRET number: type() still reports
		-- "number", so a type check alone passes and gives false confidence, and the first
		-- ~= or .. against it throws once execution is tainted by this addon. Observed
		-- 2026-09-18 hovering a buff in combat.
		--
		-- Consequence, and it is a platform limit rather than something to work around: no
		-- ID line appears for a restricted aura while in combat. Out of combat it shows
		-- normally, and an aura whose spell is on Blizzard's never-secret allowlist still
		-- shows even in combat — which is why this gates on the VALUE being secret rather
		-- than on C_Secrets.ShouldAurasBeSecret(), a blanket combat gate that would
		-- needlessly suppress the allowlisted case too.
		if issecretvalue(id) or type(id) ~= "number" then
			return
		end
		tooltip:AddLine((isAura and "Aura spell ID: " or "Spell ID: ") .. id, 0.8, 0.8, 0.8)

		-- A spell and aura tooltip agree on this number because tooltipData.id IS the
		-- spell ID in both cases — one field, not two that coincide. The divergence that
		-- actually matters for tracking is a spell override: the ID a tooltip shows can
		-- differ from the base spell, and UNIT_SPELLCAST_SUCCEEDED may report the other
		-- one. Surface both sides whenever the client says they differ, so a mismatch is
		-- visible at hover time instead of showing up as a timer that never fires.
		-- Existence-checked (capability, not client identity) and pcall'd because these
		-- can reject an ID the client does not fully know. Tooltips fire on hover, not
		-- per frame, so this is not a hot path.
		local function RelatedID(fn)
			if type(fn) ~= "function" then
				return nil
			end
			local ok, other = pcall(fn, id)
			-- Same rule again, and it is needed independently: even with a non-secret id,
			-- these APIs can hand back a secret number, and `other ~= id` then throws. The
			-- pcall does NOT cover it — the call succeeds (ok == true) and the comparison
			-- after it is what raises. So screen the return value before comparing it.
			if not ok or issecretvalue(other) or type(other) ~= "number" then
				return nil
			end
			if other ~= id then
				return other
			end
			return nil
		end

		local base = RelatedID(C_Spell and C_Spell.GetBaseSpell)
		if base then
			tooltip:AddLine("Base spell ID: " .. base, 0.9, 0.7, 0.4)
		end
		local override = RelatedID(C_Spell and C_Spell.GetOverrideSpell)
		if override then
			tooltip:AddLine("Override spell ID: " .. override, 0.9, 0.7, 0.4)
		end
	end)
end
