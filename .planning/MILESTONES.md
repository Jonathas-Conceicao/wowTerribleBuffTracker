# Milestones

## v0.3.0 WoW Forever compatibility (Shipped: 2026-09-19)

**Scope:** Multi-flavour support. One shared Lua/XML source set loading on both WoW Midnight retail and the WoW Forever beta, from two flavour-suffixed TOCs, with no forked source file and no runtime flavour branch.
**Phases:** 7 phases (25-30, with 27.1 inserted mid-milestone), 12 plans
**Timeline:** 2 days (2026-09-18 → 2026-09-19), 57 commits
**Interface:** 120100 (Midnight retail) + **16001** (Forever beta) — first release to ship two
**Verified on:** Forever `1.60.1.69913` / interface `16001`, and Midnight retail 12.1.x, both 2026-09-18
**Known deferred items at close:** 5 requirements (`DIST-03`…`DIST-07`, need a real tag push) + 4 tooling todos — see STATE.md Deferred Items

### Key accomplishments

- **Split flavour TOCs.** `TerribleBuffTracker.toc` became `TerribleBuffTracker_Mainline.toc` (Interface 120100) via a pure `git mv` — `1 file changed, 0 insertions(+), 0 deletions(-)` — and `TerribleBuffTracker_Camelot.toc` (Interface 16001) was copied from it. The two differ on exactly two lines, `## Interface:` and `## Notes:`, and `scripts/check-toc.ps1` enforces that as a pre-tag guard rather than leaving it to convention. The `_Camelot` suffix is case-sensitive and was verified through `git ls-files`, not a file browser.
- **`UNIT_SPELLCAST_SUCCEEDED` confirmed working on Forever.** This was the milestone-deciding unknown: TBT's entire detection strategy rests on that event delivering a usable spellID, and nothing else in the addon would have mattered if it did not. It does.
- **Argument-free multi-client `install.bat`.** Deploys the shared file set and both TOCs to every WoW client folder present on the machine in one pass across seven known flavour folders, silently skips absent ones, and exits nonzero with a diagnostic naming the root when none are found. Uses an explicit 10-file list rather than a glob, because `.#Display.lua` emacs lock files match `*.lua`.
- **Two flavour-pure release zips from one tag.** `.pkgmeta` split into `.pkgmeta-mainline` / `.pkgmeta-camelot` — byte-identical once each cross-ignore line is stripped — and `release.yml` gained a serialised (`max-parallel: 1`) two-job matrix passing `-m .pkgmeta-<flavor>`, `-g <flavor>`, and a `{game-type}`-templated `-n`.
- **TOOL-01: spell and aura IDs in every tooltip.** One shared implementation behind a capability existence check on `TooltipDataProcessor.AddTooltipPostCall` — a capability check, not a client-identity check, so a client lacking the API degrades to a silent no-op. Registered once for `AllTypes` and filtered against an allow-set, because `Enum.TooltipDataType` is engine-side and a member that does not exist on Forever would error at load if registered directly. Items are excluded by never being added. This is what made Forever cast-detection testing possible at all.
- **META-01: data-driven meta-tile hiding.** A Suggested meta tile is hidden when none of its catalog spells resolve on the current client, via per-provider `HasResolvableCatalog` and the memoised `ns:IsSuggestedKeyResolvable`. Chosen over the flavour guard the user first suggested, because the locked constraints forbid flavour branching — and it has a property the guard would not: a future Forever build that ships lust spells makes the tiles reappear with no code change.
- **Three Forever-only defects fixed with narrow defensive reads, no flavour branch.** The empty lust tooltip (`9fde1eb`), the drag nil-call on the Forever-absent `GetScaledCursorPositionForFrame` (`9e32f92`, 53 errors in one session), and a secret-value comparison in the new tooltip code that threw when hovering an aura in combat (`19c4ddc`).
- **A real retail bug corrected on the way.** The Trinket and Pot at-rest tiles had been presenting an unresolved hardcoded retail item as if it were real; an empty-bags alt saw an icon and name it could not obtain. Four unconditional `FALLBACK_ORDER[1]` sites gave way to a shared neutral placeholder. The one place v0.3 deliberately changed retail behaviour, and recorded under `### Changes` in the changelog for that reason.
- **The invisible-diff bug root-caused.** `stylua.toml` now pins `line_endings = "Windows"` so the bare invocation is correct, and `.gitattributes` declares line endings explicitly so a line-ending-only change can no longer produce an empty `git diff`.

