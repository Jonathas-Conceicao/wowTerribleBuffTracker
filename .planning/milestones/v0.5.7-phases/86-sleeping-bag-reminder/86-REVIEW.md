---
phase: 86
status: clean
reviewed: 2026-11-10
files: [Providers.lua, Core.lua, ReminderClick.lua, docs/REMINDERS.md]
---

# Phase 86 Code Review

Reviewed the diff 38dac28..f5c3356 inline (orchestrator).

- `OfferItemInBags` guards a missing API, a failed call, a secret and a non-number count, as
  `PickUseItem` does; it is declared above its only caller (no upvalue-order trap).
- `ns:MetaReminderSuggestionKeys`: only a def with `offerItem` takes the new branch; every other row
  runs the unchanged `ResolveSpellKnown(def.knownID, false) == true`.
- `ns:RebuildTrackerLoad`: the new `elseif` sits after orphan / ALWAYS / NEVER / non-number, so an
  explicit Never still unloads the row and the combat hold is never reached for it.
- `ns:TrackerLoadReason`: returns nil for the row before any `ns:SpellLabel` call.
- `ns:MetaReminderOfferItem` is on `ns`, called through `ns.` guards; one map read.
- The row: `castID = false`, `useItems = { { 211527, 1 } }`, default (Forever) client, no group.
- Hot paths: no per-frame work, no allocation; the bag read runs only when Suggested is drawn.

No findings.
