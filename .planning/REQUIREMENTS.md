# Requirements — v0.5.7 Sleeping bag and some more

**Defined:** 2026-11-10, at kickoff, with the user. Research done inline (user decision): the item and
buff were read from Wowhead's `/forever/` tooltips, the Forever aura ranks come from
`research/FOREVER-REMINDERS.md` §5/§12, and the retail auras are the three the shipped retail
Devotion row already lists (verified in game 2026-10-01).

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces
automatically.

**Scope rule (user, carried from v0.5.6):** nothing works differently from today except what these
requirements name. Rows and groups are data through `MetaReminderRow` / `MetaReminderGroup`.

## v0.5.7 Requirements

### Sleeping bag (Forever only)

- [x] **SBAG-01**: On Forever, a Well-Rested reminder exists, keyed on the buff
  [429959](https://www.wowhead.com/forever/spell=429959), 120 min. Using the Cozy Sleeping Bag
  [211527](https://www.wowhead.com/forever/item=211527) unfurls the bag and the buff arrives only after
  a minute of rest, so the reminder hides when the aura appears, not on the click. It is not
  registered on retail.
- [x] **SBAG-02**: Suggested offers the Well-Rested reminder only while the Cozy Sleeping Bag is in
  the character's bags (an item-count check, not a known-spell check). Every other row's offer is
  unchanged.
- [x] **SBAG-03**: A placed Well-Rested reminder loads on every Forever character, with or without the
  bag (reminders are account-wide; user decision), and shows while the buff is missing. Every other
  row's load rule is unchanged, and the user's Load setting (Never) still applies.
- [x] **SBAG-04**: A click on the Well-Rested reminder, out of combat, uses the Cozy Sleeping Bag when
  it is in the bags. Without the bag, the click does nothing and raises no Lua error, the same as the
  familiar scroll click (CLICK-07). The overlay follows the bag arriving or leaving the bags, through
  the existing bag-change re-mark. The game's own "item not ready" message on cooldown is acceptable.

### Paladin auras (both clients, IDs never mixed)

- [ ] **PAURA-01**: On Forever, one reminder per paladin aura, each keyed on its top rank: Devotion
  [10293](https://www.wowhead.com/forever/spell=10293) (existing row), Retribution
  [10301](https://www.wowhead.com/forever/spell=10301), Concentration
  [19746](https://www.wowhead.com/forever/spell=19746), Shadow Resistance
  [19896](https://www.wowhead.com/forever/spell=19896), Frost Resistance
  [19898](https://www.wowhead.com/forever/spell=19898), Fire Resistance
  [19900](https://www.wowhead.com/forever/spell=19900). Permanent (no timer). Each is offered only to a
  paladin who knows a rank of it.
- [ ] **PAURA-02**: On Forever, any paladin aura up (any rank, cast by anyone) hides every Forever aura
  reminder: one group in the Forever block with the six rows and every lower rank, replacing the
  current Devotion-only "any aura" group (user decision: grouped like the blessings).
- [ ] **PAURA-03**: On retail, one reminder per aura: Devotion
  [465](https://www.wowhead.com/spell=465) (existing row), Concentration
  [317920](https://www.wowhead.com/spell=317920), Crusader [32223](https://www.wowhead.com/spell=32223),
  tagged retail, permanent, grouped so any one up hides all three. Retribution Aura (183435) stays
  out: documented on retail but no longer in the class toolkit (user, 2026-11-10).
- [ ] **PAURA-04**: No ID is shared between a Forever and a retail aura row, every new row carries its
  client tag, and the existing Devotion rows keep their keys (`metaReminder:10293`,
  `metaReminder:465`), so placed reminders are not orphaned.

### Review doc

- [ ] **DOC-08**: `docs/REMINDERS.md` lists the Well-Rested reminder (with its item link) and every
  aura row in the right client table, sorted by class; `node scripts/reminders-doc-check.js` and its
  `--selftest` pass. Excluded candidates (Sanctity Aura, retail Retribution Aura) go in
  `.planning/research/REMINDERS-NOT-INCLUDED.md`, not the doc.

### Cleanup and verification

- [ ] **CLEAN-02**: Cleanup per CLAUDE.md: unused code and duplication this milestone introduced,
  hot paths it touches (the load refresh and the bag-change re-mark), `stylua .`, and the release
  scripts.
- [ ] **VER-16**: The user checks in game what they can reach: on Forever, the Well-Rested offer
  with and without the bag, the click using the bag, the reminder on a character without the bag,
  and the aura reminders on a paladin; on retail, the three aura reminders. Rows not checked keep
  "(unverified in game)" in their comment.

## Future Requirements

- Backlog 999.29 (weapon enchants: imbues, poisons, oils) stays in the backlog.

## Out of Scope

- **Starting the Well-Rested timer on the click.** The bag only unfurls; the buff comes after a
  minute of rest, so a click-started timer would be wrong.
- **Tracking Well-Rested stacks.** The reminder watches presence only.
- **Sanctity Aura (Forever)** — not on the Forever paladin ability list (v0.5.6 research).
- **Retail Retribution Aura (183435)** — not in the Midnight class toolkit.
- **A per-aura model where only the same aura satisfies its reminder** — the user chose the grouped
  model.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SBAG-01 | Phase 86 | Complete |
| SBAG-02 | Phase 86 | Complete |
| SBAG-03 | Phase 86 | Complete |
| SBAG-04 | Phase 86 | Complete |
| PAURA-01 | Phase 87 | Pending |
| PAURA-02 | Phase 87 | Pending |
| PAURA-03 | Phase 87 | Pending |
| PAURA-04 | Phase 87 | Pending |
| DOC-08 | Phase 87 | Pending |
| CLEAN-02 | Phase 88 | Pending |
| VER-16 | Phase 89 | Pending |
