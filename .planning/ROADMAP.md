# Roadmap: TerribleBuffTracker

## Milestones

- [x] **v0.5.0 Elaborate tracking** — Phases 53-60 (shipped 2026-09-29) — [archive](milestones/v0.5.0-ROADMAP.md)
- [x] **v0.4.1 Generic Item Tracking and Forever Racials** — Phases 46-52 (shipped 2026-09-26) — [archive](milestones/v0.4.1-ROADMAP.md)
- [x] **v0.4.0 Cooldown Tracking and Full CDM View** — Phases 31-45 (shipped 2026-09-23) — [archive](milestones/v0.4.0-ROADMAP.md)
- [x] **v0.3.0 WoW Forever compatibility** — Phases 25-30 (shipped 2026-09-19) — [archive](milestones/v0.3.0-ROADMAP.md)
- [x] **v0.2.0 Config & Edit Mode Rework** — Phases 1-6 (shipped 2026-03-30) — [archive](milestones/v0.2.0-ROADMAP.md)
- [x] **v0.2.1 Aura-Based Timer Cancellation** — Phases 7-11 (shipped 2026-04-04) — [archive](milestones/v0.2.1-ROADMAP.md)
- [x] **v0.2.3 Trinket & Pot Meta-Trackers** — Phases 12-16 (shipped 2026-04-13) — [archive](milestones/v0.2.3-ROADMAP.md)
- [x] **v0.2.4 SpellProvider Refactor** — Phases 17-24 (shipped 2026-04-22) — [archive](milestones/v0.2.4-ROADMAP.md)

## Phases

<details>
<summary>✅ v0.5.0 Elaborate tracking (Phases 53-60) — SHIPPED 2026-09-29</summary>

Full detail archived at [`milestones/v0.5.0-ROADMAP.md`](milestones/v0.5.0-ROADMAP.md); requirements
at [`milestones/v0.5.0-REQUIREMENTS.md`](milestones/v0.5.0-REQUIREMENTS.md).

**Feature phases.** The naming scheme comes first, because editing and detailed tracking both add
per-kind behaviour on top of it. The edit dialog's shared field definition lands before the input
features add fields to it, and detailed tracking comes last among the features so its options are
editable from the moment they exist. Detailed tracking is split in two for cleaner verification:
the mode and aura rules first, then visibility and cross-spell rules on top of them.

- [x] **Phase 53: Naming Scheme & Saved-Data Migration** — every tracker kind carries one canonical
  name in code and in saved data; an existing v0.4.1 database migrates on first load with nothing
  lost, proven by a real logout/login
- [x] **Phase 54: Edit Trackers** — any user buff or user cooldown tracker can be edited after
  creation, spell ID included; the add and edit dialogs are built from one shared field definition
- [x] **Phase 55: ID Preview, Suggested Cooldown & Secrecy** — both dialogs preview the ID being
  entered and auto-fill a cooldown from the game; tooltips show the aura secrecy level, and a
  "secret?" badge warns when aura-driven behaviour will not work in combat
- [x] **Phase 56: Detailed Tracking — Mode & Aura Rules** — a simple/detailed switch, a separate aura
  ID, an opt-out of aura-loss cancellation, and an unreadable aura never treated as absent
- [x] **Phase 57: Detailed Tracking — Visibility & Cross-Spell Rules** — show always, only while the
  aura is present, or only while it is absent; a list of spells whose cast ends the tracker, working
  in combat
- [x] **Phase 57.1: Tracker Dialog Redesign (INSERTED)** — Simple and Detailed as Blizzard text tabs,
  the Detailed tab prefilled with defaults, visibility as a radio dropdown, and no saved mode flag
- [x] **Phase 57.2: Buff Reminders Category (INSERTED)** — reminders become a third TBT tab with
  their own container: a buff reminder shows only while its aura is missing; the
  visibility option is removed from buffs and cooldowns
- [x] **Phase 57.3: Tracker Load Rule (INSERTED, branch `topic/visibility`)** — every tracker loads
  When known / Always / Never; a tracker that isn't loaded is never processed or drawn and shows
  greyed in the TBT tab; the racial race filter becomes "When known"
- [x] **Phase 57.4: Class Buff Meta Reminders (INSERTED, Forever)** — built-in reminders for the
  class buffs (Arcane Intellect, Fortitude, Mark of the Wild, the Blessings, ...), offered as
  Suggested tiles on the Reminders tab, loaded When known, ranks from the spellbook
