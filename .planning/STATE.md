---
gsd_state_version: 1.0
milestone: v0.4.1
milestone_name: "Generic Item Tracking and Forever Racials"
status: in_progress
last_updated: "2026-09-25"
last_activity: 2026-09-26 — Phases 51 (Forever) and 52 (retail) both PASSED. All racials and their cancellations, the dispel indicator on both clients, consumables on both clients, and the pandemic highlight confirmed on retail IN M+. No Lua errors on either flavour. Every phase of v0.4.1 is now complete and reviewed. Remaining before release, in order: the user pastes their own CHANGELOG entry from 50-CHANGELOG-DRAFT.md (deciding two open recommendations), then squash-merge the milestone branch to `main`, then run release.bat FROM main.
progress:
  total_phases: 7
  completed_phases: 8
  total_plans: 18
  completed_plans: 18
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-20)

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.
**Current focus:** v0.4.1 — Generic Item Tracking and Forever Racials. Phase numbering continues from v0.4.0's Phase 45 and never restarts, so this milestone starts at Phase 46.

## v0.4.0 Release — done

Both steps completed. `f0c8e35` is on `main` and the `v0.4.0` tag exists. The warning block that
sat here described them as outstanding; it was written at archive time on 2026-09-23 and was
already stale when read on 2026-09-24, so it was replaced rather than left to mislead.

`.planning/REQUIREMENTS.md` is archived per milestone and written fresh by `/gsd-new-milestone`.

## Current Position
Milestone: **v0.4.1 — Generic Item Tracking and Forever Racials** (started 2026-09-24)
Phase: **49 COMPLETE (2026-09-25).** All five plans executed and merged, all ten races collected in
game, all 21 racials tracked, and the G1-G10 gate run by the user. **G4 — the migration — PASSED on
a real logout/login**: pre-phase `racial`/`racial2` entries were gone and their replacements
survived under `racial:<spellID>`. **G8 (Skyborne upward duration correction) is WAIVED for this
release by user decision** — the 15-minute condition was never reproducible, so both Skyborne second
racials ship on their minimum duration. RACE-07, RACE-08 and RACE-10 are closed; RACE-09 was closed
by D-7 rather than implemented (the generic tile its message lived on no longer exists).
Earlier: **46, 47, 48 and 48.1 ALL COMPLETE** — every gate run and passed, on retail AND Forever 1.60.1.
All ten ITEM requirements, all five PAND and all four DISP are closed. **Every feature this milestone
scoped is now built and verified on both flavours.**

**Nine fixes landed after the gate pass, all from in-game reports.** Plainsrunning's stack count;
Shadowmeld's in-combat behaviour (no buff tile, no lingering tile, and — separately — its 2-minute
in-combat cooldown); Walk on Air and then every racial buff gaining unconditional aura cancellation;
tracked item counts reconciling at login; and Eureka! spending a stack on every ability rather than
only harmful ones. Two of these were caused by a comment asserting something that was never checked
— see Blockers below.

**Phase 50 (Cleanup & Release Prep) is CLOSED — executed 2026-09-25, verification `passed` 5/5, code
review `clean`.** 3 plans, 2 waves. What landed:
- **SC3** — `ApplyDispelBorder` (`Display.lua`) now dirty-checks on a non-secret `cooldownID`
  identity instead of re-issuing `SetAtlas` every render pass while the atlas is secret. Landed in
  wave 1 deliberately: **its behavioural proof is carried to Phases 51/52**, which are in-game review
  passes already scheduled. That is a design decision, not an outstanding gap.
- **SC1/SC2** — the three milestone-introduced racial def-by-spellID walks unified behind
  `ns:RacialDefInList` (on `ns`, not a file-local — the upvalue trap this project has hit five
  times), and `ns:IsRacialKeyVisible`'s per-render-pass `string.match` allocation closed by memoising
  the PARSED KEY only. Memoising the visibility ANSWER would be a bug: it depends on `UnitRace`,
  which can be unreadable early in a session.
