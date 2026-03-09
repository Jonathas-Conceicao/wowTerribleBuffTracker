local addonName, ns = ...

-- Hardcoded style matching Blizzard CDM bars
local BAR_HEIGHT = 26
local BAR_ICON_SIZE = 28
local UPDATE_INTERVAL = 0.05
local BUFF_ICON_SIZE = 38

local inCombat = false

local BAR_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 18,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local barPool = {}
local iconPool = {}
local timeSinceUpdate = 0

local function FormatTime(remaining)
	if remaining >= 60 then
		local m = math.floor(remaining / 60)
		local s = math.floor(remaining % 60)
		return string.format("%d:%02d", m, s)
	else
		return string.format("%d", math.floor(remaining))
	end
end

local function GetBarColor(fraction)
	if fraction > 0.3 then
		return 0.2, 0.6, 1.0 -- blue
	elseif fraction > 0.1 then
		return 1.0, 0.8, 0.0 -- yellow
	else
		return 1.0, 0.2, 0.2 -- red
	end
end

---------------------------------------------------------------------
-- Frame creation — hardcoded CDM-matching style
---------------------------------------------------------------------

local function CreateTimerBar(parent)
	local bar = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
	bar:SetSize(200, BAR_HEIGHT)
	bar:SetBackdrop(BAR_BACKDROP)
	bar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
	bar:SetBackdropBorderColor(0.75, 0.75, 0.75, 0.9)

	-- Progress fill (inset to stay inside border)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	bar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar.fill:SetPoint("TOPLEFT", 4, -4)
	bar.fill:SetHeight(BAR_HEIGHT - 8)

	-- Spark (bright line at leading edge of fill)
	bar.spark = bar:CreateTexture(nil, "ARTWORK", nil, 1)
	bar.spark:SetTexture("Interface\\Buttons\\WHITE8X8")
	bar.spark:SetWidth(3)
	bar.spark:SetPoint("TOP", bar.fill, "TOPRIGHT", 0, -1)
	bar.spark:SetPoint("BOTTOM", bar.fill, "BOTTOMRIGHT", 0, 0)
	bar.spark:SetBlendMode("ADD")

	-- Spark glow (middle pixel that leaks over the border)
	bar.sparkGlow = bar:CreateTexture(nil, "OVERLAY", nil, 7)
	bar.sparkGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
	bar.sparkGlow:SetWidth(1)
	bar.sparkGlow:SetPoint("TOP", bar.fill, "TOPRIGHT", 0, 1)
	bar.sparkGlow:SetPoint("BOTTOM", bar.fill, "BOTTOMRIGHT", 0, -3)
	bar.sparkGlow:SetBlendMode("ADD")

	-- Icon frame outside bar, left side (backdrop border + rounded mask, same as buff icons)
	bar.iconFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	bar.iconFrame:SetSize(BAR_ICON_SIZE, BAR_ICON_SIZE)
	bar.iconFrame:SetPoint("RIGHT", bar, "LEFT", -1, 0)
	bar.iconFrame:SetBackdrop(BAR_BACKDROP)
	bar.iconFrame:SetBackdropColor(0, 0, 0, 0.7)
	bar.iconFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	bar.icon = bar.iconFrame:CreateTexture(nil, "ARTWORK")
	bar.icon:SetPoint("TOPLEFT", 3, -3)
	bar.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	bar.iconMask = bar.iconFrame:CreateMaskTexture()
	bar.iconMask:SetTexture(
		"Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
		"CLAMPTOBLACKADDITIVE",
		"CLAMPTOBLACKADDITIVE"
	)
	bar.iconMask:SetPoint("TOPLEFT", bar.icon, "TOPLEFT", -4, 4)
	bar.iconMask:SetPoint("BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", 4, -4)
	bar.icon:AddMaskTexture(bar.iconMask)

	-- Label text
	bar.label = bar:CreateFontString(nil, "OVERLAY")
	bar.label:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	bar.label:SetPoint("LEFT", bar, "LEFT", 9, 0)
	bar.label:SetJustifyH("LEFT")
	bar.label:SetWordWrap(false)

	-- Time text
	bar.time = bar:CreateFontString(nil, "OVERLAY")
	bar.time:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	bar.time:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
	bar.time:SetJustifyH("RIGHT")

	-- Constrain label to not overlap time text
	bar.label:SetPoint("RIGHT", bar.time, "LEFT", -4, 0)

	-- Extend hit area left to cover the icon frame outside the bar
	bar:SetHitRectInsets(-BAR_ICON_SIZE, 0, 0, 0)

	bar:SetScript("OnEnter", function(self)
		if not ns.barTooltipsShown then
			return
		end
		if self.spellID then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			GameTooltip:SetSpellByID(self.spellID)
			GameTooltip:Show()
		end
	end)
	bar:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	bar:Hide()
	return bar
