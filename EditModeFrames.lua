local _, ns = ...

ns.editModeActive = false

---------------------------------------------------------------------
-- Position helpers
---------------------------------------------------------------------

-- Seeds a missing registry entry with its default, then applies the saved-or-default point
-- and visibility. Idempotent and unconditional — this is what gives an upgraded v0.3.0
-- database its new `essential` and `utility` entries, since Plan 01's migration deliberately
-- does not seed them, and what lets ns.CreateContainerFrames call it for a container created
-- after ApplyEditModePositions's own loop has already run.
local function ApplyContainerPosition(def)
	-- The table guard lives HERE, not only in ApplyEditModePositions, because this function has
	-- two entry points: that loop, and ns.CreateContainerFrames. Init calls CreateContainerFrames
	-- for every def BEFORE ApplyEditModePositions runs, so on any database without an
	-- editModePositions table -- a fresh install, or every single login on the Forever beta, which
	-- never reads saved variables back -- the first container indexed a nil table and threw,
	-- aborting InitEditModeFrames partway and leaving no containers at all.
	if ns.db.editModePositions == nil then
		ns.db.editModePositions = {}
	end

	if ns.db.editModePositions[def.key] == nil then
		-- The anchor POINT is part of the default, not fixed at CENTER. The four base containers
		-- declare BOTTOM/BOTTOM so they land exactly where the CDM viewer they mirror does; a
		-- user container declares neither and keeps the CENTER anchor every container used to
		-- have. Seeded once -- a container the player has already positioned keeps its saved
		-- anchor, because this branch does not run for it.
		ns.db.editModePositions[def.key] = {
			point = def.defaultPoint or "CENTER",
			relativeTo = "UIParent",
			relativePoint = def.defaultRelativePoint or "CENTER",
			x = def.defaultX,
			y = def.defaultY,
		}
	end

	local pos = ns.db.editModePositions[def.key]
	local container = ns.containers[def.key]
	container:ClearAllPoints()
	container:SetPoint(pos.point, pos.relativeTo, pos.relativePoint, pos.x, pos.y)

	if ns.db.tbtVisible ~= false then
		container:Show()
	else
		container:Hide()
	end
end

local function ApplyEditModePositions()
	for _, def in ipairs(ns.CONTAINERS) do
		ApplyContainerPosition(def)
	end
end

---------------------------------------------------------------------
-- Edit Mode overlay — covers entire container, Blizzard NineSlice style
---------------------------------------------------------------------

