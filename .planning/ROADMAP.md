# Roadmap: TerribleBuffTracker

## Milestones

- [x] **v0.3.0 WoW Forever compatibility** — Phases 25-30 (shipped 2026-09-19) — [archive](milestones/v0.3.0-ROADMAP.md)
- [x] **v0.2.0 Config & Edit Mode Rework** — Phases 1-6 (shipped 2026-03-30) — [archive](milestones/v0.2.0-ROADMAP.md)
- [x] **v0.2.1 Aura-Based Timer Cancellation** — Phases 7-11 (shipped 2026-04-04) — [archive](milestones/v0.2.1-ROADMAP.md)
- [x] **v0.2.3 Trinket & Pot Meta-Trackers** — Phases 12-16 (shipped 2026-04-13) — [archive](milestones/v0.2.3-ROADMAP.md)
- [x] **v0.2.4 SpellProvider Refactor** — Phases 17-24 (shipped 2026-04-22) — [archive](milestones/v0.2.4-ROADMAP.md)

## Phases

<details>
<summary>✅ v0.3.0 WoW Forever compatibility (Phases 25-30) — SHIPPED 2026-09-19</summary>

- [x] **Phase 25: TOC Split & Retail Regression Gate** — `TerribleBuffTracker_Mainline.toc` (120100) + `TerribleBuffTracker_Camelot.toc` (16001) from one shared file list, plus `scripts/check-toc.ps1` as a pre-tag drift guard. Both in-game gates PASSED 2026-09-18
- [x] **Phase 26: Install Tooling** — argument-free `install.bat` deploying the shared file set and both TOCs to every present WoW client, skipping absent ones, failing when none are found
- [x] **Phase 27: Provider At-Rest Defensive Fix** — Trinket and Pot tiles no longer present an unresolved hardcoded item as real; shared neutral placeholder. Verified on both flavours
- [x] **Phase 27.1: Forever Testing Enablers (INSERTED)** — TOOL-01 spell+aura ID tooltip, META-01 data-driven meta-tile hide, lust tooltip fix, drag nil-call fix. Inserted mid-milestone on user approval because the milestone was otherwise untestable
- [x] **Phase 28: Forever In-Game Verification Pass** — build `1.60.1.69913`, zero failures. `UNIT_SPELLCAST_SUCCEEDED` confirmed to deliver a usable spellID; two Forever-only defects found and fixed
- [x] **Phase 29: Packaging & Distribution** — `.pkgmeta-mainline`/`.pkgmeta-camelot` and a serialised two-flavour matrix in `release.yml`. Implementation complete; `DIST-03`…`DIST-07` deferred to the first real tag push by user decision
- [x] **Phase 30: Cleanup** — dead `TRINKET_FALLBACK_ORDER` removed, `stylua.toml` + `.gitattributes` root-cause fix for the invisible-diff bug, hot-path audit verdict `NONE`, release scripts reviewed end to end

**Closed:** 25/30 requirements. **Deferred to first release:** `DIST-03`…`DIST-07`.
**Known issue at ship:** settings do not persist between sessions on the Forever beta — a client-side bug, not TBT's.

</details>

<details>
<summary>v0.2.0 Config & Edit Mode Rework (Phases 1-6) — SHIPPED 2026-03-30</summary>

- [x] **Phase 1: Data Migration** — Expand SavedVariables schema and backfill existing entries
- [x] **Phase 2: Edit Mode Containers** — Two independently movable containers registered with Edit Mode
- [x] **Phase 3: CDM Tab Shell** — Tab button injection and content panel frame; old config UI removed
- [x] **Phase 4: CDM Tab Sections** — Four sections rendered from DB state with Add button and delete drop zone
- [x] **Phase 5: Drag-and-Drop** — Buff drag between sections with ghost frame, drop zone highlighting, and delete zone
- [x] **Phase 6: Cleanup** — Dead code removal, hot-path audit, stylua, release prep

</details>

<details>
<summary>v0.2.1 Aura-Based Timer Cancellation (Phases 7-11) — SHIPPED 2026-04-04</summary>

- [x] **Phase 7: Safety Infrastructure** — Grace period, blocked flag, reset triggers, and preview guard wired before any scan logic
- [x] **Phase 8: Aura Scan and Cancellation** — UNIT_AURA handler and scan function that silently cancel timers for absent buffs
- [x] **Phase 9: Zone Transition Handling** — Post-login and zone-exit scans to catch buffs stripped by loading screens
- [x] **Phase 10: Lust Tracking** — Sated-family debuff detection auto-starts lust timer; class-aware meta-buff icon in CDM tab
- [x] **Phase 11: Cleanup** — Hot-path audit, stylua, recentlyCast table growth check, release prep

