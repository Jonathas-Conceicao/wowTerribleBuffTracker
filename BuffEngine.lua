local _, ns = ...

-- Runtime-only guard flags (not persisted to SavedVariables)
-- D-15: One-shot debug-log flag. Set to true on first C_Secrets.ShouldAurasBeSecret()==true of a session.
-- Cleared on combat-end and zone-change via ns:ClearSecretGateLog (Core.lua call sites).
ns.secretGateLogged = false
ns.debugLogging = false

-- Phase 21 (D-01/D-02/D-03): preview procs live in a SEPARATE table from real procs.
-- ns.activeTimers (declared in Core.lua) holds ONLY real procs with source="cast"/"debuff".
-- ns.previewTimers holds ONLY preview procs (no source field). Table separation provides
-- identity — no need for `isPreview` flag or `source="preview"` marker. ns:GetActiveTimers()
-- merges both with real-priority.
ns.previewTimers = {}

-- Secret-safe aura reads. While aura restrictions are active (combat, encounter, M+, PvP) the whole
-- UNIT_AURA payload arrives as secret values, and addon code may only store or pass a secret —
-- iterating, indexing, comparing or boolean-testing one throws. Every restricted aura read in this
-- addon goes through the two helpers below.

-- True when a table from a restricted API can be iterated/indexed by addon code.
-- type() and canaccesstable() are both safe to call on secrets.
function ns:CanReadTable(t)
	return type(t) == "table" and canaccesstable(t)
end

-- Secret-safe single-aura read. Per-spell "never secret" flags outrank the blanket restriction, so
-- lookups by spell ID still return real data for allowlisted spells (the Sated debuffs are). The
-- secrecy predicate MUST be asked first: a hidden aura returns no values, so a bare nil cannot tell
-- "absent" from "hidden".
-- Returns: aura, true  — readable, aura present
--          nil, true   — readable, aura absent
--          nil, false  — unreadable; presence is UNKNOWN and must never be read as absence
function ns:ReadPlayerAura(spellID)
	if C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return nil, false
	end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	-- issecretvalue() first: it is safe on nil and on secrets, unlike the == comparison below.
	if issecretvalue(aura) then
		return nil, false
	end
	if aura == nil then
		return nil, true
	end
	if not ns:CanReadTable(aura) then
		return nil, false
	end
	return aura, true
end

-- Thin wrapper. Combat-gates once at entry (PITFALL-5), then iterates all registered
-- providers calling each one's RefreshAtRest method. Meta-providers (Trinket/Pot)
-- perform the actual inventory scan inside their own RefreshAtRest; Lust/UserSpell
-- providers inherit the base no-op from SpellProviderBaseMixin.
function ns:RefreshProvidersAtRest()
	if InCombatLockdown() then
		return
	end
	for _, provider in ipairs(ns.providers) do
		provider:RefreshAtRest()
	end
end

