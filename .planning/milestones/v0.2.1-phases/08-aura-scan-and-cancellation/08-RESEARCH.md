# Phase 8: Aura Scan and Cancellation - Research

**Researched:** 2026-04-03
**Domain:** WoW Midnight aura scanning, active timer lifecycle management
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `ns:ScanActiveTimersForCancellation()` iterates `ns.activeTimers`, calls `GetPlayerAuraBySpellID(spellID)` for each, removes entries where the aura is absent.
- **D-02:** Batch all removals in one pass, call `ns:UpdateDisplay()` once at the end — not per-removal. Only call UpdateDisplay if at least one timer was cancelled.
- **D-03:** Debug logging shows a single summary line per scan: "Cancelled N timers: [list of labels]" — not per-timer individual lines.
- **D-04:** Only scan timers that were created from a cast (via `UNIT_SPELLCAST_SUCCEEDED`). Add an origin marker to timers created by `OnSpellCastSucceeded` (e.g., `source = "cast"`). The scan skips timers without this marker. This future-proofs for Phase 10 where lust timers start from debuff detection, not a cast.
- **D-05:** No grace period after cast. If `GetPlayerAuraBySpellID` returns nil and the timer was cast-originated, cancel immediately. Aura data is trustworthy when not blocked.

### Claude's Discretion

None specified in context.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

### Carried Forward Infrastructure (Phase 7 — already implemented)

- Debug toggle via `/tbt debug` (Phase 7 D-01)
- Preview guard: scan skips when `ns.previewActive` is true
- Blocked flag: scan unreachable when `ns.auraCheckBlocked` is true
- isFullUpdate suppression: scan unreachable on zone boundary events
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AURA-04 | When not blocked, addon scans active timers via GetPlayerAuraBySpellID and silently removes timers for buffs no longer present | D-01 through D-05 directly address this; guard chain from Phase 7 ensures scan only runs when aura data is trustworthy |
</phase_requirements>

---

## Summary

Phase 8 replaces the placeholder stub at `BuffEngine.lua:237` with a real `ScanActiveTimersForCancellation` function, and adds a `source = "cast"` field to timers created in `OnSpellCastSucceeded`. The Phase 7 guard chain is already in place and working — this phase slots the scan body into the slot those guards were protecting.

The implementation is small: one new function (~20 lines), one modified function (add `source = "cast"` to the timer table), and replacement of one placeholder comment with a function call. All scaffolding for blocked flag management, preview guards, and isFullUpdate suppression already exists.

The key behavioral contract: scan only runs for cast-originated timers (`source = "cast"`), cancels immediately (no grace period), batches all removals, and calls `UpdateDisplay` once at the end if anything changed. Debug output is a single summary line.

**Primary recommendation:** Add `source = "cast"` to the timer table in `OnSpellCastSucceeded`, implement `ScanActiveTimersForCancellation` with source-filter and batch logic, replace the Phase 8 placeholder comment with the call.

---

## Standard Stack

### Core APIs (no installation required — WoW Midnight built-ins)

| API | Version | Purpose | Why Standard |
|-----|---------|---------|--------------|
| `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` | Interface 120000 | Look up whether a spell's buff is currently on the player | Most direct API for per-spellID lookup; exactly how CDM's `FindLinkedSpellForCurrentAuras` works |
| `C_Secrets.ShouldAurasBeSecret()` | Interface 120000 | Gate check before any aura scan | Already wired in Phase 7 guard chain; blocks the entire scan path when true |
| `GetTime()` | WoW global | Timestamp comparison for timer expiry | Already used throughout BuffEngine.lua |

### Supporting Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `stylua` | Lua formatter | Run after every file edit per CLAUDE.md |
| `scripts/install.bat` | Deploy to WoW | Run after changes to test in-game |

---

## Architecture Patterns

### What Already Exists (Phase 7 infrastructure)

```lua
-- BuffEngine.lua — guard chain is in place at lines 212-241
function ns:OnUnitAura(updateInfo)
    if C_Secrets.ShouldAurasBeSecret() then ... return end   -- Guard 1: secret check
    if updateInfo and updateInfo.isFullUpdate then ... return end  -- Guard 2: suppress isFullUpdate
    if ns.previewActive then return end                       -- Guard 3: preview guard
    -- Phase 8 will add: ns:ScanActiveTimersForCancellation() -- <-- placeholder at line 237
end
```

The guard order is the safety contract. Phase 8 replaces the placeholder comment at line 237 with the actual call. The guards are NOT modified.

