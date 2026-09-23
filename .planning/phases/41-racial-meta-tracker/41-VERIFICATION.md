---
phase: 41-racial-meta-tracker
verified: 2026-09-21T19:17:12Z
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
score: 5/5 roadmap success criteria verified at code level; 5/5 requirements (RACE-01..05) satisfied at code level; 6 in-game checks outstanding (Forever gnome dependency, Forever regression, retail parity)
overrides_applied: 0
human_verification:
  - test: "(Forever, gnome) THE HEADLINE CHECK: open CDM tab, confirm the Racial tile resolves to Eureka! at full colour (not desaturated). Cast Eureka!, confirm the tile shows 3 stacks and a 15s bar. Spend three qualifying casts (e.g. Fireball/Frost Nova-class harmful casts), confirm the tracker ends early rather than running the full 15s."
    expected: "Full-colour tile; 3→2→1→0 stack countdown; early expiry on the third qualifying cast, matching the timestamped log already captured in TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md (lines 536-548)."
    why_human: "Live client, live aura/cast interaction, and visual desaturation state cannot be exercised from static code. A greyed gnome tile on Forever is a FAILURE, not a pass — record unperformed rather than substituting the greyed presentation as a pass if no gnome character is available."
  - test: "(Forever, non-gnome) Open CDM tab, observe the Racial tile; hover it; cast that character's own racial ability."
    expected: "Tile renders desaturated; tooltip shows 'Your racial is not supported yet. / Only Eureka! (gnome) is implemented in this version. / Use the + button to track it yourself.'; casting the racial starts no timer/tracker."
    why_human: "Visual desaturation and tooltip rendering, plus confirming absence of a started timer, require a live client."
  - test: "(Forever) Drag the greyed Racial tile into a container."
    expected: "Tile is draggable and addable like any other Suggested tile; the resulting tracker is inert (placeholder, never fires) per RACE-04."
    why_human: "Drag-and-drop interaction and pooled-frame rendering are only observable live."
  - test: "(Forever) Regression pass: every pre-existing tracker (buff bars, buff icons, cooldown icons with charge counts) rendered before this phase."
    expected: "All look exactly as before — no stray stack numbers, no layout shift, no desaturation leakage onto non-Suggested items."
    why_human: "The shared render loop (RenderIconContainer/RenderBarContainer/ApplyCooldownSlot) was touched by Plan 02; only a live comparison can confirm no visual regression, even though the code-level dirty-stamp trace (Step 4b below) shows every widget-owning path sets or clears the stamp."
  - test: "(Forever) RACE-05 end to end: hover a real Forever racial in the spellbook, read the Spell ID: TOOL-01 prints, type it into the + dialog with a duration, confirm the tracker starts on the next cast."
    expected: "A plain buff tracker (no stack logic) starts and runs on cast, proving the escape hatch works for an unsupported racial."
    why_human: "End-to-end tooltip-read → dialog-type → cast-triggers-tracker flow requires a live client and a real spell cast."
  - test: "(Retail, Phase 44, gnome-only) RACE-01's retail half — the tile appears on retail too — plus a parity re-run of the full stack-count behaviour."
    expected: "Same full-colour Eureka! presentation and 3→2→1→0 behaviour as Forever."
    why_human: "By user decision no retail check happens before Phase 44; retail is the client with no probing behind it. Without a gnome test character this cannot be performed at all and must be recorded unperformed, not substituted with the greyed result."
---

# Phase 41: Racial Meta-Tracker (Eureka! only) Verification Report

