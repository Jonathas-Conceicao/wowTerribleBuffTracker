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
-- matching corner. THE one place that arithmetic lives: TBT's own pooled icons and the engine
-- aura slots MergeMode hands to Blizzard have to land on the same grid, and every time the two
-- were derived separately they drifted apart -- first by padding, then by scale, then by origin.
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
-- A merged aura the engine owns is the one case TBT does not draw itself, so its answer comes
-- from the CDM's own item frames instead -- ns:RefreshMergeShownSlots stamps entry.cdmShown from
-- them. That flag is Blizzard's own "is this up", already computed, and readable as a plain
-- boolean; TBT must not re-derive it from the aura APIs, and cannot ask the engine, whose frames
-- refuse tainted reads while auras are secret.
local function SlotDraws(entry, timer, settings, iconEditing, engineDrawsHere)
	if engineDrawsHere and entry.isMerged then
		return entry.cdmShown == true
	end
	-- Phase 47: an item tracker produces no ns.activeTimers entry either, for exactly the same
	-- reason a cooldown tracker does not, so it must draw on the same terms. Currently
	-- unreachable for one: the centred layout this function gates is derived from
	-- ns:GetContainerCategory(def) == "buffs", and an item tracker always lives in a spells
	-- container. The widening is defensive, one token, and correct on its own terms rather than
	-- load-bearing today.
	return timer ~= nil
		or (entry.trackerType == "cooldown" or entry.trackerType == "item")
		or entry.isMerged
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
	end
	pools[key] = nil
	timersByContainer[key] = nil
	cachedSettings[key] = nil
	ns.containerTooltipsShown[key] = nil
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

function ns:ShowBuffTooltip(frame, proc, opts)
	GameTooltip_SetDefaultAnchor(GameTooltip, frame)
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

	-- Phase 41 (RACE-02): stack count, copied field-for-field from Blizzard's own
	-- CooldownViewerBuffBarItemTemplate `Applications` FontString
	-- (Blizzard_CooldownViewer/CooldownViewer.xml, the bar's Icon sub-frame). Parented to
	-- bar.iconFrame, not bar.statusBar, so it draws over the icon exactly as Blizzard's does,
	-- and created after bar.iconOverlay so it layers on top of it (both OVERLAY). Uses
	-- NumberFontNormalSmall, not the buff icon's NumberFontNormal (see frame.chargeCount's
	-- comment above CreateTimerIcon) -- TBT's bar icon is 30x30, matching Blizzard's small face.
	bar.stacks = bar.iconFrame:CreateFontString(nil, "OVERLAY")
	bar.stacks:SetFontObject(NumberFontNormalSmall)
	bar.stacks:SetSize(32, 10)
	bar.stacks:SetJustifyH("RIGHT")
	bar.stacks:SetPoint("BOTTOMRIGHT", -5, 5)
	bar.stacks:Hide() -- a freshly pooled bar has no stack answer yet

	-- Phase 48.1 (DISP-02): the bar's dispel-type border. On a bar Blizzard draws this around the
	-- ICON, not around the bar -- CooldownViewerBuffBarItemTemplate anchors its DebuffBorder to
	-- $parent.Icon at the same -3/+3 inset the icon template uses (CooldownViewer.xml:246-251), so
	-- the two faces match and only the frame level differs.
	--
	-- Parented to `bar` and level-bumped, mirroring Blizzard's own numbers: its DebuffBorder is
	-- frameLevel 520 against Icon 512 and Bar 511, i.e. above both. TBT's equivalents are
	-- iconFrame at +2 and statusBar at +1, so +3 is the matching slot. Explicit rather than
	-- creation-order-dependent, unlike the icon path above, because here it has to clear two
	-- siblings rather than one parent's layers -- the same class of defect as S13 at the bar
	-- border below, where omitting a bump rendered a border behind the fill.
	bar.dispelBorder = CreateFrame("Frame", nil, bar)
	bar.dispelBorder:SetFrameLevel(bar:GetFrameLevel() + 3)
	bar.dispelBorder:SetPoint("TOPLEFT", bar.iconFrame, "TOPLEFT", -3, 3)
	bar.dispelBorder:SetPoint("BOTTOMRIGHT", bar.iconFrame, "BOTTOMRIGHT", 3, -3)
	bar.dispelBorder.Texture = bar.dispelBorder:CreateTexture(nil, "ARTWORK")
	bar.dispelBorder.Texture:SetAllPoints()
	bar.dispelBorder:Hide()

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

	-- Phase 48.1 (DISP-01): the dispel-type border, built field-for-field from Blizzard's
	-- CooldownViewerItemDebuffBorderTemplate and its use inside CooldownViewerBuffIconItemTemplate
	-- (Blizzard_CooldownViewer/CooldownViewer.xml:12-19, :189-193). A Frame holding one ARTWORK
	-- texture, anchored to the ICON rather than the frame, inset -3/+3 on both corners.
	--
	-- A child Frame, not a bare texture on `frame`, and created immediately after the Cooldown for
	-- the same load-bearing reason frame.chargeCount documents below: a same-level child created
	-- after the Cooldown draws above the swipe, while an OVERLAY texture parented straight to the
	-- icon would sit under it. Blizzard's own <Frames> order is Cooldown, DebuffBorder,
	-- Applications, so this sits between the two -- the charge count stays on top, as it is there.
	--
	-- Hidden on creation: a freshly pooled icon has no dispel answer yet, and a merged entry that
	-- never carries a harmful aura must never flash one.
	frame.dispelBorder = CreateFrame("Frame", nil, frame)
	frame.dispelBorder:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -3, 3)
	frame.dispelBorder:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 3, -3)
	frame.dispelBorder.Texture = frame.dispelBorder:CreateTexture(nil, "ARTWORK")
	frame.dispelBorder.Texture:SetAllPoints()
	frame.dispelBorder:Hide()

	-- Phase 38 (CD-03): charge count, copied field-for-field from Blizzard's own source in
	-- Blizzard_CooldownViewer/CooldownViewer.xml. Both CooldownViewerBuffIconItemTemplate
	-- (its `Applications` frame) and CooldownViewerEssentialItemTemplate (its `ChargeCount`
	-- frame) use the identical construction: a setAllPoints child *Frame* holding one
	-- OVERLAY FontString inheriting NumberFontNormal anchored BOTTOMRIGHT (-2, 2).
	-- Three details are load-bearing, not taste:
	--   * the child Frame is created AFTER the Cooldown, in the same <Frames> block, so it
	--     draws above the swipe -- an OVERLAY font string parented straight to the icon
	--     would sit under it;
	--   * NumberFontNormal, not the 30x30 CooldownViewerUtilityItemTemplate's
	--     NumberFontNormalSmall -- TBT's icon is 40x40, the BuffIcon size, so NumberFontNormal
	--     is the matching pair;
	--   * hidden on creation, because a freshly pooled icon has no charge answer yet and the
	--     sticky chargeCapable cache only populates once a readable value arrives.
	-- Phase 40 will put a merged CDM Essential cooldown beside a TBT one in the same
	-- container, where any difference in font, size or position would show.
	frame.chargeCount = CreateFrame("Frame", nil, frame)
	frame.chargeCount:SetAllPoints()
	frame.chargeCount.Current = frame.chargeCount:CreateFontString(nil, "OVERLAY")
	frame.chargeCount.Current:SetFontObject(NumberFontNormal)
	frame.chargeCount.Current:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.chargeCount:Hide()

	-- Phase 40: the countdown for a MERGED buff icon, and nothing else -- every TBT-owned icon
	-- draws its numbers through the Cooldown widget above, which does it for free once
	-- SetCooldown has been called. A merged buff icon can never have SetCooldown called on it
	-- (see RelayMergedIconTime), so it needs somewhere of its own to put the relayed text.
	-- Parented to the icon frame and NOT to chargeCount, even though chargeCount is where the
	-- other relayed text lives: that frame is hidden whenever there is no charge count to show,
	-- and a hidden parent hides its children, so a countdown parented there would never appear.
	-- An explicit OVERLAY sublevel puts it above iconOverlay; it does not need to clear the
	-- swipe, because a merged buff icon never draws one.
	frame.mergedTime = frame:CreateFontString(nil, "OVERLAY")
	frame.mergedTime:SetDrawLayer("OVERLAY", 7)
	-- NumberFontNormal is only the fallback for the one frame before RelayMergedIconTime has
	-- matched the real font; see MatchMergedTimeFont for why it cannot be the final answer.
	frame.mergedTime:SetFontObject(NumberFontNormal)
	frame.mergedTime:SetPoint("CENTER", 0, 0)
	frame.mergedTime:Hide()

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
-- Pandemic highlight FX (Phase 48, PAND-01/PAND-02/PAND-05) -- render half only.
-- Every frame below is created by TBT via CreateFrame and parented to a TBT widget. The
-- CDM-owned pool backing Blizzard's own highlight frame is never acquired from, never released
-- to, and Blizzard's own highlight frame is never read, reparented or touched -- this whole
-- section crosses no CDM boundary at all, which is what makes Show/Hide/SetPoint/SetFrameLevel
-- on these frames taint-free (the locked rule is about frames TBT does not own).
---------------------------------------------------------------------

