local _, ns = ...

-- Phase 40 (STEAL-03/05/06/07/08) -- the CDM mirror data source.
--
-- TBT reads the player's Cooldown Manager (CDM) configuration through the
-- C_CooldownViewer namespace only. Five injection experiments proved that touching a CDM
-- frame in any of the following ways taints it permanently, surviving combat and clearing
-- only on /reload (.planning/research/TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md). TBT writes
-- to a CDM frame in exactly two places, each only through the plain C widget calls its own
-- header lists: the viewer block in this file (parking the viewers) and MergeReanchor.lua
-- (moving and styling the item frames). The rules below bind both. TBT must never:
--   1. call a Blizzard MIXIN method on a CDM frame -- CooldownViewerMixin,
--      CooldownViewerItemMixin, EditModeSystemMixin and the rest. Plain C widget getters and
--      setters are a different thing and are permitted where the viewer block below or
--      MergeReanchor.lua's header lists them; so is exactly one generic-container call,
--      viewer.itemFramePool:EnumerateActive, whose admission is argued in full above
--      ns:RefreshMergeShownSlots. One pre-existing exception lives outside Merge Mode:
--      EditModeFrames.lua's Copy-Config button reads the viewer's settings through
--      GetSettingValue / GetSettingValueBool (EditModeSystemMixin getters), out of combat, on click
--   2. write a field on a CDM frame
--   3. parent anything into a CDM frame
--   4. call C_CooldownViewer.SetLayoutData -- it would overwrite the player's live config
--
-- Known fidelity limit (STEAL-05, partially met): GetCooldownViewerCategorySet returns the
-- game's spec-default category set. The live CDM UI's displayed list instead comes from
-- CooldownViewerSettings:GetDataProvider():GetOrderedCooldownIDsForCategory, which honours
-- the player's persisted category overrides and hidden-group overrides -- data reachable
-- only through a Blizzard mixin call, forbidden above. So this mirror follows spec, talent,
-- learned-spell, override and hotfix changes correctly, but a spell the player manually hid
-- in the CDM can still appear here, and one they moved to another CDM category can appear in
-- the wrong TBT container. Closing that gap needs the forbidden mixin call; accepted for
-- this phase per .planning/phases/40-cdm-steal-mode/40-01-PLAN.md Risks. (That directory keeps
-- its old name on purpose -- see the note at the head of REQUIREMENTS.md.)

-- Phase 40 (STEAL-06): one array per base container that has a cdmCategoryName -- user
-- containers never get one, so they never get an array here and stay out of the mirror.
-- This file-scope loop is the ONLY creation site; ns:RefreshMergeMirror only wipe()s.
ns.mergeSlots = {}
for _, def in ipairs(ns.CONTAINERS) do
	if def.cdmCategoryName then
		ns.mergeSlots[def.key] = {}
	end
end

-- Resolves the CDM category enum value by name, nil on any client lacking the enum. This is
-- the capability check that lets the whole feature degrade to a silent no-op mirror rather
-- than a load-time error on a client without Enum.CooldownViewerCategory.
local function ResolveCategory(def)
	return Enum.CooldownViewerCategory and def.cdmCategoryName and Enum.CooldownViewerCategory[def.cdmCategoryName]
end

-- Resolved once, not per refresh -- capability-checked the same way, never a flavour check.
local HIDE_BY_DEFAULT = Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideByDefault

-- One guarded flags read. `flags` is documented non-nilable but is guarded anyway: it is about to
-- go into bit.band, which raises on a secret.
local function HasCooldownFlag(info, mask)
	if not mask then
		return false
	end
	local flags = info.flags
	if issecretvalue(flags) or type(flags) ~= "number" then
		return false
	end
	return bit.band(flags, mask) ~= 0
end

-- Phase 43.1 -- ITEM-BACKED CDM ENTRIES (trinkets, potions, healthstones).
--
-- Not every cooldown the CDM shows is a spell. CooldownViewerCooldown.spellID is Nilable
-- (CooldownViewerDocumentation.lua:132), and an item-backed entry carries `equipSlot` (an
-- equipped trinket) or `spellCategoryID` (a generic item cooldown -- potions and healthstones)
-- instead. The mirror used to require a readable numeric spellID and drop everything else,
-- which is exactly why trinkets and potions never appeared in a merged container while every
-- class spell beside them did.
--
-- Blizzard resolves the same two shapes in CooldownViewerItemDataMixin:GetSpellTexture
-- (:548-590) and :GetNameText (:593-626). The order below is theirs: the spell category is
-- checked before the equipment slot, because a generic item cooldown has a fixed icon per
-- category rather than one per item.

-- The two lookup tables live in Core.lua: the pot meta-tracker needs the combat-potion icon for
-- its own fallback, and Providers.lua loads before this file.
local SPELL_CATEGORY_ICON = ns.SPELL_CATEGORY_ICON
local SPELL_CATEGORY_TITLE_KEY = ns.SPELL_CATEGORY_TITLE_KEY

-- Returns icon, label, equipSlot, spellCategoryID for an entry with no usable spellID, or nil
-- when this is not an item after all and the entry really should be skipped. Exactly one of
-- equipSlot and spellCategoryID is ever set: an equipped item, or a generic item cooldown.
--
-- Runs at mirror-build time only -- a spec change, a CDM edit, a zone-in -- never per frame, so
-- the pcalls and the item lookups cost nothing on the render path.
local function ResolveItemIdentity(info)
	local category = info.spellCategoryID
	if not issecretvalue(category) and type(category) == "number" then
		local icon = SPELL_CATEGORY_ICON[category]
		if icon then
			local key = SPELL_CATEGORY_TITLE_KEY[category]
			local title = key and _G[key]
			return icon, (type(title) == "string" and title) or nil, nil, category
		end
	end

	local equipSlot = info.equipSlot
	if issecretvalue(equipSlot) or type(equipSlot) ~= "number" then
		return nil
	end

	-- ItemUtil.GetEquipSlotTexture gives the equipped item's icon, or the empty paper-doll slot
	-- texture when the slot is bare -- which is what the CDM itself draws there
	-- (ItemUtil.lua:407-423). Capability-checked, never a flavour check.
	local icon
	if ItemUtil and ItemUtil.GetEquipSlotTexture then
		local ok, texture = pcall(ItemUtil.GetEquipSlotTexture, equipSlot)
		if ok and not issecretvalue(texture) and texture then
			icon = texture
		end
	end
	if not icon then
		return nil
	end

	-- The item's own name, when it can be had. An empty slot, or a client that cannot answer,
	-- leaves the label blank rather than failing the entry -- the icon alone is enough to place
	-- the trinket in the row, which is what was missing.
	local label
	if C_Item and C_Item.GetItemName and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
		local ok, name = pcall(function()
			local loc = ItemLocation:CreateFromEquipmentSlot(equipSlot)
			if loc and loc:IsValid() then
				return C_Item.GetItemName(loc)
			end
		end)
		if ok and not issecretvalue(name) and type(name) == "string" and name ~= "" then
			label = name
		end
	end

	return icon, label, equipSlot, nil
end

-- Reusable scratch for the item-frame id walk below. Never handed out beyond BuildViewerIDs.
local viewerIDs = {}
local viewerOrder = {}

-- Set by a Merge-on mirror rebuild; consumed by the next shown-slot pass, which renders before it
-- places (STEAL-13). The rebuild itself places nothing (ReanchorMergeViewers is told to skip), so
-- after a configuration change the cooldownID -> cell map the previous configuration built is
-- placed through only by a viewer's own Layout post-hook, for that viewer alone, and the viewer
-- check in PlaceItem keeps that pass on the right container (MergeReanchor.lua).
local mirrorChangedForPlacement = false

-- Sorts the collected ids by the layoutIndex Blizzard stamped on each item frame. Hoisted to
-- file scope rather than written inline so no closure is allocated per refresh.
local function ByLayoutIndex(a, b)
	return (viewerOrder[a] or 0) < (viewerOrder[b] or 0)
end

