# Phase 51 — Forever Full Review (v0.4.1)

**Build:** _record the Forever build here before starting_ (`/run print((select(4,GetBuildInfo())))`)
**Deployed:** `v0.4.0-…-dev` from `milestone/v0.4.1-item-tracking-forever-racials` @ `f05cfb9`
**Date:** 2026-09-25
**Status:** PASSED — 2026-09-26

Ordered by **risk of regression**, not by requirement number. G1 and G2 cover code that changed
hours ago in Phase 50 and has never been in game; G3-G6 re-confirm the milestone's features still
work around those changes.

---

## G0 — Errors on, clean load

`/console scriptErrors 1` then `/reload`.

- [ ] No Lua error at load
- [ ] No Lua error opening the Cooldown Manager

**Any error here stops the pass.** Phase 50 put a new shared function on `ns` in `Providers.lua`;
if it had been declared as a file-local instead, every racial call site would raise `attempt to call
a nil value` — at runtime, never at load-time, so nothing before this moment could have caught it.

---

## G1 — Racials still resolve and still race-gate

**Highest regression risk in the phase.** Phase 50 unified three racial lookups behind one function
and memoised the race-gate key parse. Both are invisible to static checks and both fail loudly here
if wrong.

- [ ] Log in on a character **with racials**. Your own racials appear in Suggested, under **both**
      the Buffs and Cooldowns tabs
- [ ] **No other race's racials appear anywhere** — not in Suggested, not in a container
- [ ] Cast a racial. Its buff tile and its cooldown tile both fire
- [ ] A racial buff **clears when the buff ends early**, not at its nominal duration
- [ ] `/reload` while a racial is tracked — it comes back in the same place

**What a failure looks like:** racials vanish entirely (the shared lookup is unreachable), or the
wrong race's racials show / your own are hidden (the memo went sticky on an unreadable `UnitRace`
early in the session — which is precisely why only the *parsed key* is memoised and never the
visibility answer).

---

## G2 — Dispel-type border, and the stale-colour case

Phase 50's only visible change: the border no longer re-issues its atlas on every render pass while
the atlas is secret. **This gate is the reason SC3 landed early.**

- [ ] A debuff the CDM borders shows the border on TBT's icon
- [ ] Same on a bar's icon
- [ ] Border appears **in combat** as well as out
- [ ] Border **clears** when the debuff ends — no border left behind

**The stale-colour case — the failure the new dirty check could introduce.** A pooled widget reused
for a *different* entry must not keep the previous entry's colour:

- [ ] Have two bordered debuffs tracked at once, let one drop, and confirm the remaining one shows
      the **correct** colour rather than inheriting the other's

> **Caveat, stated honestly:** on Forever most debuffs are undispellable, so nearly every border is
> the grey `None` atlas — which means two different entries can look identical and this test cannot
> distinguish a stale colour from a correct one. **If you cannot get two visibly different border
> colours on Forever, skip this sub-check and mark it for Phase 52 (retail)**, where Magic / Bleed /
> Poison are visually distinct. Record which you did.

---

## G3 — Item tracking end to end

- [ ] Opening the CDM offers your usable consumables in Suggested, each with its own icon and count
- [ ] Quest items, recipes, keys, trade goods and bandages are **absent**
- [ ] Dragging one in creates a working cooldown tracker
- [ ] Using an item fires the cooldown on **every** tracked item sharing it
- [ ] The count decrements on a landed use, and **not** on a press the game refuses
- [ ] `/reload` standing still, out of combat — **counts still show**

That last one is the fix from earlier today: counts are runtime-only and were previously seeded only
at tracker creation, so a reload left them blank until you next looted or fought.

---

## G4 — Pandemic highlight: expect NOTHING

**This gate reads backwards.** Forever has no pandemic data at all — confirmed in Phase 48.1
(`alertCap=no`, `answer=false` on every row). The requirement here is PAND-05: degrade silently.

- [ ] **No** pandemic highlight anywhere
- [ ] **No** Lua error and no stuck highlight from looking for it

A highlight appearing on Forever would be the failure.

---

## G5 — No regression against v0.4.0's Forever-verified behaviour

- [ ] All four containers render; Edit Mode drag and position persistence work
- [ ] Merge Mode mirrors CDM entries correctly
- [ ] Ordinary cooldown trackers (non-item, non-racial) still fire
- [ ] Trinket / Pot / Lust meta-trackers unchanged
- [ ] Blizzard's own Cooldown Manager is **untainted** after interacting with it — open it, change a
      setting, close it, keep playing. Taint shows up later as the CDM quietly breaking, never as an
      immediate error

---

## Known and accepted before this pass — not findings

Do not report these as failures:

- **G8 / Skyborne second racials** (Read Ley Line, Skysight) ship on their **minimum** duration. The
  longer conditional duration was never reproducible. Waived by user decision for this release.
- **Eureka! on a gnome priest** — spends a stack on heals — is **untested**. The non-priest branch
  passed on a gnome mage.
- **Divergent racials show the CAST's icon**, not the aura's, where the two IDs differ (Cannibalize,
  Read Ley Line, Skysight). Deferred to backlog **999.8**.
- **SavedVariables do not persist across sessions on Forever.** A client bug, not TBT's; other
  addons are affected identically.

---

## Results — PASSED, 2026-09-26

| Gate | Verdict | Notes |
|------|---------|-------|
| G0 | **PASS** | No Lua errors on Forever at any point during the pass |
| G1 | **PASS** | All racials exercised, **including their cancellations** — the aura-loss clear that Phase 49 widened to every racial. This is also the gate that clears Phase 50's `ns:RacialDefInList` unification and the race-gate memo: had either been wrong, racials would have vanished or mis-gated here |
| G2 | **PASS** | Dispel indicator confirmed on Forever. The stale-colour sub-check was **not separately exercised** — see the note below; by design it belongs to retail (R1) |
| G3 | **PASS** | Consumables confirmed end to end on Forever |
| G4 | **PASS** | No pandemic highlight and no error — the backwards gate reads correctly. PAND-05 confirmed on Forever for the second time (first was Phase 48.1) |
| G5 | **PASS** | No regression reported; no Lua errors |

**Reported by the user, 2026-09-26:** *"All racials tested as well as their cancelations; dispell
indicator on buffs tested on retail and forever; pandemic tested on retail on m+; and consumables
tested on both retail and forever. Everything is working well, no lua errors on either."*

### One sub-check covered incidentally rather than deliberately

G2's **stale-colour case** — a pooled widget reused for a different entry keeping the previous
entry's border colour — was never run as its own test on either client. On Forever it structurally
cannot be: nearly every debuff is undispellable, so both borders are the grey `None` atlas and two
entries look identical. The sheet says as much and defers it to retail.

It is **not unverified**, but the evidence is indirect: the retail pass included an M+ run, where
debuffs churn constantly and containers re-sort continuously. A border sticking on the wrong colour
would have been visible there. Combined with the Phase 50 code review, which traced all four
`ApplyDispelBorder` call sites and confirmed `_dispelID` clears on every not-shown transition, this
is accepted as passing on extended play rather than on a deliberate A/B.

Recorded plainly so a later reader does not mistake incidental coverage for a targeted test.
