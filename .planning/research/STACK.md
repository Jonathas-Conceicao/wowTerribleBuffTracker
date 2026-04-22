# Technology Stack

**Project:** TerribleBuffTracker
**Sources:** Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`
**Confidence:** HIGH — all findings verified against local Blizzard source files

---

## v0.2.4 Addition: SpellProvider Abstraction — Lua OOP and Event Dispatch Patterns

**Researched:** 2026-04-18
**Scope:** Lua 5.1 idioms for class-like abstractions, polymorphic dispatch, event routing, and table pooling in a WoW addon (no external libraries).

---

### Core Pattern: Mixin-Based "Class" Construction

WoW Midnight's runtime is Lua 5.1 with Blizzard's own mixin helpers available as globals. The canonical OOP pattern in Blizzard code is the **mixin table** — a plain table of functions, instantiated with `CreateFromMixins`. This is how all CDM providers (`CooldownViewerItemMixin`, `CooldownViewerItemDataMixin`, `CooldownViewerSettingsDataProviderMixin`) are built.

Source: `CooldownViewer.lua:92` — `CooldownViewerItemMixin = CreateFromMixins(CooldownViewerItemDataMixin, CooldownViewerVisualAlertTargetMixin)` and `CooldownViewerSettingsDataProvider.lua:1` — `CooldownViewerSettingsDataProviderMixin = {}`.

#### `Mixin(target, ...)` — copy methods into an existing table

```lua
-- Built-in WoW global (C-layer, not defined in SharedXML Lua)
-- Copies all key/value pairs from each mixin table into target.
-- Returns target.
Mixin(target, MixinA, MixinB)
```

#### `CreateFromMixins(...)` — create a new table from one or more mixins

```lua
-- Built-in WoW global. Creates a new empty table, then copies all methods
-- from each mixin into it in left-to-right order (last wins on collisions).
-- Equivalent to: Mixin({}, ...)
local instance = CreateFromMixins(SpellProviderMixin)
```

**Use `CreateFromMixins` for SpellProvider instances.** Each call produces a fresh table with its own state fields — no shared state between instances.

#### `CreateAndInitFromMixin(mixin, ...)` — create + call Init in one step

```lua
-- Defined in Blizzard_SharedXMLBase/Mixin.lua
-- Creates instance via CreateFromMixins, then calls instance:Init(...)
local provider = CreateAndInitFromMixin(UserSpellProviderMixin, spellID, duration, label)
```

Use this when every provider type has an `Init(...)` constructor. The pattern is: define `SpellProviderBaseMixin` with stub methods, define `ConcreteProviderMixin` with real implementations, then construct with `CreateFromMixins(SpellProviderBaseMixin, ConcreteProviderMixin)`.

---

### SpellProvider Mixin Pattern — Copy-Paste Starting Point

```lua
-- SpellProvider base "interface" — defines the contract.
-- Concrete providers are built with CreateFromMixins(SpellProviderBaseMixin, ConcreteMixin).
local SpellProviderBaseMixin = {}

-- Returns a list of WoW event names this provider needs routed to it.
-- BuffEngine calls provider:OnTrigger(event, ...) for each listed event.
function SpellProviderBaseMixin:GetEventInterests()
    return {} -- override in concrete provider
end

-- Called by BuffEngine when a registered event fires.
-- Returns an ActiveProc table if the event triggers a proc, or nil.
-- Shape: { key=any, icon=number, duration=number, label=string, expiresAt=number, source=string }
function SpellProviderBaseMixin:OnTrigger(event, ...)
    return nil -- override in concrete provider
end

-- Returns display info for CDM tab and config (at-rest state).
-- Shape: { icon=number, label=string, duration=number, spellID=number|nil }
function SpellProviderBaseMixin:GetPreviewInfo()
    return nil -- override in concrete provider
end
```

**Why this shape:**
- `GetEventInterests()` decouples event registration from Core.lua — BuffEngine owns event routing, not each provider.
- `OnTrigger()` returning a normalized plain table means Display never branches on provider type.
- `GetPreviewInfo()` feeds both CDMTab (icon grid) and preview timer generation from a single source.

---

### Concrete Provider: UserSpellProvider

```lua
local UserSpellProviderMixin = {}

function UserSpellProviderMixin:Init(spellID, duration, label)
    self.spellID  = spellID
    self.duration = duration
    self.label    = label
end

