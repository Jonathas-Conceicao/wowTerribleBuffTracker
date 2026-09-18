---
phase: 27-provider-at-rest-defensive-fix
verified: 2026-09-18T11:41:20Z
status: passed
score: 7/7 must-haves verified statically; the observable rendering half closed on both flavours by the run-sheets
---

# Phase 27: Provider At-Rest Defensive Fix Verification Report

**Phase Goal:** The Trinket and Pot Suggested tiles never present an unresolved hardcoded fallback item as if it were real, on any flavor.
**Verified:** 2026-09-18T11:41:20Z
**Status:** passed — superseded 2026-09-19, see Closure Note

## Closure Note

**Closed 2026-09-19 at milestone close.** The one gap this report names — the *observable* rendering behaviour on a real game client — was closed in both directions:

- **Forever:** `.planning/testing/FOREVER-TEST-PASS.md` step 8 — all three meta tiles rendered the `134400` question-mark placeholder, answering `VER-08`'s open question (the guard renders a placeholder, not nothing) and confirming the tiles stayed draggable.
- **Retail:** `.planning/testing/RETAIL-REGRESSION-PASS.md` step 3 — all three tiles present and draggable, confirming the fix did not hide a catalog that does resolve. This was the milestone's only destructive-risk item.

PAR-01 is therefore verified on both flavours. Note this is also the one place v0.3 deliberately changed *retail* behaviour: an empty-bags alt used to see a real retail item's icon and name it could not obtain, and now sees a neutral placeholder. It is recorded under `### Changes` in the v0.3.0 changelog for that reason.

## Goal Achievement

### Observable Truths

Truths drawn from `27-01-PLAN.md`'s `must_haves.truths` frontmatter.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `TrinketProvider:RefreshAtRest` leaves `atRest.spellID` nil instead of `TRINKET_FALLBACK_ORDER[1]` (D-05) | VERIFIED | `Providers.lua` diff: the `if not trinketItemID then trinketItemID = TRINKET_FALLBACK_ORDER[1] end` block is deleted; `FindSpellByItemID` already returns `nil, nil` for a nil itemID |
| 2 | `PotProvider:RefreshAtRest` leaves `atRest.spellID` nil instead of `POT_FALLBACK_ORDER[1]` (D-05) | VERIFIED | Same pattern deleted at the pot site; `ipairs(POT_FALLBACK_ORDER)` scan loop untouched |
| 3 | When `atRest.spellID` is nil, Trinket/Pot `GetDisplayInfo` returns a neutral placeholder — no spellID, generic label, question-mark icon — never the hardcoded fallback item's real spellID (D-03) | VERIFIED | `UnresolvedDisplayInfo(label)` returns `{ icon = 134400, label = label, duration = 0, spellID = nil }`; both `GetDisplayInfo` methods call it in place of the old `FindSpellByItemID(..., FALLBACK_ORDER[1])` retry |
| 4 | Trinket/Pot `GetDisplayInfo` never returns nil, so `CDMTab.lua:137`/`:518` `if info then` gates still fire and both Suggested tiles stay draggable (D-04) | VERIFIED (statically) | `grep -c 'return nil'` inside both `GetDisplayInfo` bodies = 0; `CDMTab.lua:137`/`:518` read and confirmed to gate entry-creation on `if info then`, which is satisfied by the non-nil placeholder table |
| 5 | No inventory API and no flavor branch exists anywhere in `GetDisplayInfo`'s path (D-06, D-07) | VERIFIED | Zero matches for `GetInventoryItemID\|C_Item.GetItemCount\|INVSLOT_` inside both `GetDisplayInfo` bodies; zero matches for `WOW_PROJECT\|GetBuildInfo\|IsTestBuild\|Interface: ?1[26]` anywhere in the file |
| 6 | Both `RefreshAtRest` methods still open with `InCombatLockdown()` early return (D-07) | VERIFIED | `grep -c 'if InCombatLockdown() then'` across both `RefreshAtRest` bodies = 2 |
| 7 | `LustProviderMixin` and `UserSpellProviderMixin` are byte-unchanged (D-09) | VERIFIED | `git diff HEAD~1 HEAD -- Providers.lua` case-insensitive scan for `lust\|userspell` on added/removed diff lines = 0 matches |

