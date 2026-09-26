---
phase: 40-cdm-steal-mode
verified: 2026-09-21T18:44:33Z
status: passed
closed_at_milestone: v0.4.0 (2026-09-23)
closure_evidence:
  - ".planning/testing/43-FOREVER-E2E-PASS.md"
  - ".planning/testing/44-RETAIL-PASS.md"
closure_note: >-
  Closed in bulk at milestone close, not item by item. The human_verification list below was
  written when this phase's code landed and records what still needed a live client at that
  moment. Those observations were carried out in Phase 43 (Forever beta, build 1.60.1.69913,
  continuous play-testing 2026-09-21 to 22) and Phase 44 (retail, Mythic+ and a raid encounter,
  2026-09-23). The user signed both off as a whole -- "everything on Forever is tested and
  acceptable" and "no lua errors so far" -- rather than ticking each row, so read the list below
  as covered by those two passes collectively, not as individually attested. It is kept intact
  because it is the best record of what this phase could not prove statically.
score: 5/5 roadmap success criteria verified at code level (SC1-SC4 fully; SC3/STEAL-05 and STEAL-04 carry a documented partial-fidelity limit); 8/8 requirements (STEAL-01..08) satisfied at code level; STEAL-08's in-game half and 5 other in-game checks outstanding
overrides_applied: 0
human_verification:
  - test: "Fresh /reload, then /tbt — steal-mode checkbox unticked on a database that never had it on"
    expected: "Checkbox reads unchecked (STEAL-01)"
    why_human: "UI state on a live client; the code default (ns.db.stealMode = false seed in Core.lua) is verified statically but the widget's rendered state is not"
  - test: "Tick it, close the CDM window, out of combat"
    expected: "All four Blizzard viewers disappear; their items appear in TBT's four base containers styled as TBT items, alongside the user's own trackers (STEAL-02, STEAL-03, STEAL-04)"
    why_human: "Frame visibility and rendered widget appearance require a live client"
  - test: "Same session: add a spell to a CDM category and remove another"
    expected: "TBT's containers follow within a second or two, with no /reload (STEAL-05)"
    why_human: "Live event-driven refresh timing cannot be proven from static code alone"
  - test: "Untick the checkbox and close the CDM window"
    expected: "Each Blizzard viewer returns to exactly the shown/hidden state it had before steal mode was turned on, including a viewer that was already hidden then (STEAL-07)"
    why_human: "Runtime frame-state restoration is only observable live"
  - test: "Taint run from a fresh /reload: open-world combat + casting, leave combat, open Edit Mode, move a TBT container, save/exit Edit Mode, combat again"
    expected: "No Lua error, specifically no CooldownViewerItemData.lua:782 hasTotem taint error, in any of those phases (STEAL-08 in-game half)"
    why_human: "Taint is a runtime property of the live Lua environment and cannot be proven by static diff-reading alone; the code-level half (no forbidden call form anywhere in the ten-commit diff) is settled in this report"
  - test: "Click 'Copy Blizzard CDM Config' (EditModeFrames.lua, pre-existing v0.3.0 feature) while steal mode is active"
    expected: "No Lua error/taint from calling viewer:GetSettingValue(...) on a viewer TBT is currently hiding"
    why_human: "This interaction between a pre-existing mixin-call feature and a hidden CDM viewer was never exercised by this phase and has no static proxy — flagged per the verification brief, not part of STEAL-01..08 but worth one explicit check before this ships"
---

# Phase 40: CDM Steal Mode Verification Report

