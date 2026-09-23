# Phase 34: Edit Mode Selection on Mouse-Down - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning

<domain>
## Phase Boundary

TBT's Edit Mode containers select the way Blizzard's systems do — on mouse-DOWN, so the highlight is
visible while the drag is happening rather than appearing after the button is released.

In scope: `EditModeFrames.lua`'s `WireSelectableDrag` and `ns:SelectContainer`.
Out of scope: the four-container rework (Phase 35), which shares this code path and is sequenced right
after for that reason.
</domain>

<decisions>
## Implementation Decisions

### Match Blizzard exactly
Read from `wow-ui-source` `Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`:
- `EditModeSystemSelectionBaseMixin:OnMouseDown` (line 3207) calls
  `EditModeManagerFrame:SelectSystem(self.parent)` outright — no click-versus-drag test, no threshold.
- `EditModeSystemMixin:SelectSystem` (line 848) is guarded by `if not self.isSelected`, so clicking an
  already-selected system is a no-op rather than a toggle.
- `EditModeSystemMixin:CanBeMoved` returns `self.isSelected and not self.isLocked`, so for Blizzard
  selection is a **precondition** of dragging.

TBT follows all three.

### Re-clicking a selected container no longer deselects it
TBT's old handler toggled: a click on the selected container cleared the selection. Blizzard does not do
this, and keeping the toggle is incompatible with selecting on mouse-down — every drag of an already
selected container would deselect it on the way.

Deselection still has a path, unchanged: the `GLOBAL_MOUSE_DOWN` handler clears the selection when the
click lands outside every TBT frame, which is how Blizzard behaves too.

### The drag threshold is deleted, not repurposed
`dragStartX`, `dragStartY` and `DRAG_THRESHOLD` existed only to distinguish a click from a drag on
mouse-up. With selection on mouse-down there is nothing to distinguish — both gestures start the same
way — so all three are removed rather than left dead.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WireSelectableDrag(overlay, container, containerKey)` already abstracts both containers; the fix lands
  in one place and applies to bars and icons alike.
- `ns:SelectContainer` / `ns:DeselectContainer` / `ns:ClearSelection` already exist with the right shape.

### Established Patterns
- `ns:SelectContainer` clears Blizzard's own Edit Mode selection through a `pcall` on
  `EditModeManagerFrame:ClearSelectedSystem`, because that call can touch secure state. That defensive
  wrapper is untouched — but it is now reached on every mouse-down, which is what made the idempotence
  guard necessary rather than merely tidy.

### Integration Points
- `clickDetector`'s `GLOBAL_MOUSE_DOWN` handler and `IsMouseOverTBTFrame()` own deselection.
- `ns:ClearSelection` has four other callers (Edit Mode exit, popup close, checkbox) — all unaffected.
</code_context>

<specifics>
## Specific Ideas

Reported during the v0.2.4 Phase 18 human-verify session, 2026-04-21: the container "only appears
selected after releasing the click, which makes drags feel laggy because the highlight doesn't appear
during the drag motion."
</specifics>

<deferred>
## Deferred Ideas

None.
</deferred>
