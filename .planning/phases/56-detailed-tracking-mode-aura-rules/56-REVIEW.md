---
phase: 56-detailed-tracking-mode-aura-rules
reviewed: 2026-09-28T00:00:00Z
depth: deep
files_reviewed: 4
files_reviewed_list:
  - BuffEngine.lua
  - Providers.lua
  - CDMTab.lua
  - scripts/aura-read-gate.js
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# Phase 56: Code Review Report

**Reviewed:** 2026-09-28
**Depth:** deep
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Scope: `git diff 88aac0f..HEAD -- '*.lua' scripts/aura-read-gate.js`. I read the full current code around every hunk, and I traced the call chains into ScanActiveTimersForCancellation, ns:ReadPlayerAura, ns:AcquireProc/AcquireAliveBuffs, RebuildRankIndex (Core.lua), ns:AddTrackedBuff/UpdateTrackedBuff, ns:ShowBuffTooltip and CreateAddDialog's walker. I ran `node scripts/aura-read-gate.js` (PASS, 8 reads in 3 readers), `--selftest` (6/6) and `migrate-dryrun.js --selftest` (7/7). `stylua --check` is clean, and all three Lua files are `w/crlf`.

The main points hold up:

- **Simple trackers behave as before.** When `entry.detailed` is falsy, `CancelsOnAuraLoss` returns true and `DetailedAuraID` returns nil. OnTrigger then evaluates exactly the old expression, `(fams and fams[ownerKey]) or ns:AcquireAliveBuffs(ownerKey, entry.spellID)`.
- **Aura ID and opt-out.** The aura ID takes priority over the rank family. The opt-out leaves `aliveBuffs` nil. `AcquireProc` wipes the pooled proc, so no stale `aliveBuffs` survives.
- **No aliasing.** The aura-ID branch draws from the per-slot pool, never from a `rankFamilies` array.
- **Gating.** Both runtime gates key on `entry.detailed`, never on child keys.
- **Hot paths.** Two method calls per cast and no allocation. The render path is untouched.
- **Dialog state.** Resets and prefills clear every cache key (`shownID`, `resolved`, `checkedID`, `checkedGen`, `level`). The walker's closing `RefreshState(true)` re-renders the portrait after the Spell ID prefill, so the portrait is not stale on open. All three detailed fields prefill correctly. Hidden children keep their values (WR-02). `keepOnAuraLoss` is stored only when unchecked.
- **Closure and upvalue order.** Every state table exists before the closures that capture it, whether they are wired directly or through `ns:BuildSecrecyBadge`. Every helper and constant used by a field is declared above `TRACKER_FIELDS`.
- **Portrait art.** The overlay offsets (-9, 8 / 9, -8) match Blizzard's 50px `CooldownViewerEssentialItemTemplate` exactly.

The defects are in the DTRK-06 static proof, which is weaker than it claims, and in one runtime interaction between the aura ID and Forever's rank families.

## Warnings

### WR-01: aura-read-gate.js misses several ways to read an aura, so the "cannot bypass it by construction" claim is false

**File:** `scripts/aura-read-gate.js:5-6, 28, 56-66`

**Issue:** `DETECT_RE` only matches the literal text `C_UnitAuras.<name>`, plus `UnitAura(`, `UnitBuff(`, `UnitDebuff(` and two AuraUtil names. I checked each shape below against the regex in node, and every one passes with 0 violations:

- `local UA = C_UnitAuras` followed by `UA.GetPlayerAuraBySpellID(id)`. There is no dot after `C_UnitAuras`, so this is the easiest bypass to write by accident, for example by hoisting an upvalue for speed.
- `C_UnitAuras["GetPlayerAuraBySpellID"](id)` and `C_UnitAuras . GetPlayerAuraBySpellID(id)`.
- Bare globals and other APIs: `GetPlayerAuraBySpellID(id)`, `UnitAuraBySlot(...)`, `UnitAuraSlots(...)`, `C_TooltipInfo.GetUnitBuff/GetUnitAura(...)`.
- `print("a --", C_UnitAuras.GetPlayerAuraBySpellID(1))`. `stripComment` cuts the line at the first ` --`, even inside a string, so the read is never seen.

Phase 57 adds an aura-state cache and treats this script as the standing check, so a missed bypass there would ship with a green gate.

