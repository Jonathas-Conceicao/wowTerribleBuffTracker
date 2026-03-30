# Phase 1: Data Migration - Research

**Researched:** 2026-03-28
**Domain:** WoW addon SavedVariables schema migration — Lua table backfill, schema versioning, field cleanup
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Direct mapping from old fields to new `section` field:
  - `displayMode="bar"` + `enabled=true` → `section="bars"`
  - `displayMode="buff"` + `enabled=true` → `section="buffs"`
  - `enabled=false` (any displayMode) → `section="hidden"`
- **D-02:** Old `displayMode` and `enabled` fields are removed after migration. `section` is the single source of truth — clean break, no backwards compatibility shim.
- **D-03:** Add a `schemaVersion` number field to `TerribleBuffTrackerDB` root (not per-entry). Bump on each migration. Pre-migration data is implicitly version 0; after this migration, version is 1.
- **D-04:** Migration runs only when `schemaVersion` is nil or less than the target version. This replaces the current field-presence check pattern in `InitBuffEngine()`.
- **D-05:** Newly added buffs default to `section="hidden"` (Not Displayed). User must explicitly promote them to "Tracked Bars" or "Tracked Buffs" in the CDM tab.

### Claude's Discretion

- Migration function placement (inline in `InitBuffEngine` vs. separate function)
- Whether to log migration activity to chat
- Error handling for unexpected field values

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MIG-01 | User's existing tracked buffs are preserved when upgrading to v0.2.0 | Migration iterates `trackedBuffs` without wiping; schemaVersion guard prevents double-migration |
| MIG-02 | Existing `displayMode`/`enabled` values are mapped to `section` field (bars/buffs/hidden) | D-01 mapping fully specified; all three cases covered; old fields removed after backfill |
</phase_requirements>

---

## Summary

Phase 1 is a pure data migration with no UI changes. It adds a `schemaVersion` integer to `TerribleBuffTrackerDB`, runs a one-time backfill that derives `section` from the existing `enabled`/`displayMode` fields on each `trackedBuffs` entry, removes the deprecated fields, and updates the write paths in `BuffEngine.lua` so new entries default to `section="hidden"`.

The existing codebase already has a partial migration pattern in `InitBuffEngine()` (lines 4–12) that backfills `enabled` and `displayMode` for entries that predate those fields. The new migration slots in directly below that pattern, adds the schemaVersion guard around all backfill logic, and extends `AddTrackedBuff()` to write `section` instead of `enabled`/`displayMode`.

The largest risk is correctness of the three-way mapping and ensuring that `Display.lua`'s `UpdateDisplay()` function — which currently reads `entry.displayMode` and `entry.enabled` directly — is updated in the same commit to read `entry.section` instead. Failing to update Display.lua means the display silently breaks even though the data is correctly migrated.

**Primary recommendation:** Implement the migration inside `InitBuffEngine()` (not a separate function) because that is already the established pattern and the call site in `Core.lua:ADDON_LOADED` is already correct. Keep migration logic tightly co-located with schema knowledge.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WoW SavedVariables | N/A | Persistent account-wide DB | Only persistence mechanism available to addons |
| Lua table iteration (`pairs`) | Built-in | Iterate `trackedBuffs` entries for backfill | Standard pattern; already used throughout codebase |
| `GetTime()` | WoW API | N/A for this phase | Not needed — migration is pure table mutation |

No external libraries. This phase is pure Lua table manipulation using the existing WoW addon infrastructure.

### Supporting

None required for this phase.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline migration in `InitBuffEngine` | Separate `MigrateDB()` function | Separate function is slightly cleaner for large migrations; inline is simpler and matches the existing pattern in this file. Given the small size of this migration, inline is preferred. |
| Integer `schemaVersion` | String version like `"1.0"` | Integer comparison is simpler, less error-prone, and matches the convention used by most WoW addon migration patterns. |

**Installation:** No packages to install — pure Lua.

---

## Architecture Patterns

### Recommended Project Structure

No structural changes. This phase modifies two existing files only:

```
TerribleBuffTracker/
├── BuffEngine.lua    -- MODIFIED: migration logic, AddTrackedBuff, SetBuffEnabled, SetBuffDisplayMode, OnSpellCastSucceeded, StartAllPreviewTimers
├── Display.lua       -- MODIFIED: replace entry.enabled / entry.displayMode reads with entry.section
└── Core.lua          -- READ-ONLY: schemaVersion init belongs here OR at the top of InitBuffEngine (discretion)
```

