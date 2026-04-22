# Feature Research

**Domain:** SpellProvider abstraction — unified buff detection and display interface
**Researched:** 2026-04-18
**Confidence:** HIGH (derived from direct code analysis of v0.2.3 implementation)

---

## Four Buff Types: Side-by-Side Comparison

### Detection Trigger

| Buff Type | Event | Signal | Guard |
|-----------|-------|--------|-------|
| UserSpell | `UNIT_SPELLCAST_SUCCEEDED` | `trackedBuffs[spellID]` entry exists | `entry.section == "hidden"` |
| Trinket | `UNIT_SPELLCAST_SUCCEEDED` | `TRINKET_SPELLS[spellID]` exists | `trackedBuffs["trinket"].section == "hidden"` |
| Pot | `UNIT_SPELLCAST_SUCCEEDED` | `POT_SPELLS[spellID]` exists | `trackedBuffs["pot"].section == "hidden"` |
| Lust | `UNIT_AURA` addedAuras loop | `SATED_DEBUFF_TO_LUST[aura.spellId]` maps debuff to buff | `ns.previewActive` suppresses; per-aura `issecretvalue()` guard |

UserSpell, Trinket, and Pot share the same WoW event but diverge on which lookup succeeds.
Lust is the only type driven by UNIT_AURA; it responds to the Sated *debuff* appearing, not the buff itself.

---

### Duration Resolution

| Buff Type | Source | Flexibility |
|-----------|--------|-------------|
| UserSpell | `entry.duration` from SavedVariables (user-set at add time) | Per-buff, user editable |
| Trinket | `TRINKET_SPELLS[castSpellID].duration` — CSV-derived, per cast spell | Per spell, hardcoded in code |
| Pot | `POT_SPELLS[castSpellID].duration` — CSV-derived, per cast spell | Per spell, hardcoded in code |
| Lust | Hardcoded 40 seconds | Fixed, never user-configurable |

Trinket and Pot resolve duration at cast time from the *actual* cast spellID, not from the "trinket"/"pot"
DB slot entry. The DB slot stores `duration = 0` as a sentinel meaning "resolve at cast time." UserSpell
reads from SavedVariables. Lust ignores the DB entry duration entirely.

**Preview duration bug (current):** `StartAllPreviewTimers` uses `entry.duration` for all types. For
trinket/pot, `entry.duration = 0` (sentinel), so preview starts a 0-second timer that expires
instantly. GetPreviewInfo() on each provider must return a valid non-zero duration to fix this.

---

### Icon Resolution

Icon resolution has two states: **at-rest** (no active timer, placeholder shown) and **active** (timer running).

| Buff Type | At-Rest Icon | Active Icon | Icon Changes on Proc? |
|-----------|-------------|-------------|----------------------|
| UserSpell | `GetSpellIcon(spellID)` | Same | No |
| Trinket | `RefreshMetaIcons()` scan: equipped trinket slot -> reverse itemID->spellID -> `GetSpellIcon(resolvedSpellID)` | `GetSpellIcon(castSpellID)` — the specific trinket cast | Yes |
| Pot | `RefreshMetaIcons()` scan: bag `C_Item.GetItemCount` -> reverse itemID->spellID -> `GetSpellIcon(resolvedSpellID)` | `GetSpellIcon(castSpellID)` — the specific pot cast | Yes |
| Lust | `GetSpellIcon(ResolveSuggestedSpellID("lust"))` — class-aware (Bloodlust/Heroism/etc.) | `GetSpellIcon(lustSpellID)` — the actual detected buff | Yes |

At-rest icon for Trinket/Pot is combat-gated: `RefreshMetaIcons()` returns early if `InCombatLockdown()`.
The cache may be stale during combat; this is expected and acceptable.

At-rest icon for Lust is spec-aware via `GetHunterLustSpell()` (BM vs MM Hunter diverge). This is a live
call to `GetSpecializationInfo`, not a cached value, so it stays correct across spec swaps within session.