### New Function: ScanActiveTimersForCancellation

**What:** Iterates `ns.activeTimers`, queries each cast-originated timer via `GetPlayerAuraBySpellID`, nils out entries where the aura is absent. Calls `UpdateDisplay` once at end if anything was cancelled.

**Zero-allocation design:** No temp tables per call. Use a counter for cancelled count and accumulate the label list only when `ns.debugLogging` is true (string building is expensive, skip it otherwise).

```lua
-- Source: CONTEXT.md specifics + ARCHITECTURE.md pattern
function ns:ScanActiveTimersForCancellation()
    local cancelledCount = 0
    local cancelledLabels  -- only allocated when debug logging is on

    for spellID, timer in pairs(ns.activeTimers) do
        -- D-04: Only scan cast-originated timers
        if timer.source == "cast" then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if aura == nil then
                -- D-05: Cancel immediately, no grace period
                ns.activeTimers[spellID] = nil
                cancelledCount = cancelledCount + 1
                if ns.debugLogging then
                    if not cancelledLabels then
                        cancelledLabels = {}
                    end
                    table.insert(cancelledLabels, timer.label or tostring(spellID))
                end
            end
        end
    end

    -- D-02: Single UpdateDisplay call, only if something changed
    if cancelledCount > 0 then
        -- D-03: Single summary debug line
        if ns.debugLogging and cancelledLabels then
            print(
                "|cff00ccffTBT Debug|r: Cancelled "
                    .. cancelledCount
                    .. " timer(s): "
                    .. table.concat(cancelledLabels, ", ")
            )
        end
        if ns.UpdateDisplay then
            ns:UpdateDisplay()
        end
    end
end
```

### Modified: OnSpellCastSucceeded — add source marker

**Change:** Add `source = "cast"` to the timer table built at line 62-70.

```lua
-- BuffEngine.lua — OnSpellCastSucceeded (lines 52-75)
-- Current timer table (lines 62-70):
ns.activeTimers[spellID] = {
    spellID = spellID,
    expiresAt = now + entry.duration,
    startedAt = now,
    duration = entry.duration,
    icon = ns:GetSpellIcon(spellID),
    label = entry.label or ("Spell " .. spellID),
    section = entry.section or "bars",
    source = "cast",  -- <-- ADD THIS (D-04)
}
```

### Integration Point

Replace the placeholder comment at `BuffEngine.lua:237`:

```lua
-- BEFORE (line 237):
-- Phase 8 will add: ns:ScanActiveTimersForCancellation()
if ns.debugLogging then
    print("|cff00ccffTBT Debug|r: UNIT_AURA passed all guards — scan pending (Phase 8)")
end

-- AFTER:
ns:ScanActiveTimersForCancellation()
```

The existing debug print for "scan pending" is also removed — it was a placeholder log for Phase 7 testing only.

### Anti-Patterns to Avoid

- **Building debug strings outside the debug guard:** String concatenation in Lua allocates garbage. Only build the `cancelledLabels` table and call `table.concat` when `ns.debugLogging` is true.
- **Calling UpdateDisplay per-removal:** D-02 requires a single call at the end. Display rebuilds are expensive.
- **Scanning timers without `source = "cast"`:** Preview timers and future lust timers (Phase 10: `source = "debuff"`) must not be touched by this scan. The source filter is the future-proofing contract.
- **Modifying the Phase 7 guard chain:** The guards at lines 212-235 are the safety contract. Do not reorder or remove them.
- **Using `pairs` result order for debug output ordering:** `pairs` iteration order over a hash table is undefined in Lua. The label list will be in arbitrary order — that is acceptable for a debug summary line.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "Is this buff currently on the player?" | Custom aura slot iterator | `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` | Single API call per spell; handles all secret restrictions; same approach as CDM |
| "Is aura data trustworthy right now?" | Custom probe logic | `C_Secrets.ShouldAurasBeSecret()` | Authoritative flag; already in the Phase 7 guard chain |
| Display refresh after batch changes | Per-removal UpdateDisplay | Call once after the loop (D-02) | Display rebuild walks all active timers and redraws frames |

**Key insight:** The scan is inherently simple because Phase 7 built all the guards. Phase 8 is filling in one function body and one field addition — not building infrastructure.

---

## Common Pitfalls

### Pitfall 1: Debug string allocation in hot path

**What goes wrong:** Building `cancelledLabels` table and calling `table.concat` unconditionally creates garbage on every scan pass, even when nothing is cancelled and debug logging is off.

**Why it happens:** Lua string concatenation allocates new strings. `table.insert` on an unconditionally-created table also allocates.