-- STEAL-05: the cooldownIDs the CDM is ACTUALLY displaying for this viewer, in the player's
-- own order, or nil when the viewer cannot answer.
--
-- This is what closes the gap the first implementation could not. GetCooldownViewerCategorySet
-- returns the game's SPEC-DEFAULT set: it knows nothing about the player adding a spell to a
-- category, hiding one, or dragging one from Utility to Essential. Those live in the CDM's own
-- persisted overrides, which reach the viewer through
-- CooldownViewerSettings:GetDataProvider():GetOrderedCooldownIDsForCategory -- a Blizzard mixin
-- call, forbidden here. Reported in play-testing on 2026-09-21: a buff newly added to a CDM
-- category never appeared in TBT.
--
-- The viewer's own item frames are the same list, already resolved. CooldownViewerMixin
-- :RefreshLayout acquires exactly one item frame per id from GetCooldownIDs() and stamps
-- itemFrame.layoutIndex = i in that order (CooldownViewer.lua:2021-2031, :2066-2068), so
-- walking the pool yields the overridden, ordered, player-visible set with no mixin call and
-- no new API surface beyond the EnumerateActive already admitted below.
--
-- Returns nil -- NOT an empty list -- when the pool is unbuilt or unreachable, so the caller
-- can fall back to the spec-default set rather than emptying the player's containers.
--
-- STEAL-13: mid-drag reads are not a cause of a wrong order. The settings window drags its own
-- CooldownViewerDraggedItem, not a viewer item frame; OnDataChanged fires once, on the drop
-- (EndOrderChange); RefreshLayout stamps layoutIndex before Layout, and the same-count path keeps
-- layoutIndex and re-assigns ids in place. The deferred read here always sees a consistent order.
local function BuildViewerIDs(viewer)
	wipe(viewerIDs)
	wipe(viewerOrder)

	local pool = viewer.itemFramePool
	if not pool or not pool.EnumerateActive then
		return nil
	end

	for itemFrame in pool:EnumerateActive() do
		-- A nil cooldownID is normal and is skipped rather than guarded against: while the CDM
		-- settings window is open Blizzard pads the viewer with placeholder item frames that
		-- carry no id at all (GetItemCount's edit-mode minimum), and those are not player
		-- configuration.
		local cooldownID = itemFrame.cooldownID
		if not issecretvalue(cooldownID) and type(cooldownID) == "number" and viewerOrder[cooldownID] == nil then
			local layoutIndex = itemFrame.layoutIndex
			if issecretvalue(layoutIndex) or type(layoutIndex) ~= "number" then
				layoutIndex = 0
			end

			viewerOrder[cooldownID] = layoutIndex
			viewerIDs[#viewerIDs + 1] = cooldownID
		end
	end

	if #viewerIDs == 0 then
		return nil
	end

	table.sort(viewerIDs, ByLayoutIndex)
	return viewerIDs
end

-- Phase 69 review IN-01: cooldownID -> the key of the first container whose viewer holds an item
-- frame for it, and the ids a list already took this rebuild. Together they publish each id in one
-- list only, preferring the container whose viewer owns the frame, so Display never sees an id
-- twice and the duplicate-attach guard in MergeReanchor.lua stays a pure safety net. Module-level
-- and wiped per rebuild.
local frameOwnerByID = {}
local claimedIDs = {}

local function CollectFrameOwners(viewer, key)
	local pool = viewer.itemFramePool
	if not pool or not pool.EnumerateActive then
		return
	end
	for itemFrame in pool:EnumerateActive() do
		local cooldownID = itemFrame.cooldownID
		if not issecretvalue(cooldownID) and type(cooldownID) == "number" and frameOwnerByID[cooldownID] == nil then
			frameOwnerByID[cooldownID] = key
		end
	end
end

-- STEAL-15: viewers (by CDM viewer global) already announced this session.
local mergeVisibilityWarned = {}

-- STEAL-15, reverse direction: the CDM's own Visibility (In Combat / Hidden) hides the viewer the
-- merged frames are still children of, so a merged entry cannot show in a visible TBT container.
-- TBT may not Show a Blizzard viewer (no Show, no Hide: it runs the CDM's OnShow on TBT's stack
-- and Blizzard hides it again on the next combat edge), so the player is told once per viewer per
-- session, and only for a viewer that has merged entries. A field read only; writes no frame.
-- A method on ns so it resolves at call time, whatever order the file declares things in.
function ns:CheckMergeViewerVisibility()
	if not (Enum and Enum.CooldownViewerVisibleSetting) then
		return
	end
	for _, def in ipairs(ns.CONTAINERS) do
		local global = def.cdmViewerGlobal
		local viewer = global and _G[global]
		local list = ns.mergeSlots and ns.mergeSlots[def.key]
		if viewer and not mergeVisibilityWarned[global] and list and #list > 0 then
			local setting = viewer.visibleSetting
			-- Only the two values that are known to hide the viewer are reported (Phase 69 review
			-- IN-03). Always prints nothing, and so does any value a future client adds, which
			-- `/tbt merge` likewise labels "unknown" rather than calling it hidden.
			local state
			if not issecretvalue(setting) and type(setting) == "number" then
				if setting == Enum.CooldownViewerVisibleSetting.InCombat then
					state = "is set to show only in combat"
				elseif setting == Enum.CooldownViewerVisibleSetting.Hidden then
					state = "is hidden"
				end
			end
			if state then
				mergeVisibilityWarned[global] = true
				print(
					"|cff00ccffTBT|r: "
						.. def.title
						.. " "
						.. state
						.. " in the Cooldown Manager's own Visibility setting. While Blizzard hides it, its merged"
						.. " entries cannot show in TBT, whatever TBT's container visibility is. Fix: turn Merge Mode"
						.. " off, set that Cooldown Manager section's Visibility to Always in Edit Mode, then turn"
						.. " Merge Mode back on."
				)
			end
		end
	end
end

-- Phase 40 (STEAL-03/STEAL-06): rebuilds ns.mergeSlots from what the CDM is displaying, or
-- from the spec-default category set when the viewers cannot answer. Event-driven only (see
-- the event frame below) -- never called from ns:UpdateDisplay or any OnUpdate script, exactly
-- like ns.cooldownGeneration in Core.lua. Table construction here is fine and expected: this
-- runs on a spec change or a CDM edit, not on a frame.
function ns:RefreshMergeMirror()
	for _, list in pairs(ns.mergeSlots) do
		wipe(list)
	end

	-- Off leaves every array empty -- the render path (Display.lua, Plan 02) needs no
	-- merge-mode branch at all, it only ever indexes the shown-slot arrays and reads #.
	if not ns.db or ns.db.mergeMode ~= true then
		ns:QueueMergeShownSlots()
		-- Hands any re-anchored CDM icons back to their viewers (MergeReanchor.lua).
		if ns.ReanchorMergeViewers then
			pcall(ns.ReanchorMergeViewers, ns)
		end
		return
	end

	-- Capability check, not a flavour check: a client missing either symbol degrades to an
	-- empty mirror instead of a Lua error.
	if
		not C_CooldownViewer
		or not C_CooldownViewer.GetCooldownViewerCategorySet
		or not C_CooldownViewer.GetCooldownViewerCooldownInfo
	then
		return
	end

	-- Which container's viewer owns each id's frame, read before any list is filled, so a list
	-- earlier in registry order (a spec-default fallback, or a viewer mid-move) cannot take an id
	-- whose frame lives in a later container's viewer (Phase 69 review IN-01).
	wipe(frameOwnerByID)
	wipe(claimedIDs)
	for _, def in ipairs(ns.CONTAINERS) do
		local viewer = def.cdmViewerGlobal and _G[def.cdmViewerGlobal]
		if viewer and ns.mergeSlots[def.key] and ResolveCategory(def) then
			pcall(CollectFrameOwners, viewer, def.key)
		end
	end

	for _, def in ipairs(ns.CONTAINERS) do
		local list = ns.mergeSlots[def.key]
		local category = list and ResolveCategory(def)

		if category then
			-- The viewer's own item frames first, because they honour the player's CDM edits;
			-- the spec-default category set only as the fallback for a client where the pool
			-- cannot be read. pcall'd like every other call into a frame TBT does not own.
			local ids
			local viewer = def.cdmViewerGlobal and _G[def.cdmViewerGlobal]
			if viewer then
				local ok, fromFrames = pcall(BuildViewerIDs, viewer)
				if ok then
					ids = fromFrames
				end
			end

			-- false = allowUnlearned: the game does the learned-spell filtering for us.
			if ids == nil then
				ids = C_CooldownViewer.GetCooldownViewerCategorySet(category, false)
			end

			if ns:CanReadTable(ids) then
				for _, cooldownID in ipairs(ids) do
					-- One list per id: not one another list already took, and not one whose frame
					-- another container's viewer owns. An unclaimable id gets no info, so it is skipped.
					local claimable = not issecretvalue(cooldownID)
						and not claimedIDs[cooldownID]
						and (frameOwnerByID[cooldownID] or def.key) == def.key
					local info = claimable and C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)

					if ns:CanReadTable(info) then
						-- These filters mirror Blizzard's own
						-- CooldownViewerSettingsDataProvider.lua:110-126 and :249-260.
						local skip = info.isInvisible == true or info.isKnown == false

						-- HideByDefault is a DEFAULT, and it is only TBT's business to apply it
						-- when TBT built the list itself. When the ids came from the item
						-- frames, Blizzard has already resolved defaults against the player's
						-- own show/hide choices, so re-applying it here would drop exactly the
						-- spell the player went out of their way to turn on.
						if not skip and ids ~= viewerIDs and HasCooldownFlag(info, HIDE_BY_DEFAULT) then
							skip = true
						end

						local spellID, iconOverride, itemLabel, equipSlot, itemCategory
						-- Captured for EVERY entry, and that is the fix for a real bug rather
						-- than tidying. These used to be read only when no spellID was found, on
						-- the assumption that an entry is either a spell or an item. It is not:
						-- Freightrunner's Flask is an equipped trinket that ALSO names a spell --
						-- the effect it applies, 1250533 -- and the CDM's own tile carries both
						-- its spellID and its equipSlot.
						--
						-- Missing that cost the trinket its cooldown. The effect spell has no
						-- spell cooldown of its own -- the cooldown lives on the ITEM -- so
						-- GetSpellCooldownDuration had nothing to give, and with no equipSlot
						-- recorded there was nothing to fall back to. Every ordinary spell beside
						-- it drew fine, which is exactly what made it look like a trinket problem
						-- rather than a missing field. (History: since Phase 70 Blizzard's own
						-- frame draws the cooldown, so both are kept for /tbt merge only.)
						local rawEquipSlot = info.equipSlot
						if not issecretvalue(rawEquipSlot) and type(rawEquipSlot) == "number" then
							equipSlot = rawEquipSlot
						end
						local rawCategory = info.spellCategoryID
						if not issecretvalue(rawCategory) and type(rawCategory) == "number" then
							itemCategory = rawCategory
						end

						if not skip then
							spellID = info.overrideSpellID or info.spellID
							if issecretvalue(spellID) or type(spellID) ~= "number" then
								-- Not a spell at all. Its icon and label have to come from the
								-- item instead; the slot and category above are already in hand.
								spellID = nil
								iconOverride, itemLabel = ResolveItemIdentity(info)
								if not iconOverride then
									skip = true
								end
							end
						end

						if not skip then
							local label = itemLabel or ""
							local spellInfo = spellID and C_Spell.GetSpellInfo(spellID)
							if spellInfo then
								local name = spellInfo.name
								if not issecretvalue(name) and type(name) == "string" then
									label = name
								end
							end

							-- No layoutOrder: CDM order is preserved by insertion order, and
							-- Plan 02 appends mirrored slots after the user's own without
							-- re-sorting.
							-- Mirrored CDM entries are runtime-only (never saved) and take the
							-- user kinds so the shared slot predicates (ns:IsCooldownSlotEntry,
							-- ns:IsBagItemEntry) treat them exactly as before the naming scheme.
							table.insert(list, {
								key = "cdm:" .. cooldownID,
								-- Kept alongside the key rather than re-parsed out of it: the
								-- shown-state mirror below joins on this, and pulling a number
								-- back out of a string every refresh would be silly.
								cooldownID = cooldownID,
								spellID = spellID,
								label = label,
								section = def.key,
								trackerType = (def.kind == "icon" and def.cdmCategoryName ~= "TrackedBuff")
										and ns.KIND.USER_CD
									or ns.KIND.USER_BUFF,
								-- Both nil for an ordinary spell entry. iconOverride is the item
								-- icon Display draws in place of a spell texture (the preview
								-- placeholder). equipSlot is diagnostic only (/tbt merge): since
								-- Phase 70 Blizzard's own frame draws the item's cooldown.
								iconOverride = iconOverride,
								equipSlot = equipSlot,
								-- Carried for the diagnostics: a generic item cooldown names no
								-- spell, so its category is the only thing that identifies it.
								spellCategoryID = itemCategory,
								isMerged = true,
							})
							claimedIDs[cooldownID] = true
						end
					end
				end
			end
		end
	end

	-- Every rebuild here replaces the entry tables the shown-slot arrays hold references to,
	-- so the shown pass always follows. Queued rather than called inline for the reason given
	-- in its own header: it must run after Blizzard's handler for the same event, not before.
	mirrorChangedForPlacement = true
	ns:QueueMergeShownSlots()

	-- Installs the viewer Layout hooks (MergeReanchor.lua) and places
	-- nothing. The map is still the previous configuration's; the render the queued shown pass
	-- runs (mirrorChangedForPlacement) rebuilds it and its flush places (Phase 69 review WR-03).
	pcall(ns.ReanchorMergeViewers, ns, true)
	-- STEAL-15: tell the player once when the CDM's own Visibility hides a viewer with merged entries.
	pcall(ns.CheckMergeViewerVisibility, ns)
end

---------------------------------------------------------------------
-- Phase 40 (STEAL-03) -- mirroring WHICH of those entries the CDM is currently showing.
--
-- ns.mergeSlots above is the CONFIGURED set: every cooldownID the player's CDM categories
-- contain. That is not the same as what the CDM puts on screen. An item frame whose viewer
-- has hideWhenInactive set is shown only while it is active -- CooldownViewerItemMixin
-- :ShouldBeShown returns early on `not self.hideWhenInactive`, otherwise on self:IsActive()
-- (CooldownViewer.lua:284-307) -- which is exactly the default for the tracked-buff and
-- tracked-bar categories. So mirroring the configured set alone put a tracked debuff in TBT
-- whenever it was configured rather than when it was really on the target. Reported in
-- play-testing on 2026-09-21 with Polymorph, which sat in TBT permanently.
--
-- TBT must not re-derive "is it up" itself. Doing so would mean reading the aura APIs, which
-- return secret values under restriction, and then branching on the answer -- the one thing
-- the Secret Values rules forbid outright. The answer already exists, computed by Blizzard,
-- as the shown flag on each CDM item frame. This block reads that flag and nothing else.
--
-- WHY THIS EXTENDS THE PERMITTED CDM SURFACE, AND HOW FAR.
-- The boundary at the top of this file forbids calling a Blizzard mixin method on a CDM
-- frame. Reaching the item frames needs one call that is not a plain C widget getter:
--
--     viewer.itemFramePool:EnumerateActive()
--
-- It is admitted deliberately, and it is the only addition. It is not a CDM mixin method:
-- itemFramePool is a secure pool PROXY (Pools.lua:857 sets CreateFramePool =
-- CreateSecureFramePool, and :736 returns :ToProxy()), so the call lands on
-- ObjectPoolProxyMixin, a generic SharedXMLBase container type with no CooldownViewer code in
-- it at all. It is also provably read-only: the proxy forwards to
-- SecureObjectPoolMixin:EnumerateActive (Pools.lua:241-243), which returns
-- SecureMap:Enumerate, an iterator whose entire body is securecallfunction(next, tbl, key)
-- (SecureTypes.lua:64-71). It writes nothing, and securecallfunction is Blizzard's own
-- taint-scrubbing wrapper. There is no C_* alternative: C_CooldownViewer exposes seven
-- functions, all config-level, none carrying live shown or active state
-- (CooldownViewerDocumentation.lua).
--
-- The pool cannot be walked as a field instead. pool.activeObjects reads nil from here --
-- the real table lives on the private object behind the proxy -- which is why the
-- pre-existing capability check in ns:InitDisplay never hit this.
--
-- In THIS pass the item frames are only read: itemFrame.cooldownID (a raw field read) and
-- itemFrame:IsShown() (a C widget getter, the same class of call as the viewer:IsShown()
-- already on the permitted list). Writes to item frames happen only in MergeReanchor.lua,
-- through the plain C setters its header lists; no item frame is parented or has a mixin
-- method called on it, anywhere.
--
-- The shown-state read also uses the IsVisible C getter on item frames, only while previewing,
-- for the STEAL-14 placeholder. Same class of read as IsShown; no write.
---------------------------------------------------------------------

-- Same one-array-per-mirroring-container shape as ns.mergeSlots, and the same rule: this loop
-- is the ONLY creation site and the refresh below only wipe()s and refills. The entries are
-- REFERENCES to the tables in ns.mergeSlots -- nothing is copied or constructed per pass.
ns.mergeShownSlots = {}
for _, def in ipairs(ns.CONTAINERS) do
	if def.cdmCategoryName then
		ns.mergeShownSlots[def.key] = {}
	end
end

-- Reused across refreshes, both wiped once per def: cooldownID -> true for every item frame the
-- CDM currently has on screen (shown), and for every one it is actually DRAWING (visible, only
-- used while previewing, STEAL-14).
local shownCooldownIDs = {}
local visibleCooldownIDs = {}

-- Fills `into` from one viewer's live item frames and returns how many active item frames it
-- saw. That count is the "did I get an answer at all" signal, and it is why the return value
-- matters: zero active frames never means "nothing is up right now" -- Blizzard acquires one
-- item frame per configured cooldownID in RefreshLayout and then merely HIDES the inactive ones
-- (CooldownViewer.lua:2013-2035), so a viewer with any configuration at all has active frames
-- whether or not anything is showing. Zero therefore means the pool has not been built yet, or
-- cannot be read on this client, and the caller falls back to the unfiltered mirror rather than
-- silently emptying the player's containers.
--
-- `readVisible` reads IsVisible instead of IsShown. IsVisible is used only while previewing: the
-- frame's own shown flag misses a viewer hidden by the CDM's Visibility setting, and a cell is
-- only filled if the frame is really drawn.
local function CollectFrameCooldownIDs(viewer, into, readVisible)
	local pool = viewer.itemFramePool
	if not pool or not pool.EnumerateActive then
		return 0
	end

	local seen = 0
	for itemFrame in pool:EnumerateActive() do
		seen = seen + 1

		-- Guarded before use, per the addon-wide rule, even though neither value is expected
		-- to be secret: a cooldownID that is unreadable simply does not join, and an
		-- unreadable flag is treated as not shown.
		local cooldownID = itemFrame.cooldownID
		if not issecretvalue(cooldownID) and type(cooldownID) == "number" then
			local on
			if readVisible then
				on = itemFrame:IsVisible()
			else
				on = itemFrame:IsShown()
			end
			if not issecretvalue(on) and on == true then
				into[cooldownID] = true
			end
		end
	end

	return seen
end

-- Rebuilds ns.mergeShownSlots from the CDM's live per-item shown flags. Event-driven only,
-- exactly like ns:RefreshMergeMirror -- never called from ns:UpdateDisplay or any OnUpdate.
-- Allocates nothing per pass beyond the iterator closure SecureMap:Enumerate returns: the
-- outer arrays and the join set are module-level and wiped.
function ns:RefreshMergeShownSlots()
	for _, list in pairs(ns.mergeShownSlots) do
		wipe(list)
	end

	if not ns.db or ns.db.mergeMode ~= true then
		return
	end

	local previewing = ns:IsMergePreviewState()

	for _, def in ipairs(ns.CONTAINERS) do
		local slots = ns.mergeSlots[def.key]
		local shown = ns.mergeShownSlots[def.key]

		-- Tracked Buffs are published whole, shown or not: Display needs every configured entry to
		-- size the container and to work out which grid cell each buff belongs in, while each
		-- entry's own cdmShown stamp says which ones Blizzard's moved frames are drawing. Nothing
		-- is drawn from the entry itself, so nothing is drawn twice.
		local publishWhole = def.cdmCategoryName == "TrackedBuff"

		if slots and shown and #slots > 0 then
			wipe(shownCooldownIDs)
			wipe(visibleCooldownIDs)
			local visibleSeen = 0
			if previewing and def.cdmViewerGlobal then
				local previewViewer = _G[def.cdmViewerGlobal]
				if previewViewer then
					local ok, count = pcall(CollectFrameCooldownIDs, previewViewer, visibleCooldownIDs, true)
					if ok and not issecretvalue(count) and type(count) == "number" then
						visibleSeen = count
					end
				end
			end

			-- While previewing, publish EVERYTHING configured and do not consult the CDM's shown
			-- flags at all. `seen == 0` is already the "no answer, show it all" path, so previewing
			-- simply takes it.
			--
			-- This used to lean on Blizzard showing all its own items while the settings window is
			-- open, which it does -- and that is why preview worked there. It does not hold in
			-- Edit Mode, where an item's shown state depends on the viewer's editing state rather
			-- than on the settings window, so merged buffs never appeared. Deciding it here makes
			-- preview mean the same thing in both states instead of inheriting whatever Blizzard
			-- happens to do.
			--
			-- Tracked Buffs publishes its whole configured set (publishWhole), so the container is
			-- sized for every entry and its footprint never shifts as buffs come and go. It does
			-- NOT throw the shown flags away though: each entry is stamped with its own, below,
			-- because a centred run has to know which merged auras are actually up to close the
			-- gaps and re-centre. The count comes from Blizzard's own item frames, which is the
			-- one place it is a plain readable boolean rather than a secret.
			local seen = 0
			local viewer = not previewing and def.cdmViewerGlobal and _G[def.cdmViewerGlobal]
			if viewer then
				-- pcall'd for the same reason EachViewer is: this is a call into a Blizzard
				-- container on a frame TBT does not own, and degrading to the unfiltered mirror
				-- beats taking down the render.
				local ok, count = pcall(CollectFrameCooldownIDs, viewer, shownCooldownIDs, false)
				if ok and not issecretvalue(count) and type(count) == "number" then
					seen = count
				end
			end

			for _, entry in ipairs(slots) do
				-- Stamped on EVERY entry, published or not: Display reads it to decide whether a
				-- merged aura takes a cell in a centred run. "seen == 0" is the no-answer case --
				-- no viewer, or a viewer with no item frames -- and there everything counts as
				-- shown, exactly as the publish filter below treats it.
				entry.cdmShown = (seen == 0) or (shownCooldownIDs[entry.cooldownID] == true)

				-- Outside preview this is always true, so Display draws nothing extra. While
				-- previewing it is false when Blizzard's frame for the id is not drawn, so Display
				-- can show TBT's own placeholder (STEAL-14). With no answer from the pool
				-- (visibleSeen 0) there is no frame to place either, so false is right.
				-- Accepted limitation: it is stamped only by this event-driven pass, so toggling
				-- Edit Mode's Cooldown Manager checkbox can leave the placeholder lagging until
				-- the next pass.
				entry.cdmFrameVisible = not previewing
					or (visibleSeen > 0 and visibleCooldownIDs[entry.cooldownID] == true)

				if publishWhole or seen == 0 or shownCooldownIDs[entry.cooldownID] then
					shown[#shown + 1] = entry
				end
			end
		end
	end

	-- Only after a mirror rebuild (a CDM edit, a preview edge or a spec change), never on an aura
	-- burst, so the combat render rate does not change. The render rebuilds the cooldownID -> cell
	-- map from the lists this pass just published and its own flush places them (STEAL-13). The
	-- rebuild placed nothing, so this is the first placement through the new map; only a viewer's
	-- Layout post-hook can have placed through the old one in between, for its own viewer only.
	if mirrorChangedForPlacement then
		mirrorChangedForPlacement = false
		if ns.UpdateDisplay then
			pcall(ns.UpdateDisplay, ns)
		end
	end
	-- Blizzard may have handed an item frame a different
	-- cooldownID since the last pass, so every frame is re-matched to its cell here.
	pcall(ns.PlaceAllMergedItems, ns)
	-- This pass runs deferred on the events Blizzard refreshes its cooldown items on, and that
	-- refresh re-enables the swipe a Show Timer off container turned off (MergeReanchor.lua).
	pcall(ns.ReassertMergedSwipe, ns)
end

-- Un-suppression state, deliberately independent of TBT's own "Edit Mode active" flag in
-- EditModeFrames.lua: that flag is set to false when the user unticks TBT inside the Edit Mode
-- panel, which is not the same thing as Edit Mode being closed. (The flag is named by description
-- rather than by identifier so the STEAL-08 audit grep for it stays a true negative in this file.)
--
-- Declared HERE, above ns:IsMergePreviewState and the EventRegistry callbacks that write it: a
-- file-local is only an upvalue to functions defined after it.
local editModeOpen = false

-- True while the CDM settings window or Edit Mode is open, which is when TBT shows every
-- configured entry and draws its own placeholder for a merged entry whose Blizzard frame is not
-- drawn (STEAL-14), the way the CDM itself previews its whole configured set.
--
-- QUERIED LIVE, NEVER LATCHED, and that is the whole point.
--
-- The first version of this kept a cdmSettingsOpen boolean set on the settings window's OnShow
-- and cleared on its OnHide. A latched flag is only ever as good as the edge that clears it, and
-- the failure is silent and total: one missed OnHide and the preview state is stuck for the rest
-- of the session. Asking the frames what they are doing right now cannot get stuck.
--
-- Both are plain C widget reads on frames this addon already reads elsewhere, and both are
-- capability-guarded, so a client without either frame simply reports "not previewing".
-- ON ns, NOT A FILE-LOCAL, and that is load-bearing rather than style. A file-local is only an
-- upvalue to functions defined AFTER it, and this predicate has callers on both sides of its own
-- declaration -- ns:RefreshMergeShownSlots sits well above it. As a local it read nil there and
-- threw "attempt to call a nil value" the moment Merge Mode was switched on. Resolving through ns
-- happens at call time, so declaration order stops mattering. The same trap cost editModeOpen a
-- commit two changes ago; it is worth not paying a third time.
function ns:IsMergePreviewState()
	if CooldownViewerSettings and CooldownViewerSettings.IsVisible and CooldownViewerSettings:IsVisible() then
		return true
	end

	if EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown() then
		return true
	end

	-- The edge flag is still consulted as a backstop for the window between Blizzard firing
	-- EditMode.Enter and the manager frame actually being shown.
	return editModeOpen
end

-- Kept as the TRIGGER for a rebuild on the settings window's edges. It no longer holds the state
-- -- ns:IsMergePreviewState reads that live -- so there is nothing here that can latch.
function ns:SetMergeCDMSettingsOpen()
	-- The rebuild queues the shown pass, which puts the TBT side into the right state for the
	-- new mode.
	ns:QueueMergeMirror()
end

-- Single-flight guard for ns:QueueMergeMirror below.
local mirrorQueued = false

local function FlushMergeMirror()
	mirrorQueued = false
	ns:RefreshMergeMirror()
end

-- Deferred for the same reason the shown-slot pass is, and it became load-bearing the moment
-- the mirror started reading the viewers' item frames. TBT registers
-- CooldownViewerSettings.OnDataChanged at addon load; the CDM viewers register it from their
-- own OnShow, which happens later, and CallbackRegistryMixin fires callbacks in registration
-- order. So TBT's callback runs BEFORE the viewers have rebuilt their item pools, and a mirror
-- that read them inline would see the configuration as it was before the player's edit -- the
-- exact "a buff I just added to the CDM never shows up in TBT" symptom. C_Timer.After(0) puts
-- the rebuild after every synchronous handler for the event, whatever order they registered in.
function ns:QueueMergeMirror()
	if mirrorQueued then
		return
	end

	mirrorQueued = true
	C_Timer.After(0, FlushMergeMirror)
end

-- Single-flight guard for ns:QueueMergeShownSlots below.
local shownQueued = false

local function FlushMergeShownSlots()
	shownQueued = false
	ns:RefreshMergeShownSlots()
end

-- ALWAYS deferred, and not for the taint reason ns:QueueMergeVisibility is deferred -- this
-- function writes no frame at all. It is deferred because it READS a state Blizzard is in the
-- middle of computing. TBT's event frame and the CDM viewers register for the same events
-- (UNIT_AURA, PLAYER_TARGET_CHANGED, PLAYER_TOTEM_UPDATE, BAG_UPDATE_COOLDOWN --
-- CooldownViewer.lua:1729-1736), and the order in which two frames receive one event is not
-- defined. Reading the shown flags inline would therefore be a coin flip between the state
-- before Blizzard's handler ran and the state after, so a buff could appear in TBT a whole
-- aura event late. C_Timer.After(0) puts the read after every synchronous handler for that
-- event, and the flag coalesces a UNIT_AURA burst into one refresh per frame.
function ns:QueueMergeShownSlots()
	if shownQueued then
		return
	end

	shownQueued = true
	C_Timer.After(0, FlushMergeShownSlots)
end

---------------------------------------------------------------------
-- Phase 40 (STEAL-01/02/06/07) -- suppressing and restoring Blizzard's CDM viewers.
--
-- This block is TBT's whole surface on the CDM VIEWER frames. It is one of exactly two places
-- TBT writes to a Blizzard CDM frame: the other is MergeReanchor.lua, whose header lists the
-- C widget calls Merge Mode makes on the CDM ITEM frames (and the one Layout post-hook per
-- viewer), and is the baseline any item-frame write must be judged against. Every operation
-- below is a plain C widget call on the VIEWER frame, and never a Blizzard Lua mixin method:
--   1. _G[def.cdmViewerGlobal]      -- a global table lookup, no frame method at all (read)
--   2. viewer.SomeMethod            -- a field read, used only as a capability check  (read)
--   3. viewer:GetNumPoints/GetPoint -- C widget getters                               (read)
--   4. viewer:IsClampedToScreen     -- C widget getter                                (read)
--   5. viewer:GetParent             -- C widget getter                                (read)
--   6. viewer:ClearAllPoints/SetPoint      -- C widget setters                       (WRITE)
--   7. viewer:SetClampedToScreen           -- C widget setter                        (WRITE)
-- No CDM mixin method is called -- not IsActive, not ShouldBeShown, not GetItemCount, and not
-- the per-setting getter EditModeFrames.lua's pre-existing Copy-Config button uses (named
-- here only by description, so the STEAL-08 audit grep for it stays a true negative in this
-- file). No field is written on a CDM frame. Nothing is parented into one.
-- C_CooldownViewer.SetLayoutData is never called. The five measured injection variants each
-- tainted the CDM permanently, so this list is a hard boundary, not a guideline.
--
-- WHY THE VIEWER IS NO LONGER HIDDEN (Phase 40, revised after play-testing 2026-09-21).
-- The first implementation called viewer:Hide(). Hiding is what broke three separate things:
--   1. CooldownViewerMixin:OnHide unregisters UNIT_AURA, PLAYER_TARGET_CHANGED and the rest
--      (CooldownViewer.lua:1741-1753), and RefreshLayout only calls RefreshData `if
--      self:IsShown()` (:2052). A hidden viewer therefore freezes: its cached aura data and
--      its per-item shown states stop tracking the game.
--   2. Because the per-item shown states freeze, TBT has no way to tell which CDM entries the
--      player would actually be seeing, so a tracked debuff (the reported case: Polymorph)
--      shows in TBT whenever it is configured rather than when it is really on the target.
--   3. Blizzard re-shows the viewers from UpdateShownState on combat and level changes and on
--      the cooldownViewerEnabled CVar (:1764-1765, :1755-1760), so TBT and Blizzard fought
--      over the shown flag and TBT could only ever win a frame late.
-- Keeping the viewer SHOWN and moving it off-screen instead fixes all three at once: every
-- Blizzard event handler stays registered, the item frames keep accurate shown states and
-- live aura data, and there is no shown-state fight left to lose.
--
-- WHY OFF-SCREEN PLACEMENT AND NOT ALPHA.
-- Alpha 0 fails on both of the things that matter here. It is contested -- the CDM's own
-- Opacity setting writes the viewer's alpha, so Blizzard overwrites TBT's 0 whenever the
-- player touches that slider or Edit Mode re-applies a layout -- and, worse, it leaves the
-- frame hoverable: CooldownViewerItemMixin:SetTooltipsShown does SetMouseMotionEnabled(true)
-- per item frame whenever the viewer's Tooltips setting is on (CooldownViewer.lua:322-325,
-- :1998), so an alpha-0 viewer is an invisible block of dead screen space that still pops
-- tooltips. Turning that setting off would need a CDM mixin call, which is forbidden above.
-- An off-screen anchor solves both: nothing is drawn where the player is looking, and the
-- cursor cannot reach a rect that is outside the screen, so there is nothing to hover. It is
-- also uncontested by any CDM setting -- only Edit Mode re-anchors a system frame, and
-- EditMode.Exit and EDIT_MODE_LAYOUTS_UPDATED both re-assert below.
---------------------------------------------------------------------

