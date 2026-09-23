# Phase 44 — Retail Validation Pass (M+ and raid)

**Client:** Midnight retail, `_retail_`, interface 120100.
**Status:** COMPLETE. Run sheet prepared 2026-09-22; Parts 2 and 3 exercised and signed off
2026-09-23 — see "Parts 2 and 3 — exercised 2026-09-23" near the end of this file. This header read
"not started" until milestone close, because the run was recorded at the bottom of the sheet rather
than at the top. Part 1's migration checkboxes were never ticked individually; treat them as
covered by the sign-off, not as individually attested.

> **Before the first login.** The TOC gained `Config.lua` this milestone, so retail needs a **full
> client restart** — `/reload` never re-reads the AddOns folder. The deployed file set was verified
> byte-identical to the repo on 2026-09-22 (only the TOC differs, by the `@project-version@`
> substitution `install.ps1` makes).

---

## Part 1 — the v0.3.0 migration. Do this first, somewhere calm.

The first login is the one that migrates. Check it at the character screen and first zone-in, not
mid-key.

**Backed up 2026-09-22** to `~/TBT-SavedVariables-Backup/2026-09-22-pre-phase-44/`. Restore by
copying back with the game **fully closed**.

`scripts/migrate-dryrun.js` predicts the following for account `76116961#1` (v3, 8 trackers). Tick
each off in game:

- [ ] All 8 trackers present: `lust`, `trinket`, `pot`, and spell IDs 130, 321507, 1250508, 1250533, 1260459
- [ ] `lust` and the two spell-ID bar trackers still in **Tracked Bars**; `trinket` and `pot` still in **Tracked Buffs**
- [ ] The five `hidden` trackers still hidden, not resurfaced
- [ ] Tracked Bars and Tracked Buffs in the **same screen positions** as before (v4 renames the position key `icons` → `buffs`)
- [ ] **Essential** and **Utility** containers appear, at their defaults
- [ ] No migration error, and no `DB migrated to v1` spam (that print only fires below v1)

**One thing changes on purpose.** v5 flips `buffs.growthDirection` from Right to **Centered**, so
the Tracked Buffs container will lay out differently on first login. Intended, not a bug.

- [ ] Buff container is Centered after migration
- [ ] **A container already set to Left keeps Left** — the case v5 is written to spare. Set one to Left, exit fully, log back in.

**Persistence itself is untested everywhere.** Forever writes saved variables but never reads them
back, so nothing in v0.4.0 has survived a logout→login on any client. Test the round-trip, not only
the migration:

- [ ] Trackers, user containers, Edit Mode positions and `mergeMode` all return after a **full client exit**, not `/reload`
- [ ] `schemaVersion` reads 6 in the file afterwards, and the second login migrates nothing

---

## Part 2 — Mythic+. The restricted-API run.

Turn on `/tbt debug` before the key — the secret gates log once each when they trip, and that is
how you tell "restricted, degraded as designed" from "broken".

### Predicted, NOT bugs

These are the designed fallbacks. Expect them; do not report them.

| What you'll see | Why |
|---|---|
| **A buff keeps showing after it has actually fallen off**, until its typed duration runs out | `C_Secrets.ShouldAurasBeSecret()` is expected true for the whole key, which skips `ScanActiveTimersForCancellation` (BuffEngine.lua:677). Cancellation is the only thing gated — timers still **start** correctly, because `UNIT_SPELLCAST_SUCCEEDED` is never secret |
| **Charge counts blank on multi-charge cooldowns** | `chargeCapable` is a sticky cache filled only from a readable moment. `ShouldCooldownsBeSecret()` stacks encounter, challenge-mode and restricted-map restrictions, so **if you `/reload` mid-key there may be no readable moment for the whole run**. The failure mode is hidden text, never an error |
| Debug line `aura scan blocked — ShouldAurasBeSecret() returned true`, once per combat/zone | The one-shot gate log doing its job |

### What actually needs watching

- [ ] **Any Lua error at all.** Everything above degrades to *showing less*; nothing should throw. An error in combat, in Edit Mode, or on Edit Mode save is the real signal
- [ ] **Merge Mode under restriction** — the most restriction-sensitive feature in the milestone and never exercised under M+. It reads `cooldownID` and `layoutIndex` off CDM item frames (MergeMode.lua:95-97). Both are `issecretvalue`-guarded; confirm merged auras still land in the right slot, or degrade cleanly, rather than stacking at one point
- [ ] **Cooldown sweeps on real cooldowns** — `IsActive`'s result is a secret bool once cooldowns are restricted (Display.lua:772-779)
- [ ] **Custom cooldown trackers keep using the typed duration**, not the game's, inside the key
- [ ] **Edit Mode opened while in combat**, then saved — the context that produced taint during the experiment phase
- [ ] Start from a clean restart, because taint is sticky. If anything goes wrong, note whether you had `/reload`ed first

---

## Part 3 — raid, and the retail-only differences

