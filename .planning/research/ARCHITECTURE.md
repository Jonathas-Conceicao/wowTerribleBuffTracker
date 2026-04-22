# Architecture Research

**Domain:** WoW Midnight addon — SpellProvider/ActiveProc refactor (v0.2.4)
**Researched:** 2026-04-18
**Confidence:** HIGH (read directly from codebase; no external APIs involved)

## Standard Architecture

### System Overview — Before (v0.2.3)

```
Core.lua
  UNIT_SPELLCAST_SUCCEEDED  ──────────────────────────────────────────┐
  UNIT_AURA                 ──────────────────────────────────────┐   │
                                                                   │   │
BuffEngine.lua                                                     │   │
  ns.activeTimers (keyed by spellID or "lust"/"trinket"/"pot")    │   │
  OnSpellCastSucceeded()        ◄────────────────────────────────────┘
    ├── TRINKET_SPELLS[id]?  ──► trinket branch (numeric key, metaSlot)
    ├── POT_SPELLS[id]?      ──► pot branch     (numeric key, metaSlot)
    └── trackedBuffs[id]?    ──► user-spell branch (numeric key, no metaSlot)
  OnUnitAura()                  ◄──────────────────────────────────┘
    ├── SATED_DEBUFF_TO_LUST?  ──► StartLustTimer() (string key "lust")
    └── ScanActiveTimersForCancellation()
  StartAllPreviewTimers()  — divergent icon/label resolution for string vs numeric keys
  GetAtRestMetaInfo()      — trinket/pot only
  ResolveSuggestedSpellID() — lust only

Display.lua
  UpdateDisplay()  20Hz OnUpdate
    ├── active timer?  timer.icon (numeric or string key, metaSlot alias)
    └── placeholder?
          ├── GetSuggestedAtRestIcon()  ──► trinket/pot path
          └── ResolveSuggestedSpellID() ──► lust path
  tooltip: two parallel codepaths (bar OnEnter / icon OnEnter) — duplicated

CDMTab.lua
  RefreshTBTSections()
    ├── suggested section: getCDMSpellID() or getCDMIcon() dispatch
    └── user sections: string-key check → GetAtRestMetaIcon / ResolveSuggestedSpellID
  BeginDrag ghost: string-key check → GetAtRestMetaIcon / ResolveSuggestedSpellID
  tooltip OnEnter: string-key check → metaInfo / ResolveSuggestedSpellID / label-only
```

**Problem summary:** Three branches in `OnSpellCastSucceeded`, icon resolution logic duplicated 6+ times across three files, `StartAllPreviewTimers` has its own special-cased loop, timer shape has optional fields (`metaSlot`, `lustBuffID`, `source`) that create implicit contracts only some consumers respect.

---

### System Overview — After (v0.2.4 target)

```
Core.lua  (unchanged event routing)
  UNIT_SPELLCAST_SUCCEEDED  ──► BuffEngine: ns:OnSpellCastSucceeded(spellID)
  UNIT_AURA                 ──► BuffEngine: ns:OnUnitAura(updateInfo)

Providers.lua  (NEW FILE)
  ns.providers = { UserSpellProvider, TrinketProvider, PotProvider, LustProvider }
  Each provider implements:
    provider.events[]          — which WoW events it cares about
    provider:OnTrigger(event, payload) → ActiveProc or nil
    provider:GetPreviewProcs() → list of ActiveProc (one per enabled DB slot)
    provider:GetPreviewInfo(key) → { icon, label, duration } for CDM at-rest rendering

ActiveProc shape (plain table, uniform across all providers):
  {
    key       = string|number,   -- unique display slot (DB key or "trinket"/"pot")
    icon      = number,          -- texture ID, always resolved by provider
    label     = string,          -- display name, always resolved by provider
    duration  = number,
    expiresAt = number,          -- GetTime() + duration
    startedAt = number,
    section   = string,          -- "bars" | "buffs"
    layoutOrder = number,
  }

BuffEngine.lua  (simplified)
  ns.activeProcs = {}            -- replaces ns.activeTimers
  ns:OnSpellCastSucceeded(id)  ──► for each provider: if id in provider.events → OnTrigger
  ns:OnUnitAura(info)          ──► for each provider: if UNIT_AURA in provider.events → OnTrigger
  ns:GetActiveProcs()          ──► expiry sweep + sort, returns list of ActiveProc
  StartAllPreviewTimers()      ──► for each provider: merge GetPreviewProcs()
  ScanActiveTimersForCancellation() — remains, but dispatch is per-proc source field

Display.lua  (no type-specific branching)
  UpdateDisplay()  20Hz
    proc.icon, proc.label, proc.key used directly — no resolution chains
  tooltip: single implementation, calls provider:GetPreviewInfo(proc.key)

CDMTab.lua  (simplified)
  RefreshTBTSections() — at-rest icons from provider:GetPreviewInfo(key).icon
  BeginDrag ghost icon  — same source
  tooltip OnEnter       — same source
```

