---
phase: 53-naming-scheme-saved-data-migration
plan: 05
subsystem: infra
tags: [migration, schema-versioning, naming-scheme, wow-addon, lua, node, saved-variables]

# Dependency graph
requires:
  - phase: 53-naming-scheme-saved-data-migration
    provides: "plan 53-01's scripts/migrate-dryrun.js --selftest (the executable spec), plan 53-02's Core.lua ns.KIND/ns.KEY_PREFIX/ns.META_KEY scheme and BuffEngine.lua schema v8, plan 53-03's Providers.lua on the scheme, plan 53-04's Display.lua/MergeMode.lua/CDMTab.lua on the scheme"
provides:
  - "Confirmed byte-for-byte reconciliation between BuffEngine.lua's ns:MigrateKindKeys (schema v8) and scripts/migrate-dryrun.js's migrateV8 -- gating, classification, move-not-rebuild, entry.key/trackerType rewrite, and the spellID/itemID backfills all agree with no code change required"
  - "A passing whole-codebase naming-gate sweep: no old kind identifier (trackerType buff/cooldown/item, cd:/item:/racial: prefixes, lust/trinket/pot literals, *_KEY_PREFIX constants) survives outside BuffEngine.lua's frozen v6/v7 migration literals"
  - "A hot-path audit confirming UserSpellProviderMixin:OnTrigger allocates nothing per cast, Display.lua's render paths do zero key parsing, and ns:RebuildCastIndex is reached from exactly the four sites the scheme design specifies"
  - "A deployed build (./scripts/install.bat, 4 client folders) and an ordered in-game verification checklist for the user (NAME-02's real logout/login proof)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cross-file naming-scheme gate sweep: a fixed battery of greps/awks run once at the end of a phase to prove a property (no old identifier survives) that no single plan's own acceptance criteria could check alone"

key-files:
  created: []
  modified: []

key-decisions:
  - "No divergence found between BuffEngine.lua's ns:MigrateKindKeys and scripts/migrate-dryrun.js's migrateV8 -- both files were left unchanged, per the plan's own instruction ('If both already agree, change neither file'). Plans 53-01 through 53-04 already built the Lua migration directly from the node spec's interfaces block, so the two never drifted."
  - "The six full-line comments in BuffEngine.lua/CDMTab.lua/Display.lua naming an old provider identifier (TrinketProvider, PotProvider, LustProvider, RacialProviderMixin, LustProviderMixin) are left as-is -- the plan's own gate 6 acceptance form filters full-line comments in files other than Providers.lua, and rewriting prose-only history references was out of this task's scope"

requirements-completed: []

# Metrics
duration: 4min
completed: 2026-09-28
---

# Phase 53 Plan 05: Reconciliation, Naming Gates, and Deploy Summary

**Reconciled BuffEngine.lua's schema-v8 migration against scripts/migrate-dryrun.js's executable spec with zero divergence found, ran the whole-phase naming-gate sweep and hot-path audit clean, and deployed the build to 4 WoW client folders with an ordered in-game verification checklist for NAME-02's real logout/login proof.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-09-28T11:32:57Z (previous plan's completion commit, 824ab65)
- **Completed:** 2026-09-28T11:36:00Z
- **Tasks:** 2/2 completed (Task 1: verification only, no file changes; Task 2: deploy only, no file changes)
- **Files modified:** 0 (this plan is verification and deployment; no divergence to fix, no scripts to edit)

## Accomplishments

