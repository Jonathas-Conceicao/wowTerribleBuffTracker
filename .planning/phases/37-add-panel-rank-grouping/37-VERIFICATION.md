---
phase: 37-add-panel-rank-grouping
verified: 2026-09-21T17:19:58Z
status: passed
closed_at_milestone: v0.4.0 (2026-09-23)
closure_evidence:
  - ".planning/testing/43-FOREVER-E2E-PASS.md"
  - ".planning/testing/44-RETAIL-PASS.md"
closure_note: >-
  Closed in bulk at milestone close, not item by item. The human_verification list below was
  written when this phase's code landed and records what still needed a live client at that
  moment. Those observations were carried out in Phase 43 (Forever beta, build 1.60.1.69913,
  continuous play-testing 2026-09-21 to 22) and Phase 44 (retail, Mythic+ and a raid encounter,
  2026-09-23). The user signed both off as a whole -- "everything on Forever is tested and
  acceptable" and "no lua errors so far" -- rather than ticking each row, so read the list below
  as covered by those two passes collectively, not as individually attested. It is kept intact
  because it is the best record of what this phase could not prove statically.
score: 4/4 roadmap success criteria verified at code level; 5/5 requirements (ADD-01, ADD-02, ADD-03, RANK-01, RANK-02) satisfied at code level; ADD-03 retail half deferred to Phase 44; 10-step in-game checkpoint outstanding
overrides_applied: 0
human_verification:
  - test: "Open the `+` dialog on the Forever beta and confirm ADD-01/ADD-02/ADD-03 widgets render and behave (Buff/Cooldown mutual exclusion, Container button lists Not Displayed + four base + RankTest after live creation, Cover all ranks checked by default)"
    expected: "All three controls present and behave as coded; RankTest container appears in the menu with no /reload"
    why_human: "Rendered widget layout, menu contents at runtime, and live container creation require a running client"
  - test: "Add Fireball rank 3 (145) with cover-all-ranks checked into Tracked Bars, then cast rank 1 (133) and rank 2 (143)"
    expected: "One single bar starts and restarts under spell ID 145 (the CDM's ID) — never a second bar"
    why_human: "This is the headline RANK-01/RANK-02 behavior and can only be observed by actually casting in-game; static reading confirms the mechanism exists but not that GetBaseSpell/GetOverrideSpell/C_SpellBook return real data on this client build"
  - test: "Add a different spell with cover-all-ranks unchecked, then cast a sibling rank of it"
    expected: "Nothing triggers (the negative case)"
    why_human: "Requires a live cast and observation of the display"
  - test: "Add a spell as type Cooldown into a visible container"
    expected: "Chat confirms '(cooldown, ...)', the entry appears in the CDM tab section, and nothing renders in the world (Phase 38 owns rendering)"
    why_human: "Visual absence of rendering and CDM tab listing require a live client"
  - test: "/reload after all of the above"
    expected: "Dialog rebuilds with Buff/Not Displayed/cover-all-ranks-checked defaults; existing trackers keep their sections; rank dispatch still works (index rehydrates at PLAYER_ENTERING_WORLD)"
    why_human: "Reload behavior and post-reload cast dispatch can only be observed live"
  - test: "Watch for Lua errors on dialog open, add, cast, and /reload"
    expected: "No uncaught Lua error at any point"
    why_human: "Runtime error absence cannot be proven by static analysis alone"
---

# Phase 37: Redesigned Add Panel & Rank Grouping Verification Report

