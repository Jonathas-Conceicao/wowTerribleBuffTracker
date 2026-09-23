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

-- Phase 35.1 (CFG-01): the Suggested section's grid reserves its first two slots for the
-- add (+) square and the gear (config) square, in that order. One constant is the single
-- source for both squares' layoutIndex and the catalog's starting slot, so adding a third
-- square later is a one-line change instead of two numbers that can disagree.
local SUGGESTED_RESERVED_SLOTS = 2

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

-- Phase 35 (CONT-01/CONT-03), rebuildable since Phase 36 (CONT-04/CONT-05): one section per
-- ns.CONTAINERS registry entry, in registry order, then Not Displayed, then Suggested.
-- SectionHitTest and the reorder marker walk VALID_DROP_SECTIONS every frame during a drag,
-- and ns:UpdateScrollChildHeight reads #SECTION_DEFS, so both tables are wiped and refilled
-- IN PLACE by ns.RebuildContainerSectionDefs below — never reassigned with `= {}` again after
-- this point, because the drag hot loops hold upvalues to these exact tables. A rebuild runs
-- only on load, container create and container delete, never per frame.
local SECTION_DEFS = {}
local VALID_DROP_SECTIONS = {}

function ns.RebuildContainerSectionDefs()
	wipe(SECTION_DEFS)
	wipe(VALID_DROP_SECTIONS)
	for _, def in ipairs(ns.CONTAINERS) do
		table.insert(SECTION_DEFS, { key = def.key, title = def.title, category = ns:GetContainerCategory(def) })
		table.insert(VALID_DROP_SECTIONS, def.key)
	end
	-- "both" means shown under either tab. Not Displayed is the drop target every tab needs,
	-- and Suggested carries the + and settings squares, which the user asked to reach from
	-- either tab. Their CONTENTS are still filtered by category in ns:RefreshTBTSections --
	-- a hidden buff tracker must not be visible, and therefore draggable, from the Spells tab.
	table.insert(SECTION_DEFS, { key = "hidden", title = "Not Displayed", category = "both" })
	table.insert(SECTION_DEFS, { key = "suggested", title = "Suggested", category = "both" })
	table.insert(VALID_DROP_SECTIONS, "hidden")
end

ns.RebuildContainerSectionDefs()

-- Which tracker category the CDM tab is currently showing: "spells" or "buffs".
--
-- Defaults to "buffs" because every tracker that existed before v0.4.0 is a buff, so a player
-- who has not touched the new tab finds their own trackers where they left them. Runtime-only:
-- which tab was last open is not worth a saved variable, and starting somewhere predictable
-- beats restoring somewhere surprising.
ns.tbtActiveCategory = "buffs"

-- A section is laid out and rendered only under its own tab. Cross-category drag is blocked by
-- this and nothing else: SectionHitTest already skips any section whose frame is not shown, so
-- hiding the other category's sections makes "buffs and spells cannot be moved between them"
-- structural rather than a rule enforced in the drop handler.
local function IsSectionActive(def)
	return def.category == "both" or def.category == ns.tbtActiveCategory
end

-- Drag state (wiped with wipe() on EndDrag — never reassigned, per CLAUDE.md pattern)
local tbtDragState = {}

-- Forward declarations (BeginDrag/EndDrag used inside CreateIconFrame closures)
local BeginDrag, EndDrag

-- Create a tracker from a Suggested tile, or move it if one already exists.
--
-- Written once and called from both add paths -- the right-click menu and the drag drop --
-- which were the same twenty lines twice over. Unifying them is what lets the racial COOLDOWN
-- tiles work without a third copy: their keys are "cd:<spellID>" rather than meta strings, so
-- validating against ns.SUGGESTED_KEYS alone would have created nothing at all.
local function AddSuggestedTracker(key, targetSection)
	if ns.db.trackedBuffs[key] then
		ns:SetBuffSection(key, targetSection)
		return
	end

	-- A cooldown tile carries its spell in the key; a meta tile IS its key. Either way the
	-- display info is what fills the entry, which is why a racial cooldown's seed duration
	-- matters -- see ns:RacialCooldownSeed.
	local cooldownSpellID = ns:CooldownKeySpellID(key)
	if not cooldownSpellID then
		local known = false
		for _, suggestedKey in ipairs(ns.SUGGESTED_KEYS) do
			if suggestedKey == key then
				known = true
				break
			end
		end
		if not known then
			return
		end
	end

	local info = ns:GetDisplayInfoForKey(key)
	if not info then
		return
	end

	local maxOrder = 0
	for _, e in pairs(ns.db.trackedBuffs) do
		if e.layoutOrder and e.layoutOrder > maxOrder then
			maxOrder = e.layoutOrder
		end
	end

	ns.db.trackedBuffs[key] = {
		key = key,
		label = info.label,
		duration = info.duration,
		section = targetSection,
		layoutOrder = maxOrder + 1,
		-- Only a cooldown tile sets this. A meta buff entry leaves it nil, which
		-- ns:GetTrackerCategory already reads as "buffs".
		trackerType = cooldownSpellID and "cooldown" or nil,
		spellID = cooldownSpellID or nil,
	}
