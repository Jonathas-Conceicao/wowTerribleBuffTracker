local _, ns = ...

-- CDM Tab integration for TerribleBuffTracker.
-- CRITICAL: We must NEVER touch CooldownViewerSettings.TabButtons or call
-- SetDisplayMode with TBT strings — doing so taints CDM's secure code.

-- TBT's own tab icons, shipped under Media/Textures in a faction-themed pair each
-- (icon_<name>_ally / icon_<name>_horde). The TBT logo stays on the TOC and the settings panel.
-- The faction is read once, on first use: every caller (ns:InitCDMTab, gated on
-- PLAYER_ENTERING_WORLD, and the tracker dialog, built when first opened) runs after login, and
-- a character never changes faction within a session. Anything but Horde -- including a
-- Neutral starting Pandaren -- gets the Alliance set.
local TAB_ICON_DIR = "Interface\\AddOns\\TerribleBuffTracker\\Media\\Textures\\"
local tabIconSuffix
local function TabIcon(name)
	if not tabIconSuffix then
		tabIconSuffix = UnitFactionGroup("player") == "Horde" and "_horde" or "_ally"
	end
	return TAB_ICON_DIR .. name .. tabIconSuffix
end

-- Description text for meta-buff tiles in the CDM Suggested section (D-06/D-07 Phase 23).
-- Kept CDMTab-local — this is settings UX text, not provider concern.
local META_DESCRIPTIONS = {
	[ns.META_KEY.TRINKET] = "Tracks all current season's on-use trinkets",
	[ns.META_KEY.POT] = "Tracks all current season's damage potions",
	[ns.META_KEY.LUST] = "Matches all Heroism/Bloodlust effects",
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
	-- Phase 46 (ITEM-01): warm the item catalogue before Suggested draws. Rebuilt unconditionally
	-- here rather than only when dirty -- a CDM open is a rare, user-driven event, and this is
	-- what satisfies the locked cadence's "a bag update with the CDM closed marks the catalogue
	-- dirty; the next open rebuilds it" without needing the dirty flag to be correct across a
	-- whole session.
	ns:RefreshItemCatalogue()
	ns:RefreshTBTSections()
	ns.configOpen = true
	ns:StartAllPreviewTimers()
end

local function StopPreview()
	ns.configOpen = false
	ns:ClearAllTimers()
end

-- Phase 46 (ITEM-01/T-46-06): coalesces a BAG_UPDATE burst into at most one item-catalogue
-- rebuild per frame, and only while the CDM is actually shown. ns.configOpen (set by StartPreview
-- above) is the existing "CDM/config surface is open" flag -- this reuses it rather than
-- inventing a second one.
local itemCatalogueRebuildScheduled = false

local function RequestItemCatalogueRebuild()
	if not ns.configOpen then
		return
	end
	if itemCatalogueRebuildScheduled then
		return
	end
	itemCatalogueRebuildScheduled = true
	C_Timer.After(0, function()
		itemCatalogueRebuildScheduled = false
		-- Re-check both: the CDM may have closed, or the dirty flag may already have been
		-- cleared by another path, in the one frame between scheduling and this callback.
		if ns:IsItemCatalogueDirty() and ns.configOpen then
			ns:RefreshItemCatalogue()
			ns:RefreshTBTSections()
		end
	end)
end

-- Exposed on ns, not called directly: Providers.lua's ns:MarkItemCatalogueDirty() late-binds
-- through this field, guarded, because Providers.lua loads before CDMTab.lua and the field is nil
-- until this file runs. A Lua file-local is an upvalue only to functions declared AFTER it, and
-- this project has produced that bug four times.
ns.RequestItemCatalogueRebuild = RequestItemCatalogueRebuild

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

-- Which tracker category the CDM tab is currently showing: "spells", "buffs" or "reminders".
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
-- which were the same twenty lines twice over. Three key shapes are recognised: the
-- ns.SUGGESTED_KEYS meta keys, "metaItem:<itemID>" bag items and "metaReminder:<spellID>" class buffs.
local function AddSuggestedTracker(key, targetSection)
	-- Only the tile's own key is ever reused. A built-in tracker never touches a user tracker for
	-- the same spell (user decision 2026-09-29): a metaItem:X tile creates or moves
	-- metaItem:X alone, and a user tracker for the same item stays exactly where it is.
	if ns.db.trackedBuffs[key] then
		ns:SetBuffSection(key, targetSection)
		return
	end

	-- A meta tile IS its key; an item tile carries its itemID in the key. Either way the display
	-- info is what fills the entry.
	local itemID = ns:ItemKeyItemID(key)
	-- A class-buff tile (Phase 57.4) is admitted only for a spell in the Providers.lua class-buff
	-- table: a metaReminder key for any other spell creates nothing.
	local metaReminderSpellID = ns:KeyNumericID(key, ns.KIND.META_REMINDER)
	if metaReminderSpellID and not ns:MetaReminderDef(metaReminderSpellID) then
		metaReminderSpellID = nil
	end
	if not itemID and not metaReminderSpellID then
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
		-- Every Suggested key is canonical, so its own kind IS the entry's kind -- Lust mints
		-- metaSkill, trinket/pot/bag items mint metaItem. A meta buff entry carries a kind too.
		-- Class-buff tiles (Phase 57.4) mint metaReminder, whose duration and rank coverage the
		-- next rebuild re-applies from the Providers.lua table (ns:ApplyMetaReminderDef).
		trackerType = ns:KeyKind(key),
		-- An item entry carries no spellID -- writing itemID here would misroute
		-- ApplyCooldownSlot's spellID branch and produce a spell-shaped tooltip and a wrong icon.
		spellID = metaReminderSpellID or nil,
		itemID = itemID or nil,
		-- Not optional and no second chance: an item entry has no spellID, and
		-- ApplyCachedIcon (Display.lua) reads entry.iconOverride straight off the DB entry and
		-- NEVER re-derives it from ns:GetDisplayInfoForKey. Omit this and the tile renders the
		-- 134400 question mark forever, identically for every item, with no error and no log
		-- line. The cooldown-kind sibling above never needed this field, which is exactly what
		-- makes it so easy to omit.
		iconOverride = itemID and info.icon or nil,
	}

	if itemID then
		-- D-05: the one guarded cooldown-and-count read at drop time, made in Providers.lua and
		-- nowhere else. info.duration is always 0 for an item (ns:ItemDisplayInfo), so without
		-- this a potion drunk moments ago would be dragged in looking ready -- wrong, and wrong
		-- in the direction that matters most.
		ns:SeedItemTracker(key, itemID, ns.db.trackedBuffs[key])
	end

	-- The pooled proc buffers for the new key, so its first cast allocates nothing (the pool rule).
	ns:PreallocateProc(key)

	-- The cast path reads the cast indexes (ns.cooldownKeyBySpell etc.), not a per-cast concat,
	-- so a freshly-minted key (e.g. a bag item tile) is invisible to the next cast until
	-- the indexes learn it. ns:RebuildRankIndex runs ns:RebuildCastIndex first, and also builds the
	-- rank families and the rank-aware aura watch, so a new metaReminder (Phase 57.4) answers a
	-- lower-rank cast and reads its aura at once (it refreshes the aura states itself) -- the same
	-- call ns:AddTrackedBuff makes.
	if ns.RebuildRankIndex then
		ns:RebuildRankIndex()
	end

	-- A generation bump, nothing more. ns.trackerGeneration is what
	-- Display.lua's RefreshCooldownSlotCounts stamps its per-container cooldown slot count on --
	-- without this, a container holding only the tracker just created here (item or cooldown) can
	-- stay hidden under hideWhenInactive until some unrelated event happens to bump it. Same
	-- nil-guarded idiom as ns:AddTrackedBuff (BuffEngine.lua).
	if ns.MarkTrackersDirty then
		ns:MarkTrackersDirty()
	end
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

	-- Phase 46 (ITEM-03): charge count, copied field-for-field from Display.lua's
	-- frame.chargeCount (Phase 38, CD-03) -- itself copied from Blizzard's own
	-- CooldownViewerEssentialItemTemplate. Same child Frame + OVERLAY FontString +
	-- NumberFontNormal + BOTTOMRIGHT(-2, 2) construction, same hidden-on-creation state.
	-- Display.lua's "created after the Cooldown so it draws above the swipe" ordering
	-- rationale does not apply here: CreateIconFrame has no Cooldown widget at all (a plain
	-- icon + highlight), so this count fontstring is the only piece being borrowed, not
	-- layered above a swipe that does not exist on this frame.
	f.chargeCount = CreateFrame("Frame", nil, f)
	f.chargeCount:SetAllPoints()
	f.chargeCount.Current = f.chargeCount:CreateFontString(nil, "OVERLAY")
	f.chargeCount.Current:SetFontObject(NumberFontNormal)
	f.chargeCount.Current:SetPoint("BOTTOMRIGHT", -2, 2)
	f.chargeCount:Hide()

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

		-- An item tile gets the ITEM's own tooltip, not a spell-shaped one. ns:ShowBuffTooltip
		-- below is built around SetSpellByID and an item entry carries no spellID at all, so
		-- routing an item through it yields the "Unknown" fallback -- which is what the CDM tab
		-- showed before this branch existed (reported on retail 2026-09-24).
		--
		-- SetItemByID is a GameTooltip method on Blizzard's own shared tooltip, not a CDM frame,
		-- so none of MergeMode.lua's frame prohibitions are in play here.
		--
		-- Covers Suggested and tracked tiles alike: both key on the metaItem:<itemID> shape.
		local hoveredItemID = ns:ItemKeyItemID(self.spellID)
		if hoveredItemID then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			-- Shared with the on-screen icons (Display.lua), including the uncached fallback.
			ns:SetTooltipItem(hoveredItemID)
			local heldCount = ns:TrackedItemCount(self.spellID) or ns:ItemCatalogueCount(hoveredItemID)
			if type(heldCount) == "number" then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(("In bags: %d"):format(heldCount), 1, 1, 1)
			end
			if ns.debugLogging then
				GameTooltip:AddLine(("itemID %d"):format(hoveredItemID), 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
			return
		end

		local info = ns:GetDisplayInfoForKey(self.spellID)
		if not info then
			-- Non-meta user spell with no provider info; still try bare tooltip. self.spellID is
			-- a tracker KEY here, not necessarily a spellID, so this goes through the parser
			-- rather than assuming the key IS a spellID.
			local fallbackSpellID = ns:SpellKeySpellID(self.spellID)
			if fallbackSpellID then
				ns:ShowBuffTooltip(self, { spellID = fallbackSpellID }, {
					showSpellID = true,
				})
				-- Phase 57.3 (LOAD-03): say why a greyed tile is not loaded. Hover-time only.
				local reason = ns:TrackerLoadReason(self.spellID)
				if reason then
					GameTooltip:AddLine(reason, 1, 0.3, 0.3)
					GameTooltip:Show()
				end
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
		-- Phase 57.3 (LOAD-03): say why a greyed tile is not loaded (not known, or Load is Never),
		-- so a tracker that went grey after the update explains itself. Hover-time only.
		local reason = ns:TrackerLoadReason(self.spellID)
		if reason then
			GameTooltip:AddLine(reason, 1, 0.3, 0.3)
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
					-- REM-01: a Suggested tile belongs to the tab showing it, so it is offered
					-- only to containers of that tab's category -- never across categories.
					for _, def in ipairs(ns.CONTAINERS) do
						if ns:GetContainerCategory(def) == ns.tbtActiveCategory then
							rootDescription:CreateButton("Add to " .. def.title, function()
								addSuggestedToSection(def.key)
							end)
						end
					end
					-- D-08: No "Remove" option for suggested items
				end)
				return
			end
			MenuUtil.CreateContextMenu(self, function(_owner, rootDescription)
				-- Tiles are pooled, so the menu acts on the key it was opened for, not whatever
				-- self.spellID holds by the time a button is clicked (54-03). Every button below
				-- uses trackerKey, never self.spellID (WR-03): ns:RefreshTBTSections can re-acquire
				-- this frame for another tracker while the menu is open, and Remove would then
				-- delete the wrong one.
				local trackerKey = self.spellID
				local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[trackerKey]
				-- REM-01: a tracker never moves across categories. Only containers of the
				-- tracker's own category are listed, the menu twin of the drag rule (hidden
				-- sections of another tab are never hit-tested). No entry, no Move to.
				local trackerCategory = entry and ns:GetTrackerCategory(entry)
				if trackerCategory then
					for _, def in ipairs(ns.CONTAINERS) do
						if def.key ~= sectionName and ns:GetContainerCategory(def) == trackerCategory then
							rootDescription:CreateButton("Move to " .. def.title, function()
								ns:SetBuffSection(trackerKey, def.key)
								ns:RefreshTBTSections()
							end)
						end
					end
				end
				if sectionName ~= "hidden" then
					rootDescription:CreateButton("Hide", function()
						ns:SetBuffSection(trackerKey, "hidden")
						ns:RefreshTBTSections()
					end)
				end
				-- userBuff, userCd and userReminder only (EDIT-01, Phase 57.2): Lust, trinket, pot,
				-- class-buff reminders and bag items get no Edit entry.
				-- Reached through the ns field, not a file-local -- CreateIconFrame is declared
				-- above CreateAddDialog, so a file-local ns.tbtAddDialog would still be nil here.
				if ns:IsEditableTracker(entry) then
					rootDescription:CreateButton("Edit", function()
						ns.tbtAddDialog.OpenForEdit(trackerKey)
					end)
				end
				rootDescription:CreateDivider()
				rootDescription:CreateButton("Remove", function()
					ns:RemoveTrackedBuff(trackerKey)
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

	-- Phase 57.4 review WR-03: a Suggested tile never deletes (EndDrag cancels it), so the delete
	-- zone does not light up for one.
	SetDeleteZoneHighlight(overDelete and not tbtDragState.isFromSuggested)

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
		tbtDragState.suggestedKey = iconFrame.spellID -- string key e.g. metaSkill:lust
	end

	-- Show ghost at cursor; resolve class-aware icon for suggested items
	local ghost = GetOrCreateGhostFrame()
	-- Resolve class-aware / meta-aware icon via unified dispatch (D-15 Phase 23). iconFrame.spellID
	-- is a tracker KEY, not necessarily a spellID, so the bare-icon fallback goes through the
	-- parser instead of assuming the key IS a spellID.
	local ghostInfo = ns:GetDisplayInfoForKey(iconFrame.spellID)
	local ghostIconID = (ghostInfo and ghostInfo.icon) or ns:GetSpellIcon(ns:SpellKeySpellID(iconFrame.spellID))
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
			-- Phase 57.4 review WR-03: a Suggested tile is a catalogue entry, not a tracker. A
			-- class-buff tile stays offered once tracked and carries the placed
			-- tracker's key, so deleting by that key removed the tracker the user placed. A drag
			-- that started in Suggested cancels here like a drop back on Suggested.
			if not tbtDragState.isFromSuggested then
				local spellID = tbtDragState.spellID
				wipe(tbtDragState)
				ns:RemoveTrackedBuff(spellID)
				ns:RefreshTBTSections()
				PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
				return
			end
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
		-- nil, "suggested", or a Suggested tile on "delete" → cancel silently (D-04, D-05, WR-03)
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
		-- Phase 46 (S10): a pooled frame keeps its previous tile's charge count. Clearing it
		-- here, once, covers both acquisition paths -- a freshly created frame is already
		-- hidden by CreateIconFrame's own f.chargeCount:Hide(), and a recycled frame is
		-- cleared by ReleaseAll() running this reset function at the top of every
		-- ns:RefreshTBTSections pass. The discipline lives here, not in the itemPool:Acquire()
		-- call sites -- each tile loop only needs to Show()/SetText() when a count applies.
		frame.chargeCount.Current:SetText("")
		frame.chargeCount:Hide()
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

-- One tile per Suggested key, used by the class-buff tiles (Reminders tab, Phase 57.4). The key is stored opaquely in item.spellID, which every shared
-- handler (drag, tooltip, right-click) reads. Pooled frames must lose a previous tile's grey and
-- count, so both are cleared here.
local function PlaceSuggestedKeyTile(section, key, slot)
	local item = section.itemPool:Acquire()
	local info = ns:GetDisplayInfoForKey(key)
	item.spellID = key
	item.Icon:SetTexture((info and info.icon) or 134400)
	item.Icon:SetDesaturated(false)
	item.chargeCount:Hide()
	item.sectionName = "suggested"
	item.layoutIndex = slot
	item:Show()
	return item
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

			-- The catalogue tiles are all buff meta-trackers (lust, trinket, pot), so
			-- they belong to the Buffs tab. The + and settings squares are NOT part of this --
			-- they occupy the reserved slots and are built once in ns:BuildAllSections, so they
			-- stay put under either tab, which is what the user asked for.
			if def.key == "suggested" and ns.tbtActiveCategory == "spells" then
				-- The Cooldowns tab offers the bag-derived item catalogue and nothing else: every
				-- other catalogue entry is a buff meta-tracker.
				local suggestedSlot = SUGGESTED_RESERVED_SLOTS

				-- Phase 46 (ITEM-03): the bag-derived item catalogue. No ns:IsSuggestedKeyResolvable call here -- that
				-- function answers "does this provider's catalog exist on this client at all",
				-- which has no meaning for a bag-derived, per-character-inventory list; the
				-- item builder's own taxonomy filter (classID/subClassID/use-spell) already
				-- decides membership, and it is baked into what ns:ItemCatalogue() contains.
				-- This loop only reads the cache ns:RefreshItemCatalogue already built (CDM-open
				-- scan + BAG_UPDATE dirty flag, Plan 02) -- no C_Container/C_Item call belongs
				-- on this render path.
				--
				-- Dragging an item tile into a container creates a real metaItem:<itemID>
				-- tracker entry (ITEM-04, Phase 47) -- AddSuggestedTracker now resolves
				-- ns:ItemKeyItemID(key) as a valid key shape alongside a metaReminder
				-- key and a ns.SUGGESTED_KEYS member. Once tracked, the
				-- metaItem:<itemID> entry below is what makes it drop out of this loop
				-- (ITEM-02) -- no separate removal code needed.
				for _, itemID in ipairs(ns:ItemCatalogue()) do
					local itemKey = ns:TrackerKey(ns.KIND.META_ITEM, itemID)
					if not ns.db.trackedBuffs[itemKey] then
						suggestedSlot = suggestedSlot + 1
						local item = section.itemPool:Acquire()
						local info = ns:GetDisplayInfoForKey(itemKey)
						-- Opaque tracker key stored in the existing spellID field, not a new
						-- item.itemID field -- every shared handler (drag, tooltip, right-click)
						-- reads self.spellID and already treats it as opaque (Core.lua:466-467).
						item.spellID = itemKey
						item.Icon:SetTexture((info and info.icon) or 134400)
						-- Item tiles have no unsupported state, but a pooled frame keeps the
						-- previous tile's desaturation.
						item.Icon:SetDesaturated(false)
						item.sectionName = "suggested"
						-- No item.suggestedIndex: grep -n suggestedIndex CDMTab.lua finds only
						-- the two write sites above and no reader -- there is nothing to index
						-- into for a bag-derived list, so adding one here would be noise.
						local count = ns:ItemCatalogueCount(itemID)
						if count then
							item.chargeCount.Current:SetText(count)
							item.chargeCount:Show()
						else
							-- The scan-time issecretvalue()/type() guard rejected this count at
							-- catalogue build time; degrade the tile rather than show a stale or
							-- wrong value (D-03/S10).
							item.chargeCount:Hide()
						end
						item.layoutIndex = suggestedSlot
						item:Show()
					end
				end
			elseif def.key == "suggested" and ns.tbtActiveCategory ~= "buffs" then
				-- Only the Reminders tab reaches this branch (the Cooldowns tab takes the one
				-- above). Phase 57.4 (MREM-02): the class buffs this character knows, for this
				-- client (rows are tagged per client in Providers.lua's MetaReminderRow).
				-- A tile stays after its reminder exists, so dragging it again moves that
				-- reminder (AddSuggestedTracker). The + and settings squares keep slots 1-2.
				local suggestedSlot = SUGGESTED_RESERVED_SLOTS
				for _, reminderKey in ipairs(ns:MetaReminderSuggestionKeys()) do
					suggestedSlot = suggestedSlot + 1
					PlaceSuggestedKeyTile(section, reminderKey, suggestedSlot)
				end
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
						item.spellID = suggestedKey -- string key metaSkill:lust / metaItem:trinket / metaItem:pot
						item.Icon:SetTexture(iconID)
						-- A tile whose provider reports unsupported is greyed rather than hidden;
						-- written on every tile because item frames are pooled.
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
					--
					-- The loop variable is named spellID but holds the tracker KEY. Phase 57.3
					-- (LOAD-03): the TBT tab lists EVERY tracker, loaded or not -- one that is not
					-- loaded is drawn greyed below, and stays draggable, editable and deletable.
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
					local iconID = (displayInfo and displayInfo.icon)
						or ns:GetSpellIcon(ns:SpellKeySpellID(info.spellID))
					item.Icon:SetTexture(iconID)
					-- Phase 57.3 (LOAD-03): a tracker that is not loaded is desaturated, exactly as
					-- Blizzard's CDM settings show an unlearned spell
					-- (CooldownViewerSettings.lua:174, Icon:SetDesaturated(not isKnown)), no alpha
					-- change. Written on every pooled tile every pass, so a recycled tile never
					-- inherits the grey.
					item.Icon:SetDesaturated(not ns:IsTrackerLoaded(info.spellID))
					-- An item tracker keeps its count here, not only in Suggested. Reported on
					-- retail 2026-09-24: the number showed on the Suggested tile and then vanished
					-- the moment the item was dragged into a container or into Not Displayed,
					-- because this branch -- the one that draws every TRACKED entry -- never wrote
					-- the fontstring the Suggested branch does.
					--
					-- Written on EVERY tile every pass, not only on item ones: these frames are
					-- pooled, so a tile recycled from an item into a spell must lose the number
					-- rather than inherit it. Same rule the SetDesaturated call above follows, and
					-- the same trap its own comment records in the Suggested branch.
					local trackedItemID = ns:ItemKeyItemID(info.spellID)
					local trackedCount = trackedItemID and ns:TrackedItemCount(info.spellID)
					if type(trackedCount) == "number" then
						item.chargeCount.Current:SetText(trackedCount)
						item.chargeCount:Show()
					else
						item.chargeCount.Current:SetText("")
						item.chargeCount:Hide()
					end
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

-- The inverse of ParseDuration, used by edit-mode prefill (54-03) to show a saved duration back
-- to the player. Never produces exponent notation (no %g, no tostring of a number): a bare number
-- is seconds, as the field always meant, and every result this produces parses back through
-- ParseDuration.
--
-- Length rule: every value the duration box itself can produce formats to at most 6 characters,
-- the box's SetMaxLetters(6) (worst cases "99999m", "999999", "5999.4" from "99.99m", "59.994"
-- from ".9999m"); the %.4f form may round (".12345" shows as "0.1235"), which is harmless because
-- the duration field's read returns the saved number untouched while the box text is unchanged;
-- only a legacy or hand-edited saved value can format longer than 6, and for that case the
-- duration field's prefill raises that box's max letters to fit. Chosen as the simplest option
-- (over comparing numbers in read): EditBox:SetText is clamped to the max letters, so without the
-- raise a long saved value would be shown truncated.
local function FormatDuration(seconds)
	if type(seconds) ~= "number" or seconds <= 0 then
		return ""
	end

	if seconds == math.floor(seconds) then
		if seconds >= 60 and seconds % 60 == 0 then
			return ("%.0fm"):format(seconds / 60)
		end
		return ("%.0f"):format(seconds)
	end

	local text = ("%.4f"):format(seconds)
	text = (text:gsub("0+$", ""))
	text = (text:gsub("%.$", ""))
	return text
end

-- CONTEXT's art choice for the secret-aura badge. Referenced on classic branches, which does
-- not prove it ships on Forever, so the badge falls back to text when C_Texture.GetAtlasInfo
-- does not know it.
local SECRECY_BADGE_ATLAS = "transmog-icon-warning-small"

-- ADD-06: the CDM mask + overlay atlases and the 50px icon offsets (-9, 8 / 9, -8) of Blizzard's
-- CooldownViewerEssentialItemTemplate (wow-ui-source CooldownViewer.xml). Display.lua's own icons
-- use smaller offsets for their smaller sizes; these match the essential template alone.
local PORTRAIT_SIZE = 50
local CDM_ICON_MASK_ATLAS = "UI-HUD-CoolDownManager-Mask"
local CDM_ICON_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"

-- Shared render for an ID preview: the portrait (spellPreview, below) and Plan 03's aura ID row
-- both call this from their own update. The caller's state table must already hold:
--   icon          texture to set (ARTWORK, already masked by the caller)
--   name          FontString to set
--   hover         the mouse region ns:ShowBuffTooltip anchors to and IsOwned checks against
--   tooltipProc   the { spellID, label } table the caller's OnEnter hands to ShowBuffTooltip
--   tooltipOpts   the tooltip options table the caller's OnEnter hands to ShowBuffTooltip
--   generation    number, built at 0 and never reset by the caller -- bumped here on every
--                 resolution (including a late resolution of an ID that was still unknown), so a
--                 sibling field can key its own cache on it (WR-01) instead of the ID alone
-- and this function owns, in the caller's state table:
--   shownID, resolved   the ID last rendered and whether it resolved
--   spellID             the resolved ID, or nil while empty/unresolved (what tooltipProc mirrors)
function ns:RefreshIDPreview(state, id)
	if id == state.shownID and state.resolved then
		return
	end

	if id <= 0 then
		state.shownID = id
		state.resolved = true
		state.spellID = nil
		state.tooltipProc.spellID = nil
		-- A dimmed placeholder, not a hidden texture, so the 50px slot never collapses to a
		-- bare border while the box is empty.
		state.icon:SetTexture(134400)
		state.icon:SetDesaturated(true)
		state.icon:SetAlpha(0.4)
		state.name:SetText("")
		-- The row is now empty, so a tooltip the mouse had open on it goes too.
		if GameTooltip:IsOwned(state.hover) then
			GameTooltip:Hide()
		end
		return
	end

	local spellName, iconID = ns:SpellPreview(id)
	-- Retry path: an ID the client had not cached when it was typed is re-queried on every later
	-- dialog change (a Duration keystroke, for example) until it resolves, instead of sticking on
	-- "Unknown spell" forever. This costs one pcall'd lookup per change, and only while the row is
	-- still unknown.
	if id == state.shownID and spellName == nil then
		return
	end

	state.shownID = id
	state.resolved = spellName ~= nil
	state.icon:SetDesaturated(false)
	state.icon:SetAlpha(1)

	if spellName then
		state.generation = state.generation + 1
		state.icon:SetTexture(iconID)
		state.name:SetText(spellName)
		state.name:SetTextColor(1, 1, 1)
	else
		state.icon:SetTexture(134400)
		state.name:SetText("Unknown spell")
		state.name:SetTextColor(0.6, 0.6, 0.6)
	end

	state.spellID = id
	-- The box is a 10-digit numeric field, and ShowBuffTooltip's GetSpellInfo call is unguarded:
	-- past the 32-bit spell ID range it gets a nil target instead.
	state.tooltipProc.spellID = id <= 2147483647 and id or nil

	-- IN-04: a tooltip already open on this row (the mouse resting on it while the ID is typed) is
	-- redrawn for the new spell. Only reached when the row changed.
	if GameTooltip:IsOwned(state.hover) then
		ns:ShowBuffTooltip(state.hover, state.tooltipProc, state.tooltipOpts)
	end
end

-- Shared builder for the "secret?" badge: the portrait's corner badge (secrecyBadge, below) and
-- Plan 03's aura ID row both call this. `state` must be the CALLER's own already-declared table
-- (declared before this call, per the closure-binding rule) -- the OnEnter closure below reads
-- state.level from it. Placement (SetPoint, SetFrameLevel) is the caller's job, not this one's.
function ns:BuildSecrecyBadge(parent, state)
	local badge = CreateFrame("Frame", nil, parent)
	badge:EnableMouse(true)

	-- Art decided once, here at build, rather than re-checked on every update.
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SECRECY_BADGE_ATLAS) then
		badge:SetSize(16, 16)
		local tex = badge:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints()
		tex:SetAtlas(SECRECY_BADGE_ATLAS)
	else
		badge:SetSize(56, 16)
		local text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetAllPoints()
		text:SetText("(secret?)")
	end

	badge:SetScript("OnEnter", function()
		GameTooltip_SetDefaultAnchor(GameTooltip, badge)
		GameTooltip:SetText(ns:SecrecyLine(state.level) or "", 1, 0.82, 0)
		local explanation = ns:SecrecyExplanation(state.level)
		if explanation then
			GameTooltip:AddLine(explanation, 1, 1, 1, true)
		end
		local scopeNote = ns:SecrecyScopeNote()
		if scopeNote then
			GameTooltip:AddLine(scopeNote, 0.5, 0.5, 0.5, true)
		end
		GameTooltip:Show()
	end)
	badge:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return badge
