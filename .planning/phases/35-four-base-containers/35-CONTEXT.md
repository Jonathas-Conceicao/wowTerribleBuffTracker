# Phase 35: Four Base Containers & Saved-Position Migration - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning
**Mode:** Decisions taken with the user up front, before the autonomous run

<domain>
## Phase Boundary

TBT's two Edit Mode containers become four, matching the CDM's own grouping, with existing layouts
carried over rather than reset.

In scope: the four base containers, their Edit Mode registration and position persistence, the CDM tab
sections that correspond to them, and the schema migration.

Out of scope: user-created containers and per-container settings (Phase 36), the config panel
(Phase 35.1), cooldown rendering (Phase 38). The two cooldown containers exist and are positionable here
but stay empty until Phase 38 gives them content — that is expected, not a gap.
</domain>

<decisions>
## Implementation Decisions

### The four containers
- Names are fixed and user-visible: **Tracked Buffs, Tracked Bars, Essential Cooldowns, Utility
  Cooldowns**. They mirror Blizzard's CDM categories deliberately, so steal mode in Phase 40 has an
  unambiguous destination.
- None may be renamed or deleted. No affordance for either appears anywhere.
- Each is independently movable with its own persisted position, exactly as the two existing ones are.

### CDM tab layout
- **One section per container.** The tab lists Tracked Buffs, Tracked Bars, Essential Cooldowns and
  Utility Cooldowns, then (from Phase 36) each user container, then Not Displayed and Suggested.
- This is the natural extension of what already exists: `entry.section` *is* the container, and
  `SECTIONS` in `CDMTab.lua` already pairs a key with a title. Drag-and-drop between sections keeps
  working unchanged because the mechanism is unchanged — only the list grew.
- Accepted cost: the tab gets long once many user containers exist. Rejected alternatives were
  accordion-style single-open sections and a container dropdown, both of which would have required
  reworking the existing drag-and-drop.

### Keys and migration
- **Keep the existing section keys.** `"bars"` stays the key for Tracked Bars and `"buffs"` for Tracked
  Buffs. Every `entry.section` already written by v0.3.0 is then correct with no rewriting, which makes
  the riskiest requirement (`CONT-03`) a no-op for tracker placement.
- Only two new keys are introduced, for the cooldown containers. Pick them to read as ids, not labels,
  and keep them stable — they become the mapping target for steal mode.
- `ns.db.editModePositions` currently holds `bars` and `icons`. `bars` carries straight over;
  `icons` becomes the Tracked Buffs position. Note the existing asymmetry (`buffs` section vs `icons`
  position key) and do not let it propagate into the two new entries.
- Bump `schemaVersion` and add the migration beside the existing three in `BuffEngine.lua`.
- The two cooldown containers start at defaults. Derive those from the existing bar/buff defaults
  (`ReadPoint(..., 300, 0)` / `(..., 300, -80)`) so nothing lands on top of the player's UI.

### Persistence testing
- `/reload` is **not** a persistence test — the data survives in memory and the check cannot fail. Only
  logout→login exercises the load path, and only on retail, since the Forever beta does not read saved
  variables back at all (a client bug, documented, not TBT's).
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WireSelectableDrag(overlay, container, containerKey)` in `EditModeFrames.lua` already abstracts a
  container's select-and-drag wiring per key — it extends to four callers without change.
- `ns:SelectContainer` / `ns:DeselectContainer` / `ns:ClearSelection` are keyed by a container string
  already; `selectedContainer` holds one key at a time.
- `SECTIONS` in `CDMTab.lua:40` is a plain ordered list of `{ key, title }`, and `VALID_DROP_SECTIONS`
  at `:47` lists the drop targets. Both are the extension points.
- `cachedBarSettings` / `cachedIconSettings` in `Display.lua` are the per-container settings caches;
  four containers means this pattern generalises rather than duplicates.

### Established Patterns
- Settings are snapshotted via `SnapshotSettings()` on load, layout hooks and `EditMode.Exit` — never
  read per-frame. Keep that.
- Schema migrations live in `BuffEngine.lua` guarded on `ns.db.schemaVersion`, each bumping the version
  at the end. Three exist; follow their shape.
- Reusable module-level tables are `wipe()`d each cycle in hot paths to avoid GC pressure.

### Integration Points
- `Display.lua:UpdateDisplay` splits timers into `barTimers` / `iconTimers` by `timer.section`. With
  four containers this becomes a per-container grouping rather than a two-way split.
- `EditModeFrames.lua:ShowEditModeHandles` applies minimum sizes so an empty container stays clickable;
  note the Phase 34 lesson that `UpdateDisplay` runs afterwards and can overwrite the height. The
  `EXAMPLE_BAR_SLOT` placeholder solves this for bars — the same treatment may be wanted for the new
  containers.
</code_context>

<specifics>
## Specific Ideas

The four names are the user's, chosen to mirror Blizzard's so steal mode reads naturally: "TBT will now
have 4 base containers (Tracked Buffs 0 and so on, mirroring blizzard), these should not be detable and
name should also be pinned down".
</specifics>

<deferred>
## Deferred Ideas

- Per-container settings UI — `CONT-06`, Phase 36.
- An example-icon placeholder for an empty *icon* container, mirroring `EDM-07`'s example bar. Not done
  in Phase 34 because the report was specific to bars; worth revisiting once four containers can each be
  empty.
</deferred>
