---
status: human_needed
phase: 47-item-tracking-cooldown-sharing
verified: 2026-09-24T00:00:00Z
score: 5/5 statically verifiable, 0/5 in-game-confirmed
overrides_applied: 0
human_verification:
  - test: "G1 (ITEM-02, ITEM-04) — Open CDM > TBT tab > Cooldowns category. Drag a Suggested consumable tile into a container."
    expected: "A tile appears showing the item's own icon (not a question mark, not 134400); the item leaves the Suggested list; it renders under Cooldowns, not Buffs."
    why_human: "Requires a live client with real bag contents and a real drag gesture. Proves entry.iconOverride, ns:GetTrackerCategory's 'item' widening, and the Suggested-loop drop-out all work together at runtime, not just that the source reads correctly."
  - test: "G2 (ITEM-05) — Track two potions that share a cooldown group (Forever: any two of Minor Healing / Mana / Rejuvenation Potion, measured sharing one 120s group). Drink one."
    expected: "The other tile — never used — starts its sweep at the same moment with the same remaining time."
    why_human: "This is the one behaviour no static read can infer: it requires the game's own C_Item.GetItemCooldown to actually report a shared cooldown across two itemIDs, and requires watching a second, untouched tile change live. Cannot be shortened."
  - test: "G3 (ITEM-06) — With a tracked item on cooldown, press it again (refused press). Confirm count does not change. Then use a different, off-cooldown tracked item and confirm its count drops by exactly 1."
    expected: "Refused press: count unchanged. Landed use: count drops by exactly 1."
    why_human: "Requires a live UNIT_SPELLCAST_SUCCEEDED (or its absence) from the game client — cannot be produced or simulated outside the game."
  - test: "G4 (ITEM-07) — Enter combat, drink a tracked potion (count drops locally), loot more of the same item mid-fight, leave combat."
    expected: "The displayed count corrects to the true bag count after combat ends."
    why_human: "Requires real combat state transitions and real looting; PLAYER_REGEN_ENABLED firing and InCombatLockdown() gating can only be exercised in a live session."
  - test: "G5 (ITEM-09) — Drink a tracked item down to its last one, then drink the last one so the stack leaves the bags entirely. Confirm in the Blizzard bag UI it is genuinely gone."
    expected: "The TBT tile remains visible, its sweep keeps running to expiry, and it shows 0 (not hidden, not errored, not disappeared). If the whole container vanishes rather than just the tile, the defect is RefreshCooldownSlotCounts specifically."
    why_human: "Requires a real multi-step consumption sequence ending in genuine zero bag stock, which only the live client's bag state can produce. Cannot be shortened."
---

# Phase 47: Item Tracking & Cooldown Sharing Verification Report

**Phase Goal:** Dragging a Suggested item creates a real cooldown tracker whose count and
shared-cooldown display stay correct through use, looting, and combat.

**Verified:** 2026-09-24
**Status:** human_needed
**Re-verification:** No — initial verification

## Framing

This project has no test runner and none is planned (confirmed in `47-VALIDATION.md`'s own Test
Infrastructure table: "No test suite exists... the phase gate is the in-game check list below").
The only runtime that can prove any of this phase's six requirements (ITEM-02, 04, 05, 06, 07, 09)
is a live WoW Forever beta client, via checks G1–G5 defined in `47-VALIDATION.md`. **None of G1–G5
have been run.** No `HUMAN-UAT.md` or equivalent exists for Phase 47, and `.planning/STATE.md`'s
Phase 46 carry-over note establishes the same "code complete, not yet verified in game" pattern for
the phase this one builds on. 47-03-SUMMARY.md's own frontmatter leaves `requirements-completed`
empty and states explicitly: "Do not tick those requirements in REQUIREMENTS.md on the strength of
this summary alone." I agree with that self-assessment after independently re-reading the shipped
source below — the static half is unusually solid, but it proves shape, not behavior.

