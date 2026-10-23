-- TBT Duration Probe — throwaway, never shipped (v0.5.3 kickoff, 2026-10-22).
--
-- Answers, on retail, the questions the "buff duration alongside cooldowns" milestone depends on:
--   Q1  Item aura parity: does the buff an item applies carry the item's use-spell ID
--       (C_Item.GetItemSpell), or a different aura ID?
--   Q2  Spell aura parity: for the player's cooldown spells, is the buff's aura ID the cast
--       spellID? Checked live (cast -> aura added) and statically through the CDM's own
--       linkedSpellIDs for every cooldown entry.
--   Q3  Static duration: can a buff's duration be had BEFORE the buff is ever up — from the
--       spell description or the spell/item tooltip — and is any of it secret?
--   Q4  Aura secrecy: C_Secrets.GetSpellAuraSecrecy for each candidate aura ID.
--
-- Usage (retail, out of combat unless a step says otherwise):
--   /tbtd scan          bag consumables + equipped trinkets + CDM cooldown entries (Q1-Q4 static)
--   /tbtd spell <id>    static lookup for one spell
--   /tbtd item <id>     static lookup for one item
--   (live)              just use items / cast cooldowns; every cast and the auras added within
--                       1.5s after it are logged with a PARITY verdict. Out of combat first, then
--                       a couple in combat to see what turns secret.
--   /tbtd show          copy window with everything so far      /tbtd clear   reset the log
--
-- Secret-value discipline: issecretvalue() first, before type/compare/concat/index.

