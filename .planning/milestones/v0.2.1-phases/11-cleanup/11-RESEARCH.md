# Phase 11: Cleanup - Research

**Researched:** 2026-04-04
**Domain:** Lua dead-code audit, hot-path review, DRY refactor, preview save/restore, release prep
**Confidence:** HIGH (all findings from direct code inspection)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** SC-1 (recentlyCast cleanup) is N/A — grace period was not implemented, no recentlyCast table exists.
- **D-02:** SC-2 (zero-allocation scan) is already satisfied — cancelledLabels only allocates under debugLogging AND cancellation. Hot path is zero-allocation.
- **D-03:** Run stylua on all Lua files, fix any formatting issues.
- **D-04:** Update CHANGELOG.md with v0.2.1 features. Update release scripts if needed.
- **D-05:** Review all files modified in v0.2.1 for dead code, unused variables, and redundant patterns.
- **D-06:** The meta-buff string-key icon/label resolution pattern (iterating SUGGESTED_BUFFS to find getCDMSpellID) is repeated in 5+ places across BuffEngine.lua, CDMTab.lua, and Display.lua. Consider extracting a shared helper like `ns:ResolveSuggestedSpellID(key)` to DRY this up.
- **D-07:** Preview must NOT overwrite running buffs. `StartAllPreviewTimers` currently wipes `ns.activeTimers = {}` and replaces everything. Fix: save active timers before preview, merge preview timers on top, and restore real timers on `ClearAllTimers` instead of wiping. Opening/closing CDM should not lose active buff tracking.

### Claude's Discretion

- All cleanup decisions are Claude's discretion — this is a technical housekeeping phase.

### Deferred Ideas (OUT OF SCOPE)

- None — preview buff preservation moved into this phase (D-07).

</user_constraints>

---

## Summary

Phase 11 is a pure housekeeping phase before cutting v0.2.1. The codebase is in good shape: all Lua files already pass `stylua --check` with exit 0, the hot-path scan (`ScanActiveTimersForCancellation`) is zero-allocation as confirmed by D-02, and `recentlyCast` was never implemented so SC-1 is N/A. Two substantive code changes are required: (1) extract a shared `ns:ResolveSuggestedSpellID(key)` helper to eliminate the SUGGESTED_BUFFS iteration loop that appears in eight distinct call sites across three files, and (2) fix `StartAllPreviewTimers` / `ClearAllTimers` to save and restore real active timers so opening CDM settings does not destroy in-flight buff countdowns.

Two minor dead-code items were found: `ns.tbtTabActive` is written in `ShowTBTPanel` and `HideTBTPanel` but never read anywhere — it can be deleted. The `entry.spellID = spellID` mutation in `Display.lua:UpdateDisplay` silently pollutes the SavedVariables table (the numeric spellID key is backfilled as a field on its own value); this is harmless at runtime but worth making a local variable instead to avoid the SavedVariables write.

CHANGELOG.md needs a v0.2.1 entry. The `release.bat` script is correct but pushes to `main` unconditionally — at release time the v0.2.1 branch must be merged to main first, or the script call must target the correct branch. This is a workflow note, not a bug in the script itself.

**Primary recommendation:** Implement D-06 helper first (reduces code before the stylua pass), then D-07 save/restore, then remove dead code, then CHANGELOG.

---

## Dead Code Audit

### Confirmed Dead Code

| Location | Item | Finding |
|----------|------|---------|
| `CDMTab.lua:1136,1147` | `ns.tbtTabActive` | Written in `ShowTBTPanel`/`HideTBTPanel`, never read in any `.lua` file. Delete both assignments. |

### Non-Dead But Worth Noting

| Location | Item | Finding |
|----------|------|---------|
| `Display.lua:421,552` | `entry.spellID = spellID` | Mutates live `ns.db.trackedBuffs` entries to backfill `spellID` as a field value. Functional but persists an extra key into `TerribleBuffTrackerDB`. Could be replaced with a local `slot = { spellID = spellID, ... }` copy to avoid touching the DB object. However this touches hot-path layout logic — only fix if it causes problems; keep as LOW priority. |
| `BuffEngine.lua:5` | `ns.auraCheckBlocked = false` | Correct initialization — not dead, consumed by `OnUnitAura` and `ClearAuraBlock`. |
| `BuffEngine.lua:5` | `ns.previewActive = false` | Correct initialization — consumed in `StartAllPreviewTimers`, `ClearAllTimers`, `OnUnitAura`. |