**Phase Goal:** One add flow that says what kind of tracker this is, where it goes, and — on Forever only — whether it covers every rank of the spell; and ranked spell IDs that stop silently disagreeing with the CDM.
**Verified:** 2026-09-21T17:19:58Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The add dialog offers a buff-or-cooldown choice and a container choice, and the new entry lands in exactly the container chosen, as exactly the type chosen | VERIFIED (code) | `CDMTab.lua:864-933` `buffCheck`/`cooldownCheck` mutually-exclusive pair (self-recheck idiom copied from `CreateContainerDialog`) and `containerBtn` opening `MenuUtil.CreateContextMenu` built from `ipairs(ns.CONTAINERS)` (`927-931`), never `SECTION_DEFS`. Add handler (`981-985`) passes `trackerType`, `section = dialog.selectedSection`, `coverAllRanks` straight into `ns:AddTrackedBuff`'s `opts`, which writes them verbatim (`BuffEngine.lua:228-243`). |
| 2 | On Forever the dialog shows a "cover all ranks" checkbox, checked by default; on retail no such control exists in the dialog at all — not hidden dynamically, not shown disabled. This is the milestone's one sanctioned runtime flavour check, and no second one appears anywhere in the diff | VERIFIED (code) | `grep -n 'GetBuildInfo' *.lua` → exactly one hit, `Core.lua:310`. `ns.CLIENT_HAS_SPELL_RANKS` (`Core.lua:318`) has exactly one reader, `CDMTab.lua:941`. `CreateFrame` for `rankCheck` (`CDMTab.lua:943`) sits inside the `if ns.CLIENT_HAS_SPELL_RANKS then` block (`941-953`), including its own `y` gap advance (`942`); no `:Hide()`, `:Disable()` or `SetEnabled(false)` call exists anywhere in the file (`grep -n 'rankCheck' CDMTab.lua` shows only creation, the two nil-guarded reads at `984`/`1025-1027`, and comments). `grep -rn 'IsVanilla\|IsRetail\|IsForever\|WOW_PROJECT\|tocversion' *.lua` — no hits. |
| 3 | A tracker added with "cover all ranks" checked starts on any rank of that spell being cast — Fireball 133, 143 and 145 all drive the same tracker | VERIFIED (code, mechanism); UNCONFIRMED (live behavior) | `Providers.lua:82-133` `UserSpellProviderMixin:OnTrigger` falls back to `ns.rankIndex[spellID]` on a direct-lookup miss (`84-96`), re-resolves under `ownerKey`, and returns a proc whose `key`/`spellID` are both `ownerKey` (`123-124`) — never the cast ID. `Core.lua:356-471` `ns:ResolveRankFamily` seeds from `GetBaseSpell`/`GetOverrideSpell`, then performs a name-matched `C_SpellBook` scan (capability-guarded, `400-408`), then a bounded (non-recursive) expansion pass (`454-467`) so a rank-1 add still reaches the CDM's own ID. This is the correct mechanism per the CONTEXT.md-recorded planning refinement, but whether `GetBaseSpell`/`GetOverrideSpell`/`C_SpellBook` actually return usable data on the Forever build is unconfirmed by probe per the plan's own risk note — this is exactly the headline in-game check listed below. |
| 4 | A tracker whose spell ID differs from the ID the CDM holds for the same spell resolves to the same entry the CDM uses, so the two never show contradictory state side by side | VERIFIED (code, mechanism); UNCONFIRMED (live behavior) | Same evidence as #3 — `RANK-02` is closed by the same `ownerKey`-derived proc plus the base/override expansion pass that specifically targets IDs the scan newly discovered (`Core.lua:454-467`, "This is what lets a user who added the rank they cast still reach the ID the CDM holds"). |

