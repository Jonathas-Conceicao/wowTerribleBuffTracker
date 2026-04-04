# Feature Landscape: Aura-Based Timer Cancellation

**Domain:** WoW addon — aura monitoring with secret value constraints
**Researched:** 2026-04-03
**Milestone:** v0.2.1

---

## Context and Constraints

This milestone adds one mechanism: silently cancel active timers when tracked buffs are no longer present in aura data. The existing system (UNIT_SPELLCAST_SUCCEEDED + GetTime()) starts timers. UNIT_AURA stops them early.

**Critical constraint:** Aura data is "SecretWhenUnitAuraRestricted" in WoW Midnight (Interface 120000+). In-combat, in mythic keystone, in PvP, and in active instance encounters, aura field values (spellId, duration, expirationTime, name) become opaque secret values. Attempting to index a secret value produces a Lua error: `"table index is secret"` or `"attempt to perform arithmetic on a secret number value"`.

**What is never secret (HIGH confidence — verified via Warcraft Wiki and Blizzard's CooldownViewer.lua source):**
- `removedAuraInstanceIDs` in the UNIT_AURA updateInfo payload — always numeric, always readable
- `updatedAuraInstanceIDs` in the UNIT_AURA updateInfo payload — always readable
- `auraInstanceID` field on individual `addedAuras` entries — always readable

**What is conditionally secret:**
- `addedAuras[i].spellId` — readable out of combat, secret in restricted contexts
- `addedAuras[i].duration`, `expirationTime`, `name` — same restriction
- `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` return value — marked `SecretWhenUnitAuraRestricted`; returns an opaque table (or nil if absent) during combat lockdown; fields on it cannot be indexed

**Blizzard's own pattern (HIGH confidence — verified directly in CooldownViewer.lua and CooldownViewerItemData.lua):**
CDM builds a `spellID → auraInstanceID` registry. It calls `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` at setup time (when data is accessible) to populate the mapping. On UNIT_AURA, it consumes only `removedAuraInstanceIDs` — which are never secret — to look up which tracked item lost its aura. This avoids touching secret fields in the hot path. TBT should replicate this exact pattern.

---

## Table Stakes

Features users expect from this milestone. Missing any of these means the milestone goal is unmet.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Register UNIT_AURA for "player" unit | Core detection mechanism — no event, no cancellation | Low | Single `RegisterEvent` call added to Core.lua |
| Build spellID → auraInstanceID map on startup | Enables secret-safe removal detection using never-secret instance IDs | Medium | Iterate `activeTimers` on PLAYER_ENTERING_WORLD; call `GetPlayerAuraBySpellID` for each to capture current instanceID |
| Update map when OnSpellCastSucceeded fires | After cast, a new aura appears — must capture its instanceID immediately while data is accessible | Medium | Call `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` inside `ns:OnSpellCastSucceeded` after setting `ns.activeTimers[spellID]` |
| Cancel timer on removedAuraInstanceIDs match | Core cancellation behavior — covers lust-on-wipe, trinket procs, dispels, manual buff cancellations | Low | Iterate `removedAuraInstanceIDs`; reverse-lookup spellID from map; `ns.activeTimers[spellID] = nil` + `ns:UpdateDisplay()` |
| Blocked flag when aura data is secret | Prevents Lua errors from secret-value indexing in restricted contexts | Medium | Set via `C_Secrets.ShouldUnitAuraInstanceBeSecret` check, or by detecting a failed field read; prevents map-rebuild and spellId reads in the handler |
| Clear blocked flag on PLAYER_REGEN_ENABLED | Re-enables aura checks after combat ends | Low | Register event in Core.lua; clear `ns.auraBlocked` flag |
| Clear blocked flag on ZONE_CHANGED_NEW_AREA | Re-enables after zone transitions (keystone ends, instance exits, area changes) | Low | Register event; clear flag; optionally trigger a fresh scan |
| isFullUpdate / nil updateInfo fallback | `updateInfo` can be nil or arrive with `isFullUpdate=true` — must handle gracefully | Medium | When triggered: scan all `activeTimers` via `GetPlayerAuraBySpellID`; cancel any where result is nil |

---

## Differentiators

Features that improve quality or robustness. Not blocking, but high value for correctness.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-aura secret guard (not blanket block) | More granular — non-secret auras still cancel timers even when some auras are secret in the same event | Medium | Use `C_Secrets.ShouldUnitAuraInstanceBeSecret("player", auraInstanceID)` per-aura before any field access. Pattern from Cell PR #457. Only needed if blanket blocked flag proves too conservative |
| Rebuild auraInstanceMap on PLAYER_ENTERING_WORLD | Handles login, reload, and instance entry where timers may have survived | Low | Iterate `activeTimers`; call `GetPlayerAuraBySpellID`; populate map. If result is nil, cancel the timer (buff didn't survive the zone) |
| Scan + cancel on ZONE_CHANGED_NEW_AREA | Clears timers for buffs stripped by zone transitions that don't fire UNIT_AURA | Low | Same scan as PLAYER_ENTERING_WORLD; guards against loading-screen removal edge case |
| Debug flag for blocked/unblocked state changes | Surfaces aura-blocking behavior during development without production spam | Low | `if ns.db.debugMode then print(...) end` gate in Core.lua |

---

## Anti-Features

Features to explicitly not build in this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Reading aura duration to update timer remaining | Duration field is secret in combat — defeats the entire secret-guarding strategy | Use only presence/absence detection; never read temporal fields from aura data |
| Auto-discovering new tracked spells from aura data | Scope creep per PROJECT.md — only cancel already-tracked buffs | New buff discovery is a future milestone |
| Tracking UNIT_AURA for units other than "player" | Party/target aura data is more restricted and irrelevant to TBT's use case | Filter `unit == "player"` in handler; reject all other units |
| Blanket block all UNIT_AURA processing when any aura is secret | Too aggressive — non-secret auras (out-of-combat buffs, whitelisted spells) can still cancel timers safely | Default: block only map rebuilds and spellId field reads; keep removedAuraInstanceIDs processing always-on since those IDs are never secret |
| Polling aura state on an OnUpdate tick | GC pressure and unnecessary work — UNIT_AURA is event-driven and sufficient | Stick to event-driven pattern; no per-frame polling |
| Updating expiresAt from aura expirationTime | Explicitly out of scope per PROJECT.md; field is secret in combat anyway | Only nil-out timers (cancellation); never mutate durations from aura data |

---

## Feature Dependencies

```
Register UNIT_AURA event (Core.lua)
  → isFullUpdate / nil updateInfo fallback scan
  → Blocked flag logic
      → PLAYER_REGEN_ENABLED clears flag
      → ZONE_CHANGED_NEW_AREA clears flag

PLAYER_ENTERING_WORLD (existing, Core.lua)
  → Rebuild spellID → auraInstanceID map (new)
      → Scan active timers: cancel any where buff is absent

OnSpellCastSucceeded (existing, BuffEngine.lua)
  → After setting ns.activeTimers[spellID]: call GetPlayerAuraBySpellID
      → Store result.auraInstanceID in ns.auraInstanceMap[spellID]

removedAuraInstanceIDs processing
  → Reverse-lookup: auraInstanceMap (spellID → instanceID, inverted) OR iterate map
      → ns.activeTimers[spellID] = nil
      → ns:UpdateDisplay() (existing)
```

**Dependency on existing BuffEngine:**
- `ns.activeTimers` is the sole cancellation target — already a simple keyed table by spellID
- `ns:UpdateDisplay()` already exists and handles nil timers correctly
- `ns:OnSpellCastSucceeded()` is the right hook for map population (fires at cast time before aura data becomes secret)
- `ns:GetActiveTimers()` already cleans expired entries via GetTime() — no change needed

**New state required:**
- `ns.auraInstanceMap` — table mapping `spellID → auraInstanceID` (populated at cast time and login)
- `ns.auraBlocked` — boolean flag; gates map-rebuild and spellId reads

---

## Edge Cases

### Buff Refresh (Same Spell Recasted Before Expiry)

When a tracked buff is refreshed, the UNIT_AURA event fires with the aura's instanceID in `updatedAuraInstanceIDs`, NOT in `removedAuraInstanceIDs`. The timer should not be cancelled. `OnSpellCastSucceeded` already fires on each cast and resets `expiresAt` — no additional aura logic needed.

**Risk:** Some buffs receive a new auraInstanceID on refresh; the old one appears in `removedAuraInstanceIDs` and a new one appears in `addedAuras` simultaneously. If the removal is processed before `UNIT_SPELLCAST_SUCCEEDED` fires, TBT would incorrectly cancel the timer and then immediately restart it on the cast event. The display flickers for one frame.

**Mitigation:** The cast event fires before the aura event in practice (cast completes, then server sends aura update). Accept the theoretical race; the timer will self-correct within the same frame cycle.

### Stacking Buffs (Multiple auraInstanceIDs Per SpellID)

Buffs like Maelstrom Weapon can have multiple simultaneous instances (one per stack), each with a distinct auraInstanceID. TBT tracks one timer per spellID. If one stack falls off (one auraInstanceID in `removedAuraInstanceIDs`) but the spell still has active stacks, TBT must NOT cancel the timer.

**Mitigation:** Store only the single instanceID captured at last cast time in `ns.auraInstanceMap[spellID]`. Only cancel when the removed instanceID matches the stored one. Other stacks have different instanceIDs that will not match. This works correctly for the "lust on wipe" case (all instances removed) and incorrectly only when the specific stored instance is the one that fell off but others remain — an edge case that results in a stale but harmless cosmetic timer.

### Buff Removal During Loading Screens / Zone Transitions

`UNIT_AURA` does not fire for buffs stripped during loading screens. Buffs can be silently removed with no event. TBT timers would continue running past the point where the buff existed.

**Mitigation (included as differentiator above):**
- On `PLAYER_ENTERING_WORLD`: scan all active timers via `GetPlayerAuraBySpellID`; cancel any that return nil (buff absent). This handles most zone-stripping cases.
- On `ZONE_CHANGED_NEW_AREA`: same scan.

**Limitation:** If aura data is itself restricted at the moment of the scan (unlikely at login but possible in some PvP zone entry scenarios), the scan silently skips cancellation. The timer runs to natural expiry.

### Buff Removal During Combat (Blocked State)

The blocked flag prevents aura-based cancellation in restricted contexts. Timers run to natural expiry if the buff falls off in combat (e.g., Bloodlust dispelled on a wipe). The timer shows stale data for the remainder of its configured duration.

This is the explicit design tradeoff: correctness in restricted contexts is sacrificed to prevent Lua errors. The alternative (unconstrained secret-value access) would produce addon errors in raid/keystone content — a far worse outcome.

### isFullUpdate = true

`updateInfo.isFullUpdate = true` signals a complete aura state reset with no incremental data. All incremental fields (`removedAuraInstanceIDs`, `addedAuras`, `updatedAuraInstanceIDs`) will be nil. TBT must perform a full scan of active timers via `GetPlayerAuraBySpellID` for each tracked spell, cancelling any where the result is nil. This also invalidates the stored auraInstanceMap entries — rebuild them from the full scan result.

### nil updateInfo

The second argument to the UNIT_AURA handler can be nil. This is equivalent to `isFullUpdate = true` for TBT's purposes. Guard: `if not updateInfo or updateInfo.isFullUpdate then`.

### Multiple Removals in One Event

`removedAuraInstanceIDs` is a table. Iterate the full table on every UNIT_AURA event, not just the first entry. Multiple buffs can be removed simultaneously (e.g., combat end strips all combat-only effects at once).

---

## MVP Recommendation

Implement in this order:

1. Register UNIT_AURA in Core.lua; route to a new `ns:OnUnitAura(unit, updateInfo)` in BuffEngine.lua
2. Add `ns.auraInstanceMap = {}` and `ns.auraBlocked = false` to Core.lua init
3. In `ns:OnSpellCastSucceeded`: after setting activeTimers entry, call `GetPlayerAuraBySpellID` and store `result.auraInstanceID` if non-secret
4. In `ns:OnUnitAura`: if blocked, return early. Handle nil/isFullUpdate with full scan. Process `removedAuraInstanceIDs` for matches.
5. Add blocked flag: test with `C_Secrets.ShouldUnitAuraInstanceBeSecret` on the first addedAura in the payload; if true, set flag and skip remainder
6. Register PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA in Core.lua; clear `ns.auraBlocked`; trigger full scan
7. On PLAYER_ENTERING_WORLD: rebuild map and scan for absent timers

**Defer:**
- Per-aura granular guards (differentiator): add only if blanket blocking proves too aggressive
- Debug logging flag: add after core logic is validated

---

## Confidence Assessment

| Claim | Confidence | Source |
|-------|------------|--------|
| `removedAuraInstanceIDs` is never secret | HIGH | Warcraft Wiki UNIT_AURA; Blizzard CooldownViewer.lua source |
| `GetPlayerAuraBySpellID` is SecretWhenUnitAuraRestricted | HIGH | Warcraft Wiki API docs; Blizzard forum thread |
| CDM uses spellID → auraInstanceID registry pattern | HIGH | CooldownViewer.lua and CooldownViewerItemData.lua in wow-ui-source |
| `C_Secrets.ShouldUnitAuraInstanceBeSecret` exists and is usable | HIGH | Warcraft Wiki; Cell PR #457 |
| isFullUpdate / nil updateInfo requires full scan | HIGH | Warcraft Wiki UNIT_AURA page |
| Buff refresh may produce new auraInstanceID (race condition) | MEDIUM | Inferred from addedAuras/removedAuraInstanceIDs docs; not explicitly stated |
| PLAYER_ENTERING_WORLD scan reliably catches zone-stripped buffs | MEDIUM | BuffActive addon pattern; depends on aura data being accessible at login |
| Stacking buff per-stack instanceID independence | MEDIUM | Inferred from UNIT_AURA documentation; behavior with multiple same-spell stacks not explicitly documented |
| Cast events fire before aura events (ordering) | LOW | Community convention; not guaranteed by WoW API contract |

---

## Sources

- [UNIT_AURA — Warcraft Wiki](https://warcraft.wiki.gg/wiki/UNIT_AURA)
- [C_Secrets.ShouldUnitAuraInstanceBeSecret — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_Secrets.ShouldUnitAuraInstanceBeSecret)
- [Patch 12.0.0/Planned API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes)
- [Patch 12.0.0/API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [How to Track Specific Buffs in Midnight — Spiritbloom.Pro](https://spiritbloom.pro/blog/tracking-buffs-in-midnight)
- [WoW 12.0.0 Midnight Compatibility PR — Cell addon (enderneko/Cell)](https://github.com/enderneko/Cell/pull/457)
- [oUF auras element — oUF-wow/oUF](https://github.com/oUF-wow/oUF/blob/master/elements/auras.lua)
- [Is there a secure/legal way to check player buffs in combat in 12.x — Blizzard Forums](https://us.forums.blizzard.com/en/wow/t/is-there-a-securelegal-way-to-check-specific-player-buffs-in-combat-in-12x/2246291)
- [Blizzard Continues to Loosen API Restrictions — Wowhead](https://wowhead.com/news/blizzard-continues-to-loosen-addon-api-restrictions-and-whitelist-select-spells-379691)
- Blizzard UI Source (local): `CooldownViewer.lua` — `OnUnitAura`, `auraInstanceIDToItemFramesMap` pattern
- Blizzard UI Source (local): `CooldownViewerItemData.lua` — `GetPlayerAuraBySpellID` usage at setup time
- Location: `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\`

---

*Supersedes: v0.2.0 feature research (CDM tab / Edit Mode / drag-and-drop)*
*Researched: 2026-04-03 for milestone v0.2.1*