### Pattern 1: Schema Version Guard

**What:** Check `schemaVersion` at DB init time and run migrations sequentially up to the current version.

**When to use:** Every time the DB schema changes across a release boundary.

**Example:**
```lua
-- In BuffEngine.lua: InitBuffEngine()
local CURRENT_SCHEMA_VERSION = 1

function ns:InitBuffEngine()
    -- Run schema migrations
    local ver = ns.db.schemaVersion or 0

    if ver < 1 then
        -- Migration v0 → v1: replace enabled/displayMode with section
        for _, entry in pairs(ns.db.trackedBuffs) do
            if not entry.section then
                if entry.enabled == false then
                    entry.section = "hidden"
                elseif entry.displayMode == "buff" then
                    entry.section = "buffs"
                else
                    -- bar, nil, or any unexpected value → bars
                    entry.section = "bars"
                end
            end
            -- Remove deprecated fields (D-02)
            entry.enabled = nil
            entry.displayMode = nil
        end
        ns.db.schemaVersion = 1
    end

    -- Future migrations follow the same pattern:
    -- if ver < 2 then ... ns.db.schemaVersion = 2 end
end
```

**Key detail:** The `entry.enabled = nil` and `entry.displayMode = nil` assignments must execute unconditionally within the `ver < 1` block — not guarded by `if entry.section then`. This ensures old fields are removed from entries that already had a section from a partial migration attempt.

### Pattern 2: schemaVersion placement — Core.lua vs InitBuffEngine

**Two viable options:**

Option A — `Core.lua` sets `schemaVersion` on the DB table initializer only when DB is created fresh (already has `if not TerribleBuffTrackerDB`). The version guard check lives in `InitBuffEngine`. This keeps Core.lua touching only structural init, not migration logic.

Option B — `Core.lua` calls a `ns:MigrateDB()` function before `InitBuffEngine`. Cleaner separation but adds indirection.

**Recommendation (Discretion):** Option A. The schemaVersion field is initialized to `nil` (absent) when not set, and the migration check `ns.db.schemaVersion or 0` handles this correctly. No change to `Core.lua` needed for this phase.

### Pattern 3: Display.lua — Replacing enabled/displayMode reads with section

`UpdateDisplay()` in `Display.lua` currently filters `trackedBuffs` entries using `entry.displayMode` and `entry.enabled`. After migration, these fields are nil. Every read site must be updated to use `entry.section`:

| Current code | Replacement |
|---|---|
| `if entry.displayMode ~= "buff" and entry.enabled ~= false then` | `if entry.section == "bars" then` |
| `if entry.displayMode == "buff" and entry.enabled ~= false then` | `if entry.section == "buffs" then` |
| `timer.displayMode = entry.displayMode or "bar"` | `timer.section = entry.section or "bars"` |
| `if timer.displayMode == "buff" then` | `if timer.section == "buffs" then` |

`OnSpellCastSucceeded` in `BuffEngine.lua` also reads `entry.enabled`:

| Current code | Replacement |
|---|---|
| `if entry.enabled == false then return end` | `if entry.section == "hidden" then return end` |

`StartAllPreviewTimers` reads `entry.enabled ~= false` — same replacement.

`SetBuffEnabled` and `SetBuffDisplayMode` write to the removed fields — these functions should either be removed entirely (no caller in this phase) or converted to `SetBuffSection`.

### Anti-Patterns to Avoid

- **Reinitialising `trackedBuffs` from scratch:** Never do `ns.db.trackedBuffs = {}` in migration code. The whole point is to preserve existing entries. Only ever iterate and mutate.
- **Checking `if not entry.section` around the field removal:** The `entry.enabled = nil` and `entry.displayMode = nil` cleanup must run even for entries that already had a `section` from a hypothetical partial migration. Guard only the section assignment, not the cleanup.
- **Leaving orphan write paths:** `AddTrackedBuff` currently sets `enabled = true` and `displayMode = "bar"`. If these writes remain after migration, entries added post-migration will have the old fields again. Update `AddTrackedBuff` in the same commit.
- **Double-migration:** The schemaVersion guard (`if ver < 1`) prevents running the migration twice. Do not add any other condition that could bypass this guard.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Schema versioning | Custom "field presence check" per field | `schemaVersion` integer on DB root | Field presence checks cannot distinguish "never set" from "set to nil by a previous migration"; also cannot handle multi-version gaps |
| Field removal | Setting fields to empty string | `field = nil` in Lua | Setting to nil removes the key from the table entirely — correct for cleanup. Empty string is not nil and will persist. |

