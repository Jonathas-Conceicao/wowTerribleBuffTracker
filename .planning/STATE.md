---
gsd_state_version: 1.0
milestone: v0.5.1
milestone_name: "Clickable Reminders and new icons"
status: complete
last_updated: "2026-10-01"
last_activity: 2026-10-01 — Milestone v0.5.1 archived and squash-merged to main
progress:
  total_phases: 6
  completed_phases: 6
  total_plans: 12
  completed_plans: 12
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-01)

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.
**Current focus:** Planning the next milestone (`/gsd-new-milestone`; phases start at 67).

## Current Position

Phase: — (v0.5.1 complete; Phases 61-66 all done)
Plan: —
Status: v0.5.1 shipped 2026-10-01 — Phase 66 passed on Forever and retail (incl. M+), user sign-off;
archived to `.planning/milestones/v0.5.1-*` and squash-merged to `main`. The user writes the
CHANGELOG entry, commits the new `Assets/` images with it, and tags the release.
Last activity: 2026-10-01 — milestone close

- Next kickoff: archive the phase log below to `.planning/milestones/v0.5.1-STATE-phase-log.md` and
  move `.planning/phases/61-*`..`65-*` to `.planning/milestones/v0.5.1-phases/`, as done for v0.5.0.
- Released and tagged `v0.5.1` by the user, 2026-10-01; the zip ships only `Media/Textures` BLPs (62-HUMAN-UAT #2 passed).
- Still open: 61-HUMAN-UAT #2 (waits on 999.19/999.20).

## v0.5.1 Phase Log

*Kept for the record until the next kickoff archives it. Superseded by the Current Position above;
every pending UAT note below was closed by Phase 66 on 2026-10-01.*

Phase: 66 of 66 (Human Testing) — in progress: **retail general review passed 2026-10-01** (user);
Forever regression check pending. Phase 65 executed 2026-10-01 (review WR-01 fixed in `be337ab`;
its 3 in-game checks passed on retail the same day)
Plan: —
Status: Phase 64 retail UAT passed 2026-10-01 (every class, clicks, lead window, combat, M+; Mark
of the Wild fixed to 1126, Lightning Shield 192106 added); only 64 #1 (Forever) pending, being
tested by the user
Last activity: 2026-09-30 — Phases 61, 62 and 63 executed, code-reviewed, review findings fixed,
verified (all `human_needed`) and deployed. In-game UAT deferred to Phase 66 by the user's
one-testing-pass decision: 5 items in `61-HUMAN-UAT.md`, 2 in `62-HUMAN-UAT.md`, 11 in
`63-HUMAN-UAT.md`. **Phase 63 added `ReminderClick.lua` to the TOC — a full client restart is
needed before testing, not `/reload`.** Phase 65 carries named cleanup targets from the 63 review:
IN-01 (shared spell-name helper), IN-02 (repeated stamp-clear code), IN-05 (tooltip hide without
ownership check), IN-06 (castID field duplicates the auraID field's preview row).
**User in-game review 2026-09-30:** clicks, Edit Mode, every paladin blessing, left/right/centre
orientations, combat and mid-combat expiry all worked with no errors. Two follow-ups requested and
built the same day, outside the phase flow: TAB-10 faction-themed tab icons (`5a7256d`, `_ally` /
`_horde`, resolved once per login) and REM-05, reminders showing in the last max(1s, 10%) of their
buff with its real remaining time (`0a40b05`). Both deployed; checks added as 63-HUMAN-UAT #12-13.

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 61 | Bug Fixes | EDM-08, STEAL-09 | Executed — UAT deferred to 66 |
| 62 | New Icons | TAB-08, TAB-09, INST-10, DIST-13 | Executed — UAT deferred to 66 |
| 63 | Clickable Reminders | CLICK-01..06 | Executed — UAT deferred to 66 |
| 64 | Retail Class-Buff Reminder Suggestions | MREM-04, MREM-05 | Executed — UAT deferred to 66 |
| 65 | Cleanup | — (process only) | Executed — UAT deferred to 66 |
| 66 | Human Testing (Forever, then retail) | — (testing pass, no plans) | Not started |

- Branch: `milestone/v0.5.1-clickable-reminders-new-icons`, cut from `topic/dev` on 2026-09-30.
- Phases start at **61** (v0.5.0 ended at Phase 60; numbering never restarts).
- Research skipped: backlog 999.18 in ROADMAP.md is the settled design for clickable reminders.
- **v0.5.0 is released** — squash-merged to `main` as `9aa91d7` and tagged `v0.5.0` (on `22f9f36`, the changelog commit after it). Its phase log
  is archived at `.planning/milestones/v0.5.0-STATE-phase-log.md` and its phase directories at
  `.planning/milestones/v0.5.0-phases/`.

Scope, confirmed by the user at kickoff, in build order: 999.9 (Edit Mode taint), 999.17 (Merge
Mode charge count), new tab icons, clickable reminders (999.18), retail class-buff reminder
suggestions (Mage specified; the user supplies other classes when that phase starts), cleanup, then
**one** human testing phase — Forever first, then retail — instead of two separate review phases.


## Last Milestone at a Glance

v0.5.1 Clickable Reminders and new icons: out-of-combat click-to-cast on every reminder through
secure overlays, an editable Cast spell ID, reminders showing in the last 10% of their buff,
faction-themed tab icons with a PNG→BLP pipeline, retail class-buff suggestions for every class,
and the Edit Mode taint and Merge Mode charge-count fixes. 16 of 16 requirements, verified in game
on the Forever beta and Midnight retail (incl. M+), 2026-10-01.

Full record: `.planning/MILESTONES.md` (v0.5.1 entry), `.planning/milestones/v0.5.1-ROADMAP.md`,
`.planning/milestones/v0.5.1-REQUIREMENTS.md`, `.planning/testing/66-HUMAN-TESTING.md`.

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