-- Lazy, pcall-guarded creator for TBT's OWN instance of Blizzard's icon pandemic FX template.
-- Parented to icon:GetParent() -- the TBT container -- and NOT to the icon itself. This is
-- load-bearing: RenderIconContainer hides TBT's own pooled icon for a merged Tracked Buff
-- whenever the engine draws that aura (see the engineDrawsHere/entry.isMerged branch's
-- icon:Hide() below), and Tracked Buffs is exactly the pandemic-relevant category -- item-backed
-- entries structurally never carry a pandemic window at all (Blizzard's own IsItem()
-- short-circuit). An FX frame parented to the icon would therefore be invisible in the
-- mainstream case -- the same hidden-parent hazard frame.mergedTime's own comment above already
-- records. Parenting to the container avoids it entirely.
local function EnsurePandemicIconFX(icon)
	if icon.pandemicFX then
		return icon.pandemicFX
	end
	if icon._pandemicFailed then
		return nil
	end

	local parent = icon:GetParent()
	-- No mechanism exists to introspect a virtual template's existence ahead of instantiation
	-- (PANDEMIC.md, "Absence-of-template guard"), so pcall around CreateFrame itself is the only
	-- defensive option -- same shape as pcall(CollectShownCooldownIDs, viewer) in MergeMode.lua.
	-- A failure is stamped once here, never retried every tick (PAND-05, S10).
	local ok, fx = pcall(CreateFrame, "Frame", nil, parent, "CooldownPandemicFXTemplate")
	if not ok or not fx then
		icon._pandemicFailed = true
		return nil
	end

	-- Icon offsets, Blizzard's own default AnchorPandemicStateFrame (CooldownViewer.lua:2129-2133).
	-- Anchored to the icon's own rect, not the container's -- a hidden frame keeps its points and
	-- size, so this resolves whether or not the icon is currently shown, and follows the icon
	-- whenever the layout moves it, with no per-tick repositioning needed.
	fx:ClearAllPoints()
	fx:SetPoint("TOPLEFT", icon, "TOPLEFT", -6, 6)
	fx:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 6, -6)

	-- SyncEntryContainers gives a merged aura container host:GetFrameLevel() + 10
	-- (MergeMode.lua:1410, :1457) -- one level above that keeps this highlight from ever being
	-- covered by an engine aura frame.
	fx:SetFrameLevel(parent:GetFrameLevel() + 11)
	fx:Hide() -- a freshly created FX has no answer yet, exactly like frame.chargeCount / bar.stacks

	icon.pandemicFX = fx
	return fx
end

-- Lazy, pcall-guarded creator for TBT's OWN instance of Blizzard's bar pandemic FX template.
-- Parented to bar itself, unlike the icon's -- bars are never engine-drawn (the aura-group
-- cover-up applies to the Tracked Buffs ICON category only) and RenderBarContainer calls
-- bar:Show() unconditionally for every slot it lays out, so there is no hidden-parent hazard here
-- and parenting straight to the widget matches Blizzard's own shape.
local function EnsurePandemicBarFX(bar)
	if bar.pandemicFX then
		return bar.pandemicFX
	end
	if bar._pandemicFailed then
		return nil
	end

	local ok, fx = pcall(CreateFrame, "Frame", nil, bar, "CooldownPandemicBarFXTemplate")
	if not ok or not fx then
		bar._pandemicFailed = true
		return nil
	end

	-- Bar offsets, Blizzard's own BuffBarCooldownViewerMixin override
	-- (CooldownViewer.lua:2353-2358), anchored to bar.statusBar -- the fill sub-region, TBT's
	-- exact structural equivalent of Blizzard's cooldownItem.Bar (confirmed independently by
	-- RelayMergedBar reading itemFrame.Bar). NOT bar, NOT bar.fillTexture.
	fx:ClearAllPoints()
	fx:SetPoint("TOPLEFT", bar.statusBar, "TOPLEFT", -9, 10)
	fx:SetPoint("BOTTOMRIGHT", bar.statusBar, "BOTTOMRIGHT", 9, -10)

	-- Omitting this bump renders the border behind the bar fill (S13) -- the same defect
	-- Blizzard's own UI would have if its override were skipped (CooldownViewer.lua:2357).
	fx:SetFrameLevel(bar.statusBar:GetFrameLevel() + 1)
	fx:Hide() -- a freshly created FX has no answer yet, exactly like frame.chargeCount / bar.stacks

	bar.pandemicFX = fx
	return fx
end

-- Shared dirty-checked Show/Hide toggle both apply functions below call.
-- AnimateWhileShownTemplate starts and stops its own AnimationGroup purely from the frame's own
-- Show/Hide, with no controller code needed -- this toggle IS the entire animation lifecycle.
-- Never call Play/Stop on the animation group directly.
local function SetPandemicShown(widget, fx, active)
	if widget._pandemicShown == active then
		return
	end
	widget._pandemicShown = active
	if active then
		fx:Show()
	else
		fx:Hide()
	end
end

-- Call-site entry point for icons (Task 2). Safe to call unconditionally for every icon slot on
-- every tick. When active is false and no FX frame has ever been created, this costs exactly one
-- field read -- the common case for every player who never sees a pandemic window.
local function ApplyPandemicIcon(icon, active, settings)
	if not active then
		local fx = icon.pandemicFX
		if not fx then
			return
		end
		SetPandemicShown(icon, fx, false)
		return
	end

	local fx = EnsurePandemicIconFX(icon)
	if not fx then
		return
	end

	-- The icon FX is parented to the container, not the icon, so unlike a true child of the icon
	-- it does not inherit ApplyIconStyle's SetScale/SetAlpha -- match them explicitly here, each
	-- behind its own dirty stamp so an unchanged value costs one comparison.
	if icon._pandemicScale ~= settings.iconScale then
		icon._pandemicScale = settings.iconScale
		fx:SetScale(settings.iconScale)
	end
	if icon._pandemicAlpha ~= settings.alpha then
		icon._pandemicAlpha = settings.alpha
		fx:SetAlpha(settings.alpha)
	end

	SetPandemicShown(icon, fx, true)
end

-- Call-site entry point for bars (Task 2). ApplyPandemicBar needs neither scale nor alpha
-- matching, unlike ApplyPandemicIcon -- the bar FX is a true child of bar and inherits both
-- already.
local function ApplyPandemicBar(bar, active)
	if not active then
		local fx = bar.pandemicFX
		if not fx then
			return
		end
		SetPandemicShown(bar, fx, false)
		return
	end

	local fx = EnsurePandemicBarFX(bar)
	if not fx then
		return
	end

	SetPandemicShown(bar, fx, true)
end

-- Phase 48.1 (DISP-01/DISP-02/DISP-03) -- render half. One call site per widget kind, shared by
-- icons and bars because both carry an identically-built `dispelBorder`; the only thing that
-- differed between them was construction, and that is done by the time this runs.
--
-- `atlas` is entry.dispelAtlas straight off MergeMode's mirror, and it decides nothing: `shown`
-- does. TBT never interprets the atlas -- it does not know or care which of the six dispel types
-- it names -- so a client that adds a seventh works here with no change.
--
-- Dirty-checked on the widget exactly as SetPandemicShown is, and for the same reason: this runs
-- per widget per render pass at 20 Hz, and the overwhelmingly common answer is nil-to-nil, which
-- must cost one field compare and no widget call at all.
--
-- SetAtlas's second argument is useAtlasSize, passed false to match Blizzard's own
-- TextureKitConstants.IgnoreAtlasSize at AuraUtil.lua:612 -- the texture is SetAllPoints to a
-- frame that is already the right size, so letting the atlas resize it would undo the -3/+3 inset.
-- The literal rather than the constant keeps this off a SharedXML global that Forever need not
-- have.
-- Sentinel standing in for "this pass's atlas is secret". A fresh table, so it can never collide
-- with a real atlas name however Blizzard renames its assets.
local SECRET_ATLAS_KEY = {}