---

### Component Responsibilities

| Component | Responsibility | New vs Modified |
|-----------|----------------|-----------------|
| `Providers.lua` | Houses all SpellProvider implementations; registers `ns.providers` | NEW FILE |
| `UserSpellProvider` | Watches `UNIT_SPELLCAST_SUCCEEDED`; emits procs for `ns.db.trackedBuffs` numeric entries | NEW (extracted from `OnSpellCastSucceeded` branch 3) |
| `TrinketProvider` | Watches `UNIT_SPELLCAST_SUCCEEDED`; matches `TRINKET_SPELLS`; emits procs on "trinket" key | NEW (extracted from branch 1) |
| `PotProvider` | Watches `UNIT_SPELLCAST_SUCCEEDED`; matches `POT_SPELLS`; emits procs on "pot" key | NEW (extracted from branch 2) |
| `LustProvider` | Watches `UNIT_AURA`; matches `SATED_DEBUFF_TO_LUST`; emits procs on "lust" key | NEW (extracted from `OnUnitAura`) |
| `BuffEngine.lua` | Routes events to providers; owns `ns.activeProcs` lifecycle; expiry sweep | MODIFIED (simplified) |
| `Display.lua` | Consumes `ns:GetActiveProcs()` only; zero type-specific branching | MODIFIED (simplified) |
| `CDMTab.lua` | Calls `provider:GetPreviewInfo(key)` for at-rest icons and tooltips | MODIFIED (simplified) |
| `Core.lua` | Event routing — unchanged | UNMODIFIED |
| `EditModeFrames.lua` | Container positioning — unchanged | UNMODIFIED |

---

## Recommended Project Structure

```
TerribleBuffTracker/
├── Core.lua              # event routing — unmodified
├── Providers.lua         # NEW: all SpellProvider implementations + ns.providers registry
├── BuffEngine.lua        # simplified: proc lifecycle, event dispatch to providers
├── Display.lua           # simplified: consumes ActiveProc shape only
├── CDMTab.lua            # simplified: uses provider:GetPreviewInfo for icon/tooltip
├── EditModeFrames.lua    # unmodified
├── CDMTab.xml            # unmodified
```

### Why a single Providers.lua (not one file per provider)

The four providers are small (20-40 lines each) and tightly coupled to the same data tables (`TRINKET_SPELLS`, `POT_SPELLS`, `SATED_DEBUFF_TO_LUST`) that already live in `BuffEngine.lua`. Splitting into four files adds load-order friction for negligible organizational gain. One file keeps all provider logic visible together, making it easy to add a new season's data without hunting across files.

If providers grow substantially (e.g. complex aura-scan chains), splitting is a valid future step.

---

## Architectural Patterns

### Pattern 1: Provider Interface

**What:** Each provider is a table with a defined interface. BuffEngine calls through the interface; providers never call back into BuffEngine (no circular deps).

**When to use:** Any time you need to add a new trigger source without touching the routing loop.

**Trade-offs:** Interface discipline required — Lua has no enforcement. Compensate with explicit assertions in dev builds.

