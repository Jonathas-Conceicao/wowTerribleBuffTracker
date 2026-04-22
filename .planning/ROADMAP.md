# Roadmap: TerribleBuffTracker

## Milestones

- [x] **v0.2.0 Config & Edit Mode Rework** — Phases 1-6 (shipped 2026-03-30) — [archive](milestones/v0.2.0-ROADMAP.md)
- [x] **v0.2.1 Aura-Based Timer Cancellation** — Phases 7-11 (shipped 2026-04-04) — [archive](milestones/v0.2.1-ROADMAP.md)
- [x] **v0.2.3 Trinket & Pot Meta-Trackers** — Phases 12-16 (shipped 2026-04-13) — [archive](milestones/v0.2.3-ROADMAP.md)
- [x] **v0.2.4 SpellProvider Refactor** — Phases 17-24 (shipped 2026-04-22) — [archive](milestones/v0.2.4-ROADMAP.md)

## Phases

<details>
<summary>v0.2.0 Config & Edit Mode Rework (Phases 1-6) — SHIPPED 2026-03-30</summary>

- [x] **Phase 1: Data Migration** — Expand SavedVariables schema and backfill existing entries
- [x] **Phase 2: Edit Mode Containers** — Two independently movable containers registered with Edit Mode
- [x] **Phase 3: CDM Tab Shell** — Tab button injection and content panel frame; old config UI removed
- [x] **Phase 4: CDM Tab Sections** — Four sections rendered from DB state with Add button and delete drop zone
- [x] **Phase 5: Drag-and-Drop** — Buff drag between sections with ghost frame, drop zone highlighting, and delete zone
- [x] **Phase 6: Cleanup** — Dead code removal, hot-path audit, stylua, release prep

</details>

<details>
<summary>v0.2.1 Aura-Based Timer Cancellation (Phases 7-11) — SHIPPED 2026-04-04</summary>

- [x] **Phase 7: Safety Infrastructure** — Grace period, blocked flag, reset triggers, and preview guard wired before any scan logic
- [x] **Phase 8: Aura Scan and Cancellation** — UNIT_AURA handler and scan function that silently cancel timers for absent buffs
- [x] **Phase 9: Zone Transition Handling** — Post-login and zone-exit scans to catch buffs stripped by loading screens
- [x] **Phase 10: Lust Tracking** — Sated-family debuff detection auto-starts lust timer; class-aware meta-buff icon in CDM tab
- [x] **Phase 11: Cleanup** — Hot-path audit, stylua, recentlyCast table growth check, release prep

</details>

<details>
<summary>v0.2.3 Trinket & Pot Meta-Trackers (Phases 12-16) — SHIPPED 2026-04-13</summary>

- [x] **Phase 12: Schema Migration + Data Tables** — TRINKET_SPELLS (9) / POT_SPELLS (4) spellID-keyed tables, SUGGESTED_BUFFS entries, DATA-03 N/A reconciliation
- [x] **Phase 13: Timer Functions + Cast Detection** — OnSpellCastSucceeded fan-out with metaSlot tagging and shared-slot overwrite; in-game spell ID verification
- [x] **Phase 14: Icon Resolution + Caching** — ns.metaIcons cache, RefreshMetaIcons (combat-gated CSV-order fallback), GetAtRestMetaIcon helper, StartPreview hook, Display placeholder fix; ICON-06 N/A reconciliation
- [x] **Phase 15: Display Integration + Active Icon Switching** — Verification-only (ICON-03/04 satisfied by Phase 13 + 14 architecture)
- [x] **Phase 16: Cleanup** — stylua pass, dead-code scan (no-op), CHANGELOG v0.2.3 entry, PROJECT.md Validated block, .pkgmeta release-notes annotation

</details>

<details>
<summary>v0.2.4 SpellProvider Refactor (Phases 17-24) — SHIPPED 2026-04-22</summary>

- [x] **Phase 17: Provider Skeleton + UserSpellProvider** — Providers.lua with interface contract; UserSpellProvider wired through dispatch loop
- [x] **Phase 18: TrinketProvider + PotProvider + BuffEngine Dispatch** — All cast-triggered providers active; BuffEngine dispatch loop replaces hardcoded branches; activeProcs lifecycle established
- [x] **Phase 19: LustProvider + UNIT_AURA Dispatch** — LustProvider with pre-gate ordering; UNIT_AURA routed through provider dispatch; all four providers complete
- [x] **Phase 20: GetDisplayInfo + Dispatch Helper** — GetDisplayInfo on all four providers; ns:GetDisplayInfoForKey exported; provider-owned RefreshAtRest (PROV-F3 pulled forward); trinket/pot 0-second preview bug fixed at provider layer
- [x] **Phase 21: Preview Mode Migration** — Additive preview architecture; separate ns.previewTimers; fixes mid-CDM real-cast loss as architectural side-effect
- [x] **Phase 22: Display.lua Unification** — Zero type-specific branches; single shared tooltip handler; per-widget icon cache
- [x] **Phase 23: CDMTab.lua Unification** — All icon/tooltip resolution through ns:GetDisplayInfoForKey; META_DESCRIPTIONS demoted to file-local
- [x] **Phase 24: Cleanup** — Dead code removal (3 shims + 2 exports), RefreshMetaIcons → RefreshProvidersAtRest rename, stylua pass, v0.2.4 CHANGELOG, interface 120005 bump

</details>

## Backlog

### Phase 999.1: Edit Mode container selects on click-release instead of click-down (BACKLOG)

**Goal:** Match Blizzard's native Edit Mode selection behavior — TBT containers (bars/buffs) should highlight and open settings popup on mouse-DOWN, not mouse-UP. Currently the container only appears selected after releasing the click, which makes drags feel laggy because the highlight doesn't appear during the drag motion.

**Requirements:** TBD

**Context:**
- Reported in v0.2.4 Phase 18 human-verify session (2026-04-21)
- Affected files: `EditModeFrames.lua` — check OnMouseDown vs OnMouseUp handlers on `TBTBarContainer` / `TBTBuffContainer`
- Reference: Blizzard's `EditModeSystemTemplates.lua` in `wow-ui-source` at `C:\Users\jonat\Repositories\wow-ui-source`

Plans:
- [ ] TBD (promote with `/gsd:review-backlog` when ready)
