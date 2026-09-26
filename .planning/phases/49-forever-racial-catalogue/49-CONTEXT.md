# Phase 49: Forever Racial Catalogue - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning
**Source:** Synthesised from `.planning/research/FOREVER-RACIALS.md` — the collection log and the
seven locked decisions the user made in session on 2026-09-24. No separate discuss-phase was run
because the discussion already happened, in full, against live in-game data.

<domain>
## Phase Boundary

Implement every Forever racial as its own race-gated tracker entry, replacing the two generic
`racial` / `racial2` slots that `Providers.lua` uses today.

**All data collection is finished.** Ten races, every racial, every spell ID, duration and cooldown,
recorded in `.planning/research/FOREVER-RACIALS.md`. This phase writes code; it does not gather data
and must not block on gathering any.

**In scope:** the `RACIAL_SPELLS` table for all ten races; the per-racial race-gated tracker model
(RACE-10) including migration; the no-duration guard; the indefinite buff tile; aura-driven start
for Plainsrunning; the Skyborne short-then-correct duration.

**Out of scope:** retail racials (`RACE-06`, deferred again at milestone kickoff); any general
"state tracker" feature beyond the two members named below; dispel/pandemic work (Phases 48/48.1,
closed).
</domain>

<decisions>
## Implementation Decisions

Every item here is **locked** — settled with the user on 2026-09-24. `D-n` numbers match the
Decisions section of `FOREVER-RACIALS.md`; read that file for the evidence behind each.

### D-4 / RACE-10 — the model change (the largest piece)
- **One tracker entry per racial**, keyed distinctly. `item:<itemID>` is the established precedent;
  `racial:<spellID>` is the obvious analogue but the exact format is Claude's discretion.
- **Visible only to its own race.** A troll sees their two racials in Suggested under *both* Buffs
  and Cooldowns. An orc sees the orc racials and **no trace of the troll ones — not in Suggested and
  not in any container.**
- **Race-gating applies at render time, not only in Suggested.** Gating Suggested alone would leave
  another race's racials sitting in a container.
- **Placement is account-wide and per racial.** Move Berserking to a container on one troll and
  every other troll finds it there. Follows from the existing account-wide `TerribleBuffTrackerDB`.
- **A tracked racial leaves Suggested**, exactly as an `item:` key already does (ITEM-02).
- **Migration is required**: existing `racial` / `racial2` entries become the new per-racial keys, or
  players lose their placements.

### D-7 / RACE-09 — obsolete, do not implement
RACE-10 deletes the generic racial tile the "not yet supported" message lives on, so the requirement
has no subject. `RACIAL_SUPPORTED_LINES` and `RACIAL_UNSUPPORTED_LINES` (`Providers.lua:814-819`)
become dead code and should be removed. **Accepted consequence:** a future Forever race sees no
racial tile and no explanation.

### The no-duration guard — prerequisite for everything else
`StartRacialProc` does `proc.expiresAt = now + def.duration` unguarded. **Four cooldown-only racials
across three races** (Will of the Forsaken, War Stomp, Cultivation, and Find Treasure's cooldown
absence) mean a row without a `duration` raises on first cast. Build this before entering any row.

### D-1 / D-6 — Shadowmeld
- Indefinite buff tile, **no countdown**.
- Ended when an aura read positively reports aura `20580` missing — reuse
  `ScanActiveTimersForCancellation` (`BuffEngine.lua:637`), which never concludes absence from an
  unreadable result. This is an `aliveBuffs` assignment, not a new mechanism.
- **Also cleared immediately on entering combat.** Aura reads are secret in combat for a tainted
  caller, so the scan cannot see the drop there.
- **Keeps its 10s cooldown tile** (user reversed an earlier decision to drop it).

### D-6 — Find Treasure
Indefinite buff tile, no countdown, same positive-absence clearing. **No cooldown tile — it has no
cooldown**, so this falls out of the data rather than needing a rule.

### D-2 — Plainsrunning (tauren) is in scope
Same shape as Shadowmeld: visible out of combat, gone in combat, ended by the aura going absent.
**Structural difference to solve: it has no cast.** Every existing racial proc starts from
`UNIT_SPELLCAST_SUCCEEDED`; this is a passive simply *present* out of combat, so it needs an
aura-driven start. `UNIT_AURA` is already routed through provider dispatch (`BuffEngine.lua:695`).