-- EditModeSystemTemplate carries clampedToScreen="true" (EditModeSystemTemplates.xml:4), so
-- an off-screen anchor is dragged back on-screen unless clamping is turned off first. Both
-- the clamp flag and the anchor are captured and restored (STEAL-07).
local OFFSCREEN_POINT = "TOPLEFT"
local OFFSCREEN_X = -10000
local OFFSCREEN_Y = 10000

-- The largest anchor offset TBT will accept as "a placement the player could actually have".
-- UIParent is a virtual coordinate space a few thousand units across at most, and every Edit
-- Mode system is clamped to the screen, so nothing the player can produce comes near this.
--
-- It exists because of one specific Blizzard code path: EditModeSystemMixin:SetScaleOverride
-- reads a system frame's LIVE anchors and rewrites them with rescaled offsets
-- (EditModeSystemTemplates.lua:126-136). If that runs while a viewer is parked off-screen,
-- TBT's own -10000 comes back as, say, -6667 -- no longer an exact match for the parked
-- anchor, and a naive re-capture would then record TBT's own doing as the player's layout and
-- restore the CDM to somewhere off-screen forever. Refusing to capture any implausible offset
-- makes that unrecoverable case impossible: the stale-but-correct capture is kept and the
-- viewer is simply re-parked.
local MAX_PLAUSIBLE_OFFSET = 4000