Fallback for all types: `134400` (question mark icon).

---

### Label Resolution

| Buff Type | At-Rest Label | Active Label | Changes on Proc? |
|-----------|--------------|--------------|-----------------|
| UserSpell | `entry.label` from SavedVariables | Same `entry.label` (captured at timer creation) | No |
| Trinket | `entry.label` ("Trinket") | `C_Spell.GetSpellInfo(castSpellID).name` or fallback to `entry.label` | Yes |
| Pot | `entry.label` ("Damage Pot") | `C_Spell.GetSpellInfo(castSpellID).name` or fallback | Yes |
| Lust | Resolved via `ResolveSuggestedSpellID` + `GetSpellInfo` | `C_Spell.GetSpellInfo(lustSpellID).name` or "Lust / Heroism" | Yes |

Trinket and Pot labels meaningfully change between states: at-rest shows a generic category name;
active shows the specific proc spell name ("Light Company Guidon", "Potion of Recklessness", etc.).

---

### Timer Key (activeTimers index)

This is a key source of current complexity.

| Buff Type | activeTimers key (current) | DB slot key | Bridge required? |
|-----------|---------------------------|------------|-----------------|
| UserSpell | numeric `spellID` | numeric `spellID` | No — direct match |
| Trinket | numeric `castSpellID` (e.g. 1259633) | `"trinket"` (string) | Yes — `metaSlot = "trinket"` field; Display double-indexes `activeBySpell` with both keys |
| Pot | numeric `castSpellID` | `"pot"` (string) | Yes — same double-index pattern |
| Lust | `"lust"` (string) | `"lust"` (string) | No — direct match |

The numeric/string mismatch for Trinket/Pot is the primary source of Display complexity. The `metaSlot`
field exists only to bridge this gap. Moving to a stable string key (`"trinket"`, `"pot"`) as the proc key
eliminates the bridge entirely — reproc becomes a simple overwrite, eviction becomes a simple overwrite,
and Display drops the double-index pattern.

---

### Reproc Behavior

| Buff Type | Current reproc action | With unified string key |
|-----------|----------------------|------------------------|
| UserSpell | `activeTimers[spellID] = newTimer` — natural overwrite | Same |
| Trinket | Eviction loop: scan all `ns.activeTimers` for `metaSlot == "trinket"`, nil it, then insert new numeric key | `activeProcs["trinket"] = newProc` — natural overwrite |
| Pot | Same eviction loop as Trinket | `activeProcs["pot"] = newProc` — natural overwrite |
| Lust | Guard in `StartLustTimer`: if timer exists and unexpired, return early (Lust cannot reproc while Sated is up) | Same guard, but checked in LustProvider.OnTrigger or BuffEngine |

The eviction loop for Trinket/Pot (`for existingID, existingTimer in pairs(ns.activeTimers)`) is O(n)
over all active timers and only exists because of the key mismatch. It disappears with stable string keys.

---

### Cancellation (ScanActiveTimersForCancellation)

| Buff Type | `source` field | Cancellation check | Edge case |
|-----------|---------------|-------------------|-----------|
| UserSpell | `"cast"` | `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` nil -> cancel | `spellID` is the timer key (numeric) — works directly |
| Trinket | `"cast"` | `GetPlayerAuraBySpellID(castSpellID)` nil -> cancel | With string key, `castSpellID` must be stored as a separate field on the proc |
| Pot | `"cast"` | `GetPlayerAuraBySpellID(castSpellID)` nil -> cancel | Same — needs `castSpellID` field on proc |
| Lust | `"debuff"` | Check all `SHARED_LUST_BUFFS[lustBuffID]` entries; any present -> keep; all absent -> cancel | `lustBuffID` is the detected buff ID (e.g. 32182 for Heroism), not the Sated debuff ID |

