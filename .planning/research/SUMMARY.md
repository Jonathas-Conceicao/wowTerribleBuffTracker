# Project Research Summary

**Project:** TerribleBuffTracker
**Domain:** WoW addon cross-flavor packaging — adding WoW Forever (`camelot`, Interface 16001, beta) as a second supported flavor alongside WoW Midnight retail (Interface 120100)
**Researched:** 2026-09-18
**Confidence:** HIGH on the packaging/TOC mechanics that gated this milestone; MEDIUM-LOW on anything that can only be settled by logging into the Forever beta client

## Executive Summary

This milestone is metadata and tooling only: one TBT package, unchanged behavior, running on two clients. The central blocking question — which TOC suffix the WoW client reads for Forever — is now resolved with high confidence: **`TerribleBuffTracker_Camelot.toc`, not `_Vanilla.toc`**, backed by five independent sources including Blizzard's own shipped Forever-beta TOC files and a live, unauthenticated API this synthesis re-queried directly during writing. No `.pkgmeta` or `release.yml` changes are required — the already-pinned BigWigs packager auto-discovers `_Camelot`-suffixed TOCs today. The almost entirely shared Lua/XML codebase should load and run on Forever essentially unmodified: every structural dependency TBT has (Cooldown Manager, Edit Mode, the secret-value API, the spell-info API) was diffed directly against Blizzard's `forever-beta` source branch and found unchanged or additive-only.

The one confirmed code-level defect this research surfaces is narrow and flavor-agnostic: `Providers.lua`'s `RefreshAtRest` for the Trinket and Pot providers unconditionally falls back to a hardcoded retail item when nothing on the character matches, and — unlike the cast-detection path, which is a genuine harmless no-op on Forever — this fallback is guaranteed to resolve to a *real* retail spellID (it's pulled from the same static table), not "no match." Whether that renders as a misleading real retail icon/name or degrades to a harmless placeholder depends on whether Forever's client-side spell database still contains retail-exclusive spell data — an empirical question no source review can answer. A small, flavor-agnostic defensive-read fix is recommended and is in-scope as parity work.

The largest risk isn't Forever at all — it's regressing the already-shipping retail install while doing the rename. Renaming the existing `TerribleBuffTracker.toc` to `TerribleBuffTracker_Mainline.toc` is the step most likely to silently break real users with zero error dialog if anything about it is wrong. The second-largest risk is a case-sensitivity trap on `_Camelot` that is invisible on the developer's Windows machine and only surfaces on GitHub's case-sensitive Linux runner (or possibly the client itself). Both are mitigated below. Beyond packaging, the single highest-value unknown that in-game testing must resolve first is whether `UNIT_SPELLCAST_SUCCEEDED` delivers a usable numeric `spellID` on Forever — TBT's entire timer-tracking architecture has no fallback if it doesn't.

## Key Findings

### Recommended Stack

Two hand-maintained TOC files at repo root (`TerribleBuffTracker_Mainline.toc` @ Interface 120100, `TerribleBuffTracker_Camelot.toc` @ Interface 16001) referencing one identical, unforked Lua/XML file list. No new libraries, no packager flags, no workflow YAML changes. `install.bat` gains a loop over `_retail_` and `_classic_beta_` target folders (both TOCs copied to whichever exist; the client picks the one it understands).

**Core technologies:**
- WoW client TOC flavor-suffix system (`_Mainline`/`_Camelot`) — client-native multi-flavor mechanism, zero runtime code changes, matches the locked split-TOC decision
- `## Interface: 120100` (Midnight) / `## Interface: 16001` (Forever) — both independently re-derivable from live `.build.info` version strings via `concat(major, pad2(minor), pad2(patch))`
- BigWigs Packager (`BigWigsMods/packager@v2`, currently resolving to `v2.6.1`) — already recognizes the `_Camelot` suffix and the `16???`->`forever` interface-prefix mapping; no config change needed

### Gating Question — Resolved

