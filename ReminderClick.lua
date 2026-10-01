-- ReminderClick.lua
-- Click-to-cast overlays for reminder icons (backlog 999.18, CLICK-01..05).
-- One pooled SecureActionButtonTemplate button per clickable reminder icon.
-- A click casts on the player, except the ally-cast rows (ns:ReminderCastUnit), which leave the
-- unit unset so the game's default targeting applies.
-- Invariants:
--   1. An overlay is never anchored to a TBT frame (only to UIParent, in screen
--      coordinates), so TBT's display tree never becomes protected.
--   2. Nothing protected is written in combat; work is deferred to
--      PLAYER_REGEN_ENABLED and combat visibility belongs to the state driver.
--   3. No Blizzard Edit Mode frame is ever touched.
local _, ns = ...

local overlays = {}
local clickIcons = {}
local dirty = false
local scheduled = false
-- Review WR-01: Blizzard Edit Mode is open. Set only by this file's EditMode.Enter/Exit callbacks;
-- ns.editModeActive alone is not enough (it is false while Edit Mode stays open with TBT's sidebar
-- checkbox unticked). Edit Mode cannot be open at file load, so false is the true initial state.
local editModeOpen = false
-- Review WR-03: a flush that had to skip a stamped icon (not visible yet, no usable rect, name not
-- resolved) schedules ONE retry. retrySpent bounds it to one per dirty edge, so a permanent skip
-- (a bad cast ID) costs one extra flush, never a timer loop; the next real mark re-arms it.
local retryScheduled = false
local retrySpent = false
local RETRY_DELAY = 1
-- Forward-declared: Flush schedules it, and it calls Flush (assigned below Flush).
local RetryFromTimer

local COMBAT_VISIBILITY = "[combat] hide; show"
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

-- The NAME (not the ID) is the cast attribute so the game casts the highest
-- known rank. Unreadable or missing names yield nil: no click action.
local function ResolveCastName(spellID)
	if not (C_Spell and C_Spell.GetSpellInfo) then
		return nil
	end
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if not ok or not ns:CanReadTable(info) then
		return nil
	end
	local name = info.name
	if issecretvalue(name) or type(name) ~= "string" or name == "" then
		return nil
	end
	return name
end

local function OverlayOnEnter(self)
	local icon = self.tbtIcon
	if icon and ns.containerTooltipsShown[icon.containerKey] then
		ns:ShowBuffTooltip(self, icon.proc)
	end
end

