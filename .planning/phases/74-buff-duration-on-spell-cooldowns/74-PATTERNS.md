# Phase 74: Buff Duration on Spell Cooldowns - Pattern Map

**Mapped:** 2026-10-22
**Files analyzed:** 5 modified (no new files)
**Analogs found:** 5 / 5 (all in-repo; one capability, the greyed field state, has only a partial analog)

No RESEARCH.md (research skipped by user decision). File list comes from 74-CONTEXT.md.

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `CDMTab.lua` — 3 new `TRACKER_FIELDS` entries (checkbox, Aura ID, Duration) | component (dialog field defs) | request-response (form → saved entry) | `keepOnAuraLoss` (CDMTab.lua:2200-2237), `BuildFollowSpellIDField` (:1524-1723) + `auraID` use (:2191-2199), `duration` (:2035-2151) | exact |
| `CDMTab.lua` — field contract: new greyed/disabled state (walker in `CreateAddDialog`) | component (dialog walker) | event-driven (onChange → RefreshState) | `visible()` hook in RefreshState (:2627-2658) + only greyed control `barsCheck:Disable()` (:2951-2961) | partial (no greyed field state exists yet) |
| `BuffEngine.lua` — saved keys, preview, cancellation | service (engine) | CRUD + batch | `ENGINE_OWNED` (:1125-1135), `ns:StartAllPreviewTimers` (:1513-1572), `ns:ScanActiveTimersForCancellation` (:1586-1629) | exact (no edit needed for persistence) |
| `Providers.lua` — userCd cast also starts a buff timer | provider | event-driven (UNIT_SPELLCAST_SUCCEEDED) | `ns:StartReminderFromCast` (:214-241) side-effect writer; `ns:FillUserBuffProc` (:97-156) | exact |
| `Display.lua` — live-timer branch draws on the cooldown icon | component (render, hot path) | streaming (per-tick) | `RenderIconContainer` timer branch (:1634-1663) above cooldown branch (:1664-1677) | exact (likely no edit in Phase 74) |
| `Core.lua` — kinds / helpers | config | — | `ns:IsCooldownSlotEntry` (:580-588), `ns:CooldownDuration` (:731-733) | read-only reference; a small helper may be added |

---

## Pattern Assignments

### CDMTab.lua — the "Track buff duration" checkbox field

**Analog:** `keepOnAuraLoss`, CDMTab.lua:2200-2237. It is the Advanced-tab checkbox. Copy its build, reset, prefill, read and validate shape exactly.

```lua
{
	id = "keepOnAuraLoss",
	entryKey = "keepOnAuraLoss",
	tab = "advanced",
	build = function(row, y, onChange, dialog)
		local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		check:SetPoint("TOPLEFT", row, "TOPLEFT", 32, y)
		check:SetChecked(true)
		check:SetScript("OnClick", onChange)

		local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", check, "RIGHT", 4, 0)
		label:SetText("End when the aura is lost")

		return { check = check }, y - 26
	end,
	reset = function(state)
		state.check:SetChecked(true)
	end,
	prefill = function(state, entry)
		state.check:SetChecked(not entry.keepOnAuraLoss)
	end,
	read = function(state)
		return (not state.check:GetChecked()) and true or nil
	end,
	validate = function()
		return true
	end,
	visible = function(state, ctx)
		return ns.BUFF_LIKE_KINDS[ctx.kind] == true
	end,
},
```

Changes for the new field (e.g. `id = entryKey = "buffEnabled"`):
- Defaults to **off**: `reset` uses `SetChecked(false)`, `prefill` uses `SetChecked(entry.buffEnabled == true)`. Missing key means off.
- `read` follows the "a default is stored as nil" rule (contract comment :1794-1801): `return state.check:GetChecked() and true or nil`. This is the same shape as `coverAllRanks` (:2181-2183).
- `visible = function(_, ctx) return ctx.kind == ns.KIND.USER_CD end`. Phase 76 widens this to bag items, so keep the predicate in one place, for example a file-local `CarriesBuff(ctx)` or an `ns:` helper.
- Keep a reference to the label in the state (`{ check = check, label = label }`). The keepOnAuraLoss analog drops it, but the greyed state needs it, and Phase 76 needs it as well.
- **Order is load-bearing** (contract :1782-1792 and :1729-1730). The checkbox must come **before** the Aura ID and Duration entries in `TRACKER_FIELDS`, so their `build` can capture it with `dialog.GetFieldState("buffEnabled")`. Only an earlier sibling is visible at build time. `load` must stay **last** (:1817).

