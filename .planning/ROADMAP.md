# Roadmap: TerribleBuffTracker

## Milestones

- [ ] **v0.5.6 More Forever Reminders** — Phases 80-85 (in progress, started 2026-11-09)
- [x] **v0.5.5 Fresh-login buff time fix** — no phases, done outside GSD (shipped 2026-10-27, `6f976e8`) — see `MILESTONES.md`
- [x] **v0.5.4 Buff countdown display fix** — Phase 79 (shipped 2026-10-24) — [archive](milestones/v0.5.4-ROADMAP.md)
- [x] **v0.5.3 Display buff duration alongside cooldowns** — Phases 73-78 (shipped 2026-10-23) — [archive](milestones/v0.5.3-ROADMAP.md)
- [x] **v0.5.2 Improved Merge Mode and small fixes** — Phases 67-72 (shipped 2026-10-10) — [archive](milestones/v0.5.2-ROADMAP.md)
- [x] **v0.5.1 Clickable Reminders and new icons** — Phases 61-66 (shipped 2026-10-01) — [archive](milestones/v0.5.1-ROADMAP.md)
- [x] **v0.5.0 Elaborate tracking** — Phases 53-60 (shipped 2026-09-29) — [archive](milestones/v0.5.0-ROADMAP.md)
- [x] **v0.4.1 Generic Item Tracking and Forever Racials** — Phases 46-52 (shipped 2026-09-26) — [archive](milestones/v0.4.1-ROADMAP.md)
- [x] **v0.4.0 Cooldown Tracking and Full CDM View** — Phases 31-45 (shipped 2026-09-23) — [archive](milestones/v0.4.0-ROADMAP.md)
- [x] **v0.3.0 WoW Forever compatibility** — Phases 25-30 (shipped 2026-09-19) — [archive](milestones/v0.3.0-ROADMAP.md)
- [x] **v0.2.0 Config & Edit Mode Rework** — Phases 1-6 (shipped 2026-03-30) — [archive](milestones/v0.2.0-ROADMAP.md)
- [x] **v0.2.1 Aura-Based Timer Cancellation** — Phases 7-11 (shipped 2026-04-04) — [archive](milestones/v0.2.1-ROADMAP.md)
- [x] **v0.2.3 Trinket & Pot Meta-Trackers** — Phases 12-16 (shipped 2026-04-13) — [archive](milestones/v0.2.3-ROADMAP.md)
- [x] **v0.2.4 SpellProvider Refactor** — Phases 17-24 (shipped 2026-04-22) — [archive](milestones/v0.2.4-ROADMAP.md)

## Phases

### v0.5.6 More Forever Reminders (Phases 80-85) — IN PROGRESS

Started 2026-11-09 on `milestone/v0.5.6-more-forever-reminders`. Research:
[`research/FOREVER-REMINDERS.md`](research/FOREVER-REMINDERS.md) (§12.3 is the final group-call
list), summary in [`research/SUMMARY.md`](research/SUMMARY.md).

