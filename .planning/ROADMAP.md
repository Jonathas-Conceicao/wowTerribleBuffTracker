# Roadmap: TerribleBuffTracker

## Milestones

- [x] **v0.4.0 Cooldown Tracking and Full CDM View** — Phases 31-45 (shipped 2026-09-23) — [archive](milestones/v0.4.0-ROADMAP.md)
- [x] **v0.3.0 WoW Forever compatibility** — Phases 25-30 (shipped 2026-09-19) — [archive](milestones/v0.3.0-ROADMAP.md)
- [x] **v0.2.0 Config & Edit Mode Rework** — Phases 1-6 (shipped 2026-03-30) — [archive](milestones/v0.2.0-ROADMAP.md)
- [x] **v0.2.1 Aura-Based Timer Cancellation** — Phases 7-11 (shipped 2026-04-04) — [archive](milestones/v0.2.1-ROADMAP.md)
- [x] **v0.2.3 Trinket & Pot Meta-Trackers** — Phases 12-16 (shipped 2026-04-13) — [archive](milestones/v0.2.3-ROADMAP.md)
- [x] **v0.2.4 SpellProvider Refactor** — Phases 17-24 (shipped 2026-04-22) — [archive](milestones/v0.2.4-ROADMAP.md)

## Phases

<details>
<summary>✅ v0.4.0 Cooldown Tracking and Full CDM View (Phases 31-45) — SHIPPED 2026-09-23</summary>

**Block A — backlog cleanup (Phases 31-34).** Small, separate, and first. `TOC-06` is a hard blocking
gate and runs alone.

- [x] **Phase 31: Single TOC** — one unsuffixed `TerribleBuffTracker.toc` declaring `## Interface: 120100, 16001`, following the pattern shipping Forever addons already use; `_Camelot.toc` and `check-toc.ps1` deleted
- [x] **Phase 32: Single-Zip Packaging** — one `.pkgmeta`, one packaging job, one zip; both `.pkgmeta-*` and the two-flavour CI matrix retired
- [x] **Phase 33: Install & Release Tooling** — `install.bat` substitutes a real dev version into the deployed TOC only, prunes stale files, and reads one shared file list; `release.bat` gains a branch guard
- [x] **Phase 34: Edit Mode Selection on Mouse-Down** — a TBT container highlights and opens its settings popup on mouse-DOWN, so the highlight is visible during the drag

**Block B — the three features (Phases 35-41).** Built and tested on the Forever beta as they land.

- [x] **Phase 35: Four Base Containers & Saved-Position Migration** — Tracked Buffs, Tracked Bars, Essential Cooldowns, Utility Cooldowns; names pinned, undeletable, independently movable, with the v0.3.0 database migrated without loss
- [x] **Phase 35.1: Config Panel (RENUMBERED from 39)** — a gear square beside the `+` button turns the tab page into an addon-wide config panel, and back again; it holds the steal-mode toggle **and container create/delete**, which is why it was renumbered to run before the user-containers phase rather than after
- [x] **Phase 36: User Containers & Per-Container Settings** — user-created containers with their own scale, padding, orientation, items-per-row and bar width; trackers move between containers
- [x] **Phase 37: Redesigned Add Panel & Rank Grouping** — buff-or-cooldown choice, container choice, and the "cover all ranks" checkbox (Forever only, by explicit version check); ranked spell IDs reconcile with the CDM's
- [x] **Phase 38: Cooldown Trackers** — cooldowns as a tracker type, icons only, charge counts, rendered from the tier-1 duration handle so they stay correct in combat and follow cooldown reduction live
- [x] **Phase 40: CDM Steal Mode** — all-or-nothing across all four categories: Blizzard's CDM containers hide and their items are **mirrored** into TBT's matching containers. TBT never injects into, parents into, or writes to a Blizzard CDM frame
- [x] **Phase 41: Racial Meta-Tracker (Eureka! only)** — Eureka! fully implemented including cast-driven stack consumption with the nominal timer as backstop; every other racial marked *not yet supported*

