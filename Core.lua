local addonName, ns = ...

-- Phase 35 (CONT-01): the base containers, in the user-visible order fixed by 35-CONTEXT.md --
-- four since Phase 35, five since Phase 57.2 added `reminders` (Buff Reminders) last. `bars`
-- and `buffs` are the v0.3.0 section keys and must never change —
-- every `entry.section` written before this phase is already correct for them. `essential`
-- and `utility` are new, id-shaped keys and are Phase 40's merge-mode mapping target
-- (Enum.CooldownViewerCategory.Essential / .Utility). No consumer may branch on a key
-- string; branch on `kind` ("bar" or "icon") instead.
-- Phase 40 (STEAL-03): `cdmCategoryName` is a NAME, not the enum value itself — a
-- file-scope reference to the CDM category enum would be a load-time dependency on an
-- enum that may not exist on every flavour, so MergeMode.lua resolves it by name behind
-- a nil check at runtime instead.
-- TRACKER CATEGORIES (user decision, 2026-09-22; third category Phase 57.2). Every container and
-- every tracker belongs to exactly one of three categories, and nothing moves between them:
--
--   "buffs"     -- Tracked Buffs and Tracked Bars. Everything that existed before v0.4.0.
--   "spells"    -- Essential Cooldowns and Utility Cooldowns. The cooldown trackers v0.4.0 adds.
--   "reminders" -- Buff Reminders and user containers made for reminders. It has no CDM
--                  counterpart: no cdmViewerGlobal / cdmCategoryName, so merge and steal mode
--                  skip it exactly as they skip a user container.
--
-- The CDM tab surfaces one tab per category, and the config page is shared. A tracker's
-- category is derived, never stored: ns:GetTrackerCategory reads trackerType, so no migration
-- and no second source of truth. A container's category IS stored, because a user-created
-- container has no tracker to derive it from.
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
-- a player has already placed. The seeds apply to a fresh install, or to a container with no
-- saved position yet.
--
-- The reminders container is the exception to "copied from Blizzard": it mirrors no CDM viewer,
-- so its seed is hand-picked by the user (2026-09-29): BOTTOMLEFT of UIParent at (850, 580), the
-- absolute x/y read off the in-game frame stack.
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
	{
		key = "reminders",
		title = "Buff Reminders",
		category = "reminders",
		frameName = "TBTReminderContainer",
		kind = "icon",
		defaultPoint = "BOTTOMLEFT",
		defaultRelativePoint = "BOTTOMLEFT",
		defaultX = 850,
		defaultY = 580,
	},
}

-- The category a tracker belongs to, derived from what it is rather than stored alongside it.
-- Phase 38 made "cooldowns are icons, never bars" a locked decision, and Phase 47 widened it to
-- item trackers -- both render icon-only through ApplyCooldownSlot. Phase 53 (NAME-01/NAME-02)
-- folds both cases into ns:IsCooldownSlotEntry: a userCd or metaSkillCd tracker, or a metaItem
-- tracker backed by a numeric itemID (a bag item, not trinket/pot), files under "spells";
-- everything else -- plain buffs, meta skill buffs, racials -- is a buff. It reads only the
-- canonical kinds, so it is correct only once schema v8 (ns:MigrateKindKeys) has stamped them: a
-- pre-v8 "cooldown"/"item" entry answers "buffs" until v8 runs. Phase 57.2 (REM-02): a reminder
-- (ns:IsReminderEntry, any kind in ns.REMINDER_KINDS) files under "reminders", tested first.
function ns:GetTrackerCategory(entry)
	if ns:IsReminderEntry(entry) then
		return "reminders"
	end
	if ns:IsCooldownSlotEntry(entry) then
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

-- 0=Right/Down, 1=Left/Up, 2=Centered. Centered is offered on BUFF- and REMINDER-category icon
-- containers (Phase 57.2: anything but spells), and is their default (user decision,
-- 2026-09-22): a buff container is read at a glance mid-fight, and a run that grows out from a
-- fixed midpoint stays where the eye already is, where a left-anchored run moves its own
-- contents every time something drops. The default seeds only a missing setting (the new
-- reminders base container, a new reminders user container); no saved setting is rewritten.
--
-- Spells containers keep Right/Down. Their whole point is a stable slot per cooldown, and the
-- Edit Mode dropdown does not offer Centered there, so this is the one place the rule is
-- expressed. Bars have no direction control at all and take 0 as they always have.
ns.GROWTH_CENTERED = 2

function ns:DefaultGrowthDirection(def)
	if def.kind ~= "bar" and ns:GetContainerCategory(def) ~= "spells" then
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
-- category is "buffs", "spells" or "reminders" (Phase 57.2) and defaults to "buffs", which is
-- what every container created before the choice existed was. A SPELLS container is icon-only,
-- enforced here rather than only in the dialog: "cooldowns are icons, never bars" is a locked
-- decision from Phase 38, and the render path relies on it -- RenderBarContainer skips a cooldown
-- tracker outright, so a bar-kind spells container would be a container nothing could ever draw
-- into. A REMINDERS container is icon-only for the same reason: a reminder has no timer, so there
-- is no bar to fill.
function ns:CreateUserContainer(title, kind, category)
	if kind ~= "bar" and kind ~= "icon" then
		return nil
	end
	category = category or "buffs"
	if category ~= "buffs" and category ~= "spells" and category ~= "reminders" then
		return nil
	end
	if (category == "spells" or category == "reminders") and kind ~= "icon" then
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
-- Tracker kind scheme (NAME-01/NAME-02, Phase 53). Eight canonical kinds, one table that mints and
-- parses every saved key -- no other file may write a key literal or a "^prefix:" pattern.
--
--   userBuff     -- a user-made buff tracker
--   userCd       -- a user-made cooldown tracker
--   userReminder -- a user-made buff reminder: shows only while its aura is missing (Phase 57.2)
--   metaSkill    -- a built-in skill, buff side: Lust and every racial buff
--   metaSkillCd  -- a built-in skill cooldown tile: racial cooldowns
--   metaReminder -- a built-in reminder (Phase 57.4): a class buff from the Providers.lua table,
--                   behaving exactly like a user reminder.
--   metaItem     -- a built-in item: trinket, pot, and a bag consumable tracked by itemID.
--                   Trinket/pot and a bag item are told apart by entry.itemID (numeric = bag
--                   item; nil = trinket/pot), never by the key shape -- all three share metaItem.
--   userItem     -- reserved for a future custom item tracker; no producer yet.
--
-- Every saved key has the shape "<kind>:<id>" -- ns:TrackerKey(kind, id) mints them, and the only
-- other concatenations are Providers.lua's few sites that prepend the precomputed
-- ns.KEY_PREFIX entries (META_SKILL_PREFIX/META_ITEM_PREFIX) directly. The legacy "cd:"/"item:"/"racial:" prefixes this scheme replaces survive ONLY
-- as frozen literals inside BuffEngine.lua's old migration blocks (v6, v7) -- nowhere else may a
-- string pattern name one.
ns.KIND = {
	USER_BUFF = "userBuff",
	USER_CD = "userCd",
	USER_REMINDER = "userReminder",
	META_SKILL = "metaSkill",
	META_SKILL_CD = "metaSkillCd",
	META_REMINDER = "metaReminder",
	META_ITEM = "metaItem",
	USER_ITEM = "userItem",
}

ns.KEY_SEPARATOR = ":"