**Fix:** Flag any reference to the namespace at all, not just a dotted call. Outside the three allowlisted functions, the shipped tree only mentions `C_UnitAuras` in comments. Widen the other patterns too:

```js
const DETECT_RE = /\bC_UnitAuras\b|\bGetPlayerAuraBySpellID\b|\bGetAuraDataBy\w+|\bUnitAura\w*\s*\(|\bUnitBuff\s*\(|\bUnitDebuff\s*\(|\bC_TooltipInfo\.GetUnit(Buff|Debuff|Aura)\b|\bAuraUtil\.(ForEachAura|FindAura\w*)/;
```

Add selftest fixtures for the alias, bracket-index and string-with-`--` shapes. Either make `stripComment` skip over quoted strings, or treat the string case as a documented known limit.

### WR-02: The predicate-order check can pass on a comment and does not prove the read is gated

**File:** `scripts/aura-read-gate.js:140-162`

**Issue:** `checkPredicateOrder` scans raw lines inside `ns:ReadPlayerAura`, comments included. It passes if any line containing the text `ShouldSpellAuraBeSecret` comes before the first line containing `GetPlayerAuraBySpellID`. Two failure scenarios:

- A refactor deletes the `if C_Secrets.ShouldSpellAuraBeSecret(...) then return nil, false end` block but leaves or adds a comment such as `-- asks ShouldSpellAuraBeSecret first`. The check still passes.
- `local _ = C_Secrets.ShouldSpellAuraBeSecret(id)` followed by an unconditional read also passes.

In both cases DTRK-06 ("unreadable is never absent") is lost with the gate green. The read would return nil for a hidden aura, and the scan would cancel the tracker.

**Fix:** Run `stripComment` on each body line before testing. Also require the predicate to be the condition of an `if` whose block returns `nil, false`. For example, match `/^\s*if\s+C_Secrets\.ShouldSpellAuraBeSecret\(/` and require `return nil, false` on the next non-comment line. Add a selftest fixture where the predicate appears only in a comment.

### WR-03: The gate's shipped-file list is hard-coded to one XML include and is not enforced anywhere

**File:** `scripts/aura-read-gate.js:169-186`

**Issue:** `loadShippedFiles` takes the `.lua` lines from the TOC and then adds `CDMTab.lua` by name. It does not read XML files for `<Script file=...>` or `<Include file=...>`. A new XML-loaded Lua file, or a second script inside `CDMTab.xml`, would ship without being scanned, and the gate would still print PASS.

The script is also not called from `scripts/release.bat` or `.github/workflows/release.yml` (grep finds no caller), so the "standing check" only happens if someone remembers to run it. 56-01-SUMMARY describes it as standing, which is not true in practice.

**Fix:** For every `.xml` entry in the TOC, parse `<Script file="...">` and `<Include file="...">` recursively, relative to that XML file, and drop the `CDMTab.lua` special case. Then call `node scripts/aura-read-gate.js` in release.yml, or in release.bat before tagging, so a violation blocks the release.

### WR-04: On Forever, a detailed aura ID replaces the whole rank family and cancels any other rank's cast at once

**File:** `Providers.lua:181-190`

**Issue:** When `coverAllRanks` is set, `ns.rankFamilies[ownerKey]` holds every rank's ID (Core.lua ~985). On Forever, a ranked buff's aura is normally a per-rank ID. If the user also enables Detailed and types an aura ID, `aliveBuffs` becomes that single ID for every rank's cast. Failure scenario:

1. The user tracks the max rank with "Cover all ranks" and types that rank's aura ID.
2. The player down-ranks and casts rank 2. OnTrigger files the proc under the same owner through `ns.rankIndex`, with `aliveBuffs = { maxRankAuraID }`.
3. On the next UNIT_AURA out of combat, `ReadPlayerAura(maxRankAuraID)` returns readable and absent, and the timer is cancelled even though the buff is up.

This is the same class of bug the phase set out to fix (a tracker cancelled at the first aura event). Here it is triggered by combining two options, and the dialog gives no warning.

**Fix:** Either check both, or block the combination.

- Check both: at rebuild time (RebuildRankIndex, where allocation is allowed), build a detailed-owner list of `{ auraID, family... }`, and pick that list in OnTrigger when both are set. The cast path stays allocation-free.
- Block the combination: have the auraID field's `validate` or hint refuse or warn when `coverAllRanks` is checked, for example "Aura ID applies to one rank only".

