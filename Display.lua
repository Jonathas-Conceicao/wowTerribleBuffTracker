local addonName, ns = ...

local BAR_WIDTH = 200
local BAR_HEIGHT = 20
local BAR_SPACING = 2
local ICON_SIZE = BAR_HEIGHT
local UPDATE_INTERVAL = 0.05
local ANCHOR_SIZE = 8

local BUFF_ICON_SIZE = 36
local BUFF_ICON_SPACING = 2

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
		return string.format("%.1f", remaining)
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

local function CreateTimerBar(parent)
	local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
	bar:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	bar:SetBackdropColor(0, 0, 0, 0.7)
	bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	-- Progress fill
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	bar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar.fill:SetPoint("TOPLEFT", 2, -2)
	bar.fill:SetHeight(BAR_HEIGHT - 4)

	-- Icon
	bar.icon = bar:CreateTexture(nil, "OVERLAY")
	bar.icon:SetSize(ICON_SIZE, ICON_SIZE)
	bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
	bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Label text
	bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.label:SetPoint("LEFT", bar, "LEFT", 4, 0)
	bar.label:SetJustifyH("LEFT")
	bar.label:SetWidth(BAR_WIDTH - 50)

	-- Time text
	bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.time:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar.time:SetJustifyH("RIGHT")

	bar:Hide()
	return bar
end

local function CreateTimerIcon(parent)
	local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	frame:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.7)
	frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

	-- Spell icon texture
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Cooldown swipe overlay
	frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	frame.cooldown:SetAllPoints(frame.icon)
	frame.cooldown:SetDrawEdge(true)
	frame.cooldown:SetDrawSwipe(true)

	frame:Hide()
	return frame
end

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

-- Find the bottommost active frame in a CDM viewer
local function GetCDMBottomFrame(viewer)
	local bottomFrame = nil
	local bottomY = math.huge

	for frame in viewer.itemFramePool:EnumerateActive() do
		if frame:IsShown() then
			local screenBottom = frame:GetBottom()
			if screenBottom and screenBottom < bottomY then
				bottomY = screenBottom
				bottomFrame = frame
			end
		end
	end

	return bottomFrame, bottomY
end

-- Find the rightmost active frame in a CDM viewer (for icon row)
local function GetCDMRightmostFrame(viewer)
	local rightFrame = nil
	local rightX = -math.huge

	for frame in viewer.itemFramePool:EnumerateActive() do
		if frame:IsShown() then
			local screenRight = frame:GetRight()
			if screenRight and screenRight > rightX then
				rightX = screenRight
				rightFrame = frame
			end
		end
	end

	return rightFrame, rightX
end

-- Get the width of CDM bars by checking an active bar frame
local function GetCDMBarWidth(viewer)
	for frame in viewer.itemFramePool:EnumerateActive() do
		if frame:IsShown() then
			return frame:GetWidth()
		end
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

function ns:RepositionTimers()
	if not ns.cdmMode then
		return
	end
	ns:UpdateDisplay()
end

function ns:InitDisplay()
	-- Check for CDM bar viewer
	local barViewer = BuffBarCooldownViewer
	local iconViewer = BuffIconCooldownViewer

	ns.cdmBarViewer = (barViewer and barViewer.itemFramePool) and barViewer or nil
	ns.cdmIconViewer = (iconViewer and iconViewer.itemFramePool) and iconViewer or nil
	ns.cdmMode = (ns.cdmBarViewer ~= nil) or (ns.cdmIconViewer ~= nil)

	if ns.cdmMode then
		-- Hook layout methods on both viewers
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

		-- Parent bars to UIParent (same as Blizzard), no draggable anchor needed
		local updateFrame = CreateFrame("Frame", nil, UIParent)
		updateFrame:SetScript("OnUpdate", function(self, elapsed)
			timeSinceUpdate = timeSinceUpdate + elapsed
			if timeSinceUpdate < UPDATE_INTERVAL then
				return
			end
			timeSinceUpdate = 0
			ns:UpdateDisplay()
		end)

		-- No anchor frames in CDM mode — positions relative to CDM viewers
		ns.anchorFrame = nil
		ns.iconAnchorFrame = nil

		print("|cff00ccffTerribleBuffTracker|r: Attached to Cooldown Manager.")
	else
		-- Standalone mode: draggable anchors
		ns.cdmMode = false
		ns:InitStandaloneDisplay()
	end