-- ns.KEY_PREFIX[kind] = "<kind>:" for every kind -- precomputed for the few remaining call sites
-- that must stay a single concat. KEY_ID_PATTERNS and KNOWN_KINDS are file-local: nothing outside
-- this file mints a pattern or tests kind membership directly, everything goes through the
-- functions below. Declared here, above every function that reads them, per the upvalue-order
-- trap (this repo's most-repeated bug).
ns.KEY_PREFIX = {}
local KEY_ID_PATTERNS = {}
local KNOWN_KINDS = {}
for _, kind in pairs(ns.KIND) do
	ns.KEY_PREFIX[kind] = kind .. ns.KEY_SEPARATOR
	KEY_ID_PATTERNS[kind] = "^" .. kind .. ns.KEY_SEPARATOR .. "(%d+)$"
	KNOWN_KINDS[kind] = true
end

-- Mints a canonical key. Every other file calls this instead of building a "<kind>:<id>" string
-- itself, except Providers.lua's META_SKILL_PREFIX/META_ITEM_PREFIX sites, which prepend the same
-- ns.KEY_PREFIX entry this function reads.
function ns:TrackerKey(kind, id)
	return ns.KEY_PREFIX[kind] .. id
end

-- The three non-numeric meta ids, spelled out once so no caller hardcodes "metaSkill:lust" etc.
ns.META_KEY = {
	LUST = ns:TrackerKey(ns.KIND.META_SKILL, "lust"),
	TRINKET = ns:TrackerKey(ns.KIND.META_ITEM, "trinket"),
	POT = ns:TrackerKey(ns.KIND.META_ITEM, "pot"),
}

-- The kind a key belongs to, or nil for anything malformed or pre-migration.
function ns:KeyKind(key)
	if type(key) ~= "string" then
		return nil
	end
	local kind = key:match("^(%a+):")
	return kind and KNOWN_KINDS[kind] and kind or nil
end

-- The numeric id a key names WITHIN one specific kind, or nil -- "userBuff:6673" answers 6673 for
-- kind userBuff and nil for every other kind, and a meta id like "metaSkill:lust" always answers
-- nil (it has no numeric id).
function ns:KeyNumericID(key, kind)
	if type(key) ~= "string" then
		return nil
	end
	local pattern = KEY_ID_PATTERNS[kind]
	if not pattern then
		return nil
	end
	local id = key:match(pattern)
	return id and tonumber(id) or nil
end

-- The numeric spell ID a cooldown key names, or nil for anything else -- a buff key, a meta item
-- key, or a malformed string. Callers that want "the spell this key is about" regardless of
-- namespace should read entry.spellID instead.
function ns:CooldownKeySpellID(key)
	return ns:KeyNumericID(key, ns.KIND.USER_CD) or ns:KeyNumericID(key, ns.KIND.META_SKILL_CD)
end

-- The numeric item ID a metaItem key names, or nil for anything else -- including the two
-- non-numeric metaItem ids, "metaItem:trinket" and "metaItem:pot".
function ns:ItemKeyItemID(key)
	return ns:KeyNumericID(key, ns.KIND.META_ITEM)
end

-- The numeric spell ID a metaSkill key names, or nil for anything else -- including
-- "metaSkill:lust", which has no numeric id.
function ns:RacialKeySpellID(key)
	return ns:KeyNumericID(key, ns.KIND.META_SKILL)
end

-- The numeric spell ID any spell-shaped key names -- userBuff, userCd, userReminder, metaSkill,
-- metaSkillCd or metaReminder -- or nil for a metaItem key, a meta id with no number, or a malformed
-- string. Icon and tooltip fallbacks that only know "this key is about some spell" go through here
-- instead of picking one kind and missing the others. The metaReminder kind (Phase 57.4) parses
-- here too, so an untracked Suggested class-buff tile's key resolves to its spell.
function ns:SpellKeySpellID(key)
	return ns:KeyNumericID(key, ns.KIND.USER_BUFF)
		or ns:KeyNumericID(key, ns.KIND.USER_CD)
		or ns:KeyNumericID(key, ns.KIND.USER_REMINDER)
		or ns:KeyNumericID(key, ns.KIND.META_SKILL)
		or ns:KeyNumericID(key, ns.KIND.META_SKILL_CD)
		or ns:KeyNumericID(key, ns.KIND.META_REMINDER)
end

-- The v8 migration's kind guess for a legacy "cd:<id>" key, which the dialog and the Suggested
-- racial tile both wrote before the kind scheme existed: a racial spellID becomes metaSkillCd.
-- Migration-only since 2026-09-29 -- ns:AddTrackedBuff no longer calls it, because typed input
-- is always a user kind (user decision). ns:IsRacialSpellID is Providers.lua's (plan 53-03);
-- Core.lua only consumes it, since the TOC loads this file first.
function ns:CooldownKindFor(spellID)
	if ns:IsRacialSpellID(spellID) then
		return ns.KIND.META_SKILL_CD
	end
	return ns.KIND.USER_CD
end

-- True for any entry that renders as a cooldown slot (icon-only, ApplyCooldownSlot) rather than a
-- buff -- a user cooldown, a racial cooldown tile, or a bag item with a numeric itemID. Nil-safe.
function ns:IsCooldownSlotEntry(entry)
	if not entry then
		return false
	end
	if entry.trackerType == ns.KIND.USER_CD or entry.trackerType == ns.KIND.META_SKILL_CD then
		return true
	end
	return entry.trackerType == ns.KIND.META_ITEM and type(entry.itemID) == "number"
end

-- True only for a metaItem entry that IS a bag item -- narrower than ns:IsCooldownSlotEntry,
-- which also answers true for trinket/pot. Nil-safe.
function ns:IsBagItemEntry(entry)
	return entry ~= nil and entry.trackerType == ns.KIND.META_ITEM and type(entry.itemID) == "number"
end

-- The reminder kinds (REM-02, Phase 57.2) and THE reminder test. Every "is this a reminder?"
-- question in the addon goes through ns.REMINDER_KINDS or ns:IsReminderEntry, never a direct
-- comparison with ns.KIND.USER_REMINDER -- only user-specific code (minting a user reminder, the
-- add/edit dialog, the user-spell display provider, the user key parser) names that kind. The
-- metaReminder kind (Phase 57.4, a built-in class-buff reminder) is in this set, so the category,
-- the watch index, Display and the dialog's field rules follow with no other change; only the cast
-- namespace and the duplicate check give it its own index. Nil-safe.
ns.REMINDER_KINDS = { [ns.KIND.USER_REMINDER] = true, [ns.KIND.META_REMINDER] = true }

function ns:IsReminderEntry(entry)
	return entry ~= nil and ns.REMINDER_KINDS[entry.trackerType] == true
end

-- The buff-like kinds (Phase 57.2-05, user decision 2026-09-29): a buff or a reminder; every buff
-- rule (timer, aura-loss cancellation, cast rules, rank families, dialog fields) keys on this, and
-- only the display and the category differ. Built from ns.REMINDER_KINDS at file load, so every
-- reminder kind (userReminder and metaReminder) is buff-like for free. Nil-safe.
ns.BUFF_LIKE_KINDS = { [ns.KIND.USER_BUFF] = true }
for kind in pairs(ns.REMINDER_KINDS) do
	ns.BUFF_LIKE_KINDS[kind] = true
end

function ns:IsBuffLikeEntry(entry)
	return entry ~= nil and ns.BUFF_LIKE_KINDS[entry.trackerType] == true
end

-- Phase 57.3 (LOAD-01/LOAD-02): the one load rule that decides whether a tracker runs at all. The
-- UI label is "Load" -- never "visibility", which containers already have. entry.load is nil for
-- When known (the stored-as-nil default), or ALWAYS / NEVER. KNOWN is the resolver's answer and is
-- never saved.
ns.LOAD = { KNOWN = "known", ALWAYS = "always", NEVER = "never" }

-- Built-in kinds carry a fixed load the user cannot edit (LOAD-02, both clients): racial buffs and
-- racial cooldowns and class-buff reminders (metaReminder, Phase 57.4) load when known; trinket,
-- pot, bag items and the reserved userItem kind always.
local FIXED_LOAD = {
	[ns.KIND.META_SKILL] = ns.LOAD.KNOWN,
	[ns.KIND.META_SKILL_CD] = ns.LOAD.KNOWN,
	[ns.KIND.META_REMINDER] = ns.LOAD.KNOWN,
	[ns.KIND.META_ITEM] = ns.LOAD.ALWAYS,
	[ns.KIND.USER_ITEM] = ns.LOAD.ALWAYS,
}

-- The effective load rule for one tracker. Every consumer asks this (or the cached state below)
-- and never special-cases a kind. Lust is a metaSkill key with no spell ID, so it is Always. A
-- built-in kind ignores any saved entry.load; a user entry honours only the exact ALWAYS / NEVER
-- strings, and anything else (nil, a hand edit) reads as When known.
function ns:TrackerLoad(key, entry)
	if not entry then
		return ns.LOAD.ALWAYS
	end
	if key == ns.META_KEY.LUST then
		return ns.LOAD.ALWAYS
	end
	local fixed = FIXED_LOAD[entry.trackerType]
	if fixed then
		return fixed
	end
	local saved = entry.load
	if saved == ns.LOAD.ALWAYS or saved == ns.LOAD.NEVER then
		return saved
	end
	return ns.LOAD.KNOWN
end

-- [key] = true|false, rebuilt only by ns:RebuildTrackerLoad (spellbook, talent, spec, login and
-- tracker-edit moments). Never written per frame or per cast.
ns.trackerLoaded = {}

-- The per-frame and per-cast read: one table lookup, no API call, no allocation. A key never
-- computed -- a Suggested tile, a merge key, a key before the first rebuild -- is loaded.
function ns:IsTrackerLoaded(key)
	return ns.trackerLoaded[key] ~= false
end

local LOAD_REASON_NEVER = "Not loaded: Load is set to Never"
local LOAD_REASON_UNKNOWN = "Not loaded: this character does not know this spell"
local LOAD_REASON_ORPHAN = "Not loaded: no longer offered as a class buff. Remove it"

-- Phase 57.4 review WR-02: a metaReminder whose spell ID has no row in the Providers.lua
-- class-buff table (the row was removed, or its ID corrected to a new one). It is never loaded,
-- so nothing processes it on stale copied data, and ns:ApplyMetaReminderDef leaves it alone. The
-- saved entry is kept (no data deletion); the user removes it from the TBT tab. Nil-guarded:
-- Providers.lua loads after this file, and before it has, nothing counts as an orphan.
function ns:IsOrphanMetaReminder(entry)
	if not entry or entry.trackerType ~= ns.KIND.META_REMINDER or not ns.MetaReminderDef then
		return false
	end
	return ns:MetaReminderDef(entry.spellID) == nil
end

-- Why a tracker is not loaded, or nil when it is. Hover-time only (the TBT tab tile tooltip).
function ns:TrackerLoadReason(key)
	if ns:IsTrackerLoaded(key) then
		return nil
	end
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
	if ns:IsOrphanMetaReminder(entry) then
		return LOAD_REASON_ORPHAN
	end
	if ns:TrackerLoad(key, entry) == ns.LOAD.NEVER then
		return LOAD_REASON_NEVER
	end
	-- Review IN-02: a metaReminder whose row loads on another spell (Blood Pact on Summon Imp)
	-- names that spell, since "this spell" would point at the buff the tile shows. Hover-time only,
	-- so the concatenation is not on any hot path.
	if entry and entry.trackerType == ns.KIND.META_REMINDER and ns.MetaReminderKnownID and ns.SpellLabel then
		local knownID = ns:MetaReminderKnownID(entry.spellID)
		if knownID ~= entry.spellID then
			return "Not loaded: this character does not know " .. ns:SpellLabel(knownID)
		end
	end
	return LOAD_REASON_UNKNOWN
end

-- Phase 57.2-05 review WR-01: seconds after a cast during which a READABLE "absent" read of a
-- buff-like tracker's aura counts as unknown. UNIT_SPELLCAST_SUCCEEDED can arrive before the
-- aura is applied, and an unrelated UNIT_AURA in that gap would otherwise end the timer the cast
-- just started (and show a reminder). Keyed on proc.castAt, stamped by ns:FillUserBuffProc, and
-- read by ns:RefreshAuraStates and ns:ScanActiveTimersForCancellation alike. On ns, not a file
-- local, so both files see it whatever their load order.
ns.CAST_AURA_GRACE = 0.5

-- ownerKey -> GetTime() of the cast that started this tracker's cooldown.
--
-- A custom cooldown tracker runs on the duration the USER typed, not on the game's own cooldown
-- (user decision, 2026-09-22, reversing CD-02). That needs a start time, and the only one
-- available is the cast: UNIT_SPELLCAST_SUCCEEDED is the same signal every buff tracker already
-- runs on, and nothing in it is secret.
--
-- Runtime-only, exactly like ns.activeTimers. Persisting it would restore a cooldown that the
-- game finished while the player was logged out, and there is no way to check.
ns.cooldownStarts = {}

-- A ONE-CAST duration override for a cooldown tracker, keyed exactly as ns.cooldownStarts is and
-- written at the same instant, by the same dispatcher.
--
-- It exists because a handful of abilities have a cooldown that depends on the circumstances of
-- the cast rather than on the ability: night elf Shadowmeld is ten seconds out of combat and two
-- minutes when used in combat as a threat drop. entry.duration cannot carry that -- it is one
-- persisted number, it is what the player sees and may have typed themselves, and rewriting it per
-- cast would make a user-visible setting flicker between two values.
--
-- Lifetime is deliberately one cast: whoever starts the cooldown writes this key on EVERY start,
-- to the override or to nil, so a cast under ordinary conditions erases a previous cast's
-- exception rather than inheriting it. Never persisted, for the same reason ns.cooldownStarts is
-- not -- a cooldown does not survive a logout in any form TBT could honestly reconstruct.
ns.cooldownOverrides = {}

-- The duration this cooldown tracker is running on RIGHT NOW: the current cast's override when it
-- has one, otherwise the tracker's own persisted duration. Every consumer of a cooldown's length
-- goes through here, so "how long is this cooldown" has exactly one answer -- the same reason
-- ns:IsCooldownRunning below exists at all.
function ns:CooldownDuration(key, entry)
	local override = ns.cooldownOverrides[key]
	if type(override) == "number" and override > 0 then
		return override
	end
	return entry and entry.duration
end

-- Is this cooldown tracker mid-cooldown right now? The single answer, shared by the render path
-- and by the preview builder, so "a real cooldown beats a preview" cannot be decided two ways.
-- Plain numbers throughout: the start is GetTime() at the cast, the duration is the player's own.
function ns:IsCooldownRunning(key, entry, now)
	local startedAt = ns.cooldownStarts[key]
	if startedAt == nil then
		return false
	end
	local duration = ns:CooldownDuration(key, entry)
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
-- Forever alone (user decision, 2026-09-23). Phase 57.4: it also gates the class-buff Suggested
-- tiles on the Reminders tab (built-in metaReminder rows carry Forever spell IDs) -- still the same
-- one range comparison.
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

-- The milestone's shared base/override lookup (ns:SpellKnownState, ns:CastRuleFamily);
-- ns:ResolveRankFamily's own seeds predate the milestone and keep their form.
local function BaseAndOverride(id)
	return RelatedSpellID(C_Spell and C_Spell.GetBaseSpell, id),
		RelatedSpellID(C_Spell and C_Spell.GetOverrideSpell, id)
end

-- RANK-01/RANK-02: given a spellID, returns a freshly allocated array of every distinct
-- numeric ID that is the same spell at a different rank or under a different override --
-- including spellID itself -- or nil when spellID is not a positive number. Called only
-- from ns:RebuildRankIndex, never from the cast path; see that function for the hot-path
-- split this preserves. includePetBook (optional, Phase 57.4 MREM-03) adds a step 5 that also
-- matches the pet spellbook by name -- asked only for a pet-spell metaReminder (Blood Pact).
function ns:ResolveRankFamily(spellID, includePetBook)
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

	-- Step 5 (Phase 57.4, MREM-03): the pet spellbook, only when asked. Blood Pact is the imp's
	-- spell, so the player spellbook scan above never sees it. The pet book is populated only
	-- while the pet is out (C_SpellBook.HasPetSpells returns nothing otherwise), which is exactly
	-- when the imp's rank of the aura can be up; SPELLS_CHANGED and UNIT_PET (review WR-01) refresh
	-- it and rebuild the rank index. Takes itemInfo.spellID only, never actionID (a pet action ID
	-- can be packed). A PetAction item may carry no spell ID ("May be nil if item is not a spell"),
	-- so the ID is checked before use and a missing one is reported under /tbt debug rather than
	-- dropped in silence.
	if
		includePetBook
		and C_SpellBook
		and C_SpellBook.HasPetSpells
		and C_SpellBook.GetSpellBookItemInfo
		and Enum
		and Enum.SpellBookSpellBank
		and Enum.SpellBookSpellBank.Pet
		and Enum.SpellBookItemType
	then
		local numPetSpells = C_SpellBook.HasPetSpells()
		if not issecretvalue(numPetSpells) and type(numPetSpells) == "number" then
			for slot = 1, numPetSpells do
				local itemInfo = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Pet)
				if itemInfo then
					local itemType = itemInfo.itemType
					local itemName = itemInfo.name
					if
						not issecretvalue(itemType)
						and (itemType == Enum.SpellBookItemType.Spell or itemType == Enum.SpellBookItemType.PetAction)
						and not issecretvalue(itemName)
						and type(itemName) == "string"
					then
						for _, name in ipairs(names) do
							if itemName == name then
								local petSpellID = itemInfo.spellID
								if not issecretvalue(petSpellID) and type(petSpellID) == "number" then
									AddFamilyID(family, seen, petSpellID)
								elseif ns.debugLogging then
									print("|cff00ccffTBT Debug|r: pet spellbook " .. itemName .. " has no spell ID")
								end
								break
							end
						end
					end
				end
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

-- Phase 56 WR-04: [ownerKey] = { auraID, id, id, ... } -- for a DETAILED buff tracker with "Cover
-- all ranks" and an aura ID, the typed aura ID followed by every ID in the owner's rank family.
-- On Forever a ranked buff's aura is normally a per-rank ID, so the aura ID alone would cancel a
-- down-ranked cast's timer at the first aura event; checking both keeps any rank's aura alive.
-- Built only in ns:RebuildRankIndex, so the cast path picks it with one lookup and allocates
-- nothing. Same lifetime rule as ns.rankFamilies: a live proc may hold one of these arrays as its
-- aliveBuffs, so the outer table is replaced per rebuild and an inner array is never mutated.
-- Phase 57.2 (REM-03): a "Cover all ranks" reminder with an aura ID gets the same list. Since
-- 57.2-05 a reminder is buff-like: its running timer's aliveBuffs and the reminder aura watch
-- (ns.reminderWatch) both read it.
ns.detailedRankFamilies = {}

-- RANK-01: [castSpellID] = ownerKey -- flat map from any ID in a family to the tracker
-- slot that owns it, excluding IDs that are themselves tracker slots. Rebuilt; wiped in
-- place with wipe() per the repos GC-pressure convention -- nothing holds a reference to
-- this table across a rebuild the way ns.rankFamilies is held.
ns.rankIndex = {}

-- The same map for COOLDOWN trackers. Two indexes rather than one, because a spell may now be
-- covered as a buff and as a cooldown at the same time and a single [castSpellID] = ownerKey map
-- could only answer for one of them.
ns.rankIndexCooldown = {}

