local _, ns = ...

-- CDM-matching dimensions
local BAR_HEIGHT = 30
local BAR_ICON_SIZE = 30
local BAR_WIDTH = 220
local BUFF_ICON_SIZE = 40
local UPDATE_INTERVAL = 0.05
local BAR_PADDING_OFFSET = -2
local ICON_PADDING_OFFSET = -4

-- Where slot N of an icon grid sits, as an anchor point plus an offset from the container's
-- matching corner. THE one place that arithmetic lives. It once also placed the engine aura slots
-- MergeMode handed to Blizzard (deleted in Phase 70); its only caller now is RenderIconContainer's
-- non-centred placement. A merged Blizzard frame follows the pooled cell it is attached to, so it
-- lands on this same grid without a second derivation.
--
-- Offsets are deliberately UNSCALED. Every icon is individually SetScale'd, so SetPoint reads
-- them in the icon's own space and the scale applies itself; see the step comment in
-- RenderIconContainer. Matches CDM GridLayoutFrame: step = GetSize() + padding.
function ns:GridSlotPlacement(index, step, perRow, orientation, direction)
	-- Inter-item padding only, split across the major (flow) and minor (wrap) axes.
	-- "Major" runs along Orientation's flow direction; "minor" is the wrap axis.
	local major = ((index - 1) % perRow) * step
	local minor = math.floor((index - 1) / perRow) * step

	if orientation == 0 then
		-- Horizontal: major flows along X, minor wraps downward (matches
		-- GridLayoutFrame's layoutFramesGoingUp = false default).
		if direction == 1 then
			-- Left: anchor from right edge of container, grow leftward
			return "TOPRIGHT", -major, -minor
		end
		-- Right (default): anchor from left edge of container, grow rightward
		return "TOPLEFT", major, -minor
	end

	-- Vertical: major flows along Y, minor wraps rightward (matches GridLayoutFrame's
	-- layoutFramesGoingRight = true default).
	if direction == 1 then
		-- Up
		return "BOTTOMLEFT", minor, major
	end
	-- Down (default)
	return "TOPLEFT", minor, -major
end

-- Where slot P of a CENTERED run sits. Centered is the odd one out: every other direction places
-- a slot from its configured index alone, so a slot's position never depends on what else is on
-- screen. Centered places it from its position among the slots CURRENTLY DRAWN, and re-centres the
-- whole run whenever that count changes -- which is the entire point of it.
--
-- capacity is the container's width in cells (the reserved count, clamped to one row), and it is
-- what the run is centred against, NOT the drawn count. Centring against the container keeps the
-- midpoint fixed where the player put it; centring against the drawn run would make the midpoint
-- meaningless.
--
-- Rows are centred individually, so a wrapped container centres its last, partial row too. With
-- every slot drawn and a full last row this returns exactly what the Right/Down path returns,
-- which is why preview looks the same under either setting.
local function CenteredSlotPlacement(drawnIndex, drawnCount, capacity, step, perRow, orientation)
	local row = math.floor((drawnIndex - 1) / perRow)
	local col = (drawnIndex - 1) % perRow
	local inThisRow = math.min(perRow, drawnCount - row * perRow)

	local major = (col + (capacity - inThisRow) / 2) * step
	local minor = row * step

	-- Always measured from TOPLEFT: the offset is absolute within the container, so there is no
	-- far edge to hang off and no Left/Up variant to branch on.
	if orientation == 0 then
		return "TOPLEFT", major, -minor
	end
	return "TOPLEFT", minor, -major
end

-- Whether a slot puts something on screen this pass. Mirrors the branch chain in
-- RenderIconContainer exactly, in the same order, and exists only because Centered has to know
-- the COUNT before it can place the first one. Any branch added there must be added here, or a
-- centred run will leave a gap for an icon that never appears.
--
-- A merged entry draws exactly when Blizzard's own frame is shown (or, while previewing, when
-- TBT's placeholder is), stamped as entry.cdmShown by ns:RefreshMergeShownSlots. That flag is
-- Blizzard's own "is this up", already computed, and readable as a plain boolean; TBT must not
-- re-derive it from the aura APIs.
-- Phase 57.2 (REM-03): the reminder gate sits right here, at the same position as the hide
-- branch RenderIconContainer's own chain adds -- after the merged early return, before anything
-- that would otherwise draw.
local function SlotDraws(entry, timer, settings, iconEditing)
	if entry.isMerged then
		-- Ignores RenderIconContainer's fail-closed merged arm (always hidden) on purpose: that arm
		-- is unreachable, since mergeShownSlots is filled only while Merge Mode is on.
		return entry.cdmShown == true
	end

	local gate = ns:ReminderGate(entry.key, entry)
	if gate == false and not (ns.configOpen or iconEditing) then
		return false
	end
	if gate == true then
		return true
	end

	-- Phase 47: an item tracker produces no ns.activeTimers entry either, for exactly the same
	-- reason a cooldown tracker does not, so it must draw on the same terms. Currently
	-- unreachable for one: the centred layout this function gates is derived from
	-- ns:GetContainerCategory(def) ~= "spells" (buffs and reminders), and an item tracker
	-- always lives in a spells container. The widening is defensive, one token, and correct on
	-- its own terms rather than load-bearing today.
	return timer ~= nil
		or ns:IsCooldownSlotEntry(entry)
		or not settings.hideWhenInactive
		or ns.configOpen
		or iconEditing
end

local inCombat = false

local timeSinceUpdate = 0

-- Per-container state (CONT-01/04), every table keyed by ns.CONTAINERS key. CONT-04 makes
-- the registry grow at runtime (user-created containers), so ns.AllocateContainerRuntime
-- below is the ONLY place any of these three tables gains a key -- not this declaration,
-- not UpdateDisplay, not either render function. ns.ReleaseContainerRuntime is the matching
-- release site. UpdateDisplay and the render functions only ever wipe() the inner lists; a
-- table constructor in any of them would cost one allocation per container every
-- UPDATE_INTERVAL seconds.
local pools = {}
local timersByContainer = {}
local cachedSettings = {}

-- Hoisted so neither render function allocates a closure per tick. Both containers sort
-- by the same key, and UpdateDisplay now calls one render per container rather than two
-- inline blocks, so an inline comparator would allocate once per container per frame.
local function ByLayoutOrder(a, b)
	return (a.layoutOrder or 0) < (b.layoutOrder or 0)
end
ns.containerTooltipsShown = {}

-- Reusable scratch tables for the render functions, wiped at the top of each render.
-- Renders run sequentially and never interleave, so one pair is shared by all containers.
local slots = {}
local activeByKey = {}

-- Phase 63 (CLICK-04) -- container key -> true while any of its icons carries a click stamp,
-- so the hidden-container path clears with one table read instead of walking the pool.
local clickStampedIn = {}

-- Nils one icon's five click-stamp fields; returns whether it carried a stamp. The only place
-- they are cleared. Declared here, above ClearClickStamps and every caller.
local function ClearClickStamp(icon)
	if icon._clickKey == nil then
		return false
	end
	icon._clickKey = nil
	icon._clickAnchor = nil
	icon._clickX = nil
	icon._clickY = nil
	icon._clickScale = nil
	return true
end

-- Nils the click stamps on every pooled icon of a container (via ClearClickStamp).
local function ClearClickStamps(pool)
	for i = 1, #pool do
		ClearClickStamp(pool[i])
	end
end

-- A container that stamped icons and then went away (hidden, or no settings) clears them and
-- marks the overlays dirty once. Costs one table read when nothing is stamped.
local function ClearContainerClickStamps(key, pool)
	if clickStampedIn[key] then
		clickStampedIn[key] = nil
		ClearClickStamps(pool)
		ns:MarkReminderClicksDirty()
	end
end

-- Phase 38 (CD-04) -- cooldown slots per container key, and the ns.trackerGeneration stamp
-- taken when the counts were last rebuilt. Same "constructed once, wiped in place, never
-- reconstructed" contract as slots/activeByKey above: RefreshCooldownSlotCounts wipe()s it.
--
-- Why a cache at all: a cooldown slot produces no timer, so a container holding only
-- cooldowns has #timers == 0 and would hide forever under hideWhenInactive. The obvious fix
-- (walk ns.db.trackedBuffs before the visibility test) adds a full pairs() walk per container
-- per UPDATE_INTERVAL on the HIDDEN path -- the common path -- which is exactly the hot-path
-- regression CLAUDE.md forbids. The tracker set only changes on a user edit, so one walk per
-- edit and a single integer compare per tick is the same answer for a tiny fraction of the cost.
local cooldownSlotCounts = {}
local cooldownCountStamp = -1

-- Phase 38 (CD-03) -- sticky spellID -> boolean "this spell has more than one charge".
-- Written ONLY from a value issecretvalue() says is readable. C_Spell.GetSpellCharges is
-- SecretWhenCooldownsRestricted, so in restricted combat maxCharges is a SECRET(number) and
-- Blizzard's own `maxCharges > 1` test would throw for a tainted caller. Caching the answer
-- from the moments it IS readable (PLAYER_REGEN_ENABLED, PLAYER_ENTERING_WORLD,
-- SPELLS_CHANGED) means the show/hide decision is never taken from a secret. Until one
-- readable answer arrives the count stays hidden -- a data-absence check, not a flavour check.
local chargeCapable = {}

-- Edit Mode placeholder for an empty bar list. Module-level and never mutated, so the
-- empty case costs no allocation. Its key matches no provider, so ns:GetDisplayInfoForKey
-- returns nil and the normal placeholder path renders the 134400 question-mark icon.
local EXAMPLE_BAR_SLOT = { key = "__tbt_example__", label = "Example Buff Name" }

---------------------------------------------------------------------
-- Settings refresh — reads ns.db.containerSettings into module-level cached tables
---------------------------------------------------------------------

local function RefreshContainerSettings()
	local all = ns.db and ns.db.containerSettings
	if not all then
		return
	end

	for _, def in ipairs(ns.CONTAINERS) do
		local src = all[def.key]
		if src then
			-- The cache table is created on first refresh and reused forever after, so the
			-- render path never allocates. A container whose DB settings are missing keeps a
			-- nil cache and is skipped by UpdateDisplay rather than rendering half-configured.
			local dst = cachedSettings[def.key]
			if not dst then
				dst = {}
				cachedSettings[def.key] = dst
			end

			dst.iconScale = math.max(0.1, (src.scale or 100) / 100)
			dst.iconPadding = src.padding or 5
			dst.alpha = (src.opacity or 100) / 100
			dst.visibleSetting = (src.visibility == 2) and 1 or (src.visibility == 3) and 2 or 0
			dst.hideWhenInactive = src.hideWhenInactive ~= false
			dst.timerShown = src.showTimer ~= false
			dst.tooltipsShown = src.showTooltips ~= false
			dst.clickToCast = src.clickToCast ~= false

			if def.kind == "bar" then
				dst.barWidth = BAR_WIDTH * (src.barWidth or 100) / 100
				dst.barContent = src.displayMode or 0
			else
				dst.orientationSetting = src.orientation or 0
				dst.iconDirection = src.growthDirection or 0
				-- math.max(1, ...) is load-bearing: a zero or negative value here divides by
				-- zero in RenderIconContainer's modulo/floor wrap arithmetic below.
				dst.itemsPerRow = math.max(1, src.itemsPerRow or 12)
			end
		end
	end

	-- A settings change reaches the moved CDM frames through the placement generation, never per tick.
	if ns.MarkMergedPlacementDirty then
		ns:MarkMergedPlacementDirty()
	end
end

ns.RefreshContainerSettings = RefreshContainerSettings

---------------------------------------------------------------------
-- Per-container runtime lifecycle (CONT-04) — the only allocation and release sites for
-- pools / timersByContainer / cachedSettings / ns.containerTooltipsShown. Core.lua's
-- ns:AttachContainerRuntime / ns:DetachContainerRuntime call these by key for every user
-- container, at rehydration and at runtime creation/deletion; the file-scope loop below
-- calls the allocator for the four base containers at load.
---------------------------------------------------------------------

-- Idempotent by construction (the `or {}` guards), so calling this twice for the same key
-- is harmless -- rehydration and the file-scope loop below both rely on that.
function ns.AllocateContainerRuntime(def)
	pools[def.key] = pools[def.key] or {}
	timersByContainer[def.key] = timersByContainer[def.key] or {}
	RefreshContainerSettings()
end

-- Safe to call for a key no longer present in ns.CONTAINERS: Core.lua's
-- ns:DeleteUserContainer unregisters the def before calling ns:DetachContainerRuntime (and
-- therefore this), by design, so this function is looked up by key alone and never walks
-- ns.CONTAINERS. WoW frames cannot be destroyed, so pooled frames are hidden and unparented
-- rather than freed; they then become unreachable along with the pool table itself.
function ns.ReleaseContainerRuntime(key)
	local pool = pools[key]
	if pool then
		for i = 1, #pool do
			pool[i]:Hide()
			pool[i]:SetParent(nil)
		end
		ClearClickStamps(pool)
	end
	clickStampedIn[key] = nil
	ns:MarkReminderClicksDirty()
	pools[key] = nil
	timersByContainer[key] = nil
	cachedSettings[key] = nil
	ns.containerTooltipsShown[key] = nil
end

-- Called only from ReminderClick's flush (a dirty edge), never per frame. Returns the count collected
-- and the count of stamped icons left out for not being visible (review WR-03: the flush retries).
function ns:CollectReminderClickIcons(out)
	wipe(out)
	local hidden = 0
	for _, def in ipairs(ns.CONTAINERS) do
		local pool = pools[def.key]
		if pool then
			for i = 1, #pool do
				local icon = pool[i]
				if icon._clickKey ~= nil then
					if icon:IsVisible() then
						out[#out + 1] = icon
					else
						hidden = hidden + 1
					end
				end
			end
		end
	end
	return #out, hidden
end

for _, def in ipairs(ns.CONTAINERS) do
	ns.AllocateContainerRuntime(def)
end

---------------------------------------------------------------------
-- Shared tooltip handler (Phase 22, D-18/D-19; extended Phase 23, D-01/D-02) —
-- used by bar + icon OnEnter (opts = nil, unchanged Phase 22 behavior, D-03/D-22)
-- and by CDMTab settings grid (opts populated with showSpellID/showDuration/extraLines).
-- Takes a frame (anchor), a proc table (numeric .spellID field), and optional opts.
-- Uniform: no type-discriminating branches (DISP-01) and no duplicated GameTooltip
-- wiring (DISP-03). Callers pass the proc directly — no legacy meta-info fallback chains.
---------------------------------------------------------------------

-- Fills GameTooltip with an item's own tooltip. SetItemByID is pcall'd: an item the client has
-- not cached (or does not know) falls back to its name, or "Item", rather than the empty frame
-- SetItemByID can otherwise leave. Shared by the on-screen icons (ns:ShowBuffTooltip below) and
-- the CDM tab's item tiles, which add their own lines after it.
function ns:SetTooltipItem(itemID)
	local ok = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
	if not ok then
		local fallbackName = C_Item.GetItemNameByID(itemID)
		if issecretvalue(fallbackName) or type(fallbackName) ~= "string" then
			fallbackName = "Item"
		end
		GameTooltip:SetText(fallbackName, 1, 1, 1)
	end
end

function ns:ShowBuffTooltip(frame, proc, opts)
	GameTooltip_SetDefaultAnchor(GameTooltip, frame)
	-- An item tracker (a bag item's saved entry is the on-screen icon's proc) gets the item's own
	-- tooltip: it has no spellID, and the spell path below would show only its label.
	local itemID = proc and proc.itemID
	if not opts and not issecretvalue(itemID) and type(itemID) == "number" and itemID > 0 then
		ns:SetTooltipItem(itemID)
		GameTooltip:Show()
		return
	end
	local spellID = (proc and type(proc.spellID) == "number") and proc.spellID or nil
	-- PAR-02 (D-13/D-14/D-15/D-16): a numeric spellID is not proof the client knows the
	-- spell. SetSpellByID on an unknown spell populates nothing while GameTooltip:Show()
	-- still renders an empty frame — the Forever lust defect found 2026-09-18. The fix
	-- lives here, not in LustProviderMixin, because the provider is correct to name its
	-- class-appropriate lust spell (changing it would break retail's working tooltip).
	-- This probe is defensive on every flavor, not Forever-specific — any client can fail
	-- to resolve any ID. TBT's own ID line below is suppressed when the spell resolves
	-- because Core.lua's TOOL-01 post-call already added it during SetSpellByID.
	local spellResolves = spellID ~= nil and C_Spell.GetSpellInfo(spellID) ~= nil
	local addedIDLine = false
	if spellResolves then
		GameTooltip:SetSpellByID(spellID)
	else
		GameTooltip:SetText((proc and proc.label) or "Unknown", 1, 1, 1)
	end
	if opts then
		if opts.showSpellID and spellID and not spellResolves then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Spell ID: " .. spellID, 0.8, 0.8, 0.8)
			-- TOOL-01 never ran here, since SetSpellByID was skipped for an
			-- unresolved spell, so this branch adds its own secrecy line.
			local secrecyLine = ns:SecrecyLine(ns:SpellAuraSecrecy(spellID))
			if secrecyLine then
				GameTooltip:AddLine(secrecyLine, 0.8, 0.8, 0.8)
			end
			addedIDLine = true
		end
		if opts.showDuration and proc and proc.duration and proc.duration > 0 then
			if not addedIDLine then
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
		if not ns.containerTooltipsShown[self.containerKey] then
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

-- Hoisted so CreateTimerIcon does not allocate a closure per pooled icon.
local function MarkCooldownsDirtyOnDone()
	ns:MarkCooldownsDirty()
end

-- The charge count's resting level, relative to its icon: one above the Cooldown, so it draws
-- over the swipe by LEVEL rather than by creation order. Declared above CreateTimerIcon, its
-- first user, for the upvalue-order rule.
local CHARGE_REST_LEVEL = 2

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
	-- THE fix for icons stuck grey after their cooldown ended (reported repeatedly in
	-- play-testing, most tellingly on 2026-09-22: out of combat, the spell came off cooldown and
	-- stayed grey until the next cast).
	--
	-- The grey is a SNAPSHOT, unlike the sweep. ApplyCooldownHandle writes a single boolean when
	-- ns.cooldownGeneration moves, and the generation only moves on SPELL_UPDATE_COOLDOWN /
	-- SPELL_UPDATE_CHARGES (Core.lua). SPELL_UPDATE_COOLDOWN is reliable when a cooldown STARTS
	-- and is not when one ENDS -- which is exactly why Blizzard's own viewer does not rely on it
	-- either: CooldownViewerBuffIconItemMixin hooks OnCooldownDone and calls RefreshActive from
	-- it (CooldownViewer.lua:1404-1406), and registers per-frame OnUpdate for items that need
	-- finer tracking. So nothing was re-evaluating the icon at the moment the cooldown expired,
	-- and the stale grey survived until some unrelated event moved the generation -- usually the
	-- player's next cast, which is precisely the reported symptom, and why it looked intermittent
	-- rather than constant: in combat something else bumps the generation within a second or two.
	--
	-- Hooking the same script Blizzard hooks fixes it at the source. The sweep TBT draws is the
	-- GCD-INCLUSIVE handle, so this also fires at the end of every global, which is harmless and
	-- mildly useful: it makes the grey self-correcting within about a second of any cast rather
	-- than sticky. Marking the generation dirty rather than re-running the apply inline keeps
	-- this to one counter bump; the next render pass does the work once for every icon.
	frame.cooldown:SetScript("OnCooldownDone", MarkCooldownsDirtyOnDone)
	frame.cooldown:SetAllPoints(frame.icon)
	frame.cooldown:SetReverse(true)
	frame.cooldown:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	frame.cooldown:SetSwipeColor(0, 0, 0, 0.7)
	frame.cooldown:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
	frame.cooldown:SetDrawEdge(true)
	frame.cooldown:SetDrawSwipe(true)

	-- Phase 38 (CD-03): charge count, copied field-for-field from Blizzard's own source in
	-- Blizzard_CooldownViewer/CooldownViewer.xml. Both CooldownViewerBuffIconItemTemplate
	-- (its `Applications` frame) and CooldownViewerEssentialItemTemplate (its `ChargeCount`
	-- frame) use the identical construction: a setAllPoints child *Frame* holding one
	-- OVERLAY FontString inheriting NumberFontNormal anchored BOTTOMRIGHT (-2, 2).
	-- Three details are load-bearing, not taste:
	--   * the child Frame is created AFTER the Cooldown, in the same <Frames> block, so it
	--     draws above the swipe -- an OVERLAY font string parented straight to the icon
	--     would sit under it. Since Phase 61 the level is also set explicitly, to
	--     CHARGE_REST_LEVEL, so the order no longer rests on creation order alone;
	--   * NumberFontNormal, not the 30x30 CooldownViewerUtilityItemTemplate's
	--     NumberFontNormalSmall -- TBT's icon is 40x40, the BuffIcon size, so NumberFontNormal
	--     is the matching pair;
	--   * hidden on creation, because a freshly pooled icon has no charge answer yet and the
	--     sticky chargeCapable cache only populates once a readable value arrives.
	-- Merge Mode puts Blizzard's own Essential item frame (re-anchored onto a cell) beside a
	-- TBT one in the same container, so any difference in font, size or position would show.
	frame.chargeCount = CreateFrame("Frame", nil, frame)
	frame.chargeCount:SetAllPoints()
	frame.chargeCount.Current = frame.chargeCount:CreateFontString(nil, "OVERLAY")
	frame.chargeCount.Current:SetFontObject(NumberFontNormal)
	frame.chargeCount.Current:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.chargeCount:SetFrameLevel(frame:GetFrameLevel() + CHARGE_REST_LEVEL)
	frame.chargeCount:Hide()

	-- Tooltips (Phase 22, D-19: delegates to shared ns:ShowBuffTooltip)
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", function(self)
		if not ns.containerTooltipsShown[self.containerKey] then
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

-- Both getters take the container key first: the pool is per container, new frames are
-- parented to that container, and .containerKey is what the OnEnter handlers read back to
-- find their own container's tooltip setting.
local function GetBar(key, index)
	local pool = pools[key]
	if not pool[index] then
		local bar = CreateTimerBar(ns.containers[key])
		bar.containerKey = key
		pool[index] = bar
	end
	return pool[index]
end

local function GetIcon(key, index)
	local pool = pools[key]
	if not pool[index] then
		local frame = CreateTimerIcon(ns.containers[key])
		frame.containerKey = key
		pool[index] = frame
	end
	return pool[index]
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
	-- One CDM viewer per registered container, resolved by name from the registry. A viewer
	-- without .itemFramePool is not a usable CooldownViewer and is left out.
	ns.cdmViewers = {}
	for _, def in ipairs(ns.CONTAINERS) do
		-- A user container (CONT-04) mirrors no Blizzard viewer, so a nil cdmViewerGlobal
		-- is normal here, not a failure -- guard the global lookup on the field existing.
		if def.cdmViewerGlobal then
			local viewer = _G[def.cdmViewerGlobal]
			if viewer and viewer.itemFramePool then
				ns.cdmViewers[def.key] = viewer
			end
		end
	end

	if not next(ns.cdmViewers) then
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
-- Display update — one render function per container kind (def.kind)
--
-- ns:UpdateDisplay calls one of these once per registered container every
-- UPDATE_INTERVAL seconds, so neither may construct a table: that would cost one
-- allocation per container per tick. The per-container tables (pools, settings,
-- timer lists) are built once at load; the scratch tables are module-level and
-- wiped here. Every `return` below ends one container's render only — the
-- dispatch loop carries on with the next container.
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Phase 38 — cooldown slot helpers (CD-02/CD-03/CD-04)
--
-- A cooldown is a SLOT, never a timer: it never enters ns.activeTimers, never reaches
-- BuffEngine's aura-driven cancellation scan (it has nothing to cancel), and produces
-- nothing for ns:GetActiveTimers to return.
-- Its sweep is owned by the engine, handed over once as a duration handle, and re-handed
-- only when Core.lua's ns.cooldownGeneration says something happened (SPELL_UPDATE_COOLDOWN,
-- SPELL_UPDATE_CHARGES, SPELLS_CHANGED, PLAYER_ENTERING_WORLD, PLAYER_REGEN_ENABLED or a
-- tracked cooldown cast). That is what keeps the 0.05s render tick free of API calls while
-- still tracking cooldown reduction live, in combat, with no /reload.
---------------------------------------------------------------------

-- Rebuild the per-container cooldown-slot counts, but only when the tracker set actually
-- changed. ns.trackerGeneration (Core.lua, Plan 01) advances on add/remove/edit only, so on
-- an idle frame this whole function is one integer compare and a return. Nil-guarded with
-- `or 0` so Display.lua still loads against a Core.lua without the counter.
local function RefreshCooldownSlotCounts()
	local generation = ns.trackerGeneration or 0
	if cooldownCountStamp == generation then
		return
	end

	local tracked = ns.db and ns.db.trackedBuffs
	if not tracked then
		-- Deliberately NOT stamped: the DB is simply not ready yet, so this must be retried
		-- on the next tick rather than cached as "no cooldown slots exist".
		return
	end

	cooldownCountStamp = generation
	wipe(cooldownSlotCounts)
	for key, entry in pairs(tracked) do
		-- Phase 47: a container holding only tracked items must stay visible too, for the
		-- identical reason a cooldown-only container does -- neither produces a
		-- ns.activeTimers entry, so #timers alone can never see them.
		-- Phase 57.3 (LOAD-03): an unloaded tracker does not count, so a container holding only
		-- unloaded cooldowns stays hidden under hideWhenInactive. ns:RebuildTrackerLoad bumps
		-- ns.trackerGeneration whenever the loaded set changes, so this stamp follows it.
		if ns:IsCooldownSlotEntry(entry) and entry.section and ns:IsTrackerLoaded(key) then
			cooldownSlotCounts[entry.section] = (cooldownSlotCounts[entry.section] or 0) + 1
		end
	end
end

-- Restore a pooled icon to full colour. `icon._desat` is a stamp that may only ever hold false
-- or nil, NEVER the value the cooldown path writes, because that value is a secret boolean and
-- `icon._desat ~= desaturated` would then compare against a secret. That comparison is precisely
-- what threw in play-testing on 2026-09-21:
--
--   Display.lua:615: attempt to compare a secret boolean value (execution tainted by
--   'TerribleBuffTracker')
--
-- and the raise is also why icons were reported stuck grey while available: it aborted before
-- SetDesaturated could be reached, so every pooled widget kept whatever desaturation it last
-- carried, which for a cooldown slot is grey. The cooldown path below therefore stamps nil and
-- writes unconditionally; only this clear path is stamped, because its two callers sit in the
-- per-tick render path and would otherwise issue a SetDesaturated call on every frame.
local function ClearIconDesaturation(icon)
	if icon._desat ~= false then
		icon._desat = false
		icon.icon:SetDesaturated(false)
	end
end

-- D-16/D-17: the per-widget icon cache. Refresh the texture only when the resolved spellID
-- changes, so a steady slot costs one comparison instead of an ns:GetSpellIcon lookup.
--
-- `cachedIcon == nil` is part of the TEST, not belt-and-braces, and it was earned by a bug: a
-- pooled frame starts with cachedSpellID AND cachedIcon nil, so a slot resolving to no spell
-- compared equal to a cache that was never populated, skipped the block, and was left with
-- SetTexture(nil) -- the placeholder rendered blank (fixed in 3c1acf2). 134400 is the
-- question-mark fallback it is left with instead.
--
-- RenderIconContainer's TIMER branch deliberately does not come through here; see the comment
-- on its own cache block for why.
--
-- Phase 43.1 (iconOverride): an item-backed CDM entry -- a trinket or a potion -- has no spell
-- texture to look up, so the merge mirror resolves its icon once at build time and hands it
-- through here. It wins over the spell lookup when present, which is Blizzard's own order:
-- GetSpellTexture checks GetSpellCategoryIcon and then the equip-slot texture before ever
-- reaching C_Spell.GetSpellTexture (CooldownViewerItemData.lua:548-590).
local function ApplyCachedIcon(widget, spellID, iconOverride)
	if widget.cachedSpellID ~= spellID or widget.cachedOverride ~= iconOverride or widget.cachedIcon == nil then
		widget.cachedSpellID = spellID
		widget.cachedOverride = iconOverride
		widget.cachedIcon = iconOverride or (spellID and ns:GetSpellIcon(spellID)) or 134400
	end
	widget.icon:SetTexture(widget.cachedIcon)
end

-- Drop the cooldown stamps a pooled widget carries away from a cooldown slot. Phase 38: a
-- widget recycled from a cooldown slot to a buff or a placeholder slot must not keep a stale
-- charge count or an engine-driven sweep.
--
-- The two user-duration stamps go with the rest, not separately: a widget that comes BACK to
-- the same tracker while it is still running would otherwise find _userCdGrey already true and
-- never re-apply the grey the branch it landed in has just removed.
--
-- CALLERS KEEP THEIR `if icon._cdKey then` GUARD; it is deliberately not folded in here. That
-- test is the steady-path cost -- one nil test per icon per frame, and nothing else -- and
-- moving it inside would make the steady path a function call instead.
local function ClearCooldownStamps(icon)
	icon._cdKey = nil
	icon._userCdState = nil
	icon._userCdGrey = nil
	icon._cdGen = nil
	icon.chargeCount:Hide()
	icon.cooldown:Clear()
end

-- Grey while the spell is on a real cooldown, full colour otherwise.
--
-- Split out of ApplyCooldownHandle in Phase 43.1 for the merged aura branch, which Phase 70
-- deleted; ApplyCooldownHandle is now its only caller. The rule it encoded for that branch is
-- Blizzard's, kept for reference: a spell whose aura lands on the TARGET keeps its cooldown grey
-- even while the aura drives the sweep -- CheckCacheCooldownValuesFromAura resets
-- cooldownDesaturated only `if not self:IsActivelyCast() or self:GetAuraDataUnit() == "player"`
-- (CooldownViewer.lua:899-901). Touch of the Magi is exactly that shape.
local function ApplyCooldownGrey(icon, spellID)
	if not spellID or not C_Spell.GetSpellCooldownDuration then
		ClearIconDesaturation(icon)
		return
	end

	-- The sweep uses the GCD-INCLUSIVE handle and the grey does not, which is not an
	-- inconsistency -- it is exactly what Blizzard does. CheckCacheCooldownValuesFromSpellCooldown
	-- sets cooldownShowSwipe and the swipe's start/duration from spellCooldownInfo whatever the
	-- global is doing, then sets cooldownDesaturated = isOnActualCooldown, which is defined as
	-- `not self.isOnGCD and self.cooldownIsActive` (CooldownViewer.lua:996, :1008). So a spell
	-- merely waiting out the global spins but stays full colour, and only a real cooldown greys.
	--
	-- C_Spell.GetSpellCooldownDuration's second argument is `ignoreGCD` (SpellDocumentation.lua
	-- :286-300), which gives that distinction without reading anything. pcall'd because the
	-- argument cannot be confirmed present on the Forever client from a Midnight-only source tree:
	-- a build that rejects it falls back to no grey at all rather than raising. This runs on a
	-- cooldown-generation change, never per frame, so the pcall is not a hot-path cost.
	local ok, realCooldown = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
	if not ok or not realCooldown or realCooldown.IsActive == nil then
		ClearIconDesaturation(icon)
		return
	end

	-- IsActive() returns a bool that is SECRET once cooldowns are restricted, so it is never
	-- compared, stamped, stored or tested -- it goes straight into the widget setter, which takes
	-- it as-is: SetDesaturated is SecretArguments = "AllowedWhenTainted"
	-- (SimpleTextureBaseAPIDocumentation.lua:414-422). Calling IsActive with no arguments is
	-- likewise fine; its own SecretArguments rule constrains what may be PASSED IN, and nothing is.
	-- The stamp is cleared to nil so ClearIconDesaturation cannot later skip its write on the
	-- strength of a stale false that this line has since overwritten.
	icon._desat = nil
	icon.icon:SetDesaturated(realCooldown:IsActive())
end

-- Hand the engine-owned duration handles to the widgets. NEITHER HANDLE IS READ FOR ITS VALUE:
-- the sweep handle goes straight from the fetch into the widget setter with a nil test as the
-- only thing done to it, and the grey handle has exactly one method called on it, IsActive, whose
-- result is passed on without ever being looked at. Neither is compared, concatenated, indexed as
-- data or tostring()ed. issecretvalue is not needed on the handles themselves --
-- C_Spell.GetSpellCooldownDuration is AllowedWhenTainted with no secrecy flag and returns a
-- LuaDurationObject, a userdata handle rather than a secret value -- but IsActive's RESULT is a
-- secret bool once cooldowns are restricted, which is handled at its call site below.
-- Both symbol tests are capability checks, not flavour checks: a client missing either the
-- fetch or the setter gets a cooldown icon with no sweep instead of a Lua error.
--
-- Phase 43.1 (hasCharges): a spell with charges is driven by its RECHARGE handle, not its
-- cooldown handle. A two-charge spell sitting at one charge is not on cooldown at all --
-- GetSpellCooldownDuration reports nothing, because the spell is castable -- so before this it
-- showed no timer whatsoever, and the player could not see the next charge coming.
--
-- C_Spell.GetSpellChargeDuration is the charge-side twin of GetSpellCooldownDuration
-- (SpellDocumentation.lua:233-248): same LuaDurationObject return, same AllowedWhenTainted, and
-- notably WITHOUT the SecretWhenCooldownsRestricted that GetSpellCharges carries. So it relays
-- exactly like the cooldown handle does, and nothing here reads a charge count.
--
-- Blizzard's equivalent is CheckCacheCooldownValuesFromCharges (CooldownViewer.lua:909-935),
-- which runs FIRST and suppresses the spell-cooldown pass entirely -- the `if not
-- self:HasVisualDataSource_Charges()` guard at :980. The branch below is that suppression.
--
-- One deliberate divergence: Blizzard draws a recharge with the edge only and the swipe off.
-- TBT keeps its usual swipe, because the swipe is what the player asked to see and because it
-- is already under the container's own "show timer" setting, which ApplyIconStyle reasserts.
--
-- The GREY needs no charge special-case and gets none. ApplyCooldownGrey above relays
-- GetSpellCooldownDuration(spellID, true):IsActive(), which for a charge spell is false
-- while any charge remains and true only at zero -- exactly Blizzard's rule
-- (cooldownDesaturated = false in the charge branch, isOnActualCooldown in the cooldown one),
-- arrived at without reading a single value.
local function ApplyCooldownHandle(icon, spellID, hasCharges)
	if not spellID or not C_Spell.GetSpellCooldownDuration or not icon.cooldown.SetCooldownFromDurationObject then
		icon.cooldown:Clear()
		return
	end

	-- Gated, and gated on a REAL charge count -- see the caller. GetSpellChargeDuration is
	-- MayReturnNothing, but "returns nothing for a spell without charges" is not something the
	-- documentation promises, and the first version of this took the CDM's own info.charges flag
	-- as the gate and found out the hard way: Touch of the Magi carries it, has no charges, and
	-- got back a non-nil handle with no recharge running. That handle draws nothing, so the spell
	-- lost its cooldown sweep entirely while the separate grey relay below still greyed it --
	-- "grey, with no counter", reported 2026-09-22. Whatever gates this must mean "this spell
	-- really does have more than one charge", not "the CDM has a charge display for it".
	local handle
	if hasCharges and C_Spell.GetSpellChargeDuration then
		handle = C_Spell.GetSpellChargeDuration(spellID)
	end
	if not handle then
		handle = C_Spell.GetSpellCooldownDuration(spellID)
	end
	if not handle then
		icon.cooldown:Clear()
		ClearIconDesaturation(icon)
		return
	end

	icon.cooldown:SetCooldownFromDurationObject(handle)
	ApplyCooldownGrey(icon, spellID)
end

-- Runs INSIDE the pcall below, so that `info.currentCharges` is indexed under protection.
-- Writing pcall(fs.SetText, fs, info.currentCharges) instead would index the struct OUTSIDE
-- the protected call -- Lua evaluates every argument before pcall runs -- which is the one
-- place a raise would take down every container's render rather than one icon's count.
-- The value reaches SetText and nothing else: no comparison, concatenation or tostring.
local function SetChargeText(fontString, info)
	fontString:SetText(info.currentCharges)
end

-- Show the charge count, matching Blizzard's CooldownViewer behaviour (shown whenever the
-- spell HAS charges, per 38-CONTEXT.md; not conditionally hidden at one charge).
--
-- C_Spell.GetSpellCharges is MayReturnNothing AND SecretWhenCooldownsRestricted, so `info`
-- can be nil and, when present, every field can be a SECRET(number). ns:CanReadTable gates
-- EVERY read of it, not just the first: chargeCapable is sticky, so a spell that was
-- charge-capable earlier in the session still takes the shown branch after a respec, a talent
-- swap, or a transient moment during PLAYER_ENTERING_WORLD when the spell is unresolvable.
-- On an unreadable struct the previous text is left exactly as it was rather than updated.
-- Called only on a generation change, never per frame, so the pcall is not a hot-path cost.
local function ApplyChargeCount(icon, spellID)
	if not spellID or not C_Spell.GetSpellCharges then
		icon.chargeCount:Hide()
		return
	end

	local info = C_Spell.GetSpellCharges(spellID)
	if not ns:CanReadTable(info) then
		return
	end

	-- The ONLY comparison this function makes on a game value, and issecretvalue guards it.
	-- Blizzard's CacheChargeValues tests maxCharges > 1 directly; that throws for a tainted
	-- caller on a secret, which is why the answer is cached from readable moments instead.
	local maxCharges = info.maxCharges
	if not issecretvalue(maxCharges) and type(maxCharges) == "number" then
		chargeCapable[spellID] = maxCharges > 1
	end

	local shown = chargeCapable[spellID] == true
	icon.chargeCount:SetShown(shown)
	if shown then
		pcall(SetChargeText, icon.chargeCount.Current, info)
	end
