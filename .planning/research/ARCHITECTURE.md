# Architecture Research: Aura-Based Timer Cancellation

**Milestone:** v0.2.1 — UNIT_AURA_UPDATE integration for timer cancellation
**Researched:** 2026-04-03
**Confidence:** HIGH (sourced directly from Blizzard UI source at C:\Users\jonat\Repositories\wow-ui-source)

---

## Question

How should `UNIT_AURA` handling integrate with the existing `BuffEngine.lua` timer system? Where should the blocked-flag state live? How should the aura scan interact with active timers keyed by `spellID`? What is the data flow from event to check to cancel?

---

## API Facts (Verified from wow-ui-source)

### Event: `UNIT_AURA`

Documented name is `UNIT_AURA`, not `UNIT_AURA_UPDATE`. Payload:

```lua
-- event == "UNIT_AURA"
local unitTarget, updateInfo = ...
-- unitTarget: UnitTokenVariant — "player", "target", etc.
-- updateInfo: UnitAuraUpdateInfo table
```

`UnitAuraUpdateInfo` fields (from `UnitConstantsDocumentation.lua`):

```lua
{
    isFullUpdate            = bool,              -- always present, default false
    removedAuraInstanceIDs  = table<number>|nil, -- NeverSecretContents = true
    addedAuras              = table<AuraData>|nil,-- ConditionalSecretContents = true
    updatedAuraInstanceIDs  = table<number>|nil, -- NeverSecretContents = true
}
```

**Critical secret value semantics:**
- `removedAuraInstanceIDs` — `NeverSecretContents = true`. Removal IDs are ALWAYS available regardless of aura secrecy. This is the reliable channel.
- `addedAuras` — `ConditionalSecretContents = true`. May be nil or contain nil entries for secret auras. Cannot be relied on.
- `updatedAuraInstanceIDs` — `NeverSecretContents = true`. Reliable.
- `isFullUpdate = true` — fired when the runtime cannot send incremental changes (e.g. zone transitions, entering combat in some cases). Must trigger a full rescan.

### Direct Lookup: `C_UnitAuras.GetPlayerAuraBySpellID(spellID)`

- `SecretWhenUnitAuraRestricted = true`, `RequiresNonSecretAura = true`
- Returns `AuraData|nil`
- Returns `nil` for secret auras even when the aura IS active on the player
- This is how "blocked" detection works: call it for a tracked spellID we just cast — if `nil` when we know the buff is active, the aura data is restricted

`AuraData` has a `spellId` field (lowercase `d` confirmed in `CooldownViewerItemData.lua` line 229).

### Direct Lookup: `C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)`

- Same secret restrictions as `GetPlayerAuraBySpellID`
- For "player" unit, use `GetPlayerAuraBySpellID` (simpler, no unit arg)

---

## Secret Value Detection Strategy

The Blizzard documentation marks many aura APIs as `SecretWhenUnitAuraRestricted`. The restriction means the function returns `nil` even when the aura exists. This is the "Secret Value" scenario described in CLAUDE.md.

**Detection approach (fail-safe guard):**

When `UNIT_AURA` fires for `"player"` and we have an active timer for a tracked buff:
1. Call `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` for a buff we know was recently cast
2. If it returns `nil` AND the timer is not expired, the aura is likely secret → set blocked flag
3. If it returns a valid `AuraData`, aura checks are working → proceed

The blocked flag is conservative: it means "I cannot trust `nil` results from the aura API." It does NOT mean `UNIT_AURA` itself is unreliable — only that the data inside it may be hidden.

**Reset triggers:** `PLAYER_REGEN_ENABLED` (out of combat) and `ZONE_CHANGED_NEW_AREA`. These are the two states where Blizzard's own code (e.g. `AuraUtil.lua` line 344-347) dumps its own caches, and are when aura data often becomes readable again.

---

## Where the Blocked Flag Lives

**Answer: `BuffEngine.lua`, on the namespace (`ns`), as a runtime-only flag.**

