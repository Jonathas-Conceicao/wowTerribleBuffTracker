# Phase 7: Safety Infrastructure - Research

**Researched:** 2026-04-04
**Domain:** WoW Midnight addon — UNIT_AURA event guards, secret value detection, blocked flag lifecycle, preview mode protection, debug toggle
**Confidence:** HIGH — all API findings verified against local Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Add a `/tbt debug` toggle that enables verbose logging of aura blocking state changes (blocked/unblocked), scan results, and secret value detection. Silent by default. Store debug flag as runtime-only (not persisted to SavedVariables).
- **D-02:** Add `ns.previewActive` boolean flag. Set to `true` in `StartAllPreviewTimers`, cleared in `ClearAllTimers`. Aura scan must skip entirely when this flag is true — preview timers must remain visible regardless of real aura state.
- **D-04:** `ns.auraCheckBlocked` set to `true` when `C_Secrets.ShouldAurasBeSecret()` returns true. Cleared on `PLAYER_REGEN_ENABLED` (combat drop) and `ZONE_CHANGED_NEW_AREA`. On next `UNIT_AURA` event after clear, re-check `ShouldAurasBeSecret()` — in M+ this re-blocks immediately since auras stay secret between pulls.
- **D-05:** When `isFullUpdate` is true in the UNIT_AURA payload, suppress any cancellation logic to prevent false cancellations from temporarily empty aura lists on zone boundaries.

### Claude's Discretion

- **D-03:** Choose between extending the existing `eventFrame` in Core.lua or creating a separate aura-focused frame in BuffEngine.lua. Decision should follow whichever pattern keeps the code cleanest given the 3 new events (UNIT_AURA, PLAYER_REGEN_ENABLED, ZONE_CHANGED_NEW_AREA) plus making PLAYER_ENTERING_WORLD persistent instead of one-shot.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AURA-01 | Addon registers UNIT_AURA (player-filtered via RegisterUnitEvent) to monitor buff presence | RegisterUnitEvent("UNIT_AURA", "player") confirmed in STACK.md and Blizzard source; single-unit scoping prevents raid/party noise |
| AURA-02 | Addon checks C_Secrets.ShouldAurasBeSecret() and sets a blocked flag when aura data is secret | C_Secrets.ShouldAurasBeSecret() is the authoritative gate; SecretPredicateAPIDocumentation.lua confirms it returns true when aura queries produce secret values |
| AURA-03 | Blocked flag clears on PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA; re-checks ShouldAurasBeSecret() on next UNIT_AURA | Both events documented with no payload; re-check on next UNIT_AURA event naturally handles re-blocking in M+ |
| ZONE-02 | isFullUpdate events are suppressed to prevent false cancellations from empty aura lists on zone boundaries | D-05 locks this: suppress all cancellation when isFullUpdate is true; this phase wires the guard but defers actual scan logic to Phase 8 |
</phase_requirements>

---

## Summary

Phase 7 wires all prerequisite guards that must exist before aura scan logic (Phase 8) is written. The work is entirely in Core.lua and BuffEngine.lua — no other files change. The guards are: (1) UNIT_AURA registered via `RegisterUnitEvent` for "player" only; (2) `ns.auraCheckBlocked` flag initialized, set via `C_Secrets.ShouldAurasBeSecret()`, and cleared on the two reset events; (3) `isFullUpdate` suppression so zone transitions cannot cause false cancellations; (4) `ns.previewActive` flag wired into `StartAllPreviewTimers` and `ClearAllTimers`; (5) `/tbt debug` toggle for verbose runtime logging.

The critical design tension in this phase is the `PLAYER_REGEN_ENABLED` question. CONTEXT.md decision D-04 explicitly includes it as a clear trigger. STATE.md (roadmap notes) says to omit it because it fires between M+ pulls, causing re-block immediately after clear. These are contradictory. **D-04 in CONTEXT.md is the authoritative locked decision** (gathered 2026-04-04 in direct discussion). The behavior described in D-04 is actually self-consistent: clear on `PLAYER_REGEN_ENABLED`, and if auras are still secret, the very next `UNIT_AURA` event re-blocks immediately — no harm, no spurious cancellation. The concern in STATE.md is addressed by the re-block-on-next-event design.

The phase produces working guard infrastructure with an inert scan stub (the handler exists and guards run, but no actual timer cancellation logic is written — that is Phase 8).