end

-- The spell-ID list boxes (the cast-rule box and the alternatives box, below) cap at this many
-- distinct spell IDs.
local MAX_CAST_RULE_IDS = 8

-- Parses a spell-ID list box's comma-separated text (the cast rule or the alternatives). Returns
-- nil for blank input (no rule stored), a FRESH array of positive integer spell IDs for valid
-- input (read stores this array directly, so the saved entry never aliases the dialog's own
-- state), or `false, message` for malformed input.
-- Whitespace is ignored; duplicate IDs are dropped silently and do not count against the cap.
-- Phase 57 review IN-07: empty tokens are ignored too, so "123," or "123, " -- the moment the user
-- types the separator for the next ID -- is not flagged as malformed, and text holding only
-- separators stores no rule, like blank input.
function ns:ParseSpellIDList(text)
	if type(text) ~= "string" then
		return nil
	end
	local compact = text:gsub("%s", "")
	if compact == "" then
		return nil
	end

	local list = {}
	local seen = {}
	for token in (compact .. ","):gmatch("([^,]*),") do
		if token ~= "" then
			if not token:match("^%d+$") then
				return false, "Use spell IDs separated by commas"
			end
			local id = tonumber(token)
			if id < 1 or id > 2147483647 then
				return false, "Spell ID is out of range"
			end
			if not seen[id] then
				seen[id] = true
				list[#list + 1] = id
				if #list > MAX_CAST_RULE_IDS then
					return false, "At most " .. MAX_CAST_RULE_IDS .. " spell IDs"
				end
			end
		end
	end

	if #list == 0 then
		return nil
	end
	return list
end

-- The Load rule's choices (Phase 57.3, LOAD-01), in menu order. When known is the default and is
-- stored as nil; Always and Never are stored as their ns.LOAD strings. Declared above
-- TRACKER_FIELDS, the file-local that reads it.
local LOAD_CHOICES = {
	{ text = "When known", value = ns.LOAD.KNOWN },
	{ text = "Always", value = ns.LOAD.ALWAYS },
	{ text = "Never", value = ns.LOAD.NEVER },
}

-- Phase 58: the WowStyle1DropdownTemplate + SetupMenu + CreateRadio pattern shared by both radio
-- dropdowns (the Load field below and CreateContainerDialog's category). One radio per choice, in
-- order. The generator is built once per dropdown, at build time, never per frame; each caller
-- keeps its own isSelected/setSelected, built once outside the generator.
local function SetupRadioMenu(dropdown, choices, isSelected, setSelected)
	dropdown:SetupMenu(function(_, rootDescription)
		for i = 1, #choices do
			local choice = choices[i]
			rootDescription:CreateRadio(choice.text, isSelected, setSelected, choice.value)
		end
	end)
end

-- Phase 57.5 (RALT-01): the spell-ID list row, shared by the buff/cooldown cast rule (endOnCast)
-- and the reminder alternatives list. File-locals above TRACKER_FIELDS, their only reader.
local function BuildSpellListField(row, y, onChange, dialog)
	-- An EARLIER sibling, captured at build like every other cross-field read here.
	local spell = dialog.GetFieldState("spellID")

	-- The "(comma separated)" label is the widest in the dialog (user decision 2026-09-29):
	-- bounded to the row's width and kept to one line, so it can never wrap down over the
	-- box -- the dialog was widened to 260 to give it that line.
	local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y)
	label:SetWidth(216)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)

	local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	box:SetSize(180, 22)
	box:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y - 18)
	box:SetMaxLetters(96)
	box:SetAutoFocus(false)
	box:SetScript("OnTextChanged", onChange)

	-- Up to MAX_CAST_RULE_IDS small icons previewing each parsed ID, populated by update.
	local icons = {}
	for i = 1, MAX_CAST_RULE_IDS do
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(16, 16)
		icon:SetPoint("TOPLEFT", row, "TOPLEFT", 32 + (i - 1) * 20, y - 44)
		icon:Hide()
		icons[i] = icon
	end

	return { editBox = box, label = label, spell = spell, icons = icons }, y - 64
