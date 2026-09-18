# Phase 25 In-Game Verification: Retail + Forever Load Gate

> **⚠ Superseded for execution.** The user tests Forever first, then checks retail for regressions —
> the reverse of this document's Section A → Section B order. **Run from the ordered run-sheets instead:**
> `.planning/testing/FOREVER-TEST-PASS.md` (first), then `.planning/testing/RETAIL-REGRESSION-PASS.md`.
> Section B is step 1 of the Forever pack; Section A is step 1 of the retail pack. Section D's failure
> protocol and triage table are reproduced in the Forever pack.
> This file remains the formal Phase 25 record for traceability.

**Status: NOT RUN — awaiting human**

No agent may fill in a result on this page. Every result field below ships empty. An automated
gate greps this file for any `PASS`/`FAIL` marking; if one is found where an agent could have
written it, the task that produced this file fails. Only a human who has actually launched both
game clients may fill in Section F.

**Build identifiers under test:**

| Flavor | Product | Build | Interface | TOC file |
|---|---|---|---|---|
| Midnight retail | `wow` | `12.1.0.69814` | `120100` | `TerribleBuffTracker_Mainline.toc` |
| WoW Forever beta | `wow_classic_beta` | `1.60.1.69893` | `16001` | `TerribleBuffTracker_Camelot.toc` |

If the build number you actually test against differs from the table above, record the build you
actually used in Section F's sign-off block — a PASS without a build number is not reproducible
information (PITFALLS.md pitfall 7).

---

## Section 0 — Deploy (both clients)

`scripts/install.bat` is **not yet flavor-aware**. Its `copy /Y "%SOURCE%TerribleBuffTracker.toc"`
line targets a file that no longer exists after Phase 25's rename (`TerribleBuffTracker.toc` →
`TerribleBuffTracker_Mainline.toc` + new `TerribleBuffTracker_Camelot.toc`), so running it today
prints one `The system cannot find the file specified` line and copies no TOC at all. Phase 26
fixes this properly (INST-04). Per D-10, this phase does not wait on that — deploy manually.

**Copy all ten files by hand** into each client's `Interface\AddOns\TerribleBuffTracker` folder:

- `TerribleBuffTracker_Mainline.toc`
- `TerribleBuffTracker_Camelot.toc`
- `Core.lua`
- `BuffEngine.lua`
- `Providers.lua`
- `EditModeFrames.lua`
- `Display.lua`
- `CDMTab.xml`
- `CDMTab.lua`
- `tbt_icon_64x64.blp`

**Both TOCs go into both clients.** The client itself picks which TOC to load based on its own
flavor — that is the entire point of the suffix mechanism. Do not try to be clever and only copy
one TOC per client.

**Deploy paths:**

- Retail: `%PROGRAMFILES(x86)%\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker`
- Forever: `%PROGRAMFILES(x86)%\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker`

### The false-pass trap — read this before launching anything

**The retail folder still contains a stale `TerribleBuffTracker.toc` from the last `install.bat`
run, from before the Phase 25 rename.** If that stale file is not deleted, the retail client will
happily load the addon from the *old unsuffixed TOC* and Gate 1 will appear to pass — while
proving absolutely nothing about whether `TerribleBuffTracker_Mainline.toc` actually works. This
is the single mistake that makes the whole gate worthless.

**Delete `TerribleBuffTracker.toc` from both client AddOns folders before launching either
client.** After deleting and copying the ten files above, open each client's
`Interface\AddOns\TerribleBuffTracker` folder and confirm it contains **exactly two `.toc`
files, both suffixed** (`TerribleBuffTracker_Mainline.toc` and `TerribleBuffTracker_Camelot.toc`)
— no unsuffixed `TerribleBuffTracker.toc` anywhere.

### Also note

The AddOns list will show the addon's version as the literal string `@project-version@` in a dev
copy deployed straight from the repo. That is the BigWigs packager's substitution keyword, not a
defect — it only gets replaced with a real version number by the packaged release build.

---

## Section A — Gate 1: retail (VER-01, TOC-01)

Criteria per D-15. This is the higher-consequence gate: it protects every existing retail user
against the Phase 25 rename silently breaking their install.

Steps, each with its expected result:

1. **Launch retail Midnight.**
2. At character select, open the AddOns list.
   - Expected: `TerribleBuffTracker` is present and **enabled** — not greyed out, not flagged
     "out of date."
3. **Log in** with any character.
   - Expected: the addon's normal `ADDON_LOADED` chat print fires (the existing, already-shipping
     "TerribleBuffTracker loaded..." line from `Core.lua` — this is a free, pre-existing smoke
     test, not new instrumentation).