### CDMTab.lua — the buff Aura ID field

**Analog:** the `BuildFollowSpellIDField` factory, CDMTab.lua:1524-1723, used for `auraID` at :2191-2199 and for `castID` at :2293-2301.

```lua
BuildFollowSpellIDField({
	id = "auraID",
	label = "Aura ID:",
	tooLarge = "Aura ID is too large",
	secrecy = true,
	visible = function(_, ctx)
		return ctx.kind ~= ns.KIND.USER_CD
	end,
}),
```

Behaviour the factory already gives (do not re-implement it):
- **Follows the Spell ID until the user types in it.** `state.followsSpell` is set in OnTextChanged only when `userInput` is true (:1596-1606). The follow write in `update` is guarded by `state.syncing` (:1660-1667).
- `reset`: the box is blank, `followsSpell = true` (:1627-1642).
- `prefill`: `followsSpell = entry[key] == nil` (:1643-1654).
- `read`: returns nil when the box is blank **or equal to the Spell ID**, otherwise the typed number (:1698-1713). A saved nil therefore means "same as the spell", and the runtime must fall back to `entry.spellID`. This is the same convention as `ns:DetailedAuraID(entry) or entry.spellID` (BuffEngine.lua:866-873).
- `validate`: only the 32-bit range check, skipped while following (:1714-1721).

Gaps the planner must close:
1. **Required-when-on validation.** CONTEXT says save is refused unless the Aura ID is filled while the checkbox is on. The factory's validate never fails on an empty box. Add an opts hook, for example `opts.required = function(state) ... end` or `opts.validate`, so that a box the user emptied (`not state.followsSpell and GetNumber() <= 0`) fails with a message. A box that is still following holds the Spell ID and counts as filled.
2. **The label is a local** (:1535-1537) and is not stored in the state. Add `state.label = label` so the greyed state can recolour it.
3. Pass `secrecy = true` so the badge describes this aura's secrecy, as `auraID` does. This is optional and left to the planner.
4. `id` doubles as `entryKey` (:1525-1528). A new key such as `buffAuraID` works unchanged. **Never reuse `auraID`**: schema v10 dropped it for userCd, and `ns:DetailedAuraID` / `ns.detailedRankFamilies` key on it for buff-like entries only (Core.lua:1754).

### CDMTab.lua — the buff Duration field

**Analog:** the `duration` field, CDMTab.lua:2035-2151. Copy build, reset, prefill, read and validate. **Drop `update`**: CONTEXT forbids prefilling from `ns:SuggestedBuffDuration`/`SuggestedCooldown`, and the box starts empty.

Build (:2039-2059). Use the Advanced indent of x=32 rather than General's 16, to match the other Advanced rows (:2207, :1537):
```lua
local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetText("Duration (30, 45s, 2m):")
label:SetPoint("TOPLEFT", row, "TOPLEFT", 16, y)
y = y - 18
local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
box:SetSize(180, 22)
box:SetPoint("TOPLEFT", row, "TOPLEFT", 16, y)
box:SetMaxLetters(6)
box:SetAutoFocus(false)
box:SetScript("OnTextChanged", onChange)
```

