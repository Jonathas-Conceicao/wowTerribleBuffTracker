# TerribleBuffTracker

## What This Is

A WoW addon for manually tracking buff and cooldown timers, running on both **Midnight retail** (Interface 120100) and the **WoW Forever beta** (Interface 16001) from one shared source set. Because `COMBAT_LOG_EVENT_UNFILTERED` is disabled in Midnight, TBT uses `UNIT_SPELLCAST_SUCCEEDED` plus known durations to create visual timer bars and icons anchored to Blizzard's Cooldown Manager (CDM).

## Core Value

Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.

## Current Milestone

**None active.** v0.3.0 shipped 2026-09-19. Start the next one with `/gsd-new-milestone`.

<details>
<summary>v0.3 WoW Forever compatibility — SHIPPED 2026-09-19 as v0.3.0</summary>

**Goal:** One shared source set loading correctly on both Midnight retail (Interface 120100) and WoW
Forever beta (Interface 16001), with two user-facing additions (TOOL-01, META-01) approved
mid-milestone on 2026-09-18.

Delivered in full, with one deferral: `DIST-03`…`DIST-07` (the observable half of two-flavour
packaging) require a real tag push and were deferred to the first release by explicit user decision.
25 of 30 requirements closed. See `.planning/milestones/v0.3.0-ROADMAP.md` and the v0.3.0 entry in
`.planning/MILESTONES.md`.

</details>

### Next Milestone Goals

Nothing committed yet. Candidates already recorded, in rough order of how much is known about them:

- **Close `DIST-03`…`DIST-07` at the first release.** Not a milestone of its own — it is the checklist
  in `29-01-SUMMARY.md`'s Deferred Verification table, run once against real CI logs. Read both matrix
  jobs' logs in full rather than the green check: the packager silently omits a game-version tag if a
  store's version list lacks it, and two identically-named zips (or one with a trailing dash) would
  mean `game_type` came out empty.
- **Forever content support (`FCON-01`…`FCON-03`)** — Forever-appropriate lust, trinket and consumable
  catalogs, and per-flavour Suggested sections. Blocked on knowing Forever's content and level cap.
  The mechanism is already in place: META-01 hides what does not resolve, so shipping real Forever
  catalogs makes the tiles reappear with no code change.
- **Phase 999.1** — Edit Mode container selects on click-release instead of click-down. Pre-existing
  backlog item, unrelated to flavours.
- **The four tooling todos** under `.planning/todos/pending/`, chief among them that `install.bat`
  never prunes, so every file ever deleted from the repo lingers in a deployed folder.

## Requirements

### Validated

