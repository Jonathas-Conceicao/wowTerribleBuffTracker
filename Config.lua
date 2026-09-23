local addonName, ns = ...

-- Config.lua -- TBT's own settings panel, under Options > AddOns.
--
-- Replaces the gear square that used to open a config PAGE inside Blizzard's Cooldown Manager
-- window (user decision, 2026-09-22: "I didn't like the config button on the cdm like I
-- requested"). The CDM tabs now do one job -- assigning trackers to containers -- and everything
-- that is not about a specific tracker lives here, reachable by "/tbt" from anywhere.
--
-- ONE FRAME, TWO HOSTS. The panel is built as a self-contained frame and then handed to
-- Settings.RegisterCanvasLayoutCategory when that API exists. It does on Midnight; TBT also ships
-- on the Forever beta (interface 16001), where it cannot be confirmed from a Midnight-only source
-- tree. So the registration is a capability check, per CLAUDE.md -- and on a client without the
-- API the same frame is shown standalone, with a backdrop, a close button and Escape-to-close,
-- rather than the panel simply not existing there.
--
-- Layout is hand-placed rather than built from Settings.CreateCheckbox and friends, for two
-- reasons: those initializers only exist on the same API this file cannot assume, and the Merge
-- Mode control is a slide switch rather than a checkbox (also a user request), which the
-- framework has no initializer for at all.

---------------------------------------------------------------------
-- Metrics. Named rather than inline so the spacing stays consistent when a section moves, and
-- so "make everything a bit roomier" is a two-line change instead of thirty.
---------------------------------------------------------------------
local PANEL_W, PANEL_H = 620, 640 -- standalone size; the canvas host resizes us instead
local LOGO_SIZE = 64 -- tbt_icon_64x64.blp at native size; scaling a BLP up only blurs it
local PAD_X = 22 -- left gutter for every element
local GAP_SECTION = 26 -- between one section's last element and the next section's header
local GAP_AFTER_HEADER = 10 -- header to its first control
local GAP_TIGHT = 8 -- between related controls
local TEXT_W = 520 -- wrap width for description paragraphs
local BUTTON_W, BUTTON_H = 180, 24
local ROW_H = 26 -- one container row in the list
local SCROLLBAR_W = 22 -- gutter the scroll bar lives in, to the right of the list

-- Slide switch. Sized to read as a switch rather than a checkbox at a glance.
local SW_W, SW_H = 46, 22
local SW_KNOB = 16
local SW_INSET = 3 -- knob gap from the track edge at either end

-- Every colour is a plain RGB fill on WHITE8X8. No atlas anywhere in this file: atlas names are
-- not guaranteed to exist on both flavours, and a missing atlas is an invisible texture rather
-- than an error, which is the worst way for this to fail.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SW_OFF_TRACK = { 0.16, 0.16, 0.18, 1 }
local SW_ON_TRACK = { 0.13, 0.52, 0.27, 1 }
local SW_OFF_KNOB = { 0.58, 0.58, 0.62, 1 }
local SW_ON_KNOB = { 0.96, 0.98, 0.96, 1 }
local SW_BORDER = { 0, 0, 0, 0.85 }

---------------------------------------------------------------------
-- The slide switch widget.
--
-- Built from coloured 8x8 fills: a border rectangle, a track one pixel inside it, and a knob that
-- sits at one end or the other. Moving the knob is a SetPoint rather than an animation -- an
-- AnimationGroup on a texture region is exactly the kind of API whose presence on Forever cannot
-- be confirmed from here, and a switch reads as a switch without the motion.
--
-- A Button, not a CheckButton: CheckButton brings a check texture and a whole state model that
-- would then have to be suppressed. The toggled state lives in the database and is pushed in with
-- :SetToggled, so this widget never holds the truth about anything.
---------------------------------------------------------------------
local function CreateSlideSwitch(parent, onClick)
	local sw = CreateFrame("Button", nil, parent)
	sw:SetSize(SW_W, SW_H)

	sw.Border = sw:CreateTexture(nil, "BACKGROUND")
	sw.Border:SetTexture(WHITE)
	sw.Border:SetPoint("TOPLEFT", -1, 1)
	sw.Border:SetPoint("BOTTOMRIGHT", 1, -1)
	sw.Border:SetVertexColor(unpack(SW_BORDER))

	sw.Track = sw:CreateTexture(nil, "BORDER")
	sw.Track:SetTexture(WHITE)
	sw.Track:SetAllPoints(sw)

	sw.Knob = sw:CreateTexture(nil, "ARTWORK")
	sw.Knob:SetTexture(WHITE)
	sw.Knob:SetSize(SW_KNOB, SW_KNOB)

	sw.Highlight = sw:CreateTexture(nil, "HIGHLIGHT")
	sw.Highlight:SetTexture(WHITE)
	sw.Highlight:SetAllPoints(sw)
	sw.Highlight:SetVertexColor(1, 1, 1, 0.10)

	-- Pushed in from the database; never inferred from the widget's own appearance.
	function sw:SetToggled(on)
		self.toggled = on and true or false
		self.Knob:ClearAllPoints()
		if self.toggled then
			self.Track:SetVertexColor(unpack(SW_ON_TRACK))
			self.Knob:SetVertexColor(unpack(SW_ON_KNOB))
			self.Knob:SetPoint("RIGHT", self, "RIGHT", -SW_INSET, 0)
		else
			self.Track:SetVertexColor(unpack(SW_OFF_TRACK))
			self.Knob:SetVertexColor(unpack(SW_OFF_KNOB))
			self.Knob:SetPoint("LEFT", self, "LEFT", SW_INSET, 0)
		end
	end

	sw:SetScript("OnClick", function(self)
		local wanted = not self.toggled
		-- Drawn first so the switch answers the click even if the handler below is slow or
		-- refuses; the caller re-pushes the real state afterwards either way.
		self:SetToggled(wanted)
		PlaySound(wanted and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		onClick(wanted)
	end)

	sw:SetToggled(false)
	return sw
end

---------------------------------------------------------------------
-- Small layout helpers. Each returns the region it made, and each takes the running Y as an
-- explicit argument rather than chaining to the previous widget -- so a section can be moved or
-- removed without re-anchoring the one that followed it.
---------------------------------------------------------------------
local function AddHeader(parent, text, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, y)
	fs:SetText(text)

	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetTexture(WHITE)
	rule:SetVertexColor(1, 1, 1, 0.12)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
	rule:SetPoint("RIGHT", parent, "RIGHT", -PAD_X, 0)

	return fs
end

local function AddParagraph(parent, text, y, indent)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X + (indent or 0), y)
	fs:SetWidth(TEXT_W - (indent or 0))
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

local function AddButton(parent, text, y, x, onClick, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or BUTTON_W, BUTTON_H)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

---------------------------------------------------------------------
-- The panel.
---------------------------------------------------------------------
local panel

local function BuildPanel()
	local f = CreateFrame("Frame", "TBTConfigPanel", UIParent)
	f:SetSize(PANEL_W, PANEL_H)
	f:Hide()

	-- --- title -------------------------------------------------------------------------
	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.Title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -20)
	f.Title:SetText("TerribleBuffTracker")

	f.Subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Subtitle:SetPoint("TOPLEFT", f.Title, "BOTTOMLEFT", 0, -4)
	f.Subtitle:SetWidth(TEXT_W)
	f.Subtitle:SetJustifyH("LEFT")
	f.Subtitle:SetText("Track the buffs and cooldowns the game no longer shows you.")

	-- The addon's own icon, centred under the strapline. tbt_icon_64x64.blp is the file the TOC
	-- already ships as ## IconTexture, so it is in the deployed file set and needs no new asset.
	-- BLP rather than the 400x400 PNG beside it: the client cannot load a PNG.
	f.Logo = f:CreateTexture(nil, "ARTWORK")
	f.Logo:SetSize(LOGO_SIZE, LOGO_SIZE)
	f.Logo:SetPoint("TOP", f.Subtitle, "BOTTOM", 0, -14)
	-- Path built with ESCAPED backslashes. The first version of this line lost them to an edit script and Lua read the
	-- remains as escape sequences -- InterfaceAddOns... became InterfaceAddOns and 	 became a literal TAB, so the
	-- texture path pointed nowhere. Space was reserved, nothing drew, and no error was raised, which is exactly how
	-- a wrong texture path fails.
	f.Logo:SetTexture("Interface\\AddOns\\TerribleBuffTracker\\tbt_icon_64x64")
	f.Logo:SetVertexColor(1, 1, 1, 1)

	local y = -80 - LOGO_SIZE - 22

	-- --- merge mode --------------------------------------------------------------------
	AddHeader(f, "Merge Mode", y)
	y = y - 20 - GAP_AFTER_HEADER

	-- ns:SetMergeMode is the single entry point for this flag. The switch never writes
	-- ns.db.mergeMode itself, so the mirror refresh and the Blizzard viewer hide/restore cannot
	-- be skipped by a second toggle site. One switch, not one per category: Merge Mode is
	-- all-or-nothing by user decision (STEAL-06).
	f.MergeSwitch = CreateSlideSwitch(f, function(wanted)
		ns:SetMergeMode(wanted)
		-- Re-pushed from the database rather than trusted: SetMergeMode is the authority, and if
		-- it ever refuses a change the switch must show what is true, not what was clicked.
		f.MergeSwitch:SetToggled(ns.db and ns.db.mergeMode == true)
	end)
	f.MergeSwitch:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, y)

	f.MergeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.MergeLabel:SetPoint("LEFT", f.MergeSwitch, "RIGHT", 10, 0)
	f.MergeLabel:SetText("Merge Blizzard's Cooldown Manager into TBT")

	y = y - SW_H - GAP_TIGHT
	AddParagraph(
		f,
		"Blizzard's tracked buffs, bars and cooldowns move into TBT's own containers, alongside "
			.. "the trackers you add yourself, and Blizzard's displays are hidden. Turn it off and "
			.. "everything goes back where it was.",
		y
	)
	y = y - 44 - GAP_SECTION

	-- --- containers --------------------------------------------------------------------
	AddHeader(f, "Containers", y)
	y = y - 20 - GAP_AFTER_HEADER

	AddParagraph(
		f,
		"Extra places to put your trackers. A buff container can show icons or bars; a cooldown "
			.. "container shows icons only.",
		y
	)
	y = y - 30

	f.NewBuffButton = AddButton(f, "New Buff Container", y, PAD_X, function()
		ns:OpenContainerDialog("buffs")
	end)
	f.NewCooldownButton = AddButton(f, "New Cooldown Container", y, PAD_X + BUTTON_W + 12, function()
		ns:OpenContainerDialog("spells")
	end)
	y = y - BUTTON_H - GAP_TIGHT

	local listTop = y

	-- --- quick actions, pinned to the bottom -------------------------------------------
	--
	-- Built BEFORE the container list even though it renders below it, because the list's bottom
	-- edge anchors to this header. Pinned to the panel's BOTTOM rather than continuing the
	-- running Y, so it stays put however many containers exist.
	f.ActionsHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.ActionsHeader:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD_X, 92)
	f.ActionsHeader:SetText("Quick Actions")

	f.ActionsRule = f:CreateTexture(nil, "ARTWORK")
	f.ActionsRule:SetTexture(WHITE)
	f.ActionsRule:SetVertexColor(1, 1, 1, 0.12)
	f.ActionsRule:SetHeight(1)
	f.ActionsRule:SetPoint("TOPLEFT", f.ActionsHeader, "BOTTOMLEFT", 0, -4)
	f.ActionsRule:SetPoint("RIGHT", f, "RIGHT", -PAD_X, 0)

	f.MoveBarsButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.MoveBarsButton:SetSize(BUTTON_W, BUTTON_H)
	f.MoveBarsButton:SetPoint("TOPLEFT", f.ActionsRule, "BOTTOMLEFT", 0, -12)
	f.MoveBarsButton:SetText("Move Bars")
	f.MoveBarsButton:SetScript("OnClick", function()
		ns:OpenEditMode()
	end)

	f.MoveBarsHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.MoveBarsHint:SetPoint("LEFT", f.MoveBarsButton, "RIGHT", 12, 0)
	f.MoveBarsHint:SetText("Opens Edit Mode, where TBT's containers can be dragged.")

	f.CDMButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.CDMButton:SetSize(BUTTON_W, BUTTON_H)
	f.CDMButton:SetPoint("TOPLEFT", f.MoveBarsButton, "BOTTOMLEFT", 0, -10)
	f.CDMButton:SetText("Cooldown Manager")
	f.CDMButton:SetScript("OnClick", function()
		ns:OpenCooldownManager()
	end)

	f.CDMHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.CDMHint:SetPoint("LEFT", f.CDMButton, "RIGHT", 12, 0)
	f.CDMHint:SetText("Opens Blizzard's Cooldown Manager and TBT's tracker tabs.")

	-- --- the container list, scrollable ------------------------------------------------
	--
	-- Bounded at BOTH ends -- top to the create buttons, bottom to the Quick Actions header --
	-- rather than given a height and allowed to grow. A plain frame that grew downward walked
	-- straight over Quick Actions once enough containers existed, and growing the PANEL instead
	-- is not available: in the Settings canvas the host decides how tall this frame gets, so
	-- anything past the canvas is simply clipped. Bounding it means the list can never collide
	-- with anything and never needs the panel to resize -- it scrolls instead.
	f.ScrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.ScrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, listTop)
	-- The scroll bar sits in the gutter this leaves on the right.
	f.ScrollFrame:SetPoint("RIGHT", f, "RIGHT", -PAD_X - SCROLLBAR_W, 0)
	f.ScrollFrame:SetPoint("BOTTOM", f.ActionsHeader, "TOP", 0, 16)

	f.ContainerList = CreateFrame("Frame", nil, f.ScrollFrame)
	f.ContainerList:SetSize(1, 1)
	f.ScrollFrame:SetScrollChild(f.ContainerList)

	f.EmptyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.EmptyLabel:SetPoint("TOPLEFT", f.ScrollFrame, "TOPLEFT", 2, -4)
	f.EmptyLabel:SetText("No extra containers yet.")

	f:SetScript("OnShow", function()
		ns:RefreshConfigPanel()
	end)

	return f
