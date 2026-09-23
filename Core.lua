local addonName, ns = ...

-- Phase 35 (CONT-01): the four base containers, in the user-visible order fixed by
-- 35-CONTEXT.md. `bars` and `buffs` are the v0.3.0 section keys and must never change —
-- every `entry.section` written before this phase is already correct for them. `essential`
-- and `utility` are new, id-shaped keys and are Phase 40's merge-mode mapping target
-- (Enum.CooldownViewerCategory.Essential / .Utility). No consumer may branch on a key
-- string; branch on `kind` ("bar" or "icon") instead.
-- Phase 40 (STEAL-03): `cdmCategoryName` is a NAME, not the enum value itself — a
-- file-scope reference to the CDM category enum would be a load-time dependency on an
-- enum that may not exist on every flavour, so MergeMode.lua resolves it by name behind
-- a nil check at runtime instead.
-- TRACKER CATEGORIES (user decision, 2026-09-22). Every container and every tracker belongs to
-- exactly one of two categories, and nothing moves between them:
--
--   "buffs"  -- Tracked Buffs and Tracked Bars. Everything that existed before v0.4.0.
--   "spells" -- Essential Cooldowns and Utility Cooldowns. The cooldown trackers v0.4.0 adds.
--
-- The CDM tab surfaces one tab per category ("TBT Cooldowns" then "TBT Buffs"), and the config page
-- is shared. A tracker's category is derived, never stored: ns:GetTrackerCategory reads
-- trackerType, so no migration and no second source of truth. A container's category IS stored,
-- because a user-created container has no tracker to derive it from.
-- DEFAULT POSITIONS ARE BLIZZARD'S, COPIED EXACTLY (user decision, 2026-09-22).
--
-- Each base container starts where the CDM viewer it mirrors starts, taken from
-- EditModePresetLayouts.lua's [Enum.EditModeSystem.CooldownViewer] block: every one of them
-- anchors BOTTOM to UIParent BOTTOM, at (0, 240) Utility, (0, 310) Essential, (0, 370) BuffIcon
-- and (420, 430) BuffBar. Matching them matters most in Merge Mode, where TBT's containers stand
-- in for Blizzard's -- landing in the same place means the swap is invisible rather than
-- something the player has to re-position first.
--
-- These are SEED values only. ns.db.editModePositions is written the first time a container is
-- positioned and is authoritative afterwards, so changing a number here never moves a container
-- a player has already placed. It does take effect on every Forever login, which never reads
-- saved variables back.
--
-- User containers deliberately do NOT follow this: they mirror no Blizzard viewer, so there is
-- no position to match, and they keep the CENTER anchor they have always had.
ns.CONTAINERS = {
	{
		key = "buffs",
		title = "Tracked Buffs",
		category = "buffs",
		frameName = "TBTBuffContainer",
		kind = "icon",
		cdmViewerGlobal = "BuffIconCooldownViewer",
		cdmCategoryName = "TrackedBuff",
		defaultPoint = "BOTTOM",
		defaultRelativePoint = "BOTTOM",
		defaultX = 0,
		defaultY = 370,
	},
	{
		key = "bars",
		title = "Tracked Bars",
		category = "buffs",
		frameName = "TBTBarContainer",
		kind = "bar",
		cdmViewerGlobal = "BuffBarCooldownViewer",
		cdmCategoryName = "TrackedBar",
		defaultPoint = "BOTTOM",
		defaultRelativePoint = "BOTTOM",
		defaultX = 420,
		defaultY = 430,
	},
	{
		key = "essential",
		title = "Essential Cooldowns",
		category = "spells",
		frameName = "TBTEssentialContainer",
		kind = "icon",
		cdmViewerGlobal = "EssentialCooldownViewer",
		cdmCategoryName = "Essential",
		defaultPoint = "BOTTOM",
		defaultRelativePoint = "BOTTOM",
		defaultX = 0,
		defaultY = 310,
	},
	{
		key = "utility",
		title = "Utility Cooldowns",
		category = "spells",
		frameName = "TBTUtilityContainer",
		kind = "icon",
		cdmViewerGlobal = "UtilityCooldownViewer",
		cdmCategoryName = "Utility",
		defaultPoint = "BOTTOM",
		defaultRelativePoint = "BOTTOM",
		defaultX = 0,
		defaultY = 240,
	},
}

-- The category a tracker belongs to, derived from what it is rather than stored alongside it.
-- Phase 38 made "cooldowns are icons, never bars" a locked decision and gave every cooldown
-- tracker trackerType == "cooldown"; everything else -- plain buffs, meta trackers, racials --
-- is a buff. Deriving means an entry written by any earlier version answers correctly with no
-- schema bump, which is why CURRENT_SCHEMA_VERSION does not move for this change.
function ns:GetTrackerCategory(entry)
	if entry and entry.trackerType == "cooldown" then
		return "spells"
	end
	return "buffs"
end

-- The category a container belongs to. Base containers declare it above; a user-created
-- container has none stored by older code, and falls back to "buffs" -- correct by history,
-- since every container that existed before v0.4.0 held buffs.
function ns:GetContainerCategory(def)
	return (def and def.category) or "buffs"
end

-- Generic item cooldowns -- potions and healthstones -- are identified by a spell CATEGORY
-- rather than by an item or a spell, and the CDM shows one fixed icon per category without
-- naming the specific item the player drank. Transcribed from Blizzard's
-- spellCategoryMetadataLookup (CooldownViewerItemData.lua:405-438).
--
-- Here rather than beside either consumer because both need them: MergeMode.lua resolves the
-- identity of an item-backed CDM entry, and Providers.lua uses the combat-potion icon as the
-- pot meta-tracker's fallback. Core.lua loads first, so both can take upvalues from it.
ns.SPELL_CATEGORY_ICON = {
	[4] = "Interface/ICONS/INV_POTION_114", -- combat potion
	[30] = "Interface/ICONS/INV_POTION_54", -- health potion
	[1711] = "Interface/ICONS/Warlock_ Healthstone",
	[2566] = "Interface/ICONS/Warlock_ Bloodstone", -- demonic healthstone
}

