---
created: 2026-09-22T00:00:00.000Z
title: A cooldown icon can still read grey for a moment around the GCD
area: display
files:
  - Display.lua
phase_hint: 42
---

## Problem

A cooldown tracker's icon occasionally shows grey while the spell is available. Reported in
play-testing on Forever, 2026-09-22, after the two fixes below had already landed:

> "there is still sometimes a gray skill due to gcd, maybe just when it's getting off-cd. No big
> deal for now."

Accepted as-is by the user in the same message — **do not treat this as a blocker**, and do not
change the current behaviour without asking. It is recorded so it is not rediscovered as new.

### What was already fixed, and why this is what is left

Two separate causes were found and closed before this residue:

1. **`Display.lua:615` raised** on `handle:IsActive() == true` — a secret boolean compared. The raise
   aborted the render mid-loop and left the icon on whatever desaturation it last had, which is what
   made the grey *stick* indefinitely. Fixed in `76b1c3e` by relaying the secret straight into
   `SetDesaturated` and never inspecting it.
2. **`SPELL_UPDATE_COOLDOWN` does not fire when a cooldown ENDS** — only when one starts. So nothing
   re-evaluated the icon at the moment it became available. Fixed by hooking `OnCooldownDone` on the
   widget, which is the same hook Blizzard's own viewer uses (`CooldownViewer.lua:1404-1406`).

What remains is narrower and self-correcting: a brief grey around the GCD as a spell comes off
cooldown, rather than a permanent one.

## Likely cause

The grey and the sweep deliberately read two different handles:

```lua
local ok, realCooldown = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)  -- ignoreGCD
icon.icon:SetDesaturated(realCooldown:IsActive())
```

`ignoreGCD = true` is what stops the GCD greying every icon on the bar — the original complaint. The
suspicion is a **timing** one rather than a logic one: when the real cooldown and the GCD end close
together, the icon is re-evaluated on an event whose ordering relative to the GCD is not guaranteed,
so it can sample `IsActive()` one frame before the handle flips. TBT cannot check this by reading —
`IsActive()` returns a secret and comparing it is the bug that started all of this.

## Solution sketch

Do not add a comparison. The options that stay inside the relay rule:

- Re-issue the desaturation from `OnCooldownDone` on the **GCD-inclusive** handle as well as the
  real one, so whichever ends last triggers a final re-evaluation.
- Or drop the event dependency for this one property and re-relay `SetDesaturated` every tick for
  icons with an active cooldown stamp. It is one C setter per cooldown icon per tick with no read
  and no branch, which is cheap, but it undoes part of Phase 38's dirty-check work — measure before
  choosing it.

Reproduce first. The user has no reliable repro; without one, any fix here is unfalsifiable.
