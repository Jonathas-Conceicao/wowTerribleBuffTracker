# Phase 85: Forever Testing Pass — checklist

**Clients:** WoW Forever first (`_forever_`), then a short retail sanity pass.
**Build under test:** branch `milestone/v0.5.6-more-forever-reminders`, already deployed by
`./scripts/install.bat`. No TOC change this milestone, so `/reload` is enough.
**Requirement:** VER-15. Rows you check move from "(unverified in game)" to verified; rows you
can't reach stay unverified. That's expected, not a failure.

**How to check an ID:** hover the buff and read TBT's ID tooltip line. To see a new reminder, open
the CDM settings → TBT tab → Suggested, and place it.

Mark each line pass / fail / skipped. On a fail, note what you saw; it becomes a fix.

## A. Mage — the priority (MREM-07, MREM-18, CLICK-07)

1. Suggested offers **Ice Armor** and **Mage Armor** (only the ones you know) next to Frost Armor.
2. With no armor up, the armor reminders show. Cast any armor: **every** armor reminder hides,
   and a 30 min timer starts.
3. ID tooltip on each armor buff reads its row ID's rank: Ice Armor 7302/7320/10219/10220,
   Mage Armor 6117/22782/22783.
4. Suggested offers one **familiar** reminder (needs Comprehend Scroll). With no familiar up it
   shows.
5. Out of combat, **click** the familiar reminder: it uses the best scroll your level allows (Cat
   at 25+, else Frog at 16+, else Rat). The familiar buff appears, the reminder hides, and a 60 min
   timer starts.
6. ID tooltip on the familiar buff reads 1302303 (Cat), 1302285 (Frog) or 1296202 (Rat).
7. Move or use up scrolls (for example, remove all Cats), then click again: it falls through to the
   next tier. With no usable scroll the icon still shows and a click does nothing.
8. **Answer:** does a new tier replace a lower one (Cat over Rat)? Does the familiar stack with
   Arcane Intellect?
9. **Answer:** do Amplify Magic and Dampen Magic stack on you? They're grouped as "one hides
   both". If they stack, the group should be split.
10. Amplify / Dampen: casting either hides both reminders (10 min).
11. If another mage can buff you: their Arcane Intellect (any rank) or Arcane Brilliance hides your
    Arcane Intellect reminder.

## B. Group buffs and blessings (RALT-05, RALT-06, MREM-06)

12. Prayer of Fortitude, Prayer of Spirit or Gift of the Wild from someone else hides the matching
    single-target reminder (where you can get one).
13. Paladin: any blessing or Greater Blessing (Kings, Might, Wisdom) on you hides every blessing
    reminder.
14. A **Blessing of Salvation or Light** reminder placed before this build: its tile is greyed,
    says "no longer offered", and Suggested no longer lists it.

## C. Other classes — any you can reach (MREM-08..16)

15. Warlock: Demon Armor / Demon Skin, where either one hides both.
16. Warlock: Demonic Sacrifice. Sacrificing any demon hides it, and a 120 min timer starts.
17. Shaman: Lightning Shield / Water Shield, where either one hides both. **Check Water Shield's ID
    tooltip reads 408510** (it's a reused ID).
18. Priest: Inner Fire (10 min); Shadowform (no timer, shows once you leave form); Shadowguard
    offered only to a Troll; Shadow Protection hidden by Prayer of Shadow Protection.
19. Paladin: one Devotion Aura reminder, hidden by any paladin aura.
20. Hunter: one Aspect of the Hawk reminder, hidden by any aspect (Monkey, Cheetah, Pack, Wild,
    Beast).
21. **Durations to confirm** (they differ from Classic): Battle Shout 3 min, Demonic Sacrifice
    2 h, Divine Spirit 60 min.

## D. Every other click unchanged (CLICK-07)

22. Click a few other reminders out of combat: each casts its spell. In combat a click does nothing.

## E. Retail sanity

23. Retail: Suggested offers no new reminder. Arcane Intellect, Fortitude, Mark of the Wild,
    Battle Shout and Devotion Aura behave as before. Reminder clicks work as before.

## F. Review doc

24. Skim `docs/REMINDERS.md`. Do the Wowhead `/forever/` links open the right spells? Is anything
    listed under "Not included" that you want?
