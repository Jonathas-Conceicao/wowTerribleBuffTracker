local _, ns = ...

ns.editModeActive = false

---------------------------------------------------------------------
-- Position helpers
---------------------------------------------------------------------

local function ApplyEditModePositions()
	-- Fresh install: write hardcoded defaults to DB
	if ns.db.editModePositions == nil then
		ns.db.editModePositions = {
			bars = {
				point = "CENTER",
				relativeTo = "UIParent",
				relativePoint = "CENTER",
				x = 300,
				y = 0,
			},
			icons = {
				point = "CENTER",
				relativeTo = "UIParent",
				relativePoint = "CENTER",
				x = 300,
				y = -80,
			},
		}
	end

	local bars = ns.db.editModePositions.bars
	local icons = ns.db.editModePositions.icons

	ns.barContainer:ClearAllPoints()
	ns.barContainer:SetPoint(bars.point, bars.relativeTo, bars.relativePoint, bars.x, bars.y)

	ns.iconContainer:ClearAllPoints()
	ns.iconContainer:SetPoint(icons.point, icons.relativeTo, icons.relativePoint, icons.x, icons.y)

	-- Apply visibility from DB
	local visible = ns.db.tbtVisible ~= false
	if visible then
		ns.barContainer:Show()
		ns.iconContainer:Show()
	else
		ns.barContainer:Hide()
		ns.iconContainer:Hide()
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

local selectedContainer = nil -- "bars" | "buffs" | nil
local dragStartX, dragStartY
local DRAG_THRESHOLD = 4

function ns:SelectContainer(which)
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
	local overlay = which == "bars" and ns.barSelectedOverlay or ns.iconSelectedOverlay
	overlay:Show()

	ns:ShowSettingsPopup(which)
end

function ns:DeselectContainer(which)
	local overlay = which == "bars" and ns.barSelectedOverlay or ns.iconSelectedOverlay
	overlay:Hide()
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
		local viewer = key == "bars" and ns.cdmBarViewer or ns.cdmIconViewer
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

		if key == "bars" then
			cs.barWidth = viewer:GetSettingValue(S.BarWidthScale) or cs.barWidth
		end

		ns.RefreshContainerSettings()
		ns:UpdateDisplay()

		-- Refresh the popup to show new values
		ns:ShowSettingsPopup(key)

		print("|cff00ccffTBT|r: Copied Blizzard CDM settings for " .. (key == "bars" and "Bars" or "Buffs") .. ".")
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

	popup.Title:SetText(containerKey == "bars" and "TBT Bars" or "TBT Buffs")

	-- Use activeContainerKey in callbacks so switching containers reads the correct key
	local layoutIndex = 1

	local function AddDropdown(labelText, settingKey, options)
		local frame = popup.pools:GetPool("EditModeSettingDropdownTemplate"):Acquire()
		frame.layoutIndex = layoutIndex
		layoutIndex = layoutIndex + 1
		frame.Label:SetText(labelText)
		frame.Dropdown:SetupMenu(function(_, rootDesc)
			local key = activeContainerKey
			for _, opt in ipairs(options) do
				rootDesc:CreateRadio(opt.text, function()
					return ns.db.containerSettings[key][settingKey] == opt.value
				end, function()
					ns.db.containerSettings[key][settingKey] = opt.value
					ns.RefreshContainerSettings()
					ns:UpdateDisplay()
				end, opt.value)
			end
		end)
		frame:Show()
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
	local directionOptsBuffs = { { text = "Right", value = 0 }, { text = "Left", value = 1 } }
	local visOpts = {
		{ text = "Always Visible", value = 0 },
		{ text = "In Combat", value = 2 },
		{ text = "Hidden", value = 3 },
	}

	if containerKey == "bars" then
		-- TBT Bars order: Icon Size, Icon Padding, Bar Width, Opacity, Visibility,
		-- Hide When Inactive, Show Timer, Show Tooltips
		AddSlider("Icon Size", "scale", 50, 200, 5, ShowAsPercentage)
		AddSlider("Icon Padding", "padding", 0, 20, 1, ShowAsInteger)
		AddSlider("Bar Width", "barWidth", 50, 200, 1, ShowAsPercentage)
		AddSlider("Opacity", "opacity", 50, 100, 1, ShowAsPercentage)
		AddDropdown("Visibility", "visibility", visOpts)
		AddCheckbox("Hide When Inactive", "hideWhenInactive")
		AddCheckbox("Show Timer", "showTimer")
		AddCheckbox("Show Tooltips", "showTooltips")
	else
		-- TBT Buffs order: Orientation, Icon Direction, Icon Size, Icon Padding,
		-- Opacity, Visibility, Hide When Inactive, Show Timer, Show Tooltips
		AddDropdown("Orientation", "orientation", orientOpts)
		AddDropdown("Icon Direction", "growthDirection", directionOptsBuffs)
		AddSlider("Icon Size", "scale", 50, 200, 5, ShowAsPercentage)
		AddSlider("Icon Padding", "padding", 0, 20, 1, ShowAsInteger)
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

