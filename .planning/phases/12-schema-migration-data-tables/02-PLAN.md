---
phase: 12-schema-migration-data-tables
plan: 02
type: execute
wave: 2
depends_on: [01]
files_modified:
  - BuffEngine.lua
  - CDMTab.lua
  - .planning/REQUIREMENTS.md
autonomous: true
requirements: [DATA-03]
must_haves:
  truths:
    - "ns.SUGGESTED_BUFFS contains 3 entries after BuffEngine.lua loads: lust, trinket, pot"
    - "Opening the CDM settings window shows trinket and pot entries in the Suggested section alongside lust, with no Lua errors"
    - "CDMTab.lua's Suggested section render falls through to getCDMIcon when getCDMSpellID returns nil"
    - "REQUIREMENTS.md traceability marks DATA-03 as N/A for v0.2.3 (no stale keys to migrate)"
    - "InitBuffEngine contains a comment explaining why v3 is terminal for v0.2.3 (D-05 rationale)"
    - "stylua passes with no changes on BuffEngine.lua and CDMTab.lua"
  artifacts:
    - path: "BuffEngine.lua"
      provides: "SUGGESTED_BUFFS entries for trinket and pot with getCDMIcon placeholder"
      contains: "key = \"trinket\""
    - path: "CDMTab.lua"
      provides: "Nil-safe Suggested section icon render (getCDMIcon fallback)"
      contains: "getCDMIcon"
    - path: ".planning/REQUIREMENTS.md"
      provides: "DATA-03 marked N/A with rationale"
      contains: "N/A"
  key_links:
    - from: "ns.SUGGESTED_BUFFS[trinket/pot entries]"
      to: "CDMTab.lua Suggested render loop"
      via: "getCDMSpellID returns nil, getCDMIcon fallback path"
      pattern: "suggested.getCDMIcon"
---

<objective>
Register the trinket and pot meta-trackers in ns.SUGGESTED_BUFFS so they appear in the CDM Suggested section, add a nil-safe icon fallback in the CDMTab Suggested render (prevents question-mark icon regression between Phase 12 and Phase 14), and reconcile the DATA-03 requirement discrepancy by documenting why no schema migration is needed for v0.2.3.

Purpose: Without the SUGGESTED_BUFFS entries, there is no UI surface for users to drag trinket/pot into Bars/Buffs in later phases. Without the nil guard, the render would display a question mark for trinket/pot until Phase 14 wires real icon resolution. Without the DATA-03 reconciliation, requirements coverage is ambiguous.
Output: Two new SUGGESTED_BUFFS entries, a 5-line nil guard in CDMTab.lua, a code comment in InitBuffEngine, and an updated traceability note in REQUIREMENTS.md.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/12-schema-migration-data-tables/12-CONTEXT.md
@.planning/phases/12-schema-migration-data-tables/12-RESEARCH.md
@.planning/phases/12-schema-migration-data-tables/12-01-SUMMARY.md
@CLAUDE.md
@BuffEngine.lua
@CDMTab.lua

<interfaces>
<!-- Existing lust SUGGESTED_BUFFS entry (BuffEngine.lua lines 50-64) — template for new entries -->
```lua
ns.SUGGESTED_BUFFS = {
    {
        key = "lust",
        label = "Lust / Heroism",
        duration = 40,
        metaBuff = true,
        getCDMSpellID = function()
            local _, classFilename = UnitClass("player")
            if classFilename == "HUNTER" then
                return GetHunterLustSpell()
            end
            return ns.CLASS_LUST_SPELL[classFilename] or 2825
        end,
    },
}
```

