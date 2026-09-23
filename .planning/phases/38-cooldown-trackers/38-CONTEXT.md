# Phase 38: Cooldown Trackers - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning
**Mode:** Decisions taken with the user up front, before the autonomous run

<domain>
## Phase Boundary

A spell cooldown becomes a first-class tracker type alongside buffs.

In scope: the cooldown tracker type, its icon-only rendering from a duration handle, charge counts,
preview support, and the schema migration that lets a buff-only database gain cooldown entries.
Out of scope: the add dialog that creates them (Phase 37), and steal mode's mirrored cooldowns
(Phase 40) — though both cooldown containers exist from Phase 35 and this phase is what fills them.
</domain>

<decisions>
## Implementation Decisions

### Rendering — icons only, engine-driven
- Cooldowns render as **icons only**, never bars. User decision: *"cooldowns are icons, and can have
  more than one charge"*. The two cooldown containers are icon containers.
- The sweep is driven by the **tier-1 duration-handle path**: `C_Spell.GetSpellCooldownDuration` handed
  to `Cooldown:SetCooldownFromDurationObject` (or `StatusBar:SetTimerDuration` where a bar is involved
  elsewhere). The engine animates it and tracks cooldown reduction live.
- **Nothing is read.** No per-frame reads, no secret value compared or concatenated. This is what makes
  it work in restricted combat where the aura APIs hard-error.
- Measured working 2026-09-20 on Forever with genuinely secret values: live handle returned total 25,
  remaining 7.471, percent 0.29884, and a handle is returned even when nothing is running (zeroed, with
  `IsActive() == false`).

### Charges
- **Match Blizzard's CDM exactly** — the same font string, position (bottom-right of the icon), font and
  size the `CooldownViewer` item uses. TBT already pixel-matches CDM's atlases and templates, and
  stolen CDM cooldowns will sit beside TBT's own in the same container from Phase 40, so any difference
  would show.
- Shown whenever the spell has charges; not conditionally hidden at one charge.

### Scope of spells
- A cooldown tracker must work for spells the **Blizzard CDM does not support** — that is the whole
  point of the feature, and the case `TOC`-era testing used (Escape Artist, a racial the CDM does not
  track).

### Migration
- A database created before this phase loads with every buff tracker intact. New cooldown entries
  survive logout→login on retail — the only client where persistence can be tested, since the Forever
  beta does not read saved variables back.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Display.lua:CreateTimerIcon` already builds an icon frame with a `CooldownFrameTemplate` cooldown
  child — the widget exists, and the change is what drives it.
- The provider architecture (`Providers.lua`) is where a cooldown tracker's trigger belongs;
  `UserSpellProvider` already owns user-added spells.
- `ns:GetDisplayInfoForKey` is the single display-data entry point for every tracker type.
- The per-widget icon cache (`cachedSpellID` / `cachedIcon`) — note its nil-vs-unpopulated trap, fixed
  2026-09-20 in `3c1acf2`; any new cache site needs the same `or cachedIcon == nil` guard.

### Established Patterns
- Timers are `expiresAt = GetTime() + duration`, keyed by `proc.key`. A cooldown is **not** that shape —
  it is a handle the engine owns. Do not force it into the existing `activeTimers` model without
  deciding deliberately how `ns:GetActiveTimers` reports it.
- The normalised 9-field proc shape, with `proc.spellID` always numeric, drives icon, tooltip and
  cancellation.
- Additive preview: `ns.previewTimers` is separate from real timers and `StartAllPreviewTimers` skips
  running slots, using `ns:GetDisplayInfoForKey` as its sole data source.

### Integration Points
- `ScanActiveTimersForCancellation` is aura-driven and is disabled under `ShouldAurasBeSecret()`
  (`BuffEngine.lua:388`). Cooldowns have nothing to cancel — do not route them through it.
- `C_Spell.GetSpellCooldownDuration` is `AllowedWhenTainted` with no secrecy flag. The returned
  `LuaDurationObject` is a **userdata handle, not a secret value** — the `SecretArguments` tier never
  applies to passing it back into a widget setter.
</code_context>

<specifics>
## Specific Ideas

"Icon with charges, both new bars will have cooldowns, and cooldowns are icons, and can have more than
one charge."
</specifics>

<deferred>
## Deferred Ideas

- Trinket and consumable cooldowns via the same mechanism (`C_Item` equivalents) — not requested, and
  the Trinket/Pot meta-trackers already cover that ground by cast detection.
- Cooldowns as bars. Explicitly excluded; revisit only on request.
</deferred>
