# Phase 27: Provider At-Rest Defensive Fix - Context

**Gathered:** 2026-09-18
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous run — user unavailable, all decisions at Claude's discretion and flagged for review)

<domain>
## Phase Boundary

The Trinket and Pot Suggested tiles must never present an unresolved hardcoded fallback item as if it were a real, obtainable item — on any flavor. This is the milestone's **only authorized Lua change**.

Requirements owned: PAR-01.

**Not this phase:** any new capability, flavor branching, Forever-specific spell catalogs, or changes to the Lust/UserSpell providers. Verification of the fix's real-world rendering happens in Phase 28.

</domain>

<decisions>
## Implementation Decisions

### The defect — corrected and expanded from research

Research (ARCHITECTURE.md, confirmed by SUMMARY.md's adjudication) flagged **one** site. Reading `Providers.lua` directly during this discuss found **two per provider**, and fixing only the first would relocate the bug rather than remove it:

| # | Site | Line | Trigger |
|---|------|------|---------|
| 1 | `TrinketProviderMixin:RefreshAtRest` | ~299 | no equipped trinket matches `TRINKET_ITEM_IDS` |
| 2 | `TrinketProviderMixin:GetDisplayInfo` | ~313 | `atRest.spellID` unpopulated (e.g. logged in during combat, before any `RefreshAtRest`) |
| 3 | `PotProviderMixin:RefreshAtRest` | ~394 | no bagged potion matches `POT_FALLBACK_ORDER` |
| 4 | `PotProviderMixin:GetDisplayInfo` | ~406 | `atRest.spellID` unpopulated |

- **D-01:** All **four** sites are in scope. Sites 2 and 4 are a genuine addition to what research identified — record this in the phase SUMMARY so the finding is traceable.
- **D-02:** Why the fallback resolves rather than failing: `FindSpellByItemID` looks `TRINKET_FALLBACK_ORDER[1]` (itemID `249344`) up against `TRINKET_SPELLS`, the very table it was drawn from, so the lookup is **guaranteed to succeed** and return a real retail spellID. This is structurally different from the `OnTrigger` cast path, which is a genuine harmless no-op because no Forever cast can ever match.

### The fix — placeholder, NOT nil

- **D-03:** **Do not return `nil` from `GetDisplayInfo` when nothing resolves.** A literal reading of PAR-01 ("show nothing") suggests `nil`, but that breaks a working retail behavior — see D-04. Instead return a **neutral placeholder**: no `spellID`, a generic label already used by the existing code (`"Trinket"` / `"Damage Pot"`), and the default question-mark icon (`134400`, the fallback `CDMTab.lua:409` already uses).
- **D-04:** **Why `nil` is wrong.** `CDMTab.lua:137` and `CDMTab.lua:518` both gate tracked-buff creation behind `if info then`. Returning `nil` would make the Trinket and Pot tiles impossible to drag out of the Suggested section at all. On retail, a fresh alt with an empty bag and no equipped trinket would lose the ability to add these tiles — a regression introduced by a fix meant to *improve* correctness. Every other consumer (`Display.lua:465`, `:632`, `CDMTab.lua:85`, `:408`, `:745`) handles `nil` safely, but these two do not merely handle it — they silently drop the feature.
- **D-05:** `RefreshAtRest` (sites 1 and 3) stops assigning the fallback itemID and instead leaves `atRest.spellID = nil`. The "nothing resolved" state is then represented honestly in the cache, and `GetDisplayInfo` renders the D-03 placeholder from it.
- **D-06:** **No flavor branch.** The guard is flavor-agnostic and applies identically on retail and Forever, per the milestone's locked cross-flavor constraint. Forever gets correct behavior as a side-effect of correct retail behavior, not via a `WOW_PROJECT_ID` check.
- **D-07:** Preserve `PITFALL-5` / `D-19`: inventory APIs (`GetInventoryItemID`, `C_Item.GetItemCount`) stay in `RefreshAtRest` only and must NOT be introduced into `GetDisplayInfo`. The existing `InCombatLockdown()` gates in both `RefreshAtRest` methods stay.
- **D-08:** Keep the shape of the returned table identical (`{ icon, label, duration, spellID }`) so no consumer needs changing. In the placeholder case `spellID` is `nil` and `duration` is `nil`; consumers already tolerate both.

### Scope discipline

- **D-09:** Do not touch `LustProviderMixin` or `UserSpellProviderMixin`. `LustProvider:RefreshAtRest` is deliberately the base no-op (D-14 from v0.2.4) and must stay so.
- **D-10:** Do not delete `TRINKET_FALLBACK_ORDER` / `POT_FALLBACK_ORDER` — both are still the iteration order for the real bag/equipment scan in `RefreshAtRest`. Only the *unconditional* `[1]` assignment is removed.
- **D-11:** `stylua` must be run after the edit, per CLAUDE.md's standing workflow rule.

### Claude's Discretion

The entire phase was auto-discussed — the user is away. D-03/D-04 is the decision most worth a human look, because it deliberately interprets PAR-01's "show nothing" as "show a neutral placeholder" rather than literally nothing. See Deferred Questions.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope
- `.planning/ROADMAP.md` — Phase 27 goal and its two success criteria
- `.planning/REQUIREMENTS.md` — PAR-01 exact wording; the Out of Scope table (no new features, no flavor branching)
- `.planning/PROJECT.md` — Constraints (parity-only, cross-flavor), Key Decisions

### The defect analysis
- `.planning/research/SUMMARY.md` §"Adjudicated conflict - Is the trinket/pot at-rest fallback a real defect?" — the verdict that this is real, and the open empirical question of whether Forever resolves retail spellIDs
- `.planning/research/ARCHITECTURE.md` — the original flag (note: it identified only the `RefreshAtRest` sites, not the `GetDisplayInfo` ones)

### Code
- `Providers.lua` — all four fix sites; `FindSpellByItemID` (~173); the `TRINKET_SPELLS` / `POT_SPELLS` tables and both `*_FALLBACK_ORDER` arrays (~161-162)
- `CDMTab.lua:137`, `CDMTab.lua:518` — the two `if info then` gates that make D-03/D-04 load-bearing
- `CDMTab.lua:409` — precedent for `134400` as the neutral fallback icon
- `Display.lua:465`, `Display.lua:632` — the other `GetDisplayInfoForKey` consumers, both nil-safe

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `134400` is already the established "unknown" icon fallback in `CDMTab.lua:409` — reuse it rather than inventing a new placeholder constant.
- `"Trinket"` and `"Damage Pot"` are already the `or`-fallback labels inside both `GetDisplayInfo` methods; the placeholder path should reuse those exact strings.
- `ns:GetSpellIcon(spellID)` is the existing icon resolver; the placeholder path bypasses it entirely since there is no spellID.

### Established Patterns
- **Minimal at-rest cache (v0.2.4 D-13):** `atRest` holds only `{ spellID, duration }`; icon and label are *derived* in `GetDisplayInfo`. The fix must not add fields to the cache.
- **PITFALL-5 / D-19:** inventory APIs belong in `RefreshAtRest`, never `GetDisplayInfo`. This is an explicit, load-bearing invariant from the v0.2.4 refactor.
- **Combat gating:** both `RefreshAtRest` methods open with `if InCombatLockdown() then return end`, plus `ns:RefreshProvidersAtRest` gates at the wrapper level (v0.2.4 D-17/D-18).
- Providers are stateless w.r.t. lifecycle; `BuffEngine` owns all proc lifecycle. This phase touches only at-rest display, never the proc path.

### Integration Points
- `ns:GetDisplayInfoForKey(key)` (`Providers.lua:602`) dispatches to the provider by key — unchanged by this phase.
- Seven consumer call sites across `CDMTab.lua`, `Display.lua`, and `BuffEngine.lua:281`. Only the two `CDMTab` entry-creation gates constrain the fix's shape.

</code_context>

<specifics>
## Specific Ideas

- The user's framing when approving this work was "a parity fix, not new capability" and explicitly noted it "also fixes a retail edge case (fresh alt, empty bags)". D-03/D-04 is chosen to honor that second half — a `nil` return would have *broken* the retail edge case instead of fixing it.

</specifics>

<deferred>
## Deferred Ideas

- **Whether Forever resolves retail-exclusive spellIDs at all** — determines whether the pre-fix bug rendered as a real-but-wrong item or a harmless placeholder. Recorded as Phase 28 checklist item (VER-08). The fix is correct regardless, which is why it is not blocked on the answer.
- **Forever-appropriate trinket/pot catalogs** — `FCON-02` in REQUIREMENTS.md, a future milestone.

</deferred>

<deferred_questions>
## Deferred Questions for Human Review

Raised because the user is away; do not block on these.

1. **D-03/D-04 — placeholder instead of `nil`.** PAR-01 says the tiles should "show nothing rather than a hardcoded retail item's icon and name." Implemented as a neutral placeholder (question-mark icon + generic label, no spellID) rather than a literal `nil`, because `nil` would make the tiles undraggable from the Suggested section and regress the retail empty-bags case the requirement explicitly wanted fixed. **If you wanted literal `nil`, this needs revisiting** — but then `CDMTab.lua:137`/`:518` need a companion change to keep the tiles addable.
2. **Sites 2 and 4 are an expansion of the agreed scope.** Research and the roadmap both described one fallback site per provider; there are two. Fixing all four is the only way PAR-01 actually holds, but it is more code than the phase was scoped against. Flagging rather than silently widening.

</deferred_questions>

---

*Phase: 27-Provider At-Rest Defensive Fix*
*Context gathered: 2026-09-18 (autonomous)*
