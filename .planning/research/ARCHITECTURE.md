# Architecture Research

**Domain:** WoW Midnight addon — meta-tracker slots (trinkets & damage pots)
**Researched:** 2026-04-11
**Confidence:** HIGH (code read directly; APIs verified against warcraft.wiki.gg)

## Standard Architecture

### System Overview (Existing + New)

```
+------------------------------------------------------------------+
|  Core.lua — Event router                                          |
|  ADDON_LOADED, PLAYER_ENTERING_WORLD,                             |
|  UNIT_SPELLCAST_SUCCEEDED, UNIT_AURA,                             |
|  PLAYER_REGEN_ENABLED, ZONE_CHANGED_NEW_AREA                      |
+------------------+-------------------+---------------------------+
                   |                   |                   |
                   v                   v                   v
+------------------+----+  +----------+------+  +---------+--------+
|  BuffEngine.lua       |  | EditModeFrames  |  | Display.lua      |
|                       |  | .lua            |  |                  |
|  ns.activeTimers      |  | barContainer    |  | UpdateDisplay()  |
|  OnSpellCastSucceeded |  | iconContainer   |  | bar/icon pools   |
|  OnUnitAura           |  | Edit Mode       |  | RefreshContainer |
|  StartLustTimer       |  | positioning     |  | Settings()       |
|  [NEW]                |  +-----------------+  +------------------+
|  StartTrinketTimer()  |
|  StartPotTimer()      |
|  TRINKET_SPELLS table |
|  POT_SPELLS table     |
|  ResolveTrinketIcon() |
|  ResolvePotIcon()     |
|  GetAtRestMetaIcon()  |
+-----------------------+
           |
           v
+------------------------------------------------------------------+
|  CDMTab.lua — CDM tab, Suggested section                          |
|                                                                    |
|  ns.SUGGESTED_BUFFS  <-- [NEW entries: "trinket", "pot"]          |
|  RefreshTBTSections()  -> renders Suggested icons from catalog    |
|  BeginDrag/EndDrag     -> copy-on-drag from Suggested to sections |
|  addSuggestedToSection -> creates trackedBuffs entry on demand    |
+------------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | New vs Modified |
|-----------|----------------|-----------------|
| `BuffEngine.lua` — `TRINKET_SPELLS` | Maps trinket use spellID -> {duration, itemID, label} | NEW — add table |
| `BuffEngine.lua` — `POT_SPELLS` | Maps pot use spellID -> {duration, itemID, label} | NEW — add table |
| `BuffEngine.lua` — `OnSpellCastSucceeded` | Fan-out to `StartTrinketTimer`/`StartPotTimer` when spellID in respective table | MODIFIED |
| `BuffEngine.lua` — `StartTrinketTimer(spellID)` | Shared-slot timer keyed "trinket"; icon = active spell's icon; overwrite on re-proc | NEW — mirrors `StartLustTimer` |
| `BuffEngine.lua` — `StartPotTimer(spellID)` | Shared-slot timer keyed "pot"; icon = active spell's icon; overwrite on re-proc | NEW — mirrors `StartLustTimer` |
| `BuffEngine.lua` — `ResolveTrinketIcon()` | Scans equipped slots 13/14 via `GetInventoryItemID`; returns first tracked trinket icon | NEW |
| `BuffEngine.lua` — `ResolvePotIcon()` | Scans bags 0-4 via `C_Container.GetContainerItemID`; matches against POT_SPELLS itemIDs; returns icon | NEW |
| `BuffEngine.lua` — `GetAtRestMetaIcon(key)` | Helper: looks up `getAtRestIcon` fn from `ns.SUGGESTED_BUFFS` by key; called by Display.lua | NEW |
| `BuffEngine.lua` — `ns.SUGGESTED_BUFFS` | Append two new entries: key="trinket", key="pot", each with `getAtRestIcon` | MODIFIED |
| `BuffEngine.lua` — `ScanActiveTimersForCancellation` | Add `source == "meta"` skip clause to prevent string-key aura lookups | MODIFIED |
| `CDMTab.lua` — Suggested icon render | Guard: if `getCDMSpellID()` returns nil, call `getAtRestIcon()` for icon texture | MODIFIED (minor) |
| `CDMTab.lua` — Suggested tooltip | Guard: if no numeric spellID, fall back to label-only tooltip | MODIFIED (minor) |
| `Display.lua` — bar/icon at-rest path | After `ResolveSuggestedSpellID` returns nil, call `ns:GetAtRestMetaIcon(key)` | MODIFIED (minor) |
| `Core.lua` — event router | No changes; `UNIT_SPELLCAST_SUCCEEDED` already routed to `OnSpellCastSucceeded` | UNMODIFIED |
| `EditModeFrames.lua` | No changes | UNMODIFIED |

## Recommended Project Structure

No new files are required. All changes land in existing files:

```
TerribleBuffTracker/
+-- Core.lua              # unmodified
+-- BuffEngine.lua        # primary change surface
|   +-- TRINKET_SPELLS    # new lookup table (module level)
|   +-- POT_SPELLS        # new lookup table (module level)
|   +-- StartTrinketTimer # new function (after StartLustTimer)
|   +-- StartPotTimer     # new function (after StartTrinketTimer)
|   +-- ResolveTrinketIcon# new function
|   +-- ResolvePotIcon    # new function
|   +-- GetAtRestMetaIcon # new helper function
|   +-- SUGGESTED_BUFFS   # 2 new entries appended
|   +-- ScanActiveTimers  # modified: add "meta" source skip
|   +-- OnSpellCastSucceeded # modified: fan-out to trinket/pot
+-- CDMTab.lua            # minor: nil-spellID guard in Suggested section
+-- Display.lua           # minor: at-rest icon path calls GetAtRestMetaIcon
+-- EditModeFrames.lua    # unmodified
```

## Architectural Patterns

### Pattern 1: Meta-Tracker Shared Slot (mirrors lust)

**What:** One string key ("trinket" / "pot") owns a single entry in `ns.activeTimers`. Any matching spellID cast overwrites the existing timer — no per-spell slots.

**When to use:** When multiple different spells all represent the same resource cooldown that can only be in one state at a time.

**Trade-offs:** Simpler display (one bar/icon per concept). Loses per-spell granularity, which is acceptable because the player only needs to know "is my trinket on CD?" not which trinket fired.

**Example (mirrors `StartLustTimer` exactly):**
```lua
-- BuffEngine.lua
function ns:StartTrinketTimer(spellID)
    local entry = ns.db.trackedBuffs["trinket"]
    if not entry or entry.section == "hidden" then return end
    local now = GetTime()
    local def = TRINKET_SPELLS[spellID]
    local label = def.label or "Trinket"
    local info = C_Spell.GetSpellInfo(spellID)
    if info and info.name then label = info.name end
    ns.activeTimers["trinket"] = {
        spellID   = "trinket",
        expiresAt = now + def.duration,
        startedAt = now,
        duration  = def.duration,
        icon      = ns:GetSpellIcon(spellID),  -- active: cast spell icon
        label     = label,
        section   = entry.section or "bars",
        source    = "meta",  -- NOT "cast" — see Anti-Pattern 1
    }
    if ns.UpdateDisplay then ns:UpdateDisplay() end
