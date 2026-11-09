# Forever Reminder Catalogue (v0.5.6 More Forever Reminders)

**Researched:** 2026-11-09 (Forever launched 2026-11-04; build 1.60.1.x, interface 16001).
Follow-ups the same day: §11 (mage familiar scrolls) and §12 (rank coverage, after the user's "these ids need to group the different ranks").
**Scope:** candidate Forever class/self-buff reminder rows, exclusive groups, and group-buff
alternatives for `Providers.lua`'s `MetaReminderRow` / `MetaReminderGroup` table. Retail rows are
listed only for their links (section 8).
**Overall confidence:** HIGH for IDs, ranks and durations (all read from Forever's own data);
MEDIUM for aura-ID-equals-spell-ID (inferred from the data, to be confirmed with TBT's ID tooltip);
MEDIUM for a few exclusivity claims that the Forever text does not state (flagged per row).

**Scope constraint (user, 2026-11-09):** "I don't want anything to work differently than it
already does (other than the mage familiar scrolls, which will use an item when clicked instead
of casting something). This milestone focuses mainly on extending the suggestions with more
presets and adding the doc." So:
- every row, group and rank alternative below is **data only**: `MetaReminderRow` /
  `MetaReminderGroup` calls with existing arguments and opts (`client`, `auraID`, `allyCast`,
  `knownID`, `castID`);
- no matching, rank-family, load-rule or cast-path code changes are proposed;
- the one code addition is the familiar scroll's item click (§11.3).

Every rank gap in §12 closes with data alone, so none is left open.

**§12 supersedes the group calls in §4 and §5.** Those sections name the top ranks and group
buffs; §12 adds every single-target rank another player can put on you, which the final
`MetaReminderGroup` calls must carry.

---

## 1. Evidence and method

Every Forever ID below was checked against Forever's own data, never a Classic page.

| Source | What it proves | How it was used |
|--------|----------------|-----------------|
| Wowhead Forever database: `https://www.wowhead.com/forever/spell=<id>` and `/forever/item=<id>` | ID exists in Forever's client data, name, required level, rank, duration, description, and the **buff** text the aura shows | Read through Wowhead's tooltip endpoints for the same database, `https://nether.wowhead.com/forever/tooltip/spell/<id>` and `/item/<id>`, which return the `/forever/` page's tooltip as JSON (the HTML page itself is behind a CloudFront bot block for scripted fetches; `/forever/spell=7301` was also fetched as a page and matched). An ID the Forever database does not have returns **HTTP 404** (e.g. 1038, 19979, 30482, 27127) |
| Warcraft DB, Forever edition: `https://forever.warcraftdb.com/data/spell/<id>` + its search API | Second, independent Forever datamine; the name search found every ID of each spell name, including Forever-only new IDs (1.2M–1.3M range) | Cross-check of existence and of "is there a Forever-only rank I missed" |
| warcraft.wiki.gg `<Class>_abilities_(Forever)` pages | What a Forever **player** can actually learn (trainer, talent, quest, codex) | Filters out IDs that sit in Forever's data but are not obtainable (Season of Discovery rune leftovers such as Molten Armor 428741, Fel Armor 403619, Aspect of the Viper 34074) |
| Blizzard's Forever class deep dives (worldofwarcraft.blizzard.com/news/24302097, Mage & Shaman) | Design changes: Water Shield is a Restoration talent, "only one shield at a time", shaman imbues last 60 min | Exclusivity and the imbue exclusion |
| BigWigsMods/WoWUI `forever-beta` | Blizzard's shipped Forever UI | Checked `Blizzard_CooldownViewer/GroupBuffFilter.lua`: its group-buff list is data-driven from C (`C_UnitAuras.SetHiddenGroupBuffs`), with **no spell IDs in the Lua**, so the repo can't cross-check any ID here. No other spell-ID data was found in it |

**Important caveat on Forever's database.** Forever's client data still contains Season of
Discovery and NPC spells under the same names (e.g. Molten Armor 428741, Water Shield 408510,
Frost Armor 1283419, Prayer of Fortitude 450086, Shadowform 1213334). An ID being present on
`/forever/` is **necessary but not sufficient**; each recommended row below is also on the
Forever ability list for its class, or is a talent the Forever tooltip labels "Talent".

**Aura ID = spell ID** is marked *likely* when the Forever tooltip for that spell ID carries a
non-empty `buff` block (the aura the spell applies is described under the same ID). It is marked
*differs* when the buff block is empty and the aura lives under another ID (Soul Link, Demonic
Sacrifice). The user confirms each in game with TBT's ID tooltip, as for existing rows.

---

## 2. How alternatives resolve in the code, and what that means for the rows

Read from `Providers.lua` 101–160, 330–447, 1106–1193 and `Core.lua` 890–1003, 1478–1500,
1535–1607, 1652–1714. This is a description of current behaviour, which v0.5.6 leaves unchanged.

1. **An alternative ID is expanded through `ns:CastRuleFamily(altID)`.** On Forever
   (`ns.CLIENT_HAS_SPELL_RANKS`) that is `ns:ResolveRankFamily(altID)`: the ID itself, its
   base/override, then **every entry in the player's own spellbook with the same spell name**
   (one bounded pass of base/override on those). Names come from `C_Spell.GetSpellInfo(altID)`.
   So an alternative is resolved **by name family, but only across ranks the player knows**. The
   row's own watch list is built the same way (`ns.rankFamilies[key]`, coverAllRanks on Forever):
   the row's own ID plus the ranks the player knows.
2. **Consequence for self-only buffs (armors, shields, Inner Fire, Shadowform, aspects other than
   Pack/Wild):** only the player can put them on the player, and the player can only cast ranks
   they know, so **one ID per spell is enough**. Use the top rank (convention of the existing
   rows); the name family covers lower ranks.
3. **Consequence for anything another player can cast on you** (single-target buffs as well as
   group buffs): the family misses every rank the player doesn't know, **except** the one ID the
   row or alternative names. **List every such rank explicitly** as an alternative (§12): pure
   data, closed with the existing `MetaReminderGroup`. Duplicates are harmless:
   `RebuildReminderWatch` de-duplicates (`ListContains`), and `IndexFamily` is a set per key.
4. **`MetaReminderGroup` overwrites, it does not append** (`def.alternatives = others`). A row can
   be in exactly one group call. The five blessings' existing call must be **replaced** by one
   longer call, not followed by a second one.
5. **`MetaReminderGroup` runs on both clients, but rows only register on their own client.**
   This is a **live trap for v0.5.6:** `21562` is Prayer of Fortitude rank 1 on Forever **and** the
   retail Power Word: Fortitude row. An ungated `MetaReminderGroup(10938, 21562, 21564)` running on
   retail finds the retail 21562 row and gives it `{10938, 21564}` as alternatives. That would
   change retail behaviour, which the scope constraint forbids. Likewise:
   - `1459` is a `client = "both"` row, so an ungated `MetaReminderGroup(1459, …)` would add Forever
     ranks and Arcane Brilliance to retail's Arcane Intellect;
   - the §12 rank lists also contain 1126 (the retail MotW row), 6673 (the retail Battle Shout
     row) and 465 (the retail Devotion Aura row), all of which are **also legitimate Forever
     ranks**.

   **Fix, data placement only (no function change):** put every new Forever group call inside
   one `if ns.CLIENT_IS_FOREVER then … end` block in the table. `MetaReminderRow` already reads
   `ns.CLIENT_IS_FOREVER` at the same load time, so the flag is set. On retail the block never
   runs, so retail's rows, alternatives and behaviour are exactly as today. On Forever the retail
   rows never register, so listing their IDs as Forever ranks is safe. (A `client` argument on
   `MetaReminderGroup` would also work, but it changes a function; the `if` block doesn't.)
   The existing blessings call (20217, 25291, 25290, 1038, 19979) names only Forever rows, so
   moving it into the block changes nothing on either client.
6. **One-way vs mutual.** A listed ID that has a row gets the others; an ID with no row is a
   one-way alternative. So: armors/shields that each deserve a Suggested tile are **rows in one
   group** (mutual); group buffs, extra ranks and the "any aura / any aspect" cases are **one-way
   alternatives** (the retail Devotion Aura pattern).
7. **Clicks cast by name** (`ReminderClick.lua` `ResolveCastName`), so the game casts the
   highest rank the player knows. Naming a top-rank ID the character has not learned yet is fine
   for the click as well as for the load rule.

---

## 3. Mage armors (priority — the user tests these)

All three exist on Forever, all last 30 min, and each Forever tooltip says verbatim: *"Only one
type of Armor spell can be active on the Mage at any time."* That sentence is the game's own
mutual-exclusion rule, so the group is justified by the game, not by convention.

| Spell | Row ID (top rank) | All Forever rank IDs (level) | Duration | Aura = spell? | Confidence |
|-------|-------------------|------------------------------|----------|---------------|------------|
| Frost Armor *(existing row)* | [7301](https://www.wowhead.com/forever/spell=7301) | [168](https://www.wowhead.com/forever/spell=168) (1), [7300](https://www.wowhead.com/forever/spell=7300) (10), [7301](https://www.wowhead.com/forever/spell=7301) (20) | 30 min | likely (buff on ID) | HIGH |
| Ice Armor | [10220](https://www.wowhead.com/forever/spell=10220) | [7302](https://www.wowhead.com/forever/spell=7302) (30), [7320](https://www.wowhead.com/forever/spell=7320) (40), [10219](https://www.wowhead.com/forever/spell=10219) (50), [10220](https://www.wowhead.com/forever/spell=10220) (60) | 30 min | likely (buff on ID) | HIGH |
| Mage Armor | [22783](https://www.wowhead.com/forever/spell=22783) | [6117](https://www.wowhead.com/forever/spell=6117) (34), [22782](https://www.wowhead.com/forever/spell=22782) (46), [22783](https://www.wowhead.com/forever/spell=22783) (58) | 30 min | likely (buff on ID) | HIGH |
| Molten Armor | — **exclude** | Forever's data has only the SoD rune spell [428741](https://www.wowhead.com/forever/spell=428741) ("Requires level 1", rune-style ID). The TBC ID 30482 is a 404 on `/forever/`. Not on the Forever Mage ability list (warcraft.wiki.gg) or in Blizzard's Mage deep dive | 30 min | — | HIGH that a Forever mage can't learn it |

**Group:** `MetaReminderGroup(7301, 10220, 22783)` (inside the Forever block), so all three rows
are mutual alternatives. Frost Armor and Ice Armor are different names, so only this group joins
them; the rank family does not. The armors are self-only, so no lower ranks need listing (§12).

Notes:
- Ice Armor does not remove Frost Armor from the spellbook, so a level-30+ mage sees both tiles in
  Suggested; they place whichever they use. With the group, either one placed is satisfied by any
  armor.
- Ice Armor is **not** a Forever talent (Frost Armor default at 1, Ice Armor trainer at 30, Mage
  Armor trainer at 34; warcraft.wiki.gg Mage abilities (Forever)).
- Forever's DB also has NPC IDs named Frost Armor (1200, 12544, 12556, 15784, 18100, 1283419) and
  Ice Armor (506). The spellbook-scoped name family never reaches them; ignore.

---

## 4. Group buffs as alternatives (user decision 2026-11-09)

Every ID below is a Forever ID read from `/forever/` data. All last **1 hour** on Forever
(Greater Blessings were 15 min in vanilla; Forever made all Blessings and Greater Blessings 1 hour,
which the tooltips confirm). **The final calls, with every single-target rank added, are in §12.**

| Single-target row (existing) | Group buff | All Forever rank IDs | Duration | Confidence |
|------------------------------|-----------|----------------------|----------|------------|
| Arcane Intellect [1459](https://www.wowhead.com/forever/spell=1459) | Arcane Brilliance | [23028](https://www.wowhead.com/forever/spell=23028) (56; only rank; 27127 is 404) | 60 | HIGH |
| Power Word: Fortitude [10938](https://www.wowhead.com/forever/spell=10938) | Prayer of Fortitude | [21562](https://www.wowhead.com/forever/spell=21562) (48), [21564](https://www.wowhead.com/forever/spell=21564) (60) | 60 | HIGH |
| Divine Spirit [27841](https://www.wowhead.com/forever/spell=27841) | Prayer of Spirit | [27681](https://www.wowhead.com/forever/spell=27681) (60; only rank) | 60 | HIGH |
| Mark of the Wild [9885](https://www.wowhead.com/forever/spell=9885) | Gift of the Wild | [21849](https://www.wowhead.com/forever/spell=21849) (50), [21850](https://www.wowhead.com/forever/spell=21850) (60) | 60 | HIGH |
| Blessing of Kings [20217](https://www.wowhead.com/forever/spell=20217) | Greater Blessing of Kings | [25898](https://www.wowhead.com/forever/spell=25898) (60) | 60 | HIGH |
| Blessing of Might [25291](https://www.wowhead.com/forever/spell=25291) | Greater Blessing of Might | [25782](https://www.wowhead.com/forever/spell=25782) (52), [25916](https://www.wowhead.com/forever/spell=25916) (60) | 60 | HIGH |
| Blessing of Wisdom [25290](https://www.wowhead.com/forever/spell=25290) | Greater Blessing of Wisdom | [25894](https://www.wowhead.com/forever/spell=25894) (54), [25918](https://www.wowhead.com/forever/spell=25918) (60) | 60 | HIGH |
| Blessing of Salvation 1038 | Greater Blessing of Salvation | **none on Forever**: 25895 is a 404 on `/forever/`; no Salvation spell in Warcraft DB Forever search (only a `(DNT) … TEST RAID SPELL` 1286251) | — | HIGH it is absent |
| Blessing of Light 19979 | Greater Blessing of Light | **none on Forever**: 25890 is a 404 | — | HIGH it is absent |
| (Blessing of Sanctuary, removed 57.5) | Greater Blessing of Sanctuary | 25899 is a 404, consistent with the 57.5 removal | — | HIGH |

Not requested but checked: Prayer of Shadow Protection [27683](https://www.wowhead.com/forever/spell=27683)
(20 min) only matters if a Shadow Protection row is added; section 6 recommends against that row.
Forever's DB also has a party-only "Prayer of Fortitude" [450086](https://www.wowhead.com/forever/spell=450086)
(SoD-era ID, not on the priest list): **do not** list it.

**Blessings semantics.** One group call keeps the existing meaning: a paladin holds one own
blessing per target, so any blessing present satisfies every blessing reminder. Adding the
Greater Blessings to that call means any Greater Blessing satisfies them too. A finer per-type
wiring (Kings only with Greater Kings, and so on) can't be expressed as data: a second
`MetaReminderGroup` call overwrites the first (§2.4), and the scope constraint rules out changing
the function. So the one-group wiring is the only one in scope (Q2). (1038 and 19979 stay in the
call only for as long as their rows stay; see §7.)

---

## 5. Recommended new Forever rows

Durations in minutes (0 = permanent until cancelled: no timer, shown once the aura is gone).
Every row is client `forever` (the default). Every row uses only existing `MetaReminderRow`
arguments, except the familiar row's new `useItems` opt (§11).

| # | Class | Spell | Row ID | All Forever rank IDs | Min | Aura = spell? | Exclusive group | Confidence | Recommendation |
|---|-------|-------|--------|----------------------|-----|---------------|-----------------|------------|----------------|
| 1 | Mage | Ice Armor | [10220](https://www.wowhead.com/forever/spell=10220) | 7302, 7320, 10219, 10220 | 30 | likely | Mage armors | HIGH | **Include** (priority) |
| 2 | Mage | Mage Armor | [22783](https://www.wowhead.com/forever/spell=22783) | 6117, 22782, 22783 | 30 | likely | Mage armors | HIGH | **Include** (priority) |
| 3 | Warlock | Demon Armor | [11735](https://www.wowhead.com/forever/spell=11735) | [706](https://www.wowhead.com/forever/spell=706) (20), [1086](https://www.wowhead.com/forever/spell=1086) (30), [11733](https://www.wowhead.com/forever/spell=11733) (40), [11734](https://www.wowhead.com/forever/spell=11734) (50), [11735](https://www.wowhead.com/forever/spell=11735) (60) | 30 | likely | Warlock armors | HIGH (IDs); MEDIUM (exclusivity: the Forever tooltip does not state it, and Demon Armor is the vanilla successor of Demon Skin, which can't be up at the same time) | **Include** |
| 4 | Warlock | Demon Skin | [696](https://www.wowhead.com/forever/spell=696) | [687](https://www.wowhead.com/forever/spell=687) (1), [696](https://www.wowhead.com/forever/spell=696) (10) | 30 | likely | Warlock armors | HIGH / MEDIUM as above | **Include** (levels 1–19 have only this; a level-20+ warlock still sees the tile, as the mage sees Frost Armor) |
| 5 | Shaman | Lightning Shield | [10432](https://www.wowhead.com/forever/spell=10432) | [324](https://www.wowhead.com/forever/spell=324) (8), [325](https://www.wowhead.com/forever/spell=325) (16), [905](https://www.wowhead.com/forever/spell=905) (24), [945](https://www.wowhead.com/forever/spell=945) (32), [8134](https://www.wowhead.com/forever/spell=8134) (40), [10431](https://www.wowhead.com/forever/spell=10431) (48), [10432](https://www.wowhead.com/forever/spell=10432) (56) | 10 | likely | Shaman shields | HIGH | **Include** (3 charges: it also drops when spent, and the reminder rightly shows) |
| 6 | Shaman | Water Shield | [408510](https://www.wowhead.com/forever/spell=408510) | 408510 only (Restoration talent, 1 rank) | 10 | likely | Shaman shields | MEDIUM: the ID was a SoD rune; the Forever tooltip labels it "Talent", says "Only one Elemental Shield can be active", and the Forever shaman list shows Water Shield as a 1-rank Restoration talent. Confirm the talent teaches 408510 with the ID tooltip | **Include** |
| 7 | Priest | Inner Fire | [10952](https://www.wowhead.com/forever/spell=10952) | [588](https://www.wowhead.com/forever/spell=588) (12), [7128](https://www.wowhead.com/forever/spell=7128) (20), [602](https://www.wowhead.com/forever/spell=602) (30), [1006](https://www.wowhead.com/forever/spell=1006) (40), [10951](https://www.wowhead.com/forever/spell=10951) (50), [10952](https://www.wowhead.com/forever/spell=10952) (60) | 10 | likely | none (stands alone) | HIGH | **Include** (20 charges, same "drops early" note as Lightning Shield) |
| 8 | Priest | Shadowform | [15473](https://www.wowhead.com/forever/spell=15473) | 15473 only (Shadow talent) | 0 | likely (buff on ID) | none | HIGH (ID) / MEDIUM (aura shows as a normal buff; confirm in game) | **Include**: lost on death and when the priest drops it to heal; offered only to priests with the talent |
| 9 | Paladin | Any aura (named Devotion Aura) | [10293](https://www.wowhead.com/forever/spell=10293) | Devotion: [465](https://www.wowhead.com/forever/spell=465) (1), [10290](https://www.wowhead.com/forever/spell=10290) (10), [643](https://www.wowhead.com/forever/spell=643) (20), [10291](https://www.wowhead.com/forever/spell=10291) (30), [1032](https://www.wowhead.com/forever/spell=1032) (40), [10292](https://www.wowhead.com/forever/spell=10292) (50), [10293](https://www.wowhead.com/forever/spell=10293) (60) | 0 | likely | one row + one-way alternatives: Retribution [10301](https://www.wowhead.com/forever/spell=10301), Concentration [19746](https://www.wowhead.com/forever/spell=19746), Shadow Res. [19896](https://www.wowhead.com/forever/spell=19896), Frost Res. [19898](https://www.wowhead.com/forever/spell=19898), Fire Res. [19900](https://www.wowhead.com/forever/spell=19900) (all ranks in §12) | HIGH. Every aura tooltip says *"Players may only have one Aura on them per Paladin at any one time."* | **Include**: auras are permanent, drop on death, and a paladin with none up is always a mistake. Mirrors the retail Devotion row. Use **10293** as the row ID, never 465 (the retail row's key) |
| 10 | Hunter | Any aspect (named Aspect of the Hawk) | [25296](https://www.wowhead.com/forever/spell=25296) | Hawk: [13165](https://www.wowhead.com/forever/spell=13165) (10), [14318](https://www.wowhead.com/forever/spell=14318) (18), [14319](https://www.wowhead.com/forever/spell=14319) (28), [14320](https://www.wowhead.com/forever/spell=14320) (38), [14321](https://www.wowhead.com/forever/spell=14321) (48), [14322](https://www.wowhead.com/forever/spell=14322) (58), [25296](https://www.wowhead.com/forever/spell=25296) (60) | 0 | likely | one row + one-way alternatives: Monkey [13163](https://www.wowhead.com/forever/spell=13163), Cheetah [5118](https://www.wowhead.com/forever/spell=5118), Pack [13159](https://www.wowhead.com/forever/spell=13159), Wild [20043](https://www.wowhead.com/forever/spell=20043)/[20190](https://www.wowhead.com/forever/spell=20190), Beast [13161](https://www.wowhead.com/forever/spell=13161) (Forever added Beast ranks [1299445](https://www.wowhead.com/forever/spell=1299445)/[1299446](https://www.wowhead.com/forever/spell=1299446)/[1299447](https://www.wowhead.com/forever/spell=1299447), lvl 40/50/60, covered by the name family) | HIGH. Every aspect tooltip says *"Only one Aspect can be active at a time."* | **Include**, MEDIUM value: shows only when *no* aspect is up (after death, or forgetting after Cheetah). Pack/Wild from another hunter also satisfy it, which is acceptable. Do **not** list Viper (34074) or Falcon (469145): they are in the data but not on the Forever hunter list |
| 11 | Warlock | Demonic Sacrifice (any of its four buffs) | [18788](https://www.wowhead.com/forever/spell=18788) with `auraID = 18789` (existing opt) | talent, 1 rank; buffs [18789](https://www.wowhead.com/forever/spell=18789) Burning Shadow, [18790](https://www.wowhead.com/forever/spell=18790) Fel Stamina, [18791](https://www.wowhead.com/forever/spell=18791) Touch of Fire, [18792](https://www.wowhead.com/forever/spell=18792) Fel Energy | **120** | **differs** (cast 18788 has no buff; the auras are 18789–18792) | one row + one-way alternatives 18790, 18791, 18792 | HIGH (IDs, the 2-hour Forever duration, "canceled if any Demon is summoned"); MEDIUM (row shape) | **Include, second priority**: a 2-hour buff a sacrifice warlock keeps up all session. The shape is the Arcane Familiar / Symbiotic Relationship `auraID` pattern. Click casts 18788 (it sacrifices the demon that is out, which is what the player wants) |
| 12 | Priest | Shadowguard (Troll only) | [19312](https://www.wowhead.com/forever/spell=19312) | [18137](https://www.wowhead.com/forever/spell=18137) (20), [19308](https://www.wowhead.com/forever/spell=19308) (28), [19309](https://www.wowhead.com/forever/spell=19309) (36), [19310](https://www.wowhead.com/forever/spell=19310) (44), [19311](https://www.wowhead.com/forever/spell=19311) (52), [19312](https://www.wowhead.com/forever/spell=19312) (60) | 10 | likely | none | HIGH (IDs, 10 min, 3 charges; a Troll quest reward on Forever) | **Optional**: worthwhile but narrow (troll priests only; the knownID rule keeps it off everyone else). User call (Q7) |
| 13 | Mage | Familiar scroll (§11) | [1302303](https://www.wowhead.com/forever/spell=1302303) | tiers 1302303 / 1302285 / 1296202 (item uses, not ranks) | 60 | likely | one row + one-way alternatives | HIGH (IDs); see §11 | **Include** (the one row with new code: the item click, §11.3) |

Sketch of the rows (for the planner; not applied):

```lua
MetaReminderRow(10220, 30) -- Mage: Ice Armor (unverified in game)
MetaReminderRow(22783, 30) -- Mage: Mage Armor (unverified in game)
MetaReminderRow(11735, 30) -- Warlock: Demon Armor (unverified in game)
MetaReminderRow(696, 30) -- Warlock: Demon Skin (unverified in game)
MetaReminderRow(10432, 10) -- Shaman: Lightning Shield (unverified in game)
MetaReminderRow(408510, 10) -- Shaman: Water Shield (Restoration talent; unverified in game)
MetaReminderRow(10952, 10) -- Priest: Inner Fire (unverified in game)
MetaReminderRow(15473, 0) -- Priest: Shadowform (Shadow talent; permanent; unverified in game)
MetaReminderRow(10293, 0) -- Paladin: Devotion Aura, any aura satisfies (unverified in game)
MetaReminderRow(25296, 0) -- Hunter: Aspect of the Hawk, any aspect satisfies (unverified in game)
MetaReminderRow(18788, 120, nil, nil, nil, { auraID = 18789 }) -- Warlock: Demonic Sacrifice (unverified in game)
MetaReminderRow(1302303, 60, 1296017, nil, false, { useItems = { 277493, 277483, 275069 } }) -- Mage: Familiar scroll (§11; the one new opt)
```

The group calls for these rows are in §12.3.

Sanctity Aura [20218](https://www.wowhead.com/forever/spell=20218) is in Forever's data with the
one-aura-per-paladin text but is not on the Forever paladin ability list. Adding it to the aura
group is harmless (no one has it, so it never matches) but unproven. Leave it out unless a Forever
paladin sees it (Q5).

---

## 6. Every candidate considered: include / exclude

| Class | Candidate | Forever evidence | Verdict | One-line reason |
|-------|-----------|------------------|---------|-----------------|
| Mage | Frost / Ice / Mage Armor | §3 | **Include** (group) | 30-min self buff, game-enforced one-armor rule |
| Mage | Familiar scrolls | §11 | **Include** | 1-hour Int buff from a bag item; click uses the best scroll in the bags |
| Mage | Molten Armor | only SoD rune 428741 in data; not learnable | **Exclude** | Not on the Forever mage list |
| Mage | Amplify Magic ([1008](https://www.wowhead.com/forever/spell=1008), [8455](https://www.wowhead.com/forever/spell=8455), [10169](https://www.wowhead.com/forever/spell=10169), [10170](https://www.wowhead.com/forever/spell=10170)) / Dampen Magic ([604](https://www.wowhead.com/forever/spell=604), [8450](https://www.wowhead.com/forever/spell=8450), [8451](https://www.wowhead.com/forever/spell=8451), [10173](https://www.wowhead.com/forever/spell=10173), [10174](https://www.wowhead.com/forever/spell=10174)) | 10 min each, party-member target | **Exclude** | A per-encounter choice, often deliberately absent. If the user wants them: two rows grouped (do not stack, per vanilla; the Forever text does not say so, LOW), with all ranks listed (§12) |
| Mage | Mana Shield, Fire/Frost Ward, Ice Barrier | 1 min / 30 s / 1 min on Forever | **Exclude** | Short combat cooldowns, not maintained buffs |
| Mage | Arcane Brilliance as its own row | 23028, 1 h | **Exclude as a row**, use as an alternative | Not requested. One-way alternative on 1459 covers the user decision |
| Warlock | Demon Skin / Demon Armor | §5 | **Include** (group) | 30-min self armor |
| Warlock | Fel Armor | only SoD 403619 in data; not on Forever warlock list | **Exclude** | Not learnable |
| Warlock | Soul Link ([19028](https://www.wowhead.com/forever/spell=19028), aura [25228](https://www.wowhead.com/forever/spell=25228)) | talent; "Lasts as long as the Demon is active" | **Exclude** | Meaningless without a demon out, and TBT has no "pet present" load condition (adding one would be new behaviour, out of scope). It would show while demonless |
| Warlock | Demonic Sacrifice buffs | §5 row 11; 2 h on Forever | **Include (second priority)** | Long buff; one row, four auras |
| Warlock | Detect Invisibility ([132](https://www.wowhead.com/forever/spell=132), [2970](https://www.wowhead.com/forever/spell=2970), [11743](https://www.wowhead.com/forever/spell=11743)), Unending Breath ([5697](https://www.wowhead.com/forever/spell=5697)) | 10 min | **Exclude** | Situational utility (rank list in §12 if ever added) |
| Warlock | Shadow Ward | short absorb | **Exclude** | Combat cooldown |
| Shaman | Lightning Shield / Water Shield | §5 | **Include** (group) | 10-min self shield, "Only one Elemental Shield" |
| Shaman | Weapon imbues: Rockbiter ([8017](https://www.wowhead.com/forever/spell=8017)…[16316](https://www.wowhead.com/forever/spell=16316)), Flametongue ([8024](https://www.wowhead.com/forever/spell=8024)…[16342](https://www.wowhead.com/forever/spell=16342)), Frostbrand ([8033](https://www.wowhead.com/forever/spell=8033)…[16356](https://www.wowhead.com/forever/spell=16356)), Windfury Weapon ([8232](https://www.wowhead.com/forever/spell=8232)…[16362](https://www.wowhead.com/forever/spell=16362)) | Forever: "Imbue the Shaman's weapon… Lasts for 60 minutes"; **empty buff block** | **Exclude** | A weapon enchant, not an aura. TBT's reminder watches auras. (Now 60 min on Forever; a weapon-enchant reminder would be new behaviour, so a backlog item at most) |
| Shaman | Totems (Strength of Earth, Windfury, etc.) | — | **Exclude** (unchanged decision 2026-09-29) | Aura IDs differ from casts; totem buffs are positional |
| Shaman | Earth Shield | not on the Forever shaman list | **Exclude** | Not on Forever |
| Rogue | Poisons (e.g. Instant Poison VI [11340](https://www.wowhead.com/forever/spell=11340), Crippling [11202](https://www.wowhead.com/forever/spell=11202)) | "Coats a weapon with poison that lasts for 30 minutes"; empty buff block | **Exclude** | Weapon enchant from an item, not an aura |
| Priest | Inner Fire | §5 | **Include** | 10-min self buff |
| Priest | Shadowform | §5 | **Include** | Permanent form-buff, lost on death |
| Priest | Shadow Protection ([976](https://www.wowhead.com/forever/spell=976), [10957](https://www.wowhead.com/forever/spell=10957), [10958](https://www.wowhead.com/forever/spell=10958); Prayer [27683](https://www.wowhead.com/forever/spell=27683) 20 min) | 10 min | **Exclude** | Situational (shadow encounters only); a constant reminder would nag (rank list in §12 if ever added) |
| Priest | Fear Ward ([6346](https://www.wowhead.com/forever/spell=6346)) | **3 min** on Forever, 3-min cooldown | **Exclude** | Short, and a targeted cooldown |
| Priest | Shadowguard (Troll) | §5 row 12 | **Optional** | 10 min, narrow audience |
| Priest | Touch of Weakness (Undead; [2652](https://www.wowhead.com/forever/spell=2652)…[19266](https://www.wowhead.com/forever/spell=19266)) | 2 min | **Exclude** | Too short |
| Priest | Elune's Grace, Feedback | 15 s, cooldowns | **Exclude** | Combat cooldowns |
| Druid | Mark of the Wild / Thorns | existing rows | (existing) | — |
| Druid | Omen of Clarity ([16864](https://www.wowhead.com/forever/spell=16864)) | Forever: **passive**, trainer at 20, no buff block | **Exclude** | No longer a 10-min self buff on Forever: nothing to remind |
| Druid | Forms (Bear/Dire Bear, Cat, Travel, Aquatic, Moonkin) | — | **Exclude** | Situational stance-like toggles; a druid drops form constantly to heal or travel |
| Druid | Barkskin, Nature's Grasp | short | **Exclude** | Combat cooldowns |
| Warrior | Battle Shout | existing row, Forever says 3 min | (existing) | — |
| Warrior | Stances ([2457](https://www.wowhead.com/forever/spell=2457), [71](https://www.wowhead.com/forever/spell=71), [2458](https://www.wowhead.com/forever/spell=2458)) | permanent | **Exclude** | A warrior is always in exactly one stance, so it is never missing |
| Hunter | Any aspect | §5 row 10 | **Include** | Reminder only when no aspect is up |
| Hunter | Trueshot Aura | existing row; Forever 30 min, MM talent | (existing) | — |
| Paladin | Any aura | §5 row 9 | **Include** | Permanent, lost on death |
| Paladin | Seals (Righteousness [21084](https://www.wowhead.com/forever/spell=21084), Fury [1311649](https://www.wowhead.com/forever/spell=1311649), …) | still **30 s** on Forever (Judgement no longer consumes them, but the duration is unchanged) | **Exclude** | Short combat buff |
| Paladin | Righteous Fury | existing row, 30 min | (existing) | — |

---

## 7. Existing Forever rows: links and flags

All checked against `/forever/` data; durations match the row unless flagged.

| Class | Spell | Row ID | Forever link | Forever duration | Status |
|-------|-------|--------|--------------|------------------|--------|
| Mage | Arcane Intellect | 1459 | [1459](https://www.wowhead.com/forever/spell=1459) (ranks [1460](https://www.wowhead.com/forever/spell=1460), [1461](https://www.wowhead.com/forever/spell=1461), [10156](https://www.wowhead.com/forever/spell=10156), [10157](https://www.wowhead.com/forever/spell=10157)) | 60 | OK; note the row names **rank 1**, so received ranks above what the mage knows are missed today (closed by data in §12) |
| Mage | Frost Armor | 7301 | [7301](https://www.wowhead.com/forever/spell=7301) | 30 | OK |
| Priest | Power Word: Fortitude | 10938 | [10938](https://www.wowhead.com/forever/spell=10938) (ranks 1243, 1244, 1245, 2791, 10937) | 60 | OK |
| Priest | Divine Spirit | 27841 | [27841](https://www.wowhead.com/forever/spell=27841) (ranks 14752, 14818, 14819) | 60 | OK |
| Druid | Mark of the Wild | 9885 | [9885](https://www.wowhead.com/forever/spell=9885) (ranks 1126, 5232, 6756, 5234, 8907, 9884) | 60 | OK |
| Druid | Thorns | 9910 | [9910](https://www.wowhead.com/forever/spell=9910) (ranks 467, 782, 1075, 8914, 9756) | 10 | OK |
| Warrior | Battle Shout | 25289 | [25289](https://www.wowhead.com/forever/spell=25289) (ranks 6673, 5242, 6192, 11549, 11550, 11551) | 3 | OK |
| Hunter | Trueshot Aura | 20906 | [20906](https://www.wowhead.com/forever/spell=20906) (ranks 19506, 20905) | 30 | OK |
| Warlock | Blood Pact | 11767 (known via Summon Imp 688) | [11767](https://www.wowhead.com/forever/spell=11767) (ranks [6307](https://www.wowhead.com/forever/spell=6307), [7804](https://www.wowhead.com/forever/spell=7804), [7805](https://www.wowhead.com/forever/spell=7805), [11766](https://www.wowhead.com/forever/spell=11766)), [688](https://www.wowhead.com/forever/spell=688) | permanent | OK |
| Paladin | Blessing of Kings | 20217 | [20217](https://www.wowhead.com/forever/spell=20217) | 60 | OK (baseline at 20 on Forever) |
| Paladin | Blessing of Might | 25291 | [25291](https://www.wowhead.com/forever/spell=25291) (ranks 19740, 19834–19838) | 60 | OK |
| Paladin | Blessing of Wisdom | 25290 | [25290](https://www.wowhead.com/forever/spell=25290) (ranks 19742, 19850, 19852, 19853, 19854) | 60 | OK |
| Paladin | **Blessing of Salvation** | **1038** | [1038](https://www.wowhead.com/forever/spell=1038): **HTTP 404 on Forever** | — | **FLAG: evidence it does not exist on Forever** |
| Paladin | **Blessing of Light** | **19979** | [19979](https://www.wowhead.com/forever/spell=19979): **HTTP 404 on Forever** (also 19977, 19978) | — | **FLAG: evidence it does not exist on Forever** |
| Paladin | Righteous Fury | 25780 | [25780](https://www.wowhead.com/forever/spell=25780) | 30 | OK; buff on the same ID, so aura = spell is likely |

**Hard evidence on 1038 and 19979:** (a) Wowhead's Forever database returns 404 for 1038, 19977,
19978, 19979 and both Greater versions (25895, 25890), (b) Warcraft DB's Forever edition returns
"Not Found" for 1038 and its search has no Salvation or Light blessing a player can learn, and
(c) warcraft.wiki.gg's Paladin abilities (Forever) lists Might, Wisdom, Protection, Freedom,
Kings and Sacrifice but no Salvation and no Light. This is the same situation as Blessing of
Sanctuary, already removed in 57.5. A Blizzard beta patch note quoted by third parties said
Salvation "is no longer a Blessing", but no replacement spell is in the Forever data. **Do not
change the rows in this research**: the rows are harmless (never offered, since no paladin knows
them), but the user should decide whether to remove them as Sanctuary was (Q1). Removing a row is
a table edit with existing orphan handling (WR-02), so it is in scope.

(Note on the comment at Providers.lua 1069–1070: on Forever, 6673 is Battle Shout rank 1, 465 is
Devotion Aura rank 1 and 21562 is Prayer of Fortitude rank 1. The comment's warning still holds,
and it is exactly why §2.5's Forever block is needed.)

---

## 8. Retail rows already shipping (links only, no new research)

| Class | Spell | Row ID | Retail link | Notes |
|-------|-------|--------|-------------|-------|
| Mage | Arcane Intellect (both clients) | 1459 | [1459](https://www.wowhead.com/spell=1459) | |
| Mage | Arcane Familiar | 210126 | [210126](https://www.wowhead.com/spell=210126) | known via talent [205022](https://www.wowhead.com/spell=205022); click casts 1459 |
| Priest | Power Word: Fortitude | 21562 | [21562](https://www.wowhead.com/spell=21562) | |
| Druid | Mark of the Wild | 1126 | [1126](https://www.wowhead.com/spell=1126) | |
| Druid | Symbiotic Relationship | 474750 | [474750](https://www.wowhead.com/spell=474750) | aura [474754](https://www.wowhead.com/spell=474754) |
| Warrior | Battle Shout | 6673 | [6673](https://www.wowhead.com/spell=6673) | |
| Shaman | Skyfury | 462854 | [462854](https://www.wowhead.com/spell=462854) | |
| Shaman | Lightning Shield | 192106 | [192106](https://www.wowhead.com/spell=192106) | |
| Evoker | Blessing of the Bronze | 364342 | [364342](https://www.wowhead.com/spell=364342) | aura [381748](https://www.wowhead.com/spell=381748) |
| Evoker | Source of Magic | 369459 | [369459](https://www.wowhead.com/spell=369459) | |
| Paladin | Devotion Aura | 465 | [465](https://www.wowhead.com/spell=465) | alternatives Concentration Aura [317920](https://www.wowhead.com/spell=317920), Crusader Aura [32223](https://www.wowhead.com/spell=32223) |

---

## 9. Pitfalls for the phase planner

1. **Ungated Forever groups would change retail rows** (§2.5): 21562, 1459, 1126, 6673, 465. This
   is the highest-risk item in the milestone. Put every Forever group call inside the
   `if ns.CLIENT_IS_FOREVER then` block, and check it in review. The check costs no code: the
   block itself is the guard.
2. **Second `MetaReminderGroup` call overwrites the first** (§2.4): each row's ranks, group buffs
   and exclusive partners must all be in one call (§12.3).
3. **Received ranks must be listed explicitly** (§2.3, §12): the name family covers only ranks the
   player knows.
4. **Don't use SoD/NPC IDs that sit in Forever's data** (428741, 403619, 34074, 469145, 450086,
   1283419, 1213334, 1233344). Each passes a bare "exists on `/forever/`" check.
5. **Demonic Sacrifice is the only new spell row with `auraID`.** Its cast 18788 carries no buff,
   and the four buffs are four IDs. Verify the cast index starts the row from 18788 (a
   `UNIT_SPELLCAST_SUCCEEDED` of 18788) and that UNIT_AURA sees 18789–18792.
6. **Charge-based buffs** (Lightning Shield, Water Shield, Inner Fire, Shadowguard) disappear
   before their timer. Existing aura-loss handling ends the timer; the user should see the
   reminder return after the charges are spent, which is correct.
7. **Permanent rows (0 min)** have no lead window, the same as retail Devotion Aura.
8. **The familiar row is the only new code** (the item click, §11.3); everything else in v0.5.6 is
   table data.

---

## 10. Open questions for the user

- **Q1.** Blessing of Salvation (1038) and Blessing of Light (19979) look removed from Forever
  (404 in two Forever databases, absent from the Forever paladin list). Remove both rows, as
  Blessing of Sanctuary was in 57.5? (Saved entries become orphans per WR-02, no data lost.)
- **Q2.** Greater Blessings join the existing all-blessings group, so any blessing or Greater
  Blessing satisfies every blessing reminder. This is the only wiring expressible as data
  (§4). Confirm.
- **Q3.** *(Resolved by the scope constraint.)* Forever-only groups go in an
  `if ns.CLIENT_IS_FOREVER then` block, with no change to `MetaReminderGroup`.
- **Q4.** Hunter: include the "any aspect" row (named Aspect of the Hawk)? It only shows when no
  aspect is up.
- **Q5.** Paladin: include the "any aura" row (named Devotion Aura 10293), and should Sanctity
  Aura 20218 be listed as an alternative even though the Forever ability list doesn't show it?
- **Q6.** Warlock: include Demonic Sacrifice (2-hour buff, `auraID` row)? Soul Link stays out
  (it would need new load behaviour).
- **Q7.** Priest: include Shadowguard (Troll-only, 10 min)?
- **Q8.** Confirm the exclusions most likely to be wanted anyway: Amplify/Dampen Magic, Shadow
  Protection, Detect Invisibility.
- **Q9.** Shaman weapon imbues now last 60 min on Forever. They are weapon enchants, not auras,
  and a reminder for them would be new behaviour. Backlog item, or drop?
- **Q10.** In-game checks for the user's mage pass: the ID tooltip on Ice Armor and Mage Armor
  buffs should read 7302/7320/10219/10220 and 6117/22782/22783 (aura = spell). With Ice Armor up,
  a placed Frost Armor reminder should hide, and the reverse.
- Q11–Q14 (familiars) are in §11.4, Q15–Q16 (rank coverage) in §12.5.

---

## 11. Mage familiar scrolls (follow-up, 2026-11-09)

User request: "add / research the mage scroll familiar buffs, they should use the item from the
bag, the highest one present in bag", and then "these ids need to group the different ranks".

### 11.1 What they are on Forever

These are Forever-only mage consumables from the scroll system. A mage deciphers scrolls with
**Comprehend Scroll** ([1296017](https://www.wowhead.com/forever/spell=1296017), "Requires Mage,
Requires level 6", General tab). A search of Forever's data for "Familiar" (Warcraft DB Forever
search API) finds exactly **three** scroll items and their three spells. Searches for each
familiar name return exactly one spell each, so **each tier has exactly one aura ID** (no
alternate aura IDs to add). The NPCs Rat/Cat/Frog Familiar (266025, 272012, 268744) are the
summoned pets. "Arcane Familiar" (NPC 275356, a level-26 Kirin Tor humanoid) has no item or spell
and is not a fourth tier. A scan of the neighbouring item IDs (275060–275075 and 277480–277510,
the whole mage-scroll block) found no other familiar tier.

All data below was read from Forever's tooltip endpoints
(`nether.wowhead.com/forever/tooltip/item/<id>` and `/spell/<id>`). Each item's tooltip links to
its use spell, which confirms the item→spell mapping.

| Tier (high→low) | Item | Item level / required level | Class | Use spell (cast) | Aura on the player (the only aura ID for this tier) | Effect | Duration | Stack | Confidence |
|------|------|------|------|------|------|------|------|------|------|
| 1 (highest) | Scroll of Cat Familiar [277493](https://www.wowhead.com/forever/item=277493) | 40 / **25** | Mage | Cat Familiar [1302303](https://www.wowhead.com/forever/spell=1302303) (3 s cast, 1.5 s cd) | **1302303** (likely: the buff block sits on the same ID, "Your familiar increases your Intellect by 12") | +12 Int | 60 min | 5, not bound | HIGH (IDs, level, duration); MEDIUM (aura = spell) |
| 2 | Scroll of Frog Familiar [277483](https://www.wowhead.com/forever/item=277483) | 25 / **16** | Mage | Frog Familiar [1302285](https://www.wowhead.com/forever/spell=1302285) | **1302285** (likely) | +6 Int | 60 min | 5, not bound | as above |
| 3 (lowest) | Scroll of Rat Familiar [275069](https://www.wowhead.com/forever/item=275069) | 15 / **5** | Mage | Rat Familiar [1296202](https://www.wowhead.com/forever/spell=1296202) | **1296202** (likely) | +2 Int | 60 min | 5, not bound | as above |

- **Tier order** is by required level and Intellect: Cat > Frog > Rat. The tier order does not
  follow the item IDs (Frog 277483 < Cat 277493, and Rat 275069 is lowest), so the row data must
  hold an explicit ordered list, never sort by ID.
- **Mutual exclusion between tiers: UNVERIFIED-FOR-FOREVER.** No Forever tooltip says "only one
  familiar". Each tier summons "a faithful … familiar", which suggests one pet at a time (a new
  summon replacing the old), but whether the Rat aura is removed when the Cat is used is
  unconfirmed. **The wiring below is correct either way:** any tier present satisfies the reminder.
- **Overlap with planned rows:** these are separate auras with separate IDs. Nothing in the data
  says they exclude Arcane Intellect, Arcane Brilliance or the armors, so they are assumed to
  stack (+Int alongside AI) — UNVERIFIED-FOR-FOREVER, but it does not affect the wiring. **Do not
  group them with Arcane Intellect or the armor group.** They are their own reminder. Also not
  related to the **retail** Arcane Familiar row (210126, retail-only).
- Not soulbound: a mage can be traded or buy scrolls, so bag contents can change without the mage
  deciphering anything.

### 11.2 Data side: the tiers group, and the row is offered and loaded, with existing code

```lua
-- Forever. Keyed on the top tier's aura; any tier present or used satisfies it. Offered to every
-- mage who knows Comprehend Scroll (the scroll system), because no familiar is a known spell.
MetaReminderRow(1302303, 60, 1296017, nil, false, { useItems = { 277493, 277483, 275069 } }) -- Mage: Familiar scroll (Cat > Frog > Rat; unverified in game)
-- inside the Forever block; one-way: 1302285/1296202 have no row
MetaReminderGroup(1302303, 1302285, 1296202)
```

Everything here except `useItems` is existing behaviour, used as data:

- **Grouping the tiers works with the current code; no new aura machinery is needed.**
  - The row's own family is `ns:ResolveRankFamily(1302303)` = {1302303}. The name "Cat Familiar"
    matches nothing in the spellbook, which is harmless.
  - Each alternative's `ns:CastRuleFamily` is likewise just itself.
  - `ns:RebuildReminderWatch` builds {1302303, 1302285, 1296202}, and `ns:RefreshAuraStates`
    reads each with `C_UnitAuras.GetPlayerAuraBySpellID`. An item-granted aura is an ordinary
    player aura to that API, the same path the Phase 76 bag-item buffs already use.
  - The tiers are not ranks of one name, so the rank family can't join them; the explicit group
    does.
- **The cast path is unchanged.** Using a scroll fires `UNIT_SPELLCAST_SUCCEEDED` with the
  use-spell ID. TBT already relies on this for bag items (Providers.lua 1333–1339,
  `itemUseSpellToID`, Phase 47 D-01).
  - A Cat use resolves the row directly (`ns.metaReminderKeyBySpell`).
  - A Frog or Rat use starts it through `ns.alternativeKeysBySpell` (Providers.lua 431–447).
  - Timer: 60 min from `GetTime()`.
- **Offered and loaded without a known familiar spell, using the existing `knownID` argument:**
  `knownID = 1296017` (Comprehend Scroll). The load rule and the Suggested offer both call
  `ns:ResolveSpellKnown(def.knownID)` (Core.lua 1343–1347, Providers.lua 1318). This is exactly
  how Blood Pact loads via Summon Imp 688 and Arcane Familiar via its talent, so no new load
  code is needed.
  - Keying `knownID` on the row's own spell would mean the row is **never offered and never
    loaded**, because a familiar spell is never "known".
  - Comprehend Scroll is the right proxy: mage-only, level 6+, in the spellbook. Arcane Intellect
    1459 would also work, but it offers the row to level 1–5 mages who can't use any scroll.
  - The other Comprehend Scroll IDs in the data (1309965, 1309973, 1310029, 1310030) have no class
    line and a 5 s cast; they look like the per-scroll decipher effects. 1296017 is the spellbook
    one — confirm with the ID tooltip.
- **`castID = false`** (existing: Blood Pact uses it) so the spell click path never tries to cast
  anything. The new `useItems` opt drives the click instead.
- **Aura key = 1302303** (top tier, same convention as the top-rank rows).

### 11.3 The one code addition: an item click on the highest tier in the bags

Current state (`ReminderClick.lua`):
- Every overlay is created with `type1 = "spell"` (line 71). `Place` writes only the `spell`
  attribute (by name) and `unit`.
- `Flush` (out of combat only) gets `ns:ReminderCastID(entry)`, drops it unless
  `ns:ResolveSpellKnown(castID)` is true (WR-05), resolves the name, and places an overlay.
- A row with `castID = false` gets no overlay. There is no item path.

Smallest addition (every other reminder keeps the exact current behaviour):

1. **Row data.** `MetaReminderRow` copies `opts.useItems` into the def: an ordered list,
   highest tier first. The required levels (25/16/5) can sit next to the IDs, e.g.
   `{ {277493, 25}, {277483, 16}, {275069, 5} }`. Add a one-line accessor
   `ns:ReminderUseItems(entry)` beside `ns:ReminderCastID`; it is a map read with no allocation.
2. **Choose the item, in `Flush` only.** This runs out of combat already and is already deferred
   to `PLAYER_REGEN_ENABLED`. Only for an entry whose def has `useItems`: walk the list and take
   the first item with `C_Item.GetItemCount(itemID) > 0` **and**
   `UnitLevel("player") >= minLevel`.
   - The level check matters: a level-20 mage holding a traded Cat scroll can't use it, so it must
     fall through to Frog.
   - This is the existing pot-provider scan reused as a pattern
     (`MetaItemPotProviderMixin:RefreshAtRest`, Providers.lua 845–859: "first count > 0 wins",
     combat-gated).
   - Guard the reads against secret values and a missing API, as the pot scan does.
3. **Place the item overlay.** `Place` gains the action type: for the familiar,
   `type1 = "item"` and `item = "item:<id>"`; for every other reminder, exactly today's
   `type1 = "spell"` and `spell = <name>`. Each attribute is still written only on change.
   - The `item:<id>` form uses the item wherever it sits in the bags, so no bag/slot is needed,
     and it needs no cached name, so the WR-03 retry is never triggered by it.
   - Because a pooled overlay can be reused across reminders, `type1` is written in `Place` (on
     change), not only in `CreateOverlay`, and the other action attribute is cleared.
   - `unit = "player"` (the existing self default).
   - The `[combat] hide; show` state driver and all combat deferral are unchanged.
4. **Re-pick when the bags change.** Add one `ns:MarkReminderClicksDirty()` call to Core.lua's
   existing `BAG_UPDATE_DELAYED` branch (2182–2196). It coalesces to one flush per frame and
   defers in combat, as it already does for every other caller. Using the last scroll of a tier
   then falls through to the next tier on the next flush.
   - A level-up that makes a new tier usable is picked up at the next bag change, zone or reload.
     A `PLAYER_LEVEL_UP` hook is optional and not needed for the minimal version.
5. **None in the bags (or none usable).** No overlay is placed: the icon still shows, because the
   buff is missing, but a click does nothing. That is the same outcome as today's WR-05 "cast spell
   not known" case, so nothing new is introduced for it.

**Existing bag plumbing, what is reused:**
- Reused directly:
  - the `BAG_UPDATE_DELAYED` registration and its out-of-combat branch;
  - the ordered "first count > 0" scan pattern from the pot provider;
  - item use-spell detection through `UNIT_SPELLCAST_SUCCEEDED` (Phase 47);
  - the whole reminder overlay pool and its combat deferral;
  - the `knownID` load proxy and `castID = false`.
- **Not reused as a kind:** the Phase 76 bag items (`metaItem:<itemID>`, Core.lua 589–596; count
  store and `ns:ReconcileTrackedItemCounts`, Providers.lua 1370–1660). They are cooldown/buff
  trackers keyed on one item, loaded ALWAYS, with no reminder semantics, no click path and no
  "highest of several". The familiar stays a metaReminder.

### 11.4 Open questions (familiars)

- **Q11.** With no usable scroll in the bags, the reminder shows with no click action (today's
  WR-05 behaviour). OK? (Desaturating or hiding it would be new behaviour.)
- **Q12.** Offer the row to every mage who knows Comprehend Scroll (knownID 1296017; existing
  mechanism). Confirm.
- **Q13.** In-game checks:
  - The ID tooltip on the familiar buff should read 1302303 / 1302285 / 1296202 (aura = use spell).
  - Does using a Cat scroll while a Rat familiar is up replace it (tier exclusivity)?
  - Does the familiar stack with Arcane Intellect?
  - Is the spellbook Comprehend Scroll 1296017?
- **Q14.** No group with Arcane Intellect or the armors (separate auras). Confirm.

---

## 12. Rank coverage: which ranks must be listed explicitly (follow-up, 2026-11-09)

User: "these ids need to group the different ranks". Every gap below closes with data (one-way
alternatives in the existing `MetaReminderGroup`); no gap needs new code, so none is left open.

### 12.1 Where the rank family misses an aura the player can have

The row's own watch list is {row ID} ∪ {ranks of that name the player knows}. Each alternative's
family is {alt ID} ∪ {ranks of that name the player knows} (§2.1). That misses two real cases:

- **Another player's cast at a rank this player doesn't know.** Example: a level-30 priest knows
  PW:F ranks 1–3 (1243, 1244, 1245). The row names 10938, so a level-60 priest's rank 6 is caught,
  but rank 5 (10937) or rank 4 (2791) from a level-48 priest is **missed**. The reminder then shows
  while the buff is up.
- **A lower-level player receiving a higher rank.** Same mechanism. The worst existing case is
  **Arcane Intellect, whose row names rank 1 (1459)**: a level-30 mage knows ranks 1–3, so another
  mage's rank 4 (10156) or rank 5 (10157) is missed today.
- **Not a problem:** a level-60 character who knows every rank (the family is complete), and
  self-only buffs (the player can only have ranks they cast).

**Fix (data):** put every rank another player can apply into the row's one group call, as one-way
alternatives. This uses the existing "Also satisfied by" mechanism (RALT-01) unchanged.

### 12.2 Per-row table (Forever)

"Add" = the explicit IDs the row's `MetaReminderGroup` call must carry in addition to its
exclusive partners and group buffs. All IDs were read from `/forever/` data (links in §3–§7).

| Row | Can another player apply it? | Add as alternatives (beyond the row ID) | Notes |
|-----|------------------------------|------------------------------------------|-------|
| Arcane Intellect 1459 (both) | yes | 1460, 1461, 10156, 10157, + Arcane Brilliance 23028 | Row is rank 1: today misses ranks above what the mage knows. Forever block only (1459 is `both`) |
| Frost Armor 7301 / Ice Armor 10220 / Mage Armor 22783 | no (self) | none — family is enough; group partners only | — |
| Power Word: Fortitude 10938 | yes | 1243, 1244, 1245, 2791, 10937, + Prayer 21562, 21564 | 21562: Forever block |
| Divine Spirit 27841 | yes | 14752, 14818, 14819, + Prayer of Spirit 27681 | — |
| Mark of the Wild 9885 | yes | 1126, 5232, 6756, 5234, 8907, 9884, + Gift 21849, 21850 | 1126 is the retail MotW row: Forever block |
| Thorns 9910 | yes (druids Thorns tanks) | 467, 782, 1075, 8914, 9756 | Thorns has no group today; this is a new call in the Forever block |
| Battle Shout 25289 | yes (another warrior's shout) | 6673, 5242, 6192, 11549, 11550, 11551 | 6673 is the retail Battle Shout row: Forever block |
| Trueshot Aura 20906 | yes (another hunter's aura) | 19506, 20905 | — |
| Blood Pact 11767 | yes (another warlock's imp) | 6307, 7804, 7805, 11766 | The pet-book family covers your own imp's ranks; others' need listing. Forever's DB also has 7871–7873, 11768–11769, 20318–20321, 20397 named Blood Pact (vanilla teach/NPC IDs, UNVERIFIED-FOR-FOREVER as player auras). Leave them out unless the ID tooltip shows one (Q16) |
| Blessings (Kings 20217, Might 25291, Wisdom 25290, + 1038, 19979 while they exist) | yes | Might 19740, 19834, 19835, 19836, 19837, 19838; Wisdom 19742, 19850, 19852, 19853, 19854; Greater Kings 25898; Greater Might 25782, 25916; Greater Wisdom 25894, 25918 | Kings has one rank. All of these go in the **one** blessings call |
| Righteous Fury 25780 | no (self, one rank) | none | — |
| Demon Armor 11735 / Demon Skin 696 | no (self) | none — family is enough | — |
| Lightning Shield 10432 / Water Shield 408510 | no (self) | none | — |
| Inner Fire 10952 | no (self) | none | — |
| Shadowform 15473 | no (self, one rank) | none | — |
| Shadowguard 19312 (optional) | no (self) | none | — |
| Paladin aura row 10293 | yes (another paladin's aura reaches you) | Devotion 465, 10290, 643, 10291, 1032, 10292; Retribution 7294, 10298, 10299, 10300, 10301; Concentration 19746; Shadow Res. 19876, 19895, 19896; Frost Res. 19888, 19897, 19898; Fire Res. 19891, 19899, 19900 | 465 is the retail Devotion row: Forever block. Q15 |
| Hunter aspect row 25296 | only Pack/Wild (party aspects) | Monkey 13163, Cheetah 5118, Pack 13159, Wild 20043, 20190, Beast 13161 | Hawk itself is self-only. Beast's Forever ranks 1299445–7 are self-only, so the family covers them |
| Demonic Sacrifice 18788 (auraID 18789) | no | 18790, 18791, 18792 (the other three buffs, not ranks) | — |
| Familiar scroll 1302303 | no (self item use) | 1302285, 1296202 (the other tiers, not ranks) | §11.2 |
| *If ever added:* Shadow Protection 10958 | yes | 976, 10957, + Prayer 27683 | excluded in §6 |
| *If ever added:* Amplify 10170 / Dampen 10174 | yes | Amplify 1008, 8455, 10169; Dampen 604, 8450, 8451, 10173 | excluded in §6 |
| *If ever added:* Detect Invisibility 11743 | yes | 132, 2970 | excluded in §6 |

### 12.3 Final group calls (all inside the Forever block; supersede §4 and §5)

```lua
if ns.CLIENT_IS_FOREVER then
	-- Single-target class buffs: every rank another player can apply, plus the group buff.
	MetaReminderGroup(1459, 1460, 1461, 10156, 10157, 23028) -- Arcane Intellect + Arcane Brilliance
	MetaReminderGroup(10938, 1243, 1244, 1245, 2791, 10937, 21562, 21564) -- PW:F + Prayer of Fortitude
	MetaReminderGroup(27841, 14752, 14818, 14819, 27681) -- Divine Spirit + Prayer of Spirit
	MetaReminderGroup(9885, 1126, 5232, 6756, 5234, 8907, 9884, 21849, 21850) -- MotW + Gift of the Wild
	MetaReminderGroup(9910, 467, 782, 1075, 8914, 9756) -- Thorns
	MetaReminderGroup(25289, 6673, 5242, 6192, 11549, 11550, 11551) -- Battle Shout
	MetaReminderGroup(20906, 19506, 20905) -- Trueshot Aura
	MetaReminderGroup(11767, 6307, 7804, 7805, 11766) -- Blood Pact
	-- Replaces the existing blessings call. Drop 1038/19979 here if Q1 = remove.
	MetaReminderGroup(
		20217, 25291, 25290, 1038, 19979,
		19740, 19834, 19835, 19836, 19837, 19838, -- Might ranks
		19742, 19850, 19852, 19853, 19854, -- Wisdom ranks
		25898, 25782, 25916, 25894, 25918 -- Greater Kings, Might, Wisdom
	)

	-- Exclusive self-buff groups (rows are mutual; the family covers lower ranks).
	MetaReminderGroup(7301, 10220, 22783) -- Mage armors
	MetaReminderGroup(11735, 696) -- Warlock armors
	MetaReminderGroup(10432, 408510) -- Shaman shields

	-- "Any of" rows (one-way).
	MetaReminderGroup(
		10293, 465, 10290, 643, 10291, 1032, 10292, -- Devotion
		7294, 10298, 10299, 10300, 10301, -- Retribution
		19746, -- Concentration
		19876, 19895, 19896, 19888, 19897, 19898, 19891, 19899, 19900 -- resistance auras
	) -- Paladin: any aura
	MetaReminderGroup(25296, 13163, 5118, 13159, 20043, 20190, 13161) -- Hunter: any aspect
	MetaReminderGroup(18788, 18790, 18791, 18792) -- Demonic Sacrifice (row auraID 18789)
	MetaReminderGroup(1302303, 1302285, 1296202) -- Familiar scrolls
end
```

(The planner should check the stylua formatting of the multi-line calls. Per the CLAUDE.md
stylua trap, keep comments out of the middle of an expression if stylua mangles CR there: move
them above the call.)

### 12.4 Does listing a row's own ranks as alternatives cause problems in Core.lua?

Checked against the cast path (Providers.lua 376–447) and the rebuilds (Core.lua 1478–1500,
1535–1607, 1652–1714). **No correctness problem, and no code change needed.**

- **Duplicate start on the player's own cast: no.** A cast of a rank the player knows resolves the
  row through `ns:ResolveCastOwner(..., ns.metaReminderKeyBySpell, ns.rankIndexMetaReminder, ...)`
  first. The same ID is also in `ns.alternativeKeysBySpell` (its own rank is in the alternative's
  family). The alternatives loop explicitly skips `altKey == metaReminderKey`
  (Providers.lua 436–438), so the reminder starts once. A cast of a rank the player doesn't know
  can't happen.
- **Duplicate owner in the cast index: no.** `ns.metaReminderKeyBySpell` and the rank index map
  only the row's own family. Alternatives live in the separate `ns.alternativeKeysBySpell`
  (one-to-many by design). The RANK-01 rule ("the flat cast map never contains an ID that is
  itself a tracker slot") is untouched.
- **An alternative that is its own family: harmless.** `ns:CastRuleFamily(10937)` returns
  {10937} ∪ the known ranks of the same name, which overlaps the row's own family.
  `ns:RebuildReminderWatch` de-duplicates with `ListContains`, and `IndexFamily` adds a key once
  per ID, so the watch list and the alternative index each hold every ID once.
- **Two row IDs in one group** (e.g. the blessings, the armors) already work this way today
  (57.5), so nothing new there.
- **Costs (minor, for the cleanup phase to note, not to change):**
  - Each alternative ID is one `ns:ResolveRankFamily` spellbook scan per SPELLS_CHANGED, cached
    in `ns.endRuleFamilies`. Only loaded, placed reminders expand their alternatives, so a paladin
    with three blessing rows costs about 20 cached scans after a spellbook change, out of combat.
  - `ns:RefreshAuraStates` reads each ID in the watch list with `GetPlayerAuraBySpellID` while the
    buff is absent (about 22 IDs for a blessing or the aura row).
  - The edit popup's "Also satisfied by" field lists every ID with an icon, so a built-in blessing
    shows a long row of repeated blessing icons. This is cosmetic only, and user input never
    reaches a built-in's alternatives.

  No optimisation is proposed, per the scope constraint.
- **Forever block reminder:** 1126, 6673, 465, 21562 and 1459 are in these lists, so the
  `if ns.CLIENT_IS_FOREVER then` block is mandatory to keep retail exactly as it is.

### 12.5 Open questions (rank coverage)

- **Q15.** Paladin "any aura" row: should another paladin's aura satisfy it (list all ranks, as
  above)? A rank you know, cast by another paladin, already counts today, because auras can't be
  told apart by caster. Recommended: list them, so the row consistently means "an aura is on you".
- **Q16.** Blood Pact's extra Forever IDs (7871–7873, 11768–11769, 20318–20321, 20397): add only
  if the ID tooltip shows one of them as the buff on the player?

---

## Sources

Forever data (every `/forever/` link above was read through the tooltip endpoint of the same database):
- Wowhead Forever database, e.g. https://www.wowhead.com/forever/spell=7301 (page fetched), tooltip JSON https://nether.wowhead.com/forever/tooltip/spell/7301 and https://nether.wowhead.com/forever/tooltip/item/277493
- Warcraft DB Forever: https://forever.warcraftdb.com/data/spell/25780, search API https://forever.warcraftdb.com/api/v1/search/page?q=familiar
- warcraft.wiki.gg Forever ability lists: [Mage](https://warcraft.wiki.gg/wiki/Mage_abilities_(Forever)), [Warlock](https://warcraft.wiki.gg/wiki/Warlock_abilities_(Forever)), [Paladin](https://warcraft.wiki.gg/wiki/Paladin_abilities_(Forever)), [Priest](https://warcraft.wiki.gg/wiki/Priest_abilities_(Forever)), [Shaman](https://warcraft.wiki.gg/wiki/Shaman_abilities_(Forever)), [Druid](https://warcraft.wiki.gg/wiki/Druid_abilities_(Forever)), [Hunter](https://warcraft.wiki.gg/wiki/Hunter_abilities_(Forever)), [Rogue](https://warcraft.wiki.gg/wiki/Rogue_abilities_(Forever)), [Warrior](https://warcraft.wiki.gg/wiki/Warrior_abilities_(Forever))
- Blizzard, World of Warcraft: Forever Class Deep Dives (Mage and Shaman): https://worldofwarcraft.blizzard.com/news/24302097
- Warcraft Tavern, All Changes to Paladins in WoW Forever (MEDIUM, third-party summary of beta notes): https://www.warcrafttavern.com/forever/news/all-changes-to-paladins-in-wow-forever/
- BigWigsMods/WoWUI `forever-beta`, `Interface/AddOns/Blizzard_CooldownViewer/GroupBuffFilter.lua` (no spell IDs; data-driven from C)

Code read: `Providers.lua` 60–160, 330–459, 825–874, 1000–1339, `Core.lua` 880–1030, 1110–1190,
1325–1364, 1478–1510, 1525–1714, 2160–2198, `ReminderClick.lua` (whole file), `BuffEngine.lua` 34–41,
`CDMTab.lua` 2450–2490.
