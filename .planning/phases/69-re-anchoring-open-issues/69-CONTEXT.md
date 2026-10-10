# Phase 69: Re-anchoring Open Issues - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning
**Mode:** Smart discuss, front-loaded for the whole autonomous run (67-71) at the user's standing request

<domain>
## Phase Boundary

Fix the three issues the POC left open (`.planning/research/MERGE-REANCHOR-POC.md`, "Open issues"):
STEAL-13 reordering/moving an entry in the CDM settings window corrupts TBT's preview until the window
closes; STEAL-14 Edit Mode preview is missing merged bars; STEAL-15 a TBT container hidden by its
visibility setting still shows the moved frames.

</domain>

<decisions>
## Implementation Decisions

### STEAL-13 — settings-window reorder
- Rebuild the cooldownID → cell map **whole on every render pass** instead of patching it. An id not
  attached this pass loses its cell, so an entry that moved category (buff → bar) can never keep
  pointing at a cell in its old container.
- While previewing (CDM settings window or Edit Mode), a Blizzard `Layout` re-reads the mirror
  (already in the prototype). Diagnose why that is not enough — the user saw the moved buff in another
  container and bars mis-sized/misaligned until the window closed. Likely mid-drag `layoutIndex` reads
  and a stale map; fix the cause, don't add delays.

### STEAL-14 — Edit Mode bars
- Not diagnosed. Start from whether the bar viewer's frames are shown while editing and whether the
  bar container publishes merged slots in preview (`RefreshMergeShownSlots` preview path,
  `RenderBarContainer` example-slot logic, `MergedSlotsFor`).

### STEAL-15 — container visibility
- A hidden TBT container sends its merged frames **back to the parked, off-screen viewer** (not
  `SetAlpha(0)`): no new kind of write, and nothing invisible is left hoverable for tooltips. Showing
  the container re-attaches them. Applies to every hide path (visibility setting, hide when inactive,
  out of combat).

### Claude's Discretion
- Exact factoring; must keep STEAL-17 (no per-tick re-placement) intact.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MergeReanchor.lua` `cellByID` / `idByCell` / `placedOn` maps; `PlaceItem` already sends a frame with
  no cell back to its viewer.
- `Display.lua` container show/hide: `ShouldShow(...)`, `container:Hide()` early returns in
  `RenderIconContainer` / `RenderBarContainer`.

### Established Patterns
- Module-level tables `wipe()`d per pass; no per-tick allocation.

### Integration Points
- `EventRegistry` `CooldownViewerSettings.OnDataChanged` / `OnShow` / `OnHide`, `EditMode.Enter/Exit` in
  `MergeMode.lua`.

</code_context>

<specifics>
## Specific Ideas

- User report (POC round 3): "moving buffs on cdm config tab is still not working right, the preview
  gets all messed up with moved buff sometimes now showing on new container, bar size (or alignment)
  getting messed because of it." "Editmode preview is just missing the merged bars."
- In-game checks deferred to Phase 72.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