-- `shown` decides visibility and is always a plain boolean; `atlas` is RELAYED, never read, and
-- in combat it is a secret string (measured retail 2026-09-24 -- see ReadDispelBorder for the log
-- line and for why SetAtlas may be handed one).
--
-- The two are separate parameters rather than one nil-able atlas because a secret value cannot
-- safely stand in for its own presence: `atlas ~= nil` and `atlas == widget._dispelAtlas` both
-- feed a secret into a conditional, and the earlier version of this function did exactly that.
-- That is what made the in-combat case fail closed even once the value was being relayed.
--
-- Phase 50 (SC3/D-04/D-05): a FOURTH parameter, `identity`, closes the trade the paragraph above
-- describes: while the atlas is secret, `key == SECRET_ATLAS_KEY` used to force a re-set on every
-- single pass, forever, for as long as combat lasted. `identity` is a second, NON-SECRET stamp --
-- the entry's `cooldownID` -- that answers "is this the same entry as last pass?" without ever
-- touching the atlas. `cooldownID` is provably plain: MergeMode.lua:341 builds
-- `entry.key = "cdm:" .. cooldownID`, a concatenation, which raises on a secret value, so any
-- entry that exists in that list already has a non-secret cooldownID. `issecretvalue(id)` still
-- runs first, before any comparison, because a caller could in principle hand this function
-- something else later -- belt and suspenders, not because cooldownID is expected to trip it.
--
-- ACCEPTED TRADE: while the atlas stays secret AND the identity is unchanged, a dispel type that
-- somehow changed for that same cooldownID would not be re-issued until the identity changes or
-- becomes unreadable. Accepted because a dispel type is a static property of the aura a
-- cooldownID names -- it does not change out from under a live entry.
local function ApplyDispelBorder(widget, atlas, shown, identity)
	local border = widget.dispelBorder
	if not border then
		return
	end

	if not shown then
		-- Dirty-checked on the plain boolean, so the overwhelmingly common no-border case still
		-- costs one field compare and no widget call -- what the original dirty check bought,
		-- kept, without ever touching the atlas.
		if widget._dispelShown then
			widget._dispelShown = false
			widget._dispelKey = nil
			widget._dispelID = nil
			border:Hide()
		end
		return
	end

	-- issecretvalue() BEFORE any comparison -- the standing project rule -- so a secret identity
	-- never reaches a `~=`, never reaches the widget, and falls back to the always-set behaviour
	-- below rather than being trusted to prove a skip safe.
	local id = identity
	if issecretvalue(id) then
		id = nil
	end

	-- The cache key is NEVER the secret itself: comparing a secret to a stored value is the trap
	-- described above, and storing one would spread it to the next pass. A secret collapses to one
	-- sentinel, which compares unequal to every real atlas name and equal to itself.
	local key = issecretvalue(atlas) and SECRET_ATLAS_KEY or atlas
	-- Re-issue SetAtlas when: the plain key changed (unchanged from before), OR the identity
	-- changed (a pooled widget now shows a DIFFERENT entry -- the hazard D-05 names, and the
	-- reason this cannot key on the atlas alone), OR there is no readable identity this pass (the
	-- skip cannot be proven safe, so the old always-set behaviour is kept). This replaces the old
	-- `or key == SECRET_ATLAS_KEY` clause, which WAS the always-re-set behaviour this task removes.
	if widget._dispelKey ~= key or widget._dispelID ~= id or id == nil then
		widget._dispelKey = key
		widget._dispelID = id
		border.Texture:SetAtlas(atlas, false)
	end

	if not widget._dispelShown then
		widget._dispelShown = true
		border:Show()
	end
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
	for _, entry in pairs(tracked) do
		-- Phase 47: a container holding only tracked items must stay visible too, for the
		-- identical reason a cooldown-only container does -- neither produces a
		-- ns.activeTimers entry, so #timers alone can never see them.
		if (entry.trackerType == "cooldown" or entry.trackerType == "item") and entry.section then
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
-- Phase 41: the stack number goes with them too, because a recycled cooldown slot never had a
-- chance to overwrite it -- see the timer branch's own stack stamp.
--
-- CALLERS KEEP THEIR `if icon._cdKey then` GUARD; it is deliberately not folded in here. That
-- test is the steady-path cost -- one nil test per icon per frame, and nothing else -- and
-- moving it inside would make the steady path a function call instead.
--
-- icon._mergedExpiry is deliberately absent. The timer branch clears it unconditionally a few
-- lines further down, alongside icon.mergedTime:Hide(); the placeholder branch has to clear it
-- inside the guard, because its entry.isMerged sub-branch owns that stamp. Folding the
-- difference in here would either wipe a live merged sweep stamp or leave a stale one.
local function ClearCooldownStamps(icon)
	icon._cdKey = nil
	icon._userCdState = nil
	icon._userCdGrey = nil
	icon._cdGen = nil
	icon.chargeCount:Hide()
	icon.cooldown:Clear()
	icon._stacks = nil
	-- Phase 43.1: the aura-over-cooldown stamps go with the rest, for the same reason the two
	-- user-duration ones do -- a widget that comes BACK to a merged cooldown whose buff is still
	-- up would otherwise find _cdAuraOwned already true and never re-issue the SetCooldown the
	-- branch it landed in has since cleared. Distinct from icon._mergedExpiry on purpose: that
	-- stamp belongs to the merged BUFF path and the two must not alias through the shared pool.
	icon._cdAuraOwned = nil
	icon._cdAuraExpiry = nil
end

-- Grey while the spell is on a real cooldown, full colour otherwise.
--
-- Split out of ApplyCooldownHandle in Phase 43.1 so the aura branch can reach it too: a spell
-- whose aura lands on the TARGET keeps its cooldown grey even while the aura drives the sweep,
-- and that is Blizzard's rule, not a simplification -- CheckCacheCooldownValuesFromAura resets
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
	-- Not entry.duration directly: a cast whose circumstances earned a different cooldown --
	-- Shadowmeld used in combat -- left a one-cast override beside its start time, and
	-- ns:CooldownDuration is the single place the two are reconciled. Still a plain number either
	-- way, so everything this function says below about comparing numbers holds unchanged.
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

-- A merged cooldown that is currently applying a buff shows the BUFF's remaining time rather
-- than its own cooldown, and is not greyed while it does.
--
-- This is Blizzard's CheckCacheCooldownValuesFromAura (CooldownViewer.lua:861-906). That pass
-- runs AFTER the spell-cooldown pass and overwrites the start, the duration and the
-- desaturation it cached -- "if the spell results in a self buff, give those values precedence
-- over the spell's cooldown until the buff is gone", in Blizzard's own words at :863. The one
-- exception is an entry flagged HideAura (CanUseAuraForDisplay, CooldownViewerItemData.lua
-- :747-754), and that is already filtered out upstream: ns:RefreshMergeShownSlots does not
-- resolve a timing for such an entry, so expiry is simply absent here.
--
-- Nothing secret is touched. entry.auraExpiry and entry.auraDuration are plain numbers
-- ResolveMergedAuraTiming wrote from an aura it had already proved readable, so the arithmetic
-- below is on TBT's own values. Where auras ARE restricted they never arrive, this returns
-- false, and the icon keeps the cooldown-only behaviour it had before -- a graceful loss of the
-- extra information, not a failure.
--
-- Evaluated every tick rather than on a cooldown-generation change, for the same reason
-- ApplyUserCooldown is: an aura expiring does not move ns.cooldownGeneration, so a gated check
-- would leave the buff's sweep on screen until something unrelated happened to move it.
local function ApplyMergedAuraCooldown(icon, entry, now)
	-- One owner per cell. When the engine is drawing merged auras it overlays this icon with the
	-- real thing, and this icon's job underneath is the COOLDOWN -- so a previously resolved
	-- expiry, which the shown-slots pass has stopped refreshing, must not be allowed to suppress
	-- the cooldown handle on the strength of a value nobody is maintaining any more.
	if ns.mergeAuraGroupsActive then
		if icon._cdAuraOwned then
			icon._cdAuraOwned = nil
			icon._cdAuraExpiry = nil
			icon._cdGen = nil
		end
		return false
	end

	local expiry, duration = entry.auraExpiry, entry.auraDuration
	local active = type(expiry) == "number" and type(duration) == "number" and duration > 0 and expiry > now

	if not active then
		-- Hand the icon back to the handle path, and make sure it actually takes it: the block
		-- that calls ApplyCooldownHandle only runs on a generation change, and a buff dropping is
		-- not one. Clearing the generation stamp is what forces the next tick through it.
		if icon._cdAuraOwned then
			icon._cdAuraOwned = nil
			icon._cdAuraExpiry = nil
			icon._cdGen = nil
		end
		return false
	end

	if not icon._cdAuraOwned or icon._cdAuraExpiry ~= expiry then
		icon._cdAuraOwned = true
		icon._cdAuraExpiry = expiry
		icon.cooldown:SetCooldown(expiry - duration, duration)
	end

	-- The grey is NOT simply cleared here, and that is Blizzard's rule rather than caution.
	-- CheckCacheCooldownValuesFromAura resets cooldownDesaturated only `if not
	-- self:IsActivelyCast() or self:GetAuraDataUnit() == "player"` (CooldownViewer.lua:899-901).
	-- An aura on the PLAYER means the icon is showing something that is up, so it goes full
	-- colour. An aura on the TARGET -- a debuff the player cast, like Touch of the Magi -- leaves
	-- the grey to the spell's own cooldown, so the icon reads "debuff has this long left, and the
	-- spell is still recharging" at once, which is what the CDM shows there.
	--
	-- Reasserted every tick rather than stamped with the sweep above: the aura can be
	-- re-resolved onto a different unit without its expiry changing, and the desaturation relay
	-- has its own icon._desat stamp to keep it from writing twice.
	if entry.auraOnTarget then
		ApplyCooldownGrey(icon, entry.spellID)
	elseif icon._desat ~= false then
		icon._desat = false
		icon.icon:SetDesaturated(false)
	end

	return true
end