### Confirmed Not Present

- `ns.recentlyCast` — does not exist anywhere. SC-1 confirmed N/A (D-01).

---

## Repeated Pattern: ResolveSuggestedSpellID

### All Call Sites (8 total)

The following all contain an inline loop of the form:
```lua
if type(spellID) == "string" then
    for _, suggested in ipairs(ns.SUGGESTED_BUFFS) do
        if suggested.key == spellID and suggested.getCDMSpellID then
            -- use suggested.getCDMSpellID()
            break
        end
    end
end
```

| File | Function / Context | What it resolves |
|------|--------------------|-----------------|
| `BuffEngine.lua:241-250` | `StartAllPreviewTimers` | `iconSpellID` for `GetSpellIcon()` + `timerLabel` from spell info |
| `BuffEngine.lua` (via `StartLustTimer`) | Lust timer does NOT use this loop — it receives `lustSpellID` directly. Confirmed clean. | N/A |
| `CDMTab.lua:72-80` | `CreateIconFrame` `OnEnter` tooltip | `displaySpellID` for `GameTooltip:SetSpellByID` |
| `CDMTab.lua:109-113` | `CreateIconFrame` `OnEnter` suggested branch | `cdmSpellID` for `GameTooltip:SetSpellByID` |
| `CDMTab.lua:414-420` | `BeginDrag` ghost icon | `ghostIconID` for `GetSpellIcon` |
| `CDMTab.lua:758-765` | `RefreshTBTSections` non-suggested branch | `iconID` for item `Icon:SetTexture` |
| `Display.lua:457-464` | `UpdateDisplay` bar placeholder | `fallbackIcon` + `fallbackLabel` for bar rendering |
| `Display.lua:619-624` | `UpdateDisplay` icon placeholder | `iconTexture` for icon rendering |
| `Display.lua:161-168` | `CreateTimerBar` `OnEnter` tooltip | `tooltipSpellID` for `GameTooltip:SetSpellByID` |
| `Display.lua:228-235` | `CreateTimerIcon` `OnEnter` tooltip | `tooltipSpellID` for `GameTooltip:SetSpellByID` |

Total: **10 call sites** (two more than the 8 documented in CONTEXT.md — both tooltip handlers in `Display.lua` also contain the loop).

### Proposed Helper Signature

```lua
-- BuffEngine.lua (shared namespace, called from CDMTab and Display)
-- Returns the numeric CDM spellID for a string key, or nil if not found.
-- For non-string spellIDs, returns nil (caller uses spellID as-is).
function ns:ResolveSuggestedSpellID(key)
    if type(key) ~= "string" then
        return nil
    end
    for _, suggested in ipairs(ns.SUGGESTED_BUFFS) do
        if suggested.key == key and suggested.getCDMSpellID then
            return suggested.getCDMSpellID()
        end
    end
    return nil
end
```

Usage pattern after extraction:
```lua
-- Icon resolution (icon + label):
local resolvedID = ns:ResolveSuggestedSpellID(spellID) or spellID
local icon = ns:GetSpellIcon(resolvedID)
local info = type(resolvedID) == "number" and C_Spell.GetSpellInfo(resolvedID)
local label = (info and info.name) or entry.label

-- Tooltip resolution:
local tooltipSpellID = ns:ResolveSuggestedSpellID(self.spellID) or self.spellID
if type(tooltipSpellID) == "number" then
    GameTooltip:SetSpellByID(tooltipSpellID)
end
```

The `RefreshTBTSections` call site in CDMTab uses a slightly different pattern (already calls `getCDMSpellID()` directly for the suggested section without the `type(spellID) == "string"` guard because it knows the key is always a string). The helper handles this correctly since it returns nil for non-string inputs.

---

## Preview Save/Restore (D-07)

### Current Behavior (Bug)

```lua
-- BuffEngine.lua:231-266
function ns:StartAllPreviewTimers()
    ns.previewActive = true
    local now = GetTime()
    ns.activeTimers = {}   -- DESTROYS all in-flight timers
    -- ... fills with preview timers
end

function ns:ClearAllTimers()
    ns.previewActive = false
    ns.activeTimers = {}   -- DESTROYS preview timers without restoring real ones
end
```

