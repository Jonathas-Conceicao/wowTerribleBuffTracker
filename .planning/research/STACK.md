# Stack Research

**Domain:** WoW addon cross-flavor packaging — one TerribleBuffTracker (TBT) package for WoW Midnight retail (120100) and WoW Forever beta (camelot / 16001)
**Researched:** 2026-09-18

> ### ⚠ Partly superseded — 2026-09-19
>
> The assumption in the `## AllowLoadGameType` row below — *"each file is only ever discovered under
> its own flavor already"*, recorded at MEDIUM confidence — **is contradicted by the WoWUI community
> FAQ**, which states Forever is classed as `mainline` intentionally, so `_Mainline.toc` **also loads on
> Forever**. The MEDIUM confidence was the right call.
>
> Read `FOREVER-COMMUNITY-FAQ.md` in this directory alongside this file. Tracked as backlog Phase 999.3.
> Nothing else in this document is known to be affected, and the published zips are unaffected because
> each carries only one TOC.

**Confidence:** HIGH on interface numbers, TOC suffix, and packager mechanics (multiple independent, cross-corroborating sources including a live API and Blizzard's own shipped TOC files). MEDIUM on CurseForge-site specifics not reachable without an authenticated API call. Items that can only be settled in-game are marked UNVERIFIED with an exact verification procedure — the user has Forever beta access.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| WoW client TOC flavor-suffix system | `_Mainline.toc` / `_Camelot.toc` | Client-native mechanism that lets one addon folder serve multiple game clients | This is how the WoW client itself — not just the packager — decides which TOC to load per install. It requires zero runtime code changes and matches the user's locked decision (physical split TOCs, not a generated/multi-interface single TOC). VERIFIED — warcraft.wiki.gg TOC_format page, quoted verbatim below. |
| `## Interface: 120100` | Midnight retail | Interface number for the `_Mainline.toc` | VERIFIED — already shipping in `TerribleBuffTracker.toc` line 1, and matches the `12.1.0.69814` build reported in the user's `wow` product `.build.info` via the formula in "Version Compatibility" below. |
| `## Interface: 16001` | WoW Forever beta | Interface number for the `_Camelot.toc` | VERIFIED — two independent derivations agree: (a) user's own `.build.info` shows `wow_classic_beta` at version `1.60.1.69893`; (b) BigWigsMods/packager's own version→interface formula (`printf "%d%02d%02d" 1 60 1` → `16001`). Cross-checked again against three separate WoWUI `forever-beta` commit messages (`1.60.1.69913`, `1.60.1.69893`, `1.60.1.69876`) — minor version has stayed `60.1` across at least 3 beta builds, so 16001 is stable, not a moving target. |
| BigWigs Packager (`BigWigsMods/packager@v2`) | already pinned in `.github/workflows/release.yml` | Builds the release zip and (when enabled) uploads to CurseForge/Wago/GitHub | No version bump or config change needed — the packager already auto-discovers `_Mainline`/`_Camelot`-suffixed TOC files by brace-expanding the `package-as` name. VERIFIED by reading `release.sh` source (see citations). |

### Supporting Libraries

None. TBT uses no external Lua libraries today and this milestone must not introduce any (see "What NOT to Add"). The only "supporting" pieces are the two authoritative version-lookup surfaces used to derive/re-verify interface numbers over time:

| Source | Purpose | When to Use |
|--------|---------|-------------|
| `https://addons.wago.io/api/data/game` | Live, unauthenticated JSON of every flavor's current patch version, live patch, and accepted TOC suffixes | Re-derive/re-verify the Forever interface number and accepted suffixes whenever Forever leaves beta or bumps a minor version |
| Local `.build.info` (`World of Warcraft\.build.info` and `_classic_beta_\.build.info`) | Ground-truth installed build version per product, no network needed | Fastest local check before every release; also drives `install.bat`'s per-client detection |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `scripts/install.bat` | Copies the shared file set into every present client's AddOns folder | Needs no per-flavor file-picking logic — both TOC files travel together in the same folder; the WoW client (not the installer) decides which one to read. Detection should key off folder existence: `%PROGRAMFILES(x86)%\World of Warcraft\_retail_` and `...\_classic_beta_`. |
| `stylua` | Lua formatting | Unaffected — no Lua changes in this milestone. |
| GitHub Actions (`BigWigsMods/packager@v2`) | CI packaging/release | Unaffected — no new inputs/flags required (see Packaging section). |

## Critical Finding: `_Camelot.toc` Is Correct, `_Vanilla.toc` Would Be Wrong

This is the answer to the milestone's central blocking question.

**Verdict: `TerribleBuffTracker_Camelot.toc` is correct. Do not use `_Vanilla.toc`.**

The apparent ambiguity in the milestone brief — Forever ships under the `wow_classic_beta` product/`_classic_beta_` folder, which historically hosted Classic Era (`vanilla`) betas — is a red herring. The WoW client's TOC-flavor selection is driven by an internal **game-type token compiled into the client build**, not by the Battle.net product string or install folder name. That token is `camelot`, independently of which product/folder Blizzard chose to ship the beta under.

Evidence, from four independent sources that all agree with zero contradiction found:

1. **Blizzard's own shipped TOC files** (primary, most authoritative — this is literally what the client's own bundled addons declare) — VERIFIED by direct fetch:
   `Interface/AddOns/Blizzard_CooldownViewer/Blizzard_CooldownViewer.toc` on `BigWigsMods/WoWUI` branch `forever-beta`:
   ```
   ## Title: Blizzard_CooldownViewer
   ## AllowLoadGameType: standard, camelot
   ```
   `Interface/AddOns/Blizzard_EditMode/Blizzard_EditMode.toc` (same branch) also gates multiple files with `[AllowLoadGameType camelot]` / `[AllowLoadGameType standard, camelot, mists]`. Blizzard never writes `vanilla` for Forever anywhere in these files.

