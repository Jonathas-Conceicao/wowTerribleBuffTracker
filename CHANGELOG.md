# Changelog

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
