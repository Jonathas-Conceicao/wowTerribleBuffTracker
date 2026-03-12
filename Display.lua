local _, ns = ...

-- CDM-matching dimensions
local BAR_HEIGHT = 30
local BAR_ICON_SIZE = 30
local BAR_WIDTH = 220
local BUFF_ICON_SIZE = 40
local UPDATE_INTERVAL = 0.05
local BAR_PADDING_OFFSET = -2
local ICON_PADDING_OFFSET = -4

local inCombat = false

local barPool = {}
local iconPool = {}
local barContainer = nil
local iconContainer = nil
local timeSinceUpdate = 0

-- Settings caches (snapshotted from CDM, refreshed during edit mode)
local cachedBarSettings = nil
local cachedIconSettings = nil

-- Reusable tables for UpdateDisplay (wiped each cycle to avoid allocations)
local barTimers = {}
local iconTimers = {}
local activeBarBySpell = {}
local barSlots = {}
local buffSlots = {}
local activeBySpell = {}

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
-- Frame creation — CDM CooldownViewerBuffBarItemTemplate
---------------------------------------------------------------------

local function CreateTimerBar(parent)
	local bar = CreateFrame("Frame", nil, parent or UIParent)
	bar:SetSize(BAR_WIDTH, BAR_HEIGHT)

	-- Icon inside the frame (left side, 30x30)
	bar.iconFrame = CreateFrame("Frame", nil, bar)
	bar.iconFrame:SetSize(BAR_ICON_SIZE, BAR_ICON_SIZE)
	bar.iconFrame:SetPoint("LEFT")
	bar.iconFrame:SetFrameLevel(bar:GetFrameLevel() + 2)

	bar.icon = bar.iconFrame:CreateTexture(nil, "ARTWORK")
	bar.icon:SetAllPoints()

	bar.iconMask = bar.iconFrame:CreateMaskTexture()
	bar.iconMask:SetAtlas("UI-HUD-CoolDownManager-Mask")
	bar.iconMask:SetAllPoints()
	bar.icon:AddMaskTexture(bar.iconMask)

	bar.iconOverlay = bar.iconFrame:CreateTexture(nil, "OVERLAY")
	bar.iconOverlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
	bar.iconOverlay:SetPoint("TOPLEFT", -6, 5)
	bar.iconOverlay:SetPoint("BOTTOMRIGHT", 6, -5)

	-- StatusBar (height 19, anchored to the right of icon)
	bar.statusBar = CreateFrame("StatusBar", nil, bar)
	bar.statusBar:SetHeight(19)
	bar.statusBar:SetPoint("LEFT", bar.iconFrame, "RIGHT", 2, 0)
	bar.statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	bar.statusBar:SetFrameLevel(bar:GetFrameLevel() + 1)
	bar.statusBar:SetMinMaxValues(0, 1)
	bar.statusBar:SetValue(0)

	-- Status bar fill texture (atlas set on the texture object directly)
	bar.fillTexture = bar.statusBar:CreateTexture(nil, "ARTWORK")
	bar.fillTexture:SetAtlas("UI-HUD-CoolDownManager-Bar")
	bar.statusBar:SetStatusBarTexture(bar.fillTexture)

	-- Bar background
	bar.barBG = bar.statusBar:CreateTexture(nil, "BACKGROUND")
	bar.barBG:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
	bar.barBG:SetPoint("TOPLEFT", -2, 2)
	bar.barBG:SetPoint("BOTTOMRIGHT", 4, -7)

	-- Pip at leading edge of fill
	bar.pip = bar.statusBar:CreateTexture(nil, "OVERLAY")
	bar.pip:SetAtlas("UI-HUD-CoolDownManager-Bar-Pip", true)
	bar.pip:SetPoint("CENTER", bar.fillTexture, "RIGHT", 0, -1)

	-- Name text (NumberFontNormal)
	bar.label = bar.statusBar:CreateFontString(nil, "OVERLAY")
	bar.label:SetFontObject(NumberFontNormal)
	bar.label:SetPoint("TOPLEFT", 5, 0)
	bar.label:SetPoint("BOTTOMRIGHT", -25, 0)
	bar.label:SetJustifyH("LEFT")
	bar.label:SetJustifyV("MIDDLE")
	bar.label:SetWordWrap(false)

	-- Duration text (NumberFontNormal)
	bar.time = bar.statusBar:CreateFontString(nil, "OVERLAY")
	bar.time:SetFontObject(NumberFontNormal)
	bar.time:SetPoint("RIGHT", -8, 0)
	bar.time:SetJustifyH("LEFT")

	-- Tooltips
	bar:EnableMouse(true)
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