4. Run `/tbt` (or `/terriblebufftracker`).
   - Expected: the Blizzard Cooldown Manager settings window opens with the TBT tab present.
5. Glance at the TBT tab's sections.
   - Expected: previously-tracked buffs are still listed.

**On step 5:** this is a confirmation glance, not a migration test. The Phase 25 rename touched
only the TOC filename — it never touched the addon folder name, and it never touched
`## SavedVariables: TerribleBuffTrackerDB`. The `WTF` SavedVariables path is therefore
structurally unchanged, and no dedicated SavedVariables migration test is warranted here (D-15).
If step 5 shows an empty list on a character that previously had tracked buffs, that is a real
finding — but the cause is very unlikely to be the TOC rename, given the reasoning above; note
whatever you observe in Section F regardless.

---

## Section B — Gate 2: Forever (TOC-02)

Scope per D-08 — this gate answers exactly one question: **does the Forever client read
`TerribleBuffTracker_Camelot.toc`?** Nothing more.

Steps:

1. **Before reloading**, run `/console scriptErrors 1` so any silent Lua failure surfaces as an
   on-screen dialog naming file and line, instead of failing invisibly.
2. **Launch the Forever beta client** (`_classic_beta_`).
3. At character select (or in the AddOns list), confirm `TerribleBuffTracker` **appears in the
   AddOns list**.
4. **Log in** with any character.
5. Confirm **no Lua error** appears at login.

**The entire pass bar for Gate 2, verbatim, do not widen it:** appears in the AddOns list and
loads with no Lua error at login.

Do not chase CDM tab visibility, SavedVariables behavior, or tile contents as part of Gate 2 —
see Section C below for why those are explicitly out of scope here.

---

## Section C — Explicitly NOT failures on Forever (D-09)

The following must be **recorded** (for Phase 28) but must **not** be treated as a Gate 2
failure. None of these are TOC problems; conflating them with a TOC suffix failure would send
the next session chasing the wrong file:

- The Cooldown Manager being unreachable, or the TBT tab being absent, on Forever.
- SavedVariables not persisting — a known defect on beta build `1.60.1.69893`.
- Empty Trinket, Pot, or Lust tiles.

**Why:** a Forever CDM/display problem is a Phase 28 finding. Gate 2 exists solely to prove the
suffix mechanism (`_Camelot.toc`) works — letting a CDM or display issue read as "the TOC suffix
is wrong" would misdirect the next session into trying a different suffix for a problem that has
nothing to do with the TOC at all.

---

## Section D — If Gate 2 fails (D-11)

**If TBT never appears in the Forever AddOns list: stop the phase and report to the user. Do not
work around it.**

Explicitly forbidden:

- Auto-trying `_Vanilla.toc`, `_Forever.toc`, or any other suffix.
- Falling back to a single unsuffixed TOC (also barred outright by REQUIREMENTS.md's Out of
  Scope table).
- Adding `## AllowLoadGameType` speculatively, on the theory that it might help.

**Before reporting, collect these four diagnostics, in this order:**

1. **The suffix Blizzard's own TOC files use inside the live client.** List
   `_classic_beta_\Interface\AddOns\Blizzard_CooldownViewer\` and report the exact TOC filenames
   found there. This is the strongest available ground truth — it reflects what *this exact
   installed build* actually expects, which is more current than any external doc or wiki page.
2. **The contents of `_classic_beta_\.flavor.info`.**
3. **The output of** `/run print(C_AddOns.GetAddOnInfo("TerribleBuffTracker"))`.
   - `nil` means the client has zero knowledge of the addon at all — a suffix or case mismatch.
   - A table with `reason = "INTERFACE_VERSION"` means the suffix resolved correctly but the
     `## Interface:` value itself was rejected — a different fix entirely (bump the interface
     number, don't touch the suffix).
4. **The AddOns list state** — is the addon absent entirely, or present but greyed out?

**Symptom → cause → confirmation triage table** (reproduced from PITFALLS.md pitfall 3, so this
can be read without reopening the research doc under pressure):

