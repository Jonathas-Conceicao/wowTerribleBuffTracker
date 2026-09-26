# Phase 36: User Containers & Per-Container Settings - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning
**Mode:** Decisions taken with the user up front, before the autonomous run

<domain>
## Phase Boundary

The player can create as many containers as they want beyond the four base ones, each configured
independently, and move trackers between any of them.

In scope: container creation and deletion (UI hosted in Phase 35.1's config panel), per-container
settings, and moving trackers between containers.

Out of scope: steal mode, which only ever targets the four base containers.
</domain>

<decisions>
## Implementation Decisions

### Creation and deletion
- Both live **in the config panel** from Phase 35.1, not in Edit Mode and not beside the tab's `+`
  button. Keeps the tracker list clean, and the panel is already being built.
- A new container appears in Edit Mode **and** as its own section in the CDM tab, alongside the four
  base ones — consistent with Phase 35's one-section-per-container decision.
- Base containers can never be deleted; user containers always can.

### Deleting a non-empty container
- Its trackers **move to Not Displayed**. The existing `"hidden"` section already means "tracked but not
  shown", so nothing is lost and the user can drag them back out.
- The confirm dialog **names the count before the user commits**. Nothing may silently disappear — that
  is the explicit success criterion.
- Rejected: moving them to a base container (silently rearranges a layout the user may care about), and
  blocking deletion while non-empty (turns one action into several).

### Per-container settings
- Every container — base and user-created alike — carries its own scale, padding, orientation,
  items-per-row and bar width.
- Changing one container's settings must leave every other container visually unchanged. This is the
  requirement most likely to regress, because today's `cachedBarSettings` / `cachedIconSettings` are two
  module-level singletons; they need to become per-container without turning into a per-frame read.

### Moving trackers
- Any container to any other, via the existing drag-and-drop between CDM tab sections.
- Placement survives `/reload`.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Drag-and-drop between sections already exists end to end (`CDMTab.lua`): ghost frame, drop-zone
  highlighting, CDM-style reorder marker, delete zone. Adding containers adds sections; the mechanism is
  untouched.
- `ns.db.containerSettings` already stores settings per container key, with `SnapshotSettings()`
  populating the caches. Generalising from two keys to N is the shape of this work.
- `VALID_DROP_SECTIONS` (`CDMTab.lua:47`) is the allow-list of drop targets and becomes dynamic.

### Established Patterns
- Settings are cached via `SnapshotSettings()` on load, layout hooks and `EditMode.Exit` — never read
  per-frame. Whatever replaces the two singleton caches must preserve that.
- Reusable module-level tables are `wipe()`d each cycle rather than reallocated, because `UpdateDisplay`
  is a hot path.
- `layoutOrder` on each entry drives ordering within a section.

### Integration Points
- `Display.lua:UpdateDisplay` currently hard-splits into `barTimers` / `iconTimers`. Phase 35 turns that
  into per-container grouping; this phase makes the container set dynamic.
- Edit Mode registration in `EditModeFrames.lua` is currently two hardcoded frames created at load. User
  containers can be created at runtime, so creation and teardown need to work after load — including
  while Edit Mode is open.
</code_context>

<specifics>
## Specific Ideas

"add possibility for a user to creat extra containers so they can use them as they see fit", with **full
per-container settings** chosen over a name/position-only model.
</specifics>

<deferred>
## Deferred Ideas

- No cap on the number of containers was set. If one proves necessary, it is a later decision.
- Renaming a user container was never requested; only create and delete. Do not add it speculatively.
</deferred>