---------------------------------------------------------------------
-- Frame creation — CDM CooldownViewerBuffIconItemTemplate
---------------------------------------------------------------------

local function CreateTimerIcon(parent)
	local frame = CreateFrame("Frame", nil, parent or UIParent)
	frame:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)

	-- Icon texture with CDM mask
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetAllPoints()

	frame.iconMask = frame:CreateMaskTexture()
	frame.iconMask:SetAtlas("UI-HUD-CoolDownManager-Mask")
	frame.iconMask:SetAllPoints()
	frame.icon:AddMaskTexture(frame.iconMask)

	-- Overlay
	frame.iconOverlay = frame:CreateTexture(nil, "OVERLAY")
	frame.iconOverlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
	frame.iconOverlay:SetPoint("TOPLEFT", -8, 7)
	frame.iconOverlay:SetPoint("BOTTOMRIGHT", 8, -7)

	-- Cooldown swipe
	frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	frame.cooldown:SetAllPoints(frame.icon)
	frame.cooldown:SetReverse(true)
	frame.cooldown:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	frame.cooldown:SetSwipeColor(0, 0, 0, 0.7)
	frame.cooldown:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
	frame.cooldown:SetDrawEdge(true)
	frame.cooldown:SetDrawSwipe(true)

	-- Tooltips
	frame:EnableMouse(true)
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
		barPool[index] = CreateTimerBar(barContainer)
	end
	return barPool[index]
end

local function GetIcon(index)
	if not iconPool[index] then
		iconPool[index] = CreateTimerIcon(iconContainer)
	end
	return iconPool[index]
end

---------------------------------------------------------------------
-- CDM helpers
---------------------------------------------------------------------

-- Read the full CDM bar frame width (icon is now inside our frame)
local function GetCDMBarWidth(viewer)
	for frame in viewer.itemFramePool:EnumerateActive() do
		return frame:GetWidth()
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
		iconPadding = v.iconPadding or 5,
		baseBarWidth = v.baseBarWidth or 186,
		barWidthScale = v.barWidthScale or 1,
		barWidth = GetCDMBarWidth(v) or ((v.baseBarWidth or 186) * (v.barWidthScale or 1)),
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
		iconPadding = v.iconPadding or 5,
		alpha = v:GetAlpha(),
		visibleSetting = v.visibleSetting or 0,
		hideWhenInactive = v.hideWhenInactive ~= false,
		timerShown = v.timerShown ~= false,
		tooltipsShown = v.tooltipsShown ~= false,
	}
end

---------------------------------------------------------------------
-- Settings snapshot
---------------------------------------------------------------------

local function SnapshotSettings()
	if ns.cdmBarViewer then
		cachedBarSettings = ReadBarSettings()
	end
	if ns.cdmIconViewer then
		cachedIconSettings = ReadIconSettings()
	end
end

---------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------

local function ShouldShow(visibleSetting, hasActiveTimers, hideWhenInactive, viewerIsEditing)
	if ns.configOpen or viewerIsEditing then
		return true
	end
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

local function ApplyBarStyle(bar, barWidth, settings)
	bar:SetScale(settings.iconScale)
	bar:SetWidth(barWidth)
	bar:SetAlpha(settings.alpha)

	local content = settings.barContent
	bar.statusBar:ClearAllPoints()
	bar.statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

	if content == 0 then
		-- Both: show icon + label + time
		bar.iconFrame:Show()
		bar.statusBar:SetPoint("LEFT", bar.iconFrame, "RIGHT", 2, 0)
		bar.label:Show()
		bar.time:SetShown(settings.timerShown)
	elseif content == 1 then
		-- Icon Only: show icon, hide label + time
		bar.iconFrame:Show()
		bar.statusBar:SetPoint("LEFT", bar.iconFrame, "RIGHT", 2, 0)
		bar.label:Hide()
		bar.time:Hide()
	elseif content == 2 then
		-- Name Only: hide icon, bar fills full width
		bar.iconFrame:Hide()
		bar.statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
		bar.label:Show()
		bar.time:SetShown(settings.timerShown)
	end
end