### Bugs found in this milestone's own work

- **`duration = nil` would have crashed.** The placeholder was specified with a nil duration on the claim that consumers tolerate it; `BuffEngine.lua:283` computes `now + info.duration`. Caught in planning, before any code was written, and changed to `duration = 0`, the codebase's existing unresolved sentinel.
- **Omitting `-g` would have collided both zips.** The original decision was that `-g` must not be passed. Tracing the packager's `release.sh` showed TOC discovery ignores the ignore list and the auto-derive path needs exactly one game version, so both jobs would have emitted `TerribleBuffTracker-v0.3.0-.zip` and clobbered each other. `-g <flavor>` is the only mechanism that sets a correct `game_type`.
- **`/reload` does not test SavedVariables persistence.** Data survives in memory, so a `/reload`-based test cannot fail. Only logout→login exercises the load path, and doing so is what surfaced the Forever storage bug. A verification record asserting persistence on build `69913` was withdrawn.
- **A secret number reports `"number"` from `type()`.** A type check alone therefore passes and gives false confidence; `issecretvalue()` must come first, before any comparison or concatenation. The rule was already documented at `BuffEngine.lua:39` and was violated anyway in new code.

### Known issues at ship

- **Settings do not persist between sessions on the Forever beta.** A client-side bug, not TBT's: the file is written correctly on logout and is byte-identical to its `.bak`, but never read back on login, so each session starts from defaults and then overwrites the saved file. Other addons are affected identically, and there is no Forever API change to adapt to — `Blizzard_ClientSavedVariables` exists on both flavours and no new TOC directive governs it. Documented in `CHANGELOG.md` and `README.md`. Retail is unaffected.
- **Forever ships no retail spell data.** `C_Spell.GetSpellInfo(2825)` returns nil there, which is the exact discriminator META-01 relies on. Trinket, Pot and Lust tiles are all hidden on Forever as designed.

### Process notes

- Testing order was inverted mid-milestone at the user's request: Forever first, then retail for regressions. That turned Phase 26 from a dependent into a prerequisite, since `install.bat` could not deploy to any client after the TOC rename until it was fixed.
- No `WOW_PROJECT_ID`, `GetBuildInfo` or `IsTestBuild` token exists in any Lua file. The no-flavour-branch constraint held end to end.
- No rollback TOC was kept, by user choice, which is what made `VER-01` a hard blocking gate.
- Schema unchanged; no SavedVariables migration.
- stylua clean across all six Lua files at exit, all `w/crlf`.

---

_See `.planning/milestones/v0.3.0-ROADMAP.md` for full phase details._
_See `.planning/milestones/v0.3.0-REQUIREMENTS.md` for requirement-level traceability._

---

## v0.2.6 CDM Tab Placement Fix (Shipped: 2026-09)

**Scope:** Single-fix release. Developed and tagged outside the GSD workflow — no phase artifacts exist.
**Phases:** None (ad-hoc)
**Interface:** 120100 (unchanged)

### Key accomplishments

- TBT tab anchors under whichever Blizzard CDM tab is bottom-most, so a tab added by a future patch pushes ours down instead of covering it (12.1 added a "Group Buffs" tab that had been sitting on top of ours).
- The Group Buffs tab no longer stays highlighted while the TBT panel is open.

_Commit: `563b978`. No `.planning/` artifacts — recorded here and in `CHANGELOG.md` only._

---

## v0.2.5 12.1 Compatibility (Shipped: 2026-09)

**Scope:** Patch-compatibility release for WoW 12.1. Developed and tagged outside the GSD workflow — no phase artifacts exist.
**Phases:** None (ad-hoc)
**Interface bump:** 120100

### Key accomplishments

