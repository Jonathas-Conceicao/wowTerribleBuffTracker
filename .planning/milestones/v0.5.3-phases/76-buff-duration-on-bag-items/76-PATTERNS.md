# Phase 76: Buff Duration on Bag Items - Pattern Map

**Mapped:** 2026-10-22
**Files analyzed:** 5 (CDMTab.lua, BuffEngine.lua, Providers.lua, Core.lua, Display.lua)
**Analogs found:** 5 / 5. Every change extends a Phase 74 pattern that already exists in the same file.

The rule for this phase: **a bag item is "a userCd that has no spell ID, no editable General fields
and a game-owned `entry.duration`".** Everything Phase 74 built is keyed on
`ns:IsCooldownSlotEntry(entry)`, which is already true for a bag item (Core.lua:582-590). The work is
mostly about **opening** the gates that check for the kind (`ctx.kind == USER_CD`,
`IsEditableTracker`) and **closing** the paths that assume a spell ID (UpdateTrackedBuff, the
follow field, the spell portrait, and the timer-branch icon).

> Display.lua is being edited by Phase 75 right now. Line numbers quoted for Display.lua are from the
> in-progress working tree. Any Display.lua plan in Phase 76 must run **after** 75-01 lands.

---

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `BuffEngine.lua` `ns:IsEditableTracker` | predicate | request-response | itself (`:1036-1042`) | exact |
| `BuffEngine.lua` `ns:UpdateTrackedBuff` (needs a bag-item buff-only path) | service (edit commit) | CRUD | Phase 74 blocks inside it (`:1399-1403`, `:1426-1442`) | exact |
| `CDMTab.lua` right-click Edit gate | component (menu) | event-driven | `:433-441` | exact |
| `CDMTab.lua` `EDIT_TITLE_BY_KIND` | config table | n/a | `:2557-2561` | exact |
| `CDMTab.lua` `CarriesCooldownBuff` / new item `enabled` hook | predicate (field contract) | transform | `:1908-1916` | exact |
| `CDMTab.lua` TRACKER_FIELDS greyed General/Advanced fields | component (dialog fields) | request-response | `buffAuraID` / `buffDuration` defs (`:2422-2488`) + `ApplyFieldEnabled` (`:1743-1778`) | exact |
| `CDMTab.lua` `BuildFollowSpellIDField` (no-follow for items) | component factory | transform | itself (`:1528-1734`) | exact |
| `CDMTab.lua` `spellPreview` item face | component | transform | `ns:RefreshIDPreview` placeholder arm (`:1252-1267`) | role-match |
| `CDMTab.lua` confirm handler edit branch | controller | request-response | `:2959-2972` | exact |
| `Providers.lua` `MetaItemBagProviderMixin:OnTrigger` (start buff) | provider | event-driven | `UserSpellProviderMixin:OnTrigger` cooldown side (`:354-357`) | exact |
| `Providers.lua` `ns:StartCooldownBuffFromCast` (optional `proc.itemID`) | service | event-driven | itself (`:221-259`) | exact |
| `Display.lua` live-timer branch icon texture (item has no spellID) | component (render) | streaming (per tick) | `ApplyCachedIcon` (`:839-846`) | exact |
| `BuffEngine.lua` `StartAllPreviewTimers` (optional `itemID`) | service | batch | itself (`:1585-1605`) | exact |

---

## 1. Edit entry: callers, gates and the engine path

### 1a. `ns:IsEditableTracker` and EVERY caller

**Definition**, BuffEngine.lua:1036-1042:
```lua
function ns:IsEditableTracker(entry)
	if entry == nil then
		return false
	end
	local kind = entry.trackerType
	return kind == ns.KIND.USER_BUFF or kind == ns.KIND.USER_CD or kind == ns.KIND.USER_REMINDER
end
```

**All callers.** A grep over `*.lua` finds exactly three. None are in Display, MergeMode, Core,
Providers or the scripts.

| # | Site | What it gates | Effect if bag items are admitted |
|---|---|---|---|
| 1 | CDMTab.lua:437 | right-click "Edit" button on a **tracked** tile | Wanted. A Suggested tile never gets here: the `sectionName == "suggested"` branch (`:381-403`) builds its own menu and `return`s first, so BUFFCD-06 holds by construction. |
| 2 | CDMTab.lua:3014 | `dialog.OpenForEdit` re-check | Wanted. Opens with `ctx.kind = entry.trackerType` = `metaItem` (`:3020`). |
| 3 | BuffEngine.lua:1326 | `ns:UpdateTrackedBuff` refusal | **Dangerous.** See 1c. The rest of that function assumes a spell ID. |

Nothing else, such as duplicate checks, Remove, Move or the drag rules, reads this predicate. Remove,
Move and Hide in the menu (`:413-446`) are already shown for items today.

**Two options for the planner:**
- (A) Widen `IsEditableTracker` with `or ns:IsBagItemEntry(entry)`, as CONTEXT says. Then
  `UpdateTrackedBuff` **must** branch on `ns:IsBagItemEntry(entry)` before its
  `type(spellID) ~= "number"` check at `:1329` and go to a buff-only path.