**Block C — closing sequence (Phases 42-45).** Cleanup and the Forever pass were SWAPPED on
2026-09-22 by user decision: clean the code up first, then run the full review against the cleaned
code. Verifying code that is about to be rewritten gets the order backwards.

- [x] **Phase 42: Cleanup** — unify the duplication *this milestone* introduced, hot-path audit, dead-code sweep, stylua, release scripts reviewed. Pre-existing code is not refactored, with one recorded exception: the two render functions
- [x] **Phase 43: Forever End-to-End Verification Pass** — every v0.4.0 feature exercised on the Forever beta on a named build, across the four contexts that broke things during the experiments
- [x] **Phase 44: Retail Validation Pass (M+ and raid)** — the only retail exercise in the milestone; no retail probing was done during the experiment phase
- [x] **Phase 45: Documentation & Release Prep** — README, CurseForge/Wago copy and an **appended** CHANGELOG entry, written last, immediately before merge and release

**Closed:** 58/58 requirements. **Plans:** 34 across 13 plan-driven phases; Phases 43 and 44 ran as in-game testing passes with no plans.
**Verified on:** Forever beta `1.60.1.69913` (2026-09-21→22) and Midnight retail 12.1.x including Mythic+ and a raid encounter (2026-09-23).
**Known at ship:** Forever settings do not persist between sessions (a client bug); in restricted content a buff can overhang its typed duration and charge counts can be blank; no real tag push has happened, so `DIST-09`…`DIST-12` are verified locally only.

</details>

<details>
<summary>✅ v0.3.0 WoW Forever compatibility (Phases 25-30) — SHIPPED 2026-09-19</summary>

- [x] **Phase 25: TOC Split & Retail Regression Gate** — `TerribleBuffTracker_Mainline.toc` (120100) + `TerribleBuffTracker_Camelot.toc` (16001) from one shared file list, plus `scripts/check-toc.ps1` as a pre-tag drift guard. Both in-game gates PASSED 2026-09-18
- [x] **Phase 26: Install Tooling** — argument-free `install.bat` deploying the shared file set and both TOCs to every present WoW client, skipping absent ones, failing when none are found
- [x] **Phase 27: Provider At-Rest Defensive Fix** — Trinket and Pot tiles no longer present an unresolved hardcoded item as real; shared neutral placeholder. Verified on both flavours
- [x] **Phase 27.1: Forever Testing Enablers (INSERTED)** — TOOL-01 spell+aura ID tooltip, META-01 data-driven meta-tile hide, lust tooltip fix, drag nil-call fix. Inserted mid-milestone on user approval because the milestone was otherwise untestable
- [x] **Phase 28: Forever In-Game Verification Pass** — build `1.60.1.69913`, zero failures. `UNIT_SPELLCAST_SUCCEEDED` confirmed to deliver a usable spellID; two Forever-only defects found and fixed
- [x] **Phase 29: Packaging & Distribution** — `.pkgmeta-mainline`/`.pkgmeta-camelot` and a serialised two-flavour matrix in `release.yml`. Implementation complete; `DIST-03`…`DIST-07` deferred to the first real tag push by user decision
- [x] **Phase 30: Cleanup** — dead `TRINKET_FALLBACK_ORDER` removed, `stylua.toml` + `.gitattributes` root-cause fix for the invisible-diff bug, hot-path audit verdict `NONE`, release scripts reviewed end to end

**Closed:** 25/30 requirements. **Deferred to first release:** `DIST-03`…`DIST-07` — **superseded 2026-09-20** by v0.4.0's single-TOC / single-zip decision and restated there as `DIST-09`…`DIST-12`.
**Known issue at ship:** settings do not persist between sessions on the Forever beta — a client-side bug, not TBT's.

</details>

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


## Phase Details

*All phases through v0.4.0 (Phases 1-45) are archived under `.planning/milestones/`. The most recent
is [`v0.4.0-ROADMAP.md`](milestones/v0.4.0-ROADMAP.md), which carries the full detail for Phases
31-45 including each phase's status block, success criteria and the notes recorded as it ran.*

