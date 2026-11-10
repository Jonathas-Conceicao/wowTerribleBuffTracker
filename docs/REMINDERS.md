# Built-in reminders

A built-in reminder is an icon TBT shows while a class buff you can cast is missing. TBT offers it
in Suggested to a character who knows the spell. Duration is the timer TBT starts when you cast it;
`permanent` means there is no timer, and the icon shows as soon as the aura is gone.

**Also satisfied by:** if any listed spell is up, the buff counts as present and the reminder
stays hidden. An ID that has no row of its own is a one-way alternative: it hides this reminder,
but has no reminder of its own. On Forever every lower rank the character knows already counts and
is not listed. Ranks and group versions that another player can put on you are listed.

`scripts/reminders-doc-check.js` keeps this file and the reminder table in `Providers.lua` in step:
every ID linked here must be in the code, and every ID in the code must be linked here.

## Forever

WoW Forever reminders. Every link points at Wowhead's `/forever/` pages.

| Class | Spell | Row ID | Duration | Also satisfied by |
|---|---|---|---|---|
| Druid | [Mark of the Wild](https://www.wowhead.com/forever/spell=9885) | 9885 | 60 min | ranks [1126](https://www.wowhead.com/forever/spell=1126), [5232](https://www.wowhead.com/forever/spell=5232), [6756](https://www.wowhead.com/forever/spell=6756), [5234](https://www.wowhead.com/forever/spell=5234), [8907](https://www.wowhead.com/forever/spell=8907), [9884](https://www.wowhead.com/forever/spell=9884); Gift of the Wild [21849](https://www.wowhead.com/forever/spell=21849), [21850](https://www.wowhead.com/forever/spell=21850) |
| Druid | [Thorns](https://www.wowhead.com/forever/spell=9910) | 9910 | 10 min | ranks [467](https://www.wowhead.com/forever/spell=467), [782](https://www.wowhead.com/forever/spell=782), [1075](https://www.wowhead.com/forever/spell=1075), [8914](https://www.wowhead.com/forever/spell=8914), [9756](https://www.wowhead.com/forever/spell=9756) |
| General | [Well-Rested](https://www.wowhead.com/forever/spell=429959), from resting in the [Cozy Sleeping Bag](https://www.wowhead.com/forever/item=211527): a click uses the bag, and the buff arrives after a minute of rest. Offered while the bag is in your bags; once placed it loads on every character | 429959 | 120 min | none |
| Hunter | [Trueshot Aura](https://www.wowhead.com/forever/spell=20906) | 20906 | 30 min | ranks [19506](https://www.wowhead.com/forever/spell=19506), [20905](https://www.wowhead.com/forever/spell=20905) |
| Hunter | [Aspect of the Hawk](https://www.wowhead.com/forever/spell=25296) | 25296 | permanent | Hunter aspects group, below |
| Hunter | [Aspect of the Monkey](https://www.wowhead.com/forever/spell=13163) | 13163 | permanent | Hunter aspects group, below |
| Hunter | [Aspect of the Cheetah](https://www.wowhead.com/forever/spell=5118) | 5118 | permanent | Hunter aspects group, below |
| Hunter | [Aspect of the Pack](https://www.wowhead.com/forever/spell=13159) | 13159 | permanent | Hunter aspects group, below |
| Hunter | [Aspect of the Wild](https://www.wowhead.com/forever/spell=20190) | 20190 | permanent | Hunter aspects group, below |
| Hunter | [Aspect of the Beast](https://www.wowhead.com/forever/spell=13161) | 13161 | permanent | Hunter aspects group, below |
| Mage | [Arcane Intellect](https://www.wowhead.com/forever/spell=1459) | 1459 | 60 min | ranks [1460](https://www.wowhead.com/forever/spell=1460), [1461](https://www.wowhead.com/forever/spell=1461), [10156](https://www.wowhead.com/forever/spell=10156), [10157](https://www.wowhead.com/forever/spell=10157); Arcane Brilliance [23028](https://www.wowhead.com/forever/spell=23028) |
| Mage | [Frost Armor](https://www.wowhead.com/forever/spell=7301) | 7301 | 30 min | Ice Armor [10220](https://www.wowhead.com/forever/spell=10220), Mage Armor [22783](https://www.wowhead.com/forever/spell=22783) |
| Mage | [Ice Armor](https://www.wowhead.com/forever/spell=10220) | 10220 | 30 min | Frost Armor [7301](https://www.wowhead.com/forever/spell=7301), Mage Armor [22783](https://www.wowhead.com/forever/spell=22783) |
| Mage | [Mage Armor](https://www.wowhead.com/forever/spell=22783) | 22783 | 30 min | Frost Armor [7301](https://www.wowhead.com/forever/spell=7301), Ice Armor [10220](https://www.wowhead.com/forever/spell=10220) |
| Mage | [Cat Familiar](https://www.wowhead.com/forever/spell=1302303), from a scroll: a click uses the best one in your bags, [Cat](https://www.wowhead.com/forever/item=277493), [Frog](https://www.wowhead.com/forever/item=277483) or [Rat](https://www.wowhead.com/forever/item=275069). Offered once Comprehend Scroll is known | 1302303 | 60 min | Frog Familiar [1302285](https://www.wowhead.com/forever/spell=1302285), Rat Familiar [1296202](https://www.wowhead.com/forever/spell=1296202) |
| Mage | [Amplify Magic](https://www.wowhead.com/forever/spell=10170) | 10170 | 10 min | Amplify and Dampen group, below |
| Mage | [Dampen Magic](https://www.wowhead.com/forever/spell=10174) | 10174 | 10 min | Amplify and Dampen group, below |
| Paladin | [Blessing of Kings](https://www.wowhead.com/forever/spell=20217) | 20217 | 60 min | Blessings group, below |
| Paladin | [Blessing of Might](https://www.wowhead.com/forever/spell=25291) | 25291 | 60 min | Blessings group, below |
| Paladin | [Blessing of Wisdom](https://www.wowhead.com/forever/spell=25290) | 25290 | 60 min | Blessings group, below |
| Paladin | [Righteous Fury](https://www.wowhead.com/forever/spell=25780) | 25780 | 30 min | none |
| Paladin | [Devotion Aura](https://www.wowhead.com/forever/spell=10293) | 10293 | permanent | Paladin auras group, below |
| Paladin | [Retribution Aura](https://www.wowhead.com/forever/spell=10301) | 10301 | permanent | Paladin auras group, below |
| Paladin | [Concentration Aura](https://www.wowhead.com/forever/spell=19746) | 19746 | permanent | Paladin auras group, below |
| Paladin | [Shadow Resistance Aura](https://www.wowhead.com/forever/spell=19896) | 19896 | permanent | Paladin auras group, below |
| Paladin | [Frost Resistance Aura](https://www.wowhead.com/forever/spell=19898) | 19898 | permanent | Paladin auras group, below |
| Paladin | [Fire Resistance Aura](https://www.wowhead.com/forever/spell=19900) | 19900 | permanent | Paladin auras group, below |
| Priest | [Power Word: Fortitude](https://www.wowhead.com/forever/spell=10938) | 10938 | 60 min | ranks [1243](https://www.wowhead.com/forever/spell=1243), [1244](https://www.wowhead.com/forever/spell=1244), [1245](https://www.wowhead.com/forever/spell=1245), [2791](https://www.wowhead.com/forever/spell=2791), [10937](https://www.wowhead.com/forever/spell=10937); Prayer of Fortitude [21562](https://www.wowhead.com/forever/spell=21562), [21564](https://www.wowhead.com/forever/spell=21564) |
| Priest | [Divine Spirit](https://www.wowhead.com/forever/spell=27841) (Discipline talent) | 27841 | 60 min | ranks [14752](https://www.wowhead.com/forever/spell=14752), [14818](https://www.wowhead.com/forever/spell=14818), [14819](https://www.wowhead.com/forever/spell=14819); Prayer of Spirit [27681](https://www.wowhead.com/forever/spell=27681) |
| Priest | [Inner Fire](https://www.wowhead.com/forever/spell=10952) | 10952 | 10 min | none |
| Priest | [Shadowguard](https://www.wowhead.com/forever/spell=19312) (Troll only) | 19312 | 10 min | none |
| Priest | [Shadow Protection](https://www.wowhead.com/forever/spell=10958) | 10958 | 10 min | ranks [976](https://www.wowhead.com/forever/spell=976), [10957](https://www.wowhead.com/forever/spell=10957); Prayer of Shadow Protection [27683](https://www.wowhead.com/forever/spell=27683) |
| Shaman | [Lightning Shield](https://www.wowhead.com/forever/spell=10432) (3 charges, so it can drop before the timer ends) | 10432 | 10 min | Water Shield [408510](https://www.wowhead.com/forever/spell=408510) |
| Shaman | [Water Shield](https://www.wowhead.com/forever/spell=408510) (Restoration talent) | 408510 | 10 min | Lightning Shield [10432](https://www.wowhead.com/forever/spell=10432) |
| Warlock | [Blood Pact](https://www.wowhead.com/forever/spell=11767) (the imp's buff; offered once Summon Imp is known; no click action) | 11767 | permanent | ranks [6307](https://www.wowhead.com/forever/spell=6307), [7804](https://www.wowhead.com/forever/spell=7804), [7805](https://www.wowhead.com/forever/spell=7805), [11766](https://www.wowhead.com/forever/spell=11766) |
| Warlock | [Demon Armor](https://www.wowhead.com/forever/spell=11735) | 11735 | 30 min | Demon Skin [696](https://www.wowhead.com/forever/spell=696) |
| Warlock | [Demon Skin](https://www.wowhead.com/forever/spell=696) | 696 | 30 min | Demon Armor [11735](https://www.wowhead.com/forever/spell=11735) |
| Warlock | [Demonic Sacrifice](https://www.wowhead.com/forever/spell=18788) (watches aura [18789](https://www.wowhead.com/forever/spell=18789); the cast itself carries no buff) | 18788 | 120 min | the other sacrifice buffs [18790](https://www.wowhead.com/forever/spell=18790), [18791](https://www.wowhead.com/forever/spell=18791), [18792](https://www.wowhead.com/forever/spell=18792) |
| Warrior | [Battle Shout](https://www.wowhead.com/forever/spell=25289) | 25289 | 3 min | ranks [6673](https://www.wowhead.com/forever/spell=6673), [5242](https://www.wowhead.com/forever/spell=5242), [6192](https://www.wowhead.com/forever/spell=6192), [11549](https://www.wowhead.com/forever/spell=11549), [11550](https://www.wowhead.com/forever/spell=11550), [11551](https://www.wowhead.com/forever/spell=11551) |

**Amplify and Dampen group** (Mage; any one up hides both reminders): Amplify Magic
[10170](https://www.wowhead.com/forever/spell=10170) and ranks
[1008](https://www.wowhead.com/forever/spell=1008), [8455](https://www.wowhead.com/forever/spell=8455), [10169](https://www.wowhead.com/forever/spell=10169);
Dampen Magic [10174](https://www.wowhead.com/forever/spell=10174) and ranks
[604](https://www.wowhead.com/forever/spell=604), [8450](https://www.wowhead.com/forever/spell=8450), [8451](https://www.wowhead.com/forever/spell=8451), [10173](https://www.wowhead.com/forever/spell=10173).

**Blessings group** (Paladin; any one up hides every blessing reminder): Kings
[20217](https://www.wowhead.com/forever/spell=20217), Might
[25291](https://www.wowhead.com/forever/spell=25291), Wisdom
[25290](https://www.wowhead.com/forever/spell=25290); Might ranks
[19740](https://www.wowhead.com/forever/spell=19740), [19834](https://www.wowhead.com/forever/spell=19834), [19835](https://www.wowhead.com/forever/spell=19835), [19836](https://www.wowhead.com/forever/spell=19836), [19837](https://www.wowhead.com/forever/spell=19837), [19838](https://www.wowhead.com/forever/spell=19838);
Wisdom ranks
[19742](https://www.wowhead.com/forever/spell=19742), [19850](https://www.wowhead.com/forever/spell=19850), [19852](https://www.wowhead.com/forever/spell=19852), [19853](https://www.wowhead.com/forever/spell=19853), [19854](https://www.wowhead.com/forever/spell=19854);
Greater Kings [25898](https://www.wowhead.com/forever/spell=25898); Greater Might
[25782](https://www.wowhead.com/forever/spell=25782), [25916](https://www.wowhead.com/forever/spell=25916); Greater Wisdom
[25894](https://www.wowhead.com/forever/spell=25894), [25918](https://www.wowhead.com/forever/spell=25918).

**Hunter aspects group** (Hunter; any one of the six aspects up, at any rank, hides every aspect
reminder; Aspect of the Viper and Aspect of the Falcon are not on the Forever hunter list and never
count):
- Aspect of the Hawk [25296](https://www.wowhead.com/forever/spell=25296) and ranks [13165](https://www.wowhead.com/forever/spell=13165), [14318](https://www.wowhead.com/forever/spell=14318), [14319](https://www.wowhead.com/forever/spell=14319), [14320](https://www.wowhead.com/forever/spell=14320), [14321](https://www.wowhead.com/forever/spell=14321), [14322](https://www.wowhead.com/forever/spell=14322)
- Aspect of the Monkey [13163](https://www.wowhead.com/forever/spell=13163)
- Aspect of the Cheetah [5118](https://www.wowhead.com/forever/spell=5118)
- Aspect of the Pack [13159](https://www.wowhead.com/forever/spell=13159)
- Aspect of the Wild [20190](https://www.wowhead.com/forever/spell=20190) and rank [20043](https://www.wowhead.com/forever/spell=20043)
- Aspect of the Beast [13161](https://www.wowhead.com/forever/spell=13161) and Forever ranks [1299445](https://www.wowhead.com/forever/spell=1299445), [1299446](https://www.wowhead.com/forever/spell=1299446), [1299447](https://www.wowhead.com/forever/spell=1299447)

**Paladin auras group** (Paladin; any one up hides every aura reminder): Devotion Aura
[10293](https://www.wowhead.com/forever/spell=10293) and ranks
[465](https://www.wowhead.com/forever/spell=465), [10290](https://www.wowhead.com/forever/spell=10290), [643](https://www.wowhead.com/forever/spell=643), [10291](https://www.wowhead.com/forever/spell=10291), [1032](https://www.wowhead.com/forever/spell=1032), [10292](https://www.wowhead.com/forever/spell=10292);
Retribution Aura ranks
[7294](https://www.wowhead.com/forever/spell=7294), [10298](https://www.wowhead.com/forever/spell=10298), [10299](https://www.wowhead.com/forever/spell=10299), [10300](https://www.wowhead.com/forever/spell=10300), [10301](https://www.wowhead.com/forever/spell=10301);
Concentration Aura [19746](https://www.wowhead.com/forever/spell=19746); Shadow Resistance Aura
[19876](https://www.wowhead.com/forever/spell=19876), [19895](https://www.wowhead.com/forever/spell=19895), [19896](https://www.wowhead.com/forever/spell=19896);
Frost Resistance Aura
[19888](https://www.wowhead.com/forever/spell=19888), [19897](https://www.wowhead.com/forever/spell=19897), [19898](https://www.wowhead.com/forever/spell=19898);
Fire Resistance Aura
[19891](https://www.wowhead.com/forever/spell=19891), [19899](https://www.wowhead.com/forever/spell=19899), [19900](https://www.wowhead.com/forever/spell=19900).

## Retail

Midnight retail reminders. Every link points at Wowhead's retail pages.

| Class | Spell | Row ID | Duration | Also satisfied by |
|---|---|---|---|---|
| Druid | [Mark of the Wild](https://www.wowhead.com/spell=1126) | 1126 | 60 min | none |
| Druid | [Symbiotic Relationship](https://www.wowhead.com/spell=474750) (watches aura [474754](https://www.wowhead.com/spell=474754); cast on your target) | 474750 | 60 min | none |
| Evoker | [Blessing of the Bronze](https://www.wowhead.com/spell=364342) (watches aura [381748](https://www.wowhead.com/spell=381748)) | 364342 | 60 min | none |
| Evoker | [Source of Magic](https://www.wowhead.com/spell=369459) (cast on your target) | 369459 | 60 min | none |
| Mage | [Arcane Intellect](https://www.wowhead.com/spell=1459) | 1459 | 60 min | none |
| Mage | [Arcane Familiar](https://www.wowhead.com/spell=210126) (offered once the talent is known; a click casts Arcane Intellect, which grants it) | 210126 | 60 min | none |
| Paladin | [Devotion Aura](https://www.wowhead.com/spell=465) | 465 | permanent | Paladin auras group, below |
| Paladin | [Concentration Aura](https://www.wowhead.com/spell=317920) | 317920 | permanent | Paladin auras group, below |
| Paladin | [Crusader Aura](https://www.wowhead.com/spell=32223) | 32223 | permanent | Paladin auras group, below |
| Priest | [Power Word: Fortitude](https://www.wowhead.com/spell=21562) | 21562 | 60 min | none |
| Shaman | [Skyfury](https://www.wowhead.com/spell=462854) | 462854 | 60 min | none |
| Shaman | [Lightning Shield](https://www.wowhead.com/spell=192106) | 192106 | 60 min | none |
| Warrior | [Battle Shout](https://www.wowhead.com/spell=6673) | 6673 | 60 min | none |

**Paladin auras group** (Paladin; any one up hides every aura reminder): Devotion Aura
[465](https://www.wowhead.com/spell=465), Concentration Aura
[317920](https://www.wowhead.com/spell=317920), Crusader Aura
[32223](https://www.wowhead.com/spell=32223).