This verifier did **not** trust that self-assessment on faith — every claim below was re-checked
against the actual source (line numbers cited), the git diff of the phase's own commit range
(`5ec6b51~1..5c9c1e9`), and `stylua --check .` / `git ls-files --eol` run fresh. All match.

## Goal Achievement — Per-Criterion Findings

### 1. Dragging a Suggested item tile creates an ordinary cooldown tracker, and the item drops out of Suggested

**Static: VERIFIED.** `CDMTab.lua:139` (`AddSuggestedTracker`) resolves `ns:ItemKeyItemID(key)`
alongside `ns:CooldownKeySpellID(key)` (`:143-144`), widens its rejection test to
`if not cooldownSpellID and not itemID then` (`:145`), and writes `trackerType = "item"`, `itemID`,
`iconOverride = info.icon` into `ns.db.trackedBuffs["item:"..itemID]` (`:171-197`). The Suggested
item loop (`CDMTab.lua:897`, confirmed unedited by Plan 02 per its own summary and independently
grepped) reads `if not ns.db.trackedBuffs[itemKey] then` — the exact map `AddSuggestedTracker`
writes into, so the drop-out is structural, not separately coded. `ns:GetTrackerCategory`
(`Core.lua:105-108`) widened to `entry.trackerType == "cooldown" or entry.trackerType == "item"`,
confirmed by git diff to be the only change to that function, so an item entry files under
Cooldowns rather than silently disappearing under the Buffs tab filter (`CDMTab.lua:834`ish
category test).

**In-game: UNVERIFIED (G1).** Whether a real drag gesture actually reaches `AddSuggestedTracker`
with the expected key shape, and whether the resulting tile visibly shows the item's own icon
rather than the 134400 placeholder, has not been observed in a live client.

### 2. Using any item refreshes the displayed cooldown of every tracked item that shares its cooldown

**Static: VERIFIED as a state-layer chain; this is the one criterion most likely to have been
merely assumed, so it was traced function-by-function rather than taken on the summary's word.**

Chain, cited by file:line:
- `Core.lua:835` registers `UNIT_SPELLCAST_SUCCEEDED`; the handler at `Core.lua:967-973` calls
  `ns:OnSpellCastSucceeded(spellID)` unconditionally for `unit == "player"`.
- `BuffEngine.lua:239-244` (`ns:OnSpellCastSucceeded`) has zero branches and calls
  `ns:DispatchEventToProviders("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellID)`.
- `Providers.lua:1566-1580` (`ns:DispatchEventToProviders`) calls `provider:OnTrigger(event, ...)`
  for every provider registered for that event — `ItemProviderMixin` is registered at
  `Providers.lua:1472` (confirmed: `ns.providers = { TrinketProvider, PotProvider, LustProvider,
  RacialProvider, ItemProvider, UserSpellProvider }`), and its `GetEventInterests` (`:1414-1416`)
  returns `{ "UNIT_SPELLCAST_SUCCEEDED" }`.
- `ItemProviderMixin:OnTrigger` (`Providers.lua:1425-1462`) looks up `itemUseSpellToID[spellID]`
  (`:1439`) — nil means an ordinary player cast unrelated to any catalogued item, and the function
  returns nil at `:1440`. On a hit, it decrements the one matching tracked count (`:1445-1452`),
  then — **the critical step for this criterion** — calls `ns:RefreshTrackedItemCooldowns()`
  (`:1458`) unconditionally, followed by `ns:MarkCooldownsDirty()` (`:1459`).
- `ns:RefreshTrackedItemCooldowns` (`Providers.lua:1105-1129`) iterates **`pairs(ns.db.trackedBuffs)`
  — every entry with `trackerType == "item"`, not only the one just used** — and re-reads
  `C_Item.GetItemCooldown(entry.itemID)` for each, re-stamping `entry.duration` and
  `ns.cooldownStarts[key]` on a readable result (`:1116-1121`), or leaving the prior stamp exactly
  as it was on any other outcome (comment at `:1122-1126`, confirmed no `else` branch clears
  anything).
