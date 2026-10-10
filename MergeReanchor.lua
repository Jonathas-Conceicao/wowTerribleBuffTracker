local _, ns = ...

-- Merge Mode's placement engine. Blizzard's own CDM item frames are MOVED onto TBT's slots instead
-- of being redrawn. Active whenever Merge Mode is on (ns.db.mergeMode == true).
--
-- TBT still mirrors the CDM and lays every slot out exactly as before -- order, direction,
-- Centered, padding, interleaving with the player's own trackers. Only the drawing changes: a
-- merged slot's pooled TBT icon (or bar) is styled and placed but kept hidden, and Blizzard's
-- item frame for that cooldownID is anchored onto it, scaled to its on-screen size and styled by
-- the container's settings. So TBT decides where, how big and how it looks; Blizzard draws inside.
--
-- What is touched on a CDM frame, and nothing else:
--   viewer.itemFramePool:EnumerateActive()   -- already admitted in MergeMode.lua
--   FIELD READS: itemFrame.cooldownID, the child regions (Icon, Cooldown, Applications -- read only
--     to tell a buff icon from a cooldown icon -- Bar, Bar.Name, Bar.Duration) and the viewer's
--     settings fields (iconScale, timerShown, tooltipsShown, barContent, baseBarWidth,
--     barWidthScale)
--   C getters: GetParent, GetHeight, GetWidth, GetEffectiveScale, GetPoint, and IsShown on the
--     bar's Name/Duration strings
--   C setters on the item frame: ClearAllPoints, SetPoint, SetScale, SetWidth (bars), SetAlpha,
--     SetIgnoreParentAlpha, SetMouseClickEnabled, SetMouseMotionEnabled
--   C setters on its child regions: SetHideCountdownNumbers, SetDrawSwipe, SetShown, the Bar's
--     LEFT SetPoint, and SetText on the bar's Name/Duration strings when TBT reveals them
--   hooksecurefunc(viewer, "Layout", ...)    -- one post-hook per viewer
--
-- Never: SetParent, a field write on a Blizzard frame, a Blizzard mixin method call, or
-- SetLayoutData. These taint permanently.
--
-- One hook on the VIEWER's Layout rather than one SetPoint hook per icon: in Blizzard's source the
-- item frames are only ever positioned (and re-scaled and re-styled, via RefreshLayout) on the way
-- into that Layout, so four viewer hooks see every placement. Running after Layout also means the
-- viewer still sizes itself from Blizzard's own positions.

local hookedViewers = {}