function UserSpellProviderMixin:GetEventInterests()
    return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function UserSpellProviderMixin:OnTrigger(event, unit, _, castSpellID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return nil end
    if unit ~= "player" then return nil end
    if castSpellID ~= self.spellID then return nil end

    local now = GetTime()
    return {
        key       = self.spellID,
        icon      = ns:GetSpellIcon(self.spellID),
        duration  = self.duration,
        label     = self.label,
        expiresAt = now + self.duration,
        source    = "cast",
    }
end

function UserSpellProviderMixin:GetPreviewInfo()
    return {
        icon     = ns:GetSpellIcon(self.spellID),
        label    = self.label,
        duration = self.duration,
        spellID  = self.spellID,
    }
end

-- Construction:
-- local providerProto = CreateFromMixins(SpellProviderBaseMixin, UserSpellProviderMixin)
-- local p = CreateAndInitFromMixin(providerProto, spellID, duration, label)
```

---

### Concrete Provider: Multi-Spell Provider (Trinket / Pot)

Trinket and Pot providers watch a **set** of spell IDs, not one. The provider holds a lookup table of `spellID -> { duration, itemID }`.

```lua
local MultiSpellProviderMixin = {}

-- spellTable:   same shape as TRINKET_SPELLS / POT_SPELLS
-- metaKey:      string ("trinket" or "pot") — used as the ActiveProc key in BuffEngine
-- atRestIconFn: function() -> iconID  (called per-proc to get at-rest icon)
function MultiSpellProviderMixin:Init(spellTable, metaKey, atRestIconFn)
    self.spellTable   = spellTable
    self.metaKey      = metaKey
    self.atRestIconFn = atRestIconFn
end

function MultiSpellProviderMixin:GetEventInterests()
    return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function MultiSpellProviderMixin:OnTrigger(event, unit, _, castSpellID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return nil end
    if unit ~= "player" then return nil end

    local def = self.spellTable[castSpellID]
    if not def then return nil end

    local now       = GetTime()
    local spellInfo = C_Spell.GetSpellInfo(castSpellID)
    return {
        key         = self.metaKey,          -- BuffEngine uses this as the activeProcs table key
        icon        = ns:GetSpellIcon(castSpellID),
        atRestIcon  = self.atRestIconFn and self.atRestIconFn() or nil,
        duration    = def.duration,
        label       = (spellInfo and spellInfo.name) or self.metaKey,
        expiresAt   = now + def.duration,
        source      = "cast",
        castSpellID = castSpellID,           -- for aura cancellation check
    }
end

function MultiSpellProviderMixin:GetPreviewInfo()
    return {
        icon     = self.atRestIconFn and self.atRestIconFn() or 134400,
        label    = self.metaKey,
        duration = 0, -- sentinel; real duration comes from spellTable at cast time
    }
end
```

---

### Concrete Provider: LustProvider (Aura-Based)

Lust fires from `UNIT_AURA` addedAuras, not a cast. The provider declares `"UNIT_AURA"` in `GetEventInterests`. BuffEngine dispatches to it only after the existing secret/preview guards in `OnUnitAura` pass.

```lua
local LustProviderMixin = {}

-- debuffToLust: table of debuffSpellID -> lustSpellID  (existing SATED_DEBUFF_TO_LUST)
function LustProviderMixin:Init(debuffToLust)
    self.debuffToLust = debuffToLust
end

function LustProviderMixin:GetEventInterests()
    return { "UNIT_AURA" }
end

-- BuffEngine passes (event, unit, updateInfo) for UNIT_AURA.
-- Returns nil if no lust debuff found in addedAuras.
function LustProviderMixin:OnTrigger(event, unit, updateInfo)
    if event ~= "UNIT_AURA" then return nil end
    if unit ~= "player" then return nil end
    if not updateInfo or not updateInfo.addedAuras then return nil end

    for _, aura in ipairs(updateInfo.addedAuras) do
        if not issecretvalue(aura.spellId) then
            local lustSpellID = self.debuffToLust[aura.spellId]
            if lustSpellID then
                local now      = GetTime()
                local lustInfo = C_Spell.GetSpellInfo(lustSpellID)
                return {
                    key       = "lust",
                    icon      = ns:GetSpellIcon(lustSpellID),
                    duration  = 40,
                    label     = (lustInfo and lustInfo.name) or "Lust / Heroism",
                    expiresAt = now + 40,
                    source    = "debuff",
                    lustBuffID = lustSpellID,
                }
            end
        end
    end
    return nil
end

function LustProviderMixin:GetPreviewInfo()
    -- Reuse existing GetHunterLustSpell / CLASS_LUST_SPELL logic via a helper
    local classSpellID = ns:GetClassLustSpellID()
    return {
        icon     = ns:GetSpellIcon(classSpellID),
        label    = "Lust / Heroism",
        duration = 40,
        spellID  = classSpellID,
    }
end
```

---

### Event Dispatch: Routing by Provider Interest

BuffEngine builds a dispatch table at registration time. This avoids iterating all providers on every event — only interested providers are called for each event.

```lua
-- In BuffEngine (module-level, not persisted):
local providers       = {}   -- ordered list of all registered providers
local eventToProviders = {}  -- event string -> list of providers

-- Call once per provider during InitBuffEngine.
local function RegisterProvider(provider)
    table.insert(providers, provider)
    for _, event in ipairs(provider:GetEventInterests()) do
        if not eventToProviders[event] then
            eventToProviders[event] = {}
        end
        table.insert(eventToProviders[event], provider)
    end
end

-- Called from Core.lua OnEvent after guards (secret check, preview check) pass:
function ns:DispatchEventToProviders(event, ...)
    local interested = eventToProviders[event]
    if not interested then return end
    for _, provider in ipairs(interested) do
        local proc = provider:OnTrigger(event, ...)
        if proc then
            ns:HandleProc(proc)
        end
    end
end
```

**Why a dispatch table instead of an `if/elseif` chain:**
- O(1) lookup per event — scales to N providers without growing the dispatch chain.
- New providers register themselves; Core.lua never needs a new branch.
- Same pattern Blizzard uses in CDM's `alertsByEvent` table (`CooldownViewer.lua:453-456`).

**Core.lua integration — replace per-event branches with a single dispatch call:**

```lua
-- In Core.lua eventFrame OnEvent:
elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    ns:DispatchEventToProviders(event, unit, _, spellID)
elseif event == "UNIT_AURA" then
    local unit, updateInfo = ...
    ns:OnUnitAura(updateInfo)           -- secret/preview guards unchanged here
    ns:DispatchEventToProviders(event, unit, updateInfo)  -- runs after guards pass
```

`OnUnitAura` keeps the existing `C_Secrets.ShouldAurasBeSecret()` and `previewActive` guards. `DispatchEventToProviders` for `"UNIT_AURA"` is called inside `OnUnitAura` after those guards, not in Core.lua directly — this preserves the existing guard logic without duplication.

---

### ActiveProc Normalized Shape

The goal is zero type-specific branching in Display and CDMTab. The proc table shape is the enforcement mechanism.

**Required fields — all providers produce these, Display consumes only these:**

```lua
-- proc.key       = any        -- activeProcs table key (spellID number OR string slot key)
-- proc.icon      = number     -- texture file ID (never nil; 134400 = question mark)
-- proc.duration  = number     -- seconds
-- proc.label     = string     -- display name
-- proc.expiresAt = number     -- GetTime() + duration at cast time
-- proc.source    = string     -- "cast" | "debuff" (for cancellation routing in BuffEngine)
```

**Optional fields — BuffEngine-internal only, Display never reads these:**

```lua
-- proc.lustBuffID   = number  -- LustProvider only; cancellation check
-- proc.castSpellID  = number  -- MultiSpellProvider only; aura cancellation
-- proc.atRestIcon   = number  -- MultiSpellProvider only; icon to show after expiry
```

Display reads only `icon`, `duration`, `label`, `expiresAt`. It never reads `source`, `lustBuffID`, or `castSpellID`. This eliminates the string-key vs. numeric-key branching currently in Display.lua and the duplicated icon resolution chains across provider types.

---

### `HandleProc`: Replace-on-Reproc and Expiry Logic

BuffEngine's `HandleProc` is the single place that decides what to do when a proc arrives. Replace-on-reproc is a natural consequence of using `proc.key` as the table key:

```lua
function ns:HandleProc(proc)
    -- Replace-on-reproc: assigning to the same key overwrites the existing timer.
    -- Lust has a "don't restart if running" guard — implement that here, not in the provider.
    if proc.key == "lust" then
        local existing = ns.activeTimers["lust"]
        if existing and existing.expiresAt > GetTime() then
            return -- lust already running; ignore new trigger
        end
    end
    ns.activeTimers[proc.key] = proc
    if ns.UpdateDisplay then ns:UpdateDisplay() end
end
```

Trinket and pot do NOT have the lust guard (newest cast always wins — existing behavior).

---

### Table Pooling for ActiveProc Records

The current `wipe()` pattern in Display.lua for module-level accumulator tables (`barTimers`, `iconTimers`, etc.) is correct and must be preserved. Apply the same pattern to any new accumulator tables introduced in BuffEngine passes.

For the proc records themselves: do not pool in v0.2.4. Provider count is < 20; proc allocation frequency is bounded by player cast rate. WoW Lua GC handles small tables at this volume without measurable pressure.

**Only add a proc pool if profiling shows GC pressure.** The pattern if needed:

```lua
local procPool = {}

local function AcquireProc()
    local t = table.remove(procPool)
    if t then wipe(t) return t end
    return {}
end

local function ReleaseProc(proc)
    table.insert(procPool, proc)
end
-- Call ReleaseProc(old) before overwriting or nilling ns.activeTimers[key].
```

---

### Metatable-Based Inheritance: When to Use, When to Avoid

Blizzard code uses `CreateFromMixins` (flat copy), not `__index` metatables for inheritance. Both are valid Lua 5.1 but have different tradeoffs:

| Approach | Method lookup | Memory per instance | Risk |
|----------|-------------|---------------------|------|
| `CreateFromMixins` (flat copy) | O(1) direct key | Higher (methods copied per instance) | None — each instance owns its copy |
| `__index` metatable chain | O(1) + one indirection | Lower (methods shared in prototype) | Accidental shared state if methods mutate the prototype table |

**Use `CreateFromMixins` for SpellProvider.** Provider count is < 20. Flat copies are cheaper to reason about in WoW's restricted execution environment and match all existing Blizzard addon OOP.

**Avoid `__index` metatable chains** in this codebase unless a concrete memory budget forces it (it won't at this scale).

If metatables are needed for other purposes (e.g., read-only sentinel tables), the correct Lua 5.1 form is:

```lua
-- Read-only table via __newindex (example only — not for providers)
local function MakeReadOnly(t)
    return setmetatable({}, {
        __index    = t,
        __newindex = function(_, k, _)
            error("attempt to write to read-only table key: " .. tostring(k), 2)
        end,
    })
end
```

---

### What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| External OOP library (30log, middleclass, classic) | No external libs; WoW sandbox blocks `require` | `CreateFromMixins` (built-in WoW global) |
| `__index` metatable inheritance chains for providers | Blizzard doesn't use them; no memory benefit at < 20 instances; harder to reason about in restricted env | Flat mixin copies via `CreateFromMixins` |
| Rebuilding the dispatch table per-frame or per-event | Dispatch table is static after `InitBuffEngine`; never rebuild | Build once at init, reuse forever |
| Allocating accumulator tables inside `UpdateDisplay` hot path | Already solved with module-level + `wipe()` in Display.lua | Keep existing pattern; extend to new passes |
| Storing proc records in SavedVariables | Active procs are runtime-only; stale on reload | Runtime `activeTimers` table only |
| `COMBAT_LOG_EVENT_UNFILTERED` in any provider's `GetEventInterests` | Disabled in Midnight (CLAUDE.md) | `UNIT_SPELLCAST_SUCCEEDED` or `UNIT_AURA` |

---

### Sources (v0.2.4 Research)

All findings verified against local Blizzard source at `C:\Users\jonat\Repositories\wow-ui-source` and existing TBT source:

- `Interface/AddOns/Blizzard_SharedXMLBase/Mixin.lua` — `CreateAndInitFromMixin`, `SecureMixin` implementations; confirms `CreateFromMixins` is a C-layer global, not defined in Lua
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua:92` — `CooldownViewerItemMixin = CreateFromMixins(...)` canonical CDM provider construction pattern
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua:453-456` — `alertsByEvent[event]` dispatch table pattern (event string maps to list of handlers)
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettingsDataProvider.lua:1-28` — `CooldownViewerSettingsDataProviderMixin` as a stateful mixin with `EventRegistry` subscriptions
- `Interface/AddOns/Blizzard_SharedXML/EventUtil.lua` — `EventRegistry:RegisterFrameEventAndCallback` as Blizzard's event routing mechanism (reference pattern; TBT uses `SetScript("OnEvent")` directly)
- `TerribleBuffTracker/BuffEngine.lua` — existing `OnSpellCastSucceeded`, `OnUnitAura`, `StartLustTimer` as the baseline being refactored; `wipe()` accumulator pattern confirmed
- `TerribleBuffTracker/Core.lua` — existing `eventFrame:SetScript("OnEvent", ...)` flat dispatch chain being replaced by provider-based dispatch
- `TerribleBuffTracker/Display.lua` — module-level `barTimers`, `iconTimers` + `wipe()` pattern confirmed correct for hot-path tables

---

## v0.3.0 Addition: Trinket and Pot Meta-Tracker Icon APIs

**Researched:** 2026-04-11
**Scope:** WoW Midnight (Interface 120000+) APIs for inventory scanning, item icon resolution, and event triggers needed for trinket and pot meta-tracker slots

### Cast Detection (No Change)

`UNIT_SPELLCAST_SUCCEEDED` remains the detection mechanism for trinket and pot activation, exactly as used by existing tracked buffs. The spellID from this event is never a secret value (confirmed in CLAUDE.md and current practice). No new event registration is needed for detection.

The only change to the existing `OnSpellCastSucceeded` handler is recognizing the meta-slot keys (`"trinket"`, `"pot"`) and performing overwrite behavior instead of rejecting an existing active timer.

---

### Trinket Icon: Equipped Slot Scanning

#### `GetInventoryItemID("player", slot)` — Read equipped item ID

```lua
-- Global legacy function (not in C_ namespace)
-- Returns itemID (number) or nil if slot is empty
local itemID1 = GetInventoryItemID("player", INVSLOT_TRINKET1)  -- slot 13
local itemID2 = GetInventoryItemID("player", INVSLOT_TRINKET2)  -- slot 14
```

**Secret value risk:** None. No `SecretReturn` annotation in any API documentation. Blizzard uses this function without secret guards in `EquipmentManager.lua` (lines 82, 135, 229) and tutorial code. The `SecretAspect` enum has no inventory ID aspect.

**Why:** Allows comparing equipped item IDs against the known trinket item ID set to determine which trinket is equipped and therefore which icon to show at rest.

#### `GetInventoryItemTexture("player", slot)` — Read equipped item icon directly

```lua
-- Global legacy function (not in C_ namespace)
-- Returns fileID (number) or nil if slot is empty
local icon1 = GetInventoryItemTexture("player", INVSLOT_TRINKET1)
local icon2 = GetInventoryItemTexture("player", INVSLOT_TRINKET2)
```

**Secret value risk:** None. No `SecretReturn` annotation. Used by Blizzard's `BuffFrame.lua` line 703, `PaperDollFrame.lua`, `ContainerFrame.lua`, and `IconDataProvider.lua` without any secret guards.

**Why:** Avoids a two-step lookup (GetInventoryItemID → GetItemIconByID). When you have confirmed the item matches a known trinket, use this to get the icon in one call.

**Alternative:** `C_Item.GetItemIconByID(itemID)` — equally valid if you already have the itemID from the matching step and want to avoid a second slot API call.

#### Trinket slot constants

```lua
INVSLOT_TRINKET1  -- = 13 (defined in Constants.lua)
INVSLOT_TRINKET2  -- = 14 (defined in Constants.lua)
```

Use these named constants, not the raw numbers 13 and 14.

#### Pattern: trinket icon resolution

```lua
-- Scan both trinket slots; pick the first that matches a known trinket itemID
local function ResolveTrinketIcon(knownItemIDs)
    for _, slot in ipairs({ INVSLOT_TRINKET1, INVSLOT_TRINKET2 }) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID and knownItemIDs[itemID] then
            return GetInventoryItemTexture("player", slot)
        end
    end
    return 134400  -- question mark fallback
end
```

`knownItemIDs` is a lookup table built from the trinket item ID set (keys are itemIDs, values are truthy). This scan is O(2 × N_trinkets) at worst and only runs on icon refresh, not per-frame.

---

### Pot Icon: Bag Consumable Scanning

#### `C_Item.GetItemCount(itemID)` — Check if item is in bags

```lua
-- C_Item namespace (modern)
-- SecretArguments = "AllowedWhenUntainted" — safe for addon code
-- Returns count (number); 0 if not found
local count = C_Item.GetItemCount(itemID)
if count > 0 then
    -- pot is in bags
end
```

**Secret value risk:** None. `SecretArguments = "AllowedWhenUntainted"` means the function accepts secret values as arguments (not that it returns them). There is no `SecretReturn` annotation. Item count is not a secret aspect.

**Why:** Single-call check for bag presence. Searches all carried bags automatically. No need to iterate slots manually. Use for pot detection: iterate known pot item IDs, first one with count > 0 is the "current" pot.

#### `C_Item.GetItemIconByID(itemID)` — Get icon from item ID

```lua
-- C_Item namespace (modern)
-- SecretArguments = "AllowedWhenUntainted"
-- Returns fileID (number) or nil
local icon = C_Item.GetItemIconByID(itemID)
```

**Secret value risk:** None. No `SecretReturn` annotation. Used in `Blizzard_Contribution.lua`, `Blizzard_HousingMarketCart`, `Blizzard_ObjectAPI` without secret guards.

**Why:** Resolves item icon from a known item ID. This is the modern replacement for the deprecated global `GetItemIcon`. Do not use `GetItemIcon` — it only loads under the `loadDeprecationFallbacks` CVar (verified in `Deprecated_ItemScript.lua`).

#### Pattern: pot icon resolution

```lua
-- Try known pot item IDs in priority order; use the first one found in bags
local function ResolvePotIcon(orderedItemIDs)
    for _, itemID in ipairs(orderedItemIDs) do
        if C_Item.GetItemCount(itemID) > 0 then
            return C_Item.GetItemIconByID(itemID)
        end
    end
    return 134400  -- question mark fallback
end
```

`orderedItemIDs` is an ordered list of pot item IDs to check. Priority order is arbitrary (all are damage pots); any consistent ordering works.

---

### Spell Icon for Active Timer

No new API needed. The existing `ns:GetSpellIcon(spellID)` via `C_Spell.GetSpellInfo(spellID).iconID` is the correct method for resolving the cast spell's icon when a timer becomes active. This is already validated.

Store the resolved icon in the timer table at cast time (same pattern as all other timers). When the timer expires and is removed, the meta-slot display reverts to the at-rest icon (resolved via the inventory/bag scan above, cached on the SUGGESTED_BUFFS entry or a parallel table).

---

### Icon Refresh: Event Triggers

Two events are needed to keep at-rest icons current without per-frame scanning.

#### `PLAYER_EQUIPMENT_CHANGED` — Trinket slot changed

```lua
-- Fires when player equips or unequips any gear
-- Payload: equipmentSlot (number), hasCurrent (bool)
-- Source: PaperDollInfoDocumentation.lua
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

-- In handler:
elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    local slot, hasCurrent = ...
    if slot == INVSLOT_TRINKET1 or slot == INVSLOT_TRINKET2 then
        ns:RefreshTrinketIcon()
    end
```

Filter on trinket slots specifically. `hasCurrent` indicates whether the slot now has an item (true) or was unequipped (false). On false, the icon should revert to the question mark.

#### `BAG_UPDATE_DELAYED` — Bags settled after update

```lua
-- Fires once after all bag slot changes complete (debounced)
-- No payload
-- Preferred over BAG_UPDATE which fires per-slot
frame:RegisterEvent("BAG_UPDATE_DELAYED")

-- In handler:
elseif event == "BAG_UPDATE_DELAYED" then
    ns:RefreshPotIcon()
```

Use `BAG_UPDATE_DELAYED` rather than `BAG_UPDATE`. `BAG_UPDATE` fires per bag per slot change; `BAG_UPDATE_DELAYED` fires once after all changes settle. This prevents scanning bags multiple times during a single loot or vendor transaction.

#### Combat gate for icon scans

Equipment and bag scanning should not run in combat. These are initialization-time operations. Gate behind `InCombatLockdown()` and defer to `PLAYER_REGEN_ENABLED`:

```lua
local function RefreshTrinketIconSafe()
    if InCombatLockdown() then
        ns.pendingTrinketIconRefresh = true
        return
    end
    -- ... do scan
end

-- In PLAYER_REGEN_ENABLED handler (already registered):
if ns.pendingTrinketIconRefresh then
    ns.pendingTrinketIconRefresh = false
    RefreshTrinketIconSafe()
end
```

Initial scan runs on `PLAYER_ENTERING_WORLD` (after display init). Trinket refresh runs on `PLAYER_EQUIPMENT_CHANGED` filtered to slots 13/14. Pot refresh runs on `BAG_UPDATE_DELAYED`.

---

### Overwrite Behavior (Newest Cast Wins)

The meta-slot key (`"trinket"` or `"pot"`) is the `activeTimers` table key. Assigning a new timer entry to the same key naturally overwrites the previous. This is the same mechanism used by the `"lust"` slot.

Critical difference from lust: the lust handler has an early-return guard ("don't restart if already running"). Trinket and pot meta-slots must NOT have this guard — always overwrite on any new cast, regardless of whether a timer is running.

```lua
-- In OnSpellCastSucceeded, after detecting a trinket/pot spell:
ns.activeTimers["trinket"] = {
    spellID = "trinket",
    expiresAt = now + duration,
    startedAt = now,
    duration = duration,
    icon = ns:GetSpellIcon(castSpellID),  -- active icon = spell icon
    label = entry.label or "Trinket",
    section = entry.section or "bars",
    source = "cast",
    castSpellID = castSpellID,            -- store for revert logic
}
```

When the timer expires, the display layer reverts the icon to the cached at-rest icon (stored in the SUGGESTED_BUFFS definition or a ns-level cache). The timer entry does not need to store the at-rest icon — the display reads it from the meta-slot config.

---

### Cancellation via UNIT_AURA

Trinket and pot buffs are likely contextually secret in M+ (same restrictions as other tracked buffs). The existing `ScanActiveTimersForCancellation` guards behind `C_Secrets.ShouldAurasBeSecret()`. Trinket and pot meta-slot timers should use `source = "cast"` — this routes them through the existing cast-source cancellation path which calls `C_UnitAuras.GetPlayerAuraBySpellID(spellID)`.

The spellID stored in the active timer must be the castSpellID (e.g., 1259633 for Light Company Guidon), not the string key `"trinket"`. The meta-slot uses a string key, but the cancellation check needs a numeric spellID. Store the numeric castSpellID inside the timer table for this purpose, and branch in cancellation:

```lua
-- In ScanActiveTimersForCancellation, for meta-slot timers:
if timer.source == "cast" and type(spellID) == "string" then
    -- meta-slot: check castSpellID stored in timer
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(timer.castSpellID)
    if aura == nil then shouldCancel = true end
end
```

---

### APIs NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Global `GetItemIcon(itemID)` | Deprecated alias; only loaded under `loadDeprecationFallbacks` CVar (verified in Deprecated_ItemScript.lua) | `C_Item.GetItemIconByID(itemID)` |
| Global `GetItemInfoInstant(itemID)` | Also deprecated alias (same file) | `C_Item.GetItemInfoInstant(itemID)` (or just `C_Item.GetItemIconByID` if only icon needed) |
| `C_UnitAuras.GetPlayerAuraBySpellID` to detect trinket/pot activation | Buff spellIDs are contextually secret in M+; returns nil when aura is secret, indistinguishable from "buff ended" | `UNIT_SPELLCAST_SUCCEEDED` for activation detection |
| `C_Item.GetItemCooldown` to infer trinket activation | Has `SecretArguments = "AllowedWhenUntainted"` and may return secret values in restricted contexts; also doesn't tell you WHICH spell was cast | `UNIT_SPELLCAST_SUCCEEDED` |
| `BAG_UPDATE` for pot icon refresh | Fires per-slot per-bag during a transaction; multiple redundant scans | `BAG_UPDATE_DELAYED` (fires once after all changes settle) |
| Scanning bank bags (BagIndex -2, 6+) | Bank only accessible at bank; `GetContainerNumSlots` returns 0 when closed | Only scan bags 0–4 (backpack + equipped bags) |
| Per-frame icon resolution | Icon only changes on equipment swap or bag change; per-frame wastes CPU | Cache resolved icon; refresh on events only |

---

### Sources (v0.3.0 Research)

All findings verified against `C:\Users\jonat\Repositories\wow-ui-source`:

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua` — C_Container functions with SecretArguments annotations; ContainerItemInfo struct (iconFileID field confirmed); BagUpdate/BagUpdateDelayed events
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua` — C_Item.GetItemIconByID (SecretArguments=AllowedWhenUntainted, no SecretReturn); C_Item.GetItemCount; C_Item.GetItemInfoInstant; C_Item.GetItemSpell
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua` — PLAYER_EQUIPMENT_CHANGED event payload (equipmentSlot: number, hasCurrent: bool)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua` — Complete C_Secrets function list; no item/inventory predicates exist; confirms item APIs are not subject to aura-style restriction
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretAspectConstantsDocumentation.lua` — Full SecretAspect enum; no inventory ID or item icon aspect; confirms these are not secret
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua` — BagIndex enum: Backpack=0, Bag_1=1, Bag_2=2, Bag_3=3, Bag_4=4
- `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua` lines 165-166 — INVSLOT_TRINKET1=13, INVSLOT_TRINKET2=14
- `Interface/AddOns/Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua` — Confirms GetItemIcon=C_Item.GetItemIconByID and GetItemInfoInstant=C_Item.GetItemInfoInstant are deprecated; only loaded under loadDeprecationFallbacks CVar
- `Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua` line 703 — GetInventoryItemTexture used in production code without secret guard
- `Interface/AddOns/Blizzard_FrameXML/EquipmentManager.lua` lines 82, 135, 229 — GetInventoryItemID used in production code without secret guard
- `Interface/AddOns/Blizzard_FrameXMLBase/Mainline/IconDataProvider.lua` line 122 — GetInventoryItemTexture used in production code without secret guard
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua` — Confirms Cooldown is a separate SecretAspect; item icon is not in this category

---

## v0.2.1 Addition: Aura-Based Timer Cancellation APIs

**Researched:** 2026-04-03
**Scope:** WoW Midnight (Interface 120000+) APIs for UNIT_AURA event handling, aura scanning, and secret value detection

### The Key Event: UNIT_AURA

**Event name (literal):** `UNIT_AURA`
**Registration:** `frame:RegisterUnitEvent("UNIT_AURA", "player")` — unit-scoped registration restricts delivery to the specified unit token only. Do NOT use `RegisterEvent("UNIT_AURA")`, which fires for all units (target, nameplate targets, etc.) and generates unnecessary traffic.

**Payload:**
```lua
-- arg1: unitTarget (string) — the unit token that changed, e.g. "player"
-- arg2: updateInfo (UnitAuraUpdateInfo table)
local unit, updateInfo = ...
```

**UnitAuraUpdateInfo structure** (from `UnitConstantsDocumentation.lua`):
```lua
updateInfo = {
  isFullUpdate            = false, -- bool, always present (default false)
  removedAuraInstanceIDs  = { },   -- table<number> or nil; NeverSecretContents = true (ALWAYS SAFE)
  addedAuras              = { },   -- table<AuraData> or nil; ConditionalSecretContents = true (MAY BE SECRET)
  updatedAuraInstanceIDs  = { },   -- table<number> or nil; NeverSecretContents = true (ALWAYS SAFE)
}
```

Critical distinction: `removedAuraInstanceIDs` is tagged `NeverSecretContents` — instance IDs are always readable. `addedAuras` contents are `ConditionalSecretContents` — individual AuraData fields may be secret values when aura data is restricted.

When `isFullUpdate = true`, the incremental lists are unreliable; do a full re-scan of all active timers instead. This fires on zone transitions, loading screens, and similar wholesale state changes.

---

### AuraData Field Reference

`AuraData` is a Lua table returned by all C_UnitAuras lookup functions. Key fields confirmed in Blizzard source (`AuraUtil.lua`, `CooldownViewerItemData.lua`, `CooldownViewer.lua`):

```lua
auraData = {
  auraInstanceID          = number, -- unique instance for this aura application (safe to read)
  spellId                 = number, -- spell ID (may be secret when auras restricted)
  name                    = string, -- localized spell name (may be secret)
  icon                    = number, -- texture ID (may be secret)
  applications            = number, -- stack count (may be secret)
  duration                = number, -- total duration in seconds (may be secret)
  expirationTime          = number, -- GetTime() value when aura expires (may be secret)
  sourceUnit              = string, -- unit token of caster (may be secret)
  isHelpful               = bool,   -- buff flag
  isHarmful               = bool,   -- debuff flag
  isFromPlayerOrPlayerPet = bool,
  canApplyAura            = bool,
  isBossAura              = bool,
}
```

Note: Field name is `spellId` (lowercase 'd'), not `spellID`. This is confirmed throughout `CooldownViewerItemData.lua` and `CooldownViewer.lua`. This is different from the `spellID` convention used elsewhere in WoW APIs.

---

### Primary Lookup APIs

#### C_UnitAuras.GetPlayerAuraBySpellID(spellID) — RECOMMENDED for TBT

```lua
-- Returns AuraData or nil
-- SecretWhenUnitAuraRestricted = true
-- RequiresNonSecretAura = true  <- returns nil if the aura is a secret value
local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
if aura then
  -- buff is present and not a secret
end
```

Most direct API for TBT's use case. Checks a specific spell by ID on the player. Returns `nil` if the aura is absent OR if the aura exists but is a secret value. This ambiguity is why secret detection must gate the scan — see "Secret Value Detection" below.

This is exactly how CDM's `CooldownViewerItemData:FindLinkedSpellForCurrentAuras()` operates.

#### C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)

```lua
-- Returns first matching AuraData or nil
-- SecretWhenUnitAuraRestricted = true
-- RequiresNonSecretAura = true
local aura = C_UnitAuras.GetUnitAuraBySpellID("player", spellID)
```

More general form of the above. Same secret behavior. Useful if TBT ever needs to scan a non-player unit.

#### C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)

```lua
-- Returns AuraData or nil
-- SecretWhenUnitAuraRestricted = true
-- SecretArguments = "AllowedWhenUntainted"
local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)
```

Useful if you have stored a `auraInstanceID` from a previous `addedAuras` event and want to verify the aura is still present. Requires tracking instance IDs per-timer.

#### AuraUtil.ForEachAura(unit, filter, batchSize, func, usePackedAura)

```lua
-- Iterates all auras matching filter; calls func(auraData) per aura
-- batchSize: max slots per batch (nil = unlimited)
-- usePackedAura: true = func receives AuraData table (use this)
AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
  -- aura.spellId, aura.auraInstanceID, etc.
  return true -- return true to stop early
end, true)
```

Full-scan approach. Works for `isFullUpdate` recovery. Subject to the same secret restrictions as the underlying slot APIs. For TBT's targeted cancellation, `GetPlayerAuraBySpellID` per tracked buff is cheaper than a full enumeration.

---

### Secret Value Detection

#### The Core Problem

When "auras are secret" (competitive/combat PvP contexts), `GetPlayerAuraBySpellID` returns `nil` even when the buff is active. This is indistinguishable from "buff ended" without an explicit secret check. Cancelling a timer on a false `nil` is incorrect behavior.

#### C_Secrets.ShouldAurasBeSecret() — RECOMMENDED GATE CHECK

```lua
-- Returns true if aura queries will generally produce secret values
-- No arguments, no SecretArguments restriction
if C_Secrets.ShouldAurasBeSecret() then
  -- set blocked flag, skip aura scan entirely
  ns.auraCheckBlocked = true
  return
