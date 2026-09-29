---
phase: 56-detailed-tracking-mode-aura-rules
verified: 2026-09-28T16:30:00Z
status: human_needed
score: 11/11 must-haves verified statically (in-game behaviour pending)
overrides_applied: 0
deferred:
  - truth: "Cooldown trackers can be switched to detailed tracking (Cooldowns-tab Detailed checkbox)"
    addressed_in: "Phase 57"
    evidence: "57-CONTEXT: 'Cooldown trackers also get an aura ID used only for visibility' and 'reset when another spell is cast'; 56-CONTEXT grants discretion to keep the checkbox Buffs-only until Phase 57 adds cooldown children; ns:DetailedModeOffered (CDMTab.lua:1354) is the single widening point"
human_verification:
  - test: "Portrait (ADD-06): open Add on the Buffs tab and on the Cooldowns tab, type a known spell ID"
    expected: "A centered 50px icon under the title, CDM mask and border identical to a TBT tracker icon placed next to it; the spell name centered beneath; no small 18px row under the Spell ID box"
    why_human: "Visual appearance and atlas rendering need the game client"
  - test: "Portrait states: empty Spell ID box, then 999999999"
    expected: "Empty box shows a dimmed question mark and no name; 999999999 shows the question mark and 'Unknown spell' in grey; no Lua error with /console scriptErrors 1"
    why_human: "Rendering and runtime errors need the game client"
  - test: "Portrait hover and badge: hover the portrait, then enter a Contextual-secret spell ID and hover the badge"
    expected: "Portrait hover shows the game tooltip with one Spell ID line and one aura secrecy line; the badge sits on the portrait's top-right corner and its hover explains the level; on Forever record whether the badge is the atlas icon or the '(secret?)' text, and that the text stays inside the dialog"
    why_human: "Tooltip content, frame-level stacking and atlas availability per client need the game"
  - test: "Detailed switch (DTRK-01): Buffs tab Add, toggle 'Detailed tracking'; then open the Cooldowns tab Add"
    expected: "Unchecked by default; checking shows 'Aura ID (blank = same as spell):', its preview row and 'End when the aura is lost' (checked), and the dialog grows; unchecking hides them and shrinks it; Tab skips the hidden aura box. The Cooldowns tab shows no Detailed checkbox"
    why_human: "Dynamic layout and focus behaviour need the game"
  - test: "Aura ID preview (DTRK-02): with the aura box blank, then with a different ID typed"
    expected: "Blank box previews the spell ID's icon and name; a typed ID previews that spell with its own secret badge, independent of the portrait badge"
    why_human: "Live preview behaviour needs the game"
  - test: "Simple trackers unchanged: an existing pre-phase buff tracker and a new simple one"
    expected: "Each starts on the cast and ends when the buff is clicked off out of combat, exactly as in v0.4.1"
    why_human: "Runtime aura events need the game"
  - test: "Aura ID fixes the early end (DTRK-02): a buff whose aura ID differs from its cast ID (TOOL-01 'Aura spell ID' tooltip line shows it), tracked first as simple, then as detailed with that aura ID"
    expected: "Simple: ends at the first out-of-combat aura event. Detailed: keeps running while the aura is up and ends when the aura is clicked off out of combat"
    why_human: "Needs a real cast and real aura application/removal"
  - test: "Opt-out (DTRK-04): uncheck 'End when the aura is lost', Save, cast, click the aura off; then Add a new detailed tracker"
    expected: "The timer runs to its full duration; the new tracker shows the box checked"
    why_human: "Runtime aura events need the game"
  - test: "Unreadable aura never ends a tracker (DTRK-06): with a detailed tracker running, enter combat and click the aura off (or use a secret/Contextual aura, or an M+ key), then leave combat"
    expected: "The timer is not ended while the aura is unreadable; after combat ends with the aura gone it ends at the next readable check (PLAYER_REGEN_ENABLED rescan)"
    why_human: "Secret-value behaviour exists only in the live client"
  - test: "Edit prefill and switch back to simple: Edit a detailed tracker, uncheck Detailed, Save; Edit again and re-check Detailed"
    expected: "Prefill shows Detailed checked with the saved aura ID and opt-out; after Save as simple it behaves as simple; re-checking reveals the old aura ID and opt-out (kept while hidden)"
    why_human: "Dialog state round-trip needs the game"
  - test: "Persistence: after a REAL logout/login (not /reload)"
    expected: "The detailed flag, aura ID and opt-out from the previous checks are still set and behave the same"
    why_human: "SavedVariables round-trip needs a client logout"
  - test: "Forever only: a detailed tracker with 'Cover all ranks' and an aura ID"
    expected: "Cancellation follows the aura ID, not the rank family"
    why_human: "Rank families exist only on the Forever client"
  - test: "Edit a running tracker's aura ID"
    expected: "The change applies from the next cast, not to the proc in flight"
    why_human: "Runtime timing needs the game"