**Primary recommendation:** Extend the existing `eventFrame` in Core.lua (D-03 discretion) — it is the established event routing pattern, adding three new events and converting `PLAYER_ENTERING_WORLD` from one-shot to persistent costs zero complexity and avoids a second frame.

---

## Standard Stack

### Core APIs

| API | Source | Purpose | Notes |
|-----|--------|---------|-------|
| `frame:RegisterUnitEvent("UNIT_AURA", "player")` | BuffFrame.lua, CooldownViewer.lua | Player-only UNIT_AURA delivery | Do NOT use RegisterEvent — fires for all units |
| `C_Secrets.ShouldAurasBeSecret()` | SecretPredicateAPIDocumentation.lua | Global aura restriction check | No args, no SecretArguments restriction; call before any aura scan |
| `issecretvalue(value)` | FrameScriptDocumentation.lua | Per-value secret check | Belt-and-suspenders inside scan loops; not the primary gate |
| `frame:RegisterEvent("PLAYER_REGEN_ENABLED")` | UnitDocumentation.lua | Combat drop signal | No payload |
| `frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")` | MapDocumentation.lua | Zone transition signal | No payload |

### Event Payload Reference

```lua
-- UNIT_AURA payload:
local unit, updateInfo = ...
-- updateInfo.isFullUpdate           = bool (always present, default false)
-- updateInfo.removedAuraInstanceIDs = table<number>|nil  (NeverSecretContents)
-- updateInfo.addedAuras             = table<AuraData>|nil (ConditionalSecretContents)
-- updateInfo.updatedAuraInstanceIDs = table<number>|nil  (NeverSecretContents)
```

### What NOT to Use

| Avoid | Use Instead | Reason |
|-------|-------------|--------|
| `RegisterEvent("UNIT_AURA")` | `RegisterUnitEvent("UNIT_AURA", "player")` | Fires for all units; raid/party noise |
| `UnitBuff` / `UnitDebuff` / `UnitAura` by index | `C_UnitAuras.GetPlayerAuraBySpellID` | Deprecated pre-Midnight |
| Reading `auraData.spellId` without `issecretvalue()` guard | Guard first | Throws Lua error in M+/PvP/encounter contexts |

---

## Architecture Patterns

### Recommended Project Structure (no change)

Phase 7 adds no new files. All changes are in existing files:

```
Core.lua        — event registration + routing (3 new events, PLAYER_ENTERING_WORLD persistent)
BuffEngine.lua  — guard flags, handler stubs, debug toggle, preview flag
```

### Pattern 1: Extending eventFrame (D-03 Recommendation)

**What:** Add three new events to the existing `eventFrame` in Core.lua rather than creating a separate frame in BuffEngine.lua.

**When to use:** The existing `eventFrame` already handles `UNIT_SPELLCAST_SUCCEEDED`. All event routing in TBT flows through a single frame and dispatches to `ns:` methods. Staying in this pattern keeps the event handler as a thin router and the logic in BuffEngine.

**Core.lua additions:**

```lua
-- Source: Core.lua existing pattern + STACK.md confirmed
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")   -- AURA-01: player-only
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")       -- AURA-03: blocked flag clear
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")      -- AURA-03: blocked flag clear
-- PLAYER_ENTERING_WORLD: remove self:UnregisterEvent("PLAYER_ENTERING_WORLD") at line 90
```

**Handler additions in OnEvent:**

```lua
elseif event == "UNIT_AURA" then
    local unit, updateInfo = ...
    -- unit check is redundant with RegisterUnitEvent but is a safe guard
    if unit == "player" then
        ns:OnUnitAura(updateInfo)
    end
elseif event == "PLAYER_REGEN_ENABLED" then
    ns:ClearAuraBlock()
elseif event == "ZONE_CHANGED_NEW_AREA" then
    ns:ClearAuraBlock()
elseif event == "PLAYER_ENTERING_WORLD" then
    -- existing display init logic stays, but no longer unregisters
    -- the event so it fires on every load screen (for future ZONE-01)
    if not ns.displayInitialized then
        ns.displayInitialized = true
        ns:InitEditModeFrames()
        ns:InitDisplay()
    end
    -- No self:UnregisterEvent here — must stay registered for future phases
```

### Pattern 2: auraCheckBlocked Flag Lifecycle