end
```

This is the authoritative, zero-cost up-front check. Call it before attempting any aura scan in the `UNIT_AURA` handler. Source: `SecretPredicateAPIDocumentation.lua` — "Returns true if queries for aura data will generally produce secret values."

This is the correct mechanism for the "blocked flag" requirement in TBT's PROJECT.md.

#### issecretvalue(value) — Per-Value Fallback

```lua
-- Global Lua function, not namespaced
-- Returns true if the given value is a secret value type
if issecretvalue(aura.spellId) then
  -- this specific value is hidden; treat as inconclusive
end
```

Operates on individual values after a scan has run. Documented in `FrameScriptDocumentation.lua`. Used throughout Blizzard's restricted infrastructure code (`RestrictedInfrastructure.lua`, `Dump.lua`, etc.). Useful as a belt-and-suspenders guard inside a scan loop if `ShouldAurasBeSecret()` ever lags, but `ShouldAurasBeSecret()` is the right global gate.

#### C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID) — Granular Check

```lua
local isSecret = C_Secrets.ShouldUnitAuraInstanceBeSecret("player", auraInstanceID)
```

Per-instance granularity. Requires a known `auraInstanceID`. Less relevant for TBT since we scan by `spellId`.

#### When Secrets Are Active

`C_Secrets.ShouldAurasBeSecret()` returns `true` primarily in rated competitive PvP (arenas, rated battlegrounds). Blizzard's AuraUtil explicitly clears its caches on `PLAYER_REGEN_ENABLED` (leaving combat), confirming that combat exit is the primary state transition point.

The blocked flag in TBT should clear on:
- `PLAYER_REGEN_ENABLED` — left combat
- `ZONE_CHANGED_NEW_AREA` — zone transition resets secrecy context
- `PLAYER_ENTERING_WORLD` — login/reload/loading screen

---

### State Reset Events

#### PLAYER_REGEN_ENABLED

```lua
-- Fires when the player leaves combat (regeneration re-enabled)
-- No payload arguments
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
```

Blizzard's AuraUtil uses this exact event to dump visualization caches. For TBT: clear `ns.auraCheckBlocked` so the next `UNIT_AURA` can scan.

#### ZONE_CHANGED_NEW_AREA

```lua
-- Fires when the player transitions to a new zone
-- No payload arguments
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
```

Clears blocked flag. After a zone change, secrecy context may be different (e.g. leaving arena). A `UNIT_AURA` with `isFullUpdate = true` typically fires shortly after zone transitions, which naturally triggers a full rescan.

#### PLAYER_ENTERING_WORLD

```lua
-- Fires on login, reload, loading screen completion
-- Payload: isInitialLogin (bool), isReloadingUi (bool) — not needed for this use case
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
```

Full state reset. Followed by `UNIT_AURA` with `isFullUpdate = true`.

---

### Event Registration Pattern

Follow the existing TBT registration style in `Core.lua`:

```lua
-- Add to the event registration block in Core.lua:
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Add to the OnEvent dispatch:
elseif event == "UNIT_AURA" then
  ns:OnUnitAura(...)