**Example:**
```lua
-- Providers.lua
local UserSpellProvider = {}

-- Events this provider needs routed to it
UserSpellProvider.events = { "UNIT_SPELLCAST_SUCCEEDED" }

-- Returns ActiveProc or nil. Called by BuffEngine for each matching event.
function UserSpellProvider:OnTrigger(event, spellID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return nil end
    local entry = ns.db.trackedBuffs[spellID]
    if not entry or entry.section == "hidden" then return nil end
    local now = GetTime()
    return {
        key       = spellID,
        icon      = ns:GetSpellIcon(spellID),
        label     = entry.label or ("Spell " .. spellID),
        duration  = entry.duration,
        expiresAt = now + entry.duration,
        startedAt = now,
        section   = entry.section,
        layoutOrder = entry.layoutOrder,
    }
end

-- Returns { icon, label, duration } for at-rest display (CDM tab, placeholder bars).
-- Never nil — always returns a best-guess value.
function UserSpellProvider:GetPreviewInfo(key)
    local entry = ns.db.trackedBuffs[key]
    if not entry then return { icon = 134400, label = tostring(key), duration = 0 } end
    return {
        icon     = ns:GetSpellIcon(key),
        label    = entry.label or ("Spell " .. key),
        duration = entry.duration,
    }
end

-- Returns list of ActiveProc for preview mode (one per enabled DB slot this provider owns).
function UserSpellProvider:GetPreviewProcs()
    local now = GetTime()
    local result = {}
    for spellID, entry in pairs(ns.db.trackedBuffs) do
        if type(spellID) == "number" and entry.section ~= "hidden" then
            result[#result+1] = {
                key       = spellID,
                icon      = ns:GetSpellIcon(spellID),
                label     = entry.label or ("Spell " .. spellID),
                duration  = entry.duration,
                expiresAt = now + entry.duration,
                startedAt = now,
                section   = entry.section,
                layoutOrder = entry.layoutOrder,
            }
        end
    end
    return result
end
```

### Pattern 2: Replace-on-Reproc in BuffEngine

**What:** BuffEngine's dispatch loop replaces any existing proc at the same key. This is the "shared slot" semantic that trinket, pot, and lust all require. Providers return a proc; BuffEngine installs it unconditionally.

**When to use:** Always — providers never write to `ns.activeProcs` directly.

**Example:**
```lua
-- BuffEngine.lua
function ns:OnSpellCastSucceeded(spellID)
    for _, provider in ipairs(ns.providers) do
        for _, event in ipairs(provider.events) do
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                local proc = provider:OnTrigger("UNIT_SPELLCAST_SUCCEEDED", spellID)
                if proc then
                    ns.activeProcs[proc.key] = proc
                    if ns.UpdateDisplay then ns:UpdateDisplay() end
                    return  -- first matching provider wins; matches existing fan-out behavior
                end
            end
        end
    end
end
```

Note on `return` after first match: this preserves the existing v0.2.3 behavior where trinket/pot fan-out returns early and never falls through to the user-buff path. Provider order in `ns.providers` encodes this priority (TrinketProvider, PotProvider, then UserSpellProvider).

### Pattern 3: GetPreviewInfo Replaces Divergent Icon Resolution

**What:** All at-rest icon resolution (placeholder bars, CDM tab sections, drag ghosts, tooltips) is delegated to `provider:GetPreviewInfo(key)`. Callers pass the DB key; the responsible provider returns `{ icon, label, duration }`. Callers need zero knowledge of whether the key is a numeric spell, "lust", "trinket", or "pot".

**When to use:** Any time code outside a provider needs the icon or label for a configured slot that has no active proc.

**Eliminates these duplicated call chains (6 sites across Display.lua and CDMTab.lua):**
- `GetSuggestedAtRestIcon(key)` — Display.lua bar placeholder
- `GetSuggestedAtRestIcon(key)` — Display.lua icon placeholder
- `ResolveSuggestedSpellID / GetAtRestMetaIcon` — CDMTab.lua suggested section
- `GetAtRestMetaIcon / ResolveSuggestedSpellID` — CDMTab.lua user sections
- `GetAtRestMetaIcon / ResolveSuggestedSpellID` — CDMTab.lua BeginDrag ghost
- `GetAtRestMetaInfo / ResolveSuggestedSpellID` — CDMTab.lua tooltip

**After refactor:**
```lua
-- CDMTab.lua — suggested section, user sections, ghost, tooltip: all become:
local function GetPreviewInfoForKey(key)
    for _, provider in ipairs(ns.providers) do
        if provider:OwnsKey(key) then
            return provider:GetPreviewInfo(key)
        end
    end
    return { icon = 134400, label = tostring(key), duration = 0 }
end
```

`OwnsKey(key)` is a trivial per-provider check:
- `UserSpellProvider`: `type(key) == "number"`
- `TrinketProvider`: `key == "trinket"`
- `PotProvider`: `key == "pot"`
- `LustProvider`: `key == "lust"`

### Pattern 4: Cancellation Source Field Preserved

**What:** `ScanActiveTimersForCancellation` already dispatches on `timer.source`. Under the new architecture, providers declare their proc's source field. The function is unchanged; providers just need to set it correctly.