2. **warcraft.wiki.gg, "TOC format" page** (community-maintained but the standing authoritative reference for TOC mechanics) — VERIFIED by direct fetch, quoted verbatim:
   > "Addons can ship multiple `.toc` files with different filename suffixes tailored for individual clients. The WoW client first searches for the special file names as shown below, and if none are found, uses `AddonName.toc`"

   | Game Type | Expansion/Mode | Suffix |
   |---|---|---|
   | `camelot` | Forever | `AddonName_Camelot.toc` |
   | `vanilla` | World of Warcraft Classic | `AddonName_Vanilla.toc` |
   | `mainline` | Midnight, Modern modes, **and Forever** | `AddonName_Mainline.toc` |

   > "The `_Mainline` and `_Classic` suffixes have a lower priority than other suffixes that target specific expansions/modes."

   This table is decisive: `_Vanilla.toc` is explicitly reserved for the original Classic Era product, a completely different game type from Forever. `_Camelot.toc` is Forever's dedicated, highest-priority suffix. `_Mainline.toc` is also technically legal on Forever (see Fallback below) but is lower priority and is Midnight's own primary file — reusing it for Forever would collide with TBT's Midnight TOC.

3. **BigWigsMods/packager `release.sh`** (the tool already wired into `release.yml`) — VERIFIED by reading source:
   ```bash
   # interface-number prefix -> game type
   16???) game_type="forever" ;;
   # game-type token -> packager's internal flavor id
   declare -A game_flavor=( ... ["forever"]="forever" ["camelot"]="forever" ... )
   # TOC filename suffix regex the packager itself recognizes
   "$package_name"[-_](Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot)\.toc$
   # when packager auto-generates split files from a single multi-interface TOC (a path this project is NOT using):
   forever) new_file+="_Camelot.toc" ;;
   ```
   The packager never emits or recognizes `_Forever.toc` (only Wago's uploader accepts that as an alias, see below) or `_Vanilla.toc` for game type `forever`.

4. **Wago.io's own live public API** (`https://addons.wago.io/api/data/game`, unauthenticated, queried live during this research) — VERIFIED, raw response excerpt:
   ```json
   "patches": { "forever": ["1.60.1"], "classic": ["1.15.9", ...] },
   "toc_suffixes": {
     "forever": ["-Camelot", "_Camelot", "-Forever", "_Forever"],
     "classic": ["-Classic", "_Classic", "-Vanilla", "_Vanilla"]
   },
   "live_patches": { "supported_forever_patches": "1.60.1", ... }
   ```
   Wago treats `forever` and `classic`/`vanilla` as two entirely separate patch families with disjoint suffix lists. `_Camelot`/`_Forever` are Wago's accepted spellings for Forever; `_Vanilla` is exclusively Classic Era's.

5. **Third-party corroboration** — `McTalian-WoW-Addons/wow-build-tools` PR #245 ("add Titan flavor, Camelot TOC suffix and confirmed install dirs") independently confirms the same mapping (Forever → `_Camelot.toc`, interface range 16000–16001, install dir `_classic_beta_` during beta) after the author says they "confirmed install directories by examining each product's TACT configuration" rather than guessing. MEDIUM confidence (secondary tool, but methodology and conclusion match the primary sources exactly).

### How to verify this in-game (the user has Forever beta access)

1. Build the addon folder with **both** `TerribleBuffTracker_Mainline.toc` (Interface 120100) and `TerribleBuffTracker_Camelot.toc` (Interface 16001) present, plus the shared `.lua`/`.xml` files.
2. Copy that one folder, unmodified, into `_classic_beta_\Interface\AddOns\TerribleBuffTracker\` (the same folder — do not strip either TOC file; the client picks).
3. Launch Forever beta. Open the in-game AddOns list (character-select "AddOns" button, or `/reload` + Game Menu → AddOns in Midnight-style UI) and confirm TerribleBuffTracker is listed as enabled, not "Load out of date" / not red.
4. Run `/tbt` and confirm the CDM tab injects with no Lua errors (`/console scriptErrors 1` beforehand to surface silent failures).
5. Optional stronger proof of *which* TOC loaded: temporarily add a distinguishing `## Notes:` string only to `_Camelot.toc` (e.g. `## Notes: TBT [CAMELOT BUILD]`) and check the AddOns list description text in the Forever client — if it shows the Camelot-only string, `_Camelot.toc` was the one read. Revert the Notes line afterward.

### Fallback if `_Camelot.toc` somehow doesn't load on a future Forever build

Because the wiki table explicitly lists `_Mainline.toc` as also valid for Forever (lower priority than `_Camelot.toc`, but valid), the safe fallback — if a future Forever client build stops recognizing `_Camelot.toc` for any reason — is:

- Add `16001` to a comma-separated `## Interface:` list inside `_Mainline.toc` (e.g. `## Interface: 120100, 16001`) as a belt-and-suspenders safety net, so Forever falls through to the Mainline file if Camelot-suffix detection ever regresses.
- Do **not** fall back to `_Vanilla.toc` — every source above agrees that suffix targets a different, unrelated product (Classic Era) and would not resolve a Camelot-detection failure; it would simply not be read at all.
- This fallback is precautionary only — nothing in current evidence suggests `_Camelot.toc` will fail. Don't implement it speculatively; keep it documented here for if in-game verification (step 3 above) ever fails.

## TOC Directives — What Differs Per Flavor

Reading `TerribleBuffTracker.toc` (current, single-flavor) against the requirements for a two-flavor split:

| Directive | Midnight (`_Mainline.toc`) | Forever (`_Camelot.toc`) | Notes |
|---|---|---|---|
| `## Interface` | `120100` (unchanged) | `16001` (new) | Only required per-flavor difference. VERIFIED both numbers above. |
| `## Title` | `TerribleBuffTracker` | `TerribleBuffTracker` (identical) | No client or store reason to differ; CurseForge/Wago group both TOCs under one project via the shared `X-Curse-Project-ID` / `X-Wago-ID`, so a mismatched title would look like a bug, not a feature. |
| `## Notes` | unchanged | unchanged (or flavor-tagged only for the in-game verification step above, then reverted) | Cosmetic only. |
| `## Author` / `## Version` / `## URL` | unchanged | unchanged | `## Version: @project-version@` is filled in by the packager identically for every TOC file it packages — VERIFIED (`release.sh` applies the same `{project-version}` substitution per discovered TOC, no per-flavor version scheme unless the project opts into `-classic`/`-forever` tag suffixes, which TBT does not use). |
| `## Category` | `Buffs & Debuffs, Combat` | `Buffs & Debuffs, Combat` (identical) | The packager never parses or validates `## Category` (confirmed absent from `release.sh` entirely — it's a pure pass-through site metadata field for CurseForge/Wago). No evidence category taxonomy differs for Forever; CurseForge's category list is a single, flavor-independent taxonomy (MEDIUM confidence — not contradicted anywhere, but not explicitly confirmed Forever-specific by an official source). |
| `## IconTexture` | unchanged | unchanged | Purely a client-rendered path to the `.blp`; no flavor gating exists for this directive in any source reviewed. |
| `## SavedVariables` | `TerribleBuffTrackerDB` | `TerribleBuffTrackerDB` (identical) | Keeping the same SavedVariables name is deliberate and required — Forever and Midnight are separate WTF folders per install, so there's no cross-flavor collision risk, and using the same name matches the existing `Migration: Must not break existing TerribleBuffTrackerDB data` constraint if the same account ever plays both flavors. |
| `## AllowLoadGameType` | not required | not required | Filename suffix alone is what the client uses to select which TOC to read (see Critical Finding above) — `AllowLoadGameType` is a *second*, independent gate Blizzard uses internally for **single**-TOC bundled addons that must load across multiple game types without duplicate files (e.g., `CooldownViewer.toc` loading under both `standard` and `camelot` from one file). Since TBT is deliberately using **two physical files** instead, each file is only ever discovered under its own flavor already — adding `AllowLoadGameType: standard` to `_Mainline.toc` or `AllowLoadGameType: camelot` to `_Camelot.toc` would be redundant, not harmful. MEDIUM confidence this is optional rather than required — the wiki page describes the two mechanisms (suffix search, and the directive) independently without an explicit cross-reference stating the directive is skippable when suffixes are used; every other suffix-based multi-flavor addon on CurseForge (the standard, long-established pattern predating `AllowLoadGameType`) ships without it, which is strong indirect evidence it's optional. Flag as unnecessary to add for this milestone; can be revisited if in-game testing (verification step 3) surfaces a load failure. |

No directive is unsupported on Forever in anything reviewed — Forever runs the same modern TOC parser as Midnight (they share the "standard vs. classic-family vs. camelot" AllowLoadGameType vocabulary in the same Blizzard TOC files), unlike the old, more limited Classic Era TOC parser.

## Installation

Exact target file contents (for the executor phase — no packager or workflow changes required):

**`TerribleBuffTracker_Mainline.toc`** (rename of current `TerribleBuffTracker.toc`, only the filename and Interface value change — Interface value itself is unchanged):
```
## Interface: 120100
## Title: TerribleBuffTracker
## Notes: Manual buff/cooldown timer tracking for WoW Midnight
## Author: Jonathas-Conceicao
## Version: @project-version@
## URL: https://github.com/Jonathas-Conceicao/wowTerribleBuffTracker.git
## Category: Buffs & Debuffs, Combat
## X-Curse-Project-ID: 1480617
## X-Wago-ID: 5NR8YzK3
## IconTexture: Interface\AddOns\TerribleBuffTracker\tbt_icon_64x64
## SavedVariables: TerribleBuffTrackerDB

Core.lua
BuffEngine.lua
Providers.lua
EditModeFrames.lua
Display.lua
CDMTab.xml
```

**`TerribleBuffTracker_Camelot.toc`** (new file, identical file list, only `## Interface` and `## Notes` differ):
```
## Interface: 16001
## Title: TerribleBuffTracker
## Notes: Manual buff/cooldown timer tracking for WoW Forever
## Author: Jonathas-Conceicao
## Version: @project-version@
## URL: https://github.com/Jonathas-Conceicao/wowTerribleBuffTracker.git
## Category: Buffs & Debuffs, Combat
## X-Curse-Project-ID: 1480617
## X-Wago-ID: 5NR8YzK3
## IconTexture: Interface\AddOns\TerribleBuffTracker\tbt_icon_64x64
## SavedVariables: TerribleBuffTrackerDB

Core.lua
BuffEngine.lua
Providers.lua
EditModeFrames.lua
Display.lua
CDMTab.xml
```

`.pkgmeta` and `.github/workflows/release.yml`: **no changes required.** VERIFIED by reading `release.sh`'s TOC-discovery loop, which brace-expands `package-as` (`TerribleBuffTracker`) against every known suffix including `-Camelot`/`_Camelot` automatically:
```bash
for toc_path in "$topdir/$package"{,-Mainline,_Mainline,-Classic,_Classic,-Vanilla,_Vanilla,-BCC,_BCC,-TBC,_TBC,-Wrath,_Wrath,-WOTLKC,_WOTLKC,-Cata,_Cata,-Mists,_Mists,-Camelot,_Camelot}.toc; do
    if [[ -f "$toc_path" ]]; then set_toc_project_info "$toc_path"; ... fi
done
```
Because `.pkgmeta` already declares `package-as: TerribleBuffTracker` explicitly, the packager never falls back to guessing the name from the directory, so there is no "ambiguous addon name" risk from having two suffixed TOCs and no unsuffixed one. One `git push origin main <tag>` produces one GitHub release zip containing both TOC files and the shared source set — exactly the "one tag, one package, both flavors" outcome the milestone wants. No new packager CLI flags, no `-S`/split-generation flag, nothing in `release.yml`'s `env:` block needs a new game-type input.

`scripts/install.bat` (per the already-locked decision, not re-litigated here): both TOC files should be copied to *every* present client folder — do not add per-flavor `if` branching around which TOC to copy. The client, not the installer, decides which TOC to read. Only the destination-folder existence check needs to be per-client:
```bat
set "RETAIL_DEST=%PROGRAMFILES(x86)%\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker"
set "FOREVER_DEST=%PROGRAMFILES(x86)%\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker"
```
then copy the full shared file set (both `.toc` files + all `.lua`/`.xml`/`.blp`) into whichever of `RETAIL_DEST`/`FOREVER_DEST` exist, skipping absent ones — matching the locked decision verbatim.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| Two physical TOC files (`_Mainline.toc`, `_Camelot.toc`) | Single TOC with comma-separated `## Interface: 120100, 16001` and per-type `## Interface-Retail:` / `## Interface-Forever:` lines, packaged with `packager -S` to auto-generate split files at release time | Only worth it for addons juggling 5+ flavors where hand-maintaining N TOC files becomes error-prone. Explicitly rejected here — this is a locked user decision (`.planning/PROJECT.md` Key Decisions), and TBT only ever needs 2 flavors, so the generated-file indirection buys nothing and adds a build-time step to reason about. |
| `_Camelot.toc` suffix | `_Vanilla.toc` or `_Forever.toc` suffix | Never for the client-loading question — `_Vanilla` is a different product (Classic Era) per every source above. `_Forever` is accepted by Wago's *uploader* as an alias label but is not a suffix the WoW client itself searches for (absent from warcraft.wiki.gg's client-search table and from `release.sh`'s TOC-discovery regex) — do not rely on it for client loading, only `_Camelot` is confirmed client-recognized. |
| `## AllowLoadGameType` omitted from both split TOCs | Add `## AllowLoadGameType: standard` / `## AllowLoadGameType: camelot` explicitly to each | Add only if in-game verification (see Critical Finding) reveals a load failure not explained by the Interface number; otherwise unnecessary per the "What NOT to Add" section. |
| Keep `.pkgmeta` / `release.yml` unmodified | Add explicit `enable-nolib-creation` / manual per-flavor packaging jobs in `release.yml` | Only relevant if TBT ever needs no-lib (embedded-library-stripped) builds or per-flavor separate zips — not applicable; TBT has no embedded libs and one combined zip is exactly what both CurseForge and Wago expect for a suffix-based multi-flavor addon. |

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| Flavor-forked Lua/XML files (e.g. `Core_Camelot.lua`) | Explicitly out of scope per `.planning/PROJECT.md` constraint: "one shared Lua/XML file set must load on both Interface 120100 and 16001 — no flavor-forked source files in v0.3." Forever's API surface for TBT's dependencies (CDM, Edit Mode, secret-value API) already mirrors Midnight's per the milestone's own established grounding. | Keep one shared file list referenced identically by both TOC files, as shown above. If genuine Forever-only runtime branching is ever needed, it belongs in a later milestone, gated by a runtime check (e.g. `WOW_PROJECT_ID` / build-info check), never a second copy of a file. |
| A compat-shim library (e.g. a small polyfill lib vendored to smooth over API differences) | No API gap has been identified yet — this milestone is metadata/tooling only, "Forever-specific breakage fixed to reach parity only." Introducing a shim before a concrete gap is found is speculative scope creep and violates the "no new capability" constraint. | If a genuine Forever API gap surfaces during in-game verification, fix it with a guarded, fail-safe runtime check in existing shared files (matching the existing `C_Secrets`-gating pattern already used for secret values), not a library. |
| Packager `-S` / `Interface-Type:` auto-split TOC generation | Rejected alternative — the user explicitly locked in physical split TOCs over generated ones. Using both approaches simultaneously (a fallback TOC plus generated ones) is exactly the "Ambiguous addon name" failure mode `release.sh` detects and aborts on. | Two physical TOC files, maintained by hand or by the executor script, exactly as scaffolded above. |
| `## AllowLoadGameType` directives on TBT's own TOCs (as a first move) | Redundant given filename-suffix-based flavor selection already gates loading; every existing suffix-based multi-flavor CurseForge addon in the wild ships without it. Adding untested directives "just in case" adds a variable to debug if something else breaks. | Rely on filename suffix alone first; only add the directive if a concrete in-game failure points at it. |
| Uncommenting `CF_API_KEY` / `WAGO_API_TOKEN` in `release.yml` as part of this milestone | Out of scope — this milestone is "metadata and tooling only" for producing one correctly-flavored package; CurseForge/Wago uploads are a separate, currently-dormant concern unrelated to whether the client loads the addon. Both services already support the `forever`/`camelot` game version today (see Distribution below), so there is no blocker forcing this now, and enabling uploads mid-milestone would conflate two unrelated changes in one release. | Leave the two lines commented as-is; uncomment in a dedicated future change once API keys are actually provisioned, independent of this milestone. |
| Renaming `package-as` in `.pkgmeta`, or restructuring the `ignore:` list | Nothing about splitting TOC files requires it — `package-as: TerribleBuffTracker` already matches both `_Mainline` and `_Camelot` variants via the packager's own brace-expansion search (see Installation). Touching this file at all is unnecessary risk for a change that needs zero edits. | Leave `.pkgmeta` untouched. |
| A third "universal" `TerribleBuffTracker.toc` kept alongside the two flavored ones "just in case" | Reintroduces exactly the ambiguity the split is meant to resolve, and risks the unsuffixed file being picked up by an unexpected client/tool with a single, wrong Interface number. `release.sh`'s discovery loop is fine with *only* suffixed files present — an unsuffixed fallback is not required. | Delete the old unsuffixed `TerribleBuffTracker.toc` once both split files exist; don't keep it around as a "default." |

## Stack Patterns by Variant

**If targeting Midnight retail:**
- File: `TerribleBuffTracker_Mainline.toc`, `## Interface: 120100`
- Install path: `World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker`
- Product/build source of truth: root `.build.info`, row with `Product = wow` (observed `12.1.0.69814` on this machine)
- Because: this is TBT's existing, already-shipping target — unchanged by this milestone.

**If targeting WoW Forever beta:**
- File: `TerribleBuffTracker_Camelot.toc`, `## Interface: 16001`
- Install path (current beta phase): `World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker`
- Product/build source of truth: root `.build.info`, row with `Product = wow_classic_beta` (observed `1.60.1.69893` on this machine)
- Because: Forever currently ships piggybacked on the `wow_classic_beta` product during its beta phase (UNVERIFIED beyond beta: whether Forever gets its own dedicated product string and install folder — e.g. `_forever_` — at GA is not knowable yet; re-check `.build.info` product names at that time. `install.bat`'s folder-existence check should be revisited then, not before).

## Version Compatibility

| Flavor | Interface | Derivation formula | Product / build observed | Client-recognized TOC suffix | Distribution-side toc suffixes accepted |
|---|---|---|---|---|---|
| Midnight retail | `120100` | `printf "%d%02d%02d" 12 1 0` | `wow` @ `12.1.0.69814` | `_Mainline.toc` (also the unsuffixed default) | Wago: `-Mainline`, `_Mainline` |
| WoW Forever (beta) | `16001` | `printf "%d%02d%02d" 1 60 1` | `wow_classic_beta` @ `1.60.1.69893` (also seen at `.69876`, `.69913` in WoWUI commit history — minor/patch stable at `60.1`) | `_Camelot.toc` (priority) or `_Mainline.toc` (valid fallback, lower priority, shared with retail) | Wago: `-Camelot`, `_Camelot`, `-Forever`, `_Forever` |

**Re-derivation recipe for future builds (any flavor):** read the relevant product's version string `X.Y.Z` out of `.build.info` (or from a WoWUI branch's latest commit message, which BigWigsMods keeps as the literal build version), then compute `Interface = concat(X, zero-pad-2(Y), zero-pad-2(Z))`. This is exactly `BigWigsMods/packager`'s own internal formula (`release.sh`, `printf "%d%02d%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"`), and it reproduces both 120100 (from 12.1.0) and 16001 (from 1.60.1) exactly. The packager additionally free-associates the *major* version to a coarse game type (`1.x` → classic-family, refined to `forever` specifically when minor is in `6[0-9]`; `12.x`+ with no classic prefix → `retail`), which is a second, independent cross-check available if the version string alone is ambiguous.

## Sources

- `https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh` — HIGH confidence, primary source, read directly: `game_flavor` map (line 79), `toc_to_type`/`toc_to_file_type` interface-prefix maps (lines ~193-222), TOC-suffix discovery regex and brace-expansion loop (lines ~1174, ~1402), version→interface `printf` formula (lines ~305-333), CurseForge `game_id` map including `forever) game_id=88568` (line 2836), auto-split suffix map including `forever) new_file+="_Camelot.toc"` (line 1992).
- `https://raw.githubusercontent.com/BigWigsMods/WoWUI/forever-beta/Interface/AddOns/Blizzard_CooldownViewer/Blizzard_CooldownViewer.toc` — HIGH confidence, primary source (Blizzard's own shipped TOC), read directly: `## AllowLoadGameType: standard, camelot`.
- `https://raw.githubusercontent.com/BigWigsMods/WoWUI/forever-beta/Interface/AddOns/Blizzard_EditMode/Blizzard_EditMode.toc` — HIGH confidence, same branch, read directly: multiple `[AllowLoadGameType camelot]` / `[AllowLoadGameType standard, camelot, mists]` file-load gates.
- `https://api.github.com/repos/BigWigsMods/WoWUI/commits?sha=forever-beta` — HIGH confidence, queried live: last 3 commit messages `1.60.1.69913`, `1.60.1.69893`, `1.60.1.69876`, confirming version stability at `60.1`.
- `https://addons.wago.io/api/data/game` — HIGH confidence, live public API queried directly during this research: confirms `forever` patch family exists (`"forever": ["1.60.1"]`), `supported_forever_patches: "1.60.1"`, and accepted TOC suffixes `["-Camelot", "_Camelot", "-Forever", "_Forever"]` distinct from `classic`'s `["-Classic", "_Classic", "-Vanilla", "_Vanilla"]`.
- `https://www.curseforge.com/wow/search?...&gameVersionTypeId=88568` — MEDIUM confidence, confirms the same `gameVersionTypeID` (88568) found in `release.sh`'s `game_id` map is a live, queryable filter on CurseForge's site today, i.e. CurseForge has a registered game-version type for Forever. Could not confirm deeper CurseForge upload-acceptance behavior without an authenticated API key (CF_API_KEY is not provisioned/available in this environment).
- warcraft.wiki.gg "TOC format" page (fetched via WebFetch, quotes reproduced above) — HIGH confidence for the client-suffix table and `AllowLoadGameType` directive, MEDIUM confidence for anything the page doesn't explicitly state (e.g. default `AllowLoadGameType` behavior when omitted, `## Category` flavor differences) — flagged inline above as MEDIUM/UNVERIFIED where applicable.
- `https://github.com/McTalian-WoW-Addons/wow-build-tools/pull/245` — MEDIUM confidence, third-party build tool, corroborates (does not introduce) the `_Camelot.toc` mapping, Forever's `_classic_beta_` install dir during beta, and interface range 16000–16001.
- User's local `.build.info` files (`World of Warcraft\.build.info`, read directly during this research) — HIGH confidence, ground truth for this machine: `wow` @ `12.1.0.69814`, `wow_classic_beta` @ `1.60.1.69893`.
- `TerribleBuffTracker.toc`, `.pkgmeta`, `.github/workflows/release.yml`, `scripts/install.bat`, `scripts/release.bat`, `.planning/PROJECT.md` (all read directly from the repository) — ground truth for current state, used to derive the "no changes required" findings for `.pkgmeta`/`release.yml`.

---
*Stack research for: WoW Forever (camelot) cross-flavor packaging milestone*
*Researched: 2026-09-18*
