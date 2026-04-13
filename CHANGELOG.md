# Changelog

## v0.2.3 — Trinket & Pot Meta-Trackers

### New Features
- Trinket meta-tracker slot in the Suggested section — tracks current-season on-use trinkets;
- Damage pot meta-tracker slot in the Suggested section — tracks current-season damage potions;
- Trinket slot shows the icon of the first matching equipped trinket (slots 13/14); pot slot shows the icon of the first matching damage potion found in bags

## v0.2.2 — Lust Tracking Fixes

### Fixes
- Added Primal Rage (264667) detection via Fatigued debuff (264689)
- MM Hunter shows Harrier's Cry (466904) icon on CDM tab and preview
- Detection assumes Primal Rage due to the matching Fatigued debuff
  for both Primal Rage and Harrier's Cry

## v0.2.1 — Aura-Based Timer Cancellation

### New Features
- Timers for tracked buffs cancel automatically when the buff is no longer on the player
- Aura detection gated by secret value checks — automatically disabled in M+ and other restricted contexts
- Lust / Heroism timers start automatically when Sated, Exhaustion, Temporal Displacement, or Evoker Exhaustion debuffs are detected
- Class-aware lust icon: Mage sees Time Warp, Evoker sees Fury of the Aspects, others see Bloodlust
- Drag "Lust / Heroism" from the Suggested section to activate lust tracking
- Current-season drums (Void-touched Drums) supported as a lust trigger

### Improvements
- Preview timers no longer destroy active buff countdowns when CDM settings window is opened
- Extracted shared spell resolution helper to reduce code duplication across display and config files
- Removed unused code (tbtTabActive flag)

## v0.2.0 — Config & Edit Mode Rework

- New "TBT Buffs" tab inside Blizzard's Cooldown Manager settings window
- Four sections for organizing tracked buffs: Tracked Bars, Tracked Buffs, Not Displayed, and Suggested (WIP)
- Drag-and-drop buffs between sections to change how they display
- Reorder buffs within sections by dragging to a specific position
- Add new tracked buffs via the "+" button in the Suggested section
- Right-click context menu on any buff icon to move, hide, or remove it
- Delete drop zone in the Not Displayed section for quick buff removal
- Two independent movable containers (Bars and Buffs) in Edit Mode
- Click a container in Edit Mode to open its settings popup
- Per-container settings: Icon Size, Icon Padding, Bar Width, Opacity, Visibility, and more
- "Copy Blizzard CDM Config" button to import CDM settings into TBT with one click
- "Terrible Buff Tracker Settings" button in Edit Mode popup opens the CDM config tab
- Floating checkbox panel in Edit Mode to toggle TBT container visibility
- Preview timers show all tracked buffs when CDM settings window is open
- `/tbt` command now opens CDM settings with the TBT tab selected
- Old standalone config window removed

## v0.1.0 — Initial Release

- Manual buff and cooldown timer tracking for WoW Midnight
- Timer bars and buff icons anchored to Blizzard's Cooldown Manager
- Add/remove tracked buffs by Spell ID and duration
- Enable/disable individual buffs
- Display mode toggle per buff (bar or icon)
- Preview mode to test all tracked timers
- `/tbt` slash command for configuration
- BigWigs Packager CI/CD for CurseForge, Wago, and GitHub releases
