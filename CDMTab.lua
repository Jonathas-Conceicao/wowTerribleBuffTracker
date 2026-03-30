local _, ns = ...

-- CDM Tab integration for TerribleBuffTracker.
-- CRITICAL: We must NEVER touch CooldownViewerSettings.TabButtons or call
-- SetDisplayMode with TBT strings — doing so taints CDM's secure code.

local ICON_PATH = "Interface\\AddOns\\TerribleBuffTracker\\tbt_icon_64x64"

---------------------------------------------------------------------
-- Preview control (reuses existing ns.configOpen flag from Display.lua)
---------------------------------------------------------------------

local function StartPreview()
	ns.configOpen = true
	ns:StartAllPreviewTimers()
end

local function StopPreview()
	ns.configOpen = false
	ns:ClearAllTimers()
end

---------------------------------------------------------------------
-- Section framework
---------------------------------------------------------------------

local SECTION_DEFS = {
	{ key = "bars", title = "Tracked Bars" },
	{ key = "buffs", title = "Tracked Buffs" },
	{ key = "hidden", title = "Not Displayed" },
	{ key = "suggested", title = "Suggested (WIP)" },
}

-- Valid drop targets (module-level constant — avoids per-frame table allocation in OnDragUpdate)
local VALID_DROP_SECTIONS = { "bars", "buffs", "hidden" }

-- Drag state (wiped with wipe() on EndDrag — never reassigned, per CLAUDE.md pattern)
local tbtDragState = {}

-- Forward declarations (BeginDrag/EndDrag used inside CreateIconFrame closures)
local BeginDrag, EndDrag

local function CreateIconFrame(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(38, 38)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(f)
	f.Icon = icon

	local highlight = f:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(f)
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	highlight:SetBlendMode("ADD")

	f:EnableMouse(true)

	f:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and self.spellID and self.sectionName ~= "suggested" then
			-- Don't drag from collapsed sections
			local section = ns.tbtSections and ns.tbtSections[self.sectionName]
			if section and section.collapsed then
				return
			end
			BeginDrag(self)
		end
	end)

	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		-- Show the real spell tooltip if possible, then append TBT info
		local hasSpellTooltip = false
		if self.spellID and C_Spell and C_Spell.GetSpellInfo then
			local info = C_Spell.GetSpellInfo(self.spellID)
			if info and info.name then
				GameTooltip:SetSpellByID(self.spellID)
				hasSpellTooltip = true
			end
		end
		local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[self.spellID]
		if entry then
			if not hasSpellTooltip then
				GameTooltip:SetText(entry.label, 1, 1, 1)
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Spell ID: " .. self.spellID, 0.8, 0.8, 0.8)
			GameTooltip:AddLine("TBT Duration: " .. entry.duration .. "s", 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end
	end)

	f:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	f:SetScript("OnMouseUp", function(self, button, upInside)
		if button == "RightButton" and upInside then
			local sectionName = self.sectionName
			if sectionName == "suggested" then
				return
			end
			MenuUtil.CreateContextMenu(self, function(_owner, rootDescription)
				if sectionName == "bars" then
					rootDescription:CreateButton("Move to Buffs", function()
						ns:SetBuffSection(self.spellID, "buffs")
						ns:RefreshTBTSections()
					end)
					rootDescription:CreateButton("Hide", function()
						ns:SetBuffSection(self.spellID, "hidden")
						ns:RefreshTBTSections()
					end)
				elseif sectionName == "buffs" then
					rootDescription:CreateButton("Move to Bars", function()
						ns:SetBuffSection(self.spellID, "bars")
						ns:RefreshTBTSections()
					end)
					rootDescription:CreateButton("Hide", function()
						ns:SetBuffSection(self.spellID, "hidden")
						ns:RefreshTBTSections()
					end)
				elseif sectionName == "hidden" then
					rootDescription:CreateButton("Move to Bars", function()
						ns:SetBuffSection(self.spellID, "bars")
						ns:RefreshTBTSections()
					end)
					rootDescription:CreateButton("Move to Buffs", function()
						ns:SetBuffSection(self.spellID, "buffs")
						ns:RefreshTBTSections()
					end)
				end
				rootDescription:CreateDivider()
				rootDescription:CreateButton("Remove", function()
					ns:RemoveTrackedBuff(self.spellID)
					ns:RefreshTBTSections()
				end)
			end)
		end
	end)

	return f
