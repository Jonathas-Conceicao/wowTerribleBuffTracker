# Phase 7: Safety Infrastructure - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 07-safety-infrastructure
**Areas discussed:** Debug logging, Preview guard approach, Event handler structure

---

## Debug Logging

| Option | Description | Selected |
|--------|-------------|----------|
| Silent | No chat output — clean experience, harder to debug | |
| Debug-only flag | Add a /tbt debug toggle that enables verbose logging. Silent by default | ✓ |
| Always print | Always print state changes to chat | |

**User's choice:** Debug-only flag
**Notes:** `/tbt debug` toggle, silent by default, verbose when enabled

---

## Preview Guard Approach

| Option | Description | Selected |
|--------|-------------|----------|
| ns.previewActive flag | Boolean flag set by StartAllPreviewTimers, cleared by ClearAllTimers. Scan skips entirely when true. | ✓ |
| Tag timers as preview | Mark each preview timer with isPreview=true. Scan skips tagged timers. | |
| You decide | Claude picks simplest correct approach | |

**User's choice:** ns.previewActive flag (with clarification)
**Notes:** User clarified: "When previewing we should show debuf regardless of it being up, so add a flag to control that if you have to, just ensure buffs show even when off during preview"

---

## Event Handler Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Same eventFrame | Add to existing handler in Core.lua | |
| Separate aura frame | New frame in BuffEngine.lua for aura-related events | |
| You decide | Claude picks based on codebase patterns | ✓ |

**User's choice:** You decide
**Notes:** Claude has discretion on event handler organization

---

## Claude's Discretion

- Event handler structure (same frame vs separate frame for aura events)

## Deferred Ideas

None