</details>

<details>
<summary>v0.2.3 Trinket & Pot Meta-Trackers (Phases 12-16) — SHIPPED 2026-04-13</summary>

- [x] **Phase 12: Schema Migration + Data Tables** — TRINKET_SPELLS (9) / POT_SPELLS (4) spellID-keyed tables, SUGGESTED_BUFFS entries, DATA-03 N/A reconciliation
- [x] **Phase 13: Timer Functions + Cast Detection** — OnSpellCastSucceeded fan-out with metaSlot tagging and shared-slot overwrite; in-game spell ID verification
- [x] **Phase 14: Icon Resolution + Caching** — ns.metaIcons cache, RefreshMetaIcons (combat-gated CSV-order fallback), GetAtRestMetaIcon helper, StartPreview hook, Display placeholder fix; ICON-06 N/A reconciliation
- [x] **Phase 15: Display Integration + Active Icon Switching** — Verification-only (ICON-03/04 satisfied by Phase 13 + 14 architecture)
- [x] **Phase 16: Cleanup** — stylua pass, dead-code scan (no-op), CHANGELOG v0.2.3 entry, PROJECT.md Validated block, .pkgmeta release-notes annotation

</details>

<details>
<summary>v0.2.4 SpellProvider Refactor (Phases 17-24) — SHIPPED 2026-04-22</summary>

- [x] **Phase 17: Provider Skeleton + UserSpellProvider** — Providers.lua with interface contract; UserSpellProvider wired through dispatch loop
- [x] **Phase 18: TrinketProvider + PotProvider + BuffEngine Dispatch** — All cast-triggered providers active; BuffEngine dispatch loop replaces hardcoded branches; activeProcs lifecycle established
- [x] **Phase 19: LustProvider + UNIT_AURA Dispatch** — LustProvider with pre-gate ordering; UNIT_AURA routed through provider dispatch; all four providers complete
- [x] **Phase 20: GetDisplayInfo + Dispatch Helper** — GetDisplayInfo on all four providers; ns:GetDisplayInfoForKey exported; provider-owned RefreshAtRest (PROV-F3 pulled forward); trinket/pot 0-second preview bug fixed at provider layer
- [x] **Phase 21: Preview Mode Migration** — Additive preview architecture; separate ns.previewTimers; fixes mid-CDM real-cast loss as architectural side-effect
- [x] **Phase 22: Display.lua Unification** — Zero type-specific branches; single shared tooltip handler; per-widget icon cache
- [x] **Phase 23: CDMTab.lua Unification** — All icon/tooltip resolution through ns:GetDisplayInfoForKey; META_DESCRIPTIONS demoted to file-local
- [x] **Phase 24: Cleanup** — Dead code removal (3 shims + 2 exports), RefreshMetaIcons → RefreshProvidersAtRest rename, stylua pass, v0.2.4 CHANGELOG, interface 120005 bump

</details>

## Backlog

### Phase 999.1: Edit Mode container selects on click-release instead of click-down (BACKLOG)

**Goal:** Match Blizzard's native Edit Mode selection behavior — TBT containers (bars/buffs) should highlight and open settings popup on mouse-DOWN, not mouse-UP. Currently the container only appears selected after releasing the click, which makes drags feel laggy because the highlight doesn't appear during the drag motion.

**Requirements:** TBD

**Context:**
- Reported in v0.2.4 Phase 18 human-verify session (2026-04-21)
- Affected files: `EditModeFrames.lua` — check OnMouseDown vs OnMouseUp handlers on `TBTBarContainer` / `TBTBuffContainer`
- Reference: Blizzard's `EditModeSystemTemplates.lua` in `wow-ui-source` at `C:\Users\jonat\Repositories\wow-ui-source`

Plans:
- [ ] TBD (promote with `/gsd:review-backlog` when ready)

### Phase 999.2: Refresh README and store descriptions for Forever + CDM changes (BACKLOG)

**Goal:** The README and the addon's public descriptions on CurseForge and Wago tell a current story —
that TBT runs on WoW Forever as well as Midnight retail, and that Blizzard's Cooldown Manager has moved
under us since these descriptions were written.

**Requirements:** TBD

**Raised:** 2026-09-19, by the user, immediately after v0.3.0 shipped. **Flagged for the next
milestone** — the user asked to be reminded of this one at milestone start.

**Why it matters now:** v0.3.0 shipped two downloads and Forever support, and none of the public-facing
copy says so. A user landing on the CurseForge page cannot tell that a Forever build exists, or which
of the two zips to take.