elseif event == "PLAYER_REGEN_ENABLED" then
  ns:OnRegenEnabled()
elseif event == "ZONE_CHANGED_NEW_AREA" then
  ns:OnZoneChanged()
```

---

### AuraFilters Reference

String constants from `AuraUtil.AuraFilters` (pass as string literals):

| Filter | Meaning |
|--------|---------|
| `"HELPFUL"` | Buffs only |
| `"HARMFUL"` | Debuffs only |
| `"PLAYER"` | Cast by the player |
| `"HELPFUL\|PLAYER"` | Player-cast buffs only |
| `"CANCELABLE"` | Buffs the player can cancel |

For TBT scanning the player's own tracked buffs: `"HELPFUL"` covers all player buffs regardless of caster. Use `"HELPFUL|PLAYER"` if TBT only wants to cancel timers for self-cast buffs (which is the typical TBT use case — you cast the spell, it starts a timer, you want to cancel when it ends).

---

### What NOT to Use

| API | Reason |
|-----|--------|
| `UnitBuff(unit, index)` | Deprecated pre-Midnight; replaced by C_UnitAuras APIs |
| `UnitDebuff(unit, index)` | Same — deprecated |
| `UnitAura(unit, index, filter)` | Deprecated; use `C_UnitAuras.GetAuraDataByIndex` |
| `C_UnitAuras.GetUnitAuras(unit, filter)` | Returns bulk table with `ConditionalSecretContents`; harder to reason about per-entry than querying each tracked spell directly |
| `addedAuras` as cancellation signal | For cancelling timers, read `removedAuraInstanceIDs` (always safe) or use full-scan via `GetPlayerAuraBySpellID`. Never use `addedAuras` for removal logic |
| `COMBAT_LOG_EVENT_UNFILTERED` | Disabled in Midnight (CLAUDE.md constraint) |
| `RegisterEvent("UNIT_AURA")` without unit filter | Fires for all units; use `RegisterUnitEvent("UNIT_AURA", "player")` |

---

### Recommended Flow for BuffEngine.lua

```lua
-- ns.auraCheckBlocked = false  (initialized in Core.lua namespace)