| Provider | source field | Cancellation behavior |
|----------|-------------|----------------------|
| `UserSpellProvider` | `"cast"` | Cancelled when aura absent (existing) |
| `TrinketProvider` | `"cast"` | Cancelled when aura absent — SAFE because trinket buff auras are readable (not secret) |
| `PotProvider` | `"cast"` | Cancelled when aura absent |
| `LustProvider` | `"debuff"` | Cancelled via SHARED_LUST_BUFFS check (existing) |

**Note on TrinketProvider source:** The existing code uses `source = "cast"` for trinket procs and the `metaSlot` field for slot identity. This is correct behavior and should be preserved exactly — do not change to a new source value.

---

## Data Flow

### Cast-Triggered Proc (UserSpell / Trinket / Pot)

```
UNIT_SPELLCAST_SUCCEEDED (spellID)
    ↓
Core.lua: ns:OnSpellCastSucceeded(spellID)
    ↓
BuffEngine.lua: iterate ns.providers in priority order
    ↓
provider:OnTrigger("UNIT_SPELLCAST_SUCCEEDED", spellID) → ActiveProc or nil
    ↓ (proc returned)
ns.activeProcs[proc.key] = proc     -- overwrites any existing proc at same key
    ↓
ns:UpdateDisplay()
    ↓
Display.lua: proc.icon, proc.label, proc.key used directly — no resolution
```

### Aura-Triggered Proc (Lust)

```
UNIT_AURA (updateInfo)
    ↓
Core.lua: ns:OnUnitAura(updateInfo)
    ↓
BuffEngine.lua: iterate ns.providers with UNIT_AURA in events
    ↓
LustProvider:OnTrigger("UNIT_AURA", updateInfo)
    → checks addedAuras for SATED_DEBUFF_TO_LUST match
    → returns ActiveProc with key="lust" or nil
    ↓ (proc returned)
ns.activeProcs["lust"] = proc
    ↓
ns:UpdateDisplay()
```

### At-Rest Display (No Active Proc)

```
Display.lua: UpdateDisplay() — slot has no active proc
    ↓
GetPreviewInfoForKey(slot.spellID)
    ↓
ns.providers: find provider where provider:OwnsKey(slot.spellID) == true
    ↓
provider:GetPreviewInfo(slot.spellID) → { icon, label, duration }
    ↓
bar.icon:SetTexture(info.icon)
bar.label:SetText(info.label)
```

### Preview Mode

```
CDMTab.lua: StartPreview() → ns:StartAllPreviewTimers()
    ↓
BuffEngine.lua: wipe(ns.activeProcs)
    for each provider: procs = provider:GetPreviewProcs()
        for each proc: ns.activeProcs[proc.key] = proc
    merge savedPreviewTimers (real casts override preview)
    ↓
ns:UpdateDisplay()
```

---

## Integration Points — Exact Change Surface

### New: Providers.lua

New file, loaded after BuffEngine.lua (add to .toc before Display.lua).

Defines all four providers and registers them:

```lua
ns.providers = { TrinketProvider, PotProvider, LustProvider, UserSpellProvider }
```

Provider order matters: TrinketProvider and PotProvider must come before UserSpellProvider so their `OnTrigger` wins when a trinket spellID matches both `TRINKET_SPELLS` and (hypothetically) `trackedBuffs`.

Exports one helper to ns namespace:
```lua
ns.GetPreviewInfoForKey  -- used by Display.lua and CDMTab.lua
```

### Modified: BuffEngine.lua

Remove: all three branches from `OnSpellCastSucceeded`  
Remove: `StartLustTimer`, `StartTrinketTimer` (inline via provider)  
Remove: `GetSuggestedAtRestIcon`, `GetAtRestMetaIcon` (moved to providers)  
Remove: `ResolveSuggestedSpellID` (callers use `GetPreviewInfoForKey` instead)  
Keep: `ns.activeProcs` (renamed from `ns.activeTimers`), `GetActiveTimers`/`GetActiveProcs`, `ScanActiveTimersForCancellation`, `ClearAllTimers`, `StartAllPreviewTimers`, schema migration, `AddTrackedBuff`, `RemoveTrackedBuff`, `SetBuffSection`  
Keep: `TRINKET_SPELLS`, `POT_SPELLS`, `TRINKET_ITEM_IDS`, `POT_ITEM_IDS` (still needed by TrinketProvider and PotProvider — or move to Providers.lua if preferred)  
Keep: `SATED_DEBUFF_TO_LUST`, `SHARED_LUST_BUFFS` (needed by LustProvider)  
Keep: `ns.metaAtRest`, `ns.metaIcons`, `RefreshMetaIcons` — consumed by CDMTab StartPreview  
Modify: `OnSpellCastSucceeded` becomes a 10-line dispatch loop  
Modify: `OnUnitAura` keeps its lust-before-secret-gate ordering but delegates the lust proc creation to LustProvider  
Modify: `StartAllPreviewTimers` iterates `ns.providers` instead of duplicating resolution logic

