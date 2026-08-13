local _, ns = ...

-- CDM Tab integration for TerribleBuffTracker.
-- CRITICAL: We must NEVER touch CooldownViewerSettings.TabButtons or call
-- SetDisplayMode with TBT strings — doing so taints CDM's secure code.

local ICON_PATH = "Interface\\AddOns\\TerribleBuffTracker\\tbt_icon_64x64"

-- Description text for meta-buff tiles in the CDM Suggested section (D-06/D-07 Phase 23).
-- Kept CDMTab-local — this is settings UX text, not provider concern.
local META_DESCRIPTIONS = {
	trinket = "Tracks all current season's on-use trinkets",
	pot = "Tracks all current season's damage potions",
	lust = "Matches all Heroism/Bloodlust effects",
}

---------------------------------------------------------------------
-- Preview control (reuses existing ns.configOpen flag from Display.lua)
---------------------------------------------------------------------

local function StartPreview()
	-- D-14 / ICON-05: Refresh provider at-rest state (trinket/pot cache) before preview begins.
	-- Combat-gated inside RefreshProvidersAtRest (D-07) — safe to call unconditionally.
	ns:RefreshProvidersAtRest()
	ns:RefreshTBTSections()
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
	{ key = "suggested", title = "Suggested" },
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
		if button == "LeftButton" and self.spellID then
			-- Don't drag from collapsed sections (Suggested is never collapsed)
			local section = ns.tbtSections and ns.tbtSections[self.sectionName]
			if section and section.collapsed then
				return
			end
			BeginDrag(self)
		end
	end)

	f:SetScript("OnEnter", function(self)
		if not self.spellID then
			return
		end
		local info = ns:GetDisplayInfoForKey(self.spellID)
		if not info then
			-- Non-meta user spell with no provider info; still try bare tooltip
			if type(self.spellID) == "number" then
				ns:ShowBuffTooltip(self, { spellID = self.spellID }, {
					showSpellID = true,
				})
			end
			return
		end

		-- Build the proc-shaped table and opts for the shared handler
		local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[self.spellID]
		local duration
		if info.duration and info.duration > 0 then
			duration = info.duration
		elseif entry and entry.duration and entry.duration > 0 then
			duration = entry.duration
		end

		local proc = {
			spellID = info.spellID,
			label = (entry and entry.label) or info.label,
			duration = duration,
		}

		local description = META_DESCRIPTIONS[self.spellID]
		ns:ShowBuffTooltip(self, proc, {
			showSpellID = type(info.spellID) == "number",
			showDuration = duration ~= nil,
			extraLines = description and { description } or nil,
		})
	end)

	f:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	f:SetScript("OnMouseUp", function(self, button, upInside)
		if button == "RightButton" and upInside then
			local sectionName = self.sectionName
			if sectionName == "suggested" then
				-- D-08: Special menu for suggested items — Add to Bars / Add to Buffs, no Remove
				MenuUtil.CreateContextMenu(self, function(_owner, rootDescription)
					local function addSuggestedToSection(targetSection)
						local key = self.spellID
						local existing = ns.db.trackedBuffs[key]
						if existing then
							ns:SetBuffSection(key, targetSection)
						else
							for _, suggestedKey in ipairs(ns.SUGGESTED_KEYS) do
								if suggestedKey == key then
									local info = ns:GetDisplayInfoForKey(suggestedKey)
									if info then
										local maxOrder = 0
										for _, e in pairs(ns.db.trackedBuffs) do
											if e.layoutOrder and e.layoutOrder > maxOrder then
												maxOrder = e.layoutOrder
											end
										end
										ns.db.trackedBuffs[key] = {
											key = suggestedKey,
											label = info.label,
											duration = info.duration,
											section = targetSection,
											layoutOrder = maxOrder + 1,
										}
									end
									break
								end
							end
						end
						ns:RefreshTBTSections()
						if ns.configOpen then
							ns:StartAllPreviewTimers()
						end
					end
					rootDescription:CreateButton("Add to Bars", function()
						addSuggestedToSection("bars")
					end)
					rootDescription:CreateButton("Add to Buffs", function()
						addSuggestedToSection("buffs")
					end)
					-- D-08: No "Remove" option for suggested items
				end)
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
	tbtDragState.isFromSuggested = (iconFrame.sectionName == "suggested")
	if tbtDragState.isFromSuggested then
		tbtDragState.suggestedKey = iconFrame.spellID -- string key e.g. "lust"
	end

	-- Show ghost at cursor; resolve class-aware icon for suggested items
	local ghost = GetOrCreateGhostFrame()
	-- Resolve class-aware / meta-aware icon via unified dispatch (D-15 Phase 23)
	local ghostInfo = ns:GetDisplayInfoForKey(iconFrame.spellID)
	local ghostIconID = (ghostInfo and ghostInfo.icon) or ns:GetSpellIcon(iconFrame.spellID) or 134400
	ghost.Icon:SetTexture(ghostIconID)
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
			local targetSection = result
			if tbtDragState.isFromSuggested then
				-- D-05: Copy-on-drag from Suggested — create entry if not tracked, else move
				local suggestedKey = tbtDragState.suggestedKey
				local existing = ns.db.trackedBuffs[suggestedKey]
				if existing then
					-- Already tracked: move to target section
					ns:SetBuffSection(suggestedKey, targetSection)
				else
					-- Not yet tracked: create entry from suggested definition
					for _, sk in ipairs(ns.SUGGESTED_KEYS) do
						if sk == suggestedKey then
							local info = ns:GetDisplayInfoForKey(sk)
							if info then
								local maxOrder = 0
								for _, e in pairs(ns.db.trackedBuffs) do
									if e.layoutOrder and e.layoutOrder > maxOrder then
										maxOrder = e.layoutOrder
									end
								end
								ns.db.trackedBuffs[suggestedKey] = {
									key = sk,
									label = info.label,
									duration = info.duration,
									section = targetSection,
									layoutOrder = maxOrder + 1,
								}
							end
							break
						end
					end
				end
				-- D-07: Icon stays in Suggested (no removal)
				wipe(tbtDragState)
				ns:RefreshTBTSections()
				if ns.configOpen then
					ns:StartAllPreviewTimers()
				end
				PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
				return
			end
			local spellID = tbtDragState.spellID
			local entry = ns.db.trackedBuffs[spellID]
			if entry then
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
							return tostring(a.spellID) < tostring(b.spellID) -- stable tiebreak (handles mixed string/number keys)
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

		if def.key == "suggested" then
			-- Populate from SUGGESTED_KEYS catalog (D-12 Phase 23).
			-- Add square is layoutIndex 1 (always first); catalog starts at 2.
			for i, suggestedKey in ipairs(ns.SUGGESTED_KEYS) do
				local item = section.itemPool:Acquire()
				local info = ns:GetDisplayInfoForKey(suggestedKey)
				local iconID = (info and info.icon) or 134400
				item.spellID = suggestedKey -- string key "lust" / "trinket" / "pot"
				item.Icon:SetTexture(iconID)
				item.sectionName = "suggested"
				item.suggestedIndex = i -- index into ns.SUGGESTED_KEYS (D-13)
				item.layoutIndex = i + 1 -- +1 to leave slot 1 for the Add square
				item:Show()
			end
		else
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
				-- Resolve icon via unified dispatch (D-15 Phase 23). Falls back to GetSpellIcon for
				-- plain numeric user spells (provider returns nil → direct spell icon lookup).
				local displayInfo = ns:GetDisplayInfoForKey(info.spellID)
				local iconID = (displayInfo and displayInfo.icon) or ns:GetSpellIcon(info.spellID) or 134400
				item.Icon:SetTexture(iconID)
				item.sectionName = def.key
				item.layoutIndex = i -- sequential for GridLayoutFrame
				item:Show()
			end
		end

		section.container:Layout()
		ns:UpdateSectionHeight(section)
	end
	ns:UpdateScrollChildHeight()

	-- Refresh preview timers so meta-buff icons/labels reflect current spec
	if ns.configOpen then
		ns:StartAllPreviewTimers()
	end
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
	addSquare.layoutIndex = 1 -- Always first in Suggested section
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
-- Tab placement
---------------------------------------------------------------------

-- Vertical gap Blizzard uses between CDM side tabs.
local TAB_GAP = -3

-- Bottom-first fallback, used only if tab discovery comes up empty.
local KNOWN_CDM_TABS = { "GroupBuffsTab", "AurasTab", "SpellsTab" }

-- Reusable discovery buffer — refilled per call, never handed out beyond the callers below.
local cdmTabs = {}

local function CollectCDMTabs(...)
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		-- Every CDM tab template carries a displayMode key ("spells"/"auras"/"groupBuffs"/...);
		-- no other child of the settings frame does, and ours has none, so it self-excludes.
		if type(child.displayMode) == "string" then
			cdmTabs[#cdmTabs + 1] = child
		end
	end
end

-- Returns Blizzard's CDM side tabs, discovered by walking the settings frame's children.
-- Discovery is by child + displayMode rather than CooldownViewerSettings.TabButtons on purpose —
-- that array is off limits per the taint rule at the top of this file. Walking children costs
-- nothing here (called on settings open, not per frame) and needs no edit when a patch adds a tab.
local function GetCDMTabs()
	wipe(cdmTabs)
	if not CooldownViewerSettings then
		return cdmTabs
	end
	CollectCDMTabs(CooldownViewerSettings:GetChildren())
	if #cdmTabs == 0 then
		for _, name in ipairs(KNOWN_CDM_TABS) do
			local tabButton = CooldownViewerSettings[name]
			if tabButton then
				cdmTabs[#cdmTabs + 1] = tabButton
			end
		end
	end
	return cdmTabs
end

-- Re-anchors our tab under the bottom-most Blizzard tab, so a tab added by a patch pushes ours
-- down instead of being covered by it. Falls back to the last discovered tab while the settings
-- window has never been shown and frame rects are still unresolved.
local function AnchorTabBelowCDMTabs()
	local tabs = GetCDMTabs()
	local anchorTo, lowestBottom
	for _, tabButton in ipairs(tabs) do
		local bottom = tabButton:GetBottom()
		if not bottom then
			anchorTo = tabs[#tabs]
			break
		end
		if not lowestBottom or bottom < lowestBottom then
			anchorTo, lowestBottom = tabButton, bottom
		end
	end
	if not anchorTo then
		return -- XML anchor stays in effect
	end
	TBTSettingsTab:ClearAllPoints()
	TBTSettingsTab:SetPoint("TOP", anchorTo, "BOTTOM", 0, TAB_GAP)
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
			-- Re-anchor here rather than only at init: tab rects are resolved once the window has
			-- been shown, and this picks up any tab set change without hooking CDM (taint).
			AnchorTabBelowCDMTabs()
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

	AnchorTabBelowCDMTabs()
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
	-- Hide every CDM content pane; which one is up depends on its display mode.
	if CooldownViewerSettings.CooldownScroll then
		CooldownViewerSettings.CooldownScroll:Hide()
	end
	if CooldownViewerSettings.GroupBuffFilter then
		CooldownViewerSettings.GroupBuffFilter:Hide()
	end
	ns.tbtPanel:Show()
	ns.tbtPanel:SetFrameLevel(CooldownViewerSettings:GetFrameLevel() + 10)

	-- Uncheck CDM tabs, check ours. Discovered rather than named so a tab added by a patch is
	-- unchecked too (12.1's Group Buffs tab was staying lit behind our panel).
	TBTSettingsTab:SetChecked(true)
	for _, tabButton in ipairs(GetCDMTabs()) do
		if tabButton.SetChecked then
			tabButton:SetChecked(false)
		end
	end
end

function ns:HideTBTPanel()
	if ns.tbtPanel then
		ns.tbtPanel:Hide()
	end
	-- Restore whichever pane CDM's current display mode owns — the cooldown list belongs to the
	-- Spells/Auras modes, the group buff filter to the Group Buffs mode. Mirrors SetDisplayMode,
	-- which our hook runs after, so blindly showing CooldownScroll would cover the filter pane.
	local isGroupBuffs = CooldownViewerSettings.displayMode == "groupBuffs"
	if CooldownViewerSettings.CooldownScroll then
		CooldownViewerSettings.CooldownScroll:SetShown(not isGroupBuffs)
	end
	if CooldownViewerSettings.GroupBuffFilter then
		CooldownViewerSettings.GroupBuffFilter:SetShown(isGroupBuffs)
	end
	TBTSettingsTab:SetChecked(false)
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
