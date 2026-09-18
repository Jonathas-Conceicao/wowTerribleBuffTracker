# Retail Regression Pass — run SECOND

**Status: ✅ PASSED — 2026-09-18.** Both caveats resolved.

- The stale unsuffixed `TerribleBuffTracker.toc` was deleted from `_retail_` and retail confirmed loading from `TerribleBuffTracker_Mainline.toc`. Verified on disk: the folder now holds one TOC, the suffixed one. `VER-01` / `TOC-01` genuinely proven.
- **META-01 confirmed in the retail direction: all three meta tiles are present.** The catalog test is correct in both directions — hidden on Forever where nothing resolves, present on retail where it does. This was the milestone's only destructive-risk item and it is closed.

Note for future deploys: `install.bat` will restore `_Camelot.toc` to the retail folder on its next run, by design — it copies both TOCs to every client and the client ignores the one whose flavour does not match. Harmless.

---

## Desk-level safety proof — already done, no client needed

Before you spend a session on this, here's what's already established from git. Retail reads a file whose **contents never changed**:

| Check | Evidence | Result |
|---|---|---|
| Was the rename content-preserving? | `git log --stat 9054dd7` → `1 file changed, 0 insertions(+), 0 deletions(-)` | ✓ pure rename |
| Is `_Mainline.toc` byte-identical to the old `TerribleBuffTracker.toc`? | `git diff 9054dd7~1:TerribleBuffTracker.toc 9054dd7:TerribleBuffTracker_Mainline.toc` → empty output | ✓ identical |
| Does `_Camelot` differ only on the two allowlisted lines? | `diff` → exactly `## Interface:` and `## Notes:` | ✓ D-01 holds |
| Is the suffix capitalisation right in the commit? | `git ls-files` → `TerribleBuffTracker_Camelot.toc` | ✓ capital C |

So the retail TOC's content, `## SavedVariables: TerribleBuffTrackerDB`, and the addon folder name are all unchanged. Only the filename gained a documented suffix. **Recovery, if needed:** the rename is a one-command git revert.

This pass is confirmation, not discovery. It should be quick.

---

## Build under test

| Flavor | Product | Expected build | Interface | TOC file |
|---|---|---|---|---|
| Midnight retail | `wow` | `12.1.0.69814` or later | `120100` | `TerribleBuffTracker_Mainline.toc` |

- Build actually tested: `________________`
- Date: `________________`

---

## Before you launch

**1. Deploy.** `./scripts/install.bat` — no arguments. Already done if you ran it for the Forever pass; it deploys to every client present in one pass.

**2. ⚠ Delete the stale unsuffixed TOC — CONFIRMED PRESENT as of 2026-09-18.**

This is not hypothetical. The retail folder was inspected after Phase 26's deploy and currently holds **three** TOC files:

```
_retail_\Interface\AddOns\TerribleBuffTracker\
  TerribleBuffTracker.toc           ← STALE, pre-rename. DELETE THIS.
  TerribleBuffTracker_Mainline.toc  ← correct
  TerribleBuffTracker_Camelot.toc   ← correct
```

**If the stale one survives, retail loads from it and every check below passes while proving nothing about `_Mainline.toc`.** That is the one mistake that makes this pass worthless.

```
del "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker\TerribleBuffTracker.toc"
```

It was deliberately left in place rather than deleted for you: if `_Mainline.toc` turns out not to load, the stale TOC is what keeps your retail addon working, and removing it unattended would have broken retail with nobody watching. Delete it when you're at the keyboard and ready to test.

