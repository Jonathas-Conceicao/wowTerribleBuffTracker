---
phase: 35-four-base-containers
verified: 2026-09-21T00:00:00Z
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
score: 9/9 must-haves verified (code-level); 6 items require in-game confirmation
overrides_applied: 0
human_verification:
  - test: "/tbt opens the CDM tab; check section order and tracker placement"
    expected: "Six sections in order: Tracked Buffs, Tracked Bars, Essential Cooldowns, Utility Cooldowns, Not Displayed, Suggested — and every previously tracked buff is where it was left."
    why_human: "Requires a v0.3.0 saved-variables file loaded live in-client; static code reading can confirm the migration logic and section-key stability but not the rendered result."
  - test: "Enter Edit Mode and observe the four TBT overlays"
    expected: "Four overlays labelled TBT Tracked Buffs, TBT Tracked Bars, TBT Essential Cooldowns, TBT Utility Cooldowns. The pre-existing two are where they were before the upgrade; the two new ones are stacked below and not on top of the player's UI."
    why_human: "Visual placement/overlap cannot be confirmed by grep; needs the Edit Mode panel rendered."
  - test: "Drag each of the four containers to a distinct spot, then exit and re-enter Edit Mode"
    expected: "Each drags independently; positions hold across an Edit Mode exit and re-entry."
    why_human: "Runtime frame movement and Edit Mode enter/exit lifecycle require the game client."
  - test: "Open the settings popup for each of the four containers"
    expected: "Only the bar container's settings popup offers Bar Width and Display Mode."
    why_human: "Code shows the kind == \"bar\" branch is the only one adding those two controls (EditModeFrames.lua lines 420-431), but rendered popup contents need visual confirmation."
  - test: "Drag a tracker into Essential Cooldowns"
    expected: "Renders as an ICON inside that container."
    why_human: "Rendering output is only observable in-game; RenderIconContainer is dispatched for icon-kind containers (essential/utility) by code inspection, but visual confirmation is required."
  - test: "Load, enter/exit Edit Mode, and fight in combat"
    expected: "No Lua error on load, on first Edit Mode entry, on exit, or in combat."
    why_human: "Runtime error absence cannot be proven by static analysis alone."
---

# Phase 35: Four Base Containers & Saved-Position Migration Verification Report