-- STEAL-07: the placement each Blizzard viewer had BEFORE TBT moved it, keyed by
-- def.cdmViewerGlobal. Three possible values per key:
--   nil    -- TBT has not moved this viewer, so there is nothing to restore
--   false  -- the placement could not be read safely; TBT must never move this viewer
--   table  -- { clamped = bool, n = count, [i] = { point, relativeTo, relativePoint, x, y } }
-- Runtime-only and deliberately never written into ns.db: a persisted copy could hand a later
-- session an anchor that was TBT's own doing and call it the user's layout.
ns.mergePriorPlacement = {}

-- Single-flight guard for ns:QueueMergeVisibility below.
local queued = false

-- The one place in the addon that resolves a CDM viewer frame for Merge Mode. Two capability
-- checks, neither of them a flavour check: a container def with no cdmViewerGlobal (every
-- user container) is skipped, and a global that resolves to nil (a client shipping no CDM) is
-- skipped, so the whole feature degrades to a silent no-op instead of an error.
--
-- `fn` is always one of the two file-scope functions below, never a closure built per call,
-- and every call is pcall-wrapped: a placement write on a frame TBT does not own is exactly
-- the kind of call that can raise (an anchor-family error, a forbidden-frame error on a
-- client that classifies the viewers differently), and "degrade silently, never error" wins
-- over knowing why. This whole path is event-driven -- never ns:UpdateDisplay, never OnUpdate.
local function EachViewer(fn)
	for _, def in ipairs(ns.CONTAINERS) do
		local globalName = def.cdmViewerGlobal
		if globalName then
			local viewer = _G[globalName]
			if viewer then
				pcall(fn, viewer, globalName)
			end
		end
	end
