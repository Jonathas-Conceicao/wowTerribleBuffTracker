local addonName, ns = ...

-- Hardcoded style matching Blizzard CDM bars
local BAR_HEIGHT = 28
local BAR_SPACING = 2
local ICON_SIZE = BAR_HEIGHT
local ICON_GAP = 0
local UPDATE_INTERVAL = 0.05
local ANCHOR_SIZE = 8

local BUFF_ICON_SIZE = 36
local BUFF_ICON_SPACING = 2

local BAR_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 18,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local barPool = {}
local iconPool = {}
local activeBars = {}
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

	-- Icon outside bar, left side
	bar.icon = bar:CreateTexture(nil, "OVERLAY")
	bar.icon:SetSize(ICON_SIZE, ICON_SIZE)
	bar.icon:SetPoint("RIGHT", bar, "LEFT", -ICON_GAP, 0)
	bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Label text
	bar.label = bar:CreateFontString(nil, "OVERLAY")
	bar.label:SetFont("Fonts\\ARIALN.TTF", 13, "OUTLINE")
	bar.label:SetPoint("LEFT", bar, "LEFT", 8, 0)
	bar.label:SetJustifyH("LEFT")
	bar.label:SetWordWrap(false)

	-- Time text
	bar.time = bar:CreateFontString(nil, "OVERLAY")
	bar.time:SetFont("Fonts\\ARIALN.TTF", 13, "OUTLINE")
	bar.time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	bar.time:SetJustifyH("RIGHT")

	-- Constrain label to not overlap time text
	bar.label:SetPoint("RIGHT", bar.time, "LEFT", -4, 0)

	bar:Hide()
	return bar
end

local function CreateTimerIcon(parent)
	local frame = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
	frame:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)
	frame:SetBackdrop(BAR_BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.7)
	frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	-- Spell icon texture
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 1, -1)
	frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Cooldown swipe overlay
	frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	frame.cooldown:SetAllPoints(frame.icon)
	frame.cooldown:SetDrawEdge(true)
	frame.cooldown:SetDrawSwipe(true)
	frame.cooldown:SetReverse(true)

	frame:Hide()
	return frame
end

---------------------------------------------------------------------
-- Pool getters
---------------------------------------------------------------------

local function GetBar(index)
	if not barPool[index] then
		barPool[index] = CreateTimerBar(ns.anchorFrame or UIParent)
	end
	return barPool[index]
end

local function GetIcon(index)
	if not iconPool[index] then
		iconPool[index] = CreateTimerIcon(ns.iconAnchorFrame or UIParent)
	end
	return iconPool[index]
end

---------------------------------------------------------------------
-- CDM helpers
---------------------------------------------------------------------

-- Read the bar-only width from CDM (frame width minus icon area)
local function GetCDMBarWidth(viewer)
	for frame in viewer.itemFramePool:EnumerateActive() do
		local frameW = frame:GetWidth()
		local frameH = frame:GetHeight()
		-- CDM frame includes icon; subtract icon area to get bar-only width
		return frameW - frameH - ICON_GAP + 3
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
-- Init
---------------------------------------------------------------------

function ns:RepositionTimers()
	if not ns.cdmMode then
		return
	end
	ns:UpdateDisplay()
end

function ns:InitDisplay()
	local barViewer = BuffBarCooldownViewer
	local iconViewer = BuffIconCooldownViewer

	ns.cdmBarViewer = (barViewer and barViewer.itemFramePool) and barViewer or nil
	ns.cdmIconViewer = (iconViewer and iconViewer.itemFramePool) and iconViewer or nil
	ns.cdmMode = (ns.cdmBarViewer ~= nil) or (ns.cdmIconViewer ~= nil)

	if ns.cdmMode then
		if ns.cdmBarViewer then
			HookViewerLayout(ns.cdmBarViewer, function()
				ns:RepositionTimers()
			end)
		end
		if ns.cdmIconViewer then
			HookViewerLayout(ns.cdmIconViewer, function()
				ns:RepositionTimers()
			end)
		end

		local updateFrame = CreateFrame("Frame", nil, UIParent)
		updateFrame:SetScript("OnUpdate", function(self, elapsed)
			timeSinceUpdate = timeSinceUpdate + elapsed
			if timeSinceUpdate < UPDATE_INTERVAL then
				return
			end
			timeSinceUpdate = 0
			ns:UpdateDisplay()
		end)

		ns.anchorFrame = nil
		ns.iconAnchorFrame = nil

		print("|cff00ccffTerribleBuffTracker|r: Attached to Cooldown Manager.")
	else
		ns.cdmMode = false
		ns:InitStandaloneDisplay()
	end
end