Record the choice in 57-CONTEXT, because Phase 57's aura-state cache inherits the same question.

## Info

### IN-01: The mask and overlay atlases have no fallback

**File:** `CDMTab.lua:1449-1458`

**Issue:** The badge a few lines up guards its art with `C_Texture.GetAtlasInfo`. The portrait calls `mask:SetAtlas` and `overlay:SetAtlas` unguarded. If a client lacks `UI-HUD-CoolDownManager-Mask`, the icon can render fully masked or with no border. The risk is low, because the CDM (a hard dependency) ships these atlases and Display.lua uses them unguarded too, but a guard costs nothing here.

**Fix:** Call `AddMaskTexture` and create the overlay only when `C_Texture.GetAtlasInfo(atlas)` is truthy. Otherwise leave the icon square.

### IN-02: Comments misstate the portrait's offsets and the Layout start point

**File:** `CDMTab.lua:1229-1231, 2082-2083`

**Issue:** The comment says these are the offsets "Display.lua's CreateTimerIcon uses". Display.lua uses -8/7 (40px buff icon, line 459) and -6/5 (bar icon, line 342). Only Blizzard's essential template uses -9/8. The Layout comment still says rows start at "the original Spell ID label offset", but the portrait is first now.

**Fix:** Cite `CooldownViewerEssentialItemTemplate` alone, and change the Layout comment to "under the title".

### IN-03: Two identical secret badges show when the Aura ID box is blank

**File:** `CDMTab.lua:1893-1907`

**Issue:** A blank Aura ID box previews the spell ID, so its badge shows the spell's secrecy level. That is the same level the portrait badge already shows. Two identical warnings appear in one dialog.

**Fix:** In the auraID update, compute the level only when `typed > 0`. Keep the spell-ID icon and name preview.

### IN-04: The aura ID makes early cancellation more likely for auras that land after the cast

**File:** `Providers.lua:183-184`, `BuffEngine.lua:1241-1276`

**Issue:** The scan has no grace window after `startedAt`. Detailed aura IDs invite spells whose aura differs from the cast, and those are more likely to apply late (a projectile, a proc from the next ability). A UNIT_AURA for any other aura in between cancels the proc. This is the pre-existing engine rule, and the opt-out is the escape hatch.

**Fix:** None is required now. Consider a short `startedAt` grace in ScanActiveTimersForCancellation if in-game testing shows this happening.

### IN-05: Editing a running tracker does not affect the live proc

**File:** `Providers.lua:208`

**Issue:** 56-04-SUMMARY documents this. A running proc keeps the `aliveBuffs` it started with, so turning cancellation off does not save a timer that is already running.

**Fix:** None is required. Optionally, `UpdateTrackedBuff` could set `ns.activeTimers[key].aliveBuffs = nil` when `CancelsOnAuraLoss` becomes false.

## Fix Outcomes

Applied 2026-09-28 by gsd-code-fixer (`--auto`, fix scope: all). One atomic commit per finding. After the fixes: `node scripts/aura-read-gate.js` passes (10 reads in 3 allowlisted readers; the count rose from 8 because namespace guards such as `if C_UnitAuras and ...` inside the readers are now hits too), `--selftest` passes 30 cases (was 6), `node scripts/migrate-dryrun.js --selftest` passes 7, `stylua --check .` is clean, CreateAddDialog still hashes to `64e38633612791cb7e1ea41902b75ae45c18167b`, and `scripts/install.bat` redeployed to every client folder.

| Finding | Outcome | Commit |
|---|---|---|
| WR-01 | Fixed | `337e0c3` |
| WR-02 | Fixed | `2e2a534` |
| WR-03 | Fixed (discovery). Release wiring deferred to the cleanup phase | `dc7f0ad` |
| WR-04 | Fixed: "check both" | `5ecae51` |
| IN-01 | Fixed | `85dd04b` |
| IN-02 | Fixed. The in-body Layout comment is flagged, not edited | `acdb83d` |
| IN-03 | Fixed | `a596129` |
| IN-04 | Documented, no change | none |
| IN-05 | Documented, no change | none |