end

-- Fills the box from a saved list. A joined COPY of the saved array, never the array itself --
-- typing in the box must never mutate the saved entry.
local function SetSpellListText(state, list)
	state.editBox:SetText(type(list) == "table" and table.concat(list, ", ") or "")
	state.shownText = nil
end

local function UpdateSpellListIcons(state)
	local text = state.editBox:GetText()
	-- Compare before writing; the row is re-queried while any ID is still unknown, the
	-- same retry shape as ns:RefreshIDPreview's.
	if text == state.shownText and not state.pendingUnknown then
		return
	end
	state.shownText = text
	state.pendingUnknown = false

	local list = ns:ParseSpellIDList(text)
	for i = 1, MAX_CAST_RULE_IDS do
		local id = type(list) == "table" and list[i]
		local icon = state.icons[i]
		if id then
			local name, iconID = ns:SpellPreview(id)
			if name then
				icon:SetTexture(iconID)
				icon:SetVertexColor(1, 1, 1)
			else
				icon:SetTexture(134400)
				icon:SetVertexColor(1, 0.3, 0.3)
				state.pendingUnknown = true
			end
			icon:Show()
		else
			icon:Hide()
		end
	end
end

local function ReadSpellList(state)
	-- Blank stores nothing; a read nil clears a previously saved rule on edit.
	local list = ns:ParseSpellIDList(state.editBox:GetText())
	return type(list) == "table" and list or nil
end

local function ValidateSpellList(state)
	local list, message = ns:ParseSpellIDList(state.editBox:GetText())
	if list == false then
		return false, message
	end
	if type(list) == "table" then
		local ownID = state.spell.editBox:GetNumber()
		for i = 1, #list do
			if list[i] == ownID then
				return false, "Remove this tracker's own spell ID"
			end
		end
	end
	return true
end