local NINESLICE_LAYOUT = {
	["TopRightCorner"] = { atlas = "editmode-actionbar-highlight-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	["TopLeftCorner"] = { atlas = "editmode-actionbar-highlight-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	["BottomLeftCorner"] = {
		atlas = "editmode-actionbar-highlight-NineSlice-Corner",
		mirrorLayout = true,
		x = -8,
		y = -8,
	},
	["BottomRightCorner"] = {
		atlas = "editmode-actionbar-highlight-NineSlice-Corner",
		mirrorLayout = true,
		x = 8,
		y = -8,
	},
	["TopEdge"] = { atlas = "_editmode-actionbar-highlight-NineSlice-EdgeTop" },
	["BottomEdge"] = { atlas = "_editmode-actionbar-highlight-NineSlice-EdgeBottom" },
	["LeftEdge"] = { atlas = "!editmode-actionbar-highlight-NineSlice-EdgeLeft" },
	["RightEdge"] = { atlas = "!editmode-actionbar-highlight-NineSlice-EdgeRight" },
	["Center"] = { atlas = "editmode-actionbar-highlight-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

local SELECTED_NINESLICE_LAYOUT = {
	["TopRightCorner"] = { atlas = "editmode-actionbar-selected-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	["TopLeftCorner"] = { atlas = "editmode-actionbar-selected-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	["BottomLeftCorner"] = {
		atlas = "editmode-actionbar-selected-NineSlice-Corner",
		mirrorLayout = true,
		x = -8,
		y = -8,
	},
	["BottomRightCorner"] = {
		atlas = "editmode-actionbar-selected-NineSlice-Corner",
		mirrorLayout = true,
		x = 8,
		y = -8,
	},
	["TopEdge"] = { atlas = "_editmode-actionbar-selected-NineSlice-EdgeTop" },
	["BottomEdge"] = { atlas = "_editmode-actionbar-selected-NineSlice-EdgeBottom" },
	["LeftEdge"] = { atlas = "!editmode-actionbar-selected-NineSlice-EdgeLeft" },
	["RightEdge"] = { atlas = "!editmode-actionbar-selected-NineSlice-EdgeRight" },
	["Center"] = { atlas = "editmode-actionbar-selected-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

local function CreateEditModeOverlay(container, labelText)
	local overlay = CreateFrame("Frame", nil, container, "NineSliceCodeTemplate")
	overlay:SetAllPoints(container)
	overlay:SetFrameLevel(container:GetFrameLevel() + 10)
	overlay:EnableMouse(true)
	overlay.ignoreParentAlpha = true

	NineSliceUtil.ApplyLayout(overlay, NINESLICE_LAYOUT)

	-- Re-apply NineSlice on parent resize so overlay tracks container size
	container:HookScript("OnSizeChanged", function()
		if overlay:IsShown() then
			NineSliceUtil.ApplyLayout(overlay, NINESLICE_LAYOUT)
		end
	end)

	local label = overlay:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(GameFontNormal)
	label:SetText(labelText)
	label:SetTextColor(1, 1, 1, 1)
	label:SetPoint("CENTER")

	overlay:Hide()
	return overlay
end

local function CreateSelectedOverlay(container)
	local overlay = CreateFrame("Frame", nil, container, "NineSliceCodeTemplate")
	overlay:SetAllPoints(container)
	overlay:SetFrameLevel(container:GetFrameLevel() + 11)
	overlay.ignoreParentAlpha = true
	NineSliceUtil.ApplyLayout(overlay, SELECTED_NINESLICE_LAYOUT)

	-- Re-apply NineSlice on parent resize
	container:HookScript("OnSizeChanged", function()
		if overlay:IsShown() then
			NineSliceUtil.ApplyLayout(overlay, SELECTED_NINESLICE_LAYOUT)
		end
	end)
	overlay:Hide()
	return overlay
end

---------------------------------------------------------------------
-- Selection state
---------------------------------------------------------------------

local selectedContainer = nil -- any ns.CONTAINERS key, or nil

function ns:SelectContainer(which)
	-- Idempotent, matching EditModeSystemMixin:SelectSystem's `if not self.isSelected`
	-- guard. Selection now happens on every mouse-DOWN, so without this a click on an
	-- already-selected container would re-run ClearSelectedSystem and re-show the popup.
	if selectedContainer == which then
		return
	end

	-- Deselect current TBT selection if different
	if selectedContainer and selectedContainer ~= which then
		ns:DeselectContainer(selectedContainer)
	end

	-- Clear Blizzard's Edit Mode selection — remove their yellow highlight + close their popup
	-- Use pcall because ClearSelectedSystem may touch secure state in some contexts
	if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
		pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
	end

	selectedContainer = which
	local overlay = ns.containerSelectedOverlays[which]
	if overlay then
		overlay:Show()
	end

	ns:ShowSettingsPopup(which)
end

function ns:DeselectContainer(which)
	local overlay = ns.containerSelectedOverlays[which]
	if overlay then
		overlay:Hide()
	end
	selectedContainer = nil
end

function ns:ClearSelection()
	if selectedContainer then
		ns:DeselectContainer(selectedContainer)
	end
	ns:HideSettingsPopup()
end

---------------------------------------------------------------------
-- Settings popup — matches Blizzard's EditModeSystemSettingsDialog exactly
-- Position: BOTTOMRIGHT of UIParent at -250, 200 (same as CDM's Edit Mode popup)
-- Structure: ResizeLayoutFrame + DialogBorderTranslucentTemplate + close button
-- Controls: EditModeSettingDropdownTemplate + EditModeSettingSliderTemplate
---------------------------------------------------------------------

local tbtSettingsPopup = nil
local activeContainerKey = nil

local function CreateSettingsPopup()
	local popup = CreateFrame("Frame", "TBTSettingsPopup", UIParent, "ResizeLayoutFrame")
	popup:SetSize(340, 400)
	popup:SetFrameStrata("DIALOG")
	popup:SetFrameLevel(200)
	popup:SetClampedToScreen(true)
	popup:SetMovable(true)
	popup:EnableMouse(true)
	popup:RegisterForDrag("LeftButton")
	popup:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	popup:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	popup:Hide()

	popup:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -250, 200)

	local border = CreateFrame("Frame", nil, popup, "DialogBorderTranslucentTemplate")
	border.ignoreInLayout = true

	local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
	closeBtn.ignoreInLayout = true
	closeBtn:SetScript("OnClick", function()
		ns:ClearSelection()
	end)

	local title = popup:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -15)
	title.ignoreInLayout = true
	popup.Title = title

	local settings = CreateFrame("Frame", nil, popup, "VerticalLayoutFrame")
	settings:SetSize(1, 1)
	settings:SetPoint("TOP", title, "BOTTOM", 0, -12)
	settings.spacing = 2
	popup.Settings = settings

	popup.widthPadding = 40
	popup.heightPadding = 130

	popup.pools = CreateFramePoolCollection()
	popup.pools:CreatePool("FRAME", settings, "EditModeSettingDropdownTemplate")
	popup.pools:CreatePool("FRAME", settings, "EditModeSettingSliderTemplate")
	popup.pools:CreatePool("FRAME", settings, "EditModeSettingCheckboxTemplate")

	-- "Copy Blizzard CDM" button
	local copyBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	copyBtn:SetSize(220, 28)
	copyBtn:SetText("Copy Blizzard CDM Config")
	copyBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 56)
	copyBtn.ignoreInLayout = true
	copyBtn:SetScript("OnClick", function()
		local key = activeContainerKey
		if not key then
			return
		end
		local def = ns.CONTAINER_BY_KEY[key]
		-- A user container mirrors no CDM viewer at all. The button is hidden for these
		-- containers in ns:ShowSettingsPopup below, so this is belt-and-braces against a
		-- stale click queued before the popup refreshed.
		if not def.cdmViewerGlobal then
			return
		end
		-- Resolved lazily at click time, not cached — this is the capability check
		-- PROJECT.md calls for, not a flavour check. `_G[def.cdmViewerGlobal]` can be nil
		-- on Forever; the guard below handles that with a printed message, no error.
		local viewer = _G[def.cdmViewerGlobal]
		if not viewer or not viewer.GetSettingValue then
			print("|cff00ccffTBT|r: Blizzard CDM viewer not found.")
			return
		end
		local S = Enum.EditModeCooldownViewerSetting
		local cs = ns.db.containerSettings[key]

		-- Read CDM settings via GetSettingValue
		cs.orientation = viewer:GetSettingValue(S.Orientation) or cs.orientation
		cs.growthDirection = viewer:GetSettingValue(S.IconDirection) or cs.growthDirection
		cs.scale = math.max(50, viewer:GetSettingValue(S.IconSize) or cs.scale)
		cs.padding = math.max(0, viewer:GetSettingValue(S.IconPadding) or cs.padding)
		cs.opacity = math.max(50, viewer:GetSettingValue(S.Opacity) or cs.opacity)
		cs.visibility = viewer:GetSettingValue(S.VisibleSetting) or cs.visibility
		cs.hideWhenInactive = viewer:GetSettingValueBool(S.HideWhenInactive)
		cs.showTimer = viewer:GetSettingValueBool(S.ShowTimer)
		cs.showTooltips = viewer:GetSettingValueBool(S.ShowTooltips)

		if def.kind == "bar" then
			cs.barWidth = viewer:GetSettingValue(S.BarWidthScale) or cs.barWidth
			if S.BarContent then
				cs.displayMode = viewer:GetSettingValue(S.BarContent) or cs.displayMode
			end
		else
			-- Capability check, not a flavour check: S.IconLimit is engine-side and may
			-- simply not exist on a client, same as S.BarContent above.
			if S.IconLimit then
				cs.itemsPerRow = viewer:GetSettingValue(S.IconLimit) or cs.itemsPerRow
			end
		end

		ns.RefreshContainerSettings()
		ns:UpdateDisplay()

		-- Refresh the popup to show new values
		ns:ShowSettingsPopup(key)

		print("|cff00ccffTBT|r: Copied Blizzard CDM settings for " .. def.title .. ".")
	end)
	popup.CopyButton = copyBtn

	-- "Terrible Buff Tracker Settings" button at bottom
	local settingsBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	settingsBtn:SetSize(220, 28)
	settingsBtn:SetText("Terrible Buff Tracker Settings")
	settingsBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 20)
	settingsBtn.ignoreInLayout = true
	settingsBtn:SetScript("OnClick", function()
		ns:ClearSelection()
		if not CooldownViewerSettings:IsVisible() then
			-- Use ShowUIPanel so ESC can close it (Show() bypasses the UI panel system)
			ShowUIPanel(CooldownViewerSettings)
		end
		C_Timer.After(0, function()
			ns:ShowTBTPanel()
		end)
	end)
	popup.SettingsButton = settingsBtn

	tbtSettingsPopup = popup
	return popup
end

local function ShowAsPercentage(value)
	return FormatPercentage(value / 100)
end

local function ShowAsInteger(value)
	return tostring(math.floor(value + 0.5))
end

function ns:ShowSettingsPopup(containerKey)
	if not tbtSettingsPopup then
		CreateSettingsPopup()
	end

	local popup = tbtSettingsPopup
	activeContainerKey = containerKey

	-- Hide first to reset state, then release pool frames
	popup:Hide()
	popup.pools:ReleaseAll()

	popup.Title:SetText("TBT " .. ns.CONTAINER_BY_KEY[containerKey].title)
	-- A user container mirrors no CDM viewer, so offering a copy action that can only print a
	-- failure is worse than not offering it. ignoreInLayout, anchored to the popup's own
	-- BOTTOM, so hiding it moves nothing else.
	popup.CopyButton:SetShown(ns.CONTAINER_BY_KEY[containerKey].cdmViewerGlobal ~= nil)

	-- Use activeContainerKey in callbacks so switching containers reads the correct key
	local layoutIndex = 1

	-- options may be a plain list or a function returning one. A function is re-evaluated every
	-- time the menu is generated, which is what lets one dropdown's choices depend on another's
	-- current value. onSelect runs after the write and the redraw, for a dropdown that has to
	-- tell a sibling to regenerate.
	local function AddDropdown(labelText, settingKey, options, onSelect)
		local frame = popup.pools:GetPool("EditModeSettingDropdownTemplate"):Acquire()
		frame.layoutIndex = layoutIndex
		layoutIndex = layoutIndex + 1
		frame.Label:SetText(labelText)
		frame.Dropdown:SetupMenu(function(_, rootDesc)
			local key = activeContainerKey
			local opts = type(options) == "function" and options() or options
			for _, opt in ipairs(opts) do
				rootDesc:CreateRadio(opt.text, function()
					return ns.db.containerSettings[key][settingKey] == opt.value
				end, function()
					ns.db.containerSettings[key][settingKey] = opt.value
					ns.RefreshContainerSettings()
					ns:UpdateDisplay()
					if onSelect then
						onSelect()
					end
				end, opt.value)
			end
		end)
		frame:Show()
		return frame
	end

	local function AddSlider(labelText, settingKey, minVal, maxVal, stepSize, formatter)
		local frame = popup.pools:GetPool("EditModeSettingSliderTemplate"):Acquire()
		frame.layoutIndex = layoutIndex
		layoutIndex = layoutIndex + 1
		frame.Label:SetText(labelText)

		local steps = math.floor((maxVal - minVal) / stepSize)
		local currentValue = ns.db.containerSettings[containerKey][settingKey] or minVal

		local formatters = nil
		if formatter then
			formatters = { [MinimalSliderWithSteppersMixin.Label.Right] = formatter }
		end

		-- Guard: prevent Init's internal SetValue from writing back to DB
		-- (recycled pool frames may still have old callbacks that fire during Init)
		frame.Slider.tbtInitializing = true
		frame.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
			if frame.Slider.tbtInitializing then
				return
			end
			local key = activeContainerKey
			value = math.floor(value + 0.5)
			ns.db.containerSettings[key][settingKey] = value
			ns.RefreshContainerSettings()
			ns:UpdateDisplay()
		end, frame)
		frame.Slider:Init(currentValue, minVal, maxVal, steps, formatters)
		frame.Slider.tbtInitializing = false

		frame:Show()
	end

	local function AddCheckbox(labelText, settingKey)
		local frame = popup.pools:GetPool("EditModeSettingCheckboxTemplate"):Acquire()
		frame.layoutIndex = layoutIndex
		layoutIndex = layoutIndex + 1
		frame.Label:SetText(labelText)
		frame.Button:SetChecked(ns.db.containerSettings[containerKey][settingKey] == true)
		frame.Button:SetScript("OnClick", function(self)
			local key = activeContainerKey
			ns.db.containerSettings[key][settingKey] = self:GetChecked()
			ns.RefreshContainerSettings()
			ns:UpdateDisplay()
		end)
		frame:Show()
	end

	-- Options
	local orientOpts = { { text = "Horizontal", value = 0 }, { text = "Vertical", value = 1 } }
	-- Icon Direction is ONE setting with two vocabularies. growthDirection 0 means "along the
	-- flow axis, forwards" and 1 "backwards" -- which reads as Right/Left on a horizontal
	-- container and Down/Up on a vertical one, exactly as Display's own comments spell out
	-- ("0=Right/Down, 1=Left/Up"). Labelling it Right/Left on a vertical container named an axis
	-- that container does not flow along.
	--
	-- Centered is offered on BUFF containers only. A Cooldowns container exists to give a
	-- cooldown one stable slot, which is the opposite of a run that moves as things come and go,
	-- so the option is absent there rather than present and discouraged.
	local directionOptsHorizontal = { { text = "Right", value = 0 }, { text = "Left", value = 1 } }
	local directionOptsVertical = { { text = "Down", value = 0 }, { text = "Up", value = 1 } }
	local directionOptsHorizontalBuffs = {
		{ text = "Centered", value = ns.GROWTH_CENTERED },
		{ text = "Right", value = 0 },
		{ text = "Left", value = 1 },
	}
	local directionOptsVerticalBuffs = {
		{ text = "Centered", value = ns.GROWTH_CENTERED },
		{ text = "Down", value = 0 },
		{ text = "Up", value = 1 },
	}
	local function DirectionOpts()
		local cs = ns.db.containerSettings[activeContainerKey]
		local def = ns.CONTAINER_BY_KEY[activeContainerKey]
		local vertical = cs and cs.orientation == 1
		if def and ns:GetContainerCategory(def) == "buffs" then
			return vertical and directionOptsVerticalBuffs or directionOptsHorizontalBuffs
		end
		return vertical and directionOptsVertical or directionOptsHorizontal
	end
	local visOpts = {
		{ text = "Always Visible", value = 0 },
		{ text = "In Combat", value = 2 },
		{ text = "Hidden", value = 3 },
	}
	local displayModeOpts = {
		{ text = "Icon And Name", value = 0 },
		{ text = "Icon Only", value = 1 },
		{ text = "Name Only", value = 2 },
	}

	if ns.CONTAINER_BY_KEY[containerKey].kind == "bar" then
		-- Bar-kind order: Icon Size, Icon Padding, Bar Width, Opacity, Visibility,
		-- Display Mode, Hide When Inactive, Show Timer, Show Tooltips
		AddSlider("Icon Size", "scale", 50, 200, 5, ShowAsPercentage)
		AddSlider("Icon Padding", "padding", 0, 20, 1, ShowAsInteger)
		AddSlider("Bar Width", "barWidth", 50, 200, 1, ShowAsPercentage)
		AddSlider("Opacity", "opacity", 50, 100, 1, ShowAsPercentage)
		AddDropdown("Visibility", "visibility", visOpts)
		AddDropdown("Display Mode", "displayMode", displayModeOpts)
		AddCheckbox("Hide When Inactive", "hideWhenInactive")
		AddCheckbox("Show Timer", "showTimer")
		AddCheckbox("Show Tooltips", "showTooltips")
	else
		-- Icon-kind order (buffs, essential, utility): Orientation, Icon Direction, Icon
		-- Size, Icon Padding, Opacity, Visibility, Hide When Inactive, Show Timer, Show
		-- Tooltips
		-- Orientation is built first, as it displays, and reaches its sibling through a
		-- forward-declared upvalue. GenerateMenu re-runs the generator and re-registers the menu,
		-- which is what refreshes the CLOSED dropdown's text -- without it the labels would only
		-- change the next time the popup was reopened.
		local directionDropdown
		AddDropdown("Orientation", "orientation", orientOpts, function()
			if directionDropdown then
				directionDropdown.Dropdown:GenerateMenu()
			end
		end)
		directionDropdown = AddDropdown("Icon Direction", "growthDirection", DirectionOpts)
		AddSlider("Icon Size", "scale", 50, 200, 5, ShowAsPercentage)
		AddSlider("Icon Padding", "padding", 0, 20, 1, ShowAsInteger)
		AddSlider("Items Per Row", "itemsPerRow", 1, 20, 1, ShowAsInteger)
		AddSlider("Opacity", "opacity", 50, 100, 1, ShowAsPercentage)
		AddDropdown("Visibility", "visibility", visOpts)
		AddCheckbox("Hide When Inactive", "hideWhenInactive")
		AddCheckbox("Show Timer", "showTimer")
		AddCheckbox("Show Tooltips", "showTooltips")
	end

	-- Deferred layout for proper ResizeLayoutFrame sizing
	C_Timer.After(0, function()
		if popup:IsShown() or popup.pendingShow then
			popup.Settings:Layout()
			popup:Layout()
		end
	end)

	popup.pendingShow = true
	popup:Show()
	popup.pendingShow = nil
end

function ns:HideSettingsPopup()
	if tbtSettingsPopup then
		tbtSettingsPopup.pools:ReleaseAll()
		tbtSettingsPopup:Hide()
	end
	activeContainerKey = nil
end

---------------------------------------------------------------------
-- Edit Mode handles
---------------------------------------------------------------------

local function ShowContainerHandle(def)
	local container = ns.containers[def.key]
	container:Show()

	-- Ensure containers have a minimum size so the overlay is visible/clickable
	if def.kind == "bar" then
		local barWidth = (
			ns.db
			and ns.db.containerSettings
			and ns.db.containerSettings[def.key]
			and ns.db.containerSettings[def.key].barWidth
		) or 220
		if container:GetHeight() < 30 then
			container:SetHeight(30)
		end
		if container:GetWidth() < barWidth then
			container:SetWidth(barWidth)
		end
	else
		if container:GetHeight() < 40 then
			container:SetHeight(40)
		end
		if container:GetWidth() < 40 then
			container:SetWidth(40)
		end
	end

	ns.containerOverlays[def.key]:Show()
end

function ns:ShowEditModeHandles()
	-- Always show containers in Edit Mode so they are positionable
	for _, def in ipairs(ns.CONTAINERS) do
		ShowContainerHandle(def)
	end
end

function ns:HideEditModeHandles()
	local visible = ns.db.tbtVisible ~= false
	for _, def in ipairs(ns.CONTAINERS) do
		ns.containerOverlays[def.key]:Hide()
		-- Restore visibility from DB
		if not visible then
			ns.containers[def.key]:Hide()
		end
	end
end

---------------------------------------------------------------------
-- Position save
---------------------------------------------------------------------

function ns:SaveEditModePositions()
	local function ReadPoint(frame, defaultX, defaultY)
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
		return {
			point = point or "CENTER",
			relativeTo = (relativeTo and relativeTo:GetName()) or "UIParent",
			relativePoint = relativePoint or "CENTER",
			x = x or defaultX,
			y = y or defaultY,
		}
	end

	if not ns.db.editModePositions then
		ns.db.editModePositions = {}
	end

	for _, def in ipairs(ns.CONTAINERS) do
		ns.db.editModePositions[def.key] = ReadPoint(ns.containers[def.key], def.defaultX, def.defaultY)
	end
end

---------------------------------------------------------------------
-- Click-vs-drag wiring helper
---------------------------------------------------------------------

local function WireSelectableDrag(overlay, container, containerKey)
	overlay:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and ns.editModeActive then
			-- Select on mouse-DOWN, the way Blizzard does: their
			-- EditModeSystemSelectionBaseMixin:OnMouseDown calls SelectSystem outright,
			-- with no click-vs-drag test. The highlight is therefore up for the whole
			-- drag instead of appearing only once the button is released, which is what
			-- made TBT's containers feel laggy to drag.
			ns:SelectContainer(containerKey)
			container:StartMoving()
		end
	end)

	overlay:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and ns.editModeActive then
			container:StopMovingOrSizing()
		end
	end)