**What:** Runtime boolean on `ns`. Set when `C_Secrets.ShouldAurasBeSecret()` returns true. Cleared on reset events. Re-checked on every `UNIT_AURA` — if auras become secret again (M+ pull starts), it re-blocks immediately on the next event.

**Initialization in BuffEngine.lua:**

```lua
-- Source: ARCHITECTURE.md confirmed pattern
-- At module scope or in ns:InitBuffEngine()
ns.auraCheckBlocked = false
ns.previewActive = false   -- D-02
ns.debugLogging = false    -- D-01 runtime-only, not in DB
```

**OnUnitAura stub (Phase 7 scope — no scan logic yet):**

```lua
-- Source: STACK.md recommended flow
function ns:OnUnitAura(updateInfo)
    -- AURA-02: Check secret restriction first
    if C_Secrets.ShouldAurasBeSecret() then
        if not ns.auraCheckBlocked then
            ns.auraCheckBlocked = true
            if ns.debugLogging then
                print("|cff00ccffTBT Debug|r: auraCheckBlocked = true (ShouldAurasBeSecret)")
            end
        end
        return
    end

    -- ZONE-02: Suppress cancellation on full updates (zone boundary safety)
    if updateInfo and updateInfo.isFullUpdate then
        if ns.debugLogging then
            print("|cff00ccffTBT Debug|r: UNIT_AURA isFullUpdate — suppressing cancellation")
        end
        return  -- Phase 8 will handle full-update rescans
    end

    -- D-02: Skip when preview is active
    if ns.previewActive then
        return
    end

    -- Phase 8 will add: ns:ScanActiveTimersForCancellation()
end

function ns:ClearAuraBlock()
    -- Source: ARCHITECTURE.md + STACK.md — Blizzard's AuraUtil.lua uses same events
    if ns.auraCheckBlocked then
        ns.auraCheckBlocked = false
        if ns.debugLogging then
            print("|cff00ccffTBT Debug|r: auraCheckBlocked = false (reset event)")
        end
    end
end
```

### Pattern 3: Preview Mode Flag (D-02)

**What:** `ns.previewActive` set/cleared in the two existing BuffEngine functions.

```lua
-- Source: BuffEngine.lua lines 177, 198

function ns:StartAllPreviewTimers()
    ns.previewActive = true   -- ADD: D-02 guard
    local now = GetTime()
    ns.activeTimers = {}
    -- ... existing loop unchanged ...
    if ns.UpdateDisplay then ns:UpdateDisplay() end
end

function ns:ClearAllTimers()
    ns.previewActive = false  -- ADD: D-02 guard
    ns.activeTimers = {}
    if ns.UpdateDisplay then ns:UpdateDisplay() end
end
```

### Pattern 4: Debug Toggle (D-01)

**What:** `/tbt debug` subcommand toggles `ns.debugLogging`. Not persisted.

The existing slash command handler in Core.lua calls `ns:SelectTBTTab()` unconditionally. This must be extended to parse subcommands.

```lua
-- Source: Core.lua lines 99-103 — existing pattern to extend
SlashCmdList["TERRIBLEBUFFTRACKER"] = function(msg)
    local cmd = msg and msg:lower():match("^(%S+)") or ""
    if cmd == "debug" then
        ns.debugLogging = not ns.debugLogging
        local state = ns.debugLogging and "|cff00ff00ON|r" or "|cffff6600OFF|r"
        print("|cff00ccffTBT|r: Debug logging " .. state)
    else
        ns:SelectTBTTab()
    end
end
```

### Anti-Patterns to Avoid

- **Registering PLAYER_ENTERING_WORLD and unregistering it:** Line 90 of Core.lua currently unregisters PLAYER_ENTERING_WORLD after the first fire. This must be removed in Phase 7 so the event continues to fire (needed for Phase 9 ZONE-01 and for future reload/login safety).
- **Calling UpdateDisplay from OnUnitAura in Phase 7:** The Phase 7 stub should not trigger UpdateDisplay — there is nothing to cancel yet. Adding it prematurely causes a display refresh on every buff event with no timer changes.
- **Storing debugLogging in SavedVariables:** D-01 explicitly prohibits persistence. It resets to false on every login/reload — intentional.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Aura restriction detection | Custom nil-return heuristics | `C_Secrets.ShouldAurasBeSecret()` | The authoritative API; no heuristics needed |
| Per-value secret check | Custom type inspection | `issecretvalue(value)` | Blizzard global; handles all secret value types |
| Unit-scoped event filtering | Manual `if unit == "player"` after `RegisterEvent` | `RegisterUnitEvent("UNIT_AURA", "player")` | Fewer events delivered; kernel-level filter |