end

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

		-- A provider-owned constant array (never rebuilt per hover) wins over the static
		-- single-line wrap below with no per-hover table construction; passed by reference,
		-- not wrapped again.
		local description = META_DESCRIPTIONS[self.spellID]
		local extraLines = info.descriptionLines or (description and { description }) or nil
		ns:ShowBuffTooltip(self, proc, {
			showSpellID = type(info.spellID) == "number",
			showDuration = duration ~= nil,
			extraLines = extraLines,
		})
	end)

	f:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	f:SetScript("OnMouseUp", function(self, button, upInside)
		if button == "RightButton" and upInside then
			local sectionName = self.sectionName
			if sectionName == "suggested" then
				-- D-08: Special menu for suggested items — one Add to <container> per registry
				-- def, no Remove.
				MenuUtil.CreateContextMenu(self, function(_owner, rootDescription)
					local function addSuggestedToSection(targetSection)
						AddSuggestedTracker(self.spellID, targetSection)
						ns:RefreshTBTSections()
						if ns.configOpen then
							ns:StartAllPreviewTimers()
						end
					end
					for _, def in ipairs(ns.CONTAINERS) do
						rootDescription:CreateButton("Add to " .. def.title, function()
							addSuggestedToSection(def.key)
						end)
					end
					-- D-08: No "Remove" option for suggested items
				end)
				return
			end
			MenuUtil.CreateContextMenu(self, function(_owner, rootDescription)
				for _, def in ipairs(ns.CONTAINERS) do
					if def.key ~= sectionName then
						rootDescription:CreateButton("Move to " .. def.title, function()
							ns:SetBuffSection(self.spellID, def.key)
							ns:RefreshTBTSections()
						end)
					end
				end
				if sectionName ~= "hidden" then
					rootDescription:CreateButton("Hide", function()
						ns:SetBuffSection(self.spellID, "hidden")
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
			-- PAR-02: GetScaledCursorPositionForFrame is an engine-side global present on
			-- Midnight but ABSENT on Forever (build 1.60.1.69893), so this OnUpdate called a
			-- nil value every frame of every drag — 53 errors in one session, 2026-09-18.
			-- Replaced with the same GetCursorPosition/GetScale idiom the other three cursor
			-- sites in this file already use (SectionHitTest, the marker update, and the
			-- reorder hit test), which removes the engine dependency instead of shimming it
			-- and leaves one cursor idiom in the file. No flavor check needed.
			local scale = topLevel:GetScale()
			local x, y = GetCursorPosition()
			x, y = x / scale, y / scale
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
				-- D-05: Copy-on-drag from Suggested — create entry if not tracked, else move.
				-- Shares AddSuggestedTracker with the right-click menu; see its header.
				AddSuggestedTracker(tbtDragState.suggestedKey, targetSection)
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
	-- Counts only the sections the active tab actually lays out, and counts the 18px gap
	-- BETWEEN them rather than after each one -- the old "i < numSections" test used the
	-- position in SECTION_DEFS, which stops meaning "is there another one after this" as soon
	-- as some of them are filtered out.
	local total = 0
	local shownCount = 0
	for _, def in ipairs(SECTION_DEFS) do
		local section = ns.tbtSections[def.key]
		if section and IsSectionActive(def) then
			if shownCount > 0 then
				total = total + 18 -- CDM exact: 18px gap between categories
			end
			shownCount = shownCount + 1
			total = total + section.frame:GetHeight()
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
		-- CONT-04/CONT-05: skip rather than break -- deletion removes sections at runtime, and
		-- a missing user section here must not truncate the loop before Not Displayed/Suggested.
		if section then
			section.itemPool:ReleaseAll()

			-- Delete zone: permanent first slot in the Not Displayed section. Live, not decorative
			-- -- SectionHitTest gives it top priority and EndDrag calls ns:RemoveTrackedBuff on a
			-- drop here.
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

			-- The catalogue tiles are all buff meta-trackers (lust, trinket, pot, racial), so
			-- they belong to the Buffs tab. The + and settings squares are NOT part of this --
			-- they occupy the reserved slots and are built once in ns:BuildAllSections, so they
			-- stay put under either tab, which is what the user asked for.
			if def.key == "suggested" and ns.tbtActiveCategory == "spells" then
				-- The Cooldowns tab gets the racial COOLDOWN tiles, and nothing else: every other
				-- catalogue entry is a buff meta-tracker. Keys are ordinary "cd:<spellID>"
				-- strings, so adding one creates a normal cooldown tracker -- the only thing
				-- special about them is that the spell and its duration are filled in for a
				-- character who would otherwise have to look both up.
				--
				-- No ns:IsSuggestedKeyResolvable call: ns:RacialCooldownKeys only returns keys
				-- for a racial that actually resolved, so an unsupported race yields an empty
				-- list and no tiles rather than a greyed placeholder. That differs from the buff
				-- tile on purpose -- RACE-01 requires THAT one to appear on both clients.
				local suggestedSlot = SUGGESTED_RESERVED_SLOTS
				for i, cooldownKey in ipairs(ns:RacialCooldownKeys()) do
					suggestedSlot = suggestedSlot + 1
					local item = section.itemPool:Acquire()
					local info = ns:GetDisplayInfoForKey(cooldownKey)
					item.spellID = cooldownKey
					item.Icon:SetTexture((info and info.icon) or 134400)
					-- Pooled frames keep a previous tile's desaturation; these are always
					-- supported, so it is cleared rather than left.
					item.Icon:SetDesaturated(false)
					item.sectionName = "suggested"
					item.suggestedIndex = i
					item.layoutIndex = suggestedSlot
					item:Show()
				end
			elseif def.key == "suggested" and ns.tbtActiveCategory ~= "buffs" then
				-- Nothing to add beyond the reserved squares.
			elseif def.key == "suggested" then
				-- Populate from SUGGESTED_KEYS catalog (D-12 Phase 23).
				-- Add/gear squares occupy layoutIndex 1..SUGGESTED_RESERVED_SLOTS; catalog starts after.
				local suggestedSlot = SUGGESTED_RESERVED_SLOTS
				for i, suggestedKey in ipairs(ns.SUGGESTED_KEYS) do
					-- META-01 (Phase 27.1): skip a tile when none of that provider's catalog
					-- spells resolve on this client (D-09). Answered by the memoised
					-- ns:IsSuggestedKeyResolvable, so this render path never iterates a catalog
					-- no matter how often ns:RefreshTBTSections runs — every CDM open and after
					-- every drag, add, move and delete (D-10). Skipping is display-only;
					-- ns.db.trackedBuffs is deliberately untouched, so a user who already tracks
					-- a meta key keeps it (D-11). The condition is client-capability-shaped, so a
					-- client that later ships those spells shows the tile again with no code
					-- change (D-12).
					if ns:IsSuggestedKeyResolvable(suggestedKey) then
						suggestedSlot = suggestedSlot + 1
						local item = section.itemPool:Acquire()
						local info = ns:GetDisplayInfoForKey(suggestedKey)
						local iconID = (info and info.icon) or 134400
						item.spellID = suggestedKey -- string key "lust" / "trinket" / "pot"
						item.Icon:SetTexture(iconID)
						-- RACE-01 requires the tile to appear on both clients, so an unimplemented
						-- racial is greyed rather than hidden; written on every tile because item
						-- frames are pooled and a previous tile's desaturation must not persist.
						item.Icon:SetDesaturated((info and info.unsupported) == true)
						item.sectionName = "suggested"
						item.suggestedIndex = i -- index into ns.SUGGESTED_KEYS (D-13)
						item.layoutIndex = suggestedSlot
						item:Show()
					end
				end
			else
				-- Collect and sort by layoutOrder for within-section ordering
				local sorted = {}
				for spellID, entry in pairs(ns.db.trackedBuffs) do
					-- The category test matters only for "hidden", which is the one section both
					-- tabs show: a buff tracker parked there must not appear under Spells, where
					-- it could be dragged into a cooldown container. For every other section the
					-- test is free -- a section belongs to one category and so does everything
					-- filed in it -- and it costs one derived comparison per entry.
					if entry.section == def.key and ns:GetTrackerCategory(entry) == ns.tbtActiveCategory then
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
					item.Icon:SetDesaturated(false)
					item.sectionName = def.key
					item.layoutIndex = i -- sequential for GridLayoutFrame
					item:Show()
				end
			end

			section.container:Layout()
			ns:UpdateSectionHeight(section)
		end
	end
	ns:UpdateScrollChildHeight()

	-- Refresh preview timers so meta-buff icons/labels reflect current spec
	if ns.configOpen then
		ns:StartAllPreviewTimers()
	end
end

-- Unit suffixes the duration field accepts. Seconds and minutes only: an hour is 60m, and every
-- extra letter here is one more thing a typo can land on.
local DURATION_UNITS = { s = 1, m = 60 }

-- Shown in red under the field when the value will not parse. It explains the UNITS rather than
-- repeating the examples already in the field's own label, so the two lines say different things.
local DURATION_HINT = "Use s for seconds and m for minutes"

-- "30" -> 30, "45s" -> 45, "2m" -> 120, "1.5m" -> 90. Returns SECONDS, or nil for anything it
-- does not understand -- a bare number is seconds, which is what the field always meant, so no
-- existing habit stops working.
--
-- nil is the only failure signal, and the caller turns it into a disabled Add button rather than
-- an error after the fact: "2min" and "2 mins" are the obvious near-misses, and finding out they
-- were wrong only after clicking Add is worse than not being able to click it.
local function ParseDuration(text)
	if type(text) ~= "string" then
		return nil
	end

	-- One optional run of spaces either side of the unit, so "2 m" works and " 2m " does too.
	-- %d*%.?%d+ accepts "30", "1.5" and ".5" but not "30." or "".
	local amount, unit = text:lower():match("^%s*(%d*%.?%d+)%s*(%a*)%s*$")
	if not amount then
		return nil
	end

	local value = tonumber(amount)
	if not value or value <= 0 then
		return nil
	end

	if unit == "" then
		return value
	end

	local multiplier = DURATION_UNITS[unit]
	if not multiplier then
		return nil
	end
	return value * multiplier
end

local function CreateAddDialog()
	-- Simple dialog parented to UIParent at DIALOG strata so it renders
	-- above everything including CDM settings window.
	local dialog = CreateFrame("Frame", "TBTAddBuffDialog", UIParent, "BackdropTemplate")
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

	-- Title. Set from the active tab in dialog.ResetFields rather than fixed, because the tab is
	-- now the only thing that decides what is being added -- see the Type note below.
	local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetText("Add Tracker")
	title:SetPoint("TOP", dialog, "TOP", 0, -12)

	-- Layout cursor: every control below is anchored TOPLEFT to the dialog itself at this
	-- running offset, rather than chained to the previous control, so the single SetSize
	-- call after the last control can read the final height straight off it. Starts at the
	-- original Spell ID label offset.
	local y = -38

	-- Spell ID
	local spellIdLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	spellIdLabel:SetText("Spell ID:")
	spellIdLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, y)

	y = y - 18
	local spellIdBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	spellIdBox:SetSize(180, 22)
	spellIdBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, y)
	spellIdBox:SetNumeric(true)
	spellIdBox:SetMaxLetters(10)
	spellIdBox:SetAutoFocus(false)

	-- Duration. The label carries the accepted formats rather than just the unit, because the
	-- field now takes a suffix and an unsuffixed number still means seconds.
	y = y - 32
	local durationLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	durationLabel:SetText("Duration (30, 45s, 2m):")
	durationLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, y)

	y = y - 18
	local durationBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	durationBox:SetSize(180, 22)
	durationBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, y)
	durationBox:SetMaxLetters(6)
	durationBox:SetAutoFocus(false)

	-- Type (ADD-01) and Container (ADD-02) are both GONE as controls, by user decision
	-- 2026-09-22, and both answers are now implied rather than asked for.
	--
	-- Type comes from the tab. The Cooldowns tab and the Buffs tab already show disjoint sets of
	-- trackers and forbid dragging between them, so a Type control could only ever agree with
	-- the tab or contradict it -- and contradicting it filed the new tracker into the category
	-- the player could not see. The dialog says which it is in its title instead.
	--
	-- Container is always "Not Displayed". That was already the default and the locked v0.2.0
	-- rule that an unchosen container must never fall through to a visible one; choosing at
	-- creation only duplicated the drag the player makes next anyway.
	-- Cover all ranks (ADD-03): created only when the client-capability flag defined once in
	-- Core.lua is true -- absent on retail, not hidden or disabled, so the CreateFrame call
	-- itself sits inside this `if` and rankCheck stays nil there. This is that flag's only
	-- reader; every later reference to rankCheck below is nil-guarded. The gap before it is
	-- inside the `if` too, so a client without the widget does not carry its blank space.
	local rankCheck
	if ns.CLIENT_HAS_SPELL_RANKS then
		y = y - 32
		rankCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
		rankCheck:SetSize(24, 24)
		rankCheck:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, y)
		rankCheck:SetChecked(true)

		local rankLabel = rankCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		rankLabel:SetPoint("LEFT", rankCheck, "RIGHT", 4, 0)
		rankLabel:SetText("Cover all ranks")

		y = y - 26
	end

	-- Error label. Given a width and centred so the duration hint wraps to a second line instead
	-- of running out past the dialog's edge; the extra line is reserved in the y step below.
	local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontRed")
	errorLabel:SetPoint("TOP", dialog, "TOP", 0, y)
	errorLabel:SetWidth(208)
	errorLabel:SetJustifyH("CENTER")
	errorLabel:SetText("")

	y = y - 32
	-- Single height computation, driven by whatever was actually created above -- no second
	-- flavour branch on the literal height.
	dialog:SetSize(240, math.abs(y) + 46)

	-- Add button
	local addBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	addBtn:SetSize(80, 22)
	addBtn:SetText("Add")
	addBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 12)
	-- Live validation, so Add is only clickable on input that will actually work. Both fields are
	-- checked because either one empty is just as unusable as either one malformed; the message
	-- names only the duration, since the spell ID field is numeric-only and cannot be malformed,
	-- only blank.
	local function RefreshAddState()
		local durationText = durationBox:GetText()
		local seconds = ParseDuration(durationText)
		local spellID = spellIdBox:GetNumber()

		if durationText ~= "" and not seconds then
			errorLabel:SetText(DURATION_HINT)
		else
			errorLabel:SetText("")
		end

		addBtn:SetEnabled(seconds ~= nil and spellID ~= nil and spellID > 0)
	end

	dialog.RefreshAddState = RefreshAddState
	spellIdBox:SetScript("OnTextChanged", RefreshAddState)
	durationBox:SetScript("OnTextChanged", RefreshAddState)

	addBtn:SetScript("OnClick", function()
		local spellID = spellIdBox:GetNumber()
		if not spellID or spellID <= 0 then
			errorLabel:SetText("Invalid Spell ID")
			return
		end
		-- Re-parsed rather than cached from RefreshAddState: the button being enabled is a UI
		-- state, and this is the one that decides what gets stored.
		local duration = ParseDuration(durationBox:GetText())
		if not duration then
			errorLabel:SetText(DURATION_HINT)
			return
		end
		ns:AddTrackedBuff(spellID, duration, nil, {
			-- Read at click time, not at open time: the tab cannot change while a modal dialog
			-- is up, but reading it here means there is no second copy of the answer to keep in
			-- sync with the title.
			trackerType = ns.tbtActiveCategory == "spells" and "cooldown" or "buff",
			section = "hidden",
			coverAllRanks = rankCheck and rankCheck:GetChecked() or nil,
		})
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

	-- One reset path: the addSquare click handler calls this instead of clearing fields
	-- itself, so a future control is reset in one place instead of two.
	dialog.ResetFields = function()
		spellIdBox:SetText("")
		durationBox:SetText("")
		errorLabel:SetText("")
		-- The title is the whole of the type UI now, so it is the one thing that must be right
		-- every time the dialog opens.
		title:SetText(ns.tbtActiveCategory == "spells" and "Add Cooldown Tracker" or "Add Buff Tracker")
		if rankCheck then
			rankCheck:SetChecked(true)
		end
		-- Last, so it sees the cleared fields: an empty dialog opens with Add disabled.
		RefreshAddState()
	end

	return dialog
end

-- CONT-04: the New Container dialog's four checkboxes differ only in what they anchor under,
-- their Y offset, their label text and their initial checked state, so one builder makes all
-- four. Returns the checkbox and its label in that order, because a caller may need the label
-- too -- ApplyCategory greys the Bars one.
local function AddExclusiveCheck(parent, anchorTo, yOffset, text, checked)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset)
	check:SetChecked(checked)

	local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	label:SetText(text)

	return check, label
