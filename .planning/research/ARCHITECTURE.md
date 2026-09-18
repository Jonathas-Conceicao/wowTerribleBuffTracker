# Architecture Research: WoW Forever Cross-Flavor Support

**Domain:** WoW addon multi-flavor packaging (retail Midnight + WoW Forever/`camelot` beta)
**Researched:** 2026-09-18
**Confidence:** HIGH (TOC/packager mechanics verified against BigWigs packager source and warcraft.wiki.gg; MEDIUM on Forever-beta-specific client behavior, which is explicitly gated on in-game verification per the milestone context)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  Repo root (ONE shared Lua/XML file set — CLAUDE.md hard constraint) │
│  Core.lua  BuffEngine.lua  Providers.lua  EditModeFrames.lua          │
│  Display.lua  CDMTab.xml  CDMTab.lua  tbt_icon_64x64.blp              │
├──────────────────────────────────────────────────────────────────────┤
│  Two manifest files (the ONLY duplicated artifacts)                   │
│  TerribleBuffTracker_Mainline.toc (Interface 120100)                  │
│  TerribleBuffTracker_Camelot.toc  (Interface 16001)                   │
│  — WoW client picks ONE by filename suffix matching its own flavor,   │
│    per warcraft.wiki.gg TOC_format and BigWigs packager's flavor map  │
├──────────────────────────────────────────────────────────────────────┤
│  Install tooling (client-topology aware, tooling only)                │
│  scripts/install.bat → enumerates _retail_ / _classic_beta_ dirs,     │
│  copies the shared file set + BOTH TOCs into each present target      │
├──────────────────────────────────────────────────────────────────────┤
│  Release tooling (flavor-blind — the packager does the flavor work)   │
│  scripts/release.bat (tag+push, unchanged) → GitHub Actions           │
│  → BigWigsMods/packager@v2 discovers both TOCs by suffix, uploads     │
│    per-flavor artifacts to CurseForge/Wago from ONE tag                │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Change for v0.3 |
|-----------|----------------|------------------|
| `TerribleBuffTracker.toc` | Single manifest, one Interface value | REMOVED — replaced by two flavor TOCs |
| `TerribleBuffTracker_Mainline.toc` | Retail/Midnight manifest, Interface 120100 | NEW |
| `TerribleBuffTracker_Camelot.toc` | Forever manifest, Interface 16001 | NEW |
| `Core.lua` / `BuffEngine.lua` / `Providers.lua` / `EditModeFrames.lua` / `Display.lua` / `CDMTab.lua` / `CDMTab.xml` | All addon logic, shared verbatim | NO CHANGE NEEDED (bytes identical, loaded by whichever TOC the client selects) |
| `scripts/install.bat` | Deploy to local WoW installs | MODIFIED — loop over candidate flavor dirs |
| `scripts/release.bat` | Tag + push | NO CHANGE NEEDED — flavor-blind by design |
| `.github/workflows/release.yml` / BigWigs packager | Build + upload per-flavor artifacts | NO CHANGE NEEDED — packager already flavor-aware by TOC suffix |
| `.pkgmeta` | Packaging ignore rules | NO CHANGE NEEDED — ignore list is flavor-agnostic |

## Recommended Project Structure

```
TerribleBuffTracker/
├── TerribleBuffTracker_Mainline.toc   # Interface 120100 — retail/Midnight
├── TerribleBuffTracker_Camelot.toc    # Interface 16001  — Forever beta
├── Core.lua
├── BuffEngine.lua
├── Providers.lua
├── EditModeFrames.lua
├── Display.lua
├── CDMTab.xml
├── CDMTab.lua
├── tbt_icon_64x64.blp
├── .pkgmeta
├── scripts/
│   ├── install.bat
│   └── release.bat
└── .github/workflows/release.yml
```

No new folders. No `Mainline/` or `Camelot/` subtree — the whole point of the split-TOC approach (as opposed to a folder-per-flavor layout some multi-flavor addons use) is that the Lua/XML tree stays flat and single-copy, and only the two small manifest files fork.

### Structure Rationale