- [x] **Phase 57.5: Reminder Alternatives (INSERTED)** — a reminder's cast rule becomes "Also
  satisfied by": any listed buff keeps it hidden; the paladin blessings satisfy each other;
  Righteous Fury added, Sanctuary dropped

**Closing sequence, following v0.4.1.** Cleanup after all feature work, so nothing ships without a
cleanup pass, then two whole-milestone review passes: Forever first, retail the literal last phase.

- [x] **Phase 58: Cleanup** — unify duplication this milestone introduced, hot-path audit, dead code,
  stylua, release scripts reviewed; no requirements, process only
- [x] **Phase 59: Forever Full Review** — every feature this milestone built exercised end-to-end on
  the WoW Forever beta; testing pass, no plans
- [x] **Phase 60: Retail Full Review** — everything this milestone ships exercised end-to-end on
  Midnight retail, including M+; testing pass, no plans; the last phase of the milestone

**Closed:** 33/33 requirements (4 adjusted by later user decisions — ADD-07, DTRK-01, DTRK-03,
REM-02). **Plans:** 42 across 11 plan-driven phases; Phases 59 and 60 ran as in-game testing passes.
**Verified on:** WoW Forever beta and Midnight retail including M+, both 2026-09-29, user-approved.

</details>

<details>
<summary>✅ v0.4.1 Generic Item Tracking and Forever Racials (Phases 46-52) — SHIPPED 2026-09-26</summary>

Full detail archived at [`milestones/v0.4.1-ROADMAP.md`](milestones/v0.4.1-ROADMAP.md); requirements
at [`milestones/v0.4.1-REQUIREMENTS.md`](milestones/v0.4.1-REQUIREMENTS.md).

**ITEM phases (46-47), both flavours.** Generic consumable tracking: bag scan, Suggested catalogue,
drag-to-track, shared-cooldown display, use-driven count, out-of-combat reconciliation. Built on the
settled design in Backlog 999.6 below.

- [x] **Phase 46: Item Catalogue & Suggested Tiles** — bag scan produces a consumables catalogue keyed
  by itemID; each untracked item appears in Suggested with its own icon and count; quest items,
  recipes, keys, trade goods and bandages excluded; offered on both retail and Forever
- [x] **Phase 47: Item Tracking & Cooldown Sharing** — dragging a Suggested item creates a real
  cooldown tracker; using any item refreshes every item sharing its cooldown; count decrements only on
  a landed use and reconciles out of combat; a tile survives its stack reaching zero

**PAND phase (48).** Carries the CDM's pandemic refresh-window highlight into Merge Mode. Built on
the research in Backlog 999.7 below and `.planning/research/PANDEMIC.md`.

- [x] **Phase 48: Pandemic Highlight in Merge Mode** — opens with an in-game spike resolving
  `PANDEMIC.md`'s five unknowns; a merged entry's icon and bar both carry the highlight through its
  refresh window with no CDM frame tainted
- [x] **Phase 48.1: Dispel-Type Border in Merge Mode (INSERTED)** — a merged entry mirrors the
  dispel-type border Blizzard draws on its CDM item frame, on both the icon and the bar's icon.
  Inserted mid-milestone on user request, 2026-09-24, rather than renumbered: it reuses Phase 48's
  read surface and render shape wholesale, so it belongs beside it. Precedent, Phase 27.1 in v0.3.0.
  Shipped as two routes — the aura engine draws it for an ordinary merged tracked buff, the atlas
  mirror covers bars, item-backed entries and the engine-off fallback. Fully confirmed on retail
  2026-09-24: icons and bars, Magic and Bleed, in and out of combat. The atlas name is secret in
  combat and is relayed to SetAtlas unread rather than discarded

**Closing sequence (49-52), order fixed by user decision 2026-09-24.** Racial work is built last among
the milestone's features because a same-day game update may make it obsolete, and building it early
risks dropped effort. Cleanup follows it rather than preceding it, so no feature ships without a
cleanup pass — revised on 2026-09-24 from an earlier ordering that ran cleanup at 49 and would have
left the racial work as the only feature with none. Then two whole-milestone review passes, Forever
first, retail deliberately the very last phase.