end

-- CONT-04: both checkbox pairs in the New Container dialog enforce the same rule -- a click
-- checks the box itself and unchecks its partner, so a pair can never both be off and clicking
-- an already-checked box re-checks it rather than clearing it.
--
-- onSelect, when given, runs after the pair settles: false for the first box, true for the
-- second. That polarity is not arbitrary -- it is ApplyCategory(isSpells), which Buffs already
-- called with false and Cooldowns with true, so the callback is passed by name with no wrapper
-- closure in between.
local function WireExclusivePair(first, second, onSelect)
	first:SetScript("OnClick", function(self)
		self:SetChecked(true)
		second:SetChecked(false)
		if onSelect then
			onSelect(false)
		end
	end)
	second:SetScript("OnClick", function(self)
		self:SetChecked(true)
		first:SetChecked(false)
		if onSelect then
			onSelect(true)
		end
	end)
end

-- Phase 35.1 (CFG-01/CFG-02): addon-wide config page. Same parent, same two SetPoint calls
-- and the same frame level as ns.tbtPanel, so it occupies the identical rect — the page swap
-- below is a show/hide of two sibling frames, not a new frame hierarchy. No backdrop (the
-- tracker panel has none either) and it is not added to CDM's array of tab pages (CDMTab.xml's
-- taint rule at the top of this file).
-- CONT-04: modelled on CreateAddDialog above -- same BackdropTemplate/DIALOG-strata/movable/
-- UISpecialFrames idiom. Assigned to ns.tbtContainerDialog in ns:InitCDMTab.
local function CreateContainerDialog()
	local dialog = CreateFrame("Frame", "TBTNewContainerDialog", UIParent, "BackdropTemplate")
	dialog:SetSize(220, 268)
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

	table.insert(UISpecialFrames, "TBTNewContainerDialog")

	-- Title
	local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetText("New Container")
	title:SetPoint("TOP", dialog, "TOP", 0, -12)

	-- Name
	local nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameLabel:SetText("Name:")
	nameLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -38)

	local nameBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	nameBox:SetSize(180, 22)
	nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
	nameBox:SetMaxLetters(32)
	nameBox:SetAutoFocus(false)

	-- Category and kind are both pairs of mutually exclusive checkboxes, not dropdowns --
	-- UICheckButtonTemplate is the idiom this addon already uses on both flavours, and a modern
	-- dropdown template would be a Midnight-only asset. Each OnClick sets itself checked and its
	-- partner unchecked, and re-checks itself if clicked while already checked, so a pair can
	-- never both be off.
	--
	-- Category comes FIRST because it constrains kind: a spells container is icon-only, since
	-- "cooldowns are icons, never bars" is locked and RenderBarContainer skips cooldown trackers
	-- outright. Picking Spells therefore forces Icons and disables the Bars checkbox rather than
	-- letting the player choose a combination ns:CreateUserContainer would refuse.
	local categoryLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	categoryLabel:SetText("Tracks:")
	categoryLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -10)

	local buffsCheck = AddExclusiveCheck(dialog, categoryLabel, -4, "Buffs", true)

	local spellsCheck = AddExclusiveCheck(dialog, buffsCheck, -2, "Cooldowns", false)

	local kindLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	kindLabel:SetText("Display as:")
	kindLabel:SetPoint("TOPLEFT", spellsCheck, "BOTTOMLEFT", 0, -8)

	local iconsCheck = AddExclusiveCheck(dialog, kindLabel, -4, "Icons", true)

	local barsCheck, barsLabel = AddExclusiveCheck(dialog, iconsCheck, -2, "Bars", false)

	WireExclusivePair(iconsCheck, barsCheck)

	-- Spells forces Icons; Buffs hands the choice back. Disabling rather than hiding keeps the
	-- dialog one fixed size and shows the player WHY the option is unavailable.
	local function ApplyCategory(isSpells)
		if isSpells then
			iconsCheck:SetChecked(true)
			barsCheck:SetChecked(false)
			barsCheck:Disable()
			barsLabel:SetTextColor(0.5, 0.5, 0.5)
		else
			barsCheck:Enable()
			barsLabel:SetTextColor(1, 1, 1)
		end
	end

	WireExclusivePair(buffsCheck, spellsCheck, ApplyCategory)

	-- Error label
	local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontRed")
	errorLabel:SetPoint("TOP", barsCheck, "BOTTOM", 0, -10)
	errorLabel:SetText("")

	-- Create button
	local createBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	createBtn:SetSize(80, 22)
	createBtn:SetText("Create")
	createBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 12)
	createBtn:SetScript("OnClick", function()
		local kind = barsCheck:GetChecked() and "bar" or "icon"
		local category = spellsCheck:GetChecked() and "spells" or "buffs"
		-- Plan 01's ns:CreateUserContainer substitutes "Container <id>" for an empty name --
		-- that fallback is not duplicated here.
		local def = ns:CreateUserContainer(nameBox:GetText(), kind, category)
		if not def then
			errorLabel:SetText("Could not create container.")
			return
		end
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

	-- Enter confirms
	nameBox:SetScript("OnEnterPressed", function()
		createBtn:Click()
	end)

	dialog.nameBox = nameBox
	dialog.errorLabel = errorLabel
	-- Reset to the default pair every time the dialog opens, so a previous Spells choice does
	-- not leave Bars disabled on the next Buffs container.
	-- Lets the settings panel open this dialog already pointed at a category, so "New Cooldown
	-- Container" does not make the player pick Cooldowns again. Goes through the same
	-- ApplyCategory the checkboxes use, so the Icons-forced/Bars-disabled asymmetry cannot
	-- diverge between the two entry points.
	dialog.SelectCategory = function(category)
		local isSpells = category == "spells"
		buffsCheck:SetChecked(not isSpells)
		spellsCheck:SetChecked(isSpells)
		ApplyCategory(isSpells)
	end

	dialog.ResetChoices = function()
		buffsCheck:SetChecked(true)
		spellsCheck:SetChecked(false)
		iconsCheck:SetChecked(true)
		barsCheck:SetChecked(false)
		ApplyCategory(false)
	end

	return dialog
end

-- CONT-06: text is the single literal "%s" -- the whole message is built at show time by each
-- row's DeleteButton and passed as the first substitution argument, so a "%" in a user-supplied
-- container title can land inside a format ARGUMENT (always safe) but never inside the format
-- STRING itself (where it would throw). DELETE/CANCEL are FrameXML globals present on both
-- clients; the `or` fallbacks are a capability check, degrading to English text rather than a
-- nil button label if a client ever lacks one.
StaticPopupDialogs["TBT_DELETE_CONTAINER"] = {
	text = "%s",
	button1 = DELETE or "Delete",
	button2 = CANCEL or "Cancel",
	OnAccept = function(self)
		-- Read the key off self.data rather than a second callback parameter, so the same
		-- code works on both clients.
		local key = self.data and self.data.key
		if key then
			ns:DeleteUserContainer(key)
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
}

-- Chrome shared by the Suggested section's action squares (add, gear): a 38x38 frame,
-- colour background, centred 24x24 overlay icon, and the standard hover highlight.
-- Behaviour (tooltip, click, pressed state) is wired by each caller, not here.
local function CreateActionSquare(parent, r, g, b, a)
	local square = CreateFrame("Frame", nil, parent)
	square:SetSize(38, 38)
	square:EnableMouse(true)

	local bg = square:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(square)
	bg:SetColorTexture(r, g, b, a)

	local icon = square:CreateTexture(nil, "OVERLAY")
	icon:SetSize(24, 24)
	icon:SetPoint("CENTER")
	square.Icon = icon

	local highlight = square:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(square)
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	highlight:SetBlendMode("ADD")

	return square
end

-- CONT-04/CONT-05: re-anchors every existing section in SECTION_DEFS order. Called after
-- ns:BuildAllSections' initial build and again from ns.AddContainerSection/RemoveContainerSection,
-- so a runtime create/delete reproduces the exact CDM-exact 18px anchor chain
-- ns:BuildAllSections used to build inline, without duplicating it. Never allocates.
-- On ns as well as local: ns:SelectTBTCategory is defined further down the file and needs it.
-- The local name stays for the existing call sites, which are in this file and hotter.
local RelayoutTBTSections
function ns.RelayoutTBTSections()
	return RelayoutTBTSections()
end

function RelayoutTBTSections()
	local prevFrame = nil
	for _, def in ipairs(SECTION_DEFS) do
		local section = ns.tbtSections[def.key]
		if section and not IsSectionActive(def) then
			-- Hidden rather than destroyed: the frame, its pool and its collapsed state all
			-- survive a tab switch, so switching back is a relayout and not a rebuild.
			section.frame:Hide()
		elseif section then
			section.frame:Show()
			section.frame:ClearAllPoints()
			if prevFrame then
				section.frame:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -18)
			else
				section.frame:SetPoint("TOPLEFT", ns.tbtScrollChild, "TOPLEFT", 0, 0)
			end
			prevFrame = section.frame
		end
	end
	ns:UpdateScrollChildHeight()
