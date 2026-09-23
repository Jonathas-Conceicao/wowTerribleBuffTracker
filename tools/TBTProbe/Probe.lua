-- TBT Probe — throwaway API probe harness.
--
-- Phase 1 of the test plan in .planning/research/TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md:
-- report, for every API the two tests depend on, whether the value comes back
-- SECRET, readable, missing or erroring. Nothing here is shipped addon code.
--
-- Run `/tbtp` in each of the three scenarios (S1 out of combat, S2 in combat
-- open world, S3 in combat inside an instance), then `/tbtp show` and copy the
-- whole window.
--
-- Secret-value discipline, which the harness must not violate while testing it:
--   * issecretvalue() FIRST, always, before type/compare/concat.
--   * type() reports "number" for a secret number — never trust it alone.
--   * Index a table only after canaccesstable().
--   * Never tostring() or concatenate a value that might be secret.

local ADDON = ...

local _issecret = issecretvalue
local _issecrettable = issecrettable
local _canaccess = canaccesstable

local report = {}
local lastAuraPayload = "(no UNIT_AURA seen yet)"
local probeSpell, probeCdmSpell

-- Calling a Blizzard CDM mixin method from addon code runs their code on our
-- tainted stack, which can write tainted values into frame caches and leave the
-- frame permanently tainted. Edit Mode then rebuilds and hits a forbidden table:
--   CooldownViewer.lua:939 "attempted to index a table that cannot be accessed
--   while tainted (execution tainted by 'TBTProbe')"  -- dataCache = <forbidden table>
-- So those diagnostics are OFF by default and must be opted into with /tbtp unsafe.
local safeMode = true

---------------------------------------------------------------------------------------------------
-- describe / probe

local function IsSecret(v)
	return _issecret ~= nil and _issecret(v)
end

local function CanRead(t)
	if _issecrettable and _issecrettable(t) then
		return false
	end
	if _canaccess then
		return _canaccess(t)
	end
	return true
end

-- Returns a human string for any value without ever reading a secret.
local function Describe(v)
	if IsSecret(v) then
		return "SECRET(" .. type(v) .. ")"
	end
	local t = type(v)
	if t == "nil" then
		return "nil"
	elseif t == "boolean" then
		return v and "true" or "false"
	elseif t == "number" then
		-- %.4g destroyed spell/cooldown IDs (199300 printed as 1.993e+05).
		if v % 1 == 0 and v < 1e15 and v > -1e15 then
			return string.format("%d", v)
		end
		return string.format("%.6g", v)
	elseif t == "string" then
		return '"' .. v .. '"'
	elseif t == "table" then
		if not CanRead(v) then
			return "table(NO-ACCESS)"
		end
		return "table(readable, n=" .. #v .. ")"
	elseif t == "userdata" then
		return "userdata(handle)"
	end
	return t
end

