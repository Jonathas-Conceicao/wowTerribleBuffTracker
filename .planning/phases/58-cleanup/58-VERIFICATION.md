---
phase: 58-cleanup
verified: 2026-09-29T00:00:00Z
status: human_needed
score: 11/11 must-haves verified (automated); in-game load and smoke items pending
overrides_applied: 0
human_verification:
  - test: "58-HUMAN-UAT.md items 0-10 on the Forever beta and Midnight retail (first load, fresh-DB Merge Mode, reminders, In Combat on a reminders container, class buffs, buff trackers, cooldowns, load rule, dialog/panel, retail override cast rule, performance)"
    expected: "No Lua error; behaviour unchanged from the 57.5 build except that a fresh database starts with Merge Mode on"
    why_human: "Runtime behaviour inside the WoW client (SavedVariables, CDM, combat, rendering) cannot be exercised from the repo"
---

# Phase 58: Cleanup Verification Report

**Phase Goal:** The code this milestone introduced is unified, lean on its hot paths and release-ready before the review passes run against it
**Verified:** 2026-09-29
**Status:** human_needed
**Re-verification:** No, initial verification
**Range checked:** `git diff 998b0e0..HEAD` (HEAD ab1b7ea); milestone base for "pre-milestone" checks is 9934b20

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ROADMAP SC1: the milestone's duplication is unified into shared functions; pre-milestone code is not refactored | VERIFIED | Diff shows `BaseAndOverride` (Core.lua:880), `ns:SameIDList`/`ns:CopyIDList` (Core.lua ~1623-1645, Providers.lua locals deleted), `ns:ResolveCastOwner` (Providers.lua:167, used by StartCooldownFromCast, user reminder and metaReminder lookups), `SetupRadioMenu` (CDMTab.lua:1461, both call sites), `ROW_BTN_W`/`ROW_GAP` (Config.lua:35), `ns.loadRankFamilies` removed in favour of `ns:CastRuleFamily`. Every edited function is absent at 9934b20 (`git grep` 0 hits for SpellKnownState, CastRuleFamily, StartCooldownFromCast, ApplyMetaReminderDef, FindTrackerConflict, LOAD_CHOICES, CONTAINER_CATEGORY_CHOICES); the Config row at 9934b20 had only two buttons at a different offset. `RelatedSpellID` (pre-milestone) is only wrapped, not changed. The one pre-milestone line changed is the `mergeMode` seed, which is an explicit user decision (truth 6) |
| 2 | ROADMAP SC2: tick, UNIT_AURA and UNIT_SPELLCAST_SUCCEEDED paths gain no per-call allocation or redundant per-frame work; dead code gone | VERIFIED | Every hot-path hunk in the diff is a rename or an allocation-free call: `ns:ResolveCastOwner` body is table reads only; Display/BuffEngine hunks are renames. New allocations (`ns:CopyIDList`, `{ ns.reminderAuraID[key] }`, `SetupRadioMenu`'s generator) are rebuild/build time only, same count as before. Dead metaReminder branch in `ns:FindTrackerConflict` removed; `ns.loadRankFamilies` has no code reference (grep: only the "formerly" comment at Core.lua:1142). Cache wipes: `wipe(ns.endRuleFamilies)` at the same three moments (Core.lua:1416, 2065, 2189) where both caches were wiped before |
| 3 | ROADMAP SC3: `stylua` clean; every Lua file `w/crlf`, no CRCRLF | VERIFIED | `stylua --check .` exit 0. `git ls-files --eol` on all 12 Lua/XML/TOC files: `i/lf w/crlf attr/text eol=crlf`. Byte count per file: LF == CRLF, CRCR == 0 for all 12 |
| 4 | ROADMAP SC4: install.bat and release.bat reviewed against the file set; deployed addon loads with no Lua errors | VERIFIED (review) / HUMAN (load) | release.bat, install.bat, install.ps1, .pkgmeta, .github untouched in range. install.bat forwards to install.ps1; TOC load list (Core, BuffEngine, Providers, MergeMode, EditModeFrames, Config, Display, CDMTab.xml) matches the repo's Lua/XML set. Deployed copies in `_retail_` and `_classic_beta_` are byte-identical to the working tree for all 9 shipped Lua/XML files (18/18 `cmp` same). The no-Lua-error load is UAT item 0 |
| 5 | CONTEXT: pure rename of the reminder runtime; no old name left except "formerly" history notes; container Visibility keeps its name | VERIFIED | grep for the six old names in `*.lua`: only Core.lua:1158-1159 (both "formerly" lines). Independent reverse-mapping proof (scratch `verify58-renameproof.js`): mapping the six new names back on 6550e34 and dropping the added "formerly" lines reproduces be7ca11 byte-for-byte in all 8 Lua files. Remaining `visibility` hits are `cs.visibility`, Edit Mode dropdown, `entry.visibility` migrations, MergeMode's CDM visibility, and history comments |
| 6 | CONTEXT/58-01: Merge Mode on only for a fresh database; existing DBs keep their value, keyless old DBs seeded off | VERIFIED | Core.lua ~1973: `local freshDB = false`, set true only inside `if not TerribleBuffTrackerDB then`; seed is `if ns.db.mergeMode == nil then ns.db.mergeMode = freshDB end`. Same handler scope, no cross-function upvalue issue |
| 7 | CONTEXT docs: CLAUDE.md stylua rule and Architecture list; REQUIREMENTS General/Advanced with superseded notes | VERIFIED | CLAUDE.md: rule now "Run `stylua .` from the repo root", records the bare-invocation error (reproduced: `stylua --check` with no path prints "error: no files provided", exit 2), history sentence kept. Architecture adds Providers, MergeMode, Config, TOC, install.ps1, aura-read-gate.js, migrate-dryrun.js, tools/TBTProbe; install.bat no longer claims two TOCs. REQUIREMENTS: ADD-07 and DTRK-01 say General/Advanced with `**Superseded 2026-09-29**` notes; REM-02 has a dated revision note; IDs and checkboxes unchanged |
| 8 | CONTEXT: "In Combat" option kept; stale "never shows" notes corrected | VERIFIED | EditModeFrames.lua untouched in range (option still at 498/522). Corrections present: 57.2-04-SUMMARY:184-189, 57.2-REVIEW:195, 57.2-VERIFICATION:146, STATE.md:51 ("KEPT"). No Lua comment claims a reminders container never shows in combat |
| 9 | CONTEXT: release.bat left alone, no check scripts wired in; STATE records the decline | VERIFIED | `git diff --name-only 998b0e0..HEAD -- scripts/` empty; release.bat contains no `aura-read-gate`/`migrate-dryrun`. STATE.md:87 and :92 say "declined 2026-09-29 by user decision" |
| 10 | CHANGELOG.md and README.md untouched; no phase commit touched .gitignore | VERIFIED | `git diff --name-only 998b0e0..HEAD -- CHANGELOG.md README.md .gitignore` empty. The `M .gitignore` in the working tree is the user's own uncommitted change |
| 11 | Gates keep passing: aura-read-gate, its selftest, migrate-dryrun selftest | VERIFIED | `node scripts/aura-read-gate.js`: "AURA-READ GATE PASS (10 reads in 3 allowlisted readers)", exit 0. `--selftest`: "AURA-READ SELFTEST PASS (30 cases)", exit 0. `node scripts/migrate-dryrun.js --selftest`: "SELFTEST PASS (12 cases)", exit 0 |

**Score:** 11/11 truths verified by code evidence; the in-game half of SC4 and the behavioural smoke are human items.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | reminder* names, BaseAndOverride, SameIDList/CopyIDList, fresh-DB seed, shared family cache | VERIFIED | All present and called; `ns.loadRankFamilies` gone |
| `BuffEngine.lua` | ReminderGate/ReminderShowsIn, dead conflict branch removed | VERIFIED | Renamed; called from Display.lua (5 sites) |
| `Providers.lua` | ns:ResolveCastOwner, shared ID-list helpers used | VERIFIED | 3 callers of ResolveCastOwner; ApplyMetaReminderDef uses ns:SameIDList/ns:CopyIDList |
| `CDMTab.lua` | SetupRadioMenu shared by Load and category dropdowns | VERIFIED | Defined above TRACKER_FIELDS; 2 callers; `CreateRadio(` only inside it |
| `Config.lua` | ROW_BTN_W / ROW_GAP | VERIFIED | Offsets 0/180/360, width 170 unchanged numerically |
| `CLAUDE.md`, `.planning/REQUIREMENTS.md` | docs edits | VERIFIED | See truth 7 |
| `58-HUMAN-UAT.md` | smoke checklist, both clients | VERIFIED | 11 items, all pending |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ns:SpellKnownState` | `ns.endRuleFamilies` | `ns:CastRuleFamily(spellID) or false` | WIRED | Only inside `CLIENT_HAS_SPELL_RANKS and not noRanks`, so retail never reads it; same ResolveRankFamily call (no pet flag) as the old cache |
| `OnTrigger` | reminder / metaReminder / cooldown owners | `ns:ResolveCastOwner` | WIRED | Order preserved: cooldown side, reminder resolution, cross-spell side, then metaReminder |
| `ns:RebuildRankIndex` | `ns:RebuildReminderWatch` | both exits | WIRED | Core.lua ~1787, ~1879 |
| Display render paths | `ns:ReminderGate` / `ns:ReminderShowsIn` | direct calls | WIRED | Display.lua:94, 2040, 2052, 2308, 2328, 2372 |

### Data-Flow Trace (Level 4)

Not applicable beyond the key links above: the phase is a refactor with no new rendered data source. The one semantic change (fresh-DB Merge Mode) flows through the existing PLAYER_ENTERING_WORLD mirror/visibility queue, confirmed by reading and left to UAT item 1.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Style clean | `stylua --check .` | exit 0 | PASS |
| Bare stylua claim in CLAUDE.md | `stylua --check` (no path, stdin closed) | "error: no files provided", exit 2 | PASS |
| Aura reads confined | `node scripts/aura-read-gate.js` | PASS (10 reads in 3 readers) | PASS |
| Gate selftest | `node scripts/aura-read-gate.js --selftest` | PASS (30 cases) | PASS |
| Migration selftest | `node scripts/migrate-dryrun.js --selftest` | PASS (12 cases) | PASS |
| Pure rename | scratch `verify58-renameproof.js` (6550e34 reverse-mapped vs be7ca11) | 8/8 files identical | PASS |
| Deploy current | `cmp` repo vs `_retail_` and `_classic_beta_` AddOns folder | 18/18 identical | PASS |

### Probe Execution

No probe scripts (`scripts/*/tests/probe-*.sh`) exist or are declared by this phase. SKIPPED.

### Requirements Coverage

Process phase, no requirement IDs (ROADMAP: "Requirements: None"). No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Providers.lua | ~1654 | Comment line is 154 columns after the 58-03 edit (stylua does not wrap comments) | Info | Cosmetic only |
| .planning/STATE.md | 151 | v0.3.0 todo table still lists "release.bat pushes main with no branch guard" as pending, but release.bat has the REL-01 guard | Info | Pre-existing; the table is already marked "no longer current" above it; not introduced by this phase |

No TBD/FIXME/XXX markers in any Lua file touched by the phase. No stub patterns introduced.

### Human Verification Required

All of `.planning/phases/58-cleanup/58-HUMAN-UAT.md` (11 items, all `[pending]`), on the Forever beta and Midnight retail with `/console scriptErrors 1`:

1. **Item 0, first load:** /reload gives no Lua error; trackers, containers and the Merge switch are unchanged (the in-game half of ROADMAP SC4).
2. **Item 1, fresh install:** with the client fully closed, move SavedVariables aside; login shows Merge Mode on; restoring the file restores the old value.
3. **Items 2-9:** reminders, "In Combat" reminders container, class buffs (Forever), buff trackers, cooldowns and racial tile, load rule and "Cover all ranks", dialog/radio dropdowns/panel buttons, retail override cast rule. Behaviour must match the 57.5 build.
4. **Item 10, performance:** no hitch in combat with many aura changes or on zone-in.

**Why human:** runtime behaviour in the WoW client cannot be exercised from the repo.

### Gaps Summary

No gaps. Every roadmap success criterion and every CONTEXT decision is backed by code evidence in `998b0e0..HEAD`: the rename is proven mechanical, the unifications are confined to milestone code, the only pre-milestone behaviour change is the requested fresh-DB Merge Mode seed, docs edits are in place, release.bat/CHANGELOG/README are untouched, and all automated gates pass. The phase waits only on the in-game smoke session in 58-HUMAN-UAT.md.

---

_Verified: 2026-09-29_
_Verifier: Claude (gsd-verifier)_