function ns:InitStandaloneDisplay()
	local anchor = CreateFrame("Frame", "TerribleBuffTrackerAnchor", UIParent)
	anchor:SetSize(ICON_SIZE + ICON_GAP + 200, ANCHOR_SIZE)
	anchor:SetMovable(true)
	anchor:EnableMouse(true)
	anchor:SetClampedToScreen(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.displayPoint = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	if ns.db.displayPoint then
		local p = ns.db.displayPoint
		anchor:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	else
		anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	end

	anchor:Show()
	ns.anchorFrame = anchor

	-- Icon anchor
	local iconAnchor = CreateFrame("Frame", "TerribleBuffTrackerIconAnchor", UIParent)
	iconAnchor:SetSize(BUFF_ICON_SIZE, ANCHOR_SIZE)
	iconAnchor:SetMovable(true)
	iconAnchor:EnableMouse(true)
	iconAnchor:SetClampedToScreen(true)
	iconAnchor:RegisterForDrag("LeftButton")
	iconAnchor:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	iconAnchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.iconDisplayPoint = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	if ns.db.iconDisplayPoint then
		local p = ns.db.iconDisplayPoint
		iconAnchor:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	else
		iconAnchor:SetPoint("LEFT", anchor, "RIGHT", 20, 0)
	end

	iconAnchor:Show()
	ns.iconAnchorFrame = iconAnchor

	anchor:SetScript("OnUpdate", function(self, elapsed)
		timeSinceUpdate = timeSinceUpdate + elapsed
		if timeSinceUpdate < UPDATE_INTERVAL then
			return
		end
		timeSinceUpdate = 0
		ns:UpdateDisplay()
	end)
end

---------------------------------------------------------------------
-- Display update
---------------------------------------------------------------------

function ns:UpdateDisplay()
	local timers = ns:GetActiveTimers()
	local now = GetTime()

	-- Split timers by display mode
	local barTimers = {}
	local iconTimers = {}
	for _, timer in ipairs(timers) do
		if timer.displayMode == "buff" then
			table.insert(iconTimers, timer)
		else
			table.insert(barTimers, timer)
		end
	end

	-- === Render bar timers ===
	if ns.cdmMode then
		local viewer = ns.cdmBarViewer
		if viewer then
			local barWidth = GetCDMBarWidth(viewer) or 186

			for i, timer in ipairs(barTimers) do
				local bar = GetBar(i)
				local remaining = timer.expiresAt - now
				local fraction = remaining / timer.duration

				bar:SetSize(barWidth, BAR_HEIGHT)
				bar:ClearAllPoints()

				if i == 1 then
					bar:SetPoint("TOPLEFT", viewer, "BOTTOMLEFT", ICON_SIZE + ICON_GAP, -BAR_SPACING)
				else
					local prevBar = GetBar(i - 1)
					bar:SetPoint("TOPLEFT", prevBar, "BOTTOMLEFT", 0, -BAR_SPACING)
				end

				bar.icon:SetTexture(timer.icon)
				bar.label:SetText(timer.label)

				local fillWidth = math.max(1, (barWidth - 8) * fraction)
				bar.fill:SetWidth(fillWidth)
				local r, g, b = GetBarColor(fraction)
				bar.fill:SetVertexColor(r, g, b, 0.8)
				local sr, sg, sb = math.min(r + 0.4, 1), math.min(g + 0.4, 1), math.min(b + 0.4, 1)
				bar.spark:SetVertexColor(sr, sg, sb, 1)
				bar.sparkGlow:SetVertexColor(sr, sg, sb, 0.8)

				bar.time:SetText(FormatTime(remaining))
				bar:Show()
			end
		end
	else
		-- Standalone bar mode
		local barWidth = 200

		for i, timer in ipairs(barTimers) do
			local bar = GetBar(i)
			local remaining = timer.expiresAt - now
			local fraction = remaining / timer.duration

			bar:ClearAllPoints()
			bar:SetPoint(
				"TOPLEFT",
				ns.anchorFrame,
				"BOTTOMLEFT",
				ICON_SIZE + ICON_GAP,
				-((i - 1) * (BAR_HEIGHT + BAR_SPACING))
			)

			bar.icon:SetTexture(timer.icon)
			bar.label:SetText(timer.label)

			local fillWidth = math.max(1, (barWidth - 8) * fraction)
			bar.fill:SetWidth(fillWidth)
			local r, g, b = GetBarColor(fraction)
			bar.fill:SetVertexColor(r, g, b, 0.8)
			local sr, sg, sb = math.min(r + 0.4, 1), math.min(g + 0.4, 1), math.min(b + 0.4, 1)
			bar.spark:SetVertexColor(sr, sg, sb, 1)
			bar.sparkGlow:SetVertexColor(sr, sg, sb, 0.8)

			bar.time:SetText(FormatTime(remaining))
			bar:Show()
		end
	end

	-- Hide unused bars
	for i = #barTimers + 1, #barPool do
		barPool[i]:Hide()
	end

	-- === Render icon timers (fixed horizontal slots) ===
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

	-- Determine anchor
	local iconAnchorFrame, iconAnchorPoint
	if ns.cdmMode and ns.cdmIconViewer then
		iconAnchorFrame = ns.cdmIconViewer
		iconAnchorPoint = "TOPRIGHT"
	else
		iconAnchorFrame = ns.iconAnchorFrame or UIParent
		iconAnchorPoint = "BOTTOMLEFT"
	end

	for slotIndex, entry in ipairs(buffSlots) do
		local icon = GetIcon(slotIndex)
		local timer = activeBySpell[entry.spellID]

		icon:ClearAllPoints()
		local xOffset = (slotIndex - 1) * (BUFF_ICON_SIZE + BUFF_ICON_SPACING)

		if iconAnchorPoint == "TOPRIGHT" then
			icon:SetPoint("TOPLEFT", iconAnchorFrame, "TOPRIGHT", BUFF_ICON_SPACING + xOffset, 0)
		else
			icon:SetPoint("TOPLEFT", iconAnchorFrame, iconAnchorPoint, xOffset, 0)
		end

		if timer then
			icon.icon:SetTexture(timer.icon)
			icon.cooldown:SetCooldown(timer.startedAt, timer.duration)

			local remaining = timer.expiresAt - now
			local fraction = remaining / timer.duration
			local r, g, b = GetBarColor(fraction)
			icon:SetBackdropBorderColor(r, g, b, 0.8)

			icon:Show()
		else
			icon:Hide()
		end
	end

	-- Hide extra icons
	for i = #buffSlots + 1, #iconPool do
		iconPool[i]:Hide()
	end

	activeBars = timers
end