When a player opens CDM settings (`CooldownViewerSettings` becomes visible), the CDM watcher in `CDMTab.lua:1079-1094` calls `StartPreview()` → `StartAllPreviewTimers()`, wiping any running timers. On close, `StopPreview()` → `ClearAllTimers()` wipes the preview timers, leaving nothing.

### Call Sites for StartAllPreviewTimers (re-entry points)

`StartAllPreviewTimers` is also called from:
- `CDMTab.lua:165` — after adding suggested item via context menu (while preview active)
- `CDMTab.lua:555` — after copy-on-drag from Suggested section (while preview active)
- `CDMTab.lua:859` — after AddTrackedBuff dialog confirms (always called)

These mid-preview refreshes must also preserve the saved timers table — they should re-merge saved timers over the freshly generated preview set, not discard saved timers.

### Correct Fix Pattern

```lua
-- BuffEngine.lua
local savedTimers = {}   -- module-level table, avoids allocation

function ns:StartAllPreviewTimers()
    -- D-07: Save real timers before preview overwrites them
    -- Only save on the FIRST call (savedTimers empty = not in preview yet)
    if not ns.previewActive then
        wipe(savedTimers)
        for k, v in pairs(ns.activeTimers) do
            savedTimers[k] = v
        end
    end

    ns.previewActive = true
    local now = GetTime()
    wipe(ns.activeTimers)   -- wipe() instead of ns.activeTimers = {}

    -- ... existing preview timer population ...

    -- Merge real timers back on top (real timers visible during preview)
    -- Real timers that are still running override preview placeholders
    for k, v in pairs(savedTimers) do
        if v.expiresAt > now then
            ns.activeTimers[k] = v
        end
    end

    if ns.UpdateDisplay then
        ns:UpdateDisplay()
    end
end

function ns:ClearAllTimers()
    ns.previewActive = false

    -- D-07: Restore real timers instead of wiping
    wipe(ns.activeTimers)
    local now = GetTime()
    for k, v in pairs(savedTimers) do
        if v.expiresAt > now then
            ns.activeTimers[k] = v
        end
    end
    wipe(savedTimers)

    if ns.UpdateDisplay then
        ns:UpdateDisplay()
    end
end
```