-- The matching titles from the same table's tooltipTitle fields, held as global NAMES rather
-- than values: a global string absent on one flavour must leave the label empty, not raise at
-- file scope.
ns.SPELL_CATEGORY_TITLE_KEY = {
	[4] = "COOLDOWN_VIEWER_TOOLTIP_POTION_COMBAT_TITLE",
	[30] = "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE",
	[1711] = "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTHSTONE_TITLE",
	[2566] = "COOLDOWN_VIEWER_TOOLTIP_POTION_DEMONIC_HEALTHSTONE_TITLE",
}

-- The category a combat potion falls under, named once so the pot meta-tracker does not repeat
-- the magic number.
ns.SPELL_CATEGORY_COMBAT_POTION = 4

ns.CONTAINER_BY_KEY = {}
for _, def in ipairs(ns.CONTAINERS) do
	ns.CONTAINER_BY_KEY[def.key] = def
end

-- 0=Right/Down, 1=Left/Up, 2=Centered. Centered is offered on BUFF-category icon containers
-- only, and is their default (user decision, 2026-09-22): a buff container is read at a glance
-- mid-fight, and a run that grows out from a fixed midpoint stays where the eye already is,
-- where a left-anchored run moves its own contents every time something drops.
--
-- Spells containers keep Right/Down. Their whole point is a stable slot per cooldown, and the
-- Edit Mode dropdown does not offer Centered there, so this is the one place the rule is
-- expressed. Bars have no direction control at all and take 0 as they always have.
ns.GROWTH_CENTERED = 2

function ns:DefaultGrowthDirection(def)
	if def.kind ~= "bar" and ns:GetContainerCategory(def) == "buffs" then
		return ns.GROWTH_CENTERED
	end
	return 0
end

-- Registry-driven pass (CONT-01, extracted for CONT-04): seed a missing container's settings
-- from its kind's default set, and backfill new fields onto settings that already exist.
-- Idempotent and NOT version-gated -- a fresh and an upgraded database must reach the same
-- end state. Each container gets its own fresh table; never share one table between two
-- containers, or Phase 36's per-container settings would alias. The defaults table
-- constructor below must appear exactly once in this file -- that is what guarantees a user
-- container created at runtime gets a fresh table and never aliases another container's.
function ns.EnsureContainerSettings(def)
	local cs = ns.db.containerSettings[def.key]
	if not cs then
		cs = {
			orientation = def.kind == "bar" and 1 or 0, -- bars stack vertically; icons flow horizontally
			growthDirection = ns:DefaultGrowthDirection(def),
			scale = 100, -- percentage (100 = 1.0x), divided by 100 at read time
			padding = 5,
			opacity = 100, -- percentage (100 = fully opaque)
			visibility = 0, -- 0=Always Visible (show whenever buff is up)
			hideWhenInactive = true,
			showTimer = true,
			showTooltips = true,
		}
		if def.kind == "bar" then
			cs.barWidth = 100 -- percentage (100 = BAR_WIDTH default of 220px)
			cs.displayMode = 0 -- 0=Icon And Name, 1=Icon Only, 2=Name Only
		else
			-- Conservative addon default, NOT the CDM's value: Blizzard's factory IconLimit
			-- presets differ per viewer (Essential 12, Utility 7, BuffIcon 1); 12 is the
			-- highest of the three, so it wraps the least until the user picks their own.
			cs.itemsPerRow = 12
		end
		ns.db.containerSettings[def.key] = cs
	else
		if cs.hideWhenInactive == nil then
			cs.hideWhenInactive = true
		end
		if cs.showTimer == nil then
			cs.showTimer = true
		end
		if cs.showTooltips == nil then
			cs.showTooltips = true
		end
		if cs.opacity == nil then
			cs.opacity = 100
		end
		if def.kind == "bar" and cs.displayMode == nil then
			cs.displayMode = 0
		end
		if def.kind ~= "bar" and cs.itemsPerRow == nil then
			cs.itemsPerRow = 12
		end
	end
end

-- CONT-04: the key is "user" .. id, where id is the monotonic ns.db.nextContainerId counter.
-- Three guards make a collision with a base key or a CDM-tab section key impossible: (1) no
-- base key or CDM-tab section key ("hidden", "suggested") begins with "user"; (2) the counter
-- is incremented on every issue and never decremented, so a deleted container's key is never
-- reissued; (3) a live re-check loop below survives a hand-edited SavedVariables file that
-- duplicates an id. Returns key, id and advances the counter before returning.
function ns:GenerateContainerKey()
	local id = ns.db.nextContainerId
	local key = "user" .. id
	while ns.CONTAINER_BY_KEY[key] or key == "hidden" or key == "suggested" do
		id = id + 1
		key = "user" .. id
	end
	ns.db.nextContainerId = id + 1
	return key, id
end

-- CONT-04: the only place a user-container def is appended to or removed from the registry.
-- The isUser flag below is set HERE AND NOWHERE ELSE, so the four literal base entries can
-- never carry it -- ns:DeleteUserContainer's base-container guard relies on that being true.
function ns:RegisterContainerDef(record)
	local def = {
		key = record.key,
		title = record.title,
		frameName = "TBTContainer_" .. record.key,
		kind = record.kind,
		-- Defaulted, not assumed present: a container record persisted by a build before this
		-- change carries no category at all.
		category = record.category or "buffs",
		cdmViewerGlobal = nil,
		defaultX = record.defaultX,
		defaultY = record.defaultY,
		isUser = true,
	}
	table.insert(ns.CONTAINERS, def)
	ns.CONTAINER_BY_KEY[record.key] = def
	return def
end

function ns:UnregisterContainerDef(key)
	for i, def in ipairs(ns.CONTAINERS) do
		if def.key == key then
			table.remove(ns.CONTAINERS, i)
			ns.CONTAINER_BY_KEY[key] = nil
			return true
		end
	end
	return false
end

