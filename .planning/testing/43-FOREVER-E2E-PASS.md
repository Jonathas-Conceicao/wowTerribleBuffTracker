# Phase 43 — Forever End-to-End Verification Pass

**Client:** WoW Forever beta, `_classic_beta_`, product `wow_classic_beta`, build 1.60.1.69913,
interface 16001.
**Method:** not a scripted run-sheet. The pass was carried out as continuous play-testing between
2026-09-21 and 2026-09-22, feature by feature, with each defect reported, fixed and re-tested on the
same client before moving on. Signed off by the user 2026-09-22: *"everything on Forever is tested
and acceptable"*.

## Features exercised

| Feature | Result |
|---|---|
| Buff trackers — bars and icons | pass |
| Cooldown trackers, typed duration | pass (see CD-02 below) |
| Four base containers (bars/buffs/essential/utility) | pass |
| User-created containers, buff and spells, create and delete | pass |
| Centered growth on buff containers | pass, horizontal and vertical |
| Grid placement: left/right, up/down, both orientations | pass |
| Merge Mode with engine-driven sweeps | pass |
| Merged-aura positioning inside a container | pass |
| Edit Mode: drag, save, per-container settings popup | pass |
| Edit Mode: vertical containers offer Down/Up | pass |
| Edit Mode: container highlight scales with icon size | pass |
| Reduced add dialog (no container, no type field) | pass |
| Duration parsing `30s` / `2m`, invalid format blocks Add | pass |
| Add dialog cancels on tab swap and on CDM close | pass |
| Ranked grouping (`coverAllRanks`) | pass |
| Racial meta-tracker (Eureka!) | pass |
| Same spell ID as both a buff and a cooldown tracker | pass |
| Preview sweeper is additive and does not outlive itself | pass |
| Settings panel under Options > AddOns, `/tbt` | pass |
| Merge-mode slide switch, container list scroll, logo | pass |
| Allocation rework (pre-allocate on add, release on remove) | pass, no behaviour change observed |

## Defects found and fixed during the pass

All fixed and re-tested on the same client:

- merged auras starting mid-bar (container sized from withheld slots)
- icon container highlight not scaling with icon size
- custom cooldown duration overwritten by the game's real cooldown (**CD-02 reversed**)
- preview sweeper outliving the CDM close
- same spell ID colliding between a buff and a cooldown tracker (**schema v6**)
- `displayInfoPool` nil on delete (file-local upvalue trap, third instance)
- cooldown keys resolving to the question-mark icon with no tooltip
- `/tbt` raising `bad argument #1 to 'OpenSettingsPanel'`
- the Cooldown Manager button opening Advanced Options instead of the manager
- the settings panel logo drawing nothing (a broken texture path)
- the container list clipping over Quick Actions

## Known issues carried forward

- **GCD greying.** A skill can still show briefly greyed from the global cooldown. Backlogged by
  user decision; not a blocker.
- **`/reload` untestable.** A Forever beta client bug unrelated to TBT. Accepted by user decision
  2026-09-22; ongoing cooldowns are deliberately not persisted, so nothing depends on it.

## Criterion 4 — settled: Forever writes, but never reads back

Criterion 4 asks that any persistence claim be backed by logout→login rather than `/reload`.
**It is not satisfiable on this client, and that is the client's bug, not something TBT adapts to** —
which is exactly the disposition the criterion asks for.

Forever *does write* a real file:

    _classic_beta_/WTF/Account/<account>/SavedVariables/TerribleBuffTracker.lua

2689 bytes as of 2026-09-22, holding four trackers (including two `cd:` keys), four Edit Mode
positions, `mergeMode = true`, `nextContainerId = 8` and `schemaVersion = 6`. **The client never
reads it back** (confirmed by the user, 2026-09-22), so every login starts from an empty database
and anything written is discarded. That is why the file is at v6 despite nothing ever having been
migrated: a fresh database runs every block from `ver = 0` and lands on v6 too.

The consequence for the milestone: **no persistence claim has been tested anywhere yet**, and the
v4/v5/v6 migrations have only ever run against an empty table. Both are Phase 44's job, on retail,
where saved variables actually round-trip.
