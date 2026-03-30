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

## Architecture
- `Core.lua` — namespace, init, event routing, slash commands
- `BuffEngine.lua` — timer management, tracked buff config
- `EditModeFrames.lua` — Edit Mode containers, drag handles, position persistence, settings popup
- `Display.lua` — visual timer bars and buff icons
- `CDMTab.xml` — TBT tab button XML definition for CDM settings
- `CDMTab.lua` — CDM tab integration, sections UI, drag-and-drop, add/delete dialogs
- `scripts/install.bat` — copies addon to WoW retail addons folder
- `scripts/release.bat` — tags and pushes a release (GitHub Actions handles packaging)
- `.github/workflows/release.yml` — BigWigs Packager action for CurseForge/Wago/GitHub releases
- `.pkgmeta` — BigWigs Packager config

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
- Blizzard UI source: `C:\Users\jonat\Repositories\wow-ui-source` (https://github.com/Gethe/wow-ui-source)
- CDM templates: `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml` and `.lua`
- Layout system: `Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua` and `GridLayoutUtil.lua`
- Edit mode: `Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`
- Always consult these sources when making visual or layout changes to match CDM behavior

## Workflow
- Always run `stylua` on Lua files after finishing a task
- After every commit, run a performance and code cleanup review — check for hot-path allocations, redundant per-frame work, dirty-check opportunities, and dead code
- Deploy to WoW with `./scripts/install.bat` (works on Windows)
- Release with `./scripts/release.bat <version>` — tags and pushes; GitHub Actions builds and uploads

## Testing
- `/tbt` or `/terriblebufftracker` toggles config

## GSD Workflow
- Start each new milestone on a dedicated branch
- Merge to main by squashing with a clean commit message summarizing all changes
- Always run a cleanup phase at the end of new milestones: clean up unused variables, definitions, unify repeated behavior into shared functions, review hot paths (especially game loop tick functions), and check release scripts