-- CONT-04/05: rebuilds ns.CONTAINERS' user-container tail from ns.db.userContainers on
-- ADDON_LOADED, before anything that loops the registry runs. Rehydration and runtime
-- creation share ns:AttachContainerRuntime, so there is one code path to get wrong, not two.
function ns:RehydrateUserContainers()
	for _, record in ipairs(ns.db.userContainers) do
		local def = ns:RegisterContainerDef(record)
		ns:AttachContainerRuntime(def)
	end
end

-- CONT-04/05/06: the only place Core talks to Display.lua / EditModeFrames.lua / CDMTab.lua.
-- Every call is nil-guarded because Core loads FIRST: none of these hooks is defined yet at the
-- moment this file is read, and each is additionally required to no-op before its own subsystem
-- has initialised. Rehydration runs at ADDON_LOADED, which is earlier still than ns.containers
-- and ns.tbtSections being populated, so the guards are load-order insurance rather than a
-- migration leftover -- they stay.
function ns:AttachContainerRuntime(def)
	if ns.AllocateContainerRuntime then
		ns.AllocateContainerRuntime(def)
	end
	if ns.CreateContainerFrames then
		ns.CreateContainerFrames(def)
	end
	if ns.RebuildContainerSectionDefs then
		ns.RebuildContainerSectionDefs()
	end
	if ns.AddContainerSection then
		ns.AddContainerSection(def)
	end
end

function ns:DetachContainerRuntime(key)
	if ns.RemoveContainerSection then
		ns.RemoveContainerSection(key)
	end
	if ns.DestroyContainerFrames then
		ns.DestroyContainerFrames(key)
	end
	if ns.ReleaseContainerRuntime then
		ns.ReleaseContainerRuntime(key)
	end
	if ns.RebuildContainerSectionDefs then
		ns.RebuildContainerSectionDefs()
	end
end

-- CONT-06: plain counter over pairs, no allocation -- used by the delete confirmation dialog
-- to name the tracker count before the user commits.
function ns:CountContainerTrackers(key)
	local count = 0
	for _, entry in pairs(ns.db.trackedBuffs) do
		if entry.section == key then
			count = count + 1
		end
	end
	return count
end

-- CONT-04: kind must be "bar" or "icon"; title falls back to "Container " .. id and is NOT
-- required to be unique -- the key is the identity, so no uniqueness check is added.
--
-- category is "buffs" or "spells" and defaults to "buffs", which is what every container
-- created before the choice existed was. A SPELLS container is icon-only, enforced here rather
-- than only in the dialog: "cooldowns are icons, never bars" is a locked decision from Phase 38,
-- and the render path relies on it -- RenderBarContainer skips a cooldown tracker outright, so a
-- bar-kind spells container would be a container nothing could ever draw into.
function ns:CreateUserContainer(title, kind, category)
	if kind ~= "bar" and kind ~= "icon" then
		return nil
	end
	category = category or "buffs"
	if category ~= "buffs" and category ~= "spells" then
		return nil
	end
	if category == "spells" and kind ~= "icon" then
		return nil
	end
	local key, id = ns:GenerateContainerKey()
	if title == nil or title == "" then
		title = "Container " .. id
	end
	local record = {
		key = key,
		title = title,
		kind = kind,
		-- Stored rather than derived, so a record written before the choice existed keeps
		-- answering "buffs" through ns:RegisterContainerDef's default instead of needing a
		-- migration.
		category = category,
		defaultX = 300,
		defaultY = -320 - 80 * #ns.db.userContainers, -- evaluated before the insert below
	}
	table.insert(ns.db.userContainers, record)
	local def = ns:RegisterContainerDef(record)
	ns.EnsureContainerSettings(def)
	ns:AttachContainerRuntime(def)
	print("|cff00ccffTerribleBuffTracker|r: Created container |cff00ff00" .. def.title .. "|r.")
	-- The settings panel lists containers; refresh it wherever one appears rather than only on
	-- its own OnShow, so a container created while it is open shows up without reopening it.
	-- Nil-guarded: Config.lua loads after this file and the panel may not exist yet.
	if ns.RefreshConfigPanel then
		ns:RefreshConfigPanel()
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
	return def
end

-- CONT-04/05/06: deletion order is fixed -- move contents to "hidden" first, unregister the
-- def so the next UpdateDisplay tick cannot reach a half-torn-down container, THEN detach
-- runtime and drop per-key tables. Unregistering before releasing per-key tables matters: the
-- reverse would leave ns.CONTAINERS naming a key whose pools entry is already gone, and
-- Display.lua's dispatch loop would index a nil pool.
function ns:DeleteUserContainer(key)
	local def = ns.CONTAINER_BY_KEY[key]
	if not def or not def.isUser then
		print("|cff00ccffTerribleBuffTracker|r: That container cannot be deleted.")
		return false
	end

	-- Collect before mutating -- ns:SetBuffSection calls ns:UpdateDisplay(), and mutating
	-- entries while iterating the same table it reads only breaks in-game.
	local dbKeysToMove = {}
	for dbKey, entry in pairs(ns.db.trackedBuffs) do
		if entry.section == key then
			table.insert(dbKeysToMove, dbKey)
		end
	end
	for _, dbKey in ipairs(dbKeysToMove) do
		ns:SetBuffSection(dbKey, "hidden")
	end

	ns:UnregisterContainerDef(key)
	ns:DetachContainerRuntime(key)

	ns.db.containerSettings[key] = nil
	if ns.db.editModePositions then
		ns.db.editModePositions[key] = nil
	end
	for i, record in ipairs(ns.db.userContainers) do
		if record.key == key then
			table.remove(ns.db.userContainers, i)
			break
		end
	end

	print("|cff00ccffTerribleBuffTracker|r: Deleted container |cffff6600" .. def.title .. "|r.")

	-- Same reason as the create path: the settings panel lists containers, so it refreshes
	-- wherever one disappears rather than only on its own OnShow.
	if ns.RefreshConfigPanel then
		ns:RefreshConfigPanel()
	end

	-- Preview procs carry a section field snapshotted at ns:StartAllPreviewTimers() time, so a
	-- stale one naming the deleted key would otherwise fall through Display.lua's
	-- timersByContainer[timer.section] or timersByContainer.bars and render in Tracked Bars
	-- for a tick.
	if ns.configOpen then
		ns:StartAllPreviewTimers()
	end
	if ns.tbtSections then
		ns:RefreshTBTSections()
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
	return true
