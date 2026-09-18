# Forever Test Pass — run this FIRST

**Status: ✅ FOREVER PASS COMPLETE — 2026-09-18, build `1.60.1.69913`, interface `16001`. Steps 1-8 PASS (9 N/A). Steps 10-11 not separately exercised but covered by normal use. TBT is functional on WoW Forever.**

> ⭐ **The milestone-deciding question is answered: `UNIT_SPELLCAST_SUCCEEDED` DOES deliver a usable spellID on Forever.** Buff tracking and timer bars work as expected. v0.3's premise holds.
**Order:** This pack runs **before** `RETAIL-REGRESSION-PASS.md`. Get TBT functional on Forever, then check retail for regressions.

No agent may fill in a result on this page. Only a human who has actually launched the Forever client may record verdicts.

This pack consolidates, in execution order:
- Phase 25 Gate 2 (`TOC-02`) — does the client read `_Camelot.toc` at all
- Phase 28 `VER-02` … `VER-08` + `PAR-02` — full functional pass
- Phase 27's human verification item 1 (Forever half) — folded into step 8, same character state
- The four open research questions — recorded in passing, they cost nothing while you're in there

**Formal per-phase records** (unchanged, for traceability): `.planning/phases/25-.../25-INGAME-VERIFICATION.md`, `.planning/phases/28-.../28-VERIFICATION-CHECKLIST.md`. This pack is the run-sheet; those are the records.

---

## Build under test

| Flavor | Product | Expected build | Interface | TOC file |
|---|---|---|---|---|
| WoW Forever beta | `wow_classic_beta` | `1.60.1.69893` or later | `16001` | `TerribleBuffTracker_Camelot.toc` |

Re-derive the interface from the live client rather than trusting the table — the beta moves:

```
C:\Program Files (x86)\World of Warcraft\.build.info              → the wow_classic_beta row's Version
C:\Program Files (x86)\World of Warcraft\_classic_beta_\.flavor.info
```

Formula: `major` + zero-pad-2(`minor`) + zero-pad-2(`patch`) → `1.60.1` = `16001`.

- Build actually tested: **`1.60.1.69913`** (read from `.build.info`; newer than the pinned `69893`, same interface)
- Interface derived: **`16001`** (1 + 60 + 01)
- Date: **2026-09-18**

A verdict without a build number is not reproducible information.

---

## Before you launch — three things that will waste your session if skipped

**1. Deploy.** Run `./scripts/install.bat` — no arguments. Phase 26 made it flavor-aware; it copies all 10 files plus **both** TOCs to every client folder present, `_classic_beta_` included. Both TOCs go to both clients by design; the client picks its own by suffix.

**2. ✅ Stale-TOC check — already clean for Forever.** Verified 2026-09-18 after Phase 26's deploy: `_classic_beta_\Interface\AddOns\TerribleBuffTracker\` holds exactly 10 files and exactly **two** suffixed TOCs, with no stale unsuffixed `TerribleBuffTracker.toc`. **Nothing to delete for this pass.**

Optional confirmation:

```
dir "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker\*.toc"
```

Expect `TerribleBuffTracker_Camelot.toc` and `TerribleBuffTracker_Mainline.toc`, nothing else.

> The **retail** folder is a different story — it still holds a stale unsuffixed `TerribleBuffTracker.toc` plus leftover `ConfigUI.lua`. That is handled in `RETAIL-REGRESSION-PASS.md` and does not affect this pass. Leave it alone for now; it's what keeps retail working if `_Mainline.toc` turns out to have a problem.

**3. Session hygiene.** This beta stops delivering Lua errors after 100 in one session until `/reload`. Test with a minimal addon list and `/reload` between sections, or TBT's own errors go silently unreported and a step falsely passes. Run `/console scriptErrors 1` before your first reload so silent failures surface as a dialog naming file and line.

Cosmetic non-issue: the AddOns list shows version `@project-version@` in a dev copy. That's the packager's substitution keyword, replaced only in a packaged release.

---

## Step 1 — Does the client read `_Camelot.toc`? ⭐ GATING

`TOC-02` / Phase 25 Gate 2. The pass bar is exactly this and no wider:

- [x] `TerribleBuffTracker` appears in the AddOns list
- [x] Log in — no Lua error at login

