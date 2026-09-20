# TerribleBuffTracker

WoW Midnight addon (version 12.0 and up) for tracking buff/cooldown timers manually.

## Key Constraints
- `COMBAT_LOG_EVENT_UNFILTERED` is disabled in Midnight — do NOT use it
- Tracking buffs and debuffs is very limited; most values are hidden as "Secret Values"
- Secret Values may work in some contexts — guard these usages behind fail-safe calls when possible
- Spell IDs are often Secret Values themselves; the spellID from `UNIT_SPELLCAST_SUCCEEDED` is always safe to use for now
- Use `UNIT_SPELLCAST_SUCCEEDED` for cast detection
- Use `GetTime()` + known durations for timer tracking
- Requires Blizzard's Cooldown Manager (CDM) — no standalone fallback
- Two flavor TOCs ship from one shared Lua/XML file list: `TerribleBuffTracker_Mainline.toc` at Interface 120100 for Midnight retail (`World of Warcraft\_retail_`), and `TerribleBuffTracker_Camelot.toc` at Interface 16001 for WoW Forever beta (`World of Warcraft\_classic_beta_`, product `wow_classic_beta`, build 1.60.1.69913 verified 2026-09-18)
- The two TOCs may differ on `## Interface:` and `## Notes:` only — no flavor-forked Lua/XML file may exist. The `_Camelot` suffix is case-sensitive

## Architecture
- `Core.lua` — namespace, init, event routing, slash commands
- `BuffEngine.lua` — timer management, tracked buff config
- `EditModeFrames.lua` — Edit Mode containers, drag handles, position persistence, settings popup
- `Display.lua` — visual timer bars and buff icons
- `CDMTab.xml` — TBT tab button XML definition for CDM settings
- `CDMTab.lua` — CDM tab integration, sections UI, drag-and-drop, add/delete dialogs
- `scripts/install.bat` — argument-free deploy of the shared file set and both flavor TOCs to every WoW client folder present on the machine, skipping absent ones and failing when none are found
- `scripts/release.bat` — tags and pushes a release (GitHub Actions handles packaging)
- `scripts/check-toc.ps1` — pre-tag guard asserting the two flavor TOCs have not drifted
- `.github/workflows/release.yml` — BigWigs Packager action for CurseForge/Wago/GitHub releases
- `.pkgmeta-mainline` / `.pkgmeta-camelot` — BigWigs Packager config per flavor; identical shared config, each ignoring the other flavor's TOC so its own zip stays flavor-pure

## Patterns
- Namespace: `local addonName, ns = ...` shared across all files
- SavedVariables: `TerribleBuffTrackerDB` (account-wide)
- Active timers are runtime-only (not persisted)
- Display uses CDM atlas textures, StatusBar frames, SetScale(), and CooldownFrameTemplate — pixel-matching Blizzard's CooldownViewer templates
- Bars and icons are parented to Edit Mode container frames (TBTBarContainer, TBTBuffContainer)
- CDM settings (scale, padding, bar width, visibility, etc.) are cached via SnapshotSettings() on load, layout hooks, and EditMode.Exit — not read per-frame
- Reusable module-level tables wiped with `wipe()` each cycle to avoid GC pressure in hot paths
- Addon icon: `tbt_icon_64x64.blp` (BLP format required by WoW, PNG kept as source)

## Style Reference
- Blizzard UI source: `C:\Users\jonat\Repositories\wow-ui-source` (https://github.com/Gethe/wow-ui-source) — Midnight-only (branch `live`, 12.1.0); read-only, never check out another branch or modify this working tree, the user works in it
- WoW Forever UI source: `https://github.com/BigWigsMods/WoWUI` branch `forever-beta` — Blizzard's own shipped Forever TOCs (e.g. `Blizzard_CooldownViewer.toc`'s `## AllowLoadGameType: standard, camelot`) can be read as ground truth here
- CDM templates: `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml` and `.lua`
- Layout system: `Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua` and `GridLayoutUtil.lua`
- Edit mode: `Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`
- Always consult these sources when making visual or layout changes to match CDM behavior

## Workflow
- **NEVER overwrite or rewrite `CHANGELOG.md`.** The user edits and cleans up this file by hand, and their version is authoritative. Do not replace a section, do not "restore" content that looks missing, and never rewrite the file wholesale with a script. Append-only, and only when asked.
- **If you see any difference between `CHANGELOG.md` and what you expect — STOP and check with the user.** A diff is not evidence of a mistake to fix. It is almost certainly a deliberate edit. Show the user the diff, say what you think is missing and why, and wait. Violated 2026-09-19: a commit message describing changelog additions did not match the file, because the user had since rewritten the entry to be concise. That mismatch was read as a failed edit rather than an intentional cleanup, the whole v0.3.0 section was replaced by script, and the user's work was destroyed. A commit message is not a source of truth about current file contents, and a shorter entry is not a regression.
- Run `stylua` on Lua files from the repo root after finishing a task. The repo-root `stylua.toml` pins `line_endings = "Windows"`, so the bare invocation (no flags) is now correct — no caller needs to remember `--line-endings Windows`. This rule previously read "Always run `stylua`" with no config in place: the bare invocation reflowed files to LF, and because `core.autocrlf=true` with no `.gitattributes` makes the index `i/lf`, that reflow produced an empty `git diff` and left no trace, twice, before it was noticed
- After every commit, run a performance and code cleanup review — check for hot-path allocations, redundant per-frame work, dirty-check opportunities, and dead code
- Deploy to WoW with `./scripts/install.bat` (works on Windows)
- Release with `./scripts/release.bat <version>` — tags and pushes; GitHub Actions builds and uploads

## Testing
- `/tbt` or `/terriblebufftracker` toggles config

## GSD Workflow
- Start each new milestone on a dedicated branch
- Merge to main by squashing with a clean commit message summarizing all changes
- Always run a cleanup phase at the end of new milestones: clean up unused variables and definitions, unify repeated behavior **the milestone itself introduced** into shared functions, review hot paths (especially game loop tick functions), and check release scripts
- Code that predates the milestone is protected instead by `PROJECT.md`'s "No refactors during cleanup phases" Key Decision — read together the two rules are complementary, not contradictory: this mandate covers duplication a milestone introduces, `PROJECT.md`'s decision protects everything pre-existing. Settled by user decision, 2026-09-18 (Phase 30)