end

ns.activeTimers = {}

-- Phase 38 (CD-04/CD-05): invalidation stamps, read by Display.lua. A cooldown is never a
-- timer and never enters ns.activeTimers above -- these two counters are how Display.lua
-- learns a cooldown widget or the tracker set changed, without polling either one per frame.
-- Two counters, not one, because they are advanced at very different rates: SPELL_UPDATE_COOLDOWN
-- fires roughly once per GCD in combat, while the tracker set only changes on a user edit.
-- Folding both into one counter would force Display.lua to pay the expensive rebuild at the
-- cheap counter's rate.
-- ownerKey -> GetTime() of the cast that started this tracker's cooldown.
--
-- A custom cooldown tracker runs on the duration the USER typed, not on the game's own cooldown
-- (user decision, 2026-09-22, reversing CD-02). That needs a start time, and the only one
-- available is the cast: UNIT_SPELLCAST_SUCCEEDED is the same signal every buff tracker already
-- runs on, and nothing in it is secret.
--
-- Runtime-only, exactly like ns.activeTimers. Persisting it would restore a cooldown that the
-- game finished while the player was logged out, and there is no way to check.
-- A tracker's DB key namespace.
--
-- ns.db.trackedBuffs was keyed by spell ID alone, which made "Frostbolt the buff" and "Frostbolt
-- the cooldown" the SAME RECORD -- adding one silently replaced the other. Reported 2026-09-22,
-- and it is a design bug rather than a regression: tracking a spell's buff and its cooldown at
-- once is an ordinary thing to want, and the schema could not express it.
--
-- Cooldown trackers therefore live under "cd:<spellID>" and buffs keep the bare numeric ID. One
-- table, two namespaces, chosen over two tables because every consumer that walks
-- pairs(ns.db.trackedBuffs) -- six of them -- keeps working untouched, and because the UI already
-- treats a tracker's key as opaque: CDMTab's item.spellID has held the strings "lust", "trinket"
-- and "pot" since Phase 23.
--
-- entry.spellID still holds the real numeric ID on every entry, so nothing that needs the spell
-- has to parse a key.
ns.COOLDOWN_KEY_PREFIX = "cd:"

function ns:TrackerKey(spellID, trackerType)
	if trackerType == "cooldown" then
		return ns.COOLDOWN_KEY_PREFIX .. spellID
	end
	return spellID
end

-- The numeric spell ID a cooldown key names, or nil for anything else -- a buff's numeric key, a
-- meta key, or a malformed string. Callers that want "the spell this key is about" regardless of
-- namespace should read entry.spellID instead.
function ns:CooldownKeySpellID(key)
	if type(key) ~= "string" then
		return nil
	end
	local id = key:match("^cd:(%d+)$")
	return id and tonumber(id) or nil
end

ns.cooldownStarts = {}

-- Is this cooldown tracker mid-cooldown right now? The single answer, shared by the render path
-- and by the preview builder, so "a real cooldown beats a preview" cannot be decided two ways.
-- Plain numbers throughout: the start is GetTime() at the cast, the duration is the player's own.
function ns:IsCooldownRunning(key, entry, now)
	local startedAt = ns.cooldownStarts[key]
	if startedAt == nil then
		return false
	end
	local duration = entry and entry.duration
	if type(duration) ~= "number" or duration <= 0 then
		return false
	end
	return (now - startedAt) < duration
end

ns.cooldownGeneration = 0
ns.trackerGeneration = 0

function ns:MarkCooldownsDirty()
	ns.cooldownGeneration = ns.cooldownGeneration + 1
end

function ns:MarkTrackersDirty()
	ns.trackerGeneration = ns.trackerGeneration + 1
end

---------------------------------------------------------------------
-- RANK-01/RANK-02/ADD-03 (Phase 37) -- rank family resolution.
--
-- The boolean defined immediately below is the milestones one sanctioned runtime
-- flavour check, licensed by explicit user decision 2026-09-20 recorded in
-- .planning/phases/37-add-panel-rank-grouping/37-CONTEXT.md: the user was offered the
-- data-driven alternative (show the "cover all ranks" checkbox only when a spell resolves
-- to a multi-rank family, which needs no flavour check at all) and explicitly declined it,
-- wanting the control to simply exist on Forever and not exist on retail. No second
-- flavour check may be added anywhere in this addon; everything else stays on
-- data-absence / capability checks, per the locked v0.3 constraint this narrows but does
-- not repeal.
---------------------------------------------------------------------

local buildInterfaceVersion = select(4, GetBuildInfo())
-- The locked issecretvalue-before-comparison rule applies even here, to an API that
-- cannot plausibly return a secret -- the cost of following it is nothing and the cost of
-- an exception is a precedent. A non-number (the secret case included) short-circuits the
-- `and` chain below to false before the range comparison ever runs: absent the ability to
-- tell, do not offer the control. Forever is the 16000-19999 range; retail Midnight is
-- 120100.
local buildVersionIsNumber = not issecretvalue(buildInterfaceVersion) and type(buildInterfaceVersion) == "number"
-- ONE range comparison, two named consumers. Adding a second test would be a second flavour
-- check and the constraint above forbids that; naming the same answer twice is not, and it keeps
-- each consumer honest about WHY it cares rather than borrowing a flag that means something else.
local isForeverBuild = buildVersionIsNumber and buildInterfaceVersion >= 16000 and buildInterfaceVersion < 20000
ns.CLIENT_HAS_SPELL_RANKS = isForeverBuild
-- Retail Midnight ships racials in the Cooldown Manager already, so TBT's racial meta-tracker
-- would be a worse duplicate of something the player can simply add to a CDM category -- and with
-- Merge Mode on, it would sit in the same container as the CDM's own copy. It is offered on
-- Forever alone (user decision, 2026-09-23).
ns.CLIENT_IS_FOREVER = isForeverBuild