Rationale:
- It is purely runtime state — not persisted (active timers are already runtime-only per CLAUDE.md)
- `BuffEngine.lua` owns all timer logic and is the natural owner of "can I trust aura data right now?"
- `Core.lua` routes events and should remain thin — logic belongs in `BuffEngine`
- The flag does not touch `TerribleBuffTrackerDB` — no migration needed

```lua
-- Runtime-only, initialized in ns:InitBuffEngine() or at module scope
ns.auraCheckBlocked = false
```

---

## Data Flow: Event → Check → Cancel

```
UNIT_AURA fires (Core.lua event handler)
    │
    ├── unit ~= "player" → return (ignore non-player events)
    │
    ▼
ns:OnUnitAura(updateInfo)        [NEW function in BuffEngine.lua]
    │
    ├── updateInfo == nil         → full rescan path
    ├── updateInfo.isFullUpdate   → full rescan path
    │
    │   INCREMENTAL PATH:
    ├── updateInfo.removedAuraInstanceIDs present?
    │       → These are safe (NeverSecretContents)
    │       → But we track by spellID not auraInstanceID
    │       → Cannot use removal IDs directly (no spellID→instanceID map)
    │       → Fall through to scan path
    │
    └── Scan path: for each active timer spellID
            → C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            → nil result: check if blocked before cancelling
```

**The aura instance ID mismatch:** TBT tracks active timers keyed by `spellID`. The `removedAuraInstanceIDs` field provides instance IDs, not spell IDs. Maintaining a reverse map from `auraInstanceID → spellID` would require tracking `addedAuras` (which is secret-conditional). This reverse map approach is fragile. The simpler and more correct approach is to scan by spellID directly via `GetPlayerAuraBySpellID` on every relevant event.

**Full scan logic:**

```lua
function ns:ScanActiveTimersForCancellation()
    if ns.auraCheckBlocked then
        return
    end

    local cancelledAny = false
    for spellID, _ in pairs(ns.activeTimers) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura == nil then
            -- Aura not present: check if this might be a secret value
            -- If we haven't confirmed aura data is readable, skip
            -- (blocked flag should have been set already if secret)
            ns.activeTimers[spellID] = nil
            cancelledAny = true
        end
    end

    if cancelledAny and ns.UpdateDisplay then
        ns:UpdateDisplay()
    end
end
```

**Blocked flag setting:**

The safest time to probe for secret values is immediately after `OnSpellCastSucceeded` creates a timer. At that point we know the buff was just cast, so if `GetPlayerAuraBySpellID` returns nil, it's a secret value.

```lua
-- In ns:OnSpellCastSucceeded, after creating the timer:
-- Probe immediately to detect secret value restriction
local probe = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
if probe == nil then
    -- The aura exists (we just cast it) but is hidden: blocked
    ns.auraCheckBlocked = true
end
```

This is a fail-safe: if the probe succeeds (aura is readable), blocked stays false and cancellation logic proceeds normally. If the probe fails, blocked is set and all UNIT_AURA scans are skipped until a reset event fires.

---

## Integration Points with BuffEngine.lua

### New Functions

| Function | Location | Purpose |
|----------|----------|---------|
| `ns:OnUnitAura(updateInfo)` | `BuffEngine.lua` | Handles `UNIT_AURA` event, routes to scan or no-op based on blocked flag |
| `ns:ScanActiveTimersForCancellation()` | `BuffEngine.lua` | Iterates `ns.activeTimers`, calls `GetPlayerAuraBySpellID` per spellID, cancels missing ones |
| `ns:ClearAuraBlock()` | `BuffEngine.lua` | Resets `ns.auraCheckBlocked = false`, called from `Core.lua` on reset events |

### Modified Functions

| Function | Change |
|----------|--------|
| `ns:OnSpellCastSucceeded(spellID)` | After timer creation, probe `GetPlayerAuraBySpellID` to detect secret value; set `ns.auraCheckBlocked = true` if nil |
| (none in `GetActiveTimers`) | No change — expiry cleanup is independent of aura logic |