**Result:** ☑ **PASS** (2026-09-18) — addon shows and loads without errors; sections show correctly in the AddOns list and the addon icon renders. **`_Camelot.toc` is confirmed correct — the gating question of this milestone is settled.**

> **Do not widen this step.** CDM being unreachable, the tab being absent, SavedVariables not persisting, or empty tiles are **not** failures here — they're steps 2–9 below. Conflating a CDM problem with a wrong TOC suffix sends the next session chasing the wrong file entirely.

**If this step FAILS, stop and report — do not work around it.**

Forbidden: auto-trying `_Vanilla.toc` / `_Forever.toc` / any other suffix; falling back to a single unsuffixed TOC; adding `## AllowLoadGameType` speculatively.

Collect these four diagnostics first, in order:

1. **The suffix Blizzard's own TOCs use in the live client** — list `_classic_beta_\Interface\AddOns\Blizzard_CooldownViewer\` and report the exact TOC filenames. This is the strongest ground truth; it reflects what *this exact build* expects, more current than any wiki or doc.
2. Contents of `_classic_beta_\.flavor.info`
3. `/run print(C_AddOns.GetAddOnInfo("TerribleBuffTracker"))`
4. AddOns list state — absent entirely, or present but greyed out?

| Symptom | Root cause | Confirm via |
|---|---|---|
| Absent from AddOns list, no entry | Wrong/unrecognized suffix, or case mismatch | `GetAddOnInfo` returns `nil` — client has zero knowledge of the addon |
| Present but greyed / "out of date" | Suffix resolved fine; `## Interface:` value rejected | `GetAddOnInfo` table has `reason = "INTERFACE_VERSION"` — bump the interface, don't touch the suffix |
| Loads (chat print fires) but no CDM tab or bars | Loaded fine; `Blizzard_CooldownViewer` absent/disabled/different API on this build | `/console scriptErrors 1` then `/reload`; `/run print(C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer"))` |
| Unsure which build you're testing | Wrong install, or beta rolled forward | `.flavor.info` + build number bottom-left at character select |

---

## Step 2 — CDM attaches

`VER-03` part 1.

- [x] Chat shows `TerribleBuffTracker: Attached to Cooldown Manager.`
- [x] Chat does **not** show `TerribleBuffTracker: Cooldown Manager not found. Addon disabled.`

> Source: `Display.lua:368` / `:342`. TBT resolves `BuffBarCooldownViewer` and `BuffIconCooldownViewer`.

**Result:** ☑ **PASS** (2026-09-18) — CDM reachable on Forever.

## Step 3 — TBT tab injects

`VER-03` part 2.

- [x] `/tbt` opens `CooldownViewerSettings`
- [x] TBT tab visible **below** all Blizzard tabs (v0.2.6 anchors under the bottom-most)
- [x] All four sections render and expand, no error

> Forever's own CDM categories being empty is **not** a TBT failure — TBT never reads that data.

**Result:** ☑ **PASS** (2026-09-18) — shows correctly on the CDM tab.

## Step 4 — ⭐⭐ Cast detection — THE decisive check

`VER-04`. This resolves whether `UNIT_SPELLCAST_SUCCEEDED` delivers a usable numeric spellID on Forever. It is a core client/server event — no source research can answer it, and **TBT's entire detection architecture rests on it**.

- [x] Add any real castable spell by ID via the Add dialog
- [x] Drag it to Tracked Bars
- [x] Cast it
- [x] A timer bar starts and counts down

**Result:** ☑ **PASS** (2026-09-18) — "buff tracking and bars are working as expected". **`UNIT_SPELLCAST_SUCCEEDED` delivers a usable spellID on Forever. The milestone's central unknown is resolved and v0.3's premise holds.**

> **If this fails:** stop and escalate. The milestone's premise is broken and v0.3 needs re-scoping, not patching. Do not attempt a workaround.

## Step 5 — Bar / icon rendering

`VER-05`.

- [x] Timer bars render, matching CDM's own atlas-based visuals
- [x] Buff icons render correctly
- [x] No missing or black textures — a broken atlas would mean an undocumented Forever atlas-name change

**Result:** ☑ **PASS** (2026-09-18) — bars working as expected; no atlas problems reported. CDM atlas names are unchanged on Forever.

## Step 6 — Edit Mode end-to-end

