---
phase: 63-clickable-reminders
verified: 2026-09-30T00:00:00Z
status: human_needed
score: 6/6 requirements verified in code (in-game behaviour deferred to Phase 66)
overrides_applied: 0
human_verification:
  - test: "Full client restart (new TOC file ReminderClick.lua), then open Edit Mode and check the Click to Cast checkbox"
    expected: "Appears on Buff Reminders and on a user-added reminders container; absent on buff/bar/cooldown containers; ticked by default; tooltip says out of combat only"
    why_human: "Popup rendering and TOC re-read need the live client"
  - test: "Untick Click to Cast, close Edit Mode; then tick it again"
    expected: "Unticked: that container's reminders are unclickable after Edit Mode closes; ticked: clickable again"
    why_human: "Live secure-frame behaviour"
  - test: "Click a shown reminder out of combat (Forever first, then retail), default CVar ActionButtonUseKeyDown=1"
    expected: "Casts the reminder's cast spell on the player by name (highest rank); the square hover highlight shows; the tooltip shows on hover (and respects Show Tooltips)"
    why_human: "Review CR-01 fix (useOnKeyDown=false) is only provable in game"
  - test: "Satisfy a reminder (cast the buff); set a container to Hidden; empty a container"
    expected: "No clickable square is left behind in any of these cases"
    why_human: "Overlay lifecycle needs the live client"
  - test: "With two reminders shown, satisfy the first"
    expected: "The remaining overlay follows its icon's new cell; overlays match icon position/size after login and after Edit Mode closes"
    why_human: "Screen-coordinate placement"
  - test: "Open Blizzard Edit Mode, including with TBT's sidebar checkbox unticked, and drag a container"
    expected: "No overlay swallows the drag or a click (review WR-01)"
    why_human: "Edit Mode interaction"
  - test: "Enter and leave combat with reminders shown; click during combat"
    expected: "Clicking does nothing in combat; no Lua error, no ADDON_ACTION_BLOCKED, no taint; overlays return after combat"
    why_human: "Combat lockdown and taint only occur in game"
  - test: "Switch Edit Mode layout/profile"
    expected: "Overlays re-place over their icons"
    why_human: "EDIT_MODE_LAYOUTS_UPDATED handling"
  - test: "Blood Pact reminder on Forever Warlock (imp)"
    expected: "Shown but has no click action, no hover highlight"
    why_human: "Forever client only"
  - test: "Edit a reminder's Cast spell ID (Advanced), save, click it; also set it back to the Spell ID"
    expected: "The click casts the new spell without needing a reload (review CR-02); the castID key is nil at default (/dump entry)"
    why_human: "In-game SavedVariables and cast"
  - test: "Alt+Z hide/show the UI, a cinematic, and a cast spell ID the character does not know"
    expected: "Overlays are restored after the UI returns (WR-03); an unknown cast spell gets no overlay (WR-05)"
    why_human: "Live client only"
---

# Phase 63: Clickable Reminders Verification Report

**Phase Goal:** Out of combat, a player can refresh a missing buff by clicking its reminder, without TBT's display ever becoming protected or tainted.
**Status:** human_needed. No code gaps found. The remaining checks run in game (Phase 66).

## Requirements Coverage

Every ID in the plan frontmatter appears in REQUIREMENTS.md, and no ID is orphaned: 63-01 has CLICK-06, 63-02 has CLICK-01/03/04/05, and 63-03 has CLICK-01/02/04.