**Phase Goal:** TBT's two containers become the four the CDM already groups by — Tracked Buffs, Tracked
Bars, Essential Cooldowns, Utility Cooldowns — with existing users' layouts carried over rather than reset.
**Verified:** 2026-09-21
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Exactly four fixed-name containers exist, with no rename/delete affordance anywhere (CONT-01) | VERIFIED | `Core.lua:9-46` — `ns.CONTAINERS` has exactly 4 entries: `buffs`/Tracked Buffs, `bars`/Tracked Bars, `essential`/Essential Cooldowns, `utility`/Utility Cooldowns. Whole-addon grep for `rename\|delete.*container\|removecontainer\|deletecontainer` returns only two comments describing the internal position-*key* rename (`icons`→`buffs`), not a UI affordance. |
| 2 | Each container is independently movable and its position cannot clobber another's (CONT-02) | VERIFIED | `EditModeFrames.lua:9-40` (`ApplyEditModePositions`) and `:520-539` (`SaveEditModePositions`) both loop `ipairs(ns.CONTAINERS)` and read/write `ns.db.editModePositions[def.key]` — a distinct DB key and a distinct frame (`ns.containers[def.key]`) per container. No shared table, no cross-key write. |
| 3 | v3→v4 migration renames the Tracked Buffs position key, nil-guarded, one-shot (CONT-03, migration half) | VERIFIED | `BuffEngine.lua:123-136` — `if ver < 4 then` copies `editModePositions.icons` to `.buffs` only when `.buffs` is absent, then unconditionally nils `.icons`; wrapped in `if ns.db.editModePositions then`, so a user who never opened Edit Mode is a clean no-op. |
| 4 | Migration runs strictly before position-apply, so the renamed key is in place before it's read (CONT-03, ordering) | VERIFIED | `Core.lua:131` calls `ns:InitBuffEngine()` (runs the migration) inside the `ADDON_LOADED` branch; `Core.lua:140` calls `ns:InitEditModeFrames()` (which calls `ApplyEditModePositions()` at `EditModeFrames.lua:780`) inside the later `PLAYER_ENTERING_WORLD` branch. `ADDON_LOADED` always fires before `PLAYER_ENTERING_WORLD`. |
| 5 | No bulk re-sectioning of `trackedBuffs` — every v0.3.0 tracker placement survives untouched (CONT-03, placement half) | VERIFIED | Whole-addon grep for `\.section\s*=` (excluding `==` comparisons) finds only: the pre-existing (pre-Phase-35) v0→v1 migration block (`BuffEngine.lua:87-91`), and `ns:SetBuffSection` (`BuffEngine.lua:260-281`), the pre-existing single-entry setter invoked only from user-driven drag/right-click actions in `CDMTab.lua`. No new bulk-rewrite loop was added anywhere. |
| 6 | A fresh database (no `schemaVersion`) reaches the full four-container state (CONT-03, fresh-install half) | VERIFIED | Fresh DB: `ver = 0`, all four migration blocks run in `BuffEngine.lua:82-136`, ending at `schemaVersion = 4` (no-ops on empty `trackedBuffs`/absent `editModePositions`). `Core.lua:93-129`'s registry-driven seed loop then creates a fresh `containerSettings[def.key]` for all four keys on every `ADDON_LOADED`. `ApplyEditModePositions` (`EditModeFrames.lua:18-39`) idempotently seeds any missing `editModePositions[def.key]` from `def.defaultX`/`def.defaultY` on every `PLAYER_ENTERING_WORLD`. Both seed paths are unconditional (not version-gated), so fresh and upgraded databases converge on the same end state. |
| 7 | No dangling references to the pre-Phase-35 paired container fields anywhere in the addon | VERIFIED | Whole-repo grep (`*.lua`, `*.xml`) for `ns\.barContainer\|ns\.iconContainer\|cachedBarSettings\|cachedIconSettings\|barPool\|iconPool\|barTimers\|iconTimers\|ns\.cdmBarViewer\|ns\.cdmIconViewer\|ns\.barTooltipsShown\|ns\.iconTooltipsShown\|ns\.barOverlay\|ns\.iconOverlay\|ns\.barSelectedOverlay\|ns\.iconSelectedOverlay` returns zero hits, including in `Providers.lua` and `CDMTab.xml`. |
| 8 | Hot-path render functions introduce no new per-tick allocations beyond the known/accepted placeholders | VERIFIED | Read `ns:UpdateDisplay`, `RenderBarContainer`, `RenderIconContainer` in full (`Display.lua:435-749`). The only table constructors inside those three bodies are `Display.lua:516` and `:667` (`bar.proc = { … }` / `icon.proc = { … }`), which are the pre-existing placeholder-proc tables already filed as a Phase 43 todo per the phase's own commit `83b73e6`. `ByLayoutOrder` (`Display.lua:29-31`) is a module-level local, not an inline closure. No other constructor or closure literal appears in any of the three functions. |
| 9 | No client-identity/flavour branch was introduced | VERIFIED | Whole-addon grep for `GetBuildInfo\|WOW_PROJECT_ID\|WOW_PROJECT_MAINLINE\|WOW_PROJECT_CLASSIC` returns zero hits. `_G[def.cdmViewerGlobal]` (`EditModeFrames.lua:255`, `Display.lua:388`) is a capability check on a global's existence, not a client-identity check. One `TerribleBuffTracker.toc`, `## Interface: 120100, 16001`, confirmed by direct read. |

