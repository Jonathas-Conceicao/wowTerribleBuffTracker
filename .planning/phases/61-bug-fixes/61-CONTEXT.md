# Phase 61: Bug Fixes - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning
**Mode:** Autonomous run 61-63; every question for the range was asked up front on 2026-09-30. None
fell in this phase — its decisions were already settled in the backlog entries.

<domain>
## Phase Boundary

Two small, independent fixes (EDM-08, STEAL-09):

1. **Backlog 999.9** — selecting a TBT container in Edit Mode stops calling
   `EditModeManagerFrame.ClearSelectedSystem`.
2. **Backlog 999.17** — in Merge Mode, a charge spell whose buff is up keeps its charge count
   visible while the cell shows the buff duration (retail repro: Mage, Prismatic Barrier).

Nothing else. The Edit Mode fix lands before Phase 63 puts secure frames next to Edit Mode.

</domain>

<decisions>
## Implementation Decisions

### 999.9 — Edit Mode taint (settled in the backlog entry)
- **Delete the call; do not replace it.** `ns:SelectContainer` (`EditModeFrames.lua` ~line 168)
  loses the `pcall(EditModeManagerFrame.ClearSelectedSystem, ...)` block and its comment. No other
  mixin call, no direct `selectedSystem` write, no `HideSystemSelections` — each taints by the same
  mechanism (a Blizzard Edit Mode mixin method invoked from TBT's click handler).
- **Accepted cost:** Blizzard's yellow highlight and its popup may stay on a Blizzard system while a
  TBT container is also selected. Cosmetic, Edit-Mode-only; not a regression.
- Everything else about selection stays: mouse-down select (EDM-06), TBT's own overlay, the settings
  popup.
- Scan the rest of TBT for any other Edit Mode mixin method call from TBT code and report it in the
  SUMMARY (do not silently widen scope; fix only if it is the same pattern and one line).

### 999.17 — Merge Mode charge count (diagnose first)
- **Not diagnosed.** The backlog names two suspects in `Display.lua`; the plan must state which one is
  real, from reading the code, before changing anything:
  1. `ApplyMergedAuraCooldown` (~line 1399) swaps the cell's cooldown owner to the aura and returns
     early / nils `icon._cdGen`, while `ApplyChargeCount` (~line 1257) only runs inside the
     `_cdGen ~= ns.cooldownGeneration` block (~line 1672), so the charge text is never re-asserted
     (or is cleared) while the aura owns the sweep.
  2. With `ns.mergeAuraGroupsActive`, the engine-drawn aura overlay sits on top of the cell and
     covers the underlying icon's `chargeCount` — in which case the overlay needs its own count
     following the CDM's `ChargeCount` rule.
- **Match the CDM.** Read `Blizzard_CooldownViewer` (`CooldownViewer.lua`, the essential/utility
  item's charge-count refresh while an aura is applied) and mirror its rule: the count shows
  whenever the spell has charges, regardless of whether the aura owns the sweep.
- **Charge values may be secret** — every read keeps the existing `issecretvalue` / sticky
  `chargeCapable` handling of `ApplyChargeCount`. No new aura reads (DTRK-06 gate:
  `node scripts/aura-read-gate.js` must still pass).
- **No regression:** a charge spell with no active buff, and non-charge spells, render exactly as
  before; when the buff ends the cell returns to its cooldown with the right count.
- Hot path: this is the per-frame display path — no new per-frame allocation; any re-assert must be
  dirty-checked (the existing `_cdGen` / cached-value style).

### Claude's Discretion
- One plan or two (the fixes touch different files and are independent).
- Exact dirty-check mechanism for the charge re-assert.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ApplyChargeCount(icon, spellID)` — `Display.lua` ~1257; the sticky `chargeCapable` cache.
- `ApplyMergedAuraCooldown(icon, entry, now)` — `Display.lua` ~1399; call site ~1670
  (`local auraOwned = not userOwned and ApplyMergedAuraCooldown(icon, entry, now)`).
- `ns.mergeAuraGroupsActive` — set in `MergeMode.lua` (~1379, 1520, 1742); engine draws aura
  groups when true (`Display.lua` ~1819, ~2299).

### Established Patterns
- Generation counters (`ns.cooldownGeneration`, `icon._cdGen`, `icon._cdKey`) gate expensive
  re-applies; follow them rather than applying every frame.
- `MergeMode.lua` rule 1: never call a Blizzard mixin method on a CDM frame.

### Integration Points
- `EditModeFrames.lua` `ns:SelectContainer` (~150-180).

</code_context>

<specifics>
## Specific Ideas

- Repro for 999.17: retail Mage, Merge Mode on, Prismatic Barrier (charges) in the CDM, cast it.
  Expected, as on the CDM icon: buff duration sweep **and** the charge number at once.
- In-game checks are deferred to Phase 66 (one human testing pass, Forever then retail). This phase
  deploys with `./scripts/install.bat` but does not block on in-game UAT.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