end

local function CreateTimerIcon(parent)
	local frame = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
	frame:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)
	frame:SetBackdrop(BAR_BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.7)
	frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	-- Spell icon texture (rounded corners via oversized circular mask)
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 3, -3)
	frame.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	frame.iconMask = frame:CreateMaskTexture()
	frame.iconMask:SetTexture(
		"Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
		"CLAMPTOBLACKADDITIVE",
		"CLAMPTOBLACKADDITIVE"
	)
	frame.iconMask:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -4, 4)
	frame.iconMask:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 4, -4)
	frame.icon:AddMaskTexture(frame.iconMask)

	-- Cooldown swipe overlay
	frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	frame.cooldown:SetAllPoints(frame.icon)
	frame.cooldown:SetDrawEdge(true)
	frame.cooldown:SetDrawSwipe(true)
	frame.cooldown:SetReverse(true)

	frame:SetScript("OnEnter", function(self)
		if not ns.iconTooltipsShown then
			return
		end
		if self.spellID then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			GameTooltip:SetSpellByID(self.spellID)
			GameTooltip:Show()
		end
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	frame:Hide()
	return frame
end

---------------------------------------------------------------------
-- Pool getters
---------------------------------------------------------------------

local function GetBar(index)
	if not barPool[index] then
		barPool[index] = CreateTimerBar(ns.cdmBarViewer)
	end
	return barPool[index]
end

local function GetIcon(index)
	if not iconPool[index] then
		iconPool[index] = CreateTimerIcon(ns.cdmIconViewer)
	end
	return iconPool[index]
end

---------------------------------------------------------------------
-- CDM helpers
---------------------------------------------------------------------

-- Read the bar-only width from CDM (frame width minus icon area)
local function GetCDMBarWidth(viewer)
	for frame in viewer.itemFramePool:EnumerateActive() do
		-- CDM frame includes icon; subtract icon area to get bar-only width
		return frame:GetWidth() - frame:GetHeight() + 3
	end
	return nil
end

local function HookViewerLayout(viewer, callback)
	hooksecurefunc(viewer, "Layout", callback)
	if viewer.UpdateLayout then
		hooksecurefunc(viewer, "UpdateLayout", callback)
	end
	if viewer.RefreshLayout then
		hooksecurefunc(viewer, "RefreshLayout", callback)
	end
end

---------------------------------------------------------------------
-- CDM settings readers
---------------------------------------------------------------------

local function ReadBarSettings()
	local v = ns.cdmBarViewer
	return {
		iconScale = v.iconScale or 1,
		iconPadding = v.iconPadding or 2,
		baseBarWidth = v.baseBarWidth or 186,
		barWidthScale = v.barWidthScale or 1,
		alpha = v:GetAlpha(),
		visibleSetting = v.visibleSetting or 0,
		barContent = v.barContent or 0,
		hideWhenInactive = v.hideWhenInactive ~= false,
		timerShown = v.timerShown ~= false,
		tooltipsShown = v.tooltipsShown ~= false,
	}
end

local function ReadIconSettings()
	local v = ns.cdmIconViewer
	return {
		orientationSetting = v.orientationSetting or 0,
		iconDirection = v.iconDirection or 0,
		iconScale = v.iconScale or 1,
		iconPadding = v.iconPadding or 2,
		alpha = v:GetAlpha(),
		visibleSetting = v.visibleSetting or 0,
		hideWhenInactive = v.hideWhenInactive ~= false,
		timerShown = v.timerShown ~= false,
		tooltipsShown = v.tooltipsShown ~= false,
	}
end

local function ShouldShow(visibleSetting, hasActiveTimers, hideWhenInactive)
	if visibleSetting == 2 then
		return false
	end
	if visibleSetting == 1 and not inCombat then
		return false
	end
	if hideWhenInactive and not hasActiveTimers then
		return false
	end
	return true
end

---------------------------------------------------------------------
-- Style application helpers
---------------------------------------------------------------------

local function ApplyBarStyle(bar, scaledHeight, barWidth, settings)
	local scaledIconSize = BAR_ICON_SIZE * settings.iconScale
	local fontSize = math.max(8, math.floor(12 * settings.iconScale + 0.5))
	bar:SetSize(barWidth, scaledHeight)
	bar.iconFrame:SetSize(scaledIconSize, scaledIconSize)
	bar.fill:SetHeight(scaledHeight - 8)
	bar:SetAlpha(settings.alpha)
	bar.label:SetFont("Fonts\\ARIALN.TTF", fontSize, "OUTLINE")
	bar.time:SetFont("Fonts\\ARIALN.TTF", fontSize, "OUTLINE")
	-- Update hit rect to cover icon frame; no extension in name-only mode
	bar:SetHitRectInsets(settings.barContent == 2 and 0 or -(scaledIconSize + 1), 0, 0, 0)

	local content = settings.barContent
	if content == 0 then
		-- Both: show icon + label + time
		bar.iconFrame:Show()
		bar.label:Show()
		bar.time:SetShown(settings.timerShown)
	elseif content == 1 then
		-- Icon Only: show icon, hide label + time
		bar.iconFrame:Show()
		bar.label:Hide()
		bar.time:Hide()
	elseif content == 2 then
		-- Name Only: hide icon, show label + time
		bar.iconFrame:Hide()
		bar.label:Show()
		bar.time:SetShown(settings.timerShown)
	end
end

local function ApplyIconStyle(frame, scaledSize, settings)
	frame:SetSize(scaledSize, scaledSize)
	frame:SetAlpha(settings.alpha)
	frame.cooldown:SetDrawSwipe(settings.timerShown)
end

---------------------------------------------------------------------
-- Init
---------------------------------------------------------------------

function ns:InitDisplay()
	local barViewer = BuffBarCooldownViewer
	local iconViewer = BuffIconCooldownViewer

	ns.cdmBarViewer = (barViewer and barViewer.itemFramePool) and barViewer or nil
	ns.cdmIconViewer = (iconViewer and iconViewer.itemFramePool) and iconViewer or nil

	if not ns.cdmBarViewer and not ns.cdmIconViewer then
		print("|cff00ccffTerribleBuffTracker|r: Cooldown Manager not found. Addon disabled.")
		return
	end

	if ns.cdmBarViewer then
		HookViewerLayout(ns.cdmBarViewer, function()
			ns:UpdateDisplay()
		end)
	end
	if ns.cdmIconViewer then
		HookViewerLayout(ns.cdmIconViewer, function()
			ns:UpdateDisplay()
		end)
	end

	-- Combat tracking for visibility setting
	inCombat = InCombatLockdown()
	local combatFrame = CreateFrame("Frame", nil, UIParent)
	combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatFrame:SetScript("OnEvent", function(_, event)
		inCombat = (event == "PLAYER_REGEN_DISABLED")
		ns:UpdateDisplay()
	end)

	local updateFrame = CreateFrame("Frame", nil, UIParent)
	updateFrame:SetScript("OnUpdate", function(self, elapsed)
		timeSinceUpdate = timeSinceUpdate + elapsed
		if timeSinceUpdate < UPDATE_INTERVAL then
			return
		end
		timeSinceUpdate = 0
		ns:UpdateDisplay()
	end)

	print("|cff00ccffTerribleBuffTracker|r: Attached to Cooldown Manager.")
end

---------------------------------------------------------------------
-- Display update
---------------------------------------------------------------------

function ns:UpdateDisplay()
	local timers = ns:GetActiveTimers()
	local now = GetTime()

	-- Split timers by display mode, skip any that have already expired
	local barTimers = {}
	local iconTimers = {}
	for _, timer in ipairs(timers) do
		if timer.expiresAt > now then
			if timer.displayMode == "buff" then
				table.insert(iconTimers, timer)
			else
				table.insert(barTimers, timer)
			end
		end
	end

	-- === Render bar timers ===
	if ns.cdmBarViewer then
		local settings = ReadBarSettings()
		ns.barTooltipsShown = settings.tooltipsShown

		local hasActiveTimers = #barTimers > 0
		local visible = ShouldShow(settings.visibleSetting, hasActiveTimers, settings.hideWhenInactive)

		if not visible then
			for i = 1, #barPool do
				barPool[i]:Hide()
			end
		else
			local scaledHeight = BAR_HEIGHT * settings.iconScale
			local scaledIconSize = BAR_ICON_SIZE * settings.iconScale
			local baseBarWidth = (GetCDMBarWidth(ns.cdmBarViewer) or (settings.baseBarWidth * settings.barWidthScale))
				- 1
			local barWidth = baseBarWidth * settings.iconScale
			local xOffset = settings.barContent == 2 and 0 or (scaledIconSize + 1)

			-- Build bar slots: all tracked bar entries if showing inactive, else active only
			local activeBarBySpell = {}
			for _, timer in ipairs(barTimers) do
				activeBarBySpell[timer.spellID] = timer
			end

			local barSlots
			if not settings.hideWhenInactive then
				barSlots = {}
				for _, entry in pairs(ns.db.trackedBuffs) do
					if entry.displayMode ~= "buff" and entry.enabled ~= false then
						table.insert(barSlots, entry)
					end
				end
				table.sort(barSlots, function(a, b)
					return a.spellID < b.spellID
				end)
			else
				barSlots = barTimers
			end

			for i, slot in ipairs(barSlots) do
				local bar = GetBar(i)
				local timer = activeBarBySpell[slot.spellID]

				bar:ClearAllPoints()
				if i == 1 then
					bar:SetPoint("TOPLEFT", ns.cdmBarViewer, "BOTTOMLEFT", xOffset, -settings.iconPadding)
				else
					local prevBar = GetBar(i - 1)
					bar:SetPoint("TOPLEFT", prevBar, "BOTTOMLEFT", 0, -settings.iconPadding)
				end

				ApplyBarStyle(bar, scaledHeight, barWidth, settings)
				bar.spellID = slot.spellID

				if timer then
					local remaining = timer.expiresAt - now
					local fraction = remaining / timer.duration

					bar.icon:SetTexture(timer.icon)
					bar.label:SetText(timer.label)

					local fillWidth = math.max(1, (barWidth - 8) * fraction)
					bar.fill:SetWidth(fillWidth)
					bar.fill:Show()
					local r, g, b = GetBarColor(fraction)
					bar.fill:SetVertexColor(r, g, b, 0.8)
					local sr, sg, sb = math.min(r + 0.4, 1), math.min(g + 0.4, 1), math.min(b + 0.4, 1)
					bar.spark:SetVertexColor(sr, sg, sb, 1)
					bar.sparkGlow:SetVertexColor(sr, sg, sb, 0.8)
					bar.spark:Show()
					bar.sparkGlow:Show()

					bar.time:SetText(FormatTime(remaining))
				else
					-- Placeholder: empty bar, no fill, no timer
					bar.icon:SetTexture(ns:GetSpellIcon(slot.spellID))
					bar.label:SetText(slot.label)
					bar.fill:Hide()
					bar.spark:Hide()
					bar.sparkGlow:Hide()
					bar.time:SetText("")
				end

				bar:Show()
			end

			-- Hide unused bars
			for i = #barSlots + 1, #barPool do
				barPool[i]:Hide()
			end
		end
	else
		for i = 1, #barPool do
			barPool[i]:Hide()
		end
	end

	-- === Render icon timers ===
	local buffSlots = {}
	for spellID, entry in pairs(ns.db.trackedBuffs) do
		if entry.displayMode == "buff" and entry.enabled ~= false then
			table.insert(buffSlots, entry)
		end
	end
	table.sort(buffSlots, function(a, b)
		return a.spellID < b.spellID
	end)

	local activeBySpell = {}
	for _, timer in ipairs(iconTimers) do
		activeBySpell[timer.spellID] = timer
	end

	if not ns.cdmIconViewer then
		for i = 1, #iconPool do
			iconPool[i]:Hide()
		end
		return
	end

	local iconSettings = ReadIconSettings()
	ns.iconTooltipsShown = iconSettings.tooltipsShown

	local hasActiveIcons = #iconTimers > 0
	local iconVisible = ShouldShow(iconSettings.visibleSetting, hasActiveIcons, iconSettings.hideWhenInactive)

	if not iconVisible then
		for i = 1, #iconPool do
			iconPool[i]:Hide()
		end
		return
	end

	local scaledSize = BUFF_ICON_SIZE * iconSettings.iconScale
	local padding = iconSettings.iconPadding
	local orientation = iconSettings.orientationSetting -- 0=Horizontal, 1=Vertical
	local direction = iconSettings.iconDirection -- 0=Right/Down, 1=Left/Up

	for slotIndex, entry in ipairs(buffSlots) do
		local icon = GetIcon(slotIndex)
		local timer = activeBySpell[entry.spellID]

		icon:ClearAllPoints()
		local offset = slotIndex == 1 and 0 or ((slotIndex - 1) * (scaledSize + padding))

		if orientation == 0 then
			-- Horizontal (1px closer + 1px lower to account for CDM outer margin)
			if direction == 1 then
				-- Left: show on right side of CDM, grow rightward (outward)
				icon:SetPoint("TOPRIGHT", ns.cdmIconViewer, "TOPRIGHT", offset + scaledSize - 2, -2)
			else
				-- Right (default): show on left side of CDM, grow leftward (outward)
				icon:SetPoint("TOPLEFT", ns.cdmIconViewer, "TOPLEFT", -(offset + scaledSize) + 2, -2)
			end
		else
			-- Vertical (2px left + 2px closer to account for CDM outer margin)
			if direction == 1 then
				-- Up
				icon:SetPoint("BOTTOMLEFT", ns.cdmIconViewer, "TOPLEFT", -2, offset - 2)
			else
				-- Down (default)
				icon:SetPoint("TOPLEFT", ns.cdmIconViewer, "BOTTOMLEFT", -2, -offset + 2)
			end
		end

		if timer then
			ApplyIconStyle(icon, scaledSize, iconSettings)
			icon.spellID = timer.spellID

			icon.icon:SetTexture(timer.icon)
			icon.cooldown:SetCooldown(timer.startedAt, timer.duration)

			local remaining = timer.expiresAt - now
			local fraction = remaining / timer.duration
			local r, g, b = GetBarColor(fraction)
			icon:SetBackdropBorderColor(r, g, b, 0.8)

			icon:Show()
		elseif not iconSettings.hideWhenInactive then
			-- Placeholder: show icon with no timer
			ApplyIconStyle(icon, scaledSize, iconSettings)
			icon.spellID = entry.spellID

			icon.icon:SetTexture(ns:GetSpellIcon(entry.spellID))
			icon.cooldown:Clear()
			icon:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

			icon:Show()
		else
			icon:Hide()
		end
	end

	-- Hide extra icons
	for i = #buffSlots + 1, #iconPool do
		iconPool[i]:Hide()
	end
end
