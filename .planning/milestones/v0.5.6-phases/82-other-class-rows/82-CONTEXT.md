# Phase 82: Other Class Rows - Context

**Gathered:** 2026-11-09
**Status:** Ready for planning
**Mode:** Autonomous kickoff. Every decision below was made by the user during `/gsd-new-milestone`
or at the autonomous kickoff, or follows directly from one; nothing is left open.

<domain>
## Phase Boundary

New Forever reminder rows for warlocks, shamans, priests, paladins and hunters, plus the mage
situational pair, each with its exclusive group and rank alternatives. All of it is data in
`Providers.lua`; no new behaviour.

</domain>

<decisions>
## Implementation Decisions

### Scope rule (user, 2026-11-09)
- Data only, through the existing `MetaReminderRow` / `MetaReminderGroup`. Every group call goes
  inside Phase 80's `if ns.CLIENT_IS_FOREVER` block.
- IDs come from research §5 and §12.2 only; Forever links only. Every new row's comment says
  "(unverified in game)".

### Rows (all client "forever", the default)
- **MREM-08 Warlock armors.** `MetaReminderRow(11735, 30)` Demon Armor, `MetaReminderRow(696, 30)`
  Demon Skin; `MetaReminderGroup(11735, 696)`.
- **MREM-09 Shaman shields.** `MetaReminderRow(10432, 10)` Lightning Shield,
  `MetaReminderRow(408510, 10)` Water Shield (Restoration talent; a reused ID, check in game);
  `MetaReminderGroup(10432, 408510)`.
- **MREM-10 Priest.** `MetaReminderRow(10952, 10)` Inner Fire; `MetaReminderRow(15473, 0)`
  Shadowform (permanent: no timer).
- **MREM-11 Paladin.** `MetaReminderRow(10293, 0)` Devotion Aura as the "any aura" row. Never use
  465, which is the retail row. One-way group with every Devotion, Retribution, Concentration and
  resistance-aura rank from §12.2, including 465 (Forever block only). Another paladin's aura
  satisfies it (default accepted at requirements). Sanctity Aura 20218 is not added.
- **MREM-12 Hunter.** `MetaReminderRow(25296, 0)` Aspect of the Hawk as the "any aspect" row.
  One-way group: Monkey 13163, Cheetah 5118, Pack 13159, Wild 20043/20190, Beast 13161. Never
  Viper 34074 or Falcon 469145.
- **MREM-14 Priest.** `MetaReminderRow(19312, 10)` Shadowguard. The existing known-spell rule
  offers it only to a priest who knows it (Trolls).
- **MREM-15 Mage, situational.** `MetaReminderRow(10170, 10)` Amplify Magic and
  `MetaReminderRow(10174, 10)` Dampen Magic. One group with both rows plus every rank: Amplify
  1008, 8455, 10169; Dampen 604, 8450, 8451, 10173. Any one up hides both.
- **MREM-16 Priest, situational.** `MetaReminderRow(10958, 10)` Shadow Protection; one-way group
  with 976, 10957 and Prayer of Shadow Protection 27683.
- **MREM-13 Warlock, last.** `MetaReminderRow(18788, 120, nil, nil, nil, { auraID = 18789 })`
  Demonic Sacrifice; one-way group with 18790, 18791, 18792. It is the only row with a separate
  aura ID, so it lands last. A click casts 18788 through the existing default.
- **MREM-17 dropped (user, 2026-11-09):** "let's drop all hunter (or other) track skills". No
  Detect Invisibility, no Track Beasts/Humanoids/etc., no Find Herbs/Minerals rows.

### Clicks
- Every new row uses the existing spell click (cast by name, on the player). None is `allyCast`:
  each reminder is about the player's own buff.

### Claude's Discretion
- Row order inside the table (grouped by class, with comments) and the formatting of the long
  group calls. No comments inside expressions: stylua CRCRLF trap.

</decisions>

<code_context>
## Existing Code Insights

- Permanent rows (`minutes = 0`) already exist: retail Devotion Aura 465 shows once the aura is
  gone, with no lead window.
- The `auraID` opt is the existing Phase 64 mechanism (474750 watches 474754).
- The known-spell rule for the Suggested offer and loading is `ns:ResolveSpellKnown(def.knownID)`.

</code_context>

<specifics>
## Specific Ideas

None beyond the rows above.

</specifics>

<deferred>
## Deferred Ideas

- Soul Link needs a "pet is out" load rule.
- Sanctity Aura 20218: add only if a Forever paladin sees it.
- Tracking and detection skills: dropped by the user, not deferred.

</deferred>