**Phase Goal:** A Racial tile that ships one racial done properly rather than a catalogue done vaguely
— Eureka! with cast-driven stack consumption, everything else honestly labelled.
**Verified:** 2026-09-21T19:17:12Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A Racial tile appears in the Suggested section on both retail and Forever | VERIFIED (code) | `BuffEngine.lua:68` `ns.SUGGESTED_KEYS = { "lust", "trinket", "pot", "racial" }`; `Providers.lua:906` `racial = RacialProvider` in `keyToProvider`; `RacialProviderMixin:HasResolvableCatalog` (`Providers.lua:884-886`) unconditionally returns `true`, so `ns:IsSuggestedKeyResolvable("racial")` never hides the tile. `CDMTab.lua:738-764` iterates `ns.SUGGESTED_KEYS` with no per-key branch, so the fourth tile renders through unchanged machinery on both clients. Resolution is by `raceID` (`Providers.lua:715,723`) plus a capability check (`C_Spell.GetSpellInfo`, `Providers.lua:724`), never by client identity — `grep -rn 'GetBuildInfo' *.lua` returns exactly one hit (`Core.lua:336`), and `ns.CLIENT_HAS_SPELL_RANKS` has exactly one definition (`Core.lua:344`) and one reader (`CDMTab.lua:950`, unrelated to Racial). Retail rendering is asserted by code reading only — see Human Verification. |
| 2 | On a gnome, casting Eureka! starts a tracker showing 3 stacks and a 15s duration | VERIFIED (code) | `Providers.lua:689-691` `RACIAL_SPELLS[7] = { spellID = 1259817, duration = 15, maxStacks = 3, ... }`. `Providers.lua:802-820` granting-cast branch: `expiresAt = now + def.duration` (written once), `stacks = def.maxStacks`. `Display.lua:1002-1016` (icon) and `834-847` (bar) render `timer.stacks` via `icon.chargeCount`/`bar.stacks`, gated by a dirty stamp. Live confirmation is a gnome-only in-game check (Human Verification) — the research log (`TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md:536-548`) already recorded this working on Forever 2026-09-20. |
| 3 | Each qualifying cast drops the stack count; tracker ends early at zero; the nominal 15s timer still ends it as backstop; over-consumption on harmful-but-harmless spells is accepted | VERIFIED (code) | `Providers.lua:823-843` consuming-cast branch: `proc.stacks = proc.stacks - 1`; `if proc.stacks <= 0 then ns:EndTimer("racial")`. `BuffEngine.lua:335-343` `ns:EndTimer` clears `ns.activeTimers[key]` only — a removal, never a shortening of `expiresAt`. `BuffEngine.lua:160-194` `ns:GetActiveTimers` expires any proc whose `expiresAt` has passed, unmodified by this phase, so the 15s backstop is pre-existing code, not new. `CastSpendsStack` (`Providers.lua:763-777`) adds no damage allow-list or school check; comments at 758-762 state the over-consumption is accepted, not mitigated. |
| 4 | Every racial other than Eureka! shows "not yet supported", explains itself in a CDM tooltip, and starts no timer when cast | VERIFIED (code) | `RACIAL_SPELLS` (`Providers.lua:689-691`) contains exactly one entry and no `supported = false` flag — absence from the table IS the unsupported state. `RacialProviderMixin:OnTrigger` (`Providers.lua:795-800`) returns `nil` immediately after `ResolveRacial()` fails, before any `C_Spell` call — inert by construction. `GetDisplayInfo`'s unsupported branch (`Providers.lua:865-878`) sets `unsupported = true`, `spellID = nil`, `descriptionLines = RACIAL_UNSUPPORTED_LINES`. `CDMTab.lua:758` `item.Icon:SetDesaturated((info and info.unsupported) == true)` runs unconditionally on every Suggested tile (idempotent against pool reuse); `CDMTab.lua:784` clears it to `false` on the tracked-items branch. `CDMTab.lua:135` `extraLines = info.descriptionLines or (description and { description }) or nil` surfaces the provider tooltip. |
| 5 | A user can build their own tracker for an unsupported racial through the normal add flow, behaving like any other buff tracker | VERIFIED (code) | `CDMTab.lua:980-994` (`addBtn` `OnClick`): reads `spellIdBox:GetNumber()`, validates `> 0`, reads a duration, calls `ns:AddTrackedBuff` with no membership test, no race check, no catalogue lookup. `grep -n '1259817\|UnitRace\|RACIAL' CDMTab.lua BuffEngine.lua` returns zero hits — confirmed directly, not just by summary claim. The unsupported tile itself stays draggable (`CDMTab.lua:411-439` `BeginDrag` reads `iconFrame.spellID` generically for any string key, no racial special case) and addable through the same generic `ns.db.trackedBuffs[suggestedKey] = {...}` path Lust already uses (`CDMTab.lua:526-545`). |