**Scope:**

1. **README** — the opening line still reads "A WoW Midnight addon". It is a two-flavour addon now.
   Mention Forever, the two downloads and which client each is for, and the interface numbers
   (120100 / 16001). `PROJECT.md`'s "What This Is" was corrected at v0.3.0 close and can be reused as
   source copy.
2. **CurseForge and Wago descriptions** — same update, plus the Forever beta storage caveat (settings do
   not persist between sessions; a client bug, not ours; retail unaffected), so Forever users are not
   surprised into filing it as a TBT bug.
3. **Recent CDM changes** — **user report, 2026-09-19: Blizzard's Cooldown Manager now tracks trinkets
   and potions natively.** The descriptions still imply TBT is the only way to see these, which would be
   stale and slightly misleading.

**The part that is more than a docs task — do not let this get buried under "update the README":**

If CDM really does track trinkets and pots natively, TBT's Trinket and Pot meta-trackers may be wholly
or partly redundant on retail. That is a product question, not a copy question, and it has three
possible answers worth costing out before any wording is chosen:

- The meta-trackers stay as-is, because CDM's version is missing something (no custom durations, no bar
  display, no Forever coverage — Forever ships no retail spell data, so `META-01` already hides those
  tiles there).
- They are narrowed to the gap CDM leaves.
- They are retired on retail, which would be the first feature TBT has ever removed and needs a user
  decision plus a migration story for anyone with `"trinket"` / `"pot"` keys already in `trackedBuffs`.

**Verify before writing any copy.** This is a user report and has not been confirmed against the live
client or `wow-ui-source`. Check `Blizzard_CooldownViewer` on the `live` branch at
`C:\Users\jonat\Repositories\wow-ui-source`, and read what CDM actually surfaces in-game, before
claiming anything about it in a public description — and before deciding what happens to the
meta-trackers.

**Context:**
- Affected: `README.md`, plus the CurseForge and Wago project descriptions (edited on those sites, not
  in the repo — worth noting that no repo change can fix the store copy)
- `FTOOL-01` is related but separate: CurseForge/Wago *upload* credentials are still deliberately
  disabled, so v0.3.0 published to GitHub releases only. Store descriptions can be updated by hand
  regardless.
- The two pre-existing README limitations (passive proc trinkets unsupported; aura cancellation delayed
  in restricted contexts) are still accurate and should survive the rewrite.

Plans:
- [ ] TBD (promote with `/gsd:review-backlog` when ready)

### Phase 999.3: Evaluate the single-TOC setup, and settle which TOC Forever loads (BACKLOG)

**Goal:** Decide — deliberately, not by drift — whether TBT keeps two flavour-suffixed TOCs or collapses
to one, now that the assumption behind the two-TOC design has been contradicted.

**Requirements:** TBD

**Raised:** 2026-09-19, from the WoWUI Discord community FAQ. Full intake and analysis:
`.planning/research/FOREVER-COMMUNITY-FAQ.md`.

**The finding:** the community states **Forever is classed as `mainline`, intentionally — so
`_Mainline.toc` also loads on Forever**, and recommends a single-TOC setup as the fix. This directly
contradicts `research/STACK.md` line 121, which recorded at MEDIUM confidence that "each file is only
ever discovered under its own flavor already." The two-TOC design rests on that assumption.

**What is and is not at risk:**
- **Published zips: safe.** Each carries exactly one TOC (verified by unzipping the real v0.3.0 assets),
  so no end user ever has both files. `DIST-04` genuinely holds.
- **Deployed dev copies: safe right now** — checked on disk 2026-09-19, each client holds only its own
  TOC — but `install.bat` copies **both** TOCs to **every** client by design, so the next run puts two
  loadable TOCs back into the Forever folder.

**Settle this first, it is cheap and it gates the rest:** `TOC-02` is marked verified because the addon
loaded on Forever and worked, which does **not** prove which TOC was read. Print
`C_AddOns.GetAddOnMetadata("TerribleBuffTracker", "Interface")` on a Forever character. If it says
`16001`, `_Camelot.toc` won and the risk is theoretical. If it says `120100`, the entire Forever
verification pass was run against the retail TOC and needs redoing.

**Then decide.** The new directives make one TOC feasible — `## Title: ... [AllowLoadGameType standard]`
style conditional metadata covers exactly the two lines (`## Interface:`, `## Notes:`) our TOCs differ
on, and there is per-file gating too. See the FAQ intake for the full table.

