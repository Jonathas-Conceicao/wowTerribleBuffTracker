# TerribleBuffTracker

A WoW Midnight addon for tracking buff and cooldown timers that
Blizzard's Cooldown Manager doesn't support — such as active trinket
procs and other effects that lack proper API exposure.

Born from the player need to min-max our characters despite Blizzard's
API pruning in Midnight, TerribleBuffTracker provides a bad way to
track extra buffs, but that's the game we play now. Since combat
events are disabled and buff tracking are a storm of **[Secret
Value]**, the addon uses `UNIT_SPELLCAST_SUCCEEDED` combined with
known durations to track timers manually.

TerribleBuffTracker attempts to integrate directly into Blizzard's
Cooldown Manager, so it feels like a native part of the game's UI. You
configure tracked buffs through a dedicated tab in CDM settings,
drag-and-drop them between display modes, and position the timer
containers independently using Edit Mode.

## AI Usage

This addon was built with the help of [Claude AI](https://claude.ai/).
I'm an experienced Software Developer but very new to Blizzard's API
and game addon/modding development. Claude assisted with learning the
WoW addon API and writing the initial implementation. The addon is
maintained by me to the best of my abilities. Use at your own leisure
— and please complain to Blizzard until they make their UI complete so
we don't need ~~crap~~ stuff like this.

## Showcase

![Lust and trinket tracked](Assets/lust_and_trinket_tracked.png)
![Adding buffs](Assets/adding_buffs.png)
![Edit Mode](Assets/edit_mode.png)

## Features

- Track any spell by ID with a custom duration
- Timer bars and buff icon display modes
- **CDM Settings tab** — "TBT Buffs" tab inside the Cooldown Manager settings window
- **Drag-and-drop** — move buffs between sections or reorder them within a section
- **Edit Mode integration** — two movable containers (Bars and Buffs) with full Edit Mode support
- **Copy Blizzard CDM Config** — one-click import of CDM's current settings into TBT
- **Aura-based timer cancellation** — tracked buff timers automatically disappear when the buff is removed when info is not **Secret Values**
- **Lust / Heroism tracking** — automatic detection via Sated-family debuffs

## Usage

- `/tbt` — Open CDM settings with the TBT Buffs tab selected
- **Add buffs:** Click the "+" icon in the Suggested section, enter a Spell ID and duration
- **Organize:** Drag buffs between Tracked Bars, Tracked Buffs, and Not Displayed sections
- **Configure display:** Enter Edit Mode, click a TBT container, and adjust settings in the popup
- **Quick actions:** Right-click any buff icon for Move, Hide, or Remove options

## Lust / Heroism Tracking

TBT includes a built-in meta-buff for tracking all Bloodlust/Heroism
variants as a single entry. It works by detecting the **Sated-family
debuffs** (Sated, Exhaustion, Temporal Displacement) which are
allowlisted by Blizzard and readable even during combat and M+.

**How it works:**
- Open CDM settings (`/tbt`) and drag the "Lust / Heroism" icon from
  the **Suggested** section into Tracked Bars or Tracked Buffs
- When any lust is cast (by you, a party member, or via drums), the
  Sated debuff triggers a 40-second timer automatically
- The timer icon and name match the **actual lust used** — if a Mage
  casts Time Warp, you see the Time Warp icon regardless of your class
- In the CDM tab, the icon shows your **class-specific lust** (Time
  Warp for Mages, Fury of the Aspects for Evokers, Bloodlust for
  everyone else)
- The timer cancels automatically if the lust buff is removed (boss
  wipe mainly for early wipes where info is not **Secret Value**)

## Known Issues and Limitations

- Only Active Buffs can be tracked:  
Passive proc trinkets are currently not supported as Blizzard's API
hides buffs behind secret values while in any relevant contexts

- Aura cancellation delay in restricted contexts:  
In M+ and other secret-value contexts, buff cancellation detection
only kicks in after combat drops or zone changes. There may be a few
seconds of delay before a removed buff's timer disappears

## License

[WTFPL](LICENSE)
