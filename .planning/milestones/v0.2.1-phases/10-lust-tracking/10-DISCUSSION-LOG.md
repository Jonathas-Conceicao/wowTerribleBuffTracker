# Phase 10: Lust Tracking - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 10-lust-tracking
**Areas discussed:** Lust data model, Debuff detection logic, CDM tab presentation, Drums support

---

## Lust Data Model — DB Key

| Option | Description | Selected |
|--------|-------------|----------|
| Special key ("lust") | String key in trackedBuffs, needs guards for numeric assumptions | ✓ |
| Sentinel spellID (-1) | Negative number as synthetic spellID | |
| Bloodlust spellID as canonical | Store under 2825 with metaBuff flag | |

**User's choice:** Special key "lust" with guards, documented where possible

---

## Lust Data Model — Pre-seeded vs User-enabled

| Option | Description | Selected |
|--------|-------------|----------|
| Pre-seeded, always present | Auto-created, can't delete | |
| User enables via Suggested | Appears in Suggested, drag to enable | ✓ |

**User's choice:** Use Suggested section properly. Suggested is a static catalog — drag copies on first use, moves on subsequent. Icon always stays in Suggested. Future-proof for more suggested buffs.
**Additional constraints from user:**
- Users can't drop INTO Suggested (not a valid drop target)
- Remove on once-suggested buff removes from DB only, stays in Suggested
- No "Remove" in Suggested right-click menu
- Right-click on Suggested offers: "Add to Bars" / "Add to Buffs"

---

## Lust Data Model — Coexistence

**User note:** Meta-buff does NOT lock out manual tracking of same spellIDs. trackedBuffs["lust"] and trackedBuffs[2825] can coexist independently.

---

## Debuff Detection Logic

| Option | Description | Selected |
|--------|-------------|----------|
| Track via addedAuras | Check addedAuras in UNIT_AURA payload for Sated-family spellIDs | ✓ |
| State flag approach | Track lustDebuffActive boolean, poll on each event | |
| You decide | Claude picks | |

**User's choice:** Use addedAuras from UNIT_AURA to detect newly applied debuffs only. Check each entry's spellId with issecretvalue() — skip secret entries individually. Match non-secret entries against known Sated-family debuff spellIDs. Trigger on new debuffs only, not existing ones.
**Additional info:** All lusts = 40s. Current season drums spellID = 1243972. Research must find all Sated debuff → lust spell mappings.

---

## CDM Tab Presentation — Gray Text

| Option | Description | Selected |
|--------|-------------|----------|
| Tooltip only | Gray line in tooltip on hover | ✓ |
| Below icon in section | Visual label below icon frame | |
| Both | Tooltip + below icon | |

**User's choice:** Tooltip only

---

## CDM Tab Presentation — Class Icon

| Option | Description | Selected |
|--------|-------------|----------|
| Runtime class detection | UnitClass('player') at load → pick class-specific icon | ✓ |
| You decide | Claude picks | |

**User's choice:** Runtime class detection
**Critical clarification from user:** CDM tab icon = player's class lust. Running timer icon = actual detected lust spell's icon (e.g., Shaman receiving Time Warp sees Time Warp icon on timer, not Bloodlust).

---

## Drums Support

| Option | Description | Selected |
|--------|-------------|----------|
| Same lust timer (40s) | Drums trigger same meta-buff timer | ✓ |
| Drums are separate | Own timer/icon | |

**User's choice:** Same 40s lust timer

---

## Claude's Discretion

None — all decisions made by user.

## Deferred Ideas

None