-- One "follows the Spell ID" field: a numeric box prefilled with, and kept in step with, the
-- Spell ID box until the user types in it, with an icon + name preview and a spell tooltip on
-- hover. Both the Aura ID and the Cast spell ID fields are built by it (Phase 65, D-01).
-- opts.id          the field id and the saved entry key
-- opts.label       the text above the box
-- opts.tooLarge    the validate message for an ID past 32 bits
-- opts.visible     the field's visible(state, ctx) hook
-- opts.secrecy     true: the tooltip carries the scope note and a secrecy badge describes this
--                  ID's own aura (the Aura ID field)
-- opts.emptyIsNone true: a box the user emptied reads false and previews "No click action"
--                  instead of the Spell ID's spell (the Cast spell ID field)
local function BuildFollowSpellIDField(opts)
	local key = opts.id
	return {
		id = key,
		entryKey = key,
		tab = "advanced",
		visible = opts.visible,
		build = function(row, y, onChange, dialog)
			-- An EARLIER sibling, captured at build like every other cross-field read here.
			local spell = dialog.GetFieldState("spellID")

			local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetText(opts.label)
			label:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y)

			local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
			box:SetSize(180, 22)
			box:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y - 18)
			box:SetNumeric(true)
			box:SetMaxLetters(10)
			box:SetAutoFocus(false)

			local hover = CreateFrame("Frame", nil, row)
			hover:SetSize(130, 20)
			hover:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y - 44)
			hover:EnableMouse(true)

			local icon = hover:CreateTexture(nil, "ARTWORK")
			icon:SetSize(18, 18)
			icon:SetPoint("LEFT", hover, "LEFT", 0, 0)

			local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
			name:SetWidth(108)
			name:SetJustifyH("LEFT")
			name:SetWordWrap(false)

			-- Built once here, not per hover: ShowBuffTooltip reads whatever these hold at
			-- OnEnter time, and update keeps tooltipProc.spellID in step with the box. One
			-- instance per row, mirroring the portrait's own tooltipProc/tooltipOpts above.
			local tooltipProc = { spellID = nil, label = "Unknown spell" }
			local tooltipOpts = { showSpellID = true }
			if opts.secrecy then
				-- IN-01: the secrecy line on this tooltip describes THIS ID's own aura, which may
				-- differ from the spell ID's -- one static note says so.
				local scopeNote = ns:SecrecyScopeNote()
				if scopeNote then
					tooltipOpts.extraLines = { scopeNote }
				end
			end

			-- Declared before any SetScript below and before ns:BuildSecrecyBadge: every closure
			-- reads this same table. A table literal built only at the return would leave them
			-- bound to the nil global state, and every hover would raise.
			local state = {
				editBox = box,
				spell = spell,
				hover = hover,
				icon = icon,
				name = name,
				tooltipProc = tooltipProc,
				tooltipOpts = tooltipOpts,
				generation = 0,
				-- Phase 57.1: true while the box has not yet been edited by the user, so update
				-- keeps writing the Spell ID box's text into it. A programmatic SetText (the
				-- follow itself, or reset/prefill) passes userInput false, so following is
				-- unaffected by our own writes -- only a real keystroke turns it off.
				followsSpell = true,
			}

			-- Phase 57.1: prefilled and kept in step with the Spell ID box until the user types
			-- here (D-02 is retired: the box is never blank by default any more).
			box:SetScript("OnTextChanged", function(_, userInput)
				-- Review IN-02: the follow write in update runs inside RefreshState's own loop,
				-- which already updates the later fields and validates -- no nested refresh.
				if state.syncing then
					return
				end
				if userInput then
					state.followsSpell = false
				end
				onChange()
			end)

			hover:SetScript("OnEnter", function()
				if state.spellID then
					ns:ShowBuffTooltip(hover, state.tooltipProc, state.tooltipOpts)
				end
			end)
			hover:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			if opts.secrecy then
				-- The badge describes the AURA ID's own secrecy (D-02), independent of the
				-- portrait's badge, which describes the spell ID's.
				state.badge = ns:BuildSecrecyBadge(row, state)
				state.badge:SetPoint("LEFT", hover, "RIGHT", 6, 0)
				state.badge:Hide()
			end

			return state, y - 72
		end,
		reset = function(state)
			-- Blank here, not the spell ID: the first update (which always runs before the
			-- dialog is shown) fills it in via the follow below, so a freshly opened Add dialog
			-- still ends up showing the spell's own ID.
			state.followsSpell = true
			state.editBox:SetText("")
			state.shownID = nil
			state.resolved = nil
			state.spellID = nil
			if opts.secrecy then
				state.level = nil
				state.checkedID = nil
				state.checkedGen = nil
				state.badge:Hide()
			end
		end,
		prefill = function(state, entry)
			-- No saved ID means the field follows the spell (the prefilled default); a saved
			-- ID, even one equal to the spell ID, means the user is done following. A saved
			-- false (no click action) is not nil, so it prefills an empty, non-following box.
			state.followsSpell = entry[key] == nil
			state.editBox:SetText(entry[key] and tostring(entry[key]) or "")
			state.shownID = nil
			state.resolved = nil
			if opts.secrecy then
				state.checkedID = nil
			end
		end,
		update = function(state)
			-- Phase 57.1: while following, keep this box's text in step with the Spell ID box.
			-- Compare before writing, and write under state.syncing: SetText fires this field's
			-- own OnTextChanged synchronously, which returns early while syncing is set instead
			-- of starting a nested RefreshState from inside this loop.
			if state.followsSpell then
				local spellText = state.spell.editBox:GetText()
				if state.editBox:GetText() ~= spellText then
					state.syncing = true
					state.editBox:SetText(spellText)
					state.syncing = false
				end
			end

			local typed = state.editBox:GetNumber()
			-- A box the user emptied means "no click action" (e.g. a reminder for a buff another
			-- class gives you), so the preview says so instead of showing the Spell ID's spell.
			if opts.emptyIsNone and not state.followsSpell and typed <= 0 then
				ns:RefreshIDPreview(state, 0)
				state.name:SetText("No click action")
				return
			end
			local id = typed > 0 and typed or state.spell.editBox:GetNumber()
			ns:RefreshIDPreview(state, id)

			if not opts.secrecy then
				return
			end
			-- The badge describes the secrecy of whatever ID this box holds, including while it
			-- follows the spell (Phase 57.1 fills the box with the spell ID then). The portrait's
			-- own badge sits on General, so on Advanced this one is the only secrecy cue in view.
			-- Only a blank box (badgeID 0) leaves the level nil and the badge hidden.
			local badgeID = typed > 0 and typed or 0
			-- Compare-before-write, keyed like secrecyBadge: an ID the client resolves late is
			-- asked again once.
			if badgeID == state.checkedID and state.generation == state.checkedGen then
				return
			end
			state.checkedID = badgeID
			state.checkedGen = state.generation
			state.level = badgeID > 0 and ns:SpellAuraSecrecy(badgeID) or nil
			state.badge:SetShown(ns:SecrecyWarns(state.level) and true or false)
		end,
		read = function(state)
			-- Blank or equal to the spell ID stores nothing (the default); a read nil clears a
			-- previously saved ID on edit. A box the user emptied reads false for emptyIsNone
			-- (no click action, the same value a built-in row uses, Blood Pact).
			local typed = state.editBox:GetNumber()
			if typed <= 0 then
				if opts.emptyIsNone and not state.followsSpell then
					return false
				end
				return nil
			end
			if typed ~= state.spell.editBox:GetNumber() then
				return typed
			end
			return nil
		end,
		validate = function(state)
			-- The aura read APIs take 32-bit IDs. Review WR-02: skipped while following, since
			-- the text is then the Spell ID's own, and that field reports its own range error.
			if not state.followsSpell and state.editBox:GetNumber() > 2147483647 then
				return false, opts.tooLarge
			end
			return true
		end,
	}
end