end
```

### Pattern 2: Data Table Lookup on Cast (mirrors SATED_DEBUFF_TO_LUST)

**What:** Module-level constant tables map spell IDs to timer metadata. `OnSpellCastSucceeded` becomes a dispatch fan-out: check `TRINKET_SPELLS`, check `POT_SPELLS`, then check `ns.db.trackedBuffs`.

**When to use:** Any time "same event, different handling based on spell identity." Adding a new trinket to track in a future season requires only a data table update, not logic changes.

**Example:**
```lua
-- BuffEngine.lua — module level
local TRINKET_SPELLS = {
    -- [spellID] = { duration = N, itemID = M, label = "..." }
    -- Season-specific usable trinkets go here
}

local POT_SPELLS = {
    -- [spellID] = { duration = N, itemID = M, label = "..." }
}

-- Modified OnSpellCastSucceeded
function ns:OnSpellCastSucceeded(spellID)
    -- Existing: user-tracked buffs
    local entry = ns.db.trackedBuffs[spellID]
    if entry and entry.section ~= "hidden" then
        -- ... existing timer start ...
    end
    -- NEW: trinket meta-tracker
    if TRINKET_SPELLS[spellID] then
        ns:StartTrinketTimer(spellID)
    end
    -- NEW: pot meta-tracker
    if POT_SPELLS[spellID] then
        ns:StartPotTimer(spellID)
    end
