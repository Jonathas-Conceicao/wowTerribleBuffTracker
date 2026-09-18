# Phase 10: Lust Tracking - Research

**Researched:** 2026-04-03
**Domain:** WoW Midnight addon — Sated-family debuff detection, meta-buff timer, CDM tab Suggested section
**Confidence:** HIGH (spell IDs verified via Wowhead; API patterns verified via wow-ui-source)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Lust Data Model**
- D-01: Lust meta-buff stored in `trackedBuffs` under the string key `"lust"` (not a numeric spellID). Code that assumes numeric keys must be guarded. Document the string-key convention where relevant.
- D-02: The lust entry has standard fields (label, duration, section, layoutOrder) plus a `metaBuff = true` flag. Duration = 40 seconds for all lust variants.
- D-03: Meta-buff does NOT lock out manual tracking of individual lust spellIDs. `trackedBuffs["lust"]` and `trackedBuffs[2825]` can coexist independently. Meta triggers from Sated debuff detection; manual triggers from UNIT_SPELLCAST_SUCCEEDED.

**Suggested Section Behavior**
- D-04: Suggested is a static catalog of recommended buffs. Lust is the first entry.
- D-05: Dragging FROM Suggested to bars/buffs/hidden: if buff not yet in user DB, copies it (creates entry). If already tracked, moves it to the target section. The icon always remains in Suggested.
- D-06: Suggested is NOT a valid drop target.
- D-07: Removing a once-suggested buff removes from user DB only. Icon stays in Suggested.
- D-08: Right-click context menu on Suggested icons offers: "Add to Bars" / "Add to Buffs". No "Remove" option.
- D-09: Set up this logic generically so future suggested buffs can be added with minimal code.

**Debuff Detection Logic**
- D-10: Use UNIT_AURA `addedAuras` list to detect newly applied debuffs only. Do NOT scan for existing debuffs.
- D-11: For each entry in `addedAuras`, check if its spellId is secret via `issecretvalue()`. If secret, skip that entry (not the whole event). If non-secret, match against known Sated-family debuff spellIDs.
- D-12: On match: start a lust timer with `source = "debuff"`. This means `ScanActiveTimersForCancellation` will NOT touch it (it only scans `source = "cast"` timers).
- D-13: Research phase must find all Sated-family debuff spellIDs and their corresponding lust buff spellIDs.

**CDM Tab Presentation**
- D-14: Lust icon in CDM tab: class-aware via `UnitClass("player")` at load time. Shaman → Bloodlust icon, Mage → Time Warp icon, Evoker → Fury of the Aspects icon, others → Bloodlust icon (default).
- D-15: Gray subtext "Matches all Heroism/Bloodlust effects" in tooltip only (AddLine in OnEnter handler).
- D-16: Running timer icon uses the icon of the actual detected lust spell (resolved from Sated debuff → lust spell mapping), NOT the player's class lust.

**Drums Support**
- D-17: Current season drums (spellID 1243972, Void-touched Drums) trigger the same 40s lust meta-buff timer.

**Carried Forward**
- Phase 8 D-04: `source = "cast"` on cast-originated timers. Lust uses `source = "debuff"`.
- Phase 7: Debug logging via `/tbt debug`.

### Claude's Discretion

None specified — all implementation details are locked via D-01 through D-17.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LUST-01 | Addon detects Sated/Exhaustion/Temporal Displacement/etc. debuffs appearing and auto-starts a lust timer | Sated-family debuff spellIDs documented below; addedAuras iteration pattern verified in CooldownViewer.lua |
| LUST-02 | Lust is represented as a single meta-buff in the CDM tab (one icon for all lust variants) | String-key "lust" in trackedBuffs; ns.SUGGESTED_BUFFS registry pattern defined |
| LUST-03 | Meta-buff icon defaults to Shaman Bloodlust; uses class-specific lust icon if player's class has one | UnitClass("player") returns classFilename ("SHAMAN", "MAGE", "EVOKER") — class-to-spellID map defined below |
| LUST-04 | CDM tab entry shows gray detail text "Matches all Heroism/Bloodlust effects" | GameTooltip:AddLine with gray RGB (0.5, 0.5, 0.5) in OnEnter; tooltip pattern already used in CreateIconFrame |
| LUST-05 | Current season drums are supported as a lust source | Void-touched Drums = spellID 1243972 confirmed; debuff it applies is in Sated family (triggers Exhausted 10min debuff) |
</phase_requirements>

