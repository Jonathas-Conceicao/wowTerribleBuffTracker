# Forever Racial Collection — Phase 49 (RACE-07/08/09)

Collection log for the Forever 1.60.1 racials. Filled in from in-game debug output, one character
per race, by the user. This is the source the `RACIAL_SPELLS` table at `Providers.lua:794` is built
from — **not** a design doc. Nothing here is implemented until the table for that race is filled.

> **Every number here is a reading of the CURRENT BETA PATCH, and racials are being actively
> changed.** User's own framing, 2026-09-24. Gnome's Eureka! is the proof: it was entered correctly
> at 180s in Phase 41 and the beta has since moved it to 120s. So a value going stale is a normal
> outcome here, not a mistake by whoever entered it, and a disagreement between this file and the
> shipped table means "re-read the client", never "someone was careless". Date every row.

## How a row is produced

`/tbt debug` on a fresh login, then use both racials. Each produces a pair:

```
TBT Debug: SPELL Berserking — spellID 20554
TBT Debug: AURA GAINED after Berserking — Berserking auraID 20554 duration 10s | cooldown 180s
```

The cast ID and the aura ID are read separately on purpose — they are not always the same number,
and `RACIAL_SPELLS` currently has only a `spellID` field, so a race where they diverge needs a
decision (see Open Questions).

## The shape each row must fill

`RACIAL_SPELLS` is keyed by the numeric raceID (third return of `UnitRace("player")`):

```lua
{ spellID = 20554, duration = 10, cooldown = 180, race = "Troll", fallbackLabel = "Berserking" },
```

`maxStacks` is optional and present only where the racial stacks — gnome Eureka! is the only known
case so far, at 3.

## Collected

### Troll — raceID 8 — COMPLETE 2026-09-24

| Racial | Cast spellID | Aura ID | Duration | Cooldown |
|---|---|---|---|---|
| Berserking | 20554 | 20554 | 10s | 180s |
| Rapid Regeneration | 1260270 | 1260270 | 6s | 180s |

```lua
[8] = {
    { spellID = 20554, duration = 10, cooldown = 180, race = "Troll", fallbackLabel = "Berserking" },
    { spellID = 1260270, duration = 6, cooldown = 180, race = "Troll", fallbackLabel = "Rapid Regeneration" },
},
```

Cast ID and aura ID are **identical** for both — worth recording, since the tooling was built
expecting them to diverge, and for troll they do not.

**The tooling validated itself here.** Berserking already existed in `RACIAL_SPELLS` as
`duration = 10, cooldown = 180`, entered by hand in Phase 41, and the automated read returned
exactly those numbers against a row nobody had disputed. Any systematic error in the capture — a
remaining-time read instead of a full cooldown, a GCD confusion, an off-by-one on the delay — would
have shown up as a disagreement on this row.

**Rapid Regeneration is new**: Forever gives troll a second racial the current table has no entry
for. 6s / 180s.

### Orc — raceID 2 — COMPLETE 2026-09-24

| Racial | Cast spellID | Aura ID | Duration | Cooldown |
|---|---|---|---|---|
| Blood Fury | 20572 | 20572 | 15s | 120s |
| **Shatter Curse** | 1299026 | 1299026 | 8s | 180s |

```lua
[2] = {
    { spellID = 20572, duration = 15, cooldown = 120, race = "Orc", fallbackLabel = "Blood Fury" },
    { spellID = 1299026, duration = 8, cooldown = 180, race = "Orc", fallbackLabel = "Shatter Curse" },
},
```

**The `"Orc Racial"` placeholder is resolved: the ability is Shatter Curse.** That row was entered
in Phase 41 with a made-up `fallbackLabel` because the real name was not known; this is the one
concrete code change the collection has produced so far that is ready to apply immediately.

Every number on this race already matched: 15/120 and 8/180 were both in the table and both came
back identical. Together with troll's Berserking that is **three independently hand-entered rows
reproduced exactly by the automated read**, which is about as much confidence in the capture as is
available without a fourth source.

### Human — raceID 1 — COLLECTED 2026-09-24, one cooldown missing

| Racial | Cast spellID | Aura | Duration | Cooldown |
|---|---|---|---|---|
| Perception | 20600 | 20600 | 20s | 180s |
| Will to Survive | 1259718 | **none** (user-confirmed) | n/a | 180s (user-reported) |

```lua
[1] = {
    { spellID = 20600, duration = 20, cooldown = 180, race = "Human", fallbackLabel = "Perception" },
    -- Will to Survive: no aura, so no `duration` key. Needs the StartRacialProc guard first.
    { spellID = 1259718, cooldown = 180, race = "Human", fallbackLabel = "Will to Survive" },
},
```

**Will to Survive printed a `SPELL` line and nothing else**, which was a tooling defect rather than
a property of the racial. The no-aura branch was gated on a *real* cooldown reading, to keep
Frostbolt and Shoot out of the log — and Will to Survive applies no aura **and** reports no readable
cooldown at the 0.35s mark, so it fell through both conditions and printed nothing. Silence is the
one thing a collection tool must never produce for a cast the user deliberately made: it is
indistinguishable from the tool being broken.

Fixed the same day by replacing the cooldown gate with **once per distinct spell per session**. A
spammed Frostbolt now costs one line for the whole session, every racial is guaranteed its line
whatever its cooldown reads, and the cooldown prints as a number, `gcd?`, or `none` — all three
being real answers, and `none` being exactly what the old gate discarded.

**Cooldown supplied directly by the user, 2026-09-24: 3 minutes.** No re-log needed.

### Dwarf — raceID 3 — COLLECTED 2026-09-24

| Racial | Cast spellID | Aura ID | Duration | Cooldown |
|---|---|---|---|---|
| Stoneform | 20594 | 20594 | 8s | 180s |
| Find Treasure | 2481 | 2481 | **permanent, until toggled off** | **none at all** |

Stoneform is ready:

```lua
{ spellID = 20594, duration = 8, cooldown = 180, race = "Dwarf", fallbackLabel = "Stoneform" },
```

**Find Treasure is a fifth shape: no duration AND no cooldown.** A pure toggle, user-confirmed — it
stays on until switched off. Every other odd racial so far still had *one* trackable number; this
has neither, so there is nothing for either tile to count.

Recommended: **leave it out of `RACIAL_SPELLS` entirely.** That is not a workaround, it is what the
existing code already does with it — `RacialCooldownKeys` only emits a key for a def with a
`cooldown`, and a permanent aura gives the buff tile nothing to show, so a row for Find Treasure
would produce no tile by either route. Adding one would be a table entry that renders nothing,
which is worse than an absent entry because it looks deliberate.

Consequence to be aware of: dwarf then has **one** trackable racial. Slot 2 resolves to false,
exactly as a one-racial race already does, and RACE-08 is still satisfied — a dwarf sees their
racial rather than a "not yet supported" tile.

Find Treasure belongs to the same family as tauren's Plainsrunning: a **state**, not a timer.
If that family ever gets a tracker, both are its members.

**`gcd?` cannot ever be auto-resolved, and this race proves it.** Tauren's Cultivation read `gcd?`
and hides a *one hour* cooldown; dwarf's Find Treasure reads `gcd?` and has *no cooldown at all*.
Identical output, opposite realities. Any rule that turned `gcd?` into a number — "assume short",
"assume none" — would be wrong half the time on the evidence collected so far. It means ask, always.

### Night Elf — raceID 4 — COLLECTED 2026-09-24, one decision needed

| Racial | Cast spellID | Aura ID | Duration | Cooldown |
|---|---|---|---|---|
| Shadowmeld | 20580 | 20580 | **permanent** | 10s |
| Elune's Light | 1259799 | 1259799 | 15s | 180s |

Elune's Light is straightforward and ready:

```lua
{ spellID = 1259799, duration = 15, cooldown = 180, race = "Night Elf", fallbackLabel = "Elune's Light" },
```

**Shadowmeld is a fourth shape `RACIAL_SPELLS` cannot express.** Its aura is `permanent` — it lasts
until the player moves or acts, not for a fixed time — and its cooldown is only 10s. A row for it
would be actively wrong in two directions at once: `duration = 0` makes
`proc.expiresAt = now + 0`, so the tile appears and vanishes in the same frame, and any invented
number would show a countdown for something that has no natural end.

**RESOLVED by D-1 and D-6 below.** Shadowmeld gets an indefinite buff tile ended by the aura going
absent (or by entering combat), **and keeps its 10s cooldown tile**. The options below are kept as
the reasoning that led there.

An earlier draft of this note called cooldown-only "the honest shape"; that was a proposal stated as
a conclusion on a question the user had reserved. Reinforced by the user: Shadowmeld is *genuinely*
permanent — **it lasts until the player moves**, not until a timer runs out.

Three shapes, with what each costs:

1. **Cooldown-only**, like War Stomp and Will of the Forsaken. Cheapest, needs nothing beyond the
   nil-duration guard already required. Cost: it shows the 10s cooldown and says nothing about
   whether you are *still stealthed*, which is the thing a player actually wants to know.
2. **Aura-cancelled buff tile — the leading candidate.** The machinery already exists and is not
   new work: `ScanActiveTimersForCancellation` (`BuffEngine.lua:637`) ends any proc whose
   `aliveBuffs` list has gone absent, and 20580 is a real readable aura out of combat, which is
   where Shadowmeld is used. The row would carry a long nominal duration purely as a backstop and
   let the aura scan do the real work, so the tile lasts exactly as long as the stealth does.
   The one thing to check rather than assume: `StartRacialProc`'s header says racial procs
   *deliberately* carry no `aliveBuffs`. Reading it, that is a warning about a pooled table handing
   the scan a list it never meant to have — i.e. about leaking one by accident, not a prohibition
   on setting one on purpose. `ns:AcquireProc` wipes, so an intentional list is safe. Worth
   confirming against that comment's author intent before relying on it.
3. **Indefinite tile with no countdown** — display it as "up" with no timer at all. Still needs a
   signal to take it down, so it reduces to option 2 with a worse-looking tile.

Option 2 is the only one that tells the player what they want to know, and it costs an `aliveBuffs`
assignment rather than a new mechanism. Recommended, not decided.

### Gnome — raceID 7 — COMPLETE 2026-09-24

| Racial | Cast spellID | Aura ID | Duration | Cooldown |
|---|---|---|---|---|
| **Escape Artist** | 20589 | 20589 | 3s | 120s |
| Eureka! | 1259817 | 1259817 | 15s | **120s — not the 180 currently in the table** |

```lua
[7] = {
    { spellID = 1259817, duration = 15, cooldown = 120, maxStacks = 3, race = "Gnome", fallbackLabel = "Eureka!" },
    { spellID = 20589, duration = 3, cooldown = 120, race = "Gnome", fallbackLabel = "Escape Artist" },
},
```

**⚠️ FIRST DISAGREEMENT WITH HAND-ENTERED DATA — and it is a real game change, not a bad entry.**
`Providers.lua:800` records Eureka! at `cooldown = 180`; the client reports **120**. Confirmed by
the user, 2026-09-24: **the ability changed in the beta.** Phase 41's 180 was correct when it was
written.