-- Dedupes while appending id to list. Drops id silently (no insert) unless it survives the
-- issecretvalue/type/positivity screen -- called for every candidate ns:ResolveRankFamily
-- considers, so this is the single point that keeps a secret or malformed value out of a
-- rank family.
local function AddFamilyID(list, seen, id)
	if issecretvalue(id) or type(id) ~= "number" or id <= 0 then
		return
	end
	if seen[id] then
		return
	end
	seen[id] = true
	table.insert(list, id)
end

-- Same idiom as the TOOL-01 tooltips RelatedID below, but id is a parameter instead of a
-- closed-over upvalue, so this is defined once at file scope and allocates no closure per
-- call -- ns:ResolveRankFamily can run once per covered tracker on every rebuild. Returns
-- nil unless fn is callable, pcall(fn, id) succeeds, and the result survives the
-- issecretvalue/type screen.
local function RelatedSpellID(fn, id)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, other = pcall(fn, id)
	if not ok or issecretvalue(other) or type(other) ~= "number" then
		return nil
	end
	return other
end

-- RANK-01/RANK-02: given a spellID, returns a freshly allocated array of every distinct
-- numeric ID that is the same spell at a different rank or under a different override --
-- including spellID itself -- or nil when spellID is not a positive number. Called only
-- from ns:RebuildRankIndex, never from the cast path; see that function for the hot-path
-- split this preserves.
function ns:ResolveRankFamily(spellID)
	if issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end

	local family = {}
	local seen = {}
	AddFamilyID(family, seen, spellID)

	-- Step 1: seed with base/override. Cheap, and what covers retail-style overrides. Not
	-- the load-bearing mechanism on a vanilla client -- see step 3.
	local seedBase = RelatedSpellID(C_Spell and C_Spell.GetBaseSpell, spellID)
	if seedBase then
		AddFamilyID(family, seen, seedBase)
	end
	local seedOverride = RelatedSpellID(C_Spell and C_Spell.GetOverrideSpell, spellID)
	if seedOverride then
		AddFamilyID(family, seen, seedOverride)
	end

	-- Step 2: the distinct spell names of the seeds so far -- what step 3 matches the
	-- spellbook scan against. Vanilla ships every rank of a spell as a same-name spellbook
	-- entry, which is what actually finds siblings a base/override call cannot reach.
	local names = {}
	local namesSeen = {}
	for _, id in ipairs(family) do
		local info = C_Spell.GetSpellInfo(id)
		if info then
			local infoName = info.name
			if not issecretvalue(infoName) and type(infoName) == "string" and infoName ~= "" then
				if not namesSeen[infoName] then
					namesSeen[infoName] = true
					table.insert(names, infoName)
				end
			end
		end
	end

	-- Step 3: name-matched spellbook scan. Capability-guarded on every symbol it touches --
	-- a client lacking any of them degrades to base/override-only resolution, a silent
	-- no-op, never a Lua error. This never actually runs on retail: ns:RebuildRankIndex
	-- early-outs before calling this function at all when no tracked entry carries
	-- coverAllRanks, and on retail no entry ever can, because the checkbox that sets it
	-- does not exist there.
	if
		C_SpellBook
		and C_SpellBook.GetNumSpellBookSkillLines
		and C_SpellBook.GetSpellBookSkillLineInfo
		and C_SpellBook.GetSpellBookItemInfo
		and Enum
		and Enum.SpellBookSpellBank
		and Enum.SpellBookItemType
	then
		local newFromScan = {}
		local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
		if not issecretvalue(numSkillLines) and type(numSkillLines) == "number" then
			for skillLineIndex = 1, numSkillLines do
				local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
				if skillLineInfo then
					local offset = skillLineInfo.itemIndexOffset
					local count = skillLineInfo.numSpellBookItems
					if
						not issecretvalue(offset)
						and type(offset) == "number"
						and not issecretvalue(count)
						and type(count) == "number"
					then
						for slot = offset + 1, offset + count do
							local itemInfo = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
							if itemInfo then
								local itemType = itemInfo.itemType
								local itemName = itemInfo.name
								if
									not issecretvalue(itemType)
									and itemType == Enum.SpellBookItemType.Spell
									and not issecretvalue(itemName)
									and type(itemName) == "string"
								then
									for _, name in ipairs(names) do
										if itemName == name then
											-- actionID is the base spell ID, spellID is the
											-- overriding one -- on a ranked client they can
											-- differ, so both are candidates.
											AddFamilyID(family, seen, itemInfo.actionID)
											AddFamilyID(family, seen, itemInfo.spellID)
											table.insert(newFromScan, itemInfo.actionID)
											table.insert(newFromScan, itemInfo.spellID)
											break
										end
									end
								end
							end
						end
					end
				end
			end
		end

		-- Step 4: one bounded pass, explicitly NOT recursive -- for each ID step 3 added,
		-- add its base/override too. This is what lets a user who added the rank they cast
		-- still reach the ID the CDM holds (RANK-02). The family is a set and this pass
		-- runs once, not to a fixed point.
		for _, id in ipairs(newFromScan) do
			local scannedBase = RelatedSpellID(C_Spell and C_Spell.GetBaseSpell, id)
			if scannedBase then
				AddFamilyID(family, seen, scannedBase)
			end
			local scannedOverride = RelatedSpellID(C_Spell and C_Spell.GetOverrideSpell, id)
			if scannedOverride then
				AddFamilyID(family, seen, scannedOverride)
			end
		end
	end

	return family
end

-- RANK-01: [ownerKey] = { id, id, ... } -- every numeric ID that drives ownerKeys timer,
-- including ownerKeys own ID. Rebuilt; freshly allocated each rebuild rather than wiped
-- in place, because a live proc in ns.activeTimers can hold a reference to one of these
-- arrays as its aliveBuffs (BuffEngine.lua) -- wiping it in place would silently empty a
-- running timers cancellation list.
ns.rankFamilies = {}