end

---------------------------------------------------------------------
-- The container list. Re-read from ns.db.userContainers on every show rather than cached, the
-- same "re-sync from the database, do not cache" rule the panel's switch follows -- a container
-- created or deleted from anywhere else is then correct here with no refresh plumbing.
---------------------------------------------------------------------
local rows = {}

function ns:RefreshConfigPanel()
	if not panel or not ns.db then
		return
	end

	panel.MergeSwitch:SetToggled(ns.db.mergeMode == true)

	local records = ns.db.userContainers or {}
	for i = 1, #rows do
		rows[i]:Hide()
	end

	for i, record in ipairs(records) do
		local row = rows[i]
		if not row then
			row = CreateFrame("Frame", nil, panel.ContainerList)
			row:SetHeight(ROW_H)
			row:SetPoint("LEFT", panel.ContainerList, "LEFT", 0, 0)
			row:SetPoint("RIGHT", panel.ContainerList, "RIGHT", -4, 0)

			row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.Label:SetPoint("LEFT", row, "LEFT", 2, 0)
			row.Label:SetJustifyH("LEFT")

			row.Delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.Delete:SetSize(70, 20)
			row.Delete:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			row.Delete:SetText("Delete")

			rows[i] = row
		end

		row:SetPoint("TOPLEFT", panel.ContainerList, "TOPLEFT", 0, -((i - 1) * ROW_H))

		local categoryName = (record.category == "spells") and "Cooldowns" or "Buffs"
		local kindName = (record.kind == "bar") and "Bars" or "Icons"
		row.Label:SetText(record.title .. "  |cff808080(" .. categoryName .. ", " .. kindName .. ")|r")

		local key = record.key
		row.Delete:SetScript("OnClick", function()
			local def = ns.CONTAINER_BY_KEY[key]
			local title = def and def.title or ""
			local count = ns:CountContainerTrackers(key)
			local message
			if count > 0 then
				message = string.format(
					'Delete the container "%s"?\n\nIts %d tracked spell(s) will be moved to Not Displayed.',
					title,
					count
				)
			else
				message = string.format('Delete the container "%s"?\n\nIt is empty.', title)
			end
			StaticPopup_Show("TBT_DELETE_CONTAINER", message, nil, { key = key })
		end)

		row:Show()
	end

	panel.EmptyLabel:SetShown(#records == 0)

	-- The scroll CHILD is sized to its contents; the scroll frame itself is fixed between the
	-- create buttons and Quick Actions, so this is what decides whether a scroll bar appears.
	-- Width is taken from the viewport so rows fill it and the right-hand Delete buttons line up.
	local viewport = panel.ScrollFrame:GetWidth()
	panel.ContainerList:SetSize(math.max(1, viewport), math.max(1, #records * ROW_H))
end

---------------------------------------------------------------------
-- Actions the panel's buttons perform. On ns rather than local so the CDM tab, a macro or a
-- future keybind can reach the same entry point instead of duplicating the guard.
---------------------------------------------------------------------

-- Blizzard's own route into Edit Mode, copied from its slash handler
-- (Blizzard_ChatFrameBase/Mainline/SlashCommandsOverrides.lua:348). Capability-checked and
-- pcall'd: ShowUIPanel is an ordinary global rather than a CDM mixin, but Edit Mode refuses to
-- open in combat and says so by raising.
function ns:OpenEditMode()
	if InCombatLockdown() then
		print("|cff00ccffTerribleBuffTracker|r: Edit Mode cannot be opened during combat.")
		return
	end
	if not EditModeManagerFrame or not ShowUIPanel then
		print("|cff00ccffTerribleBuffTracker|r: Edit Mode is not available on this client.")
		return
	end
	ns:CloseConfigPanel()
	pcall(ShowUIPanel, EditModeManagerFrame)
end

-- The Cooldown Manager window itself -- the one "/cooldownmanager" opens, where TBT's tracker
-- tabs live.
--
-- NOT ShowOptionsPanel, which is what this reached for first. Despite the name, that method opens
-- Blizzard's ADVANCED OPTIONS settings category (CooldownViewerSettings.lua:1795 --
-- Settings.OpenToCategory(Settings.ADVANCED_OPTIONS_CATEGORY_ID)), not the manager. The manager is
-- ShowUIPanel(CooldownViewerSettings), which is what CooldownViewerSettingsMixin:ShowUIPanel does
-- at :1688.
--
-- Using the global rather than the mixin is also the better citizen here: ShowUIPanel is an
-- ordinary global taking the frame as an argument, so this calls no Blizzard mixin method on a CDM
-- frame at all.
function ns:OpenCooldownManager()
	if not CooldownViewerSettings or not ShowUIPanel then
		print("|cff00ccffTerribleBuffTracker|r: the Cooldown Manager is not available on this client.")
		return
	end
	-- The settings window is a UIPanel and TBT's own panel may be one too; closing ours first
	-- keeps the frame manager from shuffling them against each other.
	ns:CloseConfigPanel()
	if Settings and SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
		pcall(HideUIPanel, SettingsPanel)
	end
	local ok = pcall(ShowUIPanel, CooldownViewerSettings)
	if not ok then
		print("|cff00ccffTerribleBuffTracker|r: could not open the Cooldown Manager.")
	end
end

-- Opens the New Container dialog pre-set to a category. The dialog itself still lives in
-- CDMTab.lua beside the other dialogs; this only reaches it and picks the starting pair.
function ns:OpenContainerDialog(category)
	local dlg = ns.tbtContainerDialog
	if not dlg then
		return
	end
	dlg.nameBox:SetText("")
	dlg.errorLabel:SetText("")
	dlg.ResetChoices()
	if category == "spells" then
		dlg.SelectCategory("spells")
	end
	dlg:Show()
	dlg.nameBox:SetFocus()
end

---------------------------------------------------------------------
-- Registration and opening.
---------------------------------------------------------------------
local settingsCategoryID

function ns:InitConfigPanel()
	if panel then
		return
	end
	panel = BuildPanel()

	-- Capability check, not a client check (CLAUDE.md): a client without the Settings API gets
	-- the standalone window below instead of a load error or a missing feature.
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "TerribleBuffTracker")
		if ok and category then
			-- Do NOT set category.ID. It looks like a name field and is the NUMERIC id the
			-- framework assigned; overwriting it with the addon name made category:GetID()
			-- return a string, and Settings.OpenToCategory forwards straight to
			-- C_SettingsUtil.OpenSettingsPanel, which rejected it:
			--   bad argument #1 to 'OpenSettingsPanel' (outside of expected range ...)
			pcall(Settings.RegisterAddOnCategory, category)
			settingsCategoryID = category:GetID()
			return
		end
	end

	-- Standalone fallback: the same frame, given the chrome the Settings host would have
	-- provided. Movable and Escape-closable, matching the addon's other dialogs.
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("HIGH")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

	if BackdropTemplateMixin then
		Mixin(panel, BackdropTemplateMixin)
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		panel:SetBackdropColor(0, 0, 0, 1)
	end

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

	table.insert(UISpecialFrames, "TBTConfigPanel")
end

function ns:OpenConfigPanel()
	ns:InitConfigPanel()

	if settingsCategoryID and Settings and Settings.OpenToCategory then
		-- Must be the numeric ID, never the category name.
		Settings.OpenToCategory(settingsCategoryID)
		return
	end

	panel:Show()
	panel:Raise()
end

function ns:CloseConfigPanel()
	-- Only meaningful for the standalone host; the Settings window owns its own closing.
	if panel and not settingsCategoryID then
		panel:Hide()
	end
end