That distinction matters for how the rest of this document is read. The risk here was never careless
data entry — it is that **a correct value goes stale**. Every previous re-log (Berserking, Blood
Fury, orc's second racial) reproduced its row exactly, so the read is trustworthy; this one caught
drift, which no amount of care at entry time could have prevented. **The table needs correcting to
120**, and this single finding justifies the whole re-log exercise.

`duration = 15` and `maxStacks = 3` both still agree.

**Escape Artist is new** — a second gnome racial the table has no entry for, continuing the pattern
that every Forever race has two.

**Reading hazard, not a bug: the first `AURA GAINED` line after enabling debug can carry a backlog.**
This log's Escape Artist line lists five auras — Power Word: Fortitude, Arcane Intellect, Find
Minerals, Camp Benefits and the racial itself — because those four landed in the eleven seconds
between `/tbt debug` and the cast, so they were genuinely new since the baseline. The system
self-corrected exactly as designed: the very next cast, Eureka!, printed one clean line. When a line
looks noisy, the racial is the entry whose name matches the cast, or simply re-cast for a clean
read.

### Tauren — raceID 6 — COLLECTED 2026-09-24, needs a re-log and one decision

| Racial | Cast spellID | Aura | Duration | Cooldown |
|---|---|---|---|---|
| War Stomp | 20549 | **none** (stuns the target; a debuff on the enemy, out of scope) | n/a | 120s (user-reported) |
| Cultivation | **20552 / 1312643 / 1312650** | none that matters | n/a | 3600s (1 hour, user-reported) |

War Stomp is ready once the no-duration guard exists:

```lua
{ spellID = 20549, cooldown = 120, race = "Tauren", fallbackLabel = "War Stomp" },
```

Cultivation still waits on the three-cast-ID question below.

Both tauren racials are **cooldown-only**, the same shape as Will of the Forsaken.

**Cultivation reports three different cast spell IDs** — 20552, 1312643 and 1312650, all named
"Cultivation", across three presses in one session. That is the first racial where a single ability
does not have a single cast ID, and it breaks an assumption the whole tracker rests on:
`RacialProviderMixin:OnTrigger` matches `spellID == def.spellID`, one number, so a row naming any one
of the three would silently miss the other two. **Needs a decision before tauren can be entered** —
most likely a row that accepts a set of IDs rather than one, or one ID identified as the real
trigger and the others explained. Worth first establishing what the three are: stages of a sequence,
a rank progression, or per-press variants.

**Plainsrunning (aura 1299038, permanent) — a new Forever passive. Deliberately OUT of this phase,
user decision 2026-09-24, noted for a possible tracker later.**

It is not Cultivation's point and appears alongside it. What makes it interesting enough to write
down: it is a **permanent out-of-combat buff that drops the moment combat starts**, so the shape a
tracker would need is the inverse of everything else here — not "runs for N seconds from a cast",
but "up whenever out of combat, zero the instant combat begins". The user's own framing: track it
while out of combat and assume zero once combat starts.

Nothing in `RACIAL_SPELLS` can express that: every row there is a duration counted from a cast, and
this has no cast and no duration. It would need its own mechanism keyed on
`PLAYER_REGEN_DISABLED`/`PLAYER_REGEN_ENABLED` rather than `UNIT_SPELLCAST_SUCCEEDED`. That is why
it stays out of Phase 49 rather than being squeezed in — it is a different feature wearing a
racial's clothes.

**`cooldown gcd?` is the guard working, not a failure.** The reading came back at GCD length for an
ability whose real cooldown is an hour, and printing `gcd?` is what stopped 1.5s being written into
the table as fact. It also means the 0.35s cooldown read does **not** reliably catch a real cooldown
for every ability — so a `gcd?` on any future racial means "ask the user", never "assume short".

**War Stomp produced no line at all**, which was a tooling bug rather than an absence: the cooldown
used to print only as part of the `AURA GAINED` line, so a racial with no aura dropped the one field
it does have. Fixed the same day. Its cooldown was then supplied directly by the user — 2 minutes.

### High Order Skyborne (Alliance) — raceID **95** — COLLECTED 2026-09-24

| Racial | Cast spellID | Aura ID | Aura name | Duration | Cooldown |
|---|---|---|---|---|---|
| Walk on Air | 1259416 | 1259416 | Walk on Air | 10s | 120s |
| Read Ley Line | 1259705 | **1270842** | **Energized** | 15s | 120s |

```lua
[95] = {
    { spellID = 1259416, duration = 10, cooldown = 120, race = "Skyborne", fallbackLabel = "Walk on Air" },
    -- Read Ley Line: blocked on the conditional-duration question, NOT ready.
    -- { spellID = 1259705, duration = 15, cooldown = 120, race = "Skyborne", fallbackLabel = "Read Ley Line" },
},
```

**The faction-prefix hypothesis was right, and the two halves are not interchangeable.** Alliance
"High Order Skyborne" is raceID **95**, Horde "Windshaper Skyborne" is **96** — two IDs, so two table
entries were always going to be needed. But they are not duplicates:

| | Alliance (95) | Horde (96) |
|---|---|---|
| Shared racial | Walk on Air 1259416, 10s/120s | **identical** |
| Second racial | Read Ley Line → Energized, 15s/120s | Skysight → Elemental Blessing, 30s/120s |

So one racial is genuinely shared and one differs in ID, name, aura and duration. Copying either
faction's block to the other would have shipped a wrong second racial to half the Skyborne
population — which is precisely the failure the "check for a counterpart" note was written to
prevent, and why it was worth one character rather than an assumption.

**Read Ley Line is the third cast/aura name divergence** (after Skysight and Cannibalize), and the
second where the name changes too. `fallbackLabel` takes the **cast** name, Read Ley Line.

**CONFIRMED 2026-09-24: Energized has the same conditional 15-minute duration.** The parallel to
Skysight holds, so this is a **designed Skyborne mechanic, not a quirk of one racial** — both
factions' second racial stretches to 15 minutes on a condition. See the shared write-up under
"The Skyborne conditional duration" below; the problem and its answer are the same for both.

### Windshaper Skyborne (Horde) — raceID **96** — COLLECTED 2026-09-24

A **new Forever-only race**, not present in retail. Full name **"Windshaper Skyborne"**, race token
`Skyborne` — note the spelling, earlier notes in this file said "Skyborn". raceID **96**, which is
well outside the 1-11 range the classic races occupy and is why it could never have been guessed.

| Racial | Cast spellID | Aura ID | Aura name | Duration | Cooldown |
|---|---|---|---|---|---|
| Walk on Air | 1259416 | 1259416 | Walk on Air | 10s | 120s |
| Skysight | 1259686 | **1259688** | **Elemental Blessing** | 30s | 120s |

```lua
[96] = {
    { spellID = 1259416, duration = 10, cooldown = 120, race = "Skyborne", fallbackLabel = "Walk on Air" },
    -- Skysight: blocked on the Elemental Blessing question below, NOT ready.
},
```

**Confirmed 2026-09-24: the Alliance counterpart exists and is a separate race** — High Order
Skyborne, raceID 95, written up above. The two share Walk on Air exactly and differ entirely on the
second racial, so neither block can be derived from the other.

**Skysight is the second cast/aura divergence, and the first where the NAME differs too** — casting
"Skysight" (1259686) applies an aura called "Elemental Blessing" (1259688). Undead Cannibalize
diverged only in number. This matters for `fallbackLabel`: the label should be the **cast** name,
Skysight, because that is what the player pressed and what the icon and tooltip resolve from.

Its conditional duration is covered below — it is not specific to this faction.

Do not enter Skysight before that is settled.

---

## The Skyborne conditional duration — the phase's main open design question

**Carried to before the phase closes, by user decision 2026-09-24.** Applies to **both** Skyborne
races, confirmed on each:

| Race | Racial | Aura | Normal | Conditional |
|---|---|---|---|---|
| Horde 96 | Skysight | Elemental Blessing 1259688 | 30s | **15 min near an elemental** |
| Alliance 95 | Read Ley Line | Energized 1270842 | 15s | **15 min on condition** |

Both confirmed by the user, so this is a **designed race mechanic, not one odd racial** — it covers
2 of the 10 races collected, and it is the only finding in this phase that `RACIAL_SPELLS` cannot
express at all.

**Why a fixed `duration` cannot work here.** 30s against 900s is a factor of 30. The short value
shows a timer that expires fourteen and a half minutes early; the long value shows one that hangs
long after the buff is gone. There is no compromise number — a wrong racial timer is worse than no
racial timer, because the player acts on it.

**The user is testing whether the aura ID changes between the two versions, and that test decides
the design.** Spelling out why, so the result is actionable the moment it arrives:

- **If the aura ID is the SAME for both versions** — the clean answer is to stop using the table's
  number for this racial and read the aura's *real* duration at cast time. `ns:ReadPlayerAura`
  already exists and already returns aura data by spell ID; the debug tooling built this phase
  proves `aura.duration` reads correctly out of combat. The row would carry the short duration only
  as a fallback.
- **If the aura ID DIFFERS between versions** — the read has to find out *which* aura landed before
  it can ask for a duration, so the row needs both IDs, or the lookup needs to enumerate. More work,
  same shape.

**The degradation is acceptable either way, which is what makes this viable.** An aura read fails in
combat (measured: auras are secret there for a tainted caller) and succeeds out of it. The 15-minute
version is acquired by standing near an elemental or a ley line — an out-of-combat activity — so the
case that needs the read is the case where the read works. In combat the read fails and the fixed
short duration is used, which is the correct answer in combat anyway.

**This generalises beyond Skyborne.** Any future racial with a context-dependent duration gets fixed
by the same mechanism, which is an argument for doing it properly rather than special-casing two
rows.

### Undead — raceID 5 — COLLECTED 2026-09-24 (pre-tooling-upgrade, cooldowns missing)

| Racial | Cast spellID | Aura ID | Duration | Cooldown |
|---|---|---|---|---|
| Cannibalize | 20577 | **20578** | 10s (user-reported) | 120s (user-reported) |
| Will of the Forsaken | 7744 | **none — applies no aura** | n/a | 120s (user-reported) |

```lua
[5] = {
    { spellID = 20577, duration = 10, cooldown = 120, race = "Undead", fallbackLabel = "Cannibalize" },
    -- Will of the Forsaken: no aura, so no `duration` key. Needs the StartRacialProc guard first.
    { spellID = 7744, cooldown = 120, race = "Undead", fallbackLabel = "Will of the Forsaken" },
},
```

**This race answers both open questions, in opposite directions.**

**Cannibalize is the first confirmed cast/aura divergence** — 20577 casts, 20578 is the aura. It
does **not** require a table change, and the reason matters: `StartRacialProc`
(`Providers.lua`) *deliberately* carries no `aliveBuffs`, so a racial proc is never aura-cancelled.
It runs on the nominal duration alone, with cast-driven stack consumption as the only other input.
Nothing in the current code path reads a racial's aura ID, so adding an `auraID` field would put an
unverified value on every row to serve no consumer. Recorded here instead, where it costs nothing
and is ready if aura-cancellation is ever wanted for racials.

**Will of the Forsaken applies no aura at all**, which is the "cooldown-only racial" case. This one
*does* need an implementation decision before it can be entered, and it is a crash risk, not a
cosmetic gap:

- `StartRacialProc` does `proc.expiresAt = now + def.duration` unguarded. A row with
  `duration = nil` raises on the first cast of that racial.
- `ResolveRacial` copies `duration` straight through, and `RacialCooldownKeys` already requires
  `def.cooldown` — so the cooldown half works untouched.
- So the shape is probably: no `duration` key, a guard in `StartRacialProc` that returns nil rather
  than starting a buff proc, and the racial surfaces as a cooldown tile only. **Do not enter
  Will of the Forsaken into `RACIAL_SPELLS` before that guard exists.**

## Progress

| Race | raceID | Status |
|---|---|---|
| Orc | 2 | ✅ complete |
| Troll | 8 | ✅ complete |
| High Order Skyborne (A) | **95** | ⚠️ Walk on Air ready; Read Ley Line blocked on the conditional-duration question |
| Windshaper Skyborne (H) | **96** | ⚠️ Walk on Air ready; Skysight blocked on the conditional-duration question |
| Undead | 5 | ✅ data complete — both rows need the no-duration guard for Will of the Forsaken |
| Tauren | 6 | ⚠️ data complete; **Cultivation's 3 cast IDs need a decision** |
| Gnome | 7 | ✅ complete — **and corrected the table: Eureka! is 120s, not 180s** |
| Human | 1 | ✅ data complete — Will to Survive needs the no-duration guard |
| Dwarf | 3 | ✅ Stoneform ready; Find Treasure is a pure toggle and stays out of the table |
| Night Elf | 4 | ✅ data complete — Shadowmeld settled by D-1/D-6 (indefinite buff tile + its 10s cooldown tile) |

**The retail race list is not the Forever race list, and the IDs are not contiguous.** Skyborne is
Forever-only at **raceID 96**, far outside the 1-11 block the classic races occupy. So the rows above
cannot be assumed to be the whole set, nothing can be inferred from an ID's neighbours, and an
unseen race cannot be guessed at. The collection is finished when the user says the roster is
covered — not when the familiar eight are filled.

~~**Outstanding roster question: does the Alliance have a Skyborne counterpart?**~~ **ANSWERED —
yes, raceID 95, and it is not a copy.** Two Skyborne races sharing one racial and differing on the
other. The general lesson for the rest of the roster: a Forever race that looks like a faction
variant still needs its own collection pass, because the IDs differ *and* the contents may.

Each uncollected race needs one character, one `/tbt debug`, both racials.

### Why four cooldowns went missing — three separate tooling defects, all now fixed

**All four values were supplied directly by the user on 2026-09-24** (Will to Survive 180, War Stomp
120, Will of the Forsaken 120, Cannibalize 120), so no re-log is needed and **the data set is
complete**. Kept because the pattern is the lesson, and because these four rows are user-reported
rather than tool-read — worth knowing if one is ever disputed.

Each gap had a different cause, and each fix narrowed the hole rather than closing it, so the next
race found what was left.

| Was missing | Cause | Fixed by |
|---|---|---|
| Undead — **both** | Log taken before the duration/cooldown capture existed at all (user: "I did the undead one before the reload") | already fixed before the next race |
| Tauren — War Stomp | No aura, and the cooldown printed **only as part of the `AURA GAINED` line** — so a racial with no aura printed nothing | the `NO AURA` line |
| Human — Will to Survive | No aura **and** no readable cooldown at 0.35s; the `NO AURA` line was gated on a *real* cooldown, so it fell through both | once-per-spell dedupe, no cooldown gate |
| Tauren — Cultivation | Read back as `gcd?`; the real value is an hour | nothing to fix — `gcd?` is correct and unresolvable |

The first three were all the same mistake in different clothes: **a condition on whether a line is
worth printing, applied to a collection tool whose job is to never be silent.** The current rule has
no such condition — one line per distinct spell per session, whatever it contains.

Gnome is worth a re-log for the same reason orc was: Eureka! is the only `maxStacks` racial known,
and whether Forever gave gnome a second racial is unknown — every race checked so far has two.

## Decisions — user, 2026-09-24

### D-1. Shadowmeld: aura-cancelled, plus an instant clear on entering combat

Resolves open question 8. Option 2 from the Night Elf section, with a combat clause added:

- Start the proc on cast, as every racial does.
- **Clear it when the aura is lost.** The machinery exists — `ScanActiveTimersForCancellation`
  (`BuffEngine.lua:637`) ends any proc whose `aliveBuffs` have gone absent, so this is an
  `aliveBuffs = { 20580 }` assignment, not a new mechanism.
- **Clear it immediately on entering combat.** Aura reads are secret in combat for a tainted caller,
  so the cancellation scan cannot see the aura drop there — and Shadowmeld breaks on almost any
  combat action anyway. Clearing on `PLAYER_REGEN_DISABLED` is both correct and the only thing
  available.

The nominal duration becomes a backstop only; the aura decides.

### D-2. Plainsrunning: IN scope, same mechanism as Shadowmeld

Reverses the earlier "stays out for now". Same shape — visible out of combat, gone in combat, ended
by the aura going absent.

**One structural difference to solve, and it is not cosmetic: Plainsrunning has no cast.** Every
existing racial proc starts from `UNIT_SPELLCAST_SUCCEEDED`, and this is a passive that is simply
*present* out of combat. So it needs an aura-driven start — the proc begins when the aura is first
seen rather than when a spell is cast. `UNIT_AURA` is already routed through provider dispatch
(`BuffEngine.lua:695`), so the event is available; what is new is a racial that begins from it.

### D-3. Skyborne conditional duration: assume short, correct upward out of combat

Resolves open question 4, for both factions.

- Always start on the **short** duration (Elemental Blessing 30s, Energized 15s). A racial that
  under-runs is recoverable; one that hangs for 14 minutes after the buff is gone is not.
- **Out of combat, read the aura's real duration and correct to it** when the long version is
  detectable. Degrades exactly right: the read fails in combat and works out of it, and the
  15-minute version is acquired out of combat by standing near an elemental or a ley line.
- The user is still testing whether the aura ID differs between versions. It no longer *blocks* —
  the short duration ships either way — it only decides whether the correction looks up one aura ID
  or two.

### D-4. Every racial becomes its own race-gated tracker

**The biggest change in the phase, and it replaces the two-slot model entirely.** Today
`RACIAL_KEYS = { "racial", "racial2" }` — two generic slots that resolve to whatever the current
character's race has. Instead:

- **One entry per racial**, keyed distinctly, the way `item:<itemID>` keys work today.
- **Visible only to its own race.** A troll sees Berserking and Rapid Regeneration in Suggested,
  under both Buffs and Cooldowns. An orc sees the two orc racials and **no trace of the troll ones**
  — not in Suggested, not in any container.
- **Placement is account-wide and persists per racial.** Move Berserking to a container on one
  troll, and every other troll finds it in that container. This follows from the existing
  account-wide `TerribleBuffTrackerDB` rather than needing anything new.
- **Once tracked, it leaves Suggested** — exactly the behaviour `item:` keys already have
  (ITEM-02), so the pattern is established rather than invented.

Consequences to design around, which the two-slot model did not have:
- A **key format** is needed. `item:<itemID>`'s precedent suggests `racial:<spellID>`.
- **Race-gating must apply at render time, not just in Suggested**, or an orc would see troll
  racials sitting in their containers.
- **Migration**: existing `racial` and `racial2` database entries have to become the new per-racial
  keys, or players lose their placements.
- **RACE-09 may become obsolete.** Its "not yet supported" tooltip names the supported races; with
  every collected race implemented there may be nothing left to say.

### D-5. Cultivation triggers on 20552 only, no fallbacks

Resolves open question 5. The row names **20552** and nothing else; 1312643 and 1312650 are
documented in the Tauren section but not wired up. No `altTriggers` list, no set matching.

Consequence to accept knowingly: if a press ever reports one of the other two IDs, that press starts
no cooldown tracker. Chosen deliberately over a set, which would have been guessing at a mechanism
nobody has characterised — and over more testing, which was not worth the time for a one-hour
gathering cooldown.

### D-6. Find Treasure and Shadowmeld: indefinite buff tile; Shadowmeld also keeps its cooldown

Resolves open questions 8 and 9 together. **Revised 2026-09-24** — an earlier version of this
decision dropped Shadowmeld's cooldown tile too; the user reversed that, and the reversal is right:
the cooldown exists, and "probably not used in practice" is a reason to expect the tile to sit idle,
not a reason to withhold it.

Both get **a buff tile that renders with no countdown**, because neither has a duration to count.
They differ on the cooldown tile, and only because the data differs:

| | Buff tile | Cooldown tile |
|---|---|---|
| Shadowmeld | yes, indefinite | **yes — `cooldown = 10`**, and `combatCooldown = 120` (F-1) |
| Find Treasure | yes, indefinite | **no — it genuinely has no cooldown** |

So there is no special case here at all: both rows simply carry what they have, and
`RacialCooldownKeys` already emits a cooldown key only for a def with a `cooldown`. Find Treasure's
missing tile falls out of the data rather than out of a rule.

Lifecycle for both: **assume on from the trigger, and set false only when an aura read positively
says it is missing** — reusing the out-of-combat cancellation TBT already does
(`ScanActiveTimersForCancellation`, `BuffEngine.lua:637`), which never concludes "absent" from an
unreadable result. Shadowmeld additionally clears on entering combat (D-1); Find Treasure does not,
since it survives combat.

Implementation note, because the existing render path does not do this today: a proc with **no
duration and no expiry** is a new shape. Every current tile counts down from `expiresAt`. These two
need a tile that shows as simply *on*, indefinitely, until something clears it.

### D-7. RACE-09 is obsolete — closed, not implemented

Confirmed with the user, 2026-09-24. RACE-09 asked the "not yet supported" tooltip to name the
supported races instead of its hardcoded "Orc, gnome and troll" line. **D-4 removes the tile that
message lives on.** With one entry per racial, each visible only to its own race, there is no
generic racial slot to occupy — a race with no entries in the table simply contributes no
suggestions, exactly as a character with no consumables contributes no item suggestions.

So the requirement is not deferred or descoped; **its subject no longer exists.** Two constants go
with it: `RACIAL_SUPPORTED_LINES` and `RACIAL_UNSUPPORTED_LINES` (`Providers.lua:814-819`) become
dead code.

Accepted consequence: a future Forever race sees **no racial tile and no explanation**. The user's
call, and consistent with the rest of the addon — nothing else in TBT announces what it cannot yet
do either.

## Post-decision findings — raised during Phase 49 execution

### F-1. Shadowmeld's cooldown is conditional on combat: 10s out, **2 minutes in**

Reported by the user 2026-09-25, read from the ability's own tooltip: *"Using this ability in combat
discourages enemies from attacking you, but increases the cooldown to 2 min."* So Shadowmeld is a
threat drop in combat and a stealth out of it, with a 12x cooldown difference between the two.

**RESOLVED 2026-09-25 — `combatCooldown = 120` on the row, plus `ns:ConditionalCooldown`.**

**The first investigation of this was wrong, and the correction is the useful part of the entry.**
It concluded this was "a label-and-seed defect, not a tracking defect", on the grounds that a
cooldown tile renders from `C_Spell.GetSpellCooldownDuration` — the live game handle — which already
knows which of the two cooldowns applies, so the sweep would be right in both cases with no change
at all.

It is not. `ApplyCooldownHandle` does drive the sweep from the live handle, but it is **never
reached for a tracker that carries a duration**. `ApplyCooldownSlot` calls `ApplyUserCooldown`
first, and that function owns the icon outright and returns `true` whenever `entry.duration` is a
positive number (`Display.lua:1254`, and the precedence comment at `:1590`). That is the deliberate
reversal of CD-02 made on 2026-09-22: *a typed duration outranks the game's own handle*. A racial
cooldown tile inherits its duration from `RACIAL_SPELLS` via `ns:RacialCooldownSeed`, so it inherits
that precedence too, and the in-combat tile ran the ten-second number while the ability had nearly
two minutes left. The user reported exactly that after the Phase 49 Alliance gate pass.

The reason the first pass got it wrong is worth naming: it found the function that *can* read the
live handle and stopped, without checking whether anything upstream gets there first. `StartRacialProc`
carried a comment asserting the same thing — *"its cooldown tile still fires, because that is a
separate tracker reading the live game handle, which already knows the longer in-combat cooldown
without being told"* — and that comment is what made the claim look already-verified. It has been
corrected in place.

**The fix.** A one-cast override, written beside the start time by the same dispatcher:

- `combatCooldown` — a new optional `RACIAL_SPELLS` field, set to `120` on Shadowmeld and on nothing
  else. `cooldown = 10` stays exactly as it was and remains what the tile seeds and previews from,
  so the label-and-seed observation above is still true and still the out-of-combat truth.
- `ns.cooldownOverrides` (`Core.lua`) — keyed exactly as `ns.cooldownStarts` is, written on **every**
  cooldown start, to the override or to `nil`. A cast under ordinary conditions erases the previous
  cast's exception rather than inheriting it. Runtime-only, like `ns.cooldownStarts`.
- `ns:CooldownDuration(key, entry)` — the single reconciliation point, consumed by both
  `ns:IsCooldownRunning` and `ApplyUserCooldown`, so "how long is this cooldown" keeps having one
  answer.
- `ns:ConditionalCooldown(spellID)` — the lookup, on `ns` rather than a file-local because its caller
  is declared above it (the upvalue-order trap this project has now hit five times).

`entry.duration` is deliberately **not** rewritten per cast: it is one persisted number, it is what
the player sees and may have typed, and flickering it between two values would make a user-visible
setting unstable.

**Contrast with the Skyborne conditional duration (D-3), because the shapes look alike and are not.**
That one needs an aura read that is *secret in combat*, which is why it degrades to the short value.
This one is decided by `InCombatLockdown()` — a plain, always-readable boolean, with no secrecy
question anywhere near it, and the same signal `StartRacialProc` already uses to suppress
Shadowmeld's in-combat buff tile, so the two cannot disagree about what kind of cast it was.

**Still to test (user, later):** whether the in-combat threat drop applies an aura of its own. If it
does, it may be separable from the stealth version; if it does not, `InCombatLockdown()` at cast time
is the only discriminator — and is sufficient.

### F-2. Eureka!'s charges are spent by different ability types per CLASS — priests were broken

**RESOLVED 2026-09-25: the harmful test stays for every class and is skipped for PRIESTS only.**
The discussion this was held open for happened; see the resolution at the end of the section.

Eureka! (gnome, 1259817, 3 stacks) consumes a charge on the next 3 qualifying casts, and what
qualifies depends on the player's class:

| Class | Spends a charge on | Resource reduced |
|---|---|---|
| Rogue | next 3 **damaging** abilities | Energy |
| Mage, Warlock | next 3 **damaging** abilities | Mana |
| Warrior | next 3 **damaging** abilities | Rage |
| **Priest** | next 3 damaging **or HEALING** abilities | Mana |

**The current predicate gets the priest case wrong, and the mechanism is already in the code.**
`CastSpendsStack` (`Providers.lua:1576`) returns **false** — does not spend — when
`IsSpellHarmful(spellID)` is `false`. So a heal never decrements the stack. For four of the five
classes that is exactly right; for a priest it means the tile will sit at 3 charges through a
healing rotation that is really burning them.

Note the shape of the fix is narrow: the predicate already exists, already handles secret values
correctly, and already excludes auto-attacks. What it lacks is a class condition — for `PRIEST`,
a helpful cast must also qualify.

**A second, less certain imprecision worth raising in the same conversation:** "damaging" and
`IsSpellHarmful` are not synonyms. A harmful spell that deals no damage — a pure snare, a debuff
application — reads `harmful == true` and would spend a charge under the current test even though
the tooltip says *damaging*. That may already be over-counting for every class, not just priests.
Unlike the priest gap, this is inferred from the API's meaning rather than observed in game, so it
needs a test before it is treated as real.

#### Resolution — 2026-09-25

**The harmful test stays for every class and is skipped for priests only.** `CastSpendsStack` gates
`IsSpellHarmful` behind `not PlayerIsPriest()`; everything else about it — the auto-attack
exclusion, the unknown-qualifies rule, the `issecretvalue`-before-comparison ordering — is
unchanged.

The user's question was *"they are the only one with stack decrease on no harm ability, right? if so,
for that just make it always decrease on any spell."* **"They" is priests**, and the instruction
scopes to them: *for priests*, spend on anything.

**It was first implemented as a global removal, which was wrong, and the misreading is worth
recording because it was not a careless one.** "They" was read as *Eureka! among the racials*, which
turned the question into "is Eureka! the only stacking racial" — a question with a true answer that
is also verifiable in the code, so the verification came back clean and confirmed the wrong reading.
`maxStacks` really is on one row only. The check passed and the instruction was still misread. The
user corrected it the same day: *"never said to fully remove IsSpellHarmful, it should be there for
all Eureka! checks but be ignored for priests gnomes."* **A verification that confirms your reading
of an instruction is not evidence that the reading was right.**

That blast-radius finding is still true and still useful, just not load-bearing for this decision:
`maxStacks` is set on exactly one row of `RACIAL_SPELLS` (gnome Eureka!, 1259817),
`ConsumeRacialStack` only reaches a proc that has stacks, and the granting cast is matched and
returned before `CastSpendsStack` is called — so this predicate governs one ability and can never
spend a stack on itself.

**The class read.** `UnitClass("player")`'s second return, memoised sticky-on-readable exactly like
`racialRaceIDMemo` — a class cannot change mid-session, so a real answer is safe forever, but an
early unreadable read must not poison the memo. Unreadable *this call* returns `true` (treat as
priest), which follows the same unknown-qualifies rule the harmful test itself follows: over-consuming
ends the tracker early, under-consuming leaves a buff on screen the player no longer has.

**The second imprecision above is NOT settled by this** — the earlier write-up claimed it was, on the
strength of the global removal. "Harmful" and "damaging" are still not synonyms, so a pure snare or a
debuff application still over-counts for rogue, mage, warlock and warrior. That remains inferred from
the API's meaning rather than observed, and still needs a test before it is treated as real.

**Verification status — half tested, and the tested half is the one that regressed.**

| Branch | Status |
|---|---|
| Non-priest (`IsSpellHarmful` applies) | **PASSED** — gnome **mage**, in game, 2026-09-25 |
| Priest (gate skipped, heals spend) | **UNTESTED this release**, by user decision |

The mage run is not a formality. The global removal that briefly shipped broke exactly this branch —
every non-harmful cast spent a stack on all five classes — so a gnome mage behaving correctly again
is direct evidence the restored gate is wired right. What it cannot exercise is `PlayerIsPriest()`
returning true, which needs a gnome priest.

**If the priest branch is ever tested, the thing to watch is a HEAL spending a stack** — that is the
whole of the change. A damaging cast spending one proves nothing, since it would spend under either
version.

### F-3. Where a racial's aura ID differs from its cast ID, show the AURA's icon — not implemented

User decision, 2026-09-25, given as a standing allowance rather than a bug report: *"in cases where
aura and skill id doesn't match we're fully fine with showing the aura icon instead of skill."*

Three rows are affected, and they are exactly the three that already carry an explicit `auraID`:

| Racial | Cast ID | Aura ID |
|---|---|---|
| Cannibalize (undead) | 20577 | 20578 |
| Read Ley Line (Alliance Skyborne) | 1259705 | 1270842 |
| Skysight (Horde Skyborne) | 1259686 | 1259688 |

**The data is already there; only the icon resolution is not.** `ns:RacialDefsForPlayer` copies
`auraID` onto every resolved def, so nothing has to be collected or re-read in game.

**It is the ICON only, not the label.** `fallbackLabel` stays the CAST name on all three rows by the
rule already recorded above — that is what the player pressed, and what the tooltip resolves from.
The user confirmed separately that the label was never the problem: *"label was never seen in game,
the tooltip is the skill's tooltip so it has always been right."*

**Why it was not folded into the Phase 49 fixes:** it touches icon resolution (`ApplyCachedIcon` /
`ns:GetSpellIcon`) rather than the racial table or the proc lifecycle, so it shares no code with any
of the bug fixes that followed the gate pass. Left as its own bounded task rather than smuggled in.

## Open questions

1. ~~**Does any race have a cast ID that differs from its aura ID?**~~ **ANSWERED — yes, undead
   Cannibalize (20577 cast / 20578 aura).** Three rows diverge in the end — Cannibalize, Read Ley
   Line and Skysight — and all three carry an explicit `auraID`.

   **The original answer here is superseded and the reason matters.** It read: *"Resolved without a
   table change: nothing reads a racial's aura ID, because `StartRacialProc` deliberately carries no
   `aliveBuffs` and racial procs are never aura-cancelled... Revisit only if racials ever gain
   aura-driven cancellation."* Racials gained exactly that on 2026-09-25 — every racial buff proc is
   now aura-cancelled unconditionally (see the `RACIAL_SPELLS` header). `auraID` is therefore
   load-bearing on all three rows, and widening the cancellation **without** it would have cancelled
   those three instantly, since a read for the cast ID correctly reports no such aura. That was
   verified before the change landed. The remaining consumer is F-3's icon resolution.
2. ~~**Do any racials apply no aura at all?**~~ **ANSWERED — yes, undead Will of the Forsaken.**
   This one *does* need work before it can be entered: `StartRacialProc` does
   `now + def.duration` unguarded, so a `duration = nil` row raises on first cast. See the undead
   section. **This is the one blocking implementation task the collection has surfaced so far.**
3. **RACE-09's supported-race list.** `RACIAL_UNSUPPORTED_LINES` (`Providers.lua:815`) hardcodes
   "Orc, gnome and troll racials are implemented in this version." That string has to be derived
   from whatever `RACIAL_SPELLS` ends up holding, not hand-edited again, or it will drift the next
   time a race is added.
4. **The Skyborne conditional duration** — **BOTH** Skyborne races, confirmed: Elemental Blessing
   (30s → 15 min) and Energized (15s → 15 min). A designed race mechanic covering 2 of 10 races,
   and the only finding `RACIAL_SPELLS` cannot express at all. **The phase's main open design
   question** — full write-up in its own section, including why the user's aura-ID test decides the
   answer and why the in-combat degradation is acceptable.
5. **Cultivation's three cast spell IDs** (tauren) — 20552, 1312643, 1312650, all one ability.
   `OnTrigger` matches a single `def.spellID`, so this cannot be entered as-is. Detail in the
   Tauren section. Second finding the current `RACIAL_SPELLS` shape cannot express.
6. **Cooldown-only racials are now the majority, not the exception.** Will of the Forsaken, War
   Stomp and Cultivation all apply no trackable buff — three of the nine racials collected. The
   `StartRacialProc` nil-duration guard (question 2) is therefore not an edge case to bolt on at the
   end; it is load-bearing for a third of the data.
7. ~~**Is 180s the universal racial cooldown on Forever?**~~ **ANSWERED — no.** 120s and 180s both
   occur, and gnome's Eureka! was hand-entered as 180 when the client says 120. That near-miss is
   the argument against ever entering a cooldown from a pattern instead of a reading.
8. ~~**Permanent-duration racials** (night elf Shadowmeld)~~ **ANSWERED — D-1 and D-6.** An
   indefinite buff tile, ended by the aura going absent or by entering combat, *plus* its 10s
   cooldown tile. Neither of the two shapes I had proposed — cooldown-only, or a buff tile instead
   of a cooldown — was right: it gets both, because it has both.
9. **"State" racials are a family, not one-offs.** Tauren Plainsrunning (permanent, drops on
    entering combat) and dwarf Find Treasure (permanent, until toggled off) are both states rather
    than timers, and neither fits `RACIAL_SPELLS`. Both stay out of Phase 49. If a later phase wants
    them, it wants *one* mechanism for the family — a tile showing on/off driven by an aura or a
    combat event — rather than two special cases. Watch for more during the remaining collection.
10. **`gcd?` must never be auto-resolved.** Tauren Cultivation reads `gcd?` over a one-hour
    cooldown; dwarf Find Treasure reads `gcd?` over no cooldown at all. Same output, opposite
    truths, so no default ("assume short", "assume none") is safe. The reading means ask the user.
