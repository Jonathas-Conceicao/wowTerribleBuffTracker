# Milestones

## v0.4.1 Generic Item Tracking and Forever Racials (Shipped: 2026-09-26)

**Scope:** Track any usable consumable from the player's bags, mirror the Cooldown Manager's pandemic and dispel-type indicators onto TBT's own trackers, and give every WoW Forever race its own racial trackers.
**Phases:** 8 (46-52; Phase 48.1 inserted mid-milestone on user request rather than renumbered, following the Phase 27.1 precedent), 18 plans
**Timeline:** 3 days (2026-09-24 → 2026-09-26), 163 commits, 7 source files changed (+4231 / -198)
**Verified on:** WoW Forever beta and Midnight retail, both 2026-09-26 — retail including a Mythic+ run
**Requirements:** 22 / 22 closed; RACE-09 closed as obsolete rather than implemented
**Known deferred items at close:** 999.5 (GCD grey), 999.8 (aura icon for divergent racials), 999.9 (Edit Mode taint), 999.10 (Shadowmeld cooldown timing), `RACE-06` (retail racials), plus two shipped waivers — G8 and F-2's priest branch. See ROADMAP.md Backlog

### Key accomplishments

- **Generic item tracking, built on one measured bet that paid off.** The kickoff decision was that a per-item `C_Item.GetItemCooldown(itemID)` read already reflects a shared cooldown, so tracking items individually gets cooldown sharing *for free* and no spell-category table is needed. Confirmed in game: one health potion fired the cooldown on all three potions sharing it. Forever's categories were separately measured to differ from retail's, so the table that was avoided would also have been wrong.
- **Blizzard computes, TBT mirrors — twice over.** Both the pandemic highlight and the dispel-type border read Blizzard's own computed state instead of recomputing it. Recomputing is closed by the platform in both cases: the inputs are secret, and the APIs that would redo the math key off `auraInstanceID`, flagged `DisallowTaintedAccess`.
- **In-combat dispel borders, via an asymmetry in what stays readable.** `border:IsShown()` remains a plain boolean while `GetAtlas()` returns a secret string in combat. So *whether* to draw is decidable and *what* to draw is not — and the atlas is relayed into `SetAtlas` unread rather than discarded. Shipped as two routes: the aura engine draws it for an ordinary merged tracked buff, the atlas mirror covers bars, item-backed entries and the engine-off fallback.
- **Every Forever racial, one tracker each, race-gated.** Ten races and 21 racials collected in game by the user over a single session, replacing the two generic `racial`/`racial2` slots with one entry per racial visible only to its own race — migrated from the old keys without losing placement, and verified across a real logout/login.
- **Aura-loss cancellation became the default rather than an opt-in.** A per-row `cancelOnAuraLoss` flag existed for hours and was removed: making "does this end when its buff ends" something someone had to remember meant every racial that could end early arrived as its own separate bug report.

### Bugs found in this milestone's own work

- **A confident comment cost the same bug two investigations.** `StartRacialProc` asserted that a racial's cooldown tile "reads the live game handle, which already knows the longer in-combat cooldown". It does not — `ApplyUserCooldown` owns any tracker carrying a duration, by the deliberate CD-02 reversal. Shadowmeld's in-combat cooldown ran 10s instead of 2 minutes, and the first investigation repeated the comment's claim and closed it as cosmetic, because the comment made the claim look already-checked.
- **A passing gate proves the path it walks, not the feature.** ITEM-07's gate exercised drift-then-correct and passed. The empty-at-login entry point was never walked — `itemTrackedCounts` is runtime-only and was seeded only at tracker creation, so counts were blank after every reload until a user noticed.
- **`itemUseSpellToID` was fed by a table nothing filled** unless the player opened the Cooldown Manager. A correctly-wired chain reading from an empty table looks exactly like a working one when traced forwards; the defect is only visible tracing backwards from the table to ask who writes it.
- **`stylua` writes CRCRLF for a comment inside a multi-line expression**, turning a Lua file binary to git — invisible to `file`, `grep` and `git diff`, catchable only by `git ls-files --eol`. Hit in Phase 48.1, and again by the Phase 50 planner via `awk` on a `.md` file.
- **The Lua file-local upvalue trap fired for the fifth time**, hours after the developer had read the comment in `Providers.lua` documenting the four prior occurrences.

## v0.4.0 Cooldown Tracking and Full CDM View (Shipped: 2026-09-23)

**Scope:** Cooldown tracking as a first-class tracker type, an all-or-nothing Merge Mode that draws Blizzard's Cooldown Manager entries inside TBT's own containers, four base containers plus user-created ones, and a collapse back to a single TOC covering both Midnight retail and the WoW Forever beta.
**Phases:** 15 (31-45; Phase 39 renumbered to 35.1 mid-milestone, so no Phase 39 exists), 34 plans
**Timeline:** 4 days (2026-09-20 → 2026-09-23), 229 commits, 142 files changed
**Interface:** 120100 (Midnight retail) + 16001 (Forever beta) from **one** TOC — v0.3.0's two flavour-suffixed TOCs retired
**Verified on:** Forever `1.60.1.69913` (2026-09-21→22) and Midnight retail 12.1.x including Mythic+ and a raid encounter (2026-09-23)
**Requirements:** 58 / 58 closed
**Known deferred items at close:** 1 backlog todo (GCD grey, never consistently reproducible), the remaining racials (`RACE-06`/`RACE-07`), and the first real tag push — see ROADMAP.md Backlog

### Key accomplishments

