# Phase 2: Edit Mode Containers - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 02-edit-mode-containers
**Areas discussed:** Container naming & structure, CDM decoupling strategy, Edit Mode sidebar integration, Initial position copy

---

## Container Naming & Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Named UIParent children | Create TBTBarContainer and TBTBuffContainer as named frames parented to UIParent. Fully independent of CDM hierarchy. | ✓ |
| Named CDM children | Keep CDM as parent but add global names. Simpler, but CDM visibility/scaling affects TBT containers. | |
| You decide | Claude picks the best structure | |

**User's choice:** Named UIParent children
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Container is draggable | SetMovable(true) on the container itself during Edit Mode. Simpler, matches Blizzard pattern. | ✓ |
| Separate overlay handles | Create overlay frames with visible drag grip texture. More polish but more complexity. | |
| You decide | Claude picks based on Blizzard patterns | |

**User's choice:** Container is draggable
**Notes:** None

---

## CDM Decoupling Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Guard with flag | Keep hooks but guard: only run when no saved Edit Mode position. | |
| Remove entirely | Remove all CDM layout hooks. TBT containers use saved positions exclusively. | ✓ |
| You decide | Claude picks safest approach | |

**User's choice:** Remove entirely
**Notes:** Clean break from CDM anchoring

---

## Edit Mode Sidebar Integration

| Option | Description | Selected |
|--------|-------------|----------|
| TBT Bars / TBT Buffs | Two separate toggles matching container names | |
| TerribleBuffTracker (single) | One checkbox that toggles both containers together | ✓ |
| You decide | Claude picks labels matching Blizzard conventions | |

**User's choice:** TerribleBuffTracker (single)
**Notes:** Simpler — both containers toggle together

---

## Initial Position Copy

| Option | Description | Selected |
|--------|-------------|----------|
| DB field check | Copy CDM GetPoint() and GetScale() once if no saved position | |
| Default hardcoded | Don't copy from CDM — use hardcoded defaults. Avoids CDM timing issues. | ✓ |
| You decide | Claude picks safest approach | |

**User's choice:** Default hardcoded
**Notes:** Avoids CDM timing issues entirely

---

## Claude's Discretion

- Exact default position coordinates
- Visual border/highlight on containers during Edit Mode
- Empty state handling when no tracked buffs exist
- DB schema for editModePositions structure

## Deferred Ideas

None — discussion stayed within phase scope.