<!-- Existing CDMTab.lua Suggested render (lines 715-728) — target for nil guard insertion -->
```lua
if def.key == "suggested" then
    for i, suggested in ipairs(ns.SUGGESTED_BUFFS) do
        local item = section.itemPool:Acquire()
        local cdmSpellID = suggested.getCDMSpellID and suggested.getCDMSpellID() or 2825
        item.spellID = suggested.key
        item.Icon:SetTexture(ns:GetSpellIcon(cdmSpellID))
        -- ...
    end
end
```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Append trinket and pot entries to ns.SUGGESTED_BUFFS and document DATA-03 N/A in InitBuffEngine</name>
  <files>BuffEngine.lua</files>
  <read_first>
    - BuffEngine.lua lines 50-110 (existing SUGGESTED_BUFFS lust entry and InitBuffEngine schema ladder)
    - .planning/phases/12-schema-migration-data-tables/12-RESEARCH.md "Pattern 3" section (lines 165-213)
    - Prior plan summary: .planning/phases/12-schema-migration-data-tables/12-01-SUMMARY.md (confirms TRINKET_SPELLS/POT_SPELLS are in place on ns)
  </read_first>
  <action>
    1. Open BuffEngine.lua. Locate the `ns.SUGGESTED_BUFFS = { ... }` block (lines 50-64). It currently contains exactly one entry (lust).

    2. AFTER the closing `}` of `ns.SUGGESTED_BUFFS`, append two new entries using `ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = ...` (do NOT edit inside the literal — append after, per research Pattern 3). Insert these EXACTLY:

    ```lua
    -- Trinket meta-tracker (D-06). getCDMIcon is a Phase 14 placeholder; Phase 12 leaves it nil
    -- so the CDM render falls through to the 134400 question-mark fallback until Phase 14 wires
    -- ns:ResolveTrinketIcon(). duration=0 is a sentinel (D-07) — real duration comes from
    -- ns.TRINKET_SPELLS[spellID].duration at cast time.
    ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = {
        key = "trinket",
        label = "Trinket",
        duration = 0,
        metaBuff = true,
        getCDMSpellID = function() return nil end,
        getCDMIcon = nil, -- Phase 14: function() return ns:ResolveTrinketIcon() end
    }

    -- Damage pot meta-tracker (D-06). Same plumbing as trinket; itemID scanning is bag-based
    -- in Phase 14 (C_Item.GetItemCount against ns.POT_ITEM_IDS).
    ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = {
        key = "pot",
        label = "Damage Pot",
        duration = 0,
        metaBuff = true,
        getCDMSpellID = function() return nil end,
        getCDMIcon = nil, -- Phase 14: function() return ns:ResolvePotIcon() end
    }
    ```

    3. Inside `function ns:InitBuffEngine()` (line 66), directly BEFORE the line `local CURRENT_SCHEMA_VERSION = 3`, add this comment block explaining why v3 is terminal for v0.2.3 (DATA-03 reconciliation per research DATA-03 Discrepancy section):

    ```lua
        -- Schema v3 is terminal for v0.2.3 (DATA-03 reconciliation).
        -- v0.2.3 introduces trinket/pot meta-trackers but creates NO new persistent SavedVariables
        -- structures — TRINKET_SPELLS and POT_SPELLS are runtime-only static tables. The SUGGESTED_BUFFS
        -- entries for "trinket"/"pot" land in ns.db.trackedBuffs only via copy-on-drag (user action),
        -- and follow the existing string-keyed lust pattern that v3 already supports. Therefore no
        -- v3->v4 migration is needed: v0.2.3 is the first release with these features, so no stale
        -- "trinket"/"pot" keys can exist in pre-upgrade SavedVariables. D-05 (CONTEXT.md) supersedes
        -- REQUIREMENTS.md DATA-03; DATA-03 is marked N/A in REQUIREMENTS.md traceability.
    ```

    Preserve all existing code — do NOT modify the lust entry, do NOT bump CURRENT_SCHEMA_VERSION, do NOT add any `if ver < 4` block.

    Run stylua on BuffEngine.lua.
  </action>
  <verify>
    <automated>bash -c 'grep -q "key = \"trinket\"" BuffEngine.lua && grep -q "key = \"pot\"" BuffEngine.lua && grep -q "getCDMIcon = nil" BuffEngine.lua && grep -q "Schema v3 is terminal for v0.2.3" BuffEngine.lua && ! grep -q "CURRENT_SCHEMA_VERSION = 4" BuffEngine.lua'</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "key = \"trinket\"" BuffEngine.lua` returns 1
    - `grep -c "key = \"pot\"" BuffEngine.lua` returns 1
    - `grep -c "label = \"Trinket\"" BuffEngine.lua` returns 1
    - `grep -c "label = \"Damage Pot\"" BuffEngine.lua` returns 1
    - `grep -c "getCDMIcon = nil" BuffEngine.lua` returns 2 (one per new entry)
    - `grep -c "duration = 0" BuffEngine.lua` returns at least 2 (D-07 sentinel in both new entries)
    - `grep -q "Schema v3 is terminal for v0.2.3" BuffEngine.lua` succeeds
    - `grep -q "DATA-03" BuffEngine.lua` succeeds (traceability comment present)
    - `grep -c "CURRENT_SCHEMA_VERSION = 3" BuffEngine.lua` returns 1 (NOT 4)
    - `grep "CURRENT_SCHEMA_VERSION = 4" BuffEngine.lua` returns no matches
    - `grep "if ver < 4" BuffEngine.lua` returns no matches
    - stylua reports no changes on BuffEngine.lua
  </acceptance_criteria>
  <done>
    ns.SUGGESTED_BUFFS has 3 entries (lust, trinket, pot) after BuffEngine.lua loads. InitBuffEngine documents DATA-03 reconciliation. No schema version bump. stylua clean.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add getCDMIcon nil fallback to CDMTab.lua Suggested render</name>
  <files>CDMTab.lua</files>
  <read_first>
    - CDMTab.lua lines 715-728 (Suggested section render loop — exact current code)
    - .planning/phases/12-schema-migration-data-tables/12-RESEARCH.md "Pitfall 1" and Pattern 3 lines 198-213 (nil guard snippet)
    - BuffEngine.lua line 112-121 (ns:GetSpellIcon already handles nil by returning 134400 — guard is defensive, not corrective)
  </read_first>
  <action>
    In CDMTab.lua, locate the Suggested section render loop (starts at `if def.key == "suggested" then` around line 715). The current body (lines 718-728) sets the icon via:

    ```lua
    local cdmSpellID = suggested.getCDMSpellID and suggested.getCDMSpellID() or 2825
    item.spellID = suggested.key
    item.Icon:SetTexture(ns:GetSpellIcon(cdmSpellID))
    ```

    Replace those three lines with the following nil-aware version (preserve surrounding assignments to item.sectionName, item.suggestedIndex, item.layoutIndex, and item:Show()):

    ```lua
    -- Resolve at-rest icon: prefer getCDMSpellID (existing class-aware path for lust),
    -- fall through to getCDMIcon for itemID-based entries (trinket/pot — Phase 14 fills in),
    -- final fallback to 134400 question-mark. D-08 plumbing (research Pattern 3).
    local cdmSpellID = suggested.getCDMSpellID and suggested.getCDMSpellID()
    local iconID
    if cdmSpellID then
        iconID = ns:GetSpellIcon(cdmSpellID)
    elseif suggested.getCDMIcon then
        iconID = suggested.getCDMIcon() or 134400
    else
        iconID = 134400
    end
    item.spellID = suggested.key
    item.Icon:SetTexture(iconID)
    ```

    Do NOT change item.sectionName / item.suggestedIndex / item.layoutIndex / item:Show() — they remain as-is below this block. Do NOT change the `for i, suggested in ipairs(ns.SUGGESTED_BUFFS) do` loop header or its closing `end`.

    Run stylua on CDMTab.lua.
  </action>
  <verify>
    <automated>bash -c 'grep -q "suggested.getCDMIcon" CDMTab.lua && grep -q "iconID = 134400" CDMTab.lua && ! grep -q "getCDMSpellID() or 2825" CDMTab.lua'</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "suggested.getCDMIcon" CDMTab.lua` returns at least 1
    - `grep -c "iconID = 134400" CDMTab.lua` returns at least 1
    - `grep "getCDMSpellID() or 2825" CDMTab.lua` returns no matches (old hardcoded Bloodlust fallback removed from this render path)
    - `grep -c "item.Icon:SetTexture(iconID)" CDMTab.lua` returns 1
    - The Suggested render loop (around former line 715) still contains `for i, suggested in ipairs(ns.SUGGESTED_BUFFS) do`
    - stylua reports no changes on CDMTab.lua
  </acceptance_criteria>
  <done>
    CDMTab.lua's Suggested render resolves icons via cdmSpellID, then getCDMIcon, then 134400 fallback. Opening CDM settings in-game (after install.bat) shows lust icon as before, and trinket + pot entries appear with question-mark icons (Phase 14 will replace with real icons). No Lua errors. stylua clean.
  </done>