-- THE FIELD DEFINITION CONTRACT (EDIT-03; 54-CONTEXT "One dialog, two modes"). TRACKER_FIELDS is
-- one ordered array literal that drives the Add dialog end to end: a new field is one entry here;
-- neither the add nor the edit path names a field. Each element is a table with:
--   id             string, unique -- how siblings find it: dialog.GetFieldState(id). GetFieldState
--                  is declared BEFORE the build loop, so a field's build may anchor to a sibling
--                  built EARLIER in this array; a later sibling is not built yet and returns nil.
--   entryKey       the saved-entry field this field owns, or nil for a display-only field that is
--                  never read or stored. spellID and duration are passed to the engine
--                  positionally; every other entryKey travels in fields/fieldKeys.
--   tab            "general" | "advanced" | nil for both (Phase 57.1). Read by RefreshState to
--                  compute field.shown alongside visible() -- see the tab-hidden sentence below.
--   available()    optional. The BUILD-TIME capability gate, evaluated ONCE at build; false means
--                  never built, no row, no space.
--   visible(state, ctx)  optional. The RUNTIME show/hide hook, evaluated on every open and after
--                  every state change; absent means always visible. This is the ONLY hook that
--                  can make a field irrelevant (field.relevant = false): a field hidden by its
--                  own visible() takes no space, is not validated, is skipped by Tab, and is not
--                  read. NOT READ MEANS NOT WRITTEN (WR-02) applies to THIS case only: an edit
--                  saved while such a field is hidden keeps that field's saved value untouched --
--                  only a field that was relevant and read can change or clear its entry key. Add
--                  has no saved value to keep, so an irrelevant field simply stores nothing there.
-- Tab-hidden fields are still validated and read; defaults are stored as nil.
--   build(row, y, onChange, dialog) -> state, nextY  creates this field's widgets on row, wires
--                  every value change to onChange, and returns a per-field state table plus the
--                  cursor for the NEXT row, gap included.
--   reset(state, ctx)          add-mode defaults.
--   prefill(state, entry, ctx) edit-mode values from the saved entry; prefill copies a table value
--                  rather than aliasing it, so editing the dialog cannot mutate the saved entry.
--   update(state, ctx, dialog) optional, runs on every change before visibility and validation;
--                  update must compare before writing to a sibling widget, or the dialog recurses
--                  without end.
--   read(state, ctx) -> value  nil means store nothing; read returns a fresh table for a
--                  table-valued field, never the state's own table.
--   validate(state, ctx) -> ok, message  ok=false disables confirm; the first failing RELEVANT
--                  field (field.relevant, both tabs) with a message wins; a message from a
--                  `tab = "advanced"` field is shown prefixed "Advanced: ".
--
-- ctx is one reusable table on the dialog: { mode = "add" | "edit", kind = ns.KIND.USER_BUFF |
-- ns.KIND.USER_CD | ns.KIND.USER_REMINDER, editingKey = key | nil }. The saved entry is not kept
-- on ctx: prefill receives it as an argument, and nothing else needs it.
--
-- Layout (the walker owns vertical placement): Layout() starts its cursor at -38, under the title
-- (its own comment inside CreateAddDialog still calls this "the original Spell ID label offset";
-- that body is kept byte-identical, and the first row there is the portrait now), anchors each
-- built field's row TOPLEFT to the dialog at the running offset (or hides it when not shown),
-- then anchors the error label TOP at the final offset and resizes the dialog to fit -- so the
-- error label always sits after the last visible row.
--
-- A display-only field (the portrait and the secret-aura badge) has no entryKey, keeps no
-- editBox key in its own state table (or it would join the Tab/Enter ring), and may return
-- nextY = y unchanged to take no vertical space of its own. It reaches a sibling's state either
-- through dialog.GetFieldState at BUILD time (an EARLIER sibling only -- a later one is not
-- built yet and returns nil), or at UPDATE time (ANY sibling: every field is built before the
-- first update runs, and update receives the dialog as its third argument). The portrait
-- (spellPreview) uses the update-time form, because it is FIRST in TRACKER_FIELDS and spellID
-- is not built yet when it builds.
--
-- Order is load-bearing. The portrait (spellPreview) is FIRST, so it draws under the title, and
-- it reads the Spell ID box at UPDATE time rather than build time -- see the display-only
-- paragraph above. During an open, the SetText in spellID's reset/prefill fires a RefreshState
-- while LATER fields still hold the previous open's state (secrecyBadge and duration can then
-- run against stale state on that pass), and the portrait and duration are only correct because
-- the walker's closing RefreshState(true) runs after every field's reset/prefill. secrecyBadge
-- and duration capture spellPreview's and spellID's states at BUILD time and read spellPreview's
-- generation in their own update, so both must come after both.
-- Keep spellPreview, spellID, secrecyBadge, duration in that order, and never make a
-- field's update depend on a LATER field having been reset, except the portrait's documented
-- update-time read of the Spell ID box.
--
-- Advanced tab (Phase 57.1, per kind since 57.2). No master checkbox and no saved mode flag:
-- `auraID`, `keepOnAuraLoss`, `endOnCast` and `alternatives` (in that order) are tagged
-- `tab = "advanced"` and simply prefilled with their defaults -- the aura ID box follows the Spell
-- ID box (`state.followsSpell`) until the user types in it, cancellation on aura loss starts
-- checked, the cast rule and the alternatives list start empty. Saving a field still holding its
-- default stores nil (aura ID equal to the spell ID, cancellation checked, an empty rule are ALL
-- stored as nil), so the runtime
-- keys on the saved VALUE, never on a flag. Per kind, through each field's own visible() hook:
-- - a buff sees auraID, keepOnAuraLoss and the cast rule, "Ends when you cast (comma separated):";
-- - a reminder (a buff tracker in its own category, user decision 2026-09-29) sees auraID,
--   keepOnAuraLoss and `alternatives`, "Also satisfied by (comma separated):", in place of the
--   cast rule (RALT-01, Phase 57.5: the one deliberate divergence from "reminders are buffs");
-- - a cooldown sees only the cast rule, labelled "Resets when you cast (comma separated):".
-- The cast rule and the alternatives list are the same spell-ID list row (BuildSpellListField and
-- its siblings, above), stored as nil when empty. The runtime readers are BuffEngine.lua's
-- `ns:DetailedAuraID`, `ns:CancelsOnAuraLoss` and `ns:ApplyEndOnCast`, Core.lua's
-- `ns:RebuildDetailedRuleIndex`, and for `alternatives` Core.lua's
-- `ns:RebuildDetailedRuleIndex` and `ns:RebuildReminderWatch` (57.5-02). General never
-- becomes invalid or disabled because of a value on Advanced (57.1-CONTEXT).
-- A reminder also sees `castID` ("Cast spell ID:", Phase 63, CLICK-06), prefilled following the
-- Spell ID and stored nil when equal, false when emptied (no click action); its runtime reader is
-- Providers.lua's `ns:ReminderCastID`.
-- Built-ins never open this dialog, so their cast spell stays table-driven.
-- `load` (Phase 57.3, LOAD-01) comes LAST on Advanced, after the spell-ID list, for every kind -- it
-- has no visible() hook, so a cooldown, a buff and a reminder all show it. When known is stored
-- as nil; Always / Never as their ns.LOAD strings. The runtime reader is Core.lua's
-- `ns:TrackerLoad`. A built-in tracker's load is fixed and it never opens this dialog.
--
-- Multi-choice settings (REM-04, user direction): the chosen control for any future multi-choice
-- field is a DropdownButton from WowStyle1DropdownTemplate set up with SetupMenu and CreateRadio,
-- one `rootDescription:CreateRadio(text, IsSelected, SetSelected, value)` per choice, with
-- IsSelected / SetSelected built once per build (not inside the generator) and `GenerateMenu()`
-- called after a change made outside the menu so the button text follows. All of it exists on
-- both retail and the Forever beta. The removed visibility field used it; the live examples are
-- now the `load` field below (in this dialog) and CreateContainerDialog's category choice, which
-- share SetupRadioMenu (above) since Phase 58.
--
-- Hazard: TRACKER_FIELDS is a file-local read by CreateAddDialog; it and every helper its
-- functions call (ParseDuration, DURATION_HINT, FormatDuration, ns:RefreshIDPreview,
-- ns:BuildSecrecyBadge, ns:ParseSpellIDList, the PORTRAIT_SIZE /
-- CDM_ICON_MASK_ATLAS / CDM_ICON_OVERLAY_ATLAS / MAX_CAST_RULE_IDS constants) must be declared
-- ABOVE CreateAddDialog. A helper declared lower in the file (e.g. AddExclusiveCheck) is nil to
-- these functions -- do not call it from a field def.
local TRACKER_FIELDS = {
	{
		id = "spellPreview",
		build = function(row, y, onChange, dialog)
			local hover = CreateFrame("Frame", nil, row)
			hover:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
			hover:SetPoint("TOP", row, "TOPLEFT", 120, y - 10)
			hover:EnableMouse(true)

			local icon = hover:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints()

			-- IN-01: each CDM atlas is applied only when the client knows it, the same guard the
			-- secrecy badge uses. Without the mask the icon stays square; without the overlay it
			-- has no border. Neither is a Lua error.
			local canCheckAtlas = C_Texture and C_Texture.GetAtlasInfo
			if canCheckAtlas and C_Texture.GetAtlasInfo(CDM_ICON_MASK_ATLAS) then
				local mask = hover:CreateMaskTexture()
				mask:SetAtlas(CDM_ICON_MASK_ATLAS)
				mask:SetAllPoints()
				icon:AddMaskTexture(mask)
			end

			if canCheckAtlas and C_Texture.GetAtlasInfo(CDM_ICON_OVERLAY_ATLAS) then
				local overlay = hover:CreateTexture(nil, "OVERLAY")
				overlay:SetAtlas(CDM_ICON_OVERLAY_ATLAS)
				overlay:SetPoint("TOPLEFT", -9, 8)
				overlay:SetPoint("BOTTOMRIGHT", 9, -8)
			end

			local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			name:SetPoint("TOP", hover, "BOTTOM", 0, -6)
			name:SetWidth(208)
			name:SetJustifyH("CENTER")
			name:SetWordWrap(false)

			-- Built once here, not per hover: ShowBuffTooltip reads whatever these hold at
			-- OnEnter time, and update keeps tooltipProc.spellID in step with the box.
			local tooltipProc = { spellID = nil, label = "Unknown spell" }
			local tooltipOpts = { showSpellID = true }
			-- IN-01: the secrecy line on this tooltip describes THIS ID's own aura, which is
			-- not always the buff's; one static note says so (none without the secrecy API).
			local scopeNote = ns:SecrecyScopeNote()
			if scopeNote then
				tooltipOpts.extraLines = { scopeNote }
			end

			-- Declared before either SetScript below: the OnEnter closure reads this same
			-- table. A table literal built only at the return would leave the closure bound
			-- to the nil global state, and every hover would raise.
			local state = {
				hover = hover,
				icon = icon,
				name = name,
				tooltipProc = tooltipProc,
				tooltipOpts = tooltipOpts,
				-- Bumped every time RefreshIDPreview resolves a spell (including a late
				-- resolution of an ID that was still unknown). Never reset: secrecyBadge and
				-- duration compare it with the value they last saw, so a late resolution
				-- re-runs their lookups.
				generation = 0,
			}

			hover:SetScript("OnEnter", function()
				if state.spellID then
					ns:ShowBuffTooltip(hover, state.tooltipProc, state.tooltipOpts)
				end
			end)
			hover:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			-- 10px top pad clears the title, then the 50px portrait, a 6px gap, and the name
			-- line below it.
			return state, y - 90
		end,
		reset = function(state)
			-- No widget work: the closing RefreshState(true) of every open renders it.
			state.shownID = nil
			state.resolved = nil
			state.spellID = nil
		end,
		prefill = function(state)
			state.shownID = nil
			state.resolved = nil
		end,
		update = function(state, ctx, dialog)
			-- The one and only place this entry reaches the Spell ID box: at UPDATE time,
			-- since spellPreview is FIRST in TRACKER_FIELDS and spellID is not built yet.
			local source = dialog.GetFieldState("spellID")
			if not source then
				return
			end
			ns:RefreshIDPreview(state, source.editBox:GetNumber())
		end,
		validate = function()
			return true
		end,
	},
	{
		id = "spellID",
		entryKey = "spellID",
		tab = "general",
		build = function(row, y, onChange, dialog)
			local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetText("Spell ID:")
			label:SetPoint("TOPLEFT", row, "TOPLEFT", 16, y)

			y = y - 18
			local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
			box:SetSize(180, 22)
			box:SetPoint("TOPLEFT", row, "TOPLEFT", 16, y)
			box:SetNumeric(true)
			box:SetMaxLetters(10)
			box:SetAutoFocus(false)
			box:SetScript("OnTextChanged", onChange)

			return { editBox = box }, y - 32
		end,
		reset = function(state)
			state.editBox:SetText("")
		end,
		prefill = function(state, entry)
			state.editBox:SetText(tostring(entry.spellID or ""))
		end,
		read = function(state)
			return state.editBox:GetNumber()
		end,
		validate = function(state, ctx)
			local spellID = state.editBox:GetNumber()
			if not spellID or spellID <= 0 then
				return false
			end
			-- Review WR-02: the 10-digit box allows values past the 32-bit spell ID range. Checked
			-- here, on General, so the message names the field the user actually typed in.
			if spellID > 2147483647 then
				return false, "Spell ID is too large"
			end
			local conflictKey = ns:FindTrackerConflict(ctx.kind, spellID, ctx.editingKey)
			if conflictKey then
				return false, "Already tracked as a " .. ns:TrackerKindWord(ctx.kind)
			end
			return true
		end,
	},
	{
		id = "secrecyBadge",
		tab = "general",
		build = function(row, y, onChange, dialog)
			local preview = dialog.GetFieldState("spellPreview")
			local source = dialog.GetFieldState("spellID")

			-- Declared before ns:BuildSecrecyBadge below: its OnEnter closure reads
			-- state.level from this same table, so it must already exist when the helper
			-- wires the closures. A table literal built only at the return would leave the
			-- closure bound to the nil global state, and every hover would raise.
			local state = { source = source, preview = preview }
			state.badge = ns:BuildSecrecyBadge(row, state)
			-- The atlas badge sits over the portrait's top-right corner; the text fallback
			-- extends right from there, still inside the 240px dialog.
			state.badge:SetPoint("BOTTOMLEFT", preview.hover, "TOPRIGHT", -10, -10)
			-- The badge's row and the portrait's row are siblings at the same frame level,
			-- so without raising it the portrait could draw over the badge and swallow its
			-- hover.
			state.badge:SetFrameLevel(preview.hover:GetFrameLevel() + 5)

			-- No vertical space of its own: the badge sits on the portrait row's corner.
			return state, y
		end,
		reset = function(state)
			state.checkedID = nil
			state.level = nil
		end,
		prefill = function(state)
			state.checkedID = nil
		end,
		update = function(state)
			-- Keyed on the ID AND the preview's resolution count (spellPreview updates first,
			-- so its count is current here): an ID the client resolves late is asked again,
			-- instead of keeping the answer it gave while the spell was still unknown.
			local id = state.source.editBox:GetNumber()
			local gen = state.preview.generation
			if id == state.checkedID and gen == state.checkedGen then
				return
			end
			state.checkedID = id
			state.checkedGen = gen
			state.level = id > 0 and ns:SpellAuraSecrecy(id) or nil
		end,
		-- Shown on BOTH tabs by user decision: this entry never branches on the tracker kind.
		-- A client without the secrecy API yields a nil level, so the badge simply never shows.
		visible = function(state)
			return ns:SecrecyWarns(state.level)
		end,
		validate = function()
			return true
		end,
	},
	{
		id = "duration",
		entryKey = "duration",
		tab = "general",
		build = function(row, y, onChange, dialog)
			local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetText("Duration (30, 45s, 2m):")
			label:SetPoint("TOPLEFT", row, "TOPLEFT", 16, y)

			y = y - 18
			local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
			box:SetSize(180, 22)
			box:SetPoint("TOPLEFT", row, "TOPLEFT", 16, y)
			box:SetMaxLetters(6)
			box:SetAutoFocus(false)
			box:SetScript("OnTextChanged", onChange)

			-- Same gap as the spell ID row above. Captured once, like spellPreview and
			-- secrecyBadge above: update reads state.source.editBox:GetNumber() live on every
			-- call, so ADD-05's suggestion always sees the box's current number, and reads the
			-- preview's resolution count so a late-resolving ID is suggested for too.
			local source = dialog.GetFieldState("spellID")
			local preview = dialog.GetFieldState("spellPreview")
			return { editBox = box, source = source, preview = preview }, y - 32
		end,
		reset = function(state)
			state.editBox:SetMaxLetters(6)
			state.editBox:SetText("")
			state.originalText = nil
			state.originalValue = nil
			state.suggestedForID = nil
			state.suggestionText = nil
		end,
		prefill = function(state, entry)
			state.originalValue = entry.duration
			state.originalText = FormatDuration(entry.duration)
			-- A saved value longer than 6 characters is shown whole, never truncated; the next
			-- reset restores 6.
			state.editBox:SetMaxLetters(math.max(6, #state.originalText))
			state.editBox:SetText(state.originalText)
			-- The prefilled saved value is the user's; with no suggestion text recorded, update
			-- can never mistake it for a suggestion and overwrite it.
			state.suggestedForID = nil
			state.suggestionText = nil
		end,
		-- ADD-05: suggest a duration while the box is still empty or holds exactly the
		-- previous suggestion. A cooldown tracker gets the game's cooldown; a buff or reminder
		-- tracker (ns.BUFF_LIKE_KINDS) gets the live aura's duration when the buff is on the
		-- player and readable, and nothing otherwise (the game has no static buff-duration API).
		-- A reminder saved with no duration (an earlier v10 build) prefills empty, and validate
		-- refuses an empty box, so it must be given a duration before it saves.
		update = function(state, ctx)
			local isCd = ctx.kind == ns.KIND.USER_CD
			if not isCd and not ns.BUFF_LIKE_KINDS[ctx.kind] then
				return
			end

			-- Compare before writing anything: this also runs on the nested RefreshState that
			-- our own SetText below fires, and on every Duration keystroke, so an unchanged ID
			-- must return here before doing any work. The preview's resolution count is part of
			-- the key: an ID the client resolves late is asked again once, and the nested pass
			-- from our own SetText sees both unchanged.
			local id = state.source.editBox:GetNumber()
			local gen = state.preview and state.preview.generation
			if id == state.suggestedForID and gen == state.suggestedGen then
				return
			end
			state.suggestedForID = id
			state.suggestedGen = gen

			-- The user typed something, or an edit prefilled it, and it is not the suggestion
			-- this field itself last wrote -- never touch it.
			local text = state.editBox:GetText()
			if text ~= "" and text ~= state.suggestionText then
				return
			end

			local seconds
			if id > 0 then
				if isCd then
					seconds = ns:SuggestedCooldown(id)
				else
					seconds = ns:SuggestedBuffDuration(id)
				end
			end
			local newText = seconds and FormatDuration(seconds) or ""
			-- The box holds 6 letters; a longer suggestion would be saved as a different,
			-- truncated number, so it is dropped instead of written.
			if #newText > 6 then
				newText = ""
			end

			-- Recorded before SetText: a new ID with no cooldown clears a held suggestion back
			-- to empty, leaving manual entry.
			state.suggestionText = newText ~= "" and newText or nil
			if newText ~= text then
				state.editBox:SetText(newText)
			end
		end,
		read = function(state)
			local text = state.editBox:GetText()
			if state.originalText ~= nil and text == state.originalText then
				return state.originalValue
			end
			return ParseDuration(text)
		end,
		validate = function(state)
			local text = state.editBox:GetText()
			if text == "" then
				return false
			end
			if not ParseDuration(text) then
				return false, DURATION_HINT
			end
			return true
		end,
	},
	{
		id = "coverAllRanks",
		entryKey = "coverAllRanks",
		tab = "general",
		available = function()
			return ns.CLIENT_HAS_SPELL_RANKS
		end,
		-- Cover all ranks (ADD-03): created only when the client-capability flag defined once in
		-- Core.lua is true -- absent on retail, not hidden or disabled. This is that flag's only
		-- reader. No leading gap here: the duration row's returned cursor already includes it.
		build = function(row, y, onChange, dialog)
			local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			check:SetSize(24, 24)
			check:SetPoint("TOPLEFT", row, "TOPLEFT", 16, y)
			check:SetChecked(true)
			check:SetScript("OnClick", onChange)

			local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetPoint("LEFT", check, "RIGHT", 4, 0)
			label:SetText("Cover all ranks")

			return { check = check }, y - 26
		end,
		reset = function(state)
			state.check:SetChecked(true)
		end,
		prefill = function(state, entry)
			state.check:SetChecked(entry.coverAllRanks == true)
		end,
		read = function(state)
			return state.check:GetChecked() and true or nil
		end,
		validate = function()
			return true
		end,
	},
	-- A cooldown's aura ID drove only the removed visibility option, and schema v10 dropped
	-- the saved key (REM-04). Buffs and reminders keep it: prefilled, following the Spell ID
	-- until typed in, stored nil when equal.
	BuildFollowSpellIDField({
		id = "auraID",
		label = "Aura ID:",
		tooLarge = "Aura ID is too large",
		secrecy = true,
		visible = function(_, ctx)
			return ctx.kind ~= ns.KIND.USER_CD
		end,
	}),
	{
		id = "keepOnAuraLoss",
		entryKey = "keepOnAuraLoss",
		tab = "advanced",
		build = function(row, y, onChange, dialog)
			local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			check:SetSize(24, 24)
			check:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y)
			check:SetChecked(true)
			check:SetScript("OnClick", onChange)

			local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetPoint("LEFT", check, "RIGHT", 4, 0)
			label:SetText("End when the aura is lost")

			return { check = check }, y - 26
		end,
		reset = function(state)
			-- Default ON (the prefilled Advanced default).
			state.check:SetChecked(true)
		end,
		prefill = function(state, entry)
			-- A missing key means cancellation is ON.
			state.check:SetChecked(not entry.keepOnAuraLoss)
		end,
		read = function(state)
			-- Stored only when opted out; a missing key means cancellation stays on (the default).
			return (not state.check:GetChecked()) and true or nil
		end,
		validate = function()
			return true
		end,
		visible = function(state, ctx)
			-- A cooldown has no aura behind it and never enters ns.activeTimers, while a buff and
			-- a reminder both do: buff-like only, not just gated by its tab.
			return ns.BUFF_LIKE_KINDS[ctx.kind] == true
		end,
	},
	{
		-- RALT-01 (Phase 57.5): hidden for a reminder, whose list is its alternatives (the next
		-- field). A buff and a cooldown keep this cast rule exactly as before.
		id = "endOnCast",
		entryKey = "endOnCast",
		tab = "advanced",
		build = BuildSpellListField,
		reset = function(state, ctx)
			state.label:SetText(
				ctx.kind == ns.KIND.USER_CD and "Resets when you cast (comma separated):"
					or "Ends when you cast (comma separated):"
			)
			SetSpellListText(state, nil)
		end,
		prefill = function(state, entry, ctx)
			state.label:SetText(
				ctx.kind == ns.KIND.USER_CD and "Resets when you cast (comma separated):"
					or "Ends when you cast (comma separated):"
			)
			SetSpellListText(state, entry.endOnCast)
		end,
		update = UpdateSpellListIcons,
		read = ReadSpellList,
		validate = ValidateSpellList,
		visible = function(state, ctx)
			return not ns.REMINDER_KINDS[ctx.kind]
		end,
	},
	{
		-- RALT-01 (Phase 57.5): a reminder's "Also satisfied by" list, in place of the cast rule --
		-- the one deliberate divergence from "reminders are buffs" (user decision 2026-09-29). A
		-- reminder is satisfied by its own buff or any listed buff, present or running from a cast.
		-- Same spell-ID list row as the cast rule; stored as nil when empty.
		id = "alternatives",
		entryKey = "alternatives",
		tab = "advanced",
		build = BuildSpellListField,
		reset = function(state)
			state.label:SetText("Also satisfied by (comma separated):")
			SetSpellListText(state, nil)
		end,
		prefill = function(state, entry)
			state.label:SetText("Also satisfied by (comma separated):")
			SetSpellListText(state, entry.alternatives)
		end,
		update = UpdateSpellListIcons,
		read = ReadSpellList,
		validate = ValidateSpellList,
		visible = function(state, ctx)
			return ns.REMINDER_KINDS[ctx.kind] == true
		end,
	},
	-- Phase 63 (CLICK-06): the spell a click on this reminder casts. Prefilled and following the
	-- Spell ID box until typed in; stored nil when equal to it, false when emptied (no click
	-- action, for a buff the character cannot cast). Reminders only.
	BuildFollowSpellIDField({
		id = "castID",
		label = "Cast spell ID:",
		tooLarge = "Cast spell ID is too large",
		emptyIsNone = true,
		visible = function(_, ctx)
			return ns.REMINDER_KINDS[ctx.kind] == true
		end,
	}),
	{
		-- Phase 57.3 (LOAD-01): whether this tracker runs at all. Never called "visibility" --
		-- containers already have one. No visible() hook: every user kind gets it.
		id = "load",
		entryKey = "load",
		tab = "advanced",
		build = function(row, y, onChange)
			local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y)
			label:SetText("Load:")

			local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
			dropdown:SetSize(180, 22)
			dropdown:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y - 18)

			local state = { dropdown = dropdown, selected = ns.LOAD.KNOWN }
			-- Built once here, not inside the menu generator, which SetupMenu/GenerateMenu may
			-- call more than once per open.
			local function IsSelected(value)
				return state.selected == value
			end
			local function SetSelected(value)
				state.selected = value
				onChange()
			end
			SetupRadioMenu(dropdown, LOAD_CHOICES, IsSelected, SetSelected)

			return state, y - 46
		end,
		reset = function(state)
			state.selected = ns.LOAD.KNOWN
			-- A change made outside the menu needs GenerateMenu so the button text follows
			-- (Blizzard_Menu/DropdownButton.lua).
			state.dropdown:GenerateMenu()
		end,
		prefill = function(state, entry)
			local saved = entry.load
			if saved == ns.LOAD.ALWAYS or saved == ns.LOAD.NEVER then
				state.selected = saved
			else
				state.selected = ns.LOAD.KNOWN
			end
			state.dropdown:GenerateMenu()
		end,
		read = function(state)
			-- When known is the default and is stored as nil; an edit back to it clears the key.
			if state.selected == ns.LOAD.KNOWN then
				return nil
			end
			return state.selected
		end,
		validate = function()
			return true
		end,
	},
}