end

---------------------------------------------------------------------
-- Drag-and-drop state machine
---------------------------------------------------------------------

-- Ghost frame: created once on first drag, reused across all drags.
-- Parented to GetAppropriateTopLevelParent() at TOOLTIP strata.
-- Its own OnUpdate handles cursor following — tbtPanel OnUpdate is
-- used separately in Task 2 for section highlight tracking.
local tbtGhostFrame
local function GetOrCreateGhostFrame()
	if not tbtGhostFrame then
		local topLevel = GetAppropriateTopLevelParent()
		tbtGhostFrame = CreateFrame("Frame", nil, topLevel)
		tbtGhostFrame:SetSize(38, 38)
		tbtGhostFrame:SetFrameStrata("TOOLTIP")
		tbtGhostFrame:SetAlpha(0.5)
		local ghostIcon = tbtGhostFrame:CreateTexture(nil, "OVERLAY")
		ghostIcon:SetAllPoints(tbtGhostFrame)
		tbtGhostFrame.Icon = ghostIcon
		tbtGhostFrame:SetScript("OnUpdate", function(self)
			local x, y = GetScaledCursorPositionForFrame(topLevel)
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", topLevel, "BOTTOMLEFT", x, y)
		end)
	end
	return tbtGhostFrame
end

-- Reorder marker: CDM-style insertion line (UI-ChatFrame-DockHighlight, ADD blend)
-- Created once, repositioned per-frame during drag.
local tbtReorderMarker
local function GetOrCreateReorderMarker()
	if not tbtReorderMarker then
		tbtReorderMarker = CreateFrame("Frame", nil, UIParent)
		tbtReorderMarker:SetSize(8, 52)
		tbtReorderMarker:SetFrameStrata("TOOLTIP")
		local tex = tbtReorderMarker:CreateTexture(nil, "ARTWORK")
		tex:SetTexture("Interface\\ChatFrame\\UI-ChatFrame-DockHighlight")
		tex:SetSize(52, 52)
		tex:SetPoint("CENTER")
		tex:SetBlendMode("ADD")
		tbtReorderMarker.Texture = tex
		tbtReorderMarker:Hide()
	end
	return tbtReorderMarker
end

-- Delete zone highlight helper
local SetDeleteZoneHighlight

-- Full SectionHitTest implementation: point-in-rect using RegionUtil.GetSides.
-- Delete zone is checked first (highest priority per D-03).
-- Uses section.frame bounds (header + container) for a larger, more forgiving hit area.
local function SectionHitTest()
	local scale = GetAppropriateTopLevelParent():GetScale()
	local cursorX, cursorY = GetCursorPosition()
	cursorX, cursorY = cursorX / scale, cursorY / scale

	-- Delete zone first (highest priority)
	if ns.tbtDeleteZone and ns.tbtDeleteZone:IsShown() then
		local left, right, bottom, top = RegionUtil.GetSides(ns.tbtDeleteZone)
		if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
			return "delete"
		end
	end

	-- Valid sections (NOT suggested per D-04, NOT collapsed)
	for _, key in ipairs(VALID_DROP_SECTIONS) do
		local section = ns.tbtSections and ns.tbtSections[key]
		if section and section.frame and section.frame:IsShown() and not section.collapsed then
			local left, right, bottom, top = RegionUtil.GetSides(section.frame)
			if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
				return key
			end
		end
	end

	return nil
end