- [x] **Phase 49: Forever Racial Catalogue** — every remaining Forever race resolves to a working
  racial tracker instead of a not-yet-supported tile; the tooltip names the races actually supported.
  All ten races collected in game and all 21 racials tracked. Gate G1-G10 run by the user
  2026-09-25: **G4 (the real logout/login migration) PASSED** — pre-phase `racial`/`racial2` entries
  were gone and their replacements survived. **G8 (Skyborne upward duration correction) is WAIVED
  for this release by user decision** — the 15-minute condition was never reproducible in game, so
  the racial ships on its minimum duration. RACE-09 was closed by D-7 rather than implemented: the
  generic tile its "not yet supported" message lived on no longer exists
- [x] **Phase 50: Cleanup & Release Prep** — carries Phase 48.1's named deferral (`ApplyDispelBorder`
  re-issues `SetAtlas` every pass while the atlas is secret); unify duplication this milestone introduced, hot-path
  audit, stylua, release scripts reviewed, README/CurseForge/Wago copy and an appended CHANGELOG entry.
  **Executed 2026-09-25 — 3 plans, 2 waves. Verification `passed` 5/5, code review `clean` with zero
  findings.** Success Criterion 5 was NARROWED before execution (see the note under this phase's
  detail): no README and no store-copy changes, and the CHANGELOG entry is drafted to
  `50-CHANGELOG-DRAFT.md` for the user to paste rather than appended by an agent.
  **SC3's behavioural proof is deliberately deferred to Phases 51/52** — landing it early so two
  scheduled in-game review passes verify it for free was the reason it went in wave 1, not an
  oversight. Two candidates were deliberately NOT unified and the reasoning recorded in the plan
  SUMMARYs: the three `Core.lua` key parsers (`cd:` predates the milestone and is protected) and the
  pandemic icon/bar FX split (confirmed justified divergence)
- [x] **Phase 51: Forever Full Review** — every feature this milestone built is exercised end-to-end
  on the WoW Forever beta; testing pass, no plans, matching v0.4.0 Phase 43's shape.
  **PASSED 2026-09-26** — all racials and their cancellations, the dispel indicator, and consumables
  confirmed; no Lua errors. Run sheet: `.planning/testing/51-FOREVER-REVIEW.md`
- [x] **Phase 52: Retail Full Review** — everything this milestone ships on retail is exercised
  end-to-end on Midnight retail; testing pass, no plans, matching v0.4.0 Phase 44's shape; **the last
  phase of the milestone**. **PASSED 2026-09-26** — the pandemic highlight confirmed **in M+**, plus
  the dispel indicator and consumables; no Lua errors. Run sheet:
  `.planning/testing/52-RETAIL-REVIEW.md`. One sub-check, R1's stale-colour re-sort case, was covered
  by extended M+ play rather than a deliberate A/B — recorded as such in the sheet rather than
  reported as a targeted test

</details>

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