-- Phase 57.2-05: the same map for REMINDER trackers. A reminder has its own cast namespace because
-- a spell may be tracked as a buff AND as a reminder (57.2 REM-02 duplicate rule), and one cast
-- must start both.
ns.rankIndexReminder = {}

-- The same map for BUILT-IN cooldown trackers (ns.KIND.META_SKILL_CD). A built-in never stops the
-- user from tracking the same spell (user decision 2026-09-29), so a userCd and a metaSkillCd for
-- one spell coexist and one cast must start both -- each needs its own namespace.
ns.rankIndexMetaCooldown = {}

-- Phase 57.4: the same map for BUILT-IN reminders (ns.KIND.META_REMINDER). A built-in never blocks
-- or shadows a user tracker for the same spell (user rule 2026-09-29), so a userReminder and a
-- metaReminder for one spell coexist and one cast starts both.
ns.rankIndexMetaReminder = {}

-- Cast index (NAME-01/NAME-02, Phase 53): [spellID] = key, one map per namespace. This is what
-- keeps the cast path a single table lookup now that no key equals a spellID -- the per-cast
-- legacy-cooldown-prefix concat that used to live in Providers.lua's OnTrigger moves here.
-- Rebuilt everywhere ns:RebuildRankIndex already runs (add/remove/migration/world entry),
-- wiped in place with wipe() per the repo's GC-pressure convention.
ns.buffKeyBySpell = {}
ns.cooldownKeyBySpell = {}
-- Phase 57.2-05: reminders get their own namespace, because a spell may be tracked as a buff AND
-- as a reminder, and a cast must resolve to both.
ns.reminderKeyBySpell = {}
-- ns.cooldownKeyBySpell indexes USER_CD only; built-in racial cooldowns (META_SKILL_CD) get their
-- own namespace, because a built-in never blocks or shadows a user tracker for the same spell
-- (user decision 2026-09-29) and a cast must resolve to both.
ns.metaCooldownKeyBySpell = {}
-- Phase 57.4: built-in reminders (META_REMINDER) get their own namespace too. A built-in never
-- blocks or shadows a user tracker for the same spell (user rule 2026-09-29), so a userReminder
-- and a metaReminder for one spell coexist and one cast starts both.
ns.metaReminderKeyBySpell = {}

-- Phase 57 DTRK-05: [triggerSpellID] = { trackerKey, ... } -- reverse index for cross-spell
-- rules (a tracker's saved entry.endOnCast). The OUTER table and every inner array are
-- allocated fresh per rebuild in ns:RebuildDetailedRuleIndex (rebuild-time allocation is
-- allowed, the cast path allocates nothing); never mutated after the rebuild that built it;
-- only entries with a saved rule are indexed. RALT-01 (Phase 57.5): never a reminder key -- a
-- reminder's list is its alternatives (ns.alternativeKeysBySpell, below).
ns.endKeysBySpell = {}

-- RALT-01 (Phase 57.5): [spellID] = { reminderKey, ... }, every loaded reminder that lists spellID
-- (or a rank or override of it) as an alternative ("Also satisfied by"). One-to-many, because the
-- five paladin blessings each list the other four. The outer table and inner arrays are fresh per
-- rebuild in ns:RebuildDetailedRuleIndex and never mutated afterwards. The cast path reads it with
-- one lookup.
ns.alternativeKeysBySpell = {}

-- Phase 57 DTRK-05: [triggerSpellID] = rank family array or false. Filled through
-- ns:CastRuleFamily, for cast-rule triggers and (RALT-01, Phase 57.5) for reminder
-- alternatives alike, so the spellbook scan in ns:ResolveRankFamily runs once per
-- trigger per spellbook change. Wiped in place (never replaced) by the SPELLS_CHANGED branch
-- out of combat and by PLAYER_ENTERING_WORLD. On retail (57.5 review WR-04) it holds the
-- base/override families instead, so an in-combat override answer never enters one. On Forever
-- the load rule's known check (ns:SpellKnownState) shares this cache through ns:CastRuleFamily
-- (Phase 58; formerly its own ns.loadRankFamilies, same values and wipe moments). On retail the
-- load rule never reads it.
ns.endRuleFamilies = {}

-- Phase 57.2 (REM-03), revised by 57.2-05: [key] = true|false, nil = unknown, for every
-- reminder entry. RUNTIME cache of the reminder's aura state (true = present, false = absent).
-- Writers: ns:RefreshAuraStates (readable reads), the cast side (Providers.lua OnTrigger, true),
-- a reminder timer's lazy expiry in ns:GetActiveTimers and a cancellation in
-- ns:ScanActiveTimersForCancellation (false), and the rebuild
-- invalidation (nil). Read per frame only through ns:ReminderGate. nil (never read, or
-- invalidated) hides a reminder. The state HOLDS while the aura cannot be read (combat,
-- restricted, secret): an unreadable read never writes it (DTRK-06). A rebuild only clears a key
-- whose watched ID changed or which left the watched set. Cleared per key by
-- ns:ClearTrackerRuntimeState. Never persisted.
ns.auraState = {}

-- Phase 58 rename, formerly ns.visibilityKeys, ns.visibilityAuraID and ns.visibilityWatch.
-- formerly also ns:RebuildVisibilityWatch, ns:VisibilityGate and ns:VisibilityShowsIn.
-- formerly "visibility"; that word now names only the container setting (cs.visibility).
-- Phase 57.2 (REM-03): array of the reminder keys (ns:IsReminderEntry, so a metaReminder joins
-- through ns.REMINDER_KINDS) -- the watch list ns:RefreshAuraStates and
-- ns:ReminderShowsIn walk. Replaced wholesale per rebuild in ns:RebuildDetailedRuleIndex.
ns.reminderKeys = {}

-- Phase 57.2 (REM-03): [key] = watched aura ID (ns:DetailedAuraID(entry) or entry.spellID) for
-- every reminder key in ns.reminderKeys. Replaced wholesale per rebuild alongside it.
ns.reminderAuraID = {}

-- Phase 57 review WR-02: [key] = the ID list ns:RefreshAuraStates reads for a reminder
-- whose watched set is more than its single aura ID, following the 56 WR-04 decision:
-- with an aura ID, ns.detailedRankFamilies[key] (aura ID plus the rank family); without one,
-- a "Cover all ranks" tracker's ns.rankFamilies[key] (on Forever each rank's aura is its own
-- ID). A key with no entry here watches ns.reminderAuraID[key] alone. Every list is a shared
-- read-only reference to an array ns:RebuildRankIndex built; the map itself is replaced
-- wholesale by ns:RebuildReminderWatch at the end of every ns:RebuildRankIndex, never per
-- event. RALT-01 (Phase 57.5): a reminder with alternatives watches the combined list -- its own
-- list (or its single aura ID) followed by each alternative's family -- built fresh there.
ns.reminderWatch = {}

-- RALT-01 (Phase 57.5): [key] = the combined watch list of a reminder with alternatives (its own
-- list followed by each alternative's family), the same array ns.reminderWatch[key] holds.
-- ns:FillUserBuffProc uses it as the timer's aliveBuffs, so "End when the aura is lost" applies
-- to the whole set. Replaced wholesale by ns:RebuildReminderWatch; shared read-only, like
-- ns.rankFamilies. That rebuild also repoints a running reminder timer at its new list (57.5
-- review WR-02).
ns.satisfiedByWatch = {}

-- Phase 57.3 (LOAD-04): spellID -> the last readable "is it known" answer. An unreadable read
-- (secret, missing API, error) holds this rather than flipping a tracker. Never wiped; bounded by
-- the tracked spell IDs and the racial list.
ns.spellKnownHeld = {}
-- Review IN-02: the same, for answers computed with noRanks (the racials), so an unreadable read
-- never falls back to an answer the other path computed with a different candidate set.
ns.spellKnownHeldNoRanks = {}

-- One guarded known-spell question: the caller passes the function, so no API is named here.
-- true / false for a readable boolean; nil for a missing function, an error, a secret or any
-- other answer.
local function AskKnown(fn, id)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, id)
	if not ok or issecretvalue(result) then
		return nil
	end
	if result == true or result == false then
		return result
	end
	return nil
end

-- Does this character know spellID? true, false, or nil (unreadable). Counts the spell, its base
-- spell and its override spell (a known retail talent override counts), and on Forever any rank of
-- its family unless noRanks. Any readable true is known; a readable false is remembered; nothing
-- readable is nil. Rebuild-time only -- never per frame or per cast. The four known-spell
-- functions are resolved here and named nowhere else in the addon. Walks the candidate IDs in one
-- loop (1 = the spell, 2 = base, 3 = override, then the cached rank family) with no table built.
--
-- Review CR-01: the STRICT functions decide. C_SpellBook.IsSpellKnown and IsPlayerSpell (a shim
-- for it on both clients) answer "does this character know it"; the spellbook-presence functions
-- (IsSpellKnownOrInSpellBook, and _G.IsSpellKnown, a shim for IsSpellInSpellBook) also answer true
-- for off-spec and not-yet-learned spells on retail, so a spec swap would never unload anything.
-- Both strict functions exist on retail and on the Forever beta (BigWigsMods/WoWUI forever-beta:
-- SpellBookDocumentation.lua, Deprecated_SpellBook.lua); the presence functions are asked only on a
-- client that has neither strict one. Forever's rank family is still walked with the strict pair.
function ns:SpellKnownState(spellID, noRanks)
	if issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end
	local a = C_SpellBook and C_SpellBook.IsSpellKnown
	local b = IsPlayerSpell
	local c, d
	if type(a) ~= "function" and type(b) ~= "function" then
		c = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
		d = _G.IsSpellKnown
	end

	local base, override = BaseAndOverride(spellID)
	local family
	local readable = false
	local i = 0
	while true do
		i = i + 1
		local id
		if i == 1 then
			id = spellID
		elseif i == 2 then
			id = base
		elseif i == 3 then
			id = override
		else
			if family == nil then
				family = false
				if ns.CLIENT_HAS_SPELL_RANKS and not noRanks then
					family = ns:CastRuleFamily(spellID) or false
				end
			end
			if not family then
				break
			end
			id = family[i - 3]
			if id == nil then
				break
			end
		end
		if id and (i == 1 or id ~= spellID) then
			local r1 = AskKnown(a, id)
			local r2 = r1 ~= true and AskKnown(b, id)
			local r3 = r1 ~= true and r2 ~= true and AskKnown(c, id)
			local r4 = r1 ~= true and r2 ~= true and r3 ~= true and AskKnown(d, id)
			if r1 == true or r2 == true or r3 == true or r4 == true then
				return true
			end
			if r1 == false or r2 == false or r3 == false or r4 == false then
				readable = true
			end
		end
	end

	if readable then
		return false
	end
	return nil
end

-- The known answer a rebuild uses: fallback before the first world entry (the spellbook is not
-- ready, and nothing runs before it anyway), otherwise the fresh readable answer (remembered), else
-- the held one, else fallback. Trackers pass true (fail open: never silently hide); the Suggested
-- racial list passes false (never offer a spell nobody could read).
function ns:ResolveSpellKnown(spellID, fallback, noRanks)
	if not ns.knownReady then
		return fallback
	end
	local heldTable = noRanks and ns.spellKnownHeldNoRanks or ns.spellKnownHeld
	local state = ns:SpellKnownState(spellID, noRanks)
	if state ~= nil then
		heldTable[spellID] = state
		return state
	end
	local held = heldTable[spellID]
	if held ~= nil then
		return held
	end
	return fallback
end

-- Swapped with ns.trackerLoaded on every rebuild, so the rebuild allocates nothing and a removed
-- key simply vanishes.
local loadScratch = {}

-- Review IN-03: the built-in racial kinds. A racial has one rank, so its known check skips the
-- Forever rank-family scan (the spellbook walk), exactly as the Suggested racial list does.
local SINGLE_RANK_KINDS = {
	[ns.KIND.META_SKILL] = true,
	[ns.KIND.META_SKILL_CD] = true,
}

