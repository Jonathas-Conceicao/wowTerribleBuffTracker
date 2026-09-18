# Phase 3: CDM Tab Shell - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 03-cdm-tab-shell
**Areas discussed:** Tab button appearance, Content panel layout, /tbt command rework, ConfigUI.lua removal

---

## Tab Button Appearance

| Option | Description | Selected |
|--------|-------------|----------|
| TBT addon icon | Use tbt_icon_64x64.blp via SetTexture. Unique, identifies TBT. | |
| Blizzard atlas icon | Use a Blizzard atlas that fits CDM style. Blends with native tabs. | ✓ |
| You decide | Claude picks something good | |

**User's choice:** Blizzard atlas icon — `hud-buff` atlas selected as placeholder. Can swap during verification.
**Notes:** User wanted to preview atlas textures in-game. Several atlas names tried but didn't render (may not exist in Midnight). Settled on `hud-buff` with option to change later.

---

## Content Panel Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Match CDM scroll area | Same background/border as CDM content area. Inset + scroll frame for Phase 4. | ✓ |
| Simple dark panel | Basic dark semi-transparent bg with border. Placeholder text. | |
| You decide | Claude matches Blizzard CDM style | |

**User's choice:** Match CDM scroll area
**Notes:** None

---

## /tbt Command Rework

| Option | Description | Selected |
|--------|-------------|----------|
| Toggle CDM to TBT tab | Open/close/switch logic depending on current state | |
| Always open CDM + TBT tab | Always opens CDM settings with TBT tab selected. Never closes. | ✓ |
| You decide | Claude picks most intuitive behavior | |

**User's choice:** Always open CDM + TBT tab
**Notes:** None

---

## ConfigUI.lua Removal

| Option | Description | Selected |
|--------|-------------|----------|
| Delete entirely | All functionality moves to CDM tab in Phase 4. Preview stays in BuffEngine. | ✓ |
| Keep preview trigger | Delete ConfigUI but add /tbt preview shortcut | |
| You decide | Claude handles removal cleanly | |

**User's choice:** Delete entirely
**Notes:** StartAllPreviewTimers/ClearAllTimers already in BuffEngine.lua

---

## Claude's Discretion

- XML file name and structure for tab button
- How to open CDM settings programmatically
- Content panel scroll frame details
- Whether CDMTab.lua is a new file or merged into existing

## Deferred Ideas

- Edit Mode selection highlighting + per-element config panel (from Phase 2 feedback)
- Tab icon may change during verification