Prefill, read and validate (:2068-2079, :2134-2150). These keep an unedited saved value exact and parse typed text:
```lua
prefill = function(state, entry)
	state.originalValue = entry.duration
	state.originalText = FormatDuration(entry.duration)
	state.editBox:SetMaxLetters(math.max(6, #state.originalText))
	state.editBox:SetText(state.originalText)
	...
read = function(state)
	local text = state.editBox:GetText()
	if state.originalText ~= nil and text == state.originalText then
		return state.originalValue
	end
	return ParseDuration(text)
end,
validate = function(state)
	local text = state.editBox:GetText()
	if text == "" then return false end
	if not ParseDuration(text) then return false, DURATION_HINT end
	return true
end,
```
- Read `entry.buffDuration` (or whatever key is chosen) in place of `entry.duration`. **Never** write `duration`, which is `ENGINE_OWNED` and positional (:1731-1733, BuffEngine.lua:1127).
- An empty box should fail **with a message** while the checkbox is on. The `duration` field returns `false` with no message (:2143-2144), which only disables confirm. CONTEXT wants "refuses to save until ... filled", so give the empty case a message, for example "Enter the buff duration". It will be shown as "Advanced: ..." by ValidateAll (:2615).
- Helpers `ParseDuration` (:1163), `FormatDuration` (:1204) and `DURATION_HINT` (:1154) are declared above `CreateAddDialog` and are safe to call. `AddExclusiveCheck` (:2859) is **below** it and must not be called from a field def (hazard note :1831-1836).

### CDMTab.lua — the greyed (disabled) state in the field contract

**There is no existing field-level greyed state.** Fields are only shown or hidden through `visible()`. The only greyed control in the file is the New Container dialog. Copy its look:

CDMTab.lua:2949-2961
```lua
-- Anything but Buffs forces Icons; Buffs hands the choice back. Disabling rather than hiding
-- keeps the dialog one fixed size and shows the player WHY the option is unavailable.
local function ApplyCategory(selected)
	if selected ~= "buffs" then
		iconsCheck:SetChecked(true)
		barsCheck:SetChecked(false)
		barsCheck:Disable()
		barsLabel:SetTextColor(0.5, 0.5, 0.5)
	else
		barsCheck:Enable()
		barsLabel:SetTextColor(1, 1, 1)
	end
end
```
Notes on the colours: `GameFontHighlightSmall` labels are white (1,1,1), so restoring to white matches the dialog. Nothing in the repo uses `DISABLED_FONT_COLOR`/`GRAY_FONT_COLOR` (grep found none), so 0.5 grey is the house convention.

**Where the hook plugs in** is the RefreshState walker, CDMTab.lua:2627-2658. Model a new optional hook on the `visible()` evaluation:
```lua
for _, field in ipairs(fieldStates) do
	local def, state = field.def, field.state
	local relevant = not def.visible or (def.visible(state, ctx) and true or false)
	local shown = relevant and (not def.tab or def.tab == currentTab)
	field.relevant = relevant
	if shown ~= field.shown then
		field.shown = shown
		dirty = true
	end
end
```
Suggested shape, which stays within the contract's rules:
- Add an optional `enabled(state, ctx, dialog) -> bool` to the contract comment (:1725-1760), next to `visible`. Absent means always enabled.
- Compute it in the same loop and **compare before writing**. Store `field.enabled` and only call the widget setters when the value flips. The contract (:1753-1755) requires compare-before-write for sibling widget writes. A generic applier can grey `state.editBox` (EditBox `:SetEnabled(bool)`), `state.check` (CheckButton `:SetEnabled`) and `state.label` (`SetTextColor(0.5,0.5,0.5)` / `(1,1,1)`). Alternatively, give each def a `setEnabled(state, enabled)` hook, which Phase 76 can reuse for every non-buff field, the `load` dropdown included (`DropdownButton:SetEnabled`).
- **Validation**: a disabled field must not block save. CONTEXT says "With it off, save succeeds". In `ValidateAll` (:2605-2621) skip `def.validate` when `field.enabled == false`, while keeping `field.relevant` semantics.
- **Read**: a disabled field is still relevant and **is still read**, because CONTEXT says values are kept. The confirm loop (:2740-2746) is unchanged. Do **not** reuse `visible()` for greying: a field hidden by `visible()` is not read (:1738-1745, WR-02), and that would also hide the boxes, which CONTEXT forbids.
- **Tab/Enter ring and focus**: `OnTabPressed` (:2664-2679) and `FocusFirstShown` (:2683-2690) test only `field.shown`. Extend both to skip `field.enabled == false`, or focus can land in a disabled box.
- The follow write in `BuildFollowSpellIDField.update` keeps working while the box is disabled. Pre-filling a greyed Aura ID with the Spell ID is consistent with "values kept".

