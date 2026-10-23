# Phase 70: Remove the Redraw Path & Close the Merge Mode Bugs - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning
**Mode:** Smart discuss, front-loaded for the whole autonomous run (67-71) at the user's standing request

<domain>
## Phase Boundary

Re-anchoring becomes the only Merge Mode path: the old redraw machinery is deleted (STEAL-19), and the
Merge Mode bugs 999.21-999.25 are closed by that deletion and checked (STEAL-20..23), including a
written review of the whole Merge Mode path proving nothing can paint one aura or frame over every
cell (999.24's requirement).

</domain>

<decisions>
## Implementation Decisions

### What is deleted (STEAL-19)
- Engine aura containers: `AURA_UNITS`, `auraContainers`, `slotFilters`, `SyncEntryContainers`,
  `SendSlotFilters`, `SlotAllowed`, `RefreshTargetAssistable`, `ns:RefreshMergeAuraGroups`,
  `ns:PlaceMergeAura`, `ns:RefreshMergeAuraUnits`, `DisableAuraGroups`, the aura-frame initializers,
  `ns.mergeAuraGroupsActive` and every Display branch keyed on it (`engineDrawsHere`).
- Merged aura timing: `ResolveMergedAuraTiming`, `TryResolveFromSpellID`, `SafeAuraCall`,
  `AuraSpellName`, `TARGET_AURA_FILTERS`, the aura-lookup latch.
- Relays: `RelayMergedBar`, `RelayMergedIconTime`, `MatchMergedTimeFont`, `icon.mergedTime`.
- Merged pandemic/dispel reads: `ReadPandemicState`, `ReadDispelBorder`, `ns:IsMergedEntryInPandemic`
  and the Display FX/border calls for merged slots — Blizzard draws its own. TBT's own pandemic/dispel
  code survives only if a non-merged tracker uses it; otherwise delete.
- Merged branches of `ApplyCooldownSlot` / `ApplyChargeCount` / `ApplyMergedAuraCooldown` and the
  `chargeCapable` cache if only merged slots used it (custom cooldown trackers may still need charges —
  check).
- The `/tbt reanchor` toggle, `ns.db.mergeReanchorExperiment` (cleared from saved data — piggyback on
  the next migration or a defaults cleanup; silent), and every `EXPERIMENT (MergeReanchor.lua)` comment
  marker (the code they mark becomes the real path).
- `scripts/aura-read-gate.js` allowlist entries for readers that no longer exist (keep the gate passing).
- `/tbt merge` diagnostics **stays**, trimmed to what still exists (mirror, shown slots, placement).

### Bug closures (STEAL-20..23)
- Verified by code reasoning plus a deferred in-game check each. Checks that need another Frost Mage,
  another mage, or being mind-controlled are **deferred to Phase 72** (user decision); record them in
  the verification as human items.
- 999.21 Frost Orb charges after a spec change: Blizzard's own frame shows the charges; confirm the
  mirror rebuild on `PLAYER_SPECIALIZATION_CHANGED` re-attaches correctly.
- 999.22/23: TBT no longer reads target auras at all; confirm.
- 999.25 Centered: confirm `SlotDraws` / `cdmShown` path re-centres with merged-only containers.

### Whole-path review (STEAL-22)
- Written to `.planning/phases/70-.../70-MERGE-PATH-REVIEW.md`: every path from an event to a pixel in
  Merge Mode, and why none can paint one aura/frame over every cell (e.g. one frame attached to many
  cells, a cell map that can fan one id out, an unfiltered aura source). Any route found is fixed in this
  phase.

### Claude's Discretion
- Order of deletion; keep `stylua .`, `aura-read-gate.js --selftest` and `migrate-dryrun.js --selftest`
  green at every commit.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- POC "What the real implementation could remove" list in `.planning/research/MERGE-REANCHOR-POC.md`.

### Established Patterns
- STEAL-08 audit grep conventions in `MergeMode.lua` comments (names written by description so audit
  greps stay true negatives) — keep or retire consistently.

### Integration Points
- `MergeMode.lua` (~2900 lines) holds most of the deleted code; `Display.lua` merged branches;
  `Core.lua` slash commands.

</code_context>

<specifics>
## Specific Ideas

- If a file leaves the TOC (e.g. `MergeReanchor.lua` folded into `MergeMode.lua`), testing needs a full
  client restart — note it for Phase 72.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
