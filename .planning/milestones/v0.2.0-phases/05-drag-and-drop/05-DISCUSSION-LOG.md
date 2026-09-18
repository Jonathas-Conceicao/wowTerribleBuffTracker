# Phase 5: Drag-and-Drop - Discussion Log

> **Audit trail only.**

**Date:** 2026-03-29
**Phase:** 05-drag-and-drop
**Areas discussed:** Drag initiation, Drop zone behavior, Visual feedback style

---

## Drag Initiation

| Option | Description | Selected |
|--------|-------------|----------|
| Left click and hold | Immediate drag on mousedown, CDM pattern | ✓ |
| Click + threshold | 5px move threshold before drag starts | |
| You decide | | |

**User's choice:** Left click and hold, match Blizzard's UI reference

---

## Drop Zone Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Any section except Suggested | Bars, Buffs, Not Displayed, delete zone. Drop outside = cancel. | ✓ |
| Any section including Suggested | Suggested acts as Not Displayed | |
| You decide | | |

**User's choice:** Any section except Suggested

---

## Visual Feedback Style

| Option | Description | Selected |
|--------|-------------|----------|
| Match CDM drag style | Ghost at TOOLTIP strata 50% alpha, CDM highlight on sections | ✓ |
| Custom highlight | Colored borders (green/red) | |
| You decide | | |

**User's choice:** Match CDM drag style

---

## Claude's Discretion

- Hit-test implementation, ghost size, source icon dimming, highlight texture
