# Phase 8: Aura Scan and Cancellation - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement the scan function that checks active timers against real aura data and silently removes timers for buffs no longer present. This replaces the Phase 8 placeholder stub in `ns:OnUnitAura`.

</domain>

<decisions>
## Implementation Decisions

### Scan Behavior
- **D-01:** `ns:ScanActiveTimersForCancellation()` iterates `ns.activeTimers`, calls `GetPlayerAuraBySpellID(spellID)` for each, removes entries where the aura is absent.
- **D-02:** Batch all removals in one pass, call `ns:UpdateDisplay()` once at the end — not per-removal. Only call UpdateDisplay if at least one timer was cancelled.
- **D-03:** Debug logging shows a single summary line per scan: "Cancelled N timers: [list of labels]" — not per-timer individual lines.

### Edge Case Handling
- **D-04:** Only scan timers that were created from a cast (via `UNIT_SPELLCAST_SUCCEEDED`). Add an origin marker to timers created by `OnSpellCastSucceeded` (e.g., `source = "cast"`). The scan skips timers without this marker. This future-proofs for Phase 10 where lust timers start from debuff detection, not a cast.
- **D-05:** No grace period after cast. If `GetPlayerAuraBySpellID` returns nil and the timer was cast-originated, cancel immediately. Aura data is trustworthy when not blocked.

### Carried Forward (Phase 7 — already implemented)
- Debug toggle via `/tbt debug` (D-01 from Phase 7)
- Preview guard: scan skips when `ns.previewActive` is true
- Blocked flag: scan unreachable when `ns.auraCheckBlocked` is true
- isFullUpdate suppression: scan unreachable on zone boundary events

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 7 Infrastructure (read to understand guard order)
- `BuffEngine.lua` lines 212-249 — OnUnitAura stub with guard chain, scan placeholder at line 237
- `Core.lua` lines 8-9, 91-107 — Event registration and routing

### WoW API
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerItemData.lua` — CDM's GetPlayerAuraBySpellID usage pattern, aura.spellId (lowercase d)

### Project Research
- `.planning/research/STACK.md` — GetPlayerAuraBySpellID signature, return type
- `.planning/research/ARCHITECTURE.md` — Integration data flow

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns.activeTimers` (keyed by spellID) — direct iteration target for scan
- `ns:GetActiveTimers()` — existing cleanup pattern (removes expired timers, same nil-and-remove approach)
- `ns:UpdateDisplay()` — existing display refresh call

### Established Patterns
- Timer removal: `ns.activeTimers[spellID] = nil` (used in GetActiveTimers, SetBuffSection)
- Timer creation in `OnSpellCastSucceeded`: builds timer table with spellID, expiresAt, startedAt, duration, icon, label, section
- Debug logging: `if ns.debugLogging then print("|cff00ccffTBT Debug|r: ...") end`

### Integration Points
- `BuffEngine.lua:237` — Replace placeholder comment with `ns:ScanActiveTimersForCancellation()` call
- `BuffEngine.lua:57-68` — `OnSpellCastSucceeded` timer creation — add `source = "cast"` field
- New function `ns:ScanActiveTimersForCancellation()` added to BuffEngine.lua

</code_context>

<specifics>
## Specific Ideas

- The scan function should be zero-allocation in the hot path (no temp tables per call) — use a counter variable for cancelled count, build debug message only when logging is enabled
- Timer origin marker `source = "cast"` on timers from OnSpellCastSucceeded enables Phase 10 to use `source = "debuff"` for lust timers without false cancellation

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-aura-scan-and-cancellation*
*Context gathered: 2026-04-04*
