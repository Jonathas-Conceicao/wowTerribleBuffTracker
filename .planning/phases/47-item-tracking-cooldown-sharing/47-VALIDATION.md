---
phase: 47
slug: item-tracking-cooldown-sharing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-24
---

# Phase 47 — Validation Strategy

> Per-phase validation contract. `47-RESEARCH.md` § Validation Architecture holds the reasoning;
> this file is the contract the executor and verifier are held to.

---

## Test Infrastructure

**No test runner exists, and none is planned.** This is a World of Warcraft addon: the only runtime
is the game client. `.planning/ROADMAP.md` records the position plainly — "No test suite exists. No
build manifest, no `luacheck`, no automated regression gate."

| Property | Value |
|----------|-------|
| **Framework** | none |
| **Config file** | none |
| **Quick run command** | `stylua .` (formatting gate, not a test) |
| **Full suite command** | none — the phase gate is the in-game check list below |
| **Estimated runtime** | static: seconds. In-game: user-driven, requires real play sequences |

Do not invent a test command. A gate that never runs is worse than no gate.

**Scope every gate to the diff, not to the file.** Corrected 2026-09-24 after S3 as originally
written (a whole-file grep over `Core.lua`) turned out to be unsatisfiable by any correct
implementation: `Core.lua:565-576` holds Phase 37's locked, explicitly-sanctioned runtime flavour
check, which predates this phase entirely. The property worth asserting is "this phase introduced
no flavour check", not "this file contains none". The same mistake produced a broken ordering gate
in Phase 46 (a whole-file `grep -n` matched unrelated pre-existing code hundreds of lines away) —
twice now, so treat a whole-file grep over a long-lived file as a defect by default. `Core.lua`'s
protected debug cast/item log is guarded the same way, diff-scoped, because that block legitimately
contains the very `hooksecurefunc` token a naive whole-file gate would forbid.

---

## Static Assertions

| ID | Check | Method | Proves |
|----|-------|--------|--------|
| S1 | stylua clean | `stylua .` then `git diff --stat` empty | No formatting drift, no invisible CRLF→LF reflow |
| S2 | Line endings held | `git ls-files --eol <touched files>` reports `w/crlf` | `git diff` cannot see a reflow; only this can |
| S3 | No flavour check **introduced** | `test "$(git diff <base>..HEAD -- <changed files> \| grep '^+' \| grep -cE 'buildInterfaceVersion\|GetBuildInfo\|wow_classic\|classicVersion')" = "0"` | One code path, both flavours |
| S4 | Secret guard ordering | Every new `GetItemCooldown` / `GetItemCount` read has `issecretvalue(v)` before `type(v)` — and before any truthiness test | The locked rule. Phase 46 has the worked example at `Providers.lua:970`: a secret non-nil value is truthy under a naive `if v then` |
| S5 | Provider returns nil | `ItemProviderMixin:OnTrigger` has no truthy return on any path | A truthy return writes into `ns.activeTimers` and creates a phantom buff timer. `ns:DispatchEventToProviders` is the single writer and does not validate |
| S6 | Icon override set | `AddSuggestedTracker`'s `item:` branch sets `entry.iconOverride` | An item entry carries no `spellID`, so `ApplyCachedIcon` cannot resolve one — without this the tile shows a permanent question mark |
| S7 | All `trackerType` gates widened | Grep `trackerType ==` across `Display.lua` and `Core.lua`; every hit checked against the three known sites | A missed gate makes the tracker silently invisible rather than visibly broken |
| S8 | Tracked count is its own store | Source read: the tracked tile's count does NOT read `ns:ItemCatalogueCount` | That table is wiped and refilled from a live bag walk and has no entry for a zero-stock item — reusing it silently breaks ITEM-09 |
| S9 | Count floor | Source read: the decrement cannot take a count below zero | |
| S10 | Debug log untouched | `git diff Core.lua` shows no edit inside the `pendingItemCasts` / `LogPlayerCast` / `LogItemUse` block | That is a separate feature the user asked for; CONTEXT.md protects it explicitly |
| S11 | No hooks on the production path | `ItemProviderMixin` uses `UNIT_SPELLCAST_SUCCEEDED` only; no new `hooksecurefunc` added | The user's locked decision. The four use-hooks fire on the press, not the use |

---

## In-Game Human Checks (phase gate)

The only route to this phase's six requirements. **Checks G2 and G5 cannot be shortened** — they
require real play sequences, not a glance at the UI.