**How to avoid:** Guard the label list creation with `if ns.debugLogging then`. Only allocate `cancelledLabels` inside the `if ns.debugLogging then` block. The counter (`cancelledCount`) is a plain integer — no allocation.

**Warning signs:** Per-frame GC pressure in combat if the scan fires frequently.

### Pitfall 2: Forgetting source filter removes ALL timers on first pass

**What goes wrong:** If `source = "cast"` is added to `OnSpellCastSucceeded` but existing live timers (created before Phase 8 is loaded in the same session) lack the field, those timers will not be scanned — which is safe (they expire naturally). But if the source filter condition is inverted or missing, ALL timers including preview and future lust timers will be scanned against aura data.

**Why it happens:** The filter is `if timer.source == "cast"` — timers without the field have `timer.source == nil`, which is not equal to `"cast"`, so they are skipped. This is correct.

**How to avoid:** The nil-safe behavior of Lua equality (`nil ~= "cast"`) provides the correct filter automatically. No explicit nil check needed.

**Warning signs:** Preview timers disappearing immediately on entering Edit Mode (would indicate the source filter is not working).

### Pitfall 3: Placeholder debug log not removed

**What goes wrong:** The Phase 7 placeholder debug print at the end of `OnUnitAura` ("scan pending (Phase 8)") fires on every `UNIT_AURA` event that passes the guards if it is not removed.

**Why it happens:** The print was added as a confirmation that the guard chain was working during Phase 7. It should be deleted when the actual scan call is inserted.

**Warning signs:** Chat spam of "TBT Debug: UNIT_AURA passed all guards — scan pending (Phase 8)" with debug logging on after Phase 8 is implemented.

### Pitfall 4: aura field name is spellId (lowercase d)

**What goes wrong:** `C_UnitAuras.GetPlayerAuraBySpellID` returns an `AuraData` table with `aura.spellId` (lowercase 'd'). Using `aura.spellID` (uppercase 'D') returns nil.

**Why it happens:** WoW's API is inconsistent — the function argument is `spellID` (uppercase D) but the returned field is `spellId` (lowercase d). This is confirmed in `CooldownViewerItemData.lua` line 13.

**How to avoid:** Phase 8 only checks `if aura == nil` — it does not read `aura.spellId`. So this pitfall does not apply to Phase 8 directly. Documenting for awareness in future phases (ZONE-01, LUST-01) that may read returned aura fields.

---

## Code Examples

### GetPlayerAuraBySpellID — CDM reference pattern

```lua
-- Source: wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua:13
-- CDM iterates linked spellIDs and checks each:
local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
if auraData then
    return spellID  -- aura is present and readable
end
-- nil means: aura absent OR aura is a secret value
```

### Existing timer removal pattern (ns:RemoveTrackedBuff)

```lua
-- Source: BuffEngine.lua:155
ns.activeTimers[spellID] = nil  -- direct nil assignment removes from hash table
```

### Existing debug logging pattern

```lua
-- Source: BuffEngine.lua:217-220
if ns.debugLogging then
    print("|cff00ccffTBT Debug|r: aura check blocked — ShouldAurasBeSecret() returned true")
end
```

### pairs iteration over activeTimers (existing pattern)

```lua
-- Source: BuffEngine.lua:82-88 (GetActiveTimers)
for spellID, timer in pairs(ns.activeTimers) do
    if timer.expiresAt <= now then
        ns.activeTimers[spellID] = nil  -- safe to nil during pairs iteration in Lua
    end
end
```

