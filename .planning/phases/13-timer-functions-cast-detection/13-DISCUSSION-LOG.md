# Phase 13: Timer Functions + Cast Detection - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-04-13
**Phase:** 13-timer-functions-cast-detection
**Areas discussed:** Cast routing, Shared-slot overwrite, DB entry ↔ timer linking, Timer label

---

## Cast Routing

| Option | Description | Selected |
|--------|-------------|----------|
| Only if meta-slot added | Matches lust pattern — timer only if user dragged trinket/pot to Bars/Buffs | ✓ |
| Always create timer | Wasteful; no display target without DB entry | |
| You decide | | |

---

## Shared-Slot Overwrite

| Option | Description | Selected |
|--------|-------------|----------|
| Iterate spell table | Loop TRINKET_SPELLS, delete matching active timers — no metadata | |
| Tag timer with meta-slot | Store metaSlot="trinket" on timer, scan activeTimers for match | ✓ |
| You decide | | |

---

## DB Entry ↔ Timer Linking

| Option | Description | Selected |
|--------|-------------|----------|
| Timer carries DB ref | Copy section/layoutOrder/label onto timer at creation. Fast, static for duration of timer. | ✓ |
| Display looks up by metaSlot | Always current if user moves slot mid-timer | |

**Notes:** User initially asked for elaboration on the question. After clarification, chose option A — mid-combat slot moves aren't a real concern.

---

## Timer Label

**User clarified:** tooltip should come from spellID's tooltip (matches active icon).

| Option | Description | Selected |
|--------|-------------|----------|
| Spell name | C_Spell.GetSpellInfo(spellID).name — actual proc name on the bar | ✓ |
| Generic slot label | "Trinket"/"Pot" | |
| You decide | | |

---

## Claude's Discretion

- OnSpellCastSucceeded internal structure (helper vs inline)
- Field ordering on timer object

## Deferred Ideas

- Icon resolution (Phase 14)
- Active icon switching (Phase 15)