end

-- Makes one container movable and wires its overlay's click-vs-drag handling. Called from the
-- Edit Mode enter loop, the sidebar checkbox's checked branch, and ns.CreateContainerFrames
-- for a container created while Edit Mode is already open.
local function WireContainerDrag(def)
	local container = ns.containers[def.key]
	container:SetMovable(true)
	WireSelectableDrag(ns.containerOverlays[def.key], container, def.key)
end

---------------------------------------------------------------------
-- Edit Mode floating panel (adjacent to EditModeManagerFrame)
-- Pattern from Plumber addon: separate panel with DialogBorderTranslucentTemplate
---------------------------------------------------------------------

local tbtEditPanel = nil

local function CreateEditModePanel()
	if tbtEditPanel then
		return
	end

	local owner = EditModeManagerFrame
	if not owner then
		return
	end

	-- Create a separate floating panel
	local panel = CreateFrame("Frame", "TBTEditModePanel", UIParent)
	panel:SetFrameStrata("DIALOG")
	panel:SetFrameLevel(owner:GetFrameLevel() + 2)
	panel:Hide()

	-- Translucent dialog border (same as Plumber)
	local border = CreateFrame("Frame", nil, panel, "DialogBorderTranslucentTemplate")

	-- Checkbox: standard WoW check button
	local cb = CreateFrame("CheckButton", "TBTEditModeCheckbox", panel, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("LEFT", panel, "LEFT", 12, 0)
	cb:SetChecked(ns.db.tbtVisible ~= false)

	local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
	label:SetText("TerribleBuffTracker")

	-- Size the panel to fit checkbox + label
	local textWidth = label:GetStringWidth()
	panel:SetSize(24 + textWidth + 32, 40)

	cb:SetScript("OnClick", function(self)
		local checked = self:GetChecked()
		ns.db.tbtVisible = checked
		if checked then
			-- Re-enable Edit Mode behavior for TBT
			ns.editModeActive = true
			for _, def in ipairs(ns.CONTAINERS) do
				WireContainerDrag(def)
			end
			ns:ShowEditModeHandles()
			ns:UpdateDisplay()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		else
			-- Disable Edit Mode behavior — act as if Edit Mode is off for TBT
			ns.editModeActive = false
			ns:ClearSelection()
			for _, def in ipairs(ns.CONTAINERS) do
				local overlay = ns.containerOverlays[def.key]
				overlay:SetScript("OnMouseDown", nil)
				overlay:SetScript("OnMouseUp", nil)
				ns.containers[def.key]:SetMovable(false)
			end
			ns:HideEditModeHandles()
			-- Let UpdateDisplay handle normal visibility (show only when buffs are active)
			ns:UpdateDisplay()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)

	-- Position tracking: follow EditModeManagerFrame
	panel.owner = owner
	panel.t = 1
	panel:SetScript("OnUpdate", function(self, elapsed)
		self.t = self.t + elapsed
		if self.t > 0.25 then
			self.t = 0
			if not self.owner:IsShown() then
				self:Hide()
				return
			end
			-- Anchor below the Edit Mode dialog
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", self.owner, "BOTTOMLEFT", 0, -4)
		end
	end)

	tbtEditPanel = panel
	ns.tbtSidebarCheckbox = cb
end

local function ShowEditModePanel()
	if not tbtEditPanel then
		CreateEditModePanel()
	end
	if tbtEditPanel then
		tbtEditPanel:Show()
		tbtEditPanel.t = 1 -- force immediate position update
		ns.tbtSidebarCheckbox:SetChecked(ns.db.tbtVisible ~= false)
	end
end

local function HideEditModePanel()
	if tbtEditPanel then
		tbtEditPanel:Hide()
	end
end

---------------------------------------------------------------------
-- Edit Mode lifecycle
---------------------------------------------------------------------

-- Global click detector: clears TBT selection when clicking outside TBT elements
local clickDetector = CreateFrame("Frame", nil, UIParent)
clickDetector:Hide()

local function IsMouseOverTBTFrame()
	-- Check if cursor is over any TBT-owned frame that should keep selection
	for _, overlay in pairs(ns.containerOverlays) do
		if overlay:IsMouseOver() then
			return true
		end
	end
	if tbtSettingsPopup and tbtSettingsPopup:IsShown() and tbtSettingsPopup:IsMouseOver() then
		return true
	end
	return false
end

clickDetector:SetScript("OnEvent", function(self, event)
	if event == "GLOBAL_MOUSE_DOWN" then
		if selectedContainer and not IsMouseOverTBTFrame() then
			ns:ClearSelection()
		end
	end
end)

function ns:OnEditModeEnter()
	-- Show the panel first (always visible so user can toggle)
	ShowEditModePanel()

	-- Only activate Edit Mode for TBT if checkbox is checked
	if ns.db.tbtVisible == false then
		ns.editModeActive = false
		return
	end

	ns.editModeActive = true

	-- Make containers movable — mouse events are on the overlay, which moves the parent
	for _, def in ipairs(ns.CONTAINERS) do
		WireContainerDrag(def)
	end

	-- Enable global click detector to deselect when clicking outside TBT
	clickDetector:RegisterEvent("GLOBAL_MOUSE_DOWN")
	clickDetector:Show()

	ns:ShowEditModeHandles()
	ns:UpdateDisplay()
end

function ns:OnEditModeExit()
	ns.editModeActive = false

	-- Disable global click detector
	clickDetector:UnregisterEvent("GLOBAL_MOUSE_DOWN")
	clickDetector:Hide()

	-- Clear any active selection before saving/hiding
	ns:ClearSelection()

	ns:SaveEditModePositions()

	for _, def in ipairs(ns.CONTAINERS) do
		local container = ns.containers[def.key]
		container:SetMovable(false)
		local overlay = ns.containerOverlays[def.key]
		overlay:SetScript("OnMouseDown", nil)
		overlay:SetScript("OnMouseUp", nil)
	end

	ns:HideEditModeHandles()
	HideEditModePanel()
end

---------------------------------------------------------------------
-- Init
---------------------------------------------------------------------

-- CONT-04/05: called from Core.lua's ns:AttachContainerRuntime for both a container rehydrated
-- at ADDON_LOADED and one created at runtime through the config panel. Returns immediately
-- when ns.containers is nil -- that is not a defensive afterthought, it is how a rehydrated
-- user container gets its frame: ns:InitEditModeFrames below loops the *whole* registry at
-- PLAYER_ENTERING_WORLD, and by then the rehydrated def is already appended. Idempotent so
-- ns:InitEditModeFrames's own loop can call it unconditionally.
function ns.CreateContainerFrames(def)
	if not ns.containers then
		return
	end
	if ns.containers[def.key] then
		return
	end

	local frame = CreateFrame("Frame", def.frameName, UIParent)
	if def.kind == "bar" then
		frame:SetSize(220, 1)
	else
		frame:SetSize(40, 40)
	end
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)

	ns.containers[def.key] = frame
	ns.containerOverlays[def.key] = CreateEditModeOverlay(frame, "TBT " .. def.title)
	ns.containerSelectedOverlays[def.key] = CreateSelectedOverlay(frame)

	ApplyContainerPosition(def)

	-- A container can be created while Edit Mode is open -- the config panel that creates one
	-- lives in the CDM settings window, itself reachable from Edit Mode -- so the new frame
	-- must be made movable, wired for selection and given its handle immediately, rather than
	-- waiting for the next EditMode.Enter. Without this branch the new container would sit on
	-- screen as an unmovable ghost until the user toggled Edit Mode off and back on.
	if ns.editModeActive then
		WireContainerDrag(def)
		ShowContainerHandle(def)
	end
