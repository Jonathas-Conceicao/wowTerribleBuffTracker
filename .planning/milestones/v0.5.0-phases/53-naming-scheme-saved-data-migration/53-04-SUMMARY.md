---
phase: 53-naming-scheme-saved-data-migration
plan: 04
subsystem: ui
tags: [naming-scheme, cdm-tab, display, merge-mode, wow-addon, lua, key-scheme]

# Dependency graph
requires:
  - phase: 53-naming-scheme-saved-data-migration
    provides: "plan 53-02's Core.lua scheme (ns.KIND/ns.KEY_PREFIX/ns.META_KEY/ns:TrackerKey/key parsers/ns:IsCooldownSlotEntry/ns:IsBagItemEntry/ns:RebuildCastIndex) and BuffEngine.lua schema v8"
  - phase: 53-naming-scheme-saved-data-migration
    provides: "plan 53-03's Providers.lua on the scheme (ns:GetDisplayInfoForKey kind-dispatched, ns:IsRacialSpellID) -- CDMTab.lua's AddSuggestedTracker calls both"
provides:
  - "Display.lua render paths (SlotDraws, RefreshCooldownSlotCounts, item-count branch, bar slot collection, icon container cooldown-slot branch) driven by ns:IsCooldownSlotEntry / ns:IsBagItemEntry instead of trackerType string tests"
  - "MergeMode.lua's mirrored CDM entries carrying ns.KIND.USER_CD / ns.KIND.USER_BUFF"
  - "CDMTab.lua minting every Suggested/Add-dialog tracker with a canonical key AND a canonical trackerType, with every icon/tooltip fallback going through a key parser instead of assuming a key is a spellID"
