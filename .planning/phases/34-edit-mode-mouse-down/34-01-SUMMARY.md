# Phase 34 — Summary 01: Edit Mode Selection on Mouse-Down

**Completed:** 2026-09-20
**Requirements:** EDM-06

## What changed

`EditModeFrames.lua` only.

**`WireSelectableDrag`** — `OnMouseDown` now calls `ns:SelectContainer(containerKey)` before
`container:StartMoving()`. `OnMouseUp` is reduced to `container:StopMovingOrSizing()`.

The click-versus-drag reconstruction on mouse-up is gone, along with the `dragStartX`, `dragStartY` and
`DRAG_THRESHOLD` locals that existed only to serve it.

**`ns:SelectContainer`** — gained an early return when the container is already selected, mirroring
`EditModeSystemMixin:SelectSystem`'s `if not self.isSelected` guard. This is load-bearing now rather
than cosmetic: selection fires on every mouse-down, so without it each click on an already-selected
container would re-run `ClearSelectedSystem` through its `pcall` and re-show the settings popup.

## Behaviour change worth knowing

**Clicking an already-selected container no longer deselects it.** The old handler toggled. That is
incompatible with selecting on mouse-down — every drag of a selected container would have deselected it
on the way — and Blizzard does not toggle either.

Deselection is unchanged and still works: the `GLOBAL_MOUSE_DOWN` handler calls `ns:ClearSelection()`
when a click lands outside every TBT frame, which is also how Blizzard behaves.

## Blizzard reference

From `wow-ui-source` `Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`:

| Line | What it establishes |
|---|---|
| 3207 | `EditModeSystemSelectionBaseMixin:OnMouseDown` calls `SelectSystem` outright — no threshold, no click-vs-drag test |
| 848 | `SelectSystem` is guarded by `if not self.isSelected` — idempotent, never a toggle |
| 878 | `CanBeMoved` returns `self.isSelected and not self.isLocked` — selection is a precondition of dragging |

## Deviations from plan

None.

## Follow-ups

Phase 35 reworks this same code path for four containers. The mouse-down wiring is per-container through
`WireSelectableDrag`, so it extends without change.

---

## Added 2026-09-20: EDM-07 — empty bar container was unclickable

**Reported by the user** alongside the EDM-06 confirmation: with nothing tracked as a bar, the bar
container could not be moved in Edit Mode at all.

**Cause.** `Display.lua`'s `UpdateDisplay` sizes the bar container from its slot count:
`totalHeight = n > 0 and (...) or 0`, then `SetHeight(math.max(1, totalHeight))`. With `n == 0` that is
a **1px-tall** frame — nothing to click, so nothing to drag.

`ns:ShowEditModeHandles` does apply a 30px floor, which is why this looked like it should already work.
It does not help: that function runs once on Edit Mode enter, and the next `UpdateDisplay` overwrites
the height back to 1.

**Fix.** In Edit Mode only, an empty bar list gets one example slot:

```lua
local EXAMPLE_BAR_SLOT = { key = "__tbt_example__", label = "Example Buff Name" }
...
if barEditing and #barSlots == 0 then
    table.insert(barSlots, EXAMPLE_BAR_SLOT)
end
```

The key deliberately matches no provider, so `ns:GetDisplayInfoForKey` returns nil and the existing
placeholder path renders the `134400` question-mark icon with the slot's label — no new render branch.
The table is module-level and never mutated, so the empty case allocates nothing, matching the file's
reuse-and-`wipe` convention.

Outside Edit Mode the example is not inserted, so an untracked container stays invisible as before.

**The buff/icon container does not have this bug** — its empty case is `SetSize(40, 40)`, which is
clickable. It renders nothing, though, so the same example treatment may be wanted there; not done,
because the report was specific to bars.