-- The sweep for an equipped item -- a trinket -- which has no spell to hand a duration handle
-- for. Blizzard's CheckCacheCooldownValuesFromEquippedItem does the same read
-- (CooldownViewer.lua:1016-1046) and runs last, only when no spell source claimed the icon,
-- which is the position this occupies below.
--
-- The one place in the cooldown path that reads NUMBERS out of the game rather than relaying a
-- handle, because there is no item equivalent of GetSpellCooldownDuration: C_Item.GetItemCooldown
-- is SecretArguments = "AllowedWhenUntainted" and so closed to TBT entirely, and the legacy
-- global returns plain values with no duration object to borrow. So every value is screened with
-- issecretvalue before it is compared, and a screened-out read leaves the icon with no sweep
-- rather than taking the render down. Under cooldown restriction that is what will happen, and a
-- trinket icon with no timer is the graceful loss here.
-- What the equipped-item read actually returned, recorded for "/tbt merge". Stamped at the point
-- of the read rather than re-read by the diagnostic, so the printed numbers are exactly the ones
-- that drove the widget -- a second read a moment later would be a different question.
ns.itemCooldownSeen = {}

local function StampItemCooldown(equipSlot, startTime, duration, enable)
	local seen = ns.itemCooldownSeen[equipSlot]
	if not seen then
		seen = {}
		ns.itemCooldownSeen[equipSlot] = seen
	end
	-- Only ever plain numbers or the "unreadable" marker; a secret is never stored.
	seen.startTime, seen.duration, seen.enable = startTime, duration, enable
	seen.at = GetTime()
end

local function ApplyItemCooldown(icon, equipSlot)
	-- Returns whether it could ANSWER, not whether a cooldown is running. A clean read saying
	-- "not on cooldown" is an answer and the caller should stop; a read it could not make is not,
	-- and the caller should try the spell handle next.
	if not GetInventoryItemCooldown then
		return false
	end

	local ok, startTime, duration, enable = pcall(GetInventoryItemCooldown, "player", equipSlot)
	if
		not ok
		or issecretvalue(startTime)
		or type(startTime) ~= "number"
		or issecretvalue(duration)
		or type(duration) ~= "number"
	then
		-- LEAVE whatever is on the widget rather than clearing it. An unreadable read is "I do
		-- not know", not "there is no cooldown", and clearing on it wiped a sweep that was
		-- running perfectly well -- the same distinction ApplyChargeCount already makes for an
		-- unreadable charge struct. A sweep set at the last readable moment keeps animating on
		-- its own.
		StampItemCooldown(equipSlot, nil, nil, nil)
		return false
	end

	StampItemCooldown(equipSlot, startTime, duration, (not issecretvalue(enable)) and enable or nil)

	-- enable is Blizzard's third return and they branch on it too (cooldownEnabled, set from it
	-- in CheckCacheCooldownValuesFromEquippedItem). An item whose cooldown is disabled draws
	-- nothing, whatever the start and duration happen to say.
	if issecretvalue(enable) or enable == 0 or enable == false then
		icon.cooldown:Clear()
		ClearIconDesaturation(icon)
		return true
	end

	-- The GREY, which this branch alone was not applying -- the handle path calls
	-- ApplyCooldownGrey and the CDM relay copies the CDM's own desaturation, so a trinket drawn
	-- from the item read was the one slot that stayed full colour while on cooldown.
	--
	-- Blizzard's rule for an equipped item is simpler than the spell one and is computed right
	-- here: CheckCacheCooldownValuesFromEquippedItem sets isOnGCD = false and cooldownIsActive =
	-- endTime > timeNow, so isOnActualCooldown -- which is what desaturation follows -- is just
	-- "the cooldown has not run out". No global-cooldown exception to carve out, because an item
	-- is never merely waiting on the GCD.
	--
	-- Every value here is a plain number that issecretvalue already cleared above, so this is
	-- arithmetic on TBT's own reads rather than a relayed secret. icon._desat is cleared to nil
	-- first because the stamp may only ever hold false (see ClearIconDesaturation).
	if startTime > 0 and duration > 0 then
		icon.cooldown:SetCooldown(startTime, duration)
		icon._desat = nil
		icon.icon:SetDesaturated((startTime + duration) > GetTime())
	else
		icon.cooldown:Clear()
		ClearIconDesaturation(icon)
	end
	return true
end

-- A generic item cooldown -- the CDM's Combat Potion tile -- names no spell in its configuration,
-- and this is how Blizzard finds one anyway: C_Spell.GetLastCategoryCooldownSource(category)
-- returns the most recent spell and item to have started a cooldown in that category, and
-- CooldownViewerItemDataMixin:RefreshSpellCategoryData writes the result back onto its own
-- cooldownInfo.spellID (CooldownViewerItemData.lua:47-57). From there the tile is an ordinary
-- spell cooldown. TBT was clearing the widget instead, which is why the potion showed its buff
-- and then nothing at all.
--
-- Cached per category, because the call is SecretWhenCooldownsRestricted: the spell ID comes back
-- secret in exactly the content where a potion cooldown is most worth seeing. The cache is filled
-- from readable moments and reused otherwise, the same sticky pattern chargeCapable uses, and it
-- is a good fit here -- a player drinks the same potion over and over, so a value learned once is
-- almost always still the right one.
local categorySpellID = {}
ns.categorySpellID = categorySpellID

local function ResolveCategorySpellID(category)
	if type(category) ~= "number" then
		return nil
	end

	if C_Spell.GetLastCategoryCooldownSource then
		local ok, spellID = pcall(C_Spell.GetLastCategoryCooldownSource, category)
		if ok and not issecretvalue(spellID) and type(spellID) == "number" and spellID > 0 then
			categorySpellID[category] = spellID
		end
	end

	return categorySpellID[category]
end

-- ASK THE CDM. Relay the cooldown straight off the item frame that owns this slot, exactly as
-- RelayMergedBar already does for a merged bar's fill and text.
--
-- This is the right shape and it is tried FIRST, before any per-item resolution, because the CDM
-- item frame has already done all of that work: spell, equipped item, spell category, charges,
-- aura preference, every branch of CacheCooldownValues. Whatever it decided to draw is what the
-- player is meant to see, and re-deriving it per entry is how TBT ended up with three separate
-- code paths and a bug in each.
--
-- Whether it WORKS is a question for the game, not for a source dump. GetCooldownTimes is
-- documented SecretReturnsForAspect = { Cooldown } and SetCooldown is SecretArguments =
-- "AllowedWhenUntainted", which reads as "a tainted addon cannot do this" -- but that was also
-- the reading that said a buff tile has no cooldown, and the game disagreed. So this tries it and
-- reports what happened: every value stays inside the pcall, nothing is compared, stamped or
-- stored, and a raise costs one failed call and falls through to the per-item chain below.
--
-- Units: GetCooldownTimes returns MILLISECONDS and SetCooldown takes seconds
-- (Blizzard_UnitFrame/Mainline/RuneFrame.lua:250-251 says so in as many words).
ns.mergeRelayState = {}