### Dialog open and commit (context, no change expected)

- Add: `OpenForAdd` resets every field (:2796-2798). Edit: `OpenForEdit` resets and then prefills (:2828-2834). Both then call `SelectGeneral()` → `RefreshState(true)`. New fields need nothing here.
- Commit (:2722-2775): `values[entryKey] = def.read(...)` for each relevant field, followed by `ns:AddTrackedBuff(values.spellID, values.duration, nil, { trackerType, section="hidden", fields = values })` or `ns:UpdateTrackedBuff(key, spellID, duration, values, readKeys)`. Both are followed by `ns:RefreshTBTSections()` and `ns:StartAllPreviewTimers()`.

---

### BuffEngine.lua — persistence (no edit expected)

**Analog:** the `ENGINE_OWNED` contract, BuffEngine.lua:1117-1135:
```lua
local ENGINE_OWNED = {
	spellID = true, duration = true, label = true, trackerType = true, section = true,
	layoutOrder = true, key = true, itemID = true, iconOverride = true,
}
```
- Add copies every non-owned field (:1221-1228). Update copies every key listed in `fieldKeys`, and nil clears it (:1388-1397). New keys such as `buffEnabled`, `buffAuraID` and `buffDuration` therefore persist with **no engine edit**. Confirm that none of them is added to `ENGINE_OWNED`.
- `UpdateTrackedBuff` with a changed ID calls `ns:ClearTrackerRuntimeState(oldKey)` (:1379). That clears `activeTimers[oldKey]` (:1106), so a running buff timer under the cooldown key is cleaned up for free.
- No schema bump is needed. Missing keys read as off.

### BuffEngine.lua — preview (`ns:StartAllPreviewTimers`, :1513-1572)

**Core pattern** (:1544-1565):
```lua
local real = ns.activeTimers[key]
local live = (real and real.expiresAt > now) or ns:IsCooldownRunning(key, entry, now)
if not live then
	local info = ns:GetDisplayInfoForKey(key)
	if info and type(info.duration) == "number" and info.duration > 0 then
		ns.previewTimers[key] = {
			key = key,
			spellID = info.spellID,
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
```
- `info.duration` for a userCd is `entry.duration`, the cooldown length (Providers.lua:429-433). For a cooldown with its buff on, the preview must use the **typed buff duration**. Branch here on the entry (for example `ns:IsCooldownSlotEntry(entry) and entry.buffEnabled and buffDuration > 0`) rather than changing `GetDisplayInfo`. That function is shared by tooltips and the Suggested tiles (Providers.lua:400-434, 1777-1802).
- `ns:GetActiveTimers` already lets a real proc win over a preview for the same key (:957-984), so keying the real buff timer under the cooldown key keeps "real beats preview" automatic.
- Preview procs are allowed to allocate (:795-799), because they exist only while the CDM window is open.

### BuffEngine.lua — early end on aura loss (no edit expected if aliveBuffs is set)

