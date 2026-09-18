# Phase 28: Forever In-Game Verification Checklist

> **⚠ Superseded for execution.** Run from `.planning/testing/FOREVER-TEST-PASS.md` instead — it puts
> Phase 25's `_Camelot.toc` load gate first (so a wrong suffix is caught before you work through
> functional steps), folds in Phase 27's human verification item so one tile-hover closes both
> requirements, and carries the failure-triage table. This file remains the formal Phase 28 record.

**Prepared:** 2026-09-18 (autonomous run — checklist only, nothing executed)
**Status:** ⛔ **Awaiting human execution** — requires a live WoW Forever beta client
**Requirements covered:** VER-02, VER-03, VER-04, VER-05, VER-06, VER-07, VER-08, PAR-02

---

## Before you start

**Preconditions**

- [ ] Phase 25's dual gate passed — retail loads from `_Mainline.toc`, Forever shows and loads from `_Camelot.toc`
- [ ] Phase 26's `install.bat` has deployed to the Forever client (`_classic_beta_`)
- [ ] Phase 27's provider fix is in the deployed build (affects step 9's expected result)

**Record the build first.** Every finding below is only reproducible against a named build. Do not copy `16001` from `PROJECT.md` — re-derive it:

```
C:\Program Files (x86)\World of Warcraft\.build.info   → the wow_classic_beta row's Version field
C:\Program Files (x86)\World of Warcraft\_classic_beta_\.flavor.info
```

- Build tested: `________________`  (expected shape: `1.60.1.NNNNN`)
- Interface derived: `________________`  (`major` + zero-padded `minor` + zero-padded `patch` → `1.60.1` = `16001`)
- Date tested: `________________`

**Session hygiene — read before testing.** The beta client stops delivering Lua errors after 100 in one session until the next `/reload`. Test with a minimal addon list and `/reload` between sections, rather than one long accumulating session. Otherwise TBT's own errors may go silently unreported and a step can falsely pass.

---

## Checklist

Run in order. Step 4 is the one that matters most — if it fails, most later steps are moot.

### 1. Addon loads — VER-02

- [ ] Log in on a Forever beta character
- [ ] Chat shows: `TerribleBuffTracker loaded. Type /tbt or /terriblebufftracker to open settings.`
- [ ] No red Lua error at `PLAYER_ENTERING_WORLD`
- [ ] If the AddOns-list entry itself is in doubt: `/run print(C_AddOns.GetAddOnInfo("TerribleBuffTracker"))`

**Result:** ☐ pass ☐ fail — notes: ______________________________

### 2. CDM attaches — VER-03 (part 1)

- [ ] Chat shows `TerribleBuffTracker: Attached to Cooldown Manager.`
- [ ] Chat does **not** show `TerribleBuffTracker: Cooldown Manager not found. Addon disabled.`

> Source: `Display.lua:368` and `Display.lua:342`. TBT resolves `BuffBarCooldownViewer` / `BuffIconCooldownViewer` (`Display.lua:335-336`).

**Result:** ☐ pass ☐ fail — notes: ______________________________

### 3. TBT tab injects — VER-03 (part 2)

- [ ] `/tbt` opens `CooldownViewerSettings`
- [ ] The TBT tab is visible **below** all of Blizzard's own tabs (v0.2.6 anchors it under the bottom-most one)
- [ ] All four sections render and expand with no error
- [ ] Forever's own CDM categories being empty is **not** a TBT failure — TBT never reads that data

**Result:** ☐ pass ☐ fail — notes: ______________________________

### 4. ⭐ Cast detection fires — VER-04 (HIGHEST PRIORITY)

**This is the single check the whole addon rests on.** It resolves whether `UNIT_SPELLCAST_SUCCEEDED` delivers a usable numeric spellID on Forever. No amount of source research can answer it.

- [ ] Add any real, castable spell by ID via the Add dialog
- [ ] Drag it to Tracked Bars
- [ ] Cast it
- [ ] A timer bar starts and counts down

**Result:** ☐ pass ☐ fail — spell used: ____________ — notes: ______________________________

> **If this fails:** stop and escalate rather than patching. The milestone's premise is broken and v0.3 needs re-scoping — see `28-CONTEXT.md` deferred question 2.

### 5. Bar / icon rendering — VER-05

- [ ] Timer bars render and match CDM's own atlas-based visuals
- [ ] Buff icons render correctly
- [ ] No missing/black textures — a broken atlas would indicate an undocumented Forever atlas-name change

