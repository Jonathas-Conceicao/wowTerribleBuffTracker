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
ns.SUGGESTED_KEYS = { ns.META_KEY.LUST, ns.META_KEY.TRINKET, ns.META_KEY.POT }

-- Hoisted to module scope (was function-local inside ns:InitBuffEngine) because the schema
-- migrations -- ns:MigrateRacialKeys, ns:MigrateKindKeys, ns:MigrateDropDetailedFlag,
-- ns:MigrateBuffReminders, ns:MigrateReminderAlternatives and ns:MigrateDropRacials, below -- run
-- OUTSIDE that function's chain, and could not read a local declared inside ns:InitBuffEngine.
-- Schema v12 (ns:MigrateDropRacials, MIG-03, Phase 67) is now the newest block in the chain and the
-- one that writes this constant -- v6 through v11 keep their own literals instead (see each
-- block's own comment for why). The migrations run once, from ns:InitBuffEngine: the old
-- world-entry retry existed only because v7 needed a readable race, and v7 no longer reads one.
local CURRENT_SCHEMA_VERSION = 12

function ns:InitBuffEngine()
	-- v4 (CONT-01/CONT-03, Phase 35): renames the Tracked Buffs Edit Mode position key,
	-- retiring the v0.3.0 asymmetry between the position key and the section key that
	-- `entry.section` has always used for the same container. This is the only structural
	-- change four base containers requires — `bars`/`buffs` are already the correct
	-- `trackedBuffs` section keys, so no tracker entry is rewritten. `essential`/`utility`
	-- positions are not seeded here; Plan 02 seeds any missing container position
	-- idempotently when positions are applied, so a fresh and an upgraded database reach
	-- the same end state.
	-- Phase 38 (CD-06) added no migration block: a pre-Phase-37 entry's nil trackerType read as
	-- a buff. Since Phase 53 the runtime reads only canonical kinds, and schema v8
	-- (ns:MigrateKindKeys, below) is what stamps a nil trackerType on a numeric key as userBuff.
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
			-- namespace, the record does not change meaning. Frozen literal, not ns:TrackerKey:
			-- that helper now mints CANONICAL "<kind>:<id>" keys, and this block must keep
			-- producing exactly what v0.4.x produced -- schema v8 below re-keys "cd:" afterwards.
			ns.db.trackedBuffs["cd:" .. key] = entry
		end
		-- v6 is now an EARLIER block in this chain, so by its own historical rule it keeps a
		-- literal rather than the constant: `ns.db.schemaVersion = 6` states where THIS
		-- migration ends, a fact about the chain that must not move just because the current
		-- version does. Schema v7 (ns:MigrateRacialKeys), v8 (ns:MigrateKindKeys), v9
		-- (ns:MigrateDropDetailedFlag), v10 (ns:MigrateBuffReminders), v11
		-- (ns:MigrateReminderAlternatives) and v12 (ns:MigrateDropRacials, all below) are the newer
		-- migrations now; v12 is the one that writes CURRENT_SCHEMA_VERSION.
		ns.db.schemaVersion = 6
	end

	-- Schema v7 (49-03): drops the legacy "racial"/"racial2" slots (Phase 67). Runs before v8.
	ns:MigrateRacialKeys()
	-- Schema v8 (NAME-01/NAME-02, Phase 53): must follow v7 -- it re-keys onto ns.KIND.
	ns:MigrateKindKeys()
	-- Schema v9 (Phase 57.1): must follow a completed v8.
	ns:MigrateDropDetailedFlag()
	-- Schema v10 (Phase 57.2): must follow a completed v9.
	ns:MigrateBuffReminders()
	-- Schema v11 (Phase 57.5): must follow a completed v10.
	ns:MigrateReminderAlternatives()
	-- Schema v12 (Phase 67, MIG-03): must follow a completed v11.
	ns:MigrateDropRacials()

	-- Pre-allocate a proc buffer for every tracker already in the database, so the first cast of
	-- a session costs nothing either. Runs after the migrations above, which is the point: a
	-- migration can still be adding or renaming slots, and pre-allocating before that would
	-- build buffers for keys that no longer exist and miss the ones that now do.
	for key in pairs(ns.db.trackedBuffs) do
		ns:PreallocateProc(key)
	end
	-- Casts cannot arrive before PLAYER_ENTERING_WORLD, whose ns:RebuildRankIndex also rebuilds
	-- the cast index -- this call keeps ns.buffKeyBySpell/ns.cooldownKeyBySpell valid from load
	-- regardless, rather than leaving them empty for the gap between ADDON_LOADED and world entry.
	ns:RebuildCastIndex()
end

-- Schema v7 (49-03): drops the pre-v7 two-slot "racial"/"racial2" tracker entries. Phase 67
-- removed racials, so those records address nothing: they are dropped, not re-keyed, and the race
-- is never read. Pinned to the LITERAL 7 (an EARLIER block in the chain; the v6 block above states
-- the rule). Spec: scripts/migrate-dryrun.js migrateV7.
function ns:MigrateRacialKeys()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	if (ns.db.schemaVersion or 0) >= 7 then
		return
	end

	ns.db.trackedBuffs.racial = nil
	ns.db.trackedBuffs.racial2 = nil
	ns.db.schemaVersion = 7
end

-- Schema v8 (NAME-01/NAME-02, Phase 53): re-keys every tracker onto the canonical "<kind>:<id>"
-- scheme (Core.lua's ns.KIND), stamps entry.trackerType with the canonical kind, and backfills
-- entry.spellID/entry.itemID where they were only implicit in the old key shape.
--
-- Runs only after schema v7 has completed. Reads ns.db.schemaVersion FRESH on every call (not a
-- `ver` captured earlier), matching ns:MigrateRacialKeys' own design: called once from
-- ns:InitBuffEngine.
--
-- Move the record, never rebuild it (the v6 precedent): every key is collected into a snapshot
-- array BEFORE any key is deleted or written, because mutating ns.db.trackedBuffs while iterating
-- it is undefined in Lua.
--
-- Classification (spec: scripts/migrate-dryrun.js migrateV8, reconciled against this code in
-- plan 53-05):
--   numeric key, trackerType nil/"buff"  -> userBuff:<key>
--   numeric key, trackerType "cooldown"  -> userCd:<key> (defensive only -- v6 should already
--                                           have re-keyed this to "cd:<id>")
--   "cd:<N>"                             -> userCd:<N>
--   either cooldown shape, N in the frozen LEGACY_RACIAL_CD list below -> DROPPED (MIG-03: a
--                                           v0.4.x racial cooldown tile is removed, never kept)
--   "item:<N>"                           -> metaItem:<N>
--   "racial:<N>"                         -> metaSkill:<N>
--   "lust" / "trinket" / "pot"           -> ns.META_KEY.LUST / .TRINKET / .POT
--   already "<knownKind>:..."            -> key unchanged, trackerType (re)stamped
--   anything else                        -> left untouched
--
-- Pinned to the LITERAL 8, not CURRENT_SCHEMA_VERSION (Phase 57.1): this is now an EARLIER block
-- in the chain, so by its own historical rule (see the v6/v7 blocks above) it keeps a literal
-- rather than the constant -- bumping CURRENT_SCHEMA_VERSION to 9 must never let a completed v8
-- database re-run this block, or skip straight to 9 without schema v9
-- (ns:MigrateDropDetailedFlag, below) actually running. v9 is now the block that writes the
-- constant; v9 runs after this one.
function ns:MigrateKindKeys()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	local ver = ns.db.schemaVersion or 0
	if ver >= 8 then
		return
	end
	if ver < 7 then
		-- Kept as a chain-order guard: v7 no longer defers, so this is not reached in practice.
		return
	end

	-- The legacy identifiers live ONLY here as function-local literals -- everywhere else in
	-- this addon a key is minted and parsed through Core.lua's ns.KIND/ns:TrackerKey scheme.
	local COOLDOWN_PATTERN = "^cd:(%d+)$"
	local ITEM_PATTERN = "^item:(%d+)$"
	local RACIAL_PATTERN = "^racial:(%d+)$"
	-- Frozen (Phase 67 review WR-01): every spellID the v0.4.0-v0.5.1 racial catalogue offered as a
	-- racial cooldown tile, i.e. every legacy cooldown key the old v8 classified as racial. History,
	-- not a catalogue -- this list must never grow. Mirrored in scripts/migrate-dryrun.js.
	local LEGACY_RACIAL_CD = {
		[20600] = true,
		[1259718] = true,
		[20572] = true,
		[1299026] = true,
		[20594] = true,
		[20580] = true,
		[1259799] = true,
		[20577] = true,
		[7744] = true,
		[20549] = true,
		[20552] = true,
		[1259817] = true,
		[20589] = true,
		[20554] = true,
		[1260270] = true,
		[1259416] = true,
		[1259705] = true,
		[1259686] = true,
	}

	-- Collected before mutating: adding and removing keys while iterating the table being
	-- iterated is undefined in Lua (the v6 block's own precedent).
	local oldKeys = {}
	for key in pairs(ns.db.trackedBuffs) do
		oldKeys[#oldKeys + 1] = key
	end

	local moved = false
	for _, oldKey in ipairs(oldKeys) do
		local entry = ns.db.trackedBuffs[oldKey]
		local newKey, kind, id
		-- Set for a legacy racial cooldown: the record is removed, not re-keyed (WR-01).
		local dropRacial = false

		if type(oldKey) == "number" then
			local trackerType = entry.trackerType
			if trackerType == nil or trackerType == "buff" then
				kind = ns.KIND.USER_BUFF
				id = oldKey
				newKey = ns:TrackerKey(kind, id)
			elseif trackerType == "cooldown" then
				if LEGACY_RACIAL_CD[oldKey] then
					dropRacial = true
				else
					kind = ns.KIND.USER_CD
					id = oldKey
					newKey = ns:TrackerKey(kind, id)
				end
			end
			-- anything else (an already-numeric key with an unrecognised trackerType) is left
			-- exactly as it is -- newKey stays nil.
		elseif type(oldKey) == "string" then
			local n = oldKey:match(COOLDOWN_PATTERN)
			if n then
				if LEGACY_RACIAL_CD[tonumber(n)] then
					dropRacial = true
				else
					id = tonumber(n)
					kind = ns.KIND.USER_CD
					newKey = ns:TrackerKey(kind, id)
				end
			else
				n = oldKey:match(ITEM_PATTERN)
				if n then
					id = tonumber(n)
					kind = ns.KIND.META_ITEM
					newKey = ns:TrackerKey(kind, id)
				else
					n = oldKey:match(RACIAL_PATTERN)
					if n then
						id = tonumber(n)
						kind = ns.KIND.META_SKILL
						newKey = ns:TrackerKey(kind, id)
					elseif oldKey == "lust" then
						kind = ns.KIND.META_SKILL
						newKey = ns.META_KEY.LUST
					elseif oldKey == "trinket" then
						kind = ns.KIND.META_ITEM
						newKey = ns.META_KEY.TRINKET
					elseif oldKey == "pot" then
						kind = ns.KIND.META_ITEM
						newKey = ns.META_KEY.POT
					else
						-- Already canonical -- key unchanged, only trackerType is (re)stamped.
						-- No id, so no spellID/itemID backfill below.
						local existingKind = ns:KeyKind(oldKey)
						if existingKind then
							kind = existingKind
							newKey = oldKey
						end
					end
				end
			end
			-- anything else (an unrecognised string key) is left exactly as it is.
		end

		-- A legacy racial cooldown is dropped silently, like v12 (67-CONTEXT); its runtime state is
		-- empty at ADDON_LOADED, the only caller. IN-01: an unclassified key is left in place (never
		-- deleted), but the runtime can no longer resolve it -- say so once, since v8 runs once per
		-- database.
		if dropRacial then
			ns.db.trackedBuffs[oldKey] = nil
			ns:ClearTrackerRuntimeState(oldKey)
			moved = true
		elseif newKey == nil then
			print("|cff00ccffTerribleBuffTracker|r: could not migrate tracker " .. tostring(oldKey) .. ".")
		end

		if newKey ~= nil then
			if newKey ~= oldKey then
				if ns.db.trackedBuffs[newKey] == nil then
					ns.db.trackedBuffs[oldKey] = nil
					ns.db.trackedBuffs[newKey] = entry
					-- Runtime-only slots follow the record to its new key. Empty at ADDON_LOADED,
					-- but a stale slot at oldKey must not linger under a key nothing reads anymore.
					ns:ReleaseProc(oldKey)
					ns:PreallocateProc(newKey)
					ns.activeTimers[oldKey] = nil
					ns.cooldownStarts[oldKey] = nil
					moved = true
				else
					-- T-49-08 precedent: drop rather than clobber. Unreachable for a real
					-- v0.4.1 database, since the mapping is injective.
					ns.db.trackedBuffs[oldKey] = nil
					entry = nil
				end
			end

			if entry then
				entry.key = newKey
				entry.trackerType = kind
				if
					id ~= nil
					and entry.spellID == nil
					and (kind == ns.KIND.USER_BUFF or kind == ns.KIND.USER_CD or kind == ns.KIND.META_SKILL)
				then
					entry.spellID = id
				end
				if id ~= nil and kind == ns.KIND.META_ITEM and entry.itemID == nil then
					entry.itemID = id
				end
			end
		end
	end

	ns.db.schemaVersion = 8
	ns:RebuildCastIndex()

	if moved then
		if ns.MarkTrackersDirty then
			ns:MarkTrackersDirty()
		end
		if ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
	end
end

-- Schema v9 (ADD-07, Phase 57.1): drops the saved `detailed` mode flag. The dialog (plan 02) no
-- longer writes it -- every runtime gate now keys on the Advanced value itself (a saved auraID,
-- keepOnAuraLoss, visibility or endOnCast is in effect on its own), so a lingering `detailed`
-- flag is read nowhere. For a record whose `detailed` was not exactly true, the four Advanced
-- keys are cleared: they were switched off under the old mode flag, and clearing them keeps that
-- record's current behaviour unchanged now that the values themselves are what gates it. A
-- record with `detailed = true` keeps its values untouched. `detailed` itself is then cleared
-- unconditionally, since no runtime path reads it after this plan.
--
-- Spec: scripts/migrate-dryrun.js migrateV9, reconciled against this code in plan 57.1-01.
-- Runs only after schema v8 has completed -- reads ns.db.schemaVersion FRESH on every call (not a
-- `ver` captured earlier), matching ns:MigrateKindKeys' own design: called once from
-- ns:InitBuffEngine. Assigning fields of the entry tables during `pairs` is safe here -- no key of
-- ns.db.trackedBuffs is added or removed, only value tables are mutated in place.
--
-- Pinned to the LITERAL 9, not CURRENT_SCHEMA_VERSION (Phase 57.2): this is now an EARLIER block
-- in the chain, so by its own historical rule (see the v6/v7/v8 blocks above) it keeps a literal
-- rather than the constant -- bumping CURRENT_SCHEMA_VERSION to 10 must never let a completed v9
-- database re-run this block, or skip straight to 10 without schema v10
-- (ns:MigrateBuffReminders, below) actually running. v10 is now the block that writes the
-- constant; v10 runs after this one.
function ns:MigrateDropDetailedFlag()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	local ver = ns.db.schemaVersion or 0
	if ver >= 9 then
		return
	end
	if ver < 8 then
		-- Kept as a chain-order guard: the chain runs in order from ns:InitBuffEngine.
		return
	end

	for _, entry in pairs(ns.db.trackedBuffs) do
		if type(entry) == "table" then
			if entry.detailed ~= true then
				entry.auraID = nil
				entry.keepOnAuraLoss = nil
				entry.visibility = nil
				entry.endOnCast = nil
			end
			entry.detailed = nil
		end
	end

	ns.db.schemaVersion = 9
	ns:RebuildCastIndex()
end

-- Schema v10 (REM-04, Phase 57.2): buff reminders become their own kind. A userBuff saved with
-- visibility "absent" (Phase 57's "show only while the aura is missing") becomes a userReminder:
-- the SAME entry table moves to userReminder:<id>, keeps its buff fields (spellID, duration,
-- auraID, coverAllRanks, keepOnAuraLoss, endOnCast, label and layoutOrder: a reminder is a buff
-- tracker in its own category, user decision 2026-09-29), drops only visibility, and moves to the
-- "reminders" base container unless it sat in "hidden".
-- Every other entry loses `visibility` (the option is gone from buffs and cooldowns), and a
-- userCd also loses `auraID`: once plan 02 removes the visibility watch nothing reads a
-- cooldown's aura ID, it fed only that watch.
--
-- When userReminder:<id> already exists, the existing record wins and the migrant is dropped
-- (57.2-CONTEXT): the user already made that reminder deliberately, and a duplicate would be
-- refused by the add path anyway.
--
-- Spec: scripts/migrate-dryrun.js migrateV10 (selftest case I), reconciled against this code in
-- plan 57.2-01 and again in 57.2-05 (kept fields). Like v7-v9: reads
-- ns.db.schemaVersion FRESH on every call, runs only after v9 has completed, and is called once
-- from ns:InitBuffEngine. Migrants are
-- collected before re-keying: adding or removing keys of the table being walked by `pairs` is
-- undefined in Lua.
--
-- Pinned to the LITERAL 10, not CURRENT_SCHEMA_VERSION (Phase 57.5): this is now an EARLIER block
-- in the chain, so by its own historical rule (see the v6-v9 blocks above) it keeps a literal
-- rather than the constant -- bumping CURRENT_SCHEMA_VERSION to 11 must never let a completed v10
-- database re-run this block, or skip straight to 11 without schema v11
-- (ns:MigrateReminderAlternatives, below) actually running. v11 is now the block that writes the
-- constant; v11 runs after this one.
function ns:MigrateBuffReminders()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	local ver = ns.db.schemaVersion or 0
	if ver >= 10 then
		return
	end
	if ver < 9 then
		-- Kept as a chain-order guard: the chain runs in order from ns:InitBuffEngine.
		return
	end

	local tracked = ns.db.trackedBuffs
	local migrants = {}
	for key, entry in pairs(tracked) do
		if type(entry) == "table" then
			if entry.trackerType == ns.KIND.USER_BUFF and entry.visibility == "absent" then
				migrants[#migrants + 1] = key
			else
				entry.visibility = nil
				if entry.trackerType == ns.KIND.USER_CD then
					entry.auraID = nil
				end
			end
		end
	end

	local moved = false
	for _, oldKey in ipairs(migrants) do
		local entry = tracked[oldKey]
		local id = entry.spellID
		if type(id) ~= "number" then
			id = ns:KeyNumericID(oldKey, ns.KIND.USER_BUFF)
		end
		if id == nil then
			-- No spell ID to key a reminder on: it stays a buff, only the option is dropped.
			entry.visibility = nil
		else
			local newKey = ns:TrackerKey(ns.KIND.USER_REMINDER, id)
			ns:ClearTrackerRuntimeState(oldKey)
			tracked[oldKey] = nil
			if tracked[newKey] == nil then
				entry.visibility = nil
				entry.trackerType = ns.KIND.USER_REMINDER
				entry.key = newKey
				entry.spellID = id
				if entry.section ~= "hidden" then
					entry.section = "reminders"
				end
				tracked[newKey] = entry
			end
			moved = true
		end
	end

	ns.db.schemaVersion = 10
	ns:RebuildCastIndex()

	if moved then
		if ns.MarkTrackersDirty then
			ns:MarkTrackersDirty()
		end
		if ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
	end
end

-- v11's one filter (57.5 review IN-02): writes id at list[count + 1] and returns the new count
-- when id is a positive number not already in list[1..count]; otherwise returns count unchanged.
-- Declared above its only caller, ns:MigrateReminderAlternatives.
local function AppendAlternativeID(list, count, id)
	if type(id) ~= "number" or id <= 0 then
		return count
	end
	for j = 1, count do
		if list[j] == id then
			return count
		end
	end
	list[count + 1] = id
	return count + 1
end

-- Schema v11 (RALT-02, Phase 57.5): for reminders only (every kind in ns.REMINDER_KINDS, user and
-- built-in), "Ends when you cast" becomes "Also satisfied by" (RALT-01): a reminder is satisfied
-- by its own buff or any listed alternative. This is the one deliberate divergence from
-- "reminders are buffs", user decision 2026-09-29. For every reminder entry with an endOnCast:
-- - a table's valid IDs (57.5 review IN-02: its ipairs sequence, positive numbers only, first
--   occurrence only) become `alternatives` as the SAME table, reduced to exactly those IDs, when
--   there is no alternatives list;
-- - when there already is one (only possible by hand-editing), each valid ID not already in it is
--   appended after its ipairs border;
-- - a table with no valid ID (empty, hash-only, junk) or a non-table value is dropped.
-- endOnCast is then cleared. Buff and cooldown trackers keep endOnCast untouched. The JS mirror
-- applies the same filter to the same (malformed, hand-edited) tables.
--
-- Spec: scripts/migrate-dryrun.js migrateV11 (selftest cases K, with its malformed sub-case, and
-- L), reconciled against this code in plan 57.5-01. Like v7-v10: reads ns.db.schemaVersion FRESH on
-- every call, runs only after v10 has completed, and is called once from ns:InitBuffEngine. Only
-- field values of the entry tables change during `pairs`; no key of ns.db.trackedBuffs is added or
-- removed. No redraw: no key moves and no section changes.
--
-- Pinned to the LITERAL 11 (Phase 67): this is now an EARLIER block in the chain, so by its own
-- historical rule (see the v6-v10 blocks above) it keeps a literal rather than the constant --
-- bumping CURRENT_SCHEMA_VERSION to 12 must never let a completed v11 database re-run this block,
-- or skip straight to 12 without schema v12 (ns:MigrateDropRacials, below) actually running. v12 is
-- now the block that writes the constant; v12 runs after this one.
function ns:MigrateReminderAlternatives()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	local ver = ns.db.schemaVersion or 0
	if ver >= 11 then
		return
	end
	if ver < 10 then
		-- Kept as a chain-order guard: the chain runs in order from ns:InitBuffEngine.
		return
	end

	for _, entry in pairs(ns.db.trackedBuffs) do
		if type(entry) == "table" and ns.REMINDER_KINDS[entry.trackerType] and entry.endOnCast ~= nil then
			local rule = entry.endOnCast
			entry.endOnCast = nil
			if type(rule) == "table" then
				if type(entry.alternatives) ~= "table" then
					-- Move: compact the valid IDs to the front of the rule's own table (a write never
					-- passes the read), then drop every other key, so the SAME table is exactly the
					-- filtered list. No valid ID: dropped.
					local count = 0
					local i = 1
					while rule[i] ~= nil do
						count = AppendAlternativeID(rule, count, rule[i])
						i = i + 1
					end
					for k in pairs(rule) do
						if not (type(k) == "number" and k >= 1 and k <= count and k % 1 == 0) then
							rule[k] = nil
						end
					end
					if count > 0 then
						entry.alternatives = rule
					end
				else
					-- Merge: append after the existing list's ipairs border.
					local list = entry.alternatives
					local count = 0
					while list[count + 1] ~= nil do
						count = count + 1
					end
					local i = 1
					while rule[i] ~= nil do
						count = AppendAlternativeID(list, count, rule[i])
						i = i + 1
					end
				end
			end
		end
	end

	ns.db.schemaVersion = 11
	ns:RebuildCastIndex()
end

-- Schema v12 (MIG-03, Phase 67): removes every saved racial tracker. Racial trackers are identified
-- by key shape only, never by a catalogue: `metaSkill:<digits>` racial buffs, `metaSkillCd:<digits>`
-- racial cooldowns, and the legacy `racial`/`racial2` slots. `metaSkill:lust` has no numeric id and
-- is kept. Silent (user decision): no chat message. Every other tracker keeps its section,
-- layoutOrder and fields.
--
-- Spec: scripts/migrate-dryrun.js migrateV12 (selftest cases D and M). Reads ns.db.schemaVersion
-- FRESH on every call, runs only after v11 has completed, and is called once from
-- ns:InitBuffEngine. Matching keys are collected before deleting: removing keys of the table being
-- walked by `pairs` is undefined in Lua. The patterns are function-local frozen literals (not
-- ns.KIND), since the metaSkillCd kind is deleted from the addon.
function ns:MigrateDropRacials()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	local ver = ns.db.schemaVersion or 0
	if ver >= CURRENT_SCHEMA_VERSION then
		return
	end
	if ver < 11 then
		-- Kept as a chain-order guard: the chain runs in order from ns:InitBuffEngine.
		return
	end

	local BUFF_PATTERN = "^metaSkill:%d+$"
	local COOLDOWN_PATTERN = "^metaSkillCd:%d+$"

	local drop = {}
	for key in pairs(ns.db.trackedBuffs) do
		if
			type(key) == "string"
			and (key:match(BUFF_PATTERN) or key:match(COOLDOWN_PATTERN) or key == "racial" or key == "racial2")
		then
			drop[#drop + 1] = key
		end
	end

	for _, key in ipairs(drop) do
		ns.db.trackedBuffs[key] = nil
		ns:ClearTrackerRuntimeState(key)
	end

	ns.db.schemaVersion = CURRENT_SCHEMA_VERSION
	ns:RebuildCastIndex()

	if #drop > 0 then
		if ns.MarkTrackersDirty then
			ns:MarkTrackersDirty()
		end
		if ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
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

-- Hands back the slot's proc table, wiped. The wipe is load-bearing rather than hygiene: a field
-- one provider set on a proc would otherwise leak into the next cast's proc for the same slot.
-- Keys never cross providers -- "metaSkill:lust", "metaItem:trinket", "metaItem:pot",
-- "userBuff:<id>", "userReminder:<id>" and "metaReminder:<id>" are all disjoint -- so this guards
-- against future edits, not present ones.
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

-- Phase 56 runtime gates, value-keyed (Phase 57.1, ADD-07: no `detailed` mode flag anywhere).
-- The dialog stores a default as nil (Phase 57.1 "Prefilled defaults, no mode flag"), so a saved
-- key IS the non-default value and is always in effect -- there is no flag left to guard it with.
-- keepOnAuraLoss is stored only when the user opted out, so a missing key still means
-- "cancellation on" (D-04); a stale auraID / keepOnAuraLoss on a tracker that never opted into
-- Advanced settings was cleared by schema v9 (ns:MigrateDropDetailedFlag). Both are
-- allocation-free, make no API call, and are safe to call from the cast path.

-- Returns entry.auraID only when it is a number > 0; nil otherwise. Never returns entry.spellID
-- -- callers decide the fallback (Phase 57 writes ns:DetailedAuraID(entry) or entry.spellID).
function ns:DetailedAuraID(entry)
	if type(entry.auraID) == "number" and entry.auraID > 0 then
		return entry.auraID
	end
	return nil
end

-- Returns false only when entry.keepOnAuraLoss is true; true otherwise (missing key =
-- cancellation ON).
function ns:CancelsOnAuraLoss(entry)
	if entry.keepOnAuraLoss then
		return false
	end
	return true
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
	--
	-- Phase 57.2-05: ns.reminderAuraID holds exactly the reminder keys that can own a timer (a
	-- reminder with a numeric spellID, the only kind the cast index maps). A reminder's timer is
	-- engine-internal while the buff is comfortably up: it stays out of the returned list, so no
	-- container draws it. It joins the list only when its reminder is actually drawn with the buff
	-- still up -- inside the lead window (ns:ReminderInLead), or while the settings or Edit Mode
	-- show every reminder -- so that icon carries the buff's real remaining time as its sweep and
	-- countdown rather than a bare placeholder. Its lazy expiry is evidence the aura ended (Phase 57 WR-03), so the
	-- reminder is marked absent and shows on this same tick, mid-combat included. Cost: one hash
	-- lookup per live timer, no allocation.
	-- 57.5 review WR-01: the expiry is only evidence, so it also queues the post-cast aura re-check
	-- (one flag, one coalesced C_Timer, no allocation): when a readable read still finds the set
	-- present (an alternative outlasting the timer), the reminder hides again.
	for key, proc in pairs(ns.activeTimers) do
		if proc.expiresAt <= now then
			ns.activeTimers[key] = nil
			if ns.reminderAuraID[key] then
				ns.auraState[key] = false
				ns:QueueCastAuraRecheck()
			end
		elseif
			ns.reminderAuraID[key] == nil
			or (proc.section ~= "hidden" and (ns.configOpen or ns.editModeActive or ns:ReminderInLead(proc, now)))
		then
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

-- Readable word for chat -- "buff" for a userBuff tracker, "cooldown" for every other kind
-- (userCd). 53-CONTEXT discretion: a tracker reads as a "cooldown" to the player, never the
-- internal kind string. Phase 57.2: "reminder" for any kind
-- in ns.REMINDER_KINDS.
function ns:TrackerKindWord(kind)
	if ns.REMINDER_KINDS[kind] then
		return "reminder"
	end
	if kind == ns.KIND.USER_BUFF then
		return "buff"
	end
	return "cooldown"
end

-- The display label for a spell with no player-typed label -- the game's resolved spell name when
-- resolvable, else a "Spell <id>" placeholder. Shared by ns:AddTrackedBuff (no label typed) and
-- ns:UpdateTrackedBuff (an ID change always re-derives the label; no label field exists to edit).
-- Secret-safe (WR-01): info.name is tested with issecretvalue() before any boolean test, type
-- check or comparison, the same guard Core.lua's ResolveRankFamily applies to the same field, so
-- this can never throw and always returns a plain string the caller may concatenate.
function ns:SpellLabel(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	local name = info and info.name
	if not issecretvalue(name) and type(name) == "string" and name ~= "" then
		return name
	end
	return "Spell " .. tostring(spellID)
end

-- True only for a userBuff, userCd or userReminder tracker -- the user-made kinds the edit dialog
-- can open (Phase 54; userReminder since Phase 57.2, so right-click Edit works on a reminder
-- tile). Every built-in kind gets no Edit entry: its data comes from a built-in table or the
-- item, not from the player (54-CONTEXT "Entry point"). Names
-- USER_REMINDER directly rather than ns.REMINDER_KINDS on purpose: the built-in
-- ns.KIND.META_REMINDER (Phase 57.4) is a reminder but is not editable -- its data comes from the
-- class-buff table. Read off the entry's own kind field, never inferred from the key's shape.
-- Nil-safe.
function ns:IsEditableTracker(entry)
	if entry == nil then
		return false
	end
	local kind = entry.trackerType
	return kind == ns.KIND.USER_BUFF or kind == ns.KIND.USER_CD or kind == ns.KIND.USER_REMINDER
end

-- The key of an existing tracker already occupying spellID's slot within kind's namespace, or
-- nil. This is the dialog-path rule (Add and Update both refuse a same-slot duplicate). A
-- built-in tracker never blocks a user one (user decision 2026-09-29): a userCd conflicts only
-- with another userCd, and a userBuff/reminder never with Lust -- each lives in its own
-- namespace.
--
-- exceptKey lets an unchanged ID never conflict with itself.
function ns:FindTrackerConflict(kind, spellID, exceptKey)
	if not ns.db or not ns.db.trackedBuffs then
		return nil
	end
	if type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end
	if exceptKey and ns:TrackerKey(kind, spellID) == exceptKey then
		return nil
	end

	local function checkCandidate(candidateKey)
		if candidateKey and candidateKey ~= exceptKey and ns.db.trackedBuffs[candidateKey] then
			return candidateKey
		end
		return nil
	end

	-- Phase 57.2 (REM-02): a reminder's namespace is its own kind. A buff and a reminder for the
	-- same spell never conflict; a second reminder for it does. Since 57.2-05 a reminder has its
	-- own cast index (ns.reminderKeyBySpell), consulted exactly like the buff side's, so this block
	-- reads only user reminders: a user tracker never conflicts with a built-in metaReminder.
	-- A metaReminder (Phase 57.4) never reaches this function: AddTrackedBuff, UpdateTrackedBuff and
	-- the add/edit dialog handle user kinds only. Its duplicate guard is AddSuggestedTracker's
	-- (CDMTab.lua) canonical-key check, which moves the existing metaReminder instead of creating a
	-- second (Phase 58 removed the unreachable metaReminder branch here, 57.4 review IN-01).
	if ns.REMINDER_KINDS[kind] then
		return checkCandidate(ns.reminderKeyBySpell and ns.reminderKeyBySpell[spellID])
			or checkCandidate(ns:TrackerKey(kind, spellID))
	end

	if kind == ns.KIND.USER_BUFF then
		return checkCandidate(ns.buffKeyBySpell and ns.buffKeyBySpell[spellID])
			or checkCandidate(ns:TrackerKey(ns.KIND.USER_BUFF, spellID))
	end

	return checkCandidate(ns.cooldownKeyBySpell and ns.cooldownKeyBySpell[spellID])
		or checkCandidate(ns:TrackerKey(ns.KIND.USER_CD, spellID))
end

-- The single list of runtime state keyed by a tracker key -- everything ns:RemoveTrackedBuff
-- clears, and everything an ID-changing ns:UpdateTrackedBuff must clear for the OLD key before
-- moving the entry. Clearing ns.cooldownStarts here (which
-- ns:RemoveTrackedBuff missed before this phase) is the found-bug fix: a removed-then-re-added
-- cooldown no longer inherits a running cooldown.
function ns:ClearTrackerRuntimeState(key)
	ns:EndTrackerRuntime(key)
	ns:ReleaseProc(key)
end

-- Phase 57.3 (LOAD-03): the non-pool half of ns:ClearTrackerRuntimeState -- every running timer,
-- preview, cooldown and aura state a key has, without releasing its proc. Core.lua's
-- ns:RebuildTrackerLoad calls this for a tracker that stops being loaded: the tracker still
-- exists, so it keeps its pool, and a later reload allocates nothing on its first cast.
function ns:EndTrackerRuntime(key)
	ns.activeTimers[key] = nil
	ns.previewTimers[key] = nil
	ns.cooldownStarts[key] = nil
	-- Phase 57 DTRK-03: the cached aura state is runtime too, and must not outlive the tracker
	-- (a removed key, or one whose ID changed under an edit) any more than the timers above do.
	ns.auraState[key] = nil
	if ns.MarkCooldownsDirty then
		ns:MarkCooldownsDirty()
	end
end

-- fields/fieldKeys contract (EDIT-02/EDIT-03, consumed by the Phase 54 shared field definition):
-- fields is a table keyed by saved-entry field name; fieldKeys is the array of the entry field
-- names the dialog actually READ this commit -- a field hidden by its visible() hook is not read,
-- is not in fieldKeys, and so keeps its saved value (WR-02). A key that IS in fieldKeys with a
-- nil value in fields is cleared. ENGINE_OWNED lists the names the engine itself writes and never
-- copies from fields -- ns:AddTrackedBuff's entry constructor and ns:UpdateTrackedBuff's
-- field-copy loop both skip these. A field added later to the dialog's shared definition is
-- therefore persisted by both functions with no edit here.
local ENGINE_OWNED = {
	spellID = true,
	duration = true,
	label = true,
	trackerType = true,
	section = true,
	layoutOrder = true,
	key = true,
	itemID = true,
	iconOverride = true,
}

-- opts (Plan 37-02, extended NAME-01/NAME-02 Phase 53, extended EDIT-02/EDIT-04 Phase 54; all
-- fields optional, three-argument callers remain valid):
--   opts.trackerType   ns.KIND.USER_CD mints a user cooldown tracker, whatever the spell is (a
--                        trinket's spell included): typed input is always a user
--                        kind, and only the Suggested tiles create built-in trackers (user
--                        decision 2026-09-29). A spell ID already tracked by the same user kind
--                        is REFUSED (a built-in tracker for it never is, 2026-09-29) and
--                        never reused (54-CONTEXT "Found bug, fixed in this phase": this used to
--                        silently overwrite the existing tracker's section/order).
--                        ns.KIND.USER_REMINDER (Phase 57.2) mints a buff reminder: a buff
--                        tracker in its own category (57.2-05, user decision 2026-09-29), so it
--                        requires and stores a duration like a buff, and it conflicts only with
--                        another reminder for the same spell. Anything else, including nil,
--                        mints ns.KIND.USER_BUFF.
--   opts.section        a container key -- written through as-is when it is a string;
--                        falls back to "hidden" otherwise (D-05, unchanged default).
--   opts.fields          the dialog's field values, keyed by entry field name (EDIT-02/EDIT-03).
--                        Every key not in ENGINE_OWNED is copied onto the new entry as-is --
--                        "cover all ranks" arrives this way now, stored as true or not at all by
--                        the field's own read, never false.
function ns:AddTrackedBuff(spellID, duration, label, opts)
	if not spellID or spellID <= 0 then
		print("|cff00ccffTerribleBuffTracker|r: Invalid spell ID.")
		return false, "Invalid spell ID"
	end

	local requestedType = opts and opts.trackerType
	local kind
	if requestedType == ns.KIND.USER_CD then
		kind = ns.KIND.USER_CD
	elseif requestedType == ns.KIND.USER_REMINDER then
		kind = ns.KIND.USER_REMINDER
	else
		kind = ns.KIND.USER_BUFF
	end
	if not duration or duration <= 0 then
		print("|cff00ccffTerribleBuffTracker|r: Invalid duration.")
		return false, "Invalid duration"
	end

	local displayLabel = label
	if not displayLabel or displayLabel == "" then
		displayLabel = ns:SpellLabel(spellID)
	end

	-- Assign next layoutOrder (max existing + 1)
	local maxOrder = 0
	for _, e in pairs(ns.db.trackedBuffs) do
		if e.layoutOrder and e.layoutOrder > maxOrder then
			maxOrder = e.layoutOrder
		end
	end

	-- D-05: new trackers still default to Not Displayed. The dialog's container choice is the
	-- only thing that overrides that default -- an unchosen container must never resolve to a
	-- visible one, so anything other than an explicit string section still falls to "hidden".
	local section = (opts and type(opts.section) == "string") and opts.section or "hidden"

	-- Canonical key (Core.lua's ns.KIND scheme), so a buff tracker and a cooldown tracker for the
	-- same spell are two records rather than one overwriting the other.
	local dbKey = ns:TrackerKey(kind, spellID)
	-- 54-CONTEXT: a spell ID already tracked in the same slot is refused, not reused -- the
	-- existing tracker is left completely untouched. A built-in tracker for the same spell is no
	-- conflict (ns:FindTrackerConflict, user decision 2026-09-29).
	local conflictKey = ns:FindTrackerConflict(kind, spellID)
	if conflictKey then
		print(
			"|cff00ccffTerribleBuffTracker|r: "
				.. displayLabel
				.. " is already tracked as a "
				.. ns:TrackerKindWord(kind)
				.. "."
		)
		return false, "Already tracked as a " .. ns:TrackerKindWord(kind)
	end

	local entry = {
		spellID = spellID,
		duration = duration,
		label = displayLabel,
		trackerType = kind,
		section = section,
		layoutOrder = maxOrder + 1,
	}
	-- EDIT-02/EDIT-03: every dialog field the engine does not own is copied onto the entry as-is.
	if opts and type(opts.fields) == "table" then
		for k, v in pairs(opts.fields) do
			if not ENGINE_OWNED[k] then
				entry[k] = v
			end
		end
	end
	ns.db.trackedBuffs[dbKey] = entry

	-- Pre-allocate the slot's proc buffers with the slot itself, so the first cast of this
	-- tracker allocates nothing either. This is the "allocate when the player adds a tracker"
	-- half of the pooling rule; ns:ReleaseProc in ns:RemoveTrackedBuff is the other half.
	ns:PreallocateProc(dbKey)

	print(
		"|cff00ccffTerribleBuffTracker|r: Now tracking |cff00ff00"
			.. displayLabel
			.. "|r ("
			.. ns:TrackerKindWord(kind)
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
	return true, dbKey
end

function ns:RemoveTrackedBuff(key)
	local entry = ns.db.trackedBuffs[key]
	if not entry then
		print(
			"|cff00ccffTerribleBuffTracker|r: "
				.. (ns:SpellKeySpellID(key) or ns:ItemKeyItemID(key) or tostring(key))
				.. " is not tracked."
		)
		return false
	end

	-- A meta entry (trinket/pot) or a pre-v1 user buff can carry no label; concatenating nil here
	-- would throw after the row is already gone and skip every rebuild below (IN-05).
	local label = entry.label or tostring(key)
	local id = entry.spellID or entry.itemID
	ns.db.trackedBuffs[key] = nil
	-- Clears activeTimers/previewTimers/cooldownStarts and the proc pools for
	-- key in one place (54-CONTEXT found bug: this used to skip cooldownStarts,
	-- so a removed-then-re-added cooldown tracker inherited a running cooldown).
	ns:ClearTrackerRuntimeState(key)

	-- A meta tracker (Lust/trinket/pot) has no spellID or itemID of its own -- its label alone
	-- identifies it, so the "(ID: ...)" suffix only appears when there is an id to show.
	if id then
		print("|cff00ccffTerribleBuffTracker|r: Stopped tracking |cffff6600" .. label .. "|r (ID: " .. id .. ").")
	else
		print("|cff00ccffTerribleBuffTracker|r: Stopped tracking |cffff6600" .. label .. "|r.")
	end

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

-- The one place the edit side-effect list lives (54-CONTEXT discretion: a dedicated function
-- over composing Add/Remove with their prints suppressed). Edits a userBuff/userCd tracker in
-- place when spellID is unchanged; moves the SAME entry table to <kind>:<newID> when it changes,
-- carrying section/layoutOrder with it and clearing every old-key runtime table. Returns
-- true, newKey on success or false, reason on refusal -- a refusal never writes anything.
-- A duration edit on an UNCHANGED ID applies to a buff from its NEXT cast: a proc already running
-- keeps the duration it was cast with, while a running cooldown picks the new length up at once
-- through ns:CooldownDuration (IN-02, accepted). Rescaling the live proc here was not done,
-- because Display.lua's icon sweep is cached on startedAt alone and would keep drawing the old
-- length, and closing that needs one more comparison on the per-frame render path.
-- NOTE: the dialog calls ns:RefreshTBTSections and ns:StartAllPreviewTimers itself after a
-- successful commit, exactly as it does after Add (CDMTab.lua is the UI layer) -- neither is
-- called from inside this function.
function ns:UpdateTrackedBuff(oldKey, spellID, duration, fields, fieldKeys)
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[oldKey]
	if not entry then
		return false, "This tracker no longer exists"
	end
	if not ns:IsEditableTracker(entry) then
		return false, "This tracker cannot be edited"
	end
	if type(spellID) ~= "number" or spellID <= 0 then
		return false, "Invalid spell ID"
	end
	-- Phase 57.2-05: a reminder requires a duration exactly like a buff (a reminder saved without
	-- one by an earlier v10 build must be given one here before it saves).
	if type(duration) ~= "number" or duration <= 0 then
		return false, "Invalid duration"
	end

	-- The tracker keeps its own kind -- an edited userCd stays userCd even for a trinket's spellID,
	-- so it stays editable (switching buff/cooldown is out of scope, 54-CONTEXT). Adding does the
	-- same since 2026-09-29: typed input is always a user kind.
	local kind = entry.trackerType
	local newKey = ns:TrackerKey(kind, spellID)

	local conflictKey = ns:FindTrackerConflict(kind, spellID, oldKey)
	if conflictKey then
		return false, "Already tracked as a " .. ns:TrackerKindWord(kind)
	end
	-- Defensive: never clobber an occupied newKey even if FindTrackerConflict's index is stale.
	if newKey ~= oldKey and ns.db.trackedBuffs[newKey] then
		return false, "Already tracked as a " .. ns:TrackerKindWord(kind)
	end

	-- Everything that can fail is resolved before the first write to saved data or runtime tables
	-- (WR-01): the kind, newKey and both conflict checks above, the label and chat ID text just
	-- below. Nothing after the `if moving` write block may call out to a game API or concatenate
	-- an unchecked value.
	--
	-- CR-01/WR-01: the label. An ID change re-derives it from the new spell (no label field
	-- exists to edit). An unchanged ID keeps the saved label, but a pre-v1 userBuff/userCd can
	-- carry none (ns:MigrateKindKeys never backfills one), so the chat line falls back to the
	-- spell's name rather than concatenating nil after the fields were already written.
	-- ns:SpellLabel is secret-safe and always returns a string.
	--
	-- idText is the chat line's ID fragment, "<old> -> <new>" on a move (IN-04: one print for
	-- both branches). tostring(entry.spellID) so a malformed legacy entry (no spellID) cannot
	-- throw; read here, before the move overwrites it.
	local moving = newKey ~= oldKey
	local shownLabel, idText
	if moving then
		shownLabel = ns:SpellLabel(spellID)
		idText = tostring(entry.spellID) .. " -> " .. tostring(spellID)
	else
		shownLabel = entry.label or ns:SpellLabel(spellID)
		idText = tostring(spellID)
	end

	if moving then
		-- Clear every old-key runtime table before the move, then move the SAME entry table
		-- (never rebuild one) so section/layoutOrder travel with it.
		ns:ClearTrackerRuntimeState(oldKey)
		ns.db.trackedBuffs[oldKey] = nil
		ns.db.trackedBuffs[newKey] = entry
		entry.spellID = spellID
		entry.key = newKey
		entry.label = shownLabel
		ns:PreallocateProc(newKey)
	end

	entry.duration = duration
	if type(fieldKeys) == "table" then
		for _, k in ipairs(fieldKeys) do
			if not ENGINE_OWNED[k] then
				-- nil clears the field -- an unticked "cover all ranks" is stored as nothing. Only
				-- keys that were read are listed, so a hidden field is never cleared (WR-02).
				entry[k] = fields and fields[k]
			end
		end
	end

	-- One chat line instead of a stop + start pair (54-CONTEXT). Every piece was resolved before
	-- the first write, so this cannot throw after the edit is committed.
	print(
		"|cff00ccffTerribleBuffTracker|r: Updated |cff00ff00"
			.. shownLabel
			.. "|r ("
			.. ns:TrackerKindWord(kind)
			.. ", ID: "
			.. idText
			.. ", "
			.. duration
			.. "s)."
	)

	-- Rebuilds, nil-guarded exactly as ns:AddTrackedBuff/ns:RemoveTrackedBuff already guard them
	-- (this file can in principle run before Core.lua's definitions are reachable).
	if ns.RebuildRankIndex then
		-- Rebuilds the cast index too, so the next cast of the new spell finds newKey and the
		-- old spell finds nothing.
		ns:RebuildRankIndex()
	end
	if ns.MarkTrackersDirty then
		ns:MarkTrackersDirty()
	end
	-- A duration change alters a running cooldown's render even when the key did not move.
	if ns.MarkCooldownsDirty then
		ns:MarkCooldownsDirty()
	end
	if ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
	return true, newKey
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

-- Phase 57 DTRK-05: the lifecycle side of a cross-spell rule. The cast path (Providers.lua
-- UserSpellProviderMixin:OnTrigger) reaches this only on an ns.endKeysBySpell index hit, and
-- passes endKeys unchanged -- the loop below is the only place that walks it.
--
-- Skip rule: never end the key this same cast is about to start. startingCdKey and
-- startingBuffKey are the keys this cast resolves to on the cooldown and buff sides; a key equal
-- to either is skipped, so a rule can never cancel the timer or cooldown its own cast is starting.
-- This costs nothing and cannot leave a half-reset cooldown. There is no startingReminderKey:
-- RALT-01 (Phase 57.5), a reminder never reaches here, because ns:RebuildDetailedRuleIndex indexes
-- no reminder's cast rule -- a reminder's list is its alternatives instead (the one deliberate
-- divergence from "reminders are buffs", user decision 2026-09-29).
--
-- Redraw rule: ns:UpdateDisplay() is called once when a buff timer was removed (a buff end must
-- show at once even when the cast returns no proc, since the dispatcher only redraws on a
-- proc), and ns:MarkCooldownsDirty() is called once when a cooldown was reset. A cast that both
-- ends one tracker and starts another redraws twice; that case is rare, and correctness beats
-- one redundant redraw.
function ns:ApplyEndOnCast(endKeys, startingCdKey, startingBuffKey)
	local tracked = ns.db and ns.db.trackedBuffs
	if not tracked then
		return
	end

	local endedBuff, endedCooldown = false, false
	for i = 1, #endKeys do
		local k = endKeys[i]
		if k ~= startingCdKey and k ~= startingBuffKey then
			local e = tracked[k]
			if e then
				if ns:IsBuffLikeEntry(e) then
					if ns.activeTimers[k] then
						ns.activeTimers[k] = nil
						endedBuff = true
					end
				elseif e.trackerType == ns.KIND.USER_CD then
					if ns.cooldownStarts[k] ~= nil then
						ns.cooldownStarts[k] = nil
						endedCooldown = true
					end
				end
			end
		end
	end

	if endedCooldown then
		ns:MarkCooldownsDirty()
	end
	if endedBuff and ns.UpdateDisplay then
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
		--
		-- Phase 57.3 (LOAD-03): a tracker that is not loaded (Load set to Never, or a When
		-- known spell this character does not know) never
		-- previews. One cached table read, ns:IsTrackerLoaded.
		--
		-- A reminder previews with its duration like a buff (user request, 2026-09-30): since the
		-- lead window a live reminder does draw its timer, so the preview shows what that looks
		-- like. One without a duration (Blood Pact) still previews as its placeholder, below.
		-- (This reverses 57.2-05's placeholder-only preview, written when a reminder's timer was
		-- never drawn.)
		if entry.section ~= "hidden" and ns:IsTrackerLoaded(key) then
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
				-- A reminder saved with no duration (Blood Pact) or an item tile reports no
				-- positive duration, and `now + nil` would raise. A tracker with no
				-- meaningful duration has no demo sweep to show, so it previews as the
				-- ordinary placeholder the render path already draws for an entry with no
				-- proc.
				if info and type(info.duration) == "number" and info.duration > 0 then
					ns.previewTimers[key] = {
						key = key,
						spellID = info.spellID, -- numeric (D-10); Display tooltip handler uses uniformly
						duration = info.duration,
						expiresAt = now + info.duration,
						startedAt = now,
						label = info.label,
						section = entry.section,
						layoutOrder = entry.layoutOrder,
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
	local now = GetTime()

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
			-- Phase 57.2-05 review WR-01: within ns.CAST_AURA_GRACE of the cast that started it, a
			-- readable absence is the aura not landed yet, not a loss -- the timer holds. Only a
			-- cast-started proc (ns:FillUserBuffProc) carries castAt.
			local inGrace = timer.castAt ~= nil and now - timer.castAt < ns.CAST_AURA_GRACE
			if allReadable and not anyPresent and not inGrace then
				ns.activeTimers[key] = nil
				-- Phase 57.2-05: a cancelled reminder timer means its aura is readably gone, so
				-- the reminder shows.
				if ns.reminderAuraID[key] then
					ns.auraState[key] = false
				end
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

-- Phase 57.2 (REM-03): the ONE reminder predicate Display calls (SlotDraws, the icon
-- placeholder condition, the bar placeholder filter, and container activity through
-- ns:ReminderShowsIn). nil = not a reminder (no gating); true = the buff is missing (a readable
-- read or a timer end found the aura gone) and no timer runs, so the reminder draws;
-- false = present, unknown or its timer running, so it hides. Phase 57.2-05: a running timer
-- means the buff is up, so the reminder hides while it runs -- except in its last stretch:
-- REMINDER_LEAD_FRACTION of the buff's duration, never less than REMINDER_LEAD_MIN seconds (user
-- request, 2026-09-30). Inside that window the gate is true while the timer still runs, so
-- Display draws the reminder through its live-timer branch: the buff's own remaining time, as
-- a sweep and countdown, on a clickable reminder. The timer's duration is the aura's real one
-- whenever ns:RefreshAuraStates could read it (57.2-05 sync), the typed one otherwise. An
-- duration-less timer has no end to lead, so it keeps the reminder hidden.
-- Allocation-free: no aura read, two hash lookups, one GetTime only while a timer runs.
local REMINDER_LEAD_FRACTION = 0.1
local REMINDER_LEAD_MIN = 1

-- True while a running reminder timer is inside its lead window. The one definition both
-- ns:ReminderGate (shows the reminder) and ns:GetActiveTimers (hands the timer to Display, so the
-- icon carries its sweep and countdown) ask, so the two cannot disagree.
function ns:ReminderInLead(timer, now)
	local duration = timer.duration
	if not duration or duration <= 0 then
		return false
	end
	local lead = duration * REMINDER_LEAD_FRACTION
	if lead < REMINDER_LEAD_MIN then
		lead = REMINDER_LEAD_MIN
	end
	return timer.expiresAt - now <= lead
end

function ns:ReminderGate(key, entry)
	if not entry or not ns:IsReminderEntry(entry) then
		return nil
	end
	local timer = ns.activeTimers[key]
	if timer == nil then
		return ns.auraState[key] == false
	end
	return ns:ReminderInLead(timer, GetTime())
end

-- Phase 57 DTRK-03: true when any reminder filed in that container must draw (a missing buff
-- must bypass hideWhenInactive). Allocation-free numeric loop.
function ns:ReminderShowsIn(containerKey)
	local keys = ns.reminderKeys
	local tracked = ns.db and ns.db.trackedBuffs
	if not tracked then
		return false
	end
	for i = 1, #keys do
		local key = keys[i]
		local entry = tracked[key]
		if entry and entry.section == containerKey and ns:ReminderGate(key, entry) == true then
			return true
		end
	end
	return false
end

-- Phase 57.2-05: an aura's real timing, or nil. Returns duration, expirationTime only when both
-- fields are readable (each passes issecretvalue BEFORE any type test or comparison), numbers,
-- duration > 0 and expirationTime > now. Inspects only a table ns:ReadPlayerAura already
-- returned: names no aura API, allocates nothing. A new name on purpose: the 57.2-02/04 gates
-- assert the old ReadableAuraTiming stays gone.
function ns:ReadableAuraExpiry(aura, now)
	if aura == nil then
		return nil
	end
	local duration, expirationTime = aura.duration, aura.expirationTime
	if issecretvalue(duration) or issecretvalue(expirationTime) then
		return nil
	end
	if type(duration) ~= "number" or type(expirationTime) ~= "number" then
		return nil
	end
	if duration <= 0 or expirationTime <= now then
		return nil
	end
	return duration, expirationTime
end

-- RALT-01 (Phase 57.5): reminders with alternatives overlap -- the five blessing reminders' watch
-- lists share the same IDs -- so ns:RefreshAuraStates reads each watched ID once per call through
-- this memo. [id] = the aura table or false, and [id] = readable (true/false). Wiped at the start
-- of every call, never rebuilt, and valid only within one call. Still ns:ReadPlayerAura
-- underneath, so an unreadable aura is never absent (DTRK-06).
local refreshAuraMemo = {}
local refreshReadableMemo = {}

local function ReadWatchedAura(id)
	local readable = refreshReadableMemo[id]
	if readable == nil then
		local aura
		aura, readable = ns:ReadPlayerAura(id)
		readable = readable and true or false
		refreshAuraMemo[id] = aura or false
		refreshReadableMemo[id] = readable
		return aura, readable
	end
	return refreshAuraMemo[id] or nil, readable
end

-- Phase 57.2 (REM-03), revised by 57.2-05 (user decision 2026-09-29: a reminder is a buff tracker
-- in its own category, so it can fire mid-combat when its buff runs out). The reminder state
-- refresh. Called from Core.lua at world entry, at combat end, when addon restrictions lift, after
-- every ns:RebuildRankIndex exit, and from ns:OnUnitAura below -- never per frame. Allocation-free:
-- no table constructor, no pairs()/ipairs() (numeric loops only); a started timer uses the pooled,
-- preallocated proc.
--
-- The 57.2 combat/unreadable clear is gone: nothing clears reminder states at combat start or on
-- a secret aura event. Rules, per reminder:
-- - Unreadable (secret auras, or any watched ID unreadable): present stays nil and the state
--   HOLDS (DTRK-06: unreadable is never absent). A readable read in combat updates the state
--   (Phase 57 review WR-03).
-- - Readable absent: exactly the buff rule. A running timer on a tracker that opted out of "End
--   when the aura is lost" keeps running and the state is left alone (the timer governs, and the
--   reminder shows when it ends) -- once a readable present read has confirmed the timer; an
--   unconfirmed cast-started one ends (57.5 review WR-03). Otherwise any running timer ends and
--   the state becomes false.
--   Within ns.CAST_AURA_GRACE of the cast that started the timer, readable absent counts as
--   unknown, as in the buff scan (the aura has not landed yet).
-- - Readable present: the state becomes true, and when the aura's expiry is readable
--   (ns:ReadableAuraExpiry) the reminder's timer follows it -- corrected when more than 0.5s off
--   (only ever extended on a tracker with "End when the aura is lost" off), or started when none
--   runs (buff from someone else, or up at login). The aura supplies the timing, so a reminder
--   with no saved duration (an earlier v10 build) gets a timer here too (57.2-05 review WR-05).
--   With several watched IDs present (a reminder with alternatives, or two ranks), the timer
--   follows the latest expiry among the present watched auras (RALT-01). When one of them has
--   no readable expiry, it outlasts them all and the timer is left alone (57.5 review WR-01).
--
-- suppressCancel (Phase 57.2-05 review WR-02): true from a full-update UNIT_AURA and from
-- PLAYER_ENTERING_WORLD, the moments ZONE-02 keeps the buff cancellation scan from running. A
-- readable absence then leaves a running timer and its state alone, exactly like a buff timer;
-- a reminder with no timer still takes the read.
function ns:RefreshAuraStates(suppressCancel)
	local keys = ns.reminderKeys
	if #keys == 0 then
		return
	end
	if C_Secrets.ShouldAurasBeSecret() then
		return
	end
	local tracked = ns.db and ns.db.trackedBuffs
	if not tracked then
		return
	end
	local now = GetTime()
	local changed = false
	wipe(refreshAuraMemo)
	wipe(refreshReadableMemo)
	for i = 1, #keys do
		local key = keys[i]
		local entry = tracked[key]
		if entry then
			local present, seenAura
			-- WR-04 "check both": a cover-all-ranks aura ID reminder watches the aura ID and every
			-- ID in its rank family, because a Forever rank's aura is its own ID.
			-- Phase 57 review WR-02: the list is prebuilt per key by ns:RebuildReminderWatch, so
			-- a cover-all-ranks reminder without an aura ID watches its whole family.
			local list = ns.reminderWatch[key]
			if list ~= nil then
				local allReadable = true
				-- RALT-01: every watched ID is read (through the per-call memo), not just up to the
				-- first present one: the present aura with the latest readable expiry is the one the
				-- timer follows.
				-- 57.5 review WR-01: a present aura with no readable expiry (permanent, or a secret
				-- expiry) outlasts every readable one, so no aura is followed at all: the state is
				-- still true, but no timer is started or synced from a shorter aura whose end would
				-- show the reminder while the open-ended one still satisfies it.
				local bestExpiry
				local openEnded = false
				for j = 1, #list do
					local aura, readable = ReadWatchedAura(list[j])
					if not readable then
						allReadable = false
					elseif aura then
						present = true
						local _, expirationTime = ns:ReadableAuraExpiry(aura, now)
						if expirationTime == nil then
							openEnded = true
						elseif bestExpiry == nil or expirationTime > bestExpiry then
							seenAura = aura
							bestExpiry = expirationTime
						end
					end
				end
				if openEnded then
					seenAura = nil
				end
				if present == nil and allReadable then
					present = false
				end
			else
				local aura, readable = ReadWatchedAura(ns.reminderAuraID[key])
				if readable and aura then
					present = true
					seenAura = aura
				elseif readable then
					present = false
				end
			end

			local proc = ns.activeTimers[key]
			-- Phase 57.2-05 review WR-01: the buff scan's cast grace. Within ns.CAST_AURA_GRACE of
			-- the cast that started the timer, a readable absence counts as unknown: the aura has
			-- not landed yet, so the timer and the state (true from the cast) both hold.
			if present == false and proc ~= nil and proc.castAt ~= nil and now - proc.castAt < ns.CAST_AURA_GRACE then
				present = nil
			end
			-- The buff rule: an opted-out tracker keeps its timer (and its state) on aura loss.
			-- WR-02: a suppressed call (full-update aura event, zone-in) ends no timer either.
			-- 57.5 review WR-03: the opt-out protects a buff a read confirmed, not a cast nothing
			-- confirmed. A cast-started timer keeps proc.castAt until the first readable present
			-- read (cleared below), so the first readable absence past the grace ends an unconfirmed
			-- one whatever the opt-out: a buff (or an alternative) cast on someone else. Reminders
			-- only; a buff tracker's opt-out is unchanged.
			local confirmed = proc ~= nil and proc.castAt == nil
			local optedOut = confirmed and not ns:CancelsOnAuraLoss(entry)
			local keepsTimer = present == false and proc ~= nil and (suppressCancel or optedOut)
			if present == false and proc ~= nil and not keepsTimer then
				ns.activeTimers[key] = nil
				proc = nil
				changed = true
			end

			local previous = ns.auraState[key]
			if not keepsTimer and present ~= nil and present ~= previous then
				ns.auraState[key] = present
				changed = true
			end

			if present == true then
				-- WR-03: a readable present read confirms a cast-started timer.
				if proc ~= nil then
					proc.castAt = nil
				end
				local duration, expirationTime = ns:ReadableAuraExpiry(seenAura, now)
				if duration then
					if proc ~= nil then
						-- 57.2-05 review WR-04: with "End when the aura is lost" off the typed
						-- timer governs, so the sync only ever extends it (a refresh by another
						-- player); shortening it to the aura's end is what that option turns off.
						local drift = expirationTime - proc.expiresAt
						local shortens = drift < -0.5 and ns:CancelsOnAuraLoss(entry)
						if drift > 0.5 or shortens then
							proc.expiresAt = expirationTime
							proc.duration = duration
							proc.startedAt = expirationTime - duration
							-- WR-03: a cast within ns.CAST_AURA_GRACE keeps this synced expiry.
							proc.syncedAt = now
							changed = true
						end
					elseif entry.section ~= "hidden" then
						-- WR-05: the aura supplies the timing, so no saved duration is needed.
						proc = ns:FillUserBuffProc(key, entry, now)
						-- A read-started timer is not a cast: no cast grace (WR-01).
						proc.castAt = nil
						proc.expiresAt = expirationTime
						proc.duration = duration
						proc.startedAt = expirationTime - duration
						proc.syncedAt = now
						ns.activeTimers[key] = proc
						changed = true
					end
				end
			end
		end
	end
	if changed and ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
end

-- Phase 57.4 review CR-01: the post-cast aura re-check. UNIT_SPELLCAST_SUCCEEDED carries no target,
-- so a cast that starts a buff-like timer (a buff, a user reminder, a metaReminder) is only
-- evidence the buff MAY be on the player: buffing another player hid the caster's own
-- missing-buff reminder until some unrelated UNIT_AURA, minutes away out of combat. One read just
-- past ns.CAST_AURA_GRACE settles it through the two existing paths, exactly like the
-- PLAYER_REGEN_ENABLED pair: a readable absence ends the timer and shows the reminder (an
-- opted-out buff tracker keeps its timer, as on any aura loss; an opted-out reminder only once a
-- read confirmed it, 57.5 review WR-03), a readable presence syncs a reminder's
-- expiry, and an unreadable read changes nothing (DTRK-06). Not a new aura reader.
--
-- One pending flag and one file-scope callback, never a closure per cast: a burst of casts
-- coalesces into one C_Timer. Each cast pushes the due time out, and a callback that fires early
-- re-arms itself for the rest, so the last cast's own grace has always passed when the read runs.
local castRecheckPending = false
local castRecheckDueAt = 0

local function RunCastAuraRecheck()
	local now = GetTime()
	if now < castRecheckDueAt then
		C_Timer.After(castRecheckDueAt - now, RunCastAuraRecheck)
		return
	end
	castRecheckPending = false
	if C_Secrets.ShouldAurasBeSecret() then
		return
	end
	ns:RefreshAuraStates()
	ns:ScanActiveTimersForCancellation()
end

-- Called by the cast side (Providers.lua) after a buff-like timer starts, and by a reminder
-- timer's lazy expiry in ns:GetActiveTimers (57.5 review WR-01). On ns, so declaration order can
-- never make it nil at the call site.
function ns:QueueCastAuraRecheck()
	local delay = ns.CAST_AURA_GRACE + 0.1
	castRecheckDueAt = GetTime() + delay
	if castRecheckPending then
		return
	end
	castRecheckPending = true
	C_Timer.After(delay, RunCastAuraRecheck)
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

	-- Phase 57.2 review WR-02: the reminder refresh runs BEFORE the full-update return below. It
	-- never reads the event payload -- every read is a live, readability-gated
	-- GetPlayerAuraBySpellID -- so a full-update batch makes its reads no less real, and skipping
	-- it left a buff gained or lost in such a batch (out-of-combat death, phasing, vehicle) on a
	-- stale reminder state. ZONE-02 only ever needed to suppress the cancellation scan. A secret
	-- event never reaches here; the secret branch above returns and every reminder state holds.
	--
	-- ZONE-02: a full update (zone boundary / loading screen transient) can read an aura as
	-- absent for a moment. isFullUpdate arrives secret while auras are restricted and a boolean
	-- test on a secret throws, so issecretvalue() gates the test; unknown counts as "not a full
	-- update" (the secret gate above has already returned in that case). Phase 57.2-05 review
	-- WR-02: read BEFORE the refresh and passed in, so a full update ends no reminder timer, the
	-- same as the buff scan it suppresses below.
	local isFullUpdate = updateInfo and updateInfo.isFullUpdate
	local fullUpdate = not issecretvalue(isFullUpdate) and isFullUpdate == true
	ns:RefreshAuraStates(fullUpdate)

	if fullUpdate then
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