| Req | Status | Code evidence |
| --- | ------ | ------------- |
| CLICK-01 | SATISFIED in code | `ReminderClick.lua` creates a pooled `SecureActionButtonTemplate` overlay with `type1=spell`, `unit=player` and `spell=<name>` (lines 61-67, 120). The CR-01 fix (`useOnKeyDown=false`, line 65) is present. `Display.lua:2746` stamps clickable icons in any reminders container, and the check is not restricted to the base container. |
| CLICK-02 | SATISFIED in code | `Display.lua:219` sets `clickToCast = src.clickToCast ~= false`, so nil means on. `EditModeFrames.lua:553-555` adds the checkbox only when the container category is `reminders`, with `defaultOn=true`. The tooltip (line 212) reads "Left-click a reminder to cast its spell. Out of combat only." |
| CLICK-03 | SATISFIED in code | `RegisterStateDriver(..., "[combat] hide; show")` is used. `Flush` returns early on `InCombatLockdown()`, and `EditMode.Enter` checks combat before it retires overlays. `PLAYER_REGEN_ENABLED` calls `Flush`. `Retire` (Unregister plus Hide) is the single way out of service. |
| CLICK-04 | SATISFIED in code | The stamp requires `gate == true`, `clickToCast`, `not iconEditing` and a non-nil anchor. Stamps are cleared on hidden containers, on pool shrink and on paths with no settings (`Display.lua:2784`, `clickStampedIn`). Placement uses `GetRect` screen coordinates with a dirty check. WR-02 (container size change), WR-03 (retry, UIParent OnShow hook) and WR-01 (`editModeOpen`) are fixed. |
| CLICK-05 | SATISFIED in code | The overlay's `OnEnter` calls `ns:ShowBuffTooltip(self, icon.proc)` and respects `containerTooltipsShown`. |
| CLICK-06 | SATISFIED in code | The `castID` field is in `TRACKER_FIELDS` (Advanced tab, reminders only, `CDMTab.lua:2303`). `read` returns nil when blank or equal to the spell ID, so the field is nil at default. `ns:ReminderCastID` (`Providers.lua:1618`) reads `def.castID` for built-ins. `MetaReminderRow` defaults `castID` to `spellID`, and Blood Pact has `castID = false` (line 1585), so it has no click action. |

## CONTEXT Decisions

| Decision | Status |
| -------- | ------ |
| Per-container "Click to Cast", nil = on, reminders containers only | Honoured |
| Unit is player | Honoured (`unit=player`) |
| Spell by name (`ResolveCastName` via `C_Spell.GetSpellInfo`; no name means no overlay) | Honoured |
| Blood Pact has no click; the `castID = false` data row is not special-cased by ID in code | Honoured |
| Cast spell field stored nil at default | Honoured |
| Overlays parented to UIParent and anchored only to UIParent | Honoured (`SetPoint("BOTTOMLEFT", UIParent, ...)`; the only frame parent is UIParent) |
| Every overlay mutation out of combat | Honoured: `CreateOverlay`, `Place`, `Retire` and `Flush` are reached only from `Flush` (combat-gated) or the gated `EditMode.Enter` callback |
| No `EditModeManagerFrame` or Edit Mode mixin calls in TBT | Honoured for Phase 63: the diff against 9f2440c adds no such reference in code. The remaining hits (`Config.lua` `ns:OpenEditMode`, `EditModeFrames.lua` popup follow, `MergeMode.lua:1302`) all predate this phase. ReminderClick uses only EventRegistry callbacks. |

## Review fixes (final state)

CR-01 (`ReminderClick.lua:65`), CR-02 (`Core.lua:1484` in `RebuildCastIndex`), WR-01 (`editModeOpen`), WR-02, WR-03, WR-04 (`issecretvalue` guards in `Place`), WR-05 (`ResolveSpellKnown`), IN-03 and IN-04 are all present in the code. IN-01, IN-02, IN-05 and IN-06's castID factory were deferred to Phase 65 and are not gaps.

## Spot-checks

- `node scripts/aura-read-gate.js` passes: AURA-READ GATE PASS (10 reads in 3 allowlisted readers).
- `ReminderClick.lua` is in the TOC (line 20), after Display.lua.
- Line endings are `w/crlf` with the `eol=crlf` attribute.
- No TODO/FIXME/XXX was found in `ReminderClick.lua`.

## Anti-patterns

None blocking. Two low-severity items are already recorded in the review and deferred to Phase 65: `OverlayOnLeave` hides `GameTooltip` unconditionally (IN-05), and `ResolveCastName` duplicates other resolvers (IN-01).

## Gaps Summary

There are no code gaps. Everything that can be checked statically is met. Combat, taint, click-cast, tooltip and placement behaviour need the live client and are listed under human_verification.

_Verifier: Claude (gsd-verifier)_