**Order.** The Forever block and the group-buff and rank data come first, because every later group
call sits inside that block. Mage armors and familiar scrolls next (the user tests these, and the
familiar item click is the milestone's only new behaviour). The other class rows follow, Demonic
Sacrifice last as the only row with a separate aura ID. Then the review doc, cleanup, and the user's
Forever testing pass as the literal last phase.

- [x] **Phase 80: Forever Group Block, Group Buffs and Rank Coverage** — one Forever-only block of group calls; group buffs, Greater Blessings and every rank count as alternatives; Salvation and Light retired
- [x] **Phase 81: Mage Armors and Familiar Scrolls** — Ice Armor and Mage Armor join Frost Armor as one group; one familiar reminder whose click uses the best scroll in the bags
- [x] **Phase 82: Other Class Rows** — warlock, shaman, priest, paladin and hunter rows plus the situational buffs, Demonic Sacrifice last
- [x] **Phase 83: Reminder Review Doc** — `docs/REMINDERS.md` lists every built-in reminder with Wowhead links, cross-checked against `Providers.lua`, not shipped
- [x] **Phase 84: Cleanup** — the milestone's own unused code and duplication, touched hot paths, stylua, release scripts
- [x] **Phase 85: Forever Testing Pass** — the user checks the new rows and groups in game; testing pass, no plans; the last phase of the milestone

<details>
<summary>✅ v0.5.4 Buff countdown display fix (Phase 79) — SHIPPED 2026-10-24</summary>

Full detail archived at [`milestones/v0.5.4-ROADMAP.md`](milestones/v0.5.4-ROADMAP.md); requirements
at [`milestones/v0.5.4-REQUIREMENTS.md`](milestones/v0.5.4-REQUIREMENTS.md).

- [x] Phase 79: Buff Countdown Display Fix (1/1 plans) — buff icons use the aura countdown format

</details>

<details>
<summary>✅ v0.5.3 Display buff duration alongside cooldowns (Phases 73-78) — SHIPPED 2026-10-23</summary>

Full detail archived at [`milestones/v0.5.3-ROADMAP.md`](milestones/v0.5.3-ROADMAP.md); requirements
at [`milestones/v0.5.3-REQUIREMENTS.md`](milestones/v0.5.3-REQUIREMENTS.md).

- [x] Phase 73: Install to Forever's New Folder (1/1 plans) — `install.ps1` deploys to `_forever_`
- [x] Phase 74: Buff Duration on Spell Cooldowns (2/2 plans) — Advanced-tab buff config; the cast starts the buff
- [x] Phase 75: Buff Look on Cooldown Icons (1/1 plans) — the CDM's yellow aura swipe, then the grey cooldown
- [x] Phase 76: Buff Duration on Bag Items (2/2 plans) — item edit dialog with only the buff fields editable
- [x] Phase 77: Cleanup (2/2 plans)
- [x] Phase 78: Human Testing (testing pass) — passed 2026-10-23; gap fix: the buff follows its live aura

</details>

<details>
<summary>✅ v0.5.2 Improved Merge Mode and small fixes (Phases 67-72) — SHIPPED 2026-10-10</summary>

Full detail archived at [`milestones/v0.5.2-ROADMAP.md`](milestones/v0.5.2-ROADMAP.md); requirements
at [`milestones/v0.5.2-REQUIREMENTS.md`](milestones/v0.5.2-REQUIREMENTS.md).

- [x] Phase 67: Remove Racials (5/5 plans) — racials gone on every client, schema v12 drops saved ones
- [x] Phase 68: Merge Mode by Re-anchoring (2/2 plans) — Blizzard's own CDM frames placed on TBT's cells
- [x] Phase 69: Re-anchoring Open Issues (3/3 plans) — settings-window reorder, Edit Mode placeholder, hidden containers
- [x] Phase 70: Remove the Redraw Path & Close the Merge Mode Bugs (5/5 plans) — whole-path paint-over review
- [x] Phase 71: Cleanup (2/2 plans)
- [x] Phase 72: Human Testing (testing pass) — passed 2026-10-10

</details>

<details>
<summary>✅ v0.5.1 Clickable Reminders and new icons (Phases 61-66) — SHIPPED 2026-10-01</summary>

Full detail archived at [`milestones/v0.5.1-ROADMAP.md`](milestones/v0.5.1-ROADMAP.md); requirements
at [`milestones/v0.5.1-REQUIREMENTS.md`](milestones/v0.5.1-REQUIREMENTS.md).

- [x] Phase 61: Bug Fixes (2/2 plans) — Edit Mode taint (999.9), Merge Mode charge count (999.17)
- [x] Phase 62: New Icons (2/2 plans) — TBT's own tab and side-tab textures, faction-themed
- [x] Phase 63: Clickable Reminders (3/3 plans) — out-of-combat click-to-cast (999.18), lead window
- [x] Phase 64: Retail Class-Buff Reminder Suggestions (2/2 plans)
- [x] Phase 65: Cleanup (3/3 plans)
- [x] Phase 66: Human Testing (testing pass) — passed 2026-10-01

</details>

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

*Every phase through v0.5.4 (Phases 1-79) is archived under `.planning/milestones/`. The most recent
is [`v0.5.4-ROADMAP.md`](milestones/v0.5.4-ROADMAP.md), which carries the full detail for Phase 79;
[`v0.5.3-ROADMAP.md`](milestones/v0.5.3-ROADMAP.md) covers Phases 73-78.*

**Scope rule for every v0.5.6 phase (user, 2026-11-09).** Nothing may work differently from today,
except the familiar-scroll item click (CLICK-07). Every row and group is data through the existing
`MetaReminderRow` / `MetaReminderGroup`; matching, watch and cast code is not changed. Every Forever
ID comes from `research/FOREVER-REMINDERS.md` only, is WoW Forever's own, and its link is
`https://www.wowhead.com/forever/spell=<id>` (items: `/forever/item=<id>`). No Classic ID and no
Classic page as evidence. New rows are Forever only; retail rows do not change. Rows the user has
not tested keep "(unverified in game)" in their trailing comment.

### Phase 80: Forever Group Block, Group Buffs and Rank Coverage
**Goal**: On Forever, a group buff, a Greater Blessing or any rank of a class buff on the player hides its reminder, while every retail reminder behaves exactly as before
**Depends on**: Nothing (first phase of the milestone)
**Requirements**: RALT-04, RALT-05, RALT-06, RALT-07, MREM-06
**Success Criteria** (what must be TRUE):
  1. On Forever, a player carrying Arcane Brilliance (23028), Prayer of Fortitude (21562, 21564), Prayer of Spirit (27681) or Gift of the Wild (21849, 21850) does not see the matching Arcane Intellect, Power Word: Fortitude, Divine Spirit or Mark of the Wild reminder
  2. On Forever, any blessing or Greater Blessing (Kings 25898, Might 25782/25916, Wisdom 25894/25918) on the player hides every blessing reminder
  3. On Forever, a rank the player does not know hides its reminder for every existing row in research §12.3 (Arcane Intellect, Fortitude, Divine Spirit, Mark of the Wild, Thorns, Battle Shout, Trueshot Aura, Blood Pact, the blessings): e.g. another mage's Arcane Intellect 10157 on a level-30 mage
  4. Blessing of Salvation (1038) and Blessing of Light (19979) are no longer offered in Suggested; one already placed shows greyed as "no longer offered" with its saved data kept; `Providers.lua` carries an internal note recording Salvation, Light and Revoker as removed from Forever
  5. On retail, every reminder, including the rows on 21562, 1459, 1126, 6673 and 465, shows and hides exactly as before and gains no alternative; all v0.5.6 group calls sit in one `if ns.CLIENT_IS_FOREVER then … end` block and `MetaReminderGroup` itself is unchanged
**Plans**: 1 plan
- [x] 80-01-PLAN.md — retire 1038/19979 with the internal note, update the header comment, add the Forever group block (nine §12.3 calls); gate `80-check-groups.js --exact`
**Notes**: Scope rule above applies. Rank lists are research §12.2/§12.3 verbatim. Blood Pact's extra data IDs (7871-7873 and others) are not added (RALT-07: only if the in-game ID tooltip shows one). The blessings call replaces the existing one, without 1038/19979. Keep comments out of the middle of multi-line calls (stylua CR trap).

### Phase 81: Mage Armors and Familiar Scrolls
**Goal**: A Forever mage is reminded of a missing armor and a missing familiar, and clicking the familiar reminder uses the best scroll in the bags
**Depends on**: Phase 80
**Requirements**: MREM-07, MREM-18, CLICK-07
**Success Criteria** (what must be TRUE):
  1. A Forever mage is offered Ice Armor (10220) and Mage Armor (22783) reminders, 30 min each, and with any of Frost Armor, Ice Armor or Mage Armor up, no armor reminder shows
  2. A Forever mage who knows Comprehend Scroll (1296017) is offered one familiar reminder, 60 min; any of Cat (1302303), Frog (1302285) or Rat (1296202) on the player hides it, using any scroll starts its timer, and it is not grouped with Arcane Intellect or the armors
  3. Out of combat, clicking the familiar reminder uses the highest-tier scroll in the bags that the player's level allows (Cat 277493 at 25, then Frog 277483 at 16, then Rat 275069 at 5); after a bag change the choice is made again, and with no usable scroll the icon shows with no click action
  4. Every other reminder's click is unchanged on both clients: out of combat it casts its spell, in combat it does nothing, and a reminder whose spell is not known gets no click
**Plans**: 1 plan
- [x] 81-01-PLAN.md — Ice Armor, Mage Armor and familiar rows with their Forever-block groups and `useItems`; the familiar overlay uses the best usable scroll (`type1 = "item"`), re-picked on `BAG_UPDATE_DELAYED`; gate `81-check.js`
**Notes**: Scope rule above applies; CLICK-07 is the milestone's only new behaviour. Shape per research §11.2-§11.3: `castID = false`, `knownID = 1296017`, an ordered `useItems` list (never sorted by ID), the item picked in `ReminderClick.lua`'s out-of-combat `Flush`, `type1 = "item"` written only for that overlay, one `ns:MarkReminderClicksDirty()` call in the existing `BAG_UPDATE_DELAYED` branch. Mage rows stay "(unverified in game)" until Phase 85.

### Phase 82: Other Class Rows
**Goal**: Forever warlocks, shamans, priests, paladins and hunters are offered reminders for their maintained self buffs, with exclusive buffs grouped so any one up hides the others
**Depends on**: Phase 80
**Requirements**: MREM-08, MREM-09, MREM-10, MREM-11, MREM-12, MREM-13, MREM-14, MREM-15, MREM-16 (MREM-17 dropped by the user: no detection or tracking skills)
**Success Criteria** (what must be TRUE):
  1. A Forever warlock sees Demon Armor (11735) and Demon Skin (696) as one group, a shaman sees Lightning Shield (10432) and Water Shield (408510) as one group, and a priest sees Inner Fire (10952, 10 min), Shadowform (15473, no timer, shown once the aura is gone) and, only if they know it, Shadowguard (19312)
  2. A Forever paladin sees one Devotion Aura (10293) reminder that any rank of Devotion, Retribution, Concentration or the three resistance auras hides; a hunter sees one Aspect of the Hawk (25296) reminder that Monkey, Cheetah, Pack, Wild or Beast hides, and that Viper or Falcon never hides
  3. Situational rows on Forever: a mage's Amplify Magic (10170) and Dampen Magic (10174) form one group; a priest's Shadow Protection (10958) is hidden by Prayer of Shadow Protection (27683) or a lower rank another priest cast; no detection or tracking skill (Detect Invisibility, Track Beasts and the like) is offered
  4. A Forever warlock sees Demonic Sacrifice (18788), 120 min, which watches aura 18789 and is hidden by any of 18790, 18791 or 18792
  5. On retail no new reminder is offered and every existing reminder is unchanged
**Plans**: 1 plan
- [x] 82-01-PLAN.md — thirteen Forever rows above the retail rows and seven group calls appended to the Forever block, Demonic Sacrifice last; gate `82-check-rows.js`
**Notes**: Scope rule above applies. Group calls go inside Phase 80's Forever block. Rows another player can apply get every rank listed per RALT-07 (research §12.2: Shadow Protection 976, 10957; Amplify 1008, 8455, 10169; Dampen 604, 8450, 8451, 10173). 465 is the retail Devotion row and only appears inside the Forever block. Demonic Sacrifice lands last, as the only row with a separate aura ID.

### Phase 83: Reminder Review Doc
**Goal**: A human can review every built-in reminder, Forever and retail, in one document kept in step with the code
**Depends on**: Phase 82
**Requirements**: DOC-06, DOC-07
**Success Criteria** (what must be TRUE):
  1. `docs/REMINDERS.md` lists every built-in reminder, Forever and retail, existing and new, with class, spell, ID, duration, group and alternatives, client and verified-in-game status, each with a Wowhead link (`/forever/` for Forever, the retail path for retail)
  2. The doc lists every candidate left out, each with a reason
  3. Every ID in the doc matches a row or alternative in `Providers.lua` and every row or alternative ID in `Providers.lua` appears in the doc, with zero mismatches; the reminder table's comment points at the doc
  4. The packaged zip contains no `docs/` (`.pkgmeta` ignores it)
**Plans**: 1 plan
- [x] 83-01-PLAN.md — doc-to-code check script with --selftest, docs/REMINDERS.md built from the current reminder table, pointer comment, .pkgmeta and CLAUDE.md lines
**Notes**: Scope rule above applies; no code behaviour changes here, only the pointer comment. Salvation, Light and Revoker stay out of this doc (MREM-06); they live in the internal note in `Providers.lua`. Lifted from research §5, §7, §8 and §11-§12.

### Phase 84: Cleanup
**Goal**: The milestone's code leaves no dead code, duplication or hot-path cost behind, and the release scripts still hold
**Depends on**: Phase 83
**Requirements**: CLEAN-01
**Success Criteria** (what must be TRUE):
  1. No unused code or duplicated behaviour introduced by Phases 80-83 remains; code that predates the milestone is not refactored
  2. The hot paths the new rows, groups and familiar click touch (the reminder aura refresh, the reminder click flush, the bag-update branch) do no new per-frame or per-event allocation
  3. `stylua .` leaves no diff and `git ls-files --eol` shows CRLF for every touched Lua file; the release scripts are reviewed
  4. The doc-to-code ID check from DOC-07 is re-run after cleanup and still finds zero mismatches
**Plans**: 1 plan
- [x] 84-01-PLAN.md — close review items 81 IN-01 (prebuilt "item:<id>"), 81 IN-03 (_spellAttr), 80 IN-04 (cap comment); hot-path verdicts, stylua/CRLF/gates, release review, install.bat
**Notes**: Scope rule above applies. Process only; the costs research §12.4 lists are noted, not optimised.

### Phase 85: Forever Testing Pass
**Goal**: The user confirms the new reminders and groups on WoW Forever, and that retail is unchanged
**Depends on**: Phase 84
**Requirements**: VER-15
**Success Criteria** (what must be TRUE):
  1. On Forever, each mage armor's ID tooltip matches its row, and one armor up hides the others
  2. The familiar reminder is checked in game: each tier's buff ID, the click using the highest scroll in the bags, whether a new tier replaces a lower one, and whether it stacks with Arcane Intellect
  3. A group buff hides its single-target reminder where one can be had, and any other class the user can reach is checked; rows not checked keep "(unverified in game)"
  4. A retail sanity pass confirms no retail reminder changed
**Plans**: None (testing pass by the user)
**Notes**: Scope rule above applies. The literal last phase of the milestone, as in earlier milestones.
**Outcome (2026-11-09)**: The user verified the mage armors and the familiar click in game; every other row ships on community feedback. Review changes: Shadowform dropped; `docs/REMINDERS.md` became one table per client sorted by class, with the verified column and Not included table moved to `.planning/research/REMINDERS-NOT-INCLUDED.md`. See `85-SUMMARY.md`.

## Progress

**Execution order:** 80 → 81 → 82 → 83 → 84 → 85 (v0.5.6)

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
| 61. Bug Fixes | v0.5.1 | 2/2 | Complete — review fixed (4 WR + 2 IN); UAT passed in Phase 66 | 2026-09-30 |
| 62. New Icons | v0.5.1 | 2/2 | Complete — review fixed (3 WR + 1 IN); UAT passed in Phase 66 | 2026-09-30 |
| 63. Clickable Reminders | v0.5.1 | 3/3 | Complete — review fixed (2 CR + 5 WR + 3 IN); UAT passed in Phase 66 | 2026-09-30 |
| 64. Retail Class-Buff Reminder Suggestions | v0.5.1 | 2/2 | Complete — review fixed (1 CR + 1 WR + 1 IN); UAT passed in Phase 66 | 2026-09-30 |
| 65. Cleanup | v0.5.1 | 3/3 | Complete — review fixed (1 WR); UAT passed in Phase 66 | 2026-10-01 |
| 66. Human Testing | v0.5.1 | — | Complete — PASSED on Forever and retail incl. M+, user sign-off; run sheet `66-HUMAN-TESTING.md` | 2026-10-01 |
| 67. Remove Racials | v0.5.2 | 5/5 | Complete — review fixed (1 WR + 4 IN); UAT passed in Phase 72 | 2026-10-10 |
| 68. Merge Mode by Re-anchoring | v0.5.2 | 2/2 | Complete — review fixed over two passes (1 CR + 5 WR + 6 IN); UAT passed in Phase 72 | 2026-10-10 |
| 69. Re-anchoring Open Issues | v0.5.2 | 3/3 | Complete — review fixed (3 WR + 5 IN); UAT passed in Phase 72 | 2026-10-10 |
| 70. Remove the Redraw Path & Close the Merge Mode Bugs | v0.5.2 | 5/5 | Complete — review fixed (2 WR + 6 IN); UAT passed in Phase 72 | 2026-10-10 |
| 71. Cleanup | v0.5.2 | 2/2 | Complete — review fixed (2 WR, comments only); checks passed in Phase 72 | 2026-10-10 |
| 72. Human Testing | v0.5.2 | — | Complete — PASSED on retail (raid and M+) and Forever; results in the 67-70 HUMAN-UAT files | 2026-10-10 |
| 73. Install to Forever's New Folder | v0.5.3 | 1/1 | Complete | 2026-10-22 |
| 74. Buff Duration on Spell Cooldowns | v0.5.3 | 2/2 | Complete | 2026-10-22 |
| 75. Buff Look on Cooldown Icons | v0.5.3 | 1/1 | Complete | 2026-10-22 |
| 76. Buff Duration on Bag Items | v0.5.3 | 2/2 | Complete | 2026-10-22 |
| 77. Cleanup | v0.5.3 | 2/2 | Complete | 2026-10-22 |
| 78. Human Testing | v0.5.3 | — | Complete — PASSED on retail; gap fix: buff follows its live aura (`469ff35`); #14 skipped | 2026-10-23 |
| 79. Buff Countdown Display Fix | v0.5.4 | 1/1 | Complete — verified in game on retail; one `/reload` miss not reproduced (fluke) | 2026-10-24 |
| 80. Forever Group Block, Group Buffs and Rank Coverage | v0.5.6 | 1/1 | Complete (code trace; in game in 85) | 2026-11-09 |
| 81. Mage Armors and Familiar Scrolls | v0.5.6 | 1/1 | Complete (code trace; in game in 85) | 2026-11-09 |
| 82. Other Class Rows | v0.5.6 | 1/1 | Complete (code trace; in game in 85) | 2026-11-09 |
| 83. Reminder Review Doc | v0.5.6 | 1/1 | Complete | 2026-11-09 |
| 84. Cleanup | v0.5.6 | 1/1 | Complete | 2026-11-09 |
| 85. Forever Testing Pass | v0.5.6 | — | Complete (mage verified in game; rest ships on feedback) | 2026-11-09 |

*Phases 43 and 44 ran as in-game testing passes rather than plan-driven phases, so they have no
plan count and no phase directory. Their record is the run sheets in `.planning/testing/`.*

*This table read "Not started" for eleven completed phases until milestone close — it was written at
roadmap creation and never updated as phases landed. Rebuilt 2026-09-23 from the phase directories
(one row per phase, plan count = SUMMARY.md count) and the run sheets.*

## Backlog

**999.5 — Cooldown icon can stay grey through the GCD.** **Closed 2026-10-10 (v0.5.2, VER-12): not seen in a long time and not seen in the Phase 72 pass on either client. If it comes back, open a new entry.** Carried out of v0.4.0 by user decision on
2026-09-23. The bug may already be fixed, but it was never consistently reproducible, so it stays
open pending more testing rather than being closed on a guess. Tracked at
`.planning/todos/done/2026-09-22-cooldown-icon-can-stay-grey-through-the-gcd.md`.

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

**999.8 — Show the AURA's icon where a racial's aura ID differs from its cast ID.** **Closed by v0.5.2 (Phase 67): racials removed from TBT.** Intake
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

**999.9 — TBT taints `EditModeManagerFrame` on every container click in Edit Mode.** **Shipped in v0.5.1 (Phase 61, EDM-08).** Found
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

**999.10 — Shadowmeld's cooldown starts when the buff ENDS, not when the skill is used.** **Closed by v0.5.2 (Phase 67): racials removed from TBT.** Reported by
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

**999.17 — Merge Mode hides the charge count while the spell's buff is up.** **Shipped in v0.5.1 (Phase 61, STEAL-09).** Reported by the user,
2026-09-30. On a charge spell whose buff is active, the Merge Mode cell correctly shows the **buff
duration** in place of the cooldown, as the CDM does — but the **charge count disappears** for as
long as the buff is up. Expected: the count stays visible, as it does on the CDM's own icon, so the
cell reads "buff has this long left, N charges remaining" at once. Reproduced on retail with the
Mage's **Prismatic Barrier**. Not yet diagnosed. Suspects in
`Display.lua`: the aura-owned sweep (`ApplyMergedAuraCooldown`) swapping the cell's owner without
the charge text being re-asserted (`ApplyChargeCount` runs only on a `_cdGen` change), or, with
`ns.mergeAuraGroupsActive`, the aura overlay drawn on top covering the underlying icon's
`chargeCount` — in which case the overlay needs its own count, on the CDM's `ChargeCount` rule.

**999.18 — Click a reminder to cast its spell (out of combat).** **Shipped in v0.5.1 (Phase 63, CLICK-01..06).** Intake 2026-09-30, user request.
Clicking a reminder icon casts the reminder's spell. On by default. Out of combat only, by design:
secure buttons cannot be changed in combat, so clicks are disabled there and that is stated
plainly in the option's tooltip.

Concept confirmed through API lookup:
- **A separate secure overlay per icon, never the icon itself.** `CreateFrame("Button", nil,
  UIParent, "SecureActionButtonTemplate")`, parented to `UIParent` and **never anchored** to the
  icon or its container, to avoid tainting the display tree: an anchor from a protected frame into
  it makes the tree protected, and every later `SetPoint`/`Show` on it would then error in combat.
- **Screen-coordinate placement.** Read the plain icon's `GetRect()` and place the overlay with
  `SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)`, copying size, strata and frame
  level + 1. Done on initial login (deferred a frame so the rects are calculated, which also clears
  any left-over mis-position) and again when Edit Mode closes. Dirty-checked on the rect.
- **The action is two attributes.** The secure handler reads what to do from attributes set on
  the button: `type1 = "spell"` (left click) and `spell = <cast spellID>`. Written only out of
  combat, and only when the reminder's cast spell changes.
- **Combat handled by the game's own secure code.**
  `RegisterStateDriver(overlay, "visibility", "[combat] hide; show")` hides the overlay in combat
  without TBT touching it. Every function that changes attributes, position, `EnableMouse` or
  visibility returns early on `InCombatLockdown()`; `PLAYER_REGEN_ENABLED` applies anything
  deferred.
- **Disabled during Edit Mode.** Overlays turn their mouse off (or hide) when Edit Mode opens, so
  they never swallow drags on the container, and are re-placed when it closes. Must not make
  999.9's `EditModeManagerFrame` taint worse.

**New advanced option on Reminders: the cast spell.** The spell a click casts is not always the
spell or aura the reminder tracks. Example, Mage on retail: the "Arcane Familiar" reminder is
gated on the talent 205022 being known and checks for the Arcane Familiar aura 210126, but the
spell to cast is **1459, Arcane Intellect**, which grants the Arcane Familiar buff when the talent
is known. The cast spellID defaults to the reminder's own spellID and can be overridden in the
reminder's advanced settings. Built-in reminders ship with the right cast spell already set.

**999.19 — Custom trackers show the buff's stack count.** Intake 2026-09-30, user request, found
during the v0.5.1 in-game review. TBT's custom (user) buff trackers ignore stacks: nothing TBT
draws for a user tracker carries a stack number, so a stacking buff shows no count. The only stack
count TBT draws today is its own cast-derived `timer.stacks` for built-in racials, on the
`icon.chargeCount` widget (Display.lua's live-timer branch in `RenderIconContainer`). A real stack
count is an aura read (`applications`), secret for a tainted caller in combat, so it would follow
the same readable-only rule as every other aura-driven behaviour, or come from the CDM where the
spell is also merged (999.16). This gap made 61-HUMAN-UAT #2 untestable; it was skipped, not failed.

**999.20 — Custom trackers show the remaining duration on the buff icon itself.** **Closed 2026-10-10: recorded in error — custom buff icons have always shown their countdown.** Intake
2026-09-30, user request, found during the v0.5.1 in-game review. A custom buff tracker's icon does
not show its remaining duration on the icon itself. Not yet diagnosed: the live-timer branch drives
the icon's Cooldown widget (`icon.cooldown:SetCooldown`), so start from how that widget's countdown
numbers and the container's "Show Timer" setting are applied. Reminders in their lead window
(REM-05) do show their countdown, so compare that path.

**999.21 — Merge Mode keeps a stale charge count after a spec change.** **Promoted into v0.5.2 (Phase 70, STEAL-20).** Reported by the user,
2026-10-03, on retail. After swapping Arcane → Frost, the Frost Orb cell showed **2 charges** while
the spell actually had none, and stayed wrong until `/reload`. Not yet diagnosed. Suspects in
`Display.lua`: `chargeCapable` is sticky per spellID and is never cleared on a spec or talent
change, and `ApplyChargeCount` leaves the previous text untouched whenever `GetSpellCharges` is
unreadable or returns nothing — and it runs only on a `_cdGen` change. So a respec can leave the
old count up with nothing ever overwriting it. Likely fix: drop `chargeCapable` and re-apply the
count on `PLAYER_SPECIALIZATION_CHANGED` / `TRAIT_CONFIG_UPDATED` / `SPELLS_CHANGED`, and hide it
(rather than keep the old text) when the spell no longer has charges.

**999.22 — Merge Mode: "Freezing" stacks on top of other cells in the centered display.** **Promoted into v0.5.2 (Phase 70, STEAL-21).**
Reported by the user, 2026-10-03, on retail (Frost Mage). The Freezing cell was drawn over other
skills in the centered (essential) viewer instead of taking its own slot. Not yet diagnosed. Two
hypotheses from the user: Freezing is a never-secret aura, so it takes a readable path the secret
ones never reach; or another Frost Mage in the group was applying Freezing to the same target.
The second ties into 999.23: `MergeMode.lua`'s target-aura lookup matches **any** caster's aura.
Start from how the aura overlay (`ns.mergeAuraGroupsActive`) positions its frame against the
cell it belongs to.

**999.23 — Merge Mode: Touch of the Magi shows as up when another mage applied it.** **Promoted into v0.5.2 (Phase 70, STEAL-21).** Reported by
the user, 2026-10-03, on retail. The player's Touch of the Magi cell lit up when a different mage
put it on the player's target. Needs a "cast by the player" filter. Likely cause in
`MergeMode.lua`: the readable target lookup calls
`C_UnitAuras.GetAuraDataBySpellName("target", spellName, filter)` with `TARGET_AURA_FILTERS =
{ "HARMFUL", "HELPFUL" }` — no `PLAYER` flag — so another caster's copy matches. The
`AURA_UNITS` candidate filter already sets `isFromPlayerOrPlayerPet` for the target; this direct
read path does not. Probably also behind 999.22.

**Note for 999.22 + 999.23 (user, 2026-10-03):** re-tested in a different raid comp with **no other
Frost Mage** — the Freezing overlap did **not** happen. So the overlap is most likely the same bug as
999.23: another mage's aura matching the player's entry. TBT never wants to track another player's
debuffs on the CDM, so once only the player's own auras can match, the overlap's positioning should
not need a fix of its own. Kept as two entries for now. When fixing and testing, do 999.23 first,
then re-test 999.22 **with another Frost Mage in the group**, which is what triggers it. Only look at
positioning if the overlap is still there after that.

**999.24 — Merge Mode: every cell turns into the same debuff while the player is mind-controlled.** **Promoted into v0.5.2 (Phase 70, STEAL-22).**
Reported by the user, 2026-10-03, on retail. During a fight where the player got mind-controlled,
every skill in the merged bar showed the same aura, a debuff on the player. **This has happened
before.** The user's requirement for the fix: **review the whole code path, not just the trigger.**
No code path may be able to paint one aura over every cell. Fixing this one trigger is not enough;
the design must make this kind of failure impossible.

Precedent: the 2026-09-22 resto-druid report, documented above `AURA_UNITS` in `MergeMode.lua`.
`AuraContainerUtil.DoesAuraPassCandidateFilters` applies `includeSpellIDs` **only** when
`CanApplyIdentityCandidateFilters` allows it. It does not allow it for
`isHarmful and UnitCanAssist("player", unit)`. In that case the spell-ID filter is skipped, the
aura matches **every** merged container, and one debuff paints every tile. That fix kept the gate
from opening on the target slot (`isFromPlayerOrPlayerPet`, plus `SlotAllowed` turning the target
slot off while the target is assistable). Suspects for how mind control gets past it:
- `targetIsAssistable` is a latch refreshed only on `PLAYER_TARGET_CHANGED` and
  `RefreshMergeAuraGroups`. Mind control changes who is friendly to whom **without changing the
  target**, so the latch goes stale. Nothing listens for `UNIT_FACTION`, `UNIT_FLAGS`,
  `PLAYER_CONTROL_LOST` / `PLAYER_CONTROL_GAINED` or the charm state.
- The **player** slot has no guard at all ("needs no such guard" because the player is always
  assistable to itself). While charmed that may not hold, and a harmful aura on the player
  becomes a candidate that skips the spell-ID filter. Check what `HELPFUL` and `isHarmful` mean
  for a charmed player's own auras.
- `isFromPlayerOrPlayerPet` may behave differently while the player is charmed, for example if
  the player counts as a pet or as the controlling unit's minion.

Direction: **fail closed.** Any state where Blizzard's identity gate could skip the spell-ID filter
must leave the slot matching nothing (`maxDuration = 0`, the existing off switch). The check must
be one that cannot go stale, for example asked when the slot's filters are sent and again on every
control or faction event, rather than a latch. Audit every `AURA_UNITS` entry and every
`SendSlotFilters` / `AddAuraSlot` call for a path where the include set can be bypassed.

**999.25 — Centered layout does not re-centre merged buffs.** **Promoted into v0.5.2 (Phase 70, STEAL-23) — treated as obsolete with 999.24, re-checked.** Reported by the user, 2026-10-04, on
retail. A Tracked Buffs container set to **Centered** does not centre. The user's container
currently holds **only merged buffs**. After adding a custom tracker, a merged buff ending still
did not make the run re-centre. **Review the centered layout as a whole**, not just this trigger.
Not yet diagnosed. Suspects:
- **`seen == 0` counts everything as shown.** In `ns:RefreshMergeShownSlots` (`MergeMode.lua`),
  `entry.cdmShown = (seen == 0) or shownCooldownIDs[...]`. When no buff is up, the CDM's buff
  viewer has no shown item frames, so `seen == 0` and **every** merged entry counts as drawn.
  `SlotDraws` then returns true for all of them, `drawnCount` equals the slot count, and the
  run is laid out at full width, which looks exactly like not centring. The "no answer" fallback
  and the "the CDM is genuinely showing nothing" answer are indistinguishable here.
- **Viewer parked off-screen.** The comment near `FlushMergeShownSlots` notes
  `CooldownViewerMixin:OnHide` unregisters `UNIT_AURA` and the rest. If the parked viewer's item
  frames stop updating, `cdmShown` goes stale.
- **No re-render on a `cdmShown` flip.** Check that a change in `cdmShown` marks the icon
  container dirty. If the render pass only re-runs on TBT's own timer or cooldown changes, a merged
  buff ending would not move the run until something else triggers a pass.
- **Engine-drawn aura containers keep their old cell.** A slot that does not draw gets no
  `anchor`, so `ns:PlaceMergeAura` is skipped and the engine's aura container stays at its last
  position. Check that a re-centred run actually moves every engine-drawn container. The
  placement dirty-check keys on anchor and offsets, so it should, provided the pass runs.

Related layout code in `Display.lua`: `CenteredSlotPlacement`, `SlotDraws` (must mirror
`RenderIconContainer`'s branch chain exactly) and the `centered` block in `RenderIconContainer`.

**999.26 — Merge Mode by moving Blizzard's CDM frames instead of redrawing them.** **Promoted into v0.5.2 (Phases 68-70, STEAL-10..19).** **Main task of
the next milestone**, by user decision 2026-10-10. Proof of concept passed on retail (raid boss
encounter, no taint); full record in `.planning/research/MERGE-REANCHOR-POC.md`. TBT keeps its
mirror and its layout. For each merged slot it hides its own widget and anchors Blizzard's item
frame onto it with `SetPoint` and `SetScale` only — no `SetParent`, no field writes, no mixin
calls — plus one `hooksecurefunc` on each viewer's `Layout`. Blizzard then draws cooldowns,
charges, auras, glows and borders exactly as the CDM does.

Scope for the milestone:
- Turn the prototype (`MergeReanchor.lua` and its `EXPERIMENT` branches) into the real Merge Mode
  rendering path.
- Fix the POC's open issues:
  - reordering in the CDM settings window corrupts the preview;
  - Edit Mode preview is missing merged bars;
  - TBT container visibility does not reach the moved frames.
- Remove the redraw machinery that goes dead for merged slots: engine aura containers, aura
  timing reads, bar and time relays, merged pandemic/dispel reads, and the merged charge-count
  path.
- Test in M+, on Forever, through a spec change, and in combat while Edit Mode is open.

Would close 999.21, 999.22, 999.23 and 999.24 by deleting their code paths. Re-check 999.25
(Centered) against the new path. Keep 999.24's requirement: no path may paint one thing over
every cell.

**999.27 — Custom cooldown trackers keep a stale charge count after a spec change.** Found
2026-10-10 by the v0.5.2 Phase 70 planner and the whole-path review (`70-MERGE-PATH-REVIEW.md`).
The same pattern as 999.21, outside Merge Mode: `Display.lua`'s `chargeCapable` cache is sticky per spellID
and never cleared on a spec or talent change, and `ApplyChargeCount` keeps the previous text when
`GetSpellCharges` is unreadable. v0.5.2 fixed 999.21 for merged slots by handing them to Blizzard's
own frames; TBT's own custom cooldown trackers still use this path. Not reproduced in game yet.

**999.28 — Review general buff duration: one aura pass for buffs, reminders and cooldown buffs.**
Intake 2026-10-23, user request, raised during the v0.5.3 Phase 78 retail pass. **Not for now:** the
current buff tracking behaviour is fine as is, and every detail of this discussion is left for
whenever this is picked up.

*What the user wants.* All three kinds watch the player's own auras, so they should follow one
flow. One detection pass runs and updates whichever buffs, reminders and cooldown buffs need it. A
buff tracker gets a new option, so it can scan for its aura on the player and take presence and
duration from the game's value:
- **on by default** for every new buff added;
- **off** for every buff tracker that already exists (no behaviour change on upgrade);
- **off** when the user adds a debuff to track.
Once enabled, the tracker scans for its aura on the player and updates presence and duration from
the game's value, the way the flask now does as a cooldown buff (below).

*Where it stands (read from `BuffEngine.lua`, 2026-10-23).* The three kinds handle a live aura
differently:

| | Starts when the aura is already up (login/reload, applied by someone else) | Follows the aura's real expiry (talents, refresh, stacking) | Ends on a readable aura loss |
|---|---|---|---|
| **Buff tracker** | No, only a cast starts it | No, it runs the typed duration | Yes (`ScanActiveTimersForCancellation`), unless "End when the aura is lost" is off |
| **Reminder** | Yes (`RefreshAuraStates`) | Yes, both ways; with the opt-out off it only ever extends | Yes, in both passes; it also holds a present/missing state that decides whether the reminder shows |
| **Cooldown buff** (v0.5.3) | Yes (`RefreshAuraStates`) | Yes, both ways | Yes (`ScanActiveTimersForCancellation`), no opt-out |

So a plain buff tracker does not pick up a buff already up at login/reload, and does not follow
an expiry the game changes. Reminders do, because v0.5.0 (Phase 57.2) built a separate refresh for
them. Cooldown buffs were attached to that same refresh in v0.5.3 Phase 78 (commits `09f36aa`,
`469ff35`), for the flask picked up after a reload.

*How the two passes split today:*
- **Two passes per aura event.** `ns:OnUnitAura` runs `RefreshAuraStates`, then
  `ScanActiveTimersForCancellation`. The post-cast re-check (`RunCastAuraRecheck`) and combat end
  (`PLAYER_REGEN_ENABLED`) run both too.
- **Some auras are read twice per event.** The refresh caches each aura read for its own pass
  (`refreshAuraMemo`), but the cancellation scan reads again. A running reminder timer is checked
  in both passes.
- **The rules differ in small ways.** Both passes use `ns.CAST_AURA_GRACE`, but each implements it
  separately. A full aura update (zone change, loading screen) suppresses only the ending of timers
  in the refresh (`suppressCancel`), but skips the cancellation scan entirely (ZONE-02). The opt-out
  on reminders only applies once a read has confirmed the buff (57.5 review WR-03); on buff trackers
  it applies at once.

*Proposed shape (2026-10-23, not decided).* One pass per aura event. Each watched aura ID is read
once (the existing memo). Then every tracked key, whatever its kind, goes through the same three
steps: start when the aura is up, follow its expiry, end on a readable loss past the cast grace.
The differences become per-kind settings rather than separate code:
- buff and reminder honour the "End when the aura is lost" opt-out; cooldown buffs have none;
- reminders also update their present/missing state;
- cooldown buffs start only in an icon container that is not hidden
  (`ns:FillCooldownBuffProc`);
- buff trackers start and follow only with the new option on.

The pieces already shared in v0.5.3 are `ReadWatchedList` (the read of a watched list, picking the
latest readable expiry), `SyncProcToAura` (the timing write) and `ns:FillCooldownBuffProc`. These
are the starting point. The refresh and the cancellation scan would merge into that one pass.

*Things to keep:*
- **Unreadable never counts as absent (DTRK-06).** Every read goes through `ns:ReadPlayerAura`,
  proven by `scripts/aura-read-gate.js`.
- **The typed Duration is never rewritten from a read.** Only the running timer follows the
  aura. A stacked aura is longer than one use's (two flasks = 2h), so the typed value stays as
  typed (user decision 2026-10-22).
- **The reminder rules from 57.2-05 and 57.5 hold:** the cast grace, the `syncedAt` window, the
  latest expiry among alternatives, and an open-ended aura outlasting the rest.
- **The behaviour change is visible.** With the option on, a buff applied by someone else (e.g.
  Power Infusion) starts the tracker. The default only applies to new buffs, so existing trackers
  are unaffected.

*A small gap to close in the same pass.* Reminders guard a fresh aura sync against the cast that
follows it (`syncedAt` in `ns:StartReminderFromCast`); cooldown buffs do not. If the aura event
arrives just before the cast, the cast resets the timer to the typed Duration for about half a
second, until the post-cast re-check moves it back.

**999.29 — Weapon-enchant reminders.** Intake 2026-11-09, user request, raised at the v0.5.6
kickoff. **Not for now:** the user asked for it to be noted only.

Reminders for weapon enchants: shaman imbues (60 min on Forever), rogue poisons, oils, sharpening
stones and the like. They are weapon enchants with no aura, so the reminder aura path
(`ns:ReadPlayerAura`, `ns:RefreshAuraStates`) cannot see them; they would need a
`GetWeaponEnchantInfo` path. Research: `.planning/research/FOREVER-REMINDERS.md` §6, where they are
excluded from v0.5.6 for this reason.

*The four original backlog phases — 999.1 (Edit Mode mouse-down), 999.2 (README and store copy),
999.3 (single-TOC migration) and 999.4 (`@project-version@` in dev installs) — were promoted into
v0.4.0 on 2026-09-20 and shipped as Phases 34, 45, 31-32 and 33 respectively.*

*999.12 (edit trackers), 999.13 (naming scheme) and 999.14 (elaborate trackers) were promoted into
v0.5.0 on 2026-09-28 and shipped as Phases 54, 53 and 56-57 (reshaped by 57.1-57.5). Their entries
above are kept as the design record, as 999.6 and 999.7 are for v0.4.1.*

*999.9 (Edit Mode taint), 999.17 (Merge Mode charge count) and 999.18 (clickable reminders) were
promoted into v0.5.1 on 2026-09-30 as Phase 61 (999.9 and 999.17) and Phase 63 (999.18). Their
entries above are kept as the design record.*

*999.5, 999.21-999.26 were promoted into v0.5.2 on 2026-10-10 (Phases 67-72); 999.8 and 999.10 close
with the racial removal in Phase 67; 999.20 was closed as recorded in error. Their entries above are
kept as the design record.*