**Score:** 4/4 roadmap success criteria verified at the code level; criteria 3 and 4's live cast behavior is the phase's headline outstanding human check.

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| ADD-01 | Add dialog lets the user choose buff vs. cooldown tracker | SATISFIED | `CDMTab.lua:864-901` (checkbox pair); `BuffEngine.lua:228,238` (`trackerType` written); `Providers.lua:106-108` + `BuffEngine.lua:324` (cooldown skip in both cast path and preview, per scope fence). |
| ADD-02 | Add dialog lets the user choose the container | SATISFIED | `CDMTab.lua:902-933` (`containerBtn`, `ipairs(ns.CONTAINERS)`); `BuffEngine.lua:229-232` (`opts.section` with `"hidden"` fallback, never a visible default). |
| ADD-03 | Forever shows "cover all ranks" checked by default; retail has no such control, absent not hidden/disabled | HALF-SATISFIED — Forever side verified in code, retail side unverifiable until Phase 44 (no retail client exercised this milestone by design) | `Core.lua:310-318` (single flavour check); `CDMTab.lua:935-953` (`CreateFrame` inside `if`, gap inside `if`, no Hide/Disable anywhere). Per `37-03-PLAN.md`'s own Risks section, record as half-verified rather than passed. |
| RANK-01 | A tracker with cover-all-ranks checked starts on any rank cast | SATISFIED (mechanism); live confirmation outstanding | `Providers.lua:84-96`, `Core.lua:356-471`, `Core.lua:495-542` (`ns:RebuildRankIndex`, event-wired at `Core.lua:629,650`). |
| RANK-02 | A tracker whose spell ID differs from the CDM's still agrees with the CDM | SATISFIED (mechanism); live confirmation outstanding | `Core.lua:454-467` (bounded base/override expansion after the name scan); `Providers.lua:118-131` (owner-keyed `key`/`spellID` in the returned proc). |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | `ns.CLIENT_HAS_SPELL_RANKS`, `ns:ResolveRankFamily`, `ns.rankIndex`, `ns.rankFamilies`, `ns:RebuildRankIndex` | VERIFIED | All present, substantive, at `Core.lua:296-542`. Wired to `SPELLS_CHANGED` (`554`, `649-650`) and `PLAYER_ENTERING_WORLD` outside the `displayInitialized` guard (`625-629`), never `ADDON_LOADED`. |
| `BuffEngine.lua` | `ns:AddTrackedBuff` opts (trackerType, section, coverAllRanks), cooldown-aware preview | VERIFIED | `200-264` (opts), `313-324` (`StartAllPreviewTimers` cooldown skip on the same `if` as the `"hidden"` test). |
| `Providers.lua` | Rank-family fallback and cooldown skip in `UserSpellProviderMixin:OnTrigger` | VERIFIED | `70-133`. No `pcall`, no `C_SpellBook` call inside `OnTrigger` (`grep -n 'pcall\|C_SpellBook' Providers.lua` — no hit in this function). |
| `CDMTab.lua` | Redesigned `CreateAddDialog` with type, container and cover-all-ranks controls | VERIFIED | `802-1031`. `dialog.ResetFields` (`1018-1028`) is the single reset path, called once from `addSquare`'s `OnMouseUp` (`1414-1421`). |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Core.lua eventFrame SPELLS_CHANGED` / `PLAYER_ENTERING_WORLD` | `ns:RebuildRankIndex` | event handler branch | WIRED | `Core.lua:554` (register), `629` (`PLAYER_ENTERING_WORLD` branch, unconditional), `649-650` (`SPELLS_CHANGED` branch). Exactly two call sites in `Core.lua`, matching the plan's stated count. |
| `ns:ResolveRankFamily` | `C_SpellBook.GetSpellBookItemInfo` | name-matched scan, capability-guarded | WIRED | `Core.lua:400-451`; every `C_SpellBook` call site sits inside the seven-symbol capability guard (`400-408`); `grep -n 'C_SpellBook' Core.lua` shows no hit above the guard. |
| `Providers.lua UserSpellProviderMixin:OnTrigger` | `ns.rankIndex` | single table lookup after the direct `trackedBuffs` miss | WIRED | `Providers.lua:90-95`; only reached when `entry` is nil after the direct lookup — an ordinary tracked cast costs no extra work. |
| `BuffEngine.lua ns:AddTrackedBuff` / `ns:RemoveTrackedBuff` | `ns:RebuildRankIndex` | nil-guarded call | WIRED | `BuffEngine.lua:260-262` (add, success path), `284-286` (remove, success path). Exactly two call sites, both `if ns.RebuildRankIndex then` guarded. |
| `CDMTab.lua CreateAddDialog container picker` | `ns.CONTAINERS` | `MenuUtil.CreateContextMenu` built by iterating the registry at open time | WIRED | `CDMTab.lua:920-933`; the `ipairs(ns.CONTAINERS)` loop is inside the `OnClick` handler, rebuilt every open — a container created after the dialog was first constructed appears with no refresh plumbing (consistent with Phase 36's registry-driven design). |
| `CDMTab.lua add button` | `ns:AddTrackedBuff` | fourth `opts` argument | WIRED | `CDMTab.lua:981-985`. Single call site, four arguments, opts table has exactly `trackerType`/`section`/`coverAllRanks`. |

### Data-Flow Trace (Level 4)

| Concern | Trace | Status |
|---|---|---|
| `ns.rankFamilies` array identity across rebuild | `Core.lua:522-527`: `ns.rankIndex` is `wipe()`'d in place; `ns.rankFamilies` is reassigned to a fresh `{}` (never `wipe()`'d internally). `Providers.lua:117`: `aliveBuffs = (fams and fams[ownerKey]) or { ownerKey }` takes a live reference, read only via `ipairs` by the cancellation scan (confirmed no mutation site for `aliveBuffs` anywhere in `BuffEngine.lua` or `Providers.lua`). | VERIFIED — matches the plan's reallocate-vs-wipe contract exactly, so a live proc's `aliveBuffs` reference cannot be silently emptied by a later rebuild. |
| Rank index never shadows a direct tracker slot | `Core.lua:536`: insert guarded by `ns.db.trackedBuffs[id] == nil and ns.rankIndex[id] == nil`. `Providers.lua:82-96`: `ns.rankIndex` is only consulted when the direct lookup already missed. | VERIFIED |
| Retail cost | `Core.lua:503-515`: `rebuildOwners` is built by scanning `ns.db.trackedBuffs` for `coverAllRanks`; since `ADD-03`'s checkbox never exists on retail, `coverAllRanks` is never written there, so the owner list is always empty and the function returns before calling `ns:ResolveRankFamily` (hence before any `C_SpellBook` symbol is touched). | VERIFIED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| `GetBuildInfo` occurs exactly once, addon-wide | `grep -n 'GetBuildInfo' *.lua` | `Core.lua:310` only | PASS |
| No second flavour check by any route | `grep -rn 'IsVanilla\|IsRetail\|IsForever\|WOW_PROJECT\|tocversion' *.lua` | no hits | PASS |
| `CLIENT_HAS_SPELL_RANKS` exactly one definition, one reader | `grep -n 'CLIENT_HAS_SPELL_RANKS' *.lua` | `Core.lua:318` (definition), `CDMTab.lua:941` (reader) | PASS |
| No `pcall`/`C_SpellBook` on the cast-time hot path | `grep -n 'pcall\|C_SpellBook' Providers.lua` | no hit inside `OnTrigger` | PASS |
| No `schemaVersion` bump | `grep -n 'CURRENT_SCHEMA_VERSION' BuffEngine.lua` | `= 4`, unchanged from pre-phase | PASS |
| `ns.db.stealMode` still has zero behavioural readers | `grep -rn 'stealMode' *.lua` | only the Phase 35.1 checkbox write/re-sync and the `Core.lua` default seed | PASS |
| No `parentArray` introduced | `grep -rn 'parentArray' *.lua` | no hits | PASS |
| `TBTSettingsTab`/`AnchorTabBelowCDMTabs` untouched | `git diff 5dfe764..1532b65 -- CDMTab.lua \| grep 'TBTSettingsTab\|AnchorTabBelowCDMTabs'` | no hits | PASS |
| `CHANGELOG.md` untouched by all six commits | `git diff --stat 5dfe764..1532b65 -- CHANGELOG.md` | empty | PASS |
| Only the four expected source files touched | `git diff --stat 5dfe764..1532b65` | `BuffEngine.lua`, `CDMTab.lua`, `Core.lua`, `Providers.lua` (plus planning docs) | PASS |
| `Display.lua`/`EditModeFrames.lua` untouched (hot-path regression check) | `git diff --stat 5dfe764..1532b65 -- Display.lua EditModeFrames.lua` | empty | PASS — phase 37 touched neither file, so the zero-table-constructor state from Phases 35/36 is unchanged |
| `stylua --check .` | `stylua --check .` | exit 0 | PASS |
| Debt markers | `grep -n 'TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER' Core.lua BuffEngine.lua Providers.lua CDMTab.lua` | no hits | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist in this repository and none are referenced by the phase's plans or summaries. SKIPPED — no runnable entry points; this is a WoW addon with no headless test harness, consistent with the verification-reality note.