---

# Phase 56: Detailed Tracking — Mode & Aura Rules Verification Report

**Phase Goal:** A user tracker can be switched to detailed tracking, follow an aura that differs from its cast spell, and choose whether losing that aura ends it, and it never ends on an aura it could not read. Plus ADD-06: the centered 50px CDM-styled portrait preview.
**Verified:** 2026-09-28
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

Traced backwards from the runtime:

- **What fills `proc.aliveBuffs` for a detailed tracker:** `UserSpellProviderMixin:OnTrigger` (Providers.lua:180-190). `ns:CancelsOnAuraLoss(entry)` false leaves it nil. Otherwise `ns:DetailedAuraID(entry)` → `ns:AcquireAliveBuffs(ownerKey, auraID)`, and that branch wins over the rank family. The fallback is the unchanged v0.4.1 expression `(fams and fams[ownerKey]) or ns:AcquireAliveBuffs(ownerKey, entry.spellID)`. Line 208 assigns it: `proc.aliveBuffs = aliveBuffs`. Its only consumer is `ns:ScanActiveTimersForCancellation` (BuffEngine.lua:1251-1276). The scan skips a nil or empty list, reads every aura only through `ns:ReadPlayerAura`, and abandons the check on any unreadable read.
- **What writes `entry.detailed`, `entry.auraID` and `entry.keepOnAuraLoss`:** the TRACKER_FIELDS entries `detailed`, `auraID` and `keepOnAuraLoss` (CDMTab.lua:1761-1968), through their `read` hooks. The confirm handler (CDMTab.lua ~2222-2256) reads only shown fields into `values`/`readKeys`. From there `ns:AddTrackedBuff` (the fields copy, BuffEngine.lua:919) or `ns:UpdateTrackedBuff` (the readKeys copy, BuffEngine.lua:1087-1091) persists them. None of the three keys is in `ENGINE_OWNED` (BuffEngine.lua:834-844), and no load-time code strips unknown entry keys.
- **What the portrait reads, and when:** `spellPreview.update` (CDMTab.lua:1516-1524) calls `dialog.GetFieldState("spellID")` at update time and passes the box's number to `ns:RefreshIDPreview`. Every field is built before the first `RefreshState`. OpenForAdd/OpenForEdit end with `RefreshState(true)`, and every keystroke re-runs it.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: Add/edit dialogs offer a simple/detailed switch; simple is the default; simple trackers behave exactly as v0.4.1 | ✓ VERIFIED (static) | `detailed` field CDMTab.lua:1761-1795: reset unchecked, prefill `entry.detailed == true`, read `true or nil`. Both runtime gates check `entry.detailed` first (BuffEngine.lua:626-641), so a simple entry, even one with stale `auraID`/`keepOnAuraLoss`, takes the verbatim v0.4.1 expression (Providers.lua:189). Buffs tab only (`ns:DetailedModeOffered`); the Cooldowns tab is deferred to Phase 57 by the discretion 56-CONTEXT grants |
| 2 | SC2: a detailed tracker with a differing aura ID starts on the cast and ends when that aura is removed out of combat; the aura ID defaults to the spell ID and gets the same preview and "secret?" badge | ✓ VERIFIED (static) | Aura ID beats the rank family (Providers.lua:182-184). Blank or equal to the spell ID is stored as nil, which falls back to the spellID path. The auraID row calls `ns:RefreshIDPreview` and `ns:BuildSecrecyBadge`, and a blank box previews the spell ID (CDMTab.lua:1892-1908) |
| 3 | SC3: opted out, clicking the aura off leaves the timer running; a new detailed tracker has cancellation ON | ✓ VERIFIED (static) | `CancelsOnAuraLoss` false → aliveBuffs nil → scan skips (BuffEngine.lua:1251). `AcquireProc` wipes any stale value. The checkbox resets to checked (CDMTab.lua:1951), read stores `true` only when unchecked (1959), and a missing key means ON |
| 4 | SC4: never ended because the aura could not be read; follows the real state once readable | ✓ VERIFIED (static) | The aura-ID list goes through the same scan → `ns:ReadPlayerAura` (predicate `C_Secrets.ShouldSpellAuraBeSecret` first, BuffEngine.lua:34-50). One unreadable read sets `allReadable=false` and aborts. `node scripts/aura-read-gate.js` → PASS (8 reads in 3 allowlisted readers); `--selftest` 6/6 |
| 5 | SC5: detailed options prefilled in edit and survive logout/login | ✓ VERIFIED (static) | Prefill for all three (CDMTab.lua:1783-1785, 1886-1891, 1953-1956). Keys persist through the generic SavedVariables copy. Hidden children keep their saved values (WR-02 readKeys rule) |
| 6 | SC6 / ADD-06: centered 50px portrait with CDM styling under the title, name centered beneath, badge on the top-right corner; the old 18px row is gone | ✓ VERIFIED (static) | `spellPreview` is first in TRACKER_FIELDS. hover is `PORTRAIT_SIZE` (50), anchored TOP at row x=120 on a 240px row, with the CDM mask and overlay atlases at -9,8/9,-8, matching wow-ui-source CooldownViewer.xml:36-39. Name: TOP to hover BOTTOM, centered, width 208. Badge: `BOTTOMLEFT` at `preview.hover` `TOPRIGHT` (-10,-10), frame level +5. The diff removes the old `SetSize(18, 18)` preview row |
| 7 | CreateAddDialog byte-identical | ✓ VERIFIED | Hash `64e38633612791cb7e1ea41902b75ae45c18167b` at HEAD and at 71ba060 |
| 8 | Cast path allocation-free, no aura read in OnTrigger | ✓ VERIFIED | OnTrigger body has no `{` and no ReadPlayerAura. The gates are field reads only |
| 9 | The Cooldowns tab never shows an empty detailed section | ✓ VERIFIED | `detailed.visible` = `ns:DetailedModeOffered(ctx)` (USER_BUFF only). The children depend on it through `ns:DetailedChildShown`, and `keepOnAuraLoss` also requires USER_BUFF |
| 10 | Shared helpers reused (no duplicated preview/badge logic) | ✓ VERIFIED | `ns:RefreshIDPreview` is called at 1523 and 1897. `ns:BuildSecrecyBadge` is called at 1580 and 1870 |
| 11 | Phase diff scope and file hygiene | ✓ VERIFIED | Source diff vs 71ba060 limited to BuffEngine.lua, Providers.lua, CDMTab.lua, scripts/aura-read-gate.js. Display/Core/MergeMode/EditModeFrames/Config/CDMTab.xml/TOC unchanged. `stylua --check` clean. All w/crlf, no `\r\r\n` |