- [~] `_retail_\Interface\AddOns\TerribleBuffTracker\` contains **exactly two `.toc` files, both suffixed** — **NOT DONE as of 2026-09-18**; all three TOCs were present during the general retail test. See caveat 1 at the top.

**Also present — stale cruft, harmless but worth knowing:** `ConfigUI.lua` (removed from the repo in v0.2.0 Phase 3) and `tbt_icon_64x64.png`. Neither is in either TOC's load list, so neither loads. `install.bat` copies but never prunes, so every file ever deleted from the repo lingers in a deployed folder. Not a blocker for this pass; logged as a backlog item.

> The Forever folder (`_classic_beta_`) was verified **clean** — exactly 10 files, exactly 2 suffixed TOCs, no stale unsuffixed TOC and no cruft. Nothing to delete there.

Cosmetic non-issue: version shows as `@project-version@` in a dev copy — packager keyword, not a defect.

---

## Step 1 — Loads from `_Mainline.toc` ⭐ GATING

`VER-01` / `TOC-01`. This is the high-consequence check — it protects every existing retail user.

- [ ] At character select, AddOns list shows `TerribleBuffTracker` **present and enabled** — not greyed out, not flagged "out of date"
- [ ] Log in — chat prints `TerribleBuffTracker loaded. Type /tbt or /terriblebufftracker to open settings.`
- [ ] No Lua error at login
- [ ] `/tbt` opens the Cooldown Manager settings window with the TBT tab present

**Result:** ☐ PASS ☐ FAIL — notes: ______________________________

## Step 2 — SavedVariables continuity

- [ ] TBT tab sections still list your previously-tracked buffs

> A confirmation glance, not a migration test. The rename touched only the TOC filename — never the addon folder name, never `## SavedVariables:`. The `WTF` path is structurally unchanged. If this shows empty on a character that had tracked buffs, record it — but the TOC rename is a very unlikely cause given the desk proof above.

**Result:** ☐ PASS ☐ FAIL — notes: ______________________________

## Step 3 — Trinket / Pot tiles on retail — closes Phase 27

Phase 27's human verification item 1, retail half. Same check as the Forever pack's step 8, different client — Phase 27's fix is flavor-agnostic and must behave identically on both.

**Character state needed:** nothing equipped in either trinket slot, no tracked damage potion in bags.

- [ ] Hover both Suggested tiles — no Lua error
- [ ] Record which state appears:

  ☐ **neutral placeholder** — question-mark icon, generic `Trinket` / `Damage Pot` label → **expected**
  ☐ **real-but-wrong retail item** — e.g. "Light Company Guidon" → **fix didn't take effect, report**

- [ ] Both tiles still draggable out of Suggested into a Bars/Buffs section

> This is the one place v0.3 deliberately **changed** retail behaviour. Before the fix, an empty-bags alt saw a real retail item's icon and name it couldn't obtain; now it should see a neutral placeholder. Both states are "no crash" — you're confirming *which*.

**Result:** ☐ PASS ☐ FAIL — notes: ______________________________

## Step 4 — No regression spot-check

Everything below shipped working in v0.2.6 and v0.3 should not have touched it. Quick confirmation only — Phase 27 changed one file (`Providers.lua`) and nothing else functional.

- [ ] Cast a tracked spell — timer bar starts and counts down normally
- [ ] Bars and icons render as they did before (CDM atlas visuals intact)
- [ ] Edit Mode: enter/exit, drag a container, settings popup opens, position persists across `/reload`
- [ ] Enter combat — no new Lua error
- [ ] Lust tile behaves as it did in v0.2.6

**Result:** ☐ PASS ☐ FAIL — notes: ______________________________

---

## If Step 1 fails

Unlikely given the desk proof, but if retail doesn't load:

1. **First suspect the stale TOC, inverted** — did you delete `TerribleBuffTracker.toc` but the deploy didn't place `TerribleBuffTracker_Mainline.toc`? Check the folder holds both suffixed TOCs.
2. `/run print(C_AddOns.GetAddOnInfo("TerribleBuffTracker"))`
   - `nil` → client has no knowledge of the addon; suffix or case problem
   - table with `reason = "INTERFACE_VERSION"` → suffix resolved, `## Interface: 120100` rejected; check "Load out of date AddOns"
3. Compare against Blizzard's own TOC filenames in `_retail_\Interface\AddOns\Blizzard_CooldownViewer\`
4. **Recovery:** `git revert 9054dd7` restores the unsuffixed TOC. Report before doing it — the finding matters more than the quick fix.

---

## Sign-off

- **Date run:** _______________
- **Retail build tested:** `wow` @ _______________
- **Step 1 (VER-01) verdict:** _______________ ← gating
- **Step 2 (SavedVariables) verdict:** _______________
- **Step 3 (Phase 27 retail half) verdict:** _______________
- **Step 4 (regression spot-check) verdict:** _______________
- **Regressions found:** _______________

**On all PASS:** `VER-01`, `TOC-01` and `PAR-01`'s observable half are closed. Phases 25 and 27 can move to fully verified, and the milestone advances to Phase 29 (Packaging & Distribution) — which is outside the current `--to 28` run.