**`TerribleBuffTracker_Camelot.toc` is correct. `TerribleBuffTracker_Vanilla.toc` would be wrong** (that suffix is reserved for Classic Era, a different game type, despite Forever currently piggybacking on the `wow_classic_beta` product/`_classic_beta_` folder during beta — a red herring).

Evidence (HIGH confidence, no contradictions found across independent sources):
1. Blizzard's own shipped `Blizzard_CooldownViewer.toc` / `Blizzard_EditMode.toc` on the `forever-beta` branch declare `## AllowLoadGameType: standard, camelot` — Blizzard never writes `vanilla` for Forever anywhere.
2. warcraft.wiki.gg's TOC_format page explicitly tables `camelot` -> `_Camelot.toc` and `vanilla` -> `_Vanilla.toc` (Classic Era only) as separate rows.
3. `BigWigsMods/packager`'s `release.sh` source: suffix regex includes `Camelot` (not `Vanilla`) for game type `forever`; `game_flavor["camelot"]="forever"`.
4. Wago's own live, unauthenticated API (**re-queried directly during this synthesis**, see below) lists `"forever": ["1.60.1"]` with `toc_suffixes.forever = ["-Camelot","_Camelot","-Forever","_Forever"]`, entirely disjoint from `classic`'s `["-Classic","_Classic","-Vanilla","_Vanilla"]`.
5. Third-party build-tool corroboration (`McTalian-WoW-Addons/wow-build-tools` PR #245) independently reaches the same mapping after examining TACT configuration.

**Re-derivation recipe for future beta builds:** read the product's version string `X.Y.Z` from `.build.info` (or a WoWUI branch's latest commit message), compute `Interface = X + zero-pad-2(Y) + zero-pad-2(Z)`. This reproduces `120100` from `12.1.0` and `16001` from `1.60.1` exactly and is the same formula the packager itself uses. The packager's own interface-prefix match (`16???`) is deliberately loose, so routine Forever beta bumps (e.g. `16001`->`16010`) will keep resolving to `forever` without any packager-side changes — only `TerribleBuffTracker_Camelot.toc`'s own literal `## Interface:` value needs manual bumping to track the live beta build, or the *client* (not CI) will show TBT as out of date.

**Adjudicated conflict — CurseForge/Wago distribution readiness:** STACK.md rated this HIGH across both stores; PITFALLS.md rated it LOW/unverifiable. Re-running the exact unauthenticated Wago probe independently during this synthesis (`curl -s https://addons.wago.io/api/data/game`) reproduces STACK's finding verbatim: `forever` is a live, first-class patch family with its own accepted TOC suffixes. **Verdict: Wago support is HIGH confidence, confirmed by a live endpoint, re-verified twice now by two independent passes.** CurseForge is a different story — the only evidence is that `gameVersionTypeID=88568` exists as a queryable filter on curseforge.com and in the packager's internal map; neither researcher could confirm CurseForge's authenticated upload path actually accepts a Forever tag, since `CF_API_KEY` is deliberately disabled and no source could query the authenticated endpoint. **PITFALLS.md's caution is right specifically for CurseForge, not for Wago** — treat CurseForge acceptance as MEDIUM/unverified until either an authenticated probe or a real (throwaway/alpha) upload is attempted.

### Architecture Approach

One shared Lua/XML file set, forked only at the TOC layer. `Providers.lua`'s dispatch architecture (`ns:DispatchEventToProviders`, `ns:GetDisplayInfoForKey`) already isolates flavor-specific data behind runtime lookups rather than flavor conditionals — this is the right existing pattern and needs no redesign. `WOW_PROJECT_ID` branching should not be added preemptively; every currently-known Forever difference is already handled by data-absence/structural discovery, not by anything that needs to know which flavor it's running on.

