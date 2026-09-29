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
- **One TOC, all flavours.** `TerribleBuffTracker.toc` declares `## Interface: 120100, 16001` — Midnight retail (`World of Warcraft\_retail_`) and the WoW Forever beta (`World of Warcraft\_classic_beta_`, product `wow_classic_beta`, build 1.60.1.69913). This follows the pattern shipping addons on Forever use (e.g. Platynator declares six interface versions in one TOC and no `## AllowLoadGameType:` line). Superseded the two-TOC split on 2026-09-20
- No flavor-forked Lua/XML file may exist. Add a new interface version to the existing `## Interface:` list rather than adding a second TOC

## Architecture
- `Core.lua` — namespace, init, event routing, slash commands
- `BuffEngine.lua` — timer management, tracked buff config
- `Providers.lua` — SpellProvider registry and event dispatch (Trinket, Pot, Lust, racial and class-buff meta trackers, user spells)
- `MergeMode.lua` — Merge Mode: mirrors the player's CDM configuration through C_CooldownViewer only and parks Blizzard's viewers off-screen, never touching a CDM frame
- `EditModeFrames.lua` — Edit Mode containers, drag handles, position persistence, settings popup
- `Config.lua` — TBT's own settings panel under Options > AddOns (`/tbt`), shown standalone where the Settings API is missing
- `Display.lua` — visual timer bars and buff icons
- `CDMTab.xml` — TBT tab button XML definition for CDM settings
- `CDMTab.lua` — CDM tab integration, sections UI, drag-and-drop, add/delete dialogs
- `TerribleBuffTracker.toc` — the one TOC for every flavour; its load list is the shipped file set
- `scripts/install.bat` — thin wrapper that forwards to install.ps1; `./scripts/install.bat` stays the documented entry point
- `scripts/install.ps1` — derives the file set from the TOC, deploys it to every WoW client folder present on the machine, substitutes a dev version in the deployed TOC only, and prunes files the repo no longer has
- `scripts/release.bat` — tags and pushes a release (GitHub Actions handles packaging)
- `scripts/aura-read-gate.js` — static proof that every aura API reference sits inside an allowlisted reader (DTRK-06); `--selftest` runs its fixtures
- `scripts/migrate-dryrun.js` — dry-runs the ADDON_LOADED defaults and schema migrations against a real SavedVariables file; `--selftest` runs its fixtures
- `tools/TBTProbe/` — throwaway API probe harness, never shipped (ignored by `.pkgmeta`)
- `.github/workflows/release.yml` — BigWigs Packager action for CurseForge/Wago/GitHub releases
- `.pkgmeta` — BigWigs Packager config; one config, one zip covering every interface version the TOC declares

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
- Run `stylua .` from the repo root after finishing a task. A bare `stylua` (no path) exits with "error: no files provided"; `stylua .` picks up the repo-root `stylua.toml`, whose `line_endings = "Windows"` means no caller needs to remember `--line-endings Windows`. This rule previously read "Always run `stylua`" with no config in place: the bare invocation reflowed files to LF, and because `core.autocrlf=true` with no `.gitattributes` makes the index `i/lf`, that reflow produced an empty `git diff` and left no trace, twice, before it was noticed
- **A `.gitattributes` now exists** (added Phase 30, 2026-09-20) and pins `*.lua`, `*.xml`, `*.toc`, `*.bat`, `*.ps1` to `eol=crlf` and `*.yml`, `.pkgmeta`, `stylua.toml` to `eol=lf`. The sentence above is kept for the history but is no longer the current state for source files. **The blind spot is only half closed:** Markdown and everything else still fall under the bare `* text=auto`, so for `.md` files a CRLF→LF reflow is still invisible to `git diff`. Confirmed 2026-09-23 on a controlled fixture: `sed -i` strips CR from **every** line of a CRLF file, including lines it did not match, and on a `text=auto` file `git diff` then reports nothing. **Never use `sed -i`, or any redirect over a source file, on anything in `.planning/` or on a `.md` file** — use the Edit tool, and assert with `git ls-files --eol <path>` afterwards. `grep`/`awk` cannot see this; only `git ls-files --eol` can
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
