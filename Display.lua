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
local timeSinceUpdate = 0

-- DB-backed display settings (populated by RefreshContainerSettings on load and settings change)
local cachedBarSettings = {}
local cachedIconSettings = {}

-- Reusable tables for UpdateDisplay (wiped each cycle to avoid allocations)
local barTimers = {}
local iconTimers = {}
local activeBarBySpell = {}
local barSlots = {}
local buffSlots = {}
local activeBySpell = {}

---------------------------------------------------------------------
-- Settings refresh — reads ns.db.containerSettings into module-level cached tables
---------------------------------------------------------------------

local function RefreshContainerSettings()
	local bs = ns.db and ns.db.containerSettings and ns.db.containerSettings.bars
	if bs then
		cachedBarSettings.iconScale = math.max(0.1, (bs.scale or 100) / 100)
		cachedBarSettings.iconPadding = bs.padding or 5
		cachedBarSettings.barWidth = BAR_WIDTH * (bs.barWidth or 100) / 100
		cachedBarSettings.alpha = (bs.opacity or 100) / 100
		cachedBarSettings.visibleSetting = (bs.visibility == 2) and 1 or (bs.visibility == 3) and 2 or 0
		cachedBarSettings.barContent = bs.displayMode or 0
		cachedBarSettings.hideWhenInactive = bs.hideWhenInactive ~= false
		cachedBarSettings.timerShown = bs.showTimer ~= false
		cachedBarSettings.tooltipsShown = bs.showTooltips ~= false
	end

	local is = ns.db and ns.db.containerSettings and ns.db.containerSettings.buffs
	if is then
		cachedIconSettings.orientationSetting = is.orientation or 0
		cachedIconSettings.iconDirection = is.growthDirection or 0
		cachedIconSettings.iconScale = math.max(0.1, (is.scale or 100) / 100)
		cachedIconSettings.iconPadding = is.padding or 5
		cachedIconSettings.alpha = (is.opacity or 100) / 100
		cachedIconSettings.visibleSetting = (is.visibility == 2) and 1 or (is.visibility == 3) and 2 or 0
		cachedIconSettings.hideWhenInactive = is.hideWhenInactive ~= false
		cachedIconSettings.timerShown = is.showTimer ~= false
		cachedIconSettings.tooltipsShown = is.showTooltips ~= false
	end
end

ns.RefreshContainerSettings = RefreshContainerSettings

---------------------------------------------------------------------
-- Shared tooltip handler (Phase 22, D-18/D-19; extended Phase 23, D-01/D-02) —
-- used by bar + icon OnEnter (opts = nil, unchanged Phase 22 behavior, D-03/D-22)
-- and by CDMTab settings grid (opts populated with showSpellID/showDuration/extraLines).
-- Takes a frame (anchor), a proc table (numeric .spellID field), and optional opts.
-- Uniform: no type-discriminating branches (DISP-01) and no duplicated GameTooltip
-- wiring (DISP-03). Callers pass the proc directly — no legacy meta-info fallback chains.
---------------------------------------------------------------------

function ns:ShowBuffTooltip(frame, proc, opts)
	GameTooltip_SetDefaultAnchor(GameTooltip, frame)
	if proc and type(proc.spellID) == "number" then
		GameTooltip:SetSpellByID(proc.spellID)
	else
		GameTooltip:SetText((proc and proc.label) or "Unknown", 1, 1, 1)
	end
	if opts then
		if opts.showSpellID and proc and type(proc.spellID) == "number" then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Spell ID: " .. proc.spellID, 0.8, 0.8, 0.8)
		end
		if opts.showDuration and proc and proc.duration and proc.duration > 0 then
			if not opts.showSpellID then
				GameTooltip:AddLine(" ")
			end
			GameTooltip:AddLine("TBT Duration: " .. proc.duration .. "s", 0.8, 0.8, 0.8)
		end
		if opts.extraLines then
			for _, line in ipairs(opts.extraLines) do
				GameTooltip:AddLine(line, 0.5, 0.5, 0.5)
			end
		end
	end
	GameTooltip:Show()
