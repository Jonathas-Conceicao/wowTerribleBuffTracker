# Merge Mode by Re-anchoring Blizzard's CDM Frames — Proof of Concept

**Tested:** 2026-10-10, retail, raid boss encounter. M+ deliberately left for the real implementation.
**Status:** POC **passed** — no taint. Chosen as the main task of the next milestone (Backlog 999.26).
**Prototype code:** `MergeReanchor.lua` plus small `EXPERIMENT (MergeReanchor.lua)` branches in
`MergeMode.lua`, `Display.lua`, `Core.lua` (`/tbt reanchor`) and one TOC line. Off unless toggled; the
toggle is saved (`ns.db.mergeReanchorExperiment`) and needs a `/reload`.

## Summary

- Merge Mode today **redraws** every CDM entry with TBT's own widgets. That needs aura reads, aura
  timing, Blizzard's aura-engine overlays, a copy of each bar's values, pandemic and dispel reads and
  a charge count. Each is a workaround for secret values, and most of the open Merge Mode bugs live
  in them (999.21 charges, 999.22/23 other casters' debuffs, 999.24 mind control).
- The POC instead **moves Blizzard's own CDM item frames** onto TBT's layout. TBT still mirrors the
  CDM configuration and lays every slot out exactly as before — order, direction, Centered, padding,
  interleaving with the player's own trackers. For a merged slot, TBT's pooled icon (or bar) is
  styled and placed but kept **hidden**. Blizzard's item frame for that `cooldownID` is anchored onto
  it and scaled to its on-screen size. TBT decides where and how big; Blizzard draws everything
  inside.
- **Result: no taint** through a raid boss encounter, Edit Mode, and resizing or moving the CDM.
  Cooldowns, charges, colours, glows, borders and timers looked **exactly** like the CDM, including
  minor style differences TBT had not yet matched. The secret-value problem does not arise, because
  TBT never reads what it moves.

## What is touched on a CDM frame

| Call | Kind | Notes |
|---|---|---|
| `viewer.itemFramePool:EnumerateActive()` | generic pool proxy | already admitted in `MergeMode.lua` |
| `itemFrame.cooldownID` | raw field read | already admitted; maps a frame to its TBT slot |
| `itemFrame:GetParent()`, `:GetHeight()` | C widget getters | sizing only |
| `itemFrame:SetScale()`, `:SetWidth()` (bars only) | C widget setters | TBT's size, not the CDM's |
| `itemFrame:ClearAllPoints()`, `:SetPoint(point, tbtCell, point, 0, 0)` | C widget setters | **never `SetParent`** |
| `hooksecurefunc(viewer, "Layout", ...)` | post-hook, one per viewer | installed only while the experiment is on |

Nothing is parented into a CDM frame, no field is written on one, and no Blizzard mixin method is
called. The viewers are still parked off-screen and kept **shown** exactly as today. A hidden viewer
stops refreshing, and the moved frames are still its children, so they show only while it does.

**Why one `Layout` hook per viewer instead of one `SetPoint` hook per icon:** in Blizzard's source,
item frames are only positioned inside `GridLayoutFrameMixin:Layout` (reached from `RefreshLayout`,
`MarkDirty → OnUpdate`, and `OnShow`). `RefreshLayout` is also where they get re-scaled
(`OnAcquireItemFrame → SetScale(iconScale)`) and bars re-widthed (`SetBarWidth`). So four post-hooks
see every placement. Running after `Layout` also lets the viewer size itself from Blizzard's own
positions before the frames move.

**Scale maths:** a frame's on-screen size is the viewer's effective scale × its own scale × its
height. So `scale = cell:GetEffectiveScale() * cell:GetHeight() / (viewer:GetEffectiveScale() *
itemFrame:GetHeight())`. Blizzard's frames are not TBT's size (Essential 50, Utility 30, Buffs 40,
Bars 220×30), so this is required, not cosmetic. For bars, `width = cell:GetWidth() * height /
cellHeight`, in the frame's own units.

## Iterations

1. **Swap only the anchor's relativeTo** (viewer → TBT container), keeping Blizzard's offsets. No
   taint, but the CDM grid landed as one block centred on the container rather than added to TBT's
   layout. It overlapped TBT's own trackers, followed the CDM's own size, and showed nothing in Edit
   Mode, because the frames were sent back to the viewer there. Rejected.
2. **Attach each frame to TBT's own hidden cell** (the current prototype). Alignment, Centered,
   interleaving, Edit Mode preview and sizing all correct. No taint.
3. Bars also take the cell's width. While previewing, a Blizzard re-layout queues a mirror rebuild,
   to try to fix reordering in the CDM settings window (did not fully fix it, see below).

## Open issues found in the POC

- **Reordering in the CDM settings window corrupts the preview.** Moving a buff there leaves the
  preview wrong until the window closes: the moved buff sometimes shows in a different container,
  and bar size or alignment goes off. Once the window closes, everything is correct. Not diagnosed.
  Suspects:
  - `cellByID` (cooldownID → TBT cell) entries are replaced but **never cleared** when an id leaves
    a container. An id that moved category, e.g. buff → bar, can keep pointing at its old cell from
    the other container until Display re-attaches it.
  - The mirror is rebuilt from the viewer's `layoutIndex` mid-drag. Blizzard's settings window
    drags its own item (`CooldownViewerDraggedItemBase`), and the viewers may be re-laid out more
    than once per move.
  - In the real implementation, a pass should rebuild the id → cell map whole rather than patch it.
- **Edit Mode preview is missing the merged bars.** Everything else in Edit Mode looks right. Not
  diagnosed. Start with whether the bar viewer's frames are shown while editing, and whether the bar
  container publishes them in preview.
- **TBT container visibility does not reach the moved frames.** They are not children of TBT's
  container, so a container hidden by its visibility setting (e.g. out of combat) still shows
  Blizzard's frames. The real implementation needs an explicit rule here.
- **TBT's own pandemic glow and dispel border are switched off** for merged slots, because Blizzard
  draws its own. That is correct, but the old code paths still run.
- **Not yet tested:** M+ (planned for the real implementation), WoW Forever, a spec change with the
  experiment on, and combat while Edit Mode is open with the experiment on. The last one is the
  case that tainted in the 2026-09-20 injection experiments.

## What the real implementation could remove

With every merged slot drawn by Blizzard's own frame, these become dead for merged entries:
- the engine aura containers (`AuraContainer` overlays, slot filters, the target-assistable guard);
- `ResolveMergedAuraTiming` and the direct aura reads behind it;
- `RelayMergedBar` and `RelayMergedIconTime`;
- `ReadPandemicState` / `ReadDispelBorder` for merged entries;
- the merged branches of `ApplyCooldownSlot` / `ApplyChargeCount`.

That closes the code paths behind 999.21, 999.22, 999.23 and 999.24 by deletion rather than by
patching. The 999.24 requirement still applies to what replaces them: **no path may paint one
thing over every cell.** What stays: the mirror (configuration and order), the shown-slot pass
(Centered needs to know what is up), parking the viewers, and TBT's layout.

## Relation to earlier findings

`TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md` (2026-09-20) found that **joining** the CDM — a TBT frame
as a child of a viewer, `layoutIndex` / `stride` writes — taints permanently. Its proposed mechanism
was that Blizzard's layout code reads fields off an addon-owned child. The POC is the opposite
direction: Blizzard's frames stay Blizzard's children with Blizzard's fields, and only their anchor
and scale are written, through C setters. This POC is consistent with that mechanism, but does not
prove it.
