---
gsd_state_version: 1.0
milestone: v0.5.0
milestone_name: "Elaborate tracking"
status: archived
last_updated: "2026-09-29"
last_activity: 2026-09-29 — v0.5.0 archived; awaiting the user's CHANGELOG entry, squash-merge to main and release.
progress:
  total_phases: 13
  completed_phases: 13
  total_plans: 42
  completed_plans: 42
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-29)

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.
**Current focus:** releasing v0.5.0 Elaborate tracking. No milestone is active; the next one starts at Phase 61.

## Current Position

**v0.5.0 archived; awaiting CHANGELOG + release.**

- Milestone: v0.5.0 Elaborate tracking — all 13 phases (53-60, incl. 57.1-57.5) complete, 42 plans,
  33/33 requirements; Forever and retail (incl. M+) full reviews approved by the user 2026-09-29.
- Archives: `.planning/milestones/v0.5.0-ROADMAP.md`, `.planning/milestones/v0.5.0-REQUIREMENTS.md`.
  Phase directories stay in `.planning/phases/` until the next kickoff moves them, as v0.4.1's were.
- Release, in order: (1) the user writes the `v0.5.0` entry in `CHANGELOG.md` (no agent edits it
  unless asked); (2) squash-merge `milestone/v0.5.0-elaborate-tracking` to `main`; (3) run
  `scripts/release.bat` from `main`, which creates the tag. No tag was created at archive time.
- Branch: `milestone/v0.5.0-elaborate-tracking`. Next milestone starts at Phase 61.

## v0.5.0 Phase Log

*Kept for the record until the next kickoff archives it as `milestones/v0.5.0-STATE-phase-log.md`,
as v0.4.1's was. Superseded by the Current Position above; the pending-UAT notes below were all
closed on 2026-09-29.*

