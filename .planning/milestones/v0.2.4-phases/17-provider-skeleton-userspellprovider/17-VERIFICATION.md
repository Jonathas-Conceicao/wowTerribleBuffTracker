---
phase: 17-provider-skeleton-userspellprovider
verified: 2026-04-19T00:00:00Z
status: passed
score: 5/5 must-haves verified
gaps: []
human_verification:
  - test: "Existing timer bars appear and behave identically to v0.2.3 — no visual regression"
    expected: "All buff types (user spells, trinket, pot, lust) produce timer bars with correct icons, labels, and durations; hidden guard suppresses hidden entries; preview mode shows non-hidden entries"
    why_human: "Visual behavior and in-game event routing cannot be verified programmatically — requires live WoW session"
    resolution: "APPROVED by user in-game (17-02 SUMMARY, Task 2 checkpoint, all 8 steps passed)"
---

# Phase 17: Provider Skeleton + UserSpellProvider Verification Report

**Phase Goal:** The SpellProvider interface contract exists and UserSpellProvider routes cast detection through it — proving the dispatch loop works before any existing behavior is removed.
**Verified:** 2026-04-19
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Providers.lua loads without Lua error when addon initializes | VERIFIED | File is syntactically valid Lua; passes `stylua --check`; in-game load confirmed (user Step 1, APPROVED) |
| 2 | ns.providers is a non-empty table containing UserSpellProvider | VERIFIED | `ns.providers = { UserSpellProvider }` at line 129 of Providers.lua; exactly one entry |
| 3 | SpellProviderBaseMixin defines all four interface methods | VERIFIED | `grep -c "^function SpellProviderBaseMixin:"` returns 4: GetEventInterests, OnTrigger, GetPreviewInfo, GetAtRestInfo |
| 4 | UserSpellProvider routes user-spell casts through ns:DispatchEventToProviders; resulting ActiveProc has all required fields | VERIFIED | BuffEngine.lua line 403 calls dispatcher; Providers.lua OnTrigger returns {key, icon, duration, label, expiresAt, source, startedAt, section, layoutOrder, spellID}; in-game cast confirmed (user Step 3, APPROVED) |
| 5 | Trinket, pot, lust, preview, and cancellation branches remain UNCHANGED | VERIFIED | All preservation greps match: TRINKET_SPELLS branch (line 324), POT_SPELLS branch (line 358), LUST-01/OnUnitAura (line 702-703), StartAllPreviewTimers with direct trackedBuffs iteration (line 534), ScanActiveTimersForCancellation source="cast" branch (line 610); CURRENT_SCHEMA_VERSION = 3 (line 249); old inline comment absent |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Providers.lua` | SpellProviderBaseMixin, UserSpellProviderMixin, ns.providers registry, ns:DispatchEventToProviders | VERIFIED | File exists at repo root; 172 lines; all four base methods + four concrete methods present; ns.providers = { UserSpellProvider } at line 129; ns:DispatchEventToProviders at line 154 |
| `TerribleBuffTracker.toc` | Providers.lua in load order between BuffEngine.lua and EditModeFrames.lua | VERIFIED | Line 15; adjacent sequence BuffEngine.lua(14) → Providers.lua(15) → EditModeFrames.lua(16) → Display.lua(17) → CDMTab.xml(18) confirmed by awk |
| `BuffEngine.lua` | OnSpellCastSucceeded with user-spell branch replaced by dispatch call; all other functions intact | VERIFIED | Dispatcher call at line 403; old inline comment absent; all preservation checks pass |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| TerribleBuffTracker.toc | Providers.lua | Load order after BuffEngine.lua and before EditModeFrames.lua | VERIFIED | Lines 14-16 are strictly adjacent in expected order |
| Providers.lua | ns.providers | Registry exported to shared namespace | VERIFIED | `ns.providers = { UserSpellProvider }` at line 129 |
| Providers.lua | ns:DispatchEventToProviders | Function exported to shared namespace | VERIFIED | `function ns:DispatchEventToProviders` at line 154 |
| BuffEngine.lua ns:OnSpellCastSucceeded | ns:DispatchEventToProviders | User-spell branch replaced by dispatch call | VERIFIED | Line 403: `ns:DispatchEventToProviders("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellID)` |
| ns:DispatchEventToProviders | ns.activeTimers[proc.key] | Dispatch installs proc keyed by proc.key | VERIFIED | `ns.activeTimers[proc.key] = proc` at line 163 of Providers.lua |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Providers.lua UserSpellProviderMixin:OnTrigger | ns.db.trackedBuffs[spellID] | SavedVariables DB read at cast time | Yes — reads live DB entry; returns nil if not found or hidden | FLOWING |
| BuffEngine.lua ns:DispatchEventToProviders call | spellID from UNIT_SPELLCAST_SUCCEEDED | WoW event arg (real cast, not hardcoded) | Yes — arg arrives from Core.lua event handler | FLOWING |

### Behavioral Spot-Checks

Step 7b: SKIPPED (WoW addon — requires live game client; cannot run Lua files outside the WoW environment)

In-game behavioral verification was performed by the user as a blocking human-verify checkpoint (Plan 17-02 Task 2). All 8 steps passed and the checkpoint was APPROVED.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| PROV-03 | 17-01, 17-02 | ActiveProc is a plain normalized table shape ({key, icon, duration, label, expiresAt, source} + optional castSpellID/lustBuffID) consumed uniformly | SATISFIED | UserSpellProviderMixin:OnTrigger returns exactly this shape (Providers.lua lines 79-91); required fields all present; marked complete in REQUIREMENTS.md traceability table |

No orphaned requirements: REQUIREMENTS.md traceability maps PROV-03 to Phase 17 only, and both plans claim it. All other v0.2.4 requirements are assigned to later phases.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Providers.lua | 6 | `ns.providers = {}` before final assignment at line 129 | Info | Harmless — intermediate assignment immediately overwritten; no data flows from the empty table |

No blockers or warnings found. The intermediate empty `ns.providers = {}` at line 6 is overwritten at line 129 before any code could read it; this is benign initialization commentary in the file header.

Negative checks confirmed:
- No `setmetatable` in Providers.lua (PITFALL-7 safe)
- No `InCombatLockdown`, `GetInventoryItemID`, or `C_Item.GetItemCount` in Providers.lua (PITFALL-5 safe)
- No writes to `ns.db.trackedBuffs[...]` in Providers.lua (PITFALL-1 safe)
- No `CURRENT_SCHEMA_VERSION` reference in Providers.lua (PITFALL-1 safe)
- Old inline user-spell comment `-- Existing regular-buff path (preserved verbatim)` absent from BuffEngine.lua (branch 3 cleanly replaced)

### Human Verification Required

The following item required human verification and was completed before this report was written:

**1. Visual regression and dispatch correctness in-game**

**Test:** Log in to WoW with the addon loaded; cast a tracked user spell, a tracked trinket, a tracked pot, and observe lust detection; verify /tbt preview mode and section="hidden" guard.

**Expected:** All timer bars appear with correct icons, labels, and countdown behavior identical to v0.2.3; user-spell casts now route through UserSpellProvider:OnTrigger but produce visually identical output; no Lua errors.

**Why human:** WoW addon Lua executes inside the game client — spell cast events, timer rendering, and CDM frame layout cannot be simulated outside the live environment.

**Resolution:** APPROVED by user (17-02-SUMMARY.md Task 2 table — all 8 steps PASS; status "APPROVED"). Commit `d2f21f2` (dispatch wiring), `6fc0baa` (install.bat fix), and `94114c7` (docs) mark the phase complete.

### Gaps Summary

No gaps. All five observable truths are verified. The three level-1/2/3 artifacts exist, are substantive, and are wired. Data flows from real WoW events through the dispatch loop to ns.activeTimers. PROV-03 is satisfied. The in-game human-verify checkpoint was approved. Phase 17 goal is achieved.

---

_Verified: 2026-04-19_
_Verifier: Claude (gsd-verifier)_
