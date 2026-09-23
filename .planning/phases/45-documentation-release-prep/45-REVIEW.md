---
phase: 45-documentation-release-prep
reviewed: 2026-09-23T06:49:20Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - README.md
  - CHANGELOG.md
findings:
  critical: 0
  warning: 3
  info: 1
  total: 4
status: issues_found
---

# Phase 45: Code Review Report

**Reviewed:** 2026-09-23T06:49:20Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Phase 45 touches exactly `README.md` and `CHANGELOG.md`. Confirmed via
`git diff --stat 82bf7b6..HEAD -- '*.lua' '*.toc' '.pkgmeta' 'scripts/'` (empty output): zero
source files, the TOC, `.pkgmeta` or any script changed in this phase — the phase's own claim
holds.

Most of the concrete, checkable claims in both files hold up against the shipped code: the
interface versions (`120100`, `16001`) match `TerribleBuffTracker.toc` line 1 exactly; the four
built-in container titles (`Tracked Buffs`, `Tracked Bars`, `Essential Cooldowns`,
`Utility Cooldowns`) match `Core.lua`'s `ns.CONTAINERS` table verbatim, including which are
icon-only; the racial spell IDs (Orc `20572`/`1299026`, Gnome `1259817`, Troll `20554`) match
`Providers.lua`'s `RACIAL_SPELLS` table exactly; `/tbt`/`/terriblebufftracker`, the
`Options > AddOns` panel, the `Copy Blizzard CDM Config` button label, the `30s`/`2m` duration
examples, and all five Sated-family debuff names are all verified accurate against source. The
banned DOC-05 comparative-claim strings (`doesn't support`, `does not support`, `natively`,
`already tracks`) are absent from both files — the old "Blizzard's Cooldown Manager doesn't
support" line is confirmed removed by the diff. No local paths, account/character names,
SavedVariables paths, or CurseForge/Wago project IDs appear in either file. No repo-relative or
GitHub-only-rendering Markdown links exist between `## Features` and `## License` in README.md.
The three public Known Issues agree in substance between the two files.

Three claims do not hold up against the shipped code, all in README.md, all Warning-severity per
the review brief's guidance for this category (a claim the code does not support, not a crash or
security defect):

1. The CDM tab is described as a single "TBT" tab that splits into "Buffs" and "Cooldowns" — the
   code implements two independent sibling tab buttons, not a parent/child pair.