Phase: 53 EXECUTED (5/5 plans, review fixes applied, deployed) — in-game UAT pending in
`53-HUMAN-UAT.md` (8 items, deferred to the end of the run).
Phase: 54 EXECUTED (4/4 plans, review fixed, deployed) — in-game UAT pending in `54-HUMAN-UAT.md`
(11 items, incl. one DECISION on racial cooldown kind).
Phase: 55 EXECUTED (3/3 plans, review fixed, deployed) — in-game UAT pending in `55-HUMAN-UAT.md`
(14 items, incl. whether retail has `GetSpellBaseCooldown` for non-charge suggestions).
Phase: 56 EXECUTED (4/4 plans, review fixed incl. WR-04 cover-all-ranks + aura ID, deployed) —
in-game UAT pending in `56-HUMAN-UAT.md` (13 items). Includes the ADD-06 portrait.
Phase: 57 EXECUTED (5/5 plans, review fixed, deployed) — in-game UAT pending in `57-HUMAN-UAT.md`
(16 items). Review fix WR-03 refines the in-combat rule to the user's own wording: visibility
follows the aura whenever it can be read, and freezes only while it can't. Only the aura-driven
START waits for combat to end.
Plan: 53-01..05, 54-01..04, 55-01..03, 56-01..04 and 57-01..05 done
Phase: 57.1 EXECUTED (3/3 plans, review fixed, deployed) — the dialog redesign: General/Advanced
TabSystemTemplate tabs, Advanced prefilled, visibility radio dropdown, no `detailed` flag (schema v9).
In-game UAT pending in `57.1-HUMAN-UAT.md` (8 items). REQUIREMENTS.md ADD-07 still says
"Simple/Detailed"; the user renamed them General/Advanced, so update the text at milestone close.
User passed in game 2026-09-29: 57.1 tabs and v9 migration, 57 "absent" reminder.
Phase: 57.2 EXECUTED (4/4 plans, review fixed, deployed, verification human_needed) — Buff
Reminders as a third category (REM-01..04): TBT Reminders tab, Buff Reminders base container,
`userReminder` kind behind `ns:IsReminderEntry`/`ns.REMINDER_KINDS` (ready for metaReminders), the
Phase 57 absent runtime reused as-is plus combat/unreadable/restriction hide, visibility option
removed (DTRK-03 superseded), schema v10. In-game UAT pending in `57.2-HUMAN-UAT.md` (20 items, the
v10 check needs a real logout/login on both clients). Phase 58 candidates from its review: WR-05
(`visibility*` names now mean reminders; Phase 58 renames them) and IN-05 (the "In Combat" option
on a reminders container: KEPT, since reminders show mid-combat when a known duration runs out).
User passed in game 2026-09-29: reminders work and the v10 migration worked.
Quick follow-up 2026-09-29: Buff Reminders seed moved to BOTTOMLEFT (850, 580), hand-picked by the
user; buff trackers now get a duration suggestion from the live aura when it is up and readable
(empty otherwise, no tooltip parsing, by user decision).
**Secrecy text trimmed 2026-09-29 at the user's direction:** the "Aura secrecy: <level>" line stays;
the explanations are short and name no content types (no M+/raid). The user may still hand-tune it.
**Built (57.2-05, 2026-09-29, review fixed, deployed, UAT pending):** reminders are buff trackers in
their own category (duration, aura-loss and cast rules back; v10 keeps them), their state is held
while the aura cannot be read, and their timer syncs to a readable expiry, so a reminder fires
mid-combat when its buff ends. Review fix 05-WR-01 added a 0.5s cast grace to BUFFS too (shared
path, per the "reminders are buffs" rule). 57.2-HUMAN-UAT.md has 26 items.
Phase: 57.3 EXECUTED (3/3 plans, deployed) -- in-game UAT pending in `57.3-HUMAN-UAT.md` (22 items),
on branch `topic/visibility` (cut from the milestone branch at 913c7a3; the user may drop it). One
load rule, "Load: When known / Always / Never" (LOAD-01..04): an editable Advanced setting on user
trackers (`entry.load`, nil = When known), fixed for built-ins (racials When known; Lust, trinket,
pot, bag items Always); an unloaded tracker is in no index, never drawn, greyed in the TBT tab. The
race gate is gone: racials are just spells, loaded when known. No schema step (still v10).
Phase: 57.4 EXECUTED (3/3 plans, deployed) -- in-game UAT pending in `57.4-HUMAN-UAT.md` (24 items, 23
pending, Priest/Druid/Warrior/Hunter rows skipped by user scope). Class buffs as built-in
`metaReminder` trackers (MREM-01..03): a 14-row Forever table in Providers.lua, offered as Suggested
tiles on the Reminders tab for known rows, own cast namespace, fixed When known load, every known
rank counts; Blood Pact loads on Summon Imp (688, unverified) and reads the imp's rank from the pet
spellbook. No schema step (still v10).
Phase: 57.5 EXECUTED (3/3 plans, deployed) -- in-game UAT pending in `57.5-HUMAN-UAT.md` (16
items). Reminder alternatives (RALT-01..03): 'Also satisfied by' replaces 'Ends when you cast' for
reminders only; the blessings satisfy each other; Righteous Fury added, Sanctuary dropped; schema
v11.
Phase: 58 EXECUTED (4/4 plans, deployed) -- in-game smoke UAT pending in `58-HUMAN-UAT.md` (11
items). Cleanup: reminder runtime renamed (visibility* to reminder*), the milestone's duplicated
family/base-override/cast-owner/ID-list/radio code unified, dead branch removed, hot paths
audited, docs corrected; new: Merge Mode on for a fresh database (user request).
**Autonomous run 56-57 finished 2026-09-28.** Phases 53-57 are all executed and deployed, and all
await in-game UAT (64 items across five HUMAN-UAT files). Remaining: Phase 58 Cleanup (named
targets: the base/override lookup duplicated three times in Core.lua, and wiring
aura-read-gate.js into release, declined 2026-09-29 by user decision), 59 Forever review, 60 Retail review.
**Autonomous run 53-55 finished 2026-09-28**; the user reviewed 55 in game ("looking nice") and asked
for the ADD-06 portrait. **Run 56-57 in progress.** Phases 53-56 are executed and deployed but NOT
closed: each waits on its HUMAN-UAT file. Next after 57: run the UAT (`/gsd-verify-work 53`..57).
`scripts/aura-read-gate.js` (30-case selftest) is the standing DTRK-06 proof; Phase 57's aura-state
cache must pass it. Wiring it into release was left to the cleanup phase (declined 2026-09-29 by user decision).