**Major components:**
1. `TerribleBuffTracker_Mainline.toc` / `TerribleBuffTracker_Camelot.toc` — the only duplicated artifacts; identical bodies, differing only in `## Interface:` (and cosmetic `## Notes:`)
2. `scripts/install.bat` — loops over candidate client folders, copies the shared file set + both TOCs to whichever exist, fails loudly if zero targets found
3. `Providers.lua` (`TrinketProviderMixin`/`PotProviderMixin`) — needs one narrow, flavor-agnostic defensive-read fix in `RefreshAtRest`/`GetDisplayInfo` (see adjudicated conflict below); every other provider needs no change

### Adjudicated conflict - Is the trinket/pot at-rest fallback a real defect?

ARCHITECTURE.md flagged a concrete defect in RefreshAtRest (confirmed by reading Providers.lua directly during this synthesis, lines ~285-327 for Trinket, ~383-419 for Pot): when nothing equipped/in bags matches the static TRINKET_SPELLS/POT_SPELLS tables, the method falls back unconditionally to TRINKET_FALLBACK_ORDER[1] (itemID 249344) / POT_FALLBACK_ORDER[1] (itemID 241308). Critically, FindSpellByItemID looks these fallback itemIDs up against the very same static table they were drawn from, so the lookup is guaranteed to succeed and return a real, valid retail spellID - this is structurally different from the OnTrigger cast-detection path, which is a genuine harmless no-op because Forever characters simply cannot produce a matching cast event at all.

FEATURES.md concluded the degraded output would be a generic placeholder ("Trinket"/question-mark icon), reasoning that C_Spell.GetSpellInfo returns nil for a spellID that doesn't exist on Forever. This is not confirmed by source - WoW clients have historically shipped a shared spell/item name-and-icon database across game modes (a Classic client can often resolve a retail-only spellID's name/icon because that data isn't stripped per flavor), so GetSpellInfo may well succeed on Forever for a genuinely retail-exclusive trinket spell, in which case the Suggested tile would show a real retail item's icon and name that no Forever character can ever obtain - precisely the "plausible-looking but wrong" outcome ARCHITECTURE.md described, not FEATURES.md's "harmless generic placeholder."