**Score:** 7/7 code-level truths statically verified. **Not covered by this table:** the *observable* rendering behavior on a real game client (does a fresh alt with no equipped trinket/no bagged potion actually see a blank/placeholder tile in-game, on retail and on Forever) — this is ROADMAP Phase 27 success criterion 1's live half, owned by Phase 28's VER-08, and cannot be checked from this environment. See "Human Verification Required" below.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Providers.lua` | Four-site at-rest fallback removal plus shared `UnresolvedDisplayInfo` placeholder helper | VERIFIED — EXISTS + SUBSTANTIVE | 650 lines (>= 600 min); contains `local function UnresolvedDisplayInfo`; `stylua --check` clean with CRLF preserved |

**Artifacts:** 1/1 verified

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `TrinketProviderMixin:GetDisplayInfo` | `UnresolvedDisplayInfo` | unresolved-state early return | WIRED | `Providers.lua`: `return UnresolvedDisplayInfo("Trinket")` present exactly once |
| `PotProviderMixin:GetDisplayInfo` | `UnresolvedDisplayInfo` | unresolved-state early return | WIRED | `Providers.lua`: `return UnresolvedDisplayInfo("Damage Pot")` present exactly once |
| `UnresolvedDisplayInfo` | `CDMTab.lua:137` / `:518` `if info then` gates | non-nil return keeps Suggested tiles addable | WIRED (statically) | `icon = 134400` confirmed inside the helper body; both CDMTab gates read directly and confirmed to test `if info then`/`if info then` truthiness only, which a table (never nil) always satisfies |

**Wiring:** 3/3 connections verified statically. Runtime confirmation (does the drag/drop and tile-render actually behave correctly end-to-end in a live UI) is part of Phase 28's scope, not claimed here.

## Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|-----------------|
| PAR-01: Trinket/Pot at-rest tiles show nothing rather than a hardcoded retail item's icon/name; guard identical on retail and Forever | PARTIAL — code complete, statically verified; **live confirmation not performed** | Requires an in-game character with no equipped trinket / no bagged potion, on both retail and Forever, to observe actual tile rendering. This environment cannot launch WoW. |

**Coverage:** 0/1 requirements fully satisfied end-to-end; 1/1 code-level implementation complete and gate-verified.

## Anti-Patterns Found

None. `UnresolvedDisplayInfo`'s `duration = 0` is a documented, precedented sentinel (matches `UserSpellProviderMixin:GetDisplayInfo`'s existing no-entry branch and `CDMTab.lua:98`'s `duration > 0` test) — not a stub or placeholder left behind by mistake. No `TODO`/`FIXME`/"coming soon" markers introduced. `TRINKET_FALLBACK_ORDER` remains declared-but-unreferenced by design (D-10, locked), annotated in-code and handed to Phase 30's dead-code sweep rather than silently left unexplained.

## Human Verification Required

### 1. Retail empty-bags/no-trinket rendering (ROADMAP Phase 27 criterion 1, observable half)
**Test:** On a retail character (or Forever beta character) with no trinket equipped in either trinket slot and no tracked damage potion in bags, open the CDM Suggested section and observe the Trinket and Pot tiles.
**Expected:** Both tiles render with a neutral/question-mark icon and a generic label ("Trinket" / "Damage Pot"), not a specific real-looking item icon/name (e.g. not "Light Company Guidon" or "Light's Potential"). Both tiles remain draggable into a Bars/Buffs section.
**Why human:** Requires a live WoW client (retail or Forever) and a character in a specific equipment/bag state. Not launchable from this execution environment.

### 2. Forever spellID resolution behavior (VER-08, tracked separately in Phase 28)
**Test:** On a Forever beta character, observe whether the pre-fix retail-only spellIDs in `TRINKET_SPELLS`/`POT_SPELLS` would have resolved to anything visible at all (i.e., does `C_Spell.GetSpellInfo` on a retail-exclusive spellID return data on Forever, or nil).
**Expected:** Documented in Phase 28's checklist regardless of outcome — the fix in this phase is correct either way, per the plan's own framing.
**Why human:** Genuinely unknown without a live Forever client; explicitly deferred to Phase 28 by both `27-CONTEXT.md` and `27-01-PLAN.md`.

## Gaps Summary

**No code-level gaps found.** All seven `must_haves.truths` from `27-01-PLAN.md`'s frontmatter are statically verified: all four `FALLBACK_ORDER[1]` fallback sites are removed, the shared `UnresolvedDisplayInfo` placeholder is wired into both `GetDisplayInfo` unresolved-state returns, neither method can return nil, both `RefreshAtRest` methods retain their combat gate, and `LustProviderMixin`/`UserSpellProviderMixin` are byte-unchanged.

**The one open item is not a gap in this plan's work — it is out of this plan's declared scope.** ROADMAP Phase 27 success criterion 1's *observable* half (what a real character with empty bags/no trinket actually sees) requires a live WoW client and is explicitly assigned to Phase 28's VER-08 by both `27-CONTEXT.md` and `27-01-PLAN.md`. This report's `human_needed` status reflects that unresolved observable half honestly — it is not a critical gap blocking Phase 27's own completion, but it does mean PAR-01 cannot be marked fully verified until Phase 28 confirms live behavior.

## Recommended Fix Plans

None. No code gaps exist. The only remaining work item is the live verification pass already scoped into Phase 28 (VER-08) — no new plan is needed inside Phase 27.

## Verification Metadata

**Verification approach:** Goal-backward (derived from `27-01-PLAN.md`'s `must_haves` frontmatter and ROADMAP Phase 27's two success criteria)
**Must-haves source:** `27-01-PLAN.md` frontmatter (`must_haves.truths`, `must_haves.artifacts`, `must_haves.key_links`)
**Automated checks:** 23 passed, 0 failed (Task 1's 14-assertion gate + Task 2's 8-assertion invariant gate, both re-run clean after two comment-wording amendments; plus the plan's own `<verification>` grep/diff-stat checks)
**Human checks required:** 2 (both game-client-dependent; both explicitly owned by Phase 28)
**Total verification time:** ~24 min (shared with plan execution)

---
*Verified: 2026-09-18T11:41:20Z*
*Verifier: Claude (subagent)*