end

function ns:InitStandaloneDisplay()
	-- Bar anchor
	local anchor = CreateFrame("Frame", "TerribleBuffTrackerAnchor", UIParent)
	anchor:SetSize(ICON_SIZE + BAR_WIDTH + 2, ANCHOR_SIZE)
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

	-- Icon anchor (to the right of bar anchor)
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

	-- OnUpdate for timer ticking
	anchor:SetScript("OnUpdate", function(self, elapsed)
		timeSinceUpdate = timeSinceUpdate + elapsed
		if timeSinceUpdate < UPDATE_INTERVAL then
			return
		end
		timeSinceUpdate = 0
		ns:UpdateDisplay()
	end)
end

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
			local bottomBar = GetCDMBottomFrame(viewer)
			local cdmWidth = GetCDMBarWidth(viewer)
			if cdmWidth then
				BAR_WIDTH = cdmWidth
			end

			for i, timer in ipairs(barTimers) do
				local bar = GetBar(i)
				local remaining = timer.expiresAt - now
				local fraction = remaining / timer.duration

				bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
				bar.label:SetWidth(BAR_WIDTH - 50)
				bar:ClearAllPoints()

				if i == 1 then
					-- Anchor to viewer frame's bottom so position is stable
					bar:SetPoint("TOPLEFT", viewer, "BOTTOMLEFT", ICON_SIZE + 2, -BAR_SPACING)
				else
					local prevBar = GetBar(i - 1)
					bar:SetPoint("TOPLEFT", prevBar, "BOTTOMLEFT", 0, -BAR_SPACING)
				end

				bar.icon:SetTexture(timer.icon)
				bar.label:SetText(timer.label)

				local fillWidth = math.max(1, (BAR_WIDTH - 4) * fraction)
				bar.fill:SetWidth(fillWidth)
				local r, g, b = GetBarColor(fraction)
				bar.fill:SetVertexColor(r, g, b, 0.8)

				bar.time:SetText(FormatTime(remaining))
				bar:Show()
			end
		end
	else
		-- Standalone bar mode
		for i, timer in ipairs(barTimers) do
			local bar = GetBar(i)
			local remaining = timer.expiresAt - now
			local fraction = remaining / timer.duration

			bar:ClearAllPoints()
			bar:SetPoint(
				"TOPLEFT",
				ns.anchorFrame,
				"BOTTOMLEFT",
				ICON_SIZE + 2,
				-((i - 1) * (BAR_HEIGHT + BAR_SPACING))
			)

			bar.icon:SetTexture(timer.icon)
			bar.label:SetText(timer.label)

			local fillWidth = math.max(1, (BAR_WIDTH - 4) * fraction)
			bar.fill:SetWidth(fillWidth)
			local r, g, b = GetBarColor(fraction)
			bar.fill:SetVertexColor(r, g, b, 0.8)

			bar.time:SetText(FormatTime(remaining))
			bar:Show()
		end
	end

	-- Hide unused bars
	for i = #barTimers + 1, #barPool do
		barPool[i]:Hide()
	end

	-- === Render icon timers (fixed horizontal slots) ===
	-- Build sorted list of all buff-mode tracked entries for fixed slot positions
	local buffSlots = {}
	for spellID, entry in pairs(ns.db.trackedBuffs) do
		if entry.displayMode == "buff" and entry.enabled ~= false then
			table.insert(buffSlots, entry)
		end
	end
	table.sort(buffSlots, function(a, b)
		return a.spellID < b.spellID
	end)

	-- Build lookup of active timers by spellID
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

	-- Hide any extra icons beyond current slot count
	for i = #buffSlots + 1, #iconPool do
		iconPool[i]:Hide()
	end

	activeBars = timers
end