end

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

	-- Tooltips (Phase 22, D-19: delegates to shared ns:ShowBuffTooltip)
	bar:EnableMouse(true)
	bar:SetScript("OnEnter", function(self)
		if not ns.barTooltipsShown then
			return
		end
		ns:ShowBuffTooltip(self, self.proc)
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

	-- Tooltips (Phase 22, D-19: delegates to shared ns:ShowBuffTooltip)
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", function(self)
		if not ns.iconTooltipsShown then
			return
		end
		ns:ShowBuffTooltip(self, self.proc)
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
		barPool[index] = CreateTimerBar(ns.barContainer)
	end
	return barPool[index]
end

local function GetIcon(index)
	if not iconPool[index] then
		iconPool[index] = CreateTimerIcon(ns.iconContainer)
	end
	return iconPool[index]
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

	RefreshContainerSettings()

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
		if timer.section == "buffs" then
			table.insert(iconTimers, timer)
		else
			table.insert(barTimers, timer)
		end
	end

	-- === Render bar timers ===
	if ns.barContainer then
		local settings = cachedBarSettings
		if not settings then
			ns.barContainer:Hide()
		else
			ns.barTooltipsShown = settings.tooltipsShown

			local hasActiveTimers = #barTimers > 0
			local barEditing = ns.editModeActive
			local visible = ShouldShow(settings.visibleSetting, hasActiveTimers, settings.hideWhenInactive, barEditing)

			if not visible then
				ns.barContainer:Hide()
			else
				ns.barContainer:Show()
				local barWidth = settings.barWidth
				-- CDM applies padding in container (unscaled) space between scaled children
				local padding = settings.iconPadding + BAR_PADDING_OFFSET

				-- Build bar slots: all tracked bar entries if showing inactive, else active only
				wipe(activeBarBySpell)
				for _, timer in ipairs(barTimers) do
					-- Index by stable provider key — THE slot identity (string for meta, numeric
					-- for user-spells). All providers populate proc.key at OnTrigger time.
					activeBarBySpell[timer.key] = timer
				end

				local showPlaceholders = not settings.hideWhenInactive or ns.configOpen or barEditing
				if showPlaceholders then
					wipe(barSlots)
					for dbKey, entry in pairs(ns.db.trackedBuffs) do
						if entry.section == "bars" then
							entry.key = dbKey -- stable slot identity (string for meta, numeric for user)
							table.insert(barSlots, entry)
						end
					end
					table.sort(barSlots, function(a, b)
						return (a.layoutOrder or 0) < (b.layoutOrder or 0)
					end)
				else
					wipe(barSlots)
					for _, t in ipairs(barTimers) do
						table.insert(barSlots, t) -- procs already have .key from provider
					end
				end

				-- Layout bars inside container.
				-- Match CDM GridLayoutFrame: step = GetHeight() + padding (both
				-- unscaled). SetScale on each bar frame scales the offset naturally.
				local scale = settings.iconScale
				local step = BAR_HEIGHT + padding

				for i, slot in ipairs(barSlots) do
					local bar = GetBar(i)
					-- Every slot (DB entry OR proc) carries .key — stable slot identity.
					local timer = activeBarBySpell[slot.key]

					bar:ClearAllPoints()
					-- Inter-item padding only: first bar at 0, subsequent bars offset by step
					bar:SetPoint("TOPLEFT", ns.barContainer, "TOPLEFT", 0, -((i - 1) * step))

					ApplyBarStyle(bar, barWidth, settings)

					-- Phase 22 (D-22/D-31): Unified icon/label resolution — single codepath for
					-- all four buff types. Active timer (proc) wins; placeholder falls back to
					-- ns:GetDisplayInfoForKey. Per-widget icon cache (D-16) keyed by spellID
					-- avoids redundant ns:GetSpellIcon calls — no branching on key type.
					local resolvedSpellID
					local resolvedLabel
					if timer then
						bar.proc = timer -- store for OnEnter tooltip (D-19)
						resolvedSpellID = timer.spellID
						resolvedLabel = timer.label
					else
						local info = ns:GetDisplayInfoForKey(slot.key)
						if info and info.spellID then
							bar.proc = { spellID = info.spellID, label = info.label, key = slot.key }
							resolvedSpellID = info.spellID
							resolvedLabel = info.label or slot.label
						else
							bar.proc = nil
							resolvedSpellID = nil
							resolvedLabel = slot.label
						end
					end

					-- D-16/D-17: Per-widget icon cache — refresh texture only when spellID changes
					if bar.cachedSpellID ~= resolvedSpellID then
						bar.cachedSpellID = resolvedSpellID
						bar.cachedIcon = resolvedSpellID and ns:GetSpellIcon(resolvedSpellID) or 134400
					end
					bar.icon:SetTexture(bar.cachedIcon)
					bar.label:SetText(resolvedLabel or "")

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
				-- Inter-item padding only: n items with (n-1) gaps between them
				local n = #barSlots
				local totalHeight = n > 0 and (n * BAR_HEIGHT + (n - 1) * padding) * scale or 0
				ns.barContainer:SetHeight(math.max(1, totalHeight))
				-- Width tracks barWidth setting
				ns.barContainer:SetWidth(math.max(1, barWidth * scale))

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
	if not ns.iconContainer then
		for i = 1, #iconPool do
			iconPool[i]:Hide()
		end
		return
	end

	local iconSettings = cachedIconSettings
	if not iconSettings then
		ns.iconContainer:Hide()
		return
	end

	ns.iconTooltipsShown = iconSettings.tooltipsShown

	local hasActiveIcons = #iconTimers > 0
	local iconEditing = ns.editModeActive
	local iconVisible =
		ShouldShow(iconSettings.visibleSetting, hasActiveIcons, iconSettings.hideWhenInactive, iconEditing)

	if not iconVisible then
		ns.iconContainer:Hide()
		return
	end

	ns.iconContainer:Show()

	wipe(buffSlots)
	for dbKey, entry in pairs(ns.db.trackedBuffs) do
		if entry.section == "buffs" then
			entry.key = dbKey -- stable slot identity
			table.insert(buffSlots, entry)
		end
	end
	table.sort(buffSlots, function(a, b)
		return (a.layoutOrder or 0) < (b.layoutOrder or 0)
	end)

	wipe(activeBySpell)
	for _, timer in ipairs(iconTimers) do
		activeBySpell[timer.key] = timer
	end

	-- Match CDM GridLayoutFrame: step = GetSize() + padding (unscaled).
	-- SetScale on each icon scales the offset naturally.
	local iconPadding = iconSettings.iconPadding + ICON_PADDING_OFFSET
	local step = BUFF_ICON_SIZE + iconPadding
	local orientation = iconSettings.orientationSetting -- 0=Horizontal, 1=Vertical
	local direction = iconSettings.iconDirection -- 0=Right/Down, 1=Left/Up

	for slotIndex, entry in ipairs(buffSlots) do
		local icon = GetIcon(slotIndex)
		local timer = activeBySpell[entry.key]

		icon:ClearAllPoints()
		-- Inter-item padding only: first icon at 0, subsequent offset by step
		local offset = (slotIndex - 1) * step

		if orientation == 0 then
			-- Horizontal
			if direction == 1 then
				-- Left: anchor from right edge of container, grow leftward
				icon:SetPoint("TOPRIGHT", ns.iconContainer, "TOPRIGHT", -offset, 0)
			else
				-- Right (default): anchor from left edge of container, grow rightward
				icon:SetPoint("TOPLEFT", ns.iconContainer, "TOPLEFT", offset, 0)
			end
		else
			-- Vertical
			if direction == 1 then
				-- Up
				icon:SetPoint("BOTTOMLEFT", ns.iconContainer, "BOTTOMLEFT", 0, offset)
			else
				-- Down (default)
				icon:SetPoint("TOPLEFT", ns.iconContainer, "TOPLEFT", 0, -offset)
			end
		end

		if timer then
			icon.proc = timer -- D-19: store for OnEnter tooltip

			-- D-16/D-17: Per-widget icon cache — refresh texture only when spellID changes
			if icon.cachedSpellID ~= timer.spellID then
				icon.cachedSpellID = timer.spellID
				icon.cachedIcon = ns:GetSpellIcon(timer.spellID)
			end
			icon.icon:SetTexture(icon.cachedIcon)
			ApplyIconStyle(icon, iconSettings)

			if icon._lastStart ~= timer.startedAt then
				icon._lastStart = timer.startedAt
				icon.cooldown:SetCooldown(timer.startedAt, timer.duration)
			end

			icon:Show()
		elseif not iconSettings.hideWhenInactive or ns.configOpen or iconEditing then
			-- Placeholder: resolve icon via ns:GetDisplayInfoForKey
			local info = ns:GetDisplayInfoForKey(entry.key)
			local resolvedSpellID = info and info.spellID or nil
			if info and info.spellID then
				icon.proc = { spellID = info.spellID, label = info.label, key = entry.key }
			else
				icon.proc = nil
			end

			if icon.cachedSpellID ~= resolvedSpellID then
				icon.cachedSpellID = resolvedSpellID
				icon.cachedIcon = resolvedSpellID and ns:GetSpellIcon(resolvedSpellID) or 134400
			end
			icon.icon:SetTexture(icon.cachedIcon)
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

	-- Size the icon container to fit its visible children (inter-item padding only)
	local visibleCount = #buffSlots
	if visibleCount > 0 then
		local totalSize = visibleCount * BUFF_ICON_SIZE + (visibleCount - 1) * iconPadding
		if orientation == 0 then
			-- Horizontal layout
			ns.iconContainer:SetSize(math.max(1, totalSize), BUFF_ICON_SIZE)
		else
			-- Vertical layout
			ns.iconContainer:SetSize(BUFF_ICON_SIZE, math.max(1, totalSize))
		end
	else
		ns.iconContainer:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)
	end
end