end

-- Capability check, not a flavour check: a client whose frames lack any one of these methods
-- gets no suppression at all rather than a half-applied one it cannot undo. Field reads only.
local function CanPlace(viewer)
	return viewer.GetNumPoints
		and viewer.GetPoint
		and viewer.SetPoint
		and viewer.ClearAllPoints
		and viewer.GetParent
		and viewer.SetClampedToScreen
		and viewer.IsClampedToScreen
end

-- True only for the exact anchor TBT writes below. Used to tell "Blizzard has re-anchored
-- this viewer since TBT moved it" from "TBT's own suppressed anchor is still in place", which
-- is what keeps the capture from ever recording TBT's own doing as the player's layout.
-- Every value compared is guarded by issecretvalue first, per the addon-wide rule.
local function IsAtOffscreenAnchor(viewer)
	local numPoints = viewer:GetNumPoints()
	if issecretvalue(numPoints) or numPoints ~= 1 then
		return false
	end

	local point, relativeTo, relativePoint, x, y = viewer:GetPoint(1)
	if
		issecretvalue(point)
		or issecretvalue(relativeTo)
		or issecretvalue(relativePoint)
		or issecretvalue(x)
		or issecretvalue(y)
	then
		return false
	end

	return point == OFFSCREEN_POINT
		and relativePoint == OFFSCREEN_POINT
		and relativeTo == UIParent
		and x == OFFSCREEN_X
		and y == OFFSCREEN_Y