-- Ordered list of meta-buff keys for CDM tab Suggested section.
-- Per-key display data (icon, label, duration, spellID) comes from ns:GetDisplayInfoForKey;
-- description text is CDMTab-local (META_DESCRIPTIONS in CDMTab.lua).
ns.SUGGESTED_KEYS = { "lust", "trinket", "pot" }
-- The racial cooldown tiles, offered on the COOLDOWNS tab rather than this list, which is the
-- Buffs catalogue. Their keys are ordinary "cd:<spellID>" strings resolved per character by
-- ns:RacialCooldownKeys, so adding one creates a normal cooldown tracker with nothing special
-- about it beyond having its duration filled in.
-- Racial is Forever-only. Retail's Cooldown Manager already carries racials, so offering TBT's
-- own would duplicate them -- and under Merge Mode it would land in the same container as the
-- CDM's copy of the same ability.
--
-- Appended rather than filtered so the list has no gap, and the Suggested section's
-- suggestedIndex stays a plain ipairs index. Only the OFFER is withheld: an entry already in a
-- player's database keeps working, because removing it would be destroying their data over a
-- presentation decision.
if ns.CLIENT_IS_FOREVER then
	-- Both slots. Forever gives most classes two racials, and the second is tracked exactly like
	-- the first: its own tile, empty by default, nothing auto-added.
	ns.SUGGESTED_KEYS[#ns.SUGGESTED_KEYS + 1] = "racial"
	ns.SUGGESTED_KEYS[#ns.SUGGESTED_KEYS + 1] = "racial2"
end

function ns:InitBuffEngine()
	-- v4 (CONT-01/CONT-03, Phase 35): renames the Tracked Buffs Edit Mode position key,
	-- retiring the v0.3.0 asymmetry between the position key and the section key that
	-- `entry.section` has always used for the same container. This is the only structural
	-- change four base containers requires — `bars`/`buffs` are already the correct
	-- `trackedBuffs` section keys, so no tracker entry is rewritten. `essential`/`utility`
	-- positions are not seeded here; Plan 02 seeds any missing container position
	-- idempotently when positions are applied, so a fresh and an upgraded database reach
	-- the same end state.
	-- Phase 38 (CD-06): adds no migration block at all. entry.trackerType reads as nil on a
	-- pre-Phase-37 entry, nil == "cooldown" is false, so a buff-only database is already
	-- correct as-is -- the schema version below stays unbumped.
	local CURRENT_SCHEMA_VERSION = 6
	local ver = ns.db.schemaVersion or 0

	if ver < 1 then
		-- v0 -> v1: Replace enabled/displayMode with section (D-01)
		for _, entry in pairs(ns.db.trackedBuffs) do
			if not entry.section then
				if entry.enabled == false then
					entry.section = "hidden"
				elseif entry.displayMode == "buff" then
					entry.section = "buffs"
				else
					entry.section = "bars"
				end
			end
			entry.enabled = nil
			entry.displayMode = nil
		end
		ns.db.schemaVersion = 1
		print("|cff00ccffTerribleBuffTracker|r: DB migrated to v1.")
	end

	if ver < 2 then
		-- v1 -> v2: Backfill layoutOrder for within-section reordering
		local order = 1
		for _, entry in pairs(ns.db.trackedBuffs) do
			if not entry.layoutOrder then
				entry.layoutOrder = order
				order = order + 1
			end
		end
		ns.db.schemaVersion = 2
	end

	if ver < 3 then
		-- v2 -> v3: Remove pre-seeded lust entry if it was added by earlier migration
		-- Lust meta-buff is now only created when user drags from Suggested (D-04/D-05)
		if ns.db.trackedBuffs["lust"] and ns.db.trackedBuffs["lust"].section == "hidden" then
			-- Only remove if user hasn't moved it (still in hidden = auto-seeded)
			ns.db.trackedBuffs["lust"] = nil
		end
		ns.db.schemaVersion = 3
	end

	if ver < 4 then
		-- v3 -> v4: rename the Tracked Buffs Edit Mode position key from `icons` to `buffs`,
		-- retiring the asymmetry where the section is "buffs" but the position was "icons".
		-- Nil-guarded: a v0.3.0 user who never entered Edit Mode has no editModePositions at
		-- all, so this is a no-op for them — Plan 02's idempotent seeding gives them all four
		-- defaults on next load.
		if ns.db.editModePositions then
			if ns.db.editModePositions.icons and not ns.db.editModePositions.buffs then
				ns.db.editModePositions.buffs = ns.db.editModePositions.icons
			end
			ns.db.editModePositions.icons = nil
		end
		ns.db.schemaVersion = 4
	end

	if ver < 5 then
		-- v4 -> v5: buff icon containers adopt Centered growth, which became their default in
		-- the same change (ns:DefaultGrowthDirection).
		--
		-- Migrated rather than left to the default, because the default only applies to a
		-- container whose settings do not exist yet -- every container a player already has
		-- carries growthDirection = 0, and nothing distinguishes "seeded before Centered
		-- existed" from "deliberately set to Right". Rewriting is defensible only because
		-- v0.4.0 has not shipped: no released build ever offered that choice, so there is no
		-- deliberate setting here to overwrite. Do NOT repeat this pattern after release.
		--
		-- Only direction 0 is touched. A container already on Left keeps it, since that is a
		-- choice this migration cannot have caused.
		if ns.db.containerSettings then
			for key, cs in pairs(ns.db.containerSettings) do
				local def = ns.CONTAINER_BY_KEY and ns.CONTAINER_BY_KEY[key]
				if
					def
					and cs.growthDirection == 0
					and def.kind ~= "bar"
					and ns:GetContainerCategory(def) == "buffs"
				then
					cs.growthDirection = ns.GROWTH_CENTERED
				end
			end
		end
		ns.db.schemaVersion = 5
	end

	if ver < 6 then
		-- v5 -> v6: cooldown trackers move to their own key namespace, "cd:<spellID>".
		--
		-- Until now ns.db.trackedBuffs was keyed by spell ID alone, so a buff tracker and a
		-- cooldown tracker for the same spell were the SAME RECORD and adding one silently
		-- replaced the other. Re-keying the cooldowns is what lets both exist.
		--
		-- Collected before mutating: adding and removing keys while iterating the table being
		-- iterated is undefined in Lua, and this loop does both.
		local rekey = {}
		for key, entry in pairs(ns.db.trackedBuffs) do
			if type(key) == "number" and entry.trackerType == "cooldown" then
				rekey[#rekey + 1] = key
			end
		end
		for _, key in ipairs(rekey) do
			local entry = ns.db.trackedBuffs[key]
			ns.db.trackedBuffs[key] = nil
			-- entry.spellID already holds the numeric ID and is not touched -- the key changes
			-- namespace, the record does not change meaning.
			ns.db.trackedBuffs[ns:TrackerKey(key, "cooldown")] = entry
		end
		-- The ONLY block that writes the constant. The earlier blocks keep their literals on
		-- purpose: `ns.db.schemaVersion = 3` inside `ver < 3` states where THAT migration ends,
		-- which is a fact about the chain and must not move when the current version does.
		-- Writing the constant here is what makes the declaration above load-bearing rather
		-- than decorative, so a future bump that touches only one of the two stops compiling
		-- the wrong answer silently.
		ns.db.schemaVersion = CURRENT_SCHEMA_VERSION
	end

	-- Pre-allocate a proc buffer for every tracker already in the database, so the first cast of
	-- a session costs nothing either. Runs after the migrations above, which is the point: a
	-- migration can still be adding or renaming slots, and pre-allocating before that would
	-- build buffers for keys that no longer exist and miss the ones that now do.
	for key in pairs(ns.db.trackedBuffs) do
		ns:PreallocateProc(key)
	end
end

function ns:GetSpellIcon(spellID)
	if not spellID or type(spellID) ~= "number" then
		return 134400 -- Question mark icon fallback for nil/string keys
	end
	local info = C_Spell.GetSpellInfo(spellID)
	if info and info.iconID then
		return info.iconID
	end
	return 134400 -- Question mark icon fallback
end

function ns:OnSpellCastSucceeded(spellID)
	-- PROV-02, D-18/D-19: OnSpellCastSucceeded has zero branches. All cast-triggered buff
	-- detection (trinket, pot, user-spell) is dispatched to providers via GetEventInterests.
	-- See Providers.lua for TrinketProvider, PotProvider, UserSpellProvider definitions.
	ns:DispatchEventToProviders("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellID)
end

-- THE PROC POOL. One proc table per tracker slot, allocated when the tracker is added and
-- released when it is removed, so a CAST allocates nothing (user decision, 2026-09-22).
--
-- The rule this implements, in the user's words: allocate when the CDM is open and the player is
-- adding or removing tracked spells, never when a proc happens. Slightly more memory held
-- constantly, no garbage generated in combat.
--
-- One buffer per slot is sufficient BY CONSTRUCTION, not by luck: ns.activeTimers is keyed by
-- slot, so a slot can hold at most one live timer, and a second cast of the same spell is
-- replacing the first rather than joining it.
--
-- PREVIEW PROCS ARE NOT POOLED, deliberately. ns.previewTimers and ns.activeTimers are separate
-- tables on purpose -- that separation is what fixed the mid-preview-cast-loss bug in Phase 21 --
-- and drawing both from one per-slot buffer would alias them and bring it straight back. Preview
-- only exists while the CDM config window is open, which is exactly the moment the rule above
-- permits allocation.
local procPool = {}

-- The aliveBuffs fallback array, pooled the same way and for the same reason. Providers that can
-- use a SHARED list (ns.rankFamilies for ranked spells, SHARED_LUST_BUFFS_LOCAL for lust) assign
-- that reference directly and must never wipe it; this is only for the one-element fallback those
-- providers used to build with a table constructor per cast.
local aliveBuffsPool = {}

-- Declared HERE, with the other pools, and not beside ns:AcquireDisplayInfo further down.
-- A Lua file-local is only an upvalue to functions defined AFTER it: sitting below
-- ns:ReleaseProc made this a nil GLOBAL read inside it, and deleting a tracker threw
-- "attempt to perform indexed assignment on global 'displayInfoPool'". The same trap has now
-- cost this project three separate bugs -- see STATE.md.
-- Display-info buffers, pooled per key for the same reason the procs are.
--
-- ns:GetDisplayInfoForKey is on the RENDER path, not just the config path: both render functions
-- call it for every placeholder slot they draw (Display.lua, the two placeholder branches), which
-- is every inactive tracker, every container, every tick, whenever "hide when inactive" is off or
-- the CDM config window is open. Every provider's GetDisplayInfo built a fresh four-field table
-- there. That is the same exposure Phase 42 removed from the tooltip payload beside it, and the
-- half it missed -- pooling the payload while the table feeding it still allocated.
--
-- Safe to share because NO caller retains one. The three config callers in CDMTab.lua read their
-- fields and drop it on the same line; ns:ShowBuffTooltip reads three fields into GameTooltip and
-- returns. Keyed by tracker key, so two different keys in flight at once cannot collide either.
-- A caller that starts holding one across frames has to stop using this.
local displayInfoPool = {}

-- Hands back the slot's proc table, wiped. The wipe is load-bearing rather than hygiene: the
-- racial proc carries "stacks" and no "aliveBuffs", every other proc carries "aliveBuffs" and no
-- "stacks", and a provider that stopped setting a field would otherwise inherit the previous
-- cast's value for it. Keys never cross providers -- "racial", "lust", "trinket", "pot" and the
-- numeric user-spell keys are disjoint -- so this guards against future edits, not present ones.
function ns:AcquireProc(key)
	local proc = procPool[key]
	if proc then
		wipe(proc)
	else
		proc = {}
		procPool[key] = proc
	end
	return proc
end

-- The one-element aliveBuffs list for a slot, reused. Callers that have a shared list to hand must
-- assign it instead of calling this.
function ns:AcquireAliveBuffs(key, spellID)
	local list = aliveBuffsPool[key]
	if list then
		wipe(list)
	else
		list = {}
		aliveBuffsPool[key] = list
	end
	list[1] = spellID
	return list
end

-- Pre-allocate a slot's buffers. Called when a tracker is added and for every entry already in
-- the database at load, so the first cast of a session costs nothing either. ns:AcquireProc
-- still creates on demand, which is what covers a meta tracker whose slot is seeded elsewhere.
function ns:PreallocateProc(key)
	if procPool[key] == nil then
		procPool[key] = {}
	end
	if aliveBuffsPool[key] == nil then
		aliveBuffsPool[key] = {}
	end
end

-- Drop a removed tracker's buffers. Without this the pools would only ever grow, and a player who
-- adds and deletes trackers all session would hold a table per slot they no longer have.
function ns:ReleaseProc(key)
	procPool[key] = nil
	aliveBuffsPool[key] = nil
	displayInfoPool[key] = nil
end

function ns:AcquireDisplayInfo(key)
	local info = displayInfoPool[key]
	if info then
		wipe(info)
	else
		info = {}
		displayInfoPool[key] = info
	end
	return info
end

-- Scratch for ns:GetActiveTimers, reused rather than rebuilt. That function runs 20 times a
-- second for as long as the addon is loaded, whether or not anything is tracked and whether or
-- not the player is in combat -- so its two table constructors and its inline comparator were
-- the addon's largest per-tick allocation by a wide margin: three objects per tick, 60 a second,
-- ~18,000 over a five-minute fight, most of them to discover that nothing had changed.
--
-- wipe() keeps each table's capacity, which is the point: after a few ticks these have grown to
-- fit the busiest moment and never allocate again. A constant, slightly larger footprint in
-- exchange for no garbage in the combat path is the trade this addon wants (user decision,
-- 2026-09-22), and it is the same trade ns.CONTAINERS' per-container lists already make.
local activeTimerSet = {}
local activeTimerList = {}

-- Hoisted for exactly the reason Display.lua hoists ByLayoutOrder: an inline comparator is a
-- fresh closure on every call. That comment has been in Display.lua since Phase 21 while the
-- function feeding it allocated one per tick.
local function ByExpiry(a, b)
	return a.expiresAt < b.expiresAt
end

function ns:GetActiveTimers()
	-- Phase 21 (D-05/D-06/D-17/D-18): merge preview + active with real-priority. Same-key
	-- collision resolves to the real proc from ns.activeTimers. Lazy cleanup of expired
	-- entries during iteration. Display.lua sees an unchanged interface — a sorted list.
	--
	-- The returned list is a SHARED BUFFER, valid until the next call. That is safe because
	-- there is exactly one caller, ns:UpdateDisplay, which walks it into the per-container lists
	-- and is finished with it before returning; WoW runs addon code single-threaded, so no event
	-- can land mid-walk. A second caller that retained the list across a tick would see it
	-- rewritten underneath them -- add one and this contract has to change with it.
	local now = GetTime()
	wipe(activeTimerSet)

	-- 1. Preview entries first (filter expired; lazy cleanup)
	for key, proc in pairs(ns.previewTimers) do
		if proc.expiresAt > now then
			activeTimerSet[key] = proc
		else
			ns.previewTimers[key] = nil
		end
	end

	-- 2. Real active entries override previews for same key (real-priority per D-05)
	for key, proc in pairs(ns.activeTimers) do
		if proc.expiresAt <= now then
			ns.activeTimers[key] = nil
		else
			activeTimerSet[key] = proc
		end
	end

	-- 3. Flatten to sorted list (ascending by expiresAt — shortest remaining time first).
	-- Counted rather than table.insert'd: # on a freshly wiped table is 0 and grows correctly,
	-- but a local counter says what is meant and skips the length lookup per entry.
	wipe(activeTimerList)
	local count = 0
	for _, proc in pairs(activeTimerSet) do
		count = count + 1
		activeTimerList[count] = proc
	end
	table.sort(activeTimerList, ByExpiry)
	return activeTimerList
end

-- opts (Plan 37-02, all fields optional, three-argument callers remain valid):
--   opts.trackerType   "buff" / "cooldown" -- anything else, including nil, stores "buff".
--   opts.section        a container key -- written through as-is when it is a string;
--                        falls back to "hidden" otherwise (D-05, unchanged default).
--   opts.coverAllRanks   true/false -- stores true or stores nothing, never false, so an
--                        uncovered entry stays byte-identical to a pre-phase one. Consumed
--                        only by ns:RebuildRankIndex (Core.lua); read nowhere in this file.
function ns:AddTrackedBuff(spellID, duration, label, opts)
	if not spellID or spellID <= 0 then
		print("|cff00ccffTerribleBuffTracker|r: Invalid spell ID.")
		return false
	end
	if not duration or duration <= 0 then
		print("|cff00ccffTerribleBuffTracker|r: Invalid duration.")
		return false
	end

	local displayLabel = label
	if not displayLabel or displayLabel == "" then
		local info = C_Spell.GetSpellInfo(spellID)
		if info and info.name then
			displayLabel = info.name
		else
			displayLabel = "Spell " .. spellID
		end
	end

	-- Assign next layoutOrder (max existing + 1)
	local maxOrder = 0
	for _, e in pairs(ns.db.trackedBuffs) do
		if e.layoutOrder and e.layoutOrder > maxOrder then
			maxOrder = e.layoutOrder
		end
	end

	local trackerType = (opts and opts.trackerType == "cooldown") and "cooldown" or "buff"
	-- D-05: new trackers still default to Not Displayed. The dialog's container choice is the
	-- only thing that overrides that default -- an unchosen container must never resolve to a
	-- visible one, so anything other than an explicit string section still falls to "hidden".
	local section = (opts and type(opts.section) == "string") and opts.section or "hidden"

	-- Namespaced, so a buff tracker and a cooldown tracker for the same spell are two records
	-- rather than one overwriting the other. See ns.COOLDOWN_KEY_PREFIX in Core.lua.
	local dbKey = ns:TrackerKey(spellID, trackerType)

	ns.db.trackedBuffs[dbKey] = {
		spellID = spellID,
		duration = duration,
		label = displayLabel,
		trackerType = trackerType,
		section = section,
		layoutOrder = maxOrder + 1,
		-- store true or store nothing, never false (see opts doc above).
		coverAllRanks = (opts and opts.coverAllRanks) and true or nil,
	}

	-- Pre-allocate the slot's proc buffers with the slot itself, so the first cast of this
	-- tracker allocates nothing either. This is the "allocate when the player adds a tracker"
	-- half of the pooling rule; ns:ReleaseProc in ns:RemoveTrackedBuff is the other half.
	ns:PreallocateProc(dbKey)

	print(
		"|cff00ccffTerribleBuffTracker|r: Now tracking |cff00ff00"
			.. displayLabel
			.. "|r ("
			.. trackerType
			.. ", ID: "
			.. spellID
			.. ", "
			.. duration
			.. "s)."
	)

	-- RANK-01: a newly covered tracker must work on the very next cast, without waiting for
	-- the next SPELLS_CHANGED. Nil-guarded because this file can in principle run before
	-- Core.lua's definitions are reachable -- load-order insurance, not a migration leftover.
	if ns.RebuildRankIndex then
		ns:RebuildRankIndex()
	end
	-- Phase 38 (CD-04): a new tracker changes the set Plan 02's per-container slot count is
	-- built from. Nil-guarded for the same load-order reason as ns:RebuildRankIndex above.
	if ns.MarkTrackersDirty then
		ns:MarkTrackersDirty()
	end
	return true
end

function ns:RemoveTrackedBuff(spellID)
	local entry = ns.db.trackedBuffs[spellID]
	if not entry then
		print("|cff00ccffTerribleBuffTracker|r: Spell ID " .. spellID .. " is not tracked.")
		return false
	end

	local label = entry.label
	ns.db.trackedBuffs[spellID] = nil
	ns.activeTimers[spellID] = nil
	-- Release the slot's pooled proc with the slot itself. The timer above is cleared first, so
	-- nothing is holding the table when it goes.
	ns:ReleaseProc(spellID)

	print("|cff00ccffTerribleBuffTracker|r: Stopped tracking |cffff6600" .. label .. "|r (ID: " .. spellID .. ").")

	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
	-- RANK-01: removing a tracker changes the set of index owners just as adding one does.
	-- Nil-guarded for the same wave-1-standalone reason as ns:AddTrackedBuff above.
	if ns.RebuildRankIndex then
		ns:RebuildRankIndex()
	end
	-- Phase 38 (CD-04): same reasoning as ns:AddTrackedBuff above -- removing a tracker also
	-- changes the set Plan 02's per-container slot count is built from.
	if ns.MarkTrackersDirty then
		ns:MarkTrackersDirty()
	end
	return true
end

function ns:SetBuffSection(spellID, section)
	if not spellID then
		return
	end
	if type(spellID) ~= "number" and type(spellID) ~= "string" then
		return
	end
	local entry = ns.db.trackedBuffs[spellID]
	if not entry then
		return
	end
	entry.section = section
	if ns.activeTimers[spellID] then
		ns.activeTimers[spellID].section = section
	end
	if section == "hidden" then
		ns.activeTimers[spellID] = nil
	end
	-- Phase 38 (CD-04): re-sectioning a tracker changes the set Plan 02's per-container slot
	-- count is built from, same as adding or removing one.
	if ns.MarkTrackersDirty then
		ns:MarkTrackersDirty()
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

-- RACE-03: the early-expiry path. BuffEngine keeps ownership of timer lifecycle; providers call
-- in, exactly as UserSpellProviderMixin:OnTrigger already calls ns:MarkCooldownsDirty. Clears the
-- real proc only when one was actually present. Does NOT touch ns.previewTimers.
function ns:EndTimer(key)
	if not ns.activeTimers[key] then
		return
	end
	ns.activeTimers[key] = nil
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:StartAllPreviewTimers()
	-- Phase 21 (D-07/D-08/D-09): additive preview. Writes to ns.previewTimers (never to
	-- ns.activeTimers). Skips keys with a live real proc so real beats preview at insertion
	-- time (D-05 priority enforced twice: here and in ns:GetActiveTimers merge). Sole data
	-- source is ns:GetDisplayInfoForKey(key) — provider owns icon/label/duration/spellID
	-- resolution (D-08).
	wipe(ns.previewTimers)
	local now = GetTime()
	for key, entry in pairs(ns.db.trackedBuffs) do
		-- A cooldown entry previews from entry.duration like any other entry -- a synthetic
		-- demo built from a number the user typed, with no game value read and no secret
		-- involved. The existing icon render path below already turns it into a demo sweep
		-- with no type branch needed.
		if entry.section ~= "hidden" then
			-- Skip if a live real proc already owns this key (D-05 priority at insertion time).
			--
			-- ns.activeTimers is not the whole answer any more. A custom cooldown never enters it
			-- -- it is a slot, not a timer -- so its live state lives in ns.cooldownStarts, and
			-- without the second test a preview would paint a demo sweep straight over a cooldown
			-- that was genuinely running. Preview is ADDITIVE: it shows what a tracker would look
			-- like where nothing is happening, and never replaces something that is.
			local real = ns.activeTimers[key]
			local live = (real and real.expiresAt > now) or ns:IsCooldownRunning(key, entry, now)
			if not live then
				local info = ns:GetDisplayInfoForKey(key)
				if info then
					ns.previewTimers[key] = {
						key = key,
						spellID = info.spellID, -- numeric (D-10); Display tooltip handler uses uniformly
						duration = info.duration,
						expiresAt = now + info.duration,
						startedAt = now,
						label = info.label,
						section = entry.section,
						layoutOrder = entry.layoutOrder,
						-- Phase 41: unconditional field copy, no type branch -- nil for every
						-- provider except Racial, so no existing preview behaviour changes and a
						-- supported racial previews at its full stack count.
						stacks = info.stacks,
						-- NO aliveBuffs (previews not in ns.activeTimers), NO icon (Display derives it D-33)
					}
				end
			end
		end
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:ClearAllTimers()
	-- Phase 21 (D-11/D-12): preview-scoped wipe. Real procs in ns.activeTimers are untouched —
	-- they continue their natural countdown. This is the architectural fix for the pre-existing
	-- mid-CDM real-cast-loss bug identified in Phase 20 verification (a trinket cast between
	-- StartAllPreviewTimers and ClearAllTimers used to be snapshotted at open time and restored
	-- at close time — any mid-preview cast was lost). Separate tables eliminate the bug.
	wipe(ns.previewTimers)
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

function ns:ScanActiveTimersForCancellation()
	local cancelledCount = 0
	local cancelledLabels

	for key, timer in pairs(ns.activeTimers) do
		-- D-09/D-11: Data-driven cancellation. aliveBuffs is the list of buff spellIDs to
		-- check — if ANY is present, the proc is alive; if NONE are present, cancel.
		-- Defensive: skip procs with missing or empty aliveBuffs (opaque — never cancel
		-- what we can't verify). No branching on timer.source (D-10).
		if timer.aliveBuffs and #timer.aliveBuffs > 0 then
			local anyPresent = false
			-- An aura read can be unreadable per spell even past the gate in OnUnitAura. Unknown
			-- presence must not be read as absence, so one unreadable buff aborts this proc's check.
			local allReadable = true
			for _, buffID in ipairs(timer.aliveBuffs) do
				local aura, readable = ns:ReadPlayerAura(buffID)
				if not readable then
					allReadable = false
					break
				elseif aura then
					anyPresent = true
					break
				end
			end
			if allReadable and not anyPresent then
				ns.activeTimers[key] = nil
				cancelledCount = cancelledCount + 1
				if ns.debugLogging then
					if not cancelledLabels then
						cancelledLabels = {}
					end
					table.insert(cancelledLabels, timer.label or tostring(key))
				end
			end
		end
	end

	if cancelledCount > 0 then
		if ns.debugLogging and cancelledLabels then
			print(
				"|cff00ccffTBT Debug|r: Cancelled "
					.. cancelledCount
					.. " timer(s): "
					.. table.concat(cancelledLabels, ", ")
			)
		end
		if ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
	end
end

function ns:OnUnitAura(updateInfo)
	-- Phase 19 (D-14): Provider dispatch runs FIRST — unconditional. LustProvider reads addedAuras
	-- internally, performs per-entry issecretvalue(aura.spellId) checks (D-10), and applies the
	-- provider-internal no-restart guard (D-12). The dispatcher has NO gate logic (D-04) so
	-- LUST-01 pre-gate ordering is preserved by architecture: Sated-detection runs before the
	-- ShouldAurasBeSecret() scan gate below, satisfying PITFALL-6.
	ns:DispatchEventToProviders("UNIT_AURA", "player", updateInfo)

	-- AURA-02 / D-14: Gate the cancellation SCAN on secret restriction. The dispatch above
	-- already completed — these gates apply only to ScanActiveTimersForCancellation.
	-- secretGateLogged (D-15) is a one-shot debug-log flag; cleared by ns:ClearSecretGateLog
	-- from Core.lua's PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA handlers.
	if C_Secrets.ShouldAurasBeSecret() then
		if not ns.secretGateLogged then
			ns.secretGateLogged = true
			if ns.debugLogging then
				print("|cff00ccffTBT Debug|r: aura scan blocked — ShouldAurasBeSecret() returned true")
			end
		end
		return
	end

	-- ZONE-02: Suppress on isFullUpdate (zone boundary / loading screen transient).
	-- isFullUpdate arrives secret while auras are restricted and a boolean test on a secret throws,
	-- so issecretvalue() gates the test; unknown counts as "not a full update" (the secret gate
	-- above has already returned in that case).
	local isFullUpdate = updateInfo and updateInfo.isFullUpdate
	if not issecretvalue(isFullUpdate) and isFullUpdate then
		if ns.debugLogging then
			print("|cff00ccffTBT Debug|r: UNIT_AURA isFullUpdate suppressed")
		end
		return
	end

	-- Phase 21 (D-15): preview guard removed. ScanActiveTimersForCancellation iterates
	-- ns.activeTimers ONLY — preview procs live in a separate ns.previewTimers table and
	-- are invisible to the scan by construction (D-19/D-20). No leakage possible because
	-- preview procs carry no aliveBuffs field; the defensive guard in ScanActiveTimersForCancellation
	-- skips procs with missing/empty aliveBuffs (D-11).
	ns:ScanActiveTimersForCancellation()
end

-- D-16: Clears the one-shot secret-gate debug-log flag so re-entering a secret
-- context logs the "aura scan blocked" message once again. Called from Core.lua
-- in PLAYER_REGEN_ENABLED (combat end) and ZONE_CHANGED_NEW_AREA handlers.
function ns:ClearSecretGateLog()
	local wasLogged = ns.secretGateLogged
	ns.secretGateLogged = false
	if ns.debugLogging and wasLogged then
		print("|cff00ccffTBT Debug|r: secret-gate log cleared")
	end
end