local function Add(line)
	report[#report + 1] = line
end

local function Row(label, value)
	Add(string.format("  %-44s %s", label, value))
end

local function Pack(...)
	return select("#", ...), { ... }
end

-- Calls fn(...) under pcall and reports every return value's secrecy.
-- Returns the first two real return values for chaining.
local function Probe(label, fn, ...)
	if type(fn) ~= "function" then
		Row(label, "MISSING (not a function)")
		return nil
	end
	local n, res = Pack(pcall(fn, ...))
	if not res[1] then
		local err = res[2]
		Row(label, IsSecret(err) and "ERROR (secret message)" or ("ERROR: " .. tostring(err)))
		return nil
	end
	if n < 2 then
		Row(label, "(returned nothing)")
		return nil
	end
	local parts = {}
	for i = 2, n do
		parts[#parts + 1] = Describe(res[i])
	end
	Row(label, table.concat(parts, " | "))
	return res[2], res[3], res[4]
end

-- For methods owned by Blizzard's CDM. Skipped in safe mode because calling them
-- is what taints the frame; the injection itself does not.
local ProbeM
local function ProbeBlizzardM(label, obj, method, ...)
	if safeMode then
		Row(label, "skipped (safe mode — /tbtp unsafe to enable)")
		return nil
	end
	return ProbeM(label, obj, method, ...)
end

-- Same, for obj:Method(...). Reports MISSING when the method does not exist.
-- Indexing a userdata handle can itself throw, so the lookup is guarded too.
local function LookupMethod(obj, method)
	local ok, fn = pcall(function()
		return obj[method]
	end)
	if not ok then
		return nil
	end
	return fn
end

function ProbeM(label, obj, method, ...)
	if obj == nil then
		Row(label, "MISSING (no object)")
		return nil
	end
	local fn = LookupMethod(obj, method)
	if type(fn) ~= "function" then
		Row(label, "MISSING (no method " .. method .. ")")
		return nil
	end
	return Probe(label, fn, obj, ...)
end

-- Reports only whether a setter accepted the value. Used for the secret sinks:
-- success here means "an addon may push this value into this widget".
local function ProbeSink(label, obj, method, ...)
	if obj == nil then
		Row(label, "MISSING (no widget)")
		return
	end
	local fn = LookupMethod(obj, method)
	if type(fn) ~= "function" then
		Row(label, "MISSING (no method " .. method .. ")")
		return
	end
	local _, res = Pack(pcall(fn, obj, ...))
	if res[1] then
		Row(label, "ACCEPTED")
	else
		local err = res[2]
		Row(label, IsSecret(err) and "REJECTED (secret message)" or ("REJECTED: " .. tostring(err)))
	end
end

-- Reads a field off a table only when the table is readable.
local function ProbeField(label, t, key)
	if t == nil then
		Row(label, "n/a (no table)")
		return nil
	end
	if IsSecret(t) then
		Row(label, "n/a (table is SECRET)")
		return nil
	end
	if type(t) ~= "table" then
		Row(label, "n/a (not a table)")
		return nil
	end
	if not CanRead(t) then
		Row(label, "n/a (table NO-ACCESS)")
		return nil
	end
	local n, res = Pack(pcall(function()
		return t[key]
	end))
	if not res[1] then
		Row(label, "ERROR indexing")
		return nil
	end
	Row(label, Describe(res[2]))
	return res[2]
end

---------------------------------------------------------------------------------------------------
-- spell selection

-- Every spellID the CDM knows about, across all categories.
local function BuildCdmSpellSet()
	local set, count = {}, 0
	if
		not (
			C_CooldownViewer
			and C_CooldownViewer.GetCooldownViewerCategorySet
			and Enum
			and Enum.CooldownViewerCategory
		)
	then
		return set, count
	end
	for _, category in pairs(Enum.CooldownViewerCategory) do
		local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, false)
		if ok and type(ids) == "table" and CanRead(ids) then
			for _, cooldownID in ipairs(ids) do
				local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
				if ok2 and type(info) == "table" and CanRead(info) then
					local sid = info.spellID
					if type(sid) == "number" and not IsSecret(sid) and not set[sid] then
						set[sid] = true
						count = count + 1
					end
					local osid = info.overrideSpellID
					if type(osid) == "number" and not IsSecret(osid) and not set[osid] then
						set[osid] = true
						count = count + 1
					end
				end
			end
		end
	end
	return set, count
end

local function BoolTrue(v)
	return not IsSecret(v) and v == true
end

-- Every active, non-passive, non-auto-attack spell in the player's book, tagged
-- with whether the CDM tracks it. Auto-attack is excluded because the first run
-- auto-picked Attack (6603), which has no cooldown and made Test 1 inconclusive.
local function CollectCandidates(cdmSet)
	local list = {}
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank) then
		return list
	end
	local okLines, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
	if not okLines or type(numLines) ~= "number" then
		return list
	end
	local seen = {}
	for lineIndex = 1, numLines do
		local okInfo, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
		if okInfo and type(lineInfo) == "table" and CanRead(lineInfo) then
			local first = (lineInfo.itemIndexOffset or 0) + 1
			local last = (lineInfo.itemIndexOffset or 0) + (lineInfo.numSpellBookItems or 0)
			for slot = first, last do
				local okItem, item = pcall(C_SpellBook.GetSpellBookItemInfo, slot, Enum.SpellBookSpellBank.Player)
				if okItem and type(item) == "table" and CanRead(item) then
					local sid = item.spellID
					if type(sid) == "number" and not IsSecret(sid) and not seen[sid] then
						local skip = BoolTrue(item.isPassive) or BoolTrue(item.isOffSpec)
						if not skip and C_Spell.IsAutoAttackSpell then
							local okA, isAuto = pcall(C_Spell.IsAutoAttackSpell, sid)
							skip = skip or (okA and BoolTrue(isAuto))
						end
						if not skip and C_Spell.IsAutoRepeatSpell then
							local okR, isRepeat = pcall(C_Spell.IsAutoRepeatSpell, sid)
							skip = skip or (okR and BoolTrue(isRepeat))
						end
						if not skip then
							seen[sid] = true
							list[#list + 1] = { id = sid, isCdm = cdmSet[sid] == true }
						end
					end
				end
			end
		end
	end
	return list
end

local function PickProbeSpells(cdmSet)
	local nonCdm, inCdm
	for _, c in ipairs(CollectCandidates(cdmSet)) do
		if c.isCdm then
			inCdm = inCdm or c.id
		else
			nonCdm = nonCdm or c.id
		end
		if nonCdm and inCdm then
			break
		end
	end
	return nonCdm, inCdm
end

local function SpellLabel(spellID)
	if IsSecret(spellID) then
		return "(SECRET spellID)"
	end
	if type(spellID) ~= "number" then
		return "(none)"
	end
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	local name = "?"
	if ok and type(info) == "table" and CanRead(info) and type(info.name) == "string" and not IsSecret(info.name) then
		name = info.name
	end
	return string.format("%d (%s)", spellID, name)
end

---------------------------------------------------------------------------------------------------
-- throwaway widgets used as secret sinks

local sinks
local function GetSinks()
	if sinks then
		return sinks
	end
	local host = CreateFrame("Frame", "TBTProbeSinkHost", UIParent)
	host:SetSize(200, 20)
	host:SetPoint("CENTER")
	host:Hide()

	local bar = CreateFrame("StatusBar", nil, host)
	bar:SetAllPoints(host)
	bar:SetMinMaxValues(0, 1)

	local cd = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
	cd:SetAllPoints(host)

	local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("CENTER")

	local tex = host:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(host)
	tex:SetColorTexture(1, 1, 1, 1)

	sinks = { host = host, bar = bar, cd = cd, fs = fs, tex = tex }
	return sinks
end

local stepCurve
local function GetStepCurve()
	if stepCurve ~= nil then
		return stepCurve
	end
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
		stepCurve = false
		return false
	end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if not ok or not curve then
		stepCurve = false
		return false
	end
	pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
	pcall(curve.AddPoint, curve, 0, 0)
	pcall(curve.AddPoint, curve, 0.001, 1)
	stepCurve = curve
	return curve
end

---------------------------------------------------------------------------------------------------
-- report sections

local function SectionContext()
	Add("--- CONTEXT ---")
	local version, build, date, iface = GetBuildInfo()
	Row("GetBuildInfo version/build/iface", tostring(version) .. " / " .. tostring(build) .. " / " .. tostring(iface))
	Row("GetBuildInfo date", tostring(date))
	local inInstance, instanceType = IsInInstance()
	Row("IsInInstance / type", tostring(inInstance) .. " / " .. tostring(instanceType))
	Row("InCombatLockdown()", Describe(InCombatLockdown()))
	Row("UnitAffectingCombat('player')", Describe(UnitAffectingCombat("player")))

	Add("")
	Add("  globals present:")
	for _, name in ipairs({
		"issecretvalue",
		"issecrettable",
		"canaccesstable",
		"hasanysecretvalues",
		"scrubsecretvalues",
		"secretunwrap",
		"secretwrap",
		"settablesecurity",
		"canaccesssecrets",
	}) do
		Row("    " .. name, _G[name] ~= nil and "yes" or "NO")
	end

	Add("")
	if C_Secrets then
		Probe("C_Secrets.HasSecretRestrictions", C_Secrets.HasSecretRestrictions)
		Probe("C_Secrets.ShouldAurasBeSecret", C_Secrets.ShouldAurasBeSecret)
		Probe("C_Secrets.ShouldCooldownsBeSecret", C_Secrets.ShouldCooldownsBeSecret)
		Probe("C_Secrets.ShouldUnitStatsBeSecret", C_Secrets.ShouldUnitStatsBeSecret)
	else
		Row("C_Secrets", "MISSING (namespace absent)")
	end
	Add("")
end

local function SectionSpellSelection(cdmSet, cdmCount)
	Add("--- SPELL SELECTION ---")
	Row("CDM-tracked spellIDs discovered", tostring(cdmCount))
	local ids = {}
	for sid in pairs(cdmSet) do
		ids[#ids + 1] = sid
	end
	table.sort(ids)
	for i = 1, math.min(#ids, 20) do
		Row("  CDM spell " .. i, SpellLabel(ids[i]))
	end
	Add("")
	Row("probe spell, NOT CDM-tracked", SpellLabel(probeSpell))
	Row("probe spell, CDM-tracked", SpellLabel(probeCdmSpell))
	Row("override with", "/tbtp spell <id>   /tbtp cdmspell <id>   (/tbtp list)")
	if probeSpell and cdmSet[probeSpell] then
		Row("WARNING", "chosen spell IS CDM-tracked; Test 1 premise not met")
	end
	Add("")
end

local function SectionCooldownAPI(header, spellID)
	Add("--- " .. header .. " ---")
	if type(spellID) ~= "number" then
		Row("(skipped)", "no spell selected")
		Add("")
		return
	end
	Row("spell", SpellLabel(spellID))

	if C_Secrets then
		Probe("C_Secrets.GetSpellCooldownSecrecy", C_Secrets.GetSpellCooldownSecrecy, spellID)
		Probe("C_Secrets.ShouldSpellCooldownBeSecret", C_Secrets.ShouldSpellCooldownBeSecret, spellID)
		Probe("C_Secrets.GetSpellAuraSecrecy", C_Secrets.GetSpellAuraSecrecy, spellID)
	end
	if C_SpellBook then
		Probe("C_SpellBook.IsSpellKnownOrInSpellBook", C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
	end
	-- Forever is vanilla, so the spellbook carries ranked variants (Frostbolt 116
	-- vs the CDM's 205). TBT keys everything by spellID, so whether a rank resolves
	-- to the CDM's ID decides if the two systems can ever agree.
	Probe("C_Spell.GetBaseSpell", C_Spell.GetBaseSpell, spellID)
	Probe("C_Spell.GetOverrideSpell", C_Spell.GetOverrideSpell, spellID)

	Add("")
	Add("  duration-object path (the tier-1 render source):")
	local dur = Probe("C_Spell.GetSpellCooldownDuration", C_Spell.GetSpellCooldownDuration, spellID, false)
	if dur ~= nil then
		ProbeM("  dur:HasSecretValues()", dur, "HasSecretValues")
		ProbeM("  dur:IsActive()", dur, "IsActive")
		ProbeM("  dur:HasStarted()", dur, "HasStarted")
		ProbeM("  dur:HasExpired()", dur, "HasExpired")
		ProbeM("  dur:GetTotalDuration()", dur, "GetTotalDuration")
		ProbeM("  dur:GetRemainingDuration()", dur, "GetRemainingDuration")
		ProbeM("  dur:GetRemainingPercent()", dur, "GetRemainingPercent")
		ProbeM("  dur:GetStartTime()", dur, "GetStartTime")
		ProbeM("  dur:GetEndTime()", dur, "GetEndTime")
		ProbeM("  dur:GetModRate()", dur, "GetModRate")
		local curve = GetStepCurve()
		if curve then
			ProbeM("  dur:EvaluateRemainingDuration(step)", dur, "EvaluateRemainingDuration", curve, 0)
			ProbeM("  dur:EvaluateRemainingPercent(step)", dur, "EvaluateRemainingPercent", curve, 0)
		else
			Row("  C_CurveUtil.CreateCurve", "MISSING")
		end
		-- A handle comes back even when nothing is running; all-zero means the
		-- spell simply was not on cooldown, and the run proves nothing about T1.
		local okTotal, total = pcall(dur.GetTotalDuration, dur, 0)
		if okTotal and not IsSecret(total) and type(total) == "number" and total == 0 then
			Row("  >>> INCONCLUSIVE", "spell was NOT on cooldown — use it, then re-run immediately")
		end
	end

	local chargeDur = Probe("C_Spell.GetSpellChargeDuration", C_Spell.GetSpellChargeDuration, spellID)
	if chargeDur ~= nil then
		ProbeM("  chargeDur:HasSecretValues()", chargeDur, "HasSecretValues")
		ProbeM("  chargeDur:GetRemainingDuration()", chargeDur, "GetRemainingDuration")
	end

	Add("")
	Add("  struct path (expected to go secret in combat):")
	local cdInfo = Probe("C_Spell.GetSpellCooldown", C_Spell.GetSpellCooldown, spellID)
	ProbeField("  cooldownInfo.startTime", cdInfo, "startTime")
	ProbeField("  cooldownInfo.duration", cdInfo, "duration")
	ProbeField("  cooldownInfo.isEnabled", cdInfo, "isEnabled")
	ProbeField("  cooldownInfo.modRate", cdInfo, "modRate")
	ProbeField("  cooldownInfo.isOnGCD", cdInfo, "isOnGCD")

	local charges = Probe("C_Spell.GetSpellCharges", C_Spell.GetSpellCharges, spellID)
	ProbeField("  charges.currentCharges", charges, "currentCharges")
	ProbeField("  charges.maxCharges", charges, "maxCharges")
	ProbeField("  charges.cooldownStartTime", charges, "cooldownStartTime")
	ProbeField("  charges.cooldownDuration", charges, "cooldownDuration")

	Probe("C_Spell.GetSpellCastCount", C_Spell.GetSpellCastCount, spellID)
	Probe("C_Spell.GetSpellDisplayCount", C_Spell.GetSpellDisplayCount, spellID, 99, "*")
	Probe("C_Spell.IsSpellUsable", C_Spell.IsSpellUsable, spellID)
	Probe("C_UnitAuras.GetCooldownAuraBySpellID", C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID, spellID)
	Add("")
	return dur
end

local function SectionSinks(dur)
	Add("--- WIDGET SECRET SINKS (does the setter accept the value?) ---")
	local s = GetSinks()
	local curve = GetStepCurve()

	local secretNum, secretBool, secretStr, curveVal
	if dur ~= nil then
		local ok, v = pcall(dur.GetRemainingPercent, dur, 0)
		if ok then
			secretNum = v
		end
		local ok2, v2 = pcall(dur.IsActive, dur)
		if ok2 then
			secretBool = v2
		end
		if curve then
			local ok3, v3 = pcall(dur.EvaluateRemainingDuration, dur, curve, 0)
			if ok3 then
				curveVal = v3
			end
		end
	end
	if probeSpell and C_Spell.GetSpellDisplayCount then
		local ok, v = pcall(C_Spell.GetSpellDisplayCount, probeSpell, 99, "*")
		if ok then
			secretStr = v
		end
	end

	Row("sample: remaining percent", Describe(secretNum))
	Row("sample: IsActive bool", Describe(secretBool))
	Row("sample: display count string", Describe(secretStr))
	Row("sample: step-curve result", Describe(curveVal))
	Add("")

	if dur ~= nil then
		ProbeSink(
			"StatusBar:SetTimerDuration(dur)",
			s.bar,
			"SetTimerDuration",
			dur,
			Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate,
			Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
		)
		ProbeSink("Cooldown:SetCooldownFromDurationObject(dur)", s.cd, "SetCooldownFromDurationObject", dur)
		ProbeM("StatusBar:GetTimerDuration()", s.bar, "GetTimerDuration")
	else
		Row("StatusBar:SetTimerDuration", "skipped (no duration handle)")
		Row("Cooldown:SetCooldownFromDurationObject", "skipped (no duration handle)")
	end

	if secretNum ~= nil then
		ProbeSink("StatusBar:SetValue(secret number)", s.bar, "SetValue", secretNum)
		ProbeSink("Texture:SetDesaturation(secret number)", s.tex, "SetDesaturation", secretNum)
	end
	if curveVal ~= nil then
		ProbeSink("Texture:SetDesaturation(curve result)", s.tex, "SetDesaturation", curveVal)
		ProbeSink("Frame:SetAlpha(curve result)", s.host, "SetAlpha", curveVal)
	end
	if secretBool ~= nil then
		ProbeSink("Frame:SetAlphaFromBoolean(secret bool)", s.host, "SetAlphaFromBoolean", secretBool, 1, 0)
	end
	if secretStr ~= nil then
		ProbeSink("FontString:SetText(secret string)", s.fs, "SetText", secretStr)
	end
	Add("")
end

local function SectionItems()
	Add("--- T1.4 ITEMS (trinket / potion route) ---")
	for _, slot in ipairs({ 13, 14 }) do
		local itemID = GetInventoryItemID("player", slot)
		Row("equipped slot " .. slot .. " itemID", Describe(itemID))
		if type(itemID) == "number" and not IsSecret(itemID) then
			local name, spellID = Probe("  C_Item.GetItemSpell", C_Item and C_Item.GetItemSpell, itemID)
			Probe("  C_Item.GetItemCooldown", C_Item and C_Item.GetItemCooldown, itemID)
			if type(spellID) == "number" and not IsSecret(spellID) then
				local d = Probe("  GetSpellCooldownDuration(on-use)", C_Spell.GetSpellCooldownDuration, spellID, false)
				if d ~= nil then
					ProbeM("    HasSecretValues()", d, "HasSecretValues")
					ProbeM("    GetRemainingDuration()", d, "GetRemainingDuration")
				end
			end
		end
	end
	Add("")
end

local auraCacheHits = 0

local function SectionCdmContainer()
	auraCacheHits = 0
	Add("--- T2 CDM CONTAINER ---")
	if C_CooldownViewer then
		Probe("C_CooldownViewer.IsCooldownViewerAvailable", C_CooldownViewer.IsCooldownViewerAvailable)
	end
	for _, name in ipairs({
		"BuffBarCooldownViewer",
		"BuffIconCooldownViewer",
		"EssentialCooldownViewer",
		"UtilityCooldownViewer",
	}) do
		local viewer = _G[name]
		Add("")
		Row(name, viewer and "present" or "MISSING")
		if viewer then
			local container = viewer.GetItemContainerFrame and viewer:GetItemContainerFrame() or nil
			Row("  GetItemContainerFrame() == viewer", tostring(container == viewer))
			Row("  .stride", Describe(viewer.stride))
			Row("  .iconLimit", Describe(viewer.iconLimit))
			Row(
				"  .childXPadding / .childYPadding",
				Describe(viewer.childXPadding) .. " / " .. Describe(viewer.childYPadding)
			)
			Row("  .isHorizontal", Describe(viewer.isHorizontal))
			Row("  .iconScale / .iconPadding", Describe(viewer.iconScale) .. " / " .. Describe(viewer.iconPadding))
			Row(
				"  .barContent / .barWidthScale",
				Describe(viewer.barContent) .. " / " .. Describe(viewer.barWidthScale)
			)
			Row("  .baseBarWidth", Describe(viewer.baseBarWidth))
			Row("  .itemFramePool", viewer.itemFramePool and "present" or "MISSING")
			Row("  IsShown()", Describe(viewer:IsShown()))
			ProbeBlizzardM("  viewer:GetStride()", viewer, "GetStride")
			ProbeBlizzardM("  viewer:GetItemCount()", viewer, "GetItemCount")
			ProbeBlizzardM("  viewer:GetAdditionalPaddingOffset()", viewer, "GetAdditionalPaddingOffset")
			ProbeBlizzardM("  viewer:IsHorizontal()", viewer, "IsHorizontal")

			local okChildren, children = pcall(viewer.GetLayoutChildren, viewer)
			if okChildren and type(children) == "table" and CanRead(children) then
				Row("  #GetLayoutChildren()", tostring(#children))
				for i = 1, math.min(#children, 3) do
					local c = children[i]
					Add("")
					Row("  child " .. i .. " layoutIndex", Describe(c.layoutIndex))
					Row("    IsShown()", Describe(c:IsShown()))
					Row("    includeAsLayoutChildWhenHidden", Describe(c.includeAsLayoutChildWhenHidden))
					Row("    ignoreInLayout", Describe(c.ignoreInLayout))
					Row("    GetWidth() / GetHeight()", Describe(c:GetWidth()) .. " / " .. Describe(c:GetHeight()))
					ProbeBlizzardM("    c:GetCooldownID()", c, "GetCooldownID")
					-- Frame-level state. In S2 IsShown() came back READABLE while the
					-- aura data was secret, so these are candidate presence signals.
					ProbeBlizzardM("    c:IsActive()", c, "IsActive")
					ProbeBlizzardM("    c:ShouldBeShown()", c, "ShouldBeShown")
					ProbeBlizzardM("    c:IsExpired()", c, "IsExpired")
					Row("    .auraSpellID", Describe(c.auraSpellID))
					Row("    .auraInstanceID", Describe(c.auraInstanceID))
					Row("    .auraDataUnit", Describe(c.auraDataUnit))
					Row("    .auraDataCached", Describe(c.auraDataCached))
					local ad = c.auraDataCached
					if ad ~= nil then
						auraCacheHits = auraCacheHits + 1
					end
					ProbeField("      cached.applications", ad, "applications")
					ProbeField("      cached.duration", ad, "duration")
					ProbeField("      cached.expirationTime", ad, "expirationTime")
					ProbeField("      cached.spellId", ad, "spellId")
					ProbeField("      cached.name", ad, "name")
					ProbeField("      cached.auraInstanceID", ad, "auraInstanceID")
				end
			else
				Row("  GetLayoutChildren()", "ERROR or missing")
			end
		end
	end
	Add("")
	Row("children with live auraDataCached", tostring(auraCacheHits))
	if auraCacheHits == 0 then
		Row("  >>> P2.7 INCONCLUSIVE", "no CDM item frame holds aura data right now")
		Row("  fix", "add a buff you currently have to CDM Tracked Buffs/Bars, then re-run")
	end
	Add("")
	Add("  mixin tables (hook targets):")
	for _, name in ipairs({
		"CooldownViewerBuffBarItemMixin",
		"CooldownViewerBuffIconItemMixin",
		"CooldownViewerEssentialItemMixin",
		"CooldownViewerUtilityItemMixin",
		"CooldownViewerItemDataMixin",
		"GridLayoutFrameMixin",
	}) do
		Row("    " .. name, _G[name] and "present" or "MISSING")
	end
	Add("")
end

---------------------------------------------------------------------------------------------------
-- watched aura (stack tracking)
--
-- The question: when a stacking buff is fully consumed mid-combat, can TBT tell
-- that it ended early? The direct aura API hard-errors while restricted, so the
-- only candidate routes are (a) a per-spell NeverSecret exemption, (b) the CDM
-- item frame's cached aura table, and (c) the CDM item frame's own shown/active
-- state, which came back READABLE in the S2 run.

local VIEWER_NAMES = {
	"BuffBarCooldownViewer",
	"BuffIconCooldownViewer",
	"EssentialCooldownViewer",
	"UtilityCooldownViewer",
}

-- Locates the CDM item frame backing a spell, matching on cooldownID -> spellID
-- because auraSpellID itself is secret while restricted.
local function FindCdmFrameForSpell(spellID)
	if type(spellID) ~= "number" or not C_CooldownViewer then
		return nil
	end
	for _, name in ipairs(VIEWER_NAMES) do
		local viewer = _G[name]
		if viewer and viewer.GetLayoutChildren then
			local ok, children = pcall(viewer.GetLayoutChildren, viewer)
			if ok and type(children) == "table" and CanRead(children) then
				for _, c in ipairs(children) do
					local okID, cid = pcall(c.GetCooldownID, c)
					if okID and type(cid) == "number" and not IsSecret(cid) then
						local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
						if ok2 and type(info) == "table" and CanRead(info) then
							local sid, osid = info.spellID, info.overrideSpellID
							local hit = (not IsSecret(sid) and sid == spellID)
								or (not IsSecret(osid) and osid == spellID)
							if hit then
								return c, name
							end
						end
					end
				end
			end
		end
	end
	return nil
end

local watchSpell, watchTicker, watchStart, watchLast
local watchLog = {}
local watchFrame
local watchSamples = 0
local watchInstanceID

-- Calls a bare function and describes its first return, never throwing.
local function SafeFn(fn, ...)
	if type(fn) ~= "function" then
		return "no-fn"
	end
	local n, res = Pack(pcall(fn, ...))
	if not res[1] then
		local e = res[2]
		if IsSecret(e) then
			return "ERR(secret)"
		end
		-- Keep it short; the full text is in the main report's aura section.
		local msg = tostring(e)
		return "ERR:" .. msg:sub(1, 40)
	end
	if n < 2 then
		return "(nothing)"
	end
	return Describe(res[2])
end

local function SafeCall(obj, method, ...)
	local fn = LookupMethod(obj, method)
	if type(fn) ~= "function" then
		return "no-method"
	end
	local _, res = Pack(pcall(fn, obj, ...))
	if not res[1] then
		return "ERR"
	end
	return Describe(res[2])
end

-- One line describing everything knowable about the watched aura right now.
local function WatchSnapshot()
	local sid = watchSpell
	local parts = {}

	-- (a) direct read by spell ID
	local _, res = Pack(pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid))
	if not res[1] then
		parts[#parts + 1] = "direct=ERR"
	else
		local aura = res[2]
		parts[#parts + 1] = "direct=" .. Describe(aura)
		if type(aura) == "table" and not IsSecret(aura) and CanRead(aura) then
			local okA, apps = pcall(function()
				return aura.applications
			end)
			parts[#parts + 1] = "apps=" .. (okA and Describe(apps) or "ERR")
			local okE, exp = pcall(function()
				return aura.expirationTime
			end)
			parts[#parts + 1] = "exp=" .. (okE and Describe(exp) or "ERR")
			-- Stash the instance ID while it is still readable. The whole question
			-- is whether it keeps working once restrictions turn on.
			local okI, iid = pcall(function()
				return aura.auraInstanceID
			end)
			if okI and type(iid) == "number" and not IsSecret(iid) then
				watchInstanceID = iid
			end
		end
	end

	-- (d) stashed-instance-ID routes. These are the calls the enumeration APIs
	-- normally feed; they were never reachable in combat because enumeration
	-- hard-errors first. With a cached ID they can be tried directly.
	if watchInstanceID then
		parts[#parts + 1] = "iid=" .. tostring(watchInstanceID)
		parts[#parts + 1] = "count="
			.. SafeFn(C_UnitAuras.GetAuraApplicationDisplayCount, "player", watchInstanceID, 1, 99)
		parts[#parts + 1] = "hasExp=" .. SafeFn(C_UnitAuras.DoesAuraHaveExpirationTime, "player", watchInstanceID)
		parts[#parts + 1] = "auraDur=" .. SafeFn(C_UnitAuras.GetAuraDuration, "player", watchInstanceID)
		parts[#parts + 1] = "byIID=" .. SafeFn(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", watchInstanceID)
	else
		parts[#parts + 1] = "iid=none"
	end

	-- (b)/(c) CDM item frame
	local frame, viewerName = FindCdmFrameForSpell(sid)
	if frame then
		parts[#parts + 1] = "cdm=" .. viewerName
		parts[#parts + 1] = "shown=" .. SafeCall(frame, "IsShown")
		parts[#parts + 1] = "active=" .. SafeCall(frame, "IsActive")
		parts[#parts + 1] = "expired=" .. SafeCall(frame, "IsExpired")
		local ad = frame.auraDataCached
		parts[#parts + 1] = "cache=" .. Describe(ad)
		if type(ad) == "table" and not IsSecret(ad) and CanRead(ad) then
			local okA, apps = pcall(function()
				return ad.applications
			end)
			parts[#parts + 1] = "cacheApps=" .. (okA and Describe(apps) or "ERR")
		end
	else
		parts[#parts + 1] = "cdm=none"
	end

	return table.concat(parts, "  ")
end

local function WatchSample(tag)
	if not watchSpell then
		return
	end
	watchSamples = watchSamples + 1
	local ok, line = pcall(WatchSnapshot)
	if not ok then
		line = "SNAPSHOT ERROR: " .. tostring(line)
	end
	-- Log only on change, or the timeline drowns in identical ticks.
	if line ~= watchLast then
		watchLast = line
		if #watchLog < 400 then
			watchLog[#watchLog + 1] = string.format("[%7.2f] %-7s %s", GetTime() - watchStart, tag or "tick", line)
		end
	end

	-- Visual pipe: whatever cannot be read can still be rendered. Preference order
	-- is the stashed instance ID (works in combat if that route is open), then the
	-- CDM frame cache, then a plain readable read.
	if watchFrame and watchFrame:IsShown() then
		local wrote = false
		if watchInstanceID and C_UnitAuras.GetAuraApplicationDisplayCount then
			local _, r = Pack(pcall(C_UnitAuras.GetAuraApplicationDisplayCount, "player", watchInstanceID, 1, 99))
			if r[1] and r[2] ~= nil then
				wrote = pcall(watchFrame.stacks.SetText, watchFrame.stacks, r[2])
			end
		end
		if not wrote then
			local frame = FindCdmFrameForSpell(watchSpell)
			local ad = frame and frame.auraDataCached
			if type(ad) == "table" and not IsSecret(ad) and CanRead(ad) then
				wrote = pcall(watchFrame.stacks.SetFormattedText, watchFrame.stacks, "%d", ad.applications)
			end
		end
		if not wrote then
			local _, r = Pack(pcall(C_UnitAuras.GetPlayerAuraBySpellID, watchSpell))
			local aura = r[1] and r[2]
			if type(aura) == "table" and not IsSecret(aura) and CanRead(aura) then
				wrote = pcall(watchFrame.stacks.SetFormattedText, watchFrame.stacks, "%d", aura.applications)
			end
		end
		if not wrote then
			pcall(watchFrame.stacks.SetText, watchFrame.stacks, "?")
		end

		-- Presence without reading it. A secret boolean into SetAlphaFromBoolean is
		-- the whole "make it disappear when the buff ends" mechanism.
		local faded = false
		if watchInstanceID and C_UnitAuras.DoesAuraHaveExpirationTime and watchFrame.SetAlphaFromBoolean then
			local _, r = Pack(pcall(C_UnitAuras.DoesAuraHaveExpirationTime, "player", watchInstanceID))
			if r[1] and r[2] ~= nil then
				faded = pcall(watchFrame.SetAlphaFromBoolean, watchFrame, r[2], 1, 0.15)
			end
		end
		if not faded then
			local frame = FindCdmFrameForSpell(watchSpell)
			if frame and watchFrame.SetAlphaFromBoolean then
				local shown = LookupMethod(frame, "IsShown")
				if shown then
					local _, sres = Pack(pcall(shown, frame))
					if sres[1] then
						pcall(watchFrame.SetAlphaFromBoolean, watchFrame, sres[2], 1, 0.15)
					end
				end
			end
		end
	end
end

local function EnsureWatchFrame()
	if watchFrame then
		return watchFrame
	end
	local f = CreateFrame("Frame", "TBTProbeWatchFrame", UIParent)
	f:SetSize(64, 64)
	f:SetPoint("CENTER", 0, -240)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	f.icon = tex

	local stacks = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
	stacks:SetPoint("BOTTOMRIGHT", 2, -2)
	f.stacks = stacks

	local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOP", f, "BOTTOM", 0, -2)
	f.label = label

	tinsert(UISpecialFrames, "TBTProbeWatchFrame")
	watchFrame = f
	return f
end

local function StartWatch(spellID)
	watchSpell = spellID
	watchStart = GetTime()
	watchLast = nil
	watchSamples = 0
	watchInstanceID = nil
	wipe(watchLog)

	local f = EnsureWatchFrame()
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if ok and type(info) == "table" and CanRead(info) then
		pcall(f.icon.SetTexture, f.icon, info.iconID)
	end
	f.label:SetText(SpellLabel(spellID))
	f.stacks:SetText("?")
	f:Show()

	if watchTicker then
		watchTicker:Cancel()
	end
	watchTicker = C_Timer.NewTicker(0.1, function()
		WatchSample("tick")
	end)
	WatchSample("start")
	print("|cff00ccffTBT Probe|r: watching " .. SpellLabel(spellID) .. ". Apply it, spend the stacks, then /tbtp show.")
end

local function StopWatch()
	if watchTicker then
		watchTicker:Cancel()
		watchTicker = nil
	end
	if watchFrame then
		watchFrame:Hide()
	end
	print("|cff00ccffTBT Probe|r: watch stopped, " .. #watchLog .. " change events logged.")
end

-- Full dump of every aura currently on the player. Out of combat this is all
-- readable, which is how you find the *aura's* spell ID — the ID you cast is
-- often not the ID of the buff it applies.
local function BuildAuraDump()
	wipe(report)
	Add("===== TBT PROBE — PLAYER AURA DUMP =====")
	Add("recorded: " .. date("%Y-%m-%d %H:%M:%S"))
	Row("InCombatLockdown()", Describe(InCombatLockdown()))
	Row("ShouldAurasBeSecret()", Describe(C_Secrets and C_Secrets.ShouldAurasBeSecret()))
	Add("")
	Add("If auras are secret right now this dump will be empty or erroring — run it")
	Add("OUT OF COMBAT with the buff active.")
	Add("")

	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		Add("--- " .. filter .. " ---")
		local _, res = Pack(pcall(C_UnitAuras.GetUnitAuras, "player", filter, 40))
		if not res[1] then
			Row("GetUnitAuras", "ERROR: " .. tostring(res[2]))
		else
			local auras = res[2]
			if type(auras) ~= "table" or not CanRead(auras) then
				Row("GetUnitAuras", Describe(auras))
			else
				Row("count", tostring(#auras))
				for i = 1, #auras do
					local a = auras[i]
					Add("")
					if type(a) ~= "table" or not CanRead(a) then
						Row("  aura " .. i, Describe(a))
					else
						ProbeField("  aura " .. i .. " .name", a, "name")
						ProbeField("    .spellId", a, "spellId")
						ProbeField("    .applications", a, "applications")
						ProbeField("    .duration", a, "duration")
						ProbeField("    .expirationTime", a, "expirationTime")
						ProbeField("    .auraInstanceID", a, "auraInstanceID")
						ProbeField("    .charges", a, "charges")
						ProbeField("    .maxCharges", a, "maxCharges")
						ProbeField("    .sourceUnit", a, "sourceUnit")
						ProbeField("    .isHelpful", a, "isHelpful")
					end
				end
			end
		end
		Add("")
	end
	Add("===== END =====")
	return table.concat(report, "\n")
end

local function SectionWatchedAura()
	if not watchSpell then
		return
	end
	Add("--- WATCHED AURA: " .. SpellLabel(watchSpell) .. " ---")
	if C_Secrets then
		Probe("C_Secrets.GetSpellAuraSecrecy", C_Secrets.GetSpellAuraSecrecy, watchSpell)
		Probe("C_Secrets.ShouldSpellAuraBeSecret", C_Secrets.ShouldSpellAuraBeSecret, watchSpell)
	end
	Row("secrecy legend", "0=NeverSecret 1=AlwaysSecret 2=ContextuallySecret")
	Probe("GetSpellMaxCumulativeAuraApplications", C_Spell.GetSpellMaxCumulativeAuraApplications, watchSpell)
	Probe("C_Spell.GetSpellCastCount", C_Spell.GetSpellCastCount, watchSpell)
	Probe("C_Spell.GetSpellDisplayCount", C_Spell.GetSpellDisplayCount, watchSpell, 99, "*")

	Add("")
	local aura = Probe("C_UnitAuras.GetPlayerAuraBySpellID", C_UnitAuras.GetPlayerAuraBySpellID, watchSpell)
	ProbeField("  aura.applications", aura, "applications")
	ProbeField("  aura.duration", aura, "duration")
	ProbeField("  aura.expirationTime", aura, "expirationTime")
	ProbeField("  aura.auraInstanceID", aura, "auraInstanceID")
	ProbeField("  aura.charges", aura, "charges")
	ProbeField("  aura.maxCharges", aura, "maxCharges")

	Add("")
	Row("stashed auraInstanceID", watchInstanceID and tostring(watchInstanceID) or "none captured yet")
	if watchInstanceID then
		Add("  ID-based routes (skipped in earlier runs because enumeration errors first):")
		Probe(
			"  GetAuraApplicationDisplayCount",
			C_UnitAuras.GetAuraApplicationDisplayCount,
			"player",
			watchInstanceID,
			1,
			99
		)
		Probe("  DoesAuraHaveExpirationTime", C_UnitAuras.DoesAuraHaveExpirationTime, "player", watchInstanceID)
		local ad = Probe("  GetAuraDuration", C_UnitAuras.GetAuraDuration, "player", watchInstanceID)
		if ad ~= nil then
			ProbeM("    auraDur:HasSecretValues()", ad, "HasSecretValues")
			ProbeM("    auraDur:GetRemainingDuration()", ad, "GetRemainingDuration")
			ProbeM("    auraDur:IsActive()", ad, "IsActive")
		end
		local byID =
			Probe("  GetAuraDataByAuraInstanceID", C_UnitAuras.GetAuraDataByAuraInstanceID, "player", watchInstanceID)
		ProbeField("    .applications", byID, "applications")
		ProbeField("    .expirationTime", byID, "expirationTime")
		Probe("  GetAuraBaseDuration", C_UnitAuras.GetAuraBaseDuration, "player", watchInstanceID)
		Probe("  GetRefreshExtendedDuration", C_UnitAuras.GetRefreshExtendedDuration, "player", watchInstanceID)
	end

	Add("")
	local frame, viewerName = FindCdmFrameForSpell(watchSpell)
	if frame then
		Row("CDM item frame found in", viewerName)
		Row("  frame:IsShown()", SafeCall(frame, "IsShown"))
		Row("  frame:IsActive()", SafeCall(frame, "IsActive"))
		Row("  frame:IsExpired()", SafeCall(frame, "IsExpired"))
		Row("  frame.auraDataCached", Describe(frame.auraDataCached))
		ProbeField("    cache.applications", frame.auraDataCached, "applications")
		ProbeField("    cache.expirationTime", frame.auraDataCached, "expirationTime")
	else
		Row("CDM item frame", "NONE — spell is not tracked by the Cooldown Manager")
		Row("  consequence", "routes (b) and (c) unavailable; only a NeverSecret exemption would work")
	end

	Add("")
	Row("watch samples taken", tostring(watchSamples) .. (watchTicker and " (ticker RUNNING)" or " (ticker STOPPED)"))
	Row("watch timeline", #watchLog .. " change events (0.1s sampling, logged on change only)")
	for _, line in ipairs(watchLog) do
		Add("    " .. line)
	end
	Add("")
end

---------------------------------------------------------------------------------------------------
-- cast-driven stack tracker (prototype)
--
-- The aura APIs are closed in combat, but UNIT_SPELLCAST_SUCCEEDED is not and its
-- spellID is safe for the player. So a consumable-stack buff can be modelled
-- entirely from casts: the granting cast starts it, qualifying casts spend it,
-- and hitting zero ends it EARLY — which is the behaviour the aura API cannot give.
--
-- C_Spell.IsSpellHarmful is AllowedWhenTainted with no secrecy flag, so the
-- "damaging ability" filter works in combat. It means "can target an enemy",
-- not "deals damage", so this logs prediction vs. reality to expose the gap.

local track = {
	spellID = nil,
	maxStacks = 3,
	duration = 15,
	stacks = 0,
	expires = 0,
	active = false,
	mode = "harmful", -- or "any"
}
local trackLog = {}
local trackFrame

local function BoolResult(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local n, res = Pack(pcall(fn, ...))
	if not res[1] or n < 2 then
		return nil
	end
	local v = res[2]
	if IsSecret(v) or type(v) ~= "boolean" then
		return nil
	end
	return v
end

-- Real stack count, readable only outside restriction. Used purely to check the
-- cast-driven model against the truth.
local function ActualStacks()
	if not track.spellID then
		return "n/a"
	end
	local _, res = Pack(pcall(C_UnitAuras.GetPlayerAuraBySpellID, track.spellID))
	if not res[1] then
		return "blocked"
	end
	local aura = res[2]
	if aura == nil then
		-- Returning nothing means either "no such aura" or "restricted and refused";
		-- GetPlayerAuraBySpellID cannot distinguish them, so say which is likely.
		if C_Secrets and C_Secrets.ShouldAurasBeSecret() then
			return "RESTRICTED (unverifiable)"
		end
		return "absent"
	end
	if type(aura) ~= "table" or IsSecret(aura) or not CanRead(aura) then
		return Describe(aura)
	end
	local okA, apps = pcall(function()
		return aura.applications
	end)
	return okA and Describe(apps) or "ERR"
end

local function TrackLog(fmt, ...)
	if #trackLog >= 300 then
		return
	end
	-- Anchored to startedAt, not to track.active — EndTrack clears active before
	-- logging, which used to stamp the END line as [0.00].
	local elapsed = track.startedAt and (GetTime() - track.startedAt) or 0
	trackLog[#trackLog + 1] = string.format("[%6.2f] ", elapsed) .. string.format(fmt, ...)
end

local function UpdateTrackVisual()
	if not trackFrame then
		return
	end
	if not track.active then
		trackFrame:Hide()
		return
	end
	trackFrame:Show()
	trackFrame.stacks:SetText(tostring(track.stacks))
	local remaining = track.expires - GetTime()
	if remaining < 0 then
		remaining = 0
	end
	trackFrame.bar:SetMinMaxValues(0, track.duration)
	trackFrame.bar:SetValue(remaining)
	trackFrame.timer:SetFormattedText("%.1f", remaining)
end

local function EndTrack(reason)
	if not track.active then
		return
	end
	track.active = false
	TrackLog("END (%s) — predicted stacks %d, actual %s", reason, track.stacks, ActualStacks())
	UpdateTrackVisual()
	print("|cff00ccffTBT Probe|r: tracked buff ended — " .. reason)
end

local function StartTrack()
	track.stacks = track.maxStacks
	track.startedAt = GetTime()
	track.expires = track.startedAt + track.duration
	track.active = true
	wipe(trackLog)
	TrackLog("APPLY — %d stacks, %ds, actual %s", track.maxStacks, track.duration, ActualStacks())
	UpdateTrackVisual()
end

local function OnTrackedCast(spellID)
	if not track.spellID then
		return
	end
	if spellID == track.spellID then
		StartTrack()
		return
	end
	if not track.active then
		return
	end

	local harmful = BoolResult(C_Spell.IsSpellHarmful, spellID)
	local helpful = BoolResult(C_Spell.IsSpellHelpful, spellID)
	local autoAttack = BoolResult(C_Spell.IsAutoAttackSpell, spellID)

	local qualifies
	if track.mode == "any" then
		qualifies = autoAttack ~= true
	else
		-- Unknown counts as qualifying: missing a decrement leaves a stale buff on
		-- screen, which is worse than dropping one early.
		qualifies = (harmful ~= false) and (autoAttack ~= true)
	end

	local name = SpellLabel(spellID)
	if qualifies then
		track.stacks = track.stacks - 1
		TrackLog(
			"CAST %s harmful=%s helpful=%s -> SPEND, predicted %d, actual %s",
			name,
			tostring(harmful),
			tostring(helpful),
			track.stacks,
			ActualStacks()
		)
		UpdateTrackVisual()
		if track.stacks <= 0 then
			EndTrack("all stacks consumed")
		end
	else
		TrackLog(
			"CAST %s harmful=%s helpful=%s -> ignored, predicted %d, actual %s",
			name,
			tostring(harmful),
			tostring(helpful),
			track.stacks,
			ActualStacks()
		)
	end
end

local function EnsureTrackFrame()
	if trackFrame then
		return trackFrame
	end
	local f = CreateFrame("Frame", "TBTProbeTrackFrame", UIParent)
	f:SetSize(240, 40)
	f:SetPoint("CENTER", 0, -300)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("LEFT", 2, 0)
	f.iconTex = icon

	local stacks = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
	stacks:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
	f.stacks = stacks

	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	bar:SetPoint("RIGHT", -6, 0)
	bar:SetHeight(20)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.9, 0.7, 0.1)
	f.bar = bar

	local timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	timer:SetPoint("RIGHT", -4, 0)
	f.timer = timer

	f:SetScript("OnUpdate", function()
		if track.active and GetTime() >= track.expires then
			EndTrack("duration expired")
		else
			UpdateTrackVisual()
		end
	end)

	tinsert(UISpecialFrames, "TBTProbeTrackFrame")
	trackFrame = f
	return f
end

local castWatcher = CreateFrame("Frame")
castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castWatcher:SetScript("OnEvent", function(_, _, _, _, spellID)
	if IsSecret(spellID) or type(spellID) ~= "number" then
		return
	end
	pcall(OnTrackedCast, spellID)
end)

local function StartTracking(spellID, maxStacks, duration, mode)
	track.spellID = spellID
	track.maxStacks = maxStacks or 3
	track.duration = duration or 15
	track.mode = mode or "harmful"
	track.active = false
	track.stacks = 0
	wipe(trackLog)

	local f = EnsureTrackFrame()
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if ok and type(info) == "table" and CanRead(info) then
		pcall(f.iconTex.SetTexture, f.iconTex, info.iconID)
	end
	f:Hide()
	print(
		string.format(
			"|cff00ccffTBT Probe|r: tracking %s — %d stacks, %ds, mode=%s. Cast it, then spend the stacks.",
			SpellLabel(spellID),
			track.maxStacks,
			track.duration,
			track.mode
		)
	)
end

local function SectionTrack()
	if not track.spellID then
		return
	end
	Add("--- CAST-DRIVEN STACK TRACKER: " .. SpellLabel(track.spellID) .. " ---")
	Row("mode", track.mode .. "  (harmful = only spells castable on enemies)")
	Row("config", string.format("%d stacks, %ds duration", track.maxStacks, track.duration))
	Row("currently active", tostring(track.active))
	Row("predicted stacks", tostring(track.stacks))
	Row("actual stacks right now", ActualStacks())
	Probe("C_Spell.IsSpellHarmful(tracked)", C_Spell.IsSpellHarmful, track.spellID)
	Add("")
	Row("event log", #trackLog .. " entries")
	for _, line in ipairs(trackLog) do
		Add("    " .. line)
	end
	Add("")
end

---------------------------------------------------------------------------------------------------
-- CDM container injection (Test 2 prototype)
--
-- Parents a TBT-owned item frame into Blizzard's own viewer and then corrects the
-- container's stride so the WHOLE row re-flows for the new count, rather than our
-- icon being tacked onto the end while Blizzard's wrap at the old count.
--
-- Hard rule learned the hard way: Blizzard's mixin METHODS can throw when called
-- from tainted code (CooldownViewer.lua:1130 compares a secret). So this reads
-- plain fields only, pcalls anything Blizzard-owned, and re-asserts through
-- hooksecurefunc so our work happens after their untainted pass.

local inject = {
	viewer = nil,
	viewerName = nil,
	frame = nil,
	log = {},
	hookedViewers = {},
	reasserting = false,
	strideBefore = nil,
	mode = "full", -- full | nostride | manual
}

local function InjectLog(fmt, ...)
	if #inject.log >= 200 then
		return
	end
	inject.log[#inject.log + 1] = string.format("[%8.2f] ", GetTime() % 100000) .. string.format(fmt, ...)
end

-- Layout children excluding ours, so we can find the highest Blizzard index.
local function LayoutChildrenOf(viewer)
	local ok, children = pcall(viewer.GetLayoutChildren, viewer)
	if not ok or type(children) ~= "table" or not CanRead(children) then
		return nil
	end
	return children
end

-- BuffIcon/BuffBar set stride == item count to force a single row/column, so the
-- stride must grow with our frame or the row breaks at Blizzard's old count.
-- Essential/Utility use iconLimit as a real wrap width and must be left alone.
local function ViewerUsesCountAsStride(name)
	return name == "BuffIconCooldownViewer" or name == "BuffBarCooldownViewer"
end

-- How many slots the CDM owns in this viewer, regardless of what is on screen.
--
-- Counting GetLayoutChildren() is wrong: with nothing procced the pool is empty,
-- so our frame took layoutIndex 1 and rendered FIRST. It only corrected itself in
-- Edit Mode, where Blizzard populates a preview of every configured buff. The
-- configured category set is the stable answer.
local function BlizzardSlotCount(viewer)
	local n, why = 0, "none"

	local category = viewer.cooldownViewerCategory
	if
		category ~= nil
		and not IsSecret(category)
		and C_CooldownViewer
		and C_CooldownViewer.GetCooldownViewerCategorySet
	then
		-- Ask for both learned-only and everything; Edit Mode previews the latter.
		for _, allowUnlearned in ipairs({ false, true }) do
			local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, allowUnlearned)
			if ok and type(ids) == "table" and CanRead(ids) and #ids > n then
				n, why = #ids, "categorySet(allowUnlearned=" .. tostring(allowUnlearned) .. ")"
			end
		end
	end

	-- Blizzard applies a minimum of 2 items, so honour its own count when higher.
	local okCount, count = pcall(viewer.GetItemCount, viewer)
	if okCount and type(count) == "number" and not IsSecret(count) and count > n then
		n, why = count, "viewer:GetItemCount()"
	end

	-- Never sit below an index that is actually present right now.
	local children = LayoutChildrenOf(viewer)
	if children then
		for _, c in ipairs(children) do
			if c ~= inject.frame then
				local idx = c.layoutIndex
				if type(idx) == "number" and not IsSecret(idx) and idx > n then
					n, why = idx, "live layoutIndex"
				end
			end
		end
	end

	return n, why
end

-- Children via the C widget API. Executes none of Blizzard's Lua, unlike
-- viewer:GetLayoutChildren().
local function RawLayoutChildren(viewer, exclude)
	local out = {}
	for _, c in ipairs({ viewer:GetChildren() }) do
		if c ~= exclude then
			local idx = c.layoutIndex
			if type(idx) == "number" and not IsSecret(idx) then
				out[#out + 1] = { frame = c, index = idx }
			end
		end
	end
	table.sort(out, function(a, b)
		return a.index < b.index
	end)
	return out
end

-- Slot count without touching a single Blizzard mixin. C_CooldownViewer is a
-- namespace API, not a frame method, so it does not run their frame code.
local function PureSlotCount(viewer, frame)
	local n = 0
	local category = viewer.cooldownViewerCategory
	if category ~= nil and not IsSecret(category) and C_CooldownViewer then
		for _, allowUnlearned in ipairs({ false, true }) do
			local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, allowUnlearned)
			if ok and type(ids) == "table" and CanRead(ids) and #ids > n then
				n = #ids
			end
		end
	end
	if n < 2 then
		n = 2 -- Blizzard's own minimumItemCount floor
	end
	for _, entry in ipairs(RawLayoutChildren(viewer, frame)) do
		if entry.index > n then
			n = entry.index
		end
	end
	return n
end

-- MODE "pure": executes ZERO Blizzard Lua. No GetItemCount, no GetLayoutChildren,
-- no Layout, no stride. Writes only our own frame's fields, and only from a fresh
-- execution frame. Blizzard's own next Layout pass positions us.
--
-- This exists because full/nostride/manual all called viewer:GetItemCount() and
-- viewer:GetLayoutChildren() via BlizzardSlotCount, and mixin calls are a known
-- taint vector — so none of those three isolated what they claimed to.
local function ReassertPure()
	local viewer, frame = inject.viewer, inject.frame
	if not (viewer and frame) then
		return
	end
	local wanted = PureSlotCount(viewer, frame) + 1
	if frame.layoutIndex ~= wanted then
		InjectLog("layoutIndex %s -> %d (pure)", tostring(frame.layoutIndex), wanted)
		frame.layoutIndex = wanted
	end
	frame.ignoreInLayout = nil

	local scale = viewer.iconScale
	if type(scale) == "number" and not IsSecret(scale) and scale > 0 and frame:GetScale() ~= scale then
		frame:SetScale(scale)
	end
	local kids = RawLayoutChildren(viewer, frame)
	if kids[1] then
		local sib = kids[1].frame
		local w, h = sib:GetWidth(), sib:GetHeight()
		if not IsSecret(w) and not IsSecret(h) and w > 0 and h > 0 then
			if frame:GetWidth() ~= w or frame:GetHeight() ~= h then
				frame:SetSize(w, h)
			end
		end
	end
	-- Deliberately no Layout() call. Blizzard lays us out on their next pass.
end

local function ReassertInjection()
	local viewer, frame = inject.viewer, inject.frame
	if not (viewer and frame) then
		return
	end
	if inject.mode == "pure" then
		ReassertPure()
		return
	end

	local slots, why = BlizzardSlotCount(viewer)
	local wantedIndex = slots + 1

	-- MODE "manual": write NOTHING that Blizzard's layout code will read. Our frame
	-- leaves the grid entirely and is positioned by hand against the last real
	-- item. On single-row viewers (BuffIcon/BuffBar) the result looks identical,
	-- because there is no wrapping to participate in.
	if inject.mode == "manual" then
		frame.layoutIndex = nil
		frame.ignoreInLayout = true
		-- GetChildren() is a C widget API, not a Blizzard mixin, so this walks the
		-- container without executing any of their Lua. Manual mode's whole point is
		-- to touch nothing of theirs.
		local last, bestIdx = nil, -1
		for _, c in ipairs({ viewer:GetChildren() }) do
			if c ~= frame then
				local idx = c.layoutIndex
				if type(idx) == "number" and not IsSecret(idx) and idx > bestIdx then
					last, bestIdx = c, idx
				end
			end
		end
		frame:ClearAllPoints()
		if last then
			if viewer.isHorizontal then
				frame:SetPoint("LEFT", last, "RIGHT", viewer.childXPadding or 0, 0)
			else
				frame:SetPoint("TOP", last, "BOTTOM", 0, -(viewer.childYPadding or 0))
			end
			InjectLog("manual placement after last Blizzard child")
		else
			frame:SetPoint("CENTER", viewer, "CENTER", 0, 0)
			InjectLog("manual placement at viewer centre (no siblings)")
		end
	else
		frame.ignoreInLayout = nil
		-- Duplicate layoutIndex raises a GMError inside GetLayoutChildren, so this
		-- must always land past every Blizzard slot.
		if frame.layoutIndex ~= wantedIndex then
			InjectLog(
				"layoutIndex %s -> %d (%d Blizzard slots via %s)",
				tostring(frame.layoutIndex),
				wantedIndex,
				slots,
				why
			)
			frame.layoutIndex = wantedIndex
		end

		-- MODE "nostride": never write to the viewer's own fields. The row then
		-- wraps at Blizzard's count — that is the cost of not touching their frame.
		if inject.mode ~= "nostride" and ViewerUsesCountAsStride(inject.viewerName) then
			if viewer.stride ~= wantedIndex then
				if inject.mode == "deferred" then
					-- MODE "deferred": the stride write is the one thing that taints,
					-- and it taints because this hook runs INSIDE Edit Mode's
					-- secureexecuterange. Pushing it onto a fresh execution frame via
					-- After(0) means the write never happens nested in their secure
					-- call stack. Edit Mode is additionally waited out entirely.
					if not inject.stridePending then
						inject.stridePending = true
						C_Timer.After(0, function()
							inject.stridePending = false
							local em = EditModeManagerFrame
							if em and em:IsShown() then
								InjectLog("stride write held — Edit Mode open")
								inject.strideWanted = wantedIndex
								return
							end
							if viewer.stride ~= wantedIndex then
								InjectLog("stride %s -> %d (deferred)", tostring(viewer.stride), wantedIndex)
								viewer.stride = wantedIndex
								pcall(viewer.Layout, viewer)
							end
						end)
					end
				else
					InjectLog("stride %s -> %d (inline)", tostring(viewer.stride), wantedIndex)
					viewer.stride = wantedIndex
				end
			end
		end
	end

	-- Blizzard applies icon scale in OnAcquireItemFrame (CooldownViewer.lua:1996),
	-- which only ever runs for POOL frames. An injected frame must re-sync it
	-- itself or it ignores the user's Icon Size slider.
	local scale = viewer.iconScale
	if type(scale) == "number" and not IsSecret(scale) and scale > 0 then
		if frame:GetScale() ~= scale then
			InjectLog("scale %.2f -> %.2f (viewer.iconScale)", frame:GetScale(), scale)
			frame:SetScale(scale)
		end
	end

	-- Bar width is a per-item property too; re-sync size from a live sibling.
	local children = LayoutChildrenOf(viewer)
	if children then
		for _, c in ipairs(children) do
			if c ~= frame then
				local okW, w = pcall(c.GetWidth, c)
				local okH, h = pcall(c.GetHeight, c)
				if okW and okH and not IsSecret(w) and not IsSecret(h) and w > 0 and h > 0 then
					if frame:GetWidth() ~= w or frame:GetHeight() ~= h then
						InjectLog("size -> %.0f x %.0f (from sibling)", w, h)
						frame:SetSize(w, h)
					end
				end
				break
			end
		end
	end

	-- Manual mode deliberately never calls a Blizzard method, Layout included.
	if inject.mode ~= "manual" then
		local okLayout, err = pcall(viewer.Layout, viewer)
		if not okLayout then
			InjectLog("Layout() FAILED: %s", tostring(err))
		end
	end
end

local pendingReassert = false

local function SafeReassert(tag)
	if inject.reasserting then
		return
	end
	-- Never write to a Blizzard frame during combat.
	--
	-- Writing viewer.stride / layoutIndex taints the viewer. That is harmless until
	-- Blizzard's own code tries to boolean-test or compare a SECRET, which only
	-- happens in combat — observed as CooldownViewerItemData.lua:782 "attempt to
	-- perform boolean test on local 'hasTotem' (a secret boolean value, while
	-- execution tainted)" firing on every cast with Edit Mode open in combat.
	-- Deferring the write until combat ends removes the window entirely.
	if InCombatLockdown() then
		pendingReassert = true
		InjectLog("deferred (%s) — in combat, no writes to Blizzard frames", tag)
		return
	end
	if inject.mode == "pure" then
		-- Never write from inside whatever called us; always a fresh frame.
		if not inject.purePending then
			inject.purePending = true
			C_Timer.After(0, function()
				inject.purePending = false
				inject.reasserting = true
				InjectLog("reassert (%s, pure/deferred)", tag)
				pcall(ReassertInjection)
				inject.reasserting = false
			end)
		end
		return
	end
	inject.reasserting = true
	InjectLog("reassert (%s)", tag)
	pcall(ReassertInjection)
	inject.reasserting = false
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
combatWatcher:SetScript("OnEvent", function()
	if pendingReassert then
		pendingReassert = false
		SafeReassert("combat ended (flushing deferred)")
	end
	-- A stride write held back while Edit Mode was open is applied once it closes.
	if inject.strideWanted and inject.viewer then
		C_Timer.After(0, function()
			local em = EditModeManagerFrame
			if em and em:IsShown() then
				return
			end
			local want = inject.strideWanted
			inject.strideWanted = nil
			if want and inject.viewer and inject.viewer.stride ~= want then
				InjectLog("stride %s -> %d (flushed after Edit Mode)", tostring(inject.viewer.stride), want)
				inject.viewer.stride = want
				pcall(inject.viewer.Layout, inject.viewer)
			end
		end)
	end
end)

local function InstallInjectionHooks(viewer, viewerName)
	if inject.hookedViewers[viewerName] then
		return
	end
	inject.hookedViewers[viewerName] = true

	-- RefreshLayout rebuilds the pool and resets stride; re-assert right after so
	-- there is no visible flash. Layout() itself is NOT hooked (recursion).
	if viewer.RefreshLayout then
		hooksecurefunc(viewer, "RefreshLayout", function()
			SafeReassert("RefreshLayout")
		end)
	end
	if viewer.itemFramePool and viewer.itemFramePool.Acquire then
		-- Log only, never re-assert. Acquire fires once per item from INSIDE
		-- RefreshLayout, after ReleaseAll has emptied the container, so acting on it
		-- re-asserted against a half-built container and briefly drove stride to 1.
		-- The RefreshLayout hook runs after every acquire and is the correct moment.
		hooksecurefunc(viewer.itemFramePool, "Acquire", function()
			InjectLog("pool Acquire (observed; reassert deferred to RefreshLayout)")
		end)
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		local owner = {}
		EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
			SafeReassert("settings closed")
		end, owner)
	end
	InjectLog("hooks installed on %s", viewerName)
end

local function UpdateInjectedVisual()
	local f = inject.frame
	if not f then
		return
	end
	if track.active then
		f:SetAlpha(1)
		f.count:SetText(tostring(track.stacks))
		if f.cd then
			-- Plain numbers from our own cast-driven timer; nothing secret here.
			pcall(f.cd.SetCooldown, f.cd, track.startedAt or GetTime(), track.duration)
		end
	else
		f:SetAlpha(0.35)
		f.count:SetText("")
		if f.cd then
			pcall(f.cd.Clear, f.cd)
		end
	end
end

local function BuildInjectedFrame(viewer, useTemplate)
	-- RawLayoutChildren, not GetLayoutChildren: no Blizzard Lua executed.
	local kids = RawLayoutChildren(viewer, nil)
	local sibling = kids[1] and kids[1].frame

	local f
	if useTemplate then
		-- T2.5: can Blizzard's own virtual template be instantiated without a
		-- cooldownID? Its mixin OnLoad runs at creation, so this may throw.
		local template = (inject.viewerName == "BuffBarCooldownViewer") and "CooldownViewerBuffBarItemTemplate"
			or "CooldownViewerBuffIconItemTemplate"
		local ok, made = pcall(CreateFrame, "Frame", "TBTInjectedItem", viewer, template)
		if ok and made then
			InjectLog("created from Blizzard template %s — OK", template)
			f = made
		else
			InjectLog("Blizzard template %s FAILED: %s", template, tostring(made))
		end
	end

	if not f then
		f = CreateFrame("Frame", "TBTInjectedItem", viewer)
		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		f.icon = icon
		-- Match CDM art so the injected item is visually indistinguishable.
		pcall(function()
			local mask = f:CreateMaskTexture()
			mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
			mask:SetAllPoints(icon)
			icon:AddMaskTexture(mask)
			local overlay = f:CreateTexture(nil, "OVERLAY")
			overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
			overlay:SetPoint("TOPLEFT", -6, 5)
			overlay:SetPoint("BOTTOMRIGHT", 6, -5)
		end)
		local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
		cd:SetAllPoints(f)
		cd:SetDrawEdge(false)
		cd:SetDrawSwipe(true)
		cd:SetDrawBling(false)
		f.cd = cd
	end

	if not f.count then
		local count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		count:SetPoint("BOTTOMRIGHT", -3, 3)
		f.count = count
	end

	-- Size and scale copied from a real sibling so user scale settings are honoured.
	if sibling then
		local okW, w = pcall(sibling.GetWidth, sibling)
		local okH, h = pcall(sibling.GetHeight, sibling)
		local okS, sc = pcall(sibling.GetScale, sibling)
		if okW and okH and not IsSecret(w) and not IsSecret(h) then
			f:SetSize(w, h)
			InjectLog("sized from sibling: %.0f x %.0f", w, h)
		end
		if okS and not IsSecret(sc) then
			f:SetScale(sc)
		end
	else
		f:SetSize(40, 40)
		InjectLog("no sibling to size from — defaulted to 40x40")
	end

	-- Mirrors Blizzard's own item template KeyValue: an inactive slot still holds
	-- its grid cell rather than collapsing the row.
	f.includeAsLayoutChildWhenHidden = true
	f:Show()

	if f.icon and track.spellID then
		local ok, info = pcall(C_Spell.GetSpellInfo, track.spellID)
		if ok and type(info) == "table" and CanRead(info) then
			pcall(f.icon.SetTexture, f.icon, info.iconID)
		end
	end
	return f
end

local function DoInject(viewerName, useTemplate, mode)
	viewerName = viewerName or "BuffIconCooldownViewer"
	local viewer = _G[viewerName]
	if not viewer then
		print("|cffff4444TBT Probe|r: no viewer named " .. viewerName)
		return
	end
	if inject.frame then
		print("|cff00ccffTBT Probe|r: already injected — /tbtp uninject first")
		return
	end

	-- Hardcoded prototype subject, per plan: Eureka! driven by the cast tracker.
	if not track.spellID then
		StartTracking(1259817, 3, 15, "harmful")
	end

	wipe(inject.log)
	inject.viewer = viewer
	inject.viewerName = viewerName
	inject.mode = mode or "full"
	inject.strideBefore = viewer.stride
	InjectLog("injecting into %s mode=%s (stride before = %s)", viewerName, inject.mode, tostring(viewer.stride))

	inject.frame = BuildInjectedFrame(viewer, useTemplate)
	InstallInjectionHooks(viewer, viewerName)
	SafeReassert("initial")
	UpdateInjectedVisual()

	if not inject.ticker then
		inject.ticker = C_Timer.NewTicker(0.1, UpdateInjectedVisual)
	end

	print(
		string.format(
			"|cff00ccffTBT Probe|r: injected into %s. Cast Eureka! and watch the row re-flow. /tbtp show for numbers.",
			viewerName
		)
	)
end

local function DoUninject()
	if not inject.frame then
		print("|cff00ccffTBT Probe|r: nothing injected.")
		return
	end
	local viewer = inject.viewer
	inject.frame:Hide()
	inject.frame:SetParent(nil)
	inject.frame.layoutIndex = nil
	inject.frame = nil
	if viewer and inject.strideBefore ~= nil and inject.mode ~= "pure" then
		viewer.stride = inject.strideBefore
		pcall(viewer.Layout, viewer)
	end
	if inject.ticker then
		inject.ticker:Cancel()
		inject.ticker = nil
	end
	InjectLog("uninjected, stride restored to %s", tostring(inject.strideBefore))
	print("|cff00ccffTBT Probe|r: uninjected. Hooks remain installed until /reload.")
end

local function SectionInjection()
	if not inject.viewerName then
		return
	end
	Add("--- CDM INJECTION PROTOTYPE ---")
	Row("target viewer", inject.viewerName)
	Row("mode", inject.mode .. "  (full | nostride | manual)")
	Row("currently injected", tostring(inject.frame ~= nil))
	Row("stride before injection", tostring(inject.strideBefore))
	local viewer = inject.viewer
	if viewer then
		Row("stride now", Describe(viewer.stride))
		Row("viewer:GetStride() (Blizzard's own)", SafeCall(viewer, "GetStride"))
		Row("uses count-as-stride", tostring(ViewerUsesCountAsStride(inject.viewerName)))
		local children = LayoutChildrenOf(viewer)
		if children then
			Row("#GetLayoutChildren()", tostring(#children))
			Add("")
			Add("  positions — even spacing here is the acceptance test:")
			for i, c in ipairs(children) do
				local okL, left = pcall(c.GetLeft, c)
				local okB, bottom = pcall(c.GetBottom, c)
				local mine = (c == inject.frame) and "  <== TBT" or ""
				Row(
					string.format("    child %d layoutIndex=%s", i, Describe(c.layoutIndex)),
					string.format(
						"left=%s bottom=%s w=%s shown=%s%s",
						okL and Describe(left) or "?",
						okB and Describe(bottom) or "?",
						Describe(select(2, pcall(c.GetWidth, c))),
						Describe(select(2, pcall(c.IsShown, c))),
						mine
					)
				)
			end
		end
	end
	Add("")
	Row("event log", #inject.log .. " entries")
	for _, line in ipairs(inject.log) do
		Add("    " .. line)
	end
	Add("")
end

local function SectionAuraAPI()
	Add("--- AURA API (lower priority: doc-inference probes) ---")
	if not C_UnitAuras then
		Row("C_UnitAuras", "MISSING")
		Add("")
		return
	end
	local ids =
		Probe("GetUnitAuraInstanceIDs(player,HELPFUL)", C_UnitAuras.GetUnitAuraInstanceIDs, "player", "HELPFUL", 10)
	if type(ids) == "table" and CanRead(ids) then
		for i = 1, math.min(#ids, 3) do
			Row("  instanceID[" .. i .. "]", Describe(ids[i]))
		end
		local first = ids[1]
		if first ~= nil and not IsSecret(first) then
			Probe(
				"  GetAuraDataByAuraInstanceID(readable id)",
				C_UnitAuras.GetAuraDataByAuraInstanceID,
				"player",
				first
			)
			Probe(
				"  GetAuraApplicationDisplayCount",
				C_UnitAuras.GetAuraApplicationDisplayCount,
				"player",
				first,
				1,
				99
			)
			Probe("  DoesAuraHaveExpirationTime", C_UnitAuras.DoesAuraHaveExpirationTime, "player", first)
			Probe("  GetAuraDuration", C_UnitAuras.GetAuraDuration, "player", first)
			Probe("  GetAuraBaseDuration", C_UnitAuras.GetAuraBaseDuration, "player", first)
		else
			Row("  (instance IDs not readable)", "richer aura APIs unreachable this way")
		end
	end
	Probe("GetUnitAuras(player,HELPFUL) [control]", C_UnitAuras.GetUnitAuras, "player", "HELPFUL", 10)
	Probe("GetAuraSlots(player,HELPFUL)", C_UnitAuras.GetAuraSlots, "player", "HELPFUL", 10)
	if probeCdmSpell then
		Probe("GetPlayerAuraBySpellID(cdm spell)", C_UnitAuras.GetPlayerAuraBySpellID, probeCdmSpell)
	end
	Add("")
	Row("last UNIT_AURA payload", "")
	Add("    " .. lastAuraPayload)
	Add("")
end

---------------------------------------------------------------------------------------------------
-- UNIT_AURA payload capture

local watcher = CreateFrame("Frame")
watcher:RegisterUnitEvent("UNIT_AURA", "player")
watcher:SetScript("OnEvent", function(_, _, _, updateInfo)
	-- Describe immediately: restrictions can change before the report is built.
	local parts = { "updateInfo=" .. Describe(updateInfo) }
	if type(updateInfo) == "table" and CanRead(updateInfo) then
		parts[#parts + 1] = "isFullUpdate=" .. Describe(updateInfo.isFullUpdate)
		parts[#parts + 1] = "addedAuras=" .. Describe(updateInfo.addedAuras)
		parts[#parts + 1] = "updatedAuraInstanceIDs=" .. Describe(updateInfo.updatedAuraInstanceIDs)
		parts[#parts + 1] = "removedAuraInstanceIDs=" .. Describe(updateInfo.removedAuraInstanceIDs)
		local removed = updateInfo.removedAuraInstanceIDs
		if type(removed) == "table" and CanRead(removed) and removed[1] ~= nil then
			parts[#parts + 1] = "removed[1]=" .. Describe(removed[1])
		end
		local added = updateInfo.addedAuras
		if type(added) == "table" and CanRead(added) and type(added[1]) == "table" and CanRead(added[1]) then
			parts[#parts + 1] = "added[1].spellId=" .. Describe(added[1].spellId)
			parts[#parts + 1] = "added[1].auraInstanceID=" .. Describe(added[1].auraInstanceID)
			parts[#parts + 1] = "added[1].applications=" .. Describe(added[1].applications)
		end
	end
	lastAuraPayload = table.concat(parts, ", ")
	-- An aura event is the moment a stack is consumed, so sample on it too rather
	-- than relying on the 0.1s ticker to land at the right instant.
	WatchSample("UNIT_AURA")
end)

---------------------------------------------------------------------------------------------------
-- copy window

local copyFrame
local function ShowCopyWindow(text)
	if not copyFrame then
		local f = CreateFrame("Frame", "TBTProbeCopyFrame", UIParent)
		f:SetSize(760, 520)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)

		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.04, 0.04, 0.05, 0.96)

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", 0, -12)
		title:SetText("TBT Probe — Ctrl+A then Ctrl+C")

		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 0, 0)

		local scroll = CreateFrame("ScrollFrame", "TBTProbeCopyScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -40)
		scroll:SetPoint("BOTTOMRIGHT", -34, 14)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetMaxLetters(0)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(700)
		edit:SetScript("OnEscapePressed", function()
			f:Hide()
		end)
		scroll:SetScrollChild(edit)

		f.edit = edit
		tinsert(UISpecialFrames, "TBTProbeCopyFrame")
		copyFrame = f
	end
	copyFrame.edit:SetText(text)
	-- Give the scroll child an explicit height; some clients do not auto-grow it.
	copyFrame.edit:SetHeight(math.max(420, #report * 14))
	copyFrame.edit:HighlightText()
	copyFrame.edit:SetFocus()
	copyFrame:Show()
end

---------------------------------------------------------------------------------------------------
-- live test bar (visual confirmation of T1.2 / T1.3)

local testBar
local function ShowTestBar()
	if type(probeSpell) ~= "number" then
		print("|cff00ccffTBT Probe|r: no probe spell selected.")
		return
	end
	if not testBar then
		local f = CreateFrame("Frame", "TBTProbeTestBar", UIParent)
		f:SetSize(260, 34)
		f:SetPoint("CENTER", 0, -160)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)

		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.7)

		local icon = CreateFrame("Frame", nil, f)
		icon:SetSize(30, 30)
		icon:SetPoint("LEFT", 2, 0)
		local tex = icon:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		f.icon = tex

		local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		cd:SetAllPoints(icon)
		cd:SetDrawEdge(false)
		cd:SetDrawSwipe(true)
		f.cd = cd

		local bar = CreateFrame("StatusBar", nil, f)
		bar:SetPoint("LEFT", icon, "RIGHT", 4, 0)
		bar:SetPoint("RIGHT", -4, 0)
		bar:SetHeight(20)
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetStatusBarColor(0.2, 0.7, 1)
		bar:SetMinMaxValues(0, 1)
		f.bar = bar

		local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", 4, 0)
		f.label = label

		tinsert(UISpecialFrames, "TBTProbeTestBar")
		testBar = f
	end

	local ok, info = pcall(C_Spell.GetSpellInfo, probeSpell)
	if ok and type(info) == "table" and CanRead(info) then
		-- SetTexture is AllowedWhenTainted, so a secret iconID is fine here.
		pcall(testBar.icon.SetTexture, testBar.icon, info.iconID)
	end
	testBar.label:SetText(SpellLabel(probeSpell))

	-- Refresh the handle on cooldown events only; the engine animates in between.
	local function Refresh()
		local okd, dur = pcall(C_Spell.GetSpellCooldownDuration, probeSpell, false)
		if not okd or dur == nil then
			return
		end
		pcall(testBar.cd.SetCooldownFromDurationObject, testBar.cd, dur)
		pcall(
			testBar.bar.SetTimerDuration,
			testBar.bar,
			dur,
			Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate,
			Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
		)
	end

	testBar:UnregisterAllEvents()
	testBar:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	testBar:RegisterEvent("SPELL_UPDATE_CHARGES")
	testBar:SetScript("OnEvent", Refresh)
	Refresh()
	testBar:Show()
	print(
		"|cff00ccffTBT Probe|r: test bar shown for " .. SpellLabel(probeSpell) .. ". Use the spell and watch it drain."
	)
end

---------------------------------------------------------------------------------------------------
-- run

local function BuildReport()
	wipe(report)
	local cdmSet, cdmCount = BuildCdmSpellSet()
	if not probeSpell or not probeCdmSpell then
		local auto, autoCdm = PickProbeSpells(cdmSet)
		probeSpell = probeSpell or auto
		probeCdmSpell = probeCdmSpell or autoCdm
	end

	local inInstance = IsInInstance()
	local scenario = "S1 (out of combat, open world)"
	if InCombatLockdown() then
		scenario = inInstance and "S3 (combat, inside instance)" or "S2 (combat, open world)"
	elseif inInstance then
		scenario = "S1-variant (out of combat, inside instance)"
	end

	Add("===== TBT PROBE REPORT =====")
	Add("scenario (auto-detected): " .. scenario)
	Add("recorded: " .. date("%Y-%m-%d %H:%M:%S"))
	Add("")
	SectionContext()
	SectionSpellSelection(cdmSet, cdmCount)
	local dur = SectionCooldownAPI("T1 COOLDOWN API — NON-CDM SPELL", probeSpell)
	SectionCooldownAPI("T1 COOLDOWN API — CDM-TRACKED SPELL (comparison)", probeCdmSpell)
	SectionSinks(dur)
	SectionItems()
	SectionCdmContainer()
	SectionWatchedAura()
	SectionTrack()
	SectionInjection()
	SectionAuraAPI()
	Add("===== END OF REPORT =====")

	return table.concat(report, "\n")
end

local lastReport

local function Run()
	local ok, text = pcall(BuildReport)
	if not ok then
		print("|cffff4444TBT Probe FAILED|r: " .. tostring(text))
		return
	end
	lastReport = text
	print("|cff00ccffTBT Probe|r: report built, " .. #report .. " lines. Use |cffffff00/tbtp show|r to copy it.")
	-- Compact chat summary so a glance is possible without opening the window.
	for _, line in ipairs(report) do
		if
			line:find("scenario", 1, true)
			or line:find("ShouldAurasBeSecret", 1, true)
			or line:find("ShouldCooldownsBeSecret", 1, true)
			or line:find("GetSpellCooldownDuration", 1, true)
			or line:find("SetTimerDuration", 1, true)
			or line:find("SetCooldownFromDurationObject", 1, true)
			or line:find("auraDataCached", 1, true)
		then
			print("  " .. line)
		end
	end
end

SLASH_TBTPROBE1 = "/tbtp"
SLASH_TBTPROBE2 = "/tbtprobe"
SlashCmdList.TBTPROBE = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = msg:match("^(%S*)%s*(.*)$")

	if cmd == "show" then
		if not lastReport then
			Run()
		end
		ShowCopyWindow(lastReport or "(no report)")
	elseif cmd == "spell" then
		probeSpell = tonumber(arg)
		print("|cff00ccffTBT Probe|r: non-CDM probe spell = " .. SpellLabel(probeSpell))
	elseif cmd == "cdmspell" then
		probeCdmSpell = tonumber(arg)
		print("|cff00ccffTBT Probe|r: CDM probe spell = " .. SpellLabel(probeCdmSpell))
	elseif cmd == "list" then
		local cdmSet = BuildCdmSpellSet()
		local list = CollectCandidates(cdmSet)
		print("|cff00ccffTBT Probe|r: " .. #list .. " candidate spells ([CDM] = tracked by the Cooldown Manager)")
		for i = 1, math.min(#list, 40) do
			local c = list[i]
			print(string.format("  %s %s", c.isCdm and "|cffffff00[CDM]|r" or "      ", SpellLabel(c.id)))
		end
		print("Pick one with a real cooldown: |cffffff00/tbtp spell <id>|r")
	elseif cmd == "unsafe" then
		safeMode = false
		print("|cffff8800TBT Probe|r: safe mode OFF — Blizzard CDM mixin methods will be called.")
		print("  This is a known taint source. Expect Edit Mode errors afterwards; /reload to clear.")
	elseif cmd == "safe" then
		safeMode = true
		print("|cff00ccffTBT Probe|r: safe mode ON — Blizzard CDM mixin methods will not be called.")
	elseif cmd == "inject" then
		local viewerName, useTemplate, mode = nil, false, "full"
		for word in arg:gmatch("%S+") do
			if word == "bar" then
				viewerName = "BuffBarCooldownViewer"
			elseif word == "essential" then
				viewerName = "EssentialCooldownViewer"
			elseif word == "utility" then
				viewerName = "UtilityCooldownViewer"
			elseif word == "template" then
				useTemplate = true
			elseif word == "nostride" or word == "manual" or word == "full" or word == "deferred" or word == "pure" then
				mode = word
			elseif word:find("CooldownViewer") then
				viewerName = word
			end
		end
		DoInject(viewerName, useTemplate, mode)
	elseif cmd == "uninject" then
		DoUninject()
	elseif cmd == "track" then
		local id, stacks, dur, mode = arg:match("^(%S*)%s*(%S*)%s*(%S*)%s*(%S*)$")
		id = tonumber(id)
		if not id then
			print("|cff00ccffTBT Probe|r: usage /tbtp track <spellID> [stacks] [duration] [harmful|any]")
			print("  e.g. /tbtp track 1259817 3 15 harmful")
		else
			StartTracking(id, tonumber(stacks), tonumber(dur), (mode ~= "" and mode) or nil)
		end
	elseif cmd == "auras" then
		local ok, text = pcall(BuildAuraDump)
		if not ok then
			print("|cffff4444TBT Probe aura dump FAILED|r: " .. tostring(text))
		else
			lastReport = text
			ShowCopyWindow(text)
		end
	elseif cmd == "watch" then
		if arg == "stop" then
			StopWatch()
		else
			local id = tonumber(arg)
			if not id then
				print("|cff00ccffTBT Probe|r: usage /tbtp watch <spellID>   (or /tbtp watch stop)")
			else
				StartWatch(id)
			end
		end
	elseif cmd == "bar" then
		ShowTestBar()
	elseif cmd == "help" then
		print("|cff00ccffTBT Probe|r commands:")
		print("  /tbtp            run the probe and print a summary")
		print("  /tbtp show       open the copy window (Ctrl+A, Ctrl+C)")
		print("  /tbtp spell <id> set the non-CDM probe spell")
		print("  /tbtp cdmspell <id>  set the CDM-tracked comparison spell")
		print("  /tbtp list       list candidate spells, marking CDM-tracked ones")
		print("  /tbtp bar        show a live test bar driven by a duration handle")
		print("  /tbtp auras      dump every aura on you — use this to find an aura's real spellID")
		print("  /tbtp track <id> [stacks] [dur] [harmful|any]  cast-driven stack prototype")
		print("  /tbtp inject [bar|essential|utility] [full|nostride|manual] [template]")
		print("      full=layoutIndex+stride  nostride=layoutIndex only  manual=no Blizzard writes")
		print("  /tbtp uninject   remove the injected frame and restore stride")
		print("  /tbtp safe | unsafe   toggle calling Blizzard CDM mixin methods (taint source)")
		print("  /tbtp watch <id> log a stacking aura over time + show a live stack widget")
		print("  /tbtp watch stop stop watching")
	else
		Run()
	end
end

print("|cff00ccffTBT Probe|r loaded. |cffffff00/tbtp help|r")