### Modified: Display.lua

Remove: `GetSuggestedAtRestIcon` (function at line 87)  
Remove: The two divergent placeholder icon paths (bar path lines ~478-507, icon path lines ~655-665)  
Replace with: single call to `ns.GetPreviewInfoForKey(slot.spellID)`  
Remove: The parallel tooltip implementations (bar OnEnter lines ~168-191, icon OnEnter lines ~235-257)  
Replace with: single shared tooltip function that calls `ns.GetPreviewInfoForKey(slot.spellID)`  
Keep: all frame creation, pool management, container sizing, combat tracking — none of this touches type-specific logic

### Modified: CDMTab.lua

Remove: `GetAtRestMetaIcon / ResolveSuggestedSpellID` chains in `RefreshTBTSections` (both suggested and user sections)  
Remove: Same chains in `BeginDrag` ghost icon setup  
Remove: `metaInfo / ResolveSuggestedSpellID` tooltip logic in `CreateIconFrame OnEnter`  
Replace all with: `ns.GetPreviewInfoForKey(spellID)` call  
Keep: drag-and-drop state machine, `addSuggestedToSection`, `StartPreview`/`StopPreview`, section structure — no changes to these

### Unmodified: Core.lua, EditModeFrames.lua, CDMTab.xml

---

## Build Order — Migration Steps

Each step leaves the addon in a runnable state. Test at each numbered step before proceeding.

| Step | File | Work | Validates |
|------|------|------|-----------|
| 1 | `Providers.lua` (new) | Create file; stub all four providers with identity-only `OwnsKey` and placeholder `GetPreviewInfo` returning `{ icon=134400, label="stub", duration=0 }`. Register `ns.providers`. Add to .toc. | File loads; no errors |
| 2 | `Providers.lua` | Implement `UserSpellProvider:OnTrigger` and `GetPreviewProcs` (exact translation from `OnSpellCastSucceeded` branch 3 and `StartAllPreviewTimers` numeric loop). | User buffs still work |
| 3 | `BuffEngine.lua` | Replace `OnSpellCastSucceeded` with provider dispatch loop. Remove old branches but keep `TRINKET_SPELLS`, `POT_SPELLS` accessible for providers. | User buff cast detection still works; trinket/pot temporarily broken (TrinketProvider/PotProvider still stubbed) |
| 4 | `Providers.lua` | Implement `TrinketProvider:OnTrigger` and `GetPreviewProcs` (translation of branch 1). | Trinket detection restored |
| 5 | `Providers.lua` | Implement `PotProvider:OnTrigger` and `GetPreviewProcs` (translation of branch 2). | Pot detection restored |
| 6 | `Providers.lua` | Implement `LustProvider:OnTrigger` and `GetPreviewProcs` (translation of `StartLustTimer` + `OnUnitAura` lust block). Modify `BuffEngine:OnUnitAura` to delegate lust proc creation to provider. | Lust detection still works |
| 7 | `Providers.lua` | Implement all four `GetPreviewInfo` methods with full icon/label resolution. Implement `ns.GetPreviewInfoForKey` dispatch helper. | At-rest info available |
| 8 | `BuffEngine.lua` | Replace `StartAllPreviewTimers` to iterate providers. Remove `StartLustTimer`, `ResolveSuggestedSpellID`, `GetAtRestMetaIcon`. | Preview mode works with unified path |
| 9 | `Display.lua` | Remove `GetSuggestedAtRestIcon`. Replace both placeholder icon paths and both tooltip OnEnter handlers with `ns.GetPreviewInfoForKey`. | Display renders correctly; zero divergent codepaths |
| 10 | `CDMTab.lua` | Replace all six icon/tooltip resolution chains with `ns.GetPreviewInfoForKey`. | CDM tab renders correctly |
| 11 | Cleanup | Remove dead code (`ns.metaIcons`, `GetSuggestedAtRestIcon`, `ResolveSuggestedSpellID`, etc.) only after confirming no remaining callers. Run stylua. | Clean compile |