function ns:ShowEditModeHandles()
	-- Always show containers in Edit Mode so they are positionable
	ns.barContainer:Show()
	ns.iconContainer:Show()

	-- Ensure containers have a minimum size so the overlay is visible/clickable
	-- Bar container width should reflect current barWidth setting
	local barWidth = (
		ns.db
		and ns.db.containerSettings
		and ns.db.containerSettings.bars
		and ns.db.containerSettings.bars.barWidth
	) or 220
	if ns.barContainer:GetHeight() < 30 then
		ns.barContainer:SetHeight(30)
	end
	if ns.barContainer:GetWidth() < barWidth then
		ns.barContainer:SetWidth(barWidth)
	end
	if ns.iconContainer:GetHeight() < 40 then
		ns.iconContainer:SetHeight(40)
	end
	if ns.iconContainer:GetWidth() < 40 then
		ns.iconContainer:SetWidth(40)
	end

	ns.barOverlay:Show()
	ns.iconOverlay:Show()
end

function ns:HideEditModeHandles()
	ns.barOverlay:Hide()
	ns.iconOverlay:Hide()

	-- Restore visibility from DB
	local visible = ns.db.tbtVisible ~= false
	if not visible then
		ns.barContainer:Hide()
		ns.iconContainer:Hide()
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

	ns.db.editModePositions.bars = ReadPoint(ns.barContainer, 300, 0)
	ns.db.editModePositions.icons = ReadPoint(ns.iconContainer, 300, -80)
end

---------------------------------------------------------------------
-- Click-vs-drag wiring helper
---------------------------------------------------------------------

local function WireSelectableDrag(overlay, container, containerKey)
	overlay:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and ns.editModeActive then
			dragStartX, dragStartY = GetCursorPosition()
			container:StartMoving()
		end
	end)

	overlay:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and ns.editModeActive then
			container:StopMovingOrSizing()
			local curX, curY = GetCursorPosition()
			local moved = math.abs(curX - (dragStartX or curX)) >= DRAG_THRESHOLD
				or math.abs(curY - (dragStartY or curY)) >= DRAG_THRESHOLD
			if not moved then
				-- It was a click — toggle selection
				if selectedContainer == containerKey then
					ns:ClearSelection()
				else
					ns:SelectContainer(containerKey)
				end
			end
			dragStartX, dragStartY = nil, nil
		end
	end)
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
			ns.barContainer:SetMovable(true)
			ns.iconContainer:SetMovable(true)
			WireSelectableDrag(ns.barOverlay, ns.barContainer, "bars")
			WireSelectableDrag(ns.iconOverlay, ns.iconContainer, "buffs")
			ns:ShowEditModeHandles()
			ns:UpdateDisplay()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		else
			-- Disable Edit Mode behavior — act as if Edit Mode is off for TBT
			ns.editModeActive = false
			ns:ClearSelection()
			ns.barOverlay:SetScript("OnMouseDown", nil)
			ns.barOverlay:SetScript("OnMouseUp", nil)
			ns.iconOverlay:SetScript("OnMouseDown", nil)
			ns.iconOverlay:SetScript("OnMouseUp", nil)
			ns.barContainer:SetMovable(false)
			ns.iconContainer:SetMovable(false)
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
	if ns.barOverlay and ns.barOverlay:IsMouseOver() then
		return true
	end
	if ns.iconOverlay and ns.iconOverlay:IsMouseOver() then
		return true
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
	ns.barContainer:SetMovable(true)
	ns.iconContainer:SetMovable(true)

	-- Wire click-vs-drag detection on both overlays
	WireSelectableDrag(ns.barOverlay, ns.barContainer, "bars")
	WireSelectableDrag(ns.iconOverlay, ns.iconContainer, "buffs")

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

	ns.barContainer:SetMovable(false)
	ns.iconContainer:SetMovable(false)

	ns.barOverlay:SetScript("OnMouseDown", nil)
	ns.barOverlay:SetScript("OnMouseUp", nil)
	ns.iconOverlay:SetScript("OnMouseDown", nil)
	ns.iconOverlay:SetScript("OnMouseUp", nil)

	ns:HideEditModeHandles()
	HideEditModePanel()
end

---------------------------------------------------------------------
-- Init
---------------------------------------------------------------------

function ns:InitEditModeFrames()
	-- Bar container — independent UIParent frame for timer bars
	ns.barContainer = CreateFrame("Frame", "TBTBarContainer", UIParent)
	ns.barContainer:SetSize(220, 1)
	ns.barContainer:SetFrameStrata("MEDIUM")
	ns.barContainer:SetClampedToScreen(true)

	-- Icon container — independent UIParent frame for buff icons
	ns.iconContainer = CreateFrame("Frame", "TBTBuffContainer", UIParent)
	ns.iconContainer:SetSize(40, 40)
	ns.iconContainer:SetFrameStrata("MEDIUM")
	ns.iconContainer:SetClampedToScreen(true)

	-- Create Edit Mode overlays (full-container highlight, Blizzard NineSlice style)
	ns.barOverlay = CreateEditModeOverlay(ns.barContainer, "TBT Bars")
	ns.iconOverlay = CreateEditModeOverlay(ns.iconContainer, "TBT Buffs")

	-- Create selected-state overlays (yellow NineSlice, shown when container is selected)
	ns.barSelectedOverlay = CreateSelectedOverlay(ns.barContainer)
	ns.iconSelectedOverlay = CreateSelectedOverlay(ns.iconContainer)

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
