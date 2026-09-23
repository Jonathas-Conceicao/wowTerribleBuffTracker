# Phase 37: Redesigned Add Panel & Rank Grouping - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning
**Mode:** Decisions taken with the user up front, before the autonomous run

<domain>
## Phase Boundary

One add flow that captures what kind of tracker this is, which container it goes in, and — on Forever —
whether it covers every rank of the spell. Plus the rank reconciliation that stops TBT and the CDM
disagreeing about the same spell.

In scope: the add dialog and the rank-family resolution.
Out of scope: cooldown *rendering*, which is Phase 38. This phase only lets the user say "cooldown".
</domain>

<decisions>
## Implementation Decisions

### The dialog
- Gains a **buff-or-cooldown** choice and a **container** choice. The new entry lands in exactly the
  container chosen, as exactly the type chosen.
- The container list includes the four base containers and every user container.
- Further layout detail was left open by the user ("we will discuss the new add popup frame we will
  have") — treat the three controls above as the contract and keep the rest close to the existing
  dialog rather than redesigning it.

### "Cover all ranks" — a flavour check, by explicit user decision
- The checkbox is **present on Forever and absent on retail**, decided by an explicit client-version
  check. Checked by default.
- The user was offered the data-driven alternative — show it only when the spell resolves to a
  multi-rank family, which needs no flavour check — and **declined it**: *"I don't want this as a
  dynamic check and have a option that either apperes dynamically on forever or that is there and hides
  or shows as disabled on Retail, so just have them either show or now show based on version."*
- **This is the milestone's one sanctioned runtime flavour check.** It narrows, but does not repeal, the
  v0.3 constraint. No second flavour check may appear anywhere in the diff; everything else stays on
  data-absence / capability checks.
- Detection: `select(4, GetBuildInfo())` — Forever `16000-19999`, retail `12xxxx`.

### Rank resolution
- With the box checked, the tracker starts on **any** rank of that spell. Fireball `133`, `143` and
  `145` all drive one tracker.
- `GetBaseSpell` / `GetOverrideSpell` are the bridge, and both are readable in combat.

**Refined at planning time, 2026-09-21 — recorded so the decision record matches what ships.**
The research note describes those two APIs as the *likely* bridge, with probes added to confirm and no
confirmed result. Planning therefore demoted them from sole mechanism to **seed and final expansion**
step, and made a name-matched `C_SpellBook` scan the load-bearing way to find rank siblings — vanilla
ships ranks as same-name entries distinguished by `subName`, which is dependable where the spell APIs
are not. Base/override is still what reaches the CDM’s own ID, which is what closes `RANK-02`.

The scan is capability-guarded on every symbol it touches, so a client lacking them degrades to
base/override-only resolution rather than erroring, and it **never runs on retail** — the rebuild
early-outs before touching `C_SpellBook` when no tracker is covered, and on retail none can be, since
the checkbox that sets `coverAllRanks` does not exist there. Verified against Blizzard’s own
`SpellBookDocumentation.lua`: every field and enum the scan assumes is real.

**Refined at planning time, 2026-09-21 — recorded so the decision record matches what ships.** The
research note describes those two APIs as the *likely* bridge, with probes added to confirm and no
confirmed result. Planning therefore demoted them from sole mechanism to **seed and final expansion
step**, and made a name-matched `C_SpellBook` scan the load-bearing way to find rank siblings — vanilla
ships ranks as same-name entries distinguished by `subName`, which is dependable where the spell APIs
are not. Base/override is still what reaches the CDM’s own ID, which is what closes `RANK-02`.

The scan is capability-guarded on every symbol it touches, so a client without them degrades to
base/override-only resolution rather than erroring, and it **never runs on retail** — the rebuild
early-outs before touching `C_SpellBook` when no tracker is covered, and on retail none can be, because
the checkbox that sets `coverAllRanks` does not exist there.
- `RANK-02` is the reason this matters beyond convenience: TBT keys everything by spellID, so a user
  adding the rank they cast silently disagrees with the CDM, which holds a different ID for the same
  spell (Frostbolt `116` vs the CDM's `205`). Resolving to a family fixes both.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- The Add dialog exists in `CDMTab.lua` (added v0.2.0, section-aware since v0.2.2) — this is a
  redesign of a working flow, not a new one.
- `TOOL-01`'s tooltip already surfaces spell and aura IDs in-game, which is how ranked IDs were
  discovered in the first place. Keep it working; it is the only way to find a Forever spell ID.
- `UserSpellProvider` owns user-added spells and already keys entries by numeric spellID.

### Established Patterns
- New trackers land in Not Displayed by default (a locked v0.2.0 decision: "User explicitly chooses
  where to show, avoids clutter"). The container choice in the dialog **supersedes that default when the
  user picks one** — but an unchosen container must still fall back to Not Displayed, not to a visible
  container.
- `issecretvalue()` before any comparison or concatenation, including on values from an API that already
  succeeded. `type()` reports `"number"` for a secret number.
- Capability checks, not client-identity checks — with `ADD-03` as the single sanctioned exception.

### Integration Points
- `ns.db.trackedBuffs` is keyed by spellID for user spells and by string for meta slots. A rank family
  needs a representative key plus the set of IDs that trigger it; `proc.key` is the stable slot identity
  and `proc.spellID` the derived numeric (a locked v0.2.4 decision — do not invert it).
- `BuffEngine.OnSpellCastSucceeded` dispatches to providers; rank matching belongs there or in
  `UserSpellProvider`, not in the display layer.
</code_context>

<specifics>
## Specific Ideas

"on Forever (not on retail) it should also have a checkbox on by default saying something like 'cover
all ranks' and if left checkd the skill CD or duration is triggered by any other rank aswell", and "the
new 'add skill' panel will also have other info, like configing it to be either a cooldown tracked or a
buff tracked".
</specifics>

<deferred>
## Deferred Ideas

- Detailed add-panel layout beyond the three required controls — the user reserved this for discussion
  when the phase arrives. Keep the change minimal and be ready to iterate.
</deferred>