| Symptom | Root cause | How to confirm |
|---|---|---|
| Addon absent from AddOns list entirely, no entry at all | Wrong/unrecognized TOC suffix, or case mismatch | `/run print(C_AddOns.GetAddOnInfo("TerribleBuffTracker"))` returns `nil` — the client has zero knowledge of the addon |
| Addon present in AddOns list but grayed out / shows "out of date" | Suffix resolved correctly, but `## Interface:` value rejected | `C_AddOns.GetAddOnInfo("TerribleBuffTracker")` returns a table whose `reason` field is `"INTERFACE_VERSION"`; also check the account setting "Load out of date AddOns" |
| Addon loads (chat print from `Core.lua`'s `ADDON_LOADED` handler appears), but CDM tab / bars never appear | Loaded fine; `Blizzard_CooldownViewer` absent, disabled, or exposes a different API surface on this build | Run `/console scriptErrors 1` **before** reload, then `/reload` — a real Lua error surfaces as an on-screen dialog naming file/line; separately, `/run print(C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer"))` |
| Uncertain which flavor/build you're even testing | Wrong install targeted, or beta build rolled forward | Read the `.flavor.info` file in the install root (e.g. `_classic_beta_\.flavor.info`) and the build number shown bottom-left on the character-select screen; cross-check against the interface number in `_Camelot.toc` |
| Uncertain what suffix/interface *this exact beta build* expects | Convention assumptions (wiki, packager docs) can lag the live build | Open Blizzard's own shipped TOCs for that install, e.g. `_classic_beta_\Interface\AddOns\Blizzard_CooldownViewer\Blizzard_CooldownViewer*.toc` — whatever suffix and interface number Blizzard's own bundled addon uses for that exact build is ground truth, more current than any external doc |

**Then ask the user which suffix to try next.** Do not decide unilaterally.

---

## Section E — Observations to record while in there (free, closes open research questions)

Cheap to capture during the same session as Gate 1/Gate 2, whether they pass or fail:

1. **Does Forever render `## Category: Buffs & Debuffs, Combat` sensibly, or show the addon as
   uncategorised?** (Research question 1, bears on D-03.) If Forever rejects it, adding a third
   allowlisted divergence line between `_Mainline.toc` and `_Camelot.toc` is a decision for the
   user to make later — do not apply a fix on the spot.
2. **Does the `## IconTexture` icon render on Forever?** (Research question 2.) Cosmetic only,
   but knowing this beforehand stops a missing icon from being misread as a load failure during
   later Forever work.
3. **The exact Blizzard TOC filenames in the live client** (research question 3) — useful to
   record even on a full PASS, as a standing cross-check for future beta builds.
4. **The version string in `_classic_beta_\.build.info`, re-derived to an interface number** via
   `major . zero-pad-2(minor) . zero-pad-2(patch)` (research question 4). If it no longer
   computes to `16001`, record the new value and report it — **do not bump the TOC unilaterally.**
   The drift guard (`scripts/check-toc.ps1`) asserts the `16xxx` range, not the exact value, so a
   routine beta bump will not fail it.

---

## Section F — Results

| Check | Expected | Result | Notes |
|---|---|---|---|
| Gate 1 — AddOns list entry | Present, enabled, not "out of date" | | |
| Gate 1 — ADDON_LOADED chat print | Fires on login | | |
| Gate 1 — `/tbt` opens CDM tab | TBT tab visible in CDM settings | | |
| Gate 1 — previously-tracked buffs still listed | List matches pre-rename state | | |
| Gate 2 — AddOns list entry | Present | | |
| Gate 2 — Lua errors at login | None | | |
| Section E — `## Category` rendering on Forever | Recorded, not gating | | |
| Section E — `## IconTexture` rendering on Forever | Recorded, not gating | | |
| Section E — live Blizzard TOC suffix/interface | Recorded, not gating | | |
| Section E — `.build.info` re-derived interface | Recorded, not gating | | |

### Sign-off

- **Date run:** _______________
- **Client builds actually tested:** retail `wow` @ _______________ / Forever `wow_classic_beta` @ _______________
- **Gate 1 verdict:** _______________
- **Gate 2 verdict:** _______________
- **Observations:** _______________

**Ordering correction (supersedes the original D-06 sequencing).** This document was written assuming
retail is gated first. The user tests Forever first, then retail — that is their only available option.
Consequences:

- **Phases 26 and 27 are no longer blocked on these verdicts, and both have already landed.** Phase 26
  became a *prerequisite* rather than a dependent: `install.bat` referenced the deleted unsuffixed TOC
  after the rename, so until it was fixed neither client could be deployed to at all.
- **Phase 29 remains blocked**, and is outside the current `--to 28` run regardless.
- **TOC-02 stays owned by Phase 25** (D-07 unchanged) — it is step 1 of the Forever run-sheet.
- The retail-first safety rationale is partly substituted by a desk-level proof recorded in
  `.planning/testing/RETAIL-REGRESSION-PASS.md`: git shows the rename was byte-for-byte
  content-preserving, so retail reads a file whose contents never changed.