Key decisions baked in:
- `wipe()` on the existing table instead of `ns.activeTimers = {}` — preserves table identity (no GC churn, and any code holding a reference to the old table won't silently detach).
- `savedTimers` is a module-level table wiped with `wipe()` per CLAUDE.md pattern — zero GC pressure.
- Real timers override preview placeholders (same key, so assigning real timer after preview generation wins).
- Expired real timers are pruned at restore time (`v.expiresAt > now`).
- On re-entry (`StartAllPreviewTimers` called mid-preview for section refresh), the `not ns.previewActive` guard prevents overwriting the saved timers with the current (preview-mixed) activeTimers.

---

## Hot Path Review

### ScanActiveTimersForCancellation (BuffEngine.lua:276-322)

**Status: Already optimal (D-02)**

- Iterates `ns.activeTimers` (pairs loop — no allocation)
- `cancelledLabels` table only allocated when `ns.debugLogging` is true AND a cancellation occurs — confirmed zero-allocation on the hot path
- `C_UnitAuras.GetPlayerAuraBySpellID` is a WoW API call that returns nil or a table; the table is a temporary return value, not something TBT allocates
- No issues found

### OnUnitAura (BuffEngine.lua:360-401)

**Status: Acceptable**

- Lust detection loop iterates `updateInfo.addedAuras` — this is a WoW-provided table, not TBT-allocated
- `issecretvalue()` guard before index is correct
- The `ShouldAurasBeSecret()` check returns early quickly when blocked
- No per-call allocations from TBT code

### UpdateDisplay (Display.lua:375-661)

**Status: Hot path — existing mitigations are correct; one observation**

- `barTimers`, `iconTimers`, `barSlots`, `buffSlots`, `activeBarBySpell`, `activeBySpell` are all module-level tables wiped with `wipe()` each cycle — per CLAUDE.md pattern, correct
- `GetActiveTimers()` (BuffEngine.lua:120-138) allocates a new `result = {}` table and sorts it on every call. Called once per `UpdateDisplay` cycle. At 20fps (UPDATE_INTERVAL=0.05), that is 20 allocations/second. This is pre-existing; not new in v0.2.1 and out of scope for this phase.
- `table.sort` in `UpdateDisplay` for `barSlots` and `buffSlots` only runs in the placeholder/inactive path — not hot during normal play when `hideWhenInactive = true`
- The `entry.spellID = spellID` mutation (lines 421, 552) fires only when `entry.spellID` is not already set — typically once per session per entry, not every frame. Benign but noted above.

**No new hot-path allocations introduced in v0.2.1.**

---

## stylua Status

All four files pass `stylua --check` with exit code 0 as of the research date. The D-03 stylua pass will need to re-run after code changes from D-06 and D-07 are applied.

```bash
# Run after all code changes:
stylua BuffEngine.lua CDMTab.lua Display.lua Core.lua
```

---

## Architecture Patterns

### Shared Helper Placement

`ns:ResolveSuggestedSpellID` belongs in `BuffEngine.lua` alongside `ns:GetSpellIcon` — both are pure resolution helpers that CDMTab.lua and Display.lua call. This follows the existing pattern where ns functions defined in BuffEngine are consumed by both display files.

### Module-Level savedTimers Table

Follows the CLAUDE.md pattern: module-level table, wiped with `wipe()`, never reassigned. Declared at the top of BuffEngine.lua near the other runtime-only tables:

```lua
-- Near ns.auraCheckBlocked = false etc.
local savedPreviewTimers = {}  -- module-local (not ns.*) — only used by Start/ClearAllTimers
```

Using a `local` rather than `ns.*` is appropriate since this is internal to BuffEngine's preview state machine.

### Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Table identity preservation | `ns.activeTimers = {}` | `wipe(ns.activeTimers)` | Preserves table reference, zero GC cost |
| Spell lookup iteration | Inline loops | `ns:ResolveSuggestedSpellID(key)` | Single source of truth for key→spellID resolution |

---

## Common Pitfalls

### Pitfall 1: Over-Merging in Mid-Preview Refresh

**What goes wrong:** When `StartAllPreviewTimers` is called a second time mid-preview (e.g., after a section change), the guard `if not ns.previewActive` prevents re-saving the current (already-mixed) `activeTimers` into `savedPreviewTimers`. If this guard is absent, `savedPreviewTimers` gets overwritten with preview+real timers, and `ClearAllTimers` would restore both preview and real timers — preview timers would persist after CDM closes.

**How to avoid:** The `not ns.previewActive` guard on the save block is mandatory.

### Pitfall 2: wipe() vs. ns.activeTimers = {} for Restore

**What goes wrong:** If restore in `ClearAllTimers` uses `ns.activeTimers = {}` (table reassignment) instead of `wipe(ns.activeTimers)`, any code that captured a reference to the old `ns.activeTimers` table (e.g., an active `for k,v in pairs(ns.activeTimers)` iteration) would silently read from the old, now-orphaned table. Additionally the old table becomes GC garbage.

**How to avoid:** Always `wipe()` the existing table, then repopulate.

### Pitfall 3: Removing tbtTabActive Without Checking All Files

**What goes wrong:** `ns.tbtTabActive` is confirmed unread in Lua files. However, there are no XML files that reference ns.* directly, and the CDMTab.xml only defines the button template. Safe to remove both assignments.

**Verified:** Grep across all `.lua` files confirms zero reads. Only the two write sites in CDMTab.lua exist.

### Pitfall 4: release.bat Pushes to main Directly

**What goes wrong:** `release.bat` runs `git push origin main "<TAG>"`. If called while on the `v0.2.1-aura-cancellation` branch before merging, it pushes the current branch tip to `main`, potentially bypassing the squash-merge workflow. The script itself is correct — the risk is in calling it before the merge.

**How to avoid:** Document in CHANGELOG workflow: squash-merge branch to main first, then call `release.bat`. No script change needed.

---

## CHANGELOG.md Assessment

Current state: v0.2.0 and v0.1.0 entries exist. No v0.2.1 entry.

### v0.2.1 Feature Summary (from completed requirements)

Based on REQUIREMENTS.md completed items and phase deliverables:

**Aura-based timer cancellation (Phase 7-9):**
- Timers for tracked buffs cancel automatically when the buff drops from the player
- Aura detection is gated by `C_Secrets.ShouldAurasBeSecret()` — automatically disabled in M+ and other restricted contexts
- Aura check unblocks on combat drop or zone change

**Lust / Heroism tracking (Phase 10):**
- Lust / Heroism timers start automatically when Sated, Exhaustion, Temporal Displacement, or Evoker Exhaustion debuffs are detected
- Class-aware icon: Mage shows Time Warp icon, Evoker shows Fury of the Aspects, all others show Bloodlust
- Drag the Lust / Heroism entry from the Suggested section to activate tracking
- Current-season drums (Drumsound) supported as a lust source

**Improvements:**
- Preview timers no longer interrupt active buff countdowns when CDM settings is opened

---

## Release Script Assessment

`scripts/release.bat` is correct. It:
1. Creates an annotated tag `v<version>`
2. Pushes both `main` and the tag to origin
3. GitHub Actions handles BigWigs packaging from the tag

No changes needed to the script. Workflow requirement: merge v0.2.1-aura-cancellation branch to main (squash) before running `release.bat v0.2.1`.

---

## Environment Availability

Step 2.6: SKIPPED (no external tool dependencies — this is code/config-only changes)

`stylua` is confirmed available at `~/.cargo/bin/stylua` (from MEMORY.md and verified clean check above).

---

## Validation Architecture

### Test Framework

WoW Lua addons have no automated test framework applicable here — all behavior requires an in-game WoW client with CDM loaded. Testing is manual.

| Property | Value |
|----------|-------|
| Framework | Manual in-game testing (WoW Midnight client) |
| Config file | none |
| Quick run command | Deploy via `./scripts/install.bat`, reload UI in-game |
| Full suite command | Same — manual verification against acceptance criteria |

### Phase Requirements → Test Map

| ID | Behavior | Test Type | Automated Command | File Exists? |
|----|----------|-----------|-------------------|-------------|
| D-06 | `ns:ResolveSuggestedSpellID("lust")` returns class-aware spellID | manual-only | n/a — WoW API | n/a |
| D-07 | Start a timer, open CDM, timer still running when CDM closes | manual-only | n/a — WoW API | n/a |
| D-03 | All Lua files pass stylua | automated | `stylua --check BuffEngine.lua CDMTab.lua Display.lua Core.lua` | ✅ (stylua installed) |
| dead-code | tbtTabActive removed with no errors | automated | `stylua --check` + in-game load | ✅ |

### Wave 0 Gaps

None — stylua is available. No test files exist and none are needed for this phase (cleanup only, no new logic that can be unit-tested without WoW runtime).

---

## Open Questions

1. **Should `ns:ResolveSuggestedSpellID` also return the label?**
   - What we know: Some call sites need both the spellID and the spell name (StartAllPreviewTimers, bar/icon placeholder rendering). Others need only the spellID (tooltips, icon texture).
   - What's unclear: Whether a single helper returning `(spellID, label)` is cleaner than two calls, or whether it creates awkward `_` discards.
   - Recommendation: Return only the spellID. Call sites that need a label can do `C_Spell.GetSpellInfo(resolvedID)` independently — this is already the pattern and keeps the helper single-purpose.

2. **Should preview timers be visible during preview, or only real timers?**
   - What we know: D-07 says "merge preview timers on top" with real timers overriding. This means the player sees placeholder preview bars alongside their real running timers.
   - What's unclear: If a real timer is running for "lust" AND a preview placeholder is generated for "lust", the real one wins (same key). This is correct behavior.
   - Recommendation: The merge-with-real-override approach is correct as designed.

---

## Sources

### Primary (HIGH confidence)
- Direct code inspection of all five Lua files (`BuffEngine.lua`, `CDMTab.lua`, `Display.lua`, `Core.lua`, `EditModeFrames.lua`) — authoritative
- `stylua --check` exit code 0 confirmed all files pass formatting
- Grep across all `.lua` files for all dead-code suspects

### Secondary (MEDIUM confidence)
- CONTEXT.md decisions (D-01 through D-07) — user-confirmed constraints

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Dead code audit: HIGH — confirmed by grep across full codebase
- Hot-path review: HIGH — direct code inspection, zero new allocations confirmed
- DRY pattern (D-06): HIGH — 10 call sites catalogued, helper signature is straightforward
- Preview save/restore (D-07): HIGH — bug confirmed, fix pattern is standard Lua table management
- CHANGELOG content: MEDIUM — feature list from requirements, actual prose needs review by user
- Release script: HIGH — script is correct, workflow note only

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (stable codebase, no external dependencies)