- (B) Keep `IsEditableTracker` for the full edit. Add `ns:IsBuffEditableTracker(entry)` =
  `IsEditableTracker(entry) or IsBagItemEntry(entry)`, used only at callers 1 and 2. Then
  UpdateTrackedBuff keeps refusing items, and a separate `ns:UpdateTrackedItemBuff` does the work.

Both are valid. (A) matches CONTEXT's wording. (B) makes "nothing else changes by accident"
structural. Either way, update the comments at BuffEngine.lua:1028-1035 and CDMTab.lua:433-434
("bag items get no Edit entry"), and CDMTab.lua:2555 ("only ns:IsEditableTracker kinds open it").

### 1b. Menu gate, CDMTab.lua:433-441 (copy as is; only the predicate changes)
```lua
				-- userBuff, userCd and userReminder only (EDIT-01, Phase 57.2): Lust, trinket, pot,
				-- class-buff reminders and bag items get no Edit entry.
				-- Reached through the ns field, not a file-local -- CreateIconFrame is declared
				-- above CreateAddDialog, so a file-local ns.tbtAddDialog would still be nil here.
				if ns:IsEditableTracker(entry) then
					rootDescription:CreateButton("Edit", function()
						ns.tbtAddDialog.OpenForEdit(trackerKey)
					end)
				end
```
`entry` comes from `ns.db.trackedBuffs[trackerKey]` (`:412`). Trinket and Pot fail
`IsBagItemEntry` because they have no numeric itemID (Core.lua:594-596), so they stay without Edit.

### `EDIT_TITLE_BY_KIND`, CDMTab.lua:2555-2561
```lua
local EDIT_TITLE_BY_KIND = {
	[ns.KIND.USER_CD] = "Edit Cooldown Tracker",
	[ns.KIND.USER_BUFF] = "Edit Buff Tracker",
	[ns.KIND.USER_REMINDER] = "Edit Reminder",
}
```
Add `[ns.KIND.META_ITEM] = "Edit Item Tracker"` (or similar). It is read at `:3023`
`dialog:SetTitle(EDIT_TITLE_BY_KIND[ctx.kind] or EDIT_TITLE_BY_KIND[ns.KIND.USER_BUFF])`. Without
the new row an item would be titled "Edit Buff Tracker".

### How the dialog resolves kind and fields, CDMTab.lua:3012-3041
```lua
	dialog.OpenForEdit = function(key)
		local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key]
		if not ns:IsEditableTracker(entry) then
			return
		end
		wipe(ctx)
		ctx.mode = "edit"
		ctx.kind = entry.trackerType
		ctx.editingKey = key
		dialog:SetTitle(EDIT_TITLE_BY_KIND[ctx.kind] or EDIT_TITLE_BY_KIND[ns.KIND.USER_BUFF])
		confirmBtn:SetText("Save")
		for _, field in ipairs(fieldStates) do
			local def, state = field.def, field.state
			def.reset(state, ctx)
			def.prefill(state, entry, ctx)
		end
		SelectGeneral()
		dialog:Show()
		FocusFirstShown()
	end
```
- The field list is not chosen per kind. **Every** built field runs reset and prefill. Visibility
  comes only from each def's `visible(state, ctx)`, and greying only from `enabled(state, ctx, dialog)`
  (RefreshState `:2815-2855`).
- `ctx.kind` is `"metaItem"`. It is not in `ns.BUFF_LIKE_KINDS` (Core.lua:615-618, which holds
  userBuff plus the reminder kinds), not in `ns.REMINDER_KINDS`, and not `USER_CD`. Section 2 lists
  what each field's hook answers for that kind.
- The dialog opens on General. For an item, every General field is greyed, so `FocusFirstShown`
  (`:2881-2888`) focuses nothing. That is harmless. Opening on Advanced for items, where the three
  editable fields are, is a discretionary nicety: `SelectTab("advanced")` exists at `:2898`.

### 1c. `ns:UpdateTrackedBuff` is NOT safe for a metaItem entry (BuffEngine.lua:1321-1454)

What it rewrites, and why each part breaks an item:

| Line | Code | Item problem |
|---|---|---|
| 1329 | `if type(spellID) ~= "number" or spellID <= 0 then return false, "Invalid spell ID"` | An item has no spell ID. The greyed spellID box reads `GetNumber()` = 0 (or the item ID if the planner shows it there), so this refuses the edit or treats the item ID as a spell. |
| 1334 | duration must be > 0 | An item's `entry.duration` is the game cooldown, and it is **0** whenever the item is not cooling down (Providers.lua:1576-1581, ItemDisplayInfo `info.duration = 0` :1738). Save would be refused. |
| 1341-1342 | `newKey = ns:TrackerKey(kind, spellID)` | This would mint `metaItem:<spellID-or-0>`: a **different key**, an orphan move of the entry, and broken `itemUseSpellToID`, counts and `iconOverride` lookups. |
| 1344 | `ns:FindTrackerConflict(kind, spellID, oldKey)` | It is meaningless for metaItem. |
| 1377-1387 | move block: `entry.spellID = spellID`, `entry.label = ns:SpellLabel(spellID)` | It would write a spellID onto an item. CDMTab.lua:204-206 warns this "would misroute ApplyCooldownSlot's spellID branch". |
| 1389 | `entry.duration = duration` | It clobbers the game cooldown. RefreshTrackedItemCooldowns would fix it later, but it is wrong in the meantime. |
| 1390-1398 | `for _, k in ipairs(fieldKeys) ... entry[k] = fields[k]` (skips ENGINE_OWNED `:1125-1135`) | **readKeys includes every RELEVANT field, greyed or not**, because the confirm loop at CDMTab.lua:2938-2944 reads `field.relevant` and ignores `enabled`. So `load`, `coverAllRanks`, `auraID` and `endOnCast` would be written onto the item if they are visible for metaItem. |
| 1407-1417 | chat print `", " .. duration .. "s)."` | For an item this prints the game cooldown. |

**What is reusable as is, for any `IsCooldownSlotEntry` entry, which includes items:**

BuffEngine.lua:1399-1403 (buff turned off ends it):
```lua
	if ns:IsCooldownSlotEntry(entry) and not ns:CooldownBuffDuration(entry) then
		ns.activeTimers[newKey] = nil
	end
```
BuffEngine.lua:1432-1442 (IN-04: a changed duration ends the running buff, a changed Aura ID repoints it):
```lua
	if ns:IsCooldownSlotEntry(entry) then
		local running = ns.activeTimers[newKey]
		local buffDuration = ns:CooldownBuffDuration(entry)
		if running ~= nil and buffDuration then
			if running.duration ~= buffDuration then
				ns.activeTimers[newKey] = nil
			else
				running.aliveBuffs = ns:CooldownBuffAliveBuffs(newKey, entry)
			end
		end
	end
```
Tail at :1443-1453: `MarkTrackersDirty`, `MarkCooldownsDirty`, `UpdateDisplay`, `return true, newKey`.

**Recommended buff-only path.** Either an early branch inside UpdateTrackedBuff (option A) or its own
`ns:UpdateTrackedItemBuff(key, fields)` (option B). Its shape:
1. Look up the entry and refuse unless `ns:IsBagItemEntry(entry)`.
2. Write **only** `entry.buffEnabled`, `entry.buffAuraID` and `entry.buffDuration` from `fields`.
   Use an explicit three-key list, so it does not depend on readKeys or ENGINE_OWNED.
3. Apply the two Phase 74 blocks above with `newKey = key`. No `RebuildRankIndex` is needed: an
   item never owns a rank family (section 5). Calling it anyway is harmless.
4. Mark both dirty flags and redraw, then `return true, key`.
5. Print a chat line keyed on `entry.label`, not on a duration.

The confirm handler (CDMTab.lua:2959-2972) must then route an item to that path. Option A makes this
automatic. Under option B, branch on `ctx.kind == ns.KIND.META_ITEM`. Either way, keep the
post-commit `ns:RefreshTBTSections(); ns:StartAllPreviewTimers(); dialog:Hide()`:
```lua
		elseif ctx.mode == "edit" then
			local ok, reason = ns:UpdateTrackedBuff(ctx.editingKey, values.spellID, values.duration, values, readKeys)
			if not ok then
				ShowError(reason or "")
				return
			end
			ns:RefreshTBTSections()
			ns:StartAllPreviewTimers()
			dialog:Hide()
		end
```

---

## 2. Greyed fields for an item: what each TRACKER_FIELDS def does for `ctx.kind == "metaItem"`

Contract text: CDMTab.lua:1801-1809. A field with `enabled() == false` is still shown, still READ
and saved, **not validated**, and skipped by Tab/Enter and FocusFirstShown. "Never grey through
visible()." A def with no `enabled` key is never touched (`:2840`).

