---
phase: 55-id-preview-suggested-cooldown-secrecy
verified: 2026-09-28T14:00:00Z
status: human_needed
score: 5/5 roadmap success criteria verified statically (in-game confirmation pending)
overrides_applied: 0
human_verification:
  - test: "Live preview updates as you type. Open Add on the Buffs tab and on the Cooldowns tab, and type a known spell ID one digit at a time."
    expected: "The row under the Spell ID box shows the spell's icon and name, and changes with every keystroke. An empty box shows an empty row."
    why_human: "Needs a real client: EditBox OnTextChanged, C_Spell.GetSpellInfo and texture rendering."
  - test: "Edit opens with its preview filled. Right-click an existing user tracker on either tab and choose Edit."
    expected: "The dialog opens with the preview already showing that tracker's icon and name."
    why_human: "The prefill order (spellID SetText fires a nested RefreshState before the other fields reset) was traced by hand only."
  - test: "Unknown ID, no error. Run /console scriptErrors 1, then type 999999999 in Add and hover the preview."
    expected: "The preview shows the question-mark icon (134400) and a grey 'Unknown spell'. The hover shows 'Unknown spell', then 'Spell ID: 999999999'. No Lua error."
    why_human: "Runtime behaviour of GetSpellInfo and GameTooltip for an ID the client does not know."
  - test: "Uncached spell retry. After a real logout and login (not /reload), open Add and type an uncommon spell ID you have not looked at this session."
    expected: "The preview shows the spell's name. If it first shows 'Unknown spell', one more keystroke anywhere in the dialog (for example in Duration) fixes it."
    why_human: "Spell cache behaviour on first lookup can only be seen in a live client."
  - test: "Preview hover tooltip. Hover the preview row for a known spell."
    expected: "The game's own spell tooltip, with exactly one 'Spell ID: N' line and one 'Aura secrecy: ...' line directly under it."
    why_human: "Depends on SetSpellByID firing the TOOL-01 post-call inside TBT's dialog."
  - test: "Secrecy line appears exactly once. Hover an action button, a spellbook spell, a buff out of combat, and a TBT tracker tile (Buffs and Cooldowns tabs)."
    expected: "Each tooltip shows exactly one 'Aura secrecy: Never secret' / 'Always secret' / 'Contextual' line, in grey, directly under the 'Spell ID:' or 'Aura spell ID:' line."
    why_human: "Needs TooltipDataProcessor post-calls and C_Secrets.GetSpellAuraSecrecy in a live client."
  - test: "Secrecy badge. On BOTH the Buffs and the Cooldowns tab, type a Contextual or Always-secret ID (Forever example: Eureka!, level 2), then a Never-secret ID (for example a Sated debuff)."
    expected: "The Contextual or Always-secret ID shows a small warning badge to the right of the preview name on both tabs. Hovering it shows 'Aura secrecy: Contextual' (or 'Always secret') in gold, plus a short white explanation. The Never-secret ID shows no badge on either tab."
    why_human: "The badge lives on a zero-height row frame and is anchored to a sibling row's hover frame. That should render, but only a live client can prove it. The level also comes from the live API."
  - test: "Badge art on Forever. On the Forever client only, show the badge (as in the previous check)."
    expected: "Write down whether it draws the transmog-icon-warning-small atlas icon or the '(secret?)' text fallback. Either is acceptable. What must not happen is a blank space or a Lua error."
    why_human: "Whether the atlas exists on Forever cannot be proven from a source dump."
  - test: "The suggestion follows the ID on the Cooldowns tab. On retail AND Forever, type a spell with a known cooldown, change the ID while the box is untouched, type your own value, change the ID again, then clear the box and change the ID once more."
    expected: "The Duration box fills in (for example 120 s shows as '2m'). The suggestion follows the ID while you have not touched it. Your typed value is kept when the ID changes. An empty box refills with the new ID's suggestion. ON RETAIL, also write down whether a spell with no charges (for example a 2-minute major cooldown) gets a suggestion at all. GetSpellBaseCooldown does not appear anywhere in the local 12.1 wow-ui-source, so on retail the suggestion may only work for charge spells."
    why_human: "Whether the legacy global GetSpellBaseCooldown exists on each client, and whether GetSpellCharges().cooldownDuration is readable, can only be checked in the live game."
  - test: "No cooldown leaves the box empty. On the Cooldowns tab, type a spell the game reports no cooldown for."
    expected: "Duration stays empty, and Add stays disabled until you type a value by hand."
    why_human: "Live API answer."
  - test: "The Buffs tab never fills Duration in. On the Buffs tab, type any spell ID, including one with a cooldown."
    expected: "The Duration box is never filled in or changed."
    why_human: "Checks the ctx.kind gate in a real dialog open."
  - test: "Edit keeps the saved duration. Edit a cooldown tracker and change its spell ID."
    expected: "The saved duration stays in the box and is not replaced by a suggestion for the new ID."
    why_human: "Runtime ordering of reset, prefill and RefreshState on edit open."
  - test: "A typed value survives, not the suggestion. On the Cooldowns tab, let a suggestion fill Duration, type your own value over it, click Add (or Save), then do a real logout and login (not /reload)."
    expected: "The tracker keeps the value you typed, not the suggestion."
    why_human: "SavedVariables are only written on logout."