end

-- STEAL-07: reads back every anchor the viewer currently has, plus its clamp flag. Returns
-- `false` -- the "never touch this viewer" sentinel -- rather than a partial capture if any
-- component is a secret value, the wrong type, or if the frame has no anchors at all: moving
-- a frame TBT cannot put back is the one failure mode with no recovery short of /reload.
-- The table constructors here are correct and cheap: this runs once per viewer per merge-mode
-- session (and again only if Blizzard re-anchors), never on a frame.
local function CapturePlacement(viewer)
	local numPoints = viewer:GetNumPoints()
	if issecretvalue(numPoints) or type(numPoints) ~= "number" or numPoints < 1 then
		return false
	end

	-- Defaulting an unreadable clamp flag to true is faithful rather than arbitrary:
	-- EditModeSystemTemplate declares clampedToScreen="true" and nothing in the CDM turns it
	-- off, so true is the state every one of these viewers ships with.
	local clamped = viewer:IsClampedToScreen()
	if issecretvalue(clamped) then
		clamped = true
	end

	local prior = { clamped = clamped and true or false, n = numPoints }

	for i = 1, numPoints do
		local point, relativeTo, relativePoint, x, y = viewer:GetPoint(i)
		if
			issecretvalue(point)
			or issecretvalue(relativeTo)
			or issecretvalue(relativePoint)
			or issecretvalue(x)
			or issecretvalue(y)
			or type(point) ~= "string"
			or type(relativePoint) ~= "string"
			or type(x) ~= "number"
			or type(y) ~= "number"
			or math.abs(x) > MAX_PLAUSIBLE_OFFSET
			or math.abs(y) > MAX_PLAUSIBLE_OFFSET
		then
			return false
		end

		-- GetPoint returns nil for relativeTo when the anchor is to the frame's own parent;
		-- resolving it here keeps the restore path a single unambiguous SetPoint overload.
		prior[i] = {
			point = point,
			relativeTo = relativeTo or viewer:GetParent(),
			relativePoint = relativePoint,
			x = x,
			y = y,
		}
	end

	return prior
end

-- STEAL-07: capture, then move off-screen. The capture condition is "nothing captured yet, OR
-- the viewer is not where TBT last put it". The first half covers the two entry paths -- a
-- checkbox click, and a login with the flag already true. The second half covers Blizzard
-- re-anchoring a still-suppressed viewer (a layout switch outside Edit Mode), and it is also
-- why TBT can never record its own suppressed anchor as the player's: the only placement that
-- is NOT re-captured is the one that is byte-for-byte TBT's own.
--
-- Note what is deliberately absent: no Show, no Hide, no shown-state read. Shown state now
-- belongs entirely to Blizzard, which is the whole point of the redesign above.
local function CaptureAndSuppress(viewer, globalName)
	local prior = ns.mergePriorPlacement[globalName]
	if prior == false then
		-- Placement was unreadable on a previous apply -- this viewer is off-limits for the
		-- rest of the session, because TBT could not put it back.
		return
	end

	if not CanPlace(viewer) then
		ns.mergePriorPlacement[globalName] = false
		return
	end

	if prior ~= nil and IsAtOffscreenAnchor(viewer) then
		-- Already parked exactly where TBT put it. Re-anchoring a GridLayoutFrame on every
		-- re-assert event (CVAR_UPDATE fires often) would cost a layout pass for no change,
		-- so the steady state writes nothing at all -- except the clamp flag, and only if
		-- something turned it back on, because a clamped frame would walk back on-screen.
		local clamped = viewer:IsClampedToScreen()
		if not issecretvalue(clamped) and clamped then
			viewer:SetClampedToScreen(false)
		end
		return
	end

	local captured = CapturePlacement(viewer)
	if captured == false then
		if prior == nil then
			-- Nothing known and nothing readable: a viewer TBT could not put back is a viewer
			-- TBT must not move. The sentinel makes that decision stick for the session.
			ns.mergePriorPlacement[globalName] = false
			return
		end
		-- An earlier capture is still held, so the unreadable placement is almost certainly
		-- TBT's own parked anchor after Blizzard rescaled its offsets (see
		-- MAX_PLAUSIBLE_OFFSET). Keep the known-good capture and simply re-park below.
	else
		ns.mergePriorPlacement[globalName] = captured
	end

	-- Clamping first: EditModeSystemTemplate is clampedToScreen, and a clamped frame would be
	-- dragged straight back on-screen by the SetPoint below.
	viewer:SetClampedToScreen(false)
	viewer:ClearAllPoints()
	viewer:SetPoint(OFFSCREEN_POINT, UIParent, OFFSCREEN_POINT, OFFSCREEN_X, OFFSCREEN_Y)
end

-- STEAL-07 restore: puts back exactly the anchors and the clamp flag that were captured, and
-- nothing else. `nil` means TBT never moved this viewer and `false` means TBT deliberately
-- never touched it -- in both cases restoring would be inventing a state rather than
-- returning one. Anchors are restored before the clamp flag so a clamped frame is clamped
-- against its real position rather than the off-screen one.
local function RestorePlacement(viewer, globalName)
	local prior = ns.mergePriorPlacement[globalName]
	if not prior then
		return
	end

	if not CanPlace(viewer) then
		return
	end

	viewer:ClearAllPoints()
	for i = 1, prior.n do
		local p = prior[i]
		viewer:SetPoint(p.point, p.relativeTo, p.relativePoint, p.x, p.y)
	end
	viewer:SetClampedToScreen(prior.clamped)
end

-- STEAL-02/STEAL-07: the only writer of CDM frame visibility. Called from exactly one place,
-- the C_Timer.After body in ns:QueueMergeVisibility below.
function ns:ApplyMergeVisibility()
	-- Merge Mode suppresses the CDM viewers in Edit Mode TOO, as of 2026-09-23 (user decision).
	--
	-- It used to un-suppress there, on the reasoning that Edit Mode is where the player positions
	-- the CDM for when Merge Mode is off. In practice that meant entering Edit Mode with Merge
	-- Mode on showed both sets of icons at once -- the CDM's, and TBT's containers holding copies
	-- of the same entries -- which is the one place the duplication is most confusing, because
	-- positioning is exactly what the player is trying to do.
	--
	-- The trade is explicit: with Merge Mode ON the CDM viewers can no longer be dragged from
	-- Edit Mode, because they are never on screen to drag. Turning Merge Mode off restores them
	-- to the placement captured before TBT moved them, and Edit Mode then behaves normally. That
	-- is the supported route to repositioning them, and it is a clearer one than "drag the thing
	-- you have told the addon to hide".
	--
	-- What made this safe to do is already in place. The captured placement is kept rather than
	-- re-captured while suppressed, so nothing can record TBT's own -10000 as the player's
	-- layout; and MAX_PLAUSIBLE_OFFSET refuses an implausible capture outright, which covers the
	-- one Blizzard path that rewrites a parked viewer's anchors
	-- (EditModeSystemMixin:SetScaleOverride, see the note above it).
	--
	-- The CDM settings window never un-suppressed either, for the same reason: the player
	-- configures in that window, not by looking at the viewers. Both windows now behave alike.
	--
	-- There is deliberately NO combat gate. The four viewers inherit
	-- EditModeCooldownViewerSystemTemplate -> EditModeSystemTemplate and GridLayoutFrame
	-- (CooldownViewer.xml:289-340, EditModeSystemTemplates.xml:4), and none of those carries
	-- protected="true", so a placement write on them is legal in combat. The CDM ITEM frames are
	-- the taint hazard, and this function never touches one; Merge Mode's item-frame writes live
	-- in MergeReanchor.lua alone, within the boundary its header lists.
	--
	-- The "never write from inside a Blizzard call stack" rule is structural rather than a
	-- branch: this function has one caller, the C_Timer.After(0) body below.
	local suppress = ns.db ~= nil and ns.db.mergeMode == true

	if suppress then
		EachViewer(CaptureAndSuppress)
	else
		EachViewer(RestorePlacement)
		-- Wiped so the next apply re-captures from scratch -- which is what makes the Edit
		-- Mode round trip pick up a position the player changed while un-suppressed. Wiping
		-- an already-empty table is the correct no-op for "TBT never moved anything".
		wipe(ns.mergePriorPlacement)
	end
end