-- RANK-01: [castSpellID] = ownerKey -- flat map from any ID in a family to the tracker
-- slot that owns it, excluding IDs that are themselves tracker slots. Rebuilt; wiped in
-- place with wipe() per the repos GC-pressure convention -- nothing holds a reference to
-- this table across a rebuild the way ns.rankFamilies is held.
ns.rankIndex = {}

-- The same map for COOLDOWN trackers. Two indexes rather than one, because a spell may now be
-- covered as a buff and as a cooldown at the same time and a single [castSpellID] = ownerKey map
-- could only answer for one of them.
ns.rankIndexCooldown = {}

-- Module-level reusable scratch table for the covered-owner list below, wiped with wipe()
-- each rebuild rather than reallocated, per the repos GC-pressure convention.
local rebuildOwners = {}

-- RANK-01/RANK-02: rebuilds ns.rankIndex and ns.rankFamilies from ns.db.trackedBuffs.
-- Event-driven only -- called from the SPELLS_CHANGED and PLAYER_ENTERING_WORLD branches
-- below. Never per-cast, never per-frame. ns:OnSpellCastSucceeded's hot-path read is a
-- single ns.rankIndex[spellID] lookup; every pcall, every C_Spell call and the entire
-- spellbook walk happen only in here.
function ns:RebuildRankIndex()
	-- Can in principle be called from an event handler before ADDON_LOADED has run.
	if not ns.db or not ns.db.trackedBuffs then
		return
	end

	wipe(rebuildOwners)
	for k, entry in pairs(ns.db.trackedBuffs) do
		-- Both namespaces. A cooldown tracker's key is a string, so the old numeric-only test
		-- silently excluded every covered cooldown from the index -- meaning a ranked cast would
		-- start its buff timer and not its cooldown.
		if entry.coverAllRanks and (type(k) == "number" or ns:CooldownKeySpellID(k)) then
			table.insert(rebuildOwners, k)
		end
	end

	-- Early-out before touching C_SpellBook at all when nothing is covered -- this is what
	-- costs a retail client nothing: the checkbox that sets coverAllRanks does not exist
	-- there, so this list is always empty on retail.
	if #rebuildOwners == 0 then
		wipe(ns.rankIndex)
		wipe(ns.rankIndexCooldown)
		wipe(ns.rankFamilies)
		return
	end

	-- pairs() order is not deterministic, and two families can legitimately claim the same
	-- ID -- sorting means the same client produces the same index every time, rather than
	-- a coin flip on which owner wins a contested ID. Compared as strings because the list now
	-- mixes numeric buff keys with "cd:" cooldown keys, and Lua refuses to order those against
	-- each other.
	table.sort(rebuildOwners, function(a, b)
		return tostring(a) < tostring(b)
	end)

	wipe(ns.rankIndex)
	-- Do NOT wipe the tables inside ns.rankFamilies -- a live proc may hold a reference to
	-- one of those arrays as its aliveBuffs (see the ns.rankFamilies comment above).
	-- Rebuild the outer table fresh instead, so a removed owners old array is simply
	-- dropped from the map, not mutated out from under a holder.
	ns.rankFamilies = {}

	wipe(ns.rankIndexCooldown)

	for _, ownerKey in ipairs(rebuildOwners) do
		-- ResolveRankFamily wants the spell, not the key.
		local ownerSpellID = ns:CooldownKeySpellID(ownerKey) or ownerKey
		local family = ns:ResolveRankFamily(ownerSpellID)
		if family then
			ns.rankFamilies[ownerKey] = family
			-- One index per namespace. A single map could not answer both, and a spell may
			-- legitimately be covered as a buff AND as a cooldown now that the schema allows it.
			local index = (ownerSpellID ~= ownerKey) and ns.rankIndexCooldown or ns.rankIndex
			local ownNamespaceKey = (ownerSpellID ~= ownerKey) and ns.COOLDOWN_KEY_PREFIX or ""
			for _, id in ipairs(family) do
				-- An ID that is itself a tracker slot owns itself -- the index must never
				-- shadow a direct lookup. First owner in sorted order wins a contested ID.
				-- Checked within the OWN namespace: a buff tracker on rank 2 must not stop a
				-- cooldown family from claiming rank 2 for the cooldown index.
				local directKey = (ownNamespaceKey == "") and id or (ownNamespaceKey .. id)
				if ns.db.trackedBuffs[directKey] == nil and index[id] == nil then
					index[id] = ownerKey
				end
			end
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- RANK-01: the only two events that can change what the players spellbook contains.
-- BuffEngine.lua adds its own ns:RebuildRankIndex() call sites on tracker add/remove
-- (Plan 02); this file only wires the two spellbook-changing events.
eventFrame:RegisterEvent("SPELLS_CHANGED")

-- Phase 38 (CD-04): RegisterEvent raises on an event name the client does not know, and
-- this addon may not assume a given event exists on every flavour. C_EventUtils.IsEventValid
-- is deliberately NOT used -- its own presence is not guaranteed, so guarding with it would
-- replace one unguarded assumption with another. This is a capability check on the event,
-- never a client-identity check; a client without the event silently gets no live sweep
-- updates rather than a load error.
local function TryRegisterEvent(frame, eventName)
	return pcall(frame.RegisterEvent, frame, eventName)
end

-- Phase 38 (CD-04): SPELL_UPDATE_CHARGES is a deliberate divergence from Blizzard --
-- CooldownViewerCooldownMixin refreshes charge info on SPELL_UPDATE_USES, not
-- SPELL_UPDATE_CHARGES. Both events are real and Blizzard_ActionBar uses SPELL_UPDATE_CHARGES
-- for the same purpose, so this is a valid choice, not a mismatch.
TryRegisterEvent(eventFrame, "SPELL_UPDATE_COOLDOWN")
TryRegisterEvent(eventFrame, "SPELL_UPDATE_CHARGES")