*Every phase through v0.5.0 (Phases 1-60) is archived under `.planning/milestones/`. The most recent
is [`v0.5.0-ROADMAP.md`](milestones/v0.5.0-ROADMAP.md), which carries the full detail for Phases
53-60 including the five inserted phases 57.1-57.5, each phase's success criteria and the notes
recorded as it ran; [`v0.4.1-ROADMAP.md`](milestones/v0.4.1-ROADMAP.md) covers Phases 46-52.*

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
| 46. Item Catalogue & Suggested Tiles | v0.4.1 | 4/4 | Complete | 2026-09-24 |
| 47. Item Tracking & Cooldown Sharing | v0.4.1 | 3/3 | Complete | 2026-09-24 |
| 48. Pandemic Highlight in Merge Mode | v0.4.1 | 3/3 | Complete | 2026-09-24 |
| 48.1. Dispel-Type Border in Merge Mode | v0.4.1 | 1/1 | Complete | 2026-09-24 |
| 49. Forever Racial Catalogue | v0.4.1 | 5/5 | Complete — G1-G7, G9, G10 passed; **G4 passed on a real logout/login**; **G8 waived for this release** | 2026-09-25 |
| 50. Cleanup & Release Prep | v0.4.1 | 3/3 | Complete — verification `passed` 5/5, code review `clean`; SC3's in-game proof carried to 51/52 by design | 2026-09-25 |
| 51. Forever Full Review | v0.4.1 | — | Complete — PASSED; racials + cancellations, dispel indicator, consumables; no Lua errors | 2026-09-26 |
| 52. Retail Full Review | v0.4.1 | — | Complete — PASSED; pandemic confirmed in M+, dispel indicator, consumables; no Lua errors | 2026-09-26 |
| 53. Naming Scheme & Saved-Data Migration | v0.5.0 | 5/5 | Complete — schema v8; review fixed (3 WR + 5 IN); UAT closed | 2026-09-29 |
| 54. Edit Trackers | v0.5.0 | 4/4 | Complete — review fixed (1 CR + 3 WR + 2 IN); UAT closed | 2026-09-29 |
| 55. ID Preview, Suggested Cooldown & Secrecy | v0.5.0 | 3/3 | Complete — review fixed (2 WR + 5 IN); UAT closed | 2026-09-29 |
| 56. Detailed Tracking — Mode & Aura Rules | v0.5.0 | 4/4 | Complete — review fixed (4 WR + 3 IN); UAT closed | 2026-09-29 |
| 57. Detailed Tracking — Visibility & Cross-Spell Rules | v0.5.0 | 5/5 | Complete — visibility option later removed by 57.2; UAT closed | 2026-09-29 |
| 57.1. Tracker Dialog Redesign (INSERTED) | v0.5.0 | 3/3 | Complete — schema v9; tabs renamed General/Advanced; UAT closed | 2026-09-29 |
| 57.2. Buff Reminders Category (INSERTED) | v0.5.0 | 5/5 | Complete — schema v10; gap plan 05 by user decision; UAT closed | 2026-09-29 |
| 57.3. Tracker Load Rule (INSERTED) | v0.5.0 | 3/3 | Complete — side-tab dialog; UAT closed, 4 items accepted not tested by name | 2026-09-29 |
| 57.4. Class Buff Meta Reminders (INSERTED) | v0.5.0 | 3/3 | Complete — Mage/Paladin/Warlock tested; 2 items skipped | 2026-09-29 |
| 57.5. Reminder Alternatives (INSERTED) | v0.5.0 | 3/3 | Complete — schema v11; UAT closed, 4 items accepted not tested by name | 2026-09-29 |
| 58. Cleanup | v0.5.0 | 4/4 | Complete — smoke UAT passed on both clients | 2026-09-29 |
| 59. Forever Full Review | v0.5.0 | — | Complete — PASSED, user sign-off; run sheet `59-FOREVER-REVIEW.md` | 2026-09-29 |
| 60. Retail Full Review | v0.5.0 | — | Complete — PASSED incl. M+, no Lua errors; run sheet `60-RETAIL-REVIEW.md` | 2026-09-29 |

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

**999.6 — Bag-driven consumables tracker (Forever).** Intake 2026-09-23, reshaped 2026-09-24 after
two in-game probe runs on Forever 1.60.1 (`/tbtp consum`, `tools/TBTProbe/Probe.lua`).

Superseded the original "pot and healthstone meta-trackers" framing, which was built around CDM
`spellCategoryID` values. **Spell categories are not used.** Items are tracked individually, because
a per-item `C_Item.GetItemCooldown(itemID)` read already reflects a shared cooldown — drinking a
health potion reports the shared cooldown on the mana potion too — so a category table buys nothing.

Measured on Forever, not inferred:

- Every modern API name resolves: `C_Item.GetItemCount / GetItemCooldown / GetItemSpell /
  GetItemInfoInstant / GetItemNameByID / IsUsableItem / GetItemQualityByID`,
  `C_Container.GetContainerNumSlots / GetContainerItemID`. No legacy-global fallback was needed.
- Item cooldowns and counts are **readable in combat**; `ShouldCooldownsBeSecret()` is false.
- **All potions share one 120s cooldown** — Lesser Healing Potion (858) put both Minor Mana Potion
  (2455) and Minor Rejuvenation Potion (2456) on 120s. Health, mana and rejuvenation are one group.
  This differs from retail, where combat (4) and health (30) potions are separate categories.
- **Healthstone (5512) is independent** of the potion group, also 120s.
- A use hook fires on the **button press, not a successful use**: a healthstone press produced no
  cooldown and no count change, and the same item worked 20s later. Never infer a use from the hook.
- `IsUsableItem` is **dynamic** — items flipped from usable to not between an out-of-combat and an
  in-combat bag scan. Unfit as a catalogue filter. `classID`/`subClassID` are stable and are the
  filter to use: quest items are `classID 12`, and bandages have a real tag, `0/7`
  (`Enum.ItemConsumableSubclass.Bandage`), so no name matching is needed to exclude them.