- **Cooldown trackers, and the same spell tracked twice.** A spell's cooldown became a tracker type of its own — icon-only, with charge counts where the client reports them. Supporting a buff tracker *and* a cooldown tracker for the same spell required re-keying the database into a `cd:<spellID>` namespace (schema v6): until then the two were literally the same record, and adding one silently replaced the other.
- **Merge Mode, with engine-driven sweeps.** The milestone's hardest problem was giving a merged buff icon a cooldown sweep, and every attempt that *read* the aura failed for structural rather than incidental reasons — the CDM's `Cooldown` getters return secrets, the numeric setters are `AllowedWhenUntainted`, the aura instance IDs sit behind `DisallowTaintedAccess`, and plain aura reads are denied the moment a fight starts, which is the one time the sweep matters. The fix was to invert the shape: hand Blizzard widgets to an `AuraContainer` and let the engine draw. TBT never injects into, parents into, or writes to a CDM frame.
- **One download, two clients.** `TerribleBuffTracker.toc` declaring `## Interface: 120100, 16001`, one `.pkgmeta`, one CI job, one zip. Follows the pattern shipping Forever addons already use (Platynator declares six interface versions and no `## AllowLoadGameType:`), which deletes the two-flavour drift bug class rather than guarding against it.
- **Four base containers plus user-created ones**, each carrying its own scale, padding, orientation, items-per-row and bar width — with the v0.3.0 database migrated across v3→v6 without loss, verified against a real saved-variables file.
- **Centered growth**, where a buff icon row re-centres on its anchor as buffs come and go. Centring is against the *container's* width in cells, not the run's own — that is what keeps the midpoint where the player put it.
- **All grid arithmetic collapsed into one function**, `ns:GridSlotPlacement`. Each time the merged and own-tracker paths derived placement separately they drifted — first by padding, then by scale, then by origin.
- **A settings panel under Options > AddOns**, opened by `/tbt`, with the Merge Mode switch and the container list.
- **Racial trackers for gnome, troll and orc**, through two racial slots, plus racial cooldown tiles. Forever-only by construction.

### Bugs found in this milestone's own work

- **`.pkgmeta` was not ignoring `.planning`**, so every release zip carried 334 tracked planning files into players' AddOns folders. Fixed in `295c601`. The one Phase 42 change that affects what ships rather than source tidiness — and it cannot be verified without a real tag push.
- **Merged auras drifted out of position, and the cause was not the engine.** Display sizes a container from the number of slots it holds; merged entries were being *withheld* from that list while the engine drew them, so a narrower container re-centred on its anchor and every offset measured from it followed. Merged entries are now published-but-not-drawn, keeping the footprint constant.
- **The `.proc` reuse hazard was real, not theoretical.** `Providers.lua` decrements `proc.stacks` on the live racial timer, so reusing `bar.proc` as a scratch buffer — the obvious shortcut — would have wiped a table `RacialProviderMixin` was still mutating.
- **`ns:GetActiveTimers` was the addon's largest per-tick allocation**: two tables and a comparator closure at 20 Hz, in combat — while `Display.lua` hoisted `ByLayoutOrder` specifically to avoid exactly that, one call up the stack.
- **Four plan-verification assertions failed during Phase 42 and all four were the assertion's fault**, never the code's: an unescaped `.` in a grep pattern, and three counts that forgot `grep -c` matches the definition line too.

### Known issues at ship

- **Settings do not persist between sessions on the WoW Forever beta.** A client bug, not TBT's: the file is written correctly on logout and never read back on login. Retail is unaffected.
- **In restricted content a buff can keep showing until its typed duration runs out.** `C_Secrets.ShouldAurasBeSecret()` holds for the whole key, which switches off the cancellation scan. Timers still *start* correctly, because `UNIT_SPELLCAST_SUCCEEDED` is never secret.
- **Charge counts can be blank in restricted content**, and a potion first used inside a key may show no timer until the player is somewhere unrestricted.
- **A custom cooldown tracker runs on the duration the user typed**, timed from the observed cast, so haste, cooldown reduction and resets make it wrong. This was a deliberate reversal of `CD-02` on 2026-09-22 after the game-handle version was reported as a bug. Merged CDM slots keep the engine's handle and are unaffected.

### Process notes

- **The requirement checkboxes and eight `human_needed` verification reports were all closed in one pass at milestone close**, against the two run sheets and the user's blanket sign-offs on each — not row by row as the work landed. The traceability table was written on 2026-09-20 and never updated as Phases 43 and 44 ran. Every ✓ in this milestone's archive should be read with that provenance.
- **Neither run sheet is a completed tick-list.** Phase 43 was continuous play-testing, feature by feature, each defect fixed and re-tested on the same client. Phase 44's sheet states plainly that its Part 2 per-feature table was not itemised.
- **Phases 42 and 43 were swapped** on 2026-09-22: clean the code first, then review the cleaned code. Seven status lines written on 2026-09-21 still say "deferred to Phase 42" and mean Phase 43.
- **Phase 39 does not exist.** It was renumbered to 35.1 so that the config panel, which owns container create/delete, lands before the phase that builds user containers.
- **No test suite exists** — no build manifest, no `luacheck`, no automated regression gate. Every claim rests on in-game observation.
- `stylua` clean at exit; `.gitattributes` pins `*.lua` to `eol=crlf`, though `.md` files remain bare `text=auto` and can still be reflowed invisibly.

---

_See `.planning/milestones/v0.4.0-ROADMAP.md` for full phase details._
_See `.planning/milestones/v0.4.0-REQUIREMENTS.md` for requirement-level traceability._

---
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