**Analog:** `ns:ScanActiveTimersForCancellation`, :1586-1629. It walks `ns.activeTimers`, reads every ID in `timer.aliveBuffs` through `ns:ReadPlayerAura`, aborts on any unreadable read, honours the `castAt` grace, and nils the timer:
```lua
if timer.aliveBuffs and #timer.aliveBuffs > 0 then
	local anyPresent, allReadable = false, true
	for _, buffID in ipairs(timer.aliveBuffs) do
		local aura, readable = ns:ReadPlayerAura(buffID)
		if not readable then allReadable = false break
		elseif aura then anyPresent = true break end
	end
	local inGrace = timer.castAt ~= nil and now - timer.castAt < ns.CAST_AURA_GRACE
	if allReadable and not anyPresent and not inGrace then
		ns.activeTimers[key] = nil
		if ns.reminderAuraID[key] then ns.auraState[key] = false end
```
- A proc under a `userCd:<id>` key with `aliveBuffs = { buffAuraID }` and `castAt = now` is cancelled by this scan with **no new aura read**. `ns.reminderAuraID[cdKey]` is nil, so the reminder line is a no-op.
- The scan is triggered by `ns:OnUnitAura` (:1965-2017), which is gated on `C_Secrets.ShouldAurasBeSecret()` first, and by the post-cast `ns:QueueCastAuraRecheck` (:1955-1963). Call `ns:QueueCastAuraRecheck()` after starting the buff, as the buff side does (Providers.lua:388-392).
- `ns:ApplyEndOnCast` (:1478-1511) ends only `cooldownStarts` for a `USER_CD` key. Whether a "Resets when you cast" rule should also end the buff timer under that key is left to the planner. Today it does not.
- `ns:SetBuffSection(key, "hidden")` (:1433-1450) and `ns:EndTrackerRuntime` (:1105-1115) both nil `activeTimers[key]`. Hidden-section and load changes therefore end the buff timer for free.

---

### Providers.lua — the userCd cast starts the buff timer

**Primary analog:** `ns:StartReminderFromCast`, Providers.lua:214-241. It is the existing side-effect writer of `ns.activeTimers` from inside `UserSpellProviderMixin:OnTrigger`. That writer is needed because the provider returns only one proc, the buff side's (dispatcher contract :1855-1878).
```lua
function ns:StartReminderFromCast(key, entry, skipRedraw)
	if not (entry and ns:IsReminderEntry(entry) and entry.section ~= "hidden") then
		return
	end
	local duration = entry.duration
	if type(duration) == "number" and duration > 0 then
		local now = GetTime()
		...
		ns.activeTimers[key] = ns:FillUserBuffProc(key, entry, now)
	end
	ns.auraState[key] = true
	if ns.QueueCastAuraRecheck then
		ns:QueueCastAuraRecheck()
	end
	if not skipRedraw and ns.UpdateDisplay then
		ns:UpdateDisplay()
	end
	return true
end
```
Define the new function on `ns`, not as a file-local, for the same reason the comment gives (:205, memory "Lua file-local upvalue order trap").

**Call site:** the cooldown side, Providers.lua:276-286:
```lua
local cdKey = ns:StartCooldownFromCast(tracked, ns.cooldownKeyBySpell, ns.rankIndexCooldown, spellID)
```
`ns:StartCooldownFromCast` (:182-192) returns only the key and applies the hidden-section rule:
```lua
function ns:StartCooldownFromCast(tracked, byKey, rankIdx, spellID)
	local cdKey, cdEntry = ns:ResolveCastOwner(tracked, byKey, rankIdx, spellID)
	if not cdEntry then return nil end
	if cdEntry.section ~= "hidden" then
		ns.cooldownStarts[cdKey] = GetTime()
		ns:MarkCooldownsDirty()
	end
	return cdKey
end
```
Start the buff "same moment, same hidden-section rule". Either start it inside the `section ~= "hidden"` block, or have the caller use `tracked[cdKey]` plus the same guard. A recast overwrites `activeTimers[cdKey]`, which gives "recast restarts" for free.

**Proc build:** `ns:FillUserBuffProc`, :97-156. It is pooled through `ns:AcquireProc(ownerKey)` and allocates nothing. **It cannot be used verbatim for a userCd entry:**
- It sets `proc.duration = entry.duration` and `expiresAt = now + entry.duration` (:142-145). For a userCd that is the **cooldown** length.
- Its aliveBuffs choice reads `ns:DetailedAuraID(entry)` (entry.auraID) and `ns.rankFamilies[ownerKey]` (:113-131). For a userCd that falls through to `ns.rankFamilies[cdKey]` (cast IDs, Core.lua:1748) or `AcquireAliveBuffs(cdKey, entry.spellID)`. Neither is the buff's aura ID.