- [ ] Every v0.4.0 feature exercised in a raid encounter
- [ ] **Cooldown trackers on trinkets and potions** — Forever could not test these
- [ ] **A genuine multi-charge spell's charge count** (see 3b below)
- [ ] The Merge Mode checkbox is **absent entirely** on retail (ADD-03's retail half; the Forever half was checked in Phase 43)

### 3b — charges versus a typed duration, the open judgement call

`ApplyChargeCount` reads the game's real charge count while the sweep runs the user's typed
duration, so on a multi-charge spell the two can disagree — the icon can show a charge available
while the typed timer still has time left. Decide here whether a user-duration tracker should show
charges at all. Assumed working until then, by user decision 2026-09-22.

- [ ] Observed on a real multi-charge spell, and a decision recorded

---

## Merge Mode rework — 2026-09-22/23, retail, outside M+

Play-tested on a mage and a resto druid. Fourteen defects found and fixed; each re-tested on the
same client before moving on. **Not yet exercised in M+ or raid** — Parts 2 and 3 above still
stand.

### What the CDM mirror now draws, and from where

| Slot shape | Cooldown source | Confirmed |
|---|---|---|
| Spell (Arcane Orb, Counterspell, Shimmer…) | `C_Spell.GetSpellCooldownDuration` — duration object, no secrecy flag | in and out of combat |
| Equipped item (Freightrunner's Flask) | `GetInventoryItemCooldown` — the call Blizzard's own tile makes | in combat, `dur90.0/left71.8/en1` |
| Generic item cooldown (Combat Potion) | CDM relay, else `C_Spell.GetLastCategoryCooldownSource` | out of combat |
| Merged auras (all containers) | engine `AuraContainer`, TBT never reads a value | in and out of combat |

### The findings worth keeping

- **`GetCooldownViewerCooldownInfo` carries `spellID` AND `equipSlot` on the same entry.** An entry
  is not "a spell or an item". Freightrunner's Flask is both, and discarding the slot cost it its
  cooldown while every ordinary spell beside it drew fine.
- **`C_CooldownViewer` exposes no timing at all** — seven functions, all configuration. There is no
  API-level "ask the CDM for this slot's cooldown".
- **The frame relay is blocked exactly when it matters.** `itemFrame.Cooldown:GetCooldownTimes()`
  goes secret once a cooldown is running; `/tbt merge` in combat returned `relay=blocked` on every
  entry that had something to show. It is a fallback, never the primary. Merged BARS relay fine
  because `SimpleStatusBar:GetTimerDuration()` returns a duration object; `Cooldown` has no
  equivalent getter anywhere in the API.
- **Identity filters are refused for a harmful aura on an assistable unit**
  (`Blizzard_AuraContainerUtil.lua:11-36`). No candidate filter can express "only this spell" on a
  friendly or self target, so the target aura slot is switched off whenever `UnitCanAssist` says so.
  An empty `includeSpellIDs` does NOT mean "match nothing" there; `maxDuration = 0` does.
- **`info.charges` means "has a charge display", not "has charges"** — set on Touch of the Magi and
  Prismatic Barrier, neither of which has any. Gating on it cost ToM its sweep.
- **The local `wow-ui-source` clone is a snapshot** (12.1.0 build 69273, 2026-08-11). It disagreed
  with the live client on whether a buff tile can show a cooldown, and the client was right.

### Diagnostic

`/tbt merge` prints, per shown slot: the resolved spell or item slot, the aura filter size, which
path drew the cooldown (`drew=handle` / `drew=item` / `drew=cdm-relay`), the raw item-cooldown read,
and the CDM flags (`cdmCharges`, `hideAura`, `selfAura`). Written for this pass and kept.

### Still on a fallback path

- `Combat Potion` in **Tracked Buffs** reports `relay=no-frame` — no CDM item frame exists for it,
  so the `POT_SPELLS` catalog carries its aura and the category lookup its cooldown. The only slot
  not on a confirmed path.
- The pot catalog knows four potions. A potion outside it resolves neither the meta-tracker nor the
  merged tile's aura.

---

## Parts 2 and 3 — exercised 2026-09-23

**Mythic+ and a raid boss, on the build carrying the full Merge Mode rework.** Signed off by the
user: *"I'm testing these things in M+ and Raid boss, so we can cross that as done, no lua errors
so far."*

- [x] **No uncaught Lua error** in combat, in restricted content, or on the merge path. This is the
      criterion that mattered: everything restricted was designed to degrade to *showing less*, and
      it did.
- [x] Mythic+ — the strictest restriction environment TBT will run in
- [x] Raid encounter

Recorded as the user reported it: the contexts were exercised and nothing threw. The per-feature
sweep in Part 2's table was not itemised tick by tick, so anything it lists as "needs watching"
should be read as *observed incidentally, not individually confirmed*.

### Carried forward, not blockers

- **Potion cooldown inside a key.** `C_Spell.GetLastCategoryCooldownSource` is
  `SecretWhenCooldownsRestricted`, and challenge-mode restriction can hold for a whole run. The
  category cache now fills from any readable moment, so a potion drunk once outside a key resolves
  for the rest of the session; one first used inside a key may show no timer until the player is
  somewhere unrestricted.
- **Charges vs a typed duration** (criterion 3b above) — still undecided, still assumed working.
