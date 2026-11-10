# Reminders not included (internal)

Internal tracking only. Moved out of `docs/REMINDERS.md` on 2026-11-09 at the user's request: the
public review doc lists only the reminders TBT ships. Candidates that were considered and left out,
mostly for Forever. IDs and reasoning are in `FOREVER-REMINDERS.md`.

| Class | Candidate | Reason |
|---|---|---|
| Mage | Molten Armor | Not learnable on Forever. |
| Warlock | Fel Armor | Not learnable on Forever. |
| Mage | Mana Shield, Fire Ward, Frost Ward, Ice Barrier | Short combat cooldowns, not buffs you keep up. |
| Warlock | Shadow Ward | Short combat cooldown. |
| Druid | Barkskin, Nature's Grasp | Short combat cooldowns. |
| Priest | Elune's Grace, Feedback | Short combat cooldowns. |
| Priest | Shadowform (15473) | Shipped in Phase 82, dropped by the user on 2026-11-09: a form like a druid's, not a reminder. A placed one is an orphan. |
| Several | Arcane Brilliance, Prayer of Fortitude, Prayer of Spirit, Prayer of Shadow Protection, Gift of the Wild, the Greater Blessings, as rows of their own | They count as alternatives on the single-target row instead. |
| Paladin | Blessing of Salvation (1038, Greater 25895), Blessing of Light (19979, Greater 25890), Revoker | Removed from Forever; dropped in Phase 80. Restore if Blizzard brings them back (note in Providers.lua). |
| Warlock | Soul Link | Lasts only while a demon is out, and TBT has no "pet is out" rule, so it would show while you have no demon. |
| Warlock, Hunter, any | Detection and tracking skills: Detect Invisibility, Track Beasts and the other hunter tracking, Find Herbs, Find Minerals | Dropped by the user on 2026-11-09. |
| Warlock | Unending Breath | Situational. |
| Shaman | Weapon imbues (Rockbiter, Flametongue, Frostbrand, Windfury Weapon) | A weapon enchant, not an aura, so there is nothing to watch. Backlog 999.29. |
| Rogue | Poisons | A weapon enchant from an item, not an aura. Backlog 999.29. |
| Shaman | Totems (Strength of Earth, Windfury Totem and the others) | The aura IDs differ from the casts, and totem buffs depend on where you stand. |
| Shaman | Earth Shield | Not on Forever. |
| Priest | Fear Ward | 3 minutes on Forever, and a targeted cooldown. |
| Priest | Touch of Weakness | 2 minutes, too short. |
| Druid | Omen of Clarity | Passive on Forever, so there is nothing to remind. |
| Druid | Forms | Toggled all the time to heal or travel. |
| Warrior | Stances | A warrior is always in one stance, so it is never missing. |
| Paladin | Seals | 30-second combat buffs. |
| Paladin | Sanctity Aura | Not on the Forever paladin list; added only if a Forever paladin sees it. |
| Paladin | Blessing of Sanctuary | No longer exists on Forever. |
| Hunter | Aspect of the Viper, Aspect of the Falcon | Not on the Forever hunter list, so they do not count toward the aspect row either. |
| Paladin (retail) | Retribution Aura (183435) | Still documented on retail but no longer in the Midnight class toolkit (user, 2026-11-10). Not a row and not in the retail aura group. |

## In-game verification status

Kept in the `(unverified in game)` trailing comments in `Providers.lua`, not in the public doc.

- Verified: the original Forever Mage, Paladin and Warlock rows (2026-09-29); every retail row
  (2026-10-01); Ice Armor, Mage Armor and the familiar scroll click (2026-11-09).
- Unverified: every other v0.5.6 row. Shipped on community feedback (user decision 2026-11-09).
  Known risks: Water Shield's reused ID 408510; Battle Shout 3 min, Demonic Sacrifice 2 h and
  Divine Spirit 60 min durations; whether Amplify and Dampen Magic stack.
- Unverified (v0.5.7, until Phase 89): the Well-Rested reminder (buff 429959, the sleeping bag
  offer and click); the Forever aura rows 10301, 19746, 19896, 19898, 19900 and the now-mutual
  aura group; the retail Concentration 317920 and Crusader 32223 rows and the now-mutual retail
  aura group.