- The render side: `ns:MarkCooldownsDirty()` bumps `ns.cooldownGeneration` (`Core.lua:543-545`),
  which `ApplyCooldownSlot` (`Display.lua:1304` onward) and `ApplyUserCooldown`
  (`Display.lua:989-1011`, reading `ns.cooldownStarts[entry.key]` and `entry.duration` — the exact
  pair `RefreshTrackedItemCooldowns` writes) consume on the next render tick via the
  `icon._cdGen ~= ns.cooldownGeneration` check (`Display.lua:1325`).

This chain is real and sound: a landed use of item A causes item B's tile (never touched) to
re-read its own cooldown and reflect a shared value on the very next render tick. No spell-category
table is needed because `C_Item.GetItemCooldown` itself reports the shared value per the
`47-CONTEXT.md` measurement (Forever 1.60.1: all potions share one 120s group).

**In-game: UNVERIFIED (G2), and G2 is explicitly the one check that "no static read can infer"** —
per `47-VALIDATION.md`'s own words. The static trace above proves the *mechanism* is wired
end-to-end; it cannot prove `C_Item.GetItemCooldown` actually reports the shared value in a live
session, nor that the sibling tile visibly updates rather than silently staying stale due to some
pooled-widget identity mismatch that only shows up at runtime. G2 must still be run.

### 3. A tracked item's count decreases only when a use actually lands, never when a press is refused

