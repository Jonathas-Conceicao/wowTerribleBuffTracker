# Research Summary: v0.5.6 More Forever Reminders

**Researched:** 2026-11-09. Full catalogue: [`FOREVER-REMINDERS.md`](FOREVER-REMINDERS.md). This
replaces the v0.3 summary, which stays in git history.

## Method

Every Forever ID was checked against Wowhead's Forever database through the same data's tooltip
endpoint (`nether.wowhead.com/forever/tooltip/spell/<id>`; an ID not on Forever returns 404),
cross-checked against `forever.warcraftdb.com`, and filtered against warcraft.wiki.gg's per-class
"abilities (Forever)" lists. The filter matters: Forever's data still holds Season of Discovery
and NPC spells no player can learn (Molten Armor 428741, Fel Armor 403619, Aspect of the Viper
34074). BigWigsMods/WoWUI `forever-beta` holds no spell-ID data.

## Mage armors (priority)

Frost Armor 7301 (ranks 168, 7300), Ice Armor 10220 (ranks 7302, 7320, 10219), Mage Armor 22783
(ranks 6117, 22782), all 30 min. Every Forever tooltip says only one Armor spell can be active.
Group: `MetaReminderGroup(7301, 10220, 22783)`. Molten Armor is not learnable on Forever.

## Code risk: groups must be gated to Forever

`MetaReminderGroup` runs on both clients. 21562 is Prayer of Fortitude rank 1 on Forever **and**
the retail Power Word: Fortitude row, and 1459 is a `both` row, so an ungated group would silently
give retail rows Forever alternatives. A second `MetaReminderGroup` call naming an ID overwrites
the first, so Greater Blessings join the existing blessings call.

## How alternatives resolve

`ns:CastRuleFamily` matches by name, but only across ranks in the player's own spellbook. Self-only
buffs need one ID; group buffs cast by someone else need every rank listed.

## Group buffs as alternatives

| Single-target row | Add as alternatives |
|---|---|
| Arcane Intellect 1459 | Arcane Brilliance 23028 |
| Power Word: Fortitude 10938 | Prayer of Fortitude 21562, 21564 |
| Divine Spirit 27841 | Prayer of Spirit 27681 |
| Mark of the Wild 9885 | Gift of the Wild 21849, 21850 |
| The blessings group | Greater Kings 25898, Might 25782/25916, Wisdom 25894/25918 (same call) |

Greater Salvation, Greater Light and Greater Sanctuary do not exist on Forever.

## Existing rows flagged

Blessing of Salvation 1038 and Blessing of Light 19979 return 404 in both Forever databases and are
absent from the Forever paladin list, as Sanctuary was in 57.5. Flagged, not changed.

## New rows recommended

Ice Armor, Mage Armor; Demon Armor 11735 + Demon Skin 696 (grouped); Lightning Shield 10432 +
Water Shield 408510 (grouped; Water Shield is a reused SoD ID, needs an in-game check); Inner Fire
10952; Shadowform 15473 (permanent); paladin "any aura" row on Devotion Aura 10293 (never 465, the
retail row) with one-way alternatives; hunter "any aspect" row on Aspect of the Hawk 25296 with
one-way alternatives; second priority Demonic Sacrifice 18788 (aura 18789, alternatives
18790-18792, 2 h on Forever); optional Shadowguard 19312 (Troll priests).

## Excluded

Shaman weapon imbues and rogue poisons (weapon enchants, no aura); Omen of Clarity (passive on
Forever); druid forms; warrior stances; paladin seals (30 s); Fear Ward (3 min); Soul Link (needs a
pet-present load rule); situational buffs (Amplify/Dampen Magic, Shadow Protection, Detect
Invisibility).

## Suggested phase order

1. Forever gate on `MetaReminderGroup`, then the group-buff alternatives (every later group needs
   the gate).
2. Mage armors (the user tests these).
3. Other class rows; Demonic Sacrifice last (the only row needing a separate aura ID).
4. `docs/REMINDERS.md`, lifted from catalogue sections 5, 7 and 8.
5. Cleanup, then the Forever testing pass.

## Confidence

| Area | Confidence | Notes |
|---|---|---|
| IDs, ranks, durations | HIGH | Two independent Forever databases agree |
| Player-learnable | HIGH | Forever ability lists |
| Aura ID = spell ID | MEDIUM | Inferred from buff text; confirm with TBT's ID tooltip |
| Exclusivity | HIGH / MEDIUM | MEDIUM for Demon Skin vs Demon Armor (not stated in text) |
| Code behaviour | HIGH | Read from Providers.lua and Core.lua |

Open questions: catalogue section 10.