end

-- The item-count parallel to ApplyChargeCount above, and deliberately a separate function
-- rather than a branch inside it: ApplyChargeCount is driven by the game's own charge API keyed
-- on spellID, and an item entry's spellID is always nil, so it is a guaranteed Hide() for one --
-- it cannot be reused, taught or extended into an item path.
--
-- Reads ns:TrackedItemCount(entry.key) only. It is deliberately NOT the Suggested list's own
-- live bag-walk count cache: that table is wipe()d and rebuilt on every rescan and carries no
-- row at all for a zero-stock item, so wiring a tracked tile to it would silently break ITEM-09
-- (a stack that has left the bags entirely) the instant a bag change triggered a rescan.
--
-- A count of zero is a real answer and is shown, not hidden -- that is exactly the ITEM-09 case,
-- where the stack is gone and the sweep is still running. No value stamp is kept on the icon:
-- the caller's block already runs only on a generation change or a pooled-widget reassignment,
-- and ns:MarkCooldownsDirty() -- called by both the provider's decrement and its reconcile -- is
-- what makes a changed count reach this function.
local function ApplyItemCount(icon, entry)
	local count = ns:TrackedItemCount(entry.key)
	if type(count) ~= "number" then
		icon.chargeCount:Hide()
		return
	end

	icon.chargeCount.Current:SetText(count)
	icon.chargeCount:Show()