**Carry into Phases 56-57 (from 54 review WR-02, fixed):** the dialog saves ONLY fields that were
visible and read at Save time ("not read means not written"), so a detailed-tracking field hidden in
simple mode keeps its saved value. Design the simple/detailed switch with that rule in mind.
Status: Autonomous run, Phases 53-55 (started 2026-09-28); context for all three taken up front
Branch: `milestone/v0.5.0-elaborate-tracking`, branched from `topic/dev`
Last activity: 2026-09-29 — ALL PHASES 53-60 COMPLETE. Phases 59 (Forever) and 60 (retail, incl.
M+) full reviews human-reviewed and approved by the user; every HUMAN-UAT file closed (items not
tested by name recorded as "accepted"). Next: milestone close-out (/gsd-complete-milestone:
audit, squash-merge to main, then release.bat; CHANGELOG entry only when the user asks).

**v0.4.1 is released** — squash-merged to `main` as `c30084a` and tagged `v0.4.1`. The "remaining
before release" list that sat here was stale; the v0.4.1 phase log is archived at
`.planning/milestones/v0.4.1-STATE-phase-log.md` and its phase directories at
`.planning/milestones/v0.4.1-phases/`.

Scope, confirmed by the user at kickoff: naming scheme (999.13), tracker editing (999.12), and simple
+ detailed tracking (999.14 widened — see PROJECT.md Current Milestone). Research skipped.

## Phase Plan — v0.5.0 (set at roadmap creation, 2026-09-28)

| Phase | Name | Requirements | Depends on |
|-------|------|--------------|------------|
| 53 | Naming Scheme & Saved-Data Migration | NAME-01, NAME-02 | — (v0.4.1 shipped) |
| 54 | Edit Trackers | EDIT-01, EDIT-02, EDIT-03, EDIT-04 | 53 |
| 55 | ID Preview, Suggested Cooldown & Secrecy | ADD-04, ADD-05, SECR-01, SECR-02, SECR-03 | 54 |
| 56 | Detailed Tracking — Mode & Aura Rules | DTRK-01, DTRK-02, DTRK-04, DTRK-06 | 55 |
| 57 | Detailed Tracking — Visibility & Cross-Spell Rules | DTRK-03, DTRK-05 | 56 |
| 58 | Cleanup | — (process) | 57 |
| 59 | Forever Full Review | — (testing pass, no plans) | 58 |
| 60 | Retail Full Review | — (testing pass, no plans; last phase) | 59 |

## Last Milestone at a Glance

v0.5.0 Elaborate tracking made every user tracker editable, named every tracker kind by one scheme
(schema v8-v11), and added Advanced settings, Buff Reminders with alternatives, a When known /
Always / Never load rule, and Forever class-buff reminders. 33 of 33 requirements closed, 4 adjusted
by later user decisions. Verified in game on the Forever beta and Midnight retail (incl. M+),
2026-09-29.

Full record: `.planning/MILESTONES.md` (v0.5.0 entry), `.planning/milestones/v0.5.0-ROADMAP.md`,
`.planning/milestones/v0.5.0-REQUIREMENTS.md`.

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
| todo | `2026-09-18-release-bat-pushes-main-with-no-branch-guard.md` | done — release.bat has the branch guard (todo is in `todos/done/`) |

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

- **Superseded 2026-09-28 — the user reports SavedVariables have persisted on Forever for a while now.** Original note: settings did not persist between sessions on the Forever beta. A client-side bug, not TBT's: the
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