- **WR-01.** A small Lua lexer removes line and block comments and blanks string contents, so a ` --` inside a string no longer truncates the line and a string or comment that names an API is never a hit. Detection flags `\bC_UnitAuras\b` anywhere in code (alias, bracket index, spaced member, any member), the bare aura globals and members (`UnitAura*`, `UnitBuff*`, `UnitDebuff*`, `Get(Player|Unit)Aura*`, `GetAuraDataBy*`, `GetAuraSlots`, `Get(Buff|Debuff)DataBy*`, `GetCooldownAuraBySpellID`, `GetUnitBuff`/`GetUnitDebuff`, which covers `C_TooltipInfo.*`, and AuraUtil's walkers), and a string literal used as an index or a `rawget` key (`_G["UnitAura"]`). The selftest has one case for each shape the review demonstrated, plus `_G`, `rawget` and alias-of-a-global, and five non-read shapes that must give 0 hits. One of those is Core.lua's `{ "UnitAura", "UnitBuff", "UnitDebuff" }` Enum member names. The current tree has zero false positives, and no allowlisted reader needed special handling. Known limit, documented in the script header: a name assembled at runtime (`_G[name]` with `name` a variable) cannot be seen statically.
- **WR-02.** The check runs on lexed code lines. It requires `if C_Secrets.ShouldSpellAuraBeSecret(...) then` followed by `return nil, false`, placed before the first aura read in `ns:ReadPlayerAura`. Selftest cases that must fail: the predicate appears only in a comment, the predicate's result is discarded, the gate block comes after the read. The gated fixture and the real BuffEngine.lua both pass.
- **WR-03.** Discovery walks the TOC in order and follows every `<Script file>` / `<Include file>` recursively, relative to each XML file. It ignores references inside XML comments. It also scans inline XML Lua (`<Script>` bodies and `<On...>` handlers) as top-level violations. The `CDMTab.lua` special case is gone. The selftest covers an in-memory tree (a nested include, a backslash path, a comment-only reference, an inline handler read) and checks that the real tree reaches CDMTab.lua through CDMTab.xml. **Wiring the gate into `scripts/release.bat` or `.github/workflows/release.yml` is left for the milestone cleanup phase to decide.** Neither file was changed, so the gate is still a manual check until then.
- **WR-04.** "Check both" was chosen over blocking the combination. `ns:RebuildRankIndex` (Core.lua) builds `ns.detailedRankFamilies[ownerKey] = { auraID, family... }` for a detailed buff tracker that has "Cover all ranks" and an aura ID. The array is allocated fresh per rebuild and read-only downstream, like `ns.rankFamilies`. OnTrigger picks it with one lookup and falls back to the pooled one-element list, so the cast path allocates nothing. A simple tracker, or a detailed one without "Cover all ranks", behaves as before. This touches Core.lua, which 56-04's whole-phase gate listed as untouched; the review fix needs it. The choice is recorded in 57-CONTEXT (aura-state cache bullet).
- **IN-01.** The mask and the overlay are each applied only when `C_Texture.GetAtlasInfo` knows the atlas. Without the mask the icon stays square, without the overlay it has no border, and neither case is a Lua error.
- **IN-02.** The portrait comment now cites `CooldownViewerEssentialItemTemplate` alone. The Layout comment at `CDMTab.lua` ~2083 sits inside `CreateAddDialog`, which must stay byte-identical, so it was not edited. Instead, the TRACKER_FIELDS header now says the cursor starts under the title and points out the stale wording in the body.
- **IN-03.** The aura-ID badge describes a typed aura ID only. A blank box leaves the level nil and the badge hidden. The spell-ID icon and name preview are unchanged.
- **IN-04 (no change).** The missing `startedAt` grace window is a pre-existing engine rule that applies to every tracker, not only detailed ones. Choosing a window length without in-game evidence would be guesswork. The per-tracker opt-out ("End when the aura is lost" unchecked) already covers a late-landing aura. Revisit only if in-game testing shows early cancels.
- **IN-05 (no change).** A running proc keeps the `aliveBuffs` it started with, by design: the list is a shared read-only reference with a fixed lifetime (the `ns.rankFamilies` rule). The case is transient because the next cast picks up the edit, and it is already documented in 56-04-SUMMARY. Clearing live procs from `UpdateTrackedBuff` would add a cross-module write for that one transient case.

---

_Reviewed: 2026-09-28_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