**Bandages are deferred, with the findings kept so they are not re-derived.** Blocked by a platform
restriction rather than a design gap:

- The gating effect is a debuff, **Recently Bandaged, spell 11196, duration 60s** — there is no item
  cooldown at all (`GetItemCooldown` reports nothing for a bandage).
- **Auras cannot be read in combat on Forever.** `C_UnitAuras.GetUnitAuras` and
  `GetAuraDataByIndex` both RAISE with "Auras cannot be accessed when secret"; the legacy
  `UnitAura`/`UnitDebuff` globals do not exist on this client at all. The debuff was only captured
  the instant combat ended and auras unlocked.
- The debuff lands on the **recipient, not the caster**. Bandaging another target consumed the item
  and left the player with no debuff, so a self-tracker cannot fire on "bandage used" — it needs
  "bandage completed on me", and `UNIT_SPELLCAST_CHANNEL_STOP` fires either way without a target.
  `UNIT_SPELLCAST_SENT` carries a target and is the untested lead.

Revisit if Blizzard ever makes that debuff readable in combat. Until then a 60s timer fired on use
would be wrong whenever the bandage went on someone else.

**Settled design, user decision 2026-09-24.** This is the agreed shape, not a proposal:

1. Opening the CDM walks the bags and filters to likely consumables: `classID == 0`, has a use-spell
   (`C_Item.GetItemSpell`), and `subClassID ~= 7` (bandages, deferred above). Quest items fall out on
   `classID`, recipes/keys/trade goods likewise, and `Craftsman's Writ` — a Forever profession quest
   item that classifies as `0/8` — falls out for having no use-spell. On the test character this
   leaves three potions, a healthstone and a bomb, plus four `0/8` oddments (glue, campfire kit,
   lute, crate). That residue is acceptable in a list the user drags from, and the filter is expected
   to be refined during the milestone.
2. Every consumable not already tracked is offered in Suggested on the **Cooldowns** tab, showing its
   icon (`C_Item.GetItemIconByID`, the one call in this plan never yet exercised) and current count.
3. On an item use, cooldowns are re-read for all **tracked** items — one
   `C_Item.GetItemCooldown(itemID)` each, keyed by itemID and never by bag/slot, which is positional
   and shifts when stacks split or bags are sorted.
4. **Count is decremented by 1 on `UNIT_SPELLCAST_SUCCEEDED`, not on the use hook.** The hook fires on
   the press; the cast event is what says the use landed. `PotProviderMixin` already proves the event
   reaches item-triggered casts (`Providers.lua:508`), and `Core.lua`'s debug log already stamps the
   effect spellID from `GetItemSpell` at hook time so the arriving cast can be tied back to the item.
   The count is reconciled against `GetItemCount` out of combat and at combat end; a decrement is
   explicitly preferred over a live read in combat, by user decision, and the residual drift (looting
   more mid-fight, multiple items consumed at once) is absorbed by that reconcile.
5. Also refresh on `BAG_UPDATE_COOLDOWN`, which `Core.lua:832` already registers — it covers use paths
   the four hooks do not catch, and is the event Blizzard's own cooldown item listens to.

Still untested and accepted as gaps, both by user decision 2026-09-24: engineering explosives (`0/0`,
Big Bronze Bomb 4380) sharing with potions, and whether `GetItemCooldown` still answers for an item
whose stack has hit zero. The latter closes for free if `start + duration` is stamped at the moment of
the successful use, since that is the last moment the value is certainly readable.

**999.7 — Carry the CDM's pandemic highlight over in Merge Mode.** Intake 2026-09-23, user request.

Pandemic is the refresh window: the point at which a buff or debuff can be recast without losing the
duration already carried over. The CDM already computes and draws it, so Merge Mode should not be
dropping it.

Blizzard's side, for reference: `CooldownViewerItemMixin:CheckSetPandemicAlertTriggerTime` /
`IsInPandemicTime` / `ShowPandemicStateFrame` (`CooldownViewer.lua:529-612`), drawn with the virtual
templates `CooldownPandemicFXTemplate` (icons) and `CooldownPandemicBarFXTemplate` (bars) from
`Blizzard_CooldownViewer/PandemicAlertAnimation.xml` — atlas `UI-CooldownManager-PandemicBorder` plus
the `UI-CooldownManager-PandemicFX-Icon0N` animation layers. Anchoring is `-6/+6` around an icon
(`CooldownViewer.lua:2129-2133`) and `-9/+10` around a bar with `frameLevel + 1`
(`CooldownViewer.lua:2353-2357`). The templates are virtual and the CDM is a hard dependency, so TBT
can instantiate them by name rather than redrawing the art.