- **Deliberately NOT unified, with reasoning recorded in the plan SUMMARYs** so it is not
  rediscovered as an oversight: the three `Core.lua` key parsers (`cd:` predates the milestone and is
  protected by "No refactors during cleanup phases") and the pandemic icon/bar FX split (four
  genuine divergences, confirmed against the code).
- **SC5, as narrowed** — a v0.4.1 entry is drafted at
  `.planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md` for the **user** to paste and
  edit. `CHANGELOG.md` and `README.md` are byte-identical to the phase's base, verified by diff.
  The draft carries two open recommendations for the user to decide: include a Known Issues bullet
  for the G8 Skyborne waiver (drafted text supplied), and whether to list the untested Eureka!
  priest branch at all.

**F-3 — the aura-icon swap for the three divergent racials — is OUT**, in ROADMAP backlog **999.8**
with its full scope intact. It was folded into Phase 50 on Claude's initiative and reversed out by
user decision the same day, to close the milestone faster. Do not re-fold it.

**Phases 51 (Forever) and 52 (retail) both PASSED, 2026-09-26.** Run sheets:
`.planning/testing/51-FOREVER-REVIEW.md` and `52-RETAIL-REVIEW.md`. Confirmed in game: all racials
and their cancellations, the dispel indicator on both clients, consumables on both clients, and the
pandemic highlight on retail **in M+** — the strongest environment available for it, and the first
time it has been exercised under real load rather than in isolation. No Lua errors on either
flavour.

**Every phase of v0.4.1 is complete.** 46, 47, 48, 48.1, 49, 50, 51, 52.

**One qualification worth carrying, because it is the difference between two kinds of pass.**
Phase 52's **R1 stale-colour sub-check** — a pooled widget reused for a different entry keeping the
previous entry's border colour — was never run as a deliberate A/B. What it got was an M+ run, where
debuffs churn and containers re-sort continuously, which stresses the same property harder than a
two-debuff setup would; combined with the Phase 50 code review tracing all four `ApplyDispelBorder`
call sites, it is accepted as passing. Recorded as "exercised under load", not "deliberately
falsified", so nobody later reads it as a targeted test that it was not.

**Remaining before release, in this order — none of it is code:**
1. **The user pastes their own CHANGELOG entry** from
   `.planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md`. Two open recommendations are
   theirs to decide: whether to include a Known Issues bullet for the G8 Skyborne waiver (text
   drafted), and whether to list the Eureka! priest branch at all, given it is the one part of that
   change never tested in game. **No agent writes to `CHANGELOG.md`.**
2. **Squash-merge** `milestone/v0.4.1-item-tracking-forever-racials` to `main` with a clean message.
3. **`./scripts/release.bat <version>` FROM `main`** — never from the milestone branch.
   `release.bat` carries a branch guard for exactly this; `TBT_ALLOW_BRANCH=1` overrides it and
   should not be used here.