**Static: VERIFIED.** The decrement (`Providers.lua:1445-1452`) is reachable only via a matched
`itemUseSpellToID[spellID]` lookup from a real `UNIT_SPELLCAST_SUCCEEDED` event — an event WoW
fires only on a landed cast, never on a button press that produces no cast (the documented reason
`D-01` in `47-CONTEXT.md` rejected the four item-use hooks: they fire on the press, "a healthstone
press produced no cooldown and no count change"). No hook is registered on the production path —
confirmed: `grep -n hooksecurefunc Providers.lua` inside the Phase 47 diff range returns nothing,
and `ItemProviderMixin`'s only interest is `UNIT_SPELLCAST_SUCCEEDED` (`:1414-1416`). The decrement
floors at zero: `itemTrackedCounts[key] = math.max(0, current - 1)` (`:1452`).

**In-game: UNVERIFIED (G3).** Whether the map correctly identifies the landed use for a *specific*
item on a live character, and whether a refused press genuinely produces no `UNIT_SPELLCAST_SUCCEEDED`
for every consumable tested (not just the healthstone probed at design time), is unconfirmed.

### 4. Leaving combat reconciles a tracked item's displayed count against the bags

**Static: VERIFIED.** `ns:ReconcileTrackedItemCounts` (`Providers.lua:1133-1160`) early-returns on
`InCombatLockdown()` (`:1135-1137`) before touching any state, so a reconcile call made *during*
combat (from the `BAG_UPDATE_DELAYED` wiring below) is a guaranteed no-op — the reconcile can never
fight the decrement while the player can still act on the count. It is wired to
`PLAYER_REGEN_ENABLED` (`Core.lua:975` region, confirmed by diff: `ns:ReconcileTrackedItemCounts()`
added immediately after the existing `ns:MarkCooldownsDirty()` call in that branch) and to
`PLAYER_EQUIPMENT_CHANGED or BAG_UPDATE_DELAYED` (`Core.lua:1023` region, confirmed by diff). On a
readable count it overwrites `itemTrackedCounts[key]` from `C_Item.GetItemCount(entry.itemID)`
(`:1146-1149`), and calls `ns:MarkCooldownsDirty()` unconditionally at the end (`:1160`) so the
corrected number actually reaches the render path.

**In-game: UNVERIFIED (G4).** Whether a real combat-exit sequence with mid-fight looting produces
the correct corrected count, and whether `PLAYER_REGEN_ENABLED` reliably fires before the player
next looks at the tile, is unconfirmed.

### 5. A tracked item keeps its tile and running cooldown after its stack reaches zero and leaves the bags

**Static: VERIFIED — the two things that could silently break this were checked directly.**

- **The count source is never the catalogue's bag-walk cache.** `ns:TrackedItemCount`
  (`Providers.lua:1058-1061`) reads only `itemTrackedCounts[key]` — a table that is **never**
  `wipe()`d by `ns:RefreshItemCatalogue` (confirmed: the wipe list at `Providers.lua:934-938` wipes
  `itemCatalogueIDs`, `itemCatalogueIcons`, `itemCatalogueCounts`, `itemUseSpellToID` — four
  tables — and `itemTrackedCounts` is declared separately at `:937` outside that list, with its own
  header comment explaining why). `Display.lua`'s `ApplyItemCount` (`:962-969`) calls
  `ns:TrackedItemCount(entry.key)` only; `grep -n ItemCatalogueCount Display.lua` returns nothing
  (S8 from `47-VALIDATION.md`, independently re-run and confirmed empty).
- **The tile stays visible.** `RefreshCooldownSlotCounts` (`Display.lua:704`) counts an entry
  toward `hasActiveIcons` when `entry.trackerType == "cooldown" or entry.trackerType == "item"` —
  this test does not consult the item's stock at all, so a zero-count item continues to hold its
  container open under `hideWhenInactive`.
- **The sweep keeps running from the stamp, not from a live read.** `ApplyUserCooldown`
  (`Display.lua:989-1011`) computes `running` from `ns.cooldownStarts[entry.key]` and
  `entry.duration` alone — both stamped once at the landed use (`ItemProviderMixin:OnTrigger` →
  `RefreshTrackedItemCooldowns`) — with no dependency on the item still existing in the bags.
- **The count renders as `0`, not hidden.** `ApplyItemCount` shows any numeric count including zero
  (`Display.lua:966-968`, only hides when `type(count) ~= "number"`, i.e., never-readable — not
  when the count is legitimately zero).

**In-game: UNVERIFIED (G5), and G5 is explicitly the one check that "cannot be shortened."** The
static evidence is unusually strong for this criterion — three independent mechanisms were each
purpose-built to avoid exactly this failure mode, and none of them reads live bag stock on the
render path — but a live multi-step consumption-to-zero sequence has not been run, and
`47-CONTEXT.md` itself flags "whether `GetItemCooldown` answers for a zero-count item... left
untested by explicit user decision" as an accepted, unresolved gap that the stamp design is
*intended* to route around rather than one that has been empirically closed.

## Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `Providers.lua` — `itemUseSpellToID`, `itemTrackedCounts` | Runtime state layer, separate from catalogue tables | VERIFIED | `:920-937`; wipe list at `:934-938` excludes `itemTrackedCounts` |
| `Providers.lua` — `ns:TrackedItemCount`, `ns:SeedItemTracker`, `ns:RefreshTrackedItemCooldowns`, `ns:ReconcileTrackedItemCounts` | Four exported functions | VERIFIED | `:1058, :1070, :1105, :1133` |
| `Providers.lua` — `ItemProviderMixin` | Registered ahead of `UserSpellProvider`, returns nil on every path | VERIFIED | `:1412-1462`; registry at `:1472`; five statement-leading returns all `nil` |
| `Core.lua` — `ns:GetTrackerCategory` | Widened for `trackerType == "item"` | VERIFIED | `:105-108` |
| `Core.lua` — event wiring | `BAG_UPDATE_COOLDOWN`, `PLAYER_REGEN_ENABLED`, `PLAYER_EQUIPMENT_CHANGED`/`BAG_UPDATE_DELAYED` call the new functions | VERIFIED | Confirmed via `git diff` hunks, not just grep |
| `CDMTab.lua` — `AddSuggestedTracker` | Creates `item:` entries | VERIFIED | `:139-197` |
| `Display.lua` — four widened `trackerType` gates | `SlotDraws`, `RefreshCooldownSlotCounts`, bar-slot exclusion, icon dispatch gate | VERIFIED | `:86-98`, `:696-709`, `:1681`, `:2043` |
| `Display.lua` — `ApplyItemCount` | Count render parallel to `ApplyChargeCount`, reads `ns:TrackedItemCount` only | VERIFIED | `:962-969`; call site `Display.lua:1352` |

## Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `ItemProviderMixin:OnTrigger` | `itemUseSpellToID` | `spellID` lookup before any table walk | WIRED | `Providers.lua:1439` |
| `ItemProviderMixin:OnTrigger` | `ns:RefreshTrackedItemCooldowns` | unconditional call on a landed use | WIRED | `Providers.lua:1458` |
| `ns:RefreshTrackedItemCooldowns` | `C_Item.GetItemCooldown` | per-tracked-item read, guarded | WIRED | `Providers.lua:1116` |
| `ns:ReconcileTrackedItemCounts` | `C_Item.GetItemCount` | combat-gated reconcile | WIRED | `Providers.lua:1146`, gate at `:1135` |
| `AddSuggestedTracker` | `ns:SeedItemTracker` | gated on `itemID` truthiness | WIRED | `CDMTab.lua:191-193`ish |
| `ApplyCooldownSlot` | `ApplyItemCount` / `ApplyChargeCount` | `entry.trackerType == "item"` branch | WIRED | `Display.lua:1350-1354` |
| `ApplyUserCooldown` | `ns.cooldownStarts[entry.key]` | same stamp key Plan 01 writes | WIRED | `Display.lua:1010` reads what `Providers.lua:1121` writes |
| `DispatchEventToProviders` | `ns.activeTimers` | must NEVER be written by `ItemProviderMixin` | CONFIRMED NEVER WIRTEN | every `OnTrigger` path returns `nil` (S5) |

## Anti-Patterns / Blocker Scan

- No `TBD`, `FIXME`, `XXX`, `TODO`, `HACK`, `PLACEHOLDER` found in the phase's diff range
  (`git diff 5ec6b51~1..5c9c1e9 -- Core.lua Providers.lua CDMTab.lua Display.lua` scanned).
- No flavour check introduced: diff of `Core.lua` shows only the two documented hunks (category
  widening + event wiring); `Core.lua:565-577`'s pre-existing sanctioned flavour check (Phase 37)
  is present and byte-identical to pre-phase source, confirmed by grep on both.
- `Core.lua`'s debug cast/item log (`pendingItemCasts`, `LogPlayerCast`, `LogItemUse`) — zero hits
  in the phase diff.
- Bandage exclusion (`subClassID ~= 7`) — zero hits in the phase diff; filter untouched.
- No Phase 48 (pandemic) or Phase 49 (racial) content in the diff — only pre-existing
  `RacialProvider` registration-order line touched (`ItemProvider` inserted before
  `UserSpellProvider`).
- `stylua --check .` — clean, exit 0.
- `git ls-files --eol` on all four touched files — `w/crlf` as required by `.gitattributes`; no
  invisible LF reflow.

## Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
| ----------- | ----------- | ------ | -------- |
| ITEM-02 | 47-02 | NEEDS HUMAN | Static: verified (criterion 1). REQUIREMENTS.md checkbox still unchecked, correctly — G1 not run. |
| ITEM-04 | 47-02 | NEEDS HUMAN | Static: verified (criterion 1). G1 not run. |
| ITEM-05 | 47-01 | NEEDS HUMAN | Static: verified as a full mechanism trace (criterion 2). G2 not run — the one check that cannot be inferred statically. |
| ITEM-06 | 47-01 | NEEDS HUMAN | Static: verified (criterion 3). G3 not run. |
| ITEM-07 | 47-01/02 | NEEDS HUMAN | Static: verified (criterion 4). G4 not run. |
| ITEM-09 | 47-01/03 | NEEDS HUMAN | Static: verified, unusually strong (criterion 5). G5 not run — explicitly cannot be shortened. |

No orphaned requirements: all six requirements declared in this phase's plans match
`.planning/REQUIREMENTS.md`'s Phase 47 mapping exactly.

## Human Verification Required

See YAML frontmatter `human_verification` for the full G1–G5 list with pass conditions. Run in this
order — **G2 and G5 require real multi-step play sequences and cannot be shortened**:

1. G1 (ITEM-02, ITEM-04) — drag-create, icon, category, Suggested drop-out
2. G2 (ITEM-05) — shared cooldown across two tracked, one used, one untouched
3. G3 (ITEM-06) — refused press vs. landed use, count behavior
4. G4 (ITEM-07) — combat-end reconcile against real looting
5. G5 (ITEM-09) — tile survives the stack reaching zero and leaving the bags

G6 (retail parity, ITEM-10) is explicitly out of scope for Phase 47 — scheduled for Phase 52 per
`47-VALIDATION.md`.

## Gaps Summary

No code-level gap was found. Every static assertion (S1–S11) in `47-VALIDATION.md` was independently
re-checked against the shipped source rather than taken from the SUMMARYs, and all pass, including
the two most failure-prone claims in this kind of phase: (a) that a landed use genuinely reaches
every tracked item's cooldown re-read, not only the one used (traced function-by-function above, not
inferred from a comment), and (b) that the tracked count store is structurally incapable of aliasing
the catalogue's bag-walk cache, which would have silently broken ITEM-09 the first time a rescan ran.

