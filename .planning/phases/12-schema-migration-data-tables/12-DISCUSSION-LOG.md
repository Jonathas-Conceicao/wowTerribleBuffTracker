# Phase 12: Schema Migration + Data Tables - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 12-schema-migration-data-tables
**Areas discussed:** Data table structure, v4 migration scope, SUGGESTED_BUFFS entries

---

## Data Table Structure

| Option | Description | Selected |
|--------|-------------|----------|
| spellID-keyed table | TRINKET_SPELLS[spellID] = {duration, itemID} — O(1) lookup, matches SATED_DEBUFF_TO_LUST pattern | ✓ |
| Array with scan | Array of entries, iterate to find match — easier to iterate for icon resolution | |
| You decide | Claude picks best structure | |

**User's choice:** spellID-keyed table
**Notes:** Matches existing SATED_DEBUFF_TO_LUST pattern for fast cast detection lookup

| Option | Description | Selected |
|--------|-------------|----------|
| Separate static lists | TRINKET_ITEM_IDS as explicit array — tiny duplication | |
| Derive at init | Build itemID list by iterating spell table once — no duplication | ✓ |
| You decide | Claude picks | |

**User's choice:** Derive at init

| Option | Description | Selected |
|--------|-------------|----------|
| Just iterate | 13 entries total, trivial | ✓ |
| Build reverse map | itemID→spellID for O(1) lookup | |
| You decide | Claude picks | |

**User's choice:** Just iterate — scale is too small to need optimization

---

## v4 Migration Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Bump version only | Empty v4 block, reserves version | |
| Skip migration | Stay at v3 — no new persistent structures | ✓ |

**User's choice:** Skip migration — no stale keys possible since v0.2.3 is the first release with these features

---

## SUGGESTED_BUFFS Entries

| Option | Description | Selected |
|--------|-------------|----------|
| Longest duration | Max from spell table (45s trinkets, 30s pots) | |
| Shortest duration | Min from spell table | |
| Nil / dynamic | Resolve at cast time | |
| 0 (sentinel) | Explicit "varies" signal | ✓ |

**User's choice:** duration = 0 as explicit sentinel. Actual timer duration resolved at cast time from spell table.
**Notes:** User asked for clarification on what duration field is used for. Traced usage to copy-on-drag (CDMTab.lua:146) — purely cosmetic for meta-buffs since timer uses spell table duration.

| Option | Description | Selected |
|--------|-------------|----------|
| Return itemID | getCDMSpellID returns itemID — but callers expect spellID | |
| New getCDMIcon function | Returns texture directly via C_Item API | |
| Claude handles it | Pick cleanest integration | ✓ |

**User's choice:** Claude handles the CDM icon plumbing — just make it show equipped trinket / bag pot at rest

---

## Claude's Discretion

- CDM icon resolution plumbing for itemID-based at-rest icons
- Data table location in BuffEngine.lua

## Deferred Ideas

- **Data storage rework**: Future milestone to review and rework trackedBuffs storage model — too many exceptions and special cases in current schema. General data model cleanup.
