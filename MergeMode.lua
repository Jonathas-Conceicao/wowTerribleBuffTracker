local _, ns = ...

-- Phase 40 (STEAL-03/05/06/07/08) -- the CDM mirror data source.
--
-- TBT reads the player's Cooldown Manager (CDM) configuration through the
-- C_CooldownViewer namespace only. Five injection experiments proved that touching a CDM
-- frame in any of the following ways taints it permanently, surviving combat and clearing
-- only on /reload (.planning/research/TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md). This file,
-- and this file alone for the lifetime of Phase 40, is where "TBT never touches a CDM
-- frame" is verified by reading it. TBT must never, anywhere in this file or any other:
--   1. call a Blizzard MIXIN method on a CDM frame -- CooldownViewerMixin,
--      CooldownViewerItemMixin, EditModeSystemMixin and the rest. Plain C widget getters and
--      setters are a different thing and are permitted where the second block below lists
--      them; so is exactly one generic-container call, viewer.itemFramePool:EnumerateActive,
--      whose admission is argued in full above ns:RefreshMergeShownSlots
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

-- The flag behind Blizzard's CooldownViewerItemDataMixin:CanUseAuraForDisplay
-- (CooldownViewerItemData.lua:747-754). An entry carrying it must NOT swap its cooldown sweep
-- for its aura's, which is the one exception to the aura-wins rule below.
local HIDE_AURA = Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideAura

-- One guarded flags read, shared by the two callers below. `flags` is documented non-nilable but
-- is guarded anyway: it is about to go into bit.band, which raises on a secret.
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

-- Returns a plain array of the entry's linked aura spell IDs, or nil when there are none worth
-- keeping. Runs at mirror-build time only, which is a spec change or a CDM edit -- never a frame.
local function CopyLinkedSpellIDs(info)
	local linked = info.linkedSpellIDs
	if not ns:CanReadTable(linked) then
		return nil
	end

	local out
	for _, linkedID in ipairs(linked) do
		if not issecretvalue(linkedID) and type(linkedID) == "number" then
			out = out or {}
			out[#out + 1] = linkedID
		end
	end
	return out
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
					local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)

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
						-- rather than a missing field.
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
							table.insert(list, {
								key = "cdm:" .. cooldownID,
								-- Kept alongside the key rather than re-parsed out of it: the
								-- shown-state mirror below joins on this, and pulling a number
								-- back out of a string every refresh would be silly.
								cooldownID = cooldownID,
								spellID = spellID,
								-- The aura a CDM entry displays is very often NOT the spell the
								-- entry is named after: Frostbolt's tracked aura is Chilled, and
								-- the CDM pairs them through this list. Matching only on spellID
								-- is why those entries never resolved. Copied rather than
								-- referenced so nothing holds a table the API owns, and each id
								-- is guarded because a secret would poison the lookup.
								linkedSpellIDs = CopyLinkedSpellIDs(info),
								label = label,
								section = def.key,
								trackerType = (def.kind == "icon" and def.cdmCategoryName ~= "TrackedBuff")
										and "cooldown"
									or "buff",
								-- Phase 43.1: Blizzard's CanUseAuraForDisplay, resolved here rather
								-- than at render time -- the flag cannot change without a mirror
								-- rebuild, and reading it per frame would mean a bit.band per
								-- merged slot per tick.
								hideAura = HasCooldownFlag(info, HIDE_AURA),
								-- Whether the CDM considers this a charge spell. A plain bool on
								-- the info struct, read here at mirror-build time rather than from
								-- C_Spell.GetSpellCharges at render time -- that call is
								-- SecretWhenCooldownsRestricted, this field is not. Display uses it
								-- to pick the recharge handle over the cooldown handle.
								hasCharges = info.charges == true,
								-- Blizzard's own flag, present in CooldownViewerCooldown but read
								-- NOWHERE in their UI, so its meaning is inferred from its name
								-- and has to be confirmed against real data before anything is
								-- built on it. If it means "this entry's aura lands on the
								-- caster", it is the discriminator that says which entries could
								-- ever need a target container at all.
								selfAura = info.selfAura == true,
								-- Both nil for an ordinary spell entry. iconOverride is the item
								-- icon Display draws in place of a spell texture; equipSlot is
								-- what the item's cooldown is read from.
								iconOverride = iconOverride,
								equipSlot = equipSlot,
								-- Carried for the aura-filter fallback in SyncEntryContainers: a
								-- generic item cooldown names no spell, so its category is the
								-- only thing that says which auras belong to it.
								spellCategoryID = itemCategory,
								isMerged = true,
							})
						end
					end
				end
			end
		end
	end

	-- Every rebuild here replaces the entry tables the shown-slot arrays hold references to,
	-- so the shown pass always follows. Queued rather than called inline for the reason given
	-- in its own header: it must run after Blizzard's handler for the same event, not before.
	ns:QueueMergeShownSlots()

	-- The engine-driven aura groups filter on the same configured set, so they are refreshed
	-- from the same place. pcall'd: a failure here must not abort the mirror.
	pcall(ns.RefreshMergeAuraGroups, ns)
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
-- pre-existing capability check in Display.lua:489 never hit this.
--
-- Everything else stays as it was: the item frames themselves are touched only through
-- itemFrame.cooldownID (a raw field read) and itemFrame:IsShown() (a C widget getter, the
-- same class of call as the viewer:IsShown() already on the permitted list). No item frame
-- is written to, parented, or has a mixin method called on it.
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

-- Reused across refreshes, wiped per viewer: cooldownID -> true for every item frame the CDM
-- currently has on screen.
local shownCooldownIDs = {}

-- cooldownID -> the CDM item frame currently drawing it, for the ids in shownCooldownIDs.
-- Rebuilt whole on every shown-state pass and wiped when Merge Mode is off, so it can never
-- hand Display a frame the CDM has since released. Display.lua relays bar values straight off
-- these frames; see the note above its RelayMergedBar. Runtime-only, never in ns.db.
ns.mergeItemFrames = {}

-- Fills shownCooldownIDs from one viewer's live item frames and returns how many active item
-- frames it saw. That count is the "did I get an answer at all" signal, and it is why the
-- return value matters: zero active frames never means "nothing is up right now" -- Blizzard
-- acquires one item frame per configured cooldownID in RefreshLayout and then merely HIDES
-- the inactive ones (CooldownViewer.lua:2013-2035), so a viewer with any configuration at
-- all has active frames whether or not anything is showing. Zero therefore means the pool
-- has not been built yet, or cannot be read on this client, and the caller falls back to the
-- unfiltered mirror rather than silently emptying the player's containers.
local function CollectShownCooldownIDs(viewer)
	local pool = viewer.itemFramePool
	if not pool or not pool.EnumerateActive then
		return 0
	end

	local seen = 0
	for itemFrame in pool:EnumerateActive() do
		seen = seen + 1

		-- Guarded before use, per the addon-wide rule, even though neither value is expected
		-- to be secret: a cooldownID that is unreadable simply does not join, and an
		-- unreadable shown flag is treated as not shown.
		local cooldownID = itemFrame.cooldownID
		if not issecretvalue(cooldownID) and type(cooldownID) == "number" then
			local isShown = itemFrame:IsShown()
			if not issecretvalue(isShown) and isShown == true then
				shownCooldownIDs[cooldownID] = true
				ns.mergeItemFrames[cooldownID] = itemFrame
			end
		end
	end

	return seen
end

-- Resolve a merged aura slot's real timing and stash it on the entry as PLAIN NUMBERS, or clear
-- it when the aura cannot be read.
--
-- This is what gives a merged buff icon a real cooldown sweep, and it exists because the earlier
-- conclusion -- "an aura sweep is impossible for a tainted addon" -- was too strong. It is true
-- that the CDM's own item frames are a dead end: every Cooldown getter is
-- SecretReturnsForAspect = { Cooldown }, every numeric Cooldown setter is
-- SecretArguments = "AllowedWhenUntainted", and the aura instance IDs that would unlock
-- C_UnitAuras.GetAuraDuration live in a table Blizzard flags DisallowTaintedAccess
-- (CooldownViewerSecure.lua). All of that stands.
--
-- What it misses is that aura data is not unconditionally secret. GetPlayerAuraBySpellID and
-- GetAuraDataBySpellName are SecretWhenUnitAuraRestricted, not "always secret", and per-spell
-- never-secret flags outrank even that -- which is exactly the ground ns:ReadPlayerAura was
-- already built on for the Sated check. So TBT can read an aura's real expirationTime and
-- duration whenever the game permits it, and hand them to the ordinary SetCooldown path, which a
-- tainted caller may use freely with NON-secret numbers. Under restriction the read fails
-- cleanly and the icon falls back to the relayed countdown text, which is what it had before.
--
-- WHY THIS DOES NOT USE ns:ReadPlayerAura, WHICH LOOKS LIKE EXACTLY THE RIGHT HELPER.
-- That helper asks C_Secrets.ShouldSpellAuraBeSecret(spellID) first and gives up when it says
-- yes. That gate is correct for the question it was written for -- "does the player have the
-- Sated debuff", where a hidden aura returns no values and a bare nil cannot tell "absent" from
-- "hidden", so acting on nil would be acting on a guess. It is WRONG for this question. Here
-- absence and unreadability have the same consequence, no sweep, so nothing is ever concluded
-- from a failed read -- and the predicate is conservative enough that going through it produced
-- no sweep at all in play-testing on 2026-09-22, even out of combat where the data reads fine.
--
-- So the read is attempted directly and judged by what comes back: ns:CanReadTable on the table,
-- issecretvalue and type on each field. That is strictly safer than a predicate, because it
-- tests the actual values rather than a prediction about them.
--
-- Called from the shown-slots pass, so it runs on aura events rather than per frame, and only
-- for slots the CDM is actually showing.
-- Both polarities: a CDM "tracked buff" is as often a debuff the player put on their target as a
-- buff on themselves.
local TARGET_AURA_FILTERS = { "HARMFUL", "HELPFUL" }

-- THE AURA APIs DO NOT ALL FAIL THE SAME WAY, AND ONE OF THEM RAISES.
--
-- C_UnitAuras.GetAuraDataByIndex is RequiresUnitAuraAccess, and that is not a soft flag: called
-- while auras are secret and the caller is tainted, it THROWS --
--
--   GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by
--   'TerribleBuffTracker'
--
-- -- so no issecretvalue guard on the RESULT can ever run. An index walk shipped on 2026-09-22
-- did exactly that, took the whole shown-slots pass down with it in combat, and left every
-- merged container empty. GetPlayerAuraBySpellID and GetAuraDataBySpellName are
-- RequiresNonSecretAura instead and degrade quietly to nil, which is why the version before it
-- failed silently rather than loudly.
--
-- So: only the quiet APIs are called, every call still goes through a pcall, and the first raise
-- latches the whole lookup off until something could plausibly have changed the restriction.
-- Belt and braces, because "an aura read cannot take the render down" matters more here than any
-- sweep does.
local auraLookupBlocked = false

-- Cleared on the events that can change aura restriction, so a latch set inside an instance or a
-- fight does not outlive it. Called from the merge event handler below.
function ns:ClearMergeAuraLookupBlock()
	auraLookupBlocked = false
end

local function SafeAuraCall(fn, a, b, c)
	if auraLookupBlocked or not fn then
		return nil
	end

	local ok, aura = pcall(fn, a, b, c)
	if not ok then
		auraLookupBlocked = true
		return nil
	end
	return aura
end