**Key insight:** Every custom guard TBT needs already has an exact Blizzard API equivalent. This phase is entirely about wiring the right APIs in the right order.

---

## Common Pitfalls

### Pitfall 1: PLAYER_REGEN_ENABLED vs. STATE.md Conflict

**What goes wrong:** STATE.md (roadmap notes) says to omit `PLAYER_REGEN_ENABLED` as an unblock trigger because it fires between M+ pulls and causes immediate re-block. CONTEXT.md D-04 explicitly includes it.

**Resolution:** CONTEXT.md D-04 is the locked decision. The behavior is safe: clear on `PLAYER_REGEN_ENABLED`, and if auras are still secret (M+ active), the very next `UNIT_AURA` re-blocks immediately. No timer is ever incorrectly cancelled — the re-block happens before any scan runs. This is the correct design.

**Warning sign:** If implementing without `PLAYER_REGEN_ENABLED`, a timer created in a raid encounter would stay blocked for the entire raid even after combat drops.

### Pitfall 2: Leaving PLAYER_ENTERING_WORLD as One-Shot

**What goes wrong:** Core.lua line 90 has `self:UnregisterEvent("PLAYER_ENTERING_WORLD")`. If this is not removed, the event never fires after the initial load, and Phase 9's ZONE-01 zone transition scan will never trigger.

**Prevention:** Remove the `UnregisterEvent` call. Guard the display init block with `if not ns.displayInitialized then` (already present) to prevent re-initialization on subsequent fires.

**Warning sign:** After a `/reload` or loading screen, `PLAYER_ENTERING_WORLD` does not appear in debug logs.

### Pitfall 3: isFullUpdate Suppression Scope

**What goes wrong:** D-05 says to suppress cancellation logic on `isFullUpdate = true`. Phase 7 has no cancellation logic yet. The guard must be written correctly for Phase 8 to inherit — if the guard is placed in the wrong location (e.g., after the preview check instead of before), Phase 8 could inadvertently run scans during zone transitions.

**Prevention:** Order guards in `ns:OnUnitAura` as: (1) secret check → block and return, (2) isFullUpdate → return (ZONE-02), (3) preview active → return (D-02), (4) [Phase 8 scan logic here]. This ordering ensures zone boundary safety gates before any execution path that touches timers.

**Warning sign:** Timers disappear on every zone transition after Phase 8 is implemented.

### Pitfall 4: ns.previewActive Flag Not Confirmed in Source

**What goes wrong:** ARCHITECTURE.md notes `ns.previewActive` is "implied" but not confirmed in the existing source. Reading BuffEngine.lua lines 177-203 confirms: `StartAllPreviewTimers` and `ClearAllTimers` exist but do NOT currently set any preview flag.

**Resolution (confirmed by reading source):** `ns.previewActive` does NOT exist today. Phase 7 must add it. This is not a blocker — it is a new flag to initialize and wire, which is exactly what Phase 7 does.

### Pitfall 5: Secret Value Comparison Lua Error

**What goes wrong:** If Phase 8 scan code accidentally compares `auraData.spellId` without an `issecretvalue()` guard, a Lua error fires in M+/PvP (not in open world, making it hard to catch in casual testing). Phase 7's `ns.auraCheckBlocked` gate prevents Phase 8 scan code from running when auras are secret — this is the primary defense.

**Relevance to Phase 7:** The blocked flag must be set BEFORE any scan path is reached. The order of checks in `OnUnitAura` is the critical safety property this phase must get right.

---

## Code Examples

### Complete OnUnitAura Stub (Phase 7)