**Score:** 9/9 truths verified at the code level. All are structural/static verifications; the phase's own plans and summaries correctly flag six behaviors that can only be confirmed in a running client (see Human Verification below).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | `ns.CONTAINERS` registry + `ns.CONTAINER_BY_KEY` lookup | VERIFIED | Lines 9-51; four entries, correct keys/titles/kinds/defaults; used by every other file. |
| `BuffEngine.lua` | v3→v4 migration renaming `editModePositions.icons`→`.buffs` | VERIFIED | Lines 79, 123-136; `CURRENT_SCHEMA_VERSION = 4`, nil-guarded rename block. |
| `EditModeFrames.lua` | Registry-driven container/overlay creation, position apply/save, selection, handles, popup | VERIFIED | `ns.containers`/`ns.containerOverlays`/`ns.containerSelectedOverlays` built from `ns.CONTAINERS` (lines 758-789); every consumer (`SelectContainer`, `ShowEditModeHandles`, `SaveEditModePositions`, settings popup, Copy CDM Config) loops the registry. |
| `CDMTab.lua` | `SECTION_DEFS`/`VALID_DROP_SECTIONS` derived from `ns.CONTAINERS`, registry-driven context menus | VERIFIED | Lines 43-55 build both lists at file load; lines 171-188 and 444-460 (plan-referenced) generalise the right-click menus. |
| `Display.lua` | Per-container settings cache, pools, render functions, `UpdateDisplay` dispatch | VERIFIED | `cachedSettings`/`pools`/`timersByContainer` keyed by `ns.CONTAINERS` (lines 22-37); `RenderBarContainer`/`RenderIconContainer` (lines 435, 581); `ns:UpdateDisplay` dispatch loop (lines 715-749). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `Core.lua` `ADDON_LOADED` backfill | `ns.CONTAINERS` | `ipairs(ns.CONTAINERS)` seeding `containerSettings` | WIRED | `Core.lua:93` |
| `BuffEngine.lua` `ver < 4` migration | `ns.db.editModePositions.icons`/`.buffs` | direct table rename | WIRED | `BuffEngine.lua:129-134`; runs before any read of the renamed key (see Truth 4). |
| `EditModeFrames.lua` `ApplyEditModePositions`/`SaveEditModePositions` | `ns.db.editModePositions[def.key]` | `ipairs(ns.CONTAINERS)` read/write | WIRED | `EditModeFrames.lua:18, 29, 32, 536-538` |
| `EditModeFrames.lua` `ns:InitEditModeFrames` | `ns.CONTAINERS` | one `CreateFrame` per registry def, stored in `ns.containers[def.key]` | WIRED | `EditModeFrames.lua:758-777` |
| `CDMTab.lua` `SECTION_DEFS`/context menus | `ns.CONTAINERS` | `ipairs(ns.CONTAINERS)` at file load and inside `OnMouseUp` | WIRED | `CDMTab.lua:44-54, 171-188` |
| `Display.lua` `ns:UpdateDisplay` | `ns.containers[def.key]` | one render call per registry def, dispatched on `def.kind` | WIRED | `Display.lua:723-748` |
| `Display.lua` `RefreshContainerSettings` | `ns.db.containerSettings[def.key]` | one cached settings table per registry def | WIRED | `Display.lua:53-88` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `Display.lua` `timersByContainer[key]` | `timers` argument to `RenderBarContainer`/`RenderIconContainer` | `ns:GetActiveTimers()` (`BuffEngine.lua:157`), which merges `ns.activeTimers` (real UNIT_SPELLCAST_SUCCEEDED-driven procs) and `ns.previewTimers` | Yes | FLOWING |
| `Display.lua` `cachedSettings[key]` | settings snapshot read in both render functions | `ns.db.containerSettings[def.key]` (real SavedVariables, not a static stub) | Yes | FLOWING |
| `CDMTab.lua` section contents | `entry.section == def.key` filter over `ns.db.trackedBuffs` | real SavedVariables table, unmodified by this phase | Yes | FLOWING |

### Behavioral Spot-Checks

SKIPPED (no runnable entry points). This is a World of Warcraft addon with no headless harness, test runner, or CLI entry point — behavior can only be observed inside the game client. This is the project's permanent condition, not a Phase 35 gap.

### Probe Execution