**Phase Goal:** Optionally, TBT becomes the whole display surface — Blizzard's CDM containers hide and their contents are mirrored into TBT's containers beside the user's own trackers, with the CDM demoted to a data source and a settings UI.
**Verified:** 2026-09-21
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Steal mode off on a fresh DB; on hides every viewer; off restores each to exactly its prior visibility | VERIFIED (code) | `Core.lua:625-626` seeds `ns.db.stealMode = false` on first load — the only other write site besides `ns:SetStealMode` (`grep -rn 'ns.db.stealMode = ' *.lua` → exactly two hits). `StealMode.lua:192-219` `CaptureAndHide`/`RestorePrior`: capture only when `ns.stealPriorShown[globalName] == nil` (never re-captures TBT's own hidden state), restore does explicit `if prior then Show() else Hide() end`, then `wipe(ns.stealPriorShown)` so the next switch-on re-captures from scratch. In-game confirmation of the actual hide/restore is deferred (see Human Verification). |
| 2 | Each CDM category's items appear in TBT's matching base container, styled as TBT items, beside the user's own trackers | VERIFIED (code) | `Display.lua:671-724` (`RenderBarContainer`) and `852-888` (`RenderIconContainer`) append `ns.stealSlots[def.key]` after `table.sort`, never sorted into the user's own ordering. Mirrored entries flow through the same pooled bar/icon widgets, `ApplyBarStyle`/`ApplyIconStyle`, and the same per-container scale/padding/opacity settings as any other slot — no separate mirror widget path exists. |
| 3 | What the player configures in the CDM is what TBT shows, without `/reload` | PARTIAL (code) — see STEAL-05 below | `StealMode.lua:50-137` `ns:RefreshStealMirror` rebuilds from `C_CooldownViewer.GetCooldownViewerCategorySet`/`GetCooldownViewerCooldownInfo`, driven by a 7+6-event frame plus an `EventRegistry` `CooldownViewerSettings.OnDataChanged` callback (`StealMode.lua:309-315, 331-335, 366-368`) — genuinely event-driven, no `/reload` needed for the cases it covers. But `GetCooldownViewerCategorySet` returns only the spec-default categorisation; the player's persisted manual hide/re-categorise overrides live behind a forbidden Blizzard mixin call (`GetOrderedCooldownIDsForCategory`). This is documented in-file (`StealMode.lua:16-24`) and in both plans' Risk sections, and is a locked, accepted limitation of the "never call a CDM mixin method" constraint — not a defect. |
| 4 | One toggle, not four — no per-category steal control anywhere | VERIFIED (code) | `grep -rno 'steal[A-Za-z]*' *.lua \| sort -u` shows no per-category identifier (no `stealEssential`, `stealBuffs`, etc.) — every occurrence is either the single `stealMode` flag, the single `TBTStealModeCheckbox` (`grep -c` → 1), or unrelated locals (`stealSlots`, `stealPriorShown`, `stealEventFrame`). `ns:SetStealMode(enabled)` (`StealMode.lua:281-293`) is the only writer. |
| 5 | Clean-`/reload` combat → Edit Mode → Edit Mode save → combat produces no Lua error/taint; diff confirms no forbidden CDM interaction | VERIFIED (code half); UNCONFIRMED (live half) | See the exhaustive taint-boundary audit below. The diff-read half is fully settled: zero forbidden interactions across all ten commits. The live taint-freedom half is a runtime property and cannot be proven statically — it is the single most important outstanding human check (see Human Verification). |

**Score:** 5/5 roadmap success criteria verified at the code level (criterion 3 carries the documented, accepted STEAL-05 partial-fidelity limitation; criterion 5's live half is outstanding).

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| STEAL-01 | Toggle on/off, off by default | VERIFIED (code) | `Core.lua:625-626` default seed; `CDMTab.lua:1231-1239` checkbox → `ns:SetStealMode`; `ns:ShowTBTConfigPage`'s `SetChecked(ns.db.stealMode == true)` (line 1739) re-syncs on every open. |
| STEAL-02 | Every Blizzard CDM container hidden while on | VERIFIED (code) | `StealMode.lua:223-255` `ns:ApplyStealVisibility`, `EachViewer(CaptureAndHide)` over all four `ns.CONTAINERS` defs with a `cdmViewerGlobal`. Live confirmation outstanding. |
| STEAL-03 | Each category's items appear in TBT's matching container | VERIFIED (code) | See SC #2 above; `def.key` is the join key between `ns.stealSlots` and the render functions. |
| STEAL-04 | Stolen items styled as TBT items, alongside the user's own trackers | PARTIAL — accepted, documented | Essential/utility mirrors: fully met — `trackerType == "cooldown"` on the mirror entry lands in the existing Phase 38 `ApplyCooldownSlot` branch with **zero new code** (`Display.lua:962-972`), so a mirrored essential/utility cooldown gets the identical engine-driven sweep and charge count as a native TBT cooldown tracker. Buff/bar mirrors: styled as TBT items but show **no countdown** — hiding the source viewer (STEAL-02) unregisters its `UNIT_AURA` handlers and there is no other legal aura-data source under the taint constraint. Documented in-code at `Display.lua:762-772` and `987-991` with the `CooldownViewer.lua:1743-1755,:2055` citations. This is the exact limitation the verification brief pre-classifies as PARTIAL, not FAILED. |
| STEAL-05 | Mirror follows what the player configures in the CDM, without reload | PARTIAL — accepted, documented | See SC #3 above. Spec/talent/learned-spell/override/hotfix changes ARE followed live. Manual re-categorisation/hide overrides are NOT, because closing that gap needs a forbidden Blizzard mixin call. Documented at `StealMode.lua:16-24`, 40-01-PLAN.md Risks, and 40-01-PLAN.md's "Notes carried in from plan review". |
| STEAL-06 | All-or-nothing, no per-category toggle | VERIFIED (code) | See SC #4 above. |
| STEAL-07 | Turning off restores exact prior visibility | VERIFIED (code) | See SC #1 above; the `== nil` capture-once guard and the `wipe()`-on-restore both trace correctly for both entry paths (checkbox click, and a login with the flag already true via `PLAYER_ENTERING_WORLD` in `REASSERT_VISIBILITY`). |
| STEAL-08 | No Lua error, no CDM taint, verified in combat / Edit Mode / Edit Mode save / post-Edit-Mode combat | SPLIT: code half VERIFIED, in-game half UNCONFIRMED | See the dedicated audit section below. |

### The Taint Boundary — Exhaustive Audit (the single most important check)

Every CDM-frame-adjacent symbol across the full diff of all ten commits (`git diff a4fb6cc~1...8264754 -- '*.lua' '*.toc'`, 5 files / 496 insertions / 12 deletions — `CDMTab.lua`, `Core.lua`, `Display.lua`, `StealMode.lua`, `TerribleBuffTracker.toc`), classified:

| Symbol / call form | File(s) | Classification | Permitted? |
|---|---|---|---|
| `_G[def.cdmViewerGlobal]` | `StealMode.lua:184, 403*` (*StealMode.lua's own `EachViewer`, only one real site) | global lookup, no frame method | Yes — read |
| `viewer:IsShown()` | `StealMode.lua:199` | C widget method | Yes — read |
| `viewer:Hide()` | `StealMode.lua:201, 217` | C widget method | Yes — write (the only write of this kind) |
| `viewer:Show()` | `StealMode.lua:215` | C widget method | Yes — write (restore path only) |
| `C_CooldownViewer.GetCooldownViewerCategorySet(...)` | `StealMode.lua:77` | namespace call, no frame | Yes |
| `C_CooldownViewer.GetCooldownViewerCooldownInfo(...)` | `StealMode.lua:81` | namespace call, no frame | Yes |
| `EventRegistry:RegisterCallback(...)` (5 registrations: `CooldownViewerSettings.OnDataChanged`, `EditMode.Enter`, `EditMode.Exit`, `CooldownViewerSettings.OnShow`, `CooldownViewerSettings.OnHide`) | `StealMode.lua:366, 391, 394, 398, 401` | callback registration, not a frame method or mixin call | Yes |

**Zero forbidden interactions found:** no `viewer.<field> =` write (`grep -nE 'viewer\.[A-Za-z_]+ *=' StealMode.lua` → empty), no `SetParent` into a CDM frame (`grep -n 'SetParent' StealMode.lua` → empty; the addon-wide `SetParent` hits are pre-existing `SetParent(nil)` release calls and one drag-marker reparent onto a TBT panel frame, none of them a CDM frame), no `SetLayoutData(` call form anywhere in the addon (`grep -rn 'SetLayoutData(' *.lua` → empty), no `HookScript` on `CooldownViewerSettings` (`grep -n 'HookScript' StealMode.lua` → empty), and no CDM mixin method call (`GetSettingValue`, `IsActive`, `ShouldBeShown`, `GetItemCount`, `RefreshLayout` — all absent from `StealMode.lua`).

**The exact three `viewer:` method names used are `IsShown`, `Hide`, `Show`** — confirmed by `grep -nE 'viewer:[A-Za-z]+\(' StealMode.lua`, which returns exactly those three across the whole file.

**Two known pre-existing exceptions, confirmed not introduced by this phase:**
- `EditModeFrames.lua:267-294`'s "Copy Blizzard CDM Config" button calls `viewer:GetSettingValue(...)` — `git blame -L 267,267 EditModeFrames.lua` → commit `d086429c`, dated 2026-03-30 (v0.3.0), untouched by this phase's diff.
- `Display.lua:471-474`'s `ns:InitDisplay` reads `viewer.itemFramePool` (a field **read**, not a write or mixin call) — `git blame -L 472,474 Display.lua` → commit `4ee325be` (`feat(36-02)`), dated 2026-09-21 13:17, which predates this phase's first commit (`a4fb6cc`, 15:24) and is Phase 35/36 work, not Phase 40.

**Conclusion: the claim in `StealMode.lua`'s header comment and both SUMMARYs — that the entire CDM frame surface reduces to `_G[def.cdmViewerGlobal]`, `viewer:IsShown()`, `viewer:Hide()`, `viewer:Show()`, all in one file — holds exactly as stated, across the real diff of all ten commits.**

### The EventRegistry Owner Bug (caught during execution) — confirmed fixed

`CallbackRegistryMixin:RegisterCallback` (`wow-ui-source/.../CallbackRegistry.lua:112-131`) confirms the claimed mechanism verbatim: *"An owner can have a single callback per event. The simplest way to ensure this is to remove all callbacks for the owner prior to new registration"* — i.e. a second `RegisterCallback(event, fn, owner)` call with the same `event`+`owner` silently replaces the first.

`EditModeFrames.lua:887-892` registers `EditMode.Enter`/`EditMode.Exit` with owner `ns`. `StealMode.lua:391-397` registers the same two events with owner `stealEventFrame` — a distinct table, confirmed by `CreateFrame("Frame")` at `StealMode.lua:303`. No collision. `grep -n 'RegisterCallback("EditMode' EditModeFrames.lua StealMode.lua` shows all four registrations, two different owners. TBT's own `ns:OnEditModeEnter`/`ns:OnEditModeExit` handlers remain reachable and unreplaced.

### The Gates

`ns:ApplyStealVisibility` (`StealMode.lua:223-255`) is reached from exactly one call site — the `C_Timer.After(0, ...)` body inside `ns:QueueStealVisibility` (confirmed: `grep -n 'ns:ApplyStealVisibility()' StealMode.lua` → 1 definition + 1 call, and the call is inside `FlushStealVisibility`, itself the sole `C_Timer.After` target). Gate order matches the spec exactly: suspended (`editModeOpen or cdmSettingsOpen`, line 231) → combat (`InCombatLockdown()`, line 240) → apply. `grep -n 'C_Timer.After' StealMode.lua` shows exactly one call form (line 275); the four other hits are comment prose.

`pendingApply` is confirmed genuinely gone: `grep -n 'pendingApply' StealMode.lua` returns nothing. Both SUMMARY 03 and the code agree this was deliberately deleted rather than left as dead state, with the explicit re-trigger events (`PLAYER_REGEN_ENABLED`, `EditMode.Exit`, `CooldownViewerSettings.OnHide`) carrying the retry semantics instead.

### STEAL-07 — Restore Exactly the Prior Visibility

`CaptureAndHide` (`StealMode.lua:197-202`) captures `viewer:IsShown()` into `ns.stealPriorShown[globalName]` **only when that slot is `nil`** — so a second, third, Nth apply while steal mode stays on never overwrites the captured value with TBT's own `false`. `RestorePrior` (206-219) reads it, applies `Show()`/`Hide()` accordingly, and the caller (`ApplyStealVisibility`, line 253) `wipe()`s the whole table afterward so the next switch-on starts clean. Both entry paths converge on the same code: a checkbox click calls `ns:SetStealMode` → `QueueStealVisibility` → (deferred) `ApplyStealVisibility`; a login with `ns.db.stealMode` already `true` reaches the same `ApplyStealVisibility` via `PLAYER_ENTERING_WORLD` being in both the mirror-refresh list and `REASSERT_VISIBILITY` (`StealMode.lua:309, 341`). Confirmed correct by reading; live confirmation of the actual restored state is outstanding.

### The Re-assert List

Read against `wow-ui-source/.../Blizzard_CooldownViewer/CooldownViewer.lua`: `CooldownViewerMixin:OnLoad` (1668-1677) registers `PLAYER_IN_COMBAT_CHANGED` + `PLAYER_LEVEL_CHANGED` as plain events, `VARIABLES_LOADED` via `EventRegistry:RegisterFrameEventAndCallback`, the `cooldownViewerEnabled` CVar via `CVarCallbackRegistry`, and `CooldownViewerSettings.OnShow`/`OnHide` via `EventRegistry`; `OnEvent` (1763-1765) re-asserts on `PLAYER_IN_COMBAT_CHANGED` or `PLAYER_LEVEL_CHANGED`.

TBT's `REASSERT_VISIBILITY` table (`StealMode.lua:340-347`) covers `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_ENABLED`, `PLAYER_LEVEL_CHANGED`, `VARIABLES_LOADED`, `CVAR_UPDATE` (a reasonable generic-event proxy for the CVar callback Blizzard uses internally), and `EDIT_MODE_LAYOUTS_UPDATED`, plus the `EditMode.Enter`/`Exit` and `CooldownViewerSettings.OnShow`/`OnHide` `EventRegistry` pairs. Every Blizzard `UpdateShownState` trigger is covered **except** `PLAYER_IN_COMBAT_CHANGED`, whose absence is deliberate and documented (re-asserting there is exactly the forbidden in-combat write; `PLAYER_REGEN_ENABLED` bounds the resulting window to one combat).

`grep -n 'PLAYER_LEVEL_UP\|PLAYER_LEVEL_CHANGED' StealMode.lua` confirms `PLAYER_LEVEL_CHANGED` is registered (line 332) and `PLAYER_LEVEL_UP` appears only inside the explanatory rejection comment (lines 319, 323) — never as a registered event. Matches the claim exactly.

### Hot Path

`grep -c 'stealSlots' Display.lua` → 2 (one per render function, neither inside `ns:UpdateDisplay`). Reading `RenderBarContainer`, `RenderIconContainer`, and `ns:UpdateDisplay` end to end (Display.lua:665-1053) finds exactly two table constructors, both the pre-existing `proc = { spellID = ..., label = ..., key = ... }` placeholder lines (lines 779 and 1000) already filed for Phase 43 — unchanged from before this phase. `grep -n 'GetCooldownViewerCategorySet\|GetCooldownViewerCooldownInfo\|C_CooldownViewer' Display.lua` and `grep -n 'RefreshStealMirror' Display.lua` both return nothing — no CDM API call and no mirror rebuild anywhere on the render path.

### STEAL-03/04 — The Mirror Renders

Mirrored slots reach the correct container purely via `def.key` (the join key shared by `ns.CONTAINERS`, `ns.stealSlots`, and both render functions' `def.key` parameter). `StealMode.lua:126-128`'s `trackerType` branch correctly maps `essential`/`utility` → `"cooldown"` and `buffs`/`bars` → `"buff"` (verified by hand-tracing all four container defs against `def.kind`/`def.cdmCategoryName`). A mirrored essential/utility cooldown reuses the exact Phase 38 `ApplyCooldownSlot` path with no new branch (`Display.lua:962-972`), so it is visually and mechanically identical to a native TBT cooldown tracker in the same container — the specific claim this check asked to verify.

### Read-Only Mirror

`grep -n 'ns.db.trackedBuffs' StealMode.lua` → nothing; `"cdm:"` prefix appears exactly once in the whole addon, at its creation site (`StealMode.lua:122`) — never referenced anywhere else. `CDMTab.lua`'s drag state (`tbtDragState.spellID` → `ns.db.trackedBuffs[spellID]`, lines 563-591), its delete zone, and `ns:RefreshTBTSections`'s own tracked-item list (line 745+, iterating `ns.db.trackedBuffs` and `ns.SUGGESTED_KEYS` only) never reference `ns.stealSlots` at all (`grep -n 'stealSlots' CDMTab.lua EditModeFrames.lua BuffEngine.lua Providers.lua` → empty). There is no code path anywhere by which a mirrored slot can be reordered, moved between sections, or deleted.

### STEAL-06 — All-Or-Nothing

Confirmed above (SC #4 / requirements table). No per-category identifier exists anywhere.

### Scope Fence

| Check | Result |
|---|---|
| `CURRENT_SCHEMA_VERSION` still 4 | VERIFIED — `BuffEngine.lua:82`, unchanged, no new migration step |
| `ns.CLIENT_HAS_SPELL_RANKS` one definition, one reader | VERIFIED — `Core.lua:344` (definition), `CDMTab.lua:941` (reader) |
| No `parentArray` | VERIFIED — `grep -rn 'parentArray' *.lua` empty |
| `TBTSettingsTab`/`AnchorTabBelowCDMTabs` untouched | VERIFIED — absent from the ten-commit diff of `CDMTab.lua` |
| No bulk `entry.section` rewrite | VERIFIED — no such pattern in the diff |
| `StealMode.lua` in TOC, sane load position | VERIFIED — `TerribleBuffTracker.toc` line 16, after `Core.lua`/`Providers.lua`, before `EditModeFrames.lua`; `## Interface: 120100, 16001` unchanged |
| `stylua --check .` exits 0 | VERIFIED — ran directly, exit code 0 |
| `CHANGELOG.md` untouched by all ten commits | VERIFIED — `git diff a4fb6cc~1...8264754 -- CHANGELOG.md` empty, no commit touches it |

### STEAL-08, Split Explicitly

**Code half (settled now):** Exhaustive diff-read above — zero forbidden interactions across all ten commits. VERIFIED.

**In-game half (cannot be settled statically):** No Lua error, no `CooldownViewerItemData.lua:782 hasTotem` taint error, across combat / Edit Mode / Edit Mode save / post-Edit-Mode combat, starting from a fresh `/reload` since taint is sticky and clears only there. UNCONFIRMED — listed in Human Verification below, per the verification brief's explicit instruction not to claim this from static analysis.

### Anti-Patterns Found

None. `grep -n -E "TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER" StealMode.lua Core.lua Display.lua CDMTab.lua TerribleBuffTracker.toc` returns nothing across all five files touched by this phase.

### Probe Execution

No probes declared for this phase and no conventional `scripts/*/tests/probe-*.sh` exist in this repository (`find scripts -path '*/tests/probe-*.sh'` → empty). Step 7c: SKIPPED — this project has no probe harness.

### Behavioral Spot-Checks

Skipped. This is a WoW addon with no runnable entry point outside a live game client — per the verification brief, everything requiring the game is a human check, not a static spot-check.

## Human Verification Required

See YAML frontmatter `human_verification` for the full list (6 items). Summary:

1. Fresh-DB checkbox default (STEAL-01)
2. Toggle-on hide + mirror rendering (STEAL-02/03/04)
3. Live CDM-edit follow without reload (STEAL-05)
4. Toggle-off exact restore (STEAL-07)
5. **The taint run** — the decisive test for STEAL-08's in-game half, must start from a fresh `/reload`
6. "Copy Blizzard CDM Config" while steal mode is active — an untested interaction between a pre-existing v0.3.0 mixin-call feature and a viewer TBT is currently hiding, flagged explicitly per the verification brief rather than assumed safe

All six were already identified and deferred to Phase 42 by 40-03-SUMMARY.md's own checklist; this report reproduces them as the binding human-verification list rather than trusting the summary's claim that they were "not attempted, not claimed" at face value — confirmed by reading that no in-game testing artifact, log, or screenshot exists anywhere in this phase's commits.

## Gaps Summary

No code-level gaps. Two requirements (STEAL-04, STEAL-05) carry documented, accepted partial-fidelity limitations that are structural consequences of the locked "never call a CDM mixin method" constraint — not defects, not incomplete work, and not something a further plan in this phase could close without reversing that locked decision. Everything else verified at the code level holds up under adversarial re-reading of the actual diff, not the SUMMARY narrative. The only reason this phase is not `passed` is that its in-game verification (STEAL-08's taint run above all) has not yet been performed on a live client — which is expected and by design, deferred to Phase 42.

---

*Verified: 2026-09-21T18:44:33Z*
*Verifier: Claude (gsd-verifier)*