**Key insight:** WoW SavedVariables are loaded as Lua tables. `nil` assignment removes keys. `schemaVersion` is the only reliable way to know whether a migration has already run.

---

## Runtime State Inventory

> This phase changes the DB schema but does not rename the addon, account, or any external-facing identifier.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `TerribleBuffTrackerDB.trackedBuffs` — per-entry `enabled` and `displayMode` fields in player SavedVariables | Code migration in `InitBuffEngine()` — iterate and backfill `section`, remove old fields |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | None | None |

**The only runtime state that changes** is the structure of `trackedBuffs` entries inside `TerribleBuffTrackerDB`, which lives in the WoW SavedVariables file (`WTF/Account/.../SavedVariables/TerribleBuffTracker.lua`). This file is written by WoW on logout/reload and read on next login. The migration runs in-memory on load; changes persist at the next natural WoW save.

---

## Common Pitfalls

### Pitfall 1: Migration wipes user data (Pitfall 8 from PITFALLS.md)
**What goes wrong:** Developer expands the `if not TerribleBuffTrackerDB` block in `Core.lua` to include `schemaVersion`, inadvertently reinitialising the whole DB for users who have data.
**Why it happens:** The init block is the obvious place to add new fields.
**How to avoid:** Never expand the `if not TerribleBuffTrackerDB` block. That block only runs when there is no saved data at all (first ever load). New fields on existing DBs are handled exclusively in `InitBuffEngine()`.
**Warning signs:** All tracked buffs disappear on first login after update.

### Pitfall 2: Display.lua reads nil fields after migration
**What goes wrong:** `UpdateDisplay()` references `entry.displayMode` and `entry.enabled` which are now nil. Nil comparisons silently evaluate to falsy — bars and icons stop rendering, but no Lua error fires. This looks like a display bug, not a data bug.
**Why it happens:** `Display.lua` and `BuffEngine.lua` are modified in separate commits, or the Display.lua update is missed entirely.
**How to avoid:** Update all five read sites in `Display.lua` and `BuffEngine.lua` in the same commit as the migration. Use grep to find every reference to `entry.enabled` and `entry.displayMode` before closing the task.
**Warning signs:** No tracked buffs appear after upgrading, even though `/tbt` shows them in the config.

### Pitfall 3: AddTrackedBuff still writes old fields
**What goes wrong:** After migration, a user adds a new buff via the config UI. `AddTrackedBuff` sets `enabled = true` and `displayMode = "bar"` — the new entry has the deprecated structure. The next migration run (if `schemaVersion` check is correct) will not re-run, so the entry stays broken until the user manually edits their SavedVariables.
**Why it happens:** `AddTrackedBuff` is not updated alongside the migration.
**How to avoid:** Update `AddTrackedBuff` in the same commit. Replace `enabled = true, displayMode = "bar"` with `section = "hidden"` per D-05.
**Warning signs:** Newly added buffs after the update don't appear in any display section.

### Pitfall 4: SetBuffEnabled / SetBuffDisplayMode write to removed fields
**What goes wrong:** If any code path still calls `ns:SetBuffEnabled()` or `ns:SetBuffDisplayMode()`, it writes to `entry.enabled` and `entry.displayMode` respectively — resurrecting the removed fields.
**Why it happens:** These functions exist and may be called from ConfigUI.lua (the old config window).
**How to avoid:** In this phase, ConfigUI.lua is still present. Audit whether ConfigUI.lua calls these functions. If it does, either (a) update them to write `entry.section` as a transitional measure, or (b) add a stub that maps to `SetBuffSection`. Since ConfigUI.lua is being replaced in a later phase, option (a) — updating the functions to write `section` — is the correct approach for this phase.
**Warning signs:** User enables/disables a buff in the config UI, and the change has no effect on display.

### Pitfall 5: Unexpected `displayMode` values produce wrong section
**What goes wrong:** A user with a hand-edited SavedVariables file (or a future bug) has an entry with `displayMode = "icon"` or some other unexpected string. The migration falls through to the `else` branch and assigns `section = "bars"`, which may not be the intended behavior.
**Why it happens:** The migration mapping is not exhaustive.
**How to avoid:** The `else` branch defaulting to `"bars"` is safe and intentional — it matches the pre-migration implicit default. Document this in a comment.

---

## Code Examples

### Complete migration block (recommended implementation)