- Interface bumped to 12.1 (120100).
- Survives the fully-secret `UNIT_AURA` payload that 12.1 introduced — fixed the in-combat Lua error.
- Lust / heroism tracking keeps working in combat; a lust already running when first seen now shows correct remaining time instead of restarting at 40s.
- A Sated debuff lingering after a lust ends can no longer start a phantom timer.
- Timer cancellation no longer acts on a buff whose aura cannot be read.

_Commits: `ddbbbc1`, `ac44d6b`, `1003ad0`. No `.planning/` artifacts — recorded here and in `CHANGELOG.md` only._

---

## v0.2.4 SpellProvider Refactor (Shipped: 2026-04-22)

**Scope:** Pure internal architecture refactor. Zero user-facing feature additions.
**Phases:** 8 phases, 23 plans
**Timeline:** ~9 days (2026-04-13 → 2026-04-22)
**Interface bump:** 120005

### Key accomplishments

- **SpellProvider architecture** — Four providers (UserSpell, Trinket, Pot, Lust) implementing a common interface (`GetEventInterests`, `OnTrigger`, `GetDisplayInfo`, `RefreshAtRest`) registered on `ns.providers`. `ns:DispatchEventToProviders` routes events by declared interest; `BuffEngine.OnSpellCastSucceeded` and `OnUnitAura` are single-line dispatchers with zero `if/elseif` chains (PROV-01, PROV-02).
- **Unified ActiveProc shape** — 9-field normalized plain table (`{key, spellID, duration, label, expiresAt, aliveBuffs, ...}`) consumed by one Display codepath with zero type-specific branching (PROV-03, DISP-01).
- **Single icon-resolution dispatch** — `ns:GetDisplayInfoForKey(key)` replaces all duplicated resolution chains; providers own `RefreshAtRest` (PROV-04, PROV-F3 pulled forward from v0.3+).
- **Additive preview architecture** — Separate `ns.previewTimers` table eliminates the mid-CDM real-cast-loss bug (v0.2.3 regression) as an architectural side-effect (LIFE-03).
- **Shared tooltip handler** — `ns:ShowBuffTooltip` used uniformly by timer bars, buff icons, and CDM settings tiles (DISP-03).
- **CDMTab unification** — All icon/tooltip resolution flows through `ns:GetDisplayInfoForKey`; `ns.SUGGESTED_KEYS` ordered list replaces the old closure table; `CLASS_LUST_SPELL` / `GetHunterLustSpell` demoted to Providers.lua module-local (DISP-02).
- **Orphan removal** — Three backwards-compat shims (`GetAtRestMetaIcon`, `GetAtRestMetaInfo`, `ResolveSuggestedSpellID`), two `ns.*FALLBACK_ORDER` exports, CSV source files, and `_G.tbt` debug export all deleted. `RefreshMetaIcons` renamed to `RefreshProvidersAtRest` (DISP-04).
- **Hot-path audit** — Phase 24 verified zero per-frame/per-event allocation regressions on Display render, `OnUnitAura` dispatch, and `ScanActiveTimersForCancellation`.

### Bugs fixed as architectural side-effects

- Trinket/pot preview bars showing 0-second durations (PITFALL-4) — fixed by Phase 20's provider-owned `RefreshAtRest` + `GetDisplayInfoForKey`.
- Mid-CDM real-cast loss — fixed by Phase 21's additive-preview design (separate tables, no snapshot/restore).
- Phase 22 regression (`df48029`) surfaced the exact bug class the refactor was designed to eliminate: Display read-sites using `slot.spellID` instead of `slot.key` for lookup. Unmasked by Mage Time Warp where `.key = "lust"` ≠ `.spellID = 80353`. Fixed by standardizing all reads on `.key`.

### Process notes

- No COMBAT_LOG_EVENT_UNFILTERED introduced (platform constraint held).
- Schema unchanged (`CURRENT_SCHEMA_VERSION = 3`); no SavedVariables migration.
- stylua clean across all 6 Lua files at exit.
- Phase 24 audit surfaced and resolved `_G.tbt` debug export tech debt before squash-merge.

---

_See `.planning/milestones/v0.2.4-ROADMAP.md` for full phase details._
_See `.planning/milestones/v0.2.4-REQUIREMENTS.md` for requirement-level traceability._
_See `.planning/milestones/v0.2.4-MILESTONE-AUDIT.md` for the final audit report._
