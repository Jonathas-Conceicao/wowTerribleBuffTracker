# Milestones

## v0.2.3 Trinket & Pot Meta-Trackers (Shipped: 2026-04-13)

**Phases completed:** 5 phases, 8 plans, 17 tasks

**Key accomplishments:**

- spellID-keyed TRINKET_SPELLS (9 entries) and POT_SPELLS (4 entries) added to BuffEngine.lua with derived itemID sets, providing the static data layer for Phase 13-15 trinket and pot meta-trackers
- Trinket and pot meta-trackers registered in ns.SUGGESTED_BUFFS with a nil-safe three-way icon fallback in CDMTab, making them visible in the CDM Suggested section as question-mark placeholders ready for Phase 14 icon resolution
- OnSpellCastSucceeded extended with trinket/pot meta-slot fan-out: casting any TRINKET_SPELLS or POT_SPELLS entry creates a keyed activeTimer with metaSlot, shared-slot overwrite, and source='cast' for aura-scan cancellation compatibility
- All TRINKET_SPELLS and POT_SPELLS spell IDs confirmed accurate via live in-game casts; debug instrumentation stripped from shipping BuffEngine.lua
- ns.metaIcons eager cache with combat-gated CSV-ordered scan via GetInventoryItemID + C_Item.GetItemCount, and GetAtRestMetaIcon wired into SUGGESTED_BUFFS trinket/pot getCDMIcon closures
- CDMTab StartPreview now triggers ns:RefreshMetaIcons before every preview; Display.lua bar and icon placeholder paths route trinket/pot through GetSuggestedAtRestIcon (GetAtRestMetaIcon) instead of falling back to the Bloodlust/?-icon; verified in-game for ICON-01/02/05/07
- v0.2.3 release-prep complete: stylua-clean Lua files, v0.2.3 CHANGELOG entry, PROJECT.md Validated block updated, TOC/pkgmeta confirmed correct — milestone ready to tag

---

## v0.2.1 Aura-Based Timer Cancellation (Shipped: 2026-04-04)

**Phases completed:** 5 phases, 6 plans, 11 tasks

**Key accomplishments:**

- (none recorded)

---

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
