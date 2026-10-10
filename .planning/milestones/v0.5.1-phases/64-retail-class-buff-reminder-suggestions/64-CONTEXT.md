# Phase 64: Retail Class-Buff Reminder Suggestions - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning
**Mode:** Data supplied by the user 2026-09-30 (table below); four decisions taken up front the same
day, marked **user decision**. Research skipped.

<domain>
## Phase Boundary

On retail, the Reminders tab's Suggested section offers the class-buff reminders the character
knows (MREM-04, MREM-05), as built-in `metaReminder` rows — the retail counterpart of v0.5.0's
Forever rows (Phase 57.4). Forever's offer must look and behave exactly as before. Clickable
reminders (Phase 63) apply to the new rows: each row carries its cast spell.

</domain>

<decisions>
## Implementation Decisions

### Retail rows — the user's data, verbatim (2026-09-30)

| Class   | Buff                   | Spell ID | Aura ID | Duration  |
|---------|------------------------|---------:|--------:|-----------|
| Mage    | Arcane Intellect       |     1459 |    1459 | 60 min    |
| Priest  | Power Word: Fortitude  |    21562 |   21562 | 60 min    |
| Druid   | Mark of the Wild       |   102046 |  102046 | 60 min    |
| Druid   | Symbiotic Relationship |   474750 |  474754 | 60 min    |
| Warrior | Battle Shout           |     6673 |    6673 | 60 min    |
| Shaman  | Skyfury                |   462854 |  462854 | 60 min    |
| Shaman  | Lightning Shield (added 2026-10-01) | 192106 | 192106 | 60 min |
| Evoker  | Blessing of the Bronze |   364342 |  381748 | 60 min    |
| Evoker  | Source of Magic        |   369459 |  369459 | 60 min    |
| Paladin | Devotion Aura          |      465 |     465 | Permanent |

Plus, from MREM-04 — **user decision: keep, 60 min**:

| Mage    | Arcane Familiar        | (talent 205022 known) | aura 210126 | 60 min | casts 1459 |

- "Permanent" = no duration: the reminder shows only once the aura is gone, with no lead window
  (REM-05's rule for a duration-less timer).
- Arcane Familiar: loads when talent **205022** is known (`knownID`), watches aura **210126**, and a
  click casts **1459** (Arcane Intellect grants the familiar). Its row key must not collide with the
  Arcane Intellect row's `metaReminder:1459`.
- Rows whose aura ID differs from the spell ID (Symbiotic Relationship 474750 → 474754, Blessing of
  the Bronze 364342 → 381748) need a per-row aura ID. Today `ns:ApplyMetaReminderDef` forces
  `entry.auraID = nil` ("the aura ID is the spell ID") — extend the row definition with an optional
  aura ID and apply it, so the reminder watches the right aura. Keep a row's key on its spell ID.
- Existing rows stay byte-for-byte as they are (keys `metaReminder:<spellID>` are saved — a changed
  ID orphans a placed tracker).

### Which client offers a row — **user decision: tag rows per client**
- Each row declares where it is offered: Forever, retail, or both. Several retail IDs exist on
  Forever with a different meaning (6673 = Battle Shout rank 1, where Forever's row is 25289; 465 =
  Devotion Aura rank 1; 21562 = Prayer of Fortitude), so "is it known" alone would leak retail rows
  onto Forever.
- **Reuse the existing answer, add no new comparison:** `ns.CLIENT_IS_FOREVER` (Core.lua ~845) is
  the one sanctioned interface-range comparison; its comment explicitly allows naming the same
  answer for another consumer. The current blanket gate in `ns:MetaReminderSuggestionKeys`
  (`if not ns.CLIENT_IS_FOREVER then return {} end`) is replaced by a per-row check.
- Tagging: Arcane Intellect 1459 → both (same ID, same duration on both). Every other existing row
  → Forever. Every new row → retail.
- A row not offered on this client must also not LOAD on it (an already-placed entry for it should
  not start appearing), and must not be offered in Suggested. Decide the cleanest single point
  (e.g. the row lookup or the load rule) and keep Forever's current behaviour unchanged.
- Record in PROJECT.md Key Decisions: the per-row client tag reuses `ns.CLIENT_IS_FOREVER` (no
  second comparison), approved by the user 2026-09-30.

### Click target — **user decision: ally-cast rows cast on your target**
- Symbiotic Relationship and Source of Magic are cast on an ally. Their rows carry a flag so a click
  does NOT force `unit = "player"`: the overlay leaves the unit unset (the game's default — a
  friendly target receives it, otherwise targeting/self per the game's rules). Every other reminder
  keeps the Phase 63 self-cast. Overlay attributes are still written out of combat only, on change.
- REQUIREMENTS' Out of Scope line about self-cast gets an exception for these two rows.

### Paladin auras — **user decision: any aura satisfies Devotion Aura**
- Retail Devotion Aura (465) gets alternatives Concentration Aura (**317920**) and Crusader Aura
  (**32223**) — "Also satisfied by" (RALT), table-defined like the Forever blessings group. Devotion
  stays the cast spell. Only Devotion is a row; the other two are alternatives, not suggestions.

### Claude's Discretion
- Field names for the client tag, aura ID and ally-cast flag on `MetaReminderRow`.
- Whether the retail rows sit in the same table section or a second labelled block.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Providers.lua`: `META_REMINDER_DEFS`, `MetaReminderRow(spellID, minutes, knownID, petBook,
  castID)`, `MetaReminderGroup(...)`, `ns:MetaReminderDef`, `ns:MetaReminderKnownID`,
  `ns:ReminderCastID`, `ns:ApplyMetaReminderDef`, `ns:MetaReminderSuggestionKeys` (~1540-1710).
- `Core.lua`: `ns.CLIENT_IS_FOREVER` (~845), `ns:TrackerLoad` / `FIXED_LOAD` (metaReminder = When
  known), `ns:ResolveSpellKnown`.
- `ReminderClick.lua`: the overlay attribute write (`type1`, `unit`, `spell`) in its flush.

### Established Patterns
- A row's table data is re-applied to the saved entry at every `ns:RebuildCastIndex` — no migration
  for a changed row field.
- `issecretvalue` before any comparison of a game value; no per-frame allocation.

### Integration Points
- Reminders tab Suggested section (CDMTab.lua) reads `ns:MetaReminderSuggestionKeys`.

</code_context>

<specifics>
## Specific Ideas

- In-game checks are deferred to Phase 66 (Forever first, then retail). Forever check: the class-
  buff Suggested offer and behaviour are unchanged (no 6673/465/21562 rows appear).

</specifics>

<deferred>
## Deferred Ideas

- Backlog 999.19 (custom tracker stack counts) and 999.20 (duration on a custom buff icon).

</deferred>