end
```

### Pattern 3: Lazy Icon Resolution with `getAtRestIcon`

**What:** `ns.SUGGESTED_BUFFS` entries carry an optional `getAtRestIcon` function called at render time (not cast time). For trinkets it calls `ResolveTrinketIcon()`; for pots it calls `ResolvePotIcon()`. Resolution is deferred to avoid stale data from pre-equip state.

**When to use:** When the at-rest icon depends on the player's current loadout (equipped gear, bag contents) rather than a fixed spell ID.

**Trade-offs:** Slightly more work than a fixed icon. Acceptable because the at-rest path only runs when CDM settings are open OR when `hideWhenInactive = false`. Fully out of the hot path.

**Example:**
```lua
-- BuffEngine.lua — new SUGGESTED_BUFFS entries
ns.SUGGESTED_BUFFS = {
    {  -- existing lust entry unchanged
        key = "lust", ...
    },
    {
        key           = "trinket",
        label         = "Trinket",
        duration      = 0,    -- placeholder; actual duration from TRINKET_SPELLS at cast time
        metaBuff      = true,
        getCDMSpellID = function() return nil end,  -- no fixed spell; icon from gear
        getAtRestIcon = function() return ns:ResolveTrinketIcon() end,
    },
    {
        key           = "pot",
        label         = "Damage Pot",
        duration      = 0,
        metaBuff      = true,
        getCDMSpellID = function() return nil end,
        getAtRestIcon = function() return ns:ResolvePotIcon() end,
    },
}
```

### Pattern 4: Equipped Trinket Icon Resolution

**What:** `ResolveTrinketIcon()` calls `GetInventoryItemID("player", 13)` and `GetInventoryItemID("player", 14)` to find equipped trinkets. Optionally cross-references against TRINKET_SPELLS itemIDs to confirm it is a tracked trinket. Returns `C_Item.GetItemIconByID(itemID)`.

**Confidence:** HIGH — `GetInventoryItemID` confirmed available in Midnight 12.0.1 (warcraft.wiki.gg). TrinketTracker addon for Midnight uses this exact approach.

```lua
-- BuffEngine.lua
function ns:ResolveTrinketIcon()
    for _, slot in ipairs({13, 14}) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            local icon = C_Item.GetItemIconByID(itemID)
            if icon then return icon end
        end
    end
    return 134400  -- question mark fallback
end
```

Note: Scanning only tracked trinkets (cross-referencing TRINKET_SPELLS.itemID) is more precise but less forgiving of data gaps. Recommend showing any equipped trinket icon so the slot always looks meaningful even if the specific item is not in the table.

### Pattern 5: Bag Consumable Icon Resolution

**What:** `ResolvePotIcon()` scans bags 0-4 via `C_Container.GetContainerItemID(bag, slot)`, cross-references against a pre-built set of tracked pot itemIDs, returns `C_Item.GetItemIconByID` of first match.

**Confidence:** MEDIUM — `C_Container.GetContainerItemID` confirmed available (warcraft.wiki.gg). Bag iteration pattern (0-4, `C_Container.GetContainerNumSlots`) is established addon convention but must be validated against Midnight's API naming.

**Caution:** `C_Item.GetItemIconByID` may return nil if item is not yet cached. Must guard. Do not call this in combat or on every frame tick.

```lua
-- BuffEngine.lua — build pot item ID set once at module level
local POT_ITEM_IDS = {}  -- populated after POT_SPELLS is defined
for _, def in pairs(POT_SPELLS) do
    if def.itemID then POT_ITEM_IDS[def.itemID] = true end
end

function ns:ResolvePotIcon()
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and POT_ITEM_IDS[itemID] then
                local icon = C_Item.GetItemIconByID(itemID)
                if icon then return icon end
            end
        end
    end
    return 134400