local function RelayMergedCooldown(icon, entry)
	local cooldownID = entry.cooldownID
	if not cooldownID then
		return false
	end

	local itemFrame = ns.mergeItemFrames and ns.mergeItemFrames[cooldownID]
	local source = itemFrame and itemFrame.Cooldown
	if not source or not source.GetCooldownTimes then
		ns.mergeRelayState[cooldownID] = "no-frame"
		return false
	end

	-- The whole read and write inside one pcall, deliberately: Lua evaluates arguments before the
	-- call, so splitting them would perform the arithmetic outside the protection.
	local ok = pcall(function()
		local startMs, durationMs = source:GetCooldownTimes()
		icon.cooldown:SetCooldown(startMs / 1000, durationMs / 1000)
	end)

	ns.mergeRelayState[cooldownID] = ok and "ok" or "blocked"
	if not ok then
		return false
	end

	-- ...and the GREY with it, from the same frame, for the same reason: the CDM has already
	-- decided. RefreshIconDesaturation sets it to `cooldownDesaturated and not IsExpired()`
	-- (CooldownViewer.lua:1196-1201), which is every rule about charges, auras, the GCD and
	-- expiry rolled into one boolean TBT does not have to re-derive.
	--
	-- Relayed, never read: IsDesaturated is SecretReturnsForAspect = { Desaturation } and can
	-- come back secret, while SetDesaturated is SecretArguments = "AllowedWhenTainted" and takes
	-- it as-is. The value is never compared, stamped or stored -- the same handling the engine
	-- cooldown handle's IsActive already gets.
	--
	-- Separate pcall from the sweep above. RequiresScriptObjectDesaturationAccess can deny the
	-- read on its own, and losing the grey should not cost the timer that is already relaying
	-- correctly.
	local iconTexture = itemFrame.Icon
	if iconTexture and iconTexture.IsDesaturated then
		-- Cleared to nil first so ClearIconDesaturation cannot later skip its write on the
		-- strength of a stale false this line has since overwritten.
		icon._desat = nil
		pcall(function()
			icon.icon:SetDesaturated(iconTexture:IsDesaturated())
		end)
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
	-- Order is Blizzard's: a typed duration is TBT's own override and outranks everything, then
	-- the aura, then the cooldown handle. CacheCooldownValues runs charges, then cooldown, then
	-- aura, with each later pass overwriting the earlier one -- which is the same precedence read
	-- from the other end (CooldownViewer.lua:1065-1075).
	local auraOwned = not userOwned and ApplyMergedAuraCooldown(icon, entry, now)

	if icon._cdGen ~= ns.cooldownGeneration or icon._cdKey ~= entry.key then
		icon._cdGen = ns.cooldownGeneration
		icon._cdKey = entry.key
		-- Clear the buff-path stamp so a later real or preview timer landing on this pooled
		-- widget re-issues its SetCooldown instead of being skipped as unchanged.
		icon._lastStart = nil
		-- Phase 41: same clear for the stack stamp -- a cooldown slot never has stacks, and a
		-- widget that returns to a stacking tracker later must re-issue its SetText.
		icon._stacks = nil
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
		if entry.trackerType == "item" then
			ApplyItemCount(icon, entry)
		else
			ApplyChargeCount(icon, spellID)
		end

		-- Keep the category -> spell cache warm, UNCONDITIONALLY, and not only when something
		-- needs it. This was a catch-22 that exactly matched the symptom -- a potion cooldown out
		-- of combat and nothing in it.
		--
		-- ResolveCategorySpellID used to be reached only after the CDM relay had failed. Out of
		-- combat the relay SUCCEEDS, so the lookup never ran and the cache stayed empty; in
		-- combat the relay is blocked, the lookup finally runs, and
		-- GetLastCategoryCooldownSource is SecretWhenCooldownsRestricted so it answers with a
		-- secret and the cache is still empty. The one moment it could have been filled was the
		-- one moment nothing asked.
		--
		-- Filling it here costs one call per category entry per generation change and means the
		-- answer is already in hand by the time combat makes it unreadable.
		if entry.spellCategoryID then
			ResolveCategorySpellID(entry.spellCategoryID)
		end
		-- ORDER, and it is evidence rather than preference.
		--
		-- The CDM relay is the better source when it answers: the item frame has already settled
		-- spell, item, category, charges and aura preference, and TBT copies the result. But it
		-- goes SECRET precisely when a cooldown is running -- "/tbt merge" in combat came back
		-- relay=blocked on almost every entry, and relay=ok only on the few that had nothing to
		-- show. A source that works only while there is nothing to draw cannot be the primary.
		--
		-- C_Spell.GetSpellCooldownDuration has no secrecy flag at all and hands back a duration
		-- object rather than a value, so it works in combat and out of it. Where an entry HAS a
		-- spell, that is the reliable answer and it goes first.
		--
		-- The relay keeps the job nothing else can do: an entry with no spellID -- a trinket by
		-- equipment slot, a potion by category -- where the CDM has resolved something TBT would
		-- otherwise have to re-derive.
		if not userOwned and not auraOwned then
			-- An EQUIPPED ITEM goes first, even when the entry also names a spell. The cooldown
			-- of a trinket lives on the item; the spell the CDM names is the effect it applies
			-- and has no cooldown of its own. Blizzard reaches the same place from the other
			-- direction -- CheckCacheCooldownValuesFromSpellCooldown finds nothing to claim, so
			-- CheckCacheCooldownValuesFromEquippedItem gets it -- but that test reads values TBT
			-- cannot, so TBT decides by the shape of the entry instead.
			if entry.equipSlot and ApplyItemCooldown(icon, entry.equipSlot) then
				if entry.cooldownID then
					ns.mergeRelayState[entry.cooldownID] = "item"
				end
			elseif spellID then
				-- chargeCapable ALONE, deliberately. It is set from maxCharges > 1 on a real
				-- C_Spell.GetSpellCharges struct, which is the same thing Blizzard's charge
				-- branch decides on, so it means what it says.
				--
				-- entry.hasCharges -- the CDM's own info.charges flag -- is NOT consulted here
				-- and was the cause of the Touch of the Magi regression: it is true for entries
				-- that have a charge DISPLAY rather than charges, and swapping in a recharge
				-- handle for a spell that never recharges leaves the icon with no sweep at all.
				-- The field is still mirrored, because it is the honest answer to "does the CDM
				-- show charges here" and nothing else needs to re-derive it.
				--
				-- The cost of the stricter gate is that a charge spell first seen inside
				-- restricted content, where GetSpellCharges is secret, shows no recharge until a
				-- readable moment arrives. That is the same sticky-cache limitation the charge
				-- COUNT already has, and it fails by omitting information rather than by
				-- replacing a working sweep with a blank one.
				ApplyCooldownHandle(icon, spellID, chargeCapable[spellID] == true)
				if entry.cooldownID then
					ns.mergeRelayState[entry.cooldownID] = "handle"
				end
			elseif RelayMergedCooldown(icon, entry) then
				-- Drawn by the CDM's own values, grey included.
			else
				-- A generic item cooldown. Resolved to whichever spell last started a cooldown in
				-- its category, which is what Blizzard's own tile does, and then driven by the
				-- ordinary duration handle. hasCharges is false: a potion has none, and asking
				-- would only risk the inactive-handle trap that cost Touch of the Magi its sweep.
				local categorySpell = ResolveCategorySpellID(entry.spellCategoryID)
				if categorySpell then
					ApplyCooldownHandle(icon, categorySpell, false)
				else
					-- This is the "nothing owns a sweep here" terminus, and it was the one arm of
					-- the chain that cleared the cooldown without also clearing the grey. Every
					-- other arm settles its own desaturation -- ApplyItemCooldown clears it,
					-- ApplyCooldownHandle goes through ApplyCooldownGrey, the CDM relay copies
					-- the CDM's own -- so a pooled widget arriving here simply kept whatever the
					-- last entry to use it had left behind.
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
end

-- Blizzard's own bar colour (CooldownViewer.xml, the BuffBar item's BarTexture). A merged bar
-- cannot be coloured by remaining fraction the way a TBT-owned one is -- that needs arithmetic
-- on a secret -- so it takes the CDM's flat colour instead, which is what the player was
-- looking at before Merge Mode moved it.
local MERGED_BAR_COLOR_R, MERGED_BAR_COLOR_G, MERGED_BAR_COLOR_B = 1.0, 0.5, 0.25

-- Drive a merged bar from the CDM item frame that owns it. NOTHING READ HERE IS EVER LOOKED AT:
-- every value goes straight from a Blizzard getter into the matching TBT setter, with no
-- comparison, arithmetic, concatenation or branch on any of them. That is the only reason this
-- works at all -- under restriction GetMinMaxValues, GetValue and GetText all return SECRET
-- values (SecretReturnsForAspect BarValue / Text), while SetMinMaxValues, SetValue and
-- FontString:SetText are all SecretArguments = "AllowedWhenTainted" and take them as-is.
--
-- This is why a merged bar could not have a timer until now, and it is worth recording what
-- does NOT work, so nobody re-derives it. TBT cannot compute the fill itself: that means
-- reading the aura APIs, which are secret. It cannot take a duration handle either --
-- Blizzard's BuffBar item drives its bar with SetMinMaxValues/SetValue rather than
-- SetTimerDuration (CooldownViewer.lua:1554-1581), so there is no LuaDurationObject on it to
-- borrow. Relaying the already-computed bar values is what is left, and it is exact.
--
-- The same trick does NOT extend to merged buff ICONS. Every Cooldown getter is
-- SecretReturnsForAspect = { Cooldown } and every Cooldown setter that takes numbers --
-- SetCooldown, SetCooldownDuration, SetCooldownFromExpirationTime -- is
-- SecretArguments = "AllowedWhenUntainted" (FrameAPICooldownDocumentation.lua), so a tainted
-- caller cannot pass the values on. SetCooldownFromDurationObject is the only tainted-safe
-- setter and there is no getter anywhere that returns a duration object for an aura.
--
-- That is a limit on RELAYING a sweep off the CDM's Cooldown, and only on that. It is not a
-- limit on merged buff icons having a sweep at all: they do, by two routes that never read a
-- secret. The engine draws one itself when ns.mergeAuraGroupsActive is true, because the aura
-- path hands Blizzard a Cooldown through SetDurationCooldown and the engine binds the real
-- duration object to it. And TBT issues one from plain numbers whenever MergeMode's
-- ResolveMergedAuraTiming could read the aura -- see the SetCooldown branch in
-- RenderIconContainer, which is where that is written down.
--
-- Per-tick by necessity: Blizzard animates its own bar from OnUpdate, so a relay on a slower
-- cadence would stutter. The cost is one hash lookup and six widget calls per merged bar, and
-- ns.mergeItemFrames is rebuilt event-driven rather than walked here.
local function RelayMergedBar(bar, slot)
	local cooldownID = slot.cooldownID
	local itemFrame = cooldownID and ns.mergeItemFrames and ns.mergeItemFrames[cooldownID]
	local source = itemFrame and itemFrame.Bar
	if not source or not source.GetMinMaxValues or not source.GetValue then
		return false
	end

	local minValue, maxValue = source:GetMinMaxValues()
	bar.statusBar:SetMinMaxValues(minValue, maxValue)
	bar.statusBar:SetValue(source:GetValue())

	-- Cleared so a real TBT timer landing on this pooled widget later re-issues its own
	-- SetMinMaxValues instead of being skipped as unchanged. The relay cannot use that stamp
	-- itself: comparing against a secret is exactly what threw in Display.lua:615.
	bar._lastDuration = nil

	if bar._mergedColor ~= true then
		bar._mergedColor = true
		bar.fillTexture:SetVertexColor(MERGED_BAR_COLOR_R, MERGED_BAR_COLOR_G, MERGED_BAR_COLOR_B)
	end

	local duration = source.Duration
	if duration and duration.GetText then
		bar.time:SetText(duration:GetText())
	else
		bar.time:SetText("")
	end

	bar.pip:Show()
	return true