**Score:** 11/11 truths verified statically. In-game confirmation is pending (see Human Verification).

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Detailed switch on the Cooldowns tab | Phase 57 | 57-CONTEXT: cooldown trackers get "Reset + visibility" and an aura ID for visibility. 56-CONTEXT grants the Buffs-only discretion so no empty section ships |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BuffEngine.lua` | `ns:DetailedAuraID`, `ns:CancelsOnAuraLoss` | ✓ VERIFIED | Lines 626-641, between AcquireAliveBuffs and PreallocateProc. Called from Providers.lua:181-182 |
| `Providers.lua` | OnTrigger aliveBuffs decision | ✓ VERIFIED | Lines 180-190, wired to line 208 |
| `scripts/aura-read-gate.js` | DTRK-06 static proof with `--selftest` | ✓ VERIFIED | Gate PASS, selftest 6/6 (run by the verifier) |
| `CDMTab.lua` | Portrait, shared helpers, detailed/auraID/keepOnAuraLoss fields | ✓ VERIFIED | Lines 1229-1360 (constants and helpers), 1438-1528 (portrait), 1761-1968 (detailed fields) |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| OnTrigger | `ns:AcquireAliveBuffs(ownerKey, auraID)` | `ns:DetailedAuraID(entry)` | ✓ WIRED |
| proc.aliveBuffs | `ns:ReadPlayerAura(buffID)` | ScanActiveTimersForCancellation ipairs loop | ✓ WIRED |
| spellPreview.update | spellID EditBox | `dialog.GetFieldState("spellID")` at update time | ✓ WIRED |
| secrecyBadge | portrait corner | `SetPoint("BOTTOMLEFT", preview.hover, "TOPRIGHT", -10, -10)` | ✓ WIRED |
| auraID / keepOnAuraLoss visible | detailed checkbox | `GetFieldState("detailed")` captured at build → `ns:DetailedChildShown` | ✓ WIRED |
| auraID read | entry.auraID | confirm handler values/readKeys → Add/UpdateTrackedBuff copy | ✓ WIRED |
| auraID row | shared helpers | `ns:RefreshIDPreview(state, id)`, `ns:BuildSecrecyBadge(row, state)` | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Portrait | icon/name | `ns:SpellPreview(id)` from the live Spell ID box | Yes | ✓ FLOWING |
| Portrait badge | `state.level` | `ns:SpellAuraSecrecy(id)` | Yes (nil without the API → hidden) | ✓ FLOWING |
| Aura ID row | icon/name/level | typed ID, else the spell ID | Yes | ✓ FLOWING |
| Cancellation | `proc.aliveBuffs` | saved entry → OnTrigger → scan | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Aura-read gate | `node scripts/aura-read-gate.js` | `AURA-READ GATE PASS (8 reads in 3 allowlisted readers)` | ✓ PASS |
| Gate can fail | `node scripts/aura-read-gate.js --selftest` | `AURA-READ SELFTEST PASS (6 cases)` | ✓ PASS |
| Migration regression | `node scripts/migrate-dryrun.js --selftest` | `SELFTEST PASS (7 cases)` | ✓ PASS |
| CreateAddDialog unchanged | awk \| `git hash-object --stdin` | `64e38633…` at HEAD and at 71ba060 | ✓ PASS |
| Formatting | `stylua --check BuffEngine.lua Providers.lua CDMTab.lua` | clean | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exists, and no plan declares one. The phase's static gate (`aura-read-gate.js`) was run above.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| DTRK-01 | 56-01, 56-03, 56-04 | Simple/detailed switch; simple default, unchanged | ✓ SATISFIED (static; cooldowns in Phase 57) | Truths 1, 9 |
| DTRK-02 | 56-01, 56-03, 56-04 | Aura ID differing from the spell ID; the cast starts, aura-driven behaviour follows the aura ID; default = spell ID | ✓ SATISFIED (static) | Truth 2 |
| DTRK-04 | 56-01, 56-03, 56-04 | Opt-out of ending on aura loss; default ON | ✓ SATISFIED (static) | Truth 3 |
| DTRK-06 | 56-01, 56-04 | Unreadable aura never treated as absent | ✓ SATISFIED (static) | Truth 4 |
| ADD-06 | 56-02, 56-04 | Centered 50px CDM-styled portrait | ? NEEDS HUMAN (visual) | Truth 6 |

REQUIREMENTS.md maps exactly these five IDs to Phase 56, so no requirement is orphaned. Its checkboxes and traceability rows still read "Pending"; that bookkeeping belongs to the orchestrator.

### Anti-Patterns Found

None in the lines the phase diff adds: no TBD/FIXME/XXX/TODO/HACK/placeholder markers and no OnUpdate. The `134400` question-mark texture and "Unknown spell" text are the specified unresolved states, not stubs.

Observations (Info, not gaps):
- The auraID field's `update` runs even while the row is hidden (the walker updates every field), so a spell-ID change costs one extra compare-guarded `ns:SpellPreview`/`ns:SpellAuraSecrecy` lookup. This is dialog-only and not a hot path.
- With a blank aura box, the aura row's badge describes the spell ID, which duplicates the portrait badge. That is consistent with "default aura ID = spell ID".

### Human Verification Required

See `human_verification` in the frontmatter. There are 13 ordered items covering ADD-06, DTRK-01, DTRK-02, DTRK-04 and DTRK-06, the edit round-trip, a real logout/login persistence check, and one Forever-only rank-family check. Run each on retail and on Forever.

### Gaps Summary

No code gaps. Every roadmap success criterion and every plan must-have is implemented and wired in the codebase, and the verifier re-ran every static gate independently. The Cooldowns-tab detailed switch is deferred to Phase 57 under explicit CONTEXT discretion. What remains is in-game confirmation of the visual portrait and of the runtime aura behaviour, which needs the WoW client.

---

_Verified: 2026-09-28_
_Verifier: Claude (gsd-verifier)_
