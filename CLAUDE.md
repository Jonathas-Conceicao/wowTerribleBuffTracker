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
- `Display.lua` — visual timer bars and buff icons, anchored to CDM
- `ConfigUI.lua` — config window for adding/removing tracked buffs
- `scripts/install.bat` — copies addon to WoW retail addons folder
- `scripts/release.bat` — tags and pushes a release (GitHub Actions handles packaging)
- `.github/workflows/release.yml` — BigWigs Packager action for CurseForge/Wago/GitHub releases
- `.pkgmeta` — BigWigs Packager config

## Patterns
- Namespace: `local addonName, ns = ...` shared across all files
- SavedVariables: `TerribleBuffTrackerDB` (account-wide)
- Active timers are runtime-only (not persisted)
- UI uses BackdropTemplate, bars created on demand and pooled
- Display positioning and bar width are read from CDM; all other styles are hardcoded
- Addon icon: `tbt_icon_64x64.blp` (BLP format required by WoW, PNG kept as source)

## Workflow
- Always run `stylua` on Lua files after finishing a task
- Deploy to WoW with `./scripts/install.bat` (works on Windows)
- Release with `./scripts/release.bat <version>` — tags and pushes; GitHub Actions builds and uploads

## Testing
- `/tbt` or `/terriblebufftracker` toggles config