**Result:** ☐ pass ☐ fail — notes: ______________________________

### 6. Edit Mode end-to-end — VER-06

- [ ] Enter Edit Mode; both TBT containers appear
- [ ] Drag each container; the settings popup opens
- [ ] NineSlice overlay draws correctly
- [ ] Exit Edit Mode
- [ ] `/reload` — positions persist

> **If positions do NOT persist:** check whether *other* addons also lose their settings before blaming TBT. Third-party reports against build `1.60.1.69893` claim SavedVariables are written on logout but never read back on this beta. That is a platform defect, not a TBT regression.

**Result:** ☐ pass ☐ fail ☐ blocked by platform SavedVariables bug — notes: ______________

### 7. Combat secret-value gating — VER-07

- [ ] Enter combat
- [ ] No uncaught Lua error from any aura read
- [ ] Midnight's known "blocked" behavior should **reproduce**, not crash

**Result:** ☐ pass ☐ fail — notes: ______________________________

### 8. Sated / Lust allowlist — VER-08 (part 1)

- [ ] On a class with lust access, if such content exists: the 40s timer starts even in combat
- [ ] On any class: the Suggested Lust tile renders without error even if no lust content exists yet

> Genuinely uncertain rather than expected-empty. Bloodlust (2825) and Heroism (32182) are old, stable spellIDs plausibly present on Forever. Time Warp, Fury of the Aspects and Harrier's Cry depend on specs that may not exist at the beta's level cap.

**Result:** ☐ pass ☐ fail ☐ no lust content available — notes: ______________________

### 9. Trinket / Pot tile behavior — VER-08 (part 2)

- [ ] Hover both Suggested tiles — no Lua error
- [ ] **Record which degraded state appears.** This is the empirical answer to the research conflict the milestone adjudicated, and it validates Phase 27's fix:

  ☐ neutral placeholder (question-mark icon, generic `Trinket` / `Damage Pot` label) — **expected after Phase 27's fix**
  ☐ a real-but-wrong retail item name and icon — **would mean Phase 27's fix did not take effect**
  ☐ something else: ______________________________

- [ ] Confirm both tiles are still **draggable** out of the Suggested section (Phase 27 D-04 — a `nil` return would have silently broken this)

> Empty trinket/pot behavior is **expected, not a bug**. Their catalogs are current-retail-season spellIDs no Forever character can produce.

**Result:** ☐ pass ☐ fail — notes: ______________________________

### 10. Foundational globals — sanity

- [ ] Escape closes the Add Buff dialog (confirms `UISpecialFrames` still works)

**Result:** ☐ pass ☐ fail — notes: ______________________________

### 11. Fresh WTF tree — SavedVariables isolation

- [ ] A brand-new Forever install loads TBT with zero tracked buffs and zero errors
- [ ] Rules out any cross-flavor SavedVariables assumption (retail and Forever have separate WTF trees)

**Result:** ☐ pass ☐ fail — notes: ______________________________

---

## PAR-02 — fast-follow fixes

If any step above produced a **Forever-only** Lua error:

- Fix it with a **narrow defensive read** — a nil-check or guarded call at the exact failing site
- **Never** a `WOW_PROJECT_ID` branch, a new code path, or a feature. The milestone is parity-only
- Raise it as its own plan in this phase so it gets a commit and a SUMMARY entry, rather than an ad-hoc edit

| Error | File:line | Fix applied | Commit |
|-------|-----------|-------------|--------|
|       |           |             |        |

---

## Findings summary

Fill in before closing the phase.

- **Build / interface tested:** ______________________________
- **Steps passed:** ____ / 11
- **Blocking failures:** ______________________________
- **Expected-empty confirmed (not bugs):** ☐ Trinket ☐ Pot ☐ Lust
- **Platform defects observed (not TBT):** ☐ SavedVariables not loading ☐ 100-error cap hit ☐ empty CDM categories
- **`UNIT_SPELLCAST_SUCCEEDED` verdict:** ☐ delivers usable spellID ☐ does not — **escalate**

---

## Out of scope for this phase

- Forever-appropriate lust / trinket / pot catalogs — `FCON-01..03`, a future milestone. Empty tiles get **recorded**, not fixed.
- `COMBAT_LOG_EVENT_UNFILTERED` availability on Forever — record as an observation only. TBT is not changing its detection strategy this milestone regardless.