-- Phase 43.1: item cooldowns do not fire the spell events. Blizzard's own cooldown item listens
-- to BAG_UPDATE_COOLDOWN for exactly this (CooldownViewerItemMixin:OnBagUpdateCooldownEvent,
-- CooldownViewer.lua:230), and without it a trinket used in combat kept its old sweep until some
-- unrelated spell event happened to move the generation.
TryRegisterEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

-- Phase 43.1: what the trinket and pot meta-trackers resolve from. Their at-rest scan used to
-- run from exactly one place -- the CDM tab being built -- so opening the Cooldown Manager in
-- combat found the scan combat-gated and the tile drew a question mark, while opening it out of
-- combat did not. That is the "sometimes" in the report. These are the three moments the answer
-- can actually change, plus combat ending, which is the first moment the gated scan can run.
TryRegisterEvent(eventFrame, "PLAYER_EQUIPMENT_CHANGED")
TryRegisterEvent(eventFrame, "BAG_UPDATE_DELAYED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= addonName then
			return
		end

		if not TerribleBuffTrackerDB then
			TerribleBuffTrackerDB = {
				trackedBuffs = {},
			}
		end
		ns.db = TerribleBuffTrackerDB

		if not ns.db.trackedBuffs then
			ns.db.trackedBuffs = {}
		end

		if ns.db.tbtVisible == nil then
			ns.db.tbtVisible = true
		end

		-- Phase 35.1 (CFG-03): ns.db.mergeMode is an addon-wide flag, a sibling of tbtVisible
		-- rather than a containerSettings field -- it is one switch across all four categories,
		-- not a per-container setting. Written by the checkbox in CDMTab.lua. Nothing reads this
		-- flag until Phase 40 (STEAL-01...STEAL-08).
		if ns.db.mergeMode == nil then
			ns.db.mergeMode = false
		end

		if not ns.db.containerSettings then
			ns.db.containerSettings = {}
		end

		-- CONT-04/05: two new ns.db keys, seeded idempotently like every default above --
		-- no schemaVersion bump, the same rule Phase 35.1 used for mergeMode. userContainers
		-- is an array (creation order is user-visible: CDM tab section order and Edit Mode
		-- label order). nextContainerId is a monotonic counter that never decrements, so a
		-- deleted container's key is never reissued.
		if not ns.db.userContainers then
			ns.db.userContainers = {}
		end
		if ns.db.nextContainerId == nil then
			ns.db.nextContainerId = 1
		end

		-- CONT-04/05: this position is load-bearing, not cosmetic -- it must stay exactly
		-- here, between the two guards above and the registry settings pass below. It is
		-- inside ADDON_LOADED, so it runs before PLAYER_ENTERING_WORLD fires
		-- ns:InitEditModeFrames/ns:InitDisplay and before ns:InitCDMTab, all three of which
		-- already loop the whole registry and so pick user containers up with no extra code.
		-- It is BEFORE the settings pass below, so that existing loop seeds each user
		-- container's containerSettings table for free instead of needing new seeding code.
		ns:RehydrateUserContainers()

		-- Registry-driven pass (CONT-01): seed a missing container's settings from its
		-- kind's default set, and backfill new fields onto settings that already exist. See
		-- ns.EnsureContainerSettings above for the idempotency/aliasing rationale.
		for _, def in ipairs(ns.CONTAINERS) do
			ns.EnsureContainerSettings(def)
		end

		ns:InitBuffEngine()
		-- Registers Options > AddOns > TerribleBuffTracker. Safe this early: it builds frames
		-- and reads ns.db, and touches no CDM or Edit Mode object.
		ns:InitConfigPanel()

		print(
			"|cff00ccffTerribleBuffTracker|r loaded. Type |cff00ff00/tbt|r or |cff00ff00/terriblebufftracker|r to open settings."
		)
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- RANK-01: called unconditionally, outside the ns.displayInitialized one-shot guard
		-- below, so a rebuild runs on every world entry (reload, zoning into an instance,
		-- etc.), not just the first. Deliberately NOT called from ADDON_LOADED above -- the
		-- spellbook is not populated that early, and the scan would return the seed only.
		ns:RebuildRankIndex()
		-- Phase 38 (CD-04): also unconditional and outside the one-shot guard, for the same
		-- reason -- a cooldown handle can be stale after a reload or a zone-in, not just once.
		ns:MarkCooldownsDirty()
		if not ns.displayInitialized then
			ns.displayInitialized = true
			ns:InitEditModeFrames()
			ns:InitDisplay()
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if unit == "player" then
			ns:OnSpellCastSucceeded(spellID)
		end
	elseif event == "UNIT_AURA" then
		local unit, updateInfo = ...
		if unit == "player" then
			ns:OnUnitAura(updateInfo)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns:ClearSecretGateLog()
		-- The first moment the combat-gated at-rest scan can run. A trinket swapped or a potion
		-- bought mid-fight resolves here rather than waiting for the CDM tab to be rebuilt.
		ns:RefreshProvidersAtRest()
		-- Phase 38 (CD-04): leaving combat is not reliably "the first moment a secret charge
		-- count can be read again" -- C_Secrets.ShouldCooldownsBeSecret() stacks encounter,
		-- challenge-mode and restricted-map restrictions on top of combat, so a player who
		-- reloads mid-M+ may get no readable moment for the whole run. That is safe (charge
		-- text just stays hidden), not a crash. Still worth stamping here: it is one of the
		-- moments a previously-secret charge count CAN become readable. Flagged for Phase 44's
		-- retail M+ pass.
		ns:MarkCooldownsDirty()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		ns:ClearSecretGateLog()
	elseif event == "SPELLS_CHANGED" then
		ns:RebuildRankIndex()
		ns:MarkCooldownsDirty()
	elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_COOLDOWN" then
		ns:MarkCooldownsDirty()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
		-- Combat-gated inside the wrapper, so this is safe to call unconditionally; a change made
		-- in combat is picked up by the PLAYER_REGEN_ENABLED call above.
		ns:RefreshProvidersAtRest()
	end
end)

