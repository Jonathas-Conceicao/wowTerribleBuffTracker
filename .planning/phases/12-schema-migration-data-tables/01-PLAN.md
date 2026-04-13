---
phase: 12-schema-migration-data-tables
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - BuffEngine.lua
autonomous: true
requirements: [DATA-01, DATA-02]
must_haves:
  truths:
    - "TRINKET_SPELLS table defines exactly 9 entries keyed by spellID with {duration, itemID} values matching trinket_info.csv"
    - "POT_SPELLS table defines exactly 4 entries keyed by spellID with {duration, itemID} values matching pots_info.csv"
    - "TRINKET_ITEM_IDS and POT_ITEM_IDS sets are derived at module load from the parent spell tables (not hand-maintained)"
    - "stylua passes with no changes required on BuffEngine.lua"
  artifacts:
    - path: "BuffEngine.lua"
      provides: "TRINKET_SPELLS, POT_SPELLS, TRINKET_ITEM_IDS, POT_ITEM_IDS module-level locals"
      contains: "local TRINKET_SPELLS"
  key_links:
    - from: "BuffEngine.lua module-level tables"
      to: "Phase 13 OnSpellCastSucceeded fan-out"
      via: "spellID-keyed O(1) lookup"
      pattern: "TRINKET_SPELLS\\[spellID\\]"
---

<objective>
Define the static data layer for trinket and pot meta-trackers: two module-level spellID-keyed tables (TRINKET_SPELLS, POT_SPELLS) transcribed verbatim from the CSV sources, plus itemID-keyed lookup sets derived at module load for Phase 14's equipment/bag scans.

Purpose: Phases 13-15 build on these tables unchanged. No schema migration is needed (per D-05 locked decision — v0.2.3 is first release with these features). This is a pure data addition.
Output: BuffEngine.lua module-level definitions added after the CLASS_LUST_SPELL block and before InitBuffEngine.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/12-schema-migration-data-tables/12-CONTEXT.md
@.planning/phases/12-schema-migration-data-tables/12-RESEARCH.md
@CLAUDE.md
@BuffEngine.lua
@trinket_info.csv
@pots_info.csv

<interfaces>
<!-- Existing template pattern (lines 12-18 BuffEngine.lua) — TRINKET_SPELLS/POT_SPELLS mirror this exactly -->
```lua
ns.SATED_DEBUFF_TO_LUST = {
    [57724] = 2825, -- Sated -> Bloodlust
    -- ... spellID-keyed static table, module-level local (exposed on ns)
}
```

