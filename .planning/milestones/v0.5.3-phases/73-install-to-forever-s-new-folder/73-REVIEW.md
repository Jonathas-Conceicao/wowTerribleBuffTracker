---
phase: 73-install-to-forever-s-new-folder
reviewed: 2026-10-22T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - scripts/install.ps1
  - CLAUDE.md
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase 73: Code Review Report

**Reviewed:** 2026-10-22
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

The diff (`ebd2b83..HEAD`) changes one line in each file: `'_classic_beta_'` becomes `'_forever_'` in `$flavors` (install.ps1:29), and the CLAUDE.md "One TOC, all flavours" bullet now names `_forever_` / `wowf` / build 1.60.1.70532. The edit is mechanically correct. Both files are `w/crlf`, and the rest of the deploy and prune logic is unchanged.

The phase assumes `wowf` *replaced* `wow_classic_beta`. The machine contradicts that. The root `.build.info` lists **both** products as active (`Active=1`), on the same build:

```
us 1  1.60.1.70532 wow_classic_beta
us 1  1.60.1.70532 wowf
```

`_classic_beta_\WowB.exe` and `.flavor.info` were updated at 17:34 today, which is after `_forever_` was installed at 12:41. `_classic_beta_\Interface\AddOns\TerribleBuffTracker` still holds a deployment whose TOC reads `## Version: v0.5.1-117-g3668e75-dev`, with `## Interface: 120100, 16001`. That interface matches the beta client, so it still loads there.

## Warnings

### WR-01: A live client with a stale TBT copy is silently dropped from deploys

**File:** `scripts/install.ps1:29` (also the header claim at line 1)
**Issue:** `_classic_beta_` is still an installed, active, patched-today product (`wow_classic_beta`, 1.60.1.70532). Removing it from `$flavors` does not retire it. It freezes TBT there at `v0.5.1-117-g3668e75-dev`. The script prints no message about the folder, so this is invisible: the SUMMARY's "Real install.bat run" confirms there was no `_classic_beta_` line at all. If anyone launches the beta client (the Battle.net launcher can still select it), they test old code. The version string looks like a real dev build, so they have no reason to suspect it. This is exactly the "deployed folder is an honest picture of the current source" guarantee the script header promises (INST-07/08). The script's first line also now says it deploys to "every WoW client folder present on the machine", which is false.

The phase decision "nothing already deployed there was deleted" acknowledges the stale copy but does not address it.
**Fix:** Pick one of these:
1. Keep deploying to both while both products are active (the safest option, since it costs nothing when the folder is absent):
   ```powershell
   $flavors = @('_retail_', '_ptr_', '_beta_', '_forever_', '_classic_beta_', '_classic_', '_classic_era_', '_classic_ptr_')
   ```
2. If `_classic_beta_` is meant to be retired, warn loudly when a TBT folder exists under a client not in `$flavors`:
   ```powershell
   foreach ($d in Get-ChildItem -LiteralPath $wowRoot -Directory -Filter '_*_') {
       if ($flavors -notcontains $d.Name -and (Test-Path -LiteralPath (Join-Path $d.FullName 'Interface\AddOns\TerribleBuffTracker'))) {
           Write-Host "WARNING: $($d.Name) has a TerribleBuffTracker install this script no longer updates - it is stale"
       }
   }
   ```
   With option 2, also delete the stale `_classic_beta_` copy by hand.

## Info

### IN-01: CLAUDE.md implies `wow_classic_beta` is gone

**File:** `CLAUDE.md:13`
**Issue:** The bullet rewrite drops every mention of `wow_classic_beta` / `_classic_beta_`. A future reader will think Forever has one install folder. In fact two products coexist on the same build (see WR-01), and one of them keeps a TBT copy the installer no longer updates.
**Fix:** Add a clause such as: "the old `wow_classic_beta` product (`_classic_beta_`) is still offered on the same build; install.ps1 [does / does not] deploy there." Match it to whichever WR-01 option you take.

### IN-02: The pinned build number will drift

**File:** `CLAUDE.md:13`
**Issue:** "build 1.60.1.70532" is a point-in-time fact inside a standing project instruction. The previous text pinned 69913, and this phase had to correct it. `interface 16001` also repeats the `## Interface: 120100, 16001` given earlier in the same sentence.
**Fix:** Write "build 1.60.1.x (70532 as of 2026-10-22)", or drop the build number and keep the product and folder names, which are the facts the installer relies on.

---

_Reviewed: 2026-10-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

## Resolution (orchestrator, 2026-10-22)

- **WR-01 — declined by user decision.** At kickoff the user asked for install scripts to target
  `_forever_` "instead of `_classic_beta_`". Re-adding `_classic_beta_` would reverse a locked
  decision, so no auto-fix was run. The stale `_classic_beta_` copy is noted for the user in the
  Phase 78 testing checklist (they may delete it by hand).
- **IN-01, IN-02 — left as written.** Wording nits in CLAUDE.md; the bullet names the product the
  user installs to.
