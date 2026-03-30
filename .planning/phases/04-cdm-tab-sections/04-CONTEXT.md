# Phase 4: CDM Tab Sections - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Populate the TBT tab panel with 4 collapsible sections (Tracked Bars, Tracked Buffs, Not Displayed, Suggested) showing buff icons from the DB. Each buff appears as an icon with tooltip. Suggested section has an Add button (popup dialog for Spell ID + Duration). Not Displayed has a delete drop zone visual (non-functional until Phase 5 drag). Right-click context menu on icons for Move to Bars / Move to Buffs / Remove. No drag-and-drop in this phase.

</domain>

<decisions>
## Implementation Decisions

### Section layout & headers
- **D-01:** Vertical stack of 4 collapsible sections inside `ns.tbtScrollChild`. Order: Tracked Bars, Tracked Buffs, Not Displayed, Suggested.
- **D-02:** Collapsible headers matching CDM's own section style. Reference `ListHeaderThreeSliceTemplate` or CDM's category headers from Blizzard source for exact visual pattern.
- **D-03:** Each section header is clickable to collapse/expand its content area.

### Buff icon display
- **D-04:** Icons only (no label text inline). Spell icons in a flow/grid layout within each section.
- **D-05:** Tooltip on mouseover showing buff name, spell ID, and duration.
- **D-06:** Icon size and spacing should match CDM's own cooldown item style from Blizzard source.
- **D-07:** Buffs are placed in sections based on `entry.section` — "bars" → Tracked Bars, "buffs" → Tracked Buffs, "hidden" → Not Displayed.

### Add button behavior
- **D-08:** Add button appears in the Suggested section. Visual style matches CDM patterns.
- **D-09:** Clicking Add opens a popup dialog (small modal frame) with two input fields: Spell ID (number) and Duration (seconds). Add and Cancel buttons.
- **D-10:** On Add: calls `ns:AddTrackedBuff(spellID, duration)` which creates the entry with `section="hidden"`. The new buff appears in the Not Displayed section. Dialog closes.
- **D-11:** Validation: reject non-numeric or <= 0 values. Show inline error text in the dialog.

### Delete drop zone
- **D-12:** Not Displayed section shows a visible delete drop zone (visual placeholder). It is non-functional in Phase 4 — deletion via drop only works in Phase 5 when drag is implemented.
- **D-13:** Delete zone visual should be a distinct area (e.g., red-tinted or with a trash icon) so users understand its purpose even before drag works.

### Right-click context menu
- **D-14:** Right-clicking any buff icon shows a context menu using `MenuUtil.CreateContextMenu` (not deprecated UIDropDownMenu).
- **D-15:** Menu options vary by current section:
  - In Tracked Bars: "Move to Buffs", "Hide", "Remove"
  - In Tracked Buffs: "Move to Bars", "Hide", "Remove"
  - In Not Displayed: "Move to Bars", "Move to Buffs", "Remove"
  - In Suggested: no context menu (placeholder section)
- **D-16:** "Move to Bars" sets `entry.section = "bars"`. "Move to Buffs" sets `entry.section = "buffs"`. "Hide" sets `entry.section = "hidden"`. "Remove" calls `ns:RemoveTrackedBuff(spellID)`.
- **D-17:** After any context menu action, refresh the section display to reflect the change.

### Claude's Discretion
- Exact icon size (check CDM source for cooldown item dimensions)
- Grid vs flow layout implementation details
- Collapse animation (instant hide/show vs smooth transition)
- Delete zone icon/visual treatment
- Dialog frame positioning relative to CDM window

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing code
- `CDMTab.lua` — `ns.tbtPanel` and `ns.tbtScrollChild` are the parent frames for section content
- `BuffEngine.lua` — `ns:AddTrackedBuff()`, `ns:RemoveTrackedBuff()`, `ns.db.trackedBuffs` keyed by spellID, `entry.section` field
- `Display.lua` — `ns:UpdateDisplay()` must be called after section changes to refresh timer display

### Blizzard UI source
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — Category headers, cooldown item display, grid layout patterns
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — Category frame templates, item templates
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\LayoutFrame.lua` — GridLayoutFrame for icon grid

### Research
- `.planning/research/STACK.md` — MenuUtil.CreateContextMenu pattern, GridLayoutFrame usage
- `.planning/research/FEATURES.md` — Section management feature patterns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:GetSpellIcon(spellID)` in BuffEngine.lua — returns icon texture ID for any spell
- `ns:AddTrackedBuff(spellID, duration, label)` — already creates entry with section="hidden"
- `ns:RemoveTrackedBuff(spellID)` — removes from DB and active timers
- `ns.tbtScrollChild` — scroll child frame ready for section content (from Phase 3)
- `MenuUtil.CreateContextMenu` — modern WoW context menu API (replaces deprecated UIDropDownMenu)

### Established Patterns
- Namespace: `local _, ns = ...`
- DB access: `ns.db.trackedBuffs[spellID]` with section/duration/label fields
- CDM style: match Blizzard's own templates, no custom styling
- Phase 3 lesson: don't use parentArray or iterate CDM's secure arrays

### Integration Points
- `ns.tbtScrollChild` — parent frame for all section content
- `ns:UpdateDisplay()` — call after any section change to update timer bars/icons
- `ns:StartAllPreviewTimers()` — call after adding/removing buffs while CDM is open (ns.configOpen handles this)

</code_context>

<specifics>
## Specific Ideas

- Sections should visually match CDM's own category sections (Spells/Auras categories) — reference Blizzard source for exact templates
- Icons in grid should feel like CDM's own cooldown items
- Context menu should feel native — `MenuUtil.CreateContextMenu` with standard menu patterns

</specifics>

<deferred>
## Deferred Ideas

- Drag-and-drop between sections — Phase 5
- Delete via drag to drop zone — Phase 5
- Real buff suggestions in Suggested section — future milestone
- Edit Mode selection highlighting + per-element config panel — future

</deferred>

---

*Phase: 04-cdm-tab-sections*
*Context gathered: 2026-03-29*