-- What the + square adds, by the tab showing it: its tooltip and the add dialog's title.
-- File-local and declared above CreateAddDialog so both readers see it (a local declared below
-- its caller is nil at runtime). Read on hover and on dialog open only, never per frame.
local ADD_TITLE_BY_CATEGORY = {
	spells = "Add Cooldown Tracker",
	buffs = "Add Buff Tracker",
	reminders = "Add Reminder",
}

-- The edit dialog's title by the saved entry's kind (only ns:IsEditableTracker kinds open it).
-- Beside ADD_TITLE_BY_CATEGORY for the same reason: above CreateAddDialog, read on open only.
local EDIT_TITLE_BY_KIND = {
	[ns.KIND.USER_CD] = "Edit Cooldown Tracker",
	[ns.KIND.USER_BUFF] = "Edit Buff Tracker",
	[ns.KIND.USER_REMINDER] = "Edit Reminder",
}

-- The add/edit and New Container dialogs share one look: Blizzard's panel art, ButtonFrameTemplate
-- -- the same template CooldownViewerSettings inherits on both retail and the Forever beta -- with
-- the portrait hidden and no attic (nothing sits on top of the content well). Its Inset is the
-- content well (top edge 24px under the title bar, plus a 10px gap) and its bottom 26px are the
-- button bar (plus the same gap). Buttons sit flush with the no-portrait Inset's edges (x=9, 6px
-- short of the right) and 4px up, MagicButton_OnLoad's offsets. The add/edit dialog's
-- General/Advanced tabs are LargeSideTabButtonTemplate icon tabs hanging off the right edge,
-- placed exactly like the CDM settings window's (first tab TOPLEFT to the frame's TOPRIGHT at
-- 0,-28, each next one TOP to the previous BOTTOM at y -3). Icons are 30px, TBT's own CDM side-tab
-- icon size.
local DIALOG_BUTTON_LEFT_X = 9
local DIALOG_BUTTON_RIGHT_X = -6
local DIALOG_BUTTON_Y = 4
local DIALOG_CONTENT_TOP = -34
local DIALOG_CONTENT_BOTTOM = 36
local DIALOG_SIDE_TAB_X = 0
local DIALOG_SIDE_TAB_Y = -28
local DIALOG_SIDE_TAB_GAP = -3
local DIALOG_SIDE_TAB_ICON_SIZE = 30
-- 184px of content plus the content top and bottom.
local CONTAINER_DIALOG_HEIGHT = 254

-- Builds one dialog frame. The built-in close button hides the dialog exactly like Cancel does --
-- set directly rather than left on UIPanelCloseButton_OnClick, whose HideUIPanel is meant for
-- frames the UIParent panel manager owns. Runs once per dialog at creation, never per frame.
function ns:CreatePanelDialog(name)
	local dialog = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	-- Neither dialog puts anything in the attic (the add/edit dialog's tabs hang off the right
	-- edge), so the content well starts right under the title bar. Must run before HidePortrait,
	-- which re-applies the Inset's no-portrait x offset over whatever TOPLEFT point it finds.
	ButtonFrameTemplate_HideAttic(dialog)
	ButtonFrameTemplate_HidePortrait(dialog)
	dialog.CloseButton:SetScript("OnClick", function()
		dialog:Hide()
	end)
	dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
	-- DIALOG strata so it renders above everything, including the CDM settings window.
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(200)
	dialog:Hide()
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

	table.insert(UISpecialFrames, name)

	return dialog
end

-- Replaces SidePanelTabButtonMixin:SetChecked on the dialog's side tabs: the mixin version calls
-- Icon:SetAtlas(activeAtlas/inactiveAtlas), which would wipe a file texture. Only the selected
-- highlight changes with the state; the icon is set once at creation.
local function SetDialogSideTabChecked(tab, checked)
	tab.SelectedTexture:SetShown(checked and true or false)
end

-- Builds one dialog side tab. The template's own OnMouseDown/OnMouseUp keep the icon nudge
-- and click sound; the hook below only reports a left click released over the tab. upInside is
-- nil-tolerant in case a client does not pass it. The tooltip comes from the mixin's OnEnter,
-- which reads tooltipText. Runs once per tab at dialog creation, never per frame. The icon is a
-- file shipped with the addon, so no per-flavour guard is needed.
function ns:CreateDialogSideTab(dialog, tooltipText, iconPath, iconSize, onSelect)
	local tab = CreateFrame("Frame", nil, dialog, "LargeSideTabButtonTemplate")
	tab.tooltipText = tooltipText
	tab.SetChecked = SetDialogSideTabChecked
	tab.Icon:SetTexture(iconPath)
	tab.Icon:SetSize(iconSize, iconSize)
	tab:SetChecked(false)
	tab:HookScript("OnMouseUp", function(_, button, upInside)
		if button == "LeftButton" and upInside ~= false then
			onSelect()
		end
	end)
	return tab
end

-- The add/edit dialog's width, shared by the dialog and every field row. 260 rather than the
-- original 240 so the spell-ID list rows' "(comma separated)" labels (the cast rule and the
-- alternatives) fit on one line (see BuildSpellListField).
local ADD_DIALOG_WIDTH = 260

