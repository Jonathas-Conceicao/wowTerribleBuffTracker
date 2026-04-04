# Project Research Summary

**Project:** TerribleBuffTracker v0.2.1 — Aura-Based Timer Cancellation
**Domain:** WoW Midnight (Interface 120000+) addon — event-driven aura monitoring with secret value constraints
**Researched:** 2026-04-03
**Confidence:** HIGH (all core API facts verified against local Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`)

## Executive Summary

TerribleBuffTracker v0.2.1 adds one targeted mechanism: silently cancel active timers when tracked buffs are no longer present. The existing system uses `UNIT_SPELLCAST_SUCCEEDED` + `GetTime()` to start timers manually. This milestone adds `UNIT_AURA` handling to stop them early — covering real-world cases like Bloodlust cancelled on a wipe, trinket procs falling off, dispels, and manual buff cancellations. The change touches only `Core.lua` (three new event registrations) and `BuffEngine.lua` (three new functions, one modified function). No other files change.

The dominant constraint shaping the entire implementation is WoW Midnight's secret value system. In restricted contexts (Mythic+, rated PvP, active raid encounters), aura field values — including `spellId`, `duration`, and `expirationTime` — become opaque and cannot be compared or indexed by addon code without throwing a Lua error. The reliable path, confirmed directly in Blizzard's own CDM source (`CooldownViewer.lua`, `CooldownViewerItemData.lua`), is to scan active timers using `C_UnitAuras.GetPlayerAuraBySpellID` per spell ID, gated behind `C_Secrets.ShouldAurasBeSecret()` to prevent errors when data is restricted. The `removedAuraInstanceIDs` field in the `UNIT_AURA` payload is always safe (tagged `NeverSecretContents`) but requires a `spellID → auraInstanceID` reverse map to be useful — a map that itself depends on reading `addedAuras` (which is secret-conditional). For TBT's scale (5–15 tracked buffs), a full per-spell-ID scan on every relevant `UNIT_AURA` event is simpler, equally correct, and avoids all cache-staleness risk.

The top implementation risk is the cast/aura race condition: `UNIT_AURA` can fire before the newly applied aura appears in the aura list, which would cause the scan to immediately cancel the timer just created by `UNIT_SPELLCAST_SUCCEEDED`. This must be addressed with a short grace period (`ns.recentlyCast[spellID] = GetTime() + 0.5`) before any other cancellation logic is written. A secondary risk is the blocked-flag reset trigger: `PLAYER_REGEN_ENABLED` is NOT correct for Mythic+ (aura restrictions persist between pulls in the same key), and `ZONE_CHANGED_NEW_AREA` is the right zone-exit signal. These two guard systems must be in place before the scan function is written.

## Key Findings

### Recommended Stack

All v0.2.1 APIs are native WoW Midnight Lua — no new libraries or dependencies. The implementation uses `RegisterUnitEvent("UNIT_AURA", "player")` (not `RegisterEvent`) to restrict delivery to player-unit changes only, eliminating unnecessary event traffic in group content. Secret detection uses `C_Secrets.ShouldAurasBeSecret()` as the up-front global gate and `issecretvalue()` as a per-value belt-and-suspenders fallback inside scan loops.

**Core APIs (all verified in `wow-ui-source`):**
- `frame:RegisterUnitEvent("UNIT_AURA", "player")` — unit-scoped registration; fires only for player aura changes, not party/raid/target/nameplates
- `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` — primary lookup; `SecretWhenUnitAuraRestricted = true`, `RequiresNonSecretAura = true`; returns `AuraData|nil`; nil when aura is absent OR when it exists but is secret
- `C_Secrets.ShouldAurasBeSecret()` — authoritative gate check; no arguments; zero cost when aura scan will be skipped; call before any scan
- `issecretvalue(value)` — global Lua function; per-value runtime guard; use inside scan loops as belt-and-suspenders after the gate check passes
- `PLAYER_REGEN_ENABLED` — clears blocked flag for raid encounter contexts only (fires on every combat drop, including between M+ pulls — see Pitfalls)
- `ZONE_CHANGED_NEW_AREA` — clears blocked flag on zone/instance exits; correct trigger for M+ and rated PvP exit
- `PLAYER_ENTERING_WORLD` — full state reset on login/reload; triggers rebuild of aura instance map and post-load scan

**Critical field name:** `auraData.spellId` (lowercase `d`), not `spellID`. Confirmed in `CooldownViewerItemData.lua`. A mismatched name produces a silent nil lookup — no runtime error — making it hard to detect during casual testing.

**Deprecated APIs to avoid:** `UnitBuff`, `UnitDebuff`, `UnitAura` (all replaced by `C_UnitAuras.*` in Midnight).

### Expected Features

The milestone is narrowly scoped to cancellation only. All table-stakes features are required; differentiators improve correctness edge cases.

**Must have (table stakes):**
- Register `UNIT_AURA` for "player" unit — no event, no cancellation
- Handle `isFullUpdate = true` and nil `updateInfo` with a full scan fallback
- Cancel timers when `GetPlayerAuraBySpellID` returns nil for a tracked spell ID, unless blocked or in grace period
- Set and maintain blocked flag via `C_Secrets.ShouldAurasBeSecret()` when aura data is restricted
- Clear blocked flag on `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD`
- On `PLAYER_ENTERING_WORLD`: scan all active timers and cancel any where the buff is absent

**Should have (correctness differentiators):**
- Grace period (`ns.recentlyCast[spellID] = GetTime() + 0.5`) to absorb the cast/aura event ordering race
- `ns.previewActive` guard in `ScanActiveTimersForCancellation` to prevent preview mode timers from being immediately cancelled
- Filter scan to only `ns.activeTimers` entries (not all `ns.db.trackedBuffs`) — skips hidden-section buffs with no active timer

**Defer (out of scope per PROJECT.md):**
- Reading `expirationTime` to update timer remaining — field is secret in combat, duration sync is a future milestone
- Auto-discovering new tracked spells from aura data — future milestone
- Per-aura granular secret guards (`ShouldUnitAuraInstanceBeSecret` per instance) — add only if blanket `ShouldAurasBeSecret()` proves too conservative in practice
- `spellID → auraInstanceID` reverse map optimization — add only if profiling shows the full scan is expensive (unlikely at 5–15 buffs)

**Confirmed anti-features:** Never poll on `OnUpdate`. Never read `addedAuras` field values for cancellation logic (secret-conditional). Never update `expiresAt` from aura data. Never call `GetAuraDataByAuraInstanceID` to confirm a removal (returns nil for removed auras by design, causing ambiguity).

### Architecture Approach

Only two files change. `Core.lua` registers three new events and adds three handler dispatch cases. `BuffEngine.lua` gains three new functions and one modification. All other files — `Display.lua`, `EditModeFrames.lua`, `CDMTab.lua`, `CDMTab.xml` — are untouched.

**Modified components:**
1. `Core.lua` — adds `RegisterUnitEvent("UNIT_AURA", "player")`, `RegisterEvent("PLAYER_REGEN_ENABLED")` (optional — see gaps), `RegisterEvent("ZONE_CHANGED_NEW_AREA")`; routes to `ns:OnUnitAura`, `ns:ClearAuraBlock`
2. `BuffEngine.lua` — adds `ns.auraCheckBlocked = false` and `ns.recentlyCast = {}` as runtime-only state; new functions `OnUnitAura`, `ScanActiveTimersForCancellation`, `ClearAuraBlock`; modifies `OnSpellCastSucceeded` to set grace period and probe for secret values after creating a timer

**New runtime state (not persisted):**
- `ns.auraCheckBlocked` — boolean; gates all aura scans; set when `ShouldAurasBeSecret()` returns true or when a post-cast probe returns nil for a known-active buff
- `ns.recentlyCast` — table of `spellID → GetTime() + 0.5`; prevents scan from cancelling a timer in the window immediately after a cast

**Architecture conflict resolved:** FEATURES.md recommends building a `spellID → auraInstanceID` reverse map (CDM's pattern) and consuming `removedAuraInstanceIDs` directly. ARCHITECTURE.md recommends a simpler full scan per event, noting that populating the reverse map requires reading `addedAuras` (secret-conditional) and introduces cache-staleness on `isFullUpdate`. Resolution: implement the full scan approach. At TBT's scale the difference is negligible, and the simpler design eliminates Pitfalls 7 and 8 entirely.

**Data flow:**
```
UNIT_SPELLCAST_SUCCEEDED
  → OnSpellCastSucceeded (existing) → create timer → set recentlyCast[spellID]
                                                    → probe GetPlayerAuraBySpellID
                                                    → if nil: auraCheckBlocked = true

UNIT_AURA (unit == "player")
  → OnUnitAura(updateInfo)
      → if auraCheckBlocked: return
      → if not updateInfo or isFullUpdate: ScanActiveTimersForCancellation()
      → else: ScanActiveTimersForCancellation()
              (incremental removedAuraInstanceIDs can't map to spellID without reverse map)

ScanActiveTimersForCancellation()
  → if auraCheckBlocked or previewActive: return
  → for spellID in activeTimers:
      → if recentlyCast[spellID] still valid: skip
      → aura = GetPlayerAuraBySpellID(spellID)
      → if nil: activeTimers[spellID] = nil; cancelledAny = true
  → if cancelledAny: UpdateDisplay()

PLAYER_REGEN_ENABLED / ZONE_CHANGED_NEW_AREA / PLAYER_ENTERING_WORLD
  → ClearAuraBlock() → auraCheckBlocked = false
  → (PLAYER_ENTERING_WORLD additionally triggers ScanActiveTimersForCancellation)
```

### Critical Pitfalls

1. **Cast/aura race condition** — `UNIT_AURA` fires before the newly applied aura appears in the list, immediately cancelling the timer just created by `UNIT_SPELLCAST_SUCCEEDED`. Symptom: timer flickers in then immediately disappears after casting. Prevention: set `ns.recentlyCast[spellID] = GetTime() + 0.5` in `OnSpellCastSucceeded`; skip cancellation for any spell within its grace window. Must be wired before the scan function is written.

2. **Wrong blocked-flag reset trigger** — `PLAYER_REGEN_ENABLED` fires between pulls in M+, but aura restrictions persist for the entire key run. Resetting the block on combat drop allows the next `UNIT_AURA` event to error in a between-pull lull. Symptom: intermittent Lua errors during M+ after `/reload` or between bosses. Prevention: use `ZONE_CHANGED_NEW_AREA` as the primary unblock trigger; `PLAYER_ENTERING_WORLD` for reload/login. Omit or use `PLAYER_REGEN_ENABLED` only for encounter-only scenarios after testing confirms M+ behavior.

3. **Secret value Lua error in scan** — Comparing or indexing `auraData.spellId` in a restricted context throws `"attempt to compare a Secret Value"`, aborting the event handler and generating console spam on every subsequent `UNIT_AURA`. Prevention: call `C_Secrets.ShouldAurasBeSecret()` before any scan; add `issecretvalue()` guards around individual field reads as belt-and-suspenders.

4. **`isFullUpdate` zone-transition false cancellations** — `UNIT_AURA` fires with `isFullUpdate = true` during loading screens while the player's aura list is transiently empty. A naive "scan all, cancel anything missing" wipes all active timers on every zone change. Symptom: timers disappear every time the player enters a dungeon or crosses a zone boundary. Prevention: do not treat `isFullUpdate` as a cancellation signal on its own; always check `recentlyCast` and `auraCheckBlocked` guards; consider suppressing cancellation within a window after `PLAYER_ENTERING_WORLD`.

5. **Preview mode timer cancellation** — `StartAllPreviewTimers` populates `ns.activeTimers` with fake entries for all non-hidden buffs. The aura scan immediately cancels these because the real auras are not active. Prevention: add `if ns.previewActive then return end` at the top of `ScanActiveTimersForCancellation`; set/clear `ns.previewActive` in `StartAllPreviewTimers` and `ClearAllTimers`.

6. **`RegisterEvent("UNIT_AURA")` without unit filter** — fires for every unit (party members, nameplates, focus target), generating unnecessary event traffic in group content. Prevention: use `RegisterUnitEvent("UNIT_AURA", "player")` exclusively. Non-negotiable from the start.

## Implications for Roadmap

The feature dependencies and pitfall relationships impose a strict implementation ordering: the safety infrastructure (grace period, blocked flag, correct reset triggers) must exist before the cancellation scan is written. Writing the scan first and adding guards later creates a window where M+/PvP behavior is incorrect. All four phases below follow this constraint.

### Phase 1: Safety Infrastructure

**Rationale:** The grace period and blocked flag are prerequisites for correct scan behavior. These are pure state declarations and event registrations — low risk, no WoW API calls — and they define the contract that all subsequent code depends on.

**Delivers:** `ns.auraCheckBlocked = false` and `ns.recentlyCast = {}` initialized in `BuffEngine.lua`; `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD` (extended) registered in `Core.lua` and routed to `ns:ClearAuraBlock()`; grace period set in `OnSpellCastSucceeded` after each timer creation; `ns.previewActive` flag established in `StartAllPreviewTimers` and `ClearAllTimers`.

**Addresses:** Table-stakes: blocked flag, event registrations, flag-clear events.
**Avoids:** Pitfalls 2 (wrong reset trigger), 3 (secret value error), 5 (preview mode cancellation), 6 (unfiltered event registration).

### Phase 2: UNIT_AURA Handler and Scan

**Rationale:** With all guards in place, the handler and scan can be written knowing every guard condition is already wired. The full-scan approach is chosen over the reverse-map approach for simplicity and absence of cache-staleness risk.

**Delivers:** `ns:OnUnitAura(updateInfo)` in `BuffEngine.lua` routing nil/`isFullUpdate`/incremental paths to scan; `ns:ScanActiveTimersForCancellation()` checking `auraCheckBlocked`, `recentlyCast`, and `previewActive` before scanning; `UpdateDisplay()` called only when timers are actually cancelled; Core.lua dispatch for `UNIT_AURA`.

**Addresses:** Table-stakes: core cancellation, `isFullUpdate` fallback, scan-based removal detection.
**Avoids:** Pitfalls 1 (cast/aura race — grace period check), 4 (`isFullUpdate` false cancellations — guards), 5 (preview), 6 (unit filter in Core.lua dispatch).

### Phase 3: Login and Zone-Transition Scan

**Rationale:** `UNIT_AURA` does not fire for buffs stripped during loading screens. Timers for buffs silently removed during a zone transition continue running without this phase.

**Delivers:** `PLAYER_ENTERING_WORLD` handler that calls `ScanActiveTimersForCancellation` after clearing the blocked flag; `ZONE_CHANGED_NEW_AREA` handler that also triggers a scan after clearing the flag. Both reuse the existing scan function from Phase 2.

**Addresses:** Differentiator: post-login scan; scan on zone change.
**Avoids:** Pitfall 4 (`isFullUpdate` during zone transitions — this scan is explicitly triggered by `PLAYER_ENTERING_WORLD`, not by `isFullUpdate` itself).

### Phase 4: Cleanup and Validation

**Rationale:** GSD workflow mandates a cleanup phase at milestone end. The secret value system also requires in-game validation in restricted contexts before shipping.

**Delivers:** `stylua` run on all modified files; hot-path review of `ScanActiveTimersForCancellation` (no table allocations per call; `wipe()` on `recentlyCast` entries past their expiry); confirm `UpdateDisplay` is not called twice per cast event; confirm `recentlyCast` entries are cleaned up and do not grow unbounded; dead code removal; changelog entry.

**Addresses:** GSD cleanup requirement; integration risks from PITFALLS.md (double `UpdateDisplay` call, `recentlyCast` table growth).

### Phase Ordering Rationale

- Phase 1 before Phase 2: safety guards are prerequisites, not afterthoughts. A scan written without them will misbehave in restricted content from its first event.
- Phase 3 after Phase 2: the login/zone scan reuses `ScanActiveTimersForCancellation`; that function must exist first.
- Phase 4 always last: cleanup requires a complete implementation to audit.
- The `spellID → auraInstanceID` reverse map optimization is deferred. It adds Pitfalls 7 and 8 (stale cache, `GetAuraDataByAuraInstanceID` ambiguity) for a performance gain irrelevant at 5–15 tracked buffs. Add only if in-game profiling reveals a problem.

### Research Flags

All phases have well-documented patterns from Blizzard source. No phase requires additional research before implementation:

- **Phase 1:** Event names, function signatures, and flag semantics all confirmed in `wow-ui-source` with HIGH confidence. `ns.previewActive` flag existence needs verification in current `BuffEngine.lua` during implementation.
- **Phase 2:** `GetPlayerAuraBySpellID` behavior, `updateInfo` field access, and `ShouldAurasBeSecret()` all confirmed. The full-scan approach mirrors patterns in `BuffFrame.lua` and `NamePlateAuras.lua`.
- **Phase 3:** `PLAYER_ENTERING_WORLD` post-load scan pattern confirmed in multiple Blizzard addons.
- **Phase 4:** Standard cleanup; no research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All API names, signatures, and secret annotations verified against local `wow-ui-source`; `spellId` (lowercase d) confirmed in `CooldownViewerItemData.lua` |
| Features | HIGH | Table-stakes list verified against Blizzard's CDM implementation; anti-features explicitly excluded per PROJECT.md scope; edge cases documented with confidence levels |
| Architecture | HIGH | Two-file change scope confirmed; data flow verified against existing `BuffEngine.lua` structure; FEATURES/ARCHITECTURE conflict resolved in favor of simpler full-scan approach |
| Pitfalls | HIGH | Aura pitfalls sourced from Blizzard UI source + Cell PR #457 + official Blizzard forum post; all 10 pitfalls have specific prevention strategies |

**Overall confidence:** HIGH

### Gaps to Address

- **Cast/aura event ordering is convention, not contract (LOW confidence):** The claim that `UNIT_SPELLCAST_SUCCEEDED` fires before `UNIT_AURA` within the same server tick is community convention, not guaranteed by the WoW API contract. The 0.5s grace period absorbs this, but the grace window may need tuning for instant-application buffs. Validate in-game before closing the milestone.

- **M+ restriction onset timing (MEDIUM confidence):** Research confirms aura data becomes secret "when M+ is active" but does not specify the exact moment during key start when the restriction activates relative to the first `UNIT_AURA` event. The post-cast probe detection covers this conservatively, but the exact transition is unconfirmed.

- **`PLAYER_REGEN_ENABLED` inclusion decision:** Research is split. STACK.md includes it as a reset trigger; PITFALLS.md (Pitfall 5) argues it incorrectly unblocks during M+ between-pull lulls. Recommended resolution: omit `PLAYER_REGEN_ENABLED`; use only `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD`. Revisit if testing reveals encounter-only scenarios where the block persists incorrectly after a raid wipe reset.

- **`ns.previewActive` flag existence:** ARCHITECTURE.md notes this guard is "implied" by how preview mode works. Confirm during Phase 1 that `StartAllPreviewTimers` and `ClearAllTimers` in `BuffEngine.lua` can be extended to set/clear this flag without side effects.

## Sources

### Primary (HIGH confidence — verified in `wow-ui-source`)

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua` — `UNIT_AURA` payload, `C_UnitAuras` signatures, `SecretWhenUnitAuraRestricted` and `RequiresNonSecretAura` flags
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitConstantsDocumentation.lua` — `UnitAuraUpdateInfo` struct; `NeverSecretContents` on `removedAuraInstanceIDs`; `ConditionalSecretContents` on `addedAuras`
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua` — `C_Secrets.ShouldAurasBeSecret()` signature and documentation string
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua` — `issecretvalue()` global function
- `Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua` — `AuraUtil.ForEachAura`, `AuraUtil.AuraFilters`, `PLAYER_REGEN_ENABLED` cache dump pattern
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` — `RegisterUnitEvent("UNIT_AURA", "player")`, `OnUnitAura` handler, `auraInstanceIDToItemFramesMap` pattern, `removedAuraInstanceIDs` consumption
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua` — `GetPlayerAuraBySpellID` at setup time; `aura.spellId` field name (lowercase `d`)
- `Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua` — `isFullUpdate` handling pattern, `RegisterUnitEvent("UNIT_AURA", "player")`
- `Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateAuras.lua` — `isFullUpdate` → full rescan pattern

### Secondary (MEDIUM confidence)

- [UNIT_AURA — Warcraft Wiki](https://warcraft.wiki.gg/wiki/UNIT_AURA) — event arguments, `isFullUpdate`, incremental fields
- [C_Secrets.ShouldUnitAuraInstanceBeSecret — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_Secrets.ShouldUnitAuraInstanceBeSecret) — per-instance secret check
- [WoW 12.0.0 Compatibility PR #457 — enderneko/Cell](https://github.com/enderneko/Cell/pull/457) — real-world `issecretvalue()` guard patterns; `IsAuraNonSecret()` helper
- [New UNIT_AURA Processing Optimizations — Blizzard Forum](https://us.forums.blizzard.com/en/wow/t/new-unitaura-processing-optimizations/1205007) — `isFullUpdate` design rationale (official Blizzard post, HIGH confidence for that specific claim)
- [Patch 12.0.0/API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) — `C_Secrets.*` additions, `SecretWhenUnitAuraRestricted` context

### Tertiary (LOW confidence)

- [How to Track Specific Buffs in Midnight — spiritbloom.pro](https://spiritbloom.pro/blog/tracking-buffs-in-midnight) — aura field limitations in secret contexts; findings superseded by direct Blizzard source verification

---
*Research completed: 2026-04-03*
*Ready for roadmap: yes*