SLASH_TERRIBLEBUFFTRACKER1 = "/tbt"
SLASH_TERRIBLEBUFFTRACKER2 = "/terriblebufftracker"
SlashCmdList["TERRIBLEBUFFTRACKER"] = function(msg)
	local cmd = msg and msg:lower():match("^(%S+)") or ""
	if cmd == "merge" then
		-- Diagnostic only, and deliberately NOT one of the development commands that were
		-- removed: this one answers a question about the player's own live CDM configuration
		-- that nothing else in the UI can, which is why it is worth shipping.
		ns:PrintMergeDiagnostics()
	elseif cmd == "debug" then
		ns.debugLogging = not ns.debugLogging
		local state = ns.debugLogging and "|cff00ff00ON|r" or "|cffff6600OFF|r"
		print("|cff00ccffTBT|r: Debug logging " .. state)
	else
		-- "/tbt" now opens TBT's OWN settings panel rather than Blizzard's Cooldown Manager
		-- window. The CDM tabs are still where trackers are filed into containers; everything
		-- that is not about a specific tracker moved here (user decision, 2026-09-22).
		ns:OpenConfigPanel()
	end
end

---------------------------------------------------------------------
-- TOOL-01 (Phase 27.1) — append the hovered spell's numeric ID to every
-- spell tooltip in the game UI. The API is verified present on both
-- flavors at Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua
-- (Forever on the forever-beta branch of BigWigsMods/WoWUI, retail 12.1
-- in the local wow-ui-source clone), so one shared implementation serves
-- both with no branch (D-01). The guard below is an existence check on
-- the API symbol itself — a capability check, not a client-identity
-- check — so a future client lacking it degrades to a silent no-op
-- rather than a load error (D-05). No tooltip:Show() call is needed
-- here: ProcessInfo shows the tooltip on the line right after it runs
-- the post-calls.
--
-- Scope (user request, 2026-09-18): spells AND auras/buffs, never items.
-- Enum.TooltipDataType is an engine-side enum with no generated-doc entry
-- on either flavour, so a given member may simply not exist on Forever.
-- Registering per-member would then error at load, so instead we register
-- once for AllTypes and filter on tooltipData.type against an allow-set
-- built defensively — a member that does not exist contributes nothing
-- and costs nothing, and items are excluded by never being added.
--
-- Spell and aura IDs are labelled differently on purpose. TBT detects
-- casts via UNIT_SPELLCAST_SUCCEEDED, so the ID that belongs in the Add
-- dialog is the CAST spell's ID. A buff's own aura ID is frequently a
-- different number, and printing both under one label would invite adding
-- the wrong one and then wondering why the timer never fires.
---------------------------------------------------------------------

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local SPELL_TYPE = Enum.TooltipDataType.Spell
	local AURA_TYPES = {}
	for _, member in ipairs({ "UnitAura", "UnitBuff", "UnitDebuff" }) do
		local value = Enum.TooltipDataType[member]
		if value ~= nil then
			AURA_TYPES[value] = true
		end
	end

	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes or "ALL", function(tooltip, tooltipData)
		if not (tooltip and tooltip.AddLine and tooltipData) then
			return
		end
		local dataType = tooltipData.type
		local isSpell = SPELL_TYPE ~= nil and dataType == SPELL_TYPE
		local isAura = AURA_TYPES[dataType] == true
		if not (isSpell or isAura) then
			return
		end
		local id = tooltipData.id
		-- issecretvalue() FIRST, before any comparison or concatenation — it is safe on nil
		-- and on secrets, unlike everything below (same rule as BuffEngine.lua's aura read).
		-- In combat an aura tooltip's id arrives as a SECRET number: type() still reports
		-- "number", so a type check alone passes and gives false confidence, and the first
		-- ~= or .. against it throws once execution is tainted by this addon. Observed
		-- 2026-09-18 hovering a buff in combat.
		--
		-- Consequence, and it is a platform limit rather than something to work around: no
		-- ID line appears for a restricted aura while in combat. Out of combat it shows
		-- normally, and an aura whose spell is on Blizzard's never-secret allowlist still
		-- shows even in combat — which is why this gates on the VALUE being secret rather
		-- than on C_Secrets.ShouldAurasBeSecret(), a blanket combat gate that would
		-- needlessly suppress the allowlisted case too.
		if issecretvalue(id) or type(id) ~= "number" then
			return
		end
		tooltip:AddLine((isAura and "Aura spell ID: " or "Spell ID: ") .. id, 0.8, 0.8, 0.8)

		-- A spell and aura tooltip agree on this number because tooltipData.id IS the
		-- spell ID in both cases — one field, not two that coincide. The divergence that
		-- actually matters for tracking is a spell override: the ID a tooltip shows can
		-- differ from the base spell, and UNIT_SPELLCAST_SUCCEEDED may report the other
		-- one. Surface both sides whenever the client says they differ, so a mismatch is
		-- visible at hover time instead of showing up as a timer that never fires.
		-- Existence-checked (capability, not client identity) and pcall'd because these
		-- can reject an ID the client does not fully know. Tooltips fire on hover, not
		-- per frame, so this is not a hot path.
		local function RelatedID(fn)
			if type(fn) ~= "function" then
				return nil
			end
			local ok, other = pcall(fn, id)
			-- Same rule again, and it is needed independently: even with a non-secret id,
			-- these APIs can hand back a secret number, and `other ~= id` then throws. The
			-- pcall does NOT cover it — the call succeeds (ok == true) and the comparison
			-- after it is what raises. So screen the return value before comparing it.
			if not ok or issecretvalue(other) or type(other) ~= "number" then
				return nil
			end
			if other ~= id then
				return other
			end
			return nil
		end

		local base = RelatedID(C_Spell and C_Spell.GetBaseSpell)
		if base then
			tooltip:AddLine("Base spell ID: " .. base, 0.9, 0.7, 0.4)
		end
		local override = RelatedID(C_Spell and C_Spell.GetOverrideSpell)
		if override then
			tooltip:AddLine("Override spell ID: " .. override, 0.9, 0.7, 0.4)
		end
	end)
end