-- Phase 57.3 (LOAD-03/LOAD-04): rebuilds ns.trackerLoaded from ns.db.trackedBuffs. Called first
-- thing in ns:RebuildCastIndex, so every existing rebuild site (add, edit, remove, migrations,
-- world entry, SPELLS_CHANGED, CDM drop, the coalesced talent/spec refresh) keeps it current.
--
-- A tracker that is not loaded is not processed -- no cast, rank, end-rule or reminder index, no
-- aura watch, no provider path, no preview -- and never drawn, but the TBT tab still lists it,
-- greyed. Loaded trackers behave exactly as before. Always is loaded, Never is not, When known asks
-- ns:ResolveSpellKnown; a tracker with no numeric spell ID and an unreadable answer are loaded (fail
-- open). A tracker that stops being loaded loses its running state at once -- except a When known
-- unload in combat, which waits for combat to end (review WR-01).
function ns:RebuildTrackerLoad()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	local prev = ns.trackerLoaded
	ns.trackerLoaded = loadScratch
	wipe(ns.trackerLoaded)
	local changed = false
	for key, entry in pairs(ns.db.trackedBuffs) do
		local rule = ns:TrackerLoad(key, entry)
		local loaded
		-- Review WR-02: an orphaned metaReminder (no table row) is never loaded. Its state cannot
		-- change within a session (the table is fixed at load), so no combat hold applies.
		if ns:IsOrphanMetaReminder(entry) then
			loaded = false
		elseif rule == ns.LOAD.ALWAYS then
			loaded = true
		elseif rule == ns.LOAD.NEVER then
			loaded = false
		elseif type(entry.spellID) ~= "number" then
			loaded = true
		else
			local noRanks = SINGLE_RANK_KINDS[entry.trackerType] == true
			-- Phase 57.4: a metaReminder asks its table row's known spell, which is the buff itself
			-- except for Blood Pact, whose row names Summon Imp (the imp's spell is not in the
			-- player spellbook, and the pet book is empty exactly while the reminder must show).
			local knownID = entry.spellID
			if entry.trackerType == ns.KIND.META_REMINDER and ns.MetaReminderKnownID then
				knownID = ns:MetaReminderKnownID(entry.spellID)
			end
			loaded = ns:ResolveSpellKnown(knownID, true, noRanks) == true
			-- Review WR-01: a When known tracker that was loaded stays loaded until combat ends. A
			-- temporary grant ending (or a transient false read) mid-fight must not wipe a timer or
			-- cooldown that is still running; PLAYER_REGEN_ENABLED re-runs the refresh. Loading is
			-- never deferred, and an explicit Never still applies at once.
			if not loaded and prev[key] == true and InCombatLockdown() then
				loaded = true
				ns.loadRecheckAfterCombat = true
			end
		end
		ns.trackerLoaded[key] = loaded
		local wasLoaded = prev[key] ~= false
		if wasLoaded ~= loaded then
			changed = true
		end
		if not loaded and wasLoaded and ns.EndTrackerRuntime then
			ns:EndTrackerRuntime(key)
		end
	end
	loadScratch = prev

	-- Providers.lua: the known and the tracked-and-loaded racial lists follow the final state.
	if ns.RebuildRacialLoadLists then
		ns:RebuildRacialLoadLists()
	end

	-- Review IN-01: the rank indexes and the aura watch follow the load state too, and only
	-- ns:RebuildRankIndex rebuilds them. A flip reached from a RebuildCastIndex-only caller (a CDM
	-- drop, an add, a migration) requests the coalesced full refresh, so an unloaded "Cover all
	-- ranks" owner never lingers in the rank index. Inside ns:RebuildRankIndex nothing is requested:
	-- that rebuild is already running.
	if changed and not ns.rankRebuildRunning then
		ns:RequestLoadRefresh()
	end

	if changed then
		ns:MarkTrackersDirty()
		if ns.displayInitialized then
			if ns.configOpen then
				ns:StartAllPreviewTimers()
			end
			if ns.tbtSections then
				ns:RefreshTBTSections()
			end
			if ns.UpdateDisplay then
				ns:UpdateDisplay()
			end
		end
	end
end

-- The same work as SPELLS_CHANGED, for the talent/spec/learn events. Declared once at file scope,
-- so a burst of TRAIT_CONFIG_UPDATED costs one C_Timer callback and one rebuild, never a closure.
local function RunLoadRefresh()
	ns.loadRefreshPending = nil
	if not InCombatLockdown() then
		wipe(ns.endRuleFamilies)
	end
	ns:RebuildRankIndex()
	ns:MarkCooldownsDirty()
end

function ns:RequestLoadRefresh()
	if ns.loadRefreshPending then
		return
	end
	ns.loadRefreshPending = true
	C_Timer.After(0, RunLoadRefresh)
end

-- Rebuilds the five cast-index maps above from ns.db.trackedBuffs. A spellID claimed by two
-- entries in the same namespace is corrupt data, not a normal state -- the lower tostring(key)
-- tie-break only exists to make that case deterministic rather than a coin flip. A userCd and a
-- metaSkillCd for the same spell are NOT a collision: they live in separate namespaces, and so do
-- a userReminder and a metaReminder (Phase 57.4).
-- Phase 57.3 (LOAD-03): the load state is rebuilt first, and a tracker that is not loaded is
-- left out of every cast index.
function ns:RebuildCastIndex()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	ns:RebuildTrackerLoad()
	wipe(ns.buffKeyBySpell)
	wipe(ns.cooldownKeyBySpell)
	wipe(ns.metaCooldownKeyBySpell)
	wipe(ns.reminderKeyBySpell)
	wipe(ns.metaReminderKeyBySpell)
	for key, entry in pairs(ns.db.trackedBuffs) do
		-- Phase 57.4: the Providers.lua class-buff table is a metaReminder's one source of truth,
		-- re-applied every rebuild before any index reads the entry. Nil-guarded: Providers.lua
		-- defines it, and loads after this file.
		if entry.trackerType == ns.KIND.META_REMINDER and ns.ApplyMetaReminderDef then
			ns:ApplyMetaReminderDef(entry)
		end
		local spellID = entry.spellID
		if type(spellID) == "number" and ns:IsTrackerLoaded(key) then
			local index
			if entry.trackerType == ns.KIND.USER_BUFF then
				index = ns.buffKeyBySpell
			elseif entry.trackerType == ns.KIND.META_REMINDER then
				index = ns.metaReminderKeyBySpell
			elseif ns:IsReminderEntry(entry) then
				index = ns.reminderKeyBySpell
			elseif entry.trackerType == ns.KIND.USER_CD then
				index = ns.cooldownKeyBySpell
			elseif entry.trackerType == ns.KIND.META_SKILL_CD then
				index = ns.metaCooldownKeyBySpell
			end
			if index then
				local existing = index[spellID]
				if existing == nil or tostring(key) < tostring(existing) then
					index[spellID] = key
				end
			end
		end
	end
	-- Phase 57 DTRK-05: every rebuild site above (add, update, remove, migration, world entry,
	-- SPELLS_CHANGED, CDM drop) also keeps the cross-spell reverse index current, with no new
	-- call site anywhere else.
	ns:RebuildDetailedRuleIndex()
end