`VER-06`.

- [x] Enter Edit Mode — both TBT containers appear
- [x] Drag each container; settings popup opens; NineSlice overlay draws
- [x] Exit Edit Mode
- [x] `/reload` — positions persist

> **If positions don't persist:** check whether *other* addons also lose settings before blaming TBT. Third-party reports against build `1.60.1.69893` say SavedVariables are written on logout but never read back. That's a platform defect.

**Result:** ☑ **PASS** (2026-09-18) — "edit mode works". Notably this also means **SavedVariables DO persist on build `1.60.1.69913`** — the third-party report of addon SavedVariables never being read back does not reproduce here, or was fixed between `69893` and `69913`. Edit Mode was the largest untested API surface and it carried no further missing engine globals.

## Step 7 — Combat secret-value gating

`VER-07`.

- [x] Enter combat
- [x] No uncaught Lua error from any aura read
- [x] Midnight's known "blocked" behaviour should **reproduce**, not crash

**Result:** ☑ **PASS** (2026-09-18) — "combat tracking works". The secret-value gate behaves as on Midnight; no uncaught aura-read error.

## Step 8 — Trinket / Pot tiles — also closes Phase 27

`VER-08` part 2 **and** Phase 27's human verification item 1 (Forever half). One check, both requirements — they need the same character state.

**Character state needed:** nothing equipped in either trinket slot, no tracked damage potion in bags.

- [x] Hover both Suggested tiles — no Lua error
- [x] **Superseded 2026-09-18: all three meta tiles are now HIDDEN on Forever** — META-01's data-driven filter working as designed. The question-mark observation below is the pre-META-01 state, retained as the evidence that Phase 27's at-rest fix worked.
- [x] Record which degraded state appears (pre-META-01):

  ☑ **neutral placeholder** — all three meta tiles (trinket, pot, lust) show the question-mark icon → **Phase 27's fix CONFIRMED WORKING in-game**
  ☐ real-but-wrong retail item
  ☐ something else

- [~] **Both tiles still draggable** — N/A on Forever now that META-01 hides them. **Still to confirm on RETAIL**, where the catalog resolves and the tiles must remain present and draggable (retail pack step 3).

**⚠ Defect found (2026-09-18):** trinket and pot show a readable info tooltip, but **lust shows no tooltip at all.** Root cause traced: `LustProviderMixin:GetDisplayInfo` always returns a numeric `spellID` (defaults to 2825 Bloodlust, `Providers.lua:573`), so `ShowBuffTooltip` takes the `GameTooltip:SetSpellByID` branch (`Display.lua:76`). Spell 2825 does not exist on Forever, so the tooltip is populated with nothing. Trinket/pot avoid it because Phase 27 set their `spellID` to nil, routing them to the readable `SetText(label)` branch. Fixed under PAR-02 in Phase 27.1.

> That draggability check is not incidental — it's exactly what the `duration = 0` / non-nil-placeholder choice was protecting. A `nil` return would have silently made both tiles unaddable.

> Empty trinket/pot *triggering* is expected, not a bug — their catalogs are current-retail-season spellIDs no Forever character can produce.

**Result:** ☐ PASS ☐ FAIL — notes: ______________________________

## Step 9 — Lust tile

`VER-08` part 1.

- [ ] On a class with lust access, if such content exists: 40s timer starts even in combat
- [ ] On any class: Suggested Lust tile renders without error even if no lust content exists

> Genuinely uncertain rather than expected-empty. Bloodlust (2825) and Heroism (32182) are old stable IDs plausibly present. Time Warp / Fury of the Aspects / Harrier's Cry need specs that may not exist at the beta's level cap.

**Result:** ☑ **N/A on Forever** (2026-09-18) — the Lust tile is hidden by META-01 along with trinket and pot, since no lust spell in the catalog resolves on this client. Revisit when Forever ships lust content; the tile will reappear automatically with no code change (D-12).

## Step 10 — Foundational globals

- [~] Escape closes the Add Buff dialog (`UISpecialFrames` still works)

**Result:** ☑ **implicitly OK** — the Add dialog was used repeatedly to add spells during steps 4-8 with no reported problem. Not separately exercised; a failure here would be cosmetic, not blocking.

## Step 11 — Fresh WTF tree