Plan: 46-01..04, 47-01..03, 48-01..03, 49-01..05 all executed; 48.1 built directly on user request,
no plan cycle
Status: **all in-game gates PASSED on both flavours, with G8 the single recorded waiver.**
Branch: `milestone/v0.4.1-item-tracking-forever-racials`, branched from `topic/dev`
Last activity: 2026-09-24 — Phases 46 and 47 CLOSED on the Forever pass. ITEM-05 confirmed the
milestone's central design bet: one HP potion fired the cooldown on all three pots sharing it, so a
per-item GetItemCooldown read does reflect a shared cooldown and the spell-category table correctly
stayed out of scope. ITEM-06, 07 and 08 all passed the same session. Campfire items stay in the
catalogue by user decision — they are Consumables, so no requirement bends to allow them.
Earlier — Phase 48.1 (dispel-type border) CLOSED, fully verified on retail:
icons and bars, Magic and Bleed, in and out of combat. Two routes — the aura engine draws it for
an ordinary merged tracked buff (the atlas mirror structurally cannot reach that case, since
RenderIconContainer hides TBT's pooled icon there), the mirror covers bars, item-backed entries
and the engine-off fallback. The atlas name is SECRET IN COMBAT and is relayed to SetAtlas unread
(`SecretArguments = "AllowedWhenTainted"`) rather than discarded; `IsShown()` stays plain, so
visibility is decided on a readable boolean. Also in this stretch: the CDM-tab item-icon defect
(ns:ItemDisplayInfo read only the bag catalogue — confirmed fixed in game), the engine route's
`showWithoutDispelType` divergence from the CDM's show rule, and a stylua-introduced CRCRLF that
had made MergeMode.lua binary to git

**Every requirement this milestone scoped is now implemented AND closed by a real in-game gate.**
ITEM-01..10, PAND-01..05, DISP-01..04, RACE-07, RACE-08 and RACE-10 all have a user verdict behind
them; RACE-09 was closed by D-7 rather than implemented. The run-order instructions that used to
fill this section are spent and were removed on 2026-09-25 rather than left to be re-run.

**Two waivers are on the record, and they are waivers rather than passes.** Phase 49 **G8** — the
Skyborne upward duration correction — was never reproducible in game, so both Skyborne second
racials ship on their minimum duration; and **F-2's priest branch** — a gnome priest's Eureka!
spending a stack on a heal — ships untested, by user decision on 2026-09-25. Neither is a gap
nobody noticed; both are the user's explicit call for this release.

F-2's *other* branch did get a gate: a gnome **mage** was confirmed in game the same day, which
matters because the first attempt at that fix removed `IsSpellHarmful` globally and broke exactly
that branch for all five classes. Only `PlayerIsPriest()` returning true is unexercised.

**The standing rule that produced those gates still applies to anything Phase 50 changes.** This
project has no test runner and none is planned — the only runtime is the game client, a static
sweep proves the code is *shaped* right and nothing more, and no phase checkbox is ticked on a
sweep alone.

Deployed to all four client folders. No TOC change since the single-TOC migration, so `/reload`
suffices — a full client restart is only needed when the TOC itself changes, and a real
logout/login is the only way to exercise a SavedVariables load path (which is what made Phase 49's
G4 unskippable).

**A blocker was found by code review after that phase verified, and it is worth remembering how.**
`itemUseSpellToID` — the table that turns an arriving cast into "this item was used" — was only
ever filled by the catalogue scan, which runs only while the Cooldown Manager is open. A player who
never opened the CDM would have had every landed use silently fail to decrement. The plan checker
passed the plans and the verifier traced the use chain forward and found it sound, because the
defect is only visible if you trace **backwards from the table to ask who writes it**. Fixed in
`f5dc170`; registration now comes from `ns.db.trackedBuffs` with no bag access.

Carry that into the remaining phases: a correctly-wired chain fed by an empty table reads exactly
like a working one when traced forwards.

Scope, confirmed by the user at kickoff: generic item tracking (backlog 999.6), Forever racials
(`RACE-07` only — `RACE-06`, the retail catalogue, stays deferred), and the CDM pandemic highlight
(backlog 999.7). The v0.4.0 phase log that used to fill this section is archived at
`.planning/milestones/v0.4.0-STATE-phase-log.md`.

## Phase Plan — v0.4.1 (set at roadmap creation, 2026-09-24)

| Phase | Name | Requirements | Depends on |
|-------|------|--------------|------------|
| 46 | Item Catalogue & Suggested Tiles | ITEM-01, 03, 08, 10 | — |
| 47 | Item Tracking & Cooldown Sharing | ITEM-02, 04, 05, 06, 07, 09 | 46 |
| 48 | Pandemic Highlight in Merge Mode | PAND-01..05 | — |
| 49 | Forever Racial Catalogue | RACE-07, 08, 09 | — (scheduled here by decision) |
| 50 | Cleanup & Release Prep | none (process) | 46-49 |
| 51 | Forever Full Review | none (verification pass, no plans) | 46-50 |
| 52 | Retail Full Review | none (verification pass, no plans) — **last phase** | 51 |

**Ordering note, settled 2026-09-24 over three revisions the same day.** The user first said only
"schedule RACE last", then refined it to an exact closing order — Racials, a Forever review pass, and
a retail review pass as the milestone's literal last phase. The roadmapper placed Cleanup at 49,
ahead of Racials, reasoning the racial work adds only a data-table entry per race. The user rejected
that on review: Cleanup now runs at 50, **after** all feature work, so no feature ships without a
cleanup pass. Both review passes are testing-only — no plans, no phase directory — matching v0.4.0
Phases 43-44's shape, recorded as run sheets in `.planning/testing/`.

Racials sit late because a game update landing 2026-09-24 may make the feature obsolete; building it
early risks effort that gets dropped.

See `.planning/ROADMAP.md` for full phase details, goals and success criteria.

## Last Milestone at a Glance

TBT became a two-flavour addon: one shared Lua/XML source set loading on both Midnight retail
(Interface 120100) and the WoW Forever beta (Interface 16001), selected by two flavour-suffixed TOCs,
with no forked source file and zero flavour-detection tokens in any Lua file.

25 of 30 requirements closed. Verified in-game on Forever build `1.60.1.69913` and on Midnight retail,
both 2026-09-18.

Full record: `.planning/MILESTONES.md` (v0.3.0 entry), `.planning/milestones/v0.3.0-ROADMAP.md`,
`.planning/milestones/v0.3.0-REQUIREMENTS.md`.

## Deferred Items

Acknowledged and deferred at v0.3.0 close, 2026-09-19. **Re-read 2026-09-20 at v0.4.0 kickoff — the
table below is no longer current, see the note under it.**

| Category | Item | Status |
|----------|------|--------|
| requirement | `DIST-03` — one tag produces two distinctly-named zips | open — needs a real tag push |
| requirement | `DIST-04` — each zip contains only its own flavour's TOC | open — needs a real tag push |
| requirement | `DIST-05` — both matrix jobs publish to one release without clobbering | open — needs a real tag push |
| requirement | `DIST-06` — each job's game-version tag is correct | open — needs a real tag push |
| requirement | `DIST-07` — `RELEASE_NOTES.md` correct when run once per matrix job | open — needs a real tag push |
| verification | Phase 29 `29-VERIFICATION.md` | `human_needed` — the five rows above are its open half |
| todo | `2026-09-18-install-bat-does-not-prune-stale-files.md` | pending — pruning is new behaviour outside `INST-01`…`04` |
| todo | `2026-09-18-pkgmeta-shared-ignore-list-can-drift.md` | pending — shared nine-line ignore block has no drift guard |
| todo | `2026-09-18-runtime-file-set-enumerated-three-places.md` | pending — `install.bat` `FILES` + both TOCs enumerate independently |
| todo | `2026-09-18-release-bat-pushes-main-with-no-branch-guard.md` | pending — tags whatever `HEAD` it runs from, always pushes `origin main` |

### What changed at v0.4.0 kickoff (2026-09-20)

- **`DIST-03`…`DIST-07` are superseded, not deferred.** Every one of them describes two distinctly-named
  zips, per-flavour game-version tags, or a two-job matrix. v0.4.0 moves to **one TOC and one zip**, so
  the mechanism they were written against no longer exists. v0.4.0 must restate the distribution
  requirements in single-zip terms rather than carry these forward verbatim. The Phase 29 Deferred
  Verification checklist is likewise obsolete in its two-zip specifics.
- **All four tooling todos are now in scope.** `install.bat` pruning and the three-place file-set
  enumeration are both touched directly by 999.4 and the single-TOC migration; the `.pkgmeta` drift guard
  becomes moot once there is only one `.pkgmeta`; and the `release.bat` branch guard belongs with the
  release-script pass. Reconcile them inside this milestone rather than leaving them pending.

**Original v0.3.0 note, kept for the record —** `DIST-03`…`DIST-07` were deferred by explicit user
decision, 2026-09-18: *"do the impl and we will
test once we close the milestone and add any hotfix straight to main later if needed."* The checklist to
run at that time is the Deferred Verification table in
`.planning/phases/29-packaging-distribution/29-01-SUMMARY.md`.

**Two things to watch at that first release.** Read **both** matrix jobs' full CI logs rather than the
green check — the packager silently omits a game-version tag if a store's version list lacks it. And
check the two asset names: a trailing dash, or two identically-named zips, means `game_type` came out
empty and `-g` did not take.

## Accumulated Context

### Decisions

Full decision log lives in `.planning/PROJECT.md` (Key Decisions) and the v0.3.0 archive. Only the
constraints that outlive the milestone are repeated here:

- **One shared source set, no flavour fork.** No flavour-forked Lua or XML file may exist — still
  binding. **Changed 2026-09-20:** the two-TOC half is retired. v0.4.0 moves to a single
  `TerribleBuffTracker_Mainline.toc` declaring all interface versions, which also retires
  `scripts/check-toc.ps1` and both `.pkgmeta-*` files.
- **Runtime flavour detection: one sanctioned exception, otherwise still banned.** Forever differences
  are handled as data-absence conditions with nil checks — the default, and it held end to end through
  v0.3. **Narrowed 2026-09-20 by user decision:** the add panel's "cover all ranks" checkbox is present
  on Forever and absent on retail by an explicit version check. The user was offered the data-driven
  alternative (show it only when the spell resolves to a multi-rank family, needing no flavour check)
  and declined it — they want the control unconditionally present on one flavour and unconditionally
  absent on the other, not appearing dynamically and not disabled-but-visible. **This licenses exactly
  one flavour check, not a pattern.**
- **`_Camelot` is case-sensitive** — relevant only until the single-TOC migration deletes that file.
  Capitalisation is verified through `git ls-files`, never a Windows file browser; the same rule applies
  to any TOC rename this milestone performs.
- **Capability checks, not client-identity checks.** Guard on the API symbol existing, so a client
  lacking it degrades to a silent no-op rather than a load error.
- **`issecretvalue()` comes first**, before any comparison or concatenation — including on values
  returned from an API that already succeeded. `type()` reports `"number"` for a secret number, so a
  type check alone passes and gives false confidence.
- **Cleanup-phase scope:** `CLAUDE.md`'s "unify repeated behaviour" mandate covers duplication the
  milestone itself introduced; `PROJECT.md`'s "No refactors during cleanup phases" protects everything
  pre-existing. Settled by user decision 2026-09-18.
- **v0.4.1 closing order (2026-09-24):** Racials (49) → Cleanup (50) → Forever full review (51) →
  Retail full review (52, the literal last phase). Racials sit late because a game update landing
  that day may make the feature obsolete. Cleanup follows all feature work rather than preceding it,
  so nothing ships without a cleanup pass — the roadmapper's first draft put Cleanup at 49 and the
  user rejected it on review.

### Pending Todos

**None.** All four were resolved in Phases 32-33 and moved to `.planning/todos/done/` on 2026-09-20.

### Blockers/Concerns

- **A confident comment is not a verified fact, and this milestone paid for that twice.**
  `StartRacialProc` carried a comment asserting that a racial's cooldown tile *"reads the live game
  handle, which already knows the longer in-combat cooldown without being told."* It does not:
  `ApplyCooldownSlot` calls `ApplyUserCooldown` first, and a tracker carrying a duration never
  reaches the engine handle at all — the deliberate CD-02 reversal of 2026-09-20. Shadowmeld's
  in-combat cooldown therefore ran 10s instead of 2 minutes, **and the first investigation of the
  bug repeated the comment's claim and closed it as cosmetic**, because the comment made the claim
  look already-checked. The same shape appears in `FOREVER-RACIALS.md`'s open question 1, which told
  a later reader that racials are never aura-cancelled and to revisit only if that changed — it
  changed the same day. Both are corrected in place. **When a comment asserts what another file
  does, go read that file.**

- **The TOC filename carries the game type — never re-suffix it.** `TerribleBuffTracker.toc` must stay
  unsuffixed. The BigWigs packager derives the game type from the filename suffix and then hard-fails any
  `## Interface:` value that disagrees, so `_Mainline.toc` can never declare `16001`. Resolved 2026-09-20;
  do not reopen. Any TOC change needs a **full client restart** to test — `/reload` never re-reads the
  AddOns folder.
- **Never inject into Blizzard's CDM containers.** Measured 2026-09-20: five injection variants — up to
  one using zero Blizzard Lua, C-level `GetChildren()` and deferred writes only — all tainted the CDM
  with `CooldownViewerItemData.lua:782 hasTotem` errors. Calling any Blizzard CDM mixin method leaves the
  frame tainted afterwards, and the taint is **sticky**: it survives leaving combat and clears only on
  `/reload`. A combat guard is preventive, never curative. This is why v0.4.0 mirrors into TBT's own
  containers instead.
- **Direct aura APIs hard-error for tainted callers under restriction.** Both enumeration and ID-based
  calls, and a cached instance ID does not help. Curve evaluation results are secret even from an
  addon-built curve. Both closed, not deferred — see
  `.planning/research/EXPERIMENTS-BUFF-API-AND-CDM.md`.
- **The cast-driven stack model can never self-verify in combat.** The nominal duration timer must always
  run as a backstop. `C_Spell.IsSpellHarmful` means "can target an enemy", not "deals damage", so it
  over-fires — Frost Nova consumed a Eureka! stack the game did not. Accepted by the user 2026-09-20:
  over-consuming is preferred to under-consuming, since the failure mode is a tracker ending early rather
  than showing a buff the player no longer has. Recorded so it is not re-opened as a bug.
- **Ranked spell IDs on Forever disagree with the CDM.** Vanilla ships rank variants with distinct IDs
  (Frostbolt `116` vs the CDM's `205`; Fireball `133`/`143` vs `145`). TBT keys everything by spellID, so
  a user adding the rank they cast silently disagrees with the CDM. `GetBaseSpell` / `GetOverrideSpell`
  are readable in combat and are the bridge. This is what the "cover all ranks" checkbox exists to solve.
- **`.planning/` records no retail probing for any of this.** Every measurement behind v0.4.0's feature
  design was taken on Forever build `1.60.1.69913` / interface `16001`. Retail M+/raid validation was
  deliberately skipped to save time and is the milestone's second-to-last phase.

- **Settings do not persist between sessions on the Forever beta.** A client-side bug, not TBT's: the
  file is written correctly on logout and is byte-identical to its `.bak`, but never read back on login.
  Other addons are affected identically. Nothing to fix or adapt to on the addon side —
  `Blizzard_ClientSavedVariables` exists on both flavours and no new TOC directive governs addon
  storage. Documented as a known issue in `CHANGELOG.md` and `README.md`. Retail is unaffected.
- **`/reload` does not test SavedVariables persistence** — the data survives in memory, so such a test
  cannot fail. Only logout→login exercises the load path. A v0.3 verification record asserting
  persistence was withdrawn for this reason; do not repeat the test design.
- **An engine-side global present on Midnight is not guaranteed on Forever.**
  `GetScaledCursorPositionForFrame` was absent and threw 53 errors in one drag session, from code that
  had shipped since v0.2.0. Worth a scan before assuming any engine global is safe cross-flavour.
- `install.bat` copies but never prunes, so a deployed folder still holds every file ever deleted from
  the repo — `ConfigUI.lua`, removed in v0.2.0, is still sitting in `_retail_`. Harmless today because
  nothing loads it, but it means a deployed folder is not a clean picture of the current source.