- **Two TOCs at repo root, not nested:** WoW's client-side flavor selection (documented at warcraft.wiki.gg/wiki/TOC_format) works by filename suffix matching against `<AddonFolderName>_<Suffix>.toc` sitting directly inside the addon's own folder — it does not support per-flavor subfolders for this mechanism. Both TOCs must sit next to the Lua files they reference.
- **No `Mainline/` or `Camelot/` Lua trees:** the milestone's hard constraint is "no flavor-forked source files"; introducing parallel folders (even if only for TOCs) would need per-directory `install.bat` logic and be pure structural overhead the milestone doesn't need.

## Architectural Patterns

### Pattern 1: Split flavor TOCs referencing one shared file set

**What:** Two manifest files with identical `Author/Notes/SavedVariables/file list` and *only* `## Interface:` (and file name) differing. Both list every Lua/XML file the addon has, verbatim, in the same load order.
**When to use:** Exactly TBT's situation — one code path must run unmodified on two Interface ranges, and you want deterministic per-flavor Interface declaration rather than relying on comma-form parsing.
**Trade-offs:** Pro — CurseForge/Wago and the WoW client itself both understand this natively (verified: BigWigs packager's `game_flavor` array explicitly maps `["camelot"]="forever"`, and the `_Camelot` suffix is Blizzard/community-documented, not a BigWigs invention). Con — two files can drift; needs the sync discipline covered in "File Topology" below.

**Example — `TerribleBuffTracker_Mainline.toc`:**
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

**`TerribleBuffTracker_Camelot.toc`** is byte-identical except `## Interface: 16001` on line 1. (Whether Forever additionally wants `## AllowLoadGameType: standard, camelot` is a Forever-TOC convention Blizzard's own Forever TOCs declare per PROJECT.md's Context section — carry it on the Camelot TOC only, since it is a Forever-only directive; harmless if the retail client ignores an unknown key on the Mainline TOC too, but there is no reason to add noise to a file that doesn't need it.)

### Pattern 2: Sync-checked duplicate manifests (not a generator)

**What:** Because the constraint is "one shared file set," the two TOCs' file-list *bodies* (everything after the `##` header block) must always be identical, modulo the `## Interface:` line and possibly `## AllowLoadGameType:`. Rather than building a template/codegen step (which the WeakAuras/BigWigs precedent shows even large multi-flavor addons don't bother with when the file lists are meant to differ *intentionally* — they hand-maintain divergent TOCs because their flavors genuinely need different files), TBT should add a cheap **diff-based CI/lint guard**, because TBT's file lists are supposed to be identical, so any difference is a bug by definition, not a legitimate flavor fork.
**When to use:** Whenever "no flavor-forked source files" is a load-bearing constraint and you have >1 manifest.
**Trade-offs:** Pro — a two-line `diff` catches "forgot to add NewFile.lua to the Camelot TOC" at commit time instead of at Forever runtime (where a missing file just silently doesn't load — no error, just broken behavior, since WoW does not warn about files present in one TOC and absent from another). Con — none meaningful; this is a ~5-line script.

**Example — where it belongs:** `scripts/install.bat` is the natural home for a *guard*, not `release.bat` — install.bat already runs before every local test cycle, so a mismatch is caught immediately during dev, not just at release time. A minimal PowerShell/batch approach:
```bat
:: In install.bat, before copying: strip the ## header lines and compare bodies
for /f "skip=11 delims=" %%A in ('type "%SOURCE%TerribleBuffTracker_Mainline.toc"') do echo %%A>>"%TEMP%\m.txt"
for /f "skip=11 delims=" %%A in ('type "%SOURCE%TerribleBuffTracker_Camelot.toc"') do echo %%A>>"%TEMP%\c.txt"
fc "%TEMP%\m.txt" "%TEMP%\c.txt" >nul || (echo WARNING: TOC file lists differ between flavors! & exit /b 1)
```
A `.github/workflows` lint job duplicating this check is optional belt-and-suspenders for PRs that don't run install.bat locally, but is not required for a solo-maintainer repo where install.bat runs on every deploy — one guard, in the tool that's already always run, is enough. Do not add a second one in CI unless multiple contributors start submitting PRs without running install.bat first.

### Pattern 3: Provider-level graceful absence, not flavor branching

**What:** TBT's `Providers.lua` already resolves every piece of Forever-irrelevant data (trinket/pot spell IDs, equipped-item lookups, class lust spells) through `RefreshAtRest()` → `GetDisplayInfo()`, both of which read live client state (`GetInventoryItemID`, `C_Item.GetItemCount`, `C_Spell.GetSpellInfo`) rather than asserting the retail-only IDs exist. On Forever, `TRINKET_SPELLS[spellID]` / `POT_SPELLS[spellID]` lookups in `OnTrigger` (Providers.lua lines 250, 350) simply never match — Forever characters cannot cast retail season trinket/pot spell IDs — so `OnTrigger` returns `nil` for those events, precisely the same "no match" path already used for any spell not in the static table. Nothing in that path throws or logs.
**When to use:** This is *already* TBT's architecture; the finding is that it needs no new pattern, only verification that the boundary conditions covered below hold on Forever's own Cooldown Manager and equipment/class model.
**Trade-offs:** N/A — this is a "no change needed" finding, detailed below.

## Data Flow

### Provider resolution flow (why Forever mostly "just works")

```
UNIT_SPELLCAST_SUCCEEDED (any flavor)
    → ns:DispatchEventToProviders (Providers.lua:633)
        → TrinketProvider:OnTrigger  → TRINKET_SPELLS[spellID] lookup → nil on Forever (no retail item exists)
        → PotProvider:OnTrigger      → POT_SPELLS[spellID] lookup    → nil on Forever
        → LustProvider:OnTrigger     → UNIT_AURA path, not this event → unaffected
        → UserSpellProvider:OnTrigger → ns.db.trackedBuffs[spellID] (USER data, flavor-agnostic) → works identically

CDM tab open (CDMTab.lua:RefreshTBTSections, StartPreview)
    → ns:RefreshProvidersAtRest() → TrinketProviderMixin:RefreshAtRest / PotProviderMixin:RefreshAtRest
        → GetInventoryItemID(player, INVSLOT_TRINKET1/2) → not in TRINKET_ITEM_IDS on Forever → falls through
        → trinketItemID = TRINKET_FALLBACK_ORDER[1] (Providers.lua:298-300) → ALWAYS resolves to a
          retail item, even on Forever — this is the one place fallback-to-wrong-flavor-data happens
    → Display.lua GetDisplayInfoForKey("trinket"/"pot") renders whatever atRest resolved to
```

### Key Data Flows

1. **Cast-triggered procs (trinket/pot):** silently no-op on Forever because the static ID tables never match a spell Forever can produce. This is graceful *by omission* — Providers.lua never needed a flavor check because the data itself is retail-exclusive and simply won't appear in Forever's event stream.
2. **At-rest placeholder icon (trinket/pot, Suggested section + empty-slot render):** this is the one flow that is NOT naturally graceful. `RefreshAtRest` has no "nothing equipped/in bags AND nothing in the fallback list matches this character" case — it always falls back to `TRINKET_FALLBACK_ORDER[1]` / `POT_FALLBACK_ORDER[1]`, so on Forever the Suggested-section trinket/pot tiles and any user who has dragged "trinket"/"pot" into Bars/Buffs will show a **retail item's icon and label** at rest, even though that item can never be equipped/consumed on Forever. `GetDisplayInfo` (Providers.lua:309-326, 402-419) always returns a non-nil result once any CSV entry exists, by design (D-16 "never returns nil in normal operation") — so this isn't a crash or blank slot, it's a *plausible-looking but wrong* placeholder. That is a genuine Forever-parity gap, not a crash risk.
3. **Lust:** `CLASS_LUST_SPELL` + `GetHunterLustSpell` (Providers.lua:211-227) key off `UnitClass`/`GetSpecializationInfo`, which are core client APIs present on every flavor; class lust spell IDs (Bloodlust 2825, Heroism 32182, Time Warp 80353, Fury of the Aspects 390386, Primal Rage 264667) are old, stable spells that predate the flavor split and are virtually certain to exist on Forever's spellbook (Forever is described in PROJECT.md as Classic-inspired but running Midnight-style API/expansion content, not a pre-Wrath-only ruleset) — LOW-confidence assumption, flagged as something to verify in-game rather than something to architect around.
4. **CDM tab injection (CDMTab.lua):** reads `CooldownViewerSettings`, `BuffBarCooldownViewer`, `BuffIconCooldownViewer`, atlas textures (`UI-HUD-CoolDownManager-*`) — all Blizzard_CooldownViewer assets. PROJECT.md's Context section already confirms Forever ships `Blizzard_CooldownViewer` including `GroupBuffFilter.lua`; CDMTab.lua's `GetCDMTabs()` discovery-by-`displayMode`-field walk (lines 955-985) is itself flavor-resilient by construction — it was written to survive Blizzard adding/removing tabs on retail, and that same resilience covers Forever shipping a different tab set (e.g., no Group Buffs tab) without any addon-side change.

## Scaling Considerations

Not applicable in the traditional sense (this is a single-user local addon, not a scaled service). The equivalent axis here is **flavor count**, not user count:

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 2 flavors (this milestone: Mainline + Camelot) | Two hand-maintained TOCs + a diff guard in install.bat. Sufficient. |
| 3+ flavors (hypothetical future Classic Era / Cata Classic support) | Still no code fork needed if the API surface stays this thin; the diff guard remains valid at N TOCs (compare N-1 diffs against a designated "reference" TOC). Only revisit templating/codegen if TOC *metadata* (not just file list) needs to diverge per flavor (e.g., different `X-Curse-Project-ID` per flavor listing) — TBT does not have that need today. |
| Flavor-specific feature divergence (e.g., a Forever-only Suggested-section item) | This is the point where `WOW_PROJECT_ID` branching or a genuine file fork becomes justified — see Runtime Flavor Detection below. Explicitly out of scope for v0.3. |

## Anti-Patterns

### Anti-Pattern 1: Adding `WOW_PROJECT_ID` flavor branches pre-emptively

**What people do:** Sprinkle `if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then ... else ... end` guards into `Core.lua`/`Providers.lua` "just in case" Forever needs different behavior somewhere, before any concrete Forever bug is known.
**Why it's wrong:** v0.3 is scoped as metadata-and-tooling-only with a parity-only fix budget (PROJECT.md Constraints: "Parity only"). Every speculative branch is a code path that has to be tested on both flavors forever, for a divergence that doesn't exist yet. It also directly contradicts the milestone's "no flavor-forked source files" constraint in spirit if not in literal file count — an `if` branch is a fork, just an inline one.
**Instead:** Ship identical Lua on both flavors. If in-game verification (the milestone's own Phase gate) surfaces a real Forever-only failure, add the narrowest possible runtime capability check (e.g. `if C_CooldownViewer and C_CooldownViewer.SomeAPI then`) rather than a flavor-ID branch — feature/API-presence checks survive a Forever API being backported or changed without touching TBT, whereas a `WOW_PROJECT_ID` check would need a code change every time Blizzard's flavor taxonomy shifts (see the Runtime Flavor Detection section: Forever doesn't even have a confirmed `WOW_PROJECT_ID` constant yet).

### Anti-Pattern 2: Folding the retail-only trinket/pot fallback silently instead of flagging it

**What people do:** See that `RefreshAtRest` never returns nil and conclude "no crash, no problem," shipping v0.3 with Forever showing a retail trinket icon/name in the Suggested section.
**Why it's wrong:** It's not a crash, but it is a Forever user seeing UI that references gear/consumables their character can never obtain — confusing, and arguably a parity *regression* relative to "the feature doesn't exist for you" (which is what happens for the analogous case of a spell simply never firing). Silently wrong data is worse than an empty slot.
**Instead:** This is the one piece of `Providers.lua` that genuinely may need a defensive read (not a flavor branch) during the in-game verification phase — e.g. gate `RefreshAtRest`'s hard fallback (`TRINKET_FALLBACK_ORDER[1]`) behind "did the fallback item's spell/item actually resolve via `C_Spell.GetSpellInfo`/`C_Item.GetItemInfo` on this client," so an unresolvable retail-only fallback yields "no trinket at rest" (empty/placeholder-off) instead of a wrong one. This is a defensive-read fix in the spirit of the existing `issecretvalue`/fail-safe guard patterns CLAUDE.md already mandates for Secret Values — not a new architectural component, and not flavor-forked, since the same check protects retail too (e.g. a fresh level-1 character with nothing equipped and no CSV item in bags).

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| WoW client (flavor TOC loader) | Filename-suffix match: client tries `<Folder>_<FlavorSuffix>.toc` before falling back to `<Folder>.toc` | Confirmed at warcraft.wiki.gg/wiki/TOC_format: `_Camelot.toc` is the documented Forever suffix, matching what PROJECT.md already asserts from the BigWigs packager mapping. Both sources agree — HIGH confidence on the *documented* behavior; the milestone correctly still treats "does the current Forever beta build actually implement this documented rule" as unverified, since beta clients can lag or deviate from documented final behavior. |
| BigWigs packager (`BigWigsMods/packager@v2`) | Discovers TOCs via regex `<pkg>[-_](Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot)\.toc$`, maps suffix → internal game-flavor key via a lookup table that includes `["camelot"]="forever"` | No workflow YAML change needed — this discovery is unconditional in the packager itself, already shipped in `@v2`, not something TBT's `.github/workflows/release.yml` has to opt into. |
| CurseForge / Wago upload targets | Packager derives per-flavor game-version tags from each TOC's own `## Interface:` value after running it through `toc_to_type()` (`16???` → `forever`) | Confirmed from packager source: this conversion table is exactly what PROJECT.md's Context section already states (`16???` → Forever); no new secrets/config needed unless CF/Wago require Forever to be explicitly enabled as a game on the project dashboard (an account-side toggle outside the repo, not a repo change). |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `install.bat` ↔ WoW client install layout | Filesystem copy into `%PROGRAMFILES(x86)%\World of Warcraft\_retail_\...` and (new) `..._classic_beta_\...` | Both are sibling folders under the same WoW root today (`%PROGRAMFILES(x86)%\World of Warcraft\`); enumerate as a list of `(root-relative subfolder)` pairs, not two hardcoded absolute paths, so a third flavor later is a one-line addition. |
| `release.bat` ↔ GitHub Actions | `git tag` + `git push` only — no flavor information crosses this boundary at all | Confirms Q5's answer: nothing in `release.bat` is flavor-aware today, and nothing needs to become so; flavor fan-out happens entirely inside the packager step, downstream of the tag. |
| `Providers.lua` ↔ `Display.lua`/`CDMTab.lua` | `ns:GetDisplayInfoForKey(key)` contract (Providers.lua:602-608) | This is the exact seam that already absorbs flavor differences for free — every caller in Display.lua and CDMTab.lua goes through this one function, so a future Forever-aware fallback fix (Anti-Pattern 2) is a one-function change, not a call-site sweep. |

## Answers to the Six Questions (classification summary)

### 1. File topology — MODIFIED (TOC layer only)

- **Duplicated:** exactly two files, `TerribleBuffTracker_Mainline.toc` and `TerribleBuffTracker_Camelot.toc`. Nothing else forks.
- **Shared:** every `.lua`/`.xml`/`.blp` file — `Core.lua`, `BuffEngine.lua`, `Providers.lua`, `EditModeFrames.lua`, `Display.lua`, `CDMTab.xml`, `CDMTab.lua`, `tbt_icon_64x64.blp` — referenced identically by both TOCs.
- **Keeping them in sync:** a diff-based guard belongs in `scripts/install.bat` (runs on every local deploy, the highest-frequency checkpoint in this solo-maintainer's workflow per CLAUDE.md's "Deploy to WoW with `./scripts/install.bat`" instruction) — compare the two TOCs' file-list bodies (everything after the metadata header) and fail loudly on mismatch. A duplicate CI lint step is optional, not required, for a single-maintainer repo; add it only if the project gains contributors who might skip local `install.bat` runs.
- **New component:** the sync-guard logic (≈5 lines inside `install.bat`, see Pattern 2).

### 2. Runtime flavor detection — NO CHANGE NEEDED (do not add it this milestone)

- `WOW_PROJECT_ID` and its documented sibling constants (`WOW_PROJECT_MAINLINE=1`, `WOW_PROJECT_CLASSIC=2`, `WOW_PROJECT_WOWLABS=3`, `WOW_PROJECT_BURNING_CRUSADE_CLASSIC=5`, `WOW_PROJECT_WRATH_CLASSIC=11`, `WOW_PROJECT_CATACLYSM_CLASSIC=14`, `WOW_PROJECT_MISTS_CLASSIC=19`) do **not** currently include a documented Forever/`camelot` value (warcraft.wiki.gg, checked live — MEDIUM confidence this is current, since Forever is beta and the wiki may not yet have been updated with whatever ID Blizzard assigns it internally).
- TBT needs **zero** runtime flavor branching for this milestone: nothing in `Core.lua`, `Providers.lua`, `Display.lua`, or `CDMTab.lua` currently needs to know which flavor it's on — every Forever-vs-retail difference so far identified (trinket/pot spell IDs simply not matching, CDM tab set possibly differing) is already handled by data-absence and structural discovery, not by conditionals that would need a flavor value to select a branch.
- Adding `WOW_PROJECT_ID` checks now would be premature: there is no known behavior that needs to differ *by flavor* as opposed to differing *by what's actually present in the client at runtime* (item in bags, tab existing, spell known). The latter is checked directly (already how the code works) and is strictly more correct than the former, because it also correctly handles edge cases within a single flavor (e.g., a retail character with no trinket equipped and no potions in bags — the exact same "nothing resolved" case Forever hits for a different reason).
- **What would later justify adding it:** a confirmed Forever behavior that is genuinely flavor-conditioned rather than state-conditioned — e.g., if Forever's Cooldown Manager exposes a structurally different API that can't be feature-detected (no such case is known today), or if a future milestone adds a Forever-exclusive feature that must never run on retail regardless of API presence. Until then, `WOW_PROJECT_ID` is dead-weight complexity per CLAUDE.md's own "No refactors during cleanup phases" / minimal-footprint ethos.

### 3. Graceful degradation without forking — MODIFIED (one narrow defensive read; everything else NO CHANGE NEEDED)

- The dispatch architecture (`ns:DispatchEventToProviders`, `ns:GetDisplayInfoForKey`) already isolates flavor-specific data (the `TRINKET_SPELLS`/`POT_SPELLS` static tables) behind runtime lookups keyed by live spell/item IDs, not by flavor. On Forever, `OnTrigger` for `TrinketProviderMixin`/`PotProviderMixin` (Providers.lua:239-275, 339-375) simply never matches — this is **NO CHANGE NEEDED**, it already degrades gracefully because the tables are just data, checked with plain `if not X then return nil end` guards that exist for the general "not a tracked spell" case anyway.
- The one real gap: `RefreshAtRest`'s unconditional fallback to `TRINKET_FALLBACK_ORDER[1]` / `POT_FALLBACK_ORDER[1]` (Providers.lua:298-300, 393-394) means the Suggested-section tile and any placeholder render always resolve to *some* retail item's icon/name, even when nothing that item implies is possible on the current character/flavor. This is **MODIFIED** — add a resolution check (e.g., confirm `C_Item.GetItemInfo(itemID)` or `C_Spell.GetSpellInfo(spellID)` returns real data before trusting the fallback) so an unresolvable fallback produces "nothing at rest" instead of a wrong answer. This fix is flavor-agnostic (it also protects a retail alt with empty bags) and requires no new file, no new component — a few added lines inside the two existing `RefreshAtRest` methods.
- `LustProviderMixin` and `UserSpellProviderMixin` need **NO CHANGE** — their data (class-lust spell IDs, user-entered spell IDs) is either universal-vintage content or entirely user-supplied, with no retail-only assumption baked in.

### 4. Install tooling — MODIFIED

- Current `install.bat` hardcodes one `DEST` under `_retail_` and an explicit 9-line file copy list.
- Minimal change: replace the single `DEST` with a loop over a small array of `(subfolder)` candidates — `_retail_` and `_classic_beta_` today — each checked with `if exist "%WOWROOT%\<subfolder>\Interface\AddOns"` (or similar) before copying, skipping absent ones silently per the locked decision ("no arguments... skipping absent targets").
- The file list becomes plural by exactly one line: add `TerribleBuffTracker_Mainline.toc` and `TerribleBuffTracker_Camelot.toc` (both copied to every present target — copying the "wrong" flavor's TOC into a folder is harmless since the client only reads the one matching its own flavor suffix, confirmed by the filename-match mechanism in Q1).
- **Flag:** the file list is hand-maintained in three places now if the sync-guard from Q1 is implemented as a separate check — `install.bat`'s own copy list, `Mainline.toc`, and `Camelot.toc` — all three must agree. Since `install.bat` already needs to enumerate every shipped file to copy it, the same array can double as the input to the Q1 diff-guard (compare install.bat's list against both TOC bodies) rather than maintaining three independent lists — this collapses "three lists to keep in sync" into "one list plus two derived comparisons," which is the minimal-footprint version of the guard.
- **Not silently succeeding when nothing installed:** end the script by counting how many targets were actually written to; if zero, `exit /b 1` with an explicit "No WoW installation found" message rather than printing the existing "Done!" success line unconditionally.

### 5. Release tooling — NO CHANGE NEEDED (release.bat, release.yml, .pkgmeta all flavor-blind by design)

- `scripts/release.bat` only tags and pushes; it carries no file paths, TOC names, or flavor logic today, and needs none — confirmed nothing flavor-related crosses this boundary (see Integration Points table).
- `.github/workflows/release.yml` invokes `BigWigsMods/packager@v2` with no flavor-specific inputs; the packager's own TOC-suffix discovery (confirmed above, already shipped) is what turns one tag into per-flavor CurseForge/Wago uploads. No YAML edit required.
- `.pkgmeta`'s `ignore:` list is about excluding non-shipped files (scripts, docs) — flavor-agnostic; no change.
- **Interface-version bump — where it lives now vs. later:** today it's a single-line edit in `TerribleBuffTracker.toc`'s `## Interface:` field (confirmed via `git log -p`: every prior bump, e.g. `ddbbbc1 bump version for 12.1`, touched exactly that one line in that one file). With two TOCs, a bump to either flavor's Interface number must touch only *that* TOC's `## Interface:` line — the two numbers are independent by design (120100 vs 16001 track different clients' patch cadences) — but a bump must **not** accidentally touch the shared file list below the header, and the Q1/Q4 sync-guard should diff only the file-list body, not the `## Interface:` line, so it doesn't false-positive on a legitimate single-flavor version bump.

### 6. Build order — gating unknown identified

The `_Camelot.toc` client-suffix behavior is the single gating unknown: everything else this milestone touches (file topology, install.bat, provider fallback hardening, sync-guard) can be built and even unit-verified against documentation, but **none of it is confirmed correct until the addon is observed loading on an actual Forever beta client**, because:
- The suffix mechanism is documented (warcraft.wiki.gg, BigWigs packager source) but Forever is beta — documented-but-unverified-on-this-specific-build behavior is exactly the category CLAUDE.md's philosophy flags as needing verification before being trusted as fact.
- If `_Camelot.toc` does NOT load on the current beta build (e.g., beta requires a different suffix, or requires `## AllowLoadGameType` to be present, or requires the file to be named differently than documented), every downstream verification step (CDM tab injection, cast detection, provider fallback behavior) is unreachable and any work done assuming it "just works" is unvalidated.

Suggested phase-level ordering:

1. **First, alone (gate):** Create both TOCs (Pattern 1) and confirm — via actual Forever beta client load, not inspection — that `TerribleBuffTracker_Camelot.toc` is selected and the addon appears in the AddOns list with no immediate load error. This is a single narrow phase whose only exit criterion is "addon loads on Forever." Nothing else in this milestone should be marked done before this passes.
2. **In parallel, once gate passes:**
   - `install.bat` rewrite (Q4) — independent of in-game behavior, testable by inspecting the filesystem result.
   - Sync-guard addition (Q1/Q4) — a static check, no game client needed at all; could actually be built *before* the gate, since it only compares files, not client behavior.
   - Provider fallback hardening (Q3, the `RefreshAtRest` resolution check) — can be coded before the gate but only *verified* after, since verifying "no wrong icon shown" requires a Forever character.
3. **After the gate, sequential (needs live Forever character):** in-game verification checklist per PROJECT.md's Target features — CDM tab injects, casts detected via `UNIT_SPELLCAST_SUCCEEDED`, bars/icons render, Edit Mode works, no Lua errors — plus confirming the Suggested-section trinket/pot tiles behave per the Q3 fix (either resolve correctly or show nothing, never a wrong retail item).
4. **Last:** release-tooling verification (Q5) — cutting one real tag and confirming the packager produces two distinct, correctly-tagged artifacts on CurseForge/Wago — since this depends on both TOCs being finalized and is naturally the last integration point before shipping.

## Sources

- BigWigs packager source (flavor-suffix regex, `game_flavor` lookup array including `["camelot"]="forever"`, `toc_to_type()` interface-range mapping including `16???) game_type="forever"`): https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh — HIGH confidence, read directly.
- warcraft.wiki.gg TOC_format (comma-separated `## Interface:`, `## AllowLoadGameType`, per-flavor TOC suffix list including `_Camelot.toc` for Forever): https://warcraft.wiki.gg/wiki/TOC_format — HIGH confidence, community-maintained wiki but content corroborated by packager source and by PROJECT.md's own prior research.
- warcraft.wiki.gg WOW_PROJECT_ID (constant list, absence of a Forever/camelot entry): https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID — MEDIUM confidence; absence of a documented constant is a "didn't find" finding, not proof Blizzard hasn't assigned one internally for the Forever beta client.
- BigWigsMods/BigWigs repo (`BigWigs.toc`, `.pkgmeta`): https://github.com/BigWigsMods/BigWigs — precedent showing the *alternative* the packager also supports (single TOC, comma-separated Interface list, `-S` split at package time) — not TBT's chosen approach, cited only to confirm the packager handles both strategies, corroborating that TBT's locked split-TOC decision is a supported, common pattern, not a fragile one-off.
- WeakAuras/WeakAuras2 repo (`WeakAuras_Vanilla.toc`, `WeakAuras_Cata.toc`, diffed): https://github.com/WeakAuras/WeakAuras2/tree/main/WeakAuras — precedent for real, hand-maintained, committed per-flavor TOC files (not codegen); their file lists *intentionally* diverge per flavor (they have real flavor-specific files, e.g. `Types_Vanilla.lua` vs `Types_Cata.lua`, `LibSpecializationWrapper.lua` added only for Cata+), which is the opposite of TBT's requirement — cited to justify why TBT's situation (identical file lists) is actually the simpler case, needing only a diff guard rather than any divergence-management tooling.
- TBT repo git history (`git log -p -- TerribleBuffTracker.toc`): confirms the existing single-line Interface-bump pattern (e.g. commit `ddbbbc1`), used to ground the "where does the bump live now vs. later" answer in Q5.
- TBT source read directly: `Core.lua`, `Providers.lua`, `Display.lua`, `CDMTab.lua`, `CDMTab.xml`, `TerribleBuffTracker.toc`, `scripts/install.bat`, `scripts/release.bat`, `.pkgmeta`, `.github/workflows/release.yml`, `.planning/PROJECT.md`.

---
*Architecture research for: WoW addon cross-flavor (retail Midnight + WoW Forever) packaging and tooling*
*Researched: 2026-09-18*
