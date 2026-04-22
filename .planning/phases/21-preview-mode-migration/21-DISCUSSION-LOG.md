# Phase 21: Preview Mode Migration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 21-preview-mode-migration
**Areas discussed:** Preview marking, Preview data source, ClearAllTimers shape (fill logic), previewActive flag

---

## Preview marking

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit source=preview | Every proc has a source field; scan branches guard. | |
| Absence of source | Current v0.2.3 convention; preview has no source. | |
| Separate table | ns.previewTimers distinct from ns.activeTimers. | ✓ |

**User's choice:** Separate table
**Notes:** Cleanest identity boundary. ScanActiveTimersForCancellation naturally ignores previews without guard branches. Display merge logic combines at read time.

---

## Preview data source

| Option | Description | Selected |
|--------|-------------|----------|
| GetDisplayInfoForKey only | Single source of truth. UserSpellProvider respects entry.label internally. | |
| Mix provider + DB | entry.label override at consumer level. | |
| Option C — provider owns everything | Provider internal concern; caller logic stays clean. | ✓ |

**User's choice:** Option C — provider owns everything
**Notes:** User quote: "provider should own everything, this should be cleaner in code as well. We wanna have a straightforward logic there, specially outside of Provider."

---

## ClearAllTimers / StartAllPreviewTimers fill logic

| Option | Description | Selected |
|--------|-------------|----------|
| Skip running slots | Don't create preview entry if real proc active for key. Strict 'fill non-running'. | ✓ |
| Fill all non-hidden | Create preview regardless; display merge hides under real. | |

**User's choice:** Skip running slots
**Notes:** User quote: "skip running slots; and keep in mind that the running timers are the priority; if we DO have a preview running, and a trinket is used, it should show the actual proc instead." Two rules: (1) insertion-time skip, (2) read-time real-priority merge.

---

## ns.previewActive flag

| Option | Description | Selected |
|--------|-------------|----------|
| Delete entirely | Flag exists only to work around old wipe-restore; redundant with separate tables. | ✓ |
| Keep as introspection | Future debug aid. | |

**User's choice:** Delete entirely
**Notes:** No remaining callers once OnUnitAura guard is removed. Stale debt from old hack.

---

## Claude's Discretion

- Defensive nil check on ns:GetDisplayInfoForKey return
- Exact field set on preview proc (Display compatibility)
- Debug-log prints for preview start/end (low priority)

## Deferred Ideas

- Display.lua migration — Phase 22
- CDMTab.lua migration — Phase 23
- Shim removal — Phase 24
- Tooltip consolidation — Phase 22
