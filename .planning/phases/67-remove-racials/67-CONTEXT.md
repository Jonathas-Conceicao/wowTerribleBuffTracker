# Phase 67: Remove Racials - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning
**Mode:** Smart discuss, front-loaded for the whole autonomous run (67-71) at the user's standing request

<domain>
## Phase Boundary

Remove the racial feature from TBT entirely, on every client. Forever's recent release supports racials
natively and TBT never built retail racials (`RACE-06`, dropped). Delivers RACE-11, RACE-12 and MIG-03:
no racial tile, tracker, catalogue, provider, kind or stack-count display remains, and saved racial
trackers are removed by a schema migration that leaves every other tracker untouched.

</domain>

<decisions>
## Implementation Decisions

### What counts as a racial tracker (migration)
- Saved racial trackers are identified by **kind**, never by the racial catalogue (which is deleted):
  `metaSkill:<numeric id>` (racial buffs) and `metaSkillCd:<numeric id>` (racial cooldowns), plus the
  legacy pre-v7 `racial` / `racial2` keys.
- `metaSkill:lust` is the lust meta-tracker and **stays** — only numeric `metaSkill:` ids are racials.
- A new schema **v12** migration drops them. Every other tracker keeps its section, layout order and
  settings.
- The old **v7** migration (`ns:MigrateRacialKeys`) currently reads `RACIAL_SPELLS` to re-key legacy
  `racial`/`racial2` entries. Rewrite it to simply drop those legacy keys, so nothing reads the catalogue
  and an old SavedVariables file still migrates cleanly through every step. Same change mirrored in
  `scripts/migrate-dryrun.js` (it reads `RACIAL_SPELLS` live out of Providers.lua today).
- **Silent**: no chat message when trackers are removed (user decision).
- `scripts/migrate-dryrun.js` proves it against a real SavedVariables file, and `--selftest` gains a
  fixture with racial trackers (both kinds plus a legacy key) next to non-racial ones.

### What is removed from code
- The racial catalogue (`RACIAL_SPELLS`), `MetaSkillRacialProviderMixin` and its registration, every
  `ns:Racial*` helper (`RacialCooldownSeed`, `RacialCooldownKeys`, `RacialSuggestions`,
  `RacialKeySpellID`, ...), `StartRacialProc`, the racial Suggested tiles on the Buffs and Cooldowns
  tabs, and the CDMTab racial key-shape handling.
- The `metaSkillCd` kind (`ns.KIND.META_SKILL_CD`) if it is racial-only — confirm in planning; if
  anything else mints it, keep the kind and remove only the racial use. Same for
  `ns.rankIndexMetaCooldown`.
- The cast-driven stack model (Eureka; `maxStacks`, `C_Spell.IsSpellHarmful` spending) and
  `Display.lua`'s live-timer `timer.stacks` display (bar and icon) — racial-only today.
- The racial debug collection tooling in `Core.lua` (Phase 49, RACE-07: new-buff-after-cast logging).
  The ITEM debug line stays.
- Comments that describe removed racial behaviour are removed with it; historical notes in
  `.planning/` are not rewritten.

### Not touched
- **`CHANGELOG.md` — never** (CLAUDE.md rule).
- **`README.md` and `Assets/forever_racial.png` — left to the user** (user decision 2026-10-10).
- `.planning/research/FOREVER-RACIALS.md` stays as history.

### Claude's Discretion
- Plan split and ordering (e.g. migration first, then code removal), provided `--selftest` and the
  dry-run pass at the end and no Lua path references a removed symbol (the file-local upvalue-order
  trap and nil-global calls are the main risks — grep every removed name).
- Whether `ns.LOAD.KNOWN` and similar shared tables lose their racial rows or keep generic ones.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Schema migration chain in `BuffEngine.lua` (`ns.db.schemaVersion`, steps v1..v11,
  `CURRENT_SCHEMA_VERSION`); `scripts/migrate-dryrun.js` mirrors each step and has `--selftest`.
- Key helpers in `Core.lua`: `ns.KIND`, `ns:TrackerKey`, `ns:KeyNumericID`, `ns.KEY_PREFIX`.

### Established Patterns
- Racial references: Providers.lua (~244), BuffEngine.lua (~46), Core.lua (~42), CDMTab.lua (~33),
  Display.lua (2), migrate-dryrun.js (~58).
- `ns.META_KEY.LUST = metaSkill:lust` — must survive.

### Integration Points
- Suggested tiles: `CDMTab.lua` (`ns:RacialCooldownKeys()` on the Cooldowns tab, racial buff tiles on
  the Buffs tab), `ns:GetDisplayInfoForKey` racial branch (Providers.lua ~415-440).
- Cast dispatch: Providers.lua "ONE CAST, FIVE POSSIBLE TRACKERS" (~269-300) includes the built-in racial
  cooldown path.
- Load rules: `Core.lua` kind → `ns.LOAD.KNOWN` map (~661).

</code_context>

<specifics>
## Specific Ideas

- No TOC change is expected (no file is deleted). If one happens, testing needs a full client restart.
- All in-game checks are deferred to Phase 72 (user decision for this autonomous run); verification
  should list them as human items, not block on them.

</specifics>

<deferred>
## Deferred Ideas

- README/store copy update for the racial removal — the user does it with the release.

</deferred>