### Unchanged

- `ns.activeTimers` — still a flat table keyed by `spellID`, no new fields needed
- `ns:RemoveTrackedBuff` — already does `ns.activeTimers[spellID] = nil`; cancellation reuses the same nil-assignment pattern
- `ns:GetActiveTimers` — still the consumer for display; no change needed
- All DB structures — no persistence, no migration

---

## Core.lua Changes

### New Event Registrations

```lua
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
```

### New Event Handler Cases

```lua
elseif event == "UNIT_AURA" then
    local unit, updateInfo = ...
    if unit == "player" then
        ns:OnUnitAura(updateInfo)
    end
elseif event == "PLAYER_REGEN_ENABLED" then
    ns:ClearAuraBlock()
elseif event == "ZONE_CHANGED_NEW_AREA" then
    ns:ClearAuraBlock()
```

### No Other Core.lua Changes

The existing `UNIT_SPELLCAST_SUCCEEDED` path is untouched. Slash command, DB init, display init — all unchanged.

---

## New vs. Modified Files Summary

| File | Status | What Changes |
|------|--------|--------------|
| `Core.lua` | MODIFIED | Register 3 new events (`UNIT_AURA`, `PLAYER_REGEN_ENABLED`, `ZONE_CHANGED_NEW_AREA`); add 3 handler cases; no structural changes |
| `BuffEngine.lua` | MODIFIED | Add `ns.auraCheckBlocked = false` init; add `ns:OnUnitAura(updateInfo)`, `ns:ScanActiveTimersForCancellation()`, `ns:ClearAuraBlock()`; modify `ns:OnSpellCastSucceeded` to probe for secret values |
| All other files | UNCHANGED | Display, CDMTab, EditModeFrames, TOC — no changes needed |

---

## Full Data Flow Diagram

```
UNIT_SPELLCAST_SUCCEEDED (spellID)
    ↓
ns:OnSpellCastSucceeded(spellID)        [BuffEngine.lua — existing]
    → create ns.activeTimers[spellID]
    → probe C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    → if nil: ns.auraCheckBlocked = true
    → ns:UpdateDisplay()

UNIT_AURA (unit, updateInfo)
    ↓
Core.lua: if unit == "player" → ns:OnUnitAura(updateInfo)
    ↓
ns:OnUnitAura(updateInfo)               [BuffEngine.lua — NEW]
    ├── if ns.auraCheckBlocked → return (skip entirely)
    ├── if updateInfo == nil OR isFullUpdate → ns:ScanActiveTimersForCancellation()
    └── else → ns:ScanActiveTimersForCancellation()
              (scan always: incremental removal IDs map to instanceID not spellID)

ns:ScanActiveTimersForCancellation()    [BuffEngine.lua — NEW]
    → for spellID in activeTimers:
        → aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        → if aura == nil: activeTimers[spellID] = nil
    → if any cancelled: ns:UpdateDisplay()

PLAYER_REGEN_ENABLED / ZONE_CHANGED_NEW_AREA
    ↓
Core.lua → ns:ClearAuraBlock()
    → ns.auraCheckBlocked = false
    → (next UNIT_AURA will attempt scan again)
```

---

## Edge Cases

### Timer expires naturally before aura fires

`ns:GetActiveTimers()` already cleans up expired timers on every call (`timer.expiresAt <= now → nil`). Aura cancellation fires first if the buff is removed early; expiry cleanup handles the normal path. No conflict.

### Buff cast while blocked

The timer is created normally. The block suppresses aura cancellation, not timer creation. On next reset event, the block clears; subsequent `UNIT_AURA` events will then scan and cancel any timers whose buffs are no longer present.

### Multiple active timers, some secret, some not

`ns.auraCheckBlocked` is a global flag. If ANY tracked buff is secret, all cancellation is blocked. This is conservative but correct — better to let timers expire naturally than to incorrectly cancel visible ones due to a misidentified secret value nil.