---

## Summary

Phase 10 adds automatic lust timer detection. When a Sated-family debuff appears in `addedAuras`, TBT starts a 40-second timer under the `"lust"` key. The CDM tab gains a functional Suggested section with lust as the first catalog entry.

All spell IDs for the Sated-family debuffs are verified (HIGH confidence for most; MEDIUM for Drums-specific debuff ID). The `addedAuras` iteration pattern is confirmed from Blizzard's CooldownViewer source. `issecretvalue()` per-entry guarding is the correct approach per CONTEXT.md D-11 and is consistent with how the Cell addon handled Midnight compatibility.

The CDM tab Suggested section currently has placeholder infrastructure (section key exists in SECTION_DEFS but the `if def.key ~= "suggested"` branch skips all item population). The right-click handler also has an early return for `sectionName == "suggested"`. Both need to be replaced with the copy-on-drag and catalog behavior specified in D-04 through D-09.

**Primary recommendation:** Implement lust detection in `BuffEngine.lua:OnUnitAura` after the existing guard chain, using the Sated-debuff-to-lust-spell mapping table. Implement Suggested section as a populated catalog in `CDMTab.lua`, driven by `ns.SUGGESTED_BUFFS` registry.

---

## Standard Stack

### Core (no new dependencies)

| API | Source | Purpose | Notes |
|-----|--------|---------|-------|
| `UNIT_AURA` + `addedAuras` | WoW Midnight API | Detect newly applied debuffs | Already registered in Core.lua; `addedAuras` field has `ConditionalSecretContents` |
| `issecretvalue(value)` | WoW global Lua | Per-value secret check before comparisons | Global function, no namespace. Check `aura.spellId` before matching |
| `UnitClass("player")` | WoW API | Class-aware icon selection at load time | Returns `(localizedName, classFilename, classId)` |
| `C_Spell.GetSpellTexture(spellID)` | WoW API | Get icon texture for a lust spell | Already used indirectly via ns:GetSpellIcon |
| `ns:GetSpellIcon(spellID)` | BuffEngine.lua | Existing icon resolver | Uses `C_Spell.GetSpellInfo(spellID).iconID` |
| `GameTooltip:AddLine(text, r, g, b)` | WoW API | Gray tooltip subtext | Already used in CreateIconFrame OnEnter |

No new packages or libraries required. All functionality is within existing WoW APIs and the existing TBT codebase.

---

## Sated-Family Spell ID Reference

This is the critical research deliverable for D-13. All debuff detection depends on this table.

### Lust Buff → Sated-Family Debuff Mapping