The constraint is the state, not the art. Recomputing the window needs the aura's `expirationTime`
and `duration`, which are secret — so do not recompute it, read the CDM's own answer. Note that
`MergeMode.lua`'s rule 1 forbids calling a Blizzard mixin method on a CDM frame, which rules out
`itemFrame:IsInPandemicTime()`; the lead to try first is the plain field `itemFrame.PandemicIcon`,
which `ShowPandemicStateFrame` sets and `HidePandemicStateFrame` nils, reachable from the
already-whitelisted `itemFramePool:EnumerateActive` walk and readable without a mixin call.
Unverified — prove it in the phase.

Scope is Merge Mode only. Whether TBT's own native trackers should compute a pandemic window
arithmetically from their known durations is a separate question, not part of this item.

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

**999.8 — Show the AURA's icon where a racial's aura ID differs from its cast ID.** Intake
2026-09-25, from a standing user allowance: *"in cases where aura and skill id doesn't match we're
fully fine with showing the aura icon instead of skill."*

Three rows are affected, and they are exactly the three that already carry an explicit `auraID`, so
**no data collection is needed** — only icon resolution changes:

| Racial | Cast ID | Aura ID |
|---|---|---|
| Cannibalize (undead) | 20577 | 20578 |
| Read Ley Line (Alliance Skyborne) | 1259705 | 1270842 |
| Skysight (Horde Skyborne) | 1259686 | 1259688 |