end

-- Render one cooldown slot into a pooled icon widget. Everything cheap (texture, style,
-- tooltip target) happens every tick; everything that costs an API call happens only when
-- ns.cooldownGeneration moved or this pooled widget changed which slot it draws.
-- Drive a custom cooldown tracker from the duration the USER typed, off the cast TBT saw.
--
-- This reverses CD-02, by user decision on 2026-09-22, and the reason it was decided the other
-- way is worth keeping: the game's own handle is exact and follows cooldown reduction, where a
-- typed number cannot. The cost of the reversal is real -- haste, CDR and reset procs will make
-- the number wrong -- and it is accepted, because a player who types a duration for a spell the
-- game already knows is telling TBT something the game does not know: an internal cooldown, a
-- "do not use again yet" reminder, a pull timer. Overriding that with the game's answer made the
-- typed value do nothing at all for any spell the client tracks, which is what was reported.
--
-- Returns true when it owns the icon, so the engine-handle path below is skipped entirely.
-- Nothing here is secret: the start is GetTime() at the cast, the duration is the player's own
-- number, and the comparison is between two plain numbers.
local function ApplyUserCooldown(icon, entry, now)
	-- Read through ns:CooldownDuration, the one entry point for a cooldown's length (Core.lua). A
	-- plain number, so everything this function says below about comparing numbers holds.
	local duration = ns:CooldownDuration(entry.key, entry)
	if type(duration) ~= "number" or duration <= 0 then
		return false
	end

	-- The timer branch above -- a real proc, or a preview demo while the CDM config is open --
	-- draws into this same widget and stamps icon._lastStart when it does. Seeing that stamp here
	-- means something else owned the sweep since this function last spoke, so whatever it
	-- asserted is stale and must be asserted again.
	--
	-- This is what was missing, and why a demo sweep kept running after the config window closed:
	-- the state below said "not on cooldown, already cleared" from before the window opened, the
	-- preview then drew over it, and on close the comparison still matched, so nothing cleared
	-- the preview's sweep. The clear has to be owned by whoever owns the icon, not conditional on
	-- having set it.
	if icon._lastStart ~= nil then
		icon._lastStart = nil
		icon._userCdState = nil
	end

	local startedAt = ns.cooldownStarts[entry.key]
	local running = startedAt ~= nil and (now - startedAt) < duration
	-- false, not nil, so "asserted clear" is distinguishable from "never asserted": a pooled
	-- widget arriving here for the first time must always be told, and nil is what it starts at.
	local want = running and startedAt or false

	-- Stamped for the same reason the buff path stamps icon._lastStart: SetCooldown is
	-- fire-and-forget, so re-issuing it every tick would restart the animation every frame.
	if icon._userCdState ~= want then
		icon._userCdState = want
		if running then
			icon.cooldown:SetCooldown(startedAt, duration)
		else
			icon.cooldown:Clear()
		end
	end

	-- Grey while running, full colour when ready -- the same rule the engine path applies, but
	-- reached by comparing numbers instead of relaying a secret boolean, so the GCD cannot leak
	-- into it and there is no stale-snapshot problem to guard against.
	if icon._userCdGrey ~= running then
		icon._userCdGrey = running
		icon._desat = nil
		icon.icon:SetDesaturated(running)
	end

	return true