Alternative design (per-spellID blocked map) is more precise but adds complexity for limited gain. The single flag is the right starting point.

### `isFullUpdate` with blocked flag

If `ns.auraCheckBlocked` is true, `isFullUpdate` is still ignored. The block means the aura API is unreliable, so a "full rescan" is also unreliable. Reset events are the only safe unblock mechanism.

### Preview mode

`ns:StartAllPreviewTimers()` creates fake timers for all non-hidden entries. These will be scanned by `ScanActiveTimersForCancellation`. In preview mode the real auras are likely not active, so `GetPlayerAuraBySpellID` returns nil for them, and preview timers get cancelled.

**Mitigation:** Add a `ns.previewActive` guard (already implied by how preview works — it sets `ns.activeTimers = {}` then populates all). The simplest fix is: do not register `UNIT_AURA` handling during preview, or check `ns.previewActive` in `ScanActiveTimersForCancellation` and return early.

```lua
function ns:ScanActiveTimersForCancellation()
    if ns.auraCheckBlocked then return end
    if ns.previewActive then return end  -- guard preview mode
    -- ...
end
```

`ns.previewActive` needs to be set in `StartAllPreviewTimers()` and cleared in `ClearAllTimers()`.

---

## Confidence Assessment

| Claim | Confidence | Source |
|-------|------------|--------|
| Event name is `UNIT_AURA` not `UNIT_AURA_UPDATE` | HIGH | `UnitAuraDocumentation.lua` LiteralName field |
| `removedAuraInstanceIDs` is always visible (not secret) | HIGH | `NeverSecretContents = true` in `UnitConstantsDocumentation.lua` |
| `addedAuras` may be nil/hidden for secret auras | HIGH | `ConditionalSecretContents = true` |
| `GetPlayerAuraBySpellID` returns nil for secret auras | HIGH | `SecretWhenUnitAuraRestricted = true`, `RequiresNonSecretAura = true` in `UnitAuraDocumentation.lua` |
| `isFullUpdate` requires full rescan | HIGH | Used this way in BuffFrame.lua, NamePlateAuras.lua, TargetFrame.lua |
| `PLAYER_REGEN_ENABLED` as unblock trigger | HIGH | `AuraUtil.lua` uses it to dump aura caches (lines 344-347) |
| Probing immediately after cast detects secret values | MEDIUM | Logical — we know the buff exists at that moment; nil = secret |
| Preview mode needs guard | MEDIUM | Inferred from `StartAllPreviewTimers` creating artificial timers; confirm during implementation |

---

## Sources

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_APIDocumentationGenerated\UnitAuraDocumentation.lua` — `UNIT_AURA` event payload, all `C_UnitAuras` function signatures and secret annotations (HIGH)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_APIDocumentationGenerated\UnitConstantsDocumentation.lua` — `UnitAuraUpdateInfo` structure, `NeverSecretContents` / `ConditionalSecretContents` field annotations (HIGH)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewer.lua` — `OnUnitAura` handler using `removedAuraInstanceIDs`, `updatedAuraInstanceIDs`, `addedAuras` (HIGH)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerItemData.lua` — `GetPlayerAuraBySpellID` call pattern, `aura.spellId` field name (HIGH)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_FrameXMLUtil\AuraUtil.lua` — `ForEachAura` scan pattern, `PLAYER_REGEN_ENABLED`/`PLAYER_REGEN_DISABLED` used to dump caches (HIGH)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_BuffFrame\BuffFrame.lua` — `isFullUpdate` handling pattern (HIGH)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_NamePlates\Blizzard_NamePlateAuras.lua` — `isFullUpdate` → full rescan pattern (HIGH)
- Existing `BuffEngine.lua` and `Core.lua` — confirmed `ns.activeTimers` structure, event routing pattern, namespace convention (HIGH)

---

*Architecture research for: TerribleBuffTracker v0.2.1 — Aura-Based Timer Cancellation*
*Researched: 2026-04-03*