**Incremental safety:** Steps 1-6 keep the existing BuffEngine branches active in parallel with the new provider dispatch. Only at step 3 does the old path get removed — at that point, if providers are correctly translated, behavior is identical. Steps 7-10 are purely display-layer and cannot break timer correctness.

**Key risk at step 3:** If `OnSpellCastSucceeded` dispatch loop iterates in wrong provider order, a trinket spellID could match `UserSpellProvider` (if the user somehow added that spellID manually). Guard: TrinketProvider and PotProvider must be first in `ns.providers`.

---

## Anti-Patterns

### Anti-Pattern 1: Providers write directly to ns.activeProcs

**What people do:** Have `provider:OnTrigger` store the proc in `ns.activeProcs` itself and return nothing.

**Why it's wrong:** BuffEngine can no longer enforce replace-on-reproc consistently. The "shared slot" logic gets scattered back into each provider. The interface becomes stateful and order-dependent.

**Do this instead:** Providers return a proc table or nil. BuffEngine owns all writes to `ns.activeProcs`. One place, one policy.

### Anti-Pattern 2: Provider per-file decomposition

**What people do:** Create `UserSpellProvider.lua`, `TrinketProvider.lua`, etc.

**Why it's wrong:** Each provider needs `TRINKET_SPELLS`, `SATED_DEBUFF_TO_LUST`, and other data tables. Spreading across files either duplicates data or creates cross-file namespace pollution. The providers are small enough that the organizational cost outweighs the benefit.

**Do this instead:** All providers in `Providers.lua`. If a provider grows beyond ~60 lines of logic (not counting data tables), revisit.

### Anti-Pattern 3: Calling GetPreviewInfo inside the 20Hz UpdateDisplay for active procs

**What people do:** Unify active and inactive display by always calling `GetPreviewInfo` instead of reading from the proc's own fields.

**Why it's wrong:** `GetPreviewInfo` for TrinketProvider calls `ns:GetAtRestMetaIcon` which scans equipped slots. At 20Hz this is unnecessary work — the active proc already has the resolved icon baked in at cast time.

**Do this instead:** Active proc path reads `proc.icon` and `proc.label` directly. `GetPreviewInfo` is called only in the placeholder path (slot has no active proc), which is already gated by the `hideWhenInactive` dirty-check.

### Anti-Pattern 4: Removing ns.metaAtRest before verifying RefreshMetaIcons callers

**What people do:** Delete `ns.metaAtRest`, `ns.metaIcons`, and `RefreshMetaIcons` as part of cleanup since TrinketProvider encapsulates icon resolution.

**Why it's wrong:** `CDMTab.lua:StartPreview` calls `ns:RefreshMetaIcons()` before opening the CDM settings panel to pre-warm icon caches. If TrinketProvider's `GetPreviewInfo` uses `ns.metaAtRest` internally, removing `RefreshMetaIcons` breaks the cache warm-up path.

**Do this instead:** Move `RefreshMetaIcons` into `TrinketProvider` and `PotProvider` as provider-level methods. Have CDMTab call `provider:RefreshCache()` on each provider instead. Only remove `ns.metaAtRest` after providers have their own internal cache. This is a step-11 cleanup concern, not a migration blocker.

### Anti-Pattern 5: Removing `TRINKET_SPELLS` from ns namespace before CDMTab.lua stop using it

**What people do:** Scope `TRINKET_SPELLS` as a local inside `Providers.lua` immediately.

**Why it's wrong:** `CDMTab.lua:addSuggestedToSection` and the suggested section tooltip reference `ns.TRINKET_SPELLS` (via `ns.metaAtRest` resolution). Until CDMTab is fully migrated to `GetPreviewInfo`, `ns.TRINKET_SPELLS` must remain on the namespace.

**Do this instead:** Keep `ns.TRINKET_SPELLS` and `ns.POT_SPELLS` on the namespace through all migration steps. Remove from namespace in step-11 cleanup after CDMTab migration is verified.

---

## Sources

- Codebase: `BuffEngine.lua`, `Display.lua`, `CDMTab.lua`, `Core.lua`, `EditModeFrames.lua` (read directly — HIGH confidence)
- `.planning/PROJECT.md`: milestone goals and active requirements (HIGH)
- Existing research: `.planning/research/ARCHITECTURE.md` v0.2.3 (patterns for trinket/pot that carry forward)

---
*Architecture research for: TerribleBuffTracker v0.2.4 — SpellProvider/ActiveProc refactor*
*Researched: 2026-04-18*
