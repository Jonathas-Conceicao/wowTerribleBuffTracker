# Phase 52 — Retail Full Review (v0.4.1)

**Build:** _record the retail build here_ (`/run print((select(4,GetBuildInfo())))`)
**Deployed:** `v0.4.0-…-dev` from `milestone/v0.4.1-item-tracking-forever-racials` @ `f05cfb9`
**Date:** 2026-09-25
**Status:** PASSED — 2026-09-26
**This is the milestone's last phase.**

Retail is not a re-run of the Forever sheet. Three things differ and they change what is worth
testing here:

| | Forever | Retail |
|---|---|---|
| Racial tiles | offered | **NOT offered** — `ns:RacialSuggestions` returns empty off-Forever, by design (RACE-06 deferred) |
| Pandemic highlight | no data at all — degrades silently | **real** — this is the only place PAND-01/02/03 can be tested |
| Dispel-border colours | nearly all grey `None` (most debuffs undispellable) | **visually distinct** — Magic / Bleed / Poison |

So retail owns the two checks Forever structurally cannot do: the pandemic highlight, and the
**stale-colour re-sort case** for Phase 50's new dirty check.

---

## R0 — Errors on, clean load

`/console scriptErrors 1` then `/reload`.

- [ ] No Lua error at load, none opening the Cooldown Manager

---

## R1 — Dispel border: the stale-colour case

**The check Forever cannot do, and the reason it matters most here.** Phase 50 changed
`ApplyDispelBorder` to skip re-issuing its atlas when the entry identity is unchanged. If that
identity check is wrong, a pooled widget reused for a *different* entry keeps the *previous* entry's
colour — and on retail that is visible, because the atlases differ.

- [ ] Track two debuffs with **different** dispel types (e.g. Magic and Bleed). Both border correctly
- [ ] Let one drop while the other stays. **The survivor keeps its own colour** — it does not inherit
      the other's
- [ ] Repeat with the other one dropping first
- [ ] Border still appears **in combat**, and clears when the debuff ends

A border showing the wrong colour after a container re-sorts is the specific failure this gate
exists for. It is also the only way Phase 50's SC3 gets a behavioural verdict.

---

## R2 — Pandemic highlight

**Only testable here.** Forever has no pandemic data at all.

- [ ] A merged entry inside its pandemic refresh window shows the highlight on TBT's **icon**
- [ ] Same on TBT's **bar**
- [ ] The highlight **clears** at window end without waiting on an unrelated aura event
- [ ] No Lua error, no stuck highlight

---

## R3 — Item tracking end to end

- [ ] Usable consumables offered in Suggested with icon and count
- [ ] Quest items, recipes, keys, trade goods and bandages **absent**
- [ ] Drag-to-track creates a working cooldown tracker
- [ ] Using an item fires the cooldown on every tracked item sharing it
- [ ] Count decrements on a landed use, not on a refused press
- [ ] `/reload` standing still, out of combat — **counts still show**

Retail's item-count and cooldown secrecy under combat restriction was never measured — both probes
behind this feature were Forever-only. Every read is guarded and degrades to "no count shown" rather
than erroring, so **if counts disappear under combat restriction that is expected behaviour, not a
failure.** A Lua error would be the failure.

---

## R4 — No racial tiles on retail

Reads backwards, like Forever's pandemic gate.

- [ ] **No racial tiles offered in Suggested**, under either tab

Retail's own Cooldown Manager already carries racials, so offering TBT's would duplicate them.
RACE-06 (retail racials) is deferred.

---

## R5 — Phase 50's racial refactor did not break NON-racial trackers

**Subtle, and easy to skip on retail because "racials aren't on retail."** They are not — but
`ns:IsRacialKeyVisible` still runs on retail, on **every tracked entry, every render pass**, and
Phase 50 added a memo inside it. It returns `true` for any key that is not racial-shaped, which on
retail is *all of them*. A bug in that memo breaks ordinary trackers here, not racials.