end

-- The merged-buff-ICON counterpart of RelayMergedBar, and a deliberately smaller promise: it
-- relays the countdown TEXT only, and not the spiral with it.
--
-- Smaller, but it is the FALLBACK rather than the ceiling. A merged buff icon does get a real
-- sweep when the aura's timing is readable: MergeMode's ResolveMergedAuraTiming writes
-- entry.auraExpiry / entry.auraDuration and the SetCooldown branch in RenderIconContainer issues
-- it from those plain numbers, and when ns:RefreshMergeAuraGroups has the engine path running
-- the engine draws the spiral itself off a duration object TBT never sees. This runs when
-- neither is available, which is what restricted content gives: a number and no spiral, rather
-- than nothing at all.
--
-- What is impossible is RELAYING a sweep off the CDM's own Cooldown the way the bar values are
-- relayed, and this is where that is recorded so it does not get retried.

-- A Cooldown widget can only be driven by numbers or by a duration object. Every numeric setter
-- -- SetCooldown, SetCooldownDuration, SetCooldownFromExpirationTime -- is
-- SecretArguments = "AllowedWhenUntainted", so a tainted caller cannot pass on the values it
-- reads off the CDM's Cooldown, which are themselves secret (every getter there is
-- SecretReturnsForAspect = { Cooldown }). SetCooldownFromDurationObject is the one
-- tainted-safe setter, and nothing in the API hands out a duration object for an AURA:
-- C_UnitAuras.GetAuraDuration does, but it takes an auraInstanceID, which Blizzard keeps in a
-- CreateSecureAuraInstanceMap (CooldownViewer.lua:1659). Merged ESSENTIAL and UTILITY icons are
-- unaffected -- they are cooldowns, and ApplyCooldownSlot gets a real duration object for those
-- straight from C_Spell.GetSpellCooldownDuration.
--
-- What IS available is the text Blizzard has already rendered into its own countdown
-- FontString, which Cooldown:GetCountdownFontString hands back. FontString:GetText returns a
-- secret under restriction and FontString:SetText is SecretArguments = "AllowedWhenTainted", so
-- the string goes straight across with nothing done to it -- the same relay rule as everywhere
-- else in this file.
-- Make the relayed countdown look like every other TBT buff icon's countdown.
--
-- It was shipped on NumberFontNormal, which is wrong and visibly so -- that is the small
-- bottom-corner font TBT uses for charge and stack counts, not the large centred one a cooldown
-- draws its numbers in. Reported in play-testing on 2026-09-22 as "different number font or size
-- or something".
--
-- The font is COPIED from the source rather than named, and that is what makes it correct
-- rather than a guess that happens to match today. TBT's own buff icons draw their numbers
-- through the Cooldown widget and never call SetCountdownFont, so they use the client's default
-- cooldown countdown font. Blizzard's BuffIcon item template does not set cooldownFont either
-- -- only the Essential and Utility templates do, to GameFontHighlightHugeOutline and
-- GameFontHighlightOutline (CooldownViewer.xml:23, :92) -- so its countdown FontString is
-- drawing in that same default. Copying from it therefore lands on exactly the font TBT's own
-- icons use, at the same 40x40 icon size, with no hardcoded name to drift when Blizzard changes
-- the default.
--
-- Reading TBT's own countdown FontString instead would be the more direct thing to do and does
-- not work: a container holding only merged buff slots never has SetCooldown called on any of
-- its widgets, so icon.cooldown never creates a countdown FontString to copy from.
--
-- Stamped per widget -- the font cannot change under us, and this must not run every frame.
-- GetFont carries no secrecy flag (SimpleFontStringAPIDocumentation.lua:121-131) but its
-- results are type-guarded anyway, per the addon-wide rule; an unreadable font leaves the
-- fallback in place rather than raising inside the render loop.
local function MatchMergedTimeFont(icon, fontString)
	if icon._mergedFont or not fontString.GetFont then
		return
	end

	local path, height, flags = fontString:GetFont()
	if issecretvalue(path) or type(path) ~= "string" or issecretvalue(height) or type(height) ~= "number" then
		return
	end

	icon._mergedFont = true
	icon.mergedTime:SetFont(path, height, flags)
end