end

function ns:BuildAllSections()
	ns.tbtSections = {}
	for _, def in ipairs(SECTION_DEFS) do
		ns.tbtSections[def.key] = BuildTBTSection(ns.tbtScrollChild, def)
	end
	RelayoutTBTSections()

	-- Create the Add Buff dialog (shared modal)
	ns.tbtAddDialog = CreateAddDialog()

	-- Add and gear action squares occupy the first SUGGESTED_RESERVED_SLOTS slots of the
	-- Suggested section's grid (skill-like appearance).
	local suggestedSection = ns.tbtSections.suggested
	local addSquare = CreateActionSquare(suggestedSection.container, 0.1, 0.6, 0.1, 0.4)
	addSquare.Icon:SetAtlas("communities-chat-icon-plus")
	addSquare.layoutIndex = 1 -- Always first in Suggested section

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
			dlg.ResetFields()
			dlg:Show()
			dlg.spellIdBox:SetFocus()
		end
	end)
	addSquare:Show()

	suggestedSection.container:Layout()
end

-- CONT-04/CONT-05: both no-op before ns:BuildAllSections has run. Rehydrated containers are
-- appended to the registry at ADDON_LOADED, well before ns.tbtSections exists, and
-- ns:BuildAllSections itself later loops the rebuilt SECTION_DEFS, so a container created
-- before the CDM tab has ever been built is picked up for free — this is a genuine no-op,
-- not a missed section.
function ns.AddContainerSection(def)
	if not ns.tbtSections then
		return
	end
	if ns.tbtSections[def.key] then
		return
	end
	ns.tbtSections[def.key] = BuildTBTSection(ns.tbtScrollChild, def)
	RelayoutTBTSections()
	ns:RefreshTBTSections()