function ns:OnUnitAura(unit, updateInfo)
  -- Step 1: Check if aura data is restricted
  if C_Secrets.ShouldAurasBeSecret() then
    ns.auraCheckBlocked = true
    return  -- do not cancel any timers; data is unreliable
  end

  -- Step 2: Full update — rescan everything
  if updateInfo and updateInfo.isFullUpdate then
    ns:ScanAndCancelStaleTimers()
    return
  end

  -- Step 3: Incremental update — check for removals
  if updateInfo and updateInfo.removedAuraInstanceIDs then
    -- removedAuraInstanceIDs is NeverSecretContents, always safe
    -- If TBT stores auraInstanceID per timer, cancel directly here
    -- Otherwise, a full scan is the safe fallback
    ns:ScanAndCancelStaleTimers()
  end
end

function ns:ScanAndCancelStaleTimers()
  for spellID, _ in pairs(ns.activeTimers) do
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if aura == nil then
      ns.activeTimers[spellID] = nil
    end
  end
  if ns.UpdateDisplay then
    ns:UpdateDisplay()
  end
end

function ns:OnRegenEnabled()
  ns.auraCheckBlocked = false
end

function ns:OnZoneChanged()
  ns.auraCheckBlocked = false
end
```

The `ScanAndCancelStaleTimers` approach is safe even on full updates because it queries each tracked spell specifically rather than relying on incremental diff data.

---

### Sources (v0.2.1 Research)

All findings verified against `C:\Users\jonat\Repositories\wow-ui-source`:

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua` — C_UnitAuras function signatures, SecretWhenUnitAuraRestricted flags, RequiresNonSecretAura flags
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitConstantsDocumentation.lua` — UnitAuraUpdateInfo struct (isFullUpdate, removedAuraInstanceIDs, addedAuras, updatedAuraInstanceIDs field definitions and secret tags)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua` — C_Secrets namespace, ShouldAurasBeSecret signature and documentation string
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua` — issecretvalue global function signature
- `Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua` — AuraUtil.ForEachAura implementation, AuraUtil.AuraFilters, PLAYER_REGEN_ENABLED cache dump pattern
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` — RegisterUnitEvent("UNIT_AURA", "player", "target"), OnUnitAura handler pattern, removedAuraInstanceIDs/addedAuras access pattern
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua` — GetPlayerAuraBySpellID usage, aura.spellId field name (lowercase 'd' confirmed)
- `Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua` — RegisterUnitEvent("UNIT_AURA", "player") registration pattern, updateInfo field access
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` — PLAYER_REGEN_ENABLED event (no payload)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua` — ZONE_CHANGED_NEW_AREA event (no payload)

---

## v0.2.0 Stack: CDM Tab Integration, Edit Mode, Drag-and-Drop

**Researched:** 2026-03-28
**Confidence:** HIGH (all findings verified directly from Blizzard UI source)

### Core Technologies

| Technology | Version/Source | Purpose | Why Recommended |
|------------|---------------|---------|-----------------|
| WoW Lua Frame API | Interface 120000 | All UI frames, event handling | Native; no alternative |
| `CooldownViewerSettingsTabTemplate` | `CooldownViewerSettings.xml:140` | TBT lateral tab button on the CDM window | Inherits `LargeSideTabButtonTemplate` with `parentArray="TabButtons"` — CDM's tab system iterates `self.TabButtons` so any frame with that parentArray and a `displayMode` KeyValue is picked up by `SetupTabs()` |
| `SidePanelTabButtonMixin` | `SharedUIPanelTemplates.lua:295` | Tab button behavior (SetChecked, tooltips, icon atlas) | CDM tab template uses this mixin; `SetChecked(bool)` swaps `activeAtlas`/`inactiveAtlas` and shows/hides `SelectedTexture`; tab click handled via `SetCustomOnMouseUpHandler` |
| `EventRegistry` | Blizzard global | CDM lifecycle hooks, reorder events | CDM fires `CooldownViewerSettings.OnShow`, `CooldownViewerSettings.OnHide`, and `CooldownViewerSettings.OnDataChanged` — the canonical hook points for a third-party tab to attach/detach its panel |
| `GridLayoutFrame` | `LayoutFrame.xml` / `GridLayoutUtil.lua` | Category item grid layout | CDM uses `GridLayoutFrame` with `childXPadding`, `childYPadding`, `stride`, `isHorizontal`, `layoutFramesGoingRight`, `layoutFramesGoingUp`, `alwaysUpdateLayout` as KeyValues — this is how icon grids and bar lists auto-layout |
| `ResizeLayoutFrame` | `LayoutFrame.xml` | Auto-sizing category container | CDM category template (`CooldownViewerSettingsCategoryTemplate`) inherits `ResizeLayoutFrame`; TBT sections should do the same so height adjusts as items are added/removed |
| `CreateFramePool` | WoW Frame API | Item pool for drag-drop grid cells | CDM category uses `CreateFramePool("Frame", self.Container, itemTemplate)` with `itemPool:Acquire()` / `itemPool:ReleaseAll()` — this is the pattern for pooling draggable buff icons |
| `StartMoving` / `StopMovingOrSizing` | WoW Frame API | TBT movable containers (bars + buffs) | Third-party addons cannot register with `Enum.EditModeSystem` (requires a server-side enum entry). The standard pattern is: `EventRegistry:RegisterCallback("EditMode.Enter", ...)` to show drag handles and `EventRegistry:RegisterCallback("EditMode.Exit", ...)` to persist positions in SavedVariables |
| `GLOBAL_MOUSE_UP` | WoW event | Drag-drop commit / cancel | CDM uses `self:RegisterEvent("GLOBAL_MOUSE_UP")` and `self:UnregisterEvent("GLOBAL_MOUSE_UP")` bracketed around a drag session; LeftButton = commit, RightButton = cancel |
| `GetScaledCursorPositionForFrame` | WoW API | Cursor position during drag | CDM uses this in `CooldownViewerSettingsDraggedItemMixin:OnUpdate()` to follow the cursor correctly across scale changes |
| `GetAppropriateTopLevelParent` | Blizzard global | Parent for drag cursor phantom | CDM creates the drag-following ghost frame with `CreateFrame("Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")` |
| `MenuUtil.CreateContextMenu` | Blizzard SharedXML | Right-click context menu | CDM uses `MenuUtil.CreateContextMenu(self, function(owner, rootDescription) ... end)` for per-item context menus — the correct Midnight pattern replacing old `UIDropDownMenu` |
| `ScrollFrameTemplate` | Blizzard SharedXML | Scrollable category list | CDM uses `ScrollFrameTemplate` with `scrollBarHideIfUnscrollable=false`; TBT should use the same for the buff list in the settings panel |

### Supporting APIs

| API | Source | Purpose | When to Use |
|-----|--------|---------|-------------|
| `CreateAnchor` | `LayoutFrame.lua` | Layout-frame anchor helper | Used inside `GridLayoutFrame` children to chain SetPoint calls cleanly |
| `RegionUtil.GetSides` | Blizzard SharedXML | Get left/right/bottom/top of a region | CDM uses this in nearest-item hit-testing during drag; needed for drop-zone targeting |
| `AnchorUtil.CreateAnchor` | Blizzard SharedXML | Edit Mode settings dialog anchor | `EditModeSystemMixin:SetupSettingsDialogAnchor` uses this; not needed by TBT but documents where anchor helpers live |
| `StaticPopup_Show` | WoW global | "Add Buff" spell ID/duration dialog | CDM uses `StaticPopup_Show` for confirmation dialogs; for the Add button in Suggested section this is simpler than a custom dialog frame |
| `ListHeaderThreeSliceTemplate` | Blizzard SharedXML | Category header bar | CDM category uses this as `parentKey="Header"` — provides the collapse arrow, title text, and click registration |
| `GetCursorPosition` | WoW API | Cursor hit-testing during drag | CDM uses this in `UpdateReorderMarker`; divide by `GetAppropriateTopLevelParent():GetScale()` before comparing to frame coords |
| `PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)` | WoW API | Drag start audio feedback | CDM plays this in `OnDragStart`; also `SOUNDKIT.UI_CURSOR_DROP_OBJECT` on release |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `stylua` | Lua formatter | Run after every file edit; configured in `.stylua.toml` |
| `scripts/install.bat` | Deploy to WoW | Run after changes to test in-game |
| WoW UI source (`wow-ui-source`) | Pattern reference | Always consult before implementing any CDM or Edit Mode integration |

---

### Integration Patterns

#### CDM Tab Integration

**How CDM's tab system works** (verified from `CooldownViewerSettings.xml` and `CooldownViewerSettings.lua`):

1. The CDM settings frame XML defines tabs as `parentArray="TabButtons"` — Lua sees them as `self.TabButtons[1]`, `self.TabButtons[2]`, etc.
2. `SetupTabs()` iterates `self.TabButtons` and calls `tabButton:SetCustomOnMouseUpHandler(TabHandler)`.
3. `TabHandler` calls `self:SetDisplayMode(tab.displayMode)` on click.
4. `SetDisplayMode(mode)` calls `SetChecked()` on each tab and `SetCurrentCategories()` with the category list for that mode.

**TBT cannot reuse CDM's `displayMode` routing** because `displayModeToCategories` is a local table. TBT must inject a tab button into `CooldownViewerSettings.TabButtons` after the frame exists, then listen to `CooldownViewerSettings.OnShow` to show/hide its own panel frame parented to `CooldownViewerSettings`.

**Recommended tab injection approach:**

```lua
-- After CooldownViewerSettings is loaded (use EventUtil.ContinueAfterAllEvents
-- with "VARIABLES_LOADED" and "PLAYER_ENTERING_WORLD"):
local tbtTab = CreateFrame("Frame", "TBTSettingsTab",
    CooldownViewerSettings, "CooldownViewerSettingsTabTemplate")