local function RelayMergedIconTime(icon, entry, settings)
	if not settings.timerShown then
		return false
	end

	local cooldownID = entry.cooldownID
	local itemFrame = cooldownID and ns.mergeItemFrames and ns.mergeItemFrames[cooldownID]
	local source = itemFrame and itemFrame.Cooldown
	if not source or not source.GetCountdownFontString then
		return false
	end

	local fontString = source:GetCountdownFontString()
	if not fontString or not fontString.GetText then
		return false
	end

	MatchMergedTimeFont(icon, fontString)
	icon.mergedTime:SetText(fontString:GetText())
	icon.mergedTime:Show()
	return true
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
	-- Phase 40 (STEAL-03): a container holding only mirrored CDM bars must still be visible
	-- under hideWhenInactive.
	local hasActiveTimers = #timers > 0 or mergedCount > 0
	local barEditing = ns.editModeActive
	local visible = ShouldShow(settings.visibleSetting, hasActiveTimers, settings.hideWhenInactive, barEditing)

	if not visible then
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
			-- D-4: an account-wide database plus a per-character race means an orc can be
			-- holding a troll's racial -- the race gate below applies here, not only in
			-- Suggested, or it would still draw in whatever container it was left in.
			if
				entry.section == def.key
				and entry.trackerType ~= "cooldown"
				and entry.trackerType ~= "item"
				and ns:IsRacialKeyVisible(dbKey)
			then
				entry.key = dbKey -- stable slot identity (string for meta, numeric for user)
				table.insert(slots, entry)
			end
		end
		table.sort(slots, ByLayoutOrder)
	else
		for _, t in ipairs(timers) do
			table.insert(slots, t) -- procs already have .key from provider
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

		-- Phase 48 (PAND-02, S14): one unconditional call per slot, ahead of the
		-- timer/merged/placeholder chain below, so a pooled bar reused by a plain TBT timer
		-- clears the previous slot's highlight the same way bar._stacks / bar._lastDuration
		-- already are. Gated inline on slot.isMerged (D-05) so a native TBT tracker can never
		-- light up. Uses the render pass's own `now` parameter; adds no clock read of its own.
		ApplyPandemicBar(bar, slot.isMerged and ns:IsMergedEntryInPandemic(slot, now))

		-- Phase 48.1 (DISP-02): same placement and same gate as the pandemic call above -- one
		-- unconditional call per slot, ahead of the branch chain, so a pooled bar reused by a
		-- plain TBT timer clears the previous slot's border. `and nil` rather than `and false`:
		-- ApplyDispelBorder's dirty check compares against the stored value, and nil is the
		-- no-border state everywhere else in this path, so a native tracker must resolve to nil
		-- and not to a second falsy spelling that would defeat the compare on alternate passes.
		-- Phase 50 (SC3): fourth argument is the non-secret identity (cooldownID) that lets the
		-- dirty check tell "same entry, unchanged" from "pooled widget, different entry" without
		-- ever inspecting the atlas.
		ApplyDispelBorder(bar, slot.dispelAtlas, slot.isMerged and slot.dispelShown == true, slot.cooldownID)

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
			-- This resolves the icon and label only. The bar's fill and countdown come from
			-- RelayMergedBar in the block below, which drives them straight off the CDM item
			-- frame that owns this slot.
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
				-- the mirror slot. Wiping and reusing bar.proc itself would wipe a live timer, which
				-- RacialProviderMixin is still mutating (proc.stacks).
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
			-- 49-04/D-6: an indefinite proc (Shadowmeld, Find Treasure) has no natural end --
			-- expiresAt/duration carry only the 86400s backstop (ns.INDEFINITE_DURATION), so
			-- drawing a countdown from them would show a lie. Draw it as simply on instead: a
			-- full bar, no fill animation, no number.
			if timer.indefinite then
				-- -1 sentinel: neither nil (the placeholder branch's own sentinel below) nor any
				-- real duration, so a bar alternating between placeholder and indefinite never
				-- skips its SetMinMaxValues.
				if bar._lastDuration ~= -1 then
					bar._lastDuration = -1
					bar.statusBar:SetMinMaxValues(0, 1)
				end
				bar.statusBar:SetValue(1)
				bar._mergedColor = nil
				bar.fillTexture:SetVertexColor(GetBarColor(1))

				bar.pip:Show()

				bar.time:SetText("")
			else
				local remaining = timer.expiresAt - now
				local fraction = remaining / timer.duration

				if bar._lastDuration ~= timer.duration then
					bar._lastDuration = timer.duration
					bar.statusBar:SetMinMaxValues(0, timer.duration)
				end
				bar.statusBar:SetValue(remaining)
				local r, g, b = GetBarColor(fraction)
				bar._mergedColor = nil
				bar.fillTexture:SetVertexColor(r, g, b)

				bar.pip:Show()

				bar.time:SetText(FormatTime(remaining))
			end

			-- Phase 41 (RACE-02): the bar-side analogue of the icon stack stamp above, driving
			-- bar.stacks (Blizzard's CooldownViewerBuffBarItemTemplate `Applications`
			-- FontString, see CreateTimerBar's comment). timer.stacks is TBT's own cast-derived
			-- integer, never a game value, so this needs no issecretvalue, no
			-- ns:CanReadTable and no pcall.
			if bar._stacks ~= timer.stacks then
				bar._stacks = timer.stacks
				if timer.stacks ~= nil then
					bar.stacks:SetText(timer.stacks)
					bar.stacks:Show()
				else
					bar.stacks:Hide()
				end
			end
		elseif slot.isMerged and RelayMergedBar(bar, slot) then
			-- Driven entirely by RelayMergedBar. A merged bar carries no stack count of its own
			-- -- Blizzard draws applications on its item frame's own Applications FontString,
			-- which is not mirrored -- so the stale-stack clear below applies here too.
			if bar._stacks ~= nil then
				bar._stacks = nil
				bar.stacks:Hide()
			end
		else
			-- Placeholder: empty bar, no fill, no timer
			if bar._lastDuration ~= nil then
				bar._lastDuration = nil
				bar.statusBar:SetMinMaxValues(0, 1)
			end
			bar.statusBar:SetValue(0)
			bar.pip:Hide()
			bar.time:SetText("")

			-- Phase 41: a placeholder bar never keeps a stale stack number.
			if bar._stacks ~= nil then
				bar._stacks = nil
				bar.stacks:Hide()
			end
		end

		bar:Show()
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
		-- Phase 48 code review WR-01: hiding the bar hides its FX child VISUALLY, but
		-- AnimateWhileShownTemplate starts and stops its AnimationGroup from the FX frame's OWN
		-- Show/Hide, not an ancestor's -- so a trailing bar that once showed a highlight would
		-- keep that animation looping, invisible, until the pooled frame was reused. Cheap
		-- (ApplyPandemicBar returns immediately when the frame has no FX yet), and it makes this
		-- loop symmetric with the icon path's own clear.
		ApplyPandemicBar(pool[i], false)
		-- Phase 48.1: this one IS covered by pool[i]:Hide(), since the border is a true child of
		-- the bar and carries no animation to keep running. Cleared anyway, so the pooled widget's
		-- _dispelShown and _dispelKey match what it is actually showing -- otherwise a bar hidden
		-- while bordered and later reused for an unbordered slot would dirty-check its way out of
		-- the Hide it needs.
		ApplyDispelBorder(pool[i], nil, false)
	end
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
	-- Phase 40: a container the engine is drawing merged auras into counts as active regardless
	-- of what TBT itself has in it. Those aura frames are children of this container, so hiding
	-- it hides them -- and TBT cannot ask how many are visible, because reading an engine aura
	-- frame is denied while auras are secret. That is what emptied the Tracked Buffs container
	-- when the aura groups first shipped: TBT stopped publishing merged slots to Display (the
	-- engine owns them now), mergedCount fell to zero, hideWhenInactive hid the container, and
	-- the engine frames went with it. An empty container draws nothing, so leaving it shown is
	-- free.
	local engineDrawsHere = ns.mergeAuraGroupsActive
		and def.cdmCategoryName == "TrackedBuff"
		and ns.db.mergeMode == true
	local hasActiveIcons = #timers > 0 or (cooldownSlotCounts[def.key] or 0) > 0 or mergedCount > 0 or engineDrawsHere
	local iconEditing = ns.editModeActive
	local iconVisible = ShouldShow(settings.visibleSetting, hasActiveIcons, settings.hideWhenInactive, iconEditing)

	if not iconVisible then
		container:Hide()
		return
	end

	container:Show()

	wipe(slots)
	for dbKey, entry in pairs(ns.db.trackedBuffs) do
		-- D-4: an account-wide database plus a per-character race means an orc can be holding
		-- a troll's racial -- the race gate below applies here, not only in Suggested, or it
		-- would still draw in whatever container it was left in.
		if entry.section == def.key and ns:IsRacialKeyVisible(dbKey) then
			entry.key = dbKey -- stable slot identity
			table.insert(slots, entry)
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

	-- Centred is a buff-container setting. Re-derived here rather than trusted from the database,
	-- so a value left behind by a container that changed category cannot produce a layout its
	-- dropdown never offered.
	local centered = direction == ns.GROWTH_CENTERED and ns:GetContainerCategory(def) == "buffs"

	-- The run is centred against the container's own width in cells, so this is the reserved
	-- count -- not the drawn one. See CenteredSlotPlacement.
	local capacity = math.min(#slots, perRow)
	local drawnCount = 0
	if centered then
		for i = 1, #slots do
			local entry = slots[i]
			if SlotDraws(entry, activeByKey[entry.key], settings, iconEditing, engineDrawsHere) then
				drawnCount = drawnCount + 1
			end
		end
	end
	local drawnIndex = 0

	for slotIndex, entry in ipairs(slots) do
		local icon = GetIcon(def.key, slotIndex)
		local timer = activeByKey[entry.key]

		local anchor, offsetMajor, offsetMinor
		if centered then
			-- A slot that draws nothing takes no cell at all, which is what makes the run close
			-- up and re-centre. Placed before the branch chain so the chain itself is untouched.
			if SlotDraws(entry, timer, settings, iconEditing, engineDrawsHere) then
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

		-- Phase 48 (PAND-01, S14): resolved once, before the branch chain below, so it is
		-- correct across all four of that chain's outcomes at once -- engine-drawn merged buff,
		-- item-backed merged buff, merged placeholder, and a live TBT timer landing on the same
		-- pooled widget. Because the FX is container-parented, a slot that stops being merged
		-- must still reach this call with false, which it does unconditionally per slot -- a
		-- non-merged entry always resolves to false (D-05), no second branch needed. Uses the
		-- render pass's own `now` parameter; adds no clock read of its own.
		ApplyPandemicIcon(icon, entry.isMerged and ns:IsMergedEntryInPandemic(entry, now), settings)

		-- Phase 48.1 (DISP-01): resolved here for the same reason the pandemic call above is --
		-- once, before the branch chain, so it is correct across all four of that chain's
		-- outcomes at once. Unlike the pandemic FX this border IS a true child of the pooled
		-- icon, so an engine-drawn merged aura that hides the icon hides its border too, which is
		-- correct: the engine's own frame carries Blizzard's border in that case.
		-- Phase 50 (SC3): fourth argument is the non-secret identity (cooldownID) that lets the
		-- dirty check tell "same entry, unchanged" from "pooled widget, different entry" without
		-- ever inspecting the atlas.
		ApplyDispelBorder(icon, entry.dispelAtlas, entry.isMerged and entry.dispelShown == true, entry.cooldownID)

		if engineDrawsHere and entry.isMerged then
			-- PLACED, not drawn. The engine draws this aura and drives its sweep; TBT decides
			-- only where it goes, and hands that cell over here. Its own pooled icon stays hidden
			-- so nothing is drawn twice.
			--
			-- The entry is still walked rather than dropped from the list, because that is what
			-- sizes the container for it. Dropping them is what collapsed the container to the
			-- width of TBT's own trackers once: a container hangs off a corner or an edge (BOTTOM,
			-- by Blizzard default), so a narrower one re-centres on its anchor and takes every
			-- offset measured from it with it.
			if anchor then
				ns:PlaceMergeAura(entry, container, anchor, offsetMajor, offsetMinor, settings.iconScale)
			end

			-- An ITEM-backed tracked buff -- a trinket or a potion -- keeps its own icon
			-- underneath, showing the item's cooldown, and lets the engine's aura frame cover it
			-- while the buff is up. Exactly the overlay the cooldown containers use.
			--
			-- This was left out because CooldownViewerBuffIconItemMixin:RefreshCooldownInfo
			-- drives its sweep purely from GetCooldownValues -- aura, totem or edit-mode timing
			-- and nothing else -- so a buff tile looked like it could not show a cooldown at all.
			-- The live game says otherwise, reported 2026-09-22, and the game is the authority:
			-- the local wow-ui-source dump is 12.1.0 build 69273 from 2026-08-11 and the client
			-- has moved since. Read it for intent, never for proof of absence.
			--
			-- Scoped to item-backed entries on purpose. An ordinary tracked buff is a pure aura
			-- and must still go quiet when it drops; only a trinket or a potion has a second
			-- thing to say.
			if entry.equipSlot or entry.spellCategoryID then
				ApplyCooldownSlot(icon, entry, settings, now)
				icon.mergedTime:Hide()
				icon._mergedExpiry = nil
				icon:Show()
			else
				icon:Hide()
			end
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
			-- A TBT-owned timer draws its own numbers through the Cooldown widget, so a pooled
			-- widget that last drew a merged slot must drop the relayed text and its sweep stamp.
			icon.mergedTime:Hide()
			icon._mergedExpiry = nil
			ApplyIconStyle(icon, settings)

			-- 49-04/D-6: an indefinite proc (Shadowmeld, Find Treasure) has no natural end, so a
			-- radial sweep drawn from its 86400s backstop duration would show a lie. SetCooldown(0,
			-- 0) is the clear-the-sweep idiom, present on both flavours -- Cooldown:Clear() buys
			-- nothing here and is one more symbol to be confident about. The -1 sentinel is neither
			-- nil nor any real startedAt, keeping the write out of the per-frame path once applied.
			if timer.indefinite then
				if icon._lastStart ~= -1 then
					icon._lastStart = -1
					icon.cooldown:SetCooldown(0, 0)
				end
			elseif icon._lastStart ~= timer.startedAt then
				icon._lastStart = timer.startedAt
				icon.cooldown:SetCooldown(timer.startedAt, timer.duration)
			end

			-- Phase 41 (RACE-02): reuses Phase 38's icon.chargeCount widget rather than a
			-- second one -- see CreateTimerIcon's comment for why it already sits where
			-- Blizzard puts an Applications count. timer.stacks is TBT's own cast-derived
			-- integer (RacialProviderMixin decrements it on a qualifying cast), never a game
			-- value, so unlike ApplyChargeCount above this needs no issecretvalue, no
			-- ns:CanReadTable and no pcall.
			if icon._stacks ~= timer.stacks then
				icon._stacks = timer.stacks
				if timer.stacks ~= nil then
					icon.chargeCount.Current:SetText(timer.stacks)
					icon.chargeCount:Show()
				else
					icon.chargeCount:Hide()
				end
			end

			icon:Show()
		elseif entry.trackerType == "cooldown" or entry.trackerType == "item" then
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
			-- entry.isMerged is always false for an item entry, so the merge-aura call below
			-- is already a no-op for it and needs no guard.
			ApplyCooldownSlot(icon, entry, settings, now)
			icon.mergedTime:Hide()
			icon._mergedExpiry = nil
			icon:Show()

			-- Phase 43.1: OVERLAY, not replace. Unlike the Tracked Buffs branch above, the icon
			-- stays shown and keeps drawing the spell's cooldown; the engine's aura frame is
			-- placed on the same cell, above it, and covers it for exactly as long as the aura is
			-- up. Between them that is Blizzard's "show the buff's time, then the cooldown"
			-- without TBT reading either value -- which matters because reading is what does not
			-- work: mid-combat on retail every merged slot resolves its aura to nothing.
			--
			-- Same size as the icon (both 40), so the cover is exact. An entry whose spell has no
			-- aura never gets a frame and the cooldown simply shows through.
			if entry.isMerged and anchor then
				ns:PlaceMergeAura(entry, container, anchor, offsetMajor, offsetMinor, settings.iconScale)
			end
		elseif entry.isMerged or not settings.hideWhenInactive or ns.configOpen or iconEditing then
			-- Phase 38: same pooled-widget reset as the timer branch above -- see
			-- ClearCooldownStamps.
			if icon._cdKey then
				ClearCooldownStamps(icon)
				-- Cleared with the widget it stamps, or a merged slot landing on this pooled icon
				-- would think its sweep was still set and never re-issue it. Out of the helper
				-- because the timer branch clears this stamp unconditionally instead.
				icon._mergedExpiry = nil
			end

			-- Placeholder: resolve icon via ns:GetDisplayInfoForKey, unless this is a Phase 40
			-- mirrored slot, whose entry (built by MergeMode.lua's mirror refresh) is already
			-- the tooltip payload -- it carries spellID and label directly, same trick
			-- ApplyCooldownSlot already uses ("The DB entry itself is the tooltip payload").
			-- Per-item shown state IS mirrored now -- a slot that reaches this loop is one the
			-- CDM currently has on screen, filtered in ns:RefreshMergeShownSlots. There is
			-- still no countdown: that value lives on the same item frames but is not mirrored,
			-- because nothing consumes it yet.
			local resolvedSpellID
			if entry.isMerged then
				icon.proc = entry
				resolvedSpellID = entry.spellID

				-- A real sweep whenever MergeMode could read the aura's timing (see
				-- ResolveMergedAuraTiming). These are plain numbers by the time they reach here --
				-- that function refuses to store anything else -- so this is the ordinary
				-- SetCooldown path, stamped on the expiry so a re-render does not restart the
				-- animation every frame.
				--
				-- When the sweep is up the Cooldown widget draws its own numbers, so the relayed
				-- text is hidden to avoid printing the countdown twice. The relay stays as the
				-- fallback for when the aura is unreadable, which is what restricted content
				-- gives: a number and no spiral, rather than nothing at all.
				if entry.auraExpiry and entry.auraDuration then
					if icon._mergedExpiry ~= entry.auraExpiry then
						icon._mergedExpiry = entry.auraExpiry
						icon.cooldown:SetCooldown(entry.auraExpiry - entry.auraDuration, entry.auraDuration)
					end
					icon.mergedTime:Hide()
				else
					if icon._mergedExpiry ~= nil then
						icon._mergedExpiry = nil
						icon.cooldown:Clear()
					end
					if not RelayMergedIconTime(icon, entry, settings) then
						icon.mergedTime:Hide()
					end
				end
			else
				icon.mergedTime:Hide()
				icon._mergedExpiry = nil
				local info = ns:GetDisplayInfoForKey(entry.key)
				resolvedSpellID = info and info.spellID or nil
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
			end

			ApplyCachedIcon(icon, resolvedSpellID, entry.iconOverride)
			ClearIconDesaturation(icon)
			ApplyIconStyle(icon, settings)

			if icon._lastStart then
				icon._lastStart = nil
				icon.cooldown:Clear()
			end

			-- Phase 41: a slot with no live timer never keeps a stack number. One comparison
			-- per placeholder icon per frame, matching the icon._cdKey guard style above.
			if icon._stacks ~= nil then
				icon._stacks = nil
				icon.chargeCount:Hide()
			end

			icon:Show()
		else
			icon:Hide()
		end
	end

	-- Hide extra icons
	for i = #slots + 1, #pool do
		pool[i]:Hide()
		-- Phase 48: pool[i]:Hide() does NOT hide the pandemic FX -- it hangs off the
		-- container, not the icon (see EnsurePandemicIconFX's comment) -- so without this
		-- explicit clear a shrinking container would leave a highlight floating over an empty
		-- cell. The bar path's FX IS a true child of bar, so it needs no clear to stay out of
		-- sight -- but it carries one anyway (WR-01), because the animation group stops on the
		-- FX frame's own Hide, not an ancestor's.
		ApplyPandemicIcon(pool[i], false, settings)
		-- Phase 48.1: same reasoning as the bar pool's clear -- pool[i]:Hide() already takes the
		-- border off screen with its parent, but the stored _dispelShown has to be cleared with it
		-- or the dirty check will skip the Hide when this widget is reused unbordered.
		ApplyDispelBorder(pool[i], nil, false)
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
	if visibleCount > 0 then
		local majorCount = math.min(visibleCount, perRow)
		local minorCount = math.ceil(visibleCount / perRow)
		local majorSize = (majorCount * BUFF_ICON_SIZE + (majorCount - 1) * iconPadding) * settings.iconScale
		local minorSize = (minorCount * BUFF_ICON_SIZE + (minorCount - 1) * iconPadding) * settings.iconScale
		if orientation == 0 then
			-- Horizontal layout
			container:SetSize(math.max(1, majorSize), math.max(1, minorSize))
		else
			-- Vertical layout
			container:SetSize(math.max(1, minorSize), math.max(1, majorSize))
		end
	else
		-- An empty icon container keeps one icon of size so it stays clickable in Edit
		-- Mode. An example-icon placeholder, the icon equivalent of the bar path's
		-- example slot, is explicitly deferred by 35-CONTEXT.md.
		local empty = BUFF_ICON_SIZE * settings.iconScale
		container:SetSize(empty, empty)
	end
end

function ns:UpdateDisplay()
	local timers = ns:GetActiveTimers()
	local now = GetTime()

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

	for _, def in ipairs(ns.CONTAINERS) do
		local container = ns.containers and ns.containers[def.key]
		local settings = cachedSettings[def.key]
		if not container or not settings then
			-- No frame or no settings snapshot: hide whatever this container last
			-- rendered and move on, so one unconfigured container cannot stop the rest.
			-- Deletion unregisters the def before releasing its pool (Core.lua), so a nil
			-- pool here is defence in depth rather than the expected case.
			local pool = pools[def.key]
			if pool then
				for i = 1, #pool do
					pool[i]:Hide()
				end
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