**Do not migrate unprompted — it collides with a locked user decision.** One TOC implies one package
loading everywhere, which is the "single multi-flavour zip" option the user **explicitly rejected** in
favour of two flavour-pure zips. Migrating also retires `check-toc.ps1`, both `.pkgmeta-*` files and the
CI matrix — machinery that works, is guard-verified and shipped. The upside is that it deletes this whole
bug class and is what the community recommends. **User's call.**

**Context:**
- `RETAIL-REGRESSION-PASS.md`'s note that "the client ignores the one whose flavour does not match" rests
  on the contradicted assumption, at least in the Forever direction
- The FAQ warns the `ExcludeLoadGameType` syntax **will change**, so anything built on it needs revisiting
- Patch 12.1.5 also recognises `_Standard.toc` as retail-only, an alternative to `_Mainline.toc`

Plans:
- [ ] TBD (promote with `/gsd:review-backlog` when ready)

### Phase 999.4: Addon shows `@project-version@` as its in-game version (BACKLOG)

**Goal:** The addon reports a real version number in its in-game metadata — the character-select AddOns
list, the in-game addon panel, and any external addon manager — instead of the literal string
`@project-version@`.

**Requirements:** TBD

**Raised:** 2026-09-19 by the user, flagged **for the next milestone**. Restated by the user: the zip is
fine, *"the addon shows in-game as this string instead of an actual version. This is what needs to be
fixed."* **The in-game metadata is the deliverable.** Do not close this by explaining the zip is correct.

**Cause, established 2026-09-19 from disk:**

| Artifact | `## Version:` reads | Why |
|---|---|---|
| Repo source (both TOCs) | `@project-version@` | Correct — a packager keyword, meant to sit there |
| Published v0.3.0 zips, both flavours | `v0.3.0` | Substitution works at package time |
| **Every install on this machine** | **`@project-version@`** | **The symptom** |

`install.bat` does a plain `copy /Y` of the repo TOC straight into the AddOns folder. It never passes
through the BigWigs packager, which is the only thing that expands `@project-version@`. So the copy that
is actually *running* always carries the raw keyword, and that is what the client reads for its metadata.

Checked all four WoW client folders — `_retail_`, `_classic_beta_`, `_ptr_`, `_beta_`. **Every one is a
dev deploy; not one is a zip install.** So there is currently no install anywhere on the machine that
would show a real version, which is exactly the reported experience.

Also confirmed: TBT's Lua never reads its own version (`grep` for `GetAddOnMetadata` returns nothing), so
there is no in-addon display to fix — only the TOC the client reads.

**Fix direction (not decided):** have `install.bat` substitute a version while copying, instead of a bare
`copy /Y`. Constraints:
- **Never modify the repo's own TOC files.** Substitute into the deployed copy only, on the way past. A
  hardcoded version in the repo TOC would break the packager keyword the real releases depend on, which
  currently works.
- The value must be unmistakably a dev build — `git describe --tags --dirty` output, or `<version>-dev`.
  A bare `0.3.0` sitting in a dev folder would be worse than the raw keyword, which is at least honest
  about being unsubstituted.
- `check-toc.ps1` reads the repo TOCs, not the deployed ones, so it should be unaffected — confirm rather
  than assume.
- `install.bat` is also named in the open todo `2026-09-18-runtime-file-set-enumerated-three-places.md`;
  worth doing in one pass.

**Related finding while checking this — stale TOCs are worse than recorded.** `install.bat` copies but
never prunes, and the damage is concrete:
- `_beta_` holds **three** TOCs, one of them a pre-v0.2.0 leftover declaring `## Version: 1.0.0`
- `_ptr_` holds **three** TOCs
- `_retail_` and `_classic_beta_` are clean, one TOC each

A stale unsuffixed `TerribleBuffTracker.toc` is not inert — it is a loadable TOC, and on `_beta_` it
advertises version `1.0.0`. This compounds Phase 999.3 (`_Mainline.toc` may also load on Forever): an
addon manager or client reading the wrong file gets wrong metadata, and during v0.3 a stale retail TOC
nearly invalidated the whole retail verification pass for exactly this reason. Tracked separately as
`2026-09-18-install-bat-does-not-prune-stale-files.md`, but fix it alongside this — a version fix that
leaves three TOCs in place has not fixed what the user sees.

**Context:**
- Affected: `scripts/install.bat`. No TOC, Lua or CI change is implied.
- Verify the fix the way the bug was found: deploy, then read `## Version:` from the deployed TOC and
  check the in-game AddOns list, not the repo or the zip.

Plans:
- [ ] TBD (promote with `/gsd:review-backlog` when ready)
