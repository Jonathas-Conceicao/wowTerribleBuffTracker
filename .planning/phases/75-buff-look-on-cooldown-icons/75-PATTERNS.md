# Phase 75: Buff Look on Cooldown Icons - Pattern Map

**Mapped:** 2026-10-22
**Files analyzed:** 1 modified (Display.lua), plus read-only design inputs (BuffEngine.lua preview, Core.lua predicates, Phase 74 helpers)
**Analogs found:** 1 / 1 (the analogs all live inside Display.lua itself; ground truth is Blizzard's CDM source)

Line numbers are as of 2026-10-22, on the branch with Phase 74 plan 74-02 **not yet executed**
(`ns:CooldownBuffDuration` does not exist in Core.lua yet; 74-02 adds it right after
`ns:IsCooldownRunning`, Core.lua ~738-748). Phase 74 makes **no code change** in Display.lua (comments
only, at :104-108, :759-762, :790-791), so the code line numbers below should still hold after 74-02,
give or take a few lines where comments are rewritten.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Display.lua` — new swipe-look helper (buff/yellow vs cooldown/dark), stamped | utility (widget styler) | per-tick render, dirty-checked | `ApplyUserCooldown` stamp idiom (Display.lua:1062-1112) + `ClearIconDesaturation` (:814-819) | exact (same file, same idiom) |
| `Display.lua` — `RenderIconContainer` live-timer branch (:1634-1663) | component (render branch) | per-tick render | itself + cooldown-slot branch (:1664-1677) | exact |
| `Display.lua` — `ClearCooldownStamps` (:858-865) | utility (pooled-widget reset) | per-tick render | itself | exact |
| `Display.lua` — count survival during buff (BUFFDISP-04) | utility | generation-gated | `ApplyCooldownSlot` gen block (:1136-1156) | exact |
| `BuffEngine.lua` `ns:StartAllPreviewTimers` (:1513-1572) | read-only input | preview | — (74-02 already changes it to preview the buff duration) | n/a, no edit expected |

## Blizzard ground truth (read-only: `C:\Users\jonat\Repositories\wow-ui-source`, branch `live`)

### Colours — `Blizzard_CooldownViewer/CooldownViewer.lua:14-22`
```lua
CooldownViewerConstants = {
	...
	ITEM_AURA_COLOR = CreateColor(1, 0.95, 0.57, 0.7);
	ITEM_COOLDOWN_COLOR = CreateColor(0, 0, 0, 0.7);
};
```

### Aura state — `CooldownViewerCooldownItemMixin:CheckCacheCooldownValuesFromAura` (CooldownViewer.lua:861-907)
Totem arm :866-881, aura arm :883-905. The aura arm:
```lua
		local auraData = self:GetAuraDataCached();
		if auraData then
			-- NOTE: Auras are in a priority class where we want to show their cooldown info, but keep the charge count display, but not the charge cooldown display.
			self:AddVisualDataSource_Aura();
			self.cooldownEnabled = true;
			self.cooldownStartTime = auraData.expirationTime - auraData.duration;
			self.cooldownDuration = auraData.duration;
			self.cooldownModRate = auraData.timeMod;
			self.cooldownSwipeColor = CooldownViewerConstants.ITEM_AURA_COLOR;
			self.cooldownShowDrawEdge = false;
			self.cooldownShowSwipe = true;
			self.cooldownUseAuraDisplayTime = true;
			self.cooldownPlayFlash = false;
			self.cooldownPaused = false;

			-- This may have already been set by CheckCacheCooldownValuesFromSpellCooldown
			if not self:IsActivelyCast() or self:GetAuraDataUnit() == "player" then
				self.cooldownDesaturated = false;
			end
```
The NOTE comment at :885-886 is Blizzard's own statement of BUFFDISP-04: **the charge count stays during the aura**, only the charge *sweep* is replaced. Comment at :864: "If the spell results in a self buff, give those values precedence over the spell's cooldown until the buff is gone" — i.e. the aura replaces the cooldown sweep entirely while it runs (BUFFDISP: cooldown not shown during the buff).

### Cooldown states (for contrast)
- Charges, `CheckCacheCooldownValuesFromCharges` :909-935 — `ITEM_COOLDOWN_COLOR`, `cooldownShowDrawEdge = true`, `cooldownShowSwipe = false` (edge only; TBT deliberately diverges, see Display.lua:935-937).
- Spell cooldown, `CheckCacheCooldownValuesFromSpellCooldown` :979-1012 — `ITEM_COOLDOWN_COLOR` (:1003), `cooldownShowDrawEdge = false` (:1004), `cooldownShowSwipe = true`, `cooldownUseAuraDisplayTime = false`, `cooldownDesaturated = self.isOnActualCooldown` (:1008).
- Equipped item :1016-1046 and Edit Mode :1048-1060 — `ITEM_COOLDOWN_COLOR`, edge false.

### Where the state is applied — `RefreshSpellCooldownInfo` (CooldownViewer.lua:1138-1153)
```lua
	if isExpired then
		CooldownFrame_Clear(cooldownFrame);
		cooldownFrame:SetDrawEdge(false);
	else
		cooldownFrame:SetSwipeColor(self.cooldownSwipeColor.r, self.cooldownSwipeColor.g, self.cooldownSwipeColor.b, self.cooldownSwipeColor.a);
		cooldownFrame:SetDrawSwipe(self.cooldownShowSwipe);
		cooldownFrame:SetUseAuraDisplayTime(self.cooldownUseAuraDisplayTime);
		CooldownFrame_Set(cooldownFrame, self.cooldownStartTime, self.cooldownDuration, self.cooldownEnabled, self.cooldownShowDrawEdge, self.cooldownModRate);
	end
```
Desaturation, `RefreshIconDesaturation` :1196-1202:
```lua
	local desaturated = self.cooldownDesaturated and not self:IsExpired();
	iconTexture:SetDesaturated(desaturated);
```

### `CooldownFrame_Set` — `Blizzard_FrameXMLUtil/Cooldown.lua:2-13`
```lua
function CooldownFrame_Set(self, start, duration, enable, forceShowDrawEdge, modRate)
	if enable and enable ~= 0 and start > 0 and duration > 0 then
		self:SetDrawEdge(not not forceShowDrawEdge);
		self:SetCooldown(start, duration, modRate);
	else
		CooldownFrame_Clear(self);
	end
end

function CooldownFrame_Clear(self)
	self:Clear();
end
```
So the `drawEdge` argument is just `SetDrawEdge(bool)` immediately before `SetCooldown`. It never touches reverse.

### Reverse is fixed per template, never toggled
`grep SetReverse(` over `Blizzard_CooldownViewer` and `Blizzard_FrameXMLUtil` returns **nothing**. Reverse comes only from the XML:

- `CooldownViewer.xml:48` (inside `CooldownViewerEssentialItemTemplate`, :20) and `:117` (inside `CooldownViewerUtilityItemTemplate`, :89):
```xml
			<Cooldown parentKey="Cooldown" setAllPoints="true">
				<SwipeTexture file="Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe">
					<Color r="1" g="1" b="1" a="1"/>
				</SwipeTexture>
				<EdgeTexture file="Interface\Cooldown\UI-HUD-ActionBar-SecondaryCooldown"/>
			</Cooldown>
```
  -> **no `reverse` attribute = reverse false**; swipe colour is white in XML and is overwritten per state by `SetSwipeColor` in `RefreshSpellCooldownInfo`.
- `CooldownViewer.xml:183` (inside `CooldownViewerBuffIconItemTemplate`, :158):
```xml
			<Cooldown parentKey="Cooldown" reverse="true" setAllPoints="true">
				<SwipeTexture file="Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe">
					<Color r="0" g="0" b="0" a="0.7"/>
				</SwipeTexture>
```
- Buff icon swipe, `CooldownViewerBuffIconItemMixin` :1394-1425:
```lua
function CooldownViewerBuffIconItemMixin:GetCooldownSwipeColor()
	-- Adding API for this, but still using the standard cooldown colors even though this is an aura
	return CooldownViewerConstants.ITEM_COOLDOWN_COLOR;
end
...
		local forceShowDrawEdge = false;
		CooldownFrame_Set(cooldownFrame, startTime, duration, isEnabled, forceShowDrawEdge, timeMod);
```
  and `OnLoad` :1394-1399 calls `cooldownFrame:SetUseAuraDisplayTime(true)`.
- Base `CooldownFrameTemplate` (`Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3-11`) — swipe `0,0,0,0.64`, no reverse.
- API: `SetReverse(reverse bool, default false)` is `SecretArguments = "AllowedWhenUntainted"`; `SetUseAuraDisplayTime` likewise — "Aura durations are displayed slightly differently than cooldown durations. Setting this to true will adjust the display logic to stay in sync with aura timers." (`Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua:486-494, :545-553`). TBT passes plain booleans, so neither restriction bites.

### What reverse does (derived from the two templates above, not guessed)
A Cooldown's swipe covers the **remaining** fraction when `reverse=false` and the **elapsed** fraction when `reverse=true`:
- Essential/Utility item (reverse false) in the aura state: at the start remaining = 100 %, so the icon is **fully covered by the yellow `ITEM_AURA_COLOR` swipe**, which shrinks clockwise to nothing as the aura runs out — exactly "a yellowish fill of the icon that is cleared by the sweep effect".
- Buff icon (reverse true, black 0.7): starts uncovered and darkens as the aura runs out.
- TBT today (`SetReverse(true)`, black 0.7, edge on, icon desaturated while a cooldown runs): the grey icon starts uncovered (reads "white-ish") and the black swipe grows over it as the cooldown elapses (reads "clears to grey"). This is the user's "what we already have for cd" and must stay.

**Therefore, per state (the planner's choice, sourced from the CDM):**

| State | `SetReverse` | `SetSwipeColor` | `SetDrawEdge` | `SetDesaturated` | Source |
|-------|-------------|-----------------|---------------|------------------|--------|
| Buff running on a cooldown slot (yellow) | **false** | **1, 0.95, 0.57, 0.7** | **false** | false | Essential item XML :48 (no reverse) + aura arm :892-893 + `CooldownFrame_Set` :3 |
| Cooldown running, no buff (today) | true | 0, 0, 0, 0.7 | true | grey while running | Display.lua:561-565 (unchanged) |
| Buffs tab / Reminders tab / Trinket / Pot timers (today) | true | 0, 0, 0, 0.7 | true | false | Display.lua:561-565, BuffIcon :183 / :1406-1408 |

`SetUseAuraDisplayTime(true)` is the CDM's aura-state companion; TBT never calls it today (grep: no hits) and does not use the CDM's countdown-number logic, so it is optional. If the planner adopts it, it must be stamped and reverted with the rest of the look.

---

## Pattern Assignments

### `Display.lua` — icon construction (the default look a pooled icon is born with)

**Analog:** `CreateTimerIcon` (Display.lua:518-607). Cooldown block :537-566:
```lua
	frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	...
	frame.cooldown:SetScript("OnCooldownDone", MarkCooldownsDirtyOnDone)
	frame.cooldown:SetAllPoints(frame.icon)
	frame.cooldown:SetReverse(true)
	frame.cooldown:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	frame.cooldown:SetSwipeColor(0, 0, 0, 0.7)
	frame.cooldown:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
	frame.cooldown:SetDrawEdge(true)
	frame.cooldown:SetDrawSwipe(true)
```
These five setters are the "dark look" a new helper must restore. Note `CHARGE_REST_LEVEL` (:513-516) is declared above `CreateTimerIcon` "for the upvalue-order rule" — any new file-local constant (e.g. the aura colour components) or helper must likewise be declared **above its first caller** (MEMORY: Lua file-local upvalue order trap; or put it on `ns`).

`frame.chargeCount` (:585-591) is a child Frame at `CHARGE_REST_LEVEL` above the Cooldown, so it already draws over a yellow swipe — no layering change needed for BUFFDISP-04.

### `Display.lua` — `ApplyIconStyle` (:690-694), called every tick by every branch
```lua
local function ApplyIconStyle(frame, settings)
	frame:SetScale(settings.iconScale)
	frame:SetAlpha(settings.alpha)
	frame.cooldown:SetDrawSwipe(settings.timerShown)
end
```
"Show Timer" keeps applying to both states (CONTEXT) — leave as is; the new look helper must **not** call `SetDrawSwipe`, or it fights this.

### `Display.lua` — stamp idiom to copy (dirty-checked per-icon state)

**Analog 1:** `ClearIconDesaturation` (:814-819) — a stamp that only ever holds `false`/`nil`:
```lua
local function ClearIconDesaturation(icon)
	if icon._desat ~= false then
		icon._desat = false
		icon.icon:SetDesaturated(false)
	end
end
```
**Analog 2:** `ApplyUserCooldown` (:1062-1112) — `_lastStart` handover, `_userCdState`, `_userCdGrey`:
```lua
	if icon._lastStart ~= nil then
		icon._lastStart = nil
		icon._userCdState = nil
	end

	local startedAt = ns.cooldownStarts[entry.key]
	local running = startedAt ~= nil and (now - startedAt) < duration
	local want = running and startedAt or false

	if icon._userCdState ~= want then
		icon._userCdState = want
		if running then
			icon.cooldown:SetCooldown(startedAt, duration)
		else
			icon.cooldown:Clear()
		end
	end

	if icon._userCdGrey ~= running then
		icon._userCdGrey = running
		icon._desat = nil
		icon.icon:SetDesaturated(running)
	end
```
Copy this shape for a new look stamp (e.g. `icon._auraLook`, true/false/nil; nil = "never asserted", so a fresh pooled widget is always told). The values compared are plain booleans TBT computes from typed numbers — never a game value — so the secret-boolean warning at :801-813 does not apply. Recommended helper (Claude's discretion on name/placement), declared **above** `ApplyCooldownSlot` and `RenderIconContainer`:

```lua
-- shape only; values from the "per state" table above
local function ApplySwipeLook(icon, aura)
	if icon._auraLook ~= aura then
		icon._auraLook = aura
		local cd = icon.cooldown
		cd:SetReverse(not aura)
		if aura then cd:SetSwipeColor(1, 0.95, 0.57, 0.7) else cd:SetSwipeColor(0, 0, 0, 0.7) end
		cd:SetDrawEdge(not aura)
		-- force the owning branch to re-issue SetCooldown under the new look
		icon._lastStart = nil
		icon._userCdState = nil
	end
end
```
Re-issuing `SetCooldown` after a reverse change is the safe reading: Blizzard always sets look then calls `CooldownFrame_Set` -> `SetCooldown` in the same pass (RefreshSpellCooldownInfo :1148-1151), never toggles the look on a running sweep. Clearing `_lastStart`/`_userCdState` piggybacks on the existing "stale stamp means re-assert" rule (:1070-1083).

### `Display.lua` — `ClearCooldownStamps` (:847-865)
```lua
local function ClearCooldownStamps(icon)
	icon._cdKey = nil
	icon._userCdState = nil
	icon._userCdGrey = nil
	icon._cdGen = nil
	icon.chargeCount:Hide()
	icon.cooldown:Clear()
end
```
Callers keep the `if icon._cdKey then` guard (comment :855-857 — deliberate, steady-path cost). Callers: timer branch :1637-1639, placeholder branch :1684-1686, `ShowMergedPlaceholderIcon` :1479-1481.

Two consequences for this phase:
1. **BUFFDISP-04 is broken here today**: when a buff proc lands under a cooldown key, the timer branch calls this and `chargeCount:Hide()` runs, so the charge/item count vanishes during the buff. The fix must not route a cooldown-slot entry's buff through that `Hide()`.
2. **CONTEXT "Hot path"**: the new look stamp must be reset when a pooled icon switches tracker. Note `ClearCooldownStamps` only runs when `_cdKey` is set, i.e. only for a widget leaving the cooldown-slot branch; a widget that drew a yellow buff in the timer branch and is then reassigned to a Buffs-tab timer never passes `_cdKey`. Safer than relying on `ClearCooldownStamps`: assert the look in **every** branch that issues `SetCooldown` (timer branch with `aura = isBuffOnCooldownSlot`, cooldown-slot branch with `aura = false`) — the stamp makes that one boolean compare per icon per tick. Placeholder branches clear the sweep (:1712-1715, :1482-1485) so a stale look there is invisible until the next `SetCooldown`, which re-asserts.

### `Display.lua` — `RenderIconContainer` live-timer branch (:1634-1663) — the main edit site
```lua
		elseif timer then
			if icon._cdKey then
				ClearCooldownStamps(icon)
			end

			icon.proc = timer -- D-19: store for OnEnter tooltip

			if icon.cachedSpellID ~= timer.spellID then
				icon.cachedSpellID = timer.spellID
				icon.cachedIcon = ns:GetSpellIcon(timer.spellID)
			end
			icon.icon:SetTexture(icon.cachedIcon)
			-- Buff icons are never greyed; only a cooldown slot desaturates. Cleared here so a
			-- pooled widget that last drew a cooldown does not keep its grey.
			ClearIconDesaturation(icon)
			ApplyIconStyle(icon, settings)

			if icon._lastStart ~= timer.startedAt then
				icon._lastStart = timer.startedAt
				icon.cooldown:SetCooldown(timer.startedAt, timer.duration)
			end

			icon:Show()
		elseif ns:IsCooldownSlotEntry(entry) then
			...
			ApplyCooldownSlot(icon, entry, settings, now)
			icon:Show()
```
`timer = activeByKey[entry.key]` (:1588); `entry` is the DB entry (slots built from `ns.db.trackedBuffs`, :1535-1547), so `ns:IsCooldownSlotEntry(entry)` is available here at no extra lookup.

Already correct for the yellow state, keep: `ClearIconDesaturation` (not desaturated), `SetCooldown(timer.startedAt, timer.duration)` (the buff proc's own start/length, so the cooldown is **not** shown during the buff), and the branch order (timer above cooldown-slot, so the buff wins while it runs and the cooldown look appears at once when the proc leaves `activeByKey`).

To add (planner's structure):
- Compute `local auraOnCd = ns:IsCooldownSlotEntry(entry) and ns:CooldownBuffDuration(entry) ~= nil` (or a cheaper per-entry test). Gate on the **entry being a cooldown slot**, not on the timer: that is what restricts yellow (BUFFDISP-05) — see "What flows through this branch" below.
- `ApplySwipeLook(icon, auraOnCd)` before the `_lastStart` block.
- For a cooldown-slot entry, skip the `chargeCount:Hide()` in `ClearCooldownStamps` and keep the count live (next section).
- Do not use `icon.proc = entry` here: the tooltip payload stays the live timer (D-19).

### What flows through the live-timer branch (why the gate must be on the entry)
- **Buffs-tab / Reminders-tab trackers** (userBuff, userReminder, metaReminder etc.): real procs from `ns.activeTimers` and preview procs from `ns.previewTimers`, merged by `ns:GetActiveTimers()` (BuffEngine.lua:9-14), indexed by `BuildActiveByKey` (Display.lua:1218-1223). `ns:IsCooldownSlotEntry` is false for them -> dark look.
- **Trinket / Pot meta trackers**: keys `ns.KEY.TRINKET` / `ns.KEY.POT` (Core.lua:532-533), `trackerType == "metaItem"` with **no numeric `itemID`**, so `ns:IsCooldownSlotEntry` (Core.lua:580-588) is false -> dark look. (The comment on `ns:IsBagItemEntry` at Core.lua:590-591 claiming IsCooldownSlotEntry "also answers true for trinket/pot" is stale: both functions have the same body. Do not rely on it.)
- **userCd with buff on, real**: Phase 74's `ns:StartCooldownBuffFromCast` files a proc under the cooldown's own key (74-02 Task 1) -> yellow.
- **userCd with buff on, preview**: 74-02 Task 2 makes `ns:StartAllPreviewTimers` use `ns:CooldownBuffDuration(entry)` as the demo duration -> yellow (CONTEXT "Preview").
- **userCd with buff off, preview**: `StartAllPreviewTimers` (BuffEngine.lua:1521-1566) still builds a demo proc from `info.duration` (the cooldown length) that draws through this same branch -> must stay dark. This is why the test is "entry has its buff on", not merely "entry is a cooldown slot".
- **Bag items** (`IsBagItemEntry`, Phase 76) reuse the same predicate; no item-specific branch here.

Predicates (Core.lua):
```lua
function ns:IsCooldownSlotEntry(entry)            -- :580-588
	if not entry then return false end
	if entry.trackerType == ns.KIND.USER_CD then return true end
	return entry.trackerType == ns.KIND.META_ITEM and type(entry.itemID) == "number"
end
```
`ns:CooldownBuffDuration(entry)` — added by 74-02 Task 1: returns `entry.buffDuration` only when `entry.buffEnabled == true` and it is a positive number, else nil; allocation-free.

### `Display.lua` — count survival (BUFFDISP-04): the generation-gated block to share

**Analog:** `ApplyCooldownSlot` (:1114-1191), gen block :1136-1156:
```lua
	if icon._cdGen ~= ns.cooldownGeneration or icon._cdKey ~= entry.key then
		icon._cdGen = ns.cooldownGeneration
		icon._cdKey = entry.key
		icon._lastStart = nil
		if ns:IsBagItemEntry(entry) then
			ApplyItemCount(icon, entry)
		else
			ApplyChargeCount(icon, spellID)
		end

		if not userOwned then
			if spellID then
				ApplyCooldownHandle(icon, spellID, chargeCapable[spellID] == true)
			else
				icon.cooldown:Clear()
				ClearIconDesaturation(icon)
			end
		end
	end
```
`ApplyChargeCount` (:994-1018) and `ApplyItemCount` (:1035-1044) are generation-driven, never per frame (comments :993, :1031-1034). Constraint for the planner: the gen block also owns `ApplyCooldownHandle` (the engine sweep for a non-userOwned slot). If the timer branch sets `_cdKey`/`_cdGen` while drawing the buff, the cooldown-slot branch will **not** re-run the handle when the buff ends, leaving the buff's sweep on the icon. Options:
- (a) Split the count half into its own helper (e.g. `ApplySlotCount(icon, entry, spellID)`) with its own stamp pair (e.g. `_cntGen`/`_cntKey`), called from both the timer branch (cooldown-slot entries only) and `ApplyCooldownSlot`; keep `_cdKey`/`_cdGen` nil during the buff so the handle re-runs on handover. Add the new stamps to `ClearCooldownStamps`.
- (b) In the timer branch for a cooldown-slot entry, clear `_cdKey/_cdGen/_userCdState/_userCdGrey` but not `chargeCount`, and call the count helpers under a separate stamp.
Either way `ApplyUserCooldown`'s `_lastStart` handover (:1080-1083) already makes the cooldown re-assert itself "at once" when the buff proc leaves.

### `Display.lua` — `ApplyCooldownSlot` / cooldown-slot branch (:1664-1677) — assert the dark look
`ApplyCooldownSlot` already calls `ApplyIconStyle` (:1123) every tick; add the look assertion beside it (`ApplySwipeLook(icon, false)`) so the cooldown keeps "what we already have" after a buff. Grey stays owned by `ApplyUserCooldown` (:1105-1109) / `ApplyCooldownGrey` (:875-908): CONTEXT "an icon is grey only while a cooldown shows and no buff does" falls out of branch order, since the timer branch calls `ClearIconDesaturation` and resets `_userCdGrey` via `ClearCooldownStamps` (so grey is re-applied on handover; analog comment :851-853).

### `Display.lua` — `ShowMergedPlaceholderIcon` (:1477-1492) and Merge Mode branch (:1609-1628)
Out of scope (merged slots are Blizzard's frames; CONTEXT "Merge Mode is untouched"). The placeholder clears its sweep, so no look assertion needed there.

---

## Shared Patterns

### Per-icon dirty-check stamps
**Source:** Display.lua:814-819, :1080-1109, :1658-1661
**Apply to:** every new widget setter in the render path (`SetReverse`, `SetSwipeColor`, `SetDrawEdge`, any `SetUseAuraDisplayTime`). One compare on the steady path, setters only on change; nil means "never asserted".

### Pooled-widget handover
**Source:** `ClearCooldownStamps` (:847-865) + the `_lastStart` handover in `ApplyUserCooldown` (:1070-1083) + `ApplyCooldownSlot` clearing `_lastStart` (:1139-1141)
**Apply to:** any new stamp. Whoever owns the icon now re-asserts; never rely on the previous owner having cleaned up.

### No allocation in the render tick
**Source:** comments at Display.lua:121-134, :1203-1204; module tables wiped, no table constructors/closures per tick.
**Apply to:** the look helper (literal numbers or file-local upvalues for the aura colour, not `CreateColor` per call). If the colour lives in upvalues, declare them above the helper (upvalue-order rule, CHARGE_REST_LEVEL precedent :513-516).

### Secret safety
The look decision reads only TBT's own saved keys (`buffEnabled`, `buffDuration`) and `trackerType`; no game value, no aura read, so `scripts/aura-read-gate.js` is unaffected. Do not derive the state from `C_UnitAuras`.

### Workflow
Edit tool only (Lua files pinned `eol=crlf`; never `sed -i`), then `stylua .`, `node scripts/aura-read-gate.js`, `git ls-files --eol Display.lua` must show `w/crlf`. CDMTab.lua is being edited by another agent; this phase needs no CDMTab.lua change.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (yellow swipe colour / reverse toggle) | — | — | TBT has never changed reverse or swipe colour after `CreateTimerIcon`; the values come from Blizzard's CDM (table above), the stamping from Display.lua's own idiom |

## Metadata

**Analog search scope:** Display.lua, Core.lua (:574-598), BuffEngine.lua (:1-20, :1513-1572), Phase 74 74-02-PLAN.md; wow-ui-source `Blizzard_CooldownViewer/CooldownViewer.lua`, `CooldownViewer.xml`, `Blizzard_FrameXMLUtil/Cooldown.lua`, `Blizzard_FrameXMLUtil/Mainline/Cooldown.xml`, `Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua`
**Files scanned:** 9
**Pattern extraction date:** 2026-10-22
