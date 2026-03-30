# Phase 1: Data Migration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 01-data-migration
**Areas discussed:** Migration mapping, Schema versioning, New buff defaults

---

## Migration Mapping

| Option | Description | Selected |
|--------|-------------|----------|
| Direct map | displayMode='bar' + enabled → 'bars', displayMode='buff' + enabled → 'buffs', !enabled → 'hidden' | ✓ |
| All to hidden | All existing buffs start in 'hidden' — user re-assigns them in the new UI | |
| You decide | Claude picks the most sensible mapping | |

**User's choice:** Direct map
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Remove old fields | Clean break — section is the single source of truth, old fields deleted after migration | ✓ |
| Keep both | Keep displayMode/enabled alongside section for backwards compatibility | |

**User's choice:** Remove old fields
**Notes:** None

---

## Schema Versioning

| Option | Description | Selected |
|--------|-------------|----------|
| schemaVersion field | Add a schemaVersion number to TerribleBuffTrackerDB root. Bump on each migration. Clear intent. | ✓ |
| Field-presence check | Check if section field exists (like current enabled/displayMode backfill). Simpler but less explicit. | |
| You decide | Claude picks the approach | |

**User's choice:** schemaVersion field
**Notes:** None

---

## New Buff Defaults

| Option | Description | Selected |
|--------|-------------|----------|
| Hidden (Not Displayed) | New buffs land in Not Displayed — user explicitly drags them to bars or buffs. Matches milestone summary. | ✓ |
| Bars | New buffs immediately appear as bars — visible right away, user can move later | |

**User's choice:** Hidden (Not Displayed)
**Notes:** Consistent with milestone summary decision that new buffs from Add button land in Not Displayed.

---

## Claude's Discretion

- Migration function placement (inline in InitBuffEngine vs separate function)
- Whether to log migration activity to chat
- Error handling for unexpected field values

## Deferred Ideas

None — discussion stayed within phase scope.