end

local function ApplyCooldownSlot(icon, entry, settings, now)
	-- Every entry ns:AddTrackedBuff has ever written carries a numeric spellID, so this screen
	-- should never fire; when it does it yields a blank icon with no sweep, not an error.
	local spellID = entry.spellID
	if type(spellID) ~= "number" then
		spellID = nil
	end

	ApplyCachedIcon(icon, spellID, entry.iconOverride)
	ApplyIconStyle(icon, settings)

	-- The DB entry itself is the tooltip payload: it already carries the numeric spellID and
	-- the label ns:ShowBuffTooltip reads, so the placeholder branch's per-tick table
	-- constructor is not needed here.
	icon.proc = entry

	-- A custom tracker's own duration wins over the game's handle, and is evaluated EVERY tick
	-- rather than on a generation change: nothing fires an event when a TBT-owned cooldown
	-- finishes, so the grey has to come off by the clock. Two number comparisons and two stamp
	-- tests on the steady path, no API call and no allocation.
	local userOwned = ApplyUserCooldown(icon, entry, now)

	if icon._cdGen ~= ns.cooldownGeneration or icon._cdKey ~= entry.key then
		icon._cdGen = ns.cooldownGeneration
		icon._cdKey = entry.key
		-- Clear the buff-path stamp so a later real or preview timer landing on this pooled
		-- widget re-issues its SetCooldown instead of being skipped as unchanged.
		icon._lastStart = nil
		-- Charges first, because ApplyCooldownHandle now asks whether this spell has any: the
		-- answer lives in the sticky chargeCapable cache that ApplyChargeCount fills, and calling
		-- it second left the very first generation of a charge spell with no recharge sweep.
		--
		-- Charges come from the game whoever owns the sweep: a typed duration says how long the
		-- player wants to wait, never how many charges the spell has.
		--
		-- Phase 47: an item entry has no charges and no spellID for the charge API to answer
		-- about, so it branches to the item-count parallel instead, in the same position in the
		-- block -- the ordering reason above applies identically to it.
		if ns:IsBagItemEntry(entry) then
			ApplyItemCount(icon, entry)
		else
			ApplyChargeCount(icon, spellID)
		end

		-- Where the entry has a spell, C_Spell.GetSpellCooldownDuration hands back a duration object
		-- rather than a value, has no secrecy flag, and so works in combat and out of it.
		if not userOwned then
			if spellID then
				-- chargeCapable ALONE, deliberately. It is set from maxCharges > 1 on a real
				-- C_Spell.GetSpellCharges struct, which is the same thing Blizzard's charge
				-- branch decides on, so it means what it says.
				--
				-- The CDM's own info.charges flag (once mirrored as entry.hasCharges, removed in
				-- Phase 70) is NOT consulted here
				-- and was the cause of the Touch of the Magi regression: it is true for entries
				-- that have a charge DISPLAY rather than charges, and swapping in a recharge
				-- handle for a spell that never recharges leaves the icon with no sweep at all.
				--
				-- The cost of the stricter gate is that a charge spell first seen inside
				-- restricted content, where GetSpellCharges is secret, shows no recharge until a
				-- readable moment arrives. That is the same sticky-cache limitation the charge
				-- COUNT already has, and it fails by omitting information rather than by
				-- replacing a working sweep with a blank one.
				ApplyCooldownHandle(icon, spellID, chargeCapable[spellID] == true)
			else
				-- The "nothing owns a sweep here" terminus: it must clear the grey as well as the
				-- sweep, or a pooled widget keeps whatever the last entry to use it left behind.
				--
				-- Reported on retail 2026-09-24: an augment rune has no cooldown on the
				-- current patch, so entry.duration stays 0, ApplyUserCooldown declines it at
				-- its first guard, and it falls through to here and renders grey. No
				-- cooldown means READY, which is full colour.
				icon.cooldown:Clear()
				ClearIconDesaturation(icon)
			end
		end
	end