-- spellID -> name, memoised: the same handful of ids are looked up on every aura event, and
-- C_Spell.GetSpellName is not free. Never holds a secret -- the guard below runs before the store.
local auraNameBySpellID = {}

local function AuraSpellName(spellID)
	local name = auraNameBySpellID[spellID]
	if name ~= nil then
		return name
	end

	if C_Spell and C_Spell.GetSpellName then
		local fetched = C_Spell.GetSpellName(spellID)
		if not issecretvalue(fetched) and type(fetched) == "string" and fetched ~= "" then
			auraNameBySpellID[spellID] = fetched
			return fetched
		end
	end

	auraNameBySpellID[spellID] = false
	return false
end

-- Writes entry.auraExpiry / entry.auraDuration from one candidate spell ID, and answers whether
-- it managed to. Player by ID first -- exact and cheapest -- then the target by name, which is
-- the only lookup the API offers for a unit other than the player.
local function TryResolveFromSpellID(entry, spellID)
	if type(spellID) ~= "number" or not C_UnitAuras then
		return false
	end

	-- Ask before reading, and take yes for an answer.
	--
	-- This gate was here, then removed on 2026-09-22 on the reasoning that it was conservative
	-- and was blocking a read that would have worked. Live testing showed the opposite: on the
	-- Forever client every aura path fails for a tainted caller -- the quiet APIs return nil and
	-- GetAuraDataByIndex raises outright -- and this predicate was correctly predicting exactly
	-- that. It was right and the removal was wrong.
	--
	-- Reinstated as an efficiency gate rather than a correctness one, since the guards below
	-- already handle a failed read safely. Without it a client that can never answer still pays
	-- up to three API calls per candidate spell ID, per slot, on every aura event, forever.
	if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret and C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return false
	end

	local aura = SafeAuraCall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
	local onTarget = false

	if not ns:CanReadTable(aura) then
		local spellName = AuraSpellName(spellID)
		if spellName then
			for i = 1, #TARGET_AURA_FILTERS do
				aura = SafeAuraCall(C_UnitAuras.GetAuraDataBySpellName, "target", spellName, TARGET_AURA_FILTERS[i])
				if ns:CanReadTable(aura) then
					onTarget = true
					break
				end
			end
		end
	end

	if not ns:CanReadTable(aura) then
		return false
	end

	-- Guarded individually even though ns:CanReadTable passed: a readable table can still carry
	-- secret fields, and these two are about to be used in arithmetic.
	local expiry = aura.expirationTime
	local duration = aura.duration
	if issecretvalue(expiry) or type(expiry) ~= "number" then
		return false
	end
	if issecretvalue(duration) or type(duration) ~= "number" or duration <= 0 then
		return false
	end

	entry.auraExpiry = expiry
	entry.auraDuration = duration
	-- WHICH unit the aura was found on, because Blizzard's desaturation rule turns on it: a
	-- spell the player actively casts whose aura lands on the TARGET stays greyed while the aura
	-- drives the sweep, and only an aura on the PLAYER clears the grey
	-- (CheckCacheCooldownValuesFromAura, CooldownViewer.lua:899-901). Touch of the Magi is the
	-- case that exposed this.
	entry.auraOnTarget = onTarget
	return true
end

local function ResolveMergedAuraTiming(entry)
	entry.auraExpiry = nil
	entry.auraDuration = nil
	entry.auraOnTarget = nil

	-- The entry's own spell first, then whatever the CDM says it is linked to. The linked list is
	-- what makes an entry like Frostbolt resolvable at all: the aura it displays is Chilled, and
	-- linkedSpellIDs is the only thing that pairs them.
	if TryResolveFromSpellID(entry, entry.spellID) then
		return
	end

	local linked = entry.linkedSpellIDs
	if linked then
		for i = 1, #linked do
			if TryResolveFromSpellID(entry, linked[i]) then
				return
			end
		end
	end
end

-- Phase 48 (D-03) -- the state-change half of the /tbt debug dump for PANDEMIC.md's five
-- unknowns. A NEW call site of the existing ns.debugLogging flag (Core.lua:1055-1058);
-- Core.lua's protected debug cast/item log (D-04) is untouched -- this neither calls, wraps,
-- extends nor relocates any part of it. Guard-clause early return, same idiom Core.lua's own
-- logging functions use, so the hot path costs one boolean test and allocates nothing when
-- debug is off.
--
-- Only prints on a state CHANGE (old boolean vs new), using the previous value already on the
-- entry rather than a fourth stamped field. The OFF line's GetTime() compared against the last
-- readable `finish` answers unknown 1 (does PandemicIcon clear promptly or linger); the
-- secret/type columns in and out of combat answer unknown 2; running it on a target-debuff
-- entry answers unknown 5.
local function LogPandemicStateChange(entry, wasActive, startTime, endTime)
	if not ns.debugLogging then
		return
	end

	local isActive = entry.pandemicActive == true
	if wasActive == isActive then
		return
	end

	-- issecretvalue(v) and type(v) are themselves always safe to print -- they are the
	-- introspection functions used to detect a secret and never return one -- but the VALUE
	-- behind them is screened the same issecretvalue()-then-type() way as everywhere else in
	-- this file before it is allowed anywhere near a concatenation.
	local startSecret, startType = issecretvalue(startTime), type(startTime)
	local startVal = (not startSecret and startType == "number") and startTime or nil
	local endSecret, endType = issecretvalue(endTime), type(endTime)
	local endVal = (not endSecret and endType == "number") and endTime or nil

	local line = "|cff00ccffTBT Debug|r: |cffff8040PANDEMIC|r "
		.. (entry.label ~= "" and entry.label or "(no label)")
		.. " id="
		.. tostring(entry.cooldownID)
		.. " "
		.. (isActive and "ON" or "OFF")
		.. " t="
		.. GetTime()
		.. " start(secret="
		.. tostring(startSecret)
		.. ",type="
		.. startType
		.. ",val="
		.. tostring(startVal)
		.. ") finish(secret="
		.. tostring(endSecret)
		.. ",type="
		.. endType
		.. ",val="
		.. tostring(endVal)
		.. ")"
	print(line)
end