| Field (line) | entryKey | tab | `available` | `visible` today for metaItem | `enabled` hook today | State holds `label`? | Item prefill today |
|---|---|---|---|---|---|---|---|
| `spellPreview` (:1919-2016) | none | both | - | always | none | n/a (`hover`,`icon`,`name`) | resolves the spellID box as a spell, which is empty for an item, so it shows a dimmed 134400 and no name |
| `spellID` (:2017-2062) | spellID | general | - | always | none | **no**: `return { editBox = box }` :2035 | `tostring(entry.spellID or "")` = **""** |
| `secrecyBadge` (:2063-2115) | none | general | - | `SecrecyWarns(level)`, nil for id 0, so hidden | none | (`badge`) | - |
| `duration` (:2116-2232) | duration | general | - | always | none | **no**: `{ editBox, source, preview }` :2139 | `FormatDuration(entry.duration)`, the game cooldown (often 0). `update` returns early: not cd, not buff-like (:2168-2171) |
| `coverAllRanks` (:2233-2268) | coverAllRanks | general | `ns.CLIENT_HAS_SPELL_RANKS` (Forever only) | always | none | **no**: `{ check = check }` :2254; label is a child FontString of the check | `entry.coverAllRanks == true`, so unchecked |
| `auraID` (:2272-2280) | auraID | advanced | - | `ctx.kind ~= USER_CD`, so **shown** | none | yes (factory) | follows the empty spellID box |
| `keepOnAuraLoss` (:2281-2319) | keepOnAuraLoss | advanced | - | `BUFF_LIKE_KINDS[kind]`, so hidden | - | - | - |
| `endOnCast` (:2320-2347) | endOnCast | advanced | - | `not REMINDER_KINDS[kind]`, so **shown**, labelled "Ends when you cast" (:2329) | none | yes (`BuildSpellListField` :1450) | empty |
| `alternatives` (:2348-2371) | | advanced | - | reminders only, so hidden | - | - | - |
| `castID` (:2375-2383) | | advanced | - | reminders only, so hidden | - | - | - |
| `buffEnabled` (:2384-2418) | buffEnabled | advanced | - | `CarriesCooldownBuff`, **USER_CD only**, so hidden | none | yes | - |
| `buffAuraID` (:2422-2430) | buffAuraID | advanced | - | `CarriesCooldownBuff`, so hidden | `BuffFieldEnabled` | yes | - |
| `buffDuration` (:2431-2488) | buffDuration | advanced | - | `CarriesCooldownBuff`, so hidden | `BuffFieldEnabled` | yes | - |
| `load` (:2489-2543) | load | advanced | - | always | none | **no**: `{ dropdown, selected }` :2504 | `entry.load` nil, so **"When known"**. That is wrong for an item, whose fixed load is ALWAYS (Core.lua:633-637). |

### Hook pattern to copy, CDMTab.lua:1905-1916
```lua
local function CarriesCooldownBuff(_, ctx)
	return ctx.kind == ns.KIND.USER_CD
end

local function BuffFieldEnabled(_, ctx, dialog)
	return dialog.GetFieldState("buffEnabled").check:GetChecked() and true or false
end
```
- Widen `CarriesCooldownBuff` to `ctx.kind == ns.KIND.USER_CD or ctx.kind == ns.KIND.META_ITEM`.
  The comment at :1905-1907 already says "Phase 76 widens it to bag items". `ctx` holds only the
  kind, not the entry. Since the dialog opens only for bag items among metaItem entries (it is gated
  in OpenForEdit), `ctx.kind == META_ITEM` is sufficient there.
- Add one file-local next to it, declared **above TRACKER_FIELDS** (upvalue-order rule, memory
  note), e.g. `local function NotItemField(_, ctx) return ctx.kind ~= ns.KIND.META_ITEM end`. Set it
  as `enabled = NotItemField` on `spellID`, `duration`, `coverAllRanks` and `load`, and on `auraID`
  and `endOnCast` if those stay visible.
- Because greyed fields are **not validated** (:2797), greying `spellID` and `duration` is what stops
  their `validate` (spellID > 0, :2046-2050; duration non-empty, :2222-2226) from blocking Save.

### ApplyFieldEnabled, CDMTab.lua:1743-1778 (generic and already sufficient for the widgets)
```lua
local function ApplyFieldEnabled(state, enabled)
	local r = enabled and 1 or 0.5
	local alpha = enabled and 1 or 0.5
	if state.label then state.label:SetTextColor(r, r, r) end
	if state.editBox then
		if not enabled then state.editBox:ClearFocus() end
		state.editBox:SetEnabled(enabled)
		state.editBox:SetTextColor(r, r, r)
	end
	if state.check then state.check:SetEnabled(enabled) end
	if state.dropdown then state.dropdown:SetEnabled(enabled) end
	if state.hover then state.hover:SetAlpha(alpha); state.hover:EnableMouse(enabled) end
	if state.name then state.name:SetAlpha(alpha) end
	if state.badge then state.badge:SetAlpha(alpha); state.badge:EnableMouse(enabled) end
end
```
**Plan-checker gap:** `spellID`, `duration`, `coverAllRanks` and `load` do not keep their label in
state, so their labels stay white while the box greys. Fix it the way Phase 74 did for `buffEnabled`
(`return { check = check, label = label }` :2403) and `buffDuration`
(`return { editBox = box, label = label }` :2453): add `label = label` to each build's returned
table.
- spellID :2035: `return { editBox = box, label = label }, y - 32`
- duration :2139: add `label = label` to the table
- coverAllRanks :2254: `return { check = check, label = label }, y - 26` (the label is
  `check:CreateFontString`, and SetTextColor works the same)
- load :2504: `local state = { dropdown = dropdown, selected = ns.LOAD.KNOWN, label = label }`

Caution: the spellID state table **must not** gain any key the focus ring or other fields
misinterpret. `label` is safe; only `editBox` joins the ring (:2709).

### Prefilling item values into the greyed fields
What a bag item entry actually holds, from AddSuggestedTracker CDMTab.lua:193-215:
`key, label (item name), duration (game cd), section, layoutOrder, trackerType="metaItem", spellID=nil, itemID, iconOverride (item icon)`.