### D-3 — Skyborne conditional duration (both factions)
Always start on the **short** duration (Elemental Blessing 30s, Energized 15s). **Out of combat,
read the aura's real duration and correct upward** when the 15-minute version is detectable. A
racial that under-runs is recoverable; one hanging 14 minutes past its buff is not. Degrades
correctly: the read fails in combat and works out of it, and the long version is acquired out of
combat.

### D-5 — Cultivation (tauren)
Trigger on **20552 only, no fallbacks.** 1312643 and 1312650 are documented but deliberately
unwired. Knowingly accepted: a press reporting one of those starts no tracker.

### Claude's Discretion
- The exact key format for a racial entry.
- How race-gating is implemented at render time (filter in the render path, at mirror-build time, or
  at DB read).
- Migration mechanics and where the migration runs.
- How an indefinite tile is represented internally (sentinel expiry, a flag, or a separate path).
- Task and plan decomposition.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The data and the decisions
- `.planning/research/FOREVER-RACIALS.md` — **the single source for this phase.** All ten races with
  spell IDs, durations and cooldowns; decisions D-1..D-7 with their reasoning; the answered and
  closed open questions. Every table row to be written is already in here, several as paste-ready
  Lua blocks.

### Code this phase changes
- `Providers.lua:772-819` — `RACIAL_SPELLS`, `RACIAL_SLOT_BY_KEY`, `ns.RACIAL_KEYS`,
  `RACIAL_SUPPORTED_LINES`, `RACIAL_UNSUPPORTED_LINES`
- `Providers.lua:~826-900` — `ResolveRacial`, `ns:RacialCooldownKeys`, `ns:RacialCooldownSeed`
- `Providers.lua:~1344-1500` — `RacialProviderMixin`, `StartRacialProc`, `ConsumeRacialStack`
- `BuffEngine.lua:637` — `ScanActiveTimersForCancellation`, the `aliveBuffs` mechanism
- `BuffEngine.lua:34` — `ns:ReadPlayerAura`, and why it gates on `ShouldSpellAuraBeSecret`
- `Core.lua` — `/tbt debug` racial collection tooling added this phase

### Patterns to follow rather than invent
- **`item:<itemID>`** (Phases 46-47) — the precedent for a dynamically-keyed tracker that appears in
  Suggested, leaves it once tracked, and resolves display info through `ns:GetDisplayInfoForKey`.
  `Providers.lua:1547` (`GetDisplayInfoForKey`) and `Core.lua:515` (`ns:ItemKeyItemID`).
- `CLAUDE.md` — secret-value rules, the one-TOC constraint, and the stylua/CRLF workflow.
</canonical_refs>

<specifics>
## Specific Ideas

- **Ten races**, including two Forever-only Skyborne entries at raceID **95** (Alliance, High Order)
  and **96** (Horde, Windshaper). They share Walk on Air exactly and differ on the second racial, so
  neither block can be derived from the other.
- **Gnome Eureka! must be corrected to `cooldown = 120`.** `Providers.lua:800` says 180; the beta
  changed it. Phase 41's entry was right when written — this is drift, not a bad entry.
- **Orc's `fallbackLabel = "Orc Racial"` placeholder resolves to "Shatter Curse."**
- `fallbackLabel` always takes the **cast** name, never the aura's, where they differ (Skysight →
  Elemental Blessing, Read Ley Line → Energized, Cannibalize → aura 20578).
- Cast ID and aura ID diverge on three racials. **No `auraID` field is needed** — nothing reads a
  racial's aura ID today, because `StartRacialProc` deliberately carries no `aliveBuffs`. Shadowmeld,
  Find Treasure and Plainsrunning are the exceptions that now *do* need one.
</specifics>

<deferred>
## Deferred Ideas

- **Retail racials (`RACE-06`)** — deferred again at v0.4.1 kickoff; this milestone is Forever only.
- **A general "state tracker" feature.** Plainsrunning and Find Treasure are handled as named cases.
  If more combat-gated or toggle passives appear, they want one shared mechanism rather than N
  special cases — not this phase.
- **Whether the Skyborne long-duration aura has a different aura ID.** The user is still testing.
  It no longer blocks: D-3 ships the short duration either way, and the answer only decides whether
  the upward correction looks up one aura ID or two.
- **Whether Forever has races beyond these ten.** New IDs appear without warning (95/96 are far
  outside the classic 1-11 block), so nothing can be inferred — each would need its own pass.
</deferred>

---

*Phase: 49-forever-racial-catalogue*
*Context synthesised 2026-09-24 from the in-session decision record.*