-- Phase 48 (PAND-03/04/05) -- stamps entry.pandemicActive and the guarded
-- entry.pandemicStart/entry.pandemicFinish pair from the CDM item frame cached for this
-- entry's cooldownID. This is the only place in the phase that touches a CDM-owned object
-- (this file's header, :5-25): every access below is a plain table-field read, never a mixin
-- method, never a write onto the frame, and the CDM-owned pool backing Blizzard's own
-- pandemic frame is never touched, acquired or released.
--
-- Reads ns.mergeItemFrames[entry.cooldownID] only -- the cache CollectShownCooldownIDs already
-- populates (:497) -- and does nothing else to reach the frame: no EnumerateActive, no viewer
-- lookup, no C_CooldownViewer call. Called only through pcall(ReadPandemicState, entry) from
-- ns:RefreshMergeShownSlots, below.
local function ReadPandemicState(entry)
	local itemFrame = ns.mergeItemFrames[entry.cooldownID]
	if not itemFrame then
		-- No cached frame for this cooldownID this pass: a merged entry with no observable
		-- pandemic state. Clear all three stamps rather than leaving a stale `true` from a
		-- previous pass on the entry -- that stuck highlight is exactly what PAND-05 forbids.
		local wasActive = entry.pandemicActive == true
		entry.pandemicActive = false
		entry.pandemicStart = nil
		entry.pandemicFinish = nil
		entry.pandemicTrigger = nil
		LogPandemicStateChange(entry, wasActive, nil, nil)
		return
	end

	-- Primary signal (48-CONTEXT.md D-01): PandemicIcon is a frame REFERENCE, not a data
	-- field -- only numeric/string data on a frame can be secret-tainted, so there is nothing
	-- here for issecretvalue to catch. This whole function is pcall'd at its one call site
	-- below, so even a future client that made this read raise would degrade the feature
	-- rather than take the refresh pass down.
	local wasActive = entry.pandemicActive == true
	local nextActive = itemFrame.PandemicIcon ~= nil

	-- Refinement (D-01): the two timestamps, guarded issecretvalue() THEN type(), exactly as
	-- MergeMode.lua:650-656 guards aura.expirationTime/duration -- never the reverse. Stamped
	-- all-or-nothing: if either is unreadable, BOTH entry.pandemicStart and
	-- entry.pandemicFinish go nil, so no consumer can ever see a half window. No
	-- duration<=0-style sanity check here -- that belongs to aura-duration semantics and has
	-- no equivalent for a pandemic window.
	-- The single trigger timestamp, read alongside the pair. See ns:IsMergedEntryInPandemic for
	-- why: the live retail frame carries Get/SetPandemicAlertTriggerTime but no start/end pair,
	-- so this is the name the shipped methods actually imply. Same guard, same all-or-nothing
	-- staging as everything else here.
	local triggerTime = itemFrame.pandemicAlertTriggerTime
	local nextTrigger
	if not issecretvalue(triggerTime) and type(triggerTime) == "number" and triggerTime > 0 then
		nextTrigger = triggerTime
	end

	local startTime = itemFrame.pandemicStartTime
	local endTime = itemFrame.pandemicEndTime
	local nextStart, nextFinish
	if
		not issecretvalue(startTime)
		and type(startTime) == "number"
		and not issecretvalue(endTime)
		and type(endTime) == "number"
	then
		nextStart = startTime
		nextFinish = endTime
	end

	-- Phase 48 code review CR-01: all three fields are STAGED into locals above and committed
	-- together here, with no read of a CDM field between the first write and the last.
	--
	-- Writing entry.pandemicActive at the point it was read -- before the two timestamp reads --
	-- broke the all-or-nothing guarantee the comment above claims. The timestamp reads are the
	-- ones that can plausibly raise (they are the secret-tainted candidates, which is why they
	-- are guarded at all), and this whole function is pcall'd at its call site. So a raise
	-- between the two left entry.pandemicActive holding THIS pass's answer beside
	-- entry.pandemicStart/Finish holding the PREVIOUS pass's -- and because
	-- ns:IsMergedEntryInPandemic gives the numeric pair precedence over the boolean, a stale
	-- window could silently suppress a highlight Blizzard was actively showing, or hold one
	-- past its true end. That is the stuck highlight PAND-05 forbids, reached from the read side.
	--
	-- Committing together means a raise anywhere in this function leaves the entry exactly as
	-- the previous pass left it -- a coherent state, and the same one the absent-frame branch
	-- above already produces.
	entry.pandemicActive = nextActive
	entry.pandemicStart = nextStart
	entry.pandemicFinish = nextFinish
	entry.pandemicTrigger = nextTrigger

	-- Not gated on category, hideAura, engineOwns, isAuraCategory, equipSlot or
	-- spellCategoryID: Blizzard's own pandemic-trigger check short-circuits on IsItem() before
	-- it ever computes a window (CooldownViewer.lua:530), so item-backed entries structurally
	-- never carry the signal and need no filter here (PANDEMIC.md, "no filtering needed"). Do
	-- not add one back.

	LogPandemicStateChange(entry, wasActive, startTime, endTime)
end

-- Phase 48.1 (DISP-01/DISP-02/DISP-03) -- stamps entry.dispelAtlas, the dispel-type border
-- Blizzard is currently drawing on this entry's CDM item frame, or nil when it draws none.
--
-- WHY MIRROR AN ATLAS NAME RATHER THAN RESOLVE THE DISPEL TYPE.
-- The dispel type lives on aura data, and every route to it from a tainted addon is closed the
-- same way the aura DURATION routes were (:505-560 above): C_UnitAuras.GetAuraDispelTypeColor is
-- RequiresUnitAuraAccess -- the flag measured on 2026-09-22 to RAISE rather than degrade -- and it
-- keys off an auraInstanceID, which Blizzard holds in a DisallowTaintedAccess table. So TBT cannot
-- compute this value, in combat or out of it.
--
-- It does not need to. Blizzard's own UNTAINTED code already did the read and wrote the answer
-- onto a texture: CooldownViewerItemMixin:RefreshIconBorder calls DebuffBorder:UpdateFromAuraData,
-- which calls AuraUtil.SetAuraBorderAtlasFromAura, which Show()s the border and sets one of six
-- atlases from auraData.dispelName -- or Hide()s it when the aura is not harmful
-- (AuraUtil.lua:645-652). Reading the atlas name back is the same "Blizzard computes, TBT mirrors"
-- trade Phase 48 made for the pandemic window, and it holds up in combat for the same reason: the
-- computation happened on Blizzard's side of the taint line, not TBT's.
--
-- DEBUFF-ONLY IS INHERITED, NOT IMPLEMENTED. There is no isHarmful test here and there must not be
-- one: Blizzard's Show/Hide already encodes it, so a hidden border means "not a harmful aura" and
-- TBT draws nothing. A helpful aura carries a dispelName too -- that is what makes a buff
-- Spellstealable -- so adding a polarity test here would be the only way to start drawing one.
-- Matching Blizzard exactly was the user's decision, 2026-09-24.
--
-- Deliberately its own function with its own pcall at the call site rather than folded into
-- ReadPandemicState, for the reason ResolveMergedAuraTiming's call site already gives: one pcall
-- per concern, so a raise in either half stays distinguishable from the other.
local function ReadDispelBorder(entry)
	local itemFrame = ns.mergeItemFrames[entry.cooldownID]
	local border = itemFrame and itemFrame.DebuffBorder

	-- Two plain table-field reads (parentKey children, this file's header :5-25), then two plain C
	-- widget getters. No mixin method -- UpdateFromAuraData is precisely the mixin call the locked
	-- rule forbids, and it is never made here. Nothing is written onto the frame.
	--
	-- IsShown, NOT IsVisible: under Merge Mode TBT hides Blizzard's CDM containers, so the border's
	-- EFFECTIVE visibility is false for every merged entry on screen. IsShown reports the frame's
	-- own flag, which is what UpdateFromAuraData set and therefore what carries the answer.
	-- IsVisible here would silently mean "no entry ever has a border".
	--
	-- `border` is nil on any client whose CooldownViewer has no DebuffBorder -- Forever's 1.60.1
	-- CDM is the live candidate -- in which case nextAtlas stays nil and the feature degrades to
	-- exactly today's rendering (DISP-03), with no version check needed.
	-- TWO stamps, and the split is the whole point.
	--
	-- MEASURED, retail 2026-09-24, Moonfire as a bar in combat:
	--   dispel=unreadable(secret=true,type=string)  aura(dispelName=<secret>,harmful=<secret>)
	-- The atlas NAME is a secret string in combat, and so is dispelName on auraDataCached, so both
	-- mirror sources go dark together. Out of combat both read fine -- which is exactly why
	-- Entangling Roots bordered on a bar out of combat and nothing bordered in it. Same shape as
	-- Phase 48's pandemic timestamps, and the same lesson: one signal is not enough.
	--
	-- But the two halves of the answer do NOT have the same secrecy. `border:IsShown()` is a plain
	-- boolean in combat -- proven by that very log line, which could only have been printed from
	-- inside the branch this test guards. So WHETHER to draw is readable; only WHAT to draw is not.
	--
	-- So the atlas is stamped WITHOUT the issecretvalue/type filter that used to be here. That
	-- filter was correct for a value TBT reads and wrong for one it only relays: Texture:SetAtlas
	-- is SecretArguments = "AllowedWhenTainted", and `atlas` is the single parameter of the six not
	-- marked NeverSecret (SimpleTextureBaseAPIDocumentation.lua:366-377) -- Blizzard's explicit
	-- permission for a tainted caller to pass one through. ApplyDispelBorder therefore hands it
	-- straight to SetAtlas and never inspects it. Nothing downstream may branch on dispelAtlas;
	-- branch on dispelShown, which is what it is for.
	--
	-- A shown border always has a real atlas, so there is no secret-wrapping-nil case to defend
	-- against: SetAuraBorderAtlas falls back to DEBUFF_DISPLAY_INFO["None"].basicAtlas, which is
	-- never nil, and Blizzard sets it before Show()ing (AuraUtil.lua:609-613).
	local nextShown = false
	local nextAtlas
	if border and border.Texture and border:IsShown() then
		nextShown = true
		nextAtlas = border.Texture:GetAtlas()
	end

	-- Staged and committed together, the CR-01 discipline -- now that there are two fields, the
	-- guarantee has to be earned rather than being structural. A half-written pair would mean
	-- dispelShown true beside last pass's atlas.
	entry.dispelShown = nextShown
	entry.dispelAtlas = nextAtlas
end

-- Render-time resolver Display consumes (Plan 48-02): touches no frame, no API, allocates
-- nothing. D-01's precedence, not inverted: readable numbers win because they give the exact
-- window bounds, so the highlight can clear at the true end of the window on the render tick
-- (PAND-03) instead of inheriting Blizzard's own OnUpdate-deregistration lag (PANDEMIC.md
-- unknown 1); the boolean is the fallback, mirroring whatever Blizzard is currently drawing.
-- Both stamped numbers are already proven plain by ReadPandemicState above, and `now` is the
-- caller's own GetTime(), so neither needs a guard here -- do not add one, it would pay for
-- the hot path twice.
function ns:IsMergedEntryInPandemic(entry, now)
	if not entry then
		return false
	end

	if entry.pandemicStart and entry.pandemicFinish then
		return now >= entry.pandemicStart and now <= entry.pandemicFinish
	end

	-- entry.pandemicTrigger is deliberately NOT a route here, though it is read and stamped for
	-- the debug dump. Measured on retail 2026-09-24, Entangling Roots, out of combat:
	--
	--   window ACTIVE   icon=yes  trigger=nil       start=86547.021  finish=86556.021
	--   window PENDING  icon=no   trigger=86577.006 start=86577.006  finish=86586.006
	--
	-- So pandemicAlertTriggerTime is "the time this alert is SCHEDULED to fire", consumed and
	-- nil'd once it does -- which is what PANDEMIC.md's OnUpdate-deregistration note was
	-- describing. It is not the window start, and it is present exactly when the window is NOT
	-- yet active.
	--
	-- Using it as a fallback was a guess made while no window had ever been observed, and it was
	-- wrong twice over: it would read true for a window that has not started, and `now >= trigger`
	-- has no upper bound, so it would latch on forever if the pair were ever absent -- the stuck
	-- highlight PAND-05 exists to forbid. The pair and the icon are both measured working, so
	-- there is nothing for a third route to add.
	return entry.pandemicActive == true
end

-- Rebuilds ns.mergeShownSlots from the CDM's live per-item shown flags. Event-driven only,
-- exactly like ns:RefreshMergeMirror -- never called from ns:UpdateDisplay or any OnUpdate.
-- Allocates nothing per pass beyond the iterator closure SecureMap:Enumerate returns: the
-- outer arrays and the join set are module-level and wiped.
function ns:RefreshMergeShownSlots()
	for _, list in pairs(ns.mergeShownSlots) do
		wipe(list)
	end

	-- Wiped once per pass, not per viewer: a frame that stopped being shown must stop being
	-- reachable, and Merge Mode being off must leave nothing behind for Display to relay from.
	wipe(ns.mergeItemFrames)

	if not ns.db or ns.db.mergeMode ~= true then
		return
	end

	for _, def in ipairs(ns.CONTAINERS) do
		local slots = ns.mergeSlots[def.key]
		local shown = ns.mergeShownSlots[def.key]

		-- Tracked Buffs the engine is drawing are still published, and must be: Display needs the
		-- entry to size the container for it and to work out which grid cell its aura belongs in.
		-- It does not DRAW them -- see the placed branch in RenderIconContainer -- so nothing is
		-- drawn twice.
		--
		-- Withholding them was the earlier fix for exactly that double-draw, and it cost the
		-- container its width; placing without drawing is the correct half of that trade.
		local engineOwns = ns.mergeAuraGroupsActive and def.cdmCategoryName == "TrackedBuff"

		if slots and shown and #slots > 0 then
			wipe(shownCooldownIDs)

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
			-- An engine-owned category also publishes everything configured, so the container is
			-- sized for every entry and its footprint never shifts as buffs come and go. It does
			-- NOT throw the shown flags away though: each entry is stamped with its own, below,
			-- because a centred run has to know which merged auras are actually up to close the
			-- gaps and re-centre. The count comes from Blizzard's own item frames, which is the
			-- one place it is a plain readable boolean rather than a secret.
			local seen = 0
			local viewer = not ns:IsMergePreviewState() and def.cdmViewerGlobal and _G[def.cdmViewerGlobal]
			if viewer then
				-- pcall'd for the same reason EachViewer is: this is a call into a Blizzard
				-- container on a frame TBT does not own, and degrading to the unfiltered mirror
				-- beats taking down the render.
				local ok, count = pcall(CollectShownCooldownIDs, viewer)
				if ok and not issecretvalue(count) and type(count) == "number" then
					seen = count
				end
			end

			-- Which categories need an aura expiry resolved here.
			--
			-- Tracked Buffs, unless the engine already owns them: it drives its own Cooldown
			-- widget off the real duration object, so an expiry resolved here would be read by
			-- nobody.
			--
			-- Essential and Utility TOO, as of Phase 43.1. They do get a real cooldown handle
			-- through ApplyCooldownSlot, but a cooldown that applies a buff must show the BUFF's
			-- remaining time while it is up and only fall back to the cooldown once it drops.
			-- Blizzard does exactly that in CheckCacheCooldownValuesFromAura
			-- (CooldownViewer.lua:861-906), which runs AFTER the spell-cooldown pass and
			-- overwrites what it cached. Without this a defensive like a shield showed its
			-- cooldown, greyed, for the whole time it was actually up.
			--
			-- Tracked Bars still need nothing: RelayMergedBar drives them straight off the CDM's
			-- own StatusBar values.
			-- ...and ONLY when the engine is not drawing them, which as of Phase 43.1 is all
			-- three categories rather than Tracked Buffs alone. Two owners for one cell is what
			-- this test prevents: where the engine draws the aura, an expiry resolved here would
			-- be read by nobody, and the two lookups per entry per aura event would be spent for
			-- nothing. The read path survives as the fallback for a client where the engine path
			-- latched off, and as the out-of-combat nicety it has always been.
			local isAuraCategory = not ns.mergeAuraGroupsActive
				and (
					def.cdmCategoryName == "TrackedBuff"
					or def.cdmCategoryName == "Essential"
					or def.cdmCategoryName == "Utility"
				)

			for _, entry in ipairs(slots) do
				-- Stamped on EVERY entry, published or not: Display reads it to decide whether a
				-- merged aura takes a cell in a centred run. "seen == 0" is the no-answer case --
				-- no viewer, or a viewer with no item frames -- and there everything counts as
				-- shown, exactly as the publish filter below treats it.
				entry.cdmShown = (seen == 0) or (shownCooldownIDs[entry.cooldownID] == true)

				-- pcall'd for the same structural reason as pcall(ResolveMergedAuraTiming, entry)
				-- below, not because a specific raise is expected from a frame-reference read:
				-- this pass wipes the shown-slot arrays before refilling them, so ANY raise
				-- partway through leaves every merged container empty until the next aura event
				-- -- exactly what the GetAuraDataByIndex raise did on 2026-09-22. Deliberately
				-- its own pcall rather than folded into ResolveMergedAuraTiming's: that one's
				-- scope is aura-timing resolution, and widening it would make a raise in either
				-- half indistinguishable. Unconditional, for every entry, exactly as
				-- entry.cdmShown above -- not gated behind the publish branch below.
				pcall(ReadPandemicState, entry)

				-- Phase 48.1 (DISP-01): same placement and same reasoning as the pandemic read
				-- above -- unconditional for every entry, ahead of the publish branch, in its own
				-- pcall so a raise here cannot be mistaken for one in pandemic state. An entry
				-- whose frame has gone is cleared rather than left holding the previous pass's
				-- atlas, which is the stuck-border twin of what PAND-05 forbids (DISP-03).
				pcall(ReadDispelBorder, entry)

				if engineOwns or seen == 0 or shownCooldownIDs[entry.cooldownID] then
					-- entry.hideAura is Blizzard's CanUseAuraForDisplay, stamped at mirror-build
					-- time: an entry flagged HideAura keeps its cooldown and never swaps to its
					-- aura, and skipping it here means two fewer aura lookups per event as well.
					if isAuraCategory and not entry.hideAura then
						-- pcall'd as a structural guarantee, not because a specific raise is
						-- expected: everything inside is already guarded. This pass wipes the
						-- shown-slot arrays before refilling them, so ANY raise partway through
						-- leaves every merged container empty until the next aura event -- which
						-- is exactly what the GetAuraDataByIndex raise did on 2026-09-22. The
						-- sweep is a nicety; the containers rendering is not.
						pcall(ResolveMergedAuraTiming, entry)
					end
					shown[#shown + 1] = entry
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Phase 40 -- ENGINE-DRIVEN SWEEPS for merged Tracked Buff auras.
--
-- Every attempt to give a merged buff icon a cooldown swipe by READING the aura failed, and the
-- reason it failed is structural rather than incidental. The CDM's own Cooldown returns secrets
-- from every getter; the numeric Cooldown setters are AllowedWhenUntainted; the aura instance
-- IDs that would unlock C_UnitAuras.GetAuraDuration sit behind DisallowTaintedAccess; and the
-- plain aura reads work out of combat and are denied the moment a fight starts, which is the one
-- time the sweep matters. A read-based sweep was never going to work.
--
-- The supported route is the opposite shape: do not read the aura and draw it -- hand Blizzard
-- widgets and let the ENGINE draw. An AuraContainer is given a unit and a filter, and creates
-- aura frames on its own. Inside the one window where addon code may touch such a frame, TBT
-- creates an icon Texture and a Cooldown as children of it and registers them through
-- CustomAuraButtonSharedMixin:SetIcon / :SetDurationCooldown. The engine then binds the real
-- duration object to that Cooldown (it calls AddSecretAspect(Enum.SecretAspect.Cooldown) on it),
-- shows the frame only while the aura is up, and lays the visible ones out itself. Secrecy never
-- enters into it, because TBT never sees a value.
--
-- Constraints that shape everything below, all of them Blizzard's:
--   * Widgets handed over MUST be descendants of the aura frame
--     (AuraContainerUtil.ValidateInboundScriptObject -> RegionUtil.IsDescendantOf), so they are
--     created inside initializeFrame and nowhere else.
--   * The frames carry DenyTaintedAccessWhenAurasAreSecret
--     (CustomAuraContainerConstants.AccessRestrictionFlags, applied post-creation to every frame
--     the engine makes), so TBT must not touch one after creation -- no SetPoint, no Show, no
--     reads -- and least of all once a fight is on, which is the only time it would matter. So
--     TBT anchors the CONTAINER and never the frame: each container is given exactly one
--     AddAuraSlot, its frame pinned at the container's own origin inside initializeFrame and
--     never touched again, and moving the container moves the aura with it.
--   * No aura GROUP is ever added, so the container never gains UntrustedLayoutScriptExecution
--     and TBT stays free to place it. DisableUntrustedLayoutScriptsTemplate is kept anyway:
--     leaving it out is what broke this once already, back when the containers were chained to
--     one another, and opting out of untrusted layout costs nothing.
--
-- Two units per entry, because a CDM "tracked buff" is as often a debuff on the player's target
-- as a buff on the player and nothing says which in advance. Both are filtered to the same
-- spell-ID set. For the container shape itself -- one per merged entry per unit, and why that is
-- load-bearing rather than redundant -- see the block above auraContainers. That is the
-- authoritative statement; a second statement of it here is what drifted in the first place.
---------------------------------------------------------------------

-- The aura slot every merged container carries, named here because the filter helper below
-- needs it. Declared ABOVE that helper on purpose: a file-local is only an upvalue to functions
-- defined after it, and this file has produced that bug before.
local AURA_SLOT_KEY = "tbtMerged"

-- fromPlayerOnly on the target entry is load-bearing, and the reason is Blizzard's, not a
-- preference. AuraContainerUtil.DoesAuraPassCandidateFilters applies includeSpellIDs and
-- excludeSpellIDs ONLY when CanApplyIdentityCandidateFilters says it may, and that returns false
-- for `auraData.isHarmful and UnitCanAssist("player", unitToken)` -- a harmful aura on a friendly
-- unit (Blizzard_AuraContainerUtil.lua:11-36). Their comment says why: they will not let an addon
-- filter encounter debuffs on friendly units by spell ID, because that would allow "Move now!"
-- displays.
--
-- The consequence for this container is total. With a friendly target -- a healer's normal state
-- -- every debuff landing on that unit skips the spell-ID filter and matches EVERY entry, so one
-- raid debuff paints itself and its duration across every merged tile at once. Reported on a
-- resto druid 2026-09-22; a mage targeting enemies never saw it, because an enemy is not
-- assistable and the filter works there.
--
-- isFromPlayerOrPlayerPet is evaluated OUTSIDE that gate, unconditionally (:85-87), so it holds
-- where the spell-ID filter does not. It also says exactly what this container is for: debuffs
-- the PLAYER applied to their target. A boss debuff on a friendly unit is not from the player.
--
-- Not added to the player entry, which wants buffs from anyone -- a lust, an external cooldown.
-- That entry needs no such guard: a helpful aura on an assistable unit passes the gate, so its
-- spell-ID filter works normally.
local AURA_UNITS = {
	{ unit = "player", filter = "HELPFUL" },
	{ unit = "target", filter = "HARMFUL", fromPlayerOnly = true },
}

-- One reusable candidate-filter table per unit, rather than a constructor at each call site:
-- filters are re-sent for every entry on every configuration change, and SetAuraSlotCandidateFilters
-- securecopy()s what it is given, so TBT is free to keep and rewrite its own.
local candidateFilterByUnit = {}
for i = 1, #AURA_UNITS do
	candidateFilterByUnit[AURA_UNITS[i].unit] = { isFromPlayerOrPlayerPet = AURA_UNITS[i].fromPlayerOnly }
end

-- Send one slot's filters, and answer whether it took.
--
-- `active` false means "match nothing", and that CANNOT be expressed by an empty includeSpellIDs
-- -- which is what this file used to do, in DisableAuraGroups and for a hideAura entry. An empty
-- include set is skipped along with every other identity filter for a harmful aura on a friendly
-- unit, so it disables nothing there. maxDuration = 0 is evaluated unconditionally and rejects
-- every aura including permanent ones ("Max duration filters implicitly always filter out
-- permanent auras", Blizzard_AuraContainerUtil.lua:101-106), so it is the one reliable off switch.
-- Handed to a slot being switched off, so the caller never has to build one. Never written to.
local EMPTY_INCLUDE_SET = {}

-- WHY THE GATE IS THE ANSWER AND NOT A PATCH -- settled 2026-09-22, after this was removed
-- entirely and had to come back.
--
-- The first instinct, and a reasonable one, is that TBT should not be deciding which auras
-- belong to a slot: it should ask the CDM about each slot and draw what it says. That route was
-- checked and it is closed. Every Cooldown getter on a CDM item frame is
-- SecretReturnsForAspect = { Cooldown }, and every Cooldown setter -- SetCooldown,
-- SetCooldownDuration, SetCooldownFromExpirationTime -- is SecretArguments =
-- "AllowedWhenUntainted" (FrameAPICooldownDocumentation.lua), so a tainted caller can neither
-- read the value nor pass it on. There is no duration-object getter to relay either. The
-- merged BAR relay works only because StatusBar's setters are AllowedWhenTainted; icons have no
-- equivalent. So asking the CDM per slot is not an option that was overlooked -- it does not
-- exist.
--
-- That leaves the engine's own filtered container, and its one restriction is NARROW and exactly
-- known: identity filters are refused for a harmful aura on an ASSISTABLE unit
-- (Blizzard_AuraContainerUtil.lua:11-36). On a hostile target the filter works perfectly, and
-- matches what the CDM itself does -- Blizzard's FindLinkedSpellForCurrentAuras likewise only
-- accepts an aura whose sourceUnit is the player.
--
-- So the gate is not TBT second-guessing the CDM. It is TBT declining to ask a question Blizzard
-- refuses to answer correctly, and the window where it declines -- a friendly or self target --
-- is exactly the window where no enemy debuff could be relevant anyway. Removing the container
-- outright instead cost Moonfire, a debuff the CDM tracks in Tracked Buffs, and that was the
-- wrong trade.
--
-- A CDM "tracked buff" is not always a buff. Touch of the Magi, a warlock's dots, any
-- debuff-based tracker: the thing whose duration the CDM shows sits on the player's TARGET, not
-- on the player. That is the whole job of the target container, and for a spec that has one it
-- is the only way the duration can be drawn.
--
-- It is also the only part of this feature that can misbehave, because of the rule in AURA_UNITS
-- above: on an ASSISTABLE unit, a harmful aura cannot be filtered by spell ID at all, so every
-- debuff there matches every entry. isFromPlayerOrPlayerPet narrows that to debuffs the player
-- applied -- and a self-inflicted debuff IS applied by the player, so it walks straight through
-- and floods the containers exactly as a boss debuff did. Reported 2026-09-22, after the first
-- fix.
--
-- There is no candidate filter that can express "only this spell" on a friendly unit; Blizzard
-- has deliberately closed that door. So the only correct answer is to switch the target
-- container OFF whenever the target is one TBT cannot filter on, and take the feature back the
-- moment a hostile target makes it safe again.
--
-- UnitCanAssist is a plain unit API, and the question is asked on a target change rather than
-- per frame -- PLAYER_TARGET_CHANGED already drives this file. No target at all counts as safe:
-- there are no target auras to match.
local targetIsAssistable = false

local function RefreshTargetAssistable()
	local assistable = false
	if UnitExists and UnitCanAssist and UnitExists("target") then
		local ok, canAssist = pcall(UnitCanAssist, "player", "target")
		if ok and not issecretvalue(canAssist) and canAssist then
			assistable = true
		end
	end

	local changed = assistable ~= targetIsAssistable
	targetIsAssistable = assistable
	return changed
end

-- Whether this unit's slot may be live at all right now, independent of what the entry wants.
-- Only the target slot ever answers false, and only while the target is assistable.
local function SlotAllowed(spec)
	return not (spec.fromPlayerOnly and targetIsAssistable)
end

local function SendSlotFilters(container, unit, includeSet, active)
	local filters = candidateFilterByUnit[unit]
	filters.includeSpellIDs = includeSet
	filters.maxDuration = (not active) and 0 or nil
	return pcall(container.SetAuraSlotCandidateFilters, container, AURA_SLOT_KEY, filters)
end
local AURA_ICON_SIZE = 40

-- True while the CDM settings window is open, which is the one state the engine path cannot
-- serve. An aura group shows auras that are genuinely on the unit and nothing else -- there is no
-- "show me everything configured" mode, because the frames are bound to real auras. But the CDM
-- previews every configured entry while its settings window is open, and TBT has to do the same
-- or the player is configuring against an empty container.
--
-- So the engine path stands down for the duration: the filter empties, ns.mergeAuraGroupsActive
-- goes false, and TBT's own rendering resumes and draws every configured entry as a placeholder.
-- Preview without sweeps, which is exactly what the CDM itself shows.
-- Un-suppression state, deliberately independent of TBT's own "Edit Mode active" flag in
-- EditModeFrames.lua: that flag is set to false when the user unticks TBT inside the Edit Mode
-- panel, which is not the same thing as Edit Mode being closed. (The flag is named by description
-- rather than by identifier so the STEAL-08 audit grep for it stays a true negative in this file.)
--
-- Declared HERE, above ns:RefreshMergeAuraGroups, rather than down beside the placement code that
-- was its only original reader: the engine aura path needs it too, and a file-local is only an
-- upvalue to functions defined after it.
local editModeOpen = false

-- QUERIED LIVE, NEVER LATCHED, and that is the whole point.
--
-- The first version of this kept a cdmSettingsOpen boolean set on the settings window's OnShow
-- and cleared on its OnHide. A latched flag is only ever as good as the edge that clears it, and
-- the failure is silent and total: one missed OnHide and the engine path is switched off for the
-- rest of the session with nothing to show for it but "the sweeps stopped working". That is what
-- happened. Asking the frames what they are doing right now cannot get stuck.
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
	-- The mirror rebuild refreshes the aura groups and queues the shown pass, so one call puts
	-- both the engine side and the TBT side into the right state for the new mode.
	ns:QueueMergeMirror()
end

-- unit -> cooldownID -> AuraContainer. ONE CONTAINER PER MERGED ENTRY PER UNIT, which is what
-- makes a layout that MOVES possible at all.
--
-- The obvious shape is one container per unit holding a slot per entry, and that is what this was.
-- It works for a grid that never moves and cannot work for one that does: an aura frame carries
-- DenyTaintedAccessWhenAurasAreSecret (CustomAuraContainerConstants.AccessRestrictionFlags,
-- applied post-creation to every frame the engine makes), so TBT may not SetPoint one while a
-- fight is on -- which is exactly when a centred run needs to re-centre.
--
-- The CONTAINER carries no such restriction. TBT creates it with CreateFrame and owns it, and no
-- aura GROUP is ever added, so it never gains UntrustedLayoutScriptExecution either. So the rule
-- here is simply: TBT moves containers, never frames. Each container holds exactly one slot pinned
-- at its own origin and never touched again, and moving the container moves the aura with it.
--
-- Two units per entry because a CDM tracked buff may be a buff on the player or a debuff on the
-- target and nothing says which in advance. At most one of a pair ever has a visible aura; the
-- other draws nothing and costs one idle frame.
local auraContainers = {}

local EMPTY_ENTRIES = {}

-- Which TBT containers get engine-drawn auras, by container key.
--
-- Tracked Buffs was the original and only member. Essential and Utility joined in Phase 43.1,
-- for a reason the "/tbt merge" diagnostic settled rather than a guess: mid-combat on retail,
-- EVERY merged slot reported aura=unresolved. The read-based route -- ask C_UnitAuras, get an
-- expiry, draw it -- does not work for a tainted caller in combat, which is the only time a
-- cooldown's buff duration is worth showing. So "show the buff's remaining time before the
-- cooldown" could not be delivered by reading, however carefully.
--
-- The engine route already works and is already proven here: hand Blizzard the widgets and let
-- it draw. The difference for a cooldown container is that the aura frame OVERLAYS TBT's own
-- icon instead of replacing it -- the icon underneath keeps showing the spell's cooldown, and
-- the engine covers it with the aura for exactly as long as the aura is up. That is the same
-- two-sources-one-cell effect Blizzard gets by switching its item between them, arrived at
-- without TBT reading either.
local AURA_HOST_KEYS = { "buffs", "essential", "utility" }

-- cooldownID -> the include set handed to that entry's slots. One table per entry, reused and
-- wiped rather than rebuilt, since a filter is re-sent on every configuration change. Each set
-- holds the entry's own spell ID plus its linked aura IDs, which is what makes an entry like
-- Frostbolt resolvable at all, since the aura it displays is Chilled.
local slotFilters = {}

-- cooldownID -> the placement last issued, as four separate values rather than a packed key: the
-- render path runs at 20 Hz and must not allocate a string per merged entry per tick to find out
-- that nothing moved.
local placedAnchor, placedX, placedY, placedScale = {}, {}, {}, {}
-- ...and which container it was placed against, because an entry can move between categories.
local placedHost = {}

-- Set false the first time anything here fails, and never retried. This path is a bonus on top of
-- a display that already works without it; it must never cost more than one failed attempt.
local auraGroupsUsable = true

-- True once every merged entry has its containers and its filter. While it is true the engine
-- DRAWS the merged Tracked Buffs and TBT only places them -- see the reserved branch in
-- RenderIconContainer, which consumes the grid cell and hands it here without drawing an icon.
-- It stays false on any client where the setup failed, and there the existing TBT rendering
-- carries on exactly as before.
ns.mergeAuraGroupsActive = false

-- The one window in which addon code may touch an engine aura frame. Everything TBT wants the
-- engine to drive is created here, as a child of the frame, and registered before returning.
local function InitializeAuraFrame(frame)
	frame:SetSize(AURA_ICON_SIZE, AURA_ICON_SIZE)

	-- Pinned to its container's origin, once, and never moved again -- the container is the thing
	-- that moves. Unscaled for the same reason: the container carries the scale, so this frame
	-- inherits it exactly as a TBT icon's children inherit the icon's.
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", 0, 0)

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(frame)
	frame:SetIcon(icon)

	-- Same construction as TBT's own pooled icons in Display.lua, so a merged aura looks like
	-- every other TBT icon: CDM mask, CDM overlay, CDM swipe texture and colour, reverse sweep.
	local mask = frame:CreateMaskTexture()
	mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
	mask:SetAllPoints(frame)
	icon:AddMaskTexture(mask)

	local overlay = frame:CreateTexture(nil, "OVERLAY")
	overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
	overlay:SetPoint("TOPLEFT", -8, 7)
	overlay:SetPoint("BOTTOMRIGHT", 8, -7)

	local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	cooldown:SetReverse(true)
	cooldown:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	cooldown:SetSwipeColor(0, 0, 0, 0.7)
	cooldown:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
	cooldown:SetDrawEdge(true)
	cooldown:SetDrawSwipe(true)
	frame:SetDurationCooldown(cooldown)

	-- The stack count, drawn by the ENGINE exactly as the icon and the sweep above are. All TBT
	-- does is register a FontString; CustomAuraButtonPrivateMixin:ApplyApplicationCount fills it
	-- (Blizzard_CustomAuraButton.lua:351-370) and applies the same "only when applications > 1"
	-- rule Blizzard's own buff icons use (CooldownViewer.lua:1372-1378, GetApplicationsText).
	-- SetApplicationCount adds the Text and Shown secret aspects to the FontString itself, so
	-- TBT never sees the number and no secrecy question arises -- the same reason the icon and
	-- the sweep work.
	--
	-- NumberFontNormal anchored BOTTOMRIGHT at -2, 2 is the CDM's own Applications font string
	-- (CooldownViewer.xml:195-204), so a merged stack count sits where an unmerged one does.
	--
	-- pcall'd on its own rather than left to the caller's: SyncEntryContainers treats ANY raise
	-- from frame setup as "latch the whole engine path off", and a missing stack number is not
	-- worth losing merged sweeps over. A client whose aura button mixin predates
	-- SetApplicationCount keeps the icon and the sweep and simply shows no stacks.
	if frame.SetApplicationCount then
		local applications = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		applications:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
		pcall(frame.SetApplicationCount, frame, applications)
	end

	-- Phase 48.1 (DISP-01), and the ONLY route that works for an ordinary merged tracked buff.
	--
	-- The atlas mirror in ReadDispelBorder cannot reach this case, and the reason is structural
	-- rather than a bug in it: RenderIconContainer HIDES TBT's own pooled icon for a merged
	-- tracked buff whenever the engine draws that aura (Display.lua, the engineDrawsHere branch's
	-- icon:Hide()), so a border drawn on the pooled icon is a border on a hidden frame. That is
	-- the same hidden-parent hazard EnsurePandemicIconFX already documents and dodges by
	-- parenting to the container. Here there is something better available than dodging it.
	--
	-- The engine draws this one too. An aura button takes a dispel-type texture and fills it from
	-- the same AuraUtil.SetAuraBorderAtlas the CDM's own DebuffBorder uses
	-- (Blizzard_CustomAuraButton.lua:437-443), so TBT registers a texture and reads nothing --
	-- exactly the trade SetApplicationCount above makes for the stack count, and for the same
	-- reason: the values stay on Blizzard's side of the taint line.
	--
	-- THE OPTIONS ARE CHOSEN TO REPRODUCE THE CDM'S OWN RULE, NOT TO RESTATE THE DEFAULTS.
	--
	-- An earlier version of this comment claimed all three relevant defaults already matched and
	-- that passing any of them would be noise. That was wrong on one, and the mismatch was real:
	--
	--   CDM      (AuraUtil.lua:645-652)  show iff auraData.isHarmful -- full stop. A harmful aura
	--                                    with NO dispel type still shows, on
	--                                    DEBUFF_DISPLAY_INFO["None"].basicAtlas, the grey default.
	--   Engine   (Blizzard_CustomAuraButton.lua:372-384, with defaults) hides exactly that case,
	--                                    because showWithoutDispelType defaults to false.
	--
	-- So a harmful, undispellable debuff bordered grey on an unmerged CDM tile and nothing at all
	-- on TBT's merged one. showWithoutDispelType = true is what closes that, and it is passed
	-- BECAUSE it differs from the default, not to restate one.
	--
	-- The other two are left implicit because they genuinely do match: showWhenHarmful defaults
	-- true and showWhenHelpful defaults false, which is the CDM's isHarmful test exactly. That is
	-- still the DISP-04 distinction -- debuff-only stays inherited from Blizzard rather than
	-- reimplemented here; only the no-dispel-type case had to be steered back onto the CDM's
	-- answer. User's rule, 2026-09-24: show whatever atlas the CDM shows, and only when the CDM
	-- says it should be shown.
	--
	-- Border, not the BorderWithIcon default: the CDM calls SetAuraBorderAtlasFromAura with no
	-- showDispelType argument, which selects basicAtlas -- the plain border with no corner symbol
	-- (AuraUtil.lua:609-613). Matching the unmerged tile is the whole point.
	--
	-- Hosted on a child frame created after the Cooldown rather than as a bare OVERLAY texture on
	-- `frame`, for the reason Display.lua's own dispelBorder records: a sibling child created
	-- later draws above the swipe, an OVERLAY texture on the parent draws beneath it. The host is
	-- still a descendant of `frame`, which is what AddDispelTypeTexture's
	-- ValidateInboundScriptObject requires.
	--
	-- pcall'd on its own exactly as the stack count is, and guarded on both the method and the
	-- enum: SyncEntryContainers treats any raise from frame setup as "latch the whole engine path
	-- off", and a missing border is not worth losing every merged sweep over. A client without
	-- either -- Forever 1.60.1 is the candidate -- keeps the icon, the sweep and the stacks.
	if frame.AddDispelTypeTexture and Enum and Enum.CustomAuraButtonDispelTypeTextureStyle then
		local borderHost = CreateFrame("Frame", nil, frame)
		borderHost:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
		borderHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)

		local dispelBorder = borderHost:CreateTexture(nil, "ARTWORK")
		dispelBorder:SetAllPoints()

		-- Stamped rather than discarded, because this call failing is INVISIBLE otherwise: a
		-- border that never appears looks identical whether the texture was rejected here or the
		-- aura simply is not dispellable. "/tbt merge" prints this, so one dump separates them.
		local ok = pcall(frame.AddDispelTypeTexture, frame, dispelBorder, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.Border,
			showWithoutDispelType = true,
		})
		ns.mergeDispelTextureState = ok and "ok" or "rejected"
	else
		ns.mergeDispelTextureState = "unsupported"
	end
end

-- Latch the engine path off AND leave nothing of it on screen.
--
-- Switching the flag alone was not enough. A failure part-way through setup could leave some
-- containers already built and already filtered, so they went on drawing auras while
-- ns.mergeAuraGroupsActive went false and TBT resumed drawing the same auras itself -- every
-- merged buff twice. Emptying every filter first makes the survivors match nothing, so the
-- handover back to TBT is clean whatever stage the failure happened at.
local function DisableAuraGroups()
	auraGroupsUsable = false
	ns.mergeAuraGroupsActive = false

	for _, includeSet in pairs(slotFilters) do
		wipe(includeSet)
	end

	for unit, byID in pairs(auraContainers) do
		for _, container in pairs(byID) do
			if container.SetAuraSlotCandidateFilters then
				-- active = false, which sends maxDuration = 0. Emptying includeSpellIDs alone --
				-- what this used to do -- does not disable a target container at all while the
				-- player has a friendly target, because identity filters are skipped for harmful
				-- auras there. A latch that does not actually latch is worse than none.
				SendSlotFilters(container, unit, EMPTY_INCLUDE_SET, false)
			end
		end
	end
end

-- Creates the container pair for one entry the first time it is seen, and re-filters it on every
-- later pass. Returns false on any failure, which latches the whole feature off.
local function SyncEntryContainers(host, entry, enabled)
	local id = entry.cooldownID

	local includeSet = slotFilters[id]
	if includeSet == nil then
		includeSet = {}
		slotFilters[id] = includeSet
	end
	wipe(includeSet)
	-- entry.hideAura is Blizzard's CanUseAuraForDisplay (CooldownViewerItemData.lua:747-754), and
	-- it has to be honoured HERE as well as in the read path, which is where it was first applied
	-- and where alone it was not enough. An entry carrying the flag must keep showing its
	-- cooldown and never swap to its aura, and once the engine started drawing these containers
	-- it would happily have overlaid one -- Wild Growth and Ironbark both carry the flag, and
	-- both apply their aura to an ally rather than to the caster, which is why Blizzard sets it.
	--
	-- An empty include set is how a slot is told to match nothing; it is the same mechanism
	-- DisableAuraGroups uses. So the container still exists and still occupies its cell, it
	-- simply never has an aura to draw, and TBT's cooldown icon shows through undisturbed.
	if enabled and not entry.hideAura then
		if type(entry.spellID) == "number" then
			includeSet[entry.spellID] = true
		end
		local linked = entry.linkedSpellIDs
		if linked then
			for j = 1, #linked do
				includeSet[linked[j]] = true
			end
		end

		-- A generic item cooldown -- the CDM's "Combat Potion" tile -- names no spell of its own,
		-- and an aura slot can ONLY be filtered by spell ID: candidateFilters offers spell IDs,
		-- dispel types, durations and booleans, and no category filter at all
		-- (Blizzard_CustomAuraContainer.lua:72-138). So an entry that arrives here with nothing
		-- in its include set can never show an aura, however long its buff is up -- which is
		-- exactly what was reported for the Blizzard potion buff.
		--
		-- TBT already keeps the list the CDM will not give: POT_SPELLS, the combat-potion buff
		-- IDs the pot meta-tracker fires on. Seeding from it is using TBT's own data for an entry
		-- that is about precisely those potions.
		--
		-- Only when the set is otherwise EMPTY. Where Blizzard has named the auras itself, its
		-- list is the authority and broadening it would show a potion buff on a tile the player
		-- configured for something narrower.
		if next(includeSet) == nil and entry.spellCategoryID == ns.SPELL_CATEGORY_COMBAT_POTION and ns.POT_SPELLS then
			for potSpellID in pairs(ns.POT_SPELLS) do
				includeSet[potSpellID] = true
			end
		end
	end

	-- Everything above either filled the include set or deliberately left it empty -- Merge Mode
	-- off, the entry gone from the configuration, or hideAura. One test covers all of them, and
	-- it is what decides between a live filter and the maxDuration off switch.
	local active = next(includeSet) ~= nil

	for i = 1, #AURA_UNITS do
		local spec = AURA_UNITS[i]
		local byID = auraContainers[spec.unit]
		if byID == nil then
			byID = {}
			auraContainers[spec.unit] = byID
		end

		local container = byID[id]
		if container then
			if not SendSlotFilters(container, spec.unit, includeSet, active and SlotAllowed(spec)) then
				return false
			end

			-- A CDM entry can be moved between categories by the player, and its container was
			-- parented to whichever TBT container it lived in when it was first seen. Re-parent
			-- rather than rebuild -- an aura slot cannot be removed from a container, so the old
			-- one has to be kept and reused. TBT owns this frame, so SetParent on it is
			-- unprotected and legal in combat; the engine's aura frame inside is not touched.
			if container:GetParent() ~= host then
				pcall(container.SetParent, container, host)
				pcall(container.SetFrameLevel, container, host:GetFrameLevel() + 10)
				-- Force the next render to re-place it: the placement stamp still holds the cell
				-- it had under its previous parent.
				placedAnchor[id] = nil
			end
		else
			-- pcall'd as one unit: on a client without the frame type, the template, or any of
			-- the mixin methods, this whole feature switches off and the existing rendering
			-- carries on untouched.
			--
			-- DisableUntrustedLayoutScriptsTemplate is kept although no group is added and so
			-- nothing applies UntrustedLayoutScriptExecution today. Leaving it out is what broke
			-- this once already, when the containers were chained to one another, and a container
			-- that opts out of untrusted layout costs nothing.
			local ok, created = pcall(
				CreateFrame,
				"AuraContainer",
				nil,
				host,
				"CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate"
			)
			if not ok or not created or not created.SetUnit or not created.AddAuraSlot then
				return false
			end

			local setupOk = pcall(function()
				created:SetUnit(spec.unit)
				created:SetSize(AURA_ICON_SIZE, AURA_ICON_SIZE)
				created:ClearAllPoints()
				created:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
				local live = active and SlotAllowed(spec)
				local filters = candidateFilterByUnit[spec.unit]
				filters.includeSpellIDs = includeSet
				filters.maxDuration = (not live) and 0 or nil
				created:AddAuraSlot(AURA_SLOT_KEY, spec.filter, {
					initializeFrame = InitializeAuraFrame,
					candidateFilters = filters,
				})
			end)

			if not setupOk then
				return false
			end

			-- Above the pooled icons, which are children of the same host at the default level.
			-- On a Tracked Buffs container nothing is drawn underneath and this is harmless; on a
			-- cooldown container it is what makes the overlay an overlay.
			pcall(created.SetFrameLevel, created, host:GetFrameLevel() + 10)

			byID[id] = created
			-- Force the first placement: a container created this pass has never been positioned,
			-- and the render path only issues a SetPoint when the cell CHANGES.
			placedAnchor[id] = nil
		end
	end

	return true
end

function ns:RefreshMergeAuraGroups()
	if not auraGroupsUsable then
		return
	end

	-- Before any filter is built: SlotAllowed reads it, and a pass that ran with a stale answer
	-- would leave the target slot live against a friendly unit.
	RefreshTargetAssistable()

	local enabled = ns.db ~= nil and ns.db.mergeMode == true and not ns:IsMergePreviewState()

	-- An entry that left the CDM configuration keeps its containers -- there is no way to remove
	-- an aura slot -- and has its filter emptied instead, which makes it match nothing. Wiping
	-- every set first and refilling only the live ones does that without a second pass or a
	-- difference to compute.
	for _, includeSet in pairs(slotFilters) do
		wipe(includeSet)
	end

	local ok = true
	for h = 1, #AURA_HOST_KEYS do
		local key = AURA_HOST_KEYS[h]
		local host = ns.containers and ns.containers[key]
		local entries = (ns.mergeSlots and ns.mergeSlots[key]) or EMPTY_ENTRIES

		-- A host that does not exist yet is skipped rather than failing the pass: containers are
		-- built on PLAYER_ENTERING_WORLD and this can run before that on a reload.
		if host then
			for i = 1, #entries do
				if not SyncEntryContainers(host, entries[i], enabled) then
					ok = false
					break
				end
			end
		end

		if not ok then
			break
		end
	end

	-- Re-send the emptied filters of entries no longer in the configuration. Their sets were
	-- wiped above but the engine still holds the previous copy until it is told otherwise.
	if ok then
		for unit, byID in pairs(auraContainers) do
			for id, container in pairs(byID) do
				local includeSet = slotFilters[id]
				if includeSet and next(includeSet) == nil then
					-- An entry that left the configuration, or one carrying hideAura. Both mean
					-- "show nothing", and both need the maxDuration switch rather than an empty
					-- include set to mean it on a friendly target.
					SendSlotFilters(container, unit, includeSet, false)
				end
			end
		end
	end

	if not ok then
		return DisableAuraGroups()
	end

	-- Set at the END, and only when every entry got its containers. Setting it mid-loop meant it
	-- went true after the first container was created and stayed true even when a later one
	-- failed. Display reads this to decide whether to keep the Tracked Buffs container shown and
	-- whether to draw merged slots of its own.
	ns.mergeAuraGroupsActive = enabled
end

-- Put one merged entry's aura where Display has just decided it goes.
--
-- Called from the render path once per merged entry per tick, so it early-outs on an unchanged
-- placement before touching anything. The four stamp values are compared separately rather than
-- packed into a string, because packing would allocate at 20 Hz to discover nothing moved.
--
-- Both of the entry's containers get the same cell. Only one of them can have a visible aura --
-- an entry is a buff on the player or a debuff on the target -- so the other sits there empty.
--
-- Not pcall'd, and that is the point of the whole per-entry-container design: this moves frames
-- TBT created and owns, which carry no aura access restriction, so it is legal in combat. The
-- engine's own frames are never touched here.
function ns:PlaceMergeAura(entry, host, anchor, offsetX, offsetY, scale)
	if not ns.mergeAuraGroupsActive or not host then
		return
	end

	local id = entry.cooldownID
	if
		placedAnchor[id] == anchor
		and placedX[id] == offsetX
		and placedY[id] == offsetY
		and placedScale[id] == scale
		and placedHost[id] == host
	then
		return
	end
	placedAnchor[id], placedX[id], placedY[id], placedScale[id] = anchor, offsetX, offsetY, scale
	placedHost[id] = host

	for i = 1, #AURA_UNITS do
		local byID = auraContainers[AURA_UNITS[i].unit]
		local container = byID and byID[id]
		if container then
			-- Scaled like a TBT icon: the container carries the scale, so the offsets above are
			-- read in its own scaled space and "scale naturally", exactly as Display's comment on
			-- its own icons says. That is what keeps the two on one grid.
			container:SetScale(scale)
			container:ClearAllPoints()
			-- The entry's OWN host, not a hard-coded Tracked Buffs container: merged auras are
			-- placed into Essential and Utility too as of Phase 43.1.
			container:SetPoint(anchor, host, anchor, offsetX, offsetY)
		end
	end
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
-- This block is the ENTIRE surface on which TBT touches a Blizzard CDM frame, for the whole
-- addon and the whole milestone. Every operation below is a plain C widget call on the
-- VIEWER frame -- never on a CDM item frame, and never a Blizzard Lua mixin method:
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
	-- protected="true", so a placement write on them is legal in combat. Only the CDM ITEM
	-- frames were ever the taint hazard, and TBT never touches one.
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
	-- The aura-lookup latch is cleared on every event this frame sees. That is deliberately
	-- broad: the latch only exists to stop a raising API being called over and over, and every
	-- event here is either a combat edge, a zone or world change, or a CDM edit -- all moments
	-- where aura restriction can have changed. Clearing too eagerly costs one failed pcall;
	-- clearing too rarely costs the sweep for the rest of the session.
	ns:ClearMergeAuraLookupBlock()

	-- A target change is the one thing an aura container cannot notice by itself, so it is poked
	-- explicitly here. See ns:RefreshMergeAuraUnits for why this is the sanctioned route rather
	-- than a workaround. Called inline: it is a plain API call on a container TBT created, and
	-- Blizzard documents driving it from exactly this event.
	if event == "PLAYER_TARGET_CHANGED" then
		ns:RefreshMergeAuraUnits()
	end

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
		-- be live. The engine path stands down and TBT draws every configured entry.
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
		-- Hands the Tracked Buffs container back to TBT for the duration, so every configured
		-- entry previews. See ns:SetMergeCDMSettingsOpen.
		ns:SetMergeCDMSettingsOpen()
	end, mergeEventFrame)
	EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
		ns:QueueMergeVisibility()
		ns:QueueMergeShownSlots()
		-- Preview over: the engine takes the container back and only live auras show again.
		ns:SetMergeCDMSettingsOpen()
	end, mergeEventFrame)