local function ApplyIconStyle(frame, settings)
	frame:SetScale(settings.iconScale)
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

	-- Bar container — mirrors CDM's GridLayoutFrame approach
	if ns.cdmBarViewer then
		barContainer = CreateFrame("Frame", nil, ns.cdmBarViewer)
		barContainer:SetPoint("TOPLEFT", ns.cdmBarViewer, "BOTTOMLEFT")
		barContainer:SetPoint("TOPRIGHT", ns.cdmBarViewer, "BOTTOMRIGHT")
		barContainer:SetHeight(1) -- resized dynamically in UpdateDisplay
		barContainer:Show()
	end

	-- Icon container — anchored adjacent to CDM icon viewer
	if ns.cdmIconViewer then
		iconContainer = CreateFrame("Frame", nil, ns.cdmIconViewer)
		iconContainer:SetAllPoints(ns.cdmIconViewer)
		iconContainer:Show()
	end

	-- Initial settings snapshot from CDM
	SnapshotSettings()

	-- Hook CDM layout changes to re-snapshot settings
	if ns.cdmBarViewer then
		HookViewerLayout(ns.cdmBarViewer, function()
			SnapshotSettings()
			ns:UpdateDisplay()
		end)
	end
	if ns.cdmIconViewer then
		HookViewerLayout(ns.cdmIconViewer, function()
			SnapshotSettings()
			ns:UpdateDisplay()
		end)
	end

	-- Edit mode exit — final snapshot after user saves
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		SnapshotSettings()
		ns:UpdateDisplay()
	end, ns)

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

	-- Split timers by display mode (reuse tables to avoid allocations)
	wipe(barTimers)
	wipe(iconTimers)
	for _, timer in ipairs(timers) do
		if timer.displayMode == "buff" then
			table.insert(iconTimers, timer)
		else
			table.insert(barTimers, timer)
		end
	end

	-- === Render bar timers ===
	if barContainer then
		local settings = cachedBarSettings
		if not settings then
			barContainer:Hide()
		else
			ns.barTooltipsShown = settings.tooltipsShown

			local hasActiveTimers = #barTimers > 0
			local barEditing = ns.cdmBarViewer.isEditing
			local visible = ShouldShow(settings.visibleSetting, hasActiveTimers, settings.hideWhenInactive, barEditing)

			if not visible then
				barContainer:Hide()
			else
				barContainer:Show()
				local barWidth = settings.barWidth
				-- CDM applies padding in container (unscaled) space between scaled children
				local padding = settings.iconPadding + BAR_PADDING_OFFSET

				-- Build bar slots: all tracked bar entries if showing inactive, else active only
				wipe(activeBarBySpell)
				for _, timer in ipairs(barTimers) do
					activeBarBySpell[timer.spellID] = timer
				end

				local showPlaceholders = not settings.hideWhenInactive or ns.configOpen or barEditing
				if showPlaceholders then
					wipe(barSlots)
					for _, entry in pairs(ns.db.trackedBuffs) do
						if entry.displayMode ~= "buff" and entry.enabled ~= false then
							table.insert(barSlots, entry)
						end
					end
					table.sort(barSlots, function(a, b)
						return a.spellID < b.spellID
					end)
				else
					wipe(barSlots)
					for _, t in ipairs(barTimers) do
						table.insert(barSlots, t)
					end
				end

				-- Layout bars inside container.
				-- Match CDM GridLayoutFrame: step = GetHeight() + padding (both
				-- unscaled). SetScale on each bar frame scales the offset naturally.
				local scale = settings.iconScale
				local step = BAR_HEIGHT + padding
				local topMargin = padding

				for i, slot in ipairs(barSlots) do
					local bar = GetBar(i)
					local timer = activeBarBySpell[slot.spellID]

					bar:ClearAllPoints()
					bar:SetPoint("TOPLEFT", barContainer, "TOPLEFT", 0, -(topMargin + (i - 1) * step))

					ApplyBarStyle(bar, barWidth, settings)

					if bar.spellID ~= slot.spellID then
						bar.spellID = slot.spellID
						bar.icon:SetTexture(timer and timer.icon or ns:GetSpellIcon(slot.spellID))
						bar.label:SetText(timer and timer.label or slot.label)
					end

					if timer then
						local remaining = timer.expiresAt - now
						local fraction = remaining / timer.duration

						if bar._lastDuration ~= timer.duration then
							bar._lastDuration = timer.duration
							bar.statusBar:SetMinMaxValues(0, timer.duration)
						end
						bar.statusBar:SetValue(remaining)
						local r, g, b = GetBarColor(fraction)
						bar.fillTexture:SetVertexColor(r, g, b)

						bar.pip:Show()

						bar.time:SetText(FormatTime(remaining))
					else
						-- Placeholder: empty bar, no fill, no timer
						if bar._lastDuration ~= nil then
							bar._lastDuration = nil
							bar.statusBar:SetMinMaxValues(0, 1)
						end
						bar.statusBar:SetValue(0)
						bar.pip:Hide()
						bar.time:SetText("")
					end

					bar:Show()
				end

				-- Size container in parent (unscaled) space.
				local n = #barSlots
				local totalHeight = n > 0 and topMargin * scale + (n * BAR_HEIGHT + (n - 1) * padding) * scale or 0
				barContainer:SetHeight(math.max(1, totalHeight))

				-- Hide unused bars
				for i = #barSlots + 1, #barPool do
					barPool[i]:Hide()
				end
			end
		end
	else
		for i = 1, #barPool do
			barPool[i]:Hide()
		end
	end

	-- === Render icon timers ===
	if not iconContainer then
		for i = 1, #iconPool do
			iconPool[i]:Hide()
		end
		return
	end

	local iconSettings = cachedIconSettings
	if not iconSettings then
		iconContainer:Hide()
		return
	end

	ns.iconTooltipsShown = iconSettings.tooltipsShown

	local hasActiveIcons = #iconTimers > 0
	local iconEditing = ns.cdmIconViewer.isEditing
	local iconVisible =
		ShouldShow(iconSettings.visibleSetting, hasActiveIcons, iconSettings.hideWhenInactive, iconEditing)

	if not iconVisible then
		iconContainer:Hide()
		return
	end

	iconContainer:Show()

	wipe(buffSlots)
	for _, entry in pairs(ns.db.trackedBuffs) do
		if entry.displayMode == "buff" and entry.enabled ~= false then
			table.insert(buffSlots, entry)
		end
	end
	table.sort(buffSlots, function(a, b)
		return a.spellID < b.spellID
	end)

	wipe(activeBySpell)
	for _, timer in ipairs(iconTimers) do
		activeBySpell[timer.spellID] = timer
	end

	-- Match CDM GridLayoutFrame: step = GetSize() + padding (unscaled).
	-- SetScale on each icon scales the offset naturally.
	local iconPadding = iconSettings.iconPadding + ICON_PADDING_OFFSET
	local step = BUFF_ICON_SIZE + iconPadding
	local topMargin = iconPadding
	local orientation = iconSettings.orientationSetting -- 0=Horizontal, 1=Vertical
	local direction = iconSettings.iconDirection -- 0=Right/Down, 1=Left/Up

	for slotIndex, entry in ipairs(buffSlots) do
		local icon = GetIcon(slotIndex)
		local timer = activeBySpell[entry.spellID]

		icon:ClearAllPoints()
		local offset = topMargin + (slotIndex - 1) * step

		if orientation == 0 then
			-- Horizontal
			if direction == 1 then
				-- Left: show on right side of CDM, grow rightward
				icon:SetPoint("TOPLEFT", ns.cdmIconViewer, "TOPRIGHT", offset, 0)
			else
				-- Right (default): show on left side of CDM, grow leftward
				icon:SetPoint("TOPRIGHT", ns.cdmIconViewer, "TOPLEFT", -offset, 0)
			end
		else
			-- Vertical
			if direction == 1 then
				-- Up
				icon:SetPoint("BOTTOMLEFT", ns.cdmIconViewer, "TOPLEFT", 0, offset)
			else
				-- Down (default)
				icon:SetPoint("TOPLEFT", ns.cdmIconViewer, "BOTTOMLEFT", 0, -offset)
			end
		end

		if timer then
			if icon.spellID ~= timer.spellID then
				icon.spellID = timer.spellID
				icon.icon:SetTexture(timer.icon)
			end
			ApplyIconStyle(icon, iconSettings)

			if icon._lastStart ~= timer.startedAt then
				icon._lastStart = timer.startedAt
				icon.cooldown:SetCooldown(timer.startedAt, timer.duration)
			end

			icon:Show()
		elseif not iconSettings.hideWhenInactive or ns.configOpen or iconEditing then
			-- Placeholder: show icon with no timer
			if icon.spellID ~= entry.spellID then
				icon.spellID = entry.spellID
				icon.icon:SetTexture(ns:GetSpellIcon(entry.spellID))
			end
			ApplyIconStyle(icon, iconSettings)

			if icon._lastStart then
				icon._lastStart = nil
				icon.cooldown:Clear()
			end

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
