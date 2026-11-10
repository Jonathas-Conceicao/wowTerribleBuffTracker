# Phase 87: Paladin Aura Reminders - Context

**Gathered:** 2026-11-10
**Status:** Ready for planning
**Mode:** Autonomous kickoff. Every decision below was made by the user during `/gsd-new-milestone`
(2026-11-10) or follows directly from one; nothing is left open.

<domain>
## Phase Boundary

Data only: new `MetaReminderRow` rows and `MetaReminderGroup` calls for paladin auras on both
clients, plus the review doc. No behaviour changes. **IDs are never mixed between clients** (user).

</domain>

<decisions>
## Implementation Decisions

### Forever (PAURA-01, PAURA-02)
- Rows, each permanent (`minutes = 0`), each keyed on its top rank, Forever default client tag,
  comment ending "(unverified in game)":
  - Devotion 10293 — existing row, key unchanged; its comment loses the "any paladin aura satisfies
    it, one-way" wording (now mutual).
  - Retribution 10301, Concentration 19746, Shadow Resistance 19896, Frost Resistance 19898,
    Fire Resistance 19900 — new.
- The known-spell rule (rank family) offers each only to a paladin who knows a rank of it.
- Group (user: "grouped like the blessings", any aura hides all): the existing Devotion-only
  `MetaReminderGroup(10293, 465, 10290, ...)` in the `if ns.CLIENT_IS_FOREVER` block is REPLACED by
  one call listing the six rows and every lower rank (the same 22 IDs it lists today). With six rows
  in it, every row gets the other 21 as alternatives. 465 stays only inside the Forever block
  (it is Devotion rank 1 on Forever and the retail row's ID).
- Sanctity Aura is not added (not on the Forever paladin list).

### Retail (PAURA-03)
- Rows tagged `{ client = "retail" }`, permanent: Devotion 465 (existing, unchanged key),
  Concentration 317920, Crusader 32223 (new). They must be declared BEFORE the existing top-level
  `MetaReminderGroup(465, 317920, 32223)`, which then makes the three mutual. Update that group's
  comment (they are rows now, not alternatives only).
- Retribution Aura 183435 is NOT added (user, 2026-11-10: documented, not in the class toolkit).

### ID separation (PAURA-04)
- No Forever row ID equals a retail row ID. Keys `metaReminder:10293` and `metaReminder:465` stay.

### Review doc (DOC-08)
- `docs/REMINDERS.md`: the new rows in the right client table, sorted by class; the paladin auras
  group paragraph updated (now mutual, six rows); the retail Devotion row's "Also satisfied by"
  updated. `node scripts/reminders-doc-check.js` and `--selftest` pass.
- `.planning/research/REMINDERS-NOT-INCLUDED.md`: Sanctity Aura (Forever) and Retribution Aura
  183435 (retail) with the reason.

### Claude's Discretion
- Row order within the paladin block, comment wording.

</decisions>

<code_context>
## Existing Code Insights

- `Providers.lua` ~1219-1220 Forever Devotion row; ~1243 retail Devotion row; ~1247
  `MetaReminderGroup(465, 317920, 32223)`; ~1312-1338 the Forever paladin group.
- Forever aura ranks (research `FOREVER-REMINDERS.md` §5/§12): Devotion 465, 10290, 643, 10291,
  1032, 10292, 10293; Retribution 7294, 10298, 10299, 10300, 10301; Concentration 19746; Shadow
  Resistance 19876, 19895, 19896; Frost Resistance 19888, 19897, 19898; Fire Resistance 19891,
  19899, 19900.

</code_context>

<specifics>
## Specific Ideas

Links: `https://www.wowhead.com/forever/spell=<id>` for Forever, `https://www.wowhead.com/spell=<id>`
for retail.

</specifics>

<deferred>
## Deferred Ideas

- Per-aura model (only the same aura satisfies its reminder): rejected by the user.

</deferred>