end

function ns.RemoveContainerSection(key)
	if not ns.tbtSections then
		return
	end
	local section = ns.tbtSections[key]
	if not section then
		return
	end
	section.itemPool:ReleaseAll()
	section.frame:Hide()
	section.frame:ClearAllPoints()
	section.frame:SetParent(nil)
	ns.tbtSections[key] = nil
	RelayoutTBTSections()
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
	-- Spells first, then Buffs under it: the order the user asked for, and the order the XML
	-- placeholder anchors already declare, restated here because this runs against the live
	-- rects once the window has been shown.
	TBTSpellsTab:ClearAllPoints()
	TBTSpellsTab:SetPoint("TOP", anchorTo, "BOTTOM", 0, TAB_GAP)
	TBTSettingsTab:ClearAllPoints()
	TBTSettingsTab:SetPoint("TOP", TBTSpellsTab, "BOTTOM", 0, TAB_GAP)
end

---------------------------------------------------------------------
-- Tab init
---------------------------------------------------------------------

-- Both TBT tabs are set up identically apart from their label and the category they select.
-- Written once here rather than twice inline, so the two cannot drift.
local function SetUpTBTTab(tab, label, category)
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
		GameTooltip:SetText(label)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	tab:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			ns:SelectTBTCategory(category)
		end
	end)
