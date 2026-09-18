# Phase 10: Lust Tracking - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect Sated-family debuffs appearing on the player and auto-start a lust timer. Single meta-buff entry in CDM tab with class-aware icon and tooltip. Activate the Suggested section as a real feature with proper copy-on-drag behavior for future expansion.

</domain>

<decisions>
## Implementation Decisions

### Lust Data Model
- **D-01:** Lust meta-buff stored in `trackedBuffs` under the string key `"lust"` (not a numeric spellID). Code that assumes numeric keys must be guarded. Document the string-key convention where relevant.
- **D-02:** The lust entry has standard fields (label, duration, section, layoutOrder) plus a `metaBuff = true` flag. Duration = 40 seconds for all lust variants.
- **D-03:** Meta-buff does NOT lock out manual tracking of individual lust spellIDs. `trackedBuffs["lust"]` and `trackedBuffs[2825]` can coexist independently. Meta triggers from Sated debuff detection; manual triggers from UNIT_SPELLCAST_SUCCEEDED.

### Suggested Section Behavior
- **D-04:** Suggested is a **static catalog** of recommended buffs. Lust is the first entry. More will be added in future versions.
- **D-05:** Dragging FROM Suggested to bars/buffs/hidden: if buff not yet in user DB, **copies** it (creates entry). If already tracked, **moves** it to the target section. The icon always remains in Suggested.
- **D-06:** Suggested is NOT a valid drop target — users cannot drag into it.
- **D-07:** Removing a once-suggested buff (via right-click "Remove" or drag to delete zone) removes from user DB only. Icon stays in Suggested.
- **D-08:** Right-click context menu on Suggested icons offers: "Add to Bars" / "Add to Buffs". No "Remove" option.
- **D-09:** Set up this logic generically so future suggested buffs can be added with minimal code (a registry/table of suggested buff definitions).

### Debuff Detection Logic
- **D-10:** Use UNIT_AURA `addedAuras` list to detect **newly applied** debuffs only. Do NOT scan for existing debuffs.
- **D-11:** For each entry in `addedAuras`, check if its spellId is secret (via `issecretvalue()`). If secret, skip that entry (not the whole event). If non-secret, match against known Sated-family debuff spellIDs.
- **D-12:** On match: start a lust timer with `source = "debuff"` (not "cast"). This means `ScanActiveTimersForCancellation` from Phase 8 will NOT touch it (it only scans `source = "cast"` timers).
- **D-13:** Research phase must find: all Sated-family debuff spellIDs and their corresponding lust buff spellIDs (Bloodlust, Heroism, Time Warp, Fury of the Aspects, Drums). Current season drums spellID = 1243972.

### CDM Tab Presentation
- **D-14:** Lust icon in CDM tab: class-aware via `UnitClass("player")` at load time. Shaman → Bloodlust icon, Mage → Time Warp icon, Evoker → Fury of the Aspects icon, others → Bloodlust icon (default).
- **D-15:** Gray subtext "Matches all Heroism/Bloodlust effects" in **tooltip only** (added as a gray `AddLine` in the OnEnter handler). No visual change to the 38x38 icon frame.
- **D-16:** **Running timer icon** uses the icon of the **actual detected lust spell** (resolved from the Sated debuff → corresponding lust spell mapping), NOT the player's class lust. If a Shaman receives Time Warp from a Mage, the timer shows Time Warp's icon.

### Drums Support
- **D-17:** Current season drums (spellID 1243972) trigger the same 40s lust meta-buff timer. Same meta-buff entry, same duration, same display behavior.

### Carried Forward
- Phase 8 D-04: `source = "cast"` on cast-originated timers. Lust uses `source = "debuff"` — not scanned by ScanActiveTimersForCancellation.
- Phase 7: Debug logging via `/tbt debug` — log lust detection events.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing CDM Tab Code
- `CDMTab.lua` lines 27-32 — SECTION_DEFS and section framework
- `CDMTab.lua` lines 43-94 — CreateIconFrame with tooltip, drag, and right-click handlers
- `CDMTab.lua` lines 96-140 — Right-click context menu per section
- `CDMTab.lua` lines 598-628 — Suggested section setup and Add square
- `CDMTab.lua` lines 628-800 — AddBuffDialog

### Timer System
- `BuffEngine.lua` lines 47-69 — OnSpellCastSucceeded timer creation (pattern for lust timer creation)
- `BuffEngine.lua` lines 212-241 — OnUnitAura + ScanActiveTimersForCancellation

### WoW API
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerItemData.lua` — CDM's addedAuras handling pattern

### Project Research
- `.planning/research/FEATURES.md` — Sated debuff detection patterns
- `.planning/research/STACK.md` — UNIT_AURA addedAuras payload, issecretvalue()

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CreateIconFrame` — existing icon frame factory, can be reused for Suggested section lust icon
- `ns:GetSpellIcon(spellID)` — existing icon resolver
- `ns:SetBuffSection(spellID, section)` — existing section assignment (needs string-key guard)
- `ns:RefreshTBTSections()` — single refresh entry point for all sections
- `VALID_DROP_SECTIONS` — must NOT include "suggested"

### Established Patterns
- Timer creation: `ns.activeTimers[key] = { spellID, expiresAt, startedAt, duration, icon, label, section, source }`
- Tooltip: `GameTooltip:AddLine(text, r, g, b)` for gray text lines
- Right-click menus: `MenuUtil.CreateContextMenu` with `rootDescription:CreateButton`
- Section iteration: `for _, entry in pairs(ns.db.trackedBuffs)` — must handle string keys

### Integration Points
- `BuffEngine.lua:OnUnitAura` — add debuff detection after existing guard chain
- `CDMTab.lua:SECTION_DEFS` — Suggested section activation
- `CDMTab.lua:CreateIconFrame` — tooltip modification for meta-buff
- `CDMTab.lua` drag handlers — copy-on-drag from Suggested
- `CDMTab.lua` right-click handlers — special menu for Suggested icons
- `BuffEngine.lua:InitBuffEngine` — pre-seed suggested registry

</code_context>

<specifics>
## Specific Ideas

- Suggested buff registry: a table like `ns.SUGGESTED_BUFFS = { lust = { key = "lust", label = "Lust / Heroism", ... } }` that defines all suggested buffs. CDM tab reads this to populate the Suggested section. Future buffs added by appending to this table.
- Sated → lust mapping table: `{ [satedSpellID] = lustSpellID }` for reverse lookup. When a Sated debuff is detected, look up which lust spell it corresponds to, use that spell's icon for the running timer.
- The `"lust"` key in activeTimers means the running timer key is also `"lust"` (not a spellID) — consistent with the DB key.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 10-lust-tracking*
*Context gathered: 2026-04-04*