- Timer tracking via UNIT_SPELLCAST_SUCCEEDED + GetTime() + known duration — v0.1
- Timer bars and buff icons displayed anchored to CDM — v0.1
- Config UI for adding/removing tracked buffs (spell ID, duration, label) — v0.1
- Enable/disable individual buffs — v0.1
- Display mode toggle per buff (bar or icon) — v0.1
- Preview mode (starts all timers for testing) — v0.1
- SavedVariables persistence (account-wide) — v0.1
- `/tbt` slash command to open config — v0.1
- CI/CD with BigWigs Packager for CurseForge/Wago/GitHub releases — v0.1
- Schema migration v0→v1: section-based buff management model (bars/buffs/hidden) — v0.2 Phase 1
- Edit Mode: two independent movable containers (bars, buffs) with position persistence, floating checkbox panel, NineSlice overlay — v0.2 Phase 2
- CDM tab shell: TBT Buffs tab in CDM settings, content panel, /tbt opens CDM, ConfigUI.lua removed — v0.2 Phase 3
- CDM tab sections: 4 collapsible sections, icon grids, Add dialog, delete zone visual, right-click context menus — v0.2 Phase 4
- Drag-and-drop: section-to-section drag, within-section reorder, CDM-style reorder marker, delete zone drag — v0.2 Phase 5
- UNIT_AURA event registration (player-filtered), secret-value blocked flag, isFullUpdate suppression, preview guard, debug toggle — v0.2.1 Phase 7
- Aura scan cancellation: ScanActiveTimersForCancellation removes timers for absent buffs via GetPlayerAuraBySpellID — v0.2.1 Phase 8
- Lust meta-buff: Sated-family debuff detection auto-starts 40s timer, class-aware CDM icon, Suggested section activated as static catalog — v0.2.1 Phase 10
- Trinket meta-tracker: shared slot tracking all season on-use trinkets via cast detection, shared-slot overwrite (newest cast wins) — v0.2.3 Phases 12-13
- Damage pot meta-tracker: shared slot tracking all current-season damage potions via cast detection, shared-slot overwrite — v0.2.3 Phases 12-13
- Dynamic CDM icon resolution: trinket shows equipped trinket icon, pot shows bag consumable icon; refreshes on CDM settings open (out of combat); falls back to first CSV entry — v0.2.3 Phase 14
- Active timer icon switches to cast spell icon; reverts to at-rest resolved icon on expiry — v0.2.3 Phases 13-15
- SpellProvider skeleton: Providers.lua with SpellProviderBaseMixin + UserSpellProviderMixin (CreateFromMixins); ns:DispatchEventToProviders routes user-spell casts through provider OnTrigger — v0.2.4 Phase 17 (PROV-03)
- TrinketProvider + PotProvider (separate mixins per D-05); static data relocated to Providers.lua with ns.* exports preserved; BuffEngine.OnSpellCastSucceeded reduced to single dispatcher call (zero if/elseif branches); cast-triggered procs carry castSpellID for aura cancellation; Display.lua metaSlot dual-index replaced with timer.key lookup — v0.2.4 Phase 18 (PROV-02, LIFE-01)
- LustProvider (4th and final provider registered at position 3); lust data colocated (SATED_DEBUFF_TO_LUST, SHARED_LUST_BUFFS new export, CLASS_LUST_SPELL, GetHunterLustSpell) with ns.* exports; BuffEngine.OnUnitAura rewritten dispatch-first preserving LUST-01 by architecture (dispatcher is dumb and uniform — providers self-govern secret/preview safety); no-restart guard provider-internal; ScanActiveTimersForCancellation reads ns.SHARED_LUST_BUFFS; flag renamed secretGateLogged / ClearSecretGateLog for clarity — v0.2.4 Phase 19 (PROV-01, LIFE-02)
- GetDisplayInfo unified provider contract (collapsed GetPreviewInfo + GetAtRestInfo); ns:GetDisplayInfoForKey dispatch helper via local keyToProvider table; PROV-F3 pulled in — TrinketProvider/PotProvider own minimal atRest cache (spellID + duration; icon/label derived via GetSpellIcon + C_Spell.GetSpellInfo) and RefreshAtRest with combat gate; ns:RefreshMetaIcons reduced to thin wrapper iterating ns.providers; BuffEngine shims (GetAtRestMetaIcon, GetAtRestMetaInfo, ResolveSuggestedSpellID) delegate through ns:GetDisplayInfoForKey — v0.2.4 Phase 20 (PROV-04, PROV-F3 absorbed)
- Additive-preview architecture: separate ns.previewTimers table; StartAllPreviewTimers skips running slots and uses ns:GetDisplayInfoForKey as sole data source; ClearAllTimers wipes only previews (no snapshot/restore); ns:GetActiveTimers merges both tables with real-priority override; ns.previewActive flag and OnUnitAura guard deleted; fixes trinket/pot 0-second preview bug AND mid-CDM real cast loss in one pass — v0.2.4 Phase 21 (LIFE-03)
- Display unification + proc shape cleanup: 9-field normalized proc shape (dropped icon/source/castSpellID/lustBuffID/string-coexistence); proc.spellID always numeric drives icon + tooltip + cancellation; unified ScanActiveTimersForCancellation via proc.aliveBuffs list (single-loop strategy, no source branching); ns:ShowBuffTooltip shared handler between Display bar/icon OnEnter; Display derives icon per-widget via cachedSpellID/cachedIcon cache (providers stay UI-agnostic); SHARED_LUST_BUFFS demoted to Providers.lua local; GetSuggestedAtRestIcon + metaIconsDirty flag fully deleted — v0.2.4 Phase 22 (DISP-01, DISP-03)
- Orphan removal and release prep: three backwards-compat shims (GetAtRestMetaIcon, GetAtRestMetaInfo, ResolveSuggestedSpellID), ns.TRINKET_FALLBACK_ORDER / ns.POT_FALLBACK_ORDER namespace exports, and stale phase-lifecycle comments all deleted (grep-gated sweep); ns:RefreshMetaIcons renamed ns:RefreshProvidersAtRest to match post-refactor architecture; pots_info.csv and trinket_info.csv source files removed; hot-path audit confirmed no allocation regressions on Display render, OnUnitAura dispatch, or ScanActiveTimersForCancellation; v0.2.4 CHANGELOG entry added; stylua-clean — v0.2.4 Phase 24 (DISP-04)
- 12.1 compatibility: interface bump to 120100; survives the fully-secret `UNIT_AURA` payload; lust/heroism tracking keeps working in combat; an already-running lust shows correct remaining time instead of restarting at 40s; a lingering Sated debuff can no longer start a phantom timer; cancellation no longer acts on an unreadable aura — v0.2.5 (shipped outside GSD)
- CDM tab placement fix: TBT tab anchors under whichever Blizzard tab is bottom-most (so a future patch's tab pushes ours down instead of covering it); Group Buffs tab no longer stays highlighted while the TBT panel is open — v0.2.6 (shipped outside GSD)
- Split flavor TOCs (`TerribleBuffTracker_Mainline.toc` at 120100, `TerribleBuffTracker_Camelot.toc` at 16001) sharing one identical file list, with `scripts/check-toc.ps1` as a pre-tag drift guard; verified in-game on both flavours 2026-09-18 — Forever on build `1.60.1.69913`, and retail from `_Mainline.toc` once the stale unsuffixed TOC was deleted from the deployed folder (`TOC-01`/`VER-01` closed) — v0.3 Phase 25
- Argument-free multi-client `install.bat` deploying the shared file set and both TOCs to every client folder present, skipping absent ones, failing when none found — v0.3 Phase 26
- Provider at-rest defensive fix: Trinket and Pot tiles never present an unresolved hardcoded fallback as real; a shared neutral placeholder with `duration = 0` keeps both tiles draggable rather than returning nil (`nil` would throw at `BuffEngine.lua:283`, which computes `now + info.duration`); confirmed on both flavours — Forever showed the question-mark placeholder, retail kept all three tiles present and draggable — v0.3 Phase 27
- TOOL-01 spell and aura ID tooltip: one shared implementation behind a capability existence check on `TooltipDataProcessor.AddTooltipPostCall`, no flavor branch; what unblocked Forever cast-detection testing at all — v0.3 Phase 27.1
- META-01 data-driven meta-tile hide via per-provider `HasResolvableCatalog` and the memoised `ns:IsSuggestedKeyResolvable`, plus the PAR-02 resolve-before-`SetSpellByID` guard; verified in both directions — Forever hides all three tiles as designed, retail keeps all three present and draggable — v0.3 Phase 27.1
- Forever in-game verification pass on build `1.60.1.69913`, interface `16001`, 2026-09-18: `UNIT_SPELLCAST_SUCCEEDED` delivers a usable spellID, CDM attaches, the tab injects, bars and icons render on CDM's atlases, Edit Mode works end-to-end, combat produces no uncaught aura-read error; zero failures, two Forever-only defects found and fixed (`9fde1eb`, `9e32f92`). **Correction:** the pass originally recorded SavedVariables as persisting, on the basis of a `/reload` test. That test could not have failed — `/reload` keeps the data in memory and never exercises the load path. Cross-session persistence is broken on this beta; see Context — v0.3 Phase 28
- Packaging split into two flavor-pure configs: `.pkgmeta` replaced by `.pkgmeta-mainline` / `.pkgmeta-camelot` (identical shared config, each cross-ignoring the other flavor's TOC); `release.yml` gained a serialised two-job matrix (`max-parallel: 1`) passing `-m .pkgmeta-<flavor>` and a `{game-type}`-templated `-n`, with `RELEASE_NOTES.md` regenerated per job; `CHANGELOG.md`'s v0.3.0 entry names the tested beta build and interface. Guard-verified via `check-toc.ps1` assertion 3 and reviewed statically — configured and guard-verified, **not yet exercised by a real tag push** (`DIST-03`…`DIST-07` remain the milestone's one open gap, deferred to the first release by user decision) — v0.3 Phase 29

### Active

*None — v0.3.0 shipped and `.planning/REQUIREMENTS.md` was archived to
`.planning/milestones/v0.3.0-REQUIREMENTS.md`. A fresh REQUIREMENTS.md is created by
`/gsd-new-milestone`. Carry-forward candidates are listed under Next Milestone Goals above.*

## Current State

**Last shipped:** v0.3.0 WoW Forever compatibility (tagged 2026-09-19) — interface 120100 (Midnight retail) + 16001 (Forever beta). First release to ship two flavours.

**Planning drift note:** v0.2.5 (12.1 compatibility) and v0.2.6 (CDM tab placement) were both developed, tagged and released outside the GSD workflow, so they have no phase artifacts under `.planning/phases/`. They are recorded in `CHANGELOG.md`, `MILESTONES.md` and the Validated list above; that is the whole of their planning record — no phases are reconstructed retroactively.

**Current milestone:** none active. v0.3 ran Phases 25-30 (continuing from v0.2.4's Phase 24), so the next milestone starts at Phase 31 — phase numbering never restarts.

**Open backlog:** Phase 999.1 (Edit Mode container selects on click-release instead of click-down) — captured during v0.2.4 verification, still awaiting promotion.

**v0.3.0 shipped 2026-09-19.** Functional on WoW Forever as of build `1.60.1.69913` and regression-free
on Midnight retail, both verified in-game 2026-09-18. The two retail items that were provisional at
Phase 30 are now closed: the retail pass was re-run after deleting the stale unsuffixed
`TerribleBuffTracker.toc` from the deployed folder (so the load is genuinely from `_Mainline.toc`), and
META-01's retail behaviour was confirmed — all three meta tiles present and draggable. **One requirement
group remains open by decision:** `DIST-03`…`DIST-07`, the observable half of two-flavour packaging,
which cannot be checked without a real tag push.

**Known issue shipped with v0.3.0:** settings do not persist between sessions on the Forever beta. A
client-side bug — see Context.

### Out of Scope

- Updating timer durations from aura data — future enhancement
- Aura-based buff auto-discovery — only checks already-tracked buffs
- Preview preserving per-buff state on CDM open/close — works at timer level but could be more granular

## Context

- WoW Midnight (Interface 120000+), COMBAT_LOG_EVENT_UNFILTERED disabled
- **Forever ships no retail spell data (found 2026-09-18, `FOREVER-TEST-PASS.md`):** the lust Suggested tile rendered the `134400` question-mark icon, which only occurs when `C_Spell.GetSpellInfo(2825)` returns nil. That nil is the exact discriminator META-01's data-driven hide relies on — the mechanism needs no flavor check, and a client that later ships those spells shows the tiles again with no code change.
- **`GetScaledCursorPositionForFrame` is absent from Forever's engine (found 2026-09-18, `FOREVER-TEST-PASS.md`):** `CDMTab.lua`'s ghost-frame `OnUpdate` called it every frame of every drag — 53 errors in one session. Fixed in `9e32f92` by reusing the `GetCursorPosition()`/`GetScale()` idiom the file's three other cursor sites already used, removing the engine dependency instead of shimming it. The defect was pre-existing since v0.2.0, not a v0.3 regression — the lesson generalises: an engine-side global present on Midnight is not guaranteed on Forever.
- **SavedVariables do NOT persist across sessions on the Forever beta (corrected 2026-09-19):** an earlier note here claimed they did, on build `1.60.1.69913`, because Edit Mode container positions survived `/reload`. **That test was invalid** — `/reload` keeps the data in memory and never exercises the load path, so it could not have failed. Logout and log back in and every value is a hardcoded default; the saved file is written correctly on logout and is byte-identical to its `.bak`, so the client writes but never reads. Other addons are affected identically, which is what first surfaced it. The third-party report filed against build `69893` was right. **TBT is not at fault and there is nothing to adapt to:** `Blizzard_ClientSavedVariables` is present on both flavours and no new TOC directive governs addon storage. Documented as a known issue in `CHANGELOG.md` and `README.md`; retail is unaffected.
- CDM is Blizzard's Cooldown Manager — addon must integrate with its settings UI
- Blizzard UI source available at `C:\Users\jonat\Repositories\wow-ui-source`
- CDM templates: `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml` and `.lua`
- Edit Mode: `Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`
- Layout: `Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua` and `GridLayoutUtil.lua`
- Current display anchors bars/icons to CDM containers; Edit Mode will decouple this
- **WoW Forever** is Blizzard's third game pillar (Classic-inspired with its own quirks) alongside Retail (Midnight) and Classic; it follows a Midnight-style API, so cross-flavor code should stay shared
- Forever beta ships under product `wow_classic_beta` → installs to `World of Warcraft\_classic_beta_`; build `1.60.1.69893+` → Interface **16001**
- Forever's game-type token is `camelot` (Blizzard TOCs declare `## AllowLoadGameType: standard, camelot`); BigWigs packager's flavor TOC suffix is `_Camelot`, and it maps interface prefix `16???` → game type `forever`
- Forever ships `Blizzard_CooldownViewer` (including `GroupBuffFilter.lua`), `Blizzard_EditMode`, and the secret-value API docs — TBT's hard dependencies are all present
- Forever API/style mirrors: `BigWigsMods/WoWUI` branch `forever-beta` (primary) and `Gethe/wow-ui-source` branch `forever`

## Constraints

- **API**: No COMBAT_LOG_EVENT_UNFILTERED — must use UNIT_SPELLCAST_SUCCEEDED
- **UI Framework**: Must use WoW's native frame/widget system (no external libs)
- **CDM Dependency**: Tab must integrate with existing CDM settings window, not replace it
- **Compatibility**: Interface 120100 (Midnight retail) **and** 16001 (Forever beta), from one shared source set selected by two flavour-suffixed TOCs. The two TOCs may differ on `## Interface:` and `## Notes:` only; `scripts/check-toc.ps1` enforces this pre-tag
- **Migration**: Must not break existing TerribleBuffTrackerDB data
- **Cross-flavor**: one shared Lua/XML file set must load on both Interface 120100 (Midnight) and 16001 (Forever) — no flavor-forked source files in v0.3
- **Forever fixes stay narrow**: Forever-specific breakage is fixed solely with narrow defensive reads — no `WOW_PROJECT_ID` branch, no flavor-forked code path. That half of the original parity-only constraint still holds and is still binding. The parity-only *scope* was widened on 2026-09-18 with explicit user approval to admit two capabilities beyond parity: TOOL-01 (spell and aura ID tooltip) and META-01 (data-driven meta-tile hide)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Integrate as CDM tab rather than standalone window | Matches Blizzard UI patterns, reduces addon footprint | ✓ Good — shipped v0.2.0 |
| Two independent Edit Mode elements (bars + buffs) | Users may want bars and buff icons in different positions | ✓ Good — shipped v0.2.0 |
| Copy CDM settings once on fresh install | Sensible defaults without ongoing coupling | ✓ Good — shipped v0.2.0 |
| New buffs land in Not Displayed | User explicitly chooses where to show, avoids clutter | ✓ Good — shipped v0.2.0 |
| Stateless providers; BuffEngine owns all lifecycle (Option A) | Keeps providers testable and side-effect-free; single place to reason about proc expiry and reproc | ✓ Good — shipped v0.2.4 |
| Plain-table ActiveProc (no metatable) | Avoids per-instance metatable GC overhead in hot paths | ✓ Good — shipped v0.2.4 |
| Dispatcher-first event flow; providers self-govern secret/preview safety | LUST-01 ordering preserved by architecture instead of by an explicit branch in BuffEngine | ✓ Good — shipped v0.2.4 |
| Additive preview with separate `ns.previewTimers` | Eliminates snapshot/restore and the mid-CDM real-cast-loss bug as an architectural side-effect | ✓ Good — shipped v0.2.4 |
| Key-driven display reads (`proc.key`, not `proc.spellID`) | `.key` is stable across meta-buff slot contents; `.spellID` is a derived numeric. Phase 22 regression proved this is load-bearing | ✓ Good — codified in v0.2.4 after `df48029` regression fix |
| No refactors during cleanup phases | Keeps release-prep phases narrow and predictable; prevents last-mile scope creep. Protects code that **predates the milestone**; `CLAUDE.md`'s GSD Workflow cleanup mandate separately covers duplication the milestone itself introduces — complementary, not contradictory (settled 2026-09-18) | ✓ Good — Phase 16 + Phase 24 honored this. Phase 30 is where the two rules first collided (real v0.3-introduced duplication in `install.bat` / `.pkgmeta-*`); the reading above was settled by user decision on 2026-09-18 |
| Split flavor TOCs (`_Mainline` + `_Camelot`) over a single multi-interface TOC | Client selects the right TOC per flavor with no reliance on comma-form parsing; CurseForge/Wago receive correctly-tagged per-flavor uploads | ✓ Good — shipped v0.3.0. Verified on both clients 2026-09-18; the `_Camelot` suffix was confirmed empirically by the Forever client loading the file |
| `install.bat` installs to every client present, no arguments | Simplest possible change; `./scripts/install.bat` keeps working unchanged in the existing workflow | ✓ Good — shipped v0.3.0; deployed every Forever test build during the milestone |
| v0.3 is metadata + tooling only — no Forever features | Establishes a verified cross-flavor baseline before any Forever-specific capability work | **Superseded 2026-09-18** — widened with explicit user approval to admit TOOL-01 and META-01: TOOL-01 was a hard prerequisite for testing cast detection on Forever at all (no other way to discover Forever spell IDs on that client), and META-01 removed three tiles that could never carry a value there |
| Widen v0.3 scope to admit TOOL-01 + META-01 | The alternative was an untestable milestone: no way to discover a working Forever spell ID without a diagnostic tooltip, and three tiles permanently showing a wrong retail value with no data-driven hide | ✓ Good — approved 2026-09-18, both shipped Phase 27.1 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? Move to Out of Scope with reason
2. Requirements validated? Move to Validated with phase reference
3. New requirements emerged? Add to Active
4. Decisions to log? Add to Key Decisions
5. "What This Is" still accurate? Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-19 after the v0.3.0 milestone*