end

-- Phase 40 (STEAL-03/STEAL-04): the mirrored CDM slots for this container, built by
-- MergeMode.lua's event-driven mirror refresh -- never rebuilt here, never a table constructor.
-- Off (Merge Mode disabled) leaves this array empty, so it costs one index and one # per tick
-- with no branch on merge-mode state at either call site.
--
-- ns.mergeShownSlots, NOT ns.mergeSlots: the latter is everything the player's CDM has
-- CONFIGURED, the former only what the CDM currently has on screen. Reading the configured set
-- here is what put a tracked debuff in TBT permanently instead of while it was on the target --
-- see the long note above ns:RefreshMergeShownSlots in MergeMode.lua.
--
-- Two return values rather than a table: this runs once per container per tick, for every
-- container, and must not allocate.
local function MergedSlotsFor(def)
	local merged = ns.mergeShownSlots and ns.mergeShownSlots[def.key]
	return merged, merged and #merged or 0
end

-- Index this tick's live timers by stable provider key -- THE slot identity (string for meta
-- trackers, numeric for user spells). Every provider populates proc.key at OnTrigger time.
--
-- Called from each render function at its OWN position, which is deliberately not the same one:
-- RenderBarContainer fills the index BEFORE it builds its slots, RenderIconContainer AFTER it
-- has built them and appended the mirror. Neither reads the index before its call, so the two
-- orders agree today -- but aligning them is a behaviour change nothing here can test, so they
-- stay where they were.
local function BuildActiveByKey(timers)
	wipe(activeByKey)
	for _, timer in ipairs(timers) do
		activeByKey[timer.key] = timer
	end