end
```

## Data Flow

### Trinket/Pot Cast Flow

```
UNIT_SPELLCAST_SUCCEEDED (spellID)
    |
    v
Core.lua: ns:OnSpellCastSucceeded(spellID)
    |
    +-- TRINKET_SPELLS[spellID]? --> ns:StartTrinketTimer(spellID)
    |       --> ns.activeTimers["trinket"] = { icon=spellIcon, source="meta", ... }
    |       --> ns:UpdateDisplay()
    |
    +-- POT_SPELLS[spellID]?    --> ns:StartPotTimer(spellID)
            --> ns.activeTimers["pot"]     = { icon=spellIcon, source="meta", ... }
            --> ns:UpdateDisplay()
```

### At-Rest Icon Resolution Flow

```
Display.lua: UpdateDisplay() (placeholder path — no active timer)
    |
    v
slot.spellID is "trinket" or "pot" (string key)
    |
    v
ns:ResolveSuggestedSpellID(slot.spellID) --> nil  (no fixed spellID for these)
    |
    v
[NEW] ns:GetAtRestMetaIcon(slot.spellID)
    --> looks up SUGGESTED_BUFFS entry by key
    --> calls entry.getAtRestIcon()
    --> ResolveTrinketIcon() or ResolvePotIcon()
    |
    v
GetInventoryItemID / C_Container scan --> itemID --> C_Item.GetItemIconByID
    |
    v
bar.icon:SetTexture(resolvedIcon)
```

### Active Timer Icon Switch Flow

```
Cast fires --> ns.activeTimers["trinket"].icon = ns:GetSpellIcon(castSpellID)
    |
    v (display tick)
timer exists --> bar.icon:SetTexture(timer.icon)        <- active spell icon shown

    (timer expires --> GetActiveTimers removes it)
    |
    v (display tick)
no timer --> at-rest path --> GetAtRestMetaIcon()        <- equipped trinket icon shown
```

### Why Aura Cancellation Is Safe (Without Modification)

`ScanActiveTimersForCancellation` dispatches on `timer.source`. Trinket and pot timers use `source = "meta"`. Without a guard, the existing code falls through to the end of the if/elseif chain and does nothing — no cancellation occurs. However, this is fragile (relies on silent fall-through). The explicit guard below makes intent clear and prevents future breakage.

**Required modification to `ScanActiveTimersForCancellation`:**
```lua
if timer.source == "cast" then
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if aura == nil then shouldCancel = true end
elseif timer.source == "debuff" and timer.lustBuffID then
    -- existing lust check (unchanged)
elseif timer.source == "meta" then
    -- trinket/pot: no aura to check; timer runs to natural expiry
    shouldCancel = false
end
```

## Integration Points

### BuffEngine.lua — Specific Integration Locations

| Integration Point | Exact Location | Change |
|-------------------|----------------|--------|
| `TRINKET_SPELLS` table | After `SHARED_LUST_BUFFS` (line ~22) | Add new module-level constant |
| `POT_SPELLS` table | After `TRINKET_SPELLS` | Add new module-level constant |
| `POT_ITEM_IDS` set | After `POT_SPELLS` | Build lookup set for bag scan |
| `ns.SUGGESTED_BUFFS` | After lust entry (line ~50) | Append trinket and pot entries |
| `ns:OnSpellCastSucceeded` | After existing `trackedBuffs` lookup (line ~137) | Add two table-driven fan-out checks |
| `ns:ScanActiveTimersForCancellation` | In the source dispatch block (line ~350) | Add `elseif timer.source == "meta"` skip clause |
| New functions | After `ns:StartLustTimer` (line ~404) | `StartTrinketTimer`, `StartPotTimer`, `ResolveTrinketIcon`, `ResolvePotIcon`, `GetAtRestMetaIcon` |

### CDMTab.lua — Specific Integration Locations

| Integration Point | Exact Location | Change |
|-------------------|----------------|--------|
| Suggested icon texture | `RefreshTBTSections`, suggested branch (~line 721) | `cdmSpellID = suggested.getCDMSpellID()` may be nil; use `suggested.getAtRestIcon and suggested.getAtRestIcon()` as fallback for `item.Icon:SetTexture` |
| Suggested tooltip | `OnEnter` handler (~line 101), `getCDMSpellID()` path | Guard nil return: if cdmSpellID is nil, skip `SetSpellByID` and show label-only tooltip |
| `BeginDrag` ghost icon | `BeginDrag` (~line 406) | `resolved = ns:ResolveSuggestedSpellID(iconFrame.spellID)` may be nil for trinket/pot; fall back to `ns:GetAtRestMetaIcon(iconFrame.spellID)` for ghost icon |

### Display.lua — Specific Integration Locations

| Integration Point | Exact Location | Change |
|-------------------|----------------|--------|
| Bar at-rest icon | `UpdateDisplay`, bar placeholder path (~line 444) | After `ResolveSuggestedSpellID` returns nil, call `ns:GetAtRestMetaIcon(slot.spellID)` |
| Icon at-rest icon | `UpdateDisplay`, icon placeholder path (~line 601) | Same pattern |

**Concrete change (both paths follow same shape):**
```lua
-- Before (current, Display.lua ~line 444):
local resolvedID = ns:ResolveSuggestedSpellID(slot.spellID) or slot.spellID
local fallbackIcon = ns:GetSpellIcon(resolvedID)