local function OverlayOnLeave(self)
	-- Only the tooltip this overlay put up: another frame may own GameTooltip by now.
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function CreateOverlay()
	local overlay = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	overlay:RegisterForClicks("LeftButtonUp")
	-- Review CR-01: pinned so the release acts whatever ActionButtonUseKeyDown says. Left nil,
	-- SecureActionButton_OnClick falls back to that CVar (on by default) and ignores an up-click.
	overlay:SetAttribute("useOnKeyDown", false)
	overlay:SetAttribute("type1", "spell")
	local highlight = overlay:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(HIGHLIGHT_TEXTURE)
	highlight:SetBlendMode("ADD")
	overlay:SetScript("OnEnter", OverlayOnEnter)
	overlay:SetScript("OnLeave", OverlayOnLeave)
	overlay:Hide()
	overlay.inService = false
	overlays[#overlays + 1] = overlay
	return overlay
end

-- The one way out of service. Callers guarantee out of combat.
local function Retire(overlay)
	if overlay.inService then
		UnregisterStateDriver(overlay, "visibility")
		overlay.inService = false
	end
	overlay:Hide()
	overlay.tbtIcon = nil
end

local function Place(overlay, icon, castName, unit)
	local left, bottom, width, height = icon:GetRect()
	-- Review WR-04: a rect or scale with a secret aspect is never compared or multiplied; the icon
	-- is skipped this pass. Secrets are tested before the nil test: nothing compares a secret.
	if issecretvalue(left) or issecretvalue(bottom) or issecretvalue(width) or issecretvalue(height) or left == nil then
		return false
	end
	local iconScale, parentScale = icon:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if issecretvalue(iconScale) or issecretvalue(parentScale) then
		return false
	end
	local ratio = iconScale / parentScale
	left, bottom, width, height = left * ratio, bottom * ratio, width * ratio, height * ratio
	if overlay._left ~= left or overlay._bottom ~= bottom or overlay._width ~= width or overlay._height ~= height then
		overlay:ClearAllPoints()
		overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
		overlay:SetSize(width, height)
		overlay._left, overlay._bottom, overlay._width, overlay._height = left, bottom, width, height
	end
	local strata = icon:GetFrameStrata()
	if overlay._strata ~= strata then
		overlay:SetFrameStrata(strata)
		overlay._strata = strata
	end
	local level = icon:GetFrameLevel() + 1
	if overlay._level ~= level then
		overlay:SetFrameLevel(level)
		overlay._level = level
	end
	if overlay._castName ~= castName then
		overlay:SetAttribute("spell", castName)
		overlay._castName = castName
	end
	-- nil leaves the game's default targeting (a friendly target receives the cast); "player" is the
	-- Phase 63 self-cast. Written on change only; Place is only reached out of combat (Flush's
	-- InCombatLockdown guard). Writing nil clears the attribute for a reused pooled overlay.
	if overlay._unit ~= unit then
		overlay:SetAttribute("unit", unit)
		overlay._unit = unit
	end
	overlay.tbtIcon = icon
	if not overlay.inService then
		RegisterStateDriver(overlay, "visibility", COMBAT_VISIBILITY)
		overlay.inService = true
	end
	return true
end

local function Flush()
	if InCombatLockdown() then
		dirty = true
		return
	end
	dirty = false
	local used = 0
	local skipped = 0
	if not editModeOpen and not ns.editModeActive and ns.db ~= nil then
		local count, hidden = ns:CollectReminderClickIcons(clickIcons)
		skipped = hidden
		for i = 1, count do
			local icon = clickIcons[i]
			local entry = ns.db.trackedBuffs[icon._clickKey]
			local castID = entry and ns:ReminderCastID(entry)
			-- Review WR-05: a cast spell this character does not know gets no overlay (a click would
			-- only raise an error). The load rule's own known check: rank-family aware on Forever, so
			-- any known rank passes. Not a skip: SPELLS_CHANGED rebuilds the cast index, which re-marks.
			if castID and ns:ResolveSpellKnown(castID, false) ~= true then
				castID = nil
			end
			local castName = castID and ResolveCastName(castID)
			if castName then
				local overlay = overlays[used + 1] or CreateOverlay()
				if Place(overlay, icon, castName, ns:ReminderCastUnit(entry)) then
					used = used + 1
				else
					skipped = skipped + 1
				end
			elseif castID then
				-- A cast spell whose name did not resolve (possibly not cached yet).
				skipped = skipped + 1
			end
		end
	end
	for i = used + 1, #overlays do
		Retire(overlays[i])
	end
	if skipped > 0 and not retrySpent and not retryScheduled then
		retrySpent = true
		retryScheduled = true
		C_Timer.After(RETRY_DELAY, RetryFromTimer)
	end
end

RetryFromTimer = function()
	retryScheduled = false
	-- In combat Flush only records dirty; PLAYER_REGEN_ENABLED runs it.
	Flush()
end

local function FlushFromTimer()
	scheduled = false
	if dirty then
		Flush()
	end
end

function ns:MarkReminderClicksDirty()
	dirty = true
	retrySpent = false
	if scheduled or InCombatLockdown() then
		return
	end
	scheduled = true
	C_Timer.After(0, FlushFromTimer)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
-- TBT's container positions are account-wide and not re-applied on a layout/profile switch, so this
-- only buys a cheap re-place after Blizzard's own layout change (review IN-06). pcall: an event a
-- client does not know would otherwise error at load.
pcall(eventFrame.RegisterEvent, eventFrame, "EDIT_MODE_LAYOUTS_UPDATED")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		Flush()
	else
		ns:MarkReminderClicksDirty()
	end
end)

-- Review WR-03: an icon stamped while the UI was hidden (Alt+Z, a cinematic) was skipped as not
-- visible, and no stamp changes when the UI comes back. A post-hook only: nothing on UIParent is
-- replaced or called, and the hook costs one call per show.
local function OnUIParentShow()
	ns:MarkReminderClicksDirty()
end
UIParent:HookScript("OnShow", OnUIParentShow)

-- Owner is eventFrame, never ns: EditModeFrames.lua already registers these
-- events with owner ns and a second ns registration would replace it.
EventRegistry:RegisterCallback("EditMode.Enter", function()
	editModeOpen = true
	if InCombatLockdown() then
		dirty = true
		return
	end
	for i = 1, #overlays do
		Retire(overlays[i])
	end
end, eventFrame)

EventRegistry:RegisterCallback("EditMode.Exit", function()
	editModeOpen = false
	ns:MarkReminderClicksDirty()
end, eventFrame)