local report = {}

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function D(v)
	if IsSecret(v) then
		return "<SECRET>"
	end
	if v == nil then
		return "nil"
	end
	local t = type(v)
	if t == "table" then
		if canaccesstable and not canaccesstable(v) then
			return "<forbidden table>"
		end
		local parts = {}
		for i = 1, #v do
			parts[#parts + 1] = D(v[i])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
end

local function Log(fmt, ...)
	local n = select("#", ...)
	local args = {}
	for i = 1, n do
		args[i] = D((select(i, ...)))
	end
	local line = (n > 0) and fmt:format(unpack(args, 1, n)) or fmt
	report[#report + 1] = line
end

local function Call(fn, ...)
	if not fn then
		return false, "<missing API>"
	end
	return pcall(fn, ...)
end

-- Every "N sec" / "N min" / "N.N sec" in a string, as seconds. enUS only — this probe is asking
-- whether the text is READABLE and carries the number, not shipping a parser.
local function ParseDurations(text)
	if IsSecret(text) then
		return "<SECRET text>"
	end
	if type(text) ~= "string" or text == "" then
		return "none"
	end
	local found = {}
	for num, unit in text:gmatch("(%d+%.?%d*)%s*(%a+)") do
		local u = unit:lower()
		local n = tonumber(num)
		if n and (u == "sec" or u == "seconds" or u == "second") then
			found[#found + 1] = n .. "s"
		elseif n and (u == "min" or u == "minutes" or u == "minute") then
			found[#found + 1] = (n * 60) .. "s"
		elseif n and (u == "hr" or u == "hour" or u == "hours") then
			found[#found + 1] = (n * 3600) .. "s"
		end
	end
	return (#found > 0) and table.concat(found, " ") or "none"
end

local function TooltipText(data)
	if IsSecret(data) or type(data) ~= "table" then
		return nil, D(data)
	end
	if canaccesstable and not canaccesstable(data) then
		return nil, "<forbidden>"
	end
	local lines = data.lines
	if type(lines) ~= "table" then
		return nil, "no lines"
	end
	local out = {}
	for i = 1, #lines do
		local l = lines[i]
		local left = l and l.leftText
		if IsSecret(left) then
			return nil, "<SECRET line " .. i .. ">"
		end
		if type(left) == "string" and left ~= "" then
			out[#out + 1] = left
		end
	end
	return table.concat(out, " | "), nil
end

local SECRECY_NAMES = { [0] = "NeverSecret", [1] = "AlwaysSecret", [2] = "ContextuallySecret" }
local function Secrecy(spellID)
	if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy) then
		return "<missing API>"
	end
	local ok, lvl = pcall(C_Secrets.GetSpellAuraSecrecy, spellID)
	if not ok then
		return "ERR " .. D(lvl)
	end
	if IsSecret(lvl) then
		return "<SECRET>"
	end
	return SECRECY_NAMES[lvl] or D(lvl)
end

local function SpellName(spellID)
	local ok, name = Call(C_Spell and C_Spell.GetSpellName, spellID)
	return ok and D(name) or ("ERR " .. D(name))
end

local function StaticSpell(spellID, indent)
	indent = indent or "  "
	local okD, desc = Call(C_Spell and C_Spell.GetSpellDescription, spellID)
	local descDur = okD and ParseDurations(desc) or ("ERR " .. D(desc))
	local okT, tip = Call(C_TooltipInfo and C_TooltipInfo.GetSpellByID, spellID)
	local tipText, tipErr
	if okT then
		tipText, tipErr = TooltipText(tip)
	else
		tipErr = "ERR " .. D(tip)
	end
	local tipDur = tipText and ParseDurations(tipText) or ("(" .. D(tipErr) .. ")")
	local okA, aura = Call(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, spellID)
	local auraState
	if not okA then
		auraState = "ERR " .. D(aura)
	elseif aura == nil then
		auraState = "not up"
	elseif IsSecret(aura) then
		auraState = "<SECRET aura>"
	else
		auraState = "UP dur=" .. D(aura.duration) .. " exp=" .. D(aura.expirationTime)
	end
	Log(
		"%sspell %s '%s' secrecy=%s | desc-dur=%s | tip-dur=%s | aura-now=%s",
		indent,
		spellID,
		SpellName(spellID),
		Secrecy(spellID),
		descDur,
		tipDur,
		auraState
	)
	if okD and not IsSecret(desc) and type(desc) == "string" and desc ~= "" then
		Log("%s  desc: %s", indent, desc:gsub("[\r\n]+", " "))
	elseif okD and not IsSecret(desc) and (desc == nil or desc == "") then
		Log("%s  desc: <empty — spell data maybe not loaded yet; rerun>", indent)
	end
end

-- itemID -> use-spellID, for the live watcher to recognise item casts.
local useSpellToItem = {}

local function StaticItem(itemID, where)
	local okS, spellName, useSpellID = Call(C_Item and C_Item.GetItemSpell, itemID)
	local okN, itemName = Call(C_Item and C_Item.GetItemNameByID, itemID)
	if not okS then
		Log("item %s (%s) GetItemSpell ERR %s", itemID, where, spellName)
		return
	end
	Log("item %s '%s' (%s) useSpell=%s '%s'", itemID, okN and itemName or "?", where, useSpellID, spellName)
	if not IsSecret(useSpellID) and type(useSpellID) == "number" then
		useSpellToItem[useSpellID] = itemID
		StaticSpell(useSpellID)
	end
	local okT, tip = Call(C_TooltipInfo and C_TooltipInfo.GetItemByID, itemID)
	if okT then
		local text, err = TooltipText(tip)
		if text then
			local use = text:match("Use:[^|]*") or "(no Use: line)"
			Log("  item-tip Use-dur=%s | %s", ParseDurations(use), use)
		else
			Log("  item-tip %s", err)
		end
	else
		Log("  item-tip ERR %s", tip)
	end
end

local function ScanBags()
	Log("== Bag consumables (the Suggested catalogue's filter: class 0, not bandage, has use-spell)")
	local seen = {}
	for bag = 0, 4 do
		local okN, slots = Call(C_Container and C_Container.GetContainerNumSlots, bag)
		if okN and not IsSecret(slots) and type(slots) == "number" then
			for slot = 1, slots do
				local okI, id = Call(C_Container.GetContainerItemID, bag, slot)
				if okI and not IsSecret(id) and type(id) == "number" and not seen[id] then
					seen[id] = true
					local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
					if classID == 0 and subClassID ~= 7 then
						local _, useSpellID = C_Item.GetItemSpell(id)
						if useSpellID then
							StaticItem(id, "bag")
						end
					end
				end
			end
		end
	end
end

local function ScanTrinkets()
	Log("== Equipped trinkets")
	for _, slot in ipairs({ 13, 14 }) do
		local id = GetInventoryItemID("player", slot)
		if IsSecret(id) then
			Log("slot %s: <SECRET itemID>", slot)
		elseif id then
			StaticItem(id, "slot " .. slot)
		else
			Log("slot %s: empty", slot)
		end
	end
end

-- Q2 static: does each CDM cooldown entry list its own spellID among linkedSpellIDs, or point at
-- a different aura? Read-only C_CooldownViewer data, no frame or mixin is touched.
local CATEGORY_NAMES = { [0] = "Essential", [1] = "Utility", [2] = "TrackedBuff", [3] = "TrackedBar" }
local function ScanCDM()
	Log("== CDM cooldown entries (C_CooldownViewer, read only)")
	if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
		Log("C_CooldownViewer missing")
		return
	end
	for cat = 0, 3 do
		local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
		if not ok or IsSecret(ids) or type(ids) ~= "table" then
			Log("category %s: %s", CATEGORY_NAMES[cat], ok and D(ids) or ("ERR " .. D(ids)))
		else
			Log("-- category %s (%s entries incl. unlearned)", CATEGORY_NAMES[cat], #ids)
			for _, cdID in ipairs(ids) do
				local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
				if okI and type(info) == "table" and not IsSecret(info) then
					local sid = info.spellID
					local linked = info.linkedSpellIDs
					local verdict = "-"
					if not IsSecret(sid) and type(linked) == "table" and not IsSecret(linked) then
						if #linked == 0 then
							verdict = "no linked aura"
						else
							verdict = "linked differs"
							for i = 1, #linked do
								if not IsSecret(linked[i]) and linked[i] == sid then
									verdict = "linked == spellID"
								end
							end
						end
					end
					if info.isKnown or cat <= 1 then
						Log(
							"  cd %s spell=%s '%s' known=%s selfAura=%s hasAura=%s linked=%s item(slot=%s cat=%s) -> %s",
							cdID,
							sid,
							sid and SpellName(sid) or "-",
							info.isKnown,
							info.selfAura,
							info.hasAura,
							linked,
							info.equipSlot,
							info.spellCategoryID,
							verdict
						)
					end
					if cat <= 1 and info.isKnown and not IsSecret(sid) and type(sid) == "number" then
						StaticSpell(sid, "      ")
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- live: cast -> auras added in the next 1.5s

local WINDOW = 1.5
local pending = {} -- { spellID, t, itemID }

local function OnCast(spellID)
	if IsSecret(spellID) then
		Log("[cast] <SECRET spellID>")
		return
	end
	local itemID = useSpellToItem[spellID]
	pending[#pending + 1] = { spellID = spellID, t = GetTime(), itemID = itemID, matched = false }
	Log(
		"[cast] %s '%s'%s combat=%s aurasSecret=%s",
		spellID,
		SpellName(spellID),
		itemID and (" (item " .. itemID .. ")") or "",
		InCombatLockdown(),
		C_Secrets and C_Secrets.ShouldAurasBeSecret and D(C_Secrets.ShouldAurasBeSecret()) or "?"
	)
	-- Direct lookup with the cast ID: answers parity without the UNIT_AURA payload at all.
	C_Timer.After(0.3, function()
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
		if not ok then
			Log("  [+0.3s] GetPlayerAuraBySpellID(cast %s) ERR %s", spellID, aura)
		elseif aura == nil then
			Log("  [+0.3s] GetPlayerAuraBySpellID(cast %s) = nil (no aura with the cast ID)", spellID)
		elseif IsSecret(aura) then
			Log("  [+0.3s] GetPlayerAuraBySpellID(cast %s) = <SECRET>", spellID)
		else
			Log(
				"  [+0.3s] GetPlayerAuraBySpellID(cast %s) FOUND dur=%s exp=%s",
				spellID,
				aura.duration,
				aura.expirationTime
			)
		end
	end)
end

local function OnAura(info)
	if IsSecret(info) or type(info) ~= "table" then
		return
	end
	local added = info.addedAuras
	if IsSecret(added) or type(added) ~= "table" or #added == 0 then
		return
	end
	local now = GetTime()
	for i = #pending, 1, -1 do
		if now - pending[i].t > WINDOW then
			if not pending[i].matched then
				Log("  [cast %s] no aura added within %ss", pending[i].spellID, WINDOW)
			end
			table.remove(pending, i)
		end
	end
	if #pending == 0 then
		return
	end
	for _, a in ipairs(added) do
		local aid = a.spellId
		if IsSecret(aid) then
			Log("  [aura+] <SECRET spellId> dur=%s helpful=%s", a.duration, a.isHelpful)
		elseif a.sourceUnit == nil or IsSecret(a.sourceUnit) or a.sourceUnit == "player" then
			for _, p in ipairs(pending) do
				local verdict = (aid == p.spellID) and "PARITY MATCH" or "DIFFERS"
				p.matched = true
				Log(
					"  [aura+] %s '%s' dur=%s after cast %s%s +%.2fs -> %s",
					aid,
					SpellName(aid),
					a.duration,
					p.spellID,
					p.itemID and (" (item " .. p.itemID .. ")") or "",
					now - p.t,
					verdict
				)
			end
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:SetScript("OnEvent", function(_, event, _, a2, a3)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		OnCast(a3)
	else
		OnAura(a2)
	end
end)

---------------------------------------------------------------------------------------------------
-- copy window

local copyFrame
local function ShowCopyWindow(text)
	if not copyFrame then
		local w = CreateFrame("Frame", "TBTDurationProbeCopy", UIParent)
		w:SetSize(860, 560)
		w:SetPoint("CENTER")
		w:SetFrameStrata("FULLSCREEN_DIALOG")
		w:EnableMouse(true)
		w:SetMovable(true)
		w:RegisterForDrag("LeftButton")
		w:SetScript("OnDragStart", w.StartMoving)
		w:SetScript("OnDragStop", w.StopMovingOrSizing)
		local bg = w:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.04, 0.04, 0.05, 0.96)
		local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", 0, -12)
		title:SetText("TBT Duration Probe — Ctrl+A then Ctrl+C")
		local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 0, 0)
		local scroll = CreateFrame("ScrollFrame", "TBTDurationProbeScroll", w, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -40)
		scroll:SetPoint("BOTTOMRIGHT", -34, 14)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetMaxLetters(0)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(800)
		edit:SetScript("OnEscapePressed", function()
			w:Hide()
		end)
		scroll:SetScrollChild(edit)
		w.edit = edit
		tinsert(UISpecialFrames, "TBTDurationProbeCopy")
		copyFrame = w
	end
	copyFrame.edit:SetText(text)
	copyFrame.edit:SetHeight(math.max(460, #report * 14))
	copyFrame.edit:HighlightText()
	copyFrame.edit:SetFocus()
	copyFrame:Show()
end

local function Header()
	local _, build, _, iface = GetBuildInfo()
	Log("TBT Duration Probe — build %s iface %s, %s", build, iface, date("%Y-%m-%d %H:%M"))
end

SLASH_TBTDURATION1 = "/tbtd"
SlashCmdList.TBTDURATION = function(msg)
	local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "scan" then
		Header()
		ScanTrinkets()
		ScanBags()
		ScanCDM()
		print("TBT Duration Probe: scan done (" .. #report .. " lines). /tbtd show")
	elseif cmd == "spell" and tonumber(arg) then
		StaticSpell(tonumber(arg), "")
		print("TBT Duration Probe: logged. /tbtd show")
	elseif cmd == "item" and tonumber(arg) then
		StaticItem(tonumber(arg), "manual")
		print("TBT Duration Probe: logged. /tbtd show")
	elseif cmd == "show" then
		ShowCopyWindow(table.concat(report, "\n"))
	elseif cmd == "clear" then
		wipe(report)
		wipe(pending)
		print("TBT Duration Probe: cleared")
	else
		print("/tbtd scan | spell <id> | item <id> | show | clear   (casts are logged live)")
	end
end