The phase is `human_needed`, not `passed`, because none of this phase's six requirements can be
closed by source reading alone — `47-VALIDATION.md` designed it this way deliberately, and the
executor's own Task 3 checkpoint was correctly left unattempted rather than approximated. This is
not a deficiency in the work; it is the expected state for a WoW addon phase whose only real test
harness is a human playing the game. Do not mark this phase `passed`, and do not tick any of
ITEM-02/04/05/06/07/09 in `.planning/REQUIREMENTS.md`, until G1–G5 have been run and reported.

---

_Verified: 2026-09-24_
_Verifier: Claude (gsd-verifier)_

---

## Post-Verification Amendment — 2026-09-24

**This verification ran before code-review BLOCKER B1 was found, and its criterion-2 and
criterion-3 findings were correct about the code they examined but wrong about the behaviour.**

The verification traced the landed-use chain forward from `ItemProviderMixin:OnTrigger` and
confirmed it refreshes every tracked item rather than only the one used. That tracing was accurate.
What it did not check was whether the lookup table at the head of that chain — `itemUseSpellToID` —
was ever populated outside the Cooldown Manager being open. It was not: the only writer was
`ns:RefreshItemCatalogue`, reachable only from `CDMTab.lua:36` and an `ns.configOpen`-gated rebuild.

So for a player who never opened the CDM in a session, `OnTrigger` would look up an empty map,
return early, and the whole verified chain would never execute. Criterion 3 (count decrements on a
landed use) would fail outright; criterion 2 (shared-cooldown refresh) would fail with it.

Fixed in `f5dc170` — tracked items now register their use-spells from `ns.db.trackedBuffs`, with no
bag access, at tracker creation, on `PLAYER_ENTERING_WORLD`, and after each catalogue rebuild.

**The verdict is unchanged at `human_needed`**, and the in-game gate matters more now, not less: G3
is the check that would have caught this, and it remains unrun. The general lesson for the next
phase's verification is to trace a chain **backwards to its data source**, not only forwards from
its entry point — a correctly-wired chain fed by an empty table is indistinguishable from a working
one when read forwards.