| ID | Requirement | Check | Pass condition |
|----|-------------|-------|----------------|
| G1 | ITEM-02, ITEM-04 | Drag a Suggested consumable into a container | A tile appears showing the item's own icon (not a question mark); the item leaves Suggested; it files under **Cooldowns**, not Buffs |
| G2 | ITEM-05 | Track **two** potions that share a cooldown group (on Forever, any two of Minor Healing / Mana / Rejuvenation — measured sharing one 120s group in 999.6). Drink **one** | The **other** tile — never used — starts its sweep at the same moment with the same remaining time. This is the single behaviour no static read can infer |
| G3 | ITEM-06 | With a tracked item already on cooldown, try to use it again (a refused press) | The count does **not** decrease. Then use a different, off-cooldown tracked item: its count decreases by exactly 1 |
| G4 | ITEM-07 | Enter combat, drink a tracked potion, then loot more of the same item mid-fight. Leave combat | The displayed count corrects to the true bag count |
| G5 | ITEM-09 | Drink a tracked item down to its last, then drink the last one so the stack leaves the bags. Confirm in the Blizzard bag UI that it is genuinely gone | The TBT tile **remains visible**, its sweep runs correctly through to expiry, and it shows `0` — it does not disappear and does not error |
| G6 | ITEM-10 (Phase 52) | Repeat G1–G5 on Midnight retail | Identical behaviour out of combat. If a value comes back secret in combat/M+/raid, the tile keeps its last stamp and degrades rather than erroring |

G6 is scheduled in Phase 52, not here. Retail secrecy for `GetItemCooldown` / `GetItemCount` is
unmeasured — both probe runs behind this design were Forever-only. The `issecretvalue`-first guards
plus the stamp-at-use fallback are what make shipping it safe ahead of the answer.

---

## Decisions Made Here

**Seed the cooldown at tracker creation.** `47-RESEARCH.md` Open Question 1 asked whether dragging
an item that is *already* on cooldown should show that cooldown immediately. It should: read
`C_Item.GetItemCooldown(itemID)` once at creation and stamp it. Without this, dragging a potion you
drank thirty seconds ago produces a tile that looks off-cooldown until the next use — visibly wrong,
and wrong in the direction that matters (it would tell you the potion is ready when it is not). The
cost is one API call at drop time, which is not a hot path. Guarded like every other read; where it
returns nothing, the tile simply starts un-stamped, which is today's behaviour.

The other two open questions stay closed by user decision and need no action here: whether
`GetItemCooldown` answers at zero count (moot — the stamp design covers it), and retail secrecy
(Phase 52).

---

## Per-Task Verification Map

Filled by the planner — one row per task, naming its static gates and which in-game check it
ultimately answers.

| Task ID | Plan | Wave | Requirement | Static gate | In-game gate | Status |
|---------|------|------|-------------|-------------|--------------|--------|
| 47-01 T1 | 01 | 1 | ITEM-06 | S1, S2, S10, S11 | G3 | planned |
| 47-01 T2 | 01 | 1 | ITEM-05, ITEM-07, ITEM-09 | S1, S2, S3, S4, S8, S9, S10 | G2, G4, G5 | planned |
| 47-01 T3 | 01 | 1 | ITEM-05, ITEM-06, ITEM-09 | S1, S2, S5, S9, S10, S11 | G2, G3, G5 | planned |
| 47-02 T1 | 02 | 2 | ITEM-04, ITEM-07 | S1, S2, S3, S7 (Core.lua half), S10, S11 | G1, G4 | planned |
| 47-02 T2 | 02 | 2 | ITEM-02, ITEM-04 | S1, S2, S3, S6, S11 | G1 | planned |
| 47-03 T1 | 03 | 3 | ITEM-04, ITEM-09 | S1, S2, S3, S7 (completeness gate) | G1, G5 | planned |
| 47-03 T2 | 03 | 3 | ITEM-05, ITEM-09 | S1, S2, S8 | G3, G5 | planned |
| 47-03 T3 | 03 | 3 | all six | none -- this IS the in-game gate | G1-G5 | pending user |

---

## Environment Availability

| Dependency | Required by | Available |
|------------|-------------|-----------|
| stylua | S1 | yes — `~/.cargo/bin/stylua`, run bare from repo root |
| git `ls-files --eol` | S2 | yes — the only tool that sees a CRLF reflow |
| WoW Forever beta client | G1–G5 | yes — build 1.60.1 |
| Midnight retail client | G6 (Phase 52) | yes |

---

## Security Domain

Unchanged from Phase 46. A single-player client addon with no network surface, no authentication
and no server-side trust boundary; it reads client-local data and writes `TerribleBuffTrackerDB`.

| Category | Applies | Control |
|----------|---------|---------|
| V5 Input Validation | Yes, narrow | `issecretvalue()`-then-`type()` on every API read (S4). The trust boundary is "is this value the shape I expect" |
| V2/V3/V4/V6 | No | No auth, sessions, multi-user boundary or cryptography |

| Threat | STRIDE | Mitigation |
|--------|--------|------------|
| Secret-value type confusion | Tampering (of TBT's own logic) | S4 |
| Phantom timer written to `ns.activeTimers` by a provider returning a truthy proc | Tampering | S5 — the dispatcher is the single writer and does not validate its input |