Verdict: ARCHITECTURE.md is correct that this is a genuine, confirmed code-level asymmetry worth fixing (a small, flavor-agnostic defensive-read guard: don't trust the fallback until you confirm it resolves to something real and obtainable - the same fix also helps a retail alt with nothing equipped/in bags). FEATURES.md is correct that no crash or Lua error will occur either way, and its "this bucket may end up empty" framing correctly captures that the OnTrigger no-op path needs no fix. Whether the fix's specific mechanism (an existence check) actually prevents the wrong-icon case, versus a harmless-placeholder case, is not resolvable from source - it depends on whether Forever's client ships the full retail spell database. This is a genuine unknown requiring in-game testing (see checklist below), and the fix should still be made regardless of the answer, since it strictly improves correctness on both flavors.

### Critical Pitfalls (ranked)

1. **The rename trap (highest consequence)** - `git mv TerribleBuffTracker.toc TerribleBuffTracker_Mainline.toc` looks trivial but is the one change that can silently break the existing, shipping retail install with no error dialog (addon vanishes from the list, or loads flagged "out of date"). Mitigate by: doing the rename as its own isolated commit; immediately reloading a real retail client and confirming the load chat print + /tbt still work; and temporarily keeping the old unsuffixed TerribleBuffTracker.toc alongside both new suffixed files as a zero-cost rollback safety net (verified: the packager's discovery loop adds every TOC variant it finds with no "ambiguous name" conflict once package-as is explicitly set, which it already is). Remove the unsuffixed TOC only in the milestone's cleanup phase, after both flavors have been verified in-game for at least one release cycle.
2. **Case-sensitivity trap on `_Camelot`** - the packager's suffix regex requires a capital C, and the file-discovery glob is a literal, case-sensitive bash match. Windows/NTFS is case-insensitive, so a locally-created TerribleBuffTracker_camelot.toc (lowercase) looks completely normal in Explorer, in any editor, and to `dir` - but silently fails to match on GitHub's ubuntu-latest runner (and very likely in the WoW client's own case-sensitive suffix match too). This is invisible until CI or in-game testing. Mitigate by creating _Camelot.toc as a literal copy of the working _Mainline.toc with only the Interface/Notes lines edited - never retype the suffix from memory - and verify the committed filename via `git ls-files`, never a Windows file browser.
3. **Interface-version drift between the two TOCs** - with two independent Interface values, a wrong number in either file makes the packager hard-error the entire release (including an unrelated retail bugfix tag), not just the affected flavor. A cheap pre-tag guard (regex-check each TOC's interface falls in its expected range, plus a body-diff confirming the two file lists stay identical) catches this before it reaches a tag push. See guard justification below.
4. **Distribution metadata gaps** - CurseForge's actual acceptance of a Forever version tag is unverified (see adjudicated conflict above); a live version-lookup miss on either store doesn't fail the release, it just silently omits the Forever tag (easy to scroll past in a green CI run). Mitigate by reading the full CI log, not just the pass/fail status, and by treating a Forever-only upload gap as a store-side backfill issue, not a code bug - the zip itself is still correct.
5. **Beta volatility** - Forever's beta build/interface can move under the milestone; the packager's loose interface-prefix match absorbs routine bumps, but _Camelot.toc's own literal Interface value must still be manually kept current, or the client (not CI) flags TBT as out of date independent of any code correctness.

### Adjudicated conflict - Packaging work scope, and is a CI guard justified?

STACK.md and ARCHITECTURE.md both concluded correctly that no .pkgmeta or release.yml edits are required - the packager already auto-discovers _Camelot-suffixed TOCs by brace-expansion, verified directly from release.sh source by multiple researchers independently. PITFALLS.md's proposed "packaging/distribution verification phase" and CI guard are not in conflict with this - they operate at a different layer: nothing needs to change in the packaging config, but the milestone still needs to verify the packager behaves as documented on this specific beta build, and to guard against the two TOCs drifting apart in ways the packager only catches at tag time with a generic error message.

Recommendation: adopt the lightweight version of the guard, but keep it small and scoped.

- Justified and recommended: a short shell/CI step (or an install.bat-embedded check) that regex-validates each TOC's Interface value falls in its expected range and diffs the two TOCs' file-list bodies for equality. This is roughly 10 lines, directly protects against the milestone's two highest-named risks (Pitfalls 1 and 3 above), and mechanically enforces the locked "one shared file list" decision rather than leaving it as an unenforced convention. Small, cheap, targeted - worth building this milestone.
- Premature and out of scope this milestone: any new CI machinery around CurseForge/Wago upload verification (e.g. automated authenticated version-list checks). CF_API_KEY/WAGO_API_TOKEN are deliberately disabled and re-enabling them is explicitly out of scope per the locked "metadata and tooling only" constraint. The equivalent verification this milestone should do is a manual, one-off, unauthenticated probe (exactly the Wago curl command re-run above, plus unzipping a built artifact to confirm both TOCs are present) - not a standing CI job. Building CF/Wago upload-verification automation now, before tokens even exist, is speculative machinery for a concern (live store acceptance) that can't be fully resolved without the tokens anyway.

### In-Game Verification Checklist (consolidated, deduplicated, ordered by risk/payoff)

Run against a real Forever beta character, in this order, after the TOC-split gate passes:

1. **Addon loads** - install via the Camelot TOC, log in, confirm the "TerribleBuffTracker loaded..." chat line and no red Lua error at PLAYER_ENTERING_WORLD. Confirm via `/run print(C_AddOns.GetAddOnInfo("TerribleBuffTracker"))` if the list entry itself is in doubt.
2. **CDM attaches** - confirm the "Attached to Cooldown Manager" chat line, not "Cooldown Manager not found".
3. **CDM settings/TBT tab injects** - `/tbt` opens CooldownViewerSettings with the TBT tab visible below Blizzard's own tabs, all four sections open with no error.
4. **Cast detection fires (highest-priority check)** - add any real spell by ID, drag to Tracked Bars, cast it. This is the single check that resolves whether UNIT_SPELLCAST_SUCCEEDED delivers a usable spellID on Forever, which everything else in this addon depends on.
5. **Bar/icon rendering** - compare against CDM's own atlas-based visuals; a broken atlas texture would indicate an undocumented Forever atlas-name change.
6. **Edit Mode end-to-end** - enter/exit, drag containers, confirm the settings popup and NineSlice overlay work, confirm position persists across /reload.
7. **Combat secret-value gating** - enter combat, confirm no uncaught Lua error from any aura read (Midnight's known "blocked" behavior should reproduce, not crash).
8. **Sated/Lust allowlist, if content permits** - as a class with lust access, confirm the 40s timer starts even in combat; as any class, confirm the Suggested tile still renders without error if no lust content exists yet.
9. **Trinket/Pot placeholder behavior** - hover the Suggested tiles; confirm no Lua error, and specifically note which degraded state appears (generic placeholder vs. a real-but-wrong retail item name/icon) - this is the empirical answer the adjudicated conflict above depends on, and should be recorded either way.
10. **Foundational-globals sanity** - confirm Escape closes the Add Buff dialog (UISpecialFrames still works).
11. **Fresh-Forever-WTF-tree check** - confirm a brand-new Forever install loads TBT with zero tracked buffs and zero errors (rules out any cross-flavor SavedVariables assumption).
12. **Session hygiene** - test with a minimal addon list and /reload between sessions; do not run one long accumulating session (see platform caveats below).

### Features expected to be empty/meaningless on Forever - not bugs

- **Trinket Suggested tile** - will never trigger from any Forever cast; the static TRINKET_SPELLS table is keyed entirely to current-season retail spellIDs no Forever character can produce. Confirmed structurally impossible, not merely unlikely.
- **Pot Suggested tile** - same reasoning, same certainty.
- **Lust Suggested tile** - possibly empty, but genuinely uncertain rather than confirmed-empty: Bloodlust (2825) and Heroism (32182) are old, stable spellIDs plausible to exist on Forever; three of the five lust-family spells (Time Warp, Fury of the Aspects, Hunter's Harrier's Cry) depend on specs/classes that may not exist at Forever's current beta level cap. Treat as unknown until tested, not as a confirmed gap.
- **Blizzard's own CDM category suggestions** - third-party reports describe every C_CooldownViewer category as empty on Forever even for known/unlearned spells. This is a Blizzard-side content gap, not a TBT dependency (TBT never reads that category data) - don't mistake an empty Blizzard CDM list for a TBT failure.

### Genuine unknowns - only in-game testing can resolve these

1. **Does UNIT_SPELLCAST_SUCCEEDED deliver a usable numeric spellID on Forever?** The single highest-priority unknown - TBT's entire cast-detection architecture rests on it, and it cannot be checked from any UI-source diff (it's a core client/server event, not scripted Lua).
2. **Does the per-spell "never secret" allowlist for the Sated-family debuffs (LustProvider's in-combat detection) survive on Forever the way it does on Midnight 12.1?** This is live game data invisible to any API-doc diff.
3. **Does C_Spell.GetSpellInfo resolve retail-exclusive trinket/pot spellIDs on the Forever client?** Determines whether the confirmed RefreshAtRest fallback defect (see adjudicated conflict above) manifests as a misleading real item or a harmless placeholder.
4. **Does a Bloodlust/Heroism-equivalent lust effect exist in Forever's current beta content at all**, and at what level cap?
5. **Is COMBAT_LOG_EVENT_UNFILTERED available on Forever?** Recorded for awareness only - TBT is not changing its detection strategy regardless of the answer; this is explicitly out of scope for action this milestone.

### Platform/beta caveats that could cause false bug reports against TBT

- **SavedVariables may not load at all on this beta build.** A third-party bug report against the same build (1.60.1.69893) claims addon SavedVariables are written on logout but never read back in - every addon starts from hardcoded defaults every session. If TBT's config or Edit Mode positions don't persist across /reload on Forever, check whether other installed addons show the same symptom before concluding it's a TBT-specific regression.
- **The beta client stops delivering Lua errors after 100 errors in a single session** until the next /reload. If another addon is error-flooding, TBT's own errors could go silently unreported. Test with a minimal addon list and /reload between test sessions rather than one long accumulating session.

## Implications for Roadmap

Based on the combined research, the recommended phase decomposition reconciles ARCHITECTURE.md's "gate, then parallel, then sequential live-verification, then release-tooling-last" ordering with PITFALLS.md's per-pitfall phase mapping and FEATURES.md's checklist. Per .planning/PROJECT.md, numbering continues from Phase 24 (last v0.2.4 phase), so v0.3 starts at Phase 25.

### Phase 25: TOC Split & Retail Regression Gate
**Rationale:** This is the milestone's single blocking gate - nothing else should be considered done until a real retail client is confirmed unbroken and a real Forever client is confirmed to load the addon at all.
**Delivers:** TerribleBuffTracker_Mainline.toc (renamed, Interface 120100 unchanged) + new TerribleBuffTracker_Camelot.toc (Interface 16001), isolated rename commit, old unsuffixed TOC kept temporarily as rollback safety, plus the lightweight interface-range/file-list-diff guard.
**Addresses:** "Split flavor TOCs" target feature.
**Avoids:** Pitfall 1 (rename trap), Pitfall 2 (interface drift), Pitfall 3 (wrong-suffix silent failure) - each verified in-game immediately, not deferred.

### Phase 26: Install Tooling
**Rationale:** Independent of live client behavior once the TOCs exist - testable by filesystem inspection alone; can run in parallel with Phase 25's in-game verification.
**Delivers:** install.bat looping over _retail_/_classic_beta_ targets, copying the shared file set + both TOCs to whichever exist, failing loudly if zero targets found.
**Uses:** Stack/Architecture's per-client folder-detection pattern.
**Implements:** Locked decision - "installs to every client present, no arguments."

### Phase 27: Provider At-Rest Defensive Fix
**Rationale:** The one confirmed, flavor-agnostic code defect (see adjudicated conflict above) - small enough to code before live verification, but only fully verifiable against a live Forever character.
**Delivers:** A resolution-check guard in TrinketProviderMixin/PotProviderMixin's RefreshAtRest/GetDisplayInfo, so an unresolvable fallback yields "nothing at rest" instead of trusting a hardcoded retail item unconditionally. Also benefits retail edge cases (e.g. a fresh alt with empty bags/no trinket).
**Implements:** ARCHITECTURE.md's Anti-Pattern 2 mitigation, within the "parity fix, not new capability" constraint.

### Phase 28: Forever In-Game Verification Pass
**Rationale:** Requires a live Forever beta character; this is where every genuine unknown in this document gets resolved empirically rather than assumed from source.
**Delivers:** The consolidated 12-step checklist above executed and recorded against a specific beta build/interface number, plus fast-follow fixes for any Forever-only Lua error found (narrow defensive reads, never flavor branches).
**Addresses:** "In-game verification on Forever" target feature; resolves the UNIT_SPELLCAST_SUCCEEDED unknown, the Sated allowlist unknown, and the Phase 27 fix's actual effectiveness.
**Avoids:** Pitfall 5 (shared-source Forever-only breakage), Pitfall 6 (SavedVariables edge case), Pitfall 8 (verification gaps - nothing here should be inferred from the retail result).

### Phase 29: Packaging & Distribution Verification
**Rationale:** Depends on both TOCs being finalized; naturally last before shipping. No packaging code changes are needed, but the milestone still needs to verify the packager's documented behavior holds for this specific beta window.
**Delivers:** A cut (or dry-run) tag, unzipped artifact confirming both TOCs are present, full CI log scan for "no game version match" warning lines, and a manual unauthenticated re-probe of both stores' version endpoints (the Wago probe is already confirmed HIGH by this research; re-run it at release time as a freshness check, and attempt the equivalent CurseForge probe if any token becomes available).
**Avoids:** Pitfall 4 (distribution metadata gaps) - without building new CI machinery for it.

### Phase 30: Cleanup
**Rationale:** CLAUDE.md's standing GSD workflow requires a cleanup phase at the end of every milestone.
**Delivers:** Removal of the temporary unsuffixed TerribleBuffTracker.toc fallback (only after both flavors have shipped one verified release cycle), a review of install.bat/release.bat, a hot-path/dead-code pass over anything touched in Phase 27, and an explicit Forever-support note in CHANGELOG.md naming the tested beta build/interface number.

### Phase Ordering Rationale

- Phase 25 is a hard gate, not a parallelizable task - every other phase's work is unvalidated until a real client (both retail and Forever) confirms the TOC mechanism behaves as documented on this specific beta build.
- Phases 26 and 27 can be coded before the gate resolves (they're filesystem/logic checks respectively) but should only be marked verified after Phase 25's live confirmation and Phase 28's live Forever pass, respectively.
- Phase 28 is sequential and must follow the gate - it's the only phase that resolves the genuine unknowns (cast detection, Sated allowlist, provider fallback's actual rendering) that no source review can settle.
- Phase 29 is deliberately last - it depends on final TOCs and is the natural pre-release checkpoint, matching both ARCHITECTURE.md's ordering and PITFALLS.md's "before the public release tag" placement.
- Phase 30 closes the loop on the one piece of deliberate technical debt this milestone accepts (the temporary third TOC) and satisfies the standing CLAUDE.md cleanup requirement.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 27 (Provider At-Rest Defensive Fix):** the actual mechanism (existence-check granularity) depends on the unresolved question of whether Forever's client exposes the full retail spell database - worth a --research-phase pass to pin down the exact GetSpellInfo/GetItemInfo behavior before finalizing the guard's condition.
- **Phase 28 (Forever In-Game Verification Pass):** per PITFALLS.md, this is explicitly the phase most likely to warrant its own deeper research once real Forever API shapes are observed (e.g. if CDM's field/function shape diverges from Midnight's in a way the source diff didn't catch).

Phases with standard, well-documented patterns (skip --research-phase):
- **Phase 25 (TOC Split):** the suffix/interface mechanics are HIGH-confidence, multiply-corroborated, and this synthesis re-verified the live Wago data itself.
- **Phase 26 (Install Tooling):** a straightforward filesystem-loop change, no open questions.
- **Phase 29 (Packaging Verification):** no packaging code changes needed; this phase is a checklist, not new engineering.
- **Phase 30 (Cleanup):** standard, already-established pattern per CLAUDE.md's GSD workflow.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Interface numbers, TOC suffix mechanics, and packager behavior verified against Blizzard's own shipped Forever-beta TOCs, warcraft.wiki.gg, and packager source directly; the Wago live-API claim was independently re-verified during this synthesis and matches exactly. CurseForge upload-acceptance specifically remains MEDIUM (see adjudicated conflict). |
| Features | MEDIUM | HIGH for every structurally diffable API/UI dependency (CDM, Edit Mode, secret-value API, spell-info API) - all confirmed unchanged or additive-only between Blizzard's forever/live source branches. LOW for anything gated on live game data invisible to source (cast-event payload shape, per-spell secrecy allowlist, spell/item database scope) - correctly flagged as needing in-game testing rather than guessed at. |
| Architecture | HIGH | Packaging/topology conclusions verified directly against packager source and cross-checked by two independent researchers reaching identical "no config change needed" findings. MEDIUM on the provider-fallback defect's actual on-Forever manifestation - the code-level asymmetry is confirmed by direct read, but which failure mode it produces depends on an unverified client-data-scope assumption. |
| Pitfalls | MEDIUM | HIGH for packager/TOC mechanics (read directly from release.sh at a pinned commit). LOW for CurseForge/Wago live backend acceptance and the beta-timeline claims, both explicitly sourced from unofficial fan-site aggregation and flagged as directional-only by the researcher. |

**Overall confidence:** MEDIUM-HIGH. Everything that can be settled by reading source (packager, Blizzard's own shipped TOCs and Lua, warcraft.wiki.gg, and a live re-queried API) is HIGH confidence and mutually corroborated across all four research files with no unresolved contradictions after adjudication. Everything gated on live Forever beta behavior - cast-event payload, secret-value allowlist persistence, and the provider-fallback's actual rendering - is an honest, explicitly-flagged unknown that this milestone's own Phase 28 exists specifically to resolve.

### Gaps to Address

- **CurseForge Forever version-list acceptance** - unverified without an authenticated token; handle during Phase 29 as a manual probe (or accept the store-side tag omission as a known, non-blocking gap for this release).
- **Whether GetSpellInfo resolves retail-exclusive spellIDs on Forever** - directly determines the severity/nature of the Phase 27 fix's real-world effect; handle by explicitly recording the observed behavior during Phase 28's checklist item 9, and revisit Phase 27's exact guard condition afterward if needed.
- **UNIT_SPELLCAST_SUCCEEDED payload on Forever** - the load-bearing unknown for the entire addon; resolved by Phase 28's checklist item 4, first in priority order for a reason.
- **Sated-family secrecy allowlist persistence** - resolved opportunistically during Phase 28 if a lust-capable class/content combination is available to test; if not testable this milestone, document as a known gap rather than blocking the release on it.
- **Beta-platform noise (SavedVariables load reliability, 100-error session cap)** - not a TBT defect to fix; document in the milestone's testing notes so future bug reports against these specific symptoms are correctly triaged as platform issues first.

## Sources

### Primary (HIGH confidence)
- https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh (commit e50a250f, tag v2.6.1) - TOC-suffix discovery, interface validation, CurseForge/Wago upload logic, version-to-interface formula - read directly by three researchers independently.
- https://raw.githubusercontent.com/BigWigsMods/WoWUI/forever-beta/ Blizzard_CooldownViewer and Blizzard_EditMode source and TOC files - diffed directly against the live branch.
- https://addons.wago.io/api/data/game - live, unauthenticated, queried independently by two researchers and again during this synthesis; all three queries agree.
- https://warcraft.wiki.gg/wiki/TOC_format - TOC suffix table, AllowLoadGameType directive, Patch 9.1.0 origin of flavor-suffix support.
- User's local .build.info files and TerribleBuffTracker.toc/.pkgmeta/release.yml/install.bat/release.bat/Providers.lua - read directly from the repository, including a direct re-read of Providers.lua's RefreshAtRest/GetDisplayInfo during this synthesis to adjudicate the trinket/pot conflict.

### Secondary (MEDIUM confidence)
- https://github.com/McTalian-WoW-Addons/wow-build-tools/pull/245 - third-party corroboration of the _Camelot mapping and install-directory behavior.
- https://github.com/BigWigsMods/packager/pull/202 - establishes Forever packager support as freshly-landed (merged the day before this research) and contested during its own review.
- https://www.curseforge.com/wow/search - confirms a queryable game-version-type filter exists (gameVersionTypeId=88568), but not upload-time acceptance.
- Thunderz96/forever-addon-kit and Caeth/CleanCombatLog - dated, build-specific, live-captured third-party observations of Forever beta behavior (CDM globals present, combat-aura secrecy reproduces, CLEU availability an open question).

### Tertiary (LOW confidence)
- WebSearch-derived claims about CurseForge/Wago "not yet supporting Forever" and the beta's public end date - unofficial fan-site aggregation, flagged by the originating researcher as directional-only, not confirmed fact.
- The provider-fallback "shared client spell database" assumption underlying the trinket/pot defect's severity - historical WoW-client behavior pattern, not confirmed for this specific Forever build; needs Phase 28 in-game confirmation.

---
*Research completed: 2026-09-18*
*Ready for roadmap: yes*
