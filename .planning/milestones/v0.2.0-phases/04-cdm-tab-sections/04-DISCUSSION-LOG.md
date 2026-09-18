# Phase 4: CDM Tab Sections - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-03-29
**Phase:** 04-cdm-tab-sections
**Areas discussed:** Section layout & headers, Buff icon display, Add button behavior, Delete drop zone, Right-click context menu

---

## Section Layout & Headers

| Option | Description | Selected |
|--------|-------------|----------|
| Vertical stack, fixed | Always visible sections | |
| Vertical stack, collapsible | Clickable headers to expand/collapse | ✓ |
| You decide | | |

**User's choice:** Vertical stack, collapsible — match CDM's exact section style from Blizzard source
**Notes:** User emphasized using UI reference to mimic exact CDM style

---

## Buff Icon Display

| Option | Description | Selected |
|--------|-------------|----------|
| Icon + label + duration | List row style | |
| Icon grid with tooltip | Icons only, hover for details | ✓ |
| Icon + label row | Icon with name, no duration | |

**User's choice:** Icon-only grid with tooltip on mouseover, no duration in settings window. Match CDM reference style.

---

## Add Button Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Popup dialog | Modal with Spell ID + Duration fields | ✓ |
| Inline inputs | Fields appear in section directly | |
| You decide | | |

**User's choice:** Popup dialog

---

## Delete Drop Zone

| Option | Description | Selected |
|--------|-------------|----------|
| Right-click context menu | Right-click to remove | |
| Delete button per icon | X overlay on each icon | |
| Delete zone only (Phase 5) | Visual present, functional with drag only | ✓ |

**User's choice:** Delete zone visual only — functional in Phase 5 with drag

---

## Right-Click Context Menu (user-initiated)

| Option | Description | Selected |
|--------|-------------|----------|
| Move to Bars / Move to Buffs / Remove | Section move + delete | ✓ |
| Move to Bars / Move to Buffs / Hide / Remove | Same plus Hide | |
| You decide | | |

**User's choice:** Move to Bars / Move to Buffs / Remove (context-sensitive per section, with Hide added for Bars/Buffs sections)

---

## Claude's Discretion

- Exact icon size from CDM source
- Grid vs flow layout details
- Collapse animation style
- Delete zone visual treatment
- Dialog positioning

## Deferred Ideas

- Drag-and-drop between sections — Phase 5
- Delete via drag — Phase 5
- Real buff suggestions — future milestone