The aura check is blocked in Mythic+/restricted zones via `C_Secrets.ShouldAurasBeSecret()`. When
blocked, no cancellation occurs — timers run to natural expiry. This is intentional and correct.

With a string key for Trinket/Pot, the cancellation scan must check `proc.castSpellID` rather than
the proc key itself. The `castSpellID` field becomes a required part of the ActiveProc shape for
cast-sourced meta-slot procs.

---

## Minimal Common Interface: SpellProvider

All four types can be normalized to these four methods:

### GetEventInterest() -> { eventName, ... }

Declares which WoW events the provider listens to. BuffEngine routes only to providers that declared
interest in the fired event.

| Provider | Returns |
|----------|---------|
| UserSpellProvider | `{ "UNIT_SPELLCAST_SUCCEEDED" }` |
| TrinketProvider | `{ "UNIT_SPELLCAST_SUCCEEDED" }` |
| PotProvider | `{ "UNIT_SPELLCAST_SUCCEEDED" }` |
| LustProvider | `{ "UNIT_AURA" }` |

### OnTrigger(event, ...) -> proc | nil

Called by BuffEngine when a matching event fires. Returns a normalized ActiveProc table or nil (event
args not for this provider — e.g. a spellcast that's not in TRINKET_SPELLS).

**ActiveProc shape:**

```lua
{
    key        = "...",   -- stable slot key for activeProcs table (string or number)
    icon       = 134400,  -- texture ID at time of trigger (cast spell icon)
    duration   = 0,       -- seconds (non-zero)
    label      = "...",   -- display string (resolved at trigger time)
    source     = "cast",  -- "cast" | "debuff" — cancellation scan strategy
    -- present only when needed by cancellation scan:
    castSpellID  = nil,   -- numeric; Trinket/Pot only — used by GetPlayerAuraBySpellID check
    lustBuffID   = nil,   -- numeric; Lust only — used by SHARED_LUST_BUFFS lookup
}
```

**Key field decisions per provider:**

| Provider | `key` | Rationale |
|----------|-------|-----------|
| UserSpellProvider | numeric `spellID` | Direct 1:1 with DB slot; no bridge needed |
| TrinketProvider | `"trinket"` (string) | Stable DB slot key; eliminates metaSlot bridge; reproc = overwrite |
| PotProvider | `"pot"` (string) | Same |
| LustProvider | `"lust"` (string) | Already string-keyed; no change |

### GetPreviewInfo() -> proc

Returns a proc for preview mode. Must return a valid non-zero duration.

| Provider | icon source | duration source | label source |
|----------|------------|-----------------|-------------|
| UserSpellProvider | `GetSpellIcon(spellID)` | `entry.duration` from DB | `entry.label` from DB |
| TrinketProvider | `metaAtRest.trinket.icon` from cache | `metaAtRest.trinket.duration` from cache | resolved spell name or "Trinket" |
| PotProvider | `metaAtRest.pot.icon` from cache | `metaAtRest.pot.duration` from cache | resolved spell name or "Damage Pot" |
| LustProvider | `GetSpellIcon(ResolveSuggestedSpellID("lust"))` | hardcoded 40 | "Lust / Heroism" |

TrinketProvider and PotProvider must read from the `ns.metaAtRest` cache (populated by
`RefreshMetaIcons()`). GetPreviewInfo() must not trigger a new scan — only read the cache.

### GetAtRestInfo() -> { icon, label }

Returns display data when no active timer exists (CDM placeholder / hideWhenInactive=false state).
Display and CDMTab call this instead of implementing their own branching logic.

| Provider | icon | label |
|----------|------|-------|
| UserSpellProvider | `GetSpellIcon(spellID)` | `entry.label` |
| TrinketProvider | `ns:GetAtRestMetaIcon("trinket")` (cache) | resolved spell name or `entry.label` |
| PotProvider | `ns:GetAtRestMetaIcon("pot")` (cache) | resolved spell name or `entry.label` |
| LustProvider | `GetSpellIcon(ns:ResolveSuggestedSpellID("lust"))` | `entry.label` or "Lust / Heroism" |

---

## Feature Landscape

### Table Stakes (Required for SpellProvider to be correct)

Features the refactor must preserve to avoid breaking existing behavior.

| Feature | Why Required | Complexity | Notes |
|---------|-------------|------------|-------|
| OnTrigger returns nil for non-matching events | Prevents false triggers; Trinket and Pot both watch UNIT_SPELLCAST_SUCCEEDED | LOW | Each provider short-circuits on table miss |
| Stable proc key per provider | Display and cancellation scan find proc by consistent key; no metaSlot bridge | LOW | Trinket/Pot switch from numeric castSpellID to string slot key |
| Icon switches on proc (Trinket, Pot, Lust) | Active icon differs from at-rest — intentional UX indicating which specific item fired | MEDIUM | `icon` field in proc set from castSpellID or lustSpellID at trigger time |
| Lust no-restart guard | Lust cannot reproc while Sated debuff is up — guard is correctness | LOW | Check in LustProvider.OnTrigger or in BuffEngine before replace-on-reproc |
| Trinket/Pot shared-slot overwrite | One meta-slot timer active at a time; with stable string key this is natural | LOW | Eviction loop eliminated; `activeProcs["trinket"] = newProc` |
| Cancellation `source` field on ActiveProc | BuffEngine cancellation scan dispatches on "cast" vs "debuff" strategy | LOW | Required field; provider sets it |
| `lustBuffID` field on Lust proc | `SHARED_LUST_BUFFS` lookup requires the detected buff ID (e.g. 32182) | LOW | Required for Lust cancellation correctness |
| `castSpellID` field on Trinket/Pot proc | `GetPlayerAuraBySpellID` needs the numeric cast spell, not the string slot key | LOW | Required when Trinket/Pot switch to string proc key |
| Preview non-zero duration for all types | Trinket/Pot currently show 0s preview (duration=0 sentinel in DB) | MEDIUM | GetPreviewInfo() reads from metaAtRest cache for Trinket/Pot |
| Combat-gated icon refresh | RefreshMetaIcons blocked during combat; GetAtRestInfo must read cache only | LOW | Providers call ns:GetAtRestMetaIcon(), never trigger a scan |
| Secret-value guard in Lust OnTrigger | `issecretvalue(aura.spellId)` check must run before table index | LOW | LustProvider.OnTrigger embeds this check; must run before ShouldAurasBeSecret gate |
| isFullUpdate suppression | UNIT_AURA isFullUpdate = zone boundary transient; suppress aura scan | LOW | LustProvider or BuffEngine routing discards isFullUpdate events |

### Differentiators (Clean interface unlocks)

Features that become possible or cleaner with the unified interface.

| Feature | Value Proposition | Complexity | Notes |
|---------|------------------|------------|-------|
| Zero type-specific branches in Display | Display becomes a pure consumer of ActiveProc and GetAtRestInfo; no metaSlot, no ResolveSuggestedSpellID | MEDIUM | All branching moves into providers |
| Zero type-specific branches in CDMTab | Tooltip, icon, label resolution use GetAtRestInfo from provider; no META_DESCRIPTIONS inline table | MEDIUM | CDMTab currently has its own metaInfo/META_DESCRIPTIONS branch |
| New buff type = new file only | Adding a 5th provider requires no changes to BuffEngine, Display, or CDMTab | LOW | GetEventInterest() is the extension point |
| Preview duration correct for all types | Trinket/Pot preview currently shows 0s timers — visually broken | LOW | Side effect of GetPreviewInfo() returning cache-resolved duration |
| BuffEngine owns all lifecycle | Replace-on-reproc, expiry sweep, cancellation are BuffEngine responsibilities | MEDIUM | Providers must be stateless |
| Tooltip consolidation | Display and CDMTab both implement tooltip resolution; GetAtRestInfo could return tooltipSpellID | MEDIUM | Defer if not needed for initial refactor |

### Anti-Features (Avoid these)

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|--------------|-----------------|-------------|
| Provider holds active timer state | Natural — provider "knows" its timer | Breaks single-source-of-truth; cancellation scan and Display must consult both BuffEngine and providers | Provider is stateless; BuffEngine owns activeProcs |
| Provider directly calls UpdateDisplay | Provider "knows" when something changed | Couples providers to rendering; prevents testability | BuffEngine calls UpdateDisplay after processing OnTrigger return |
| Polymorphic proc requiring consumer branching | Provider-specific fields consumed by Display | Reintroduces the type-specific branching the refactor aims to eliminate | Only include fields all consumers need; `castSpellID` and `lustBuffID` are for cancellation scan only, not Display |
| Dynamic event registration per provider | Providers could call RegisterEvent themselves | Bypasses BuffEngine routing; complicates teardown and ordering | Providers declare interest via GetEventInterest(); Core.lua registers events centrally |
| Icon refresh inside OnTrigger (Trinket/Pot) | "Update at-rest icon when trinket fires" | `InCombatLockdown()` blocks item scanning; OnTrigger fires during combat | RefreshMetaIcons() on CDM open only; OnTrigger reads from cache |
| Aura-based cancellation for Trinket/Pot at cast time | Cancellation during combat for accuracy | Trinket/Pot aura spellIDs are secret values in combat | Timer runs to natural expiry; same accepted behavior as pre-refactor |

---

## Feature Dependencies

```
GetEventInterest()
    required by -> BuffEngine event routing
                       required by -> OnTrigger() being called at all

OnTrigger() -> ActiveProc
    required by -> BuffEngine lifecycle (replace-on-reproc, expiry sweep)
    required by -> Display (consumes ActiveProc icon/label/duration/key)
    required by -> Cancellation scan (reads source / castSpellID / lustBuffID)

GetPreviewInfo() -> proc
    required by -> StartAllPreviewTimers (preview mode)
    depends on  -> RefreshMetaIcons() cache for Trinket/Pot (at-rest duration)

GetAtRestInfo() -> { icon, label }
    required by -> Display placeholder rendering
    required by -> CDMTab icon grid rendering
    depends on  -> RefreshMetaIcons() cache for Trinket/Pot (at-rest icon)
    depends on  -> ResolveSuggestedSpellID for Lust (class-aware, live call)

RefreshMetaIcons()
    required by -> GetAtRestInfo() for Trinket/Pot
    required by -> GetPreviewInfo() for Trinket/Pot
    combat-gated by -> InCombatLockdown()
```

### Dependency Notes

- **GetPreviewInfo() depends on RefreshMetaIcons():** CDMTab `StartPreview()` already calls
  `RefreshMetaIcons()` before iterating procs. Providers read from cache; they never trigger a scan.
- **Lust OnTrigger ordering:** The `issecretvalue(aura.spellId)` check and Sated-debuff detection
  must execute before the `ShouldAurasBeSecret()` gate (LUST-01 in current code). LustProvider must
  embed this ordering, or BuffEngine must guarantee it for UNIT_AURA routing.
- **String key for Trinket/Pot unlocks Display simplification:** Once proc key is `"trinket"` /
  `"pot"`, Display drops the `metaSlot` double-index. This is a prerequisite for zero-branching Display.
- **`castSpellID` on proc is prerequisite for cancellation correctness:** Cancellation scan uses
  `GetPlayerAuraBySpellID(castSpellID)` — this must be the numeric spell ID, not the string slot key.

---

## MVP Definition

### Required for v0.2.4 to ship

- [ ] `GetEventInterest()` on all four providers
- [ ] `OnTrigger()` on all four providers — returns normalized ActiveProc or nil
- [ ] `GetPreviewInfo()` on all four providers — non-zero duration for all types
- [ ] `GetAtRestInfo()` on all four providers — Display and CDMTab drop all branching
- [ ] BuffEngine: single `activeProcs` table, replace-on-reproc by proc key, expiry sweep
- [ ] BuffEngine: cancellation scan reads `source` / `castSpellID` / `lustBuffID` from ActiveProc
- [ ] Display: consumes only ActiveProc and GetAtRestInfo() — no metaSlot, no ResolveSuggestedSpellID
- [ ] CDMTab: consumes GetAtRestInfo() from provider — no META_DESCRIPTIONS branch

### Defer within milestone (add if time allows)

- [ ] Tooltip resolution consolidated into provider `GetTooltipInfo()` — currently duplicated between
      Display OnEnter and CDMTab OnEnter

### Future (v0.3+)

- [ ] Aura-based duration override (reading actual remaining time from aura data if Blizzard unlocks)
- [ ] Dynamic buff discovery (auto-tracking without user adding spell IDs)

---

## Edge Cases: Explicit Handling Required

### Reproc

| Scenario | Expected behavior | Implementation |
|----------|-----------------|---------------|
| User spell recast before expiry | Replace timer — reset countdown | BuffEngine: `activeProcs[proc.key] = proc` |
| Same trinket cast twice | Replace timer — reset countdown | Same overwrite with string key |
| Different trinket cast while first active | Replace timer — new spell icon and label | Same overwrite; old numeric castSpellID discarded |
| Pot recast (same or different) | Replace timer | Same |
| Lust while lust already active | No-op — Sated prevents re-cast anyway | LustProvider.OnTrigger checks `activeProcs["lust"]` expiry; returns nil if unexpired |

### Cancellation

| Scenario | Expected behavior | Notes |
|----------|-----------------|-------|
| Aura scan blocked (M+) | No cancellation; timer runs to expiry | `auraCheckBlocked` flag gates scan; preserved |
| Lust buff cleansed early | All `SHARED_LUST_BUFFS[lustBuffID]` absent -> cancel | Must check all entries in the shared group |
| Trinket proc dispelled | `GetPlayerAuraBySpellID(proc.castSpellID)` nil -> cancel | `castSpellID` on proc required |
| isFullUpdate suppresses scan | Discard event | Already in OnUnitAura; preserved in provider routing |

### Preview Mode

| Scenario | Expected behavior | Notes |
|----------|-----------------|-------|
| CDM opened mid-combat | RefreshMetaIcons skips; stale at-rest cache used | Acceptable; existing behavior preserved |
| Preview while real timer active | Real timers (source field present) merged over preview timers | Existing savedPreviewTimers logic preserved |
| Trinket/Pot preview duration | GetPreviewInfo() reads `metaAtRest[key].duration` — non-zero | Fixes current 0s bug |
| Lust preview | GetPreviewInfo() returns 40s | Unchanged |

### Icon Refresh (Combat Restriction)

| Scenario | Expected behavior | Notes |
|----------|-----------------|-------|
| Player equips different trinket mid-session | At-rest icon stale until next CDM open | Acceptable; RefreshMetaIcons called on CDM open |
| Different trinket used than equipped scan detected | Active icon is always cast spell icon — always correct | cast icon does not depend on scan |
| Spec change (BM -> MM Hunter) | Lust at-rest icon updates immediately | GetAtRestInfo() calls ResolveSuggestedSpellID live, not cached |

---

## Sources

- Direct analysis: `BuffEngine.lua` (v0.2.3, 2026-04-18)
- Direct analysis: `Display.lua` (v0.2.3, 2026-04-18)
- Direct analysis: `Core.lua` event registration
- Direct analysis: `CDMTab.lua` tooltip and icon branching
- `.planning/PROJECT.md` requirements (Active section, v0.2.4 milestone)

---
*Feature research for: SpellProvider abstraction (TerribleBuffTracker v0.2.4)*
*Researched: 2026-04-18*
