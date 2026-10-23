# Phase 68: Merge Mode by Re-anchoring - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning
**Mode:** Smart discuss, front-loaded for the whole autonomous run (67-71) at the user's standing request

<domain>
## Phase Boundary

Turn the re-anchor prototype into Merge Mode's real rendering path. With Merge Mode on, every merged
CDM entry is drawn by Blizzard's own CDM item frame, placed on its TBT slot and styled by TBT's
container settings; TBT draws nothing of its own on a merged slot. Delivers STEAL-10, 11, 12, 16, 17,
18. The POC's open issues (settings-window reorder, Edit Mode bars, container visibility) are Phase
69; deleting the old redraw path and the `/tbt reanchor` toggle is Phase 70 — this phase may leave the
old code in place but unreachable when Merge Mode is on.

Design record: `.planning/research/MERGE-REANCHOR-POC.md`. Prototype: `MergeReanchor.lua` plus the
`EXPERIMENT (MergeReanchor.lua)` branches in `MergeMode.lua`, `Display.lua`, `Core.lua` (commit `3bc4ad6`).

</domain>

<decisions>
## Implementation Decisions

### Activation
- Merge Mode on is enough — the re-anchor path no longer depends on `ns.db.mergeReanchorExperiment`.
  (The toggle itself and its saved flag are removed in Phase 70; here it simply stops gating.)
- `MergeReanchor.lua` keeps its name: no TOC change, no full client restart needed.

### What touches Blizzard's frames (hard boundary)
- Only C widget calls on the item frames and their child regions: `ClearAllPoints`, `SetPoint`,
  `SetScale`, `SetWidth`/`SetHeight`, `SetAlpha`, `SetShown`-class visibility setters on child regions,
  mouse-enable setters, font/texture setters on child regions — plus one `hooksecurefunc` on each
  viewer's `Layout`.
- **Never**: `SetParent`, a field write on a Blizzard frame, a Blizzard mixin method call
  (`SetBarContent`, `SetTimerShown`, `SetTooltipsShown`, `RefreshLayout`, ...),
  `C_CooldownViewer.SetLayoutData`. These taint permanently (`TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md`).

### Styling — every container setting applies (user decision 2026-10-10)
- **Everything TBT's Edit Mode offers for the container applies to the moved frames**: position,
  size (icon scale; bar width), padding/layout, opacity, and the rest — show timer, tooltips, bar
  content (icon / name / both) and anything else the container settings popup exposes.
- User's words: *"Everything we have on edit mode for the container should apply for the merged
  (moved) icons. So opacity, size, position and anything else. We can then start restricting things
  when we hit actual errors."* So: apply each setting with the plain setters above; where a setting can
  only be applied through a Blizzard mixin method, do NOT call the mixin — reproduce its effect with
  plain setters on the child regions (e.g. `cooldownFrame:SetHideCountdownNumbers`, region `:SetShown`,
  `SetMouseMotionEnabled`), and record any setting that cannot be reproduced safely as an open item
  rather than calling the mixin.
- Re-apply after every Blizzard `Layout` (the hook) since `RefreshLayout`/`OnAcquireItemFrame` resets
  scale, timer/tooltip state and bar width/content on acquire.

### Placement model (from the POC, keep)
- TBT keeps its mirror and lays every slot out exactly as before. A merged slot's pooled icon (or bar)
  is styled and placed but kept hidden; Blizzard's item frame for that `cooldownID` is anchored onto it
  (icons: CENTER; bars: LEFT) and scaled so its on-screen height matches; bars also take the row width.
- **STEAL-17:** re-place a frame only when its cell, scale or size changes, or after its viewer's
  `Layout` — never per render tick. The prototype recomputes scale (4 game calls) per merged slot per
  refresh; fix that (stamp per cell/settings generation).
- CDM frames stay in TBT's containers during Edit Mode (user liked this in the POC).
- **STEAL-18:** turning Merge Mode off returns every moved frame to its viewer (anchor back on the
  parked viewer is enough; Blizzard's next Layout re-places it) and the existing visibility code
  restores the viewers' positions — no `/reload`.

### Claude's Discretion
- Whether `AttachMergedItem` stays a per-slot call from Display or becomes one pass over a slot list.
- How style application is factored (one `ApplyMergedStyle(itemFrame, settings, kind)` is the expected
  shape).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MergeReanchor.lua`: `ns:IsMergeReanchorActive`, `PlaceItem`, `PlaceViewer`, `ns:PlaceAllMergedItems`,
  `ns:AttachMergedItem(entry, cell, point)`, `ns:ReanchorMergeViewers` (installs the Layout hooks).
- `Display.lua`: `ApplyIconStyle` / `ApplyBarStyle` (scale, alpha, swipe, bar width/content),
  `RenderIconContainer` (branch `reanchorHere and entry.isMerged`), `RenderBarContainer` (end-of-loop
  branch), `SlotDraws`, `CenteredSlotPlacement`; container settings cached by `RefreshContainerSettings`
  (`settings.iconScale`, `alpha`, `timerShown`, `tooltipsShown`, `barContent`, `iconPadding`, ...).
- `MergeMode.lua`: `ns:RefreshMergeMirror`, `ns:RefreshMergeShownSlots` (calls `PlaceAllMergedItems`),
  `ns.mergeItemFrames` (cooldownID → shown item frame), viewer parking (`ApplyMergeVisibility`).

### Established Patterns
- Dirty-check stamps on pooled widgets; module-level tables wiped, never reallocated per tick.
- Blizzard item frame children: `Icon`, `Cooldown` (via `GetCooldownFrame` — a mixin method; read the
  field `itemFrame.Cooldown` instead), `ChargeCount`, `Applications`, bars: `Bar`, `Icon`, `Bar.Name`,
  `Bar.Duration` (verify names against `wow-ui-source` CooldownViewer.xml).

### Integration Points
- `Display.lua` render passes call `ns:AttachMergedItem`; `MergeMode.lua` calls `ReanchorMergeViewers`
  and `PlaceAllMergedItems`; `RefreshMergeAuraGroups` is disabled while re-anchoring.

</code_context>

<specifics>
## Specific Ideas

- POC result: no taint through a retail raid boss; Edit Mode preview and resizing worked; bars were
  matched on width in the last POC round.
- All in-game checks deferred to Phase 72 (user decision for this run). M+ is checked in 72.

</specifics>

<deferred>
## Deferred Ideas

- Restyling Blizzard's textures/borders beyond what TBT's container settings expose — out of scope.

</deferred>