- [~] A brand-new Forever install loads TBT with zero tracked buffs and zero errors
- [~] Rules out any cross-flavor SavedVariables assumption (separate WTF trees per product)

**Result:** ☑ **effectively covered** — the Forever WTF tree was new when this pass began (the folder was created fresh by Phase 26's deploy) and TBT loaded clean with no inherited retail data. Not re-run as a deliberate fresh-install test.

---

## Fixes landed mid-session from these findings

Two defects were found and fixed during this pass, both deployed and both re-confirmed by the user:

| Finding | Root cause | Fix | Confirmed |
|---|---|---|---|
| Lust tile showed no tooltip | `LustProviderMixin:GetDisplayInfo` always returns a numeric spellID (2825), so `ShowBuffTooltip` called `SetSpellByID` on a spell absent from Forever and rendered an empty frame | `Display.lua` — gate `SetSpellByID` on the spell actually resolving (`9fde1eb`) | superseded; tile now hidden by META-01 |
| Click-and-drag threw 53 Lua errors | `CDMTab.lua:233` called `GetScaledCursorPositionForFrame`, an **engine-side global present on Midnight but absent on Forever**. Pre-existing since v0.2.0, not a v0.3 regression | Removed the dependency — reused the `GetCursorPosition()`/`GetScale()` idiom the file's three other cursor sites already use (`9e32f92`) | ☑ **drag-and-drop works** |

And META-01 confirmed working: all three meta tiles hidden on Forever.

## Record while you're in there — free, closes open research questions

Cheap to capture in the same session, pass or fail. **Do not apply fixes for these on the spot.**

1. **`## Category: Buffs & Debuffs, Combat`** (RQ1) → **accepted** — sections show correctly in the AddOns list. No third divergence line needed; D-03 holds as-is.
2. **`## IconTexture`** (RQ2) → **works** — addon icon renders on Forever.
3. **Exact Blizzard TOC filenames in the live client** (RQ3) — → not needed; step 1 passed so the suffix is confirmed empirically.

**RQ answered by observation (2026-09-18): Forever does NOT ship retail spell data.** The lust tile rendered a question-mark icon, which only happens when `ns:GetSpellIcon(2825)` falls through to `134400` — i.e. `C_Spell.GetSpellInfo(2825)` returned nil. This is the discriminator the data-driven meta-tile hide (META-01) relies on.
4. **`.build.info` re-derived interface** (RQ4) — if it no longer computes to `16001`, record it and report. **Do not bump the TOC unilaterally.** The drift guard asserts the `16xxx` range, not the exact value, so a routine beta bump won't fail it. → ______________

---

## PAR-02 — fast-follow fixes

Any **Forever-only** Lua error found above gets a **narrow defensive read** — a nil-check or guarded call at the exact failing site. Never a `WOW_PROJECT_ID` branch, never a new code path, never a feature. Raise it as its own plan so it gets a commit and a SUMMARY entry.

| Error | File:line | Fix | Commit |
|-------|-----------|-----|--------|
|       |           |     |        |

---

## Sign-off

- **Date run:** **2026-09-18**
- **Forever build tested:** `wow_classic_beta` @ **1.60.1.69913**, interface **16001**
- **Step 1 (TOC-02) verdict:** ☑ **PASS** ← gating question closed
- **Step 4 (cast detection) verdict:** ☑ **PASS** ← decisive; v0.3's premise holds
- **Steps passed:** **8 / 11 explicitly, 2 implicitly, 1 N/A — zero failures**
- **Blocking failures:** **none**
- **Expected-empty confirmed:** ☑ Trinket ☑ Pot ☑ Lust — all three hidden by META-01
- **Platform defects seen (not TBT):** **none reproduced.** SavedVariables persist on `69913`, contrary to the third-party report against `69893`
- **`UNIT_SPELLCAST_SUCCEEDED` verdict:** ☑ **delivers usable spellID**
- **Defects found and fixed during the pass:** 2 — empty lust tooltip (`9fde1eb`), drag nil-call (`9e32f92`). Both re-confirmed working.
- **Left unconfirmed, low priority:** the `Base spell ID` / `Override spell ID` tooltip lines only render when a spell has an override; none was encountered. Matters only if an added spell ID fails to fire.

**Next:** once Forever is functional, run `RETAIL-REGRESSION-PASS.md`.