- **Load:** prefill should show `ns:TrackerLoad(key, entry)` (Core.lua:643-659), which returns
  `ALWAYS` for metaItem, instead of reading `entry.load`. `prefill(state, entry, ctx)` gets ctx, and
  the key is `ctx.editingKey`. Alternatively special-case `ctx.kind == META_ITEM` to set
  `state.selected = ns.LOAD.ALWAYS`.
- **Duration:** `FormatDuration(entry.duration)` already shows the game cooldown. Note it is 0 when
  ready. An alternative is `ns:CooldownDuration(key, entry)`. Either way, nothing is written back
  (buff-only path).
- **Spell ID vs Item ID:** the item has no spell ID. **Hazard if the item ID is placed in the
  spellID box:**
  1. `buffAuraID` (a follow field) copies the spellID box text while `followsSpell` is true
     (`:1666-1673`). That would prefill the item ID into the Aura ID box, which violates the
     user's "empty by default" decision.
  2. `spellPreview` would resolve the item ID as a **spell** through `ns:RefreshIDPreview`
     (`:2004-2012`, `:1270`), and `secrecyBadge` would run `ns:SpellAuraSecrecy(itemID)`
     (`:2105`).
  3. The follow field's `read` returns nil when `typed == spell box number` (`:1715-1718`).

  Safer: keep the spellID box empty for items (its honest value), and put the item identity on the
  portrait: icon = `entry.iconOverride`, name = `entry.label`. If the planner does want "Item ID:" in
  that row, set the label text per kind in reset/prefill (copy endOnCast's per-kind label
  `:2327-2340`). Then all three hazards above need their own item guard.
- **Portrait (spellPreview) for an item:** its `update` calls
  `ns:RefreshIDPreview(state, source.editBox:GetNumber())` on every refresh. Copy the id<=0 arm's
  widget calls (`:1252-1267`: `icon:SetTexture`, `SetDesaturated`, `SetAlpha`, `name:SetText`), but
  with `entry.iconOverride` / `entry.label`. Stash them in `state` in `prefill`, clear them in
  `reset`, and in `update` branch `if ctx.kind == ns.KIND.META_ITEM then ... return end`, with a
  compare-before-write stamp so it does not re-set every keystroke. The hover tooltip: the item path
  of `ns:ShowBuffTooltip` (Display.lua:350-357) fires only when `proc.itemID` is set **and opts is
  nil**. The portrait passes `state.tooltipOpts`, so an item tooltip would need its own OnEnter arm,
  or this can be left as no tooltip (greyed, with `hover:EnableMouse(false)` from ApplyFieldEnabled
  if spellPreview gets `enabled = NotItemField`).
- **`auraID` / `endOnCast`:** these are not "existing fields" of an item; it has neither. Decide one
  of two things. Either grey them with `NotItemField` (they then show empty and greyed), or hide them
  for items through `visible`. Hiding is allowed here, because a hidden field is simply not read and
  an item never had that value. Caveat: CONTEXT says "every field except the three buff fields ...
  greyed". If kept visible, endOnCast's label for an item should still read sensibly (it currently
  says "Ends when you cast").

---

## 3. Buff fields for items: gates and follow behaviour