```lua
-- Source: STACK.md recommended flow + D-04/D-05 from CONTEXT.md
function ns:OnUnitAura(updateInfo)
    -- AURA-02: Gate on secret restriction
    if C_Secrets.ShouldAurasBeSecret() then
        if not ns.auraCheckBlocked then
            ns.auraCheckBlocked = true
            if ns.debugLogging then
                print("|cff00ccffTBT Debug|r: aura check blocked — ShouldAurasBeSecret() returned true")
            end
        end
        return
    end

    -- ZONE-02: Suppress on full update (zone boundary / loading screen transient)
    if updateInfo and updateInfo.isFullUpdate then
        if ns.debugLogging then
            print("|cff00ccffTBT Debug|r: UNIT_AURA isFullUpdate suppressed")
        end
        return
    end

    -- D-02: Skip while preview timers are active
    if ns.previewActive then
        return
    end

    -- Phase 8 will add scan logic here
    if ns.debugLogging then
        print("|cff00ccffTBT Debug|r: UNIT_AURA passed all guards — scan pending (Phase 8)")
    end
end
```

### ClearAuraBlock

```lua
-- Source: ARCHITECTURE.md + AuraUtil.lua PLAYER_REGEN_ENABLED pattern
function ns:ClearAuraBlock()
    local wasBlocked = ns.auraCheckBlocked
    ns.auraCheckBlocked = false
    if ns.debugLogging and wasBlocked then
        print("|cff00ccffTBT Debug|r: aura check unblocked")
    end
end
```

### Flag Initialization (BuffEngine.lua module scope)

```lua
-- Runtime-only flags — NOT in TerribleBuffTrackerDB
ns.auraCheckBlocked = false
ns.previewActive    = false
ns.debugLogging     = false
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UnitBuff(unit, index)` slot iteration | `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` | Midnight (12.0) | Direct spell lookup; no slot enumeration needed |
| Manual nil-check for "buff absent" | `C_Secrets.ShouldAurasBeSecret()` + `issecretvalue()` | Midnight (12.0) | Distinguish "absent" from "secret" reliably |
| `RegisterEvent("UNIT_AURA")` (all units) | `RegisterUnitEvent("UNIT_AURA", "player")` | Before Midnight | Kernel-level filter; fewer events |

**Deprecated / removed in Midnight:**
- `UnitBuff`, `UnitDebuff`, `UnitAura(unit, index, filter)` — all deprecated, replaced by `C_UnitAuras` namespace
- `COMBAT_LOG_EVENT_UNFILTERED` — disabled entirely (CLAUDE.md constraint)

---

## Open Questions

1. **PLAYER_ENTERING_WORLD persistent registration side effects**
   - What we know: Removing `self:UnregisterEvent("PLAYER_ENTERING_WORLD")` makes the event fire on every login, reload, and loading screen completion. The init guard (`if not ns.displayInitialized`) prevents double-init.
   - What's unclear: Whether any other code path assumes PLAYER_ENTERING_WORLD is one-shot.
   - Recommendation: Scan Core.lua and BuffEngine.lua for any code that depends on PLAYER_ENTERING_WORLD being one-shot before removing the unregister. A search for `displayInitialized` references is sufficient.

2. **ns.auraCheckBlocked initial state on reload mid-combat/M+**
   - What we know: The flag is runtime-only. On reload, it resets to false regardless of the game state.
   - What's unclear: After a `/reload` in an active M+ key, the first UNIT_AURA fires and `ShouldAurasBeSecret()` returns true → block is immediately re-set. This produces one "unblocked → blocked" state transition per reload. No timer is cancelled (block is set before any scan). No error. This is acceptable.
   - Recommendation: Document this behavior in a code comment; it is intentional.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 7 is code-only changes. No external tools, services, CLIs, databases, or runtimes beyond the existing WoW addon environment are required. `stylua` is already installed at `~/.cargo/bin/stylua` per CLAUDE.md.

---

## Validation Architecture

Phase 7 guard logic cannot be unit tested in isolation (all APIs are WoW runtime-only). Validation is manual in-game testing.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual in-game validation |
| Config file | none |
| Quick run command | `/reload` + test scenario |
| Full suite command | All scenarios below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Command | Automated? |
|--------|----------|-----------|---------|-----------|
| AURA-01 | UNIT_AURA fires only for "player" unit | manual | Cast a buff; observe debug log shows exactly one UNIT_AURA line | No — WoW runtime |
| AURA-02 | Blocked flag set when ShouldAurasBeSecret returns true | manual | Enter M+ or arena; `/tbt debug`; cast tracked buff; observe "blocked" message | No — requires live content |
| AURA-03 | Blocked flag clears on PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA | manual | Leave combat; observe "unblocked" in debug log | No — WoW runtime |
| ZONE-02 | isFullUpdate suppresses cancellation | manual | Zone change with active timer; verify timer survives zone transition | No — WoW runtime |