- [ ] Every tracker you have configured still renders — buffs, cooldowns, items, meta-trackers
- [ ] Nothing has silently disappeared from a container after a `/reload`

---

## R6 — No regression against v0.4.0's retail-verified behaviour

- [ ] All four containers render; Edit Mode drag and position persistence work
- [ ] Merge Mode mirrors CDM entries correctly
- [ ] Ordinary cooldown trackers fire; charges and the grey-while-on-cooldown state behave
- [ ] Trinket / Pot / Lust meta-trackers unchanged
- [ ] **Blizzard's own Cooldown Manager is untainted** after interacting with it — open it, change a
      setting, close it, keep playing. Taint surfaces later as the CDM quietly breaking, never as an
      immediate error

---

## Known and accepted — not findings

- **Backlog 999.9 — TBT taints `EditModeManagerFrame` on a container click in Edit Mode.** Found
  2026-09-25, left in place by user decision. If a taint error appears in an Edit Mode or action-bar
  frame during this pass, it is a **known candidate**, not a new finding. Other developers report
  controller-related code tainting broadly on this patch; both causes are live and neither is
  confirmed.
- **Divergent racials show the CAST's icon**, not the aura's — backlog 999.8. Not visible on retail.
- **Eureka! on a gnome priest** untested; **Skyborne second racials** on minimum duration (G8).
  Forever-only, not visible here.
- **A cooldown icon can read grey for a moment around the GCD** — backlog 999.5, never reliably
  reproducible, accepted.

---

## Results — PASSED, 2026-09-26

| Gate | Verdict | Notes |
|------|---------|-------|
| R0 | **PASS** | No Lua errors on retail at any point |
| R1 | **PASS (extended play, not a targeted A/B)** | Dispel indicator confirmed on retail. The stale-colour re-sort sub-check was not run as its own test — see below |
| R2 | **PASS** | Pandemic highlight confirmed on retail **in M+**, which is the strongest available environment for it: constant aura churn, real refresh windows, heavy container re-sorting. PAND-01/02/03 close here |
| R3 | **PASS** | Consumables confirmed end to end on retail |
| R4 | **PASS** | No racial tiles offered on retail; no error |
| R5 | **PASS** | No tracker disappeared — the race-gate memo's non-racial path (which on retail is every key) is sound |
| R6 | **PASS** | No regression; no CDM taint error reported after interacting with Blizzard's own Cooldown Manager |

**Reported by the user, 2026-09-26:** *"All racials tested as well as their cancelations; dispell
indicator on buffs tested on retail and forever; pandemic tested on retail on m+; and consumables
tested on both retail and forever. Everything is working well, no lua errors on either."*

### R1's stale-colour case — how it actually got covered

This sheet named R1 as the **only** place Phase 50's SC3 could get a behavioural verdict, because
retail is the only client where dispel atlases are visually distinct. The deliberate A/B — two
differently-bordered debuffs, let one drop, check the survivor's colour — was not run as a discrete
test.

What it got instead is an **M+ run**, which is arguably a harder test of the same property: debuffs
appear and expire continuously, containers re-sort constantly, and widgets are recycled between
entries far more aggressively than a two-debuff setup would produce. A border inheriting the wrong
colour would have been visible repeatedly. Nothing was reported.

Supporting evidence, not proof on its own: the Phase 50 code review traced all four
`ApplyDispelBorder` call sites and confirmed `_dispelID` is cleared on every not-shown transition,
so both pool resets reach it.

**Accepted as passing.** Recorded this way so the distinction between "exercised under load" and
"deliberately falsified" stays visible to a later reader.

### Two gates whose retail answer was genuinely unknown before this pass

- **R3 under combat restriction.** Both probes behind item tracking were Forever-only; retail's
  item-count and cooldown secrecy under restriction had never been measured. Every read is
  `issecretvalue`-guarded and degrades to "no count shown" rather than erroring — no error was
  reported, so the guards hold.
- **R2 at all.** Forever has no pandemic data, so until this run the highlight had only ever been
  confirmed on retail in isolated testing, never under raid/M+ load.