Gates to widen: `visible = CarriesCooldownBuff` on `buffEnabled` (:2391), `buffAuraID` (:2428) and
`buffDuration` (:2438). `enabled = BuffFieldEnabled` stays as is. The save rule ("ticked, so both
filled") comes from `buffDuration.validate` (:2476-2487) and from `buffAuraID`'s `requiredMessage`.

**Follow-the-Spell-ID trap (must fix for items).** BuildFollowSpellIDField (CDMTab.lua:1528-1734):
```lua
		prefill = function(state, entry)
			state.followsSpell = entry[key] == nil
			state.editBox:SetText(entry[key] and tostring(entry[key]) or "")
			...
		update = function(state)
			if state.followsSpell then
				local spellText = state.spell.editBox:GetText()
				if state.editBox:GetText() ~= spellText then
					state.syncing = true
					state.editBox:SetText(spellText)
					state.syncing = false
				end
			end
		...
		validate = function(state)
			...
			-- A box still following the Spell ID holds it, so it counts as filled; only a box the
			-- user emptied fails, and only for a field that asked for it.
			if opts.requiredMessage and not state.followsSpell and state.editBox:GetNumber() <= 0 then
				return false, opts.requiredMessage
			end
```
For an item with no saved `buffAuraID`, `followsSpell = true`. It follows an empty spellID box, so
the box shows empty (good). **But validate then passes with an empty box**, because "following counts
as filled". Save would store `buffEnabled = true` with no Aura ID. That breaks the "both must be
filled" rule, and the running buff's aliveBuffs becomes `AcquireAliveBuffs(key, nil)` = `{}`, which
the cancellation scan skips (BuffEngine.lua:1637). The buff would never end early.

Fix pattern: make an item's Aura ID box **never follow**. The factory's `prefill` and `reset` get
`(state, entry, ctx)` / `(state, ctx)` (contract :1814-1815; reset is called with ctx at :2995/:3030).
- Add an opt, e.g. `opts.follows = function(ctx) return ctx.kind ~= ns.KIND.META_ITEM end`, used for
  buffAuraID only. In reset and prefill: `state.followsSpell = (not opts.follows or opts.follows(ctx)) and ...`.
- With `followsSpell = false`, the existing `requiredMessage` check fires on an empty box, and
  `read` returns the typed ID because `typed ~= 0` (spell box). The comparison `typed ~= state.spell.editBox:GetNumber()`
  (:1715) is against 0 for an item, so any typed ID is stored. Good.
- Keep this field's `update` preview working: with `typed <= 0` it falls back to the spell box id 0,
  which gives the placeholder (:1683-1684). That is fine.
- Also update the comment at :2419-2421 ("following the Spell ID until typed in") to cover items.

Runtime fallback check: `ns:CooldownBuffAuraID(entry)` (Core.lua:773-778) returns
`CooldownBuffTypedAuraID(entry) or entry.spellID`, which is **nil** for an item with no typed ID.
Nothing in the item path calls it except for display. The dialog guarantees a typed ID whenever
`buffEnabled`. `ns:CooldownBuffDuration` (Core.lua:758-767) never reads `entry.duration`, so the
game-cooldown overwrite cannot leak into the buff (BUFFCD saved-data decision satisfied with no code).

---

## 4. Item cast path

### Current OnTrigger, Providers.lua:1766-1804
```lua
function MetaItemBagProviderMixin:OnTrigger(event, unit, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return nil end
	if unit ~= "player" then return nil end
	if type(spellID) ~= "number" then return nil end
	local itemID = itemUseSpellToID[spellID]
	if itemID == nil then
		return nil
	end
	local key = META_ITEM_PREFIX .. itemID
	if ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs[key] then
		local current = itemTrackedCounts[key]
		if current ~= nil then
			itemTrackedCounts[key] = math.max(0, current - 1)
		end
	end
	ns:RefreshTrackedItemCooldowns()
	ns:MarkCooldownsDirty()
	return nil
end
```
**Analog for the insertion**, from the user-spell cooldown side, Providers.lua:354-357:
```lua
	local cdKey = ns:StartCooldownFromCast(tracked, ns.cooldownKeyBySpell, ns.rankIndexCooldown, spellID)
	if cdKey then
		ns:StartCooldownBuffFromCast(cdKey, tracked[cdKey])
	end
```
Insert `ns:StartCooldownBuffFromCast(key, entry)` for the matched `key` (`metaItem:<itemID>` from
the map, so "last writer wins" picks the tracker whose item matched). Place it **after**
`RefreshTrackedItemCooldowns()` / `MarkCooldownsDirty()` so the cooldown stamp is current. Keep
`return nil`: the buff is a **side-effect writer** of `ns.activeTimers`, exactly like the userCd one.
Reuse the existing tracked-entry lookup (`ns.db.trackedBuffs[key]`, which is one hash read) rather
than a second walk. The hot-path rule: the untracked-cast early-out at :1780-1783 stays first.

`ns:StartCooldownBuffFromCast` (Providers.lua:221-259) needs **no change** to accept an item:
- `ns:IsCooldownSlotEntry(entry)` is true for a bag item (Core.lua:589).
- `entry.section ~= "hidden"` plus the icon-container check (:225-234) give the hidden-section rule.
- The load rule holds trivially: bag items are `FIXED_LOAD = ALWAYS` (Core.lua:633-637).
- `ns:CooldownBuffDuration(entry)` gates on `buffEnabled` / `buffDuration` (missing means off).
- `ns:CooldownBuffAliveBuffs(key, entry)` returns `ns:AcquireAliveBuffs(key, typedID)` for an item
  (section 5).
- `ns:FillUserBuffProc(key, entry, now, aliveBuffs)` (:101-160): `proc.spellID = entry.spellID` is
  **nil** for an item, and `proc.label = entry.label` (the item name) is set. It does not allocate,
  because the pool is preallocated by `ns:PreallocateProc(key)` at AddSuggestedTracker
  (CDMTab.lua:226) and at load.

**Comment updates required** (they now state the opposite):
- Providers.lua:1758-1765: "An item tracker has no buff side, no duration to hand-maintain and no
  ns.activeTimers entry at all". It still must **return** nil; the buff is a side-effect write.
- Providers.lua:1927-1935 DESIGN NOTE list of writers: add the bag-item OnTrigger to the
  `ns:StartCooldownBuffFromCast` bullet.
- Providers.lua:198-220 header: "A user cooldown with ..." should become "A user cooldown or bag
  item ...".

**Optional proc field for the tooltip:** `icon.proc = timer` in the live-timer branch
(Display.lua:1738), and `ns:ShowBuffTooltip`'s item path keys on `proc.itemID` (Display.lua:352-357).
A buff proc for an item has no itemID (AcquireProc wipes, BuffEngine.lua:833-842), so the tooltip
falls to the label-only spell path while the buff runs. Setting `proc.itemID = entry.itemID` after
Fill in StartCooldownBuffFromCast costs nothing (one field write, no allocation). It is nil for
userCd, so they are unaffected.

### Refresh paths never touch buff keys (verified)
- `ns:SeedItemTracker` (Providers.lua:1545-1582) writes only `entry.duration` and
  `ns.cooldownStarts[key]` (:1573-1574), plus counts.
- `ns:RefreshTrackedItemCooldowns` (Providers.lua:1589-1611) writes only `entry.duration` and
  `ns.cooldownStarts[key]` (:1602-1603).
- No migration or other code touches `buffEnabled` / `buffAuraID` / `buffDuration`. A grep finds
  only Core.lua (5), CDMTab.lua (10) and BuffEngine.lua (7), all Phase 74 readers and writers.

### AddSuggestedTracker re-add/move, CDMTab.lua:150-246
```lua
	if ns.db.trackedBuffs[key] then
		ns:SetBuffSection(key, targetSection)
		return
	end
```
A move of an existing item keeps the **same entry table**, so the buff keys survive.
`ns:SetBuffSection` (BuffEngine.lua:1456-1482) ends the running buff only on a move to `"hidden"`
(`:1471-1473`), which is the Phase 74 hidden rule. Only a removed-then-re-added item builds a fresh
literal (:193-215) with no buff keys. That is correct (missing means off), because removal ran
`ClearTrackerRuntimeState`. **No change needed**; at most a comment.

### Other end-paths, checked for items
- `ns:ApplyEndOnCast` (BuffEngine.lua:1505-1543) has a `USER_CD`-only branch at :1522. An item
  never has an `endOnCast` rule, so nothing applies, provided the item edit path never writes
  `endOnCast` (section 1c).
- Remove and unload go through `ns:EndTrackerRuntime` (BuffEngine.lua:1105-1115), which nils
  `activeTimers[key]` for any kind.
- Preview, `StartAllPreviewTimers` (BuffEngine.lua:1585-1605):
  `local buffDuration = ns:IsCooldownSlotEntry(entry) and ns:CooldownBuffDuration(entry)` already
  covers items. Effect: a buff-on item now **gets** a preview proc (before, `info.duration = 0`
  meant no preview). That preview table has `spellID = info.spellID`, which is nil for an item. The
  same icon/tooltip note as below applies. Adding `itemID = entry.itemID` there is optional, and it
  is edit-time only (not hot).

### Display: an item buff proc has no spellID (Phase 76 change in Display.lua, after 75 lands)
Live-timer branch, Display.lua:1738-1749 (working tree):
```lua
			icon.proc = timer -- D-19: store for OnEnter tooltip
			-- ... "a live timer always carries a numeric spellID" -- reachability argument ...
			if icon.cachedSpellID ~= timer.spellID then
				icon.cachedSpellID = timer.spellID
				icon.cachedIcon = ns:GetSpellIcon(timer.spellID)
			end
			icon.icon:SetTexture(icon.cachedIcon)
```
`ns:GetSpellIcon(nil)` returns **134400** (BuffEngine.lua:766-769). It works today only by accident:
a widget that last drew the same item through `ApplyCachedIcon` has `cachedSpellID == nil`, so the
test is false and the cached item icon stays. A pooled widget arriving from any other tracker shows
the question mark for the whole buff. This is exactly the assumption the comment flags.
Analog fix, ApplyCachedIcon (Display.lua:839-846):
```lua
local function ApplyCachedIcon(widget, spellID, iconOverride)
	if widget.cachedSpellID ~= spellID or widget.cachedOverride ~= iconOverride or widget.cachedIcon == nil then
		widget.cachedSpellID = spellID
		widget.cachedOverride = iconOverride
		widget.cachedIcon = iconOverride or (spellID and ns:GetSpellIcon(spellID)) or 134400
	end
	widget.icon:SetTexture(widget.cachedIcon)
end
```
Use `ApplyCachedIcon(icon, timer.spellID, slotEntry and entry.iconOverride or nil)` in the timer
branch, or call it only `if slotEntry`, to leave buff and reminder procs byte-identical. It is
stamped, so the per-tick cost is unchanged. `slotEntry` is already a local there (Display.lua:1707,
Phase 75). The item count (ApplySlotCount → ApplyItemCount) and the yellow look are already handled
by Phase 75 for any `IsCooldownSlotEntry`.

---

## 5. RebuildRankIndex and the indexes `ns:CooldownBuffAliveBuffs` assumes

`ns:CooldownBuffAliveBuffs`, Core.lua:806-812:
```lua
function ns:CooldownBuffAliveBuffs(key, entry)
	local typedAuraID = ns:CooldownBuffTypedAuraID(entry)
	if typedAuraID then
		return ns.detailedRankFamilies[key] or ns:AcquireAliveBuffs(key, typedAuraID)
	end
	return ns.rankFamilies[key] or ns:AcquireAliveBuffs(key, entry.spellID)
end
```
Owner selection in `ns:RebuildRankIndex`, Core.lua:1739-1754:
```lua
	for k, entry in pairs(ns.db.trackedBuffs) do
		if
			entry.coverAllRanks
			and type(entry.spellID) == "number"
			and ns:IsTrackerLoaded(k)
			and (ns:IsBuffLikeEntry(entry) or entry.trackerType == ns.KIND.USER_CD)
		then
			table.insert(rebuildOwners, k)
		end
	end
```
A bag item fails three of the four conditions: no `coverAllRanks`, no numeric `spellID`, and it is
neither buff-like nor USER_CD. So it is **never** a rank owner, and both `ns.rankFamilies[key]` and
`ns.detailedRankFamilies[key]` are always nil for `metaItem:<id>`. Consequences:
- With a typed Aura ID (always the case, once section 3 is fixed), the result is
  `ns:AcquireAliveBuffs(key, typedAuraID)`, the pooled one-element list (BuffEngine.lua:846-856). That
  is correct and allocation-free.
- With no typed ID it would be `AcquireAliveBuffs(key, nil)`, i.e. `{}`, and the scan skips it
  (BuffEngine.lua:1637). It does not crash, but the buff never ends early. This is why the dialog
  must enforce a typed ID (section 3).
- This must stay so: if the greyed `coverAllRanks` were ever **written** onto an item (the generic
  field copy, section 1c), the item still would not qualify (no spellID). Do not rely on that; the
  buff-only save path writes nothing but the three buff keys.
- The cast-side indexes (`ns.cooldownKeyBySpell`, `ns.rankIndexCooldown`) never hold an item. An
  item use is recognised only through `itemUseSpellToID` (Providers.lua:1334). It is kept current by
  `ns:RegisterTrackedItemUseSpell` (:1516-1527), `RegisterAllTrackedItemUseSpells` (:1534-1543) and
  `ns:SeedItemTracker` (:1552). Collision handling is last writer wins, debug-logged
  (Providers.lua:1429-1441).
- The edit's buff-only path need not call `ns:RebuildRankIndex`, because nothing it writes changes
  an index. The IN-04 repoint `running.aliveBuffs = ns:CooldownBuffAliveBuffs(key, entry)` is still
  correct, since it reuses the pooled list.

---

## Shared Patterns

### Compare-before-write and no per-tick allocation
**Source:** RefreshState's enabled flip, CDMTab.lua:2840-2846, and the Phase 75 stamps.
**Apply to:** any new `update` arm (the item portrait) and the Display icon fix.
```lua
			if def.enabled then
				local enabled = def.enabled(state, ctx, dialog) and true or false
				if enabled ~= field.enabled then
					field.enabled = enabled
					ApplyFieldEnabled(state, enabled)
				end
			end
```

### Missing key means off, nil-safe ns helpers
**Source:** Core.lua:758-792 (`CooldownBuffDuration`, `CooldownBuffAuraID`, `CooldownBuffTypedAuraID`).
**Apply to:** every runtime reader. Do not add a schema bump. The `CURRENT_SCHEMA_VERSION = 12` and
ENGINE_OWNED tables (BuffEngine.lua:1125-1135) stay unchanged.

### Upvalue-order rule
Any new file-local hook (`NotItemField`, or a widened `CarriesCooldownBuff`) must be declared above
`TRACKER_FIELDS` (CDMTab.lua:1918), next to `CarriesCooldownBuff` (:1908). New engine helpers go on
`ns`, like `ns:CooldownBuff*`.

### Secret-value ordering
**Source:** Providers.lua:1568-1572 (`issecretvalue()` before `type()`/truthiness).
**Apply to:** any new item read, e.g. if the dialog re-reads `C_Item.GetItemCooldown` for the greyed
duration (prefer `entry.duration` instead, which needs no API call). No aura read is added, so
`node scripts/aura-read-gate.js` stays green.

### File hygiene (CLAUDE.md)
Use the Edit tool only. Never use `sed -i` or a redirect. Run `stylua .`. Check
`git ls-files --eol <file>` gives `w/crlf`. Keep comments out of multi-line expressions (the stylua
CRCRLF trap). Run `./scripts/install.bat` after changes.

---

## No Analog Found

| File / piece | Role | Data Flow | Reason |
|---|---|---|---|
| Item face on the dialog portrait (`spellPreview` item arm) | component | transform | The dialog has only ever previewed spells. Combine the `RefreshIDPreview` id<=0 arm (CDMTab.lua:1252-1267) with `entry.iconOverride`/`entry.label` (stored for this exact reason, CDMTab.lua:208-214). |
| Buff-only commit for a bag item | service | CRUD | UpdateTrackedBuff is spell-keyed throughout. Assemble it from its own Phase 74 blocks (BuffEngine.lua:1399-1403, :1432-1453). |

## Metadata

**Analog search scope:** Core.lua, BuffEngine.lua, Providers.lua, CDMTab.lua, Display.lua
(read-only); Phase 74 summaries and review-fix; 75-01-PLAN.
**Files scanned:** 5 source files plus 5 planning docs.
**Pattern extraction date:** 2026-10-22