local function CreateAddDialog()
	local dialog = ns:CreatePanelDialog("TBTAddBuffDialog")

	-- Title. Set from the active tab in dialog.OpenForAdd rather than fixed, because the tab is
	-- now the only thing that decides what is being added -- see the Type note below.
	dialog:SetTitle("Add Tracker")

	-- ctx is the one reusable table describing what this open of the dialog means -- see the
	-- field definition contract above TRACKER_FIELDS. Wiped and refilled on every OpenForAdd (and
	-- 54-03's OpenForEdit), never reassigned.
	local ctx = {}
	dialog.ctx = ctx

	-- Every field built below is tracked here rather than by name, so the dialog names no
	-- individual field: fieldStates is the ordered walk list, fieldById answers
	-- dialog.GetFieldState, focusRing is the Tab/Enter ring, values is the reused table the
	-- confirm handler fills from every visible field's read before handing it to the engine, and
	-- readKeys is the reused array of exactly the entry keys that were read -- the only keys an
	-- edit may write (WR-02: a hidden field keeps its saved value).
	local fieldStates = {}
	local fieldById = {}
	local focusRing = {}
	local values = {}
	local readKeys = {}

	-- Declared before the build loop so a field's build may anchor to an earlier sibling built
	-- earlier in TRACKER_FIELDS (a later sibling is not built yet and returns nil).
	dialog.GetFieldState = function(id)
		local field = fieldById[id]
		return field and field.state
	end

	-- Forward-declared: the per-field onChange closure below calls it, but it is only assigned
	-- after Layout exists.
	local RefreshState

	-- Phase 57.1: which tab is selected right now. Read by RefreshState below to decide each
	-- field's field.shown; written only by SelectTab, created with the side tabs after
	-- FocusFirstShown near the end of this function.
	local currentTab = "general"

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
	for _, def in ipairs(TRACKER_FIELDS) do
		if not def.available or def.available() then
			local row = CreateFrame("Frame", nil, dialog)
			row:SetSize(ADD_DIALOG_WIDTH, 1)
			local state, nextY = def.build(row, 0, function()
				RefreshState()
			end, dialog)
			local field = { def = def, state = state, row = row, height = -nextY }
			row:SetHeight(field.height)
			fieldStates[#fieldStates + 1] = field
			fieldById[def.id] = field
			if state.editBox then
				focusRing[#focusRing + 1] = { box = state.editBox, field = field }
			end
		end
	end

	-- Error label. Given a width and centred so the duration hint wraps to a second line instead
	-- of running out past the dialog's edge. Layout anchors it below the last visible row.
	local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontRed")
	errorLabel:SetWidth(208)
	errorLabel:SetJustifyH("CENTER")
	errorLabel:SetText("")
	dialog.errorLabel = errorLabel

	-- Whether Layout reserved room for the error label. The label takes space only while it has
	-- a message, so an empty label leaves no gap above the buttons; RefreshState re-lays out
	-- only when this flips.
	local errorShown = false

	-- Confirm button. Text is "Add" here and set to "Save" by 54-03's OpenForEdit.
	local confirmBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	confirmBtn:SetSize(80, 22)
	confirmBtn:SetText("Add")
	confirmBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", DIALOG_BUTTON_LEFT_X, DIALOG_BUTTON_Y)

	-- Cancel button
	local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancelBtn:SetSize(80, 22)
	cancelBtn:SetText("Cancel")
	cancelBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", DIALOG_BUTTON_RIGHT_X, DIALOG_BUTTON_Y)
	cancelBtn:SetScript("OnClick", function()
		dialog:Hide()
	end)

	-- The walker that owns vertical placement: anchors every SHOWN row in order starting at the
	-- dialog's content top, hides every other row, then anchors the
	-- error label below the last visible row and resizes the dialog to fit. Called on every open
	-- and whenever a field's visibility changes.
	local function Layout()
		local y = DIALOG_CONTENT_TOP
		for _, field in ipairs(fieldStates) do
			if field.shown then
				field.row:ClearAllPoints()
				field.row:SetPoint("TOPLEFT", dialog, "TOPLEFT", 0, y)
				field.row:Show()
				y = y - field.height
			else
				field.row:Hide()
			end
		end

		errorLabel:ClearAllPoints()
		errorLabel:SetPoint("TOP", dialog, "TOP", 0, y)
		if errorShown then
			y = y - 32
		end

		-- Single height computation, driven by whatever is actually visible -- no second
		-- flavour branch on the literal height. The error label always sits after the last
		-- visible row (W2: retail's label used to overlap the Duration box), and takes room
		-- only while it shows a message.
		dialog:SetSize(ADD_DIALOG_WIDTH, math.abs(y) + DIALOG_CONTENT_BOTTOM)
	end

	-- Sets the error label and re-lays out only when it goes from empty to non-empty or back,
	-- so the dialog grows to fit a message and closes the gap again once it clears.
	local function ShowError(text)
		errorLabel:SetText(text)
		local hasError = text ~= ""
		if hasError ~= errorShown then
			errorShown = hasError
			Layout()
		end
	end

	-- The walk shared by live validation and the confirm click: a RELEVANT field is validated
	-- whether or not its tab is the one currently shown (Phase 57.1 -- both tabs' fields are part
	-- of the tracker now, unlike the old detailed-hidden rule), so a bad value on the hidden tab
	-- still disables confirm. A field hidden by its OWN visible() (e.g. keepOnAuraLoss on a
	-- cooldown) is not relevant and is never validated. The first failing relevant field with a
	-- message wins; when that field's tab is "advanced", the message is prefixed "Advanced: " so a
	-- user looking at General knows where to look -- the concatenation runs only here, on a
	-- failing validation, never per frame.
	local function ValidateAll()
		local allOk = true
		local message = ""
		for _, field in ipairs(fieldStates) do
			if field.relevant then
				local def, state = field.def, field.state
				local ok, msg = def.validate(state, ctx)
				if not ok then
					allOk = false
					if message == "" and msg then
						message = (def.tab == "advanced") and ("Advanced: " .. msg) or msg
					end
				end
			end
		end
		return allOk, message
	end

	-- Runs on every field change: updates live-derived fields, re-evaluates every field's
	-- visibility (re-laying out only when something actually changed, or when forced on open),
	-- then re-validates and enables/disables confirm. A field never adds a leading gap for
	-- itself -- build already returned the cursor for the next row, gap included.
	RefreshState = function(forceLayout)
		for _, field in ipairs(fieldStates) do
			local def, state = field.def, field.state
			if def.update then
				def.update(state, ctx, dialog)
			end
		end

		-- Phase 57.1: relevant is the field's own visible() answer, independent of the tab; shown
		-- additionally requires the field's tab (if any) to be the one currently selected. Layout
		-- and the Tab/Enter ring walk field.shown only, so the dialog's height and focus order
		-- follow the current tab; ValidateAll and confirm walk field.relevant, so a value on the
		-- other tab is still checked and saved.
		local dirty = forceLayout and true or false
		for _, field in ipairs(fieldStates) do
			local def, state = field.def, field.state
			local relevant = not def.visible or (def.visible(state, ctx) and true or false)
			local shown = relevant and (not def.tab or def.tab == currentTab)
			field.relevant = relevant
			if shown ~= field.shown then
				field.shown = shown
				dirty = true
			end
		end
		if dirty then
			Layout()
		end

		local allOk, message = ValidateAll()
		ShowError(message)
		confirmBtn:SetEnabled(allOk)
	end
	dialog.RefreshState = RefreshState

	-- Tab/Enter ring over every field that owns an EditBox, wrapping and skipping a hidden
	-- field's box; gives up after one full lap rather than looping forever if every box in the
	-- ring is hidden.
	for i, entry in ipairs(focusRing) do
		entry.box:SetScript("OnTabPressed", function()
			local nextIndex = i
			for _ = 1, #focusRing do
				nextIndex = (nextIndex % #focusRing) + 1
				local candidate = focusRing[nextIndex]
				if candidate.field.shown then
					candidate.box:SetFocus()
					return
				end
			end
		end)
		entry.box:SetScript("OnEnterPressed", function()
			confirmBtn:Click()
		end)
	end

	-- Phase 57.1: the one focus rule OpenForAdd, OpenForEdit and a tab click all share -- focuses
	-- the first SHOWN box in the ring, or nothing if every box in the ring is hidden.
	local function FocusFirstShown()
		for _, entry in ipairs(focusRing) do
			if entry.field.shown then
				entry.box:SetFocus()
				return
			end
		end
	end

	-- Phase 57.1: the General/Advanced tabs, icon side tabs hanging off the dialog's right edge
	-- (see the dialog constants above ns:CreatePanelDialog). Declared after FocusFirstShown, since
	-- SelectTab calls it.
	local iconSize = DIALOG_SIDE_TAB_ICON_SIZE
	local generalSideTab, advancedSideTab

	-- The one tab switch a tab click and an open share. Runs on a tab click or an open, never per
	-- frame.
	local function SelectTab(which)
		currentTab = which
		generalSideTab:SetChecked(which == "general")
		advancedSideTab:SetChecked(which == "advanced")
		RefreshState(true)
		if dialog:IsShown() then
			FocusFirstShown()
		end
	end

	-- What OpenForAdd and OpenForEdit call to land on General.
	local function SelectGeneral()
		SelectTab("general")
	end

	generalSideTab = ns:CreateDialogSideTab(dialog, "General", TabIcon("icon_info"), iconSize, SelectGeneral)
	generalSideTab:SetPoint("TOPLEFT", dialog, "TOPRIGHT", DIALOG_SIDE_TAB_X, DIALOG_SIDE_TAB_Y)
	advancedSideTab = ns:CreateDialogSideTab(dialog, "Advanced", TabIcon("icon_advanced"), iconSize, function()
		SelectTab("advanced")
	end)
	advancedSideTab:SetPoint("TOP", generalSideTab, "BOTTOM", 0, DIALOG_SIDE_TAB_GAP)

	confirmBtn:SetScript("OnClick", function()
		-- Re-validated rather than trusting the last RefreshState pass: the button being
		-- enabled is a UI state, and this is the one that decides what gets stored.
		local allOk, message = ValidateAll()
		if not allOk then
			if message ~= "" then
				ShowError(message)
			end
			return
		end

		-- Phase 57.1: a RELEVANT field is read regardless of which tab is selected -- a field
		-- hidden only by its tab is still part of the tracker and must be saved. Only a field
		-- hidden by its OWN visible() (e.g. keepOnAuraLoss on a cooldown, the Cooldowns-tab
		-- opt-out) is absent from both values and readKeys, so ns:UpdateTrackedBuff leaves its
		-- saved value alone instead of writing nil over it (WR-02).
		wipe(values)
		wipe(readKeys)
		for _, field in ipairs(fieldStates) do
			local entryKey = field.def.entryKey
			if field.relevant and entryKey then
				values[entryKey] = field.def.read(field.state, ctx)
				readKeys[#readKeys + 1] = entryKey
			end
		end

		if ctx.mode == "add" then
			local ok, reason = ns:AddTrackedBuff(values.spellID, values.duration, nil, {
				trackerType = ctx.kind,
				section = "hidden",
				fields = values,
			})
			if not ok then
				ShowError(reason or "")
				return
			end
			ns:RefreshTBTSections()
			ns:StartAllPreviewTimers()
			dialog:Hide()
		elseif ctx.mode == "edit" then
			-- Same post-commit calls as add; no field is named here either. On refusal (a
			-- same-slot duplicate, or the tracker vanishing under the open dialog) the engine
			-- writes nothing, so the reason is shown and the dialog stays open unchanged
			-- (54-CONTEXT "Duplicate rejection ... tracker is left unchanged").
			local ok, reason = ns:UpdateTrackedBuff(ctx.editingKey, values.spellID, values.duration, values, readKeys)
			if not ok then
				ShowError(reason or "")
				return
			end
			ns:RefreshTBTSections()
			ns:StartAllPreviewTimers()
			dialog:Hide()
		end
	end)

	dialog.OpenForAdd = function()
		wipe(ctx)
		ctx.mode = "add"
		-- Read at open time, not at click time: the tab cannot change while a modal dialog is
		-- up, since ns:SelectTBTCategory calls ns:DismissTBTDialogs.
		local category = ns.tbtActiveCategory
		if category == "spells" then
			ctx.kind = ns.KIND.USER_CD
		elseif category == "reminders" then
			ctx.kind = ns.KIND.USER_REMINDER
		else
			ctx.kind = ns.KIND.USER_BUFF
		end

		-- The title is the whole of the type UI now, so it is the one thing that must be right
		-- every time the dialog opens.
		dialog:SetTitle(ADD_TITLE_BY_CATEGORY[category] or ADD_TITLE_BY_CATEGORY.buffs)
		confirmBtn:SetText("Add")

		for _, field in ipairs(fieldStates) do
			field.def.reset(field.state, ctx)
		end

		-- Phase 57.1: opening always selects General (57.1-CONTEXT). SelectGeneral runs
		-- SelectTab above, which forces the layout and re-validates, so rows and
		-- dialog size already match the fields' visibility before Show; an empty dialog opens
		-- with Add disabled.
		SelectGeneral()
		dialog:Show()
		FocusFirstShown()
	end

	-- 54-03 (EDIT-01/02/03): the same frame as OpenForAdd, opened in edit mode for one existing
	-- tracker. ns:IsEditableTracker is re-checked here even though the context-menu "Edit" button
	-- is already gated on it -- a tracker removed between the right-click and the click on "Edit"
	-- must never open the dialog. kind comes from the saved entry's own trackerType, never from
	-- the active tab or the key shape.
	dialog.OpenForEdit = function(key)
		local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
		if not ns:IsEditableTracker(entry) then
			return
		end

		wipe(ctx)
		ctx.mode = "edit"
		ctx.kind = entry.trackerType
		ctx.editingKey = key

		dialog:SetTitle(EDIT_TITLE_BY_KIND[ctx.kind] or EDIT_TITLE_BY_KIND[ns.KIND.USER_BUFF])
		confirmBtn:SetText("Save")

		for _, field in ipairs(fieldStates) do
			-- Reset first so a field whose prefill does not touch every sub-widget still starts
			-- clean, then prefill from the saved entry -- neither name a field individually.
			local def, state = field.def, field.state
			def.reset(state, ctx)
			def.prefill(state, entry, ctx)
		end

		-- Phase 57.1: opening always selects General (57.1-CONTEXT), same as OpenForAdd.
		-- SelectGeneral forces the layout, so a prefilled value that changes a field's visibility (e.g.
		-- Cover all ranks' availability) is reflected immediately and the dialog is sized to the
		-- visible rows before Show.
		SelectGeneral()
		dialog:Show()
		FocusFirstShown()
	end

	-- Whichever way the dialog closes -- Cancel, Escape (UISpecialFrames), ns:DismissTBTDialogs on
	-- a tab switch or the CDM closing, or a successful commit hiding it above -- no stale
	-- editingKey can reach the next open in either mode.
	dialog:SetScript("OnHide", function()
		wipe(ctx)
	end)

	return dialog
end

-- CONT-04: the New Container dialog's Icons/Bars checkboxes differ only in what they anchor
-- under, their Y offset, their label text and their initial checked state, so one builder makes
-- both. Returns the checkbox and its label in that order, because a caller may need the label
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

-- CONT-04: the New Container dialog's one remaining checkbox pair (Icons/Bars) -- a click checks
-- the box itself and unchecks its partner, so the pair can never both be off and clicking an
-- already-checked box re-checks it rather than clearing it. The category, once a second pair,
-- is a radio dropdown since Phase 57.2 (three choices).
local function WireExclusivePair(first, second)
	first:SetScript("OnClick", function(self)
		self:SetChecked(true)
		second:SetChecked(false)
	end)
	second:SetScript("OnClick", function(self)
		self:SetChecked(true)
		first:SetChecked(false)
	end)
end

-- The New Container dialog's category choices, in menu order. File-local and declared above
-- CreateContainerDialog for the same reason as TRACKER_FIELDS: a local below its reader is nil.
local CONTAINER_CATEGORY_CHOICES = {
	{ value = "buffs", text = "Buffs" },
	{ value = "spells", text = "Cooldowns" },
	{ value = "reminders", text = "Reminders" },
}

-- Phase 35.1 (CFG-01/CFG-02): addon-wide config page. Same parent, same two SetPoint calls
-- and the same frame level as ns.tbtPanel, so it occupies the identical rect — the page swap
-- below is a show/hide of two sibling frames, not a new frame hierarchy. No backdrop (the
-- tracker panel has none either) and it is not added to CDM's array of tab pages (CDMTab.xml's
-- taint rule at the top of this file).
-- CONT-04: modelled on CreateAddDialog above -- same ns:CreatePanelDialog frame (ButtonFrameTemplate,
-- DIALOG strata, movable, UISpecialFrames), minus the side tabs. Assigned to ns.tbtContainerDialog
-- in ns:InitCDMTab.
local function CreateContainerDialog()
	local dialog = ns:CreatePanelDialog("TBTNewContainerDialog")
	dialog:SetSize(220, CONTAINER_DIALOG_HEIGHT)

	dialog:SetTitle("New Container")

	-- Name
	local nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameLabel:SetText("Name:")
	nameLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, DIALOG_CONTENT_TOP)

	local nameBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	nameBox:SetSize(180, 22)
	nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
	nameBox:SetMaxLetters(32)
	nameBox:SetAutoFocus(false)

	-- Category is a radio dropdown (WowStyle1DropdownTemplate + SetupMenu + CreateRadio), the
	-- recorded pattern for any multi-choice setting (see the TRACKER_FIELDS contract comment).
	-- Phase 57.1 established that the template, SetupMenu and CreateRadio all exist on both
	-- retail and the Forever beta, so this is no Midnight-only asset. Kind (Icons/Bars) stays a
	-- pair of exclusive checkboxes.
	--
	-- Category comes FIRST because it constrains kind: a cooldown or reminder container is
	-- icon-only ("cooldowns are icons, never bars" is locked, RenderBarContainer skips cooldown
	-- trackers, and ns:CreateUserContainer refuses a bar reminders container). Any category but
	-- Buffs therefore forces Icons and disables the Bars checkbox rather than letting the player
	-- choose a combination ns:CreateUserContainer would refuse.
	local categoryLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	categoryLabel:SetText("Tracks:")
	categoryLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -10)

	local dropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
	dropdown:SetSize(180, 22)
	dropdown:SetPoint("TOPLEFT", categoryLabel, "BOTTOMLEFT", 0, -4)

	local kindLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	kindLabel:SetText("Display as:")
	kindLabel:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -8)

	local iconsCheck = AddExclusiveCheck(dialog, kindLabel, -4, "Icons", true)

	local barsCheck, barsLabel = AddExclusiveCheck(dialog, iconsCheck, -2, "Bars", false)

	WireExclusivePair(iconsCheck, barsCheck)

	-- Anything but Buffs forces Icons; Buffs hands the choice back. Disabling rather than hiding
	-- keeps the dialog one fixed size and shows the player WHY the option is unavailable.
	local function ApplyCategory(selected)
		if selected ~= "buffs" then
			iconsCheck:SetChecked(true)
			barsCheck:SetChecked(false)
			barsCheck:Disable()
			barsLabel:SetTextColor(0.5, 0.5, 0.5)
		else
			barsCheck:Enable()
			barsLabel:SetTextColor(1, 1, 1)
		end
	end

	-- The selected category, read by Create. IsSelected/SetSelected are built once here, not
	-- inside the menu generator, which SetupMenu/GenerateMenu may call more than once per open.
	local selectedCategory = "buffs"
	local function IsSelected(value)
		return selectedCategory == value
	end
	local function SetSelected(value)
		selectedCategory = value
		ApplyCategory(value)
	end

	SetupRadioMenu(dropdown, CONTAINER_CATEGORY_CHOICES, IsSelected, SetSelected)

	-- Error label
	local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontRed")
	errorLabel:SetPoint("TOP", barsCheck, "BOTTOM", 0, -10)
	errorLabel:SetText("")

	-- Create button
	local createBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	createBtn:SetSize(80, 22)
	createBtn:SetText("Create")
	createBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", DIALOG_BUTTON_LEFT_X, DIALOG_BUTTON_Y)
	createBtn:SetScript("OnClick", function()
		local kind = barsCheck:GetChecked() and "bar" or "icon"
		-- Plan 01's ns:CreateUserContainer substitutes "Container <id>" for an empty name --
		-- that fallback is not duplicated here.
		local def = ns:CreateUserContainer(nameBox:GetText(), kind, selectedCategory)
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
	cancelBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", DIALOG_BUTTON_RIGHT_X, DIALOG_BUTTON_Y)
	cancelBtn:SetScript("OnClick", function()
		dialog:Hide()
	end)

	-- Enter confirms
	nameBox:SetScript("OnEnterPressed", function()
		createBtn:Click()
	end)

	dialog.nameBox = nameBox
	dialog.errorLabel = errorLabel
	-- Lets the settings panel open this dialog already pointed at a category, so "New Cooldown
	-- Container" does not make the player pick Cooldowns again. Goes through the same
	-- ApplyCategory the dropdown uses, so the Icons-forced/Bars-disabled asymmetry cannot
	-- diverge between the two entry points. An unknown category falls back to Buffs.
	-- GenerateMenu refreshes the button's shown text: SetupMenu's own comment
	-- (Blizzard_Menu/DropdownButton.lua) says a change made outside a menu open needs it.
	dialog.SelectCategory = function(category)
		if category ~= "spells" and category ~= "reminders" then
			category = "buffs"
		end
		selectedCategory = category
		ApplyCategory(category)
		dropdown:GenerateMenu()
	end

	-- Reset to Buffs and Icons every time the dialog opens, so a previous Cooldowns or
	-- Reminders choice does not leave Bars disabled on the next Buffs container.
	dialog.ResetChoices = function()
		iconsCheck:SetChecked(true)
		barsCheck:SetChecked(false)
		dialog.SelectCategory("buffs")
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
		GameTooltip:SetText(ADD_TITLE_BY_CATEGORY[ns.tbtActiveCategory] or ADD_TITLE_BY_CATEGORY.buffs)
		GameTooltip:AddLine("Click to track a new spell", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	addSquare:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Click opens dialog
	addSquare:SetScript("OnMouseUp", function(_, button, upInside)
		if button == "LeftButton" and upInside then
			ns.tbtAddDialog.OpenForAdd()
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
	-- Cooldowns first, then Buffs under it, then Reminders under that: the order the user asked
	-- for, and the order the XML placeholder anchors already declare, restated here because this
	-- runs against the live rects once the window has been shown.
	TBTSpellsTab:ClearAllPoints()
	TBTSpellsTab:SetPoint("TOP", anchorTo, "BOTTOM", 0, TAB_GAP)
	TBTSettingsTab:ClearAllPoints()
	TBTSettingsTab:SetPoint("TOP", TBTSpellsTab, "BOTTOM", 0, TAB_GAP)
	TBTRemindersTab:ClearAllPoints()
	TBTRemindersTab:SetPoint("TOP", TBTSettingsTab, "BOTTOM", 0, TAB_GAP)
end

---------------------------------------------------------------------
-- Tab init
---------------------------------------------------------------------

-- All three TBT tabs are set up identically apart from their label, the category they
-- select and their icon. Written once here rather than inline per tab, so they cannot drift.
local function SetUpTBTTab(tab, label, category, iconPath)
	-- Set icon via SetTexture (not SetAtlas — our icon is a file, not an atlas)
	tab.Icon:SetTexture(iconPath)
	tab.Icon:SetSize(30, 30)

	-- Store atlas fields so SetChecked (from LargeSideTabButtonTemplate) works
	-- SidePanelTabButtonMixin:SetChecked reads activeAtlas/inactiveAtlas
	-- but since we use SetTexture, override SetChecked to avoid SetAtlas calls
	tab.activeAtlas = nil
	tab.inactiveAtlas = nil

	-- Override SetChecked to use SetTexture instead of SetAtlas
	function tab:SetChecked(checked)
		self.Icon:SetTexture(iconPath)
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
	SetUpTBTTab(TBTSpellsTab, "TBT Cooldowns", "spells", TabIcon("icon_cooldown"))
	SetUpTBTTab(TBTSettingsTab, "TBT Buffs", "buffs", TabIcon("icon_buff"))
	SetUpTBTTab(TBTRemindersTab, "TBT Reminders", "reminders", TabIcon("icon_reminder"))

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
	TBTRemindersTab:Show()
end

-- Switch the CDM tab between the two tracker categories. The section frames are not rebuilt --
-- RelayoutTBTSections hides the other category's and re-chains the rest, and
-- ns:RefreshTBTSections repopulates the two shared sections with this category's contents.
-- Treat an open dialog as cancelled whenever the thing it was opened from goes away.
--
-- Both float at DIALOG strata over the whole UI rather than inside the CDM window, so neither is
-- taken down by the CDM closing or by a tab change -- an Add dialog would sit there still titled
-- for the tab the player has left, and file its tracker into that tab when clicked. Hiding is the
-- whole of "cancel" here: nothing is committed until Add/Save is clicked, and OpenForAdd /
-- OpenForEdit reset or prefill every field on the next open.
--
-- ns.tbtAddDialog is one frame in two modes (54-03): OpenForAdd and OpenForEdit are the same
-- singleton, so this one Hide dismisses whichever mode is open, and "cancel" in edit mode commits
-- nothing either -- the dialog's OnHide wipes its ctx, so no stale editingKey survives to the
-- next open.
function ns:DismissTBTDialogs()
	if ns.tbtAddDialog then
		ns.tbtAddDialog:Hide()
	end
	if ns.tbtContainerDialog then
		ns.tbtContainerDialog:Hide()
	end
end

function ns:SelectTBTCategory(category)
	if category ~= "spells" and category ~= "buffs" and category ~= "reminders" then
		return
	end

	-- Before the swap, not after: what is being added depends on the tab, and carrying a
	-- half-filled dialog across that change would silently re-target it.
	ns:DismissTBTDialogs()

	ns.tbtActiveCategory = category
	TBTSpellsTab:SetChecked(category == "spells")
	TBTSettingsTab:SetChecked(category == "buffs")
	TBTRemindersTab:SetChecked(category == "reminders")

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
	TBTRemindersTab:SetChecked(ns.tbtActiveCategory == "reminders")
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
	TBTRemindersTab:SetChecked(false)
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