| Lust Buff | Lust SpellID | Class/Source | Sated Debuff | Debuff SpellID | Confidence |
|-----------|-------------|-------------|-------------|---------------|------------|
| Bloodlust | 2825 | Shaman (Horde) | Sated | 57724 | HIGH — Wowhead confirmed |
| Heroism | 32182 | Shaman (Alliance) | Exhaustion | 57723 | HIGH — Wowhead confirmed |
| Time Warp | 80353 | Mage | Temporal Displacement | 80354 | HIGH — Wowhead confirmed |
| Fury of the Aspects | 390386 | Evoker | Exhaustion | 390435 | HIGH — Wowhead confirmed (different Exhaustion from Heroism's) |
| Primal Rage | 264667 | Hunter pet (Ferocity) | Sated | 57724 | MEDIUM — Wowhead states "become Sated"; modern retail spell |
| Void-touched Drums | 1243972 | Leatherworking consumable (Midnight) | Exhausted | 57723 or 390435 | LOW — applies "Exhausted" per Wowhead description but specific debuff spellID not confirmed in sources |

**Important distinctions:**
- Heroism (57723) and Fury of the Aspects (390435) both apply an "Exhaustion" debuff, but they are DIFFERENT spell IDs. Both must be in the detection table.
- Bloodlust and modern Primal Rage both apply Sated (57724) — one detect covers both.
- Void-touched Drums debuff ID needs in-game verification. The description says "Exhausted (10 min)" which matches Heroism's 57723, but it could be 390435 or a new Midnight-specific ID.

### Recommended Detection Table

```lua
-- Maps Sated-family DEBUFF spellID → corresponding LUST BUFF spellID (for icon resolution)
ns.SATED_DEBUFF_TO_LUST = {
    [57724]  = 2825,   -- Sated → Bloodlust (covers Bloodlust + Primal Rage)
    [57723]  = 32182,  -- Exhaustion → Heroism (covers Heroism + possibly Drums)
    [80354]  = 80353,  -- Temporal Displacement → Time Warp
    [390435] = 390386, -- Exhaustion (Evoker) → Fury of the Aspects
}
```

The Drums debuff ID (likely 57723 based on description) should be added once confirmed in-game. The planner should add a task to verify the Drums debuff ID in-game and update this table if needed.

### Class-Aware CDM Icon Map

```lua
-- Use UnitClass("player") — second return value is classFilename (locale-independent)
local _, classFilename = UnitClass("player")
local CLASS_LUST_SPELL = {
    SHAMAN = 2825,   -- Bloodlust
    MAGE   = 80353,  -- Time Warp
    EVOKER = 390386, -- Fury of the Aspects
}
local cdmIconSpellID = CLASS_LUST_SPELL[classFilename] or 2825  -- default: Bloodlust
```

UnitClass return values verified against Warcraft Wiki: `(localizedName, classFilename, classId)` where classFilename is always uppercase English ("SHAMAN", "MAGE", "EVOKER", etc.).

---

## Architecture Patterns

### Recommended Project Structure (additions only)

No new files. Changes are confined to:
- `BuffEngine.lua` — lust debuff detection in `OnUnitAura`, `ns.SATED_DEBUFF_TO_LUST` table, lust timer creation
- `CDMTab.lua` — Suggested section population from `ns.SUGGESTED_BUFFS`, drag/right-click handlers for Suggested, lust tooltip gray text

### Pattern 1: Lust Timer Seeding in InitBuffEngine

The lust meta-buff must be pre-seeded into `trackedBuffs` if not already present. This ensures it appears in the CDM tab even for existing users upgrading.

```lua
-- In ns:InitBuffEngine(), after schema migrations:
if not ns.db.trackedBuffs["lust"] then
    local maxOrder = 0
    for _, e in pairs(ns.db.trackedBuffs) do
        if e.layoutOrder and e.layoutOrder > maxOrder then
            maxOrder = e.layoutOrder
        end
    end
    ns.db.trackedBuffs["lust"] = {
        key      = "lust",
        label    = "Lust / Heroism",
        duration = 40,
        section  = "hidden",  -- lands in Not Displayed by default
        layoutOrder = maxOrder + 1,
        metaBuff = true,
    }
end
```

This is a schema migration step (bump CURRENT_SCHEMA_VERSION to 3).

### Pattern 2: addedAuras Debuff Detection in OnUnitAura

Insert AFTER the existing `ScanActiveTimersForCancellation()` call. The existing guard chain (ShouldAurasBeSecret → isFullUpdate → previewActive) must remain first.

```lua
-- Source: CONTEXT.md D-10, D-11, D-12; verified against CooldownViewer.lua:1601
function ns:OnUnitAura(updateInfo)
    -- [existing guards: ShouldAurasBeSecret, isFullUpdate, previewActive]
    ns:ScanActiveTimersForCancellation()

    -- D-10: Only check addedAuras (newly applied debuffs)
    if updateInfo and updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            -- D-11: Per-entry secret check before any field access
            if not issecretvalue(aura.spellId) then
                local lustSpellID = ns.SATED_DEBUFF_TO_LUST[aura.spellId]
                if lustSpellID then
                    ns:StartLustTimer(lustSpellID)
                end
            end
        end
    end
end
```

**Critical:** `issecretvalue(aura.spellId)` must be called before `ns.SATED_DEBUFF_TO_LUST[aura.spellId]`. Indexing a table with a secret value produces a Lua error ("table index is secret").

### Pattern 3: Lust Timer Creation

```lua
-- D-12: source = "debuff" so ScanActiveTimersForCancellation skips it
-- D-16: icon = icon of actual detected lust spell, not player class lust
function ns:StartLustTimer(lustSpellID)
    local entry = ns.db.trackedBuffs["lust"]
    if not entry or entry.section == "hidden" then
        return
    end
    -- Don't restart if timer is already running from this lust event
    -- (addedAuras can fire multiple times in one event for the same aura)
    local existing = ns.activeTimers["lust"]
    if existing and existing.expiresAt > GetTime() then
        return
    end
    local now = GetTime()
    ns.activeTimers["lust"] = {
        spellID   = "lust",   -- string key, consistent with trackedBuffs key
        expiresAt = now + 40,
        startedAt = now,
        duration  = 40,
        icon      = ns:GetSpellIcon(lustSpellID),  -- actual lust spell icon
        label     = entry.label or "Lust / Heroism",
        section   = entry.section or "bars",
        source    = "debuff",
    }
    if ns.debugLogging then
        print("|cff00ccffTBT Debug|r: Lust detected (spellID " .. lustSpellID .. "), timer started.")
    end
    if ns.UpdateDisplay then
        ns:UpdateDisplay()
    end
end
```

### Pattern 4: Suggested Section Registry

```lua
-- Defined at module level in BuffEngine.lua (or CDMTab.lua init):
-- Pre-seeded before CDMTab builds sections
ns.SUGGESTED_BUFFS = {
    {
        key          = "lust",
        label        = "Lust / Heroism",
        duration     = 40,
        metaBuff     = true,
        -- CDM icon spellID resolved at display time via UnitClass
        getCDMSpellID = function()
            local _, classFilename = UnitClass("player")
            local CLASS_LUST_SPELL = {
                SHAMAN = 2825,
                MAGE   = 80353,
                EVOKER = 390386,
            }
            return CLASS_LUST_SPELL[classFilename] or 2825
        end,
    },
}
```

### Pattern 5: Suggested Section Drag (Copy-on-Drag)

The current CDMTab.lua `OnMouseDown` handler skips drag for `sectionName == "suggested"` (line 59). This must be changed to allow drag but route it through copy-on-drag logic in `BeginDrag`/`EndDrag`.

```lua
-- In BeginDrag: set tbtDragState.isFromSuggested = true
-- In EndDrag (on drop to valid section):
if tbtDragState.isFromSuggested then
    local suggestedDef = ns.SUGGESTED_BUFFS[tbtDragState.suggestedKey]
    if suggestedDef then
        local existing = ns.db.trackedBuffs[suggestedDef.key]
        if existing then
            ns:SetBuffSection(suggestedDef.key, dropSection)
        else
            -- Create new entry from suggested def
            ns.db.trackedBuffs[suggestedDef.key] = {
                key      = suggestedDef.key,
                label    = suggestedDef.label,
                duration = suggestedDef.duration,
                section  = dropSection,
                layoutOrder = (maxOrder + 1),
                metaBuff = suggestedDef.metaBuff,
            }
        end
    end
    -- Icon remains in Suggested (no removal)
end
```

### Anti-Patterns to Avoid

- **Indexing aura.spellId before issecretvalue check:** Produces "table index is secret" Lua error in restricted contexts. Always call `issecretvalue(aura.spellId)` first.
- **Scanning all auras for Sated debuff:** Use `addedAuras` only (D-10). Do not call `C_UnitAuras.GetPlayerAuraBySpellID` for Sated debuffs — that API returns nil for debuffs on the player (it checks buffs, not debuffs). Sated is a debuff, not a buff.
- **Using numeric key for lust timer:** `ns.activeTimers["lust"]` uses the string key consistently. Do not use a spellID as the timer key for lust.
- **Restarting lust timer on each addedAuras entry:** Multiple aura entries can appear per UNIT_AURA event. Guard with an early return if a non-expired lust timer already exists.
- **Blocking the whole addedAuras check when any entry is secret:** D-11 specifies per-entry checks. Skip the individual secret entry, not the whole loop.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Class name lookup | String parsing of localized class names | `UnitClass("player")` second return value (classFilename) | Locale-independent; "SHAMAN" not "Chamán" |
| Spell icon resolution | Custom texture path lookup | `ns:GetSpellIcon(spellID)` (existing) | Already handles fallback |
| Secret value detection | Try/catch or pcall wrapping | `issecretvalue(value)` global | Official Blizzard API; zero overhead on non-secret values |
| Context menu | Custom popup frame | `MenuUtil.CreateContextMenu` | Already used in CDMTab.lua |

---

## Current CDMTab.lua State: Suggested Section

### What Exists (WIP placeholders)

The Suggested section infrastructure exists but is intentionally unpopulated:

1. **SECTION_DEFS line 31:** `{ key = "suggested", title = "Suggested (WIP)" }` — section exists, title is "WIP"
2. **RefreshTBTSections line 598:** `if def.key ~= "suggested" then` — skips all item population for Suggested
3. **OnMouseDown line 59:** `if button == "LeftButton" and self.spellID and self.sectionName ~= "suggested" then` — blocks drag from Suggested
4. **OnMouseUp line 99:** `if sectionName == "suggested" then return end` — blocks right-click menu for Suggested
5. **BuildAllSections line 752:** The "Add Buff" square (+ button) is added to `suggestedSection.container` as `layoutIndex = 1` — this was placeholder positioning

### What Must Change

- SECTION_DEFS title: `"Suggested (WIP)"` → `"Suggested"`
- `RefreshTBTSections`: replace `if def.key ~= "suggested"` branch with Suggested catalog population using `ns.SUGGESTED_BUFFS`
- `OnMouseDown`: allow drag from Suggested (set `isFromSuggested` flag in drag state)
- `OnMouseUp`: replace early return with special Suggested right-click menu ("Add to Bars" / "Add to Buffs", no Remove)
- `BuildAllSections`: the Add Buff + square should move to `layoutIndex = 2` once the lust icon occupies `layoutIndex = 1`, or simply remove it from Suggested (it's confusing next to static catalog items). This is a planner decision — flag it.
- Lust icon tooltip: add `GameTooltip:AddLine("Matches all Heroism/Bloodlust effects", 0.5, 0.5, 0.5)` in the OnEnter handler (only for `metaBuff = true` entries)

### Tooltip Pattern for Meta-Buff Gray Text

```lua
-- Source: existing CreateIconFrame OnEnter handler pattern (CDMTab.lua lines 69-90)
-- For metaBuff entries, append gray subtext after the spell tooltip:
if entry and entry.metaBuff then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Matches all Heroism/Bloodlust effects", 0.5, 0.5, 0.5)
end
GameTooltip:Show()
```

---

## Common Pitfalls

### Pitfall 1: "Table Index Is Secret" on aura.spellId

**What goes wrong:** Accessing `ns.SATED_DEBUFF_TO_LUST[aura.spellId]` when `aura.spellId` is a secret value causes a Lua error: "table index is secret".
**Why it happens:** `addedAuras` has `ConditionalSecretContents`. In M+, rated PvP, and encounter contexts, `spellId` is opaque.
**How to avoid:** Always call `issecretvalue(aura.spellId)` before using the value as a table key. Skip the entry if true.
**Warning signs:** Lua error in restricted content (M+, rated PvP). No error in open world.

### Pitfall 2: GetPlayerAuraBySpellID Returns Nil for Debuffs

**What goes wrong:** Using `C_UnitAuras.GetPlayerAuraBySpellID(57724)` to check if Sated is active — returns nil even when Sated is present.
**Why it happens:** This API returns player buffs (HELPFUL auras). Sated is a debuff (HARMFUL). Buff and debuff slots are separate.
**How to avoid:** Use `addedAuras` event detection (D-10). If a presence check is needed, use `AuraUtil.ForEachAura("player", "HARMFUL", ...)`.
**Warning signs:** Lust timer never starts, or debug log shows Sated detected but timer check fails.

### Pitfall 3: Lust Timer Cancelled by ScanActiveTimersForCancellation

**What goes wrong:** The lust timer starts but is immediately cancelled on the next UNIT_AURA event because Sated is not found by `C_UnitAuras.GetPlayerAuraBySpellID`.
**Why it happens:** `ScanActiveTimersForCancellation` uses `GetPlayerAuraBySpellID` which only checks buffs, not debuffs. And `source = "debuff"` guard was not implemented.
**How to avoid:** D-12 specifies `source = "debuff"` on the lust timer. `ScanActiveTimersForCancellation` already guards `if timer.source == "cast"` — lust timers with `source = "debuff"` are skipped automatically.
**Warning signs:** Lust timer appears briefly then vanishes.

### Pitfall 4: String Key "lust" Breaks Numeric-Assuming Code

**What goes wrong:** `ns:AddTrackedBuff(spellID, duration, label)` line 100 checks `if not spellID or spellID <= 0` — this comparison fails for a string key.
**Why it happens:** D-01 introduces a string key into a table that previously had only numeric keys.
**How to avoid:** The lust entry is pre-seeded in `InitBuffEngine`, never added via `AddTrackedBuff`. String-key guards are needed in: `SetBuffSection`, `RemoveTrackedBuff`, `StartAllPreviewTimers`, and any loop iterating `trackedBuffs`. In most loops `for key, entry in pairs(...)` is already safe — the risk is only in operations that arithmetic-compare the key.
**Warning signs:** Lua error on `/tbt` open or any CDM tab refresh.

### Pitfall 5: Drums Debuff ID Mismatch

**What goes wrong:** Void-touched Drums apply "Exhausted" but the specific debuff spellID is not confirmed from web research. If it is a new Midnight-specific ID (not 57723 or 390435), it won't be detected.
**Why it happens:** Research could not confirm the exact spellID from available sources.
**How to avoid:** The planner should include a task to verify in-game: cast/use drums on PTR or live, check UNIT_AURA addedAuras, log `aura.spellId`. Add confirmed ID to `ns.SATED_DEBUFF_TO_LUST`.
**Warning signs:** Drums used in party but no lust timer starts.

---

## Code Examples

### addedAuras Iteration (from Blizzard CooldownViewer.lua)

```lua
-- Source: wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua:1601
if unitAuraUpdateInfo.addedAuras then
    for _, aura in ipairs(unitAuraUpdateInfo.addedAuras) do
        -- CDM accesses aura.spellId here (trusted code; no issecretvalue check)
        -- TBT must add issecretvalue check per D-11
    end
end
```

### NeedsAddedAuraUpdate Field Access (from CooldownViewer.lua:405)

```lua
-- Source: wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua:405
function CooldownViewerItemMixin:NeedsAddedAuraUpdate(auraInfo)
    if auraInfo.sourceUnit ~= "player" then  -- sourceUnit is safe to read
        return false;
    end
    local spellID = auraInfo.spellId;  -- spellId may be secret
    -- [further use of spellID]
end
```

Note: CDM does not call `issecretvalue()` because it is trusted Blizzard code that runs in a secure context. TBT must add this guard.

### SetAuraInstanceInfo (from CooldownViewerItemData.lua:228)

```lua
-- Source: wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua:228
-- Confirms field name is spellId (lowercase 'd'), not spellID
function CooldownViewerItemDataMixin:SetAuraInstanceInfo(auraInfo)
    local auraSpellID, auraInstanceID = auraInfo.spellId, auraInfo.auraInstanceID;
end
```

### UnitClass Usage

```lua
-- Source: Warcraft Wiki API_UnitClass (HIGH confidence)
local _, classFilename = UnitClass("player")
-- classFilename is always uppercase English: "SHAMAN", "MAGE", "EVOKER", "WARRIOR", etc.
-- Safe to use as table key; not subject to localization
```

### GameTooltip Gray Line

```lua
-- Source: existing CDMTab.lua OnEnter pattern (lines 69-90)
GameTooltip:AddLine("Matches all Heroism/Bloodlust effects", 0.5, 0.5, 0.5)
-- R=0.5, G=0.5, B=0.5 gives neutral gray
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| Ancient Hysteria / Netherwinds (Hunter pets) | Removed in BfA; replaced by Primal Rage | Do not add Ancient Hysteria/Netherwinds IDs |
| Fatigued (264689) from older Primal Rage variants | Modern Primal Rage (264667) applies Sated (57724) | Only track 57724 for Primal Rage in modern retail |
| Thunderous Drums / Timeless Drums (TWW) | Void-touched Drums (1243972) in Midnight | Only add Midnight drums; prior drums are out of scope (REQUIREMENTS.md LUST-F01) |

---

## Open Questions

1. **Void-touched Drums exact debuff spellID**
   - What we know: The drum effect description says "become Exhausted" with 10-minute duration. Two candidate IDs: Heroism's Exhaustion (57723) or Fury of the Aspects' Exhaustion (390435).
   - What's unclear: Whether Drums in Midnight apply one of these existing IDs or a new Midnight-specific ID.
   - Recommendation: Planner adds a Wave 1 task to verify in-game: use Void-touched Drums (spellID 1243972), observe UNIT_AURA addedAuras via debug print, log the debuff spellId. Update `ns.SATED_DEBUFF_TO_LUST` table accordingly. Tentative implementation: include 57723 initially (Heroism's Exhaustion is the most common drums debuff historically), add 390435 as well for completeness.

2. **"Add Buff" square in Suggested section**
   - What we know: Currently the + square is `layoutIndex = 1` in the Suggested container. Once lust icon is added at `layoutIndex = 1`, the + square needs to be at `layoutIndex = 2` or relocated.
   - What's unclear: Whether the + square belongs in Suggested at all, or whether it should be a standalone element outside the section.
   - Recommendation: Move + square to `layoutIndex` after all catalog icons. The Suggested section is for the catalog, and adding a new buff is a different action. Planner decides final layout.

3. **Primal Rage debuff ID cross-check**
   - What we know: Wowhead states modern Primal Rage (264667) applies Sated (57724). Older versions had their own debuff IDs.
   - What's unclear: Whether any Midnight-era change affected this.
   - Recommendation: 57724 is the safe assumption. If Primal Rage lust does not trigger a timer, verify in-game.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely code changes (Lua files only). No external tools, services, CLIs, or databases beyond the existing WoW addon environment.

---

## Validation Architecture

`workflow.nyquist_validation` is not set in `.planning/config.json` (absent = enabled). However, TBT has no automated test framework. This addon is validated exclusively in-game.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None (WoW addon — in-game testing only) |
| Config file | n/a |
| Quick run command | Deploy: `./scripts/install.bat` then launch WoW |
| Full suite command | Manual in-game checklist |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | In-Game Verification | Automatable? |
|--------|----------|-----------|---------------------|--------------|
| LUST-01 | Sated debuff triggers lust timer | manual | Have another player (or use a test dummy with a lust ability) apply a lust; verify 40s timer appears | No |
| LUST-01 | Temporal Displacement triggers lust timer | manual | Mage casts Time Warp; verify timer starts | No |
| LUST-01 | Fury of the Aspects triggers lust timer | manual | Evoker casts Fury; verify timer starts | No |
| LUST-01 | Timer uses correct icon for detected spell | manual | Verify icon matches the lust ability used, not player's class icon | No |
| LUST-02 | CDM tab shows lust as single meta-buff entry | manual | Open CDM tab; verify lust icon appears in Suggested | No |
| LUST-03 | Class-aware CDM icon | manual | Test on Shaman (Bloodlust), Mage (Time Warp), Evoker (Fury), Warrior (Bloodlust default) | No |
| LUST-04 | Gray tooltip subtext | manual | Hover over lust icon in CDM tab; verify gray "Matches all Heroism/Bloodlust effects" line | No |
| LUST-05 | Drums trigger lust timer | manual | Use Void-touched Drums (1243972); verify timer starts; also verify Drums debuff spellID | No |

### Wave 0 Gaps

None — no automated test infrastructure exists or is expected for this addon. All verification is manual in-game.

---

## Sources

### Primary (HIGH confidence)

- `wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` lines 1574–1612 — addedAuras iteration pattern, OnUnitAura handler
- `wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua` lines 228–235 — `auraInfo.spellId` field name (lowercase d confirmed)
- `wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` lines 405–419 — `NeedsAddedAuraUpdate` pattern accessing `auraInfo.spellId`
- `.planning/research/STACK.md` — issecretvalue() global, AuraData field reference, ConditionalSecretContents tags (verified from Blizzard APIDocumentation Lua files)
- `.planning/research/FEATURES.md` — addedAuras SecretContents classification, UNIT_AURA payload structure
- [Wowhead spell=57724](https://www.wowhead.com/spell=57724/sated) — Sated debuff, applied by Bloodlust
- [Wowhead spell=57723](https://www.wowhead.com/spell=57723/exhaustion) — Exhaustion debuff, applied by Heroism (spellID 32182)
- [Wowhead spell=80354](https://www.wowhead.com/spell=80354/temporal-displacement) — Temporal Displacement, applied by Time Warp
- [Wowhead spell=390435](https://www.wowhead.com/spell=390435/exhaustion) — Exhaustion (Evoker-specific), applied by Fury of the Aspects (390386)
- [Warcraft Wiki UnitClass](https://warcraft.wiki.gg/wiki/API_UnitClass) — `UnitClass("player")` return values

### Secondary (MEDIUM confidence)

- [Wowhead spell=264667](https://www.wowhead.com/spell=264667/primal-rage) — Modern Primal Rage applies Sated (57724)
- [Wowhead spell=1243972](https://www.wowhead.com/spell=1243972/void-touched-drums) — Void-touched Drums, Midnight leatherworking; applies "Exhausted" 10min debuff (specific ID unconfirmed)
- [Cell PR #457](https://github.com/enderneko/Cell/pull/457) — issecretvalue per-field guard pattern for Midnight addon compatibility

### Tertiary (LOW confidence)

- Drums exact debuff spellID — multiple candidates (57723, 390435); requires in-game verification

---

## Project Constraints (from CLAUDE.md)

- `COMBAT_LOG_EVENT_UNFILTERED` is disabled in Midnight — NOT used
- `UNIT_SPELLCAST_SUCCEEDED` is safe for cast detection — lust uses `addedAuras` instead (debuff, not cast)
- Requires Blizzard's CDM — no standalone fallback
- `ns.SATED_DEBUFF_TO_LUST` is a new module-level table; wipe() is NOT needed (it is a constant, not a per-frame scratch table)
- Namespace: `local addonName, ns = ...` — all new state on `ns`
- SavedVariables: lust entry in `TerribleBuffTrackerDB.trackedBuffs["lust"]` — persisted as per D-01
- Active timers are runtime-only — `ns.activeTimers["lust"]` is not persisted
- Run `stylua` on all Lua files after finishing task
- Deploy via `./scripts/install.bat` after changes

---

## Metadata

**Confidence breakdown:**
- Sated-family debuff spellIDs (Bloodlust/Heroism/TimeWarp/FuryOfAspects): HIGH — verified via Wowhead
- Primal Rage debuff (Sated 57724): MEDIUM — modern Wowhead states Sated, but older pet ability variants differ
- Drums debuff spellID: LOW — description confirms "Exhausted 10min" but exact spell ID unconfirmed
- addedAuras iteration pattern: HIGH — verified directly in Blizzard CooldownViewer source
- issecretvalue() per-entry usage: HIGH — confirmed in STACK.md, Cell PR pattern
- UnitClass("player") return format: HIGH — verified via Warcraft Wiki
- CDMTab Suggested section current state: HIGH — read directly from CDMTab.lua source

**Research date:** 2026-04-03
**Valid until:** 2026-07-03 (30 days for stable WoW API; spell IDs very stable once assigned)