affects: [53-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Slot-shape predicates (ns:IsCooldownSlotEntry/ns:IsBagItemEntry) replace every trackerType string comparison at every UI read site, matching the pattern Providers.lua (53-03) already established"
    - "Key-as-key, not key-as-spellID: every fallback that used to assume a tracker key WAS a numeric spellID (tooltip fallback, drag-ghost icon, tracked-tile icon) now calls ns:SpellKeySpellID(key) first and only proceeds on a non-nil result"
    - "A freshly-minted key needs ns:RebuildCastIndex() before the next cast can find it -- AddSuggestedTracker calls it right after writing (and seeding) the entry, the same moment ns:RebuildRankIndex already rebuilds it elsewhere"

key-files:
  created: []
  modified:
    - "Display.lua - SlotDraws, RefreshCooldownSlotCounts, ApplyItemCount branch, bar slot collection, and the icon container's cooldown-slot branch all call ns:IsCooldownSlotEntry/ns:IsBagItemEntry"
    - "MergeMode.lua - mirrored CDM entries mint ns.KIND.USER_CD / ns.KIND.USER_BUFF instead of the old \"cooldown\"/\"buff\" literals"
    - "CDMTab.lua - META_DESCRIPTIONS keyed by ns.META_KEY.*; AddSuggestedTracker mints trackerType = ns:KeyKind(key) and calls ns:RebuildCastIndex(); tile OnEnter fallback, drag-ghost icon and tracked-tile icon fallback all resolve through ns:SpellKeySpellID; Suggested-loop key minting uses ns:TrackerKey(ns.KIND.META_ITEM/META_SKILL, id); Add dialog mints ns.KIND.USER_CD/ns.KIND.USER_BUFF; every comment quoting an old key shape updated to the canonical <kind>:<id> shape"

key-decisions:
  - "__tbt_example__ and MergeMode.lua's runtime-only \"cdm:\" mirror-key prefix left unrenamed -- both are 53-CONTEXT's explicit discretion (never saved) and renaming either would touch code outside this plan's three files for no scheme benefit"
  - "The plan's editing rule (Edit tool, or a node fs.readFileSync/writeFileSync fallback preserving CRLF) was used for five of CDMTab.lua's multi-line comment/code edits after the Edit tool's exact-string match failed on tab-vs-space transcription from the Read tool's line-numbered output -- confirmed via `cat -A` that the source uses tabs, then replaced with a node script that matched the literal tab/CRLF bytes"

requirements-completed: [NAME-01, NAME-02]

# Metrics
duration: 5min
completed: 2026-09-28
---

# Phase 53 Plan 04: UI Consumers on the Naming Scheme Summary

**Display.lua and MergeMode.lua stop testing old `trackerType` strings in favour of `ns:IsCooldownSlotEntry`/`ns:IsBagItemEntry` and canonical mirror kinds, and CDMTab.lua mints every Suggested/Add-dialog tracker with a canonical key and kind while routing every icon/tooltip fallback through `ns:SpellKeySpellID` instead of assuming a key is a spell ID.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-09-28T08:27:00-03:00 (previous plan's completion commit)
- **Completed:** 2026-09-28T08:31:34-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 3

## Accomplishments
- Display.lua's five render-path read sites (`SlotDraws`, `RefreshCooldownSlotCounts`, the item-count-vs-charge-count branch, the bar slot collector, and the icon container's cooldown-slot branch) no longer compare `entry.trackerType` against `"cooldown"`/`"item"`/`"buff"` literals -- all five call `ns:IsCooldownSlotEntry(entry)` or `ns:IsBagItemEntry(entry)`.
- MergeMode.lua's mirrored CDM entry now mints `ns.KIND.USER_CD`/`ns.KIND.USER_BUFF` (same condition as before), with a comment explaining the mirrored entries are runtime-only and take the user kinds so the shared slot predicates treat them exactly as before.
- CDMTab.lua's `META_DESCRIPTIONS` is keyed by `ns.META_KEY.TRINKET/POT/LUST` (Core.lua loads first per the TOC, so these resolve at file load).
- `AddSuggestedTracker` mints `trackerType = ns:KeyKind(key)` for every Suggested key (Lust and racial buffs -> `metaSkill`, trinket/pot/bag items -> `metaItem`, racial cooldowns -> `metaSkillCd`) -- every entry now carries a kind, closing the gap where meta buff entries previously had none. It also calls the nil-guarded `ns:RebuildCastIndex()` right after the entry is written (and after `ns:SeedItemTracker` for items), so a freshly-created racial cooldown tile is visible to the cast-index lookup on the very next cast instead of only after the next `ns:RebuildRankIndex` call.
- Every place that treated a CDMTab key as a bare spell ID now goes through `ns:SpellKeySpellID`: the tile `OnEnter` tooltip fallback (`type(self.spellID) == "number"` -> `ns:SpellKeySpellID(self.spellID)`), the drag-ghost icon fallback, and the tracked-tile icon fallback in the render loop.
- Key minting in the Suggested loops uses `ns:TrackerKey(ns.KIND.META_ITEM, itemID)` and `ns:TrackerKey(ns.KIND.META_SKILL, def.spellID)` in place of the removed `ns.ITEM_KEY_PREFIX`/`ns.RACIAL_KEY_PREFIX` concatenations.
- The Add dialog mints `trackerType = ns.tbtActiveCategory == "spells" and ns.KIND.USER_CD or ns.KIND.USER_BUFF`.
- Every comment in the three files that quoted an old key shape (`"lust"`, `"trinket"`, `"pot"`, `"cd:<spellID>"`, `"item:<itemID>"`, `"racial:<spellID>"`) was rewritten to the canonical `<kind>:<id>` shape, so no line in any of the three files names a pre-scheme key.
- `grep -rn 'ITEM_KEY_PREFIX\|RACIAL_KEY_PREFIX\|COOLDOWN_KEY_PREFIX' --include="*.lua" .` across the whole repo returns nothing -- the project-hazard leftover check is clean.

## Task Commits

Each task was committed atomically:

1. **Task 1: Display.lua and MergeMode.lua -- slot predicates and canonical mirror kinds** - `e5780e9` (feat)
2. **Task 2: CDMTab.lua -- canonical minting from Suggested and Add, parser-based icon/tooltip fallbacks** - `605a6c5` (feat)

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified
- `Display.lua` - `SlotDraws`, `RefreshCooldownSlotCounts`, `ApplyItemCount` branch, bar slot collection, and icon-container cooldown-slot branch all call `ns:IsCooldownSlotEntry`/`ns:IsBagItemEntry`; the `entry.key = dbKey` comment updated to describe the `<kind>:<id>` shape
- `MergeMode.lua` - mirrored entry's `trackerType` mints `ns.KIND.USER_CD`/`ns.KIND.USER_BUFF`; comment added above the `table.insert` explaining why
- `CDMTab.lua` - `META_DESCRIPTIONS` keyed by `ns.META_KEY.*`; `AddSuggestedTracker` mints `trackerType = ns:KeyKind(key)` and calls `ns:RebuildCastIndex()`; tile `OnEnter`, drag-ghost icon and tracked-tile icon fallbacks resolve through `ns:SpellKeySpellID`; Suggested-loop key minting through `ns:TrackerKey`; Add dialog mints `ns.KIND.USER_CD`/`ns.KIND.USER_BUFF`; all old-key-shape comments updated

## Decisions Made
- `__tbt_example__` and MergeMode.lua's runtime-only `"cdm:"` mirror-key prefix left unrenamed, per 53-CONTEXT's explicit discretion -- neither is ever saved, and renaming either would have no scheme benefit while touching code outside this plan's three files.
- Five of CDMTab.lua's multi-line comment/code edits (the item-key comment block, the racial-suggestion block, the D-4 loop-variable comment, and two icon-fallback lines) were applied via a small node `fs.readFileSync`/`fs.writeFileSync` script instead of the Edit tool, per the plan's own editing-rule fallback -- the Edit tool's exact-string match failed because the Read tool's line-numbered display renders the file's tab indentation ambiguously; `cat -A` confirmed the source uses tabs, and the node script matched the literal tab/CRLF bytes directly. All resulting edits were verified with the same acceptance greps and with `stylua --check`.

## Deviations from Plan

None - plan executed exactly as written. All Task 1 and Task 2 acceptance-criteria greps/awk checks passed, `stylua --check` passed on all three files with no comment forced into a multi-line expression (the ghost-icon and tracked-tile-icon lines stylua reflowed onto multiple lines were pre-existing single-expression statements with no inline comment, so no CRCRLF risk applied), and `node scripts/migrate-dryrun.js --selftest` still prints `SELFTEST PASS (5 cases)` unchanged. The Edit-tool-to-node-script fallback documented above is the mechanism the plan itself specifies for exactly this situation, not a deviation from it.

## Issues Encountered

None beyond the Edit-tool whitespace-matching issue described above, which the plan's own fallback resolved on the first retry -- no repeated attempts were needed.

## Human Verification Needed

None for this plan's own scope. Both tasks are pure Lua source edits verified by `stylua --check`, `git ls-files --eol`, `git diff --numstat`, the full set of structural grep/awk acceptance criteria specified in the plan, and the repo-wide leftover-prefix grep -- no WoW client is available in this environment. In-game icon/tooltip/label verification for every kind (user buff, user cooldown, and every meta kind), plus the real logout/login migration verification (NAME-02), is plan 53-05's responsibility, as this plan's own `<verification>` section states.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Display.lua, MergeMode.lua and CDMTab.lua are now fully on the naming scheme alongside Core.lua (53-02), BuffEngine.lua (53-02) and Providers.lua (53-03) -- no file in the addon still compares `trackerType` against an old kind string or mints a key through a removed prefix constant. Plan 53-05 can now reconcile the full Lua migration against plan 53-01's `scripts/migrate-dryrun.js --selftest` spec and run the real in-game logout/login verification (NAME-02), plus the in-game icon/tooltip/label checks for every kind this plan's own verification section deferred to it. No blockers.

---
*Phase: 53-naming-scheme-saved-data-migration*
*Completed: 2026-09-28*