-- RALT-01 (Phase 57.5): one family expansion for a cast-rule trigger and for a reminder
-- alternative (CONTEXT: "each alternative covers its rank family (Forever) and its base/override
-- (retail), as the aura ID and rank families do today"). Returns the family array, or nil for a
-- non-number, a value <= 0, or a Forever ID with no family. Forever: ns:ResolveRankFamily, cached
-- per ID in ns.endRuleFamilies so the spellbook scan runs once per ID per spellbook change (the
-- cached array is shared; callers never mutate it). Retail: no ranks exist, so only the two
-- guarded base/override lookups run. Rebuild-time only, never from the cast, aura or render path.
-- 57.5 review WR-04: the retail family is cached in ns.endRuleFamilies too, exactly like Forever's,
-- so it is refreshed only where that cache is wiped (out of combat): an in-combat SPELLS_CHANGED
-- with a different (or secret) override answer can no longer change a reminder's combined watch
-- list and invalidate its state mid-fight. A retail cast rule shares the cache, so it too keeps
-- its out-of-combat override until combat ends. Phase 58: on Forever the load rule's known check
-- (ns:SpellKnownState) reads its rank family through here too, so one cache serves both.
function ns:CastRuleFamily(triggerID)
	if type(triggerID) ~= "number" or triggerID <= 0 then
		return nil
	end
	local family = ns.endRuleFamilies[triggerID]
	if family ~= nil then
		return family or nil
	end
	if ns.CLIENT_HAS_SPELL_RANKS then
		family = ns:ResolveRankFamily(triggerID) or false
	else
		family = { triggerID }
		local base, override = BaseAndOverride(triggerID)
		if base then
			family[#family + 1] = base
		end
		if override then
			family[#family + 1] = override
		end
	end
	ns.endRuleFamilies[triggerID] = family
	return family or nil
end

-- Appends key to byID[id] for every id in family, once each. Rebuild-time only; its only reader
-- is ns:RebuildDetailedRuleIndex, below.
local function IndexFamily(byID, family, key)
	for _, id in ipairs(family) do
		local list = byID[id]
		if not list then
			list = {}
			byID[id] = list
		end
		local already = false
		for _, existingKey in ipairs(list) do
			if existingKey == key then
				already = true
				break
			end
		end
		if not already then
			list[#list + 1] = key
		end
	end
end

-- Phase 57 DTRK-05: rebuilds ns.endKeysBySpell from ns.db.trackedBuffs. For every non-reminder
-- buff-like (ns:IsBuffLikeEntry) or USER_CD entry with a numeric entry.endOnCast array, each
-- listed trigger ID is expanded to its rank/override family through ns:CastRuleFamily (retail:
-- two guarded base/override lookups, no spellbook scan; Forever: ns:ResolveRankFamily; both
-- cached per trigger ID in ns.endRuleFamilies, never per cast), and every ID in that family is mapped
-- back to the tracker's own key. RALT-01 (Phase 57.5): a reminder's entry.alternatives are
-- expanded the same way into ns.alternativeKeysBySpell instead; no reminder is ever in
-- ns.endKeysBySpell. Every buff-like
-- or USER_CD entry with a rule or a mode is indexed (Phase 57.1, ADD-07: no `detailed` mode flag
-- anywhere -- a default is stored as nil, so there is no stale value to guard against), so a
-- tracker with no saved rule or mode is simply never picked up.
function ns:RebuildDetailedRuleIndex()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end

	local byTrigger = {}
	local byAlternative = {}
	-- Phase 57.2 (REM-03): the same walk also rebuilds the reminder watch list, so a rebuild
	-- triggered anywhere (add, update, remove, migration, world entry, SPELLS_CHANGED, CDM drop)
	-- keeps cross-spell rules, reminders and their alternatives (RALT-01) current with one pass.
	-- Selected through ns:IsReminderEntry, so a metaReminder joins through ns.REMINDER_KINDS.
	local keys = {}
	local auraIDs = {}
	for key, entry in pairs(ns.db.trackedBuffs) do
		-- Phase 57.3 (LOAD-03): a tracker that is not loaded is neither a reminder watch key nor a
		-- cross-spell rule owner. A reminder leaving the watch list loses its aura state through
		-- the invalidation loop below.
		if ns:IsTrackerLoaded(key) then
			if ns:IsReminderEntry(entry) and type(entry.spellID) == "number" then
				keys[#keys + 1] = key
				auraIDs[key] = ns:DetailedAuraID(entry) or entry.spellID
				-- RALT-01 (Phase 57.5): casting a listed alternative starts this reminder too.
				if type(entry.alternatives) == "table" then
					for _, altID in ipairs(entry.alternatives) do
						local family = ns:CastRuleFamily(altID)
						if family then
							IndexFamily(byAlternative, family, key)
						end
					end
				end
			end
			-- RALT-01 (Phase 57.5): reminders use alternatives ("Also satisfied by") instead of the
			-- cast rule -- the one deliberate divergence from "reminders are buffs" (user decision
			-- 2026-09-29) -- so ns.endKeysBySpell never holds a reminder key.
			if
				((ns:IsBuffLikeEntry(entry) and not ns:IsReminderEntry(entry)) or entry.trackerType == ns.KIND.USER_CD)
				and type(entry.endOnCast) == "table"
			then
				for _, triggerID in ipairs(entry.endOnCast) do
					local family = ns:CastRuleFamily(triggerID)
					if family then
						IndexFamily(byTrigger, family, key)
					end
				end
			end
		end
	end
	-- Whole-table replace, so the cast path never sees a half-built map.
	ns.endKeysBySpell = byTrigger
	ns.alternativeKeysBySpell = byAlternative

	-- Phase 57 DTRK-03: an edited aura ID must not keep the old aura's cached state -- the
	-- refresh after this rebuild (RefreshAuraStates, called from RebuildRankIndex's two exits)
	-- re-reads it out of combat. Invalidate before publishing the new watch tables, in both
	-- directions (an old key whose ID changed, and a key newly watching a different ID).
	for key, oldID in pairs(ns.reminderAuraID) do
		if auraIDs[key] ~= oldID then
			ns.auraState[key] = nil
		end
	end
	for key, newID in pairs(auraIDs) do
		if ns.reminderAuraID[key] ~= newID then
			ns.auraState[key] = nil
		end
	end
	ns.reminderKeys = keys
	ns.reminderAuraID = auraIDs
end

-- 57.5 review IN-03 (on ns since Phase 58, shared by ns:RebuildReminderWatch below and
-- Providers.lua's ns:ApplyMetaReminderDef). Rebuild-time only. True when a and b are both tables
-- holding the same IDs in the same order (ipairs), or two equal non-tables such as nil and nil.
function ns:SameIDList(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	local i = 1
	while a[i] ~= nil or b[i] ~= nil do
		if a[i] ~= b[i] then
			return false
		end
		i = i + 1
	end
	return true
end

-- A fresh copy of an ID array (always a proper sequence). Rebuild-time only.
function ns:CopyIDList(list)
	local copy = {}
	for i = 1, #list do
		copy[i] = list[i]
	end
	return copy
end

-- A numeric membership test for the combined watch list below (no tContains). Rebuild-time only.
local function ListContains(list, id)
	for i = 1, #list do
		if list[i] == id then
			return true
		end
	end
	return false
end

-- Phase 57 review WR-02: rebuilds ns.reminderWatch from ns.reminderKeys and the rank family
-- tables. Called at both exits of ns:RebuildRankIndex, after ns.rankFamilies and
-- ns.detailedRankFamilies are final. Rebuild-time only; allocates two outer tables, plus one
-- combined list per reminder with alternatives. RALT-01 (Phase 57.5): such a reminder watches its
-- own list (or its single aura ID) followed by each alternative's ns:CastRuleFamily, deduplicated,
-- published as ns.reminderWatch[key] and ns.satisfiedByWatch[key] alike. A reminder with no
-- alternatives keeps exactly its old list.
function ns:RebuildReminderWatch()
	local tracked = ns.db and ns.db.trackedBuffs
	if not tracked then
		return
	end
	local watch = {}
	local satisfied = {}
	local oldWatch = ns.reminderWatch
	local keys = ns.reminderKeys
	for i = 1, #keys do
		local key = keys[i]
		local entry = tracked[key]
		if entry then
			local list = ns.detailedRankFamilies[key]
			if list == nil and entry.coverAllRanks and ns:DetailedAuraID(entry) == nil then
				list = ns.rankFamilies[key]
			end
			if type(entry.alternatives) == "table" and #entry.alternatives > 0 then
				local combined
				if list ~= nil then
					combined = ns:CopyIDList(list)
				else
					combined = { ns.reminderAuraID[key] }
				end
				for _, altID in ipairs(entry.alternatives) do
					local family = ns:CastRuleFamily(altID)
					if family then
						for j = 1, #family do
							if not ListContains(combined, family[j]) then
								combined[#combined + 1] = family[j]
							end
						end
					end
				end
				list = combined
				satisfied[key] = combined
			end
			watch[key] = list

			-- Phase 57 review IN-03: a state read against a different ID list is stale. Compared by
			-- content, because every rebuild allocates fresh arrays.
			local old = oldWatch[key]
			local same = ns:SameIDList(old, list)
			if not same then
				ns.auraState[key] = nil
			end
		end
	end
	ns.reminderWatch = watch
	ns.satisfiedByWatch = satisfied

	-- 57.5 review WR-02: a running reminder timer follows the list just built, so the cancellation
	-- scan and ns:RefreshAuraStates never disagree about the set after an edit (alternatives added
	-- or removed, a rank learned). The same choice ns:FillUserBuffProc makes, in its order. Only a
	-- proc that carries a list is repointed (an opted-out tracker's carries none). Rebuild-time
	-- only; the pooled one-element list is reused, never allocated here.
	for i = 1, #keys do
		local key = keys[i]
		local proc = ns.activeTimers[key]
		if proc ~= nil and proc.aliveBuffs ~= nil then
			proc.aliveBuffs = satisfied[key] or watch[key] or ns:AcquireAliveBuffs(key, ns.reminderAuraID[key])
		end
	end
end

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

	-- The cast index is refreshed at the same moments as the rank index -- every call site below
	-- (add, remove, migration, world entry, SPELLS_CHANGED) keeps both current with one call. The
	-- flag tells ns:RebuildTrackerLoad that the rank indexes are rebuilt right after (review IN-01).
	ns.rankRebuildRunning = true
	ns:RebuildCastIndex()
	ns.rankRebuildRunning = nil

	wipe(rebuildOwners)
	for k, entry in pairs(ns.db.trackedBuffs) do
		-- No key equals a spellID anymore, so ownership is read off entry.trackerType/spellID
		-- instead of the key shape the old (type(k) == "number" or ns:CooldownKeySpellID(k))
		-- test relied on. Phase 57.2-05: a reminder is buff-like, so a Forever "Cover all ranks"
		-- reminder gets its family for both its aura watch and its own cast namespace
		-- (ns.rankIndexReminder): a rank cast starts the reminder's timer like a buff's.
		-- Phase 57.3 (LOAD-03): an unloaded tracker owns no rank family (the load state is
		-- current: ns:RebuildCastIndex above rebuilt it).
		if
			entry.coverAllRanks
			and type(entry.spellID) == "number"
			and ns:IsTrackerLoaded(k)
			and (
				ns:IsBuffLikeEntry(entry)
				or entry.trackerType == ns.KIND.USER_CD
				or entry.trackerType == ns.KIND.META_SKILL_CD
			)
		then
			table.insert(rebuildOwners, k)
		end
	end

	-- Early-out before touching C_SpellBook at all when nothing is covered -- this is what
	-- costs a retail client nothing: the checkbox that sets coverAllRanks does not exist
	-- there, so this list is always empty on retail (a metaReminder, always rank-covering, is only
	-- ever offered on Forever -- Phase 57.4).
	if #rebuildOwners == 0 then
		wipe(ns.rankIndex)
		wipe(ns.rankIndexCooldown)
		wipe(ns.rankIndexMetaCooldown)
		wipe(ns.rankIndexReminder)
		wipe(ns.rankIndexMetaReminder)
		wipe(ns.rankFamilies)
		wipe(ns.detailedRankFamilies)
		-- Phase 57 review WR-02: the families are final (empty) here, so the watch lists are too.
		ns:RebuildReminderWatch()
		-- Phase 57 DTRK-03: ns.detailedRankFamilies is final on this exit too (empty here), the
		-- watched list for a cover-all-ranks aura ID tracker; wait for the display, whose
		-- per-container tables do not exist before the first InitDisplay.
		if ns.displayInitialized then
			ns:RefreshAuraStates()
		end
		return
	end

	-- pairs() order is not deterministic, and two families can legitimately claim the same
	-- ID -- sorting means the same client produces the same index every time, rather than a coin
	-- flip on which owner wins a contested ID. Sorted by the owner's spellID first (this
	-- reproduces the old key-string order exactly -- v0.4.1 keys were "N" and "cd:N", whose
	-- string order within a namespace was the spellID's string order), tied by key.
	table.sort(rebuildOwners, function(a, b)
		local entryA, entryB = ns.db.trackedBuffs[a], ns.db.trackedBuffs[b]
		local spellA, spellB = tostring(entryA.spellID), tostring(entryB.spellID)
		if spellA ~= spellB then
			return spellA < spellB
		end
		return tostring(a) < tostring(b)
	end)

	wipe(ns.rankIndex)
	-- Do NOT wipe the tables inside ns.rankFamilies -- a live proc may hold a reference to
	-- one of those arrays as its aliveBuffs (see the ns.rankFamilies comment above).
	-- Rebuild the outer table fresh instead, so a removed owners old array is simply
	-- dropped from the map, not mutated out from under a holder.
	ns.rankFamilies = {}
	ns.detailedRankFamilies = {}

	wipe(ns.rankIndexCooldown)
	wipe(ns.rankIndexMetaCooldown)
	wipe(ns.rankIndexReminder)
	wipe(ns.rankIndexMetaReminder)

	for _, ownerKey in ipairs(rebuildOwners) do
		local ownerEntry = ns.db.trackedBuffs[ownerKey]
		local ownerSpellID = ownerEntry.spellID
		-- Phase 57.4 (MREM-03): a pet-spell metaReminder (Blood Pact) also reads the pet spellbook.
		local petBook = ownerEntry.trackerType == ns.KIND.META_REMINDER
			and ns.MetaReminderUsesPetBook ~= nil
			and ns:MetaReminderUsesPetBook(ownerSpellID)
		local family = ns:ResolveRankFamily(ownerSpellID, petBook)
		if family then
			ns.rankFamilies[ownerKey] = family
			-- WR-04: the aura ID first, then the family's IDs it does not already name. Gated
			-- through ns:DetailedAuraID, so a tracker with no saved aura ID gets no entry and
			-- keeps using the family above unchanged.
			-- Phase 57.2: any buff-like owner (a buff or a reminder). Not USER_CD: a cooldown's
			-- aura ID fed only the old visibility watch, and schema v10 drops it.
			local auraID = ns:IsBuffLikeEntry(ownerEntry) and ns:DetailedAuraID(ownerEntry)
			if auraID then
				local combined = { auraID }
				for _, id in ipairs(family) do
					if id ~= auraID then
						combined[#combined + 1] = id
					end
				end
				ns.detailedRankFamilies[ownerKey] = combined
			end
			-- One index per namespace. A single map could not answer them all, and a spell may
			-- legitimately be covered as a buff, a reminder, a user cooldown AND a built-in
			-- cooldown at once. Phase 57.2-05: a reminder writes its own pair, so a rank cast
			-- resolves to it like a buff's; a built-in cooldown likewise (2026-09-29), and a
			-- built-in reminder (Phase 57.4) picks its own pair before the user reminder one.
			local index, byKeyIndex
			if ownerEntry.trackerType == ns.KIND.META_REMINDER then
				index, byKeyIndex = ns.rankIndexMetaReminder, ns.metaReminderKeyBySpell
			elseif ns:IsReminderEntry(ownerEntry) then
				index, byKeyIndex = ns.rankIndexReminder, ns.reminderKeyBySpell
			elseif ownerEntry.trackerType == ns.KIND.USER_CD then
				index, byKeyIndex = ns.rankIndexCooldown, ns.cooldownKeyBySpell
			elseif ownerEntry.trackerType == ns.KIND.META_SKILL_CD then
				index, byKeyIndex = ns.rankIndexMetaCooldown, ns.metaCooldownKeyBySpell
			else
				index, byKeyIndex = ns.rankIndex, ns.buffKeyBySpell
			end
			for _, id in ipairs(family) do
				-- An ID that is itself a tracker slot owns itself -- the index must never
				-- shadow a direct lookup. First owner in sorted order wins a contested ID.
				-- Checked within the OWN namespace via the cast index, which already separates
				-- "does a direct buff tracker own this spellID" from the cooldown answer -- a
				-- buff tracker on rank 2 must not stop a cooldown family from claiming rank 2.
				if byKeyIndex[id] == nil and index[id] == nil then
					index[id] = ownerKey
				end
			end
		end
	end
	-- Phase 57 review WR-02: the families are final here, so the watch lists are too.
	ns:RebuildReminderWatch()
	-- Phase 57 DTRK-03: ns.detailedRankFamilies is final here, the watched list for a
	-- cover-all-ranks aura ID tracker; wait for the display, whose per-container tables do not
	-- exist before the first InitDisplay.
	if ns.displayInitialized then
		ns:RefreshAuraStates()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- 49-04/D-1/D-2: the combat-entry edge. A plain RegisterEvent, not TryRegisterEvent -- this event
-- name is long-standing on both clients (MergeMode.lua's own PLAYER_REGEN_DISABLED comment records
-- it as "certain to exist on both clients"), and the pcall wrapper below is reserved for names
-- that might not be.
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
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

-- Phase 46 (ITEM-01): the item catalogue's rescan trigger while the CDM is open. BAG_UPDATE is
-- in practice universal on both flavours, but every other bag-family event in this file goes
-- through the pcall-wrapped capability helper rather than a bare RegisterEvent -- a capability
-- check on the event, never a client-identity check (D-03) -- so this one matches rather than
-- being the one exception.
TryRegisterEvent(eventFrame, "BAG_UPDATE")

-- Phase 43.1: what the trinket and pot meta-trackers resolve from. Their at-rest scan used to
-- run from exactly one place -- the CDM tab being built -- so opening the Cooldown Manager in
-- combat found the scan combat-gated and the tile drew a question mark, while opening it out of
-- combat did not. That is the "sometimes" in the report. These are the three moments the answer
-- can actually change, plus combat ending, which is the first moment the gated scan can run.
TryRegisterEvent(eventFrame, "PLAYER_EQUIPMENT_CHANGED")
TryRegisterEvent(eventFrame, "BAG_UPDATE_DELAYED")

-- Phase 57.2 review WR-01: the reminder states' missing edge. C_Secrets.ShouldAurasBeSecret() can
-- flip with no combat edge and no UNIT_AURA (a keystone starting before the pull, ending out of
-- combat). Blizzard documents this event as fired before a restriction activates and after one
-- deactivates (RestrictedActionsDocumentation.lua, 12.1 live). The forever-beta documentation dump
-- lists it too, but a dump cannot prove the event fires there, so it goes through the pcall
-- path: a client without it keeps the pre-WR-01 behaviour and never a load error.
TryRegisterEvent(eventFrame, "ADDON_RESTRICTION_STATE_CHANGED")

-- Phase 57.3 (LOAD-04): the moments a "When known" tracker can change state besides SPELLS_CHANGED
-- and world entry -- learning a spell, a spec swap, a talent change. Through the pcall path,
-- because a documentation dump cannot prove an event fires on a given client. All five coalesce
-- into one ns:RequestLoadRefresh per frame.
TryRegisterEvent(eventFrame, "LEARNED_SPELL_IN_SKILL_LINE")
TryRegisterEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED")
TryRegisterEvent(eventFrame, "ACTIVE_TALENT_GROUP_CHANGED")
TryRegisterEvent(eventFrame, "TRAIT_CONFIG_UPDATED")
TryRegisterEvent(eventFrame, "PLAYER_TALENT_UPDATE")
-- Phase 57.4 review WR-01: the player's pet changing (the imp summoned, dismissed or replaced)
-- changes the pet spellbook Blood Pact's rank family reads (ns:ResolveRankFamily step 5). Nothing
-- proves SPELLS_CHANGED fires for that on Forever, so the pet change joins the same coalesced
-- rebuild. Fires for every unit; the handler keeps only the player's.
TryRegisterEvent(eventFrame, "UNIT_PET")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= addonName then
			return
		end

		local freshDB = false
		if not TerribleBuffTrackerDB then
			freshDB = true
			TerribleBuffTrackerDB = {
				trackedBuffs = {},
			}
		end
		ns.db = TerribleBuffTrackerDB
		-- Dev-only key from the 57.3 dialog-style comparison; the dialogs now have one look.
		ns.db.dialogStyle = nil

		if not ns.db.trackedBuffs then
			ns.db.trackedBuffs = {}
		end

		if ns.db.tbtVisible == nil then
			ns.db.tbtVisible = true
		end

		-- Phase 35.1 (CFG-03): ns.db.mergeMode is an addon-wide flag, a sibling of tbtVisible
		-- rather than a containerSettings field -- it is one switch across all four categories,
		-- not a per-container setting. Written by ns:SetMergeMode (MergeMode.lua), reached from
		-- the Merge switch in Config.lua, and by this seed. An existing database keeps its saved
		-- value, and one that predates the key is seeded off, as before.
		-- A fresh database (created above on this load) starts merged: user decision 2026-09-29.
		if ns.db.mergeMode == nil then
			ns.db.mergeMode = freshDB
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
		-- 49-03: second, guaranteed-readable attempt at schema v7's racial re-key.
		-- ADDON_LOADED (where ns:InitBuffEngine already called this once) is not a
		-- guaranteed-readable moment for UnitRace("player"), and the cost of the extra call is
		-- one comparison once the version has been bumped. Without this, a character whose race
		-- was unreadable at load would defer forever -- the only other entry point is the next
		-- ADDON_LOADED -- and losing a placement is exactly what D-4's "Migration is required"
		-- clause exists to prevent.
		ns:MigrateRacialKeys()
		-- Schema v8 (NAME-01/NAME-02, Phase 53): must follow a completed v7 on the same trigger --
		-- it re-keys onto ns.KIND and cannot classify a stray "racial"/"racial2" slot v7 has not
		-- yet resolved. A one-comparison no-op once ns.db.schemaVersion is already 8.
		ns:MigrateKindKeys()
		-- Schema v9 (Phase 57.1): must follow a completed v8 on the same trigger.
		ns:MigrateDropDetailedFlag()
		-- Schema v10 (Phase 57.2): must follow a completed v9 on the same trigger.
		ns:MigrateBuffReminders()
		-- Schema v11 (Phase 57.5): must follow a completed v10 on the same trigger.
		ns:MigrateReminderAlternatives()
		-- Phase 57 DTRK-05: the spellbook is populated here for the first time, so any Forever
		-- rank family cached from ADDON_LOADED (seed/base/override IDs only) is stale. Wipe
		-- before the rebuild below so it recomputes from the real spellbook.
		wipe(ns.endRuleFamilies)
		-- Phase 57.3 (LOAD-04): the first moment the spellbook is populated. Before it every When
		-- known tracker counts as loaded; from here the rebuild below asks the spellbook.
		ns.knownReady = true
		-- RANK-01: called unconditionally, outside the ns.displayInitialized one-shot guard
		-- below, so a rebuild runs on every world entry (reload, zoning into an instance,
		-- etc.), not just the first. Deliberately NOT called from ADDON_LOADED above -- the
		-- spellbook is not populated that early, and the scan would return the seed only.
		ns:RebuildRankIndex()
		-- Phase 38 (CD-04): also unconditional and outside the one-shot guard, for the same
		-- reason -- a cooldown handle can be stale after a reload or a zone-in, not just once.
		ns:MarkCooldownsDirty()
		-- Phase 47 (ITEM-06), code review BLOCKER B1: register the use-spell of every tracked
		-- item now, so a tracker restored from SavedVariables decrements from its first use even
		-- if the player never opens the Cooldown Manager this session. Unconditional and outside
		-- the one-shot guard for the same reason as the two above -- item data can be uncached on
		-- an early login and resolve later, and a zone-in is a cheap place to retry. No bag
		-- access: it reads ns.db.trackedBuffs.
		if ns.RegisterAllTrackedItemUseSpells then
			ns:RegisterAllTrackedItemUseSpells()
		end
		-- Phase 47 gap, reported 2026-09-25: a tracked item's count vanished after a /reload.
		--
		-- itemTrackedCounts is RUNTIME-ONLY -- deliberately, since a stale persisted count is
		-- worse than no count -- so it is empty on every login and reload. It was seeded only at
		-- tracker CREATION and refreshed only by BAG_UPDATE_DELAYED or leaving combat, and none of
		-- those necessarily happen after a reload. A player who reloaded while standing still, out
		-- of combat, with an already-tracked item therefore had no count until they next looted,
		-- swapped gear or fought.
		--
		-- ITEM-07's gate passed because it tested exactly the path that did work: let the count
		-- drift, leave combat, watch it correct. The empty-at-login case is a different entry
		-- point and nothing exercised it until a testing session full of reloads did.
		--
		-- Combat-gated inside the wrapper, so this is safe to call unconditionally here; a login
		-- in combat is picked up by the PLAYER_REGEN_ENABLED call.
		if ns.ReconcileTrackedItemCounts then
			ns:ReconcileTrackedItemCounts()
		end
		if not ns.displayInitialized then
			ns.displayInitialized = true
			ns:InitEditModeFrames()
			ns:InitDisplay()
		end
		-- Phase 57 DTRK-03: the initial aura-state read at login/reload, now that the display
		-- (and ns.detailedRankFamilies, rebuilt above) both exist. A buff already up at login
		-- with a readable expiry starts its reminder's timer here (57.2-05). Suppressed (57.2-05
		-- review WR-02): after a zone-in loading screen an aura can read absent for a moment, and
		-- no buff timer is cancelled here either.
		ns:RefreshAuraStates(true)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if unit == "player" then
			ns:OnSpellCastSucceeded(spellID)
			-- After the tracker, not before: the log is a diagnostic and must never be
			-- what decides whether a timer starts. Defined at the bottom of this file.
			ns:LogPlayerCast(spellID)
		end
	elseif event == "UNIT_AURA" then
		local unit, updateInfo = ...
		if unit == "player" then
			ns:OnUnitAura(updateInfo)
		end
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		-- Phase 57.2 review WR-01: while the event dispatches, an Activating restriction is not
		-- enforced yet, so a read here could still succeed and show a reminder a moment before
		-- auras go secret. Only a known Inactive state re-reads (after a deactivation; the refresh
		-- still returns early if another restriction keeps auras secret). Any other state, including
		-- a secret or unknown one, does nothing: since 57.2-05 every reminder state simply holds
		-- while auras cannot be read. Inactive is 0 in the enum on both clients' documentation, the
		-- fallback for a client without the Enum table.
		local _, state = ...
		local inactive = Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
		if not issecretvalue(state) and state == inactive then
			ns:RefreshAuraStates()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- 49-04/D-1/D-2: the combat-entry edge, and the only signal available while aura reads
		-- are secret in combat. Shadowmeld and Plainsrunning both end here rather than waiting
		-- for a cancellation scan that cannot see the drop once combat starts. Kept to this one
		-- call so the combat-entry edge stays cheap.
		ns:EndCombatClearedRacials()
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns:ClearSecretGateLog()
		-- Phase 57.3 review WR-01: a When known unload held back during combat applies now.
		if ns.loadRecheckAfterCombat then
			ns.loadRecheckAfterCombat = nil
			ns:RequestLoadRefresh()
		end
		-- Phase 57.2 (REM-03): combat end re-reads the reminder states (and syncs a running
		-- reminder timer to a readable expiry), before the cancellation scan below.
		ns:RefreshAuraStates()
		-- 49/D-1: leaving combat is the first moment an aura read can succeed again, and until
		-- now nothing re-checked here -- ns:ScanActiveTimersForCancellation ran ONLY from
		-- UNIT_AURA (BuffEngine.lua). A proc whose aura ended mid-combat therefore survived until
		-- the next unrelated aura event, and an INDEFINITE one had no expiry to fall back on, so
		-- it lingered indefinitely. Reported from the Alliance gate pass, 2026-09-25.
		--
		-- Safe to call unconditionally: the scan skips any proc without an aliveBuffs list, and
		-- never concludes "absent" from an unreadable read -- so the worst case here is that it
		-- finds nothing, and it only ever draws when it actually cancelled something.
		ns:ScanActiveTimersForCancellation()
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
		-- Phase 47 (ITEM-07, D-03): leaving combat is the moment the locally decremented tracked
		-- item count is reconciled against the bags, absorbing drift a decrement cannot see --
		-- looting more mid-fight, several items consumed at once, a stack traded away.
		ns:ReconcileTrackedItemCounts()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		ns:ClearSecretGateLog()
	elseif event == "SPELLS_CHANGED" then
		-- Phase 57 DTRK-05: the spellbook changed, so any cached Forever rank family may be
		-- stale. In combat the old families stay valid -- a Forever rank cannot be learned
		-- mid-fight -- and the next out-of-combat SPELLS_CHANGED refreshes them instead.
		if not InCombatLockdown() then
			wipe(ns.endRuleFamilies)
		end
		ns:RebuildRankIndex()
		ns:MarkCooldownsDirty()
	elseif
		event == "LEARNED_SPELL_IN_SKILL_LINE"
		or event == "PLAYER_SPECIALIZATION_CHANGED"
		or event == "ACTIVE_TALENT_GROUP_CHANGED"
		or event == "TRAIT_CONFIG_UPDATED"
		or event == "PLAYER_TALENT_UPDATE"
		or event == "UNIT_PET"
	then
		-- Phase 57.3 (LOAD-04): re-evaluate the load state, coalesced to one rebuild per frame.
		-- PLAYER_SPECIALIZATION_CHANGED also fires for party members; only the player's matters.
		-- Phase 57.4 review WR-01: UNIT_PET likewise, and its rebuild re-reads the pet spellbook.
		local unit = ...
		local unitScoped = event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UNIT_PET"
		if not unitScoped or (not issecretvalue(unit) and unit == "player") then
			ns:RequestLoadRefresh()
		end
	elseif event == "BAG_UPDATE_COOLDOWN" then
		-- Phase 47: the event Blizzard's own cooldown item listens to for item cooldowns. Covers
		-- use paths the use-spell map does not catch -- a charge consumed by something other than
		-- a player cast, or an item whose catalogue row has not been rebuilt yet.
		ns:RefreshTrackedItemCooldowns()
		ns:MarkCooldownsDirty()
	elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
		ns:MarkCooldownsDirty()
	elseif event == "BAG_UPDATE" then
		-- Phase 46: set the dirty flag only. BAG_UPDATE fires in bursts, and the locked cadence
		-- (rebuild only while the CDM is shown, coalesced to at most one rebuild per frame) lives
		-- in CDMTab.lua's coalescing consumer -- NOT here, unlike the neighbouring
		-- PLAYER_EQUIPMENT_CHANGED/BAG_UPDATE_DELAYED branch below, which calls
		-- ns:RefreshProvidersAtRest() directly. That asymmetry is deliberate, not a bug to "fix":
		-- this catalogue's rescan is strictly more expensive (a full bag walk) than that branch's
		-- handful of GetInventoryItemID/GetItemCount reads.
		ns:MarkItemCatalogueDirty()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
		-- Combat-gated inside the wrapper, so this is safe to call unconditionally; a change made
		-- in combat is picked up by the PLAYER_REGEN_ENABLED call above.
		ns:RefreshProvidersAtRest()
		-- Phase 47 (ITEM-07, D-03): BAG_UPDATE_DELAYED fires once after a burst of bag changes
		-- rather than per change, and the reconcile is combat-gated internally, so this call is a
		-- no-op in combat and costs one InCombatLockdown() check the rest of the time.
		--
		-- Scoped to BAG_UPDATE_DELAYED only, per Phase 47 code review W2: this branch is shared
		-- with PLAYER_EQUIPMENT_CHANGED, and swapping a weapon or trinket cannot change how many
		-- consumables are in the bags. Reconciling there was harmless but pointless work on an
		-- event that fires on every gear change.
		if event == "BAG_UPDATE_DELAYED" then
			ns:ReconcileTrackedItemCounts()
		end
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
		if ns.debugLogging then
			-- Both resolved through ns, NOT called as file-locals. This handler sits hundreds of
			-- lines ABOVE where they are defined, and a Lua local is an upvalue only to functions
			-- declared after it -- so a local called from here is nil at call time. See
			-- ns:LogPlayerRace for what that cost.
			ns:LogPlayerRace()
			-- Snapshot the buffs already up, so the first racial cast after this reports only
			-- itself. See ns:BaselinePlayerAuras.
			ns:BaselinePlayerAuras()
		end
	else
		-- "/tbt" now opens TBT's OWN settings panel rather than Blizzard's Cooldown Manager
		-- window. The CDM tabs are still where trackers are filed into containers; everything
		-- that is not about a specific tracker moved here (user decision, 2026-09-22).
		ns:OpenConfigPanel()
	end
end

---------------------------------------------------------------------
-- SPELL INFO HELPERS (Phase 55) -- shared by the secrecy line the
-- TOOL-01 block below adds, by ns:ShowBuffTooltip's own unresolved-ID
-- branch, by the Add/Edit dialog's live preview, secrecy badge and
-- suggested-cooldown field, and later by the detailed-mode aura ID
-- field (Phases 56-57). Every read here is issecretvalue-first,
-- pcall-guarded and capability-checked: an absent API means a helper
-- answers nil (or false), never an error. This section sits above the
-- TOOL-01 block, so nothing in it may reach for the locally scoped
-- guarded-read helpers declared further down this file -- those names
-- are not yet in scope at this point in the file, so every guard below
-- is written out inline instead of borrowed from them.
---------------------------------------------------------------------

-- Capability capture, once, at load: nil on a client with no secrecy API
-- at all, so every helper below degrades to "no answer" behind one nil
-- check instead of re-probing the API on every call.
local SpellAuraSecrecyAPI = C_Secrets and C_Secrets.GetSpellAuraSecrecy

-- Built once below, only when the enum exists: numeric secrecy level ->
-- the one prebuilt tooltip line, numeric secrecy level -> the longer badge
-- explanation (the never-secret level has none), plus one generic line and
-- explanation for a level not in the spec. SECRECY_NEVER holds the
-- never-secret member's own numeric value, used as the "does this level
-- even warrant a badge" threshold. There is deliberately no bare-label
-- getter: both the tooltip line and the badge title read the prebuilt line.
local SECRECY_NEVER = nil
local SECRECY_LINES = {}
local SECRECY_EXPLANATIONS = {}
local SECRECY_UNKNOWN_LINE = nil
local SECRECY_UNKNOWN_EXPLANATION = nil

if Enum and Enum.SecrecyLevel then
	local SECRECY_SPEC = {
		{ member = "NeverSecret", label = "Never secret", explanation = nil },
		{
			member = "AlwaysSecret",
			label = "Always secret",
			explanation = "This spell's aura is always hidden from addons. Changes to its"
				.. " duration won't be picked up; the timer runs from the cast.",
		},
		{
			member = "ContextuallySecret",
			label = "Contextual",
			explanation = "This spell's aura and cooldown can be hidden in combat. Unexpected"
				.. " duration or cooldown changes may not be picked up by the addon in these"
				.. " contexts.",
		},
	}

	-- The ONLY place the line prefix is written -- every caller gets a prebuilt
	-- string back, never a fresh concatenation.
	local linePrefix = "Aura secrecy: "
	for _, spec in ipairs(SECRECY_SPEC) do
		local value = Enum.SecrecyLevel[spec.member]
		if type(value) == "number" then
			SECRECY_LINES[value] = linePrefix .. spec.label
			if spec.explanation then
				SECRECY_EXPLANATIONS[value] = spec.explanation
			end
			if spec.member == "NeverSecret" then
				SECRECY_NEVER = value
			end
		end
	end

	-- A level this table does not know (a future Enum.SecrecyLevel member) is
	-- treated conservatively as NOT never-secret: it gets this generic line and
	-- explanation and shows the badge, rather than looking the same as "no warning".
	SECRECY_UNKNOWN_LINE = linePrefix .. "Unknown"
	SECRECY_UNKNOWN_EXPLANATION = "Unrecognised secrecy level. This spell's aura may be hidden" .. " from addons."
end

-- Guarded secrecy-level read for one spell ID: returns the numeric level
-- when the client can answer, or nil when it cannot -- no capability, a
-- secret or non-numeric or non-positive spellID, or a secret, failed or
-- non-numeric answer. Any readable numeric level is returned, including one
-- this file does not know: the helpers below map that to "Unknown" rather
-- than hiding it. No table is created and no string is built here; this
-- runs on every game tooltip, so the cost has to stay flat.
function ns:SpellAuraSecrecy(spellID)
	if not SpellAuraSecrecyAPI or SECRECY_NEVER == nil then
		return nil
	end
	if issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end
	local ok, level = pcall(SpellAuraSecrecyAPI, spellID)
	if not ok or issecretvalue(level) or type(level) ~= "number" then
		return nil
	end
	return level
end

-- Returns the one prebuilt tooltip-line string for a secrecy level, the
-- prebuilt "Unknown" line for a level this client does not recognise, or
-- nil for nil. One table read, no allocation (TOOL-01 hot path).
function ns:SecrecyLine(level)
	if level == nil then
		return nil
	end
	return SECRECY_LINES[level] or SECRECY_UNKNOWN_LINE
end

-- Returns the longer badge explanation for a secrecy level, the generic
-- explanation for an unrecognised level, or nil -- including for the
-- never-secret level, which has none.
function ns:SecrecyExplanation(level)
	if level == nil or level == SECRECY_NEVER then
		return nil
	end
	return SECRECY_EXPLANATIONS[level] or SECRECY_UNKNOWN_EXPLANATION
end

-- True for any level other than never-secret (SECR-03's "does this
-- warrant the badge" threshold), an unrecognised level included, since a
-- warning must fail towards showing; false for never-secret or nil.
function ns:SecrecyWarns(level)
	if level == nil or SECRECY_NEVER == nil then
		return false
	end
	return level ~= SECRECY_NEVER
end

-- The secrecy is looked up for the typed/hovered ID itself. A buff's aura
-- is often a different spell ID from the cast, so the dialog's preview and
-- badge tooltips say which ID the level describes. Built once at load; nil
-- on a client with no secrecy API, where no secrecy line is ever shown.
local SECRECY_SCOPE_NOTE = nil
if SpellAuraSecrecyAPI and SECRECY_NEVER ~= nil then
	SECRECY_SCOPE_NOTE = "Secrecy is for this ID's own aura; the buff's may differ."
end

-- Returns the one prebuilt scope note, or nil when secrecy is unavailable.
function ns:SecrecyScopeNote()
	return SECRECY_SCOPE_NOTE
end

-- ADD-05: a starting value for the Add/Edit dialog's duration field,
-- never a live override of what the user typed -- TBT's own cooldown
-- display still runs entirely on the typed duration (the 2026-09-22
-- decision stands). Tries the legacy base-cooldown global first, then a
-- charge spell's recharge time rounded to whole seconds, and answers nil
-- when neither gives a positive number.
function ns:SuggestedCooldown(spellID)
	if issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end

	if type(GetSpellBaseCooldown) == "function" then
		local ok, ms = pcall(GetSpellBaseCooldown, spellID)
		if ok and not issecretvalue(ms) and type(ms) == "number" and ms > 0 then
			return ms / 1000
		end
	end

	-- The charge value is the CURRENT recharge time, which haste can make fractional
	-- (17.3913...), not a whole-second base value. It is rounded to whole seconds: a
	-- starting value, not a measurement, and a raw fraction would either be too long for
	-- the duration box (and dropped) or saved as a gear-dependent oddity.
	if C_Spell and C_Spell.GetSpellCharges then
		local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
		if ok and ns:CanReadTable(info) then
			local d = info.cooldownDuration
			if not issecretvalue(d) and type(d) == "number" and d > 0 then
				d = math.floor(d + 0.5)
				if d > 0 then
					return d
				end
			end
		end
	end

	return nil
end

-- ADD-05 for buffs: the game has no static "buff duration" API, so the only
-- source is the live aura. When the buff is on the player and readable (out
-- of combat, not secret) its own duration is the suggestion, rounded to whole
-- seconds; otherwise nil and the box stays empty for manual entry. An
-- indefinite aura (duration 0) suggests nothing. Reads through the allowlisted
-- ns:ReadPlayerAura (BuffEngine.lua), resolved at call time.
function ns:SuggestedBuffDuration(spellID)
	if issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end
	local aura = ns:ReadPlayerAura(spellID)
	if not aura then
		return nil
	end
	local d = aura.duration
	if issecretvalue(d) or type(d) ~= "number" or d <= 0 then
		return nil
	end
	d = math.floor(d + 0.5)
	if d > 0 then
		return d
	end
	return nil
end

-- ADD-04: name and icon for the dialog's live preview row, or nil when
-- the client does not know the spell at all -- the dialog falls back to
-- its own "Unknown spell" text for that case, not this helper.
function ns:SpellPreview(spellID)
	if issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end
	if not (C_Spell and C_Spell.GetSpellInfo) then
		return nil
	end
	-- ns:CanReadTable is an ns method (BuffEngine.lua), resolved at call time, so its
	-- position in the load order does not matter here.
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if not ok or not ns:CanReadTable(info) then
		return nil
	end
	local name = info.name
	if issecretvalue(name) or type(name) ~= "string" or name == "" then
		name = "Spell " .. spellID
	end
	local icon = info.iconID
	if issecretvalue(icon) or type(icon) ~= "number" then
		icon = 134400
	end
	return name, icon
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

		-- The aura secrecy level sits right under the ID line above: one guarded
		-- API call and a prebuilt string, since this runs on every tooltip in the
		-- game. An absent API or enum means no line at all, never an error. Every
		-- TBT tile tooltip whose spell resolves reaches this same post-call through
		-- SetSpellByID, so ns:ShowBuffTooltip must never add this line again for a
		-- resolved spell -- only its own unresolved-ID branch does, since this
		-- post-call never runs there.
		local secrecyLine = ns:SecrecyLine(ns:SpellAuraSecrecy(id))
		if secrecyLine then
			tooltip:AddLine(secrecyLine, 0.8, 0.8, 0.8)
		end

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

---------------------------------------------------------------------
-- DEBUG CAST LOG — one chat line per spell cast or item used by the
-- player while `/tbt debug` is on.
--
-- Why this is not just a print in the UNIT_SPELLCAST_SUCCEEDED handler:
-- an item's on-use fires that event carrying the item's EFFECT SPELL,
-- and nothing in the event says an item was involved. A potion and a
-- class ability are the same shape on the wire. So the item has to be
-- caught on its way out, before the cast event lands, by hooking the
-- four functions that can start an item use.
--
-- The hooks print immediately and stamp the effect spellID; the cast
-- handler then suppresses its own line for a stamped spell so one use
-- is one line. Deliberately that way round rather than "stamp now,
-- print on the cast": if the correlation fails the item still logged,
-- and the worst case is a redundant Spell line rather than silence.
-- A debug tool that loses the event it exists to show is worse than a
-- noisy one.
--
-- The ID tables at Providers.lua:223-265 are hand-maintained
-- spellID -> itemID maps, and Forever's IDs are not retail's. Harvesting
-- them by hovering tooltips (TOOL-01 above) only works for something
-- already in a bag; this covers whatever the player actually pressed.
---------------------------------------------------------------------

-- Effect spellID -> GetTime() of the item use that is about to produce it.
-- Only ever holds items the player actually used, and entries are consumed
-- by the matching cast, so this does not grow.
local pendingItemCasts = {}

-- An item use and its cast event are the same frame in practice. One second
-- is slack for a cast-time item (a bandage), not a real window.
local ITEM_CAST_WINDOW = 1.0

-- Every ID below arrives from a game API that may hand back a secret, and the
-- first comparison or concatenation against one raises. Same rule as the
-- tooltip block: issecretvalue() FIRST, before the type check, because type()
-- reports "number" for a secret number and passes on its own.
local function SafeNumber(value)
	if issecretvalue(value) or type(value) ~= "number" then
		return nil
	end
	return value
end

local function SafeString(value)
	if issecretvalue(value) or type(value) ~= "string" then
		return nil
	end
	return value
end

local function SpellName(spellID)
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if not ok or type(info) ~= "table" then
		return nil
	end
	return SafeString(info.name)
end

-- Resolves the effect spell an item casts, so the cast event it produces can be
-- recognised. Nil is a normal answer -- an item with no on-use has no effect
-- spell, and an uncached one may not answer yet.
local function ItemEffectSpellID(itemID)
	if not (C_Item and C_Item.GetItemSpell) then
		return nil
	end
	local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
	if not ok then
		return nil
	end
	return SafeNumber(spellID)
end

local function ItemName(itemID)
	if not (C_Item and C_Item.GetItemNameByID) then
		return nil
	end
	local ok, name = pcall(C_Item.GetItemNameByID, itemID)
	if not ok then
		return nil
	end
	return SafeString(name)
end

-- Logs an item use and stamps its effect spell so the cast event that follows
-- stays quiet. Called from all four use paths.
local function LogItemUse(itemID)
	if not ns.debugLogging then
		return
	end
	itemID = SafeNumber(itemID)
	if not itemID then
		return
	end

	local spellID = ItemEffectSpellID(itemID)
	if spellID then
		pendingItemCasts[spellID] = GetTime()
	end

	local line = "|cff00ccffTBT Debug|r: |cffffd100ITEM|r " .. (ItemName(itemID) or "?") .. " — itemID " .. itemID
	if spellID then
		line = line .. ", casts spellID " .. spellID
	end
	print(line)
end

-- Phase 49 racial-collection tooling (RACE-07). The workflow it serves, user's own description:
-- log into a character of each race, turn debug on, use both racials, send the log. For that to
-- produce a usable table the cast line is not enough -- a racial's CAST spell ID and the spell ID
-- of the AURA it applies are frequently different numbers, and RACIAL_SPELLS needs both.
--
-- So: after a player cast, look at the player's buffs and report only the ones that were not there
-- before. A cast that applies nothing (Shoot, Frostbolt) prints nothing extra, which matters --
-- the collection log is read by a human, and a buff dump on every cast would bury the one line
-- that carries the answer.
--
-- Out of combat only, by the user's own scoping of the exercise: aura reads are plain there
-- (ShouldAurasBeSecret() is false), so no per-field secret handling is needed. The combat gate and
-- the pcall stay anyway, at one line each, because GetAuraDataByIndex is RequiresUnitAuraAccess and
-- RAISES rather than degrading when called tainted while auras are secret (MergeMode.lua:544-556,
-- measured 2026-09-22). An accidental in-combat keypress must cost nothing; losing the whole log to
-- a raise is a worse outcome than skipping one line.
local knownPlayerAuras = {}
local seenThisScan = {}
-- spellID -> aura duration in seconds, filled by the same scan that fills the name table. Parallel
-- rather than packed into one table of tables: the scan runs on a debug path but still per cast,
-- and RACIAL_SPELLS wants a bare number anyway.
local scanDurations = {}
local newAuraNames, newAuraIDs, newAuraDurations = {}, {}, {}
-- spellID -> true for every cast already reported as applying no aura. Session-long and never
-- cleared: its whole job is to make the NO AURA line fire exactly once per spell, so clearing it
-- would reintroduce the spam it exists to prevent. Bounded by the number of distinct spells cast
-- while debug logging is on, which is a debug-only path.
local noAuraLogged = {}

-- Fills `out` with spellID -> name for the player's current buffs. Returns false when no route
-- answered, which is NOT the same as "no buffs" and must not be treated as an empty set.
local function CollectPlayerBuffs(out)
	wipe(out)
	wipe(scanDurations)

	-- Three routes, most-proven first, none assumed present: this file ships to both flavours from
	-- one source and the enumerator is exactly the kind of API that differs between them.
	-- GetUnitAuras leads because tools/TBTProbe already exercised it against Forever, so it is the
	-- one route known to exist there; the index walk is the retail-documented fallback; UnitAura is
	-- the classic-era global, which CLAUDE.md records as ABSENT on Forever but costs one type test.
	if C_UnitAuras and C_UnitAuras.GetUnitAuras then
		local ok = pcall(function()
			local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 40)
			if type(auras) ~= "table" then
				return
			end
			for i = 1, #auras do
				local aura = auras[i]
				if type(aura) == "table" then
					local id = SafeNumber(aura.spellId)
					if id then
						out[id] = SafeString(aura.name) or "?"
						scanDurations[id] = SafeNumber(aura.duration)
					end
				end
			end
		end)
		if ok and next(out) then
			return true
		end
	end

	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local ok = pcall(function()
			for i = 1, 40 do
				local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
				if not aura then
					break
				end
				local id = SafeNumber(aura.spellId)
				if id then
					out[id] = SafeString(aura.name) or "?"
					scanDurations[id] = SafeNumber(aura.duration)
				end
			end
		end)
		if ok and next(out) then
			return true
		end
	end

	if type(UnitAura) == "function" then
		local ok = pcall(function()
			for i = 1, 40 do
				-- Classic return order: name, icon, count, debuffType, duration, expirationTime,
				-- source, isStealable, nameplateShowPersonal, spellId.
				local name, _, _, _, duration, _, _, _, _, id = UnitAura("player", i, "HELPFUL")
				if not name then
					break
				end
				id = SafeNumber(id)
				if id then
					out[id] = SafeString(name) or "?"
					scanDurations[id] = SafeNumber(duration)
				end
			end
		end)
		if ok and next(out) then
			return true
		end
	end

	return false
end

-- The cast's own cooldown length, read 0.35s after the cast when the cooldown is already running,
-- so `duration` is the full value RACIAL_SPELLS wants rather than a remaining time.
--
-- Two shapes to handle: retail's C_Spell.GetSpellCooldown returns a SpellCooldownInfo table, the
-- classic-era global returns start, duration, enabled as three values. Both are tried and both are
-- pcall'd, because this ships to both flavours from one source.
--
-- The GCD is the trap. A racial off the global cooldown reads back ~1.5s here, which would be
-- recorded as a 1.5 second cooldown and be silently wrong in the table. Anything at or under 1.6s
-- is reported as "gcd?" rather than as a number, so it reads as a question in the log instead of
-- an answer.
local function ReadCastCooldown(spellID)
	local duration

	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
		if ok and type(info) == "table" then
			duration = SafeNumber(info.duration)
		end
	end

	if not duration and type(GetSpellCooldown) == "function" then
		local ok, _, d = pcall(GetSpellCooldown, spellID)
		if ok then
			duration = SafeNumber(d)
		end
	end

	if not duration or duration <= 0 then
		return nil, false
	end
	-- Second return: "this is a REAL cooldown, not the global". The caller needs the distinction
	-- because it decides whether a no-aura cast is worth a line at all -- printing every
	-- GCD-length reading would put a line under every Frostbolt and bury the collection data.
	if duration <= 1.6 then
		return "gcd?", false
	end
	return string.format("%.0f", duration), true
end

-- Prints the buffs gained since the previous scan, if any, and re-baselines. Called on a short
-- delay after a cast because an aura is not reliably applied by the time UNIT_SPELLCAST_SUCCEEDED
-- fires -- reading in the same frame is what would make a racial look like it applies nothing.
local function LogNewPlayerAuras(castSpellID)
	if not ns.debugLogging or InCombatLockdown() then
		return
	end
	if not CollectPlayerBuffs(seenThisScan) then
		return
	end

	wipe(newAuraNames)
	wipe(newAuraIDs)
	wipe(newAuraDurations)
	for id, name in pairs(seenThisScan) do
		if not knownPlayerAuras[id] then
			newAuraIDs[#newAuraIDs + 1] = id
			newAuraNames[id] = name
			-- Captured now, not read later: scanDurations is wiped by the next scan.
			newAuraDurations[id] = scanDurations[id]
		end
	end

	-- Re-baseline whether or not anything is printed, and to the scan just taken rather than by
	-- merging into it: a buff that EXPIRED has to leave the baseline too, or casting the same
	-- racial twice in one session would report nothing the second time.
	wipe(knownPlayerAuras)
	for id, name in pairs(seenThisScan) do
		knownPlayerAuras[id] = name
	end

	-- Read once, here, because BOTH branches below need it.
	local cd, cdIsReal = ReadCastCooldown(castSpellID)

	if #newAuraIDs == 0 then
		-- A cast that applied no aura still matters when it has a real cooldown, and this is
		-- exactly the cooldown-only racial: War Stomp, Will of the Forsaken. Both came back with
		-- NOTHING on their first collection pass, because the cooldown used to print only as part
		-- of the AURA GAINED line -- so the one field those racials do have was the one field the
		-- log dropped.
		--
		-- Once per distinct spell per session, which is the rule that makes this both complete and
		-- quiet.
		--
		-- The first attempt gated this on a REAL cooldown reading, to keep every Frostbolt and
		-- Shoot out of the log. That silenced the very case it was written for: human's Will to
		-- Survive applies no aura AND reports no readable cooldown at 0.35s, so it printed nothing
		-- at all (2026-09-24) -- indistinguishable, to whoever is reading the log, from the tool
		-- being broken. A collection tool must never go silent about a cast the user deliberately
		-- made.
		--
		-- Deduping by spellID bounds the noise without dropping anything: a spammed Frostbolt costs
		-- one line for the whole session, and every racial is guaranteed its line whatever its
		-- cooldown reads. The cooldown prints as whatever came back -- a number, "gcd?", or
		-- "none" -- because all three are real answers, and "none" is the one the old gate threw
		-- away.
		if not noAuraLogged[castSpellID] then
			noAuraLogged[castSpellID] = true
			print(
				"|cff00ccffTBT Debug|r: |cffffcc00NO AURA|r after "
					.. (SpellName(castSpellID) or ("spellID " .. tostring(castSpellID)))
					.. " — cooldown "
					.. (cd and (cd .. (cdIsReal and "s" or "")) or "none")
			)
		end
		return
	end

	table.sort(newAuraIDs)
	local line = "|cff00ccffTBT Debug|r: |cffffcc00AURA GAINED|r after "
		.. (SpellName(castSpellID) or ("spellID " .. tostring(castSpellID)))
		.. " —"
	for i = 1, #newAuraIDs do
		local id = newAuraIDs[i]
		line = line .. " " .. newAuraNames[id] .. " auraID " .. id

		-- duration=0 is what the game reports for a permanent aura, and it is a real answer rather
		-- than a missing one, so it is printed as "permanent" instead of as 0 or omitted.
		local dur = newAuraDurations[id]
		if dur and dur > 0 then
			line = line .. " duration " .. string.format("%.4g", dur) .. "s"
		elseif dur == 0 then
			line = line .. " duration permanent"
		end

		if i < #newAuraIDs then
			line = line .. ","
		end
	end

	-- One cooldown for the cast, appended once rather than per aura: it belongs to the spell, not
	-- to any buff it happened to apply. Read above, before the no-aura branch, which needs it too.
	if cd then
		line = line .. " | cooldown " .. cd .. (cd == "gcd?" and "" or "s")
	end

	print(line)
end

-- Called from the UNIT_SPELLCAST_SUCCEEDED handler above. Returns nothing; the
-- spellID is already screened there as the one ID this addon may trust.
function ns:LogPlayerCast(spellID)
	if not ns.debugLogging then
		return
	end
	spellID = SafeNumber(spellID)
	if not spellID then
		return
	end

	-- An item use already printed its own line for this spell. Consume the stamp
	-- either way: a stale one must not silence the same ability cast later.
	local stampedAt = pendingItemCasts[spellID]
	if stampedAt then
		pendingItemCasts[spellID] = nil
		if GetTime() - stampedAt <= ITEM_CAST_WINDOW then
			return
		end
	end

	print("|cff00ccffTBT Debug|r: |cff40ff40SPELL|r " .. (SpellName(spellID) or "?") .. " — spellID " .. spellID)

	-- 0.35s, not 0: the aura is not reliably applied in the frame UNIT_SPELLCAST_SUCCEEDED fires,
	-- and a same-frame read is what would make a racial look like it applies nothing at all. Long
	-- enough for a travel-time-free self-buff to land, short enough that the AURA GAINED line stays
	-- adjacent to its SPELL line in the log the user copies out.
	if C_Timer and C_Timer.After then
		C_Timer.After(0.35, function()
			LogNewPlayerAuras(spellID)
		end)
	end
end

-- The character's race, printed once as the collection log's header line.
--
-- RACIAL_SPELLS is keyed by the NUMERIC raceID (Providers.lua:772) and nothing else in the log
-- carries it. Survivable while collection covered races whose IDs are common knowledge; not
-- survivable once a Forever-only race appeared (Skyborn, 2026-09-24), whose row cannot be written
-- at all because its ID exists nowhere outside the client.
--
-- All three UnitRace returns: the localised name identifies the race to whoever reads the log, and
-- the token is the stable non-localised identifier if a row ever needs matching by name.
--
-- ON ns, NOT A FILE-LOCAL, and this one was learned the hard way rather than copied. The first
-- version of this inlined the print into the "/tbt debug" handler and called the file-locals
-- SafeString and SafeNumber from there. Both are declared hundreds of lines BELOW that handler, a
-- Lua local is an upvalue only to functions declared after it, so both were nil at call time and
-- every "/tbt debug" raised "attempt to call a nil value" (reported 2026-09-24, Core.lua:1074).
--
-- Providers.lua:886 documents this exact trap on ns:RacialCooldownSeed and says the project had
-- produced it FOUR times already. This was the fifth, written a few hours after reading that
-- comment. Resolving through ns happens at call time, so declaration order stops mattering.
--
-- It failed loudly, which was luck rather than design: the raise aborted the rest of the branch, so
-- ns:BaselinePlayerAuras never ran either and every collection log since carried no baseline.
function ns:LogPlayerRace()
	local raceName, raceFile, raceID = UnitRace("player")
	print(
		"|cff00ccffTBT Debug|r: |cffffcc00RACE|r "
			.. (SafeString(raceName) or "?")
			.. " ("
			.. (SafeString(raceFile) or "?")
			.. ") raceID "
			.. (SafeNumber(raceID) and tostring(raceID) or "?")
	)
end

-- Baselines the buff set the moment debug logging is switched on, so the first racial used after
-- "/tbt debug" reports just itself rather than every buff the character was already carrying.
-- Without this the first AURA GAINED line of a session is a wall of food, flasks and raid buffs
-- with the one useful ID buried in it.
function ns:BaselinePlayerAuras()
	if InCombatLockdown() then
		return
	end
	if CollectPlayerBuffs(seenThisScan) then
		wipe(knownPlayerAuras)
		for id, name in pairs(seenThisScan) do
			knownPlayerAuras[id] = name
		end
	end
end

-- The four ways an item use starts. hooksecurefunc is post-call and additive, so
-- none of these change what the function does; a failed hook costs the log line
-- for that one path and nothing else, which is why each is pcall'd separately
-- rather than assuming every global exists on both flavours.
-- `target` is the namespace table, or _G for a plain global -- passed explicitly
-- rather than defaulting, so a namespace that does not exist on a flavour skips
-- its hook instead of silently falling through to a same-named global whose
-- handler would then index the missing namespace and raise outside the pcall.
local function TryHook(target, name, handler)
	if type(target) ~= "table" or type(rawget(target, name)) ~= "function" then
		return false
	end
	if target == _G then
		return pcall(hooksecurefunc, name, handler)
	end
	return pcall(hooksecurefunc, target, name, handler)
end

-- Action bars. GetActionInfo answers "item" for an on-use item on a bar, which is
-- how a trinket or potion bound to a key gets caught.
TryHook(_G, "UseAction", function(slot)
	if not ns.debugLogging then
		return
	end
	local ok, actionType, id = pcall(GetActionInfo, slot)
	if not ok or SafeString(actionType) ~= "item" then
		return
	end
	LogItemUse(id)
end)

-- Right-clicking an item in a bag.
TryHook(C_Container, "UseContainerItem", function(bagID, slotIndex)
	if not ns.debugLogging then
		return
	end
	local ok, itemID = pcall(C_Container.GetContainerItemID, bagID, slotIndex)
	if ok then
		LogItemUse(itemID)
	end
end)

-- An equipped on-use item: a trinket clicked on the character sheet, or /use 13.
TryHook(_G, "UseInventoryItem", function(slot)
	if not ns.debugLogging then
		return
	end
	local ok, itemID = pcall(GetInventoryItemID, "player", slot)
	if ok then
		LogItemUse(itemID)
	end
end)

-- /use <name> in a macro. GetItemInfoInstant takes the same name, link or ID the
-- caller passed and answers the numeric itemID without needing the item cached.
TryHook(C_Item, "UseItemByName", function(itemInfo)
	if not ns.debugLogging then
		return
	end
	local ok, itemID = pcall(C_Item.GetItemInfoInstant, itemInfo)
	if ok then
		LogItemUse(itemID)
	end
end)