### Anti-Patterns Found

None in the four modified files.

### Human Verification Required

See YAML frontmatter `human_verification` block. These map directly to Plan 03's 10-step Forever-beta checklist (not re-derived), which is the phase's blocking `checkpoint:human-verify` — confirmed **not yet run** per `37-03-SUMMARY.md`'s own "Outstanding Checkpoint" section. The headline item is RANK-01/RANK-02's live Fireball 133/143/145 test: static reading confirms the resolution mechanism (base/override seed → name-matched spellbook scan → bounded expansion) is implemented exactly as the CONTEXT.md-recorded planning refinement specifies, but the plan's own Risks section flags that whether `GetBaseSpell`/`GetOverrideSpell` contribute anything real on the Forever build was never probed — the spellbook scan is the load-bearing fallback for exactly this reason, and only a live cast proves it produces `133`/`143`/`145` as one family.

`ADD-03`'s retail half ("the checkbox is absent on retail") is separately not verifiable until Phase 44 per the milestone's own sequencing (Phases 31-43 are Forever-only by design) — recorded as half-satisfied above, not as a gap, per the plan's explicit instruction not to claim it as passed.

### Gaps Summary

No code-level gaps found. Every observable truth, artifact, key link, and data-flow concern traces to real, substantive, wired code — not a stub. `ns.CLIENT_HAS_SPELL_RANKS` is genuinely the addon's only flavour check (one definition, one reader, gating only whether `rankCheck` is constructed). The rank-family resolver and index are event-wired correctly and the cast-path cost is exactly the nil-guarded single lookup the plan specifies. Cooldown trackers are correctly created but excluded from both the cast path and preview, matching the Phase 38 scope fence.

The phase is not closed because Plan 03 is `autonomous: false` and ends on a blocking human checkpoint that has not been run — six items require the Forever beta client: the three control presence/behavior checks, the headline RANK-01/RANK-02 live-cast test, the cooldown-type no-render confirmation, and Lua-error absence across the whole flow. None of these are code gaps; all are genuinely unobservable without a running client, which is why status is `human_needed` rather than `gaps_found`.

---

*Verified: 2026-09-21T17:19:58Z*
*Verifier: Claude (gsd-verifier)*