No probes declared or found. `find scripts -path '*/tests/probe-*.sh' -type f` returns nothing, and no PLAN/SUMMARY file in this phase references a probe script. Section not applicable.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|--------------|----------------|--------------|--------|----------|
| CONT-01 | 35-01, 35-02, 35-03, 35-04 | Four base containers, fixed names, cannot be renamed or deleted | SATISFIED | Truth 1, artifacts Core.lua/EditModeFrames.lua/CDMTab.lua |
| CONT-02 | 35-02, 35-04 | Each base container independently movable, persists position through Edit Mode | SATISFIED (code-level); in-game drag/position-hold and retail logout→login persistence remain human checks | Truth 2, key links `ApplyEditModePositions`/`SaveEditModePositions` |
| CONT-03 | 35-01, 35-02, 35-03 | Existing `TBTBarContainer`→Tracked Bars, `TBTBuffContainer`→Tracked Buffs positions carry over; trackers keep section; cooldown containers start at sensible defaults | SATISFIED | Truths 3-6 |

No orphaned requirements — `.planning/REQUIREMENTS.md` maps only CONT-01/02/03 to Phase 35, and all three appear in at least one plan's `requirements:` frontmatter.

### Anti-Patterns Found

None. `TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER` and "coming soon"/"not yet implemented"/"not available" greps return zero hits across `Core.lua`, `BuffEngine.lua`, `EditModeFrames.lua`, `Display.lua`, `CDMTab.lua`.

### Human Verification Required

The four PLAN files and all four SUMMARY files consistently and explicitly flag the same in-game pass as not performed by the autonomous run (SUMMARY "Outstanding — In-Game Pass" sections). Static code reading confirms the underlying logic is correct and wired, but the following require the WoW Forever beta client:

1. **Six CDM tab sections, correct order and tracker placement** — `/tbt` shows Tracked Buffs, Tracked Bars, Essential Cooldowns, Utility Cooldowns, Not Displayed, Suggested in that order, and every previously tracked buff is where it was left. Why human: needs a v0.3.0 saved-variables file rendered live.
2. **Four Edit Mode overlays, correct labels and non-overlapping stacking** — *TBT Tracked Buffs*, *TBT Tracked Bars*, *TBT Essential Cooldowns*, *TBT Utility Cooldowns*, with the two new ones below the existing pair and not over the player's UI. Why human: visual layout.
3. **Independent drag and position-hold across Edit Mode exit/re-entry** — each of the four moves alone and stays put. Why human: runtime frame movement.
4. **Only the bar container's settings popup offers Bar Width and Display Mode.** Code confirms the branch (`EditModeFrames.lua:420-431`); visual confirmation is separate.
5. **A tracker dragged into Essential Cooldowns renders as an icon there.** Code confirms the dispatch (`Display.lua:743-747`, icon kind → `RenderIconContainer`); rendering output needs the client.
6. **No Lua error on load, first Edit Mode entry, exit, or in combat.**

**Persistence caveat (do not treat as a gap):** Roadmap Success Criterion 2 also requires positions to survive a retail logout→login. Per this phase's own context (`35-CONTEXT.md`) and the task brief, `/reload` cannot exercise this path (SavedVariables survive in memory regardless) and the Forever beta does not read saved variables back at all. This check is explicitly deferred to Phase 44's retail pass and is not claimed here, consistent with every SUMMARY.md in this phase.

### Gaps Summary

No code-level gaps found. Every truth, artifact, and key link traced from the roadmap goal backward to the shipped code holds up under direct reading — the registry pattern is used consistently everywhere `ns.CONTAINERS` needed to reach, the schema migration is correctly ordered and nil-guarded, no bulk re-sectioning was introduced, no dangling two-container fields remain, hot-path discipline holds (only the two pre-existing, already-filed placeholder allocations remain), no flavour checks were introduced, and `stylua --check .` is clean with no line-ending churn.

The only open items are the six in-game observations every plan and summary in this phase already flagged as un-performed, plus the retail-only persistence check explicitly deferred to Phase 44. None of these are contradicted by the code; they are simply unobservable outside a running client.

---

*Verified: 2026-09-21*
*Verifier: Claude (gsd-verifier)*