### Sampling Rate

- **Per task commit:** Visual inspection — no in-game test required for flag initialization and slash command changes
- **Per wave merge:** Full manual scenario run in open world + reload
- **Phase gate:** All 4 requirements verified in-game before Phase 8 begins

### Wave 0 Gaps

None — no test framework setup required. This phase ships guard stubs that are verified manually.

---

## Project Constraints (from CLAUDE.md)

| Constraint | Impact on This Phase |
|------------|---------------------|
| `COMBAT_LOG_EVENT_UNFILTERED` is disabled | Not relevant to Phase 7 (no CLEU usage) |
| Use `UNIT_SPELLCAST_SUCCEEDED` for cast detection | Unchanged; Phase 7 adds UNIT_AURA alongside it |
| Secret Values may work in some contexts — guard with fail-safe calls | `C_Secrets.ShouldAurasBeSecret()` is the fail-safe gate; `issecretvalue()` is the belt-and-suspenders per-value guard |
| Requires Blizzard's CDM — no standalone fallback | Not relevant to Phase 7 (no CDM interaction) |
| Always run `stylua` after editing Lua files | Required after every task in this phase |
| Always run `install.bat` after changes | Required after every task to deploy for in-game testing |
| Active timers are runtime-only (not persisted) | `ns.auraCheckBlocked`, `ns.previewActive`, `ns.debugLogging` all runtime-only — correct |
| Reusable module-level tables wiped with `wipe()` each cycle | Not applicable to Phase 7 (no new hot-path tables introduced) |

---

## Sources

### Primary (HIGH confidence)

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_APIDocumentationGenerated\SecretPredicateAPIDocumentation.lua` — `C_Secrets.ShouldAurasBeSecret()` signature and documentation string
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_APIDocumentationGenerated\UnitConstantsDocumentation.lua` — `UnitAuraUpdateInfo` structure, `isFullUpdate`, `NeverSecretContents` / `ConditionalSecretContents` field annotations
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_APIDocumentationGenerated\UnitAuraDocumentation.lua` — `C_UnitAuras` function signatures and secret annotations
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_FrameXMLUtil\AuraUtil.lua` (lines 341-348) — `PLAYER_REGEN_ENABLED` used as cache-dump trigger; confirms this event as the canonical combat-exit unblock point
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_BuffFrame\BuffFrame.lua` — `RegisterUnitEvent("UNIT_AURA", "player")` registration pattern
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewer.lua` — `UNIT_AURA` handler pattern, `removedAuraInstanceIDs` access
- `.planning/research/STACK.md` — complete API reference for UNIT_AURA, C_Secrets, reset events (all verified against Blizzard source)
- `.planning/research/ARCHITECTURE.md` — integration points, data flow, new/modified function list
- `.planning/research/PITFALLS.md` — secret value edge cases, isFullUpdate behavior, race conditions
- `TerribleBuffTracker/Core.lua` — confirmed current event registration, PLAYER_ENTERING_WORLD one-shot pattern (line 90), slash command structure
- `TerribleBuffTracker/BuffEngine.lua` — confirmed StartAllPreviewTimers (line 177), ClearAllTimers (line 198) — no previewActive flag present currently

### Secondary (MEDIUM confidence)

- `.planning/phases/07-safety-infrastructure/07-CONTEXT.md` — locked decisions D-01 through D-05 from user discussion

---

## Metadata

**Confidence breakdown:**
- Event registration: HIGH — verified in Blizzard source (BuffFrame.lua, CooldownViewer.lua)
- C_Secrets API: HIGH — verified in SecretPredicateAPIDocumentation.lua
- Reset event triggers: HIGH — AuraUtil.lua uses identical pattern for PLAYER_REGEN_ENABLED
- isFullUpdate suppression: HIGH — UnitConstantsDocumentation.lua field semantics confirmed
- Preview flag absence in current code: HIGH — read BuffEngine.lua directly
- D-03 recommendation (extend eventFrame): MEDIUM — pattern reasoning from existing code; no authoritative source mandates it

**Research date:** 2026-04-04
**Valid until:** Stable — WoW Midnight API changes require verification; event names and C_Secrets API are stable once shipped in 12.0

---

*Phase: 07-safety-infrastructure*
*Research completed: 2026-04-04*
