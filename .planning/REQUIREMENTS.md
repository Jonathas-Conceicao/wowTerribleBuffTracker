# Requirements — v0.5.2 Improved Merge Mode and small fixes

**Defined:** 2026-10-10, at kickoff, with the user. Research skipped:
`.planning/research/MERGE-REANCHOR-POC.md` and backlog 999.26 in `ROADMAP.md` are the settled design.

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces
automatically.

**Scope, set by the user:** Merge Mode moves Blizzard's own CDM frames into TBT's layout instead of
redrawing them (999.26), and the redraw path is deleted rather than kept as a fallback. That closes
the Merge Mode bugs 999.21-999.24 by deletion; each is re-checked in game, and 999.24's requirement
carries over — nothing may paint one thing over every cell. 999.25 is treated as obsolete and
re-checked. Racials are removed from TBT entirely, because Forever's recent release supports them
natively and TBT never built retail racials. Then a cleanup phase and one human testing pass, on
retail including M+ and on Forever.

## v0.5.2 Requirements

### Merge Mode moves Blizzard's frames (backlog 999.26)

- [x] **STEAL-10**: With Merge Mode on, every merged CDM entry is drawn by Blizzard's own CDM item
  frame. It is placed on its TBT slot and sized to TBT's icon, or for bars to the row's height and
  width. TBT draws nothing of its own on a merged slot. Cooldowns, charges, aura timers, glows,
  pandemic and dispel borders look exactly as they do on the CDM.
- [x] **STEAL-11**: Merged entries follow TBT's layout: order, direction, Centered and padding. They
  share a container with the player's own trackers, and nothing overlaps.
- [x] **STEAL-12**: TBT moves and styles Blizzard's frames using only plain C widget setters on the item
  frames and their child regions (position, scale, size, alpha, mouse, shown state, countdown and
  swipe setters), plus one `hooksecurefunc` on each viewer's `Layout`. No `SetParent`, no field
  writes, no mixin calls. *(Widened 2026-10-10 from position/scale/width only, by the user's
  decision that every container setting applies to the moved frames.)* No taint error through combat, Edit Mode, combat while
  Edit Mode is open, a spec change, or M+.
- [x] **STEAL-13**: Reordering an entry in the CDM settings window, or moving it to another category,
  updates TBT's preview right away to match the CDM. No entry lands in the wrong container, and no bar
  is mis-sized or misaligned.
- [x] **STEAL-14**: Edit Mode preview shows every merged entry, bars included.
- [x] **STEAL-15**: A TBT container hidden by its visibility setting also hides the merged frames
  placed in it, and showing it brings them back.
- [x] **STEAL-16**: Resizing the CDM, or changing its settings, does not change how big merged frames
  are in TBT. TBT's own container settings control their size.
- [x] **STEAL-17**: A frame is re-placed only when its slot or size changes, or when Blizzard re-lays
  out its viewer — never on every display refresh.
- [x] **STEAL-18**: Turning Merge Mode off returns every moved frame to its Blizzard viewer and
  restores the viewers' positions, without `/reload`.
- [x] **STEAL-19**: The old redraw path is removed: the engine aura containers, merged aura timing
  reads, bar and time relays, merged pandemic/dispel reads, and the merged charge-count path. The
  `/tbt reanchor` toggle and its saved flag go too.

### Merge Mode bugs (backlog 999.21-999.25), verified on the new path

- [x] **STEAL-20**: After a spec change, a merged charge spell shows the right count without `/reload`
  (999.21, Frost Orb).
- [x] **STEAL-21**: A debuff another player put on the target — another Frost Mage's Freezing,
  another mage's Touch of the Magi — never shows as the player's own and never overlaps other slots
  (999.22, 999.23).
- [x] **STEAL-22**: While mind-controlled, no merged slot shows an aura it does not own. A review of
  the whole Merge Mode path finds no way for one aura or frame to be painted over every cell (999.24).
- [x] **STEAL-23**: A Centered container re-centres as merged buffs come and go (999.25).

### Racials removed

- [x] **RACE-11**: TBT offers no racial trackers on any client: no racial Suggested tiles, no racial
  meta-tracker, no racial catalogue.
- [x] **RACE-12**: Nothing racial is left in the code: the catalogue, the provider, the racial tracker
  kinds, the racial Suggested entries, and the display of racial stack counts are all gone.
- [x] **MIG-03**: Loading saved data that holds racial trackers removes them through a schema
  migration, with no errors, leaving every other tracker untouched. `scripts/migrate-dryrun.js` proves
  it against a real SavedVariables file.

### Verification

- [x] **VER-12**: No cooldown icon stays grey through the GCD on either client (999.5), checked in the
  testing pass.

## Process-only phases

As in earlier milestones, with no requirements of their own: a **Cleanup** phase (CLAUDE.md's
mandate for duplication this milestone introduces; `PROJECT.md`'s "No refactors during cleanup
phases" protects everything older), then **one Human Testing** pass — retail including M+, and
Forever.

## Closed without a requirement

- **999.20** — recorded in error on 2026-09-30. Custom buff icons have always shown their countdown
  number; the note was most likely carried over from the reminder-countdown fix (`064f76c`) that
  afternoon. 61-HUMAN-UAT #2 now waits on 999.19 alone.

## Future Requirements

- **999.11** profiles, **999.15** alerts, **999.16** CDM state for spells also in the CDM, **999.19**
  stack count on custom trackers — stay in the ROADMAP Backlog.

## Out of Scope

- **Keeping the old redraw path as a fallback** — rejected by the user at kickoff: it would keep
  999.21-999.24 alive on that path and double the code to maintain.
- **Retail racials (`RACE-06`)** — dropped with the racial feature; not deferred.
- **Restyling Blizzard's frames beyond size and position** (borders, fonts, textures) — writing into
  their regions is a larger taint risk than moving them; the POC showed Blizzard's own look is wanted.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RACE-11 | Phase 67 | Complete (verified in game, Phase 72) |
| RACE-12 | Phase 67 | Complete (verified in game, Phase 72) |
| MIG-03 | Phase 67 | Complete (verified in game, Phase 72) |
| STEAL-10 | Phase 68 | Complete (verified in game, Phase 72) |
| STEAL-11 | Phase 68 | Complete (verified in game, Phase 72) |
| STEAL-12 | Phase 68 | Complete (verified in game, Phase 72) |
| STEAL-16 | Phase 68 | Complete (verified in game, Phase 72) |
| STEAL-17 | Phase 68 | Complete (verified in game, Phase 72) |
| STEAL-18 | Phase 68 | Complete (verified in game, Phase 72) |
| STEAL-13 | Phase 69 | Complete (verified in game, Phase 72) |
| STEAL-14 | Phase 69 | Complete (verified in game, Phase 72) |
| STEAL-15 | Phase 69 | Complete (verified in game, Phase 72) |
| STEAL-19 | Phase 70 | Complete (verified in game, Phase 72) |
| STEAL-20 | Phase 70 | Complete (verified in game, Phase 72) |
| STEAL-21 | Phase 70 | Complete (verified in game, Phase 72) |
| STEAL-22 | Phase 70 | Complete (verified in game, Phase 72) |
| STEAL-23 | Phase 70 | Complete (verified in game, Phase 72) |
| VER-12 | Phase 72 | Complete (not seen on either client) |

**Coverage:** 18 / 18 v0.5.2 requirements mapped, none orphaned or duplicated. Phase 71 (Cleanup)
carries no requirement by design.