-- OnDragUpdate: per-frame reorder marker positioning during drag.
-- Shows a CDM-style insertion line next to the closest icon in the hovered section.
local function OnDragUpdate()
	if not tbtDragState.active then
		return
	end

	local scale = GetAppropriateTopLevelParent():GetScale()
	local cursorX, cursorY = GetCursorPosition()
	cursorX, cursorY = cursorX / scale, cursorY / scale

	local marker = GetOrCreateReorderMarker()

	-- Check delete zone first
	local overDelete = false
	if ns.tbtDeleteZone and ns.tbtDeleteZone:IsShown() then
		local left, right, bottom, top = RegionUtil.GetSides(ns.tbtDeleteZone)
		if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
			overDelete = true
		end
	end

	SetDeleteZoneHighlight(overDelete)

	if overDelete then
		marker:Hide()
		return
	end

	-- Find hovered section
	local hoveredSection = nil
	for _, key in ipairs(VALID_DROP_SECTIONS) do
		local section = ns.tbtSections and ns.tbtSections[key]
		if section and section.frame and section.frame:IsShown() and not section.collapsed then
			local left, right, bottom, top = RegionUtil.GetSides(section.frame)
			if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
				hoveredSection = key
				break
			end
		end
	end

	if not hoveredSection then
		marker:Hide()
		return
	end

	-- Find closest icon in the hovered section and position marker
	local section = ns.tbtSections[hoveredSection]
	local bestItem = nil
	local bestDist = math.huge
	for item in section.itemPool:EnumerateActive() do
		if item.spellID and item:IsShown() then
			local left, right, bottom, top = RegionUtil.GetSides(item)
			local cx, cy = (left + right) / 2, (bottom + top) / 2
			local dist = math.abs(cursorX - cx) + math.abs(cursorY - cy)
			if dist < bestDist then
				bestDist = dist
				bestItem = item
			end
		end
	end

	if bestItem then
		marker:ClearAllPoints()
		local left, right = RegionUtil.GetSides(bestItem)
		local centerX = (left + right) / 2
		if cursorX > centerX then
			marker:SetPoint("CENTER", bestItem, "RIGHT", 4, 0)
		else
			marker:SetPoint("CENTER", bestItem, "LEFT", -4, 0)
		end
		marker:SetParent(section.container)
		marker:SetFrameLevel(section.container:GetFrameLevel() + 10)
		marker:Show()
	else
		-- Empty section or section with only delete zone — anchor after delete zone if present
		marker:ClearAllPoints()
		if hoveredSection == "hidden" and ns.tbtDeleteZone and ns.tbtDeleteZone:IsShown() then
			marker:SetPoint("CENTER", ns.tbtDeleteZone, "RIGHT", 4, 0)
		else
			marker:SetPoint("LEFT", section.container, "LEFT", 4, 0)
		end
		marker:SetParent(section.container)
		marker:SetFrameLevel(section.container:GetFrameLevel() + 10)
		marker:Show()
	end
end

SetDeleteZoneHighlight = function(active)
	if ns.tbtDeleteZone and ns.tbtDeleteZone.dragHighlight then
		if active then
			ns.tbtDeleteZone.dragHighlight:Show()
		else
			ns.tbtDeleteZone.dragHighlight:Hide()
		end
	end
end

