# Phase 78: Human Testing — retail checklist

**Client:** Midnight retail only. Forever is not tested this milestone (servers down, user decision
2026-10-22).
**Build under test:** branch `milestone/v0.5.3-buff-duration-alongside-cooldowns`, deployed by
`./scripts/install.bat`. **Do a full client restart** before testing if the TOC was ever re-deployed;
otherwise `/reload` is enough.
**Requirement:** VER-13 — every v0.5.3 requirement checked in game in one pass.

Mark each line pass / fail. On a fail, note what you saw; it becomes a gap-closure item.

## Result — PASSED (user, 2026-10-23)

- **Visuals (section C):** "100% what I requested".
- **Combat/M+ (#7, #29, #30):** pass.
- **Logout → login (#10, #26):** pass.
- **Item edit dialog (#19–23):** pass.
- **Install (#27):** pass. The `install.bat` output names `_forever_` and no `_classic_beta_`.
- **Gap fix (section G, #31–32):** pass.
- **Charge count during the buff (#14):** **skipped** by the user.
- **#21 decision:** the item's plain Aura ID and "Ends when you cast" fields stay hidden ("lgtm").
- **Everything else:** covered by "seems to be working in general".

## A. Spell cooldown dialog (BUFFCD-01, BUFFCD-02)

1. Cooldowns tab → Add → Advanced tab: an unticked **Track buff duration** checkbox, a greyed
   **Aura ID** showing the Spell ID, and an empty greyed **Duration**.
2. Tick the box: both boxes enable; "Enter the buff duration" shows and Add stays disabled until a
   duration is typed. Clearing the Aura ID shows "Enter the buff's Aura ID". Tab skips greyed boxes.
3. Untick: Add works, the two boxes keep their text.
4. Edit the tracker: it reopens with the saved values. Buffs and Reminders dialogs show none of the
   three fields. The Duration box on cooldowns, buffs and reminders still prefills, validates and saves.
5. Chat line on edit reads as before ("Updated <label> (<kind>, ID: <ids>, <n>s).").

## B. Spell cooldown buff timer (BUFFCD-03, BUFFCD-04, BUFFCD-08)

6. Cast the spell with the buff on: the buff countdown shows on the cooldown's own icon; nothing
   appears as a separate tile or bar. A tracker in a bar container starts no buff.
7. Click the buff off / let it be dispelled (out of combat): it ends after the short cast grace.
   In restricted content it never ends early.
8. Recast restarts the buff. "Resets when you cast" ends both the cooldown and its buff.
9. Edit while the buff runs: changing the Aura ID keeps it running; changing the Duration ends it;
   turning the buff off ends it.
10. `/reload` and a real **logout → login** keep the settings (only the running timer is dropped).
    Trackers that existed before this build load with the buff off.

## C. The look (BUFFDISP-01..05)

11. While the buff runs: full **yellow fill that clears** as time passes, icon in full colour, no
    edge, no cooldown sweep.
12. When the buff ends (expires or cancelled) with the cooldown still running: the dark sweep with
    edge and a **grey** icon appear at once.
13. Neither running: full colour, no sweep. A cooldown with its buff off looks exactly as before.
14. A charge spell with its buff on keeps its **charge count** during the buff and after it.
15. Buffs-tab, Reminders-tab, Trinket and Pot icons keep the dark swipe.
16. Preview (Edit Mode and the CDM settings window): a buff-on cooldown previews yellow with its
    typed duration; a buff-off cooldown previews dark.
17. Container "Show Timer" off hides the swipe in both looks.
18. Rearrange / spec-swap so icons reorder while cooldowns run: each icon keeps its own sweep and
    grey (Phase 75 WR-02 fix).

## D. Bag items (BUFFCD-05, BUFFCD-06, BUFFCD-07)

19. A bag item moved out of Suggested shows **Edit**; a Suggested item tile does not.
20. The dialog is titled **Edit Item Tracker**, opens on Advanced, and the portrait shows the item's
    icon, name and tooltip.
21. Spell ID (empty), Duration (the item cooldown) and Load (Always) are greyed with their labels and
    cannot be edited. (Decision for you: the item's plain *Aura ID* and *Ends when you cast* fields
    are **hidden**, not greyed, because an item never has a value for them — say if you want them
    greyed instead.)
22. The buff checkbox starts off; its Aura ID and Duration start **empty** and the Aura ID never
    copies anything. Ticked, Save is blocked until both are filled.
23. Save prints "Updated <item> (item, buff Ns)." and nothing else changes (section, count, cooldown).
24. Use the item: yellow buff countdown on the **item's own icon** (never a question mark), count
    kept, then the item cooldown. Item tooltip on hover during the buff and in the preview.
25. Click the aura off (out of combat): the buff ends early. A hidden item starts nothing.
26. `/reload` and logout → login keep the item's buff settings; later item cooldown refreshes do not
    overwrite the typed buff duration.

## E. Install (INST-11)

27. `./scripts/install.bat` reports `_retail_` and `_forever_`, never `_classic_beta_`.
28. Housekeeping: an old TBT copy still sits in `_classic_beta_\Interface\AddOns\TerribleBuffTracker`
    (Phase 73 review WR-01, declined by your decision). Delete it by hand if you no longer use that
    client.

## F. Regression

29. No Lua errors during the whole pass (BugSack / `/console scriptErrors 1`).
30. A short M+ or raid pull with a buff-on cooldown: no errors, no taint, the buff behaves.

## G. Gap fix found in this pass (2026-10-22/23)

The user asked for a cooldown's buff that is already up to be picked up, and for its timer to
follow the aura's real duration. The fix (commits `838e93c`, `09f36aa`, `469ff35`) is the
cooldown-buff half of `ns:RefreshAuraStates`, which shares the reminder refresh's read and sync. The
typed Duration is never rewritten (user decision).

31. A flask's buff is picked up after `/reload`, with its real remaining time. **Pass (user,
    2026-10-23).**
32. An engineering item that extends the buff (to 9d, out of combat) is followed, and the timer
    goes back to the regular duration when that buff is lost. **Pass (user, 2026-10-23).**

The broader "one aura pass for all three kinds" review went to the backlog as 999.28.