end

-- Tell every engine container to re-evaluate its unit from scratch.
--
-- An AuraContainer listens to UNIT_AURA for its own unit and nothing else, so losing a target
-- fires nothing it cares about -- "target" simply stops existing, no aura update is sent, and the
-- frames go on showing the auras of a unit that is no longer there. Reported in play-testing:
-- merged target debuffs lingered until a new target was acquired or the fight ended.
--
-- Blizzard anticipated exactly this. AuraContainerSharedMixin:UpdateAllAuras is a deliberate
-- no-op on the base mixin whose comment reads "Exposed to allow external events to trigger
-- refreshes where needed (e.g. target changes)" -- it is the sanctioned hook, and the derived
-- custom container implements it. So the fix is to call it, not to work around it.
--
-- pcall'd like every other call into an engine object, and applied to both containers rather than
-- only the target one: it is idempotent and cheap, and a player container that re-evaluates on a
-- target change costs nothing worth branching to avoid.
-- Print what the mirror actually resolved for every slot the CDM is showing. A diagnostic, not
-- a feature: it exists because a single merged entry behaving oddly -- Touch of the Magi, whose
-- aura is a debuff on the target -- takes one look at these fields to explain and a round of
-- guesswork otherwise. Reachable as "/tbt merge".
--
-- Reads nothing new. Every field printed was resolved elsewhere and stored on the entry, so this
-- cannot be the thing that raises, and it runs only when typed.
function ns:PrintMergeDiagnostics()
	print("|cff00ccffTBT|r merge diagnostics:")
	if not ns.db or ns.db.mergeMode ~= true then
		print("  Merge Mode is OFF -- nothing is mirrored.")
		return
	end

	-- The target slot's state, because it is the one thing here that turns itself off and the
	-- reason is not guessable from the per-entry lines.
	if targetIsAssistable then
		print("  Target slot: |cffff6600OFF|r (friendly target -- debuffs there cannot be filtered by spell)")
	else
		print("  Target slot: |cff00ff00on|r")
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
				if entry.equipSlot then
					bits[#bits + 1] = "equipSlot=" .. tostring(entry.equipSlot)
					-- The numbers GetInventoryItemCooldown actually handed back, recorded at the
					-- read. The CDM drives its own equipped-item tile from exactly this call
					-- (CheckCacheCooldownValuesFromEquippedItem), so a wrong sweep here is a
					-- wrong READ, not a missing better source.
					local seen = ns.itemCooldownSeen and ns.itemCooldownSeen[entry.equipSlot]
					if not seen then
						bits[#bits + 1] = "|cffff6600itemCD=never-read|r"
					elseif seen.duration == nil then
						bits[#bits + 1] = "|cffff6600itemCD=unreadable|r"
					else
						bits[#bits + 1] = string.format(
							"itemCD=dur%.1f/left%.1f/en%s",
							seen.duration,
							math.max(0, (seen.startTime + seen.duration) - GetTime()),
							tostring(seen.enable)
						)
					end
				end
				if entry.iconOverride then
					bits[#bits + 1] = "itemIcon"
				end
				if entry.spellCategoryID then
					-- The category, and the spell GetLastCategoryCooldownSource last named for
					-- it. That spell is what the cooldown is actually read from, so "cached"
					-- here is the difference between a potion timer and a blank icon in combat.
					local cached = ns.categorySpellID and ns.categorySpellID[entry.spellCategoryID]
					bits[#bits + 1] = "cat=" .. tostring(entry.spellCategoryID)
					bits[#bits + 1] = cached and ("catSpell=" .. cached) or "|cffff6600catSpell=none|r"
				end
				-- The engine can only filter an aura slot by SPELL ID -- there is no category
				-- filter in candidateFilters -- so for an entry with no spellID of its own, this
				-- count IS whether an aura can ever be shown for it.
				-- Did the CDM relay work? This is the question that decides whether TBT needs any
				-- per-item cooldown resolution at all.
				local relay = ns.mergeRelayState and ns.mergeRelayState[entry.cooldownID]
				if relay == "ok" then
					bits[#bits + 1] = "|cff00ff00drew=cdm-relay|r"
				elseif relay == "item" then
					-- GetInventoryItemCooldown, which is where an equipped item's cooldown
					-- actually lives and where the CDM reads it too.
					bits[#bits + 1] = "|cff00ff00drew=item|r"
				elseif relay == "handle" then
					-- The duration-object path, which is the reliable one for anything with a
					-- spell. Not a fallback and not a fault.
					bits[#bits + 1] = "|cff00ff00drew=handle|r"
				elseif relay then
					bits[#bits + 1] = "|cffff6600relay=" .. relay .. "|r"
				else
					bits[#bits + 1] = "relay=untried"
				end

				local linked = entry.linkedSpellIDs
				bits[#bits + 1] = "linked=" .. (linked and #linked or 0)

				-- The include set actually handed to the engine, which is the thing that decides
				-- whether an aura can appear. Usually spellID plus the linked list; for a generic
				-- item cooldown it is whatever the POT_SPELLS fallback seeded. Zero here means the
				-- slot is filtering on nothing and will stay empty forever, which is precisely the
				-- state the Blizzard potion tile was found in.
				local includeSet = slotFilters[entry.cooldownID]
				local filterCount = 0
				if includeSet then
					for _ in pairs(includeSet) do
						filterCount = filterCount + 1
					end
				end
				-- Highlighted only when an empty filter is a PROBLEM. On a hideAura entry it is
				-- the intended state -- that entry is meant to show its cooldown and never its
				-- aura -- so colouring it there would flag correct behaviour as broken.
				if filterCount == 0 and not entry.hideAura then
					bits[#bits + 1] = "|cffff6600filter=0|r"
				else
					bits[#bits + 1] = "filter=" .. filterCount
				end
				if entry.hasCharges then
					bits[#bits + 1] = "cdmCharges"
				end
				if entry.hideAura then
					bits[#bits + 1] = "hideAura"
				end
				bits[#bits + 1] = entry.selfAura and "selfAura" or "|cffffff00notSelfAura|r"
				-- The two that matter for a debuff-on-target entry: whether the aura resolved at
				-- all, and on which unit.
				if ns.mergeAuraGroupsActive then
					-- Not a failure and not worth colouring as one: the engine owns every merged
					-- aura, so TBT deliberately stops resolving them and entry.auraExpiry is
					-- expected to be empty.
					bits[#bits + 1] = "aura=engine"
				elseif entry.auraExpiry then
					bits[#bits + 1] = "|cff00ff00aura=" .. (entry.auraOnTarget and "target" or "player") .. "|r"
				else
					bits[#bits + 1] = "|cffff6600aura=unresolved|r"
				end
				print("    " .. (entry.label ~= "" and entry.label or "(no label)") .. "  " .. table.concat(bits, " "))

				-- Phase 48 (D-03, unknowns 3 and 4) -- the on-demand half of the pandemic debug
				-- dump. Deliberately not a new slash command: Core.lua is protected this phase
				-- (D-03, D-04), so this is a new block on the existing "/tbt debug" then
				-- "/tbt merge" call site, printing only when ns.debugLogging is on -- ordinary
				-- "/tbt merge" output above is byte-identical for a user who has not enabled
				-- debug.
				if ns.debugLogging then
					-- The backwards-trace check (48-CONTEXT.md's Phase 47 lesson): a highlight
					-- that never appears with frame=no on every row means
					-- CollectShownCooldownIDs has not run, not that the pandemic signal itself
					-- is broken.
					local mergeFrame = ns.mergeItemFrames[entry.cooldownID]
					local hasFrame = mergeFrame ~= nil
					local iconPresent = hasFrame and mergeFrame.PandemicIcon ~= nil

					local rawTrigger = hasFrame and mergeFrame.pandemicAlertTriggerTime or nil
					local triggerSecret, triggerType = issecretvalue(rawTrigger), type(rawTrigger)
					local triggerVal = (not triggerSecret and triggerType == "number") and rawTrigger or nil

					local rawStart = hasFrame and mergeFrame.pandemicStartTime or nil
					local rawEnd = hasFrame and mergeFrame.pandemicEndTime or nil
					local startSecret, startType = issecretvalue(rawStart), type(rawStart)
					local startVal = (not startSecret and startType == "number") and rawStart or nil
					local endSecret, endType = issecretvalue(rawEnd), type(rawEnd)
					local endVal = (not endSecret and endType == "number") and rawEnd or nil
					-- "trigger" is not a route -- see ns:IsMergedEntryInPandemic. It is printed
					-- because it distinguishes a PENDING window from an active one, which is
					-- useful when reading a log, but it never decides the answer.
					local route = (startVal ~= nil and endVal ~= nil) and "numbers" or "boolean"

					-- Unknown 3: is Enum.CooldownViewerAlertEventType.PandemicTime a member of
					-- this cooldownID's native alert capability set (the same set
					-- CanTriggerAlertType gates on)? A plain C_CooldownViewer namespace call --
					-- the same class of API this file already uses everywhere -- not a mixin
					-- method on a frame, so it is permitted, but treated defensively anyway:
					-- capability-checked (the Enum.CooldownViewerCategory idiom at :43-54),
					-- pcall'd, the result verified with ns:CanReadTable before iterating, and
					-- each element guarded with issecretvalue before comparing it. "?" on any
					-- degrade; a run where every entry reports "no" is the answer to unknown 4.
					local alertCap = "?"
					local pandemicAlertType = Enum.CooldownViewerAlertEventType
						and Enum.CooldownViewerAlertEventType.PandemicTime
					-- Namespace existence only, not the specific function -- pcall below already
					-- degrades cleanly if that one field is absent (calling a nil value raises
					-- INSIDE pcall's own protected call, which it catches), so there is no need
					-- for a second reference to the API name here.
					if pandemicAlertType and C_CooldownViewer then
						local ok, validTypes = pcall(C_CooldownViewer.GetValidAlertTypes, entry.cooldownID)
						if ok and ns:CanReadTable(validTypes) then
							alertCap = "no"
							for _, v in pairs(validTypes) do
								if not issecretvalue(v) and v == pandemicAlertType then
									alertCap = "yes"
									break
								end
							end
						end
					end

					-- Phase 48.1 (DISP-01) diagnostics. Three outcomes have to stay
					-- distinguishable or this field is worth nothing: the client has no
					-- DebuffBorder on its item frames at all (absent -- the expected Forever
					-- answer), it has one and Blizzard is deliberately not drawing it (hidden --
					-- the expected answer for every buff and every non-dispellable debuff), and
					-- it is drawn but the atlas name did not come back as a plain string
					-- (unreadable). Collapsing any two of those into "no border" is exactly the
					-- mistake the previewNote below exists to avoid.
					--
					-- pcall'd around the two widget getters because this runs inside "/tbt merge",
					-- which must not be takeable down by a diagnostic; the render path's own read
					-- is separately pcall'd at its call site.
					-- The SECOND possible mirror source, probed here before anything is built on
					-- it. CooldownViewerItemDataMixin:GetAuraDataCached is a one-line return of
					-- self.auraDataCached (CooldownViewerItemData.lua:730), so the table is
					-- reachable as a plain field read -- no mixin call, inside the locked rule --
					-- and it carries dispelName and isHarmful directly, which is everything
					-- AuraUtil.SetAuraBorderAtlasFromAura uses to decide what to draw.
					--
					-- Worth knowing because it does NOT depend on Blizzard having drawn its own
					-- border. If the bar's DebuffBorder turns out to be absent or never shown
					-- under Merge Mode, this route can still answer, and the dump has to say so
					-- in the same pass rather than costing another test round trip.
					local auraCached = hasFrame and mergeFrame.auraDataCached or nil
					local auraNote
					if not auraCached then
						auraNote = "none"
					elseif not ns:CanReadTable(auraCached) then
						auraNote = "unreadable"
					else
						local dn = auraCached.dispelName
						local harmful = auraCached.isHarmful
						auraNote = "dispelName="
							.. ((not issecretvalue(dn) and type(dn) == "string") and dn or ("<" .. (issecretvalue(dn) and "secret" or type(
								dn
							)) .. ">"))
							.. ",harmful="
							.. (issecretvalue(harmful) and "<secret>" or tostring(harmful))
					end

					-- entry.dispelAtlas may now hold a SECRET string -- that is the point of the
					-- relay -- so it can never go through tostring() into this line.
					--
					-- Measured on Forever 2026-09-24: it printed the whole row as "???". A secret
					-- concatenated into a string makes the RESULT secret, and print() renders a
					-- secret string as "???" rather than leaking it. So one secret field did not
					-- corrupt one field, it silently destroyed every other field on the row --
					-- frame, icon, the timestamps, alertCap, all of it -- and only on the rows
					-- where a border was actually being drawn, which are the interesting ones.
					--
					-- Regression introduced by the relay change itself: before it, the atlas was
					-- filtered to plain strings on the way in, so tostring() here was safe. The
					-- read stopped filtering and this line was not revisited.
					-- issecretvalue FIRST, before the nil test and not after it: the addon-wide
					-- ordering rule is not only about type(), it is about every inspection. A
					-- secret compared against nil is the same class of mistake as a secret handed
					-- to type(), and `== nil` on a secret is exactly what ApplyDispelBorder had to
					-- be restructured to avoid.
					local stamped
					if issecretvalue(entry.dispelAtlas) then
						stamped = "<secret,relayed>"
					elseif entry.dispelAtlas == nil then
						stamped = "nil"
					else
						stamped = tostring(entry.dispelAtlas)
					end

					local borderFrame = hasFrame and mergeFrame.DebuffBorder or nil
					local dispel
					if not borderFrame then
						dispel = "absent"
					else
						local okShown, isShown = pcall(borderFrame.IsShown, borderFrame)
						if not okShown then
							dispel = "raised"
						elseif not isShown then
							dispel = "hidden"
						else
							-- pcall(tex.GetAtlas, tex) rather than pcall(function() ... end): the
							-- closure form allocates one per entry per dump, and the method-value
							-- form matches pcall(borderFrame.IsShown, borderFrame) above. The
							-- `tex` nil test has to happen BEFORE the pcall either way -- indexing
							-- a nil `tex` to build the argument list would raise outside the
							-- pcall, where nothing catches it.
							local tex = borderFrame.Texture
							local okAtlas, rawAtlas = true, nil
							if tex then
								okAtlas, rawAtlas = pcall(tex.GetAtlas, tex)
							end
							if not okAtlas then
								dispel = "raised"
							elseif not issecretvalue(rawAtlas) and type(rawAtlas) == "string" then
								dispel = rawAtlas
							else
								dispel = "unreadable(secret="
									.. tostring(issecretvalue(rawAtlas))
									.. ",type="
									.. type(rawAtlas)
									.. ")"
							end
						end
					end

					-- WHY frame=no, when it is no. ns.mergeItemFrames is filled by
					-- CollectShownCooldownIDs, which ns:RefreshMergeShownSlots skips entirely
					-- while ns:IsMergePreviewState() is true -- that is, whenever the Cooldown
					-- Manager settings window or Edit Mode is open. Running "/tbt merge" with
					-- either of those on screen is the natural thing to do, and it would report
					-- frame=no on every row: indistinguishable from the read being broken.
					--
					-- Saying which it is costs one boolean. Two outcomes that look identical in
					-- a log are the thing that makes a probe useless, which this project has
					-- already paid for once (the aura-route comparator, 2026-09-23).
					local previewNote = ""
					if not hasFrame and ns:IsMergePreviewState() then
						previewNote = " |cffffff00(preview state -- frame cache is empty by design;"
							.. " close the CDM settings window and Edit Mode, then re-run)|r"
					end

					-- engineBorder is the ENGINE route's status, and it is the one that matters for
					-- an ordinary merged tracked buff: that case is drawn by the aura engine, which
					-- gets its border from InitializeAuraFrame's AddDispelTypeTexture, not from the
					-- dispel/stamped pair beside it. Those two cover bars, item-backed entries, and
					-- the fallback where the engine path is latched off.
					print(
						"      |cffff8040PANDEMIC|r frame="
							.. (hasFrame and "yes" or "no")
							.. previewNote
							.. " icon="
							.. (iconPresent and "yes" or "no")
							.. " trigger(secret="
							.. tostring(triggerSecret)
							.. ",type="
							.. triggerType
							.. ",val="
							.. tostring(triggerVal)
							.. ") start(secret="
							.. tostring(startSecret)
							.. ",type="
							.. startType
							.. ",val="
							.. tostring(startVal)
							.. ") finish(secret="
							.. tostring(endSecret)
							.. ",type="
							.. endType
							.. ",val="
							.. tostring(endVal)
							.. ") answer="
							.. tostring(ns:IsMergedEntryInPandemic(entry, GetTime()))
							.. " route="
							.. route
							.. " alertCap="
							.. alertCap
							.. " dispel="
							.. dispel
							.. " stamped="
							.. stamped
							.. " engineBorder="
							.. tostring(ns.mergeDispelTextureState)
							.. " aura("
							.. auraNote
							.. ")"
					)

					-- Field census, printed only when the frame is cached but reports no
					-- pandemic state at all. Closes the one hypothesis the fields above cannot:
					-- "type=nil" means ABSENT, and absent looks identical whether Blizzard has
					-- simply not computed a window yet, or this client's build names the fields
					-- something other than what the 12.1 source snapshot says.
					--
					-- Measured on retail 2026-09-24: every entry reported icon=no with both
					-- timestamps type=nil, on a Frost mage -- a spec with no player-refreshable
					-- DoT, so plausibly nothing to compute a window FOR. This census tells the
					-- two apart instead of leaving it to inference, per the project's own
					-- "a source dump cannot prove absence" rule: the live client outranks the
					-- snapshot, so ask the live client.
					--
					-- Plain pairs() over the frame's own Lua fields: a read, never a mixin call
					-- and never a write, so it sits on the permitted side of this file's header
					-- (:5-25). pcall'd because a secure proxy may refuse enumeration outright,
					-- and capped so a frame with many fields cannot flood the chat frame.
					if hasFrame and not iconPresent and startType == "nil" and endType == "nil" then
						-- DATA fields are separated from methods and counted rather than named.
						-- Measured 2026-09-24: the live frame carries nine pandemic-named
						-- FUNCTIONS and, so far, no data field at all -- so naming the functions
						-- on every entry of every dump is pure noise, and it was the bulk of a
						-- very long log. The functions are also the forbidden half: every one is
						-- a mixin method this file may never call.
						--
						-- Data first, and never truncated ahead of a method: a data field is the
						-- entire point of the census, and the old shared cap could have dropped
						-- the one key worth seeing behind nine known-uninteresting ones.
						local dataNames, dataCount, fnCount = {}, 0, 0
						local okEnum = pcall(function()
							for k, v in pairs(mergeFrame) do
								if type(k) == "string" and k:lower():find("pandemic") then
									if type(v) == "function" then
										fnCount = fnCount + 1
									elseif dataCount < 16 then
										dataCount = dataCount + 1
										dataNames[dataCount] = k .. "(" .. type(v) .. ")"
									end
								end
							end
						end)
						local census
						if not okEnum then
							census = "|cffff6600enumeration refused|r"
						elseif dataCount == 0 then
							census = "no data fields -- " .. fnCount .. " pandemic methods only"
						else
							census = table.concat(dataNames, " ", 1, dataCount) .. " (+" .. fnCount .. " methods)"
						end
						print("        |cff808080pandemic fields:|r " .. census)
					end
				end
			end
		end
	end

	if total == 0 then
		print("  No shown slots. Either the CDM has nothing configured, or its viewers are unreadable.")
	end
end

function ns:RefreshMergeAuraUnits()
	if not auraGroupsUsable then
		return
	end

	-- A target change can flip whether the target slot may be live at all -- see
	-- RefreshTargetAssistable. Only re-send the filters when the answer actually moved, which for
	-- the common case of swapping between two enemies is never.
	if RefreshTargetAssistable() then
		ns:RefreshMergeAuraGroups()
	end

	for _, byID in pairs(auraContainers) do
		for _, container in pairs(byID) do
			if container.UpdateAllAuras then
				pcall(container.UpdateAllAuras, container)
			end
		end
	end
end
