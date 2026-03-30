# Phase 2: Edit Mode Containers - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Create two independently movable container frames for bars and buffs, registered with WoW's Edit Mode system. Containers are parented to UIParent (decoupled from CDM), persist position across reloads, and appear in the Edit Mode sidebar as a single toggleable checkbox. No changes to the CDM tab UI or drag-and-drop in this phase.

</domain>

<decisions>
## Implementation Decisions

### Container naming & structure
- **D-01:** Create `TBTBarContainer` and `TBTBuffContainer` as globally named frames parented to UIParent. Fully independent of CDM frame hierarchy. This allows Edit Mode anchor serialization to work correctly (GetName() returns a valid string).
- **D-02:** The containers themselves become draggable during Edit Mode via `SetMovable(true)` / `EnableMouse(true)` — no separate overlay drag handle frames. Matches Blizzard's pattern for system frames.

### CDM decoupling strategy
- **D-03:** Remove all existing CDM layout hooks entirely — `SnapshotSettings()`, `HookViewerLayout()`, and the `EditMode.Exit` snapshot callback. TBT containers use saved positions from DB exclusively. No ongoing CDM coupling.
- **D-04:** The `SnapshotSettings()` function and related CDM-reading code can be deleted. Display.lua should be restructured around the new independent containers.

### Edit Mode sidebar integration
- **D-05:** Register a single checkbox labeled "TerribleBuffTracker" in the Edit Mode sidebar dialog. This one toggle controls visibility of both containers together (not separate toggles per container).

### Initial position copy
- **D-06:** Do NOT copy from CDM at all. Use hardcoded default positions for fresh installs (e.g., center-right of screen). Avoids CDM timing issues entirely.
- **D-07:** "Fresh install" is detected by checking if `ns.db.editModePositions` is nil.

### Claude's Discretion
- Exact default position coordinates for fresh installs
- Whether to show a visual border/highlight on containers during Edit Mode
- How to handle containers when no tracked buffs exist (empty state)
- DB schema for `editModePositions` structure (point, xOfs, yOfs, scale per container)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing code
- `Display.lua` — Current container creation (lines 357-371), SnapshotSettings (line 272), CDM layout hooks (lines 376-394). All must be restructured.
- `Core.lua` — ADDON_LOADED handler where DB is initialized. Must add `editModePositions` init.
- `BuffEngine.lua` — Uses `entry.section` to determine display. No changes needed for this phase but the section values ("bars"/"buffs"/"hidden") determine which container gets each buff.

### Blizzard UI source (research references)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.lua` — Edit Mode system registration patterns
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\EditModeManager.lua` — EventRegistry callbacks for EditMode.Enter/Exit
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewer.lua` — CDM viewer frame structure (the frames we're decoupling from)

### Research
- `.planning/research/ARCHITECTURE.md` — Edit Mode integration pattern, named frame requirement
- `.planning/research/PITFALLS.md` — Pitfall about Display.lua CDM hooks fighting Edit Mode (Pitfall 9), unnamed container frame anchor serialization issue

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `EventRegistry:RegisterCallback("EditMode.Exit", ...)` already exists in Display.lua line 391 — can be extended to handle position saving
- `ns.db` (TerribleBuffTrackerDB) is the established persistence mechanism — `editModePositions` is a natural addition
- `UpdateDisplay()` already handles bar/icon layout within containers — the layout logic stays, only the container anchoring changes

### Established Patterns
- Namespace: `local _, ns = ...` shared across files
- DB init: nil-check + default table in Core.lua ADDON_LOADED
- Container creation: `CreateFrame("Frame", name, parent)` with explicit anchoring
- Event-driven updates: EventRegistry for Edit Mode, OnUpdate for timer ticking

### Integration Points
- `Display.lua:InitDisplay()` — Where containers are created and CDM hooks installed. This is the main restructuring point.
- `Core.lua:ADDON_LOADED` — Must init `ns.db.editModePositions` default
- `Display.lua:UpdateDisplay()` — Layout logic within containers stays; container positioning is separate
- Edit Mode EventRegistry — `EditMode.Enter` to show drag handles + enable moving, `EditMode.Exit` to save positions and lock

</code_context>

<specifics>
## Specific Ideas

- Containers should feel like native Edit Mode elements — draggable in Edit Mode, locked otherwise
- The sidebar checkbox pattern should match how other addons register with Edit Mode (research needed for exact API)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-edit-mode-containers*
*Context gathered: 2026-03-28*