---

# Phase 55: ID Preview, Suggested Cooldown & Secrecy Verification Report

**Phase Goal:** While entering a spell or aura ID in either dialog, the player sees exactly what they are about to track, gets the game's cooldown suggested, and is warned when aura-driven behaviour may not work in combat
**Verified:** 2026-09-28
**Status:** human_needed
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths (ROADMAP success criteria, merged with PLAN must-haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Typing an ID in the Add or Edit dialog updates a preview icon and name as it is typed. Hovering shows the game's tooltip. An unknown ID is shown as unknown (SC1, ADD-04) | VERIFIED (static) | `spellPreview` TRACKER_FIELDS entry (CDMTab.lua:1321-1428). It reads `state.source.editBox:GetNumber()` from the spellID field (source captured via `dialog.GetFieldState("spellID")`). The spellID box's `OnTextChanged` is `onChange`, so RefreshState runs every field's `update` on each keystroke (CDMTab.lua:1801-1806). The name and icon come from `ns:SpellPreview` (Core.lua:1450), which uses a pcall'd `C_Spell.GetSpellInfo` guarded by `issecretvalue`. When it returns nil, the row shows icon 134400 and "Unknown spell". An unknown ID is re-queried on every later dialog change. OnEnter calls `ns:ShowBuffTooltip` with reused tables: a resolved spell goes through `SetSpellByID`, an unresolved one gets the label "Unknown spell" plus "Spell ID: N". Both dialogs share the same frame (OpenForAdd and OpenForEdit), so both get the preview |
| 2 | On a cooldown tracker, a spell the game reports a cooldown for fills Duration. The user can overwrite it, and the typed value is saved. No reported cooldown leaves the field empty (SC2, ADD-05) | VERIFIED (static) | The `duration.update` hook (CDMTab.lua:1547-1582) is gated on `ctx.kind == ns.KIND.USER_CD`. It returns early unless the ID changed, and returns early when the box text is non-empty and differs from `state.suggestionText`, so typed text is never overwritten. It writes `FormatDuration(ns:SuggestedCooldown(id))` and records the suggestion before calling SetText, which guards against recursion. A value longer than 6 letters is dropped. `prefill` clears the suggestion state, so a saved Edit value is never replaced. `read` and `validate` are unchanged: whatever is in the box at Save is parsed and saved. `ns:SuggestedCooldown` (Core.lua:1422) tries `GetSpellBaseCooldown` (existence-checked, pcall'd, ms/1000), then `C_Spell.GetSpellCharges().cooldownDuration` (CanReadTable plus issecretvalue), then returns nil. See WARNING W1 about retail |
| 3 | Hovering a TBT tracker tile or the dialog preview shows the aura secrecy level next to the spell ID, and so does the global TOOL-01 line (SC3, SECR-01, SECR-02) | VERIFIED (static) | TOOL-01 post-call (Core.lua:1543-1546): `ns:SecrecyLine(ns:SpellAuraSecrecy(id))` is added right after the "Spell ID:" / "Aura spell ID:" AddLine, in the same 0.8 grey. It runs after the existing `issecretvalue(id)` early return. Tiles (CDMTab.lua:325, 352) and the preview both go through `ns:ShowBuffTooltip`. For a resolved spell that calls `SetSpellByID`, so TOOL-01 adds the line exactly once and ShowBuffTooltip adds none. The unresolved branch (Display.lua:275-280) adds its own line |
| 4 | An AlwaysSecret or ContextuallySecret ID shows a small "secret?" badge with an explanatory tooltip. NeverSecret shows no badge (SC4, SECR-03). The badge appears on BOTH tabs, driven by aura secrecy (CONTEXT user decision) | VERIFIED (static) | `secrecyBadge` entry (CDMTab.lua:1433-1500). `update` caches `ns:SpellAuraSecrecy(id)` once per ID change. `visible` returns `ns:SecrecyWarns(state.level)` and never branches on `ctx.kind`, so the badge is on both tabs. SecrecyWarns is true only for a recognised level other than NeverSecret. The art is the atlas `transmog-icon-warning-small` if `C_Texture.GetAtlasInfo` knows it, otherwise the text "(secret?)". OnEnter shows `SecrecyLine(level)` in gold, then `SecrecyExplanation(level)` wrapped. The explanation text says what the level means for the tracker (Core.lua:1339-1352) |
| 5 | On a client without the secrecy API, tooltips and dialogs still work, with no secrecy info and no Lua error (SC5) | VERIFIED (static only) | `SpellAuraSecrecyAPI = C_Secrets and C_Secrets.GetSpellAuraSecrecy` is captured at load. The tables are built only `if Enum and Enum.SecrecyLevel`. `ns:SpellAuraSecrecy` returns nil when either is missing, then `SecrecyLine(nil)` returns nil (no line), and `SecrecyWarns(nil)` returns false (no badge). Every API read is pcall'd. This cannot be exercised in game, because both Midnight retail and Forever have the API |
| 6 | Helpers live on ns for reuse in Phases 56-57 (PLAN 01) | VERIFIED | Six `function ns:` helpers at Core.lua:1374-1469, each with a non-comment caller |
| 7 | The TOOL-01 addition allocates nothing per tooltip (PLAN 01) | VERIFIED | One pcall, table lookups, and a line string prebuilt at load (Core.lua:1358). No closure or concatenation |
| 8 | The preview and badge have no entryKey, and CreateAddDialog is byte-identical to the phase base (PLAN 02, EDIT-03) | VERIFIED | Neither entry has an `entryKey`. The body extracted from `fe936cd` and from HEAD diffs empty |
| 9 | Hover closures read a local `state` declared before SetScript (PLAN 02) | VERIFIED | `local state = {...}` comes before both `SetScript("OnEnter")` calls in both entries |
| 10 | Automated gates: selftest, file scope, stylua (PLAN 03) | VERIFIED | `node scripts/migrate-dryrun.js --selftest` gives PASS (7 cases). The committed diff since `fe936cd` touches only Core.lua, Display.lua and CDMTab.lua (plus .planning). `.gitignore` is an unrelated uncommitted user edit. `stylua --check` is clean. `git ls-files --eol` shows w/crlf on all three files. Display.lua has only +6 lines, inside ShowBuffTooltip |

**Score:** 5/5 roadmap success criteria, 10/10 merged truths verified statically. All are pending in-game confirmation.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | SPELL INFO HELPERS section and secrecy line in TOOL-01 | VERIFIED | Contains `function ns:SpellAuraSecrecy(`. Wired from TOOL-01, Display.lua and CDMTab.lua |
| `Display.lua` | Secrecy line in the unresolved branch of ShowBuffTooltip | VERIFIED | Contains `ns:SpellAuraSecrecy(spellID)` at :277 |
| `CDMTab.lua` | `spellPreview`, `secrecyBadge`, and the `duration.update` suggestion | VERIFIED | The entries sit between `spellID` and `duration`. CreateAddDialog iterates TRACKER_FIELDS, so no extra wiring is needed |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| TOOL-01 post-call | `ns:SpellAuraSecrecy` / `ns:SecrecyLine` | `tooltip:AddLine(secrecyLine, ...)` after the ID line | WIRED |
| ShowBuffTooltip unresolved branch | `ns:SpellAuraSecrecy(spellID)` | own AddLine | WIRED |
| `spellPreview.update` | `ns:SpellPreview` | `state.source.editBox:GetNumber()` | WIRED |
| `spellPreview` OnEnter | `ns:ShowBuffTooltip` | reused `tooltipProc`/`tooltipOpts`, with `spellID` updated by `update` | WIRED |
| `secrecyBadge.visible` | `ns:SecrecyWarns` | `state.level` from `update` | WIRED. RefreshState evaluates `visible` and Layout shows or hides the row |
| `duration.update` | `ns:SuggestedCooldown` | spellID state captured at build | WIRED. RefreshState passes `ctx` as the second argument, as the hook expects |
| spellID box OnTextChanged | RefreshState | `onChange` closure from the build loop | WIRED (pre-existing Phase 54 machinery) |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| Preview icon/name | `spellName, iconID` | `ns:SpellPreview` -> `C_Spell.GetSpellInfo(id)` | yes (live API) | FLOWING |
| Badge visibility/tooltip | `state.level` | `ns:SpellAuraSecrecy` -> `C_Secrets.GetSpellAuraSecrecy` | yes (live API) | FLOWING |
| Tooltip secrecy line | `secrecyLine` | same helper, prebuilt `SECRECY_LINES[level]` | yes | FLOWING |
| Duration suggestion | `seconds` | `GetSpellBaseCooldown` / `GetSpellCharges` | yes where the API exists (see W1) | FLOWING, retail coverage uncertain |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Migration selftest unaffected | `node scripts/migrate-dryrun.js --selftest` | `SELFTEST PASS (7 cases)` | PASS |
| CreateAddDialog untouched | awk extract at `fe936cd` vs HEAD, `diff` | identical | PASS |
| Formatting | `stylua --check Core.lua Display.lua CDMTab.lua` | exit 0 | PASS |
| Line endings | `git ls-files --eol` | `w/crlf attr eol=crlf` on all three | PASS |
| Lua syntax / runtime | no Lua interpreter or WoW client available | n/a | SKIP (human) |

### Probe Execution

No probes are declared by this phase. SKIPPED.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ADD-04 | 55-02, 55-03 | Live preview (icon and name), game tooltip on hover, unknown shown as unknown | SATISFIED (pending in-game) | Truth 1 |
| ADD-05 | 55-03 | Duration filled with the spell's cooldown when the game reports one; user can override | SATISFIED (pending in-game, see W1) | Truth 2 |
| SECR-01 | 55-01, 55-02, 55-03 | TBT tile tooltips and the preview show the secrecy level next to the spell ID | SATISFIED (pending in-game) | Truth 3 |
| SECR-02 | 55-01, 55-03 | TOOL-01 line also shows secrecy | SATISFIED (pending in-game) | Truth 3 |
| SECR-03 | 55-02, 55-03 | "secret?" badge above NeverSecret, with explanatory tooltip | SATISFIED (pending in-game) | Truth 4 |

All five IDs are claimed by at least one plan. REQUIREMENTS.md maps no other ID to Phase 55, so there are no orphaned requirements.

### CONTEXT decisions honoured

- The preview is a field in the shared definition and updates on OnTextChanged. Its hover uses SetSpellByID through ShowBuffTooltip. An unknown ID is decided by `GetSpellInfo == nil` and shown with icon 134400. Yes.
- Suggestion chain order (GetSpellBaseCooldown, then GetSpellCharges.cooldownDuration, then none), fill only when the box is empty or still holds the previous suggestion, Cooldowns tab only. Yes.
- Secrecy is capability-checked rather than flavour-checked, and receives plain numbers only. Yes.
- The secrecy line comes after the TOOL-01 ID line, in the same colour, and is not printed twice for tiles. The unresolved branch and the preview get their own line. Yes.
- Badge on BOTH tabs, driven by aura secrecy, visible for levels 1 and 2, atlas with a text fallback. Yes.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Core.lua, Display.lua, CDMTab.lua (phase diff) | - | TBD/FIXME/XXX/TODO/HACK | none found | - |
| CDMTab.lua | 1476 | secrecyBadge build returns `y` unchanged, so its row frame is 240x0 while the badge is anchored to a sibling row's `preview.hover` | Info | Child frames with their own size render regardless of the parent's height, so this should draw. It is covered by human check 7 |
| CDMTab.lua | 1547-1582 | Retyping exactly the current suggestion text counts as the suggestion | Info | Documented in 55-03-SUMMARY "Known behaviour", and consistent with the CONTEXT rule |

### Warnings

- **W1 (retail coverage of ADD-05):** The local wow-ui-source (branch `live`, 12.1) never references `GetSpellBaseCooldown`, and it has no other base-cooldown API. The code checks that the global exists, so nothing errors. But if the global is absent on retail, the only source there is `GetSpellCharges().cooldownDuration`, which means only charge spells would get a suggestion. A source dump cannot prove the global is absent, so this is folded into human check 9. If retail gives no suggestion for ordinary cooldowns, SC2 technically still holds ("a spell the game reports a cooldown for"), but the user should decide whether that coverage is acceptable.

### Human Verification Required

These are the 13 items in the frontmatter `human_verification` list, in order. They mirror the 55-03-SUMMARY in-game checklist, with the retail base-cooldown question added to item 9. Run them on Midnight retail AND on Forever. `/reload` is enough to load the code. Items 4 and 13 need a real logout and login.

### Gaps Summary

The static checks found no defect. Every roadmap success criterion and every plan must-have is backed by code that exists, has real content, is wired into the dialog walker or the TOOL-01 post-call, and gets its data from live game APIs behind issecretvalue checks, pcall and capability checks. The Add/Edit dialog body is unchanged. The only open question is W1: how many retail spells get a suggested cooldown. That depends on the live client, not on the code, and it is routed to human check 9.

---

_Verified: 2026-09-28_
_Verifier: Claude (gsd-verifier)_