```lua
-- Source: decisions D-01 through D-04 in 01-CONTEXT.md
function ns:InitBuffEngine()
    local CURRENT_SCHEMA_VERSION = 1
    local ver = ns.db.schemaVersion or 0

    if ver < 1 then
        -- v0 → v1: Replace enabled/displayMode with section
        -- enabled=false → "hidden", displayMode="buff" → "buffs", else → "bars"
        for _, entry in pairs(ns.db.trackedBuffs) do
            if not entry.section then
                if entry.enabled == false then
                    entry.section = "hidden"
                elseif entry.displayMode == "buff" then
                    entry.section = "buffs"
                else
                    -- "bar", nil, or any unexpected value → bars
                    entry.section = "bars"
                end
            end
            -- Remove deprecated fields regardless of section presence (clean break)
            entry.enabled = nil
            entry.displayMode = nil
        end
        ns.db.schemaVersion = 1
    end
end
```

### Updated AddTrackedBuff (new entry default)

```lua
-- Source: decision D-05 in 01-CONTEXT.md
ns.db.trackedBuffs[spellID] = {
    spellID = spellID,
    duration = duration,
    label = displayLabel,
    section = "hidden",    -- D-05: new buffs land in Not Displayed
}
```

### Updated OnSpellCastSucceeded (section-aware skip)

```lua
-- Source: CONTEXT.md code_context, BuffEngine.lua line 28-30
if entry.section == "hidden" then
    return
end
```

### Updated UpdateDisplay bar slot filter (Display.lua)

```lua
-- Source: Display.lua line 467-469 (current); updated for section field
for _, entry in pairs(ns.db.trackedBuffs) do
    if entry.section == "bars" then
        table.insert(barSlots, entry)
    end
end
```

### Updated UpdateDisplay buff slot filter (Display.lua)

```lua
-- Source: Display.lua line 579-582 (current); updated for section field
for _, entry in pairs(ns.db.trackedBuffs) do
    if entry.section == "buffs" then
        table.insert(buffSlots, entry)
    end
end
```

### Updated active timer split (BuffEngine.lua / Display.lua)

Active timers carry a `section` field (copied from the entry at cast time). The split in `UpdateDisplay` becomes:

```lua
for _, timer in ipairs(timers) do
    if timer.section == "buffs" then
        table.insert(iconTimers, timer)
    else
        table.insert(barTimers, timer)
    end
end
```

And in `OnSpellCastSucceeded`, the timer record stores `section`:

```lua
ns.activeTimers[spellID] = {
    spellID = spellID,
    expiresAt = now + entry.duration,
    startedAt = now,
    duration = entry.duration,
    icon = ns:GetSpellIcon(spellID),
    label = entry.label or ("Spell " .. spellID),
    section = entry.section or "bars",    -- replaces displayMode
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-field presence checks (`if entry.enabled == nil`) | `schemaVersion` integer guard | This phase | Future migrations have a reliable version baseline |
| `enabled` + `displayMode` as two fields | `section` as single source of truth | This phase | Simpler read logic; fewer nil checks throughout |

**Deprecated/outdated after this phase:**
- `entry.enabled` — removed; replaced by `entry.section == "hidden"` check
- `entry.displayMode` — removed; replaced by `entry.section` value
- `ns:SetBuffEnabled()` — writes to removed field; must be updated to write `section` or removed
- `ns:SetBuffDisplayMode()` — writes to removed field; must be updated to write `section` or removed

---

## Open Questions

1. **Should `SetBuffEnabled` and `SetBuffDisplayMode` be updated or stubbed?**
   - What we know: ConfigUI.lua currently calls these functions (it has Enable/Disable buttons and display mode dropdowns). ConfigUI.lua will be replaced in a later phase.
   - What's unclear: Whether any current code path actively calls these during normal gameplay (vs. only from ConfigUI interaction).
   - Recommendation: Update both functions to write `entry.section` in this phase so the config UI continues to work. `SetBuffEnabled(spellID, false)` → set `section = "hidden"`; `SetBuffDisplayMode(spellID, "bar")` → set `section = "bars"`; `SetBuffDisplayMode(spellID, "buff")` → set `section = "buffs"`. This keeps ConfigUI functional without blocking the later replacement phase.

2. **Should migration activity be logged to chat?**
   - What we know: The existing backfill in `InitBuffEngine()` logs nothing. The user is unlikely to want a migration notice on every login (D-04 ensures it only runs once).
   - Recommendation: Log once at migration time, e.g., `print("|cff00ccffTerribleBuffTracker|r: DB migrated to v1.")`. This helps developers verify the migration ran during testing without being intrusive. Single `print`, no spam.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely in-memory Lua table mutation. No external tools, services, or CLI utilities are required. `stylua` is required post-edit per CLAUDE.md and is confirmed installed at `~/.cargo/bin/stylua`.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual in-game testing (no automated test framework for WoW addons) |
| Config file | None |
| Quick run command | `/reload` in-game, then `/tbt` to verify config shows existing buffs |
| Full suite command | See test scenarios below |

WoW addons cannot use standard test frameworks (jest, pytest, etc.) — the runtime is the WoW client itself. Validation is done via in-game verification with controlled SavedVariables states.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | How to Verify | Automatable? |
|--------|----------|-----------|----------------|-------------|
| MIG-01 | Existing buffs preserved after upgrade | Manual smoke | Create v0.1-style DB with tracked buffs → load addon → verify all entries present in config UI | No — requires WoW client |
| MIG-02 | `displayMode`/`enabled` mapped to `section` | Manual smoke | Inspect SavedVariables file or add `print` to migration — verify correct section values | No — requires WoW client |
| MIG-01 | Second upgrade does not overwrite user section | Manual smoke | Run migration, change a section in-game, `/reload`, verify section unchanged | No — requires WoW client |
| D-05 | New buffs default to section="hidden" | Manual smoke | Add a new buff via config UI → inspect `ns.db.trackedBuffs[id].section` == "hidden" | No — requires WoW client |

### Sampling Rate

- **Per task commit:** `stylua BuffEngine.lua Display.lua && ./scripts/install.bat`, then manual in-game `/reload` verification
- **Phase gate:** All four manual test scenarios above pass before proceeding to Phase 2

### Wave 0 Gaps

None — this phase requires no new test infrastructure. Validation is manual in-game testing as described above.

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on This Phase |
|-----------|---------------------|
| `COMBAT_LOG_EVENT_UNFILTERED` is disabled — do NOT use | Not relevant to data migration |
| Use `UNIT_SPELLCAST_SUCCEEDED` for cast detection | `OnSpellCastSucceeded` updated to read `entry.section` instead of `entry.enabled` |
| Use `GetTime()` + known durations for timer tracking | Not changed in this phase |
| Requires Blizzard's CDM — no standalone fallback | Not relevant to data migration |
| Always run `stylua` on Lua files after finishing a task | Must run `stylua BuffEngine.lua Display.lua` after implementation |
| After every commit, run performance and code cleanup review | Check for any per-frame reads added; none should be added in this phase |
| Namespace: `local addonName, ns = ...` | All files already follow this pattern |
| SavedVariables: `TerribleBuffTrackerDB` (account-wide) | Migration target is `TerribleBuffTrackerDB.trackedBuffs` |
| Active timers are runtime-only (not persisted) | Confirmed: active timers are rebuilt from `OnSpellCastSucceeded`; migration only affects the DB entries |
| Reusable module-level tables wiped with `wipe()` each cycle | Not applicable to migration code (runs once at load) |

---

## Sources

### Primary (HIGH confidence)

- `BuffEngine.lua` (lines 3–12) — existing migration pattern; direct source for integration point
- `Core.lua` (lines 17–28) — DB initialization and `InitBuffEngine()` call site
- `Display.lua` (lines 427–436, 466–472, 579–582) — all current reads of `entry.displayMode` and `entry.enabled`
- `.planning/phases/01-data-migration/01-CONTEXT.md` — locked decisions D-01 through D-05
- `.planning/research/ARCHITECTURE.md` (Data Model Change section, lines 256–294) — schema diagram and migration backfill example
- `.planning/research/PITFALLS.md` (Pitfall 8, lines 188–205) — migration data integrity risk

### Secondary (MEDIUM confidence)

None required — all findings are sourced from project code and locked decisions.

### Tertiary (LOW confidence)

None.

---

## Metadata

**Confidence breakdown:**
- Migration mapping: HIGH — directly specified in D-01, no ambiguity
- Implementation placement: HIGH — existing pattern in `InitBuffEngine()` is the clear integration point
- Display.lua update requirement: HIGH — `entry.displayMode`/`entry.enabled` reads are clearly visible in source
- `SetBuffEnabled`/`SetBuffDisplayMode` handling: MEDIUM — correct handling depends on ConfigUI.lua call audit (open question 1)

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain — schema migration logic does not change with WoW patches)