<!-- New tables are local (not on ns) per D-01 and research Pattern 1. Phase 13 will access via closure from BuffEngine.lua or they may be promoted to ns at that time. Keep them local for this phase. -->
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add TRINKET_SPELLS, POT_SPELLS, and derived item ID sets to BuffEngine.lua</name>
  <files>BuffEngine.lua</files>
  <read_first>
    - BuffEngine.lua lines 1-65 (existing module-level static tables and SUGGESTED_BUFFS block — know exact insertion point)
    - .planning/phases/12-schema-migration-data-tables/12-RESEARCH.md sections "Pattern 1" and "Pattern 2" (pages covering lines 105-164) — verbatim table layout and derivation loops
    - trinket_info.csv and pots_info.csv — confirm values before writing
  </read_first>
  <action>
    Insert four new module-level `local` definitions into BuffEngine.lua, immediately AFTER the `ns.CLASS_LUST_SPELL = { ... }` block (ends at line 47) and BEFORE the `ns.SUGGESTED_BUFFS = { ... }` block (starts at line 50).

    Add these blocks in order:

    1. TRINKET_SPELLS table (spellID-keyed per D-01, names as comments per D-04). Transcribe ALL 9 entries VERBATIM from trinket_info.csv:

    ```lua
    -- Static lookup: spellID -> { duration, itemID } for tracked on-use trinkets (D-01).
    -- Names are comments only (D-04); labels come from C_Spell.GetSpellInfo at cast time.
    -- Source: trinket_info.csv. Duration is used at cast time; SUGGESTED_BUFFS.duration=0 is a sentinel (D-07).
    local TRINKET_SPELLS = {
        -- Light Company Guidon
        [1259633] = { duration = 15, itemID = 249344 },
        -- Vaelgor's Final Stare
        [1260459] = { duration = 15, itemID = 249346 },
        -- Emberwing Feather
        [1250508] = { duration = 15, itemID = 250144 },
        -- Algeth'ar Puzzle Box
        [383781]  = { duration = 20, itemID = 193701 },
        -- Echo of L'ura
        [250768]  = { duration = 45, itemID = 151340 },
        -- Radiant Sunstone
        [1254624] = { duration = 20, itemID = 252411 },
        -- Freightrunner's Flask
        [1250533] = { duration = 15, itemID = 250215 },
        -- Seed of Radiant Hope
        [1263644] = { duration = 12, itemID = 250254 },
        -- Void Execution Mandate
        [1250557] = { duration = 20, itemID = 250225 },
    }
    ```

    2. POT_SPELLS table (4 entries VERBATIM from pots_info.csv):

    ```lua
    -- Static lookup: spellID -> { duration, itemID } for tracked damage potions (D-01).
    -- Source: pots_info.csv.
    local POT_SPELLS = {
        -- Light's Potential
        [1236616] = { duration = 30, itemID = 241308 },
        -- Potion of Recklessness
        [1236994] = { duration = 30, itemID = 241288 },
        -- Draught of Rampant Abandon
        [1236998] = { duration = 30, itemID = 241292 },
        -- Void-Shrouded Tincture
        [1236551] = { duration = 12, itemID = 241302 },
    }
    ```

    3. Derived item ID sets (per D-02 — NOT hand-maintained, derived at module load). Place immediately after the spell tables:

    ```lua
    -- Derived at module load (D-02): itemID -> true sets for O(1) equipment/bag lookup in Phase 14.
    -- Do NOT hand-maintain; regenerate by iterating the parent spell tables.
    local TRINKET_ITEM_IDS = {}
    for _, def in pairs(TRINKET_SPELLS) do
        TRINKET_ITEM_IDS[def.itemID] = true
    end

    local POT_ITEM_IDS = {}
    for _, def in pairs(POT_SPELLS) do
        POT_ITEM_IDS[def.itemID] = true
    end
    ```

    4. Expose to ns so Phase 13 (timer functions) and Phase 14 (icon resolution) can read them without refactoring file structure:

    ```lua
    ns.TRINKET_SPELLS = TRINKET_SPELLS
    ns.POT_SPELLS = POT_SPELLS
    ns.TRINKET_ITEM_IDS = TRINKET_ITEM_IDS
    ns.POT_ITEM_IDS = POT_ITEM_IDS
    ```

    Preserve exact spellID / itemID / duration values — do NOT round, reformat numbers, or add extra entries. No name field inside the table per D-04.

    Do NOT add any schema migration code. Per D-05 and research DATA-03 Discrepancy section, CURRENT_SCHEMA_VERSION stays at 3. InitBuffEngine is untouched by this task.

    After editing, run stylua on BuffEngine.lua per CLAUDE.md workflow.
  </action>
  <verify>
    <automated>bash -c 'grep -c "^\s*\[.*\] = { duration" BuffEngine.lua' — expect at least 13 (9 trinkets + 4 pots). Also: grep -q "local TRINKET_SPELLS = {" BuffEngine.lua && grep -q "local POT_SPELLS = {" BuffEngine.lua && grep -q "local TRINKET_ITEM_IDS = {}" BuffEngine.lua && grep -q "local POT_ITEM_IDS = {}" BuffEngine.lua && grep -q "ns.TRINKET_SPELLS = TRINKET_SPELLS" BuffEngine.lua</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "\[12[0-9]*\] = { duration" BuffEngine.lua` returns at least 13 (allow for formatting variance; count entries with duration field)
    - `grep "\[1259633\] = { duration = 15, itemID = 249344 }" BuffEngine.lua` matches exactly one line (Light Company Guidon)
    - `grep "\[1236551\] = { duration = 12, itemID = 241302 }" BuffEngine.lua` matches exactly one line (Void-Shrouded Tincture)
    - `grep "\[250768\]" BuffEngine.lua` shows duration = 45, itemID = 151340 (Echo of L'ura — 45s is the outlier duration)
    - `grep "ns.TRINKET_SPELLS = TRINKET_SPELLS" BuffEngine.lua` matches exactly one line
    - `grep "ns.POT_SPELLS = POT_SPELLS" BuffEngine.lua` matches exactly one line
    - `grep "ns.TRINKET_ITEM_IDS = TRINKET_ITEM_IDS" BuffEngine.lua` matches exactly one line
    - `grep "ns.POT_ITEM_IDS = POT_ITEM_IDS" BuffEngine.lua` matches exactly one line
    - `grep -c "CURRENT_SCHEMA_VERSION = 3" BuffEngine.lua` returns 1 (NOT bumped to 4 per D-05)
    - `grep "if ver < 4" BuffEngine.lua` returns no matches (no new migration block)
    - stylua reports no changes needed on BuffEngine.lua
  </acceptance_criteria>
  <done>
    BuffEngine.lua contains TRINKET_SPELLS (9 entries), POT_SPELLS (4 entries), derived TRINKET_ITEM_IDS and POT_ITEM_IDS, all exposed on ns. Schema version still 3. stylua clean. File loads in WoW without Lua errors (manual verify: /reload in-game produces no error, addon enabled).
  </done>
</task>

</tasks>

<verification>
Manual in-game verification (Phase 12 has no automated test framework per 12-VALIDATION.md):
1. Run `./scripts/install.bat` to deploy.
2. Launch WoW, `/reload` — expect no Lua errors.
3. `/tbt` — config toggles cleanly.
4. Confirm `/dump ns.TRINKET_SPELLS` via a debug command (or verify next plan's CDM render) shows populated tables.

Code review:
- Line count of TRINKET_SPELLS entries == 9 (count `itemID =` occurrences within the block).
- Line count of POT_SPELLS entries == 4.
- Durations match CSV exactly: trinkets 15/15/15/20/45/20/15/12/20, pots 30/30/30/12.
</verification>

<success_criteria>
- All DATA-01 entries (9 trinket rows) present with correct spellID, itemID, duration
- All DATA-02 entries (4 pot rows) present with correct spellID, itemID, duration
- Derived item ID sets populated at module load
- No schema migration code added (D-05)
- stylua clean
- No Lua errors on /reload
</success_criteria>

<output>
After completion, create `.planning/phases/12-schema-migration-data-tables/12-01-SUMMARY.md` following the summary template.
</output>