*This section fills again when the next milestone's phases are planned. Phase numbering never
restarts — the next milestone begins after Phase 45.*

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 31. Single TOC | v0.4.0 | 1/1 | Complete | 2026-09-20 |
| 32. Single-Zip Packaging | v0.4.0 | 1/1 | Complete | 2026-09-20 |
| 33. Install & Release Tooling | v0.4.0 | 1/1 | Complete | 2026-09-20 |
| 34. Edit Mode Selection on Mouse-Down | v0.4.0 | 1/1 | Complete | 2026-09-20 |
| 35. Four Base Containers & Migration | v0.4.0 | 4/4 | Complete | 2026-09-21 |
| 35.1. Config Panel | v0.4.0 | 2/2 | Complete | 2026-09-21 |
| 36. User Containers & Per-Container Settings | v0.4.0 | 5/5 | Complete | 2026-09-21 |
| 37. Redesigned Add Panel & Rank Grouping | v0.4.0 | 3/3 | Complete | 2026-09-21 |
| 38. Cooldown Trackers | v0.4.0 | 2/2 | Complete | 2026-09-21 |
| 40. CDM Merge Mode | v0.4.0 | 3/3 | Complete | 2026-09-21 |
| 41. Racial Meta-Tracker | v0.4.0 | 3/3 | Complete | 2026-09-21 |
| 42. Cleanup | v0.4.0 | 6/6 | Complete | 2026-09-22 |
| 43. Forever End-to-End Verification Pass | v0.4.0 | — | Complete | 2026-09-22 |
| 44. Retail Validation Pass (M+ and raid) | v0.4.0 | — | Complete | 2026-09-23 |
| 45. Documentation & Release Prep | v0.4.0 | 2/2 | Complete | 2026-09-23 |

*Phases 43 and 44 ran as in-game testing passes rather than plan-driven phases, so they have no
plan count and no phase directory. Their record is the run sheets in `.planning/testing/`.*

*This table read "Not started" for eleven completed phases until milestone close — it was written at
roadmap creation and never updated as phases landed. Rebuilt 2026-09-23 from the phase directories
(one row per phase, plan count = SUMMARY.md count) and the run sheets.*

## Backlog

**999.5 — Cooldown icon can stay grey through the GCD.** Carried out of v0.4.0 by user decision on
2026-09-23. The bug may already be fixed, but it was never consistently reproducible, so it stays
open pending more testing rather than being closed on a guess. Tracked at
`.planning/todos/2026-09-22-cooldown-icon-can-stay-grey-through-the-gcd.md`.

**Open from v0.4.0, not yet promoted:**

- **`RACE-06` / `RACE-07`** — the remaining racials. v0.4.0 ships gnome (Eureka!), troll (Berserking)
  and orc (Blood Fury + a second racial); every other race resolves to a "not yet supported" tile.
- **Troll and orc racials, and the racial cooldown tiles, are untested.** They landed after the
  Forever pass, which records only "Racial meta-tracker (Eureka!) | pass". Forever-only by
  construction, and left untested by explicit user decision.
- **Container-settings defaults are stated in three places with three different fallbacks.** All five
  settings disagree, because `AddSlider`'s fallback is structurally `or minVal`. Collapsing them
  changes behaviour for a partially-populated settings table — a state that could not be produced or
  tested before Phase 43. Phase 42's criterion 1 is marked PARTIAL for this.
- **`tools/TBTProbe/`** — 2,389 lines of exploratory API-probing scaffolding, in the repo but not in
  the TOC or the zip. No decision has been taken on whether it stays.
- **No test suite exists.** No build manifest, no `luacheck`, no automated regression gate. Every
  claim in v0.4.0 rests on in-game observation.

*The four original backlog phases — 999.1 (Edit Mode mouse-down), 999.2 (README and store copy),
999.3 (single-TOC migration) and 999.4 (`@project-version@` in dev installs) — were promoted into
v0.4.0 on 2026-09-20 and shipped as Phases 34, 45, 31-32 and 33 respectively.*
