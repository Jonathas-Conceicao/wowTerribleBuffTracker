---
status: passed
phase: 34
verified: 2026-09-20
must_haves_verified: 4
must_haves_total: 4
---

# Phase 34 Verification — Edit Mode Selection on Mouse-Down

| # | Criterion | Result |
|---|---|---|
| 1 | Selection fires on mouse-down, matching Blizzard | PASS (code) — `OnMouseDown` calls `ns:SelectContainer` before `StartMoving`; matches `EditModeSystemSelectionBaseMixin:OnMouseDown` |
| 2 | No dead code left behind; `stylua` clean | PASS — `dragStartX`, `dragStartY`, `DRAG_THRESHOLD` removed; `stylua --check` clean before and after |
| 3 | The highlight is visible during the drag, in-game | ✅ PASS — user-confirmed 2026-09-20: "edit-mode click does work" |
| 4 | EDM-07: an empty bar container is visible and draggable | ✅ PASS — user-confirmed 2026-09-20: the example bar shows with the question-mark icon |

## Human verification — complete

Both EDM-06 and EDM-07 confirmed in-game on Forever, 2026-09-20.

<details>
<summary>Steps that were run</summary>

On the **Forever** client:

1. Enter Edit Mode.
2. Press and hold the left mouse button on the TBT bars container and drag **without releasing**.
   The yellow selection NineSlice should appear the instant the button goes down and stay up for the
   whole drag. Before this change it appeared only on release.
3. Drag the buffs container — same behaviour, and the bars container should deselect as the buffs
   container selects.
4. Click somewhere outside both containers and the settings popup — the selection clears.
5. Click an already-selected container — it **stays** selected. This is deliberate and matches Blizzard;
   the old toggle-off behaviour is gone.

</details>

Deployed and ready: all four client folders hold `v0.3.0-9-ga4bd5bb-dirty-dev`.
