# Buff Duration Probe — v0.5.3 kickoff

**Run:** 2026-10-22, Midnight retail build 70529 (interface 120105), Arcane Mage, out of combat.
**Harness:** `tools/TBTProbe/DurationProbe.lua` (`/tbtd scan`). Forever not probed — servers down; the
user decided to assume Forever behaves the same for everything this milestone touches.

## Question

Can TBT get a buff's **duration** from an aura ID alone, before the buff is ever up?

## Answer: no — there is no duration API

- No API returns a spell's or aura's duration as a number. The only static sources are the
  **spell description** (`C_Spell.GetSpellDescription`) and the **tooltip text**
  (`C_TooltipInfo.GetSpellByID` / `GetItemByID`). Both were readable (not secret) out of combat.
- Parsing that text is not a usable source:
  - English-only text, so any parser is locale-bound.
  - Several numbers per text are common (Ice Block "10 sec … 30 sec", Invisibility "3 sec … 20 sec …
    6 sec", Hearty Refreshment "20 sec … 10 seconds … 1 hour", Time Warp "40 sec … 10 min").
  - The spell tooltip mixes in cast times (Arcane Blast "1.8 sec", Reflecting Prism "1.6 sec").
  - Grammar escapes such as `1 |4hour:hrs;` (the probe's own naive parser read that as 4 hours).
  - Many entries carry no number at all (Blink, Potent Healing Potion, Ascendant Venomstone).
- The **live aura** gives the exact duration when it is up and readable
  (`GetPlayerAuraBySpellID` → Flask of the Shattered Sun `dur=3787.185`). TBT already uses this,
  through `ns:ReadPlayerAura`, to pre-fill the add dialog (`ns:SuggestedBuffDuration`).
- `C_Secrets.GetSpellAuraSecrecy` returned `ContextuallySecret` for every spell and item use-spell
  scanned — no `NeverSecret` among them.

## Side observations

- **Spell aura ID ≠ spell ID is common** (already known before this probe). The CDM's own
  `linkedSpellIDs` point elsewhere for Touch of the Magi (321507 → 210824, 1233452), Arcane Surge
  (365350 → 365362), Alter Time (342245 → 342246), Invisibility (66 → 32612, 110960).
- **Item aura parity was not observed live** — no item or spell was used during the run, so no
  cast → aura line was logged. Untested.
- Two different items can share one use-spell (Light's Potential 241308 and 241309 → 1236616;
  Flask of the Blood Knights 241324 and 241325 → 1235110), matching the catalogue's known
  "last writer wins" collision note.

## Decision taken from this (user, 2026-10-22)

The buff duration is **not** looked up. It is user-entered config on the Advanced tab: a checkbox
(off by default), an aura ID (pre-filled with the spell ID for spells, empty for items) and a
duration the user types. See `.planning/REQUIREMENTS.md`.