end

function ns:InitCDMTab()
	-- "Cooldowns", not "Spells" (user decision, 2026-09-22): the tab will hold items as well
	-- as spells. Only the LABEL changes -- the category key stays "spells" throughout the code
	-- and in ns.db.userContainers, because renaming a persisted value would need a migration to
	-- buy nothing but a matching word.
	SetUpTBTTab(TBTSpellsTab, "TBT Cooldowns", "spells")
	SetUpTBTTab(TBTSettingsTab, "TBT Buffs", "buffs")

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
	-- The dialog outlives the config PAGE that used to build it -- it is parented to UIParent
	-- and is opened from the settings panel now (ns:OpenContainerDialog in Config.lua).
	ns.tbtContainerDialog = CreateContainerDialog()

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
			-- Backstop for the callback registered below, for a client that does not fire
			-- CooldownViewerSettings.OnHide. Idempotent, so running both costs nothing.
			ns:DismissTBTDialogs()
			ns:HideTBTPanel()
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

	-- Closing the CDM window returns it to Blizzard's own content, so that reopening it does
	-- not land straight back on TBT's page. Reported in play-testing on 2026-09-21: the TBT
	-- panel stayed up across a close/reopen, because ns:ShowTBTPanel hides CDM's panes and
	-- nothing ever put them back unless the player clicked a Blizzard tab.
	--
	-- ns:HideTBTPanel restores whichever pane the CDM's current display mode owns and unchecks
	-- our tab; it does NOT clear which TBT page was last open, so clicking the tab again still
	-- returns the player to the config page if that is where they were.
	--
	-- EventRegistry rather than a script hook: CDMTab.lua's own note above records HookScript
	-- on CooldownViewerSettings as propagating taint in instances, and a callback registration
	-- is neither a frame method call nor a Blizzard mixin call. The owner is ns.tbtPanel, not
	-- ns and not the merge-mode event frame -- CallbackRegistryMixin allows one callback per
	-- owner per event and silently drops the previous one, and MergeMode.lua already owns this
	-- same event under its own frame.
	if EventRegistry then
		EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
			ns:DismissTBTDialogs()
			ns:HideTBTPanel()
		end, ns.tbtPanel)
	end

	AnchorTabBelowCDMTabs()
	TBTSpellsTab:Show()
	TBTSettingsTab:Show()