-- Hoisted rather than built per queue: C_Timer.After keeps a reference, and CVAR_UPDATE
-- alone would otherwise allocate a closure on every fire.
local function FlushMergeVisibility()
	queued = false
	ns:ApplyMergeVisibility()
	-- STEAL-15 notice, re-checked here too (Phase 69 review IN-02): viewer.visibleSetting is written
	-- when Edit Mode applies a layout, which can come after the login mirror rebuild, and a
	-- Visibility change in Edit Mode rebuilds nothing. This flush runs on EDIT_MODE_LAYOUTS_UPDATED
	-- and on the Edit Mode Exit edge. A few field reads; the once-per-viewer table keeps it quiet.
	if ns.db and ns.db.mergeMode == true then
		pcall(ns.CheckMergeViewerVisibility, ns)
	end
end

-- STEAL-02: the "never write to a CDM frame from inside a Blizzard call stack" rule, made
-- structural. Every trigger -- event handler or EventRegistry callback -- calls this and
-- never ns:ApplyMergeVisibility directly, so C_Timer.After(0, ...) always puts the write on a
-- fresh execution frame. The queued flag coalesces a burst (CVAR_UPDATE fires often) into a
-- single apply, and nothing is allocated on this path.
function ns:QueueMergeVisibility()
	if queued then
		return
	end

	queued = true
	C_Timer.After(0, FlushMergeVisibility)
end

-- STEAL-06: the single entry point for the toggle, all-or-nothing by user decision. There is
-- no per-category variant and none may be added. ns.db.mergeMode is written here and in one
-- other place only, Core.lua's ADDON_LOADED default seed.
function ns:SetMergeMode(enabled)
	if not ns.db then
		return
	end

	ns.db.mergeMode = enabled and true or false

	-- Turning it off must take effect before Display's next render, not after the queued mirror.
	-- Until then the shown-slot lists still hold merged entries. Wiping them inline touches no
	-- frame, so no merged entry reaches the next render; that render's placement flush then sends
	-- every moved frame back to its viewer.
	if not ns.db.mergeMode then
		for _, list in pairs(ns.mergeShownSlots) do
			wipe(list)
		end
		ns:MarkMergedPlacementDirty()
	end

	-- Both are queued. The mirror used to be immediate, on the reasoning that it read
	-- C_CooldownViewer only and touched no frame; that stopped being true when it started
	-- reading the viewers' item frames for the player's real configuration.
	ns:QueueMergeMirror()
	ns:QueueMergeVisibility()
end

-- Phase 40 (STEAL-05): the mirror refresh event frame. Dedicated frame and a local,
-- three-line pcall-guarded register helper -- Core.lua's TryRegisterEvent is file-local, so
-- this is a deliberate short duplicate rather than a cross-file dependency. Candidate for
-- unification in a later cleanup phase (Phase 43).
local function TryRegisterMergeEvent(frame, eventName)
	return pcall(frame.RegisterEvent, frame, eventName)
end

-- UNIT_AURA unfiltered would fire for every unit in a raid. Registered for the same two units
-- the CDM itself registers (CooldownViewer.lua:1732), so TBT wakes on exactly the aura changes
-- that can move a CDM item's shown flag and on nothing else.
local function TryRegisterMergeUnitEvent(frame, eventName, unit1, unit2)
	return pcall(frame.RegisterUnitEvent, frame, eventName, unit1, unit2)
end

local mergeEventFrame = CreateFrame("Frame")

-- Every one of these events can change the CDM's configured category set: spec change,
-- talent change, spell learned/unlearned, a hotfix to the cooldown table, or a per-spell
-- override. None fires once per frame, so no per-event branching is needed below -- the
-- refresh itself is cheap and idempotent, so re-running it on every one of these is fine.
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_ENTERING_WORLD")
TryRegisterMergeEvent(mergeEventFrame, "SPELLS_CHANGED")
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_SPECIALIZATION_CHANGED")
TryRegisterMergeEvent(mergeEventFrame, "TRAIT_CONFIG_UPDATED")
TryRegisterMergeEvent(mergeEventFrame, "COOLDOWN_VIEWER_DATA_LOADED")
TryRegisterMergeEvent(mergeEventFrame, "COOLDOWN_VIEWER_TABLE_HOTFIXED")
TryRegisterMergeEvent(mergeEventFrame, "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")

