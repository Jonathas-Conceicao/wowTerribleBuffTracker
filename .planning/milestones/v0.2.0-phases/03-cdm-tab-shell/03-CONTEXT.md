# Phase 3: CDM Tab Shell - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Inject a "TBT Buffs" lateral tab button into Blizzard's Cooldown Manager settings window. Clicking it shows a TBT-owned content panel and hides the CDM scroll frame. Clicking back to a CDM tab restores CDM content. Remove the old standalone ConfigUI.lua. Rework /tbt to open CDM settings with TBT tab selected. No section content in this phase — the panel is an empty shell ready for Phase 4.

</domain>

<decisions>
## Implementation Decisions

### Tab button appearance
- **D-01:** Use `LargeSideTabButtonTemplate` for the tab button (43x55px), matching existing CDM tabs.
- **D-02:** Tab icon uses `hud-buff` atlas via SetAtlas. Can be changed during in-game verification if a better atlas is found.
- **D-03:** Tab label: "TBT Buffs" — short, clear, fits the tab width.

### Tab injection method
- **D-04:** Define the tab in an XML file with `parentArray="TabButtons"` so it registers at XML load time (research confirmed runtime CreateFrame does not auto-register into the TabButtons array).
- **D-05:** Never call `SetDisplayMode` with TBT strings — will crash with assertsafe. TBT manages its own tab checked state and content panel visibility independently.
- **D-06:** Hook `SetDisplayMode` via `hooksecurefunc` to detect when user clicks a CDM tab — use this to uncheck TBT tab and hide TBT panel.

### Content panel layout
- **D-07:** Content panel matches CDM's own scroll area style — same background, border, inset frame pattern. Include a scroll frame ready for Phase 4 sections.
- **D-08:** Panel is parented to CooldownViewerSettings and occupies the same area as CDM's category scroll frame.

### /tbt command rework
- **D-09:** /tbt always opens CDM settings with the TBT tab selected. Never closes/toggles. If CDM is already open on another tab, switch to TBT tab.
- **D-10:** Implementation: open CDM settings (if not open), then programmatically select the TBT tab.

### ConfigUI.lua removal
- **D-11:** Delete ConfigUI.lua entirely. All buff management functionality moves to CDM tab in Phase 4.
- **D-12:** Remove ConfigUI.lua from TerribleBuffTracker.toc.
- **D-13:** Remove `ns:ToggleConfigUI()` call from Core.lua slash command handler. Replace with the new /tbt behavior (D-09).
- **D-14:** `StartAllPreviewTimers()` and `ClearAllTimers()` stay in BuffEngine.lua (they already live there). No preview trigger from the shell — Phase 4 can add one.

### Preview on CDM open
- **D-15:** When CDM settings opens (any tab, not just TBT tab), call `ns:StartAllPreviewTimers()` to show all tracked buffs as preview bars/icons. This gives the user visual feedback of what they're configuring.
- **D-16:** When CDM settings closes, call `ns:ClearAllTimers()` to stop previews. Both functions already exist in BuffEngine.lua.

### Claude's Discretion
- Exact XML file name and structure for the tab button
- How to open CDM settings programmatically (may need to find the CDM settings toggle function)
- Content panel scroll frame implementation details
- Whether a new CDMTab.lua file is needed or if the tab logic goes in an existing file

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing code
- `Core.lua` — Slash command handler (lines 48-52) calling `ns:ToggleConfigUI()`. Must be reworked.
- `ConfigUI.lua` — File to delete. Check for any functionality that needs preserving (preview mode already in BuffEngine.lua).
- `TerribleBuffTracker.toc` — Must remove ConfigUI.lua, add new XML and CDMTab.lua files.

### Blizzard UI source
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewer.xml` — Tab button templates, parentArray="TabButtons", CooldownViewerSettingsTabTemplate
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewer.lua` — SetDisplayMode, SetupTabs, displayModeToCategories, tab click handling
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — Settings panel structure, scroll frame, category rendering

### Research
- `.planning/research/STACK.md` — CDM tab injection pattern, parentArray XML requirement, SetDisplayMode assertsafe warning
- `.planning/research/ARCHITECTURE.md` — New CDMTab.lua file recommendation, integration points
- `.planning/research/PITFALLS.md` — Pitfall about SetDisplayMode crash, COOLDOWN_VIEWER_DATA_LOADED timing

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `EventRegistry` pattern already established in EditModeFrames.lua — same pattern for CDM settings OnShow/OnHide
- `ns.db` persistence pattern for any tab-related settings
- `hooksecurefunc` pattern for hooking CDM functions safely

### Established Patterns
- Namespace: `local _, ns = ...` shared across files
- New files added to TOC between existing entries
- install.bat has hardcoded file list — must be updated for new files

### Integration Points
- `Core.lua` slash command — replace `ns:ToggleConfigUI()` with CDM settings + TBT tab selection
- `TerribleBuffTracker.toc` — add XML file and CDMTab.lua, remove ConfigUI.lua
- `scripts/install.bat` — add new files, remove ConfigUI.lua
- `CooldownViewerSettings` frame — parent for TBT content panel, hook target for tab switching

</code_context>

<specifics>
## Specific Ideas

- Tab should feel native — indistinguishable from Blizzard's own CDM tabs at first glance
- The content panel should be ready to receive Phase 4's sections without restructuring

</specifics>

<deferred>
## Deferred Ideas

- Edit Mode selection highlighting (yellow) + per-element config panel — mentioned by user during Phase 2 verification, belongs in a future phase
- Tab icon may change during verification — user wants to preview in-game first

</deferred>

---

*Phase: 03-cdm-tab-shell*
*Context gathered: 2026-03-29*