end

-- Switch the CDM tab between the two tracker categories. The section frames are not rebuilt --
-- RelayoutTBTSections hides the other category's and re-chains the rest, and
-- ns:RefreshTBTSections repopulates the two shared sections with this category's contents.
-- Treat an open dialog as cancelled whenever the thing it was opened from goes away.
--
-- Both float at DIALOG strata over the whole UI rather than inside the CDM window, so neither is
-- taken down by the CDM closing or by a tab change -- an Add dialog would sit there still titled
-- for the tab the player has left, and file its tracker into that tab when clicked. Hiding is the
-- whole of "cancel" here: nothing is committed until Add is clicked, and ResetFields clears the
-- boxes on the next open.
function ns:DismissTBTDialogs()
	if ns.tbtAddDialog then
		ns.tbtAddDialog:Hide()
	end
	if ns.tbtContainerDialog then
		ns.tbtContainerDialog:Hide()
	end
end

function ns:SelectTBTCategory(category)
	if category ~= "spells" and category ~= "buffs" then
		return
	end

	-- Before the swap, not after: what is being added depends on the tab, and carrying a
	-- half-filled dialog across that change would silently re-target it.
	ns:DismissTBTDialogs()

	ns.tbtActiveCategory = category
	TBTSpellsTab:SetChecked(category == "spells")
	TBTSettingsTab:SetChecked(category == "buffs")

	ns:ShowTBTPanel()
	ns.RelayoutTBTSections()
	ns:RefreshTBTSections()
	-- A switch lands at the top rather than at the other tab's scroll offset, which would point
	-- at nothing in particular once the section list changed under it.
	ns.tbtPanel:SetVerticalScroll(0)
end

---------------------------------------------------------------------
-- Config page swap (CFG-01/CFG-02/CFG-04)
---------------------------------------------------------------------

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
	-- Re-entering the TBT tab restores the tracker list.
	ns.tbtPanel:Show()
	ns.tbtPanel:SetFrameLevel(CooldownViewerSettings:GetFrameLevel() + 10)

	-- Uncheck CDM tabs, check ours. Discovered rather than named so a tab added by a patch is
	-- unchecked too (12.1's Group Buffs tab was staying lit behind our panel).
	TBTSpellsTab:SetChecked(ns.tbtActiveCategory == "spells")
	TBTSettingsTab:SetChecked(ns.tbtActiveCategory == "buffs")
	for _, tabButton in ipairs(GetCDMTabs()) do
		if tabButton.SetChecked then
			tabButton:SetChecked(false)
		end
	end
end

function ns:HideTBTPanel()
	-- Reached when the player picks one of Blizzard's own CDM tabs, which is a tab swap as much
	-- as switching between the two TBT tabs is.
	ns:DismissTBTDialogs()
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
	TBTSpellsTab:SetChecked(false)
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