There is an existing precedent for overriding fields after Fill, in BuffEngine.lua:1903-1910 (`ns:RefreshAuraStates`):
```lua
proc = ns:FillUserBuffProc(key, entry, now)
proc.castAt = nil
proc.expiresAt = expirationTime
proc.duration = duration
proc.startedAt = expirationTime - duration
proc.syncedAt = now
ns.activeTimers[key] = proc
```
So the cooldown buff can call Fill and then overwrite `duration`, `expiresAt` and `aliveBuffs`. For `aliveBuffs`, use `ns:AcquireAliveBuffs(cdKey, buffAuraID or entry.spellID)` (BuffEngine.lua:846-856, pooled and one element). Alternatively, factor a small sibling builder that takes `(key, entry, duration, auraID, now)`. That choice is the planner's. Keep `proc.castAt = now` (:154) so the cast grace applies. `ns:PreallocateProc(key)` already runs for every tracker (BuffEngine.lua:887-894), so the userCd key has a pooled proc and aliveBuffs list.

**Documentation sites to update:** the dispatcher's list of `ns.activeTimers` writers (Providers.lua:1855-1861), and the "A cooldown is a slot, not a timer: it never enters ns.activeTimers" comments (Providers.lua:278-279; BuffEngine.lua:1539-1543). Both stop being true once the cooldown key can carry a buff proc.

---

### Display.lua — drawing (Phase 74: no edit expected)

**Analog:** the `RenderIconContainer` branch order, Display.lua:1634-1677. The live-timer branch comes first:
```lua
elseif timer then
	if icon._cdKey then
		ClearCooldownStamps(icon)
	end
	icon.proc = timer
	if icon.cachedSpellID ~= timer.spellID then
		icon.cachedSpellID = timer.spellID
		icon.cachedIcon = ns:GetSpellIcon(timer.spellID)
	end
	icon.icon:SetTexture(icon.cachedIcon)
	ClearIconDesaturation(icon)
	ApplyIconStyle(icon, settings)
	if icon._lastStart ~= timer.startedAt then
		icon._lastStart = timer.startedAt
		icon.cooldown:SetCooldown(timer.startedAt, timer.duration)
	end
	icon:Show()
elseif ns:IsCooldownSlotEntry(entry) then
	ApplyCooldownSlot(icon, entry, settings, now)
	icon:Show()
```
- `timer = activeByKey[entry.key]` (:1588, built by `BuildActiveByKey` :1218-1223). A proc filed under the cooldown's own key therefore draws on **that icon only**.
- Routing is `timersByContainer[timer.section] or timersByContainer.bars` (:1864-1866). Setting `proc.section = entry.section` (Fill does so, Providers.lua:147) keeps it in the cooldown's container. A Cooldowns-category container is forced to Icons (CDMTab.lua:2951-2956), so the proc never reaches `RenderBarContainer`.
- Pitfall for Phase 75, not 74: while the buff runs, this branch skips `ApplyCooldownSlot` (charge and item counts) and clears the cooldown stamps.

### Core.lua — kinds and helpers (reference)

- `ns.KIND.USER_CD = "userCd"` (:498). `ns:IsCooldownSlotEntry` (:580-588) covers userCd and bag items, which is the right predicate to share with Phase 76. `ns:IsBagItemEntry` is at :592-594.
- `ns:CooldownDuration` (:731-733) returns `entry.duration`. It must stay the cooldown length. Put the buff duration in a helper of its own if one is wanted, for example `ns:CooldownBuffDuration(entry)` returning nil unless enabled with a positive number. Phase 76 needs the same helper, because `entry.duration` on a bag item is overwritten by the game's cooldown.
- `ns:IsCooldownRunning` (:738-748) is the "real beats preview" test for cooldowns.

---

## Shared Patterns

### Secret-value discipline
**Sources:** `ns:ReadPlayerAura`, BuffEngine.lua:34-50, and `ns:ReadableAuraExpiry`, :1713-1728.
**Applies to:** every aura read in this phase. The ideal is none: let the scan do the reading.
```lua
function ns:ReadPlayerAura(spellID)
	if C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return nil, false
	end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
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
```
- Call `issecretvalue(x)` **before** any `==`, `type()` test or comparison on a value that may be secret (also :1016-1026 `ns:SpellLabel`, :2000-2001 `isFullUpdate`). Treat `readable == false` as **unknown, never absent**.
- The cast `spellID` from `UNIT_SPELLCAST_SUCCEEDED` is safe (CLAUDE.md). The typed `buffDuration` and `buffAuraID` are plain user numbers.

