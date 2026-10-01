# Phase 57: Detailed Tracking — Visibility & Cross-Spell Rules - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning
**Mode:** Autonomous smart discuss — decisions taken with the user in one up-front batch covering Phases 56 and 57

<domain>
## Phase Boundary

Detailed trackers (Phase 56's `entry.detailed`) gain visibility modes driven by an aura, and
cross-spell rules: a buff tracker can end when another spell is cast, and a cooldown tracker can
reset when another spell is cast. Cooldown trackers also get an aura ID used only for visibility.

Requirements: DTRK-03, DTRK-05.

</domain>

<decisions>
## Implementation Decisions

### Visibility modes (DTRK-03) — semantics chosen by the user
| Mode | aura up | aura missing |
|---|---|---|
| **always** (default) | timer, as today | hidden, as today (container `hideWhenInactive` rules unchanged) |
| **present** | timer/icon — **including when the aura was cast by someone else**, started from the aura sighting, out of combat | hidden |
| **absent** | hidden | **reminder icon**: full colour, no timer |

- The mode is saved on the entry (e.g. `entry.visibility = "present"|"absent"`, nil = always).
  Runtime gates on `entry.detailed` (a tracker switched back to simple behaves as always).
- **Aura-driven start for "present":** copy Plainsrunning's `startFromAura` pattern
  (`RacialAuraTrigger`, Providers.lua ~1934-1960). It is guarded by `InCombatLockdown` and runs out
  of combat only: when the tracked aura (auraID or spellID) is seen and no proc is running, start
  the tracker. Without a cast, the duration is the entry's typed duration (or the aura's real
  expiration when readable, if that is cheap and safe; Claude's discretion).
- **"absent" reminder:** a full-colour icon with no sweep and no timer, drawn while the aura is known
  to be missing. It must show even when the container's `hideWhenInactive` would hide an idle
  tracker (cooldown slots are the precedent for bypassing it, Display.lua ~2253, ~2446).
- **Aura state cache, never read per frame:** the render runs at 20 Hz. Cache each detailed
  tracker's aura state (present / absent / unknown) on UNIT_AURA and at PLAYER_REGEN_ENABLED, through
  `ns:ReadPlayerAura` (keep its predicate gate). An unreadable read keeps the last known state
  (DTRK-06): **in combat the state is frozen** until a real read is possible. Initial state at
  login / reload: read once when possible, and "unknown" draws as the "always" behaviour.
- **Aura ID + "Cover all ranks" (decided in 56-REVIEW WR-04, "check both"):** a detailed buff
  tracker that covers all ranks and has an aura ID watches the aura ID AND every ID in its rank
  family, because a Forever rank's aura is its own ID. `ns:RebuildRankIndex` prebuilds that list as
  `ns.detailedRankFamilies[ownerKey]` (aura ID first, then the family), shared read-only like
  `ns.rankFamilies`. The aura-state cache must use the same list for such a tracker: "present" when
  any readable ID is up, "absent" only when every ID is readable and absent, "unknown" otherwise.
  Otherwise the watched list is `ns:DetailedAuraID(entry) or entry.spellID`, as before.
- **One predicate, used in the four Display places** the scout identified: `SlotDraws`
  (Display.lua ~86), the icon placeholder condition (~2477), the bar placeholder filter (~1998), and
  container activity (~1968, ~2253). Otherwise a reminder icon would be hidden by `hideWhenInactive`.
  Keep it allocation-free on the render path.
- Bars: "absent" on a bar-section tracker draws the idle bar as the reminder; "present" follows the
  timer. Claude's discretion on the exact bar look, matching the existing placeholder bar.

### Cooldown trackers (user decision: "Reset + visibility")
- Detailed userCd gets: an **aura ID used only for visibility** (the same Phase 56 aura-ID field
  shape: preview plus secret badge), the **visibility mode**, and **"Reset when you cast"**.
- For a cooldown, "present"/"absent" gate whether the cooldown slot draws at all (overriding
  "cooldown slots are always shown"). "always" stays the default. No aura-driven START for cooldowns;
  visibility only.

### Cross-spell rules (DTRK-05)
- One text box of comma-separated spell IDs. Label "Ends when you cast:" on buffs and "Resets when
  you cast:" on cooldowns. Below it, a line of small icons previewing each parsed ID, with unknown IDs
  marked. Validation rejects malformed input. Saved as a fresh array (the contract rule: "read
  returns a fresh table", "prefill copies"), e.g. `entry.endOnCast = { id, ... }`.
- **Ranks/overrides count:** expand each trigger ID through the rank/override family at index-build
  time (`ns:ResolveRankFamily` / base-override lookups) so a talent override or a Forever rank of B
  also triggers.
- **Reverse index built at rebuild time:** in `ns:RebuildCastIndex` (Core.lua ~870-905, called from
  RebuildRankIndex on add/update/remove/migration/world entry/SPELLS_CHANGED), build
  `ns.endKeysBySpell[spellB] = { key, ... }` fresh per rebuild. Only detailed entries with rules are
  indexed.
- **Cast path stays allocation-free:** one lookup plus a numeric loop in
  `UserSpellProviderMixin:OnTrigger`, as a side effect BEFORE the buff side decides its return
  (like the existing cooldown side effect). Buff: `ns.activeTimers[k] = nil`. Cooldown: clear
  `ns.cooldownStarts[k]` and `ns.cooldownOverrides[k]`, then `ns:MarkCooldownsDirty()`.
  - **Never end the key this same cast is about to start.** If B also starts A, end first then
    start, or skip A. Pick one and document it.
  - The dispatcher only redraws when a proc is returned. When the side effect ended something and
    no proc is returned, call `ns:UpdateDisplay()` itself (cooldowns: MarkCooldownsDirty suffices).
  - Works in combat: UNIT_SPELLCAST_SUCCEEDED's spellID is always safe.

### Claude's Discretion
- Entry field names, labels, the trigger-list max length, the icon-row layout, and the bar
  reminder look.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 56's `detailed` master checkbox, aura-ID field and helpers (build on them; capture the master
  through GetFieldState).
- `ns:ReadPlayerAura` (present / absent / unreadable), ScanActiveTimersForCancellation, and the
  PLAYER_REGEN_ENABLED rescan (Core.lua ~1201-1212).
- The indefinite-proc drawing (`SetCooldown(0,0)`, full bar) and placeholder drawing in Display.lua.
- RebuildCastIndex / RebuildRankIndex / ResolveRankFamily for the reverse index.

### Established Patterns
- Cooldown slots bypass `hideWhenInactive`.
- `startFromAura` for Plainsrunning (out of combat, InCombatLockdown-guarded).
- Rebuild-time allocation is fine; the cast and render paths allocate nothing.

### Integration Points
- Display.lua: SlotDraws, the placeholder branches, container activity.
- Providers.lua: OnTrigger side effects; UNIT_AURA provider dispatch for the aura-driven start.
- BuffEngine.lua / Core.lua: the aura-state cache refresh points.
- CDMTab.lua: TRACKER_FIELDS (the visibility selector, the triggers box, the cooldown aura-ID field).

</code_context>

<specifics>
## Specific Ideas

- The user's original framing (backlog 999.14/999.15): "alerting or even showing only when aura is
  lost". The "absent" reminder is the showing half; alerts stay in backlog 999.15.

</specifics>

<deferred>
## Deferred Ideas

- Alerts, visual and sound (backlog 999.15).
- Reading the CDM's aura state for in-combat visibility (backlog 999.16).

</deferred>
