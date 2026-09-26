# v0.4.1 CHANGELOG Draft

This is a DRAFT only. No agent appends this to `CHANGELOG.md` — paste it
above the `## v0.4.0` entry yourself, editing freely first.

```markdown
## v0.4.1 — Generic Item Tracking and Forever Racials

Track any usable item from your bags, see the Cooldown Manager's
pandemic and dispel-type indicators on TBT's own trackers, and get a
racial tracker for every WoW Forever race.

### New Features
- **Item tracking** - Any usable consumable in your bags is now offered
  as a tracker in Suggested, with its own icon and how many you're
  currently holding. Drag one in to start tracking it. Using any item
  refreshes every tracked item's cooldown, so potions and other
  consumables that share a cooldown all show it together. A tracked
  item keeps its icon and running cooldown even after you run out of
  it
- **Pandemic highlight** - A tracked cooldown or buff that's inside its
  pandemic refresh window now shows the same highlight Blizzard's
  Cooldown Manager shows, on both TBT's icons and bars
- **Dispel-type border** - A tracked buff or debuff that Blizzard's
  Cooldown Manager borders by dispel type (Magic, Curse, Disease,
  Poison or Bleed) now shows the same border on TBT's icon and bar
- **Forever Racial Trackers - every race** - Every WoW Forever race now
  has its own racial trackers, visible only to players of that race,
  completing what v0.4.0 started with gnome, troll and orc. Gnomes and
  trolls also gain their **second** racial (Escape Artist and Rapid
  Regeneration), which v0.4.0 did not cover. Racial trackers you had
  already placed carry forward automatically, so nothing you set up is
  lost

### Fixes
- A tracked racial's buff icon and timer now correctly clear when the
  buff itself ends, instead of lingering for its full nominal duration
- Eureka! (gnome) on a **priest** now spends a stack on healing casts
  too, matching the ability's own tooltip. Every other class is
  unchanged - they still spend only on damaging casts
- Eureka!'s cooldown now reads 2:00 instead of 3:00, matching what the
  game actually does. An **existing** Eureka! cooldown tracker keeps the
  old 3:00 it was created with - delete and re-add it to pick up the
  corrected value
```

## Notes for the user

**Title alternative.** The header above uses the milestone's own name.
A shorter option, if preferred: `## v0.4.1 — Item Tracking and Forever
Racials`.

**Two additions made 2026-09-26** after re-checking the entry against
`git show v0.4.0:Providers.lua` rather than against memory:

- **Eureka!'s 3:00 → 2:00 cooldown correction was missing.** v0.4.0's
  table carried `cooldown = 180`; the beta changed the ability to 120
  and Phase 49 corrected it. A gnome watched a 3-minute sweep for a
  2-minute ability. The bullet carries the caveat that matters more than
  the fix: `entry.duration` is persisted at tracker CREATION, so the
  correction only reaches newly created trackers. Without saying so, the
  first gnome to read "fixed" and still see 3:00 files a bug.
- **Gnomes and trolls gain a SECOND racial.** The original bullet read as
  "every race is now supported", which undersells it for the two races
  that already were — v0.4.0 shipped one racial each for gnome and troll.

**Deliberately NOT added: the orc second racial's label.** v0.4.0's table
really did carry the placeholder `fallbackLabel = "Orc Racial"`, and
v0.4.1 corrects it to "Shatter Curse" — so it looks like a fix. It is
not a user-visible one. `fallbackLabel` is only displayed when
`C_Spell.GetSpellInfo` fails to resolve the spell, which does not happen
on Forever; the tile has always shown the real name from the client.
Confirmed by the user, 2026-09-25: *"label was never seen in game, the
tooltip is the skill's tooltip so it has always been right."* A changelog
line for a string nobody ever saw is noise.

**Recommendation 1 — INCLUDE a Known Issues bullet for the Skyborne
duration waiver (tracked internally as G8).** Both Skyborne second
racials (Read Ley Line / Skysight) ship on their minimum duration
rather than a longer one that applies under a specific in-game
condition we could not reliably reproduce to confirm. This is
user-visible in the same way the existing Forever SavedVariables
Known Issue is, which is the precedent for writing it up rather than
omitting it. Drafted bullet, ready to paste into a `### Known Issues`
section if you agree:

```markdown
### Known Issues
- **A Skyborne character's second racial can show a shorter timer than
  the buff actually lasts under a specific condition.** We could not
  reliably reproduce that condition to confirm the correct duration,
  so the tracker uses the racial's normal (shorter) duration instead.
```

**Recommendation 2 — the Eureka! priest bullet. REWRITTEN 2026-09-25,
and the original was wrong in a way worth recording.**

The drafted bullet originally read: *"Eureka! (gnome) now spends a
stack only when you cast something harmful, instead of on every cast."*
That is backwards. `v0.4.0` already shipped the harmful-only gate —
confirmed directly: `git show v0.4.0:Providers.lua` contains
`CastSpendsStack` with the `IsSpellHarmful` test. So the drafted line
describes reverting **to** v0.4.0's behaviour, not the change v0.4.1
makes.

It also describes a state that never shipped. During Phase 49 the
harmful gate was briefly removed outright, on a misreading of the
user's instruction, and restored the same day scoped to priests
(`f9be545` then `4ac0e1c`). The drafted bullet described that
intermediate commit rather than the branch's actual end state — the
hazard of writing release copy from commit history instead of from a
diff against the last tag.

**The real change:** the harmful gate stays for rogue, mage, warlock
and warrior; it is skipped for priests only, because the priest
tooltip says *damaging or healing* where the other four say *damaging*.
The bullet above now says that.

**A tension you need to resolve, which the original draft had both
ways at once.** This bullet documents the priest branch — and the
priest branch is the one thing in this change that was **never tested
in game**. The non-priest branch passed on a gnome mage; no priest
character has exercised the new path. The original draft recommended
staying silent about the untested branch while simultaneously
listing it as a fix.

Pick one:
- **Keep the bullet** (recommended) — it is a real, intended behaviour
  change a gnome priest will notice, and describing it is more useful
  than silence. Accepts that you are announcing something unverified.
- **Drop it** — say nothing, let it surface as a bug report if the
  implementation is wrong. Costs a gnome priest the explanation for
  why their charges now behave differently.

Either way it stays on the record in `STATE.md` and
`.planning/research/FOREVER-RACIALS.md` (F-2).