**Score:** 5/5 roadmap success criteria verified at the code level.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `Providers.lua` | `RACIAL_SPELLS`, `RacialProviderMixin`, registration/dispatch | VERIFIED | One catalogue entry (raceID 7 → spellID 1259817), `OnTrigger`/`GetDisplayInfo`/`HasResolvableCatalog` all present and match plan shape; registered in `ns.providers` (position 4) and `keyToProvider.racial`. |
| `BuffEngine.lua` | `ns:EndTimer`, `SUGGESTED_KEYS` gains `"racial"`, preview stacks passthrough | VERIFIED | `ns:EndTimer` (line 335) is a pure removal; `SUGGESTED_KEYS` (line 68) has four entries; `stacks = info.stacks` (line 376) is an unconditional field copy in `ns:StartAllPreviewTimers`. `CURRENT_SCHEMA_VERSION` still `4` (line 82), unbumped as planned. |
| `Display.lua` | `bar.stacks` font string, dirty-stamp stack text on both render paths | VERIFIED | `bar.stacks` created in `CreateTimerBar` (lines 254-259) matching `NumberFontNormalSmall`/32x10/`RIGHT`/`BOTTOMRIGHT(-5,5)`. All widget-owning paths (icon timer, icon cooldown-reset ×2, icon placeholder, bar timer, bar placeholder) either set or clear `_stacks`/`icon._stacks` — traced line-by-line, no path left stale. |
| `CDMTab.lua` | Provider-driven desaturation and tooltip lines on Suggested tiles | VERIFIED | `SetDesaturated` appears exactly 2×, unconditional on the Suggested branch, `false` on the tracked-items branch. `descriptionLines` appears exactly 1×. No `"racial"` string literal anywhere in the file. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Providers.lua RacialProviderMixin:OnTrigger` | `BuffEngine.lua ns:EndTimer` | early-expiry call | WIRED | `ns:EndTimer("racial")` at `Providers.lua:837`; exactly one hit codebase-wide. |
| `Providers.lua keyToProvider` | `ns:GetDisplayInfoForKey("racial")` | string-key dispatch | WIRED | `keyToProvider.racial = RacialProvider` (line 906); `ns:GetDisplayInfoForKey` (line 917-923) routes string keys through this map. |
| `Display.lua RenderIconContainer timer branch` | `icon.chargeCount.Current` | `SetText` guarded by `icon._stacks` | WIRED | Lines 1008-1016; stamp compared before every `SetText`/`Show`/`Hide`. |
| `Display.lua RenderBarContainer timer branch` | `bar.stacks` | `SetText` guarded by `bar._stacks` | WIRED | Lines 839-847. |
| `CDMTab.lua Suggested render loop` | `ns:GetDisplayInfoForKey(...).unsupported` | `item.Icon:SetDesaturated` | WIRED | Line 758, unconditional per tile, pool-safe. |
| `CDMTab.lua icon frame OnEnter` | `ns:GetDisplayInfoForKey(...).descriptionLines` | `extraLines` | WIRED | Line 135, passed by reference, no re-wrap. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| Icon stack text (`icon.chargeCount`) | `timer.stacks` | `ns.activeTimers["racial"].stacks`, mutated in `OnTrigger`'s consuming-cast branch (a real, TBT-computed integer, not a stub/empty return) | Yes | FLOWING |
| Bar stack text (`bar.stacks`) | `timer.stacks` | Same source as above, merged into the sorted list by `ns:GetActiveTimers` | Yes | FLOWING |
| Suggested tile desaturation | `info.unsupported` | `RacialProviderMixin:GetDisplayInfo` → `ResolveRacial()` → `UnitRace("player")` + `RACIAL_SPELLS` lookup + `C_Spell.GetSpellInfo` capability check (a real per-character resolution, not a hardcoded constant) | Yes | FLOWING |
| Suggested tile tooltip | `info.descriptionLines` | Same `GetDisplayInfo` call, returns `RACIAL_SUPPORTED_LINES` or `RACIAL_UNSUPPORTED_LINES` module-level constants (provider-owned, not empty) | Yes | FLOWING |

### Behavioral Spot-Checks

Skipped — this is a WoW addon with no runnable entry point outside the game client. No server, CLI, or build output to invoke. All behavior was verified by reading the shipped code paths end to end (dispatch → mutation → render), documented above.

### Probe Execution

No `scripts/*/tests/probe-*.sh` files exist in this repository and none are declared by the phase's PLAN/SUMMARY files. `tools/TBTProbe/Probe.lua` is a manual in-game `/tbtp` tool, not an automated probe script — it was the prototype this phase's `CastSpendsStack`/stack-engine logic was productionised from (per 41-01-SUMMARY.md), and its role ends there. Step 7c: SKIPPED (no runnable/scripted probes for this phase).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| RACE-01 | 41-03 | Racial meta-tracker appears in Suggested on both retail and Forever | SATISFIED (code) | See Truth #1. Retail half unverified in-game by design (Phase 44). |
| RACE-02 | 41-01, 41-02 | Eureka! starts on cast with 3 stacks and 15s duration | SATISFIED (code) | See Truth #2. |
| RACE-03 | 41-01 | Stack loss per qualifying cast, early expiry, 15s backstop | SATISFIED (code) | See Truth #3. |
| RACE-04 | 41-01, 41-03 | Unsupported racials marked, tooltip, inert on cast | SATISFIED (code) | See Truth #4. |
| RACE-05 | 41-03 | Manual add-flow escape hatch for unsupported racials | SATISFIED (code) | See Truth #5. |

No orphaned requirements — `.planning/REQUIREMENTS.md` maps only RACE-01..05 to Phase 41, and all five appear in the plans' `requirements` frontmatter. `RACE-06`/`RACE-07` are explicitly out of scope for this phase (next minor milestone), confirmed absent from any plan's requirements list and absent from the shipped code (no second race entry in `RACIAL_SPELLS`).

### Anti-Patterns Found

None. `grep -n 'TODO\|FIXME\|XXX\|HACK\|PLACEHOLDER\|TBD'` across `Providers.lua`, `BuffEngine.lua`, `Display.lua`, `CDMTab.lua` returns zero hits. No empty-return stubs, no hardcoded-empty data flowing to render, no console-log-only implementations. `stylua --check .` exits 0 (verified directly, not from SUMMARY claim).

### Scope Fence (verify_these_specifically item 10)

- `proc.key` stays `"racial"`, `proc.spellID` is the derived numeric field — confirmed (`Providers.lua:810-811`).
- `CURRENT_SCHEMA_VERSION` still `4` — confirmed (`BuffEngine.lua:82`).
- No bulk `entry.section` rewrite — confirmed; the only `entry.section` reads in the new code are the existing single-entry pattern (`Providers.lua:804-807,815`).
- No CDM frame contact from this phase — confirmed; no `CooldownViewer`/`itemFramePool`/mixin-method references added in any of the six commits.
- `TBTSettingsTab`/`AnchorTabBelowCDMTabs` untouched — confirmed; `git show --stat` on all six commits lists only `Providers.lua`, `BuffEngine.lua`, `Display.lua`, `CDMTab.lua`, no `EditModeFrames.lua`.
- `stylua --check .` exits 0 — confirmed directly.
- `CHANGELOG.md` untouched by all six commits — confirmed: `git show --stat` on `a417f20, 2f901b5, b48cbb4, 15fd8b2, 81b82af, ff11f0f` shows no `CHANGELOG.md` entry in any commit.

### Human Verification Required

See YAML frontmatter `human_verification` for the full list (6 items). Summary:
1. **THE HEADLINE CHECK** (Forever, gnome) — full-colour Eureka! tile, 3→2→1→0 stack countdown, early expiry. Requires a gnome test character; record unperformed if unavailable rather than accepting a greyed tile as a pass.
2. (Forever, non-gnome) greyed tile, tooltip, inert on cast.
3. (Forever) greyed tile stays draggable/addable.
4. (Forever) full regression pass on every pre-existing tracker type — the shared render loop was touched.
5. (Forever) RACE-05 end-to-end: spellbook tooltip → typed spell ID → working manual tracker.
6. (Retail, Phase 44, gnome-only) RACE-01's retail half plus a parity regression of stack behaviour.

### Gaps Summary

No code-level gaps found. Every observable truth, artifact, and key link traced cleanly from cast dispatch through to rendered pixels, with the accepted over-consumption behaviour left deliberately unmitigated as the user specified, and the "no timer for unsupported" guarantee holding by construction (absence from `RACIAL_SPELLS`, not a runtime flag). The phase cannot reach `passed` because six in-game checks — most critically the Forever gnome headline check — remain outstanding by the plan's own design (explicitly deferred to Phase 42/44), which routes this report to `human_needed` rather than `passed` or `gaps_found`.

---
*Verified: 2026-09-21T19:17:12Z*
*Verifier: Claude (gsd-verifier)*