BeginDrag = function(iconFrame)
	if tbtDragState.active then
		return
	end

	tbtDragState.active = true
	tbtDragState.spellID = iconFrame.spellID
	tbtDragState.originalSection = iconFrame.sectionName

	-- Show ghost at cursor
	local ghost = GetOrCreateGhostFrame()
	ghost.Icon:SetTexture(ns:GetSpellIcon(iconFrame.spellID))
	ghost:Show()

	-- Activate per-frame highlight tracking (nil'd in EndDrag — no idle cost)
	ns.tbtPanel:SetScript("OnUpdate", OnDragUpdate)

	-- Register GLOBAL_MOUSE_UP on tbtPanel for session termination
	ns.tbtPanel:RegisterEvent("GLOBAL_MOUSE_UP")

	PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
end

-- Determine reorder position: find the icon closest to cursor in the target section
-- Returns a fractional layoutOrder that places the dragged item at the cursor position.
-- Uses X.5 values to guarantee correct sorting before the renumber pass.
local function GetDropLayoutOrder(sectionKey)
	local section = ns.tbtSections and ns.tbtSections[sectionKey]
	if not section then
		return nil
	end

	local scale = GetAppropriateTopLevelParent():GetScale()
	local cursorX, cursorY = GetCursorPosition()
	cursorX, cursorY = cursorX / scale, cursorY / scale

	-- Collect and sort visible items by layoutIndex
	local items = {}
	for item in section.itemPool:EnumerateActive() do
		if item.spellID then
			table.insert(items, item)
		end
	end
	table.sort(items, function(a, b)
		return (a.layoutIndex or 0) < (b.layoutIndex or 0)
	end)

	if #items == 0 then
		return 1
	end

	-- Find the closest item and determine before/after
	local bestIdx = 1
	local bestDist = math.huge
	for i, item in ipairs(items) do
		local left, right, bottom, top = RegionUtil.GetSides(item)
		local cx, cy = (left + right) / 2, (bottom + top) / 2
		local dist = math.abs(cursorX - cx) + math.abs(cursorY - cy)
		if dist < bestDist then
			bestDist = dist
			bestIdx = i
		end
	end

	local bestItem = items[bestIdx]
	local left, right = RegionUtil.GetSides(bestItem)
	local centerX = (left + right) / 2

	if cursorX > centerX then
		-- Insert AFTER this item: use value between this and next
		-- e.g., item at index 2 → return 2.5 (goes between 2 and 3)
		return bestIdx + 0.5
	else
		-- Insert BEFORE this item: use value between prev and this
		-- e.g., item at index 2 → return 1.5 (goes between 1 and 2)
		return bestIdx - 0.5
	end
end

EndDrag = function(commit)
	if not tbtDragState.active then
		return
	end

	-- Hide ghost immediately
	GetOrCreateGhostFrame():Hide()

	-- Clear OnUpdate for section highlights
	ns.tbtPanel:SetScript("OnUpdate", nil)

	-- Hide reorder marker and delete zone highlight
	GetOrCreateReorderMarker():Hide()
	SetDeleteZoneHighlight(false)

	-- Unregister session event
	ns.tbtPanel:UnregisterEvent("GLOBAL_MOUSE_UP")

	if commit then
		local result = SectionHitTest()
		if result == "delete" then
			local spellID = tbtDragState.spellID
			wipe(tbtDragState)
			ns:RemoveTrackedBuff(spellID)
			ns:RefreshTBTSections()
			PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
			return
		elseif result and result ~= "suggested" then
			local spellID = tbtDragState.spellID
			local entry = ns.db.trackedBuffs[spellID]
			if entry then
				local targetSection = result
				local dropOrder = GetDropLayoutOrder(targetSection)

				-- Move to new section if different
				if targetSection ~= tbtDragState.originalSection then
					ns:SetBuffSection(spellID, targetSection)
				end

				-- Set fractional layoutOrder then renumber to integers
				-- The fractional value (e.g., 2.5) sorts correctly between items
				if dropOrder and entry then
					entry.layoutOrder = dropOrder
					-- Collect all entries in target section, sort, renumber 1..N
					local sectionEntries = {}
					for sid, e in pairs(ns.db.trackedBuffs) do
						if e.section == targetSection then
							table.insert(sectionEntries, { spellID = sid, order = e.layoutOrder or 0 })
						end
					end
					table.sort(sectionEntries, function(a, b)
						if a.order == b.order then
							return a.spellID < b.spellID -- stable tiebreak
						end
						return a.order < b.order
					end)
					for i, se in ipairs(sectionEntries) do
						ns.db.trackedBuffs[se.spellID].layoutOrder = i
					end
				end

				wipe(tbtDragState)
				ns:RefreshTBTSections()
				PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
				return
			end
		end
		-- nil or "suggested" → cancel silently (D-04, D-05)
	end

	wipe(tbtDragState)
end

local function BuildTBTSection(parent, def)
	local section = {
		key = def.key,
		collapsed = false,
	}

	section.frame = CreateFrame("Frame", nil, parent)
	-- Fixed width matching CDM's CooldownViewerSettingsCategoryTemplate (344px)
	section.frame:SetWidth(344)

	section.header = CreateFrame("Button", nil, section.frame, "ListHeaderThreeSliceTemplate")
	section.header:SetSize(0, 22)
	section.header:SetPoint("TOPLEFT", section.frame, "TOPLEFT")
	section.header:SetPoint("TOPRIGHT", section.frame, "TOPRIGHT")
	section.header:SetTitleColor(false, NORMAL_FONT_COLOR)
	section.header:SetTitleColor(true, NORMAL_FONT_COLOR)
	section.header:SetHeaderText(def.title)
	section.header:UpdateCollapsedState(false)
	section.header:SetClickHandler(function(_hdr, button)
		if button == "LeftButton" then
			section.collapsed = not section.collapsed
			section.container:SetShown(not section.collapsed)
			section.header:UpdateCollapsedState(section.collapsed)
			ns:UpdateSectionHeight(section)
			ns:UpdateScrollChildHeight()
		end
	end)

	section.container = CreateFrame("Frame", nil, section.frame, "GridLayoutFrame")
	-- CDM exact: container 315px wide, 13px left indent, 15px below header
	section.container:SetPoint("TOPLEFT", section.header, "BOTTOMLEFT", 13, -15)
	section.container:SetWidth(315)
	section.container:SetHeight(46) -- initial: one row (38px icon + 8px padding)
	section.container.childXPadding = 8
	section.container.childYPadding = 8
	section.container.isHorizontal = true
	section.container.stride = 7
	section.container.layoutFramesGoingRight = true
	section.container.layoutFramesGoingUp = false
	section.container.alwaysUpdateLayout = true

	section.itemPool = CreateObjectPool(function(pool)
		return CreateIconFrame(section.container)
	end, function(pool, frame)
		frame:Hide()
		frame.spellID = nil
		frame.sectionName = nil
		frame.layoutIndex = nil
	end)

	-- No section-wide highlight — CDM uses a ReorderMarker (insertion line) instead

	return section
end

function ns:UpdateSectionHeight(section)
	if section.collapsed then
		section.frame:SetHeight(22) -- header only
	else
		section.frame:SetHeight(22 + 15 + section.container:GetHeight())
	end
end

function ns:UpdateScrollChildHeight()
	if not ns.tbtSections then
		return
	end
	local total = 0
	local numSections = #SECTION_DEFS
	for i, def in ipairs(SECTION_DEFS) do
		local section = ns.tbtSections[def.key]
		if section then
			total = total + section.frame:GetHeight()
			if i < numSections then
				total = total + 18 -- CDM exact: 18px gap between categories
			end
		end
	end
	ns.tbtScrollChild:SetHeight(total)
end

function ns:RefreshTBTSections()
	if not ns.tbtSections then
		return
	end
	for _, def in ipairs(SECTION_DEFS) do
		local section = ns.tbtSections[def.key]
		if not section then
			break
		end
		section.itemPool:ReleaseAll()

		-- Delete zone: permanent first slot in Not Displayed section (visual only in Phase 4)
		if def.key == "hidden" then
			ns.tbtDeleteZone = ns.tbtDeleteZone
				or (function()
					local zone = CreateFrame("Frame", nil, section.container)
					zone:SetSize(38, 38)

					local bg = zone:CreateTexture(nil, "BACKGROUND")
					bg:SetAllPoints(zone)
					bg:SetColorTexture(0.8, 0.1, 0.1, 0.4)

					local icon = zone:CreateTexture(nil, "OVERLAY")
					icon:SetAtlas("common-icon-redx")
					icon:SetSize(24, 24)
					icon:SetPoint("CENTER")

					return zone
				end)()
			ns.tbtDeleteZone.layoutIndex = 0
			ns.tbtDeleteZone:Show()

			-- Drag highlight overlay for delete zone (created once, distinct red per D-08)
			if not ns.tbtDeleteZone.dragHighlight then
				local dhl = ns.tbtDeleteZone:CreateTexture(nil, "OVERLAY")
				dhl:SetAllPoints(ns.tbtDeleteZone)
				dhl:SetColorTexture(1, 0, 0, 0.4)
				dhl:SetBlendMode("ADD")
				dhl:Hide()
				ns.tbtDeleteZone.dragHighlight = dhl
			end
		end

		if def.key ~= "suggested" then
			-- Collect and sort by layoutOrder for within-section ordering
			local sorted = {}
			for spellID, entry in pairs(ns.db.trackedBuffs) do
				if entry.section == def.key then
					table.insert(sorted, { spellID = spellID, order = entry.layoutOrder or 0 })
				end
			end
			table.sort(sorted, function(a, b)
				return a.order < b.order
			end)
			for i, info in ipairs(sorted) do
				local item = section.itemPool:Acquire()
				item.spellID = info.spellID
				item.Icon:SetTexture(ns:GetSpellIcon(info.spellID))
				item.sectionName = def.key
				item.layoutIndex = i -- sequential for GridLayoutFrame
				item:Show()
			end
		end

		section.container:Layout()
		ns:UpdateSectionHeight(section)
	end
	ns:UpdateScrollChildHeight()
end

local function CreateAddDialog()
	-- Simple dialog parented to UIParent at DIALOG strata so it renders
	-- above everything including CDM settings window.
	local dialog = CreateFrame("Frame", "TBTAddBuffDialog", UIParent, "BackdropTemplate")
	dialog:SetSize(220, 170)
	dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(200)
	dialog:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	dialog:SetBackdropColor(0, 0, 0, 1)
	dialog:Hide()
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

	table.insert(UISpecialFrames, "TBTAddBuffDialog")

	-- Title
	local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetText("Add Tracked Buff")
	title:SetPoint("TOP", dialog, "TOP", 0, -12)

	-- Spell ID
	local spellIdLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	spellIdLabel:SetText("Spell ID:")
	spellIdLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -38)

	local spellIdBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	spellIdBox:SetSize(180, 22)
	spellIdBox:SetPoint("TOPLEFT", spellIdLabel, "BOTTOMLEFT", 0, -4)
	spellIdBox:SetNumeric(true)
	spellIdBox:SetMaxLetters(10)
	spellIdBox:SetAutoFocus(false)

	-- Duration
	local durationLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	durationLabel:SetText("Duration (seconds):")
	durationLabel:SetPoint("TOPLEFT", spellIdBox, "BOTTOMLEFT", 0, -10)

	local durationBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	durationBox:SetSize(180, 22)
	durationBox:SetPoint("TOPLEFT", durationLabel, "BOTTOMLEFT", 0, -4)
	durationBox:SetMaxLetters(6)
	durationBox:SetAutoFocus(false)

	-- Error label
	local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontRed")
	errorLabel:SetPoint("TOP", durationBox, "BOTTOM", 0, -4)
	errorLabel:SetText("")

	-- Add button
	local addBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	addBtn:SetSize(80, 22)
	addBtn:SetText("Add")
	addBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 12)
	addBtn:SetScript("OnClick", function()
		local spellID = spellIdBox:GetNumber()
		if not spellID or spellID <= 0 then
			errorLabel:SetText("Invalid Spell ID")
			return
		end
		local duration = tonumber(durationBox:GetText())
		if not duration or duration <= 0 then
			errorLabel:SetText("Invalid Duration")
			return
		end
		ns:AddTrackedBuff(spellID, duration)
		ns:RefreshTBTSections()
		ns:StartAllPreviewTimers()
		dialog:Hide()
	end)

	-- Cancel button
	local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancelBtn:SetSize(80, 22)
	cancelBtn:SetText("Cancel")
	cancelBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 12)
	cancelBtn:SetScript("OnClick", function()
		dialog:Hide()
	end)

	-- Tab between fields
	spellIdBox:SetScript("OnTabPressed", function()
		durationBox:SetFocus()
	end)
	durationBox:SetScript("OnTabPressed", function()
		spellIdBox:SetFocus()
	end)
	-- Enter confirms
	durationBox:SetScript("OnEnterPressed", function()
		addBtn:Click()
	end)

	dialog.spellIdBox = spellIdBox
	dialog.durationBox = durationBox
	dialog.errorLabel = errorLabel

	return dialog