tbtTab.displayMode = "tbt_buffs"
tbtTab.activeAtlas = "icon_trackedbuffs"
tbtTab.inactiveAtlas = "icon_trackedbuffs"
tbtTab.tooltipText = "TBT Buffs"
-- Anchor below last existing tab
local lastTab = CooldownViewerSettings.TabButtons[#CooldownViewerSettings.TabButtons]
tbtTab:SetPoint("TOP", lastTab, "BOTTOM", 0, -3)
table.insert(CooldownViewerSettings.TabButtons, tbtTab)
```

#### Drag-and-Drop within TBT Settings Panel

CDM implements drag as a **manual drag-follow pattern**, not WoW's native pickup/cursor system:

1. `OnDragStart` or `OnMouseUp(LeftButton)` — call `BeginOrderChange(item)` on the settings frame.
2. `BeginOrderChange` creates a ghost frame parented to `GetAppropriateTopLevelParent()`, sets an `OnUpdate` on the main settings frame to reposition it each frame.
3. Ghost frame's `OnUpdate` calls `GetScaledCursorPositionForFrame(topLevel)` and `SetPoint("TOPLEFT", ...)`.
4. Main settings frame registers `GLOBAL_MOUSE_UP`. On `LeftButton` up: commits move. On `RightButton` up: cancels.

#### Edit Mode — Movable Containers

**Third-party addons cannot register with `Enum.EditModeSystem`** (verified: all `EditModeSystemTemplate` instances require a `system` KeyValue pointing to a server-backed enum entry).

**What third-party addons CAN do:**

```lua
EventRegistry:RegisterCallback("EditMode.Enter", function()
    tbtBarsHandle:Show()
    tbtBuffsHandle:Show()
end, addonKey)

EventRegistry:RegisterCallback("EditMode.Exit", function()
    tbtBarsHandle:Hide()
    tbtBuffsHandle:Hide()
    ns.db.barsAnchor = { GetPoint(tbtBarsContainer) }
    ns.db.buffsAnchor = { GetPoint(tbtBuffsContainer) }
end, addonKey)
```

---

### What NOT to Use (v0.2.0)

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `UIDropDownMenu` / `UIDropDownMenuTemplate` | Deprecated since Dragonflight; non-functional in Midnight | `MenuUtil.CreateContextMenu` |
| `EditModeManagerFrame:RegisterSystemFrame(self)` | Requires valid `Enum.EditModeSystem` entry | `EventRegistry:RegisterCallback("EditMode.Enter/Exit")` + manual `StartMoving()` |
| `COMBAT_LOG_EVENT_UNFILTERED` | Disabled in Midnight | `UNIT_SPELLCAST_SUCCEEDED` (already used by TBT) |
| Storing active timer state in SavedVariables | Active timers are runtime-only; stale on reload | Runtime tables only |
| Hooking `CooldownViewerSettings:SetDisplayMode` | Replaces function globally | `hooksecurefunc` or `EventRegistry` callbacks |

---

### Sources (v0.2.0 Research)

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.lua`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.lua`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.lua`
