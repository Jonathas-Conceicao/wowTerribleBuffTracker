# TerribleBuffTracker

WoW Midnight addon (Interface 120000) for tracking buff/cooldown timers manually.

## Key Constraints
- `COMBAT_LOG_EVENT_UNFILTERED` is disabled in Midnight — do NOT use it
- Spell/buff names are "Secret Values" — display only, cannot use in logic
- Spell IDs are safe for matching
- Use `UNIT_SPELLCAST_SUCCEEDED` for cast detection
- Use `GetTime()` + known durations for timer tracking

## Architecture
- `Core.lua` — namespace, init, event routing, slash commands
- `BuffEngine.lua` — timer management, tracked buff config
- `Display.lua` — visual timer bars
- `ConfigUI.lua` — config window for adding/removing tracked buffs

## Patterns
- Namespace: `local addonName, ns = ...` shared across all files
- SavedVariables: `TerribleBuffTrackerDB` (account-wide)
- Active timers are runtime-only (not persisted)
- UI uses BackdropTemplate, bars created on demand and pooled

## Testing
- `install.bat` copies to WoW beta addons folder
- `/tbt` toggles config, `/tbt reset` resets display position
