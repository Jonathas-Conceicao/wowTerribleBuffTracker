local _, ns = ...

-- Meta-key and prefix constants, hoisted to the very top of the file, before any function
-- definition: a file-local is only visible to functions declared AFTER it in the file (this
-- project's most-repeated bug), and every provider below mints or matches one of these. Core.lua
-- loads before this file per the TOC, so ns.META_KEY/ns.KEY_PREFIX/ns.KIND already exist here.
local LUST_KEY = ns.META_KEY.LUST
local TRINKET_KEY = ns.META_KEY.TRINKET
local POT_KEY = ns.META_KEY.POT
local META_SKILL_PREFIX = ns.KEY_PREFIX[ns.KIND.META_SKILL]
local META_ITEM_PREFIX = ns.KEY_PREFIX[ns.KIND.META_ITEM]

-- Registry of all SpellProviders in priority order. Populated at end of this file.
-- Phase 19 complete: { MetaItemTrinketProvider, MetaItemPotProvider, MetaSkillLustProvider, UserSpellProvider } — PROV-01 satisfied.
ns.providers = {}

-- Dispatch map: event name -> list of providers interested in that event.
-- Built once below after providers are registered. DO NOT rebuild per-event (PITFALL-7 performance trap).
local eventToProviders = {}

-- SpellProviderBaseMixin — defines the contract all providers must implement.
-- Concrete providers are built via CreateFromMixins(SpellProviderBaseMixin, ConcreteMixin).
-- Provider instances are constructed with CreateAndInitFromMixin(proto, ...) when Init is present.
local SpellProviderBaseMixin = {}

-- Returns a list of WoW event names this provider needs routed to it.
-- Override in concrete provider.
function SpellProviderBaseMixin:GetEventInterests()
	return {}
end

-- Called by BuffEngine dispatch when a registered event fires.
-- Returns an ActiveProc table if the event triggers a proc, or nil.
-- ActiveProc shape (Phase 22 normalized): { key, spellID (numeric), duration, expiresAt, startedAt, section, layoutOrder, label, aliveBuffs }
-- Override in concrete provider.
function SpellProviderBaseMixin:OnTrigger(event, ...)
	return nil
end

-- Returns display info for a provider key — unified contract for preview, at-rest, and runtime lookup.
-- Shape: { icon=number, label=string, duration=number, spellID=number }
-- spellID is ALWAYS numeric; for string-keyed providers, the provider resolves to its concrete
-- at-rest spellID (equipped trinket buff / bag pot buff / class-aware lust spell).
-- String-keyed providers (trinket/pot) return a neutral placeholder — spellID nil, duration 0,
-- icon 134400 — when nothing resolves at rest (D-03/D-04, Phase 27). Callers must therefore test
-- duration > 0 rather than assume a real duration.
-- Override in concrete provider. Default returns nil.
function SpellProviderBaseMixin:GetDisplayInfo(key)
	return nil
end

-- Refreshes the provider's at-rest cache (inventory scan, etc.). No-op by default.
-- D-17: Caller (ns:RefreshProvidersAtRest wrapper) combat-gates before calling. Defensive
-- guard at provider level is D-18 — inside concrete providers that touch restricted APIs.
-- D-19 / PITFALL-5: GetDisplayInfo MUST NOT call inventory APIs; only RefreshAtRest does.
function SpellProviderBaseMixin:RefreshAtRest() end

-- META-01 (Phase 27.1, D-09/D-12): answers whether this provider's catalog has anything to show
-- on the current client. Providers that carry no spell catalog are always displayable, so
-- UserSpellProvider and any future provider inherit "always shown" and only providers that
-- deliberately override can be hidden. This mechanism hides tiles whose catalog the *client*
-- cannot resolve; it names no client and no flavor, so a client that later ships those spells
-- makes the tile reappear automatically with no code change.
function SpellProviderBaseMixin:HasResolvableCatalog()
	return true
end

-- Expose on namespace so other providers (future) and tests can reference the base.
ns.SpellProviderBaseMixin = SpellProviderBaseMixin

-- UserSpellProviderMixin — kept its descriptive name rather than a kind-shaped one (53-CONTEXT
-- "Parsers and constants" leaves this to discretion) because it serves THREE kinds at once:
-- ns.KIND.USER_BUFF and ns.KIND.USER_CD (user-created trackers, keyed "userBuff:<id>" /
-- "userCd:<id>" in ns.db.trackedBuffs), and it also starts ns.KIND.META_SKILL_CD ("metaSkillCd:")
-- racial cooldown tiles -- a racial cooldown is an ordinary cooldown slot mechanically, just
-- a built-in kind with a fixed When known load (Phase 57.3: a racial is loaded when this character
-- knows it, resolved by ns:TrackerLoad like every tracker). The canonical
-- meta keys (ns.META_KEY.TRINKET, ns.META_KEY.POT, ns.META_KEY.LUST) are ignored -- the meta
-- providers further down this file own those, and have since Phases 18-19.
-- Phase 57.2: ns.KIND.USER_REMINDER ("userReminder:<id>") -- GetDisplayInfo serves its icon, name
-- and tooltip, and since 57.2-05 (user decision 2026-09-29: a reminder is a buff tracker in its own
-- category) OnTrigger starts its timer on a cast, resolved through its own namespace
-- (ns.reminderKeyBySpell, then ns.rankIndexReminder), so one cast can start a buff and a reminder.
-- Phase 57.4: ns.KIND.META_REMINDER ("metaReminder:<id>"), the built-in class-buff reminder, is
-- served the same way through its own namespace (ns.metaReminderKeyBySpell, then
-- ns.rankIndexMetaReminder), and starts through the same ns:StartReminderFromCast.
-- Phase 57.5 (RALT-01): a cast of a reminder's listed alternative ("Also satisfied by") starts
-- that reminder too, through ns.alternativeKeysBySpell and the same ns:StartReminderFromCast.
local UserSpellProviderMixin = {}

function UserSpellProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

-- Phase 57 DTRK-03: the user buff proc build, shared by every buff-like tracker so the aliveBuffs
-- decision (opt-out, aura ID, WR-04 rank family) lives in one place. Callers: OnTrigger's buff and
-- reminder sides (below) and ns:RefreshAuraStates' readable-expiry start of a reminder timer
-- (57.2-05). Pooled, allocation-free: the caller writes ns.activeTimers. The cast callers check
-- entry.duration is a positive number first; the read-started reminder timer may pass none and
-- sets duration/expiresAt itself (57.2-05 review WR-05).
function ns:FillUserBuffProc(ownerKey, entry, now)
	-- RANK-01: aliveBuffs becomes the shared family when one exists. This is a deliberate
	-- shared REFERENCE to Plan 01's ns.rankFamilies[ownerKey] array, not a copy -- safe
	-- because ns:ScanActiveTimersForCancellation only ever reads it with ipairs, and Plan 01
	-- allocates a fresh array per rebuild rather than reusing one, so a live proc's reference
	-- never goes stale. Must not be mutated or wiped here or anywhere downstream.
	local fams = ns.rankFamilies
	-- Phase 56: a detailed tracker's aura ID wins over the shared family, because ns.rankFamilies
	-- holds CAST IDs, not the aura -- same shape as StartRacialProc's def.auraID or def.spellID.
	-- WR-04: when the tracker also covers all ranks, the aura ID must not drop the family (a
	-- Forever rank's aura is its own ID), so ns.detailedRankFamilies -- the aura ID plus the
	-- family, prebuilt by ns:RebuildRankIndex and shared read-only like ns.rankFamilies -- wins.
	-- An opted-out tracker (ns:CancelsOnAuraLoss false) carries no aliveBuffs at all: the scan
	-- skips a proc with none, and ns:AcquireProc already wiped any stale value. Whatever list is
	-- chosen below is checked only by ns:ScanActiveTimersForCancellation through
	-- ns:ReadPlayerAura, so an unreadable aura never ends the tracker (DTRK-06).
	local aliveBuffs
	if ns:CancelsOnAuraLoss(entry) then
		-- RALT-01 (Phase 57.5): a reminder with alternatives stays alive while any of the set is
		-- present ("End when the aura is lost" applies to the whole set). A shared read-only
		-- reference, like ns.rankFamilies, replaced wholesale per rebuild. A buff key never has one.
		local satisfiedBy = ns.satisfiedByWatch[ownerKey]
		local auraID = ns:DetailedAuraID(entry)
		if satisfiedBy then
			aliveBuffs = satisfiedBy
		elseif auraID then
			local detailedFams = ns.detailedRankFamilies
			aliveBuffs = (detailedFams and detailedFams[ownerKey]) or ns:AcquireAliveBuffs(ownerKey, auraID)
		else
			-- The shared family when one exists, otherwise the slot's pooled one-element list.
			-- Both are read-only downstream; only the pooled one may be wiped, and only by
			-- ns:AcquireAliveBuffs.
			aliveBuffs = (fams and fams[ownerKey]) or ns:AcquireAliveBuffs(ownerKey, entry.spellID)
		end
	end

	-- Pooled, not constructed: a cast allocates nothing. See the proc pool in BuffEngine.lua.
	local proc = ns:AcquireProc(ownerKey)
	-- RANK-02: key stays the stable slot identity; spellID is THE spell this slot tracks, read
	-- straight off the entry rather than derived from the key (the key is a string "userBuff:<n>"
	-- now, not the spell ID itself) -- both come from ownerKey/entry, not the cast ID, so
	-- whichever rank the player casts, TBT files the timer under the same slot the CDM holds for
	-- that tracker.
	proc.key = ownerKey -- string slot key
	proc.spellID = entry.spellID -- numeric (D-03): THE spell
	proc.duration = entry.duration
	-- nil-tolerant (WR-05): ns:RefreshAuraStates starts a timer for a reminder with no saved
	-- duration and overwrites both fields at once with the aura's own timing.
	proc.expiresAt = now + (entry.duration or 0)
	proc.startedAt = now
	proc.section = entry.section or "bars"
	proc.layoutOrder = entry.layoutOrder
	proc.label = entry.label or ("Spell " .. tostring(entry.spellID))
	proc.aliveBuffs = aliveBuffs
	-- Phase 57.2-05 review WR-01: the cast time, for the ns.CAST_AURA_GRACE window. Not startedAt,
	-- which the reminder expiry sync rewrites. A read-started reminder timer clears it again, and
	-- so does a reminder's first readable present read (57.5 review WR-03: the timer is confirmed).
	proc.castAt = now
	return proc
end

-- Phase 58: the "direct ID first, then the rank family" rule every milestone cast namespace uses
-- (cooldowns, user reminders, metaReminders), so OnTrigger resolves each namespace with one call.
-- byID is the namespace's cast index, rankIdx its rank index. Returns key, entry for a tracked
-- owner, else nil, nil. Two table lookups on a miss; no table, closure or string. The buff side
-- keeps its own lookup (it predates the milestone). On ns, so declaration order cannot matter.
function ns:ResolveCastOwner(tracked, byID, rankIdx, spellID)
	local key = byID[spellID]
	local entry = key and tracked[key]
	if not entry then
		key = rankIdx and rankIdx[spellID]
		entry = key and tracked[key]
	end
	if entry then
		return key, entry
	end
	return nil, nil
end

-- The cooldown side of a cast for ONE cooldown namespace: byKey is the cast index
-- (ns.cooldownKeyBySpell or ns.metaCooldownKeyBySpell), rankIdx that namespace's rank index. The
-- direct hit wins, then the rank family (ns:ResolveCastOwner). Starts the cooldown unless the
-- tracker is hidden, and returns the resolved key (hidden or not) or nil. Two table lookups on a
-- miss, no allocation. On ns, not a file-local, so declaration order can never make it nil at the
-- call site.
function ns:StartCooldownFromCast(tracked, byKey, rankIdx, spellID)
	local cdKey, cdEntry = ns:ResolveCastOwner(tracked, byKey, rankIdx, spellID)
	if not cdEntry then
		return nil
	end
	if cdEntry.section ~= "hidden" then
		ns.cooldownStarts[cdKey] = GetTime()
		-- Written on EVERY start, override or nil -- see ns.cooldownOverrides (Core.lua). A cast
		-- under ordinary conditions must erase the previous cast's exception, so this assignment
		-- is unconditional and the lookup below answers nil for all but a handful of casts. The
		-- racial table's combat cooldown is a built-in tracker's data only: a user cooldown is
		-- just a spell and always runs on its typed duration (user decision 2026-09-29).
		if cdEntry.trackerType == ns.KIND.META_SKILL_CD then
			ns.cooldownOverrides[cdKey] = ns:ConditionalCooldown(spellID)
		else
			ns.cooldownOverrides[cdKey] = nil
		end
		ns:MarkCooldownsDirty()
	end
	return cdKey
end

-- --- the reminder start (Phase 57.2-05; shared since Phase 57.4) ------------------------------
--
-- A reminder is a buff tracker in its own category (user decision 2026-09-29): a cast starts
-- its timer, and the cast is evidence the buff is up, so the reminder hides at once, in combat
-- too. Its timer is engine-internal (ns:GetActiveTimers never hands it to Display) and its end
-- shows the reminder again. The dispatcher only redraws for the buff side's returned proc, so
-- this side redraws itself; a spell tracked as both redraws twice, accepted like
-- ns:ApplyEndOnCast's redraw.
--
-- One copy for both reminder kinds (MREM-01: a metaReminder behaves exactly like a user
-- reminder): OnTrigger calls it for the user reminder and for the built-in one, each resolved in
-- its own namespace. On ns, not a file-local, so declaration order can never make it nil.
--
-- 57.2-05 review WR-05: the cast is evidence the buff is up whatever the timer, so a reminder
-- saved with no duration (an earlier v10 build, or a metaReminder row with no timer such as
-- Blood Pact) still hides here; it only starts no timer.
--
-- Phase 57.5 (RALT-01): skipRedraw lets a caller that starts several reminders (the
-- alternatives side of OnTrigger) redraw once itself. Returns true when the reminder started,
-- nothing when the guard below refused it.
function ns:StartReminderFromCast(key, entry, skipRedraw)
	if not (entry and ns:IsReminderEntry(entry) and entry.section ~= "hidden") then
		return
	end
	local duration = entry.duration
	if type(duration) == "number" and duration > 0 then
		-- 57.2-05 review WR-03: an aura event just before this cast already synced the timer to
		-- the aura's real expiry (ns:RefreshAuraStates stamps proc.syncedAt); refilling it with
		-- the typed duration would undo that until the next readable aura event. Within
		-- ns.CAST_AURA_GRACE of a sync, the synced timer stands. A refill wipes syncedAt.
		local now = GetTime()
		local running = ns.activeTimers[key]
		local synced = running ~= nil and running.syncedAt ~= nil and now - running.syncedAt < ns.CAST_AURA_GRACE
		if not synced then
			ns.activeTimers[key] = ns:FillUserBuffProc(key, entry, now)
		end
	end
	ns.auraState[key] = true
	-- Phase 57.4 review CR-01: the cast names no target, so re-read the aura once the cast grace
	-- has passed (a class buff cast on someone else must bring the reminder back).
	if ns.QueueCastAuraRecheck then
		ns:QueueCastAuraRecheck()
	end
	if not skipRedraw and ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
	return true
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit (string), castGUID (string), spellID (number)
function UserSpellProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	-- ONE CAST, FIVE POSSIBLE TRACKERS. User cooldowns (ns.KIND.USER_CD), built-in racial cooldowns
	-- (ns.KIND.META_SKILL_CD), user reminders and built-in class-buff reminders
	-- (ns.KIND.META_REMINDER, Phase 57.4) each live in their own namespace, so the same spell can
	-- be tracked as a buff, a user reminder, a built-in reminder, a user cooldown AND a built-in
	-- cooldown, and a single cast has to start all of them. The cooldowns and the reminders are
	-- handled first, as side effects, and the buff decides the return value -- which keeps
	-- ns:DispatchEventToProviders' one-proc-per-provider contract intact. Phase 57.5 (RALT-01):
	-- the cast also starts every reminder that lists it as an alternative
	-- (ns.alternativeKeysBySpell), after both reminder namespaces resolved.
	--
	-- Resolving a tracker means: the cast index (ns.buffKeyBySpell / ns.cooldownKeyBySpell /
	-- ns.metaCooldownKeyBySpell / ns.reminderKeyBySpell / ns.metaReminderKeyBySpell), else the
	-- rank index for this namespace.
	-- RANK-01/RANK-02: the flat castSpellID -> ownerKey map never contains an ID that is itself a
	-- tracker slot, so the direct hit always wins and the fallback can never shadow a real tracker. Cost on a cast that matches nothing: two failed
	-- table lookups per namespace. No API call, no protected call, no allocation -- all of that
	-- happened at rebuild time.
	local tracked = ns.db and ns.db.trackedBuffs
	if not tracked then
		return nil
	end

	-- --- the cooldown side ---------------------------------------------------------------
	--
	-- A cooldown is a slot, not a timer: it never enters ns.activeTimers and therefore never
	-- reaches ns:ScanActiveTimersForCancellation, which has nothing to cancel for a cooldown.
	-- The cast is still not a timer, but it IS the start of one -- a custom cooldown tracker runs
	-- on the duration the user typed rather than the game's own cooldown, and this is the only
	-- place that start time exists. MarkCooldownsDirty also picks up a fresh charge count without
	-- waiting for SPELL_UPDATE_CHARGES.
	-- Two namespaces (user decision 2026-09-29): a user cooldown (ns.cooldownKeyBySpell) and a
	-- built-in racial cooldown (ns.metaCooldownKeyBySpell) for the same spell coexist, and one cast
	-- starts both. Only the user key feeds the cross-spell skip rule below: ns.endKeysBySpell never
	-- holds a built-in key, so a built-in can never be the key a rule would wrongly end.
	local cdKey = ns:StartCooldownFromCast(tracked, ns.cooldownKeyBySpell, ns.rankIndexCooldown, spellID)
	ns:StartCooldownFromCast(tracked, ns.metaCooldownKeyBySpell, ns.rankIndexMetaCooldown, spellID)

	-- --- reminder resolution (Phase 57.2-05) -----------------------------------------------
	--
	-- The reminder this cast resolves to, if any -- its own namespace, direct ID first, then the
	-- rank family (ns:ResolveCastOwner). Resolved here for the reminder side and the alternatives
	-- side below. No reminder is ever in the cross-spell index now (RALT-01, Phase 57.5: a
	-- reminder's list is its alternatives), so the skip rule needs no reminder key.
	local reminderKey, reminderEntry =
		ns:ResolveCastOwner(tracked, ns.reminderKeyBySpell, ns.rankIndexReminder, spellID)

	-- --- the cross-spell side (Phase 57 DTRK-05) -------------------------------------------
	--
	-- "aura A clears when skill B is cast" / "cooldown A resets when B is cast". Works in
	-- combat because UNIT_SPELLCAST_SUCCEEDED's spellID is always safe to use. The index is
	-- rank/override-expanded at rebuild time (ns:RebuildDetailedRuleIndex), so casting a rank or
	-- an override of B triggers the rule too. Placed before the buff side decides its return
	-- value, like the cooldown side above, so a cast that starts no buff still ends other
	-- trackers. One table lookup on a cast that matches nothing.
	local endKeys = ns.endKeysBySpell[spellID]
	if endKeys then
		-- Skip rule: the same two lookups the buff side makes below, so ns:ApplyEndOnCast never
		-- ends the key this same cast is about to (re)start.
		local startingBuffKey = ns.buffKeyBySpell[spellID]
		if startingBuffKey == nil and ns.rankIndex then
			startingBuffKey = ns.rankIndex[spellID]
		end
		ns:ApplyEndOnCast(endKeys, cdKey, startingBuffKey)
	end

	-- --- the reminder side (Phase 57.2-05) ---------------------------------------------------
	--
	-- The user reminder this cast resolved to above starts through the shared
	-- ns:StartReminderFromCast (its hidden-section and duration rules live there).
	if reminderEntry then
		ns:StartReminderFromCast(reminderKey, reminderEntry)
	end

	-- --- the built-in reminder side (Phase 57.4) ---------------------------------------------
	--
	-- A built-in reminder's own namespace (user rule 2026-09-29: a built-in and a user tracker for
	-- one spell never block each other, and one cast starts both): direct ID first, then the rank
	-- family, exactly like the user reminder resolution above. It never feeds the cross-spell skip
	-- rule, because ns.endKeysBySpell never holds a built-in key. Two more table lookups on a
	-- miss, no allocation.
	local metaReminderKey, metaReminderEntry =
		ns:ResolveCastOwner(tracked, ns.metaReminderKeyBySpell, ns.rankIndexMetaReminder, spellID)
	if metaReminderEntry then
		ns:StartReminderFromCast(metaReminderKey, metaReminderEntry)
	end

	-- --- the alternatives side (Phase 57.5, RALT-01) ------------------------------------------
	--
	-- Casting a listed alternative starts every reminder that lists it, with that reminder's own
	-- duration, hidden-section rule and post-cast re-check (ns:StartReminderFromCast). The keys
	-- this cast already started directly are skipped. One redraw for the lot. One table lookup on
	-- a miss, a numeric loop over a prebuilt array on a hit, no allocation.
	local altKeys = ns.alternativeKeysBySpell[spellID]
	if altKeys then
		local startedAny = false
		for i = 1, #altKeys do
			local altKey = altKeys[i]
			if
				altKey ~= reminderKey
				and altKey ~= metaReminderKey
				and ns:StartReminderFromCast(altKey, tracked[altKey], true)
			then
				startedAny = true
			end
		end
		if startedAny and ns.UpdateDisplay then
			ns:UpdateDisplay()
		end
	end

	-- --- the buff side -------------------------------------------------------------------
	local ownerKey = ns.buffKeyBySpell[spellID]
	local entry = ownerKey and tracked[ownerKey]
	if not entry then
		local idx = ns.rankIndex
		local mapped = idx and idx[spellID]
		if mapped ~= nil then
			ownerKey = mapped
			entry = tracked[mapped]
		end
	end
	if not entry then
		return nil
	end
	-- Carries over the section="hidden" guard from the branching cast handler BuffEngine used to
	-- have (its "branch 3"), which Phase 17 removed once this dispatcher took the work over.
	if entry.section == "hidden" then
		return nil
	end
	-- Defence in depth: a cooldown entry cannot reach here now that the namespaces are split --
	-- ownerKey comes from ns.buffKeyBySpell, which only ever indexes userBuff entries -- but a
	-- stale database from before the scheme migration could still carry a mismatched kind here,
	-- and it must not become a timer.
	if entry.trackerType ~= ns.KIND.USER_BUFF then
		return nil
	end

	-- Phase 57.4 review CR-01: the same post-grace re-read as the reminder side, so a buff cast
	-- on another player ends its timer once the aura reads absent.
	if ns.QueueCastAuraRecheck then
		ns:QueueCastAuraRecheck()
	end
	return ns:FillUserBuffProc(ownerKey, entry, GetTime())
end

-- key: a canonical "userBuff:<id>" or "userCd:<id>" string (also reached for "metaSkillCd:<id>"
-- racial cooldown tiles via the RacialCooldownSeed branch below, before any tracker exists, and
-- for "metaReminder:<id>" class-buff tiles via the ns:MetaReminderDef branch -- Phase 57.4).
-- Returns { icon, label, duration, spellID } or nil if the key names no spell at all.
-- D-04/D-05/D-06/D-07: spellID numeric, duration real, icon/label derived.
function UserSpellProviderMixin:GetDisplayInfo(key)
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
	-- A tracked entry's own spellID is authoritative and needs no parse. An untracked key (a
	-- Suggested tile, a drag ghost, or a racial cooldown tile with no tracker yet) falls back to
	-- parsing its own kind -- userBuff, userCd, metaSkill and metaSkillCd all resolve here.
	local spellID = (entry and type(entry.spellID) == "number" and entry.spellID) or ns:SpellKeySpellID(key)
	if not spellID then
		return nil
	end
	-- Pooled per key: this is on the render path for every placeholder slot. See
	-- ns:AcquireDisplayInfo in BuffEngine.lua for why sharing is safe here.
	local info = ns:AcquireDisplayInfo(key)
	if not entry then
		-- A racial's cooldown tile is offered in Suggested before any tracker exists, so it has
		-- to answer with the racial's real name and cooldown rather than the generic placeholder
		-- -- the entry created from this info inherits whatever duration it reports, and a 0
		-- would be baked in permanently.
		local racial = ns:RacialCooldownSeed(spellID)
		if racial then
			info.icon = ns:GetSpellIcon(spellID)
			info.label = racial.label
			info.duration = racial.cooldown
			info.spellID = spellID
			return info
		end
		-- Phase 57.4: a Suggested class-buff tile (an untracked metaReminder key) answers with the
		-- spell's real icon and name and the table's duration, so the tile tooltip reads right and
		-- the entry AddSuggestedTracker creates inherits a real label.
		local metaDef = ns:KeyNumericID(key, ns.KIND.META_REMINDER) and ns:MetaReminderDef(spellID)
		if metaDef then
			info.icon = ns:GetSpellIcon(spellID)
			info.label = ns:SpellLabel(spellID)
			info.duration = metaDef.duration or 0
			info.spellID = spellID
			return info
		end
		info.icon = 134400
		info.label = "Spell " .. tostring(spellID)
		info.duration = 0
		info.spellID = spellID
		return info
	end
	info.icon = ns:GetSpellIcon(spellID)
	info.label = entry.label or ("Spell " .. tostring(spellID))
	info.duration = entry.duration
	info.spellID = spellID
	return info
end

-- Expose for future extension and testing.
ns.UserSpellProviderMixin = UserSpellProviderMixin

-- Static lookup: spellID -> { duration, itemID } for tracked on-use trinkets (D-08).
local TRINKET_SPELLS = {
	-- Light Company Guidon
	[1259633] = { duration = 15, itemID = 249344 },
	-- Vaelgor's Final Stare
	[1260459] = { duration = 15, itemID = 249346 },
	-- Emberwing Feather
	[1250508] = { duration = 15, itemID = 250144 },
	-- Algeth'ar Puzzle Box
	[383781] = { duration = 20, itemID = 193701 },
	-- Echo of L'ura
	[250768] = { duration = 45, itemID = 151340 },
	-- Radiant Sunstone
	[1254624] = { duration = 20, itemID = 252411 },
	-- Freightrunner's Flask
	[1250533] = { duration = 15, itemID = 250215 },
	-- Seed of Radiant Hope
	[1263644] = { duration = 12, itemID = 250254 },
	-- Void Execution Mandate
	[1250557] = { duration = 20, itemID = 250225 },
}

-- Static lookup: spellID -> { duration, itemID } for tracked damage potions.
local POT_SPELLS = {
	-- Light's Potential
	[1236616] = { duration = 30, itemID = 241308 },
	-- Potion of Recklessness
	[1236994] = { duration = 30, itemID = 241288 },
	-- Draught of Rampant Abandon
	[1236998] = { duration = 30, itemID = 241292 },
	-- Void-Shrouded Tincture
	[1236551] = { duration = 12, itemID = 241302 },
}

-- Derived at module load: itemID -> true sets (D-11).
local TRINKET_ITEM_IDS = {}
for _, def in pairs(TRINKET_SPELLS) do
	TRINKET_ITEM_IDS[def.itemID] = true
end
local POT_ITEM_IDS = {}
for _, def in pairs(POT_SPELLS) do
	POT_ITEM_IDS[def.itemID] = true
end

-- Still the pot scan's real iteration order (Providers.lua MetaItemPotProviderMixin:RefreshAtRest below).
local POT_FALLBACK_ORDER = { 241308, 241288, 241292, 241302 }

-- Namespace exports for the data tables (consumed by tests and future provider extensions).
ns.TRINKET_SPELLS = TRINKET_SPELLS
ns.POT_SPELLS = POT_SPELLS
ns.TRINKET_ITEM_IDS = TRINKET_ITEM_IDS
ns.POT_ITEM_IDS = POT_ITEM_IDS

-- Reverse lookup: given an itemID, find the matching buff spellID in a spell table.
-- Used by MetaItemTrinketProvider:RefreshAtRest and MetaItemPotProvider:RefreshAtRest to resolve
-- equipped-item/bag-item -> buff-spell. Returns (spellID, duration) on match or (nil, nil) on miss.
local function FindSpellByItemID(spellTable, itemID)
	if not itemID then
		return nil, nil
	end
	for spellID, def in pairs(spellTable) do
		if def.itemID == itemID then
			return spellID, def.duration
		end
	end
	return nil, nil
end

-- META-01 (Phase 27.1, D-09): answers "does this client know any spell in this catalog?" for a
-- spellID-keyed table. Deliberately NOT an inventory or equipment test — the catalogs below
-- resolve via C_Spell.GetSpellInfo on retail even with nothing equipped or bagged, so this must
-- stay a pure client-capability check. A false result means the catalog is unusable on this
-- client, not that the player happens to own nothing.
local function AnyCatalogSpellResolves(catalog)
	for spellID in pairs(catalog) do
		if C_Spell.GetSpellInfo(spellID) then
			return true
		end
	end
	return false
end

-- Phase 27 / D-03/D-04: Shared neutral placeholder for string-keyed providers when nothing
-- resolves at rest. Returns a non-nil table so the `if info then` gates at CDMTab.lua:137 and
-- CDMTab.lua:518 still fire and both Suggested tiles stay draggable — a literal nil would make
-- them permanently un-addable. duration is 0, not nil, because BuffEngine.lua:283 computes
-- `expiresAt = now + info.duration` unconditionally inside its own `if info then`; a nil
-- duration would throw there. 0 is the codebase's existing unresolved-duration sentinel
-- (see the no-entry branch of the numeric-key provider's GetDisplayInfo above; CDMTab.lua:98's
-- duration > 0 check).
-- fallbackIcon (Phase 43.1) replaces the question mark where the caller has something more
-- useful to draw. It changes the PICTURE only: spellID stays nil and duration stays 0, so
-- "unresolved" still means unresolved everywhere that tests it, and D-05's rule against guessing
-- a spell from an unmatched item is untouched.
local function UnresolvedDisplayInfo(key, label, fallbackIcon)
	local info = ns:AcquireDisplayInfo(key)
	info.icon = fallbackIcon or 134400
	info.label = label
	info.duration = 0
	info.spellID = nil
	return info
end

-- Lust data tables. Consumed by MetaSkillLustProvider:OnTrigger (below) and ScanActiveTimersForCancellation
-- (via proc.aliveBuffs).

-- Maps Sated-family debuff spellID -> corresponding lust buff spellID.
ns.SATED_DEBUFF_TO_LUST = {
	[57724] = 2825, -- Sated -> Bloodlust
	[57723] = 32182, -- Exhaustion -> Heroism (covers Heroism + Drums)
	[80354] = 80353, -- Temporal Displacement -> Time Warp
	[390435] = 390386, -- Exhaustion (Evoker) -> Fury of the Aspects
	[264689] = 264667, -- Fatigued -> Primal Rage (Hunter pet)
}

-- D-12: Demoted from ns.* export to module-local. Only MetaSkillLustProvider reads it at OnTrigger time
-- to populate proc.aliveBuffs. BuffEngine no longer consumes it (cancellation reads proc.aliveBuffs
-- directly — no SHARED_LUST_BUFFS lookup from BuffEngine after Phase 22).
local SHARED_LUST_BUFFS_LOCAL = {
	[32182] = { 32182, 1243972 }, -- Heroism + Void-touched Drums share Exhaustion (57723)
	[2825] = { 2825 }, -- Bloodlust
	[264667] = { 264667, 466904 }, -- Primal Rage + Harrier's Cry (MM Hunter) share Fatigued
	[80353] = { 80353 }, -- Time Warp
	[390386] = { 390386 }, -- Fury of the Aspects
}

-- Provider-local class -> lust spellID map (D-18 Phase 23).
-- Previously ns.* exported for CDMTab's Suggested section; CDMTab migrated to
-- ns:GetDisplayInfoForKey(ns.META_KEY.LUST) in Phase 23 Plan 23-02 — no external readers remain.
local CLASS_LUST_SPELL = {
	SHAMAN = 2825, -- Bloodlust
	MAGE = 80353, -- Time Warp
	EVOKER = 390386, -- Fury of the Aspects
}

-- Hunter uses Primal Rage by default; MM Hunter (spec ID 254) uses Harrier's Cry.
local function GetHunterLustSpell()
	local specIndex = GetSpecialization()
	if specIndex then
		local specID = GetSpecializationInfo(specIndex)
		if specID == 254 then -- Marksmanship
			return 466904 -- Harrier's Cry
		end
	end
	return 264667 -- Primal Rage (BM/Survival)
end

-- MetaItemTrinketProviderMixin (Phase 18, D-05) — handles trinket on-use cast detection.
-- Keyed by the canonical meta key TRINKET_KEY (D-01); proc.aliveBuffs drives cancellation scan (Phase 22).
-- Does NOT read equipment or inventory APIs (PITFALL-5) — icons come from C_Spell.GetSpellInfo via ns:GetSpellIcon.
local MetaItemTrinketProviderMixin = {}

function MetaItemTrinketProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit, castGUID, spellID
function MetaItemTrinketProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	local trinketDef = TRINKET_SPELLS[spellID]
	if not trinketDef then
		return nil
	end

	local metaEntry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[TRINKET_KEY]
	if not metaEntry or metaEntry.section == "hidden" then
		return nil
	end

	local now = GetTime()
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local label = (spellInfo and spellInfo.name) or metaEntry.label or "Trinket"

	local proc = ns:AcquireProc(TRINKET_KEY)
	proc.key = TRINKET_KEY -- D-01 canonical meta key
	proc.spellID = spellID -- numeric cast spell (D-03)
	proc.duration = trinketDef.duration
	proc.expiresAt = now + trinketDef.duration
	proc.startedAt = now
	proc.section = metaEntry.section or "bars"
	proc.layoutOrder = metaEntry.layoutOrder
	proc.label = label
	proc.aliveBuffs = ns:AcquireAliveBuffs(TRINKET_KEY, spellID) -- D-05: cancel when the buff is absent
	return proc
end

-- D-13: Minimal at-rest cache — only { spellID, duration }. Icon/label DERIVED in GetDisplayInfo
-- via ns:GetSpellIcon + C_Spell.GetSpellInfo. Single source of truth: spellID is the key.
MetaItemTrinketProviderMixin.atRest = { spellID = nil, duration = nil }

-- D-14: Scans equipped INVSLOT_TRINKET1/2; reverse-looks up to buff spellID. Writes ONLY
-- { spellID, duration } to cache; leaves it honestly nil when no equipped trinket matches
-- TRINKET_ITEM_IDS (Phase 27 / D-05 — no unconditional hardcoded fallback assignment).
-- D-17/D-18: ns:RefreshProvidersAtRest wrapper combat-gates; defensive double-gate here for any
-- future caller that invokes RefreshAtRest directly.
-- PITFALL-5: inventory APIs here, NEVER in GetDisplayInfo.
function MetaItemTrinketProviderMixin:RefreshAtRest()
	if InCombatLockdown() then
		return
	end
	local trinketItemID
	-- Phase 43.1: the first equipped trinket, whether or not the catalog knows it, purely so the
	-- unresolved tile has something better than a question mark to draw. It is NOT a guess about
	-- which buff the trinket procs -- spellID and duration below are still left honestly nil when
	-- the catalog cannot answer, which is D-05's rule and stays intact. Showing the equipped
	-- item's icon for an item-backed tile is what the CDM does too (ItemUtil.GetEquipSlotTexture,
	-- used by GetSpellTexture for an equipSlot entry).
	local fallbackIcon
	for _, slot in ipairs({ INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) do
		local equipped = GetInventoryItemID("player", slot)
		if equipped and not fallbackIcon and GetInventoryItemTexture then
			local texture = GetInventoryItemTexture("player", slot)
			if not issecretvalue(texture) and texture then
				fallbackIcon = texture
			end
		end
		if equipped and TRINKET_ITEM_IDS[equipped] then
			trinketItemID = equipped
			break
		end
	end
	local spellID, duration = FindSpellByItemID(TRINKET_SPELLS, trinketItemID)
	self.atRest.spellID = spellID
	self.atRest.duration = duration
	self.atRest.fallbackIcon = fallbackIcon
end

-- D-04/D-05/D-06/D-07/D-16: Read cache; derive icon + label from spellID; return real duration.
-- Phase 27 / D-03/D-04: if the cache is unpopulated (no equipped trinket resolved), returns the
-- neutral placeholder below — never a CSV-order guess, and still never nil.
function MetaItemTrinketProviderMixin:GetDisplayInfo(key)
	local spellID = self.atRest.spellID
	local duration = self.atRest.duration
	if not spellID then
		-- The equipped trinket's own icon when there is one, resolved at rest -- never an
		-- inventory call from here (PITFALL-5). Falls back to the question mark when nothing is
		-- equipped at all, which is then the honest answer rather than a gap.
		return UnresolvedDisplayInfo(TRINKET_KEY, "Trinket", self.atRest.fallbackIcon)
	end
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local info = ns:AcquireDisplayInfo(TRINKET_KEY)
	info.icon = ns:GetSpellIcon(spellID)
	info.label = (spellInfo and spellInfo.name) or "Trinket"
	info.duration = duration
	info.spellID = spellID
	return info
end

-- META-01: trinket tiles stay visible whenever any spell in TRINKET_SPELLS resolves on this
-- client, regardless of whether a matching trinket is actually equipped (D-09).
function MetaItemTrinketProviderMixin:HasResolvableCatalog()
	return AnyCatalogSpellResolves(TRINKET_SPELLS)
end

local MetaItemTrinketProvider = CreateFromMixins(SpellProviderBaseMixin, MetaItemTrinketProviderMixin)

-- MetaItemPotProviderMixin (Phase 18, D-05) — handles damage pot cast detection.
-- Keyed by the canonical meta key POT_KEY (D-01); proc.aliveBuffs drives cancellation scan (Phase 22).
local MetaItemPotProviderMixin = {}

function MetaItemPotProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function MetaItemPotProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	local potDef = POT_SPELLS[spellID]
	if not potDef then
		return nil
	end

	local metaEntry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[POT_KEY]
	if not metaEntry or metaEntry.section == "hidden" then
		return nil
	end

	local now = GetTime()
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local label = (spellInfo and spellInfo.name) or metaEntry.label or "Damage Pot"

	local proc = ns:AcquireProc(POT_KEY)
	proc.key = POT_KEY
	proc.spellID = spellID -- numeric cast spell
	proc.duration = potDef.duration
	proc.expiresAt = now + potDef.duration
	proc.startedAt = now
	proc.section = metaEntry.section or "bars"
	proc.layoutOrder = metaEntry.layoutOrder
	proc.label = label
	proc.aliveBuffs = ns:AcquireAliveBuffs(POT_KEY, spellID) -- D-06
	return proc
end

-- D-13: Minimal at-rest cache.
MetaItemPotProviderMixin.atRest = { spellID = nil, duration = nil }

-- D-14: Scans bags via C_Item.GetItemCount in CSV order; first count>0 wins. Leaves the cache
-- honestly nil when no bagged potion matches (Phase 27 / D-05 — no unconditional hardcoded
-- fallback assignment).
-- D-17/D-18: combat-gated.
function MetaItemPotProviderMixin:RefreshAtRest()
	if InCombatLockdown() then
		return
	end
	local potItemID
	for _, itemID in ipairs(POT_FALLBACK_ORDER) do
		if (C_Item.GetItemCount(itemID) or 0) > 0 then
			potItemID = itemID
			break
		end
	end
	local spellID, duration = FindSpellByItemID(POT_SPELLS, potItemID)
	self.atRest.spellID = spellID
	self.atRest.duration = duration
end

-- D-04/D-05/D-06/D-07/D-16. Phase 27 / D-03/D-04: unpopulated cache returns the neutral
-- placeholder below — never a CSV-order guess, and still never nil.
function MetaItemPotProviderMixin:GetDisplayInfo(key)
	local spellID = self.atRest.spellID
	local duration = self.atRest.duration
	if not spellID then
		-- The CDM's own combat-potion icon rather than a question mark. A constant, not a scan:
		-- generic item cooldowns are identified by spell category and the CDM shows one fixed
		-- icon per category without naming the item, so this IS the right picture even when no
		-- specific potion has been resolved.
		return UnresolvedDisplayInfo(POT_KEY, "Damage Pot", ns.SPELL_CATEGORY_ICON[ns.SPELL_CATEGORY_COMBAT_POTION])
	end
	local spellInfo = C_Spell.GetSpellInfo(spellID)
	local info = ns:AcquireDisplayInfo(POT_KEY)
	info.icon = ns:GetSpellIcon(spellID)
	info.label = (spellInfo and spellInfo.name) or "Damage Pot"
	info.duration = duration
	info.spellID = spellID
	return info
end

-- META-01: pot tiles stay visible whenever any spell in POT_SPELLS resolves on this client,
-- regardless of whether a matching potion is actually bagged (D-09).
function MetaItemPotProviderMixin:HasResolvableCatalog()
	return AnyCatalogSpellResolves(POT_SPELLS)
end

local MetaItemPotProvider = CreateFromMixins(SpellProviderBaseMixin, MetaItemPotProviderMixin)

-- MetaSkillLustProviderMixin (Phase 19, D-01) — handles lust debuff detection via UNIT_AURA.
-- Independent concrete mixin extending SpellProviderBaseMixin; NOT shared with other providers.
-- Registered at position 3 in ns.providers (before UserSpellProvider) — satisfies PROV-01.
--
-- Gate handling (D-09/D-10/D-11):
--   * NO top-level C_Secrets.ShouldAurasBeSecret() check — Sated debuff spellIDs are Blizzard-allowlisted
--     as safe to read even when secrets are active. This is the original LUST-01 rationale.
--   * addedAuras is iterated ONLY when readable — the whole UNIT_AURA payload is secret while aura
--     restrictions are active, so OnTrigger falls back to reading the Sated debuffs by spell ID.
--   * Per-entry issecretvalue(aura.spellId) defensive check IS preserved on the readable path —
--     required in case the individual aura spellId itself is a secret-value opaque handle.
--   * No preview gate at all — providers run normally while preview is up. In v0.2.3 the caller
--     guarded StartLustTimer behind a global preview flag; no such flag exists any more. Phase 21
--     (LIFE-03) made preview ADDITIVE instead: ns:StartAllPreviewTimers writes to its own
--     ns.previewTimers table and skips any key a real proc already owns, so a provider firing
--     during preview needs no gate to win — it simply wins.
--
-- No-restart guard (D-12): provider-internal. If ns.activeTimers[LUST_KEY] exists and has not expired,
-- return nil without writing a new proc. Dispatcher remains dumb — no "no-refresh" mode.
local MetaSkillLustProviderMixin = {}

local LUST_DURATION = 40

-- Shared ActiveProc builder for both detection paths (D-08 shape).
-- startedAt is when the lust buff went out: GetTime() for a freshly added Sated debuff, or the
-- Sated debuff's derived application time on the fallback path.
local function BuildLustProc(entry, lustSpellID, startedAt)
	local lustInfo = C_Spell.GetSpellInfo(lustSpellID)
	local lustLabel = (lustInfo and lustInfo.name) or "Lust / Heroism"
	if ns.debugLogging then
		print("|cff00ccffTBT Debug|r: Lust detected (spellID " .. lustSpellID .. "), timer started.")
	end
	local proc = ns:AcquireProc(LUST_KEY)
	proc.key = LUST_KEY
	proc.spellID = lustSpellID -- numeric (D-03); was the LUST_KEY string
	proc.duration = LUST_DURATION
	proc.expiresAt = startedAt + LUST_DURATION
	proc.startedAt = startedAt
	proc.section = entry.section or "bars"
	proc.layoutOrder = entry.layoutOrder
	proc.label = lustLabel
	-- D-07. SHARED_LUST_BUFFS_LOCAL's lists are module constants shared across every cast, so
	-- they are assigned by reference and never wiped; only the fallback is pooled.
	proc.aliveBuffs = SHARED_LUST_BUFFS_LOCAL[lustSpellID] or ns:AcquireAliveBuffs(LUST_KEY, lustSpellID)
	return proc
end

-- Derives when an aura was applied from its own duration/expirationTime. Returns nil when either
-- field is secret or the aura carries no duration (permanent auras).
local function GetAuraAppliedAt(aura)
	local duration, expirationTime = aura.duration, aura.expirationTime
	if issecretvalue(duration) or issecretvalue(expirationTime) then
		return nil
	end
	if not duration or duration <= 0 or not expirationTime or expirationTime <= 0 then
		return nil
	end
	return expirationTime - duration
end

-- Fallback used when the UNIT_AURA payload is secret: read the Sated debuffs by spell ID, which
-- stays legal for the never-secret spells (ns:ReadPlayerAura asks first). Presence alone is not
-- enough — Sated lingers ~600s after a 40s lust, so the aura's own application time decides whether
-- the lust it came from is still up: no phantom timers off the Sated tail, and a lust that landed
-- before we could read it still gets the correct remaining time.
local function ScanSatedBySpellID(entry, now)
	for satedID, lustSpellID in pairs(ns.SATED_DEBUFF_TO_LUST) do
		local aura, readable = ns:ReadPlayerAura(satedID)
		if readable and aura then
			local appliedAt = GetAuraAppliedAt(aura)
			if appliedAt and appliedAt + LUST_DURATION > now then
				return BuildLustProc(entry, lustSpellID, appliedAt)
			end
		end
	end
	return nil
end

function MetaSkillLustProviderMixin:GetEventInterests()
	return { "UNIT_AURA" }
end

-- Args from UNIT_AURA: unit (string), updateInfo (table with addedAuras field)
-- Scans updateInfo.addedAuras when readable, otherwise reads the Sated debuffs by spell ID.
-- Returns the first Sated-matching proc (single proc, not a list per D-08), or nil if no match /
-- no-restart guard trips / entry hidden / aura data unreadable.
function MetaSkillLustProviderMixin:OnTrigger(event, unit, updateInfo)
	if event ~= "UNIT_AURA" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if not updateInfo then
		return nil
	end

	-- Entry guard: require a user-configured LUST_KEY entry not in hidden section.
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[LUST_KEY]
	if not entry or entry.section == "hidden" then
		return nil
	end

	-- No-restart guard (D-12): don't overwrite an already-running lust proc.
	local existing = ns.activeTimers and ns.activeTimers[LUST_KEY]
	if existing and existing.expiresAt and existing.expiresAt > GetTime() then
		return nil
	end

	-- Fast path: scan addedAuras for a Sated-family debuff. First match wins.
	-- Readability is checked on the LIST, not per entry — ipairs on a secret table errors before
	-- any per-entry guard could run.
	local addedAuras = updateInfo.addedAuras
	if ns:CanReadTable(addedAuras) then
		for _, aura in ipairs(addedAuras) do
			-- D-10: per-entry secret check; table index with aura.spellId only if safe.
			if not issecretvalue(aura.spellId) then
				local lustSpellID = ns.SATED_DEBUFF_TO_LUST[aura.spellId]
				if lustSpellID then
					return BuildLustProc(entry, lustSpellID, GetTime())
				end
			end
		end
		return nil
	end

	-- Readable payload carrying no additions: nothing could have been applied, skip the poll.
	if not issecretvalue(addedAuras) and addedAuras == nil then
		return nil
	end

	-- Payload is secret (in combat): fall back to the by-spell-ID Sated read.
	return ScanSatedBySpellID(entry, GetTime())
end

-- D-04/D-05/D-06/D-07: Class-aware fresh resolution — no cache needed. Hunter uses MM-spec-aware
-- helper; others use static class map; default 2825 (Bloodlust) if class unknown.
-- RefreshAtRest stays as base no-op (D-14) — this method is always cheap.
function MetaSkillLustProviderMixin:GetDisplayInfo(key)
	local _, classFilename = UnitClass("player")
	local lustSpellID
	if classFilename == "HUNTER" then
		lustSpellID = GetHunterLustSpell()
	else
		lustSpellID = CLASS_LUST_SPELL[classFilename] or 2825
	end
	if not lustSpellID then
		return nil
	end
	local spellInfo = C_Spell.GetSpellInfo(lustSpellID)
	local info = ns:AcquireDisplayInfo(LUST_KEY)
	info.icon = ns:GetSpellIcon(lustSpellID)
	info.label = (spellInfo and spellInfo.name) or "Lust / Heroism"
	info.duration = LUST_DURATION
	info.spellID = lustSpellID
	return info
end

-- META-01: cannot reuse AnyCatalogSpellResolves — SHARED_LUST_BUFFS_LOCAL's values are variant
-- arrays, not definition tables, so this walks primaries and variants directly. The MM-Hunter
-- variant 466904 is a spell GetDisplayInfo can actually name, so it must be part of the test.
function MetaSkillLustProviderMixin:HasResolvableCatalog()
	for primarySpellID, variants in pairs(SHARED_LUST_BUFFS_LOCAL) do
		if C_Spell.GetSpellInfo(primarySpellID) then
			return true
		end
		for _, variantSpellID in ipairs(variants) do
			if C_Spell.GetSpellInfo(variantSpellID) then
				return true
			end
		end
	end
	return false
end

local MetaSkillLustProvider = CreateFromMixins(SpellProviderBaseMixin, MetaSkillLustProviderMixin)

-- MetaSkillRacialProviderMixin (Phase 41, RACE-02/RACE-03) — a meta tile resolved to the player's own
-- racial ability, following MetaSkillLustProviderMixin's shape. For a stack-driven racial the proc itself
-- carries mutable state (proc.stacks), because the aura APIs cannot be read under restriction and
-- UNIT_SPELLCAST_SUCCEEDED casts are the only signal available while restricted. A racial with no
-- maxStacks skips all of that and is just a duration tracker.

-- RACIAL_SPELLS: numeric raceID (third return of UnitRace("player")) -> racial definition.
-- Keyed numerically, not by raceFile, because a wrong-cased string token would fail silently —
-- a miss here would mean the racial never fires and nothing would error, so the key must not be
-- defeatable by a capitalisation assumption.
--
-- Phase 49 / RACE-10: absence from this table is no longer a "not yet supported" state with its
-- own tooltip. A race missing here simply contributes no racial suggestions at all, the same way
-- a character with no consumables contributes no item suggestions — there is no tile and no
-- message. D-7 closed RACE-09 on exactly this basis: the generic racial tile its "not yet
-- supported" message lived on no longer exists once every racial is its own race-gated entry, so
-- the requirement has no subject left to implement. Accepted consequence: a future Forever race
-- (or retail, RACE-06, deferred again at this milestone's kickoff) shows nothing at all until its
-- row is added here.
--
-- `maxStacks` is OPTIONAL and is what makes a racial stack-driven. With it, qualifying casts
-- spend stacks and the tracker ends early when the last one goes (RACE-03). Without it the racial
-- is a plain duration tracker: the granting cast starts it, the nominal duration ends it, and no
-- cast is ever inspected — `OnTrigger`'s consuming path returns on `proc.stacks == nil` before
-- reaching either `C_Spell` call, so a stackless racial costs nothing per cast.
--
-- Phase 44.1: each race maps to a LIST of racials, not one. Forever gives most classes two, and
-- the second is tracked exactly like the first -- its own Suggested tile, empty by default, and
-- nothing auto-added. A race with one racial simply has a one-entry list, so the shape is uniform
-- and no caller branches on how many there are.
--
-- `cooldown` is new alongside `duration`, and the two are different things: duration is how long
-- the buff lasts, cooldown is how long until it can be used again. The cooldown feeds the
-- Suggested tiles on the Cooldowns tab, which create ordinary "metaSkillCd:<spellID>" trackers --
-- the same machinery any hand-added cooldown uses, with the number filled in.
--
-- Phase 49 / RACE-07 filled every row below from a fresh in-game collection pass, and widened the
-- field vocabulary a row can use. Fields are written in this order, each optional one omitted
-- when the racial does not have it:
--
-- `spellID` (required) — the CAST id. A racial with no cast at all (tauren Plainsrunning) uses its
-- aura id here instead, because the key namespace (`metaSkill:<spellID>`) and every lookup this
-- file and Core.lua perform are spellID-shaped; there is no separate "identity" field.
-- `duration` (optional) — omitted for a racial that applies no aura at all, and for an indefinite
-- one. 49-01's `StartRacialProc` guard returns nil on a row with no `duration`, so the racial
-- surfaces as its cooldown tile and nothing else, and never raises on `now + nil`.
-- `cooldown` (optional) — omitted for dwarf Find Treasure and tauren Plainsrunning, which
-- genuinely have none. `ns:RacialCooldownKeys` emits a key only for a def that has one, so the
-- missing tile falls out of the data rather than out of a rule (D-6).
-- `combatCooldown` (optional) — night elf Shadowmeld only so far: the cooldown a cast made IN
-- combat earns instead of `cooldown`, which its tooltip states outright. `ns:ConditionalCooldown`
-- turns it into a one-cast override; `cooldown` above stays the ordinary out-of-combat number and
-- is still what the tile seeds and previews from.
-- `maxStacks` (optional) — gnome Eureka! only, the one known stacking racial.
-- `auraID` (optional) — set where the aura id differs from the cast id (undead Cannibalize
-- 20577/20578, Alliance Skyborne's Read Ley Line 1259705/1270842, Horde Skyborne's Skysight
-- 1259686/1259688) or wherever any aura read is needed at all.
-- `indefinite` (optional) — the buff has no natural end and renders with no countdown (D-6:
-- Shadowmeld, Find Treasure, Plainsrunning). Consumed starting in 49-04.
-- AURA-LOSS CANCELLATION IS NOT A FIELD — it applies to EVERY racial buff proc, unconditionally.
-- `StartRacialProc` gives each one `aliveBuffs = { auraID or spellID }`, so
-- `ns:ScanActiveTimersForCancellation` (`BuffEngine.lua`) ends it whenever a READABLE aura read
-- positively reports the aura missing. There was briefly a `cancelOnAuraLoss` opt-in here; it was
-- removed on 2026-09-25 because making "does this end when its buff ends" opt-in meant every
-- racial that can end early arrived as its own bug report.
-- `startFromAura` (optional) — Plainsrunning only. It has no cast at all, so its proc begins from
-- a `UNIT_AURA` sighting rather than `UNIT_SPELLCAST_SUCCEEDED` (D-2).
-- `clearOnCombat` (optional) — the proc ends on `PLAYER_REGEN_DISABLED`. Set on Shadowmeld,
-- because aura reads are secret in combat for a tainted caller so the cancellation scan cannot see
-- the drop there (D-1); and on Plainsrunning, because it is an out-of-combat passive that drops
-- the instant combat begins (D-2).
-- `longDuration` (optional) — the proc starts on the short `duration` and is corrected UPWARD out
-- of combat when the aura's real duration reads longer (D-3). Both Skyborne second racials
-- stretch to fifteen minutes on a condition; a racial timer that under-runs is recoverable, one
-- hanging fourteen minutes past its buff is not.
-- `race` and `fallbackLabel` (required) — `fallbackLabel` is always the CAST name, never the
-- aura's, on every row where the two differ (Read Ley Line, not Energized; Skysight, not
-- Elemental Blessing; Cannibalize, not its unnamed aura) — that is what the player pressed and
-- what the icon and tooltip resolve from.
--
-- Every number below is a reading of the CURRENT BETA PATCH, and Forever racials are being
-- actively changed under it. Gnome Eureka!'s cooldown is the proof: entered correctly at 180s in
-- Phase 41, read back at 120s in Phase 49 because the beta changed the ability in between. A
-- disagreement between this table and the live client means "re-read the client", never "someone
-- was careless" here or at the client's end. `.planning/research/FOREVER-RACIALS.md` is the source
-- of record for every spellID, duration and cooldown in the table below — re-derive from there,
-- never from this table's own history, when a row is ever in doubt.
local RACIAL_SPELLS = {
	[1] = {
		{ spellID = 20600, duration = 20, cooldown = 180, race = "Human", fallbackLabel = "Perception" },
		{ spellID = 1259718, cooldown = 180, race = "Human", fallbackLabel = "Will to Survive" },
	},
	[2] = {
		{ spellID = 20572, duration = 15, cooldown = 120, race = "Orc", fallbackLabel = "Blood Fury" },
		{ spellID = 1299026, duration = 8, cooldown = 180, race = "Orc", fallbackLabel = "Shatter Curse" },
	},
	[3] = {
		{ spellID = 20594, duration = 8, cooldown = 180, race = "Dwarf", fallbackLabel = "Stoneform" },
		{
			spellID = 2481,
			auraID = 2481,
			indefinite = true,
			race = "Dwarf",
			fallbackLabel = "Find Treasure",
		},
	},
	[4] = {
		{
			spellID = 20580,
			cooldown = 10,
			combatCooldown = 120,
			auraID = 20580,
			indefinite = true,
			clearOnCombat = true,
			race = "Night Elf",
			fallbackLabel = "Shadowmeld",
		},
		{ spellID = 1259799, duration = 15, cooldown = 180, race = "Night Elf", fallbackLabel = "Elune's Light" },
	},
	[5] = {
		{
			spellID = 20577,
			duration = 10,
			cooldown = 120,
			auraID = 20578,
			race = "Undead",
			fallbackLabel = "Cannibalize",
		},
		{ spellID = 7744, cooldown = 120, race = "Undead", fallbackLabel = "Will of the Forsaken" },
	},
	[6] = {
		{ spellID = 20549, cooldown = 120, race = "Tauren", fallbackLabel = "War Stomp" },
		{ spellID = 20552, cooldown = 3600, race = "Tauren", fallbackLabel = "Cultivation" },
		{
			spellID = 1299038,
			auraID = 1299038,
			indefinite = true,
			startFromAura = true,
			clearOnCombat = true,
			race = "Tauren",
			fallbackLabel = "Plainsrunning",
		},
	},
	[7] = {
		{ spellID = 1259817, duration = 15, cooldown = 120, maxStacks = 3, race = "Gnome", fallbackLabel = "Eureka!" },
		{ spellID = 20589, duration = 3, cooldown = 120, race = "Gnome", fallbackLabel = "Escape Artist" },
	},
	[8] = {
		{ spellID = 20554, duration = 10, cooldown = 180, race = "Troll", fallbackLabel = "Berserking" },
		{ spellID = 1260270, duration = 6, cooldown = 180, race = "Troll", fallbackLabel = "Rapid Regeneration" },
	},
	[95] = {
		{
			spellID = 1259416,
			auraID = 1259416,
			duration = 10,
			cooldown = 120,
			race = "Skyborne",
			fallbackLabel = "Walk on Air",
		},
		{
			spellID = 1259705,
			duration = 15,
			cooldown = 120,
			auraID = 1270842,
			longDuration = true,
			race = "Skyborne",
			fallbackLabel = "Read Ley Line",
		},
	},
	[96] = {
		{
			spellID = 1259416,
			auraID = 1259416,
			duration = 10,
			cooldown = 120,
			race = "Skyborne",
			fallbackLabel = "Walk on Air",
		},
		{
			spellID = 1259686,
			duration = 30,
			cooldown = 120,
			auraID = 1259688,
			longDuration = true,
			race = "Skyborne",
			fallbackLabel = "Skysight",
		},
	},
}

-- Reverse ownership index: every spellID belonging to ANY race's racial. Built once at load by
-- walking RACIAL_SPELLS; read only by ns:IsRacialSpellID below (the schema v8 kind guess). No race
-- gating reads it: a racial is loaded when this character knows it (Phase 57.3 LOAD-04), resolved
-- by ns:TrackerLoad like every tracker.
local racialSpellOwners = {}
for _, defs in pairs(RACIAL_SPELLS) do
	for _, def in ipairs(defs) do
		racialSpellOwners[def.spellID] = true
	end
end

-- Membership test for Core.lua's ns:CooldownKindFor and BuffEngine.lua's ns:MigrateKindKeys
-- (53-CONTEXT "Migration shape"): true when spellID belongs to ANY race's racial, never gated on
-- the current character's race. Both callers run before this file's own load-time classification
-- work is otherwise needed, so this is a plain membership read with no API call.
function ns:IsRacialSpellID(spellID)
	return racialSpellOwners[spellID] == true
end

-- Phase 57.3 (LOAD-04): every raceID in RACIAL_SPELLS, ascending, built once at file load, so
-- ns:RacialDefsAll walks the races in a stable order (pairs() order is not) and the Suggested
-- racial tiles do not reshuffle between sessions.
local racialRaceIDsSorted = {}
for raceID in pairs(RACIAL_SPELLS) do
	racialRaceIDsSorted[#racialRaceIDsSorted + 1] = raceID
end
table.sort(racialRaceIDsSorted)

-- The shared empty table every "no racials for this answer" return uses, so callers never need to
-- distinguish "this race has none" from "a fresh table with nothing in it".
local EMPTY_RACIAL_DEFS = {}

-- Sticky, session-long memoisation of the player's raceID ONLY -- not the resolved def list. A
-- character's race cannot change mid-session, so once UnitRace("player") reads back a real number
-- it is safe to remember forever. An early, unreadable read must retry rather than poison this
-- memo: 49-03's migration can ask before UnitRace resolves.
local racialRaceIDMemo

-- MIGRATION-ONLY since Phase 57.3: racials are just spells, loaded when known, so nothing at runtime
-- asks for the player's race any more. Schema v7's racial re-key (BuffEngine.lua) still needs the
-- race to resolve its legacy "racial"/"racial2" slots, and that is the only reason this and
-- racialRaceIDMemo above remain.
--
-- The player's raw racial definitions straight out of RACIAL_SPELLS, with NO spell-data dependency
-- at all: no C_Spell call, no ns.CLIENT_IS_FOREVER gate, safe to call as early as ADDON_LOADED,
-- before spell data has loaded. Returns (defs, raceID): defs is the raw list for this race (or the
-- shared empty table), raceID is the resolved numeric race ID or nil when UnitRace could not be
-- read this call.
--
-- The second return is not optional. 49-03's migration must be able to tell "this race genuinely
-- has no racial here" (defs empty, raceID a real number -- safe to clean up) from "UnitRace is not
-- readable yet" (raceID nil -- must defer instead of discarding data). An empty defs table alone
-- cannot carry that distinction.
function ns:RacialDefsRaw()
	if racialRaceIDMemo then
		local raceID = racialRaceIDMemo
		return RACIAL_SPELLS[raceID] or EMPTY_RACIAL_DEFS, raceID
	end
	local _, _, raceID = UnitRace("player")
	-- issecretvalue() first: type() reports "number" for a secret number too, so testing type()
	-- alone would treat an unreadable raceID as a readable one.
	if issecretvalue(raceID) or type(raceID) ~= "number" then
		return EMPTY_RACIAL_DEFS, nil
	end
	racialRaceIDMemo = raceID
	return RACIAL_SPELLS[raceID] or EMPTY_RACIAL_DEFS, raceID
end

-- Phase 57.3 (LOAD-04): display-ready defs for EVERY racial of every race -- racials are just
-- spells (user, 2026-09-29), so which ones a character gets is decided by "is it known", never by
-- its race. One def per distinct spellID (Walk on Air is listed under two races), walked in
-- ascending raceID order for a stable list. Resolved through C_Spell.GetSpellInfo: a def whose
-- spell fails to resolve is dropped -- on retail that is what keeps a Forever-only racial from ever
-- appearing. Optional fields (auraID, indefinite, startFromAura, clearOnCombat, longDuration) are
-- copied unconditionally: they read nil on every row that does not set them.
--
-- Rebuilt into the SAME module-level array rather than allocated fresh; a def resolved once is kept
-- in racialDefsBySpellID for the session and reused by every later build, so only a def that has
-- not resolved yet is asked again. Memoised only once ns.knownReady is set (review WR-03): before
-- world entry spell data may be incomplete, and a list frozen then would stay partial all session.
-- A build that left a def unresolved is retried by ns:RebuildRacialLoadLists (rebuild time, never
-- per frame); per-frame readers such as ns:RacialDefForSpellID only ever read the memo.
local racialDefsAll = {}
local racialDefsBySpellID = {}
local racialDefsAllResolved = false
local racialDefsAllMissing = false
-- Stamped on each resolved def as it joins the array, so a spellID listed under two races (Walk on
-- Air) joins once per build with no seen-table allocated.
local racialDefsAllStamp = 0

function ns:RacialDefsAll()
	if racialDefsAllResolved then
		return racialDefsAll
	end
	racialDefsAllStamp = racialDefsAllStamp + 1
	wipe(racialDefsAll)
	local missing = false
	for _, raceID in ipairs(racialRaceIDsSorted) do
		for _, def in ipairs(RACIAL_SPELLS[raceID]) do
			local resolved = racialDefsBySpellID[def.spellID]
			if not resolved then
				local spellInfo = C_Spell.GetSpellInfo(def.spellID)
				if spellInfo then
					resolved = {
						spellID = def.spellID,
						duration = def.duration,
						cooldown = def.cooldown,
						combatCooldown = def.combatCooldown,
						maxStacks = def.maxStacks,
						auraID = def.auraID,
						indefinite = def.indefinite,
						startFromAura = def.startFromAura,
						clearOnCombat = def.clearOnCombat,
						longDuration = def.longDuration,
						label = spellInfo.name or def.fallbackLabel,
						-- Review IN-04: the two tracker keys, built once here and read by every
						-- rebuild, cast, aura and combat-edge path instead of concatenating there.
						key = META_SKILL_PREFIX .. def.spellID,
						cdKey = ns:TrackerKey(ns.KIND.META_SKILL_CD, def.spellID),
					}
					racialDefsBySpellID[def.spellID] = resolved
				else
					missing = true
				end
			end
			if resolved and resolved.buildStamp ~= racialDefsAllStamp then
				resolved.buildStamp = racialDefsAllStamp
				racialDefsAll[#racialDefsAll + 1] = resolved
			end
		end
	end
	racialDefsAllMissing = missing
	if ns.knownReady then
		racialDefsAllResolved = true
	end
	return racialDefsAll
end

-- Phase 57.3 (LOAD-04): the racials this character knows (the Suggested offer) and the racials
-- whose built-in buff tracker is tracked AND loaded (what the provider hot paths walk). Both are
-- rebuilt only by ns:RebuildRacialLoadLists, never per cast or per aura event.
ns.knownRacialDefs = {}
ns.racialDefsActive = {}

-- Called by Core.lua's ns:RebuildTrackerLoad once the loaded state is final, so both lists follow
-- every spellbook, talent, spec, login and tracker-edit moment. A racial that has never read
-- readably is not offered (fallback false), and racials have one rank, so no rank scan (noRanks).
-- Each def carries its own key (review IN-04), so nothing is concatenated. The provider hot paths
-- walk ns.racialDefsActive, which is usually zero to two entries.
function ns:RebuildRacialLoadLists()
	wipe(ns.knownRacialDefs)
	wipe(ns.racialDefsActive)
	-- Review WR-03: nothing casts before world entry, and spell data may not be ready yet, so the
	-- racial list is neither built nor memoised here before ns.knownReady.
	if not ns.knownReady then
		return
	end
	-- A def that did not resolve last time is asked again now (on retail, the Forever-only racials
	-- never resolve, so this is a handful of lookups per rebuild, never per frame).
	if racialDefsAllMissing then
		racialDefsAllResolved = false
	end
	local tracked = ns.db and ns.db.trackedBuffs
	-- The known list feeds only ns:RacialSuggestions, which offers racials on Forever alone; on
	-- retail it is never read, so skip its ~20 guarded known checks on every SPELLS_CHANGED there.
	local offersRacials = ns.CLIENT_IS_FOREVER
	for _, def in ipairs(ns:RacialDefsAll()) do
		if offersRacials and ns:ResolveSpellKnown(def.spellID, false, true) then
			ns.knownRacialDefs[#ns.knownRacialDefs + 1] = def
		end
		local key = def.key
		if tracked and tracked[key] and ns:IsTrackerLoaded(key) then
			ns.racialDefsActive[#ns.racialDefsActive + 1] = def
		end
	end
end

-- The OFFER list -- what the Buffs tab's Suggested section shows: the racials this character
-- KNOWS (Phase 57.3; no longer "the racials of this character's race"). Racial is Forever-only:
-- retail's Cooldown Manager already carries racials, so offering TBT's own would duplicate them
-- (a flavour decision from 2026-09-23, not a race gate). Both the buff-tile offer and the
-- cooldown-tile offer (ns:RacialCooldownKeys below) read through this function.
--
-- An entry already in the database is NOT withheld by this gate -- ns:RacialDefForSpellID is
-- ungated by flavour, so a retail character's pre-existing racial entry keeps resolving, and runs
-- whenever its load rule says it is loaded.
function ns:RacialSuggestions()
	if not ns.CLIENT_IS_FOREVER then
		return EMPTY_RACIAL_DEFS
	end
	return ns.knownRacialDefs
end

-- Shared walk-and-match behind every "resolve a racial def by spellID" caller (RACE-10 introduced
-- three near-identical copies of this walk; this is the one). Takes the list to walk as a
-- parameter rather than choosing one itself -- the list a caller walks is the thing that actually
-- differs between the three, so it stays the caller's choice. Allocates nothing: a plain ipairs
-- walk and one equality test.
--
-- Declared on ns, not as a file-local. A `local function` is an upvalue only to functions declared
-- AFTER it in the file, and this project has shipped that exact bug five times (see
-- ns:RacialCooldownSeed below for the fourth). ns: resolves at call time, so declaration order
-- stops mattering.
function ns:RacialDefInList(defs, spellID)
	for _, def in ipairs(defs) do
		if def.spellID == spellID then
			return def
		end
	end
	return nil
end

-- The resolved def of ANY racial matching this spellID, or nil -- one map read once
-- ns:RacialDefsAll is memoised. Any race's racial resolves (Phase 57.3), so a tile for a racial
-- this character does not know still shows its icon and name, greyed, in the TBT tab. Ungated by
-- flavour, so a retail character's pre-existing racial tracker keeps resolving.
function ns:RacialDefForSpellID(spellID)
	ns:RacialDefsAll()
	return racialDefsBySpellID[spellID]
end

-- 49-04/D-1/D-2: the combat-entry edge for the two racials that end the instant combat starts.
-- Aura reads are secret in combat for a tainted caller, so ns:ScanActiveTimersForCancellation
-- cannot see Shadowmeld's aura drop once combat begins -- and Shadowmeld breaks on almost any
-- combat action anyway. Clearing on the combat edge is both correct and the only thing available.
-- Plainsrunning is the same shape (D-2): an out-of-combat passive that drops the instant combat
-- begins, and 49-04's UNIT_AURA start (RacialAuraTrigger, above) is what brings it back once
-- combat ends. Called from Core.lua's PLAYER_REGEN_DISABLED branch -- the caller lives there, this
-- accessor lives here with the rest of the racial API.
-- Phase 57.3: walks only the tracked, loaded racials (ns.racialDefsActive).
function ns:EndCombatClearedRacials()
	for _, def in ipairs(ns.racialDefsActive) do
		if def.clearOnCombat then
			ns:EndTimer(def.key)
		end
	end
end

-- The cooldown-tracker keys for whichever racials this character knows, as ordinary
-- "metaSkillCd:<spellID>" strings. Empty for a race with none, so the Cooldowns tab simply shows
-- no racial tiles at all -- there is no generic placeholder any more (D-7).
--
-- Rebuilt into a module-level array rather than a fresh table: the Suggested section redraws on
-- every CDM open and after every drag.
local racialCooldownKeys = {}

function ns:RacialCooldownKeys()
	wipe(racialCooldownKeys)
	for _, def in ipairs(ns:RacialSuggestions()) do
		if def.cooldown then
			racialCooldownKeys[#racialCooldownKeys + 1] = def.cdKey
		end
	end
	return racialCooldownKeys
end

-- spellID -> the resolved racial def, so a "metaSkillCd:<spellID>" tile can show a real name and
-- a real duration BEFORE the tracker exists. Without it UserSpellProvider's no-entry branch would offer
-- "Spell 20572" with duration 0, and the entry created from it would carry that 0 forever.
-- On ns rather than a file-local, because its only caller -- UserSpellProviderMixin:GetDisplayInfo
-- -- is defined hundreds of lines ABOVE this point. A file-local is an upvalue only to functions
-- declared after it, and this project has produced that bug four times; resolving through ns
-- happens at call time, so declaration order stops mattering.
function ns:RacialCooldownSeed(spellID)
	-- Deliberately the gated list (RacialSuggestions), NOT ns:RacialDefsAll. RacialSuggestions
	-- returns EMPTY_RACIAL_DEFS on retail; substituting the ungated list would start seeding racial
	-- cooldown tiles there too, a behaviour change out of bounds for this phase.
	local def = ns:RacialDefInList(ns:RacialSuggestions(), spellID)
	if def and def.cooldown then
		return def
	end
	return nil
end

-- The cooldown THIS cast earns, when it differs from the tracker's own -- or nil, which is the
-- answer for every cast but a handful. Feeds ns.cooldownOverrides straight from the dispatcher.
--
-- Night elf Shadowmeld is the whole of it today: ten seconds normally, two minutes when used in
-- combat, which its own tooltip states outright ("Using this ability in combat discourages enemies
-- from attacking you, but increases the cooldown to 2 min"). Reported after the 49 Alliance gate
-- pass, 2026-09-25 -- the cd tile ran its ten seconds and went ready while the real ability had
-- nearly two minutes left.
--
-- Why this is needed at all, given that Blizzard's own handle knows the true number: it does, and
-- TBT deliberately does not ask it. ApplyUserCooldown (Display.lua) draws a cooldown tracker from
-- the duration the tracker carries and skips the engine handle entirely -- the user's typed
-- number wins, by explicit decision on 2026-09-22. A racial tile inherits its duration from
-- RACIAL_SPELLS the same way, so it inherits that decision too. An earlier comment in
-- StartRacialProc asserted the opposite ("its cooldown tile still fires, because that is a
-- separate tracker reading the live game handle") and was simply wrong about which path draws it.
--
-- InCombatLockdown() at cast time is the same signal StartRacialProc uses to suppress
-- Shadowmeld's buff tile, so the two cannot disagree about what kind of cast this was.
--
-- Cost on the common cast: one map read in ns:RacialDefForSpellID (memoised), reached only after a
-- cooldown tracker for this spell was already found.
function ns:ConditionalCooldown(spellID)
	local def = ns:RacialDefForSpellID(spellID)
	if def and def.combatCooldown and InCombatLockdown() then
		return def.combatCooldown
	end
	return nil
end

-- Class buffs as built-in reminders (Phase 57.4, MREM-01..03; retail rows Phase 64, MREM-04/05).
-- Each row carries a client tag (forever / retail / both) read against ns.CLIENT_IS_FOREVER only
-- (PROJECT.md Key Decision 2026-09-30); "is it known" alone is not enough, because 6673, 465 and
-- 21562 exist on Forever with another meaning. An off-client row is never registered, so a placed
-- one reads as an orphan. Forever spell IDs are from the user (2026-09-29). The class and name on each row are
-- reference comments only and are never saved ("class and name are to be noted for future
-- reference on the code"). The aura ID is the row's auraID, else its spell ID (Phase 64: 474750
-- watches 474754, 364342 watches 381748); the user verifies each in game with TBT's ID tooltip.
--
-- Deliberately NOT here (user decisions 2026-09-29):
--   - group versions (Arcane Brilliance, Prayer of Fortitude, Gift of the Wild, the Greater
--     Blessings) do not count as the buff being present, for now;
--   - the shaman totems Strength of Earth (25361) and Windfury (10609) are left out because their
--     auras have different IDs from the casts.
--
-- On Forever every rank the character knows counts, through the rank family (ns:ResolveRankFamily;
-- a metaReminder is rank-covering wherever ns.CLIENT_HAS_SPELL_RANKS). Retail has no ranks, so a
-- retail row watches its single aura ID (Phase 64 review CR-01/WR-01). A row's duration is in
-- minutes; 0 = no timer (aura only).
--
-- In-game verification (user, 2026-09-29): the Mage, Paladin and Warlock rows were tested in
-- game (57.4-HUMAN-UAT). The other classes are being tested now, and their rows keep
-- "(unverified in game)" in their trailing comment until reported. Righteous Fury (25780, added
-- in Phase 57.5) assumes its aura ID equals its spell ID; the user verifies it.
--
-- Blessing of Sanctuary (20914) was removed on 2026-09-29 (Phase 57.5, RALT-03): it no longer
-- exists on Forever. A placed one is an orphan per the WR-02 rule below -- greyed, "no longer
-- offered", with no data deleted.
--
-- Alternatives (RALT-03, Phase 57.5): a MetaReminderGroup after the rows makes its members list
-- each other as alternatives ("Also satisfied by", RALT-01), so any one member present or cast
-- satisfies every member's reminder. ns:ApplyMetaReminderDef applies them from here; user input
-- never reaches a built-in's alternatives.
--
-- This table is a metaReminder's one source of truth: ns:ApplyMetaReminderDef rewrites the entry's
-- derived fields from it at every ns:RebuildCastIndex, so a changed row needs no migration.
-- Changing a row's spell ID (or removing a row) is different: the key is "metaReminder:<spellID>",
-- so a saved entry for the old ID becomes an orphan. It is not loaded and its TBT tab tile says
-- to remove it (review WR-02); the new ID is offered in Suggested as a separate reminder.
local META_REMINDER_DEFS = {}
local metaReminderDefsBySpellID = {}

-- Load-time only: builds one row and indexes it. knownID is the spell the load rule and the
-- Suggested offer ask (the buff itself unless named); petBook adds the pet spellbook to the
-- row's rank family; castID is the spell a click casts (nil = the row's own spellID, false = none).
-- opts is nil or a load-time table: client ("forever", "retail" or "both"; nil = "forever"), auraID
-- (nil = the aura is the spell ID) and allyCast (true = a click does not force the player as unit).
-- This is the ONE point where a row is kept off a client: an unregistered row is neither offered
-- nor loaded (an already-placed entry for it is an orphan via ns:IsOrphanMetaReminder). Existing
-- Forever rows need no argument because nil means forever.
local function MetaReminderRow(spellID, minutes, knownID, petBook, castID, opts)
	local client = opts and opts.client or "forever"
	local isForever = ns.CLIENT_IS_FOREVER == true
	if not (client == "both" or (client == "forever" and isForever) or (client == "retail" and not isForever)) then
		return
	end
	local def = {
		auraID = opts and opts.auraID or nil,
		allyCast = opts ~= nil and opts.allyCast == true,
		spellID = spellID,
		duration = minutes > 0 and minutes * 60 or nil,
		knownID = knownID or spellID,
		petBook = petBook == true,
		castID = castID == nil and spellID or castID,
		key = ns:TrackerKey(ns.KIND.META_REMINDER, spellID),
	}
	META_REMINDER_DEFS[#META_REMINDER_DEFS + 1] = def
	metaReminderDefsBySpellID[spellID] = def
end

-- Load-time only (RALT-03, Phase 57.5): every listed row's def.alternatives becomes a fresh array
-- of the OTHER IDs in the group, in argument order. Called after the rows it names. The def's
-- array is never handed out: ns:ApplyMetaReminderDef gives each entry a copy (57.5 review IN-03).
local function MetaReminderGroup(...)
	local ids = { ... }
	for i = 1, #ids do
		local def = metaReminderDefsBySpellID[ids[i]]
		if def then
			local others = {}
			for j = 1, #ids do
				if j ~= i then
					others[#others + 1] = ids[j]
				end
			end
			def.alternatives = others
		end
	end
end

MetaReminderRow(1459, 60, nil, nil, nil, { client = "both" }) -- Mage: Arcane Intellect, same ID and duration on Forever and retail
MetaReminderRow(7301, 30) -- Mage: Frost Armor
MetaReminderRow(10938, 60) -- Priest: Power Word: Fortitude (unverified in game)
MetaReminderRow(9885, 60) -- Druid: Mark of the Wild (unverified in game)
MetaReminderRow(9910, 10) -- Druid: Thorns (unverified in game)
MetaReminderRow(25289, 3) -- Warrior: Battle Shout (unverified in game)
MetaReminderRow(20906, 30) -- Hunter: Trueshot Aura (unverified in game)
MetaReminderRow(11767, 0, 688, true, false) -- Warlock: Blood Pact (the imp's; loads when Summon Imp 688 is known; no cast spell: the imp casts it, so no click action (CLICK-06))
MetaReminderRow(20217, 60) -- Paladin: Blessing of Kings
MetaReminderRow(25291, 60) -- Paladin: Blessing of Might
MetaReminderRow(25290, 60) -- Paladin: Blessing of Wisdom
MetaReminderRow(1038, 60) -- Paladin: Blessing of Salvation
MetaReminderRow(19979, 60) -- Paladin: Blessing of Light
MetaReminderRow(25780, 30) -- Paladin: Righteous Fury (aura ID = spell ID, unverified)

-- RALT-03: the five blessings satisfy each other -- a paladin holds one own blessing per target.
MetaReminderGroup(20217, 25291, 25290, 1038, 19979)

-- The retail rows (user data 2026-09-30, MREM-04/MREM-05).
-- Arcane Familiar trade-off: a cast of 1459 starts only the Arcane Intellect row (the cast index
-- holds one owner per spell), so the familiar's reminder hides through its aura 210126 (UNIT_AURA
-- and the post-cast re-check); listing 1459 as its alternative would wrongly let Arcane Intellect
-- alone satisfy it.
MetaReminderRow(210126, 60, 205022, nil, 1459, { client = "retail" }) -- Mage: Arcane Familiar; keyed on its aura 210126 so it never collides with metaReminder:1459; loads when talent 205022 is known; a click casts Arcane Intellect 1459, which grants the familiar
MetaReminderRow(21562, 60, nil, nil, nil, { client = "retail" }) -- Priest: Power Word: Fortitude
MetaReminderRow(1126, 60, nil, nil, nil, { client = "retail" }) -- Druid: Mark of the Wild (1126 is the druid's spell; 102046, from the original table, is a same-named non-player spell no druid knows, so that row was never offered)
MetaReminderRow(474750, 60, nil, nil, nil, { client = "retail", auraID = 474754, allyCast = true }) -- Druid: Symbiotic Relationship (aura 474754; cast on your target)
MetaReminderRow(6673, 60, nil, nil, nil, { client = "retail" }) -- Warrior: Battle Shout
MetaReminderRow(462854, 60, nil, nil, nil, { client = "retail" }) -- Shaman: Skyfury
MetaReminderRow(192106, 60, nil, nil, nil, { client = "retail" }) -- Shaman: Lightning Shield (user, 2026-10-01; aura ID = spell ID)
MetaReminderRow(364342, 60, nil, nil, nil, { client = "retail", auraID = 381748 }) -- Evoker: Blessing of the Bronze (aura 381748)
MetaReminderRow(369459, 60, nil, nil, nil, { client = "retail", allyCast = true }) -- Evoker: Source of Magic (cast on your target)
MetaReminderRow(465, 0, nil, nil, nil, { client = "retail" }) -- Paladin: Devotion Aura (permanent: no duration, shown once the aura is gone, no lead window)

-- Per the user decision, Concentration Aura 317920 or Crusader Aura 32223 satisfies Devotion Aura;
-- they are alternatives only (not rows), so only 465 receives the list, and Devotion stays the cast spell.
MetaReminderGroup(465, 317920, 32223)

-- The table row for a class-buff spell ID, or nil. One map read.
function ns:MetaReminderDef(spellID)
	return metaReminderDefsBySpellID[spellID]
end

-- The spell the load rule and the Suggested offer ask for a row: the buff itself, except Blood
-- Pact, whose row names Summon Imp. A spell ID with no row answers itself.
function ns:MetaReminderKnownID(spellID)
	local def = metaReminderDefsBySpellID[spellID]
	return def and def.knownID or spellID
end

-- True only for a row whose rank family also reads the pet spellbook (Blood Pact).
function ns:MetaReminderUsesPetBook(spellID)
	local def = metaReminderDefsBySpellID[spellID]
	return def ~= nil and def.petBook == true
end

-- The spell a click on a reminder casts (CLICK-06), or nil for "no click action". A built-in reads
-- its table row (Blood Pact is data: castID = false); a user reminder reads entry.castID, defaulting
-- to its own spell ID when nil, and false when the user emptied the box (no click action). Called by ReminderClick.lua; no API call, no allocation.
function ns:ReminderCastID(entry)
	if not ns:IsReminderEntry(entry) then
		return nil
	end
	local id
	if entry.trackerType == ns.KIND.META_REMINDER then
		local def = metaReminderDefsBySpellID[entry.spellID]
		if not def or def.castID == false then
			return nil
		end
		id = def.castID
	else
		id = entry.castID
		-- false: the user emptied the Cast spell ID box -- no click action, as for Blood Pact.
		if id == false then
			return nil
		end
		if type(id) ~= "number" then
			id = entry.spellID
		end
	end
	if issecretvalue(id) or type(id) ~= "number" or id <= 0 then
		return nil
	end
	return id
end

-- Whether a click on a reminder should force the player as the cast unit: nil for the ally-cast
-- rows (Symbiotic Relationship, Source of Magic), "player" for everything else (Phase 63 self-cast).
-- Called by ReminderClick.lua's flush; nil leaves the overlay's unit unset so the game's default
-- targeting applies (a friendly target receives the cast); no API call, no allocation.
function ns:ReminderCastUnit(entry)
	if entry.trackerType == ns.KIND.META_REMINDER then
		local def = metaReminderDefsBySpellID[entry.spellID]
		if def and def.allyCast then
			return nil
		end
	end
	return "player"
end

-- Rewrites a metaReminder entry's derived fields from its table row. The table is the one source
-- of truth; this runs from ns:RebuildCastIndex every rebuild, before any index reads the entry.
-- An entry whose row was removed (or re-keyed) keeps its saved copy untouched and is never loaded
-- (ns:IsOrphanMetaReminder, review WR-02). Each field is written only when different.
-- The data is fixed: rank-covering wherever the client has spell ranks (MREM-03; Forever), the aura
-- ID comes from the row (nil = the spell ID), and no aura-loss opt-out or cross-spell rule applies.
-- Phase 64 review CR-01/WR-01: retail has no ranks, so there a metaReminder is NOT rank-covering and
-- watches its single aura ID like a retail userReminder. Forcing coverage on retail made the
-- name-matched spellbook scan pull the Arcane Familiar talent 205022 into its own watch list, and
-- rebuilt retail families uncached on every in-combat SPELLS_CHANGED. Reads the existing
-- ns.CLIENT_HAS_SPELL_RANKS answer (no new flavour comparison); a retail entry saved with
-- coverAllRanks = true by the earlier Phase 64 build is cleared here on its next rebuild.
-- Alternatives (RALT-03, Phase 57.5) come from the table only, never from user input, and a row
-- with no group clears them. This runs before
-- ns:RebuildDetailedRuleIndex reads them, in the same ns:RebuildCastIndex.
-- 57.5 review IN-03: the entry gets its OWN copy of the row's array, never the def's table, so an
-- in-place edit of a saved list can never reach the def or another row of the blessing group. The
-- copy is made only when the entry's list differs by content (the first rebuild after the row
-- changed); a saved copy that already matches is kept, so a rebuild allocates nothing.
function ns:ApplyMetaReminderDef(entry)
	local def = metaReminderDefsBySpellID[entry.spellID]
	if not def then
		return
	end
	if entry.duration ~= def.duration then
		entry.duration = def.duration
	end
	local covers = ns.CLIENT_HAS_SPELL_RANKS == true or nil
	if entry.coverAllRanks ~= covers then
		entry.coverAllRanks = covers
	end
	if entry.auraID ~= def.auraID then
		entry.auraID = def.auraID
	end
	if entry.keepOnAuraLoss ~= nil then
		entry.keepOnAuraLoss = nil
	end
	if entry.endOnCast ~= nil then
		entry.endOnCast = nil
	end
	if entry.castID ~= nil then
		entry.castID = nil
	end
	-- ns:SameIDList / ns:CopyIDList (Core.lua, 57.5 review IN-03); a def's array is always a proper
	-- sequence (MetaReminderGroup builds it).
	if entry.alternatives ~= def.alternatives and not ns:SameIDList(entry.alternatives, def.alternatives) then
		entry.alternatives = def.alternatives and ns:CopyIDList(def.alternatives)
	end
end

-- The Reminders tab's Suggested offer: the metaReminder keys for every row this character knows,
-- in table order. Render-time, called only by the Reminders tab's Suggested section (CDM open and
-- after a drag), never per frame; the rank families it needs are cached in ns.endRuleFamilies
-- (shared with the cast rules through ns:CastRuleFamily) until the next SPELLS_CHANGED. The table
-- holds only the rows tagged for this client (MREM-04/05), so the offer needs no flavour gate of its own. Fails closed like the racial offer: a row never read readably is not
-- offered; any known rank offers the row. Rebuilt into a module-level array, never a fresh table.
local metaReminderSuggestionKeys = {}

function ns:MetaReminderSuggestionKeys()
	wipe(metaReminderSuggestionKeys)
	for _, def in ipairs(META_REMINDER_DEFS) do
		if ns:ResolveSpellKnown(def.knownID, false) == true then
			metaReminderSuggestionKeys[#metaReminderSuggestionKeys + 1] = def.key
		end
	end
	return metaReminderSuggestionKeys
end

-- Bag-derived consumables catalogue (ITEM-01/ITEM-08, Phase 46). Keyed by itemID, never by bag
-- and slot -- bag/slot is positional and shifts when stacks split or bags are sorted, so it is
-- only how items are DISCOVERED, not their identity. A duplicated itemID across several bag
-- slots collapses to one catalogue row.
--
-- Five module-level tables, wiped and refilled by ns:RefreshItemCatalogue, never reallocated:
-- itemCatalogueIDs is the final, ascending, admitted list; itemCatalogueIcons/Counts are
-- itemID-keyed side tables; itemCatalogueSeen is scratch-only, used to de-dup the bag walk
-- before classification and carries no meaning once the scan ends; itemUseSpellToID (Phase 47,
-- D-01) is keyed by the item's USE-SPELL ID and holds the itemID, the opposite direction of every
-- other table here. An arriving UNIT_SPELLCAST_SUCCEEDED carries a spellID, not an itemID, and
-- this is what lets MetaItemBagProviderMixin:OnTrigger recognise a landed item use from that spellID
-- alone. Capturing it costs no extra API call: C_Item.GetItemSpell is already called below as half
-- of the ITEM-08 taxonomy filter, and its second return (the use-spell ID) was previously thrown
-- away.
--
-- ns:RefreshTBTSections has eleven call sites and redraws Suggested on every CDM open and after
-- every drag, add, move and delete -- the same lesson ns:IsSuggestedKeyResolvable's memo records
-- for the racial catalogue. The render path must read these tables and never call
-- ns:RefreshItemCatalogue itself; Plan 02 owns the dirty-flag-driven trigger that decides when a
-- rescan actually happens.
local itemCatalogueIDs = {}
local itemCatalogueIcons = {}
local itemCatalogueCounts = {}
local itemCatalogueSeen = {}
local itemCatalogueDirty = true
local itemUseSpellToID = {}

-- itemID -> icon fileID, for items that are TRACKED but not in the player's bags.
--
-- Separate from itemCatalogueIcons on purpose, and not merged into it: that table IS the
-- catalogue, and the Suggested section offers exactly what it holds (ITEM-02). Writing a
-- not-held item's icon into it would make the item offer itself as Suggested for an item the
-- player cannot use -- the phantom tile ns:ItemDisplayInfo's header says it exists to prevent.
-- This table feeds display only, and nothing iterates it.
--
-- Memoised because ns:GetDisplayInfoForKey is on the CDM tab's render path, which redraws on
-- every open and every drag, and the item tile loop's own comment sets the standard: "no
-- C_Container/C_Item call belongs on this render path". One GetItemInfoInstant per distinct
-- tracked-but-unheld itemID per session, and never once for an item that is in the bags.
--
-- `false` is a memoised MISS, distinct from nil meaning "not looked up yet" -- an item the client
-- cannot resolve at all must not be re-asked on every render either.
local itemIconFallback = {}

-- Runtime tracked-item count store (Phase 47, D-03). Keyed by the TRACKER KEY ("metaItem:<itemID>"),
-- not by itemID -- the opposite of itemCatalogueCounts above. Runtime-only and deliberately never
-- persisted, for the same reason ns.cooldownStarts is not: a count drifts while logged out
-- through mail, the bank or an alt, and there is no way to check it while offline.
--
-- Deliberately NOT itemCatalogueCounts: that table is wipe()d and refilled from a live bag walk
-- every rescan and holds NO ENTRY AT ALL for a zero-stock item -- reusing it would silently break
-- ITEM-09 (tile survives the stack reaching zero) the moment a rescan runs. This table is never
-- wiped by ns:RefreshItemCatalogue and is the only correct source for a tracked item's count.
local itemTrackedCounts = {}

-- Rebuilds the consumables catalogue unconditionally and clears the dirty flag. No return value.
-- Never call this from a render path -- see the header comment above.
function ns:RefreshItemCatalogue()
	wipe(itemCatalogueIDs)
	wipe(itemCatalogueIcons)
	wipe(itemCatalogueCounts)
	wipe(itemCatalogueSeen)
	wipe(itemUseSpellToID)

	-- Discovery: every distinct itemID currently held, bag 0 (backpack) through bag 5 (the
	-- retail/Forever reagent bag). Literal integers, not Enum.BagIndex.* -- the literals are
	-- what TBT's own probe measured working on Forever 1.60.1, and Enum.BagIndex's presence on
	-- that client is unproven. A bag the player does not have (e.g. no reagent bag) simply
	-- returns 0 slots, a data-absence condition rather than a flavour branch.
	for bag = 0, 5 do
		-- Guarded like every other API read in this function, and for a sharper reason: this one
		-- is a LOOP BOUND. A secret or nil here raises inside the `for` itself, and the raise
		-- lands after wipe() has already emptied the catalogue but before itemCatalogueDirty is
		-- cleared at the end -- so the catalogue would be left empty AND permanently dirty, and
		-- every following BAG_UPDATE would re-enter and re-raise instead of degrading. Skipping
		-- an unreadable bag loses at most that bag's rows on this pass.
		local numSlots = C_Container.GetContainerNumSlots(bag)
		if issecretvalue(numSlots) or type(numSlots) ~= "number" then
			numSlots = 0
		end
		for slot = 1, numSlots do
			local id = C_Container.GetContainerItemID(bag, slot)
			if not issecretvalue(id) and type(id) == "number" then
				itemCatalogueSeen[id] = true
			end
		end
	end

	-- Classification: taxonomy only, per the locked filter (D-02) -- classID ==
	-- Enum.ItemClass.Consumable (0), subClassID ~= Enum.ItemConsumableSubclass.Bandage (7), and a
	-- use-spell exists. Literal 0/7 for the same Forever-unverified-Enum reason as the bag range
	-- above. No item-name matching anywhere -- it would break on a non-English client.
	for itemID in pairs(itemCatalogueSeen) do
		local _, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
		if
			not issecretvalue(classID)
			and type(classID) == "number"
			and not issecretvalue(subClassID)
			and type(subClassID) == "number"
			and classID == 0
			and subClassID ~= 7
		then
			local _, useSpellID = C_Item.GetItemSpell(itemID)
			-- issecretvalue() BEFORE the truthiness test: a secret non-nil spellID is truthy
			-- under a naive "if useSpellID then", which would admit an item on false evidence.
			if not issecretvalue(useSpellID) and useSpellID then
				itemCatalogueIDs[#itemCatalogueIDs + 1] = itemID

				-- D-01: capture the use-spell -> itemID map here, at no extra API cost -- this
				-- read already happened as half the taxonomy filter above. The surviving value
				-- has only been proven non-secret and truthy so far; MetaItemBagProviderMixin:OnTrigger
				-- compares it against a numeric event spellID, so it is gated on
				-- type() == "number" as well before being trusted as a table key.
				if type(useSpellID) == "number" then
					-- Collision detection (CONTEXT.md leaves this to discretion): two catalogued
					-- items sharing one use-spell is a known, accepted gap -- last writer wins --
					-- but it is cheap to notice, so log it under the existing debug flag rather
					-- than guess. Never surfaces to a user with debug logging off. This is a new,
					-- self-contained print and does not call, extend or relocate Core.lua's
					-- protected debug cast/item log (D-06).
					local occupant = itemUseSpellToID[useSpellID]
					if occupant ~= nil and occupant ~= itemID and ns.debugLogging then
						print(
							"|cff00ccffTBT Debug|r: use-spell "
								.. useSpellID
								.. " collides between item "
								.. occupant
								.. " and item "
								.. itemID
								.. " -- last writer wins."
						)
					end
					itemUseSpellToID[useSpellID] = itemID
				end

				-- Reuse the icon this same GetItemInfoInstant call already returned rather than
				-- a second C_Item.GetItemIconByID call: GetItemInfoInstant's icon is documented
				-- non-nilable once the call succeeds, and the reuse costs zero extra API calls.
				if not issecretvalue(icon) and type(icon) == "number" then
					itemCatalogueIcons[itemID] = icon
				end

				-- The API's own aggregate, not a per-slot sum -- it already de-duplicates across
				-- every bag a stack of this item might be split across.
				local count = C_Item.GetItemCount(itemID)
				if not issecretvalue(count) and type(count) == "number" then
					itemCatalogueCounts[itemID] = count
				end
			end
		end
	end

	-- Ascending, deterministic and locale-free -- itemID order is stable across bag sorts, where
	-- bag-walk order is not, and C_Item.GetItemNameByID can return nothing before an item is
	-- cached, which rules out sorting by name.
	table.sort(itemCatalogueIDs)

	-- B1: the wipe above drops every use-spell entry, including those for TRACKED items. A
	-- tracked item at zero stock is absent from the bag walk entirely (the ITEM-09 case), so
	-- refilling from the bags alone would silently un-register exactly the items that most need
	-- to stay registered. Re-register from ns.db.trackedBuffs, which does not depend on the bags.
	ns:RegisterAllTrackedItemUseSpells()

	itemCatalogueDirty = false
end

-- The catalogue's itemID array, ascending, BY REFERENCE. Callers must iterate, never retain or
-- mutate -- the same contract ns:RacialCooldownKeys() already makes for its own array.
function ns:ItemCatalogue()
	return itemCatalogueIDs
end

-- The cached icon fileID for itemID, or nil when it was unreadable at scan time.
function ns:ItemCatalogueIcon(itemID)
	return itemCatalogueIcons[itemID]
end

-- The cached bag count for itemID, or nil when it was unreadable at scan time.
function ns:ItemCatalogueCount(itemID)
	return itemCatalogueCounts[itemID]
end

-- The tracked count for a "metaItem:<itemID>" tracker key, as a number, or nil when no count has
-- ever been readable for it. Read by Display.lua ONLY. This must never be swapped for
-- ns:ItemCatalogueCount -- see itemTrackedCounts' header comment above for why the two tables
-- are not interchangeable (D-03).
function ns:TrackedItemCount(key)
	return itemTrackedCounts[key]
end

-- Called once, at tracker creation, by AddSuggestedTracker (Plan 02). Seeds the tracked count
-- from a guarded C_Item.GetItemCount and seeds entry.duration / ns.cooldownStarts[key] from a
-- guarded C_Item.GetItemCooldown (D-05). No return value.
-- ns:RegisterTrackedItemUseSpell(itemID)
-- Writes one itemID's use-spell into itemUseSpellToID WITHOUT a bag walk.
--
-- Phase 47 code review, BLOCKER B1. The map was originally filled only by
-- ns:RefreshItemCatalogue, which runs only while Blizzard's Cooldown Manager is open
-- (CDMTab.lua:36 and the ns.configOpen-gated rebuild at :66). That is correct for the SUGGESTED
-- list, which only matters when the CDM is on screen -- but the landed-use decrement has to work
-- all session, whether or not the player ever opens that panel. Without this, a player who never
-- opened the CDM got an empty map, and every use of every tracked item silently failed to
-- decrement its count or refresh the shared cooldown, leaving the combat-end reconcile -- itself
-- combat-gated -- as the only correction. That is the opposite of the locked design, where the
-- decrement is the primary mechanism and the reconcile only absorbs drift.
--
-- A tracked item is already known from ns.db.trackedBuffs, so this needs no bag access at all.
function ns:RegisterTrackedItemUseSpell(itemID)
	if issecretvalue(itemID) or type(itemID) ~= "number" then
		return
	end
	local _, useSpellID = C_Item.GetItemSpell(itemID)
	-- issecretvalue() before the truthiness test, per the locked ordering: a secret non-nil
	-- spellID is truthy under a naive `if useSpellID then` and would poison the map with a key
	-- that can never match an arriving cast.
	if not issecretvalue(useSpellID) and useSpellID then
		itemUseSpellToID[useSpellID] = itemID
	end
end

-- ns:RegisterAllTrackedItemUseSpells()
-- Re-registers every tracked item's use-spell. Called on world entry (so a tracker restored from
-- SavedVariables works before the CDM is ever opened) and at the end of ns:RefreshItemCatalogue
-- (whose wipe would otherwise drop tracked entries for any item no longer in the bags -- exactly
-- the zero-stock case ITEM-09 exists to cover).
function ns:RegisterAllTrackedItemUseSpells()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	for _, entry in pairs(ns.db.trackedBuffs) do
		if ns:IsBagItemEntry(entry) then
			ns:RegisterTrackedItemUseSpell(entry.itemID)
		end
	end
end

function ns:SeedItemTracker(key, itemID, entry)
	if not entry or type(itemID) ~= "number" then
		return
	end

	-- B1: register the use-spell at creation, so a newly dragged tracker decrements from its very
	-- first use without waiting on a catalogue rescan.
	ns:RegisterTrackedItemUseSpell(itemID)

	-- issecretvalue() BEFORE type(): the locked ordering (T-47-01). A legitimate 0 is a real
	-- answer and must be stored; an unreadable count leaves the key absent so the tile shows no
	-- number rather than a wrong one.
	local count = C_Item.GetItemCount(itemID)
	if not issecretvalue(count) and type(count) == "number" then
		itemTrackedCounts[key] = count
	end

	-- D-05: seed the cooldown too. Creation is the ONE place the degrade rule kept by
	-- ns:RefreshTrackedItemCooldowns below does NOT apply -- a freshly created tracker has no
	-- stamp worth preserving, and a stale ns.cooldownStarts[key] left behind by a previously
	-- deleted tracker of the same itemID would otherwise produce a phantom sweep on this new one.
	-- issecretvalue() before type() on start/duration, and before the truthiness test on enable --
	-- its documented type differs between C_Item and C_Container, so a strict `== true` is wrong.
	local start, duration, enable = C_Item.GetItemCooldown(itemID)
	local readableStart = not issecretvalue(start) and type(start) == "number"
	local readableDuration = not issecretvalue(duration) and type(duration) == "number"
	local readableEnable = not issecretvalue(enable) and enable
	if readableStart and readableDuration and readableEnable and duration > 0 then
		entry.duration = duration
		ns.cooldownStarts[key] = start
	else
		-- Unreadable, disabled, or zero-duration: not an error, "not on cooldown right now" --
		-- but unlike ns:RefreshTrackedItemCooldowns' degrade rule, a brand-new tracker has no
		-- prior stamp to preserve, so clearing here is correct and entry.duration stays at the 0
		-- ns:ItemDisplayInfo already gave it.
		ns.cooldownStarts[key] = nil
	end
end

-- Re-reads C_Item.GetItemCooldown for EVERY tracked item entry and re-stamps it (D-02, D-04).
-- One read per tracked item, not only the item just used -- this is the entire mechanism behind
-- ITEM-05 (a shared cooldown shows up for free), with no spell-category table. Not combat-gated:
-- PATTERNS.md section 8 is explicit that only the count reconcile below is. Allocates nothing;
-- iterates in place. No return value.
function ns:RefreshTrackedItemCooldowns()
	if not ns.db or not ns.db.trackedBuffs then
		return
	end
	for key, entry in pairs(ns.db.trackedBuffs) do
		if ns:IsBagItemEntry(entry) then
			-- issecretvalue() before type()/truthiness -- the same ordering as ns:SeedItemTracker
			-- above, and the worked example this whole project cites (Providers.lua ~line 970).
			local start, duration, enable = C_Item.GetItemCooldown(entry.itemID)
			local readableStart = not issecretvalue(start) and type(start) == "number"
			local readableDuration = not issecretvalue(duration) and type(duration) == "number"
			local readableEnable = not issecretvalue(enable) and enable
			if readableStart and readableDuration and readableEnable and duration > 0 then
				entry.duration = duration
				ns.cooldownStarts[key] = start
			end
			-- On ANY other outcome, leave both exactly as they were -- never clear, never zero,
			-- never error. A zero/unreadable duration means "not on cooldown right now", not an
			-- error, and the existing stamp expires on its own clock inside ApplyUserCooldown
			-- (Display.lua) -- clearing it here is what would break ITEM-09.
		end
	end
end

-- Reconciles every tracked item's count against C_Item.GetItemCount and prunes orphaned keys
-- (D-03). Combat-gated internally, so callers may call it unconditionally from any branch. No
-- return value.
function ns:ReconcileTrackedItemCounts()
	if InCombatLockdown() then
		return
	end
	if not ns.db or not ns.db.trackedBuffs then
		return
	end

	for key, entry in pairs(ns.db.trackedBuffs) do
		if ns:IsBagItemEntry(entry) then
			local count = C_Item.GetItemCount(entry.itemID)
			if not issecretvalue(count) and type(count) == "number" then
				itemTrackedCounts[key] = count
			end
			-- Unreadable: leave the existing value. It is a real answer from a moment the API
			-- could answer, and is a better guess than discarding it on a transient failure.
		end
	end

	-- Prune: a key with no corresponding entry in ns.db.trackedBuffs is what keeps a
	-- deleted-and-re-added tracker from inheriting a stale count. Clearing an existing field
	-- during a pairs traversal of that same table is permitted.
	for key in pairs(itemTrackedCounts) do
		if not ns.db.trackedBuffs[key] then
			itemTrackedCounts[key] = nil
		end
	end

	-- Unconditional: without this the reconcile is invisible -- the render path's
	-- generation-gated block only re-runs when this fires, so the corrected number would never
	-- actually reach the tile.
	ns:MarkCooldownsDirty()
end

-- Sets the dirty flag and returns. Does no scanning work itself -- CDMTab.lua's coalescing
-- consumer (ns:RequestItemCatalogueRebuild) owns deciding when a rescan actually runs. Guarded:
-- CDMTab.lua loads after this file, so the field is nil until it runs; the guard is what makes
-- this file order-independent rather than assuming load order stays fixed.
function ns:MarkItemCatalogueDirty()
	itemCatalogueDirty = true
	if ns.RequestItemCatalogueRebuild then
		ns:RequestItemCatalogueRebuild()
	end
end

-- Whether the catalogue needs a rescan before its next read. Read by Plan 02's coalescing
-- consumer.
function ns:IsItemCatalogueDirty()
	return itemCatalogueDirty
end

-- itemID -> a pooled { icon, label, duration, spellID } table, the same shape every other
-- provider's GetDisplayInfo returns, or nil when itemID is not (or no longer) in the catalogue --
-- neither the icon nor the count accessor has an entry for it -- so a "metaItem:" key for an item
-- the player no longer holds resolves to nil rather than a phantom tile.
--
-- spellID is always nil and duration is always 0: an itemID is not a spellID, and Phase 46 reads
-- no item cooldowns (that is Phase 47's work). Leaving spellID nil is what makes
-- ns:ShowBuffTooltip's type(proc.spellID) == "number" test correctly decline SetSpellByID.
--
-- Pooled via ns:AcquireDisplayInfo, never a fresh table -- this is on the render and hover path,
-- same as UserSpellProviderMixin:GetDisplayInfo above. displayInfoPool (BuffEngine.lua) gains one
-- entry per distinct itemID ever catalogued -- bounded by the player's distinct consumables, tens
-- at most.
function ns:ItemDisplayInfo(itemID)
	local icon = ns:ItemCatalogueIcon(itemID)
	local count = ns:ItemCatalogueCount(itemID)

	-- Reported 2026-09-24: a TRACKED item the character does not hold drew the 134400 question
	-- mark on the CDM tab while its cooldown icon drew correctly. Both halves of that are
	-- explained by the same line -- CDMTab.lua:189-194 -- which stores entry.iconOverride at
	-- creation precisely because "ApplyCachedIcon reads entry.iconOverride straight off the DB
	-- entry and NEVER re-derives it". Display therefore had a stored answer and the tab did not;
	-- the tab re-derives through here, and here read the bag catalogue and nothing else.
	--
	-- Fixed at the source rather than by teaching the tab about iconOverride, because every other
	-- consumer of this function has the same gap: the drag ghost (CDMTab.lua:592), the delete
	-- confirmation, and any future one. An itemID's icon is a static property of the item, not of
	-- whether it is in a bag, so the catalogue was simply the wrong and narrower source.
	--
	-- ITEM-09 is the requirement this restores in the UI: "a tracked item keeps its tile after
	-- the stack reaches zero and the item leaves the player's bags". The tile kept its slot, but
	-- it lost its face.
	if icon == nil then
		local cached = itemIconFallback[itemID]
		if cached == nil then
			-- GetItemInfoInstant returns (itemID, type, subType, equipLoc, icon, classID,
			-- subClassID) -- icon is the fifth, and this is the same call and the same unpacking
			-- ns:RefreshItemCatalogue already uses. "Instant" is load-bearing: it answers from
			-- the client's own cache with no server round trip, so it cannot stall a render.
			local _, _, _, _, instantIcon = C_Item.GetItemInfoInstant(itemID)
			-- issecretvalue() BEFORE type(), the locked ordering, as everywhere else here.
			if not issecretvalue(instantIcon) and type(instantIcon) == "number" then
				cached = instantIcon
			else
				cached = false
			end
			itemIconFallback[itemID] = cached
		end
		if cached then
			icon = cached
		end
	end

	-- Unchanged in meaning: an item with no icon from EITHER source and no count is one this
	-- client knows nothing about, and still resolves to nil rather than a phantom tile.
	if icon == nil and count == nil then
		return nil
	end

	local info = ns:AcquireDisplayInfo(META_ITEM_PREFIX .. itemID)
	info.icon = icon or 134400

	-- issecretvalue() BEFORE type(): the locked ordering. An unreadable name degrades to the
	-- placeholder label rather than erroring -- an item can legitimately have no cached name yet.
	local name = C_Item.GetItemNameByID(itemID)
	if not issecretvalue(name) and type(name) == "string" then
		info.label = name
	else
		info.label = "Item " .. tostring(itemID)
	end

	info.duration = 0
	info.spellID = nil
	return info
end

-- Granting-cast procs deliberately carry no cancellation-list field: the Eureka! aura is
-- unreadable under restriction, and ns:ScanActiveTimersForCancellation skips any proc whose
-- cancellation list is absent or empty, so this proc is excluded from cancellation by
-- construction rather than by a guard. Do not add one "for consistency" with Trinket/Pot/Lust.
--
-- The nominal duration is the backstop, not a fallback: expiresAt is written once at grant time
-- and never touched again, so ns:GetActiveTimers' existing lazy-expiry loop always closes the
-- window even if not a single cast ever spends a stack. Early expiry (RACE-03) is a removal via
-- ns:EndTimer, never a shortening of expiresAt — neither ending knows about the other.
local MetaSkillRacialProviderMixin = {}

function MetaSkillRacialProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA" }
end

-- Module-level aliases taken once at load. Nil on a client lacking them, which the qualifying
-- test below treats as "unknown".
local IsSpellHarmful = C_Spell.IsSpellHarmful
local IsAutoAttackSpell = C_Spell.IsAutoAttackSpell

-- Is this character a priest? Sticky, session-long, and resolved lazily rather than at load,
-- exactly like racialRaceIDMemo above and for the same reason: a character's class cannot change
-- mid-session, so a readable answer is safe to keep forever, but an EARLY UNREADABLE READ MUST NOT
-- POISON THE MEMO. Only a real string is remembered; anything else re-asks on the next call.
--
-- UnitClass("player")'s second return is the class token, which is the same read
-- MetaSkillLustProviderMixin:GetDisplayInfo already uses for its own class map. issecretvalue before
-- type(), the locked ordering.
local playerClassMemo

local function PlayerIsPriest()
	if playerClassMemo == nil then
		local _, classFilename = UnitClass("player")
		if issecretvalue(classFilename) or type(classFilename) ~= "string" then
			-- Unknown THIS CALL. Returning true follows the same rule the harmful test below
			-- follows: unknown qualifies, because under-consuming leaves a buff on screen the
			-- player no longer has and over-consuming merely ends the tracker early.
			return true
		end
		playerClassMemo = classFilename
	end
	return playerClassMemo == "PRIEST"
end

-- Does this cast spend a Eureka! stack? Gnome Eureka! is the only consumer -- maxStacks is set on
-- exactly one row of RACIAL_SPELLS, ConsumeRacialStack only reaches a proc that HAS stacks, and
-- the granting cast is matched and returned by OnTrigger before this is ever called, so a racial
-- can never spend a stack on itself.
--
-- THE HARMFUL TEST IS PER-CLASS, and the class list is the ability's own tooltip:
--
--   rogue, mage, warlock, warrior -> "your next 3 DAMAGING abilities"
--   priest                        -> "your next 3 damaging OR HEALING abilities"
--
-- So a gnome priest was the one case the harmful gate got wrong: a heal reads harmful == false,
-- declined to spend, and the tile sat at 3 charges through a healing rotation that was really
-- burning them. Reported by the user 2026-09-25, fixed by skipping the gate for priests ONLY --
-- the gate itself stays for every other class and must not be removed. It was briefly removed
-- outright on a misreading of the instruction, and restored the same day.
--
-- Accepted over-consumption, recorded so it is never re-opened (user accepted 2026-09-20):
-- IsSpellHarmful means "can target an enemy", not "deals damage" -- Frost Nova and Polymorph will
-- spend a stack the game did not. Unknown (missing API, secret result) deliberately qualifies
-- too: under-consuming would leave a stale buff on screen, which is the worse failure mode. Do
-- not add a damage-spell allow-list or a school check.
--
-- Auto-attack is excluded for every class, priest included. It is not an ability the player casts
-- and it fires UNIT_SPELLCAST_SUCCEEDED continuously, so admitting it would drain all three stacks
-- within a swing or two of the grant.
local function CastSpendsStack(spellID)
	-- A priest's Eureka! spends on healing too, so the harmful question does not apply to one.
	if IsSpellHarmful and not PlayerIsPriest() then
		local harmful = IsSpellHarmful(spellID)
		if not issecretvalue(harmful) and harmful == false then
			return false
		end
	end
	if IsAutoAttackSpell then
		local autoAttack = IsAutoAttackSpell(spellID)
		if not issecretvalue(autoAttack) and autoAttack == true then
			return false
		end
	end
	return true
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit (string), castGUID (string), spellID (number).
-- Hot-path budget: on a character with no mapped racial, or on the common cast where no racial
-- window is open, this returns after a memoised local read, a nil test and a table index — zero
-- API calls. The two C_Spell calls above happen only while a live racial proc WITH STACKS exists
-- and the cast is not the granting cast, so a stackless racial (Berserking) never reaches them.
-- Starts a fresh racial proc for one slot, at the def's duration and -- when it has one -- its
-- stack count. Returns nil when that racial has no tracker, or its tracker is hidden.
--
-- Split out of OnTrigger when the second slot arrived: the granting path is identical for every
-- racial and differs only in which key and def it is handed, so writing it once is what keeps a
-- second racial from being a second copy of it.
local function StartRacialProc(key, def)
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
	if not entry or entry.section == "hidden" then
		return nil
	end
	-- Four collected racials apply no aura at all (undead Will of the Forsaken, human Will to
	-- Survive, tauren War Stomp and Cultivation), so def.duration is nil for them and
	-- `now + def.duration` would raise on their first cast. A cooldown-only racial surfaces as its
	-- "metaSkillCd:<spellID>" tile and nothing else. A row marked indefinite (D-6: Shadowmeld, Find
	-- Treasure, Plainsrunning) has no duration ON PURPOSE and must be let through -- it is not the
	-- cooldown-only case, it has no meaningful duration at all.
	if not def.duration and not def.indefinite then
		return nil
	end

	-- A clearOnCombat racial cast IN combat starts no buff proc at all.
	--
	-- Reported from the Alliance gate pass, 2026-09-25: Shadowmeld used in combat is a threat
	-- drop, and the stealth it would normally show either does not apply or cannot be tracked
	-- reliably -- so the honest tile is no tile. Its cooldown tile still fires, because that is a
	-- separate "metaSkillCd:<spellID>" tracker started by the dispatcher, not by this function.
	--
	-- That tile does NOT read the live game handle -- a claim this comment used to make, and which
	-- cost a second bug report: ApplyUserCooldown draws a cooldown tracker from its own duration
	-- and never asks the engine, so the in-combat tile ran Shadowmeld's ten-second number while the
	-- real ability had two minutes left. `combatCooldown` on the def and ns:ConditionalCooldown
	-- are what actually make the longer cooldown fire.
	--
	-- Without this, the proc started anyway and then could not be cleared: aura reads are secret in
	-- combat, so the cancellation scan correctly refuses to conclude "absent" from an unreadable
	-- result, and an indefinite proc has no expiry to fall back on. The tile therefore survived
	-- until combat ended and then lingered -- exactly what the user observed.
	--
	-- Gated on clearOnCombat, NOT on indefinite: Find Treasure is indefinite too and legitimately
	-- survives combat. The flag already means "this racial cannot exist in combat", which is the
	-- same claim being made here at the other edge.
	if def.clearOnCombat and InCombatLockdown() then
		return nil
	end

	local now = GetTime()
	-- Pooled and WIPED, which matters more here than anywhere else: this proc carries "stacks"
	-- and deliberately carries no "aliveBuffs" unless a def below asks for one, so a reused table
	-- that was not cleared could hand the cancellation scan a list this tracker never meant to have.
	local proc = ns:AcquireProc(key)
	proc.key = key
	proc.spellID = def.spellID
	proc.startedAt = now
	if def.indefinite then
		-- 49-04/D-6: no natural end, so duration/expiresAt carry only the 86400s backstop.
		-- proc.indefinite is what both render paths and the expiry sweep branch on; the backstop
		-- keeps any OTHER arithmetic on these fields (e.g. a caller unaware of the flag) safe.
		proc.indefinite = true
		proc.duration = ns.INDEFINITE_DURATION
		proc.expiresAt = now + ns.INDEFINITE_DURATION
	else
		proc.duration = def.duration
		proc.expiresAt = now + def.duration -- backstop: written once, never touched again.
		-- proc.indefinite left unset: ns:AcquireProc wipes, so it reads nil and cannot inherit a
		-- previous cast's true.
	end
	proc.section = entry.section or "bars"
	proc.layoutOrder = entry.layoutOrder
	proc.label = def.label
	proc.stacks = def.maxStacks
	-- EVERY racial buff proc is aura-cancelled. User decision, 2026-09-25: "all racial buffs should
	-- support the aura clear."
	--
	-- This replaced a per-row `cancelOnAuraLoss` opt-in, and the opt-in was the wrong shape rather
	-- than merely incomplete: it made "does this racial end when its buff ends" a property somebody
	-- had to remember to set, so each racial whose buff can end early -- Walk on Air on touching
	-- the ground, then Skysight -- surfaced as its own separate bug report. A racial buff ending
	-- when its aura ends is the DEFAULT, not a feature a row opts into.
	--
	-- Safe for every row, including the ones that previously did not opt in, because of two
	-- properties that already hold:
	--   * ns:ScanActiveTimersForCancellation never concludes "absent" from an UNREADABLE read, so
	--     a racial used in combat (auras secret) simply runs its nominal duration exactly as
	--     before. Nothing regresses in combat.
	--   * `def.auraID or def.spellID` is correct for all 21 rows: every racial whose aura ID
	--     differs from its cast ID carries auraID explicitly -- Cannibalize 20577/20578, Read Ley
	--     Line 1259705/1270842, Skysight 1259686/1259688 -- verified before this was widened.
	--     Widening it WITHOUT that guarantee would cancel those three instantly, since a read for
	--     the cast ID would correctly report no such aura.
	proc.aliveBuffs = ns:AcquireAliveBuffs(key, def.auraID or def.spellID)
	return proc
end

-- Spends a stack on whichever racial is live, if this cast qualifies. Reads the proc from
-- ns.activeTimers directly; the granting path does not write it -- the dispatcher's existing
-- re-assign does that. Phase 57.3: walks only the tracked, loaded racials (ns.racialDefsActive),
-- so an untracked or unloaded racial costs nothing per cast.
local function ConsumeRacialStack(spellID)
	for _, def in ipairs(ns.racialDefsActive) do
		local key = def.key
		local proc = ns.activeTimers and ns.activeTimers[key]
		if proc and proc.stacks ~= nil and proc.expiresAt > GetTime() then
			if CastSpendsStack(spellID) then
				-- proc.stacks is TBT's own cast-derived integer, never a game value -- it needs
				-- no issecretvalue guard, unlike every WoW API value elsewhere in this file. Do
				-- not add one "for consistency".
				proc.stacks = proc.stacks - 1
				if proc.stacks <= 0 then
					ns:EndTimer(key)
					return nil
				end
				-- Return the proc itself so the dispatcher's existing
				-- ns.activeTimers[proc.key] = proc re-assign and ns:UpdateDisplay() run with no
				-- new dispatcher branch.
				return proc
			end
		end
	end
	return nil
end

-- The stack count carried by an aura-driven racial's own aura, or nil to draw no number.
--
-- Plainsrunning ramps, and that count is the information the buff exists to convey -- reported by
-- the user 2026-09-25 as the one thing missing after the Horde gate pass. Nothing is needed on the
-- render side: proc.stacks is already what both paths draw (Display.lua, the bar and icon stack
-- blocks), dirty-checked against _stacks.
--
-- THIS STACK COUNT IS A GAME VALUE, WHICH EUREKA!'S IS NOT, and the distinction matters. Eureka!'s
-- proc.stacks is TBT's OWN cast-derived integer -- seeded from def.maxStacks and decremented by
-- ConsumeRacialStack -- precisely because the aura APIs cannot be read under restriction. This one
-- is re-read from the aura instead, which is only possible because an aura-driven racial is
-- inherently an out-of-combat one: Plainsrunning drops the instant combat starts, so the moment
-- the read would fail is the moment there is nothing to read. Do not "unify" the two.
--
-- applications == 0 is Blizzard's answer for a NON-stacking aura, so it maps to nil (draw nothing)
-- rather than to a literal "0"; only a genuinely stacking aura reaches 1 or more.
--
-- Takes the already-fetched aura table rather than a def, so the caller's existing
-- ns:ReadPlayerAura result is reused and no second read happens per event.
local function AuraStackCount(aura)
	local applications = aura.applications
	-- issecretvalue BEFORE type(), the addon-wide ordering: type() reports the underlying type for
	-- a secret value, so testing it first proves nothing.
	if issecretvalue(applications) or type(applications) ~= "number" or applications < 1 then
		return nil
	end
	return applications
end

-- 49-04/D-2/D-3: the racial UNIT_AURA handler. Two unrelated jobs share it because both are
-- "look at the player's own aura outside the cast stream": starting Plainsrunning, which has no
-- cast to key off (D-2), and correcting a Skyborne second racial's duration upward once the long
-- version is detectable out of combat (D-3). Declared here, between StartRacialProc (above) and
-- OnTrigger (below), because a file-local is an upvalue only to functions declared AFTER it --
-- this project has shipped that exact bug five times.
--
-- Hot path: UNIT_AURA fires constantly on the player unit. Phase 57.3: the loop walks only the
-- tracked, loaded racials (ns.racialDefsActive), usually zero to two entries, so an untracked or
-- unloaded racial costs nothing per event. Most racials have neither startFromAura nor
-- longDuration, so the interest test is still the FIRST thing this loop does, before any string
-- concatenation or API call.
local function RacialAuraTrigger()
	for _, def in ipairs(ns.racialDefsActive) do
		if def.startFromAura or def.longDuration then
			local key = def.key
			local proc = ns.activeTimers and ns.activeTimers[key]

			if def.startFromAura and not proc then
				-- D-2: Plainsrunning has no cast at all, so its proc starts from the aura being
				-- PRESENT rather than a granting cast. InCombatLockdown() precedes the read:
				-- aura reads are secret in combat for a tainted caller, so the read cannot
				-- succeed there and must not be attempted per event.
				if not InCombatLockdown() then
					local aura, readable = ns:ReadPlayerAura(def.auraID or def.spellID)
					if readable and aura then
						-- StartRacialProc already applies the "no tracker / tracker hidden"
						-- rejects, so no second check is needed here.
						local started = StartRacialProc(key, def)
						if started then
							-- Seeded from the aura TBT already holds, so the stack number is
							-- right on the very first frame the tile appears rather than only
							-- after the next UNIT_AURA. StartRacialProc set this from
							-- def.maxStacks, which is nil for an aura-driven racial.
							started.stacks = AuraStackCount(aura)
						end
						return started
					end
				end
			elseif def.startFromAura and proc and not InCombatLockdown() then
				-- The proc already exists, so the only thing left to track is the count moving.
				-- UNIT_AURA fires on a stack change, so re-reading here is what makes a ramping
				-- Plainsrunning show 1, 2, 3 rather than freezing at whatever it started on.
				--
				-- Returns the proc ONLY when the number actually changed: the dispatcher's
				-- re-assign and ns:UpdateDisplay() run on a non-nil return, and UNIT_AURA fires
				-- far more often than the stack moves.
				local aura, readable = ns:ReadPlayerAura(def.auraID or def.spellID)
				if readable and aura then
					local stacks = AuraStackCount(aura)
					if stacks ~= proc.stacks then
						proc.stacks = stacks
						return proc
					end
				end
			elseif def.longDuration and proc and not InCombatLockdown() then
				-- D-3: a Skyborne second racial always starts on the SHORT duration; out of
				-- combat only, correct UPWARD when the aura's real duration reads longer. A
				-- racial that under-runs is recoverable; one hanging fourteen minutes past its
				-- buff is not -- so a shorter (or unreadable) read is discarded, never applied.
				local aura, readable = ns:ReadPlayerAura(def.auraID or def.spellID)
				if readable and aura then
					-- GetAuraAppliedAt's exact guard order: issecretvalue on both fields first.
					local duration, expirationTime = aura.duration, aura.expirationTime
					if not issecretvalue(duration) and not issecretvalue(expirationTime) then
						if type(duration) == "number" and duration > 0 and duration > proc.duration then
							proc.duration = duration
							if type(expirationTime) == "number" and expirationTime > 0 then
								proc.expiresAt = expirationTime
							else
								proc.expiresAt = proc.startedAt + duration
							end
							-- Return the proc so the dispatcher's existing
							-- ns.activeTimers[proc.key] = proc re-assign and ns:UpdateDisplay()
							-- run with no new dispatcher branch.
							return proc
						end
					end
				end
			end
		end
	end
	return nil
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit (string), castGUID (string, arg3), spellID (number,
-- arg4). Args from UNIT_AURA: unit (string), updateInfo (table, arg3), arg4 unused. Renamed from
-- (_, spellID) so both event shapes are legible from the signature alone.
function MetaSkillRacialProviderMixin:OnTrigger(event, unit, arg3, arg4)
	if unit ~= "player" then
		return nil
	end
	if event == "UNIT_AURA" then
		return RacialAuraTrigger()
	end
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	local spellID = arg4
	if type(spellID) ~= "number" then
		return nil
	end

	-- Granting cast first, across the tracked, loaded racials (Phase 57.3: ns.racialDefsActive, so
	-- an untracked or unloaded racial costs nothing per cast). Nothing branches on how many racials
	-- a character has.
	for _, def in ipairs(ns.racialDefsActive) do
		if spellID == def.spellID then
			-- The same cast cannot also be another racial, and a racial cast never spends a stack
			-- on itself, so this is terminal either way.
			return StartRacialProc(def.key, def)
		end
	end

	-- A racial cast never spends a stack, tracked or not (review WR-02): before 57.3 the loop above
	-- walked every racial of the race, so an untracked own racial (Escape Artist with only Eureka!
	-- tracked) was terminal there. One map read keeps that rule without walking every racial.
	if ns:IsRacialSpellID(spellID) then
		return nil
	end

	-- Otherwise it may be a consuming cast for a live stack-driven racial.
	return ConsumeRacialStack(spellID)
end
-- Memoised display-info table, built at most once per spellID, never a fresh table.
-- RenderIconContainer/RenderBarContainer call ns:GetDisplayInfoForKey on the placeholder path
-- every frame (CLAUDE.md forbids hot-path allocation). The returned table is shared and must not
-- be mutated by callers.
-- One table per SPELLID now, not per slot -- RACE-10 replaced the two fixed slots with one entry
-- per racial, so the memo key follows the same shape.
local racialDisplayInfo = {}

-- knownSpellID (optional): a tracked entry's own numeric spellID, passed by ns:GetDisplayInfoForKey
-- so the per-tick placeholder draw never parses the key (IN-02). Untracked keys (a Suggested tile,
-- a drag ghost) omit it and fall back to parsing.
function MetaSkillRacialProviderMixin:GetDisplayInfo(key, knownSpellID)
	local spellID = knownSpellID or ns:RacialKeySpellID(key)
	if not spellID then
		return nil
	end
	if racialDisplayInfo[spellID] then
		return racialDisplayInfo[spellID]
	end
	local def = ns:RacialDefForSpellID(spellID)
	if not def then
		-- RACE-10: there is no generic racial slot to place-hold any more. A key that does not
		-- resolve to any racial (Phase 57.3: of any race; unknown ones show greyed, not nil) --
		-- e.g. a Forever-only racial on retail -- returns nil and the caller's existing nil
		-- handling runs, which is correct, not a gap.
		return nil
	end
	racialDisplayInfo[spellID] = {
		icon = ns:GetSpellIcon(def.spellID),
		label = def.label,
		duration = def.duration,
		spellID = def.spellID,
		stacks = def.maxStacks,
	}
	return racialDisplayInfo[spellID]
end

-- MetaSkillRacialProviderMixin:HasResolvableCatalog is gone. RACE-01's override existed so ONE greyed
-- generic racial tile could appear on both clients; RACE-10 deletes that tile, and
-- ns:IsSuggestedKeyResolvable only ever reaches a provider's HasResolvableCatalog through
-- keyToProvider below, from which the racial rows are also removed -- so the override became
-- unreachable. The base SpellProviderBaseMixin:HasResolvableCatalog (returns true) is untouched
-- and still applies to every other provider.

local MetaSkillRacialProvider = CreateFromMixins(SpellProviderBaseMixin, MetaSkillRacialProviderMixin)

-- Build the concrete UserSpellProvider by merging base + concrete mixins.
-- CreateFromMixins produces a flat copy; no metatable, no shared state between instances (PITFALL-7 GC-safe).
local UserSpellProvider = CreateFromMixins(SpellProviderBaseMixin, UserSpellProviderMixin)

-- MetaItemBagProviderMixin (Phase 47, D-01) -- ties a landed UNIT_SPELLCAST_SUCCEEDED to the item
-- tracking runtime state built earlier in this file (itemUseSpellToID, itemTrackedCounts,
-- ns:RefreshTrackedItemCooldowns). No hook of any kind is registered anywhere in this phase: the
-- four item-use hooks were measured firing on the button press rather than the landed use and are
-- rejected on the production path (D-01).
local MetaItemBagProviderMixin = {}

function MetaItemBagProviderMixin:GetEventInterests()
	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

-- Args from UNIT_SPELLCAST_SUCCEEDED: unit (string), castGUID (string), spellID (number).
--
-- EVERY PATH RETURNS NIL, UNCONDITIONALLY (T-47-04). ns:DispatchEventToProviders is the single
-- writer of ns.activeTimers for cast-triggered procs and performs NO VALIDATION on what a
-- provider returns (see its own design note below: `if proc then ns.activeTimers[proc.key] =
-- proc end`). An item tracker has no buff side, no duration to hand-maintain and no
-- ns.activeTimers entry at all -- a truthy return here would create a phantom timer that renders
-- as a buff. Do not construct a proc table here. Do not call the proc-pool acquire helper.
function MetaItemBagProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		return nil
	end
	if unit ~= "player" then
		return nil
	end
	if type(spellID) ~= "number" then
		return nil
	end

	-- The lookup that keeps an ordinary player cast cheap: one hash lookup and nothing else.
	-- This MUST come before any table walk (hot-path rule) -- the walk over
	-- ns.db.trackedBuffs lives in ns:RefreshTrackedItemCooldowns, reached only past this point.
	local itemID = itemUseSpellToID[spellID]
	if itemID == nil then
		return nil
	end

	-- Past this point the cast IS a landed use of a catalogued item (D-01).
	local key = META_ITEM_PREFIX .. itemID
	if ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key] then
		-- Decrement only when a count is already present -- a nil count means "never readable",
		-- and turning that into 0 would assert something the addon does not know. Clamped at
		-- zero below so the count can never go negative (D-03).
		local current = itemTrackedCounts[key]
		if current ~= nil then
			itemTrackedCounts[key] = math.max(0, current - 1)
		end
	end

	-- Re-read and re-stamp EVERY tracked item's cooldown, not only the one just used -- the whole
	-- of ITEM-05 (D-02, D-04). The stamp taken at this moment is also what keeps a zero-stock
	-- item's sweep running for ITEM-09.
	ns:RefreshTrackedItemCooldowns()
	ns:MarkCooldownsDirty()

	return nil
end

local MetaItemBagProvider = CreateFromMixins(SpellProviderBaseMixin, MetaItemBagProviderMixin)

-- Provider registry, one row per kind served (53-CONTEXT "Parsers and constants" — provider names
-- follow the scheme):
--   MetaItemTrinketProvider  -- ns.META_KEY.TRINKET (metaItem)
--   MetaItemPotProvider      -- ns.META_KEY.POT (metaItem)
--   MetaSkillLustProvider    -- ns.META_KEY.LUST (metaSkill)
--   MetaSkillRacialProvider  -- ns.KIND.META_SKILL, per-spellID (dynamic; not in keyToProvider)
--   MetaItemBagProvider      -- ns.KIND.META_ITEM bag items, per-itemID (dynamic; never a proc)
--   UserSpellProvider        -- ns.KIND.USER_BUFF, ns.KIND.USER_CD, ns.KIND.META_SKILL_CD, and
--                               both reminder kinds (USER_REMINDER, META_REMINDER -- Phase 57.4)
ns.providers = {
	MetaItemTrinketProvider,
	MetaItemPotProvider,
	MetaSkillLustProvider,
	MetaSkillRacialProvider,
	MetaItemBagProvider,
	UserSpellProvider,
}

-- D-08/D-09/D-10/D-11: Key-to-provider dispatch map for ns:GetDisplayInfoForKey.
-- LOCAL to Providers.lua by design (D-09) — future meta-providers update the map here,
-- not at call sites. O(1) lookup, no iteration (D-10). No OwnsKey method on base mixin (D-11).
-- Racial keys are NOT here: RACE-10 replaced the two fixed "racial"/"racial2" slots with a
-- per-spellID key, and a per-spellID key is dynamic, so it cannot live in a static map of fixed
-- meta strings. Recognised directly inside ns:GetDisplayInfoForKey below instead, the same way
-- "metaItem:<itemID>" keys are.
local keyToProvider = {
	[ns.META_KEY.TRINKET] = MetaItemTrinketProvider,
	[ns.META_KEY.POT] = MetaItemPotProvider,
	[ns.META_KEY.LUST] = MetaSkillLustProvider,
}

-- META-01 (D-10): memoises ns:IsSuggestedKeyResolvable answers per key, for the lifetime of the
-- session. Module-local — never exported.
local catalogResolvable = {}

-- ns:GetDisplayInfoForKey(key)
-- Returns { icon, label, duration, spellID } for any provider key, or nil if unresolvable.
-- Callers read the subset of fields they need; the full shape is returned unconditionally.
-- Order: (a) every tracker key is a string now, so a non-string key cannot be one; (b) the fixed
-- meta keys (metaItem:trinket, metaItem:pot, metaSkill:lust) route via keyToProvider with no
-- parse; (c) a TRACKED entry dispatches on its own kind, also with no parse -- this is what keeps
-- the render path (placeholders call this every tick) parse-free for anything already tracked,
-- and a bag item never reaches the spell provider (46-RESEARCH.md Pitfall 4 guard preserved: an
-- itemID is never treated as a spellID); (d) an UNTRACKED key (a Suggested tile, a drag ghost)
-- falls back to parsing its own kind; (e) otherwise nil, which covers the runtime-only "cdm:"
-- (MergeMode) and "__tbt_example__" keys -- never saved, left unrenamed per 53-CONTEXT discretion.
function ns:GetDisplayInfoForKey(key)
	if type(key) ~= "string" then
		return nil
	end
	local p = keyToProvider[key]
	if p then
		return p:GetDisplayInfo(key)
	end
	local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
	if entry then
		local kind = entry.trackerType
		-- Phase 57.2: a user reminder shows the same icon, name and tooltip as a user buff, so it
		-- dispatches here too, and so does the built-in class-buff reminder (Phase 57.4,
		-- ns.KIND.META_REMINDER): it is a spell-keyed reminder with no provider of its own.
		if
			kind == ns.KIND.USER_BUFF
			or kind == ns.KIND.USER_CD
			or kind == ns.KIND.META_SKILL_CD
			or kind == ns.KIND.USER_REMINDER
			or kind == ns.KIND.META_REMINDER
		then
			return UserSpellProvider:GetDisplayInfo(key)
		end
		if kind == ns.KIND.META_SKILL then
			local spellID = entry.spellID
			return MetaSkillRacialProvider:GetDisplayInfo(key, type(spellID) == "number" and spellID or nil)
		end
		if ns:IsBagItemEntry(entry) then
			return ns:ItemDisplayInfo(entry.itemID)
		end
	end
	local itemID = ns:ItemKeyItemID(key)
	if itemID then
		return ns:ItemDisplayInfo(itemID)
	end
	local racialSpellID = ns:RacialKeySpellID(key)
	if racialSpellID then
		return MetaSkillRacialProvider:GetDisplayInfo(key)
	end
	if ns:SpellKeySpellID(key) then
		return UserSpellProvider:GetDisplayInfo(key)
	end
	return nil
end

-- ns:IsSuggestedKeyResolvable(key)
-- META-01 (D-09/D-10): answers whether a Suggested-section key is worth rendering on this
-- client. ns:RefreshTBTSections has eleven call sites and redraws the Suggested section on
-- every CDM open and after every drag, so the catalog walk must happen once per key for the
-- session and the render path must only read this cache. The first call can only arrive from
-- a user-triggered CDM open, long after PLAYER_ENTERING_WORLD, so the client's spell data is
-- fully loaded by then and a sticky one-shot answer is safe — no invalidation hook is added.
function ns:IsSuggestedKeyResolvable(key)
	local cached = catalogResolvable[key]
	if cached ~= nil then
		return cached
	end
	local p = keyToProvider[key]
	if not p then
		return true
	end
	local result = (p:HasResolvableCatalog() and true) or false
	catalogResolvable[key] = result
	return result
end

-- Build eventToProviders map once after ns.providers is populated.
-- PITFALL-7 performance trap: do NOT rebuild this per event.
for _, provider in ipairs(ns.providers) do
	for _, event in ipairs(provider:GetEventInterests()) do
		if not eventToProviders[event] then
			eventToProviders[event] = {}
		end
		table.insert(eventToProviders[event], provider)
	end
end

-- ns:DispatchEventToProviders(event, ...)
-- Routes the event to all providers that declared interest via GetEventInterests().
-- Each interested provider's OnTrigger is called; if it returns a proc, the proc is stored
-- in ns.activeTimers keyed by proc.key (replace-on-reproc).
-- Returns the number of procs handled (0 if no match).
--
-- DESIGN NOTE (the migration that finished in Phases 17-19):
-- This loop is now the ONLY writer of ns.activeTimers for cast-triggered procs. The coexistence
-- period is over: BuffEngine's own branching cast handler is gone, and ns:OnSpellCastSucceeded
-- does nothing but call straight into here (BuffEngine.lua, "zero branches"). User-spell,
-- trinket, pot and lust procs all arrive through a provider's OnTrigger, so there is one writer
-- and no way to get a duplicate entry for a key. Two other writers, both by design and both under
-- a reminder's own key (Phase 57.2-05):
--   * the user-spell OnTrigger writes a reminder's proc itself, as a side effect, because a
--     provider returns one proc and the same cast may also start a buff;
--   * ns:RefreshAuraStates (BuffEngine.lua) starts a reminder's timer from a readable aura
--     expiry when none runs -- read-started, not cast-triggered.
function ns:DispatchEventToProviders(event, ...)
	local interested = eventToProviders[event]
	if not interested then
		return 0
	end
	local handled = 0
	for _, provider in ipairs(interested) do
		local proc = provider:OnTrigger(event, ...)
		if proc then
			ns.activeTimers[proc.key] = proc
			handled = handled + 1
			if ns.UpdateDisplay then
				ns:UpdateDisplay()
			end
		end
	end
	return handled
end
