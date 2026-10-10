# Changelog

## v0.5.2 — Improved Merge Mode, small fixes and drop racials on Forever

Merge Mode has been reworked and improved, better performance and
fixed some edge case bugs. Dropped the Forever Racial Meta trackers
as CDM now supports them all.

### New Features
- Added Meta Reminder for Divine Spirit on Forever
- Rebuilt and improved Merge Mode, no new configuration needed

### Removed
- Dropped the support for Racial Meta Trackers on Forever, you can
  still create your custom racial trackers if you want, just like any
  other spell

### Fixes
- Charge counts going stale after spec or talent change
- Another player's debuffs overlapping with the tracked Player ones
- Centered layout being misaligned due to overlapped debuff
- Icons being overtaken by some debuffs like Mind Control 

## v0.5.1 — Clickable reminders and new icons

Adding clickable buttons to reminders so you can easily cast your
buffs when the game allows it.

### New Features
- Clickable reminders - All suggested buffs come with the clickable
  spell ready to be used, custom reminders can set up custom spells
- On by default - On Edit Mode you can disable this new clickable cast
  functionality for the whole container
- Added class-buffs reminders to retail:
  - Mage: Arcane Intellect and Arcane Familiar
  - Priest: Power Word: Fortitude
  - Druid: Mark of the Wild and Symbiotic Relationship
  - Warrior: Battle Shout
  - Shaman: Skyfury and Lightning Shield
  - Evoker: Blessing of the Bronze and Source of Magic
  - Paladin: Devotion Aura, which is also satisfied by Concentration or Crusader Aura
- New icons for the TBT tabs, the colors are faction themed

### Fixes
- Selecting a TBT container in Edit Mode no longer clears Blizzard
  selection, this avoids some edge cases of addon taint that could
  cause the whole UI to need a reload
- In Merge Mode, spell charges can still be visible while the buff is up
- Turning Merge Mode off doesn't leave buffs behind anymore

## v0.5.0 — Buff Reminders and Elaborate Tracking

Adding direct support for Buff Reminders, a tracker that shows only
after a buff (usually a class buff) is lost.

### New Features
- Reminders - New category of buffs that appear only when you need to
  refresh them
- Edit trackers - Right-click any user-created tracker to edit it
- Reworked the add custom tracker dialog - We now have more
  configuration options
  - Spell Preview - Spell icon and full tooltip for what you're adding
  - Custom clears - You can set up that other skills will fire the
    tracker you're creating
  - Secrecy info - Indicator that an Aura/Spell can be secret and
    custom tracking will be limited
  - New style - The popup window matches the CDM window now
  - Separate Aura ID - Track a buff whose aura ID differs from the
    spell's
  - "End when the aura is lost" - Allows you to avoid auto-cancellation
- Class buff reminders (Forever) - Suggested reminders for class buffs:
  - Mage: Arcane Intellect, Frost Armor
  - Priest: Power Word: Fortitude
  - Druid: Mark of the Wild, Thorns
  - Warrior: Battle Shout
  - Hunter: Trueshot Aura
  - Warlock: Blood Pact
  - Paladin: Blessings and Righteous Fury
- Load rule - Every tracker can load "When known", "Always" or
  "Never".
- Merge mode by default - New installs start with merge mode on.

### Fixes
- Item trackers on screen now show the item's full tooltip (if enabled
  in Edit Mode).

## v0.4.1 — Generic Item Tracking, Pandemic support and Forever Racials

Adding support for tracking items' cooldowns, Pandemic indicator on
Merge mode and Forever Racials.

### New Features
- **Consumable tracking** - Consumable items you have now show on
  suggested section and you can drag them to any container for
  cooldown and quantity tracking
- **Pandemic and dispel outline support** - Tracked spells from Merge
  mode now show pandemic on retail and dispel outline indicators when
  available
- **Forever Racials** - Suggested buffs and cooldowns now offer
  trackers for all racials

## v0.4.0 — Cooldown Tracking and Full CDM View

Big update with Cooldown tracking, full CDM view and extra
containers. Working for both Midnight and Forever.

### New Features
- **Merge mode** - Use TBT has your hole Cooldown Manager and have
  custom trackers alongside Blizzard's CDM containers
- **Cooldown trackers** - Custom skills along side Blizzard's CDM
  cooldowns and buffs
- **Extra containers** - You can create extra containers for custom
  trackers of your buffs or cooldowns
- **Center aligment** - The buff container can be center-alligned
- **Forever Racial Trackers** - Still in early stages, tracking Gnome,
  Troll and Orc racials, with support for all races comming soon

### Fixes
- Merged buffs no longer drift out of position inside a container
- Edit mode container selection now happens on click press instead of
  release

## v0.3.0 — WoW Forever Support

Initial support on WoW Forever beta build (interface 16001).

### New Features
- Mousing over a spell or aura now shows its spell ID in the tooltip

### Fixes
- Dragging a buff between sections no longer throws a stream of Lua
  errors on WoW Forever

### Known Issues
- **Settings do not persist between sessions on WoW Forever beta.**
  This seems to be a bug in the beta client, not in this addon.

## v0.2.6 — CDM Tab Placement Fix

### Fixes
- The TBT tab no longer sits behind 12.1's new "Group Buffs" tab — it is
  now anchored under whichever Blizzard tab is bottom-most, so a tab added
  by a future patch pushes ours down instead of covering it
- The Group Buffs tab no longer stays highlighted while the TBT panel is open

## v0.2.5 — 12.1 Compatibility

Bumped WoW interface version to 12.1 (120100).

### Fixes
- Fixed the Lua error thrown in combat on 12.1
- Lust / Heroism tracking keeps working in combat, and a lust that was
  already running when it is first seen now shows the correct
  remaining time instead of restarting at 40s
- The Sated debuff lingering after a lust ends can no longer start a
  phantom timer
- Timer cancellation no longer acts on a buff whose aura cannot be
  read

## v0.2.4 — SpellProvider Refactor

Internal file reworking — no user-visible changes.

- Bumped WoW interface version to 12.0.5 (120005)

## v0.2.3 — Trinket & Pot Meta-Trackers

### New Features
- Trinket meta-tracker slot in the Suggested section — tracks current-season on-use trinkets;
- Damage pot meta-tracker slot in the Suggested section — tracks current-season damage potions;
- Trinket slot shows the icon of the first matching equipped trinket
  (slots 13/14); pot slot shows the icon of the first matching damage
  potion found in bags

### Fixes
- Restored "Display Mode" option (Icon And Name / Icon Only / Name Only) in the bars Edit Mode popup

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