end

-- CONT-04/05: safe to call for a key no longer present in ns.CONTAINERS -- Core.lua's
-- ns:DeleteUserContainer unregisters the def before calling ns:DetachContainerRuntime (and
-- therefore this), by design, so this function is looked up by key alone and never walks
-- ns.CONTAINERS. WoW frames cannot be destroyed: the frame is deselected, unwired, hidden,
-- cleared of points and unparented rather than freed, and its global (bound to def.frameName)
-- stays bound to the orphan forever. That is harmless and can never collide, because Plan 01's
-- nextContainerId never decrements, so no frameName is ever reused.
function ns.DestroyContainerFrames(key)
	if not ns.containers then
		return
	end
	local container = ns.containers[key]
	if not container then
		return
	end

	-- Guarded form, not a bare ns:DeselectContainer(key): that unconditionally nils the
	-- file-local selectedContainer, which would drop a *different* container's selection
	-- state if that one -- not this one -- were currently selected.
	if selectedContainer == key then
		ns:ClearSelection()
	end
	if activeContainerKey == key then
		ns:HideSettingsPopup()
	end

	local overlay = ns.containerOverlays[key]
	overlay:SetScript("OnMouseDown", nil)
	overlay:SetScript("OnMouseUp", nil)
	overlay:Hide()

	ns.containerSelectedOverlays[key]:Hide()

	container:StopMovingOrSizing() -- a drag may be in flight when the container is deleted
	container:SetMovable(false)
	container:Hide()
	container:ClearAllPoints()
	container:SetParent(nil)

	ns.containers[key] = nil
	ns.containerOverlays[key] = nil
	ns.containerSelectedOverlays[key] = nil
end

function ns:InitEditModeFrames()
	ns.containers = {}
	ns.containerOverlays = {}
	ns.containerSelectedOverlays = {}

	-- One container + overlay pair per ns.CONTAINERS registry entry (Plan 01, Core.lua)
	for _, def in ipairs(ns.CONTAINERS) do
		ns.CreateContainerFrames(def)
	end

	-- Apply saved (or default) positions
	ApplyEditModePositions()

	-- Register Edit Mode enter/exit callbacks
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		ns:OnEditModeEnter()
	end, ns)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		ns:OnEditModeExit()
	end, ns)
end