2. The Merge Mode bullet claims a merged buff icon "draws no cooldown sweep" — the opposite of
   what the code implements (Phase 40's engine-driven `AuraContainer` sweep) and what the
   project's own canonical retail-pass record confirms shipped and tested.
3. The racial trackers bullet omits that the entire feature is Forever-exclusive, unlike the
   sibling "Rank grouping" bullet which is explicitly labelled "Forever-only."

## Warnings

### WR-01: CDM tab described as one parent tab with two sub-tabs; it is two sibling tabs

**File:** `README.md:12-14` (intro) and `README.md:50-51`, `README.md:65-66` (Features/Usage)
**Issue:** README states: "TerribleBuffTracker configures through a dedicated tab inside
Blizzard's Cooldown Manager (CDM) settings window" (intro) and, more specifically, "The Cooldown
Manager settings window carries a **TBT** tab, itself split into **Buffs** and **Cooldowns**
tabs" (Usage, line 65-66) and "The **CDM settings tab**, with Buffs and Cooldowns tabs..."
(Features, line 50-51). This describes one parent "TBT" tab containing two child tabs.

The code implements two independent, equally-ranked tab buttons — `TBTSettingsTab` (labelled
"TBT Buffs") and `TBTSpellsTab` (labelled "TBT Cooldowns") — both anchored directly in the CDM
settings window's own tab column, one below the other, alongside Blizzard's native tabs
(`CDMTab.lua:1548-1590`, `AnchorTabBelowCDMTabs` at `CDMTab.lua:1516-1536`). There is no single
"TBT" tab and no parent/child relationship; a user opening the settings window sees two
separately-labelled buttons, "TBT Buffs" and "TBT Cooldowns", not one "TBT" tab that then reveals
"Buffs" and "Cooldowns" as sub-tabs.
**Fix:** Describe it as what it is, e.g.: "The Cooldown Manager settings window carries two TBT
tabs — **TBT Buffs** and **TBT Cooldowns**" (or similar), removing the "one tab split into two"
framing from both the Features bullet and the Usage bullet.

### WR-02: "Merged buff icon draws no cooldown sweep" contradicts shipped, tested behavior

**File:** `README.md:42-44`
**Issue:** The Merge Mode Features bullet states: "A merged buff icon appears and disappears
correctly but draws no cooldown sweep." This is the opposite of what the code does and of what
the project's own retail verification record confirms.

`MergeMode.lua`'s "Phase 40 — ENGINE-DRIVEN SWEEPS for merged Tracked Buff auras" section
(`MergeMode.lua:806-830` and surrounding) implements exactly this: a real cooldown sweep for
merged aura icons, drawn by Blizzard's own `AuraContainer` engine (via
`CustomAuraButtonSharedMixin:SetIcon`/`:SetDurationCooldown` and `AddSecretAspect`) rather than by
TBT reading a secret value — the comment at `MergeMode.lua:507-508` states plainly: "This is what
gives a merged buff icon a real cooldown sweep." The canonical retail verification record this
phase was told to consult, `.planning/testing/44-RETAIL-PASS.md:96-103`, has a table of what each
slot shape draws its cooldown from and lists: "Merged auras (all containers) | engine
`AuraContainer`, TBT never reads a value | in and out of combat" — i.e. confirmed working,
tested, both in and out of combat.
**Fix:** Correct or remove the "draws no cooldown sweep" clause. If there remains a real
limitation for a specific case (e.g. `hideAura` entries or a target-unit debuff on an assistable
unit, per `MergeMode.lua`'s `AURA_UNITS`/identity-filter comments), state that specific
limitation instead of the current blanket claim, which is false for the common case.

### WR-03: Racial trackers presented as generally available; the feature is Forever-exclusive

**File:** `README.md:54-56`, `CHANGELOG.md:19`
**Issue:** README's Features bullet reads: "**Racial trackers** — gnome (Eureka!), troll
(Berserking) and orc (Blood Fury and a second orc racial), plus racial cooldown tiles on the
Cooldowns tab. Verified on WoW Forever; other races show a 'not supported yet' tile." CHANGELOG's
matching bullet reads: "Racial trackers for **gnome, troll and orc**, plus racial cooldown
tiles." Neither discloses that the entire feature — including the "not supported yet" tile for
unhandled races — is absent on retail. Two bullets later, the sibling "Rank grouping" feature
*is* explicitly labelled "Forever-only," which sets an expectation that anything not so labelled
works on both clients; racial trackers do not meet that bar.

`BuffEngine.lua:81-84` gates the "racial"/"racial2" Suggested-section keys behind
`ns.CLIENT_IS_FOREVER` entirely: `if ns.CLIENT_IS_FOREVER then ... ns.SUGGESTED_KEYS[...] =
"racial" ... end`. `Core.lua:546-550` documents why: "Retail Midnight ships racials in the
Cooldown Manager already, so TBT's racial meta-tracker would be a worse duplicate... It is
offered on Forever alone (user decision, 2026-09-23)." A retail player sees no racial tile at
all — supported or "not supported yet" — for any race, contradicting the natural reading of
"Verified on WoW Forever" as a testing caveat rather than a hard platform gate. This is also the
exact correction 45-CONTEXT.md's D-12 called for ("Forever-only") but the delivered wording does
not carry the word "Forever-only" the way D-12's own description of the fix does.
**Fix:** Add an explicit platform qualifier matching the "Forever-only" wording already used for
Rank grouping, e.g.: "**Racial trackers (Forever-only)** — gnome (Eureka!), troll (Berserking)
and orc (Blood Fury and a second orc racial), plus racial cooldown tiles on the Cooldowns tab.
Not offered on retail, where the Cooldown Manager already tracks racials natively." (Note: the
word "natively" is one of DOC-05's banned strings in public copy generally, but Claude's
Discretion in 45-CONTEXT.md scopes that ban to *comparative claims about what the CDM tracks* —
worth flagging to the user rather than silently resolving, since the two rules pull in opposite
directions here.)

## Info

### IN-01: Duration input examples omit the bare-number form the parser also accepts

**File:** `README.md:69`, `README.md:965` reference is in `CDMTab.lua`, not README
**Issue:** README's Usage section says "Enter a spell ID and a duration written as `30s` or
`2m`." `CDMTab.lua:883-888`'s `ParseDuration` and its field label at `CDMTab.lua:965`
("Duration (30, 45s, 2m):") show the parser and the in-game UI both also accept a bare number
with no unit (e.g. `30`, treated as seconds). This isn't wrong, just incomplete — a player typing
`30` alone (as the in-game field label itself suggests) will succeed even though the README only
shows unit-suffixed examples.
**Fix:** Optional: extend the example list to match the in-game field's own label, e.g. "a
duration written as `30`, `45s`, or `2m`."

---

_Reviewed: 2026-09-23T06:49:20Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