</task>

<task type="auto">
  <name>Task 3: Update REQUIREMENTS.md to mark DATA-03 as N/A for v0.2.3</name>
  <files>.planning/REQUIREMENTS.md</files>
  <read_first>
    - .planning/REQUIREMENTS.md lines 10-16 (Data section) and lines 58-78 (Traceability table)
    - .planning/phases/12-schema-migration-data-tables/12-RESEARCH.md "DATA-03 Discrepancy" section (lines 55-64)
  </read_first>
  <action>
    Edit .planning/REQUIREMENTS.md to reflect the DATA-03 reconciliation per research and D-05:

    1. Under `### Data`, update the DATA-03 line from:
    ```
    - [ ] **DATA-03**: Schema v4 migration handles any stale meta-tracker keys from prior sessions
    ```
    to:
    ```
    - [x] **DATA-03**: N/A for v0.2.3 — no schema migration needed. v0.2.3 is the first release introducing trinket/pot meta-trackers, so no stale `"trinket"` / `"pot"` keys can exist in pre-upgrade SavedVariables. Superseded by CONTEXT.md D-05 (no schema version bump). Covered by documentation comment in InitBuffEngine.
    ```

    2. In the Traceability table (lines 60-78), update the DATA-03 row from:
    ```
    | DATA-03 | Phase 12 | Pending |
    ```
    to:
    ```
    | DATA-03 | Phase 12 | N/A — documented (v0.2.3 first release with these features; no stale keys possible) |
    ```

    3. Update the `*Last updated:*` footer line at the bottom of the file to today's date:
    ```
    *Last updated: 2026-04-13 after Phase 12 planning (DATA-03 reconciled)*
    ```

    Do NOT modify any other requirement IDs or sections.
  </action>
  <verify>
    <automated>bash -c 'grep -q "DATA-03.*N/A for v0.2.3" .planning/REQUIREMENTS.md && grep -q "DATA-03 | Phase 12 | N/A" .planning/REQUIREMENTS.md'</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "DATA-03" .planning/REQUIREMENTS.md` returns at least 2 (data section + traceability row)
    - `grep -q "N/A for v0.2.3" .planning/REQUIREMENTS.md` succeeds
    - `grep -q "DATA-03 | Phase 12 | N/A" .planning/REQUIREMENTS.md` succeeds
    - `grep "Schema v4 migration handles any stale" .planning/REQUIREMENTS.md` returns no matches (old text removed)
    - File still lists DATA-01 and DATA-02 as Pending (unchanged)
    - Last-updated footer reads 2026-04-13
  </acceptance_criteria>
  <done>
    REQUIREMENTS.md clearly records DATA-03 as N/A for v0.2.3 with rationale, and the traceability table matches. No other requirements altered.
  </done>
</task>

</tasks>

<verification>
Manual in-game verification (follows CLAUDE.md workflow — run `./scripts/install.bat` then in-game `/reload`):

1. Open the CDM settings window (Edit Mode → cooldown manager → TBT tab). Confirm:
   - Suggested section shows 3 entries: Lust/Heroism (class-aware icon), Trinket (question-mark icon), Damage Pot (question-mark icon).
   - No red Lua errors in the default error frame.
2. Drag the Trinket entry into Bars. Confirm a new tracked entry with `duration = 0` sentinel appears (inspect via `/run print(TerribleBuffTrackerDB.trackedBuffs.trinket.duration)` → expect 0).
3. Drag the Pot entry into Buffs. Same check on `TerribleBuffTrackerDB.trackedBuffs.pot.duration` → 0.
4. `/reload` — no Lua errors. Schema version in DB remains 3 (`/run print(TerribleBuffTrackerDB.schemaVersion)` → 3).

Grep-level verification:
- BuffEngine.lua has 3 SUGGESTED_BUFFS entries (lust preserved, trinket + pot added).
- CDMTab.lua Suggested render uses getCDMIcon fallback path.
- REQUIREMENTS.md marks DATA-03 as N/A with rationale.
</verification>

<success_criteria>
- ns.SUGGESTED_BUFFS[2].key == "trinket" and ns.SUGGESTED_BUFFS[3].key == "pot" after load
- CDM Suggested section shows trinket and pot entries without Lua errors
- CDMTab.lua Suggested render uses the getCDMIcon fallback path (ready for Phase 14)
- InitBuffEngine documents DATA-03 N/A rationale
- REQUIREMENTS.md traceability table matches
- schemaVersion in SavedVariables stays at 3
- stylua clean on BuffEngine.lua and CDMTab.lua
</success_criteria>

<output>
After completion, create `.planning/phases/12-schema-migration-data-tables/12-02-SUMMARY.md` following the summary template. Note that the Phase 12 success criteria from ROADMAP.md item #4 ("schema version reads 4") is superseded by D-05 and should be read as "schema version reads 3 (terminal for v0.2.3)" — record this in the summary's decisions section for audit trail.
</output>