-- After (new):
local resolvedID = ns:ResolveSuggestedSpellID(slot.spellID)
local fallbackIcon
if resolvedID then
    fallbackIcon = ns:GetSpellIcon(resolvedID)
else
    fallbackIcon = ns:GetAtRestMetaIcon(slot.spellID) or ns:GetSpellIcon(slot.spellID)
end
```

### Core.lua — No Changes Required

`UNIT_SPELLCAST_SUCCEEDED` is already registered (line 8) and routed to `ns:OnSpellCastSucceeded` (line 94). No new events needed.

## Suggested Build Order

Dependencies flow bottom-up. Data tables must exist before functions that use them; functions before UI that calls them.

| Step | File | Work | Dependency |
|------|------|------|------------|
| 1 | `BuffEngine.lua` | Add `TRINKET_SPELLS` and `POT_SPELLS` tables with season data | All other code depends on these |
| 2 | `BuffEngine.lua` | Add `StartTrinketTimer` and `StartPotTimer` (mirrors `StartLustTimer`) | Required before fan-out in `OnSpellCastSucceeded` |
| 3 | `BuffEngine.lua` | Modify `OnSpellCastSucceeded` to fan out to trinket/pot handlers | Activates live cast detection — testable now |
| 4 | `BuffEngine.lua` | Add `source = "meta"` guard in `ScanActiveTimersForCancellation` | Prevents premature cancellation for new timers |
| 5 | `BuffEngine.lua` | Add `ResolveTrinketIcon`, `ResolvePotIcon`, `GetAtRestMetaIcon` | Needed by SUGGESTED_BUFFS entries and Display.lua |
| 6 | `BuffEngine.lua` | Append trinket and pot entries to `ns.SUGGESTED_BUFFS` | Needed by CDMTab.lua Suggested section render |
| 7 | `CDMTab.lua` | Guard nil `cdmSpellID` in Suggested icon render, tooltip, and ghost drag | Prevents nil-icon and nil-spell errors |
| 8 | `Display.lua` | Update at-rest icon path (bars + icons) to call `GetAtRestMetaIcon` | Enables equipped-trinket / bag-pot icon in placeholders |
| 9 | Test | `/tbt`, drag trinket/pot to Bars, cast a tracked trinket/pot | Validates: cast detection -> timer -> icon switch -> expiry -> at-rest icon |

Steps 1-4 are the functional core and self-contained — cast detection and timer management work without UI polish. Steps 5-8 add the display polish. This ordering means the feature is testable in-game after step 4 (bar shows "trinket" key with question mark icon) and progressively improves through step 8.

## Anti-Patterns

### Anti-Pattern 1: Using `source = "cast"` for meta-slot timers

**What people do:** Reuse `source = "cast"` on trinket/pot timers to avoid touching `ScanActiveTimersForCancellation`.

**Why it's wrong:** `ScanActiveTimersForCancellation` iterates `ns.activeTimers` keyed by spellID. The timer key is the string `"trinket"`. The existing `source == "cast"` branch calls `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` where `spellID` is the timer's `spellID` field — which is `"trinket"`. Passing a string to this API returns nil. The timer is cancelled on the first `UNIT_AURA` event after it starts.

**Do this instead:** Use `source = "meta"` and add a skip clause in `ScanActiveTimersForCancellation`. Two extra lines; zero premature cancellations.

### Anti-Pattern 2: Resolving bag/equipped icons on every display tick

**What people do:** Call `ResolveTrinketIcon()` or `ResolvePotIcon()` inside the `UpdateDisplay()` 20Hz cycle.

**Why it's wrong:** `C_Container.GetContainerItemID` and `GetInventoryItemID` are not free. Bag scan loops inside a 20Hz frame loop create unnecessary CPU work, especially for pot scanning (up to ~120+ slots per scan). This directly contradicts the CLAUDE.md directive to avoid hot-path allocations and redundant per-frame work.

**Do this instead:** Call resolution only in the at-rest placeholder path, which is already gated behind the `bar.spellID ~= slot.spellID` dirty-check. Resolution runs only when the slot assignment changes, not every frame.

### Anti-Pattern 3: One DB entry per trinket/pot spell

**What people do:** Register each trinket spell as a separate `trackedBuffs` entry (like a normal tracked spell) and rely on the user to add them manually via the Add dialog.

**Why it's wrong:** Destroys the "shared slot" semantic. A full season trinket list has 10+ items; the CDM would show 10+ entries. The user would need to manually add each one.

**Do this instead:** One string key ("trinket") in `trackedBuffs` with `metaBuff = true`. TRINKET_SPELLS is the data table; the DB entry is the slot definition. Exactly how lust works.

### Anti-Pattern 4: Storing `getAtRestIcon` result in SavedVariables

**What people do:** Cache the resolved icon ID in `TerribleBuffTrackerDB` to avoid re-scanning.

**Why it's wrong:** Functions are not serializable. Cached icon IDs go stale when gear changes between sessions. SavedVariables load before `PLAYER_ENTERING_WORLD`; item APIs are not guaranteed available at that point.

**Do this instead:** Resolve icons lazily at render time. The existing `hideWhenInactive = true` default means the at-rest path only runs when CDM settings are open — frequency is negligible.

### Anti-Pattern 5: Querying `getAtRestIcon` in `ResolveSuggestedSpellID`

**What people do:** Extend `ns:ResolveSuggestedSpellID` to return a texture ID instead of a spellID when `getCDMSpellID` is nil.

**Why it's wrong:** `ResolveSuggestedSpellID` is called from tooltip handlers, display loops, and CDMTab — all of which expect a numeric spellID or nil. Returning a texture ID from a function named "ResolveSuggestedSpellID" breaks all existing callers.

**Do this instead:** Add a separate `ns:GetAtRestMetaIcon(key)` helper. Keep `ResolveSuggestedSpellID` returning spellIDs only. Separation of concerns; no existing call sites broken.

## Sources

- Existing codebase: `BuffEngine.lua`, `CDMTab.lua`, `Display.lua`, `Core.lua` (read directly — HIGH confidence)
- [GetInventoryItemID — warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_GetInventoryItemID) — confirmed available in Midnight 12.0.1 (HIGH)
- [C_Container.GetContainerItemID — warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_Container.GetContainerItemID) — confirmed available (HIGH)
- [C_Item.GetItemIconByID — warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemIconByID) — confirmed available in 12.0.1 (HIGH)
- [TrinketTracker (Midnight) — CurseForge](https://www.curseforge.com/wow/addons/trinkettracker-midnight) — confirms trinket slot 13/14 detection pattern works in Midnight (MEDIUM)
- [UNIT_SPELLCAST_SUCCEEDED — warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_SUCCEEDED) — spellID confirmed safe/never secret (HIGH)

---
*Architecture research for: TerribleBuffTracker v0.3.0 — trinket & pot meta-trackers*
*Researched: 2026-04-11*