### Aura-read allowlist gate
**Source:** `scripts/aura-read-gate.js:59-66`
```js
const ALLOWLIST = [
  { file: 'BuffEngine.lua', func: 'ns:ReadPlayerAura', reason: 'the gated reader -- ...' },
];
```
- Any reference to `C_UnitAuras`, `GetPlayerAura*`, `UnitAura`, `AuraUtil.ForEachAura` and similar (DETECT_RE :40-57) outside `ns:ReadPlayerAura` fails the gate. Comments and strings are blanked, so naming an API in a comment is fine.
- Verify with `node scripts/aura-read-gate.js` and `node scripts/aura-read-gate.js --selftest`. **Do not add allowlist rows.**

### Pooled, allocation-free cast path
**Sources:** `ns:AcquireProc` (BuffEngine.lua:833-842), `ns:AcquireAliveBuffs` (:846-856), `ns:PreallocateProc` (:887-894).
**Applies to:** the new cast-side buff start. Use no table constructors or closures, only `ns:` functions. Wrap `ns:QueueCastAuraRecheck` and `ns:UpdateDisplay` in nil guards as the existing callers do (Providers.lua:234-239).

### Redraw and dirty flags
- After writing `ns.activeTimers` outside the dispatcher's return value, call `ns:UpdateDisplay()` (Providers.lua:237-239). The dispatcher redraws only for the returned buff proc (:1869-1875).
- A cooldown start calls `ns:MarkCooldownsDirty()` (Providers.lua:189). Tracker set and section changes call `ns:MarkTrackersDirty()`.

### Dialog validation messages
**Source:** `ValidateAll`, CDMTab.lua:2605-2621.
- `validate` returns `false, "message"`. The first failing relevant field with a message wins, and an Advanced-tab field's message is prefixed `"Advanced: "`. `false` with no message only disables confirm.

### Field cross-reads
- Inside `build`, capture an **earlier** sibling with `dialog.GetFieldState(id)` (CDMTab.lua:2486-2489; e.g. :1533, :1986-1987). Inside `update`, any sibling works through the third argument `dialog` (:1923-1931). The greyed state of Aura ID and Duration should read the checkbox's `state.check:GetChecked()` through a captured reference.

---

## No Analog Found

| Capability | Role | Reason | Guidance |
|---|---|---|---|
| A greyed/disabled state for a **tracker field** (`TRACKER_FIELDS` contract) | dialog walker | Fields are only shown or hidden by `visible()`. The only disabled control is the separate New Container dialog's `barsCheck` (CDMTab.lua:2955-2956). | Add an optional `enabled()` hook next to `visible()` in RefreshState (:2641-2650): compare before writing, skip validate when disabled, still read, and skip disabled boxes in the Tab ring and focus. Use the `barsCheck:Disable()` + 0.5 grey label look. Make it generic over editBox, check, label and dropdown so Phase 76 can grey every non-buff field. |
| A userCd key holding a live `ns.activeTimers` proc | provider/engine | No userCd has entered `activeTimers` until now (Providers.lua:278-279). | Follow the reminder side-effect writer (Providers.lua:214-241) and the Fill-then-override precedent (BuffEngine.lua:1903-1910). Update the stale comments. |

## Metadata

**Analog search scope:** `CDMTab.lua`, `BuffEngine.lua`, `Providers.lua`, `Display.lua`, `Core.lua`, `scripts/aura-read-gate.js`
**Files scanned:** 6
**Verification commands for the plan:** `node scripts/aura-read-gate.js`, `node scripts/aura-read-gate.js --selftest`, `stylua .`, `git ls-files --eol` on any edited `.md`
**Pattern extraction date:** 2026-10-22