Scope as discussed on 2026-09-25 before it was deferred, so it does not need re-deciding:
**buff tile only** — the cooldown tile keeps the CAST's icon, because it is counting the cast's
cooldown, not the aura; **racials only**, since the racial table is the only place TBT holds an
explicit aura ID at all; and the **label stays the cast name** on all three rows, confirmed by the
user (*"label was never seen in game, the tooltip is the skill's tooltip so it has always been
right"*).

**Deferred out of Phase 50 by user decision, 2026-09-25**, to close v0.4.1 faster: it is a
user-visible behaviour change rather than cleanup, and gating all three rows needs an undead plus
both Skyborne characters. It had been folded into Phase 50 earlier the same day and was pulled back
out — the phase is process-only again. Full write-up at `.planning/research/FOREVER-RACIALS.md`, F-3.

**999.9 — TBT taints `EditModeManagerFrame` on every container click in Edit Mode.** Found
2026-09-25 while investigating a user's Lua error. **Left in place by user decision the same day** —
the error was probably unrelated and a one-line change to pre-existing code was not worth the risk
mid-review. Recorded so it is not rediscovered cold.

`ns:SelectContainer` (`EditModeFrames.lua:170-171`) calls
`pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)` — a **Blizzard Edit Mode
mixin method, invoked from TBT's own click handler** — to clear Blizzard's yellow highlight when the
user selects a TBT container instead.

**The `pcall` is false reassurance, and the code comment shows the author half-knew:** *"Use pcall
because ClearSelectedSystem may touch secure state in some contexts."* `pcall` catches **errors**.
Taint is not an error — it is a flag that spreads silently and never raises at the call site. The
guard does nothing for the actual risk.

This is the same mechanism `PROJECT.md` already records as measured and locked for the Cooldown
Manager: *"Calling any Blizzard CDM mixin method leaves the frame tainted afterwards, and the taint
is sticky: it survives leaving combat and clears only on `/reload`."* Nothing in that finding is
CDM-specific; `EditModeManagerFrame` is the same kind of object.

**Observed symptom that prompted the investigation** (cause NOT confirmed — see below): a user who
opened Edit Mode, clicked a TBT container, and kept playing later saw
`ActionButton.lua:891: bad argument #1 to 'SetCooldown' … Secret values are only allowed during
untainted execution`, on a `GamepadActionBarEditFrame…` preview button, with no TBT frame on the
stack. Taint propagates, so an all-Blizzard stack does not exonerate an addon.

**Not confirmed as the cause, and two explanations are live.** Other addon developers have reported
that anything controller-related is tainting the UI broadly on this patch, and the erroring frame is
a gamepad preview frame that Blizzard creates even for a user with no controller. Both could be true
at once. **The decisive test was never run:** disable only TBT, full client restart, reproduce.

**The fix, when it is picked up, is to stop making the call.** There is no clever alternative —
setting `selectedSystem` directly or calling a different mixin taints the same frame by the same
mechanism. Cost: Blizzard's yellow highlight may linger alongside TBT's while both are selected.
Cosmetic, and only visible inside Edit Mode.

**999.10 — Shadowmeld's cooldown starts when the buff ENDS, not when the skill is used.** Reported by
the user 2026-09-25 from in-game observation: *"the game fires the CD only when the skill is
canceled, and we are firing when it's used."*

**Current behaviour.** `UserSpellProviderMixin:OnTrigger` (`Providers.lua`) stamps
`ns.cooldownStarts[cdKey] = GetTime()` on `UNIT_SPELLCAST_SUCCEEDED` — at the CAST. Correct for every
other cooldown in the addon; wrong for Shadowmeld, whose cooldown the game starts only once stealth
breaks. A player who shadowmelds and stands still sees TBT's tile run its ten seconds and go ready
while the real ability has not started counting at all.

**Structurally unique to this one row, which bounds any fix.** Shadowmeld (20580) is the ONLY entry
in `RACIAL_SPELLS` that is both `indefinite = true` and carries a `cooldown`. Find Treasure (2481)
and Plainsrunning (1299038) are indefinite with no cooldown; every other racial has a real duration.
An ability with no natural end is exactly the shape whose cooldown cannot key off the cast, so no
other row can hit this.

**Both signals a fix needs already exist** — this is wiring, not new detection:
- Out of combat, `ns:ScanActiveTimersForCancellation` (`BuffEngine.lua`) already detects the aura
  dropping, and already ends the proc. That is the moment the cooldown should start.
- On combat entry, `ns:EndCombatClearedRacials` already clears it via `clearOnCombat`.

What is missing is a hook from "this indefinite racial's proc just ended" to "stamp
`ns.cooldownStarts` now", instead of at the cast.

**Open question for whoever picks it up — do NOT assume the in-combat case is the same.** Shadowmeld
used IN combat is a threat drop with a separate 2-minute cooldown (`combatCooldown = 120`, added
2026-09-25 as F-1), and it applies no trackable stealth, so there may be no aura-end event to key
off at all. Firing at the cast may well be correct there. The user's report describes the
out-of-combat case; the in-combat case is unverified either way.

**Deferred by user decision, 2026-09-25, for a reason that outlives this entry:** *"I don't want to
correct this right now as the CDM updates from blizzard might make most racial trackers we have
obsolete."* Blizzard's Cooldown Manager is actively changing under this beta, and if it grows native
racial support the whole racial feature — this fix, **999.8**, and `RACE-06` (retail racials) —
could be moot. Weigh that before investing in any of the three.

**999.11 — Profile support: global or per-character.** Intake 2026-09-26, user request. Not tied to
any specific milestone; noted for the next milestone discussion.

- One **account-wide toggle** picks between a single **global** profile (today's behaviour) and
  **per-character** profiles.
- A character profile holds **the tracked skills, their positions and their per-tracker configs**.
- **Everything else stays account-wide**: Merge Mode, containers and their settings, and anything
  not listed above.

For whoever picks it up: TBT has no per-character scoping at all today — the TOC declares only
`## SavedVariables: TerribleBuffTrackerDB`. The character key needs care on Forever, which has no
realms and whose `UnitName` behaves differently (`.planning/research/FOREVER-COMMUNITY-FAQ.md` §4-5).
(Forever's SavedVariables were broken platform-wide per §3, but the user reported on 2026-09-28
that they have persisted for a while now, so persistence is testable on both clients.) Open questions: what a new character starts with (empty, or a copy of global),
and whether switching the toggle copies the current setup into the new profile.

**999.12 — Edit existing user-defined trackers.** Intake 2026-09-26, user request.

Any **user-defined** tracker should let the user edit every input they set when creating it —
duration, cooldown, and the spell/item ID itself (changing it to a different one). As more options
are added (see 999.14), they become editable too; the edit dialog should be driven by the same field
list as the add dialog rather than kept in sync by hand. Built-in meta-trackers (Lust, Trinket, Pot,
racials) are out of scope unless decided otherwise. Open question: changing the ID changes the
tracker's key, so running timers, positions and cooldown state keyed by the old ID must migrate or
reset.

**999.13 — A stronger naming scheme for tracker kinds.** Intake 2026-09-26, user request.

Name the tracker kinds consistently, along the lines of: user buff tracker, user cooldown tracker,
meta skill tracker (TBT's built-in ones such as Lust), meta item tracker, and user item tracker (if
users can ever create custom item trackers). The user's example was kebab-case
(`user-buff-tracker`, ...) but the casing is open. Today the kinds are spread across provider
mixins in `Providers.lua` (`UserSpellProviderMixin`, `TrinketProviderMixin`, `PotProviderMixin`,
`LustProviderMixin`, `RacialProviderMixin`, `ItemProviderMixin`) whose names don't follow one
pattern. Worth doing **before** 999.12 and 999.14, which both add behaviour per kind. Any rename that
reaches saved keys needs a SavedVariables migration.

**999.14 — More elaborate custom buff and item trackers.** Intake 2026-09-26, user request.

Let users define more of a tracker's behaviour. Examples given:

- **Per-tracker choice of whether aura cancellation ends the timer.**
- **Cross-spell rules**, such as "aura A is cleared when skill B is used".

Constraints to carry in: aura reads are secret in combat for a tainted caller, so any
aura-driven rule only fires out of combat (the same limit that forced `clearOnCombat` on
Shadowmeld). History: racials briefly had a `cancelOnAuraLoss` opt-in, removed 2026-09-25 because
making it opt-in meant every racial that could end early showed up as a bug report
(`Providers.lua:829-834`). For user trackers the default should likely be ON with an opt-OUT —
decide that explicitly. Cast-driven rules like "B clears A" only need `UNIT_SPELLCAST_SUCCEEDED`,
which is always safe, so those are the cheaper half.

**Warn at config time (user idea, 2026-09-28).** `C_Secrets.GetSpellAuraSecrecy(spellID)` returns a
static `Enum.SecrecyLevel` — `NeverSecret` (0), `AlwaysSecret` (1) or `ContextuallySecret` (2) — the
spell's BASE secrecy, independent of whether the player is in combat right now. Blizzard uses exactly
this test (`Blizzard_AuraContainerUtil.lua:23`) to exempt Sated/Exhaustion. So the add/edit dialogs
can say, per aura ID the user enters, whether an aura rule will keep working in combat and M+
(`NeverSecret`) or only out of combat (anything else). The same check applies to 999.15's
aura-loss alerts. Not to be confused with `ShouldSpellAuraBeSecret`, which answers for the CURRENT
restriction state and was found over-conservative in play-testing (`MergeMode.lua:519-528`).
Unverified in game: how many ordinary player buffs come back `NeverSecret` — probably very few.

**999.15 — Alerts, visual and sound, like the CDM's.** Intake 2026-09-26, user request.

Per-tracker alerts with visual and sound options, modelled on the Cooldown Manager's own alerts,
with configurable conditions for when they fire — e.g. alert when an aura is **lost**, or even
**show the tracker only** when the aura is lost. Check the CDM's alert implementation in
`Blizzard_CooldownViewer` before designing, so the settings and look match. Same limit as 999.14:
aura-loss conditions can only be seen out of combat; timer-driven conditions (expired, N seconds
left, cooldown ready) come from TBT's own `GetTime()` math and work everywhere.

**999.16 — Extend detailed tracking when the spell is also in the CDM.** Intake 2026-09-28, user
request, split out of the v0.5.0 detailed-tracking scope. For v0.5.0 a tracker whose spell is also
tracked by Blizzard's Cooldown Manager gets **no special treatment**. Later, detailed tracking could
use the CDM's own state where it is available, as Merge Mode already does for pandemic and dispel
borders — for example the CDM showing an aura in combat, where TBT's own aura read is secret. Would
lift the out-of-combat-only limit on aura-driven rules for exactly those spells.

*The four original backlog phases — 999.1 (Edit Mode mouse-down), 999.2 (README and store copy),
999.3 (single-TOC migration) and 999.4 (`@project-version@` in dev installs) — were promoted into
v0.4.0 on 2026-09-20 and shipped as Phases 34, 45, 31-32 and 33 respectively.*

*999.12 (edit trackers), 999.13 (naming scheme) and 999.14 (elaborate trackers) were promoted into
v0.5.0 on 2026-09-28 and shipped as Phases 54, 53 and 56-57 (reshaped by 57.1-57.5). Their entries
above are kept as the design record, as 999.6 and 999.7 are for v0.4.1.*