-- cooldownID -> the TBT cell (a hidden pooled icon or bar) its CDM frame sits on, the reverse
-- map so a reused cell evicts the id it held before, the kind ("icon" | "bar") per id, the
-- container's cached settings table per id and the merged entry's own label per id (the text a
-- bar's revealed name is filled with). It also holds the CDM viewer frame of the container that
-- attached each id: the only viewer whose item frame may sit on that id's cell. All TBT-owned
-- tables.
local cellByID = {}
local idByCell = {}
local kindByID = {}
local settingsByID = {}
local labelByID = {}
local viewerByID = {}

-- Bumped whenever something that is not part of a frame's identity changes how it must be
-- placed or styled (container settings, UI scale, Edit Mode layout). A number bump only.
local placeGeneration = 0

-- Set when the cooldownID -> cell intent or the placement generation changed; cleared by the one
-- placement pass at the end of a render (ns:FlushMergedPlacement). Placement is never routed
-- by a list of shown frames: the flush walks Blizzard's pools directly, so it reaches hidden
-- frames and preview state (Edit Mode, CDM settings window) alike, which is exactly where settings
-- and reorders must reach the moved frames. In the steady state the flag stays clear and the
-- flush is one test.
local placementPending = false

-- The cooldownID -> cell map is rebuilt WHOLE by every render, never patched (STEAL-13): an id
-- not attached this render loses its cell, so it can never keep pointing at a cell it used
-- before -- in its own container or in one it left. Done with a per-id render stamp rather than a
-- wipe, so a render that changes nothing costs one counter comparison and no table walk:
-- attachedCount counts the ids stamped this render, mappedCount the ids holding a cell, and the
-- two differ only when some id was not attached this time.
local renderGen = 0
local attachGen = {}
local attachedCount = 0
local mappedCount = 0

-- item frame -> what it was last placed with. The dirty check; weak so a frame Blizzard drops is
-- not kept alive by it.
local weak = { __mode = "k" }
local placedOn = setmetatable({}, weak)
local placedGen = setmetatable({}, weak)
local placedID = setmetatable({}, weak)
-- item frame -> the cell it could NOT be placed on (a zero or unreadable size), stamped with the
-- same placedGen/placedID, so the dirty check skips it until something actually changes.
local unplaceableOn = setmetatable({}, weak)

-- item frame -> the anchor Blizzard gave it, captured before TBT moves it, so Merge Mode off can
-- put it back exactly there.
local origPoint = setmetatable({}, weak)
local origRel = setmetatable({}, weak)
local origRelPoint = setmetatable({}, weak)
local origX = setmetatable({}, weak)
local origY = setmetatable({}, weak)

-- Every TBT cell, so one is never captured as a Blizzard anchor.
local isCell = setmetatable({}, weak)

-- All of an id's per-id entries go together, so the maps never describe different id sets. The
-- flush's prune walks cellByID and would never reach the others once that entry is gone.
local function ForgetID(id)
	local cell = cellByID[id]
	cellByID[id] = nil
	if cell and idByCell[cell] == id then
		idByCell[cell] = nil
	end
	kindByID[id], settingsByID[id], labelByID[id] = nil, nil, nil
	viewerByID[id] = nil
end

function ns:IsMergeReanchorActive()
	return ns.db ~= nil and ns.db.mergeMode == true
end

function ns:MarkMergedPlacementDirty()
	placeGeneration = placeGeneration + 1
	placementPending = true
end

local dirtyFrame = CreateFrame("Frame")
dirtyFrame:SetScript("OnEvent", function()
	ns:MarkMergedPlacementDirty()
end)
pcall(dirtyFrame.RegisterEvent, dirtyFrame, "UI_SCALE_CHANGED")
pcall(dirtyFrame.RegisterEvent, dirtyFrame, "DISPLAY_SIZE_CHANGED")
pcall(dirtyFrame.RegisterEvent, dirtyFrame, "EDIT_MODE_LAYOUTS_UPDATED")

-- True when a child FontString is currently hidden (its own flag, not its parents'). A secret or
-- unreadable answer counts as shown, so nothing is written over it.
local function RegionHidden(region)
	local shown = region:IsShown()
	return not issecretvalue(shown) and shown == false
end

-- Reproduces the effect of Blizzard's SetBarContent plus the bar SetTimerShown with plain
-- setters. content: 0 icon and name, 1 icon only, 2 name only.
--
-- Blizzard writes the name and duration strings ONLY while they are shown (RefreshName returns
-- early on a hidden name; RefreshCooldownInfo skips a hidden duration), so a string revealed here
-- after Blizzard hid it still holds whatever the pooled frame last showed -- empty, or another
-- spell's. Revealing therefore also fills it, through the plain FontString SetText: the name with
-- `label` (the merged entry's own non-secret label; nil when TBT has none, e.g. on release), the
-- duration with "" (Blizzard's own per-OnUpdate RefreshCooldownInfo refills it while active).
-- Only on the hidden -> shown edge, so a string Blizzard is already maintaining is never
-- overwritten.
local function SetBarRegions(itemFrame, content, durationShown, label)
	local iconFrame = itemFrame.Icon
	local barFrame = itemFrame.Bar
	if not iconFrame or not barFrame then
		return
	end
	local nameText = barFrame.Name
	local durationText = barFrame.Duration
	if content == 2 then
		iconFrame:SetShown(false)
		barFrame:SetPoint("LEFT", iconFrame, "LEFT", 0, 0)
	else
		iconFrame:SetShown(true)
		barFrame:SetPoint("LEFT", iconFrame, "RIGHT", 2, 0)
	end
	if nameText then
		local showName = content ~= 1
		if
			showName
			and not issecretvalue(label)
			and type(label) == "string"
			and label ~= ""
			and RegionHidden(nameText)
		then
			nameText:SetText(label)
		end
		nameText:SetShown(showName)
	end
	if durationText then
		local showDuration = durationShown == true
		if showDuration and RegionHidden(durationText) then
			durationText:SetText("")
		end
		durationText:SetShown(showDuration)
	end
end

-- Container settings and moved frames: what is settled and what remains a known limitation.
--
-- Settled:
--   Hide When Inactive: per-item hiding is Blizzard's SetHideWhenInactive -> UpdateShownState
--     (a mixin, plus item-frame SetShown fighting Blizzard's own per-refresh shown logic). It keeps
--     its existing Merge Mode meaning -- the container-level hide, while the CDM's own per-item
--     shown state decides which merged entries appear, as the mirror has always published them.
--     The mixin is not called and the item frame is not SetShown. A container hidden by Hide When
--     Inactive is covered by the STEAL-15 rule below.
--   Visibility (always / in combat / hidden): RESOLVED, STEAL-15. The whole-map rebuild closes it.
--     A container the render hides attaches nothing that render, so the flush prunes its ids and
--     its pool walk sends their frames back to the parked, off-screen viewer: not SetAlpha(0), so
--     nothing invisible stays hoverable. The next render that shows the container re-attaches
--     them. The reverse direction, the CDM's own Visibility hiding the viewer the frames are
--     children of, cannot be undone inside the boundary; MergeMode.lua tells the player instead
--     (ns:CheckMergeViewerVisibility).
--   Click to Cast: reminders only; a merged entry is never a reminder -- not applicable.
--
-- Known limitations:
--   Bar name revealed on RELEASE (the CDM shows the name, TBT's container had hidden it): TBT has
--     no label for a frame it is handing back, so the name keeps the text it last held until
--     Blizzard's next RefreshName (its next RefreshData). The reverse direction -- TBT revealing a
--     name Blizzard hid -- is filled from the entry's label in SetBarRegions; a released frame
--     whose CDM content hides the name gets it hidden, so TBT's text never stays visible.
--   Show Timer off, swipe on cooldown icons (Essential/Utility): Blizzard re-sets the swipe on
--     every cooldown refresh (CooldownViewerCooldownItemMixin:RefreshSpellCooldownInfo), which is
--     not a Layout. TBT does not hook the item mixin; ns:ReassertMergedSwipe turns it back off
--     after the shown-slot pass, which runs deferred on the same events Blizzard refreshes on. Two
--     known gaps: the frame Blizzard's refresh renders in, before the deferred pass, can show the
--     swipe, and a refresh TBT has no event for (Blizzard's own charge-gain timer) shows it until
--     the next shown-slot pass. Show Timer ON never touches a cooldown icon's swipe: Blizzard
--     turns it off deliberately while a charge spell recharges with charges left, so turning it
--     back on after Show Timer off waits for Blizzard's next refresh (the next GCD at the latest).
--
-- Applies every container setting that reaches an item frame through a plain C setter. Scale, bar
-- width, position and padding/layout are NOT applied here: PlaceItem owns them (scale and width
-- from the cell, position and padding from TBT's grid).
local function ApplyMergedStyle(itemFrame, settings, kind, label)
	if not settings then
		return
	end
	-- Ignoring the parent's alpha makes TBT's opacity exact instead of multiplied by the parked
	-- viewer's CDM opacity: the CDM's own settings must not leak into TBT (STEAL-16 for opacity).
	itemFrame:SetIgnoreParentAlpha(true)
	itemFrame:SetAlpha(settings.alpha)
	-- Reproduces SetTooltipsShown.
	itemFrame:SetMouseClickEnabled(false)
	itemFrame:SetMouseMotionEnabled(settings.tooltipsShown == true)
	if kind == "bar" then
		local content = settings.barContent or 0
		SetBarRegions(itemFrame, content, settings.timerShown == true and content ~= 1, label)
	else
		local cooldown = itemFrame.Cooldown
		if cooldown then
			cooldown:SetHideCountdownNumbers(not settings.timerShown)
			-- A buff icon (it has Applications) never sets its own swipe, so TBT's value sticks. A
			-- cooldown icon's swipe is Blizzard's: only Show Timer off touches it -- see Known limitations above ApplyMergedStyle.
			if itemFrame.Applications then
				cooldown:SetDrawSwipe(settings.timerShown == true)
			elseif settings.timerShown ~= true then
				cooldown:SetDrawSwipe(false)
			end
		end
	end
end

-- A usable (non-secret, right-typed) viewer field, or the fallback.
local function ViewerNumber(value, fallback)
	if issecretvalue(value) or type(value) ~= "number" then
		return fallback
	end
	return value
end

local function ViewerBool(value, fallback)
	if issecretvalue(value) or type(value) ~= "boolean" then
		return fallback
	end
	return value
end

-- Undoes ApplyMergedStyle and PlaceItem's scale/width by reproducing OnAcquireItemFrame with
-- plain setters, from the viewer's own fields.
local function RestoreBlizzardStyle(itemFrame, viewer)
	local scale = ViewerNumber(viewer.iconScale, 1)
	-- Written as a positive range test so NaN (every comparison false) and infinity fall back too.
	if not (scale > 0 and scale < math.huge) then
		scale = 1
	end
	local timerShown = ViewerBool(viewer.timerShown, true)
	local tooltips = ViewerBool(viewer.tooltipsShown, true)

	itemFrame:SetScale(scale)
	itemFrame:SetIgnoreParentAlpha(false)
	itemFrame:SetAlpha(1)
	itemFrame:SetMouseClickEnabled(false)
	itemFrame:SetMouseMotionEnabled(tooltips)

	if itemFrame.Bar then
		local baseWidth = ViewerNumber(viewer.baseBarWidth, nil)
		local widthScale = ViewerNumber(viewer.barWidthScale, nil)
		if baseWidth and widthScale then
			itemFrame:SetWidth(baseWidth * widthScale)
		end
		local content = 0
		local barContent = viewer.barContent
		local enum = Enum and Enum.CooldownViewerBarContent
		if enum and not issecretvalue(barContent) then
			if barContent == enum.IconOnly then
				content = 1
			elseif barContent == enum.NameOnly then
				content = 2
			end
		end
		SetBarRegions(itemFrame, content, timerShown)
	else
		local cooldown = itemFrame.Cooldown
		if cooldown then
			cooldown:SetHideCountdownNumbers(not timerShown)
			cooldown:SetDrawSwipe(true)
		end
	end
end

-- Stores the anchor Blizzard gave the frame, unless it is unusable or is one of TBT's own cells.
local function CaptureBlizzardAnchor(itemFrame)
	local point, rel, relPoint, x, y = itemFrame:GetPoint(1)
	if
		issecretvalue(point)
		or issecretvalue(rel)
		or issecretvalue(relPoint)
		or issecretvalue(x)
		or issecretvalue(y)
		or not point
		or not rel
		or isCell[rel]
	then
		return
	end
	origPoint[itemFrame], origRel[itemFrame], origRelPoint[itemFrame] = point, rel, relPoint
	origX[itemFrame], origY[itemFrame] = x, y
end

-- Returns a frame to Blizzard's own anchor on its viewer and its own style. No-op for a frame
-- TBT never placed.
--
-- Anchor first: the frame must leave its TBT cell even if restyling raises, because on the
-- eviction path that cell already belongs to another id and two frames must never share one. The
-- captured anchor is re-applied under pcall (it can raise if another addon has since made its
-- relativeTo depend on this frame), with the viewer's corner as the fallback. Style second. The
-- bookkeeping is cleared LAST, so a raise anywhere above leaves the frame still tracked and the
-- next release walk retries it instead of losing it.
--
-- Re-captured first (Phase 69 review WR-02): a frame that is no longer on a TBT cell was
-- re-anchored by Blizzard since TBT placed it -- the Layout post-hook releases a viewer-mismatched
-- frame a moment after Blizzard's Layout put it on its new grid position -- and that fresh anchor
-- outranks the one captured at first placement, often for another cooldownID and layoutIndex.
-- CaptureBlizzardAnchor skips a frame still on a cell, so the older capture stays the fallback.
local function ReleaseItem(itemFrame)
	if not placedOn[itemFrame] then
		return
	end
	CaptureBlizzardAnchor(itemFrame)
	local viewer = itemFrame:GetParent()
	itemFrame:ClearAllPoints()
	local point = origPoint[itemFrame]
	local restored = false
	if point then
		local rel, relPoint, x, y = origRel[itemFrame], origRelPoint[itemFrame], origX[itemFrame], origY[itemFrame]
		restored = pcall(itemFrame.SetPoint, itemFrame, point, rel, relPoint, x, y)
	end
	if not restored then
		itemFrame:SetPoint("TOPLEFT", viewer, "TOPLEFT", 0, 0)
	end
	RestoreBlizzardStyle(itemFrame, viewer)
	origPoint[itemFrame], origRel[itemFrame], origRelPoint[itemFrame] = nil, nil, nil
	origX[itemFrame], origY[itemFrame] = nil, nil
	placedOn[itemFrame], placedGen[itemFrame], placedID[itemFrame] = nil, nil, nil
end

-- Puts one item frame on its cell and styles it, or returns it to Blizzard when it has none.
local function PlaceItem(itemFrame, force)
	local id = itemFrame.cooldownID
	local parent = itemFrame:GetParent()
	local cell
	if ns:IsMergeReanchorActive() and not issecretvalue(id) and type(id) == "number" then
		cell = cellByID[id]
		-- A frame may only sit on a cell its own viewer's container attached (STEAL-13). On a
		-- buff-to-bar move Blizzard re-lays out the destination viewer, and the Layout hook force-places
		-- its new frame before TBT has rendered the new lists; the old map then points that id at its
		-- old icon cell, with kind "icon", so the frame went CENTER on the wrong container with no bar
		-- width. A mismatch counts as no cell and the frame goes back to its parked viewer.
		if cell and parent ~= viewerByID[id] then
			cell = nil
		end
	end

	if not cell then
		unplaceableOn[itemFrame] = nil
		ReleaseItem(itemFrame)
		return
	end

	if
		not force
		and (placedOn[itemFrame] == cell or unplaceableOn[itemFrame] == cell)
		and placedGen[itemFrame] == placeGeneration
		and placedID[itemFrame] == id
	then
		return
	end

	-- Scaled so its on-screen height equals the cell's: effective scale is the viewer's times
	-- the frame's own, and Blizzard's frames are not the cell's size (Essential 50, Utility 30).
	local viewer = parent
	local height = itemFrame:GetHeight()
	local viewerScale = viewer:GetEffectiveScale()
	local cellHeight = cell:GetHeight()
	if
		issecretvalue(height)
		or issecretvalue(viewerScale)
		or issecretvalue(cellHeight)
		or not height
		or height <= 0
		or not viewerScale
		or viewerScale <= 0
		or not cellHeight
		or cellHeight <= 0
	then
		-- No usable size: the frame must not stay on a cell that may now belong to another id, and
		-- the stamp keeps every later pass from re-reading these sizes until something changes.
		ReleaseItem(itemFrame)
		unplaceableOn[itemFrame], placedGen[itemFrame], placedID[itemFrame] = cell, placeGeneration, id
		return
	end
	local scale = cell:GetEffectiveScale() * cellHeight / (viewerScale * height)

	-- A bar (anchored by its LEFT edge) also takes the cell's width: Blizzard sizes it from the
	-- CDM's own bar width setting, TBT's row from the container's. With the height matched by the
	-- scale, the width in the frame's own units is the cell's width times the same ratio.
	local kind = kindByID[id]
	local point = kind == "bar" and "LEFT" or "CENTER"

	if force or not placedOn[itemFrame] then
		CaptureBlizzardAnchor(itemFrame)
	end

	-- Tracked BEFORE the first setter, with no generation, so a raise partway through still leaves
	-- the frame known to the release walk and due for a retry; the full stamp is set at the end.
	placedOn[itemFrame], placedGen[itemFrame], placedID[itemFrame] = cell, nil, nil
	unplaceableOn[itemFrame] = nil

	itemFrame:SetScale(scale)
	if kind == "bar" then
		itemFrame:SetWidth(cell:GetWidth() * height / cellHeight)
	end
	itemFrame:ClearAllPoints()
	itemFrame:SetPoint(point, cell, point, 0, 0)

	ApplyMergedStyle(itemFrame, settingsByID[id], kind, labelByID[id])

	placedOn[itemFrame], placedGen[itemFrame], placedID[itemFrame] = cell, placeGeneration, id
end

local function PlaceViewer(viewer, force)
	local pool = viewer.itemFramePool
	if not pool or not pool.EnumerateActive then
		return
	end
	for itemFrame in pool:EnumerateActive() do
		pcall(PlaceItem, itemFrame, force)
	end
end

function ns:PlaceAllMergedItems(force)
	if not ns:IsMergeReanchorActive() then
		wipe(cellByID)
		wipe(idByCell)
		wipe(kindByID)
		wipe(settingsByID)
		wipe(labelByID)
		wipe(viewerByID)
		wipe(attachGen)
		wipe(unplaceableOn)
		mappedCount = 0
		-- Walks every frame TBT ever placed, not just the active ones: Blizzard may have released
		-- some to its pool, and those would otherwise keep TBT's alpha and scale forever. One pcall
		-- per frame, so one frame that raises cannot leave every frame after it on a TBT cell.
		for itemFrame in pairs(placedOn) do
			pcall(ReleaseItem, itemFrame)
		end
		return
	end
	for viewer in pairs(hookedViewers) do
		PlaceViewer(viewer, force)
	end
end

-- Called by Display for every merged slot it lays out, every render pass. `cell` is the hidden,
-- already-placed pooled widget for that slot; `settings` is the container's cached settings table;
-- `kind` is "icon" or "bar"; `viewer` is the container's CDM viewer (Display's ns.cdmViewers, or
-- the viewer global), the only viewer whose item frame may be placed on this cell.
--
-- Records the intent only -- no game call, no allocation. The frames are moved once, after the
-- whole render has laid every cell out, by ns:FlushMergedPlacement.
function ns:AttachMergedItem(entry, cell, settings, kind, viewer)
	local id = entry.cooldownID
	if not id then
		return
	end

	-- One id published by two lists in the same render, for example around a category move, keeps
	-- the first cell it got this render. Without this its cell flips on every render and every
	-- render re-places.
	if attachGen[id] == renderGen and cellByID[id] ~= cell then
		return
	end

	if attachGen[id] ~= renderGen then
		attachGen[id] = renderGen
		attachedCount = attachedCount + 1
	end

	if cellByID[id] ~= cell then
		local oldCell = cellByID[id]
		if oldCell then
			if idByCell[oldCell] == id then
				idByCell[oldCell] = nil
			end
		else
			mappedCount = mappedCount + 1
		end
		-- The cell held a different entry last pass: that entry loses it, or two CDM frames
		-- would sit on one cell. Its frame is sent back by the flush's pool walk, shown or not.
		local previous = idByCell[cell]
		if previous and previous ~= id then
			ForgetID(previous)
			mappedCount = mappedCount - 1
		end
		cellByID[id] = cell
		idByCell[cell] = id
		placementPending = true
	end
	isCell[cell] = true
	if kindByID[id] ~= kind or settingsByID[id] ~= settings or viewerByID[id] ~= viewer then
		kindByID[id], settingsByID[id], viewerByID[id] = kind, settings, viewer
		placementPending = true
	end
	-- Recorded only: the label is read when a placement reveals a bar's name, so a changed label
	-- alone does not ask for a re-place (a string reference, no allocation).
	labelByID[id] = entry.label
end

-- For `/tbt merge` only: reads TBT's own tables, no game call.
function ns:GetMergedPlacementKind(cooldownID)
	if cellByID[cooldownID] then
		return kindByID[cooldownID]
	end
	return nil
end

-- Turns the swipe back off on every placed cooldown icon whose container has Show Timer off,
-- after Blizzard's per-refresh SetDrawSwipe (see Known limitations above ApplyMergedStyle). Called from
-- the end of the shown-slot pass, which is event-driven and deferred past Blizzard's handlers --
-- never from a render. Walks TBT's own table; a game call only for a frame that needs it.
function ns:ReassertMergedSwipe()
	for itemFrame in pairs(placedOn) do
		local id = placedID[itemFrame]
		local settings = id and settingsByID[id]
		if settings and settings.timerShown ~= true and kindByID[id] == "icon" and not itemFrame.Applications then
			local cooldown = itemFrame.Cooldown
			if cooldown then
				cooldown:SetDrawSwipe(false)
			end
		end
	end
end

-- Called once at the start of ns:UpdateDisplay: opens a new render's attach set.
function ns:BeginMergedPlacement()
	renderGen = renderGen + 1
	attachedCount = 0
end

-- Called once at the end of ns:UpdateDisplay, after every cell of the render is laid out. One
-- comparison and one boolean test when nothing changed; otherwise one pool walk, where the
-- per-frame stamps keep every unchanged frame to a few table reads.
function ns:FlushMergedPlacement()
	-- Some id held a cell last render and was not attached in this one (its entry stopped being
	-- published, moved container, or its container is hidden): it loses the cell, and the pool
	-- walk below sends its frame back to its viewer whether Blizzard shows it or not.
	-- STEAL-15: every TBT hide path lands here, because each returns before ns:AttachMergedItem:
	-- Visibility Hidden; Visibility In Combat, out of combat; Hide When Inactive; a container with no
	-- frame or settings snapshot; a deleted container; a render that raised partway (68 IN-04).
	if mappedCount ~= attachedCount then
		mappedCount = 0
		for id, cell in pairs(cellByID) do
			if attachGen[id] ~= renderGen then
				ForgetID(id)
			else
				mappedCount = mappedCount + 1
			end
		end
		placementPending = true
	end

	if not placementPending then
		return
	end
	placementPending = false
	ns:PlaceAllMergedItems(false)
end

-- Installs the Layout hooks (once Merge Mode is on) and, unless `skipPlace`, force-places every
-- frame. The Merge-on mirror rebuild passes skipPlace (Phase 69 review WR-03): its map is the
-- previous configuration's, and the render the rebuild queues places from the new lists. With
-- Merge Mode off the call releases every moved frame, so that path never skips.
function ns:ReanchorMergeViewers(skipPlace)
	if ns:IsMergeReanchorActive() then
		for _, def in ipairs(ns.CONTAINERS) do
			local viewer = def.cdmViewerGlobal and _G[def.cdmViewerGlobal]
			if viewer and not hookedViewers[viewer] and viewer.Layout then
				hookedViewers[viewer] = true
				hooksecurefunc(viewer, "Layout", function()
					if not ns:IsMergeReanchorActive() then
						return
					end
					PlaceViewer(viewer, true)
					-- Blizzard's Layout has just put every shown frame of this viewer back on its own
					-- grid, so this one viewer is re-placed at once, through the previous render's map:
					-- the only placement that map still makes after a configuration change. The viewer
					-- check in PlaceItem keeps it off another container's cell; a same-viewer reorder can
					-- sit on its id's old cell until the render below moves it.
					-- While previewing, a Blizzard re-layout also rebuilds the mirror (queued,
					-- single-flight). The rebuild places nothing itself; the shown-slot pass it queues
					-- renders from the new lists, and that render's flush places (MergeMode.lua,
					-- mirrorChangedForPlacement). Outside previewing, aura churn re-lays the buff viewer
					-- too often for a full category walk each time, and the usual events cover it.
					if ns:IsMergePreviewState() then
						ns:QueueMergeMirror()
					end
				end)
			end
		end
	end
	if not skipPlace or not ns:IsMergeReanchorActive() then
		ns:PlaceAllMergedItems(true)
	end
end