end

function ns:BuildAllSections()
	ns.tbtSections = {}
	local prevFrame = nil
	for _, def in ipairs(SECTION_DEFS) do
		local section = BuildTBTSection(ns.tbtScrollChild, def)
		-- CDM exact: 18px vertical gap between categories, TOPLEFT only (fixed width)
		if prevFrame then
			section.frame:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -18)
		else
			section.frame:SetPoint("TOPLEFT", ns.tbtScrollChild, "TOPLEFT", 0, 0)
		end
		ns.tbtSections[def.key] = section
		prevFrame = section.frame
	end

	-- Create the Add Buff dialog (shared modal)
	ns.tbtAddDialog = CreateAddDialog()

	-- Add Buff square icon in Suggested section (skill-like appearance)
	local suggestedSection = ns.tbtSections.suggested
	local addSquare = CreateFrame("Frame", nil, suggestedSection.container)
	addSquare:SetSize(38, 38)
	addSquare.layoutIndex = 1
	addSquare:EnableMouse(true)

	-- Green-tinted background
	local addBg = addSquare:CreateTexture(nil, "BACKGROUND")
	addBg:SetAllPoints(addSquare)
	addBg:SetColorTexture(0.1, 0.6, 0.1, 0.4)

	-- Plus icon
	local addIcon = addSquare:CreateTexture(nil, "OVERLAY")
	addIcon:SetAtlas("communities-chat-icon-plus")
	addIcon:SetSize(24, 24)
	addIcon:SetPoint("CENTER")

	-- Highlight on hover
	local addHighlight = addSquare:CreateTexture(nil, "HIGHLIGHT")
	addHighlight:SetAllPoints(addSquare)
	addHighlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	addHighlight:SetBlendMode("ADD")

	-- Tooltip
	addSquare:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Add Buff")
		GameTooltip:AddLine("Click to track a new spell", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	addSquare:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Click opens dialog
	addSquare:SetScript("OnMouseUp", function(_, button, upInside)
		if button == "LeftButton" and upInside then
			local dlg = ns.tbtAddDialog
			dlg.spellIdBox:SetText("")
			dlg.durationBox:SetText("")
			dlg.errorLabel:SetText("")
			dlg:Show()
			dlg.spellIdBox:SetFocus()
		end
	end)
	addSquare:Show()
	suggestedSection.container:Layout()
end

---------------------------------------------------------------------
-- Tab init
---------------------------------------------------------------------

function ns:InitCDMTab()
	local tab = TBTSettingsTab

	-- Set icon via SetTexture (not SetAtlas — our icon is a file, not an atlas)
	tab.Icon:SetTexture(ICON_PATH)
	tab.Icon:SetSize(30, 30)

	-- Store atlas fields so SetChecked (from LargeSideTabButtonTemplate) works
	-- SidePanelTabButtonMixin:SetChecked reads activeAtlas/inactiveAtlas
	-- but since we use SetTexture, override SetChecked to avoid SetAtlas calls
	tab.activeAtlas = nil
	tab.inactiveAtlas = nil

	-- Override SetChecked to use SetTexture instead of SetAtlas
	function tab:SetChecked(checked)
		self.Icon:SetTexture(ICON_PATH)
		if self.SelectedTexture then
			self.SelectedTexture:SetShown(checked)
		end
	end

	-- Tooltip
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("TBT Buffs")
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Create TBT content panel — plain frame matching CDM's content area
	-- CDM's CooldownScroll has NO backdrop — it's a plain ScrollFrame
	-- inside the ButtonFrameTemplate inset. We match that: no backdrop.
	local panel = CreateFrame("ScrollFrame", "TBTSettingsPanel", CooldownViewerSettings, "ScrollFrameTemplate")
	panel:SetPoint("TOPLEFT", CooldownViewerSettings, "TOPLEFT", 17, -72)
	panel:SetPoint("BOTTOMRIGHT", CooldownViewerSettings, "BOTTOMRIGHT", -30, 29)
	panel:SetFrameLevel(CooldownViewerSettings:GetFrameLevel() + 10)

	-- ScrollBar config matching CDM's CooldownScroll
	if panel.ScrollBar and panel.ScrollBar.SetHideIfUnscrollable then
		panel.ScrollBar:SetHideIfUnscrollable(false)
	end

	-- Scroll child fills panel width minus scroll bar (17px)
	local scrollChild = CreateFrame("Frame", nil, panel)
	scrollChild:SetHeight(1)
	panel:SetScrollChild(scrollChild)

	-- Dynamically size scroll child to panel width on show
	panel:HookScript("OnSizeChanged", function(self)
		local w = self:GetWidth()
		if w > 17 then
			scrollChild:SetWidth(w - 17)
		end
	end)
	-- Also set initial width after a frame (panel has no width until shown)
	panel:HookScript("OnShow", function(self)
		local w = self:GetWidth()
		if w > 17 then
			scrollChild:SetWidth(w - 17)
		end
	end)
	scrollChild:SetWidth(1) -- placeholder until OnShow fires

	panel:Hide()
	ns.tbtPanel = panel
	ns.tbtScrollChild = scrollChild

	-- GLOBAL_MOUSE_UP handler for drag lifecycle.
	-- OnEvent is set once here (not in BeginDrag) so it's registered before
	-- any event fires. BeginDrag/EndDrag only Register/Unregister the event.
	ns.tbtPanel:SetScript("OnEvent", function(self, event, ...)
		if event == "GLOBAL_MOUSE_UP" and tbtDragState.active then
			local button = ...
			if button == "LeftButton" then
				EndDrag(true)
			elseif button == "RightButton" then
				EndDrag(false)
			end
		end
	end)

	-- Cancel drag if CDM settings panel is hidden (e.g. Escape key)
	ns.tbtPanel:HookScript("OnHide", function()
		if tbtDragState.active then
			EndDrag(false)
		end
	end)

	-- Tab click: show TBT panel, uncheck CDM tabs visually (without touching TabButtons)
	tab:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			ns:ShowTBTPanel()
		end
	end)

	-- Hook SetDisplayMode to detect CDM tab clicks (Spells/Auras).
	-- hooksecurefunc is safe — it runs AFTER the original and doesn't taint.
	-- We only hide our panel here; we never call SetDisplayMode ourselves.
	hooksecurefunc(CooldownViewerSettings, "SetDisplayMode", function()
		ns:HideTBTPanel()
	end)

	-- Preview hooks (D-15, D-16)
	-- TAINT SAFETY: Use a separate watcher frame instead of HookScript on
	-- CooldownViewerSettings. HookScript on secure frames can propagate
	-- taint when CDM fires OnShow/OnHide from secure code paths in instances.
	-- We poll only while CDM is visible, not every frame unconditionally.
	-- CDM visibility watcher: throttled poll (every 0.5s, not every frame)
	-- Cannot use HookScript on CooldownViewerSettings (taint in instances)
	-- Cannot use UI_PANEL_SHOW (doesn't exist in Midnight)
	local cdmWatcher = CreateFrame("Frame", nil, UIParent)
	local cdmWasShown = false
	local cdmWatcherElapsed = 0

	cdmWatcher:SetScript("OnUpdate", function(_, elapsed)
		cdmWatcherElapsed = cdmWatcherElapsed + elapsed
		if cdmWatcherElapsed < 0.5 then
			return
		end
		cdmWatcherElapsed = 0

		local isShown = CooldownViewerSettings:IsVisible()
		if isShown and not cdmWasShown then
			cdmWasShown = true
			StartPreview()
		elseif not isShown and cdmWasShown then
			cdmWasShown = false
			StopPreview()
		end
	end)

	-- Build all four sections and wire refresh on panel show
	ns:BuildAllSections()
	ns.tbtPanel:HookScript("OnShow", function()
		ns:RefreshTBTSections()
		-- Deferred second refresh: GridLayoutFrame may not have calculated
		-- container heights on the first Layout() call within the same frame.
		-- A one-frame delay ensures heights are settled before re-stacking.
		C_Timer.After(0, function()
			ns:RefreshTBTSections()
		end)
	end)

	tab:Show()
end

---------------------------------------------------------------------
-- Panel show/hide
---------------------------------------------------------------------

function ns:ShowTBTPanel()
	-- Hide CDM content and show TBT panel.
	-- TAINT NOTE: These calls are safe here because ShowTBTPanel is only
	-- invoked from our own tab click handler or /tbt command (addon code
	-- context), never from CDM's secure OnShow/OnHide/SetDisplayMode paths.
	-- The taint fix was removing HookScript on CooldownViewerSettings, not
	-- avoiding Hide/Show on CooldownScroll.
	if CooldownViewerSettings.CooldownScroll then
		CooldownViewerSettings.CooldownScroll:Hide()
	end
	ns.tbtPanel:Show()
	ns.tbtPanel:SetFrameLevel(CooldownViewerSettings:GetFrameLevel() + 10)

	-- Uncheck CDM tabs, check ours
	TBTSettingsTab:SetChecked(true)
	if CooldownViewerSettings.SpellsTab then
		CooldownViewerSettings.SpellsTab:SetChecked(false)
	end
	if CooldownViewerSettings.AurasTab then
		CooldownViewerSettings.AurasTab:SetChecked(false)
	end
	ns.tbtTabActive = true
end

function ns:HideTBTPanel()
	if ns.tbtPanel then
		ns.tbtPanel:Hide()
	end
	if CooldownViewerSettings.CooldownScroll then
		CooldownViewerSettings.CooldownScroll:Show()
	end
	TBTSettingsTab:SetChecked(false)
	ns.tbtTabActive = false
end

---------------------------------------------------------------------
-- /tbt command target
---------------------------------------------------------------------

function ns:SelectTBTTab()
	-- Open CDM settings if not visible
	if not CooldownViewerSettings:IsVisible() then
		if CooldownViewerSettings.ShowUIPanel then
			CooldownViewerSettings:ShowUIPanel()
		else
			ShowUIPanel(CooldownViewerSettings)
		end
	end
	-- Select TBT tab after a frame so OnShow's SetDisplayMode finishes first
	C_Timer.After(0, function()
		ns:ShowTBTPanel()
	end)
end

---------------------------------------------------------------------
-- Init gate: wait for CDM to be fully loaded
---------------------------------------------------------------------

EventUtil.ContinueAfterAllEvents(function()
	ns:InitCDMTab()
end, "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD", "COOLDOWN_VIEWER_DATA_LOADED")