- **Point-by-point reconciliation of `ns:MigrateKindKeys` (BuffEngine.lua) against `migrateV8` (scripts/migrate-dryrun.js):** gating (`ver >= CURRENT_SCHEMA_VERSION` / `ver < 7` in Lua vs `schemaVersion < 7 || schemaVersion >= 8` in JS -- equivalent since `CURRENT_SCHEMA_VERSION = 8`), collect-then-move via a snapshot array before any mutation, every classification branch (numeric nil/"buff" -> userBuff, numeric "cooldown" -> defensive re-classify via `ns:CooldownKindFor`/racial-membership, `cd:N`/`item:N`/`racial:N` string prefixes, `lust`/`trinket`/`pot` literals, already-canonical passthrough), the same-table move with the occupancy-drop-not-clobber rule, `entry.trackerType`/`entry.key` rewrite, and the `spellID`/`itemID` backfills (only when the field was nil) all agree exactly. `ns:MigrateRacialKeys` (v7) and `migrateV7` both gate/stamp on the literal `7` and both use the frozen literal `"racial:"` prefix (not `ns:TrackerKey`), and both call sites (`ns:InitBuffEngine`, Core.lua's `PLAYER_ENTERING_WORLD` branch) call v7 then v8 in that order. No divergence found; neither file was changed.
- Confirmed `ns:IsRacialSpellID` (Providers.lua) and `extractRacialSpells()` (scripts/migrate-dryrun.js) both classify "racial spellID" across **every** race (`pairs(RACIAL_SPELLS)` / `byRace` walking all keys), never gated on the current character's race, matching 53-CONTEXT's "Migration shape" decision.
- `node scripts/migrate-dryrun.js --selftest` prints `SELFTEST PASS (5 cases)` and exits 0.
- All whole-phase naming gates ran clean against the current source:
  - `grep -n '_KEY_PREFIX' *.lua` -> nothing.
  - `grep -nE 'trackerType *[=~]= *"(buff|cooldown|item)"' Core.lua Providers.lua CDMTab.lua Display.lua MergeMode.lua` -> nothing.
  - The old-prefix/meta-literal sweep across Core.lua, Providers.lua, CDMTab.lua, Display.lua, MergeMode.lua, EditModeFrames.lua, Config.lua -> nothing outside the three permitted `ns:TrackerKey(ns.KIND.META_*, "lust"/"trinket"/"pot")` call sites; that count is exactly 3.
  - BuffEngine.lua's regression-guard sweep (everything from `ns:GetSpellIcon` onward) -> nothing; `ns.SUGGESTED_KEYS` is built only from `ns.META_KEY` members.
  - Kind-string identity between Core.lua and scripts/migrate-dryrun.js for all six kinds (`userBuff`, `userCd`, `metaSkill`, `metaSkillCd`, `metaItem`, `userItem`) -> every kind present in both files; the three meta ids (`metaSkill:lust`, `metaItem:trinket`, `metaItem:pot`) appear in the dry-run and are built in Core.lua via `ns:TrackerKey`.
  - Old provider-name sweep (`\b(Trinket|Pot|Lust|Racial|Item)Provider(Mixin)?\b`) -> nothing in live code; six matches are full-line comments in BuffEngine.lua/CDMTab.lua/Display.lua (not Providers.lua), which the plan's own acceptance-criteria form (`grep -vE ':[0-9]+:\s*--'`) explicitly permits and defers to this SUMMARY to list (see Known Provider-Name Comments below).
- **Hot-path audit:** `UserSpellProviderMixin:OnTrigger` (Providers.lua) creates no string, table, or closure on the cast path -- both the cooldown-side and buff-side lookups go through `ns.cooldownKeyBySpell`/`ns.buffKeyBySpell` (single table lookups), the proc and aliveBuffs list come from the existing pools (`ns:AcquireProc`, `ns:AcquireAliveBuffs`), and the only string concat (`"Spell " .. tostring(entry.spellID)`) is a defensive fallback that only fires when `entry.label` is nil. `Display.lua` contains zero calls to any key parser (`KeyKind`, `KeyNumericID`, `SpellKeySpellID`, `CooldownKeySpellID`, `ItemKeyItemID`, `RacialKeySpellID`, or a raw `:match(`) -- its render paths read `entry.trackerType` directly via `ns:IsCooldownSlotEntry`/`ns:IsBagItemEntry`. `ns:RebuildCastIndex` is reached from exactly four sites: `ns:RebuildRankIndex` (Core.lua:908), `ns:InitBuffEngine` (BuffEngine.lua:237), `ns:MigrateKindKeys` (BuffEngine.lua:487), and `AddSuggestedTracker` (CDMTab.lua:216) -- matching the plan's specified call-site set exactly.
- Formatting and line endings: `stylua Core.lua BuffEngine.lua Providers.lua CDMTab.lua Display.lua MergeMode.lua` made no changes (all six files were already stylua-clean); `stylua --check` exits 0; `git ls-files --eol` shows `w/crlf` for all six; `git diff --numstat` is empty (no working-tree changes to report, confirming no CRCRLF corruption).
- `./scripts/install.bat` exits 0 and deployed to all 4 present client folders (`_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`); `scripts/install.bat`/`scripts/install.ps1` are unmodified (`git status --porcelain` on both is empty).

## Task Commits

No task-level commits were made. Both tasks found zero divergence / made no file changes:

1. **Task 1: Reconcile the Lua v8 with the node spec, then run the whole-phase naming gates** -- pure verification; `BuffEngine.lua` and `scripts/migrate-dryrun.js` already agreed point-for-point, so per the plan's own instruction ("If both already agree, change neither file") no edit and no commit was made.
2. **Task 2: Deploy with install.bat and hand the in-game verification list to the user** -- deploy only; `scripts/install.bat`/`scripts/install.ps1` were run, not modified, so no commit was made.

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified

None. This plan's two tasks are a verification sweep (Task 1) and a deployment run (Task 2); the plan's own objective anticipated a no-op outcome ("BuffEngine.lua or scripts/migrate-dryrun.js change only if reconciliation finds a divergence") and that is what happened.

## Decisions Made

- No divergence found between the Lua v8 migration and its node spec -- both files left unchanged, since plans 53-01 through 53-04 built the Lua migration directly against the spec's interfaces block and never drifted from it.
- The six leftover old-provider-name mentions are all full-line comments in files other than `Providers.lua` (see Known Provider-Name Comments below); left as-is per the plan's own gate-6 acceptance form, which explicitly filters them out and asks only that this SUMMARY list them.

## Known Provider-Name Comments

Full-line comments (not code) naming a pre-rename provider identifier, permitted by the plan's gate 6 (`grep -rnE '\b(Trinket|Pot|Lust|Racial|Item)Provider(Mixin)?\b' --include=*.lua . | grep -vE ':[0-9]+:\s*--'` prints nothing -- confirmed):

- `BuffEngine.lua:513` -- `-- See Providers.lua for TrinketProvider, PotProvider, UserSpellProvider definitions.`
- `BuffEngine.lua:1002` -- `-- Phase 19 (D-14): Provider dispatch runs FIRST -- unconditional. LustProvider reads addedAuras`
- `CDMTab.lua:191` -- `-- through ns:GetDisplayInfoForKey -> RacialProvider:GetDisplayInfo -> ns:GetSpellIcon,`
- `Display.lua:259` -- `-- lives here, not in LustProviderMixin, because the provider is correct to name its`
- `Display.lua:2089` -- `-- RacialProviderMixin is still mutating (proc.stacks).`
- `Display.lua:2426` -- `-- integer (RacialProviderMixin decrements it on a qualifying cast), never a game`

None of these are reachable code paths; all are historical/explanatory prose referencing the pre-53-03 provider names.

## Deviations from Plan

None -- plan executed exactly as written. Both tasks' acceptance criteria (selftest exit code, every naming grep/awk, kind-string identity loop, stylua --check, `git ls-files --eol`, `git diff --numstat`, install.bat exit code and deploy-script git status) passed on the first run with no auto-fixes needed.

## Issues Encountered

None.

## Human Verification Needed

**This is the phase's own deliverable, not a gap.** The run above is unattended; the items below are HUMAN truths for the user to verify in-game, covering ROADMAP Phase 53 success criteria 1-5 (NAME-01, NAME-02). They are NOT blocking checkpoints.

### In-Game Verification Checklist

**a. Back up SavedVariables before logging in.** Copy `WTF/Account/<account>/SavedVariables/TerribleBuffTracker.lua` (and the Forever client's copy under `_classic_beta_`) to a safe location before logging in on this build -- the migration rewrites the file on the next logout.

**b. Fully exit the game and log in (never `/reload`)** -- SavedVariables are only written on logout and only read on login, so `/reload` cannot exercise the migration path. Confirm every tracker -- user buffs, user cooldowns, Lust, trinket, pot, racial buffs, racial cooldowns (Forever), bag items -- is in the same container, same order, with the same settings (bar width, scale, hide-when-inactive, cover-all-ranks, item icon) it had before the upgrade.

**c. Log out, open the SavedVariables file.** Every tracker key should read `userBuff:<id>`, `userCd:<id>`, `metaSkill:<id-or-lust>`, `metaSkillCd:<id>`, or `metaItem:<id-or-trinket-or-pot>` -- no old `cd:`/`item:`/`racial:` prefix or bare numeric key should remain. Every entry should carry a canonical `trackerType`. The file should show `schemaVersion = 8`. No tracker should be duplicated. Log in and out again: the file should be byte-identical to the first post-migration write (the migration must not re-run).

**d. Cast and confirm:** a user buff starts its timer; a user cooldown tile sweeps; Lust (or the Sated debuff path), trinket, pot, a racial buff, and a racial cooldown (Forever) all still fire; a bag item's count/cooldown still updates; a covered-rank cast (Forever) still starts its tracker.

**e. Icons, labels and tooltips resolve for every kind** -- in bar and icon containers (both active and placeholder/preview), on tracked TBT-tab tiles, on Suggested tiles (Lust, trinket, pot, racials, bag items, racial cooldowns), and on the drag ghost while dragging a Suggested tile.

**f. Add a new user buff and a new user cooldown** from the TBT tab, log out and back in, and confirm both persist under `userBuff:<id>` / `userCd:<id>` with all their settings intact.

**g. No Lua errors throughout.** Enable `/console scriptErrors 1` or use BugSack while performing steps b-f.

**h. Chat prints on add/remove show a readable label and spell ID** (e.g. "Now tracking Recklessness (buff, ID: 1719, 12s)"), never the long `<kind>:<id>` key.

**Also available:** the user can dry-run this migration against their real file before logging in, with no game client needed:
```
node scripts/migrate-dryrun.js --race <raceID> "<path-to-TerribleBuffTracker.lua>"
```
This predicts the exact re-key the real logout/login will perform, using the same `migrateV7`/`migrateV8` code this plan just reconciled against the shipped Lua.

## User Setup Required

None -- no external service configuration required. The in-game checklist above is the user's own verification pass, not a setup step.

## Next Phase Readiness

The naming scheme is complete across the codebase (Core.lua, BuffEngine.lua, Providers.lua, Display.lua, MergeMode.lua, CDMTab.lua), the migration matches its executable spec with zero reconciliation changes needed, all whole-phase naming gates are clean, the hot-path audit found no regression, and the build is deployed to all 4 present WoW client folders. Phase 53 (NAME-01, NAME-02) is code-complete; the only remaining work is the HUMAN in-game verification checklist above, which the user runs against this deployed build with a real logout/login. No blockers.

---
*Phase: 53-naming-scheme-saved-data-migration*
*Completed: 2026-09-28*