end

-- Phase 40 (STEAL-03): append this container's mirrored CDM slots to the shared slot list.
-- They go in AFTER the caller's sort and are never sorted into it -- that preserves both the
-- user's own layoutOrder and the CDM's own configured order exactly, with no layoutOrder value
-- to invent for a mirror entry.
local function AppendMergedSlots(merged, mergedCount)
	if merged then
		for i = 1, mergedCount do
			table.insert(slots, merged[i])
		end
	end
end

local function RenderBarContainer(def, container, settings, timers, now)
	ns.containerTooltipsShown[def.key] = settings.tooltipsShown

	local pool = pools[def.key]
	-- Phase 40 (STEAL-03/STEAL-04): the mirror read, shared with RenderIconContainer -- see
	-- MergedSlotsFor for why it is the SHOWN set and not the configured one.
	local merged, mergedCount = MergedSlotsFor(def)
	-- Merge Mode on: Blizzard's bar item frames are placed on merged rows instead of TBT drawing them.
	local reanchorHere = ns:IsMergeReanchorActive()
	-- The container's CDM viewer, resolved once per render rather than per merged slot (Phase 69
	-- review IN-05): the only viewer whose frames may sit on this container's cells.
	local ownViewer = reanchorHere and (ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal])
	-- Phase 40 (STEAL-03): a container holding only mirrored CDM bars must still be visible
	-- under hideWhenInactive.
	-- Phase 57.2 review WR-03: reminders are icon-only (CreateUserContainer, v10 migration); the
	-- bar path has no reminder gate.
	local hasActiveTimers = #timers > 0 or mergedCount > 0
	local barEditing = ns.editModeActive
	local visible = ShouldShow(settings.visibleSetting, hasActiveTimers, settings.hideWhenInactive, barEditing)

	if not visible then
		-- STEAL-15: returning before ns:AttachMergedItem means this container's merged frames go back
		-- to the parked viewer in the flush; the render that shows it again re-attaches them.
		container:Hide()
		return
	end

	container:Show()
	local barWidth = settings.barWidth
	-- CDM applies padding in container (unscaled) space between scaled children
	local padding = settings.iconPadding + BAR_PADDING_OFFSET

	-- Build bar slots: all tracked bar entries if showing inactive, else active only
	BuildActiveByKey(timers)

	local showPlaceholders = not settings.hideWhenInactive or ns.configOpen or barEditing
	wipe(slots)
	if showPlaceholders then
		for dbKey, entry in pairs(ns.db.trackedBuffs) do
			-- Phase 38: "cooldowns are icons, never bars" is a locked user decision, so a
			-- cooldown tracker misfiled into a bar container is skipped rather than drawn as
			-- a permanently-empty bar. One extra field comparison per entry, no allocation.
			-- Phase 47: a tracked item is icon-only for the identical reason -- the locked
			-- v0.4.0 decision that item trackers render icon-only with a count -- so it is
			-- excluded here on the same terms, or it would draw as a permanently-empty bar too.
			-- Phase 57.3 (LOAD-03): a tracker that is not loaded takes no slot and no grid cell,
			-- in Edit Mode and the settings preview too. One cached table read per entry.
			if entry.section == def.key and not ns:IsCooldownSlotEntry(entry) and ns:IsTrackerLoaded(dbKey) then
				-- Phase 57 (DTRK-03): a gated-off tracker is skipped here unless the settings or
				-- Edit Mode are open.
				local gate = ns:ReminderGate(dbKey, entry)
				if gate ~= false or ns.configOpen or barEditing then
					entry.key = dbKey -- stable slot identity, a `<kind>:<id>` string
					table.insert(slots, entry)
				end
			end
		end
		table.sort(slots, ByLayoutOrder)
	else
		for _, t in ipairs(timers) do
			-- Phase 57 (DTRK-03): this branch only runs with the settings and Edit Mode
			-- closed, so a gated-off timer is dropped here rather than drawn.
			local gate = ns:ReminderGate(t.key, ns.db.trackedBuffs[t.key])
			if gate ~= false then
				table.insert(slots, t) -- procs already have .key from provider
			end
		end
	end

	-- Phase 40 (STEAL-03): mirrored CDM bars are appended after EITHER branch above and its sort
	-- -- see AppendMergedSlots for that contract. Specific to this path: the append happens
	-- before the example-slot check below, so a container holding mirrored bars never shows the
	-- "Example Buff Name" placeholder.
	AppendMergedSlots(merged, mergedCount)

	-- With nothing tracked, the sizing below produced a 1px-tall container, which
	-- cannot be clicked — so the bar container could not be picked up in Edit Mode
	-- at all. The 30px floor in ns:ShowEditModeHandles did not help: it runs once on
	-- Edit Mode enter and the next UpdateDisplay overwrote it. Render one example slot
	-- instead, which gives the container a real height and shows what it is for.
	if barEditing and #slots == 0 then
		table.insert(slots, EXAMPLE_BAR_SLOT)
	end

	-- Layout bars inside container.
	-- Match CDM GridLayoutFrame: step = GetHeight() + padding (both
	-- unscaled). SetScale on each bar frame scales the offset naturally.
	local scale = settings.iconScale
	local step = BAR_HEIGHT + padding

	for i, slot in ipairs(slots) do
		local bar = GetBar(def.key, i)
		-- Every slot (DB entry OR proc) carries .key — stable slot identity.
		local timer = activeByKey[slot.key]

		bar:ClearAllPoints()
		-- Inter-item padding only: first bar at 0, subsequent bars offset by step
		bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -((i - 1) * step))

		ApplyBarStyle(bar, barWidth, settings)

		-- Merge Mode on: the row is laid out and styled above, so it is the cell Blizzard's bar
		-- frame for this cooldownID is placed on; TBT's own bar stays hidden. Such a row needs no
		-- icon, label, fill or time (Phase 70 review IN-03): writing them every tick onto a bar that
		-- is hidden straight after was pure per-frame waste. Only the preview placeholder
		-- (cdmFrameVisible == false, below) needs the content block.
		--
		-- STEAL-14: the cell shows only what Blizzard draws. In Edit Mode with the CDM's own Edit
		-- Mode checkbox off, or with the viewer's Visibility hiding it, Blizzard draws nothing, so
		-- TBT previews the entry itself (the placeholder filled below). Not attaching sends the
		-- hidden frame back to the parked viewer, so nothing is drawn twice.
		-- Gated on the stamp ALONE (Phase 69 review WR-01): the shown-slot pass stamps it false only
		-- while ns:IsMergePreviewState() holds and the frame is not drawn, and true otherwise, so live
		-- play never takes the placeholder branch. A second preview predicate here (TBT's own Edit
		-- Mode flag, the polled settings flag) could only disagree with the one the stamp was made
		-- under.
		if reanchorHere and slot.isMerged and slot.cdmFrameVisible ~= false then
			bar.proc = slot
			bar:Hide()
			ns:AttachMergedItem(slot, bar, settings, "bar", ownViewer)
		else
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
			elseif slot.isMerged then
				-- Phase 40 (STEAL-03/STEAL-04): the mirror entry (built by MergeMode.lua) is
				-- already the tooltip payload -- gate on this mirror flag, not on slot.spellID,
				-- because every DB entry also carries a spellID and bypassing ns:GetDisplayInfoForKey for
				-- those would silently change the Trinket/Pot meta-tracker resolution Phase 27
				-- exists to protect. Falls through to the placeholder rendering below: empty bar,
				-- no fill, no timer.
				--
				-- This resolves the icon and label only. The CDM's own bar frame draws the fill and the
				-- time on this row.
				bar.proc = slot
				resolvedSpellID = slot.spellID
				resolvedLabel = slot.label
			else
				local info = ns:GetDisplayInfoForKey(slot.key)
				if info and info.spellID then
					-- D2: a per-widget OWNED table, refilled in place rather than rebuilt. This block is
					-- reached for every inactive tracker on every 20 Hz tick whenever "hide when inactive"
					-- is off -- in combat, across an unbounded number of containers since Phase 36 -- and
					-- allocated one table each time.
					--
					-- It has to be a SEPARATE field. bar.proc is sometimes BORROWED: the timer branch above
					-- stores the live ns.activeTimers table straight into it, and the merged branch stores
					-- the mirror slot. Wiping and reusing bar.proc itself would wipe a live timer
					-- the engine still owns.
					--
					-- All three fields are assigned on EVERY pass. The table outlives the slot that last
					-- used it, so a field written only on some paths would leak that slot's value into the
					-- next one's tooltip. ns:ShowBuffTooltip also reads proc.duration when opts.showDuration
					-- is set; this table has no duration, and any fourth field added later is assigned
					-- unconditionally or it does not go in here.
					local p = bar._placeholderProc
					if not p then
						p = {}
						bar._placeholderProc = p
					end
					p.spellID, p.label, p.key = info.spellID, info.label, slot.key
					bar.proc = p
					resolvedSpellID = info.spellID
					resolvedLabel = info.label or slot.label
				else
					bar.proc = nil
					resolvedSpellID = nil
					resolvedLabel = slot.label
				end
			end

			ApplyCachedIcon(bar, resolvedSpellID, slot.iconOverride)
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

			if reanchorHere and slot.isMerged then
				-- The preview placeholder (cdmFrameVisible == false): the live merged row took the
				-- attach branch above.
				bar:Show()
			elseif slot.isMerged then
				-- Fail-closed: a merged row is never drawn by TBT outside the preview placeholder above.
				bar:Hide()
			else
				bar:Show()
			end
		end
	end

	-- Size container in parent (unscaled) space.
	-- Inter-item padding only: n items with (n-1) gaps between them
	local n = #slots
	local totalHeight = n > 0 and (n * BAR_HEIGHT + (n - 1) * padding) * scale or 0
	container:SetHeight(math.max(1, totalHeight))
	-- Width tracks barWidth setting
	container:SetWidth(math.max(1, barWidth * scale))

	-- Hide unused bars
	for i = n + 1, #pool do
		pool[i]:Hide()
	end
