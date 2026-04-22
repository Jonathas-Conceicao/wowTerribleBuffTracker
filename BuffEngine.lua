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

function ns:InitBuffEngine()
	-- Schema v3 is terminal for v0.2.3 (DATA-03 reconciliation).
	-- v0.2.3 introduces trinket/pot meta-trackers but creates NO new persistent SavedVariables
	-- structures — TRINKET_SPELLS and POT_SPELLS are runtime-only static tables. The SUGGESTED_BUFFS
	-- entries for "trinket"/"pot" land in ns.db.trackedBuffs only via copy-on-drag (user action),
	-- and follow the existing string-keyed lust pattern that v3 already supports. Therefore no
	-- v3->v4 migration is needed: v0.2.3 is the first release with these features, so no stale
	-- "trinket"/"pot" keys can exist in pre-upgrade SavedVariables. D-05 (CONTEXT.md) supersedes
	-- REQUIREMENTS.md DATA-03; DATA-03 is marked N/A in REQUIREMENTS.md traceability.
	local CURRENT_SCHEMA_VERSION = 3
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

function ns:GetActiveTimers()
	-- Phase 21 (D-05/D-06/D-17/D-18): merge preview + active with real-priority. Same-key
	-- collision resolves to the real proc from ns.activeTimers. Lazy cleanup of expired
	-- entries during iteration. Display.lua sees an unchanged interface — a sorted list.
	local now = GetTime()
	local result = {}

	-- 1. Preview entries first (filter expired; lazy cleanup)
	for key, proc in pairs(ns.previewTimers) do
		if proc.expiresAt > now then
			result[key] = proc
		else
			ns.previewTimers[key] = nil
		end
	end

	-- 2. Real active entries override previews for same key (real-priority per D-05)
	for key, proc in pairs(ns.activeTimers) do
		if proc.expiresAt <= now then
			ns.activeTimers[key] = nil
		else
			result[key] = proc
		end
	end

	-- 3. Flatten to sorted list (ascending by expiresAt — shortest remaining time first)
	local sorted = {}
	for _, proc in pairs(result) do
		table.insert(sorted, proc)
	end
	table.sort(sorted, function(a, b)
		return a.expiresAt < b.expiresAt
	end)
	return sorted
end

function ns:AddTrackedBuff(spellID, duration, label)
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

	ns.db.trackedBuffs[spellID] = {
		spellID = spellID,
		duration = duration,
		label = displayLabel,
		section = "hidden", -- D-05: new buffs land in Not Displayed
		layoutOrder = maxOrder + 1,
	}

	print(
		"|cff00ccffTerribleBuffTracker|r: Now tracking |cff00ff00"
			.. displayLabel
			.. "|r (ID: "
			.. spellID
			.. ", "
			.. duration
			.. "s)."
	)
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

	print("|cff00ccffTerribleBuffTracker|r: Stopped tracking |cffff6600" .. label .. "|r (ID: " .. spellID .. ").")

	if ns.UpdateDisplay then
		ns:UpdateDisplay()
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
		if entry.section ~= "hidden" then
			-- Skip if a live real proc already owns this key (D-05 priority at insertion time)
			local real = ns.activeTimers[key]
			if not (real and real.expiresAt > now) then
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
			for _, buffID in ipairs(timer.aliveBuffs) do
				if C_UnitAuras.GetPlayerAuraBySpellID(buffID) then
					anyPresent = true
					break
				end
			end
			if not anyPresent then
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

	-- ZONE-02: Suppress on isFullUpdate (zone boundary / loading screen transient)
	if updateInfo and updateInfo.isFullUpdate then
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
