# Milestones

## v0.1.0 (pre-GSD)

Initial release. Manual buff/cooldown timer tracking with CDM-anchored bars/icons, standalone config UI, and CI/CD pipeline.

**Shipped:**
- Timer tracking via UNIT_SPELLCAST_SUCCEEDED + GetTime()
- Timer bars and buff icons anchored to CDM
- Config UI for adding/removing tracked buffs
- Enable/disable and display mode toggle per buff
- Preview mode
- SavedVariables persistence
- BigWigs Packager CI/CD for CurseForge/Wago/GitHub

## v0.2.0 — Config & Edit Mode Rework (shipped 2026-03-30)

Replace standalone config UI with CDM-integrated tab. Add Edit Mode support for independent buff/bar positioning.

**Shipped:**
- Schema migration to section-based buff management (bars/buffs/hidden)
- Two independent Edit Mode containers with position persistence
- CDM Settings tab ("TBT Buffs") with 4 collapsible sections
- Drag-and-drop between sections with CDM-style reorder marker
- Within-section reordering via layoutOrder
- Add Buff dialog + delete zone
- Right-click context menus (Move/Hide/Remove)
- Edit Mode settings popup (orientation, scale, padding, opacity, visibility, bar width)
- Copy Blizzard CDM Config button
- ConfigUI.lua removed — all config through CDM tab + Edit Mode

**Archive:** [v0.2.0-ROADMAP.md](milestones/v0.2.0-ROADMAP.md) | [v0.2.0-REQUIREMENTS.md](milestones/v0.2.0-REQUIREMENTS.md)