end

-- TBT's own icon-and-name placeholder for a merged entry whose Blizzard frame is not drawn while
-- previewing (STEAL-14). The entry, built by MergeMode.lua's mirror refresh, is already the
-- tooltip payload: it carries spellID and label directly, the same trick ApplyCooldownSlot uses.
--
-- It draws no sweep, countdown or charge count: Blizzard's own frame draws all three once it is
-- shown.
local function ShowMergedPlaceholderIcon(icon, entry, settings)
	-- Phase 38: same pooled-widget reset as the timer branch -- see ClearCooldownStamps.
	if icon._cdKey then
		ClearCooldownStamps(icon)
	end
	if icon._lastStart then
		icon._lastStart = nil
		icon.cooldown:Clear()
	end

	icon.proc = entry
	ApplyCachedIcon(icon, entry.spellID, entry.iconOverride)
	ClearIconDesaturation(icon)
	ApplyIconStyle(icon, settings)
	icon:Show()
end

local function RenderIconContainer(def, container, settings, timers, now)
	ns.containerTooltipsShown[def.key] = settings.tooltipsShown

	local pool = pools[def.key]
	-- Phase 40 (STEAL-03/STEAL-04): the mirror read, shared with RenderBarContainer -- see
	-- MergedSlotsFor for why it is the SHOWN set and not the configured one.
	local merged, mergedCount = MergedSlotsFor(def)
	-- Phase 38 (CD-04): a cooldown slot is ALWAYS shown -- it produces no timer, so a
	-- container holding only cooldowns would have #timers == 0 and hide forever. A cooldown
	-- slot therefore counts as activity for hideWhenInactive, matching Blizzard's Essential
	-- and Utility viewers. The count comes from the generation-stamped cache rebuilt once in
	-- ns:UpdateDisplay, never from a per-tick pairs() walk on this (usually hidden) path.
	-- Phase 40 (STEAL-03): a container holding only mirrored CDM items must still be visible
	-- under hideWhenInactive, or a merge-mode-only container never shows.
	-- Tracked Buffs publishes its whole configured set as merged slots, so mergedCount alone keeps
	-- a container holding merged entries shown.
	-- Merge Mode on: Blizzard's item frames are placed on merged cells instead of TBT drawing them.
	local reanchorHere = ns:IsMergeReanchorActive()
	-- Resolved once per render, as in RenderBarContainer (Phase 69 review IN-05).
	local ownViewer = reanchorHere and (ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal])
	-- Phase 57.2 (REM-03): a reminder whose buff is missing must keep its container shown
	-- under hideWhenInactive, exactly like a cooldown slot does above.
	local hasActiveIcons = #timers > 0
		or (cooldownSlotCounts[def.key] or 0) > 0
		or mergedCount > 0
		or ns:ReminderShowsIn(def.key)
	local iconEditing = ns.editModeActive
	local iconVisible = ShouldShow(settings.visibleSetting, hasActiveIcons, settings.hideWhenInactive, iconEditing)

	if not iconVisible then
		-- STEAL-15: returning before ns:AttachMergedItem means this container's merged frames go back
		-- to the parked viewer in the flush; the render that shows it again re-attaches them.
		container:Hide()
		-- A hidden container has no clickable area. One table read per tick, no pool walk.
		ClearContainerClickStamps(def.key, pool)
		return
	end

	container:Show()

	wipe(slots)
	for dbKey, entry in pairs(ns.db.trackedBuffs) do
		-- Phase 57.3 (LOAD-03): a tracker that is not loaded takes no slot and no grid cell, in
		-- Edit Mode and the settings preview too. One cached table read per entry.
		if entry.section == def.key and ns:IsTrackerLoaded(dbKey) then
			-- Phase 57 review WR-01, reminders since Phase 57.2: a reminder whose gate is false
			-- (its buff is up, or its state is unknown) is dropped here, exactly as the bar path
			-- drops it, so it takes no grid cell and does not count toward the container's size.
			-- Only the settings or Edit Mode keep it in the list.
			if ns:ReminderGate(dbKey, entry) ~= false or ns.configOpen or iconEditing then
				entry.key = dbKey -- stable slot identity
				table.insert(slots, entry)
			end
		end
	end
	table.sort(slots, ByLayoutOrder)

	-- Phase 40 (STEAL-03): mirrored CDM slots are appended AFTER the sort -- see
	-- AppendMergedSlots.
	AppendMergedSlots(merged, mergedCount)

	BuildActiveByKey(timers)

	-- Match CDM GridLayoutFrame: step = GetSize() + padding (unscaled).
	-- SetScale on each icon scales the offset naturally.
	local iconPadding = settings.iconPadding + ICON_PADDING_OFFSET
	local step = BUFF_ICON_SIZE + iconPadding
	local orientation = settings.orientationSetting -- 0=Horizontal, 1=Vertical
	local direction = settings.iconDirection -- 0=Right/Down, 1=Left/Up, 2=Centered
	local perRow = settings.itemsPerRow

	-- Centred is a buff- and reminder-container setting (Phase 57.2: reminders centre like buffs).
	-- Re-derived here rather than trusted from the database, so a value left behind by a
	-- container that changed category cannot produce a layout its dropdown never offered.
	local centered = direction == ns.GROWTH_CENTERED and ns:GetContainerCategory(def) ~= "spells"

	-- The run is centred against the container's own width in cells, so this is the reserved
	-- count -- not the drawn one. See CenteredSlotPlacement.
	local capacity = math.min(#slots, perRow)
	local drawnCount = 0
	if centered then
		for i = 1, #slots do
			local entry = slots[i]
			if SlotDraws(entry, activeByKey[entry.key], settings, iconEditing) then
				drawnCount = drawnCount + 1
			end
		end
	end
	local drawnIndex = 0
	-- Review IN-03: recomputed each pass so clickStampedIn clears once the last stamp does.
	local anyStamped = false

	for slotIndex, entry in ipairs(slots) do
		local icon = GetIcon(def.key, slotIndex)
		local timer = activeByKey[entry.key]
		local gate = ns:ReminderGate(entry.key, entry)

		local anchor, offsetMajor, offsetMinor
		if centered then
			-- A slot that draws nothing takes no cell at all, which is what makes the run close
			-- up and re-centre. Placed before the branch chain so the chain itself is untouched.
			if SlotDraws(entry, timer, settings, iconEditing) then
				drawnIndex = drawnIndex + 1
				anchor, offsetMajor, offsetMinor =
					CenteredSlotPlacement(drawnIndex, drawnCount, capacity, step, perRow, orientation)
			end
		else
			anchor, offsetMajor, offsetMinor = ns:GridSlotPlacement(slotIndex, step, perRow, orientation, direction)
		end

		icon:ClearAllPoints()
		if anchor then
			icon:SetPoint(anchor, container, anchor, offsetMajor, offsetMinor)
		end

		if reanchorHere and entry.isMerged then
			-- Merge Mode on: Blizzard's own item frame is moved onto this cell.
			-- The pooled icon is styled (it carries the container's scale) but stays hidden; it is
			-- only the cell the CDM frame is anchored to and sized from.
			--
			-- Accepted (Phase 68 review IN-01): in a Centered container a merged buff the CDM does not
			-- show yet takes no cell, so its cell has no points above. Blizzard shows the frame the
			-- moment the aura lands, but it has no rect until the shown-slot pass stamps cdmShown and
			-- the next render anchors the cell -- one frame plus up to UPDATE_INTERVAL late, each time
			-- the buff is applied. Once the cell is anchored the frame follows it.
			--
			-- STEAL-14: while previewing, an entry whose Blizzard frame is not drawn gets TBT's own
			-- placeholder instead and is not attached; see the bar path's comment for the reasoning.
			if entry.cdmFrameVisible == false then
				ShowMergedPlaceholderIcon(icon, entry, settings)
			else
				ApplyIconStyle(icon, settings)
				icon:Hide()
				ns:AttachMergedItem(entry, icon, settings, "icon", ownViewer)
			end
		elseif entry.isMerged then
			-- Fail-closed: unreachable while merged entries exist only with Merge Mode on, because the
			-- re-anchor branch above takes every one of them. If that ever breaks, a merged entry is
			-- hidden here rather than drawn by TBT.
			icon:Hide()
		elseif timer then
			-- Phase 38: drop the stamps a cooldown slot left on this pooled widget -- see
			-- ClearCooldownStamps. One nil test per icon per frame in the common case.
			if icon._cdKey then
				ClearCooldownStamps(icon)
			end

			icon.proc = timer -- D-19: store for OnEnter tooltip

			-- D-16/D-17: Per-widget icon cache — refresh texture only when spellID changes.
			-- NOT ApplyCachedIcon, deliberately: this block has no `cachedIcon == nil` test and
			-- no 134400 fallback, so it is not the same text. It is probably equivalent -- a live
			-- timer always carries a numeric spellID -- but that is a reachability argument, and
			-- nothing can test the timer path before Phase 43. Left as it is on purpose.
			if icon.cachedSpellID ~= timer.spellID then
				icon.cachedSpellID = timer.spellID
				icon.cachedIcon = ns:GetSpellIcon(timer.spellID)
			end
			icon.icon:SetTexture(icon.cachedIcon)
			-- Buff icons are never greyed; only a cooldown slot desaturates. Cleared here so a
			-- pooled widget that last drew a cooldown does not keep its grey.
			ClearIconDesaturation(icon)
			ApplyIconStyle(icon, settings)

			if icon._lastStart ~= timer.startedAt then
				icon._lastStart = timer.startedAt
				icon.cooldown:SetCooldown(timer.startedAt, timer.duration)
			end

			icon:Show()
		elseif ns:IsCooldownSlotEntry(entry) then
			-- Phase 38 (CD-02/CD-03/CD-04): placed BELOW the timer branch and ABOVE the
			-- placeholder branch, and both halves of that order matter. Below the timer
			-- branch so that in preview mode the synthetic proc BuffEngine builds for a
			-- cooldown entry wins and drives the demo sweep through the ordinary
			-- SetCooldown path, with no type branching (CD-05). Above the placeholder
			-- branch so a cooldown icon is shown regardless of hideWhenInactive -- the
			-- only sensible behaviour for a slot that produces no timers, and what
			-- Blizzard's Essential and Utility viewers do.
			-- Phase 47: a tracked item entry reaches here too, and needs no branch body change
			-- -- ApplyCooldownSlot is already generic on entry.key/entry.duration, and its own
			-- generation-gated block branches ApplyChargeCount vs ApplyItemCount internally.
			ApplyCooldownSlot(icon, entry, settings, now)
			icon:Show()
		elseif gate == true or not settings.hideWhenInactive or ns.configOpen or iconEditing then
			-- Phase 57.2 (REM-03): a reminder is this placeholder -- full colour, no sweep, no
			-- timer -- drawn even under hideWhenInactive via `gate == true` (its buff is missing).
			--
			-- Phase 38: same pooled-widget reset as the timer branch above -- see
			-- ClearCooldownStamps.
			if icon._cdKey then
				ClearCooldownStamps(icon)
			end

			-- Placeholder: resolve icon via ns:GetDisplayInfoForKey. A mirrored slot never reaches
			-- here: the re-anchor branch or the fail-closed arm above catches it first.
			local info = ns:GetDisplayInfoForKey(entry.key)
			local resolvedSpellID = info and info.spellID or nil
			if info and info.spellID then
				-- D2: the bar path's reused per-widget table, for the same reason and with the same
				-- two rules -- see RenderBarContainer's placeholder branch. A separate field because
				-- icon.proc is sometimes a borrowed live timer or a borrowed DB entry, and all three
				-- fields on every pass because the table outlives the slot that last filled it.
				local p = icon._placeholderProc
				if not p then
					p = {}
					icon._placeholderProc = p
				end
				p.spellID, p.label, p.key = info.spellID, info.label, entry.key
				icon.proc = p
			else
				icon.proc = nil
			end

			ApplyCachedIcon(icon, resolvedSpellID, entry.iconOverride)
			ClearIconDesaturation(icon)
			ApplyIconStyle(icon, settings)

			if icon._lastStart then
				icon._lastStart = nil
				icon.cooldown:Clear()
			end

			icon:Show()
		else
			icon:Hide()
		end

		-- Phase 63 (CLICK-04): the only per-tick part of clickable reminders -- comparisons only.
		-- GetRect and every secure write happen in ReminderClick's flush, on the dirty edge.
		-- gate == true is exactly the placeholder branch that draws a missing-buff reminder.
		local clickKey = (gate == true and settings.clickToCast and not iconEditing and anchor ~= nil) and entry.key
			or nil
		if
			icon._clickKey ~= clickKey
			or (
				clickKey
				and (
					icon._clickAnchor ~= anchor
					or icon._clickX ~= offsetMajor
					or icon._clickY ~= offsetMinor
					or icon._clickScale ~= settings.iconScale
				)
			)
		then
			if clickKey then
				icon._clickKey = clickKey
				icon._clickAnchor = anchor
				icon._clickX = offsetMajor
				icon._clickY = offsetMinor
				icon._clickScale = settings.iconScale
			else
				ClearClickStamp(icon)
			end
			ns:MarkReminderClicksDirty()
		end
		if clickKey then
			anyStamped = true
		end
	end
	clickStampedIn[def.key] = anyStamped or nil

	-- Hide extra icons
	for i = #slots + 1, #pool do
		pool[i]:Hide()
		if ClearClickStamp(pool[i]) then
			ns:MarkReminderClicksDirty()
		end
	end

	-- Size the icon container to fit its visible children (inter-item padding only).
	-- majorCount is clamped to perRow (a full row/column along the flow axis) and
	-- minorCount is how many rows/columns that grid needs -- the same wrap the SetPoint
	-- loop above just laid out.
	--
	-- Scaled, exactly as RenderBarContainer already scales its own height and width. The grid
	-- offsets above are deliberately unscaled because each icon carries its own SetScale and
	-- applies it to them; the CONTAINER carries no scale, so nothing would apply one here. Left
	-- unscaled it measured the grid in unscaled units while the icons drew in scaled ones, and
	-- the only thing that ever renders the container itself -- the Edit Mode highlight -- was the
	-- one thing that showed it: the box stayed put while the icons grew out of it.
	local visibleCount = #slots
	local containerW, containerH
	if visibleCount > 0 then
		local majorCount = math.min(visibleCount, perRow)
		local minorCount = math.ceil(visibleCount / perRow)
		local majorSize = (majorCount * BUFF_ICON_SIZE + (majorCount - 1) * iconPadding) * settings.iconScale
		local minorSize = (minorCount * BUFF_ICON_SIZE + (minorCount - 1) * iconPadding) * settings.iconScale
		if orientation == 0 then
			-- Horizontal layout
			containerW, containerH = math.max(1, majorSize), math.max(1, minorSize)
		else
			-- Vertical layout
			containerW, containerH = math.max(1, minorSize), math.max(1, majorSize)
		end
	else
		-- An empty icon container keeps one icon of size so it stays clickable in Edit
		-- Mode. An example-icon placeholder, the icon equivalent of the bar path's
		-- example slot, is explicitly deferred by 35-CONTEXT.md.
		local empty = BUFF_ICON_SIZE * settings.iconScale
		containerW, containerH = empty, empty
	end
	container:SetSize(containerW, containerH)

	-- Phase 63 review WR-02: the click stamps are container-relative, and the container re-centres
	-- on its own anchor when it grows or shrinks, so a size change moves every icon on screen with
	-- no stamp changing. Two number compares per tick; the cache always follows the size, and only a
	-- container that carries stamps asks for a re-place.
	if container._clickW ~= containerW or container._clickH ~= containerH then
		container._clickW, container._clickH = containerW, containerH
		if clickStampedIn[def.key] then
			ns:MarkReminderClicksDirty()
		end
	end
end

-- One render pass over every container, from ns:UpdateDisplay (under xpcall, see there).
local function RenderContainers(now)
	for _, def in ipairs(ns.CONTAINERS) do
		local container = ns.containers and ns.containers[def.key]
		local settings = cachedSettings[def.key]
		if not container or not settings then
			-- No frame or no settings snapshot: hide whatever this container last
			-- rendered and move on, so one unconfigured container cannot stop the rest.
			-- Deletion unregisters the def before releasing its pool (Core.lua), so a nil
			-- pool here is defence in depth rather than the expected case.
			-- STEAL-15: nothing is attached for this container, so its merged frames go back to the
			-- parked viewer in the flush.
			local pool = pools[def.key]
			if pool then
				for i = 1, #pool do
					pool[i]:Hide()
				end
				ClearContainerClickStamps(def.key, pool)
			end
			if container then
				container:Hide()
			end
		elseif def.kind == "bar" then
			RenderBarContainer(def, container, settings, timersByContainer[def.key], now)
		else
			RenderIconContainer(def, container, settings, timersByContainer[def.key], now)
		end
	end
end

-- Hands a render error to the game's error handler (BugSack etc.) at the point of the raise, so
-- the report keeps the original stack -- the same report an uncaught raise produced before.
local function ReportRenderError(err)
	return geterrorhandler()(err)
end

function ns:UpdateDisplay()
	local timers = ns:GetActiveTimers()
	local now = GetTime()

	-- Merge Mode: this render's attaches rebuild the cooldownID -> cell map whole (STEAL-13).
	ns:BeginMergedPlacement()

	-- Phase 38 (CD-04): once per tick, before the container loop -- not once per container.
	-- On an unchanged ns.trackerGeneration this is a single integer compare and a return.
	RefreshCooldownSlotCounts()

	-- Group timers by container. The per-key lists are built once at load and only
	-- wiped here. A section naming no registered container falls back to the bar
	-- container, reproducing the pre-Phase-35 "buffs to icons, everything else to
	-- bars" split for any stale or missing section value.
	for _, def in ipairs(ns.CONTAINERS) do
		wipe(timersByContainer[def.key])
	end
	for _, timer in ipairs(timers) do
		table.insert(timersByContainer[timer.section] or timersByContainer.bars, timer)
	end

	-- Phase 68 review IN-04: the container loop runs under xpcall so a raise in any render function
	-- still reaches the Merge Mode flush below -- otherwise a repeating raise would leave Blizzard's
	-- frames unplaced, and unreleased after Merge Mode off. The error behaviour is unchanged: the
	-- handler reports the error with its original stack, and the containers after the failing one
	-- are skipped exactly as before. No closure: the function and its handler are file-locals.
	xpcall(RenderContainers, ReportRenderError, now)

	-- Merge Mode: moves Blizzard's CDM frames onto the cells this render just laid out. After the
	-- loop, so every cell is placed and styled first; a single boolean test when nothing changed.
	ns:FlushMergedPlacement()
end
