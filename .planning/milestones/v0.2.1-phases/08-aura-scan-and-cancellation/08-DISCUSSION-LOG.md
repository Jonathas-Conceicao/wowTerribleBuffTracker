# Phase 8: Aura Scan and Cancellation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 08-aura-scan-and-cancellation
**Areas discussed:** Scan behavior details, Edge case handling

---

## Scan Behavior — Display Update

| Option | Description | Selected |
|--------|-------------|----------|
| Single UpdateDisplay at end | Batch all removals, one UpdateDisplay call after | ✓ |
| You decide | Claude picks the most efficient approach | |

**User's choice:** Single UpdateDisplay at end
**Notes:** Cleaner, fewer redraws

---

## Scan Behavior — Debug Logging

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, per-timer | Show each cancelled buff name/ID individually | |
| Summary only | Show "Cancelled N timers: [list]" in one line | ✓ |

**User's choice:** Summary only

---

## Edge Case — Non-Aura Spells

| Option | Description | Selected |
|--------|-------------|----------|
| Only scan if timer was created from a cast | Protects future non-aura tracking | ✓ |
| Scan all active timers regardless | Simple, assumes all tracked spells produce auras | |
| You decide | Claude picks based on patterns | |

**User's choice:** Only scan if timer was created from a cast
**Notes:** Future-proofs for Phase 10 lust timers (debuff-originated, not cast-originated)

---

## Edge Case — Race Condition

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, cancel immediately | Aura data trustworthy when not blocked | ✓ |
| Brief grace (0.5s) | Window after cast to absorb propagation lag | |

**User's choice:** Cancel immediately, no grace period

---

## Claude's Discretion

None — all decisions made by user.

## Deferred Ideas

None