Note: Removing entries from a table during `pairs` iteration is safe in Lua — the Lua reference manual guarantees that assigning `nil` to a key being iterated does not invalidate the iterator.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UnitBuff(unit, index)` slot iteration | `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` direct lookup | Midnight (12.0) | No slot iteration needed; direct O(1) lookup per spell |
| `COMBAT_LOG_EVENT_UNFILTERED` for buff tracking | `UNIT_AURA` + `UNIT_SPELLCAST_SUCCEEDED` | Midnight (12.0) | CLEU disabled; must use aura events and cast events |

**Deprecated/outdated:**
- `UnitBuff` / `UnitDebuff` / `UnitAura(unit, index)`: Replaced by C_UnitAuras namespace; do not use.

---

## Open Questions

1. **`pairs` iteration removes during iteration — confirmed safe?**
   - What we know: Lua reference manual section 7.1 states that table modifications during `next`-based iteration (which `pairs` uses) are safe for the iterated table — setting existing keys to nil is explicitly permitted.
   - What's unclear: Nothing — this is a well-established Lua behavior, used by `GetActiveTimers` in the existing code already.
   - Recommendation: Safe to use. Confirmed by the existing `GetActiveTimers` pattern at lines 82-88.

2. **Blocker from STATE.md: cast/aura event ordering**
   - What we know: D-05 (no grace period) is a locked decision. UNIT_SPELLCAST_SUCCEEDED conventionally fires before UNIT_AURA for the resulting buff.
   - What's unclear: If UNIT_AURA fires first (atypical), the scan could see nil for a buff that was just cast and hasn't appeared in the aura list yet.
   - Recommendation: D-05 is locked. The Phase 7 guard chain already handles isFullUpdate suppression. The in-game test cases in the success criteria (SC-3: "Timer created immediately before isFullUpdate event not incorrectly cancelled") should catch ordering issues. Validate in-game after implementation.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 8 is code-only changes to existing Lua files. No external tools, services, runtimes, or CLIs are required beyond `stylua` (already in use) and WoW itself.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None — no automated test infrastructure exists for this Lua addon |
| Config file | None |
| Quick run command | Manual in-game test via `/tbt debug` and spell casts |
| Full suite command | Manual in-game validation per success criteria |

No automated test framework exists for WoW Lua addons in this project. All validation is manual in-game testing.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AURA-04 | Manually cancelled buff timer disappears from display | manual | `/tbt debug` + cancel buff | N/A |
| AURA-04 | Early-falling buff timer removed before natural expiry | manual | In-game — let buff fall off early | N/A |
| AURA-04 | Timer created just before isFullUpdate not incorrectly cancelled | manual | In-game zone transition while buff active | N/A |
| AURA-04 | Display refreshed exactly once per scan pass that cancels | manual | Debug logging — observe single "Cancelled N" line | N/A |

### Sampling Rate

- **Per task commit:** Deploy via `scripts/install.bat`, test in-game
- **Per wave merge:** Full success criteria walkthrough (all 4 SC items)
- **Phase gate:** All success criteria passing before `/gsd:verify-work`

### Wave 0 Gaps

None — no test infrastructure to create. All validation is manual in-game testing per the WoW addon domain.

---

## Project Constraints (from CLAUDE.md)

- `COMBAT_LOG_EVENT_UNFILTERED` is disabled in Midnight — do NOT use it
- Tracking buffs and debuffs is very limited; most values are hidden as "Secret Values"
- Secret Values may work in some contexts — guard these usages behind fail-safe calls when possible
- Spell IDs are often Secret Values themselves; the spellID from `UNIT_SPELLCAST_SUCCEEDED` is always safe
- Use `UNIT_SPELLCAST_SUCCEEDED` for cast detection (unchanged — Phase 8 adds to this path)
- Use `GetTime()` + known durations for timer tracking (unchanged)
- Run `stylua` on Lua files after finishing a task
- After every commit, run performance and code cleanup review
- Deploy with `./scripts/install.bat`

---

## Sources

### Primary (HIGH confidence)

- `wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua` — `GetPlayerAuraBySpellID` usage pattern, `aura.spellId` field name confirmed at line 13
- `wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua` — `C_UnitAuras.GetPlayerAuraBySpellID` signature, `SecretWhenUnitAuraRestricted`, `RequiresNonSecretAura` flags
- `wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitConstantsDocumentation.lua` — `UnitAuraUpdateInfo` structure, `NeverSecretContents`/`ConditionalSecretContents` field annotations
- `BuffEngine.lua` (current) — guard chain (lines 212-249), timer table structure (lines 62-70), `ns.previewActive` confirmed at line 3, `ns.activeTimers` nil-removal pattern (line 84)
- `Core.lua` (current) — event registration (lines 6-10), routing (lines 93-107), all Phase 7 events wired
- `.planning/research/STACK.md` — comprehensive API reference for all aura APIs
- `.planning/research/ARCHITECTURE.md` — data flow diagram and integration point analysis

### Secondary (MEDIUM confidence)

- `.planning/phases/08-aura-scan-and-cancellation/08-CONTEXT.md` — all decisions (D-01 through D-05) locked by user discussion

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against local wow-ui-source
- Architecture: HIGH — Phase 7 scaffold already in repo; Phase 8 integration points are explicit stubs
- Pitfalls: HIGH — sourced from existing code patterns and Lua language spec

**Research date:** 2026-04-03
**Valid until:** Stable — WoW Midnight APIs do not change between patches at this level