-- Phase 40 (STEAL-02): the second job of the same frame -- re-asserting the off-screen
-- anchor. EDIT_MODE_LAYOUTS_UPDATED is the one that can genuinely undo it: an Edit Mode
-- layout apply re-anchors every system frame, and TBT's captured placement has to be
-- refreshed from the new one rather than restored over it (CaptureAndSuppress handles that by
-- re-capturing whenever the viewer is not at TBT's own anchor).
--
-- The rest are kept as insurance rather than because a specific Blizzard code path is known
-- to move the viewers on them: they are the events on which Blizzard touches viewer state at
-- all -- UpdateShownState runs from OnEvent on PLAYER_IN_COMBAT_CHANGED and
-- PLAYER_LEVEL_CHANGED (CooldownViewer.lua:1764-1765), from OnVariablesLoaded, and on the
-- cooldownViewerEnabled CVar changing (:1755-1760) -- and a re-assert on a viewer that is
-- already parked now writes NOTHING, because CaptureAndSuppress early-outs on its own anchor.
--
-- PLAYER_LEVEL_CHANGED, deliberately NOT PLAYER_LEVEL_UP: the latter fires only on a real
-- level-up, so level scaling or level sync would miss the re-assert entirely.
--
-- Combat start is registered at BOTH names. PLAYER_IN_COMBAT_CHANGED is the one Blizzard's own
-- viewer listens to, so matching it keeps the re-assert on the same edge; PLAYER_REGEN_DISABLED
-- is the long-standing name and is certain to exist on both clients. Registering both is safe:
-- TryRegisterMergeEvent pcalls, so a name a client does not know is a silent no-op, and the
-- queue coalesces the two into one apply. Ordering works out because ns:QueueMergeVisibility
-- defers through C_Timer.After(0) -- Blizzard's synchronous handler runs first, TBT's apply
-- reads the result on the next frame.
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_REGEN_DISABLED")
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_IN_COMBAT_CHANGED")
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_REGEN_ENABLED")
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_LEVEL_CHANGED")
TryRegisterMergeEvent(mergeEventFrame, "VARIABLES_LOADED")
TryRegisterMergeEvent(mergeEventFrame, "CVAR_UPDATE")
TryRegisterMergeEvent(mergeEventFrame, "EDIT_MODE_LAYOUTS_UPDATED")

-- Phase 40 (STEAL-03): the third job of the same frame -- re-reading which CDM items are on
-- screen. These are the events on which Blizzard's own viewers recompute item shown state:
-- the four they register in CooldownViewerMixin:OnShow (:1729-1736), plus the two cooldown
-- ones, because a cooldown item in a hideWhenInactive viewer is shown only while
-- isOnActualCooldown holds and nothing in OnShow's list covers a cooldown starting or ending.
--
-- These deliberately do NOT rebuild the mirror. The configured category set cannot change on
-- an aura gain, and rebuilding it on UNIT_AURA would run a full GetCooldownViewerCategorySet
-- walk with a table constructor per entry on every aura change in combat. The split is in
-- REFRESH_MIRROR below.
TryRegisterMergeUnitEvent(mergeEventFrame, "UNIT_AURA", "player", "target")
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_TARGET_CHANGED")
TryRegisterMergeEvent(mergeEventFrame, "PLAYER_TOTEM_UPDATE")
TryRegisterMergeEvent(mergeEventFrame, "BAG_UPDATE_COOLDOWN")
TryRegisterMergeEvent(mergeEventFrame, "SPELL_UPDATE_COOLDOWN")
TryRegisterMergeEvent(mergeEventFrame, "SPELL_UPDATE_CHARGES")

-- The events above that additionally re-assert visibility. PLAYER_ENTERING_WORLD was already
-- registered for the mirror and is listed here too: it is the apply that moves the viewers
-- off-screen on a login where ns.db.mergeMode is already true.
-- The events that can change the CDM's CONFIGURED category set, and therefore the only ones
-- that rebuild the mirror. Everything else registered above gets the shown-state refresh
-- alone, which walks item frames already in existence and constructs nothing.
--
-- PLAYER_LEVEL_CHANGED is here because a level change can change which spells are known.
-- CVAR_UPDATE and the combat edges are deliberately NOT: they re-assert placement only. Before
-- the shown-state pass existed every registered event rebuilt the mirror, which made
-- CVAR_UPDATE -- an event that fires in bursts -- a full category walk each time.
local REFRESH_MIRROR = {
	PLAYER_ENTERING_WORLD = true,
	SPELLS_CHANGED = true,
	PLAYER_SPECIALIZATION_CHANGED = true,
	TRAIT_CONFIG_UPDATED = true,
	COOLDOWN_VIEWER_DATA_LOADED = true,
	COOLDOWN_VIEWER_TABLE_HOTFIXED = true,
	COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED = true,
	PLAYER_LEVEL_CHANGED = true,
	VARIABLES_LOADED = true,
}

local REASSERT_VISIBILITY = {
	PLAYER_ENTERING_WORLD = true,
	PLAYER_REGEN_DISABLED = true,
	PLAYER_IN_COMBAT_CHANGED = true,
	PLAYER_REGEN_ENABLED = true,
	PLAYER_LEVEL_CHANGED = true,
	VARIABLES_LOADED = true,
	CVAR_UPDATE = true,
	EDIT_MODE_LAYOUTS_UPDATED = true,
	-- Reported on retail 2026-09-24: after a spec change the player's own CDM reappeared and the
	-- newly-learned spells did not stay merged. Both events were already in REFRESH_MIRROR
	-- above, so the mirror DID rebuild -- but rebuilding the mirror and parking Blizzard's
	-- viewers off-screen are two different passes, and only the first was queued. Blizzard
	-- re-shows its own viewers when the spec change repopulates them, so the park has to be
	-- re-asserted on the same edge.
	--
	-- Being in both tables is correct and not a double-apply: each pass is queued separately,
	-- single-flight, and idempotent.
	PLAYER_SPECIALIZATION_CHANGED = true,
	TRAIT_CONFIG_UPDATED = true,
}

mergeEventFrame:SetScript("OnEvent", function(_, event)
	if REFRESH_MIRROR[event] then
		-- The rebuild ends by queueing the shown-state pass itself, so the else branch below is
		-- a true alternative rather than a missing call.
		ns:QueueMergeMirror()
	else
		ns:QueueMergeShownSlots()
	end

	-- Queued, never applied inline: an event handler is a Blizzard call stack. The apply is
	-- idempotent and allocates nothing in the steady state, so CVAR_UPDATE firing often costs
	-- four global lookups and four anchor reads on viewers that are already parked -- and the
	-- single-flight queue coalesces a burst into one apply anyway.
	if REASSERT_VISIBILITY[event] then
		ns:QueueMergeVisibility()
	end
end)

-- STEAL-05: the "without a reload" path for editing the CDM while its settings window is
-- open -- none of the events above fire while the player is only dragging inside the CDM
-- settings UI. Registering an EventRegistry callback is neither a frame method call nor a
-- Blizzard mixin call, so it is not covered by the prohibitions at the top of this file.
if EventRegistry then
	EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
		ns:QueueMergeMirror()
	end, ns)

	-- Phase 40 (STEAL-02): the Edit Mode pair and the settings-window pair.
	--
	-- Edit Mode now UN-suppresses, where the old Hide-based implementation merely stopped
	-- writing. An off-screen anchor is TBT's own and Blizzard never undoes it, so without the
	-- queued apply on the Enter edge the player would find the CDM missing from the one UI
	-- that exists to position it. The Exit edge re-applies, and because ApplyMergeVisibility
	-- wipes the capture whenever it restores, that re-apply captures whatever position the
	-- player just dragged the viewer to.
	--
	-- The settings-window pair does NOT un-suppress; it only re-asserts on both edges. The
	-- player configures in that window rather than by looking at the viewers.
	--
	-- These use the independent local flags declared above rather than TBT's own "Edit Mode
	-- active" flag in EditModeFrames.lua -- see the note there.
	--
	-- The owner is mergeEventFrame, not ns: EditModeFrames.lua already registers
	-- EditMode.Enter/Exit with ns as the owner, and CallbackRegistryMixin:RegisterCallback
	-- allows one callback per owner per event -- re-using ns here would silently replace
	-- TBT's own Edit Mode handlers (CallbackRegistry.lua:128-130).
	--
	-- EventRegistry is also the sanctioned replacement for hooking the CDM settings frame's
	-- own OnShow/OnHide scripts, which CDMTab.lua:1670-1674 records as propagating taint in
	-- instances; a callback registration is neither a frame method call nor a Blizzard mixin
	-- call. (The hook API is named by description here so the STEAL-08 audit grep for it
	-- stays a true negative in this file.)
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editModeOpen = true
		-- Queued, not inline: this callback runs on Blizzard's Edit Mode call stack, and the
		-- restore is a placement write.
		ns:QueueMergeVisibility()
		-- Edit Mode is a preview state exactly like the CDM settings window: the player is
		-- positioning containers and needs to see what goes in them, not just whatever happens to
		-- be live. The mirror rebuild re-stamps the preview state for every configured entry.
		ns:QueueMergeMirror()
	end, mergeEventFrame)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editModeOpen = false
		ns:QueueMergeVisibility()
		ns:QueueMergeMirror()
	end, mergeEventFrame)
	-- Both edges do two things.
	--
	-- The placement re-assert is cheap: a viewer still parked at TBT's anchor takes no write at
	-- all. Kept because opening or closing the window is the most likely moment for Blizzard to
	-- touch viewer state, and the queue coalesces either edge into a single apply.
	--
	-- The shown-slot refresh is what gives Merge Mode the CDM's own PREVIEW behaviour. While
	-- the settings window is visible Blizzard shows every configured item whether or not it is
	-- active -- CooldownViewerItemMixin:ShouldBeShown returns true on
	-- CooldownViewerSettings:IsVisible() (CooldownViewer.lua:299-301) -- and it flips every
	-- item's flag on both edges through OnViewerSettingsShownStateChange (:1968-1974). Because
	-- TBT mirrors those flags rather than deciding for itself, re-reading them here is the
	-- whole feature: the player sees every mergeable buff laid out next to their own trackers
	-- while configuring, and only the live ones once the window closes. No preview branch, no
	-- second code path, and it cannot drift from what Blizzard does.
	--
	-- Ordering is safe for the usual reason: ns:QueueMergeShownSlots defers through
	-- C_Timer.After(0), so Blizzard's synchronous handler for the same callback has always
	-- finished flipping the flags before TBT reads them, whatever order the two registered in.
	EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
		ns:QueueMergeVisibility()
		ns:QueueMergeShownSlots()
		-- Tells the mirror the CDM settings window is open, so every configured entry
		-- previews. See ns:SetMergeCDMSettingsOpen.
		ns:SetMergeCDMSettingsOpen()
	end, mergeEventFrame)
	EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
		ns:QueueMergeVisibility()
		ns:QueueMergeShownSlots()
		-- Preview over: only the entries Blizzard is drawing show again.
		ns:SetMergeCDMSettingsOpen()
	end, mergeEventFrame)
end

-- Print what the mirror actually resolved for every slot the CDM is showing. A diagnostic, not
-- a feature: it exists because a single merged entry behaving oddly takes one look at these
-- fields to explain and a round of guesswork otherwise. Reachable as "/tbt merge".
--
-- Reads nothing new. Every field printed was resolved elsewhere and stored on the entry, so this
-- cannot be the thing that raises, and it runs only when typed.
function ns:PrintMergeDiagnostics()
	print("|cff00ccffTBT|r merge diagnostics:")
	if not ns.db or ns.db.mergeMode ~= true then
		print("  Merge Mode is OFF -- nothing is mirrored.")
		return
	end

	-- STEAL-15: the CDM's own Visibility per viewer (a field read; a hidden viewer hides merged frames).
	for _, def in ipairs(ns.CONTAINERS) do
		if def.cdmViewerGlobal then
			local viewer = _G[def.cdmViewerGlobal]
			local label = "unknown"
			local setting = viewer and viewer.visibleSetting
			if
				Enum
				and Enum.CooldownViewerVisibleSetting
				and not issecretvalue(setting)
				and type(setting) == "number"
			then
				if setting == Enum.CooldownViewerVisibleSetting.Always then
					label = "Always"
				elseif setting == Enum.CooldownViewerVisibleSetting.InCombat then
					label = "|cffff6600In Combat|r"
				elseif setting == Enum.CooldownViewerVisibleSetting.Hidden then
					label = "|cffff6600Hidden|r"
				end
			end
			print("  CDM Visibility, " .. def.title .. ": " .. label)
		end
	end

	local total = 0
	for _, def in ipairs(ns.CONTAINERS) do
		local slots = ns.mergeShownSlots and ns.mergeShownSlots[def.key]
		if slots and #slots > 0 then
			print("  |cffffff00" .. def.title .. "|r (" .. #slots .. " shown)")
			for _, entry in ipairs(slots) do
				total = total + 1
				local bits = {}
				bits[#bits + 1] = "id=" .. tostring(entry.cooldownID)
				bits[#bits + 1] = "spell=" .. tostring(entry.spellID)
				bits[#bits + 1] = "shown=" .. tostring(entry.cdmShown)
				bits[#bits + 1] = "visible=" .. tostring(entry.cdmFrameVisible)
				-- Whether the placement map holds a cell for this id (TBT tables only, no game call).
				local placement = ns:GetMergedPlacementKind(entry.cooldownID)
				bits[#bits + 1] = placement and ("cell=" .. placement) or "|cffff6600cell=none|r"
				if entry.equipSlot then
					bits[#bits + 1] = "equipSlot=" .. tostring(entry.equipSlot)
				end
				if entry.iconOverride then
					bits[#bits + 1] = "itemIcon"
				end
				if entry.spellCategoryID then
					bits[#bits + 1] = "cat=" .. tostring(entry.spellCategoryID)
				end
				print("    " .. (entry.label ~= "" and entry.label or "(no label)") .. "  " .. table.concat(bits, " "))
			end
		end
	end

	if total == 0 then
		print("  No shown slots. Either the CDM has nothing configured, or its viewers are unreadable.")
	end
end
