---
phase: 38-cooldown-trackers
verified: 2026-09-21T00:00:00Z
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
score: 5/5 roadmap success criteria verified at code level; 6/6 requirements (CD-01...CD-06) satisfied at code level, CD-01 inherited from Phase 37 and CD-06 half-verified (migration proven, persistence unprovable on Forever); 7 in-game observations outstanding
overrides_applied: 0
human_verification:
  - test: "Add a spell the Blizzard CDM does not track (e.g. Escape Artist) as a Cooldown tracker into an icon container"
    expected: "Icon appears immediately with no sweep, matching CD-04"
    why_human: "Rendered widget appearance and CDM-catalog independence require a live client"
  - test: "Cast the tracked spell; observe the sweep start, run correctly, and survive entering combat mid-sweep with no Lua error"
    expected: "Sweep starts on cast and keeps running through the combat transition (CD-02)"
    why_human: "Live combat-log-free timer behavior cannot be proven from static code alone"
  - test: "In combat, trigger an effect that reduces that spell's cooldown"
    expected: "The sweep visibly jumps with no /reload and without leaving combat (CD-02's live-CDR half)"
    why_human: "Only a genuinely secret in-combat duration handle proves the no-read contract actually holds at runtime"
  - test: "Add a genuine multi-charge spell as a Cooldown; spend a charge and let it recharge; compare the count's font/size/position against a live CDM Essential icon"
    expected: "Charge count shows bottom-right, matches CDM styling pixel-for-pixel, updates on spend/recharge (CD-03)"
    why_human: "Pixel-matching and secret-charge-count behavior require a running client with a real multi-charge spell"
  - test: "Open the CDM settings tab (config mode) with a cooldown tracker present"
    expected: "Cooldown icon shows a demo sweep beside buff bars/icons; closing clears the preview and any real sweep is unaffected (CD-05)"
    why_human: "Preview rendering is a runtime visual behavior"
  - test: "With hideWhenInactive on and no buffs active, a container holding only cooldown trackers"
    expected: "Container stays visible (cooldown slots always count as activity)"
    why_human: "Container visibility toggling is only observable live"
  - test: "From a clean /reload: combat, then Edit Mode out of combat, then an Edit Mode save, then combat again"
    expected: "No Lua error anywhere in the sequence, specifically none from SetText on a secret charge count"
    why_human: "Runtime error absence cannot be proven by static analysis"
---

# Phase 38: Cooldown Trackers Verification Report

**Phase Goal:** TBT stops being buff-only — a spell cooldown becomes a first-class tracker, rendered by the engine from a duration handle so it stays correct in restricted combat.
**Verified:** 2026-09-21
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A cooldown tracker renders as an icon-only sweep, driven by `C_Spell.GetSpellCooldownDuration` → `Cooldown:SetCooldownFromDurationObject`, no per-frame reads, no secret compared/concatenated | VERIFIED (code) | `Display.lua:569-581` `ApplyCooldownHandle` — the handle flows from the fetch straight into `SetCooldownFromDurationObject` with only a `nil` test between them; no comparison, concatenation, index, or method call on the handle. `Display.lua:654-662` `ApplyCooldownSlot` gates both `ApplyCooldownHandle` and `ApplyChargeCount` behind `icon._cdGen ~= ns.cooldownGeneration or icon._cdKey ~= entry.key` — never per frame. `grep -n 'GetSpellCooldownDuration(' Display.lua` and `grep -n 'SetCooldownFromDurationObject(' Display.lua` each show exactly one call site. |
| 2 | An effect that reduces the cooldown makes the sweep jump live, in combat, with no `/reload` | VERIFIED (code, mechanism); UNCONFIRMED (live) | `Core.lua:588-589,698-699` registers `SPELL_UPDATE_COOLDOWN`/`SPELL_UPDATE_CHARGES` (pcall-guarded via `TryRegisterEvent`) and both advance `ns.cooldownGeneration` on every firing — matching Blizzard's own `CooldownViewer.lua:2147/2170` re-read cadence per the plan's citation. `Display.lua:654` re-fetches the handle whenever that generation changed. Whether a real in-combat secret-bearing handle behaves this way was measured once during research (`38-CONTEXT.md`: "remaining 7.471... a handle is returned even when nothing is running") but the live-CDR jump itself is the phase's headline in-game check. |
| 3 | A multi-charge spell shows its current charge count, rising as charges recharge | VERIFIED (code, mechanism); UNCONFIRMED (live) | `Display.lua:602-626` `ApplyChargeCount` — `ns:CanReadTable(info)` gates every read, `issecretvalue(maxCharges)` guards the only comparison, `chargeCapable[spellID]` is sticky and written only from a readable value, and `SetChargeText` (line 588-590) indexes `info.currentCharges` *inside* the `pcall`-protected call rather than outside it (the exact blocker pattern the plan calls out and avoids). No live multi-charge spell was exercised this phase. |
| 4 | A spell the Blizzard CDM does not support behaves exactly like one it does | VERIFIED (code) | `C_Spell.GetSpellCooldownDuration` and `C_Spell.GetSpellCharges` both take a bare spell identifier with no `cooldownID` parameter and never touch `C_CooldownViewer` anywhere in `Display.lua` (`grep -n 'C_CooldownViewer' Display.lua` — no hits). The cooldown render branch (`Display.lua:915-925`) is reached purely from `entry.trackerType == "cooldown"` in `ns.db.trackedBuffs`, independent of any CDM registration. |
| 5 | Preview mode shows cooldown icons alongside buff bars/icons; a pre-phase database loads with every buff intact and new cooldown entries survive logout→login on retail | VERIFIED (code, preview + migration); UNPROVABLE HERE (retail persistence) | Preview: `BuffEngine.lua:340-364` `ns:StartAllPreviewTimers` no longer skips `trackerType == "cooldown"` (seam deleted) and builds its synthetic proc from `entry.duration` only, via the provider-agnostic `ns:GetDisplayInfoForKey`; `Display.lua:888-914`'s `if timer then` branch (unchanged) turns that proc into `icon.cooldown:SetCooldown(startedAt, duration)` with zero type branching. Migration: `BuffEngine.lua:79-82` — `CURRENT_SCHEMA_VERSION` stays `4`, no `ver < 5` block; `entry.trackerType` reads `nil` on any pre-Phase-37 entry, and `nil == "cooldown"` is false everywhere it's tested, so a buff-only DB is unchanged. Persistence across logout→login is `SavedVariables`-file behavior the Forever beta never exercises (per `38-CONTEXT.md` and the task brief) — deferred to Phase 44 on retail. |

**Score:** 5/5 roadmap success criteria verified at the code level. Criteria 2 and 3's live-behavior halves, and criterion 5's retail-persistence half, are outstanding human/Phase-44 checks — not code gaps.

### Deviations from the Plan (both SUMMARYs)

Both plans report only textual/wording corrections (a forbidden-substring rewording in a comment, and two verification-grep corrections where the grep matched an explanatory comment rather than code). Read against the actual diffs, both are cosmetic and do not change behavior — confirmed directly rather than taken on the SUMMARY's word (see the `grep`-based re-verification of each cited claim throughout this report).

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| CD-01 | User can register a spell cooldown as a tracker, choosing "cooldown" vs "buff" | SATISFIED — inherited from Phase 37, not delivered here | The add dialog's buff/cooldown choice shipped in `37-03` (`CDMTab.lua:864-901`, confirmed unmodified by this phase's `git diff --stat` — `CDMTab.lua` does not appear). Phase 38 is what makes a registered `trackerType == "cooldown"` entry mean something; no task in either 38-01 or 38-02 touches the add dialog itself. Recorded as inherited per the phase's own plan notes, not claimed as new work. |
| CD-02 | Icon with sweep driven by the game's duration handle, correct in combat, follows CDR live | SATISFIED (code); live-CDR jump and in-combat correctness are human checks | See Truth #1/#2 above. |
| CD-03 | Multi-charge spell shows current charge count, recharges correctly | SATISFIED (code); live charge behavior and pixel-match are human checks | See Truth #3 above; font/anchor verified byte-for-byte against Blizzard source (see Key Link table). |
| CD-04 | Works for spells the Blizzard CDM does not support | SATISFIED (code) | See Truth #4 above. |
| CD-05 | Renders correctly in preview mode alongside buff trackers | SATISFIED (code); visual preview confirmation is a human check | See Truth #5 above (preview half). |
| CD-06 | Cooldown trackers persist across sessions; buff-only DB migrates without loss | HALF-SATISFIED — migration proven in code, persistence unprovable on Forever | `BuffEngine.lua:79-82` (migration, verified above). Session persistence is ordinary `TerribleBuffTrackerDB` write-through with no phase-specific serialization code added or needed (a cooldown entry is a plain field on the same table every buff entry already lives in) — but the Forever beta never reads saved variables back, so the write/reload round-trip itself is deferred to Phase 44 on retail per the task brief. Recorded as half-verified, not passed. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | `ns.cooldownGeneration`/`ns.trackerGeneration`, `MarkCooldownsDirty`/`MarkTrackersDirty`, pcall-guarded event registration | VERIFIED | `Core.lua:294-312` (counters + markers, both bodies contain no `{`), `580-589` (`TryRegisterEvent`, both new events registered only through it), `664-699` (four `MarkCooldownsDirty()` call sites: shared spell-update branch, `SPELLS_CHANGED`, `PLAYER_ENTERING_WORLD` outside the one-shot guard, `PLAYER_REGEN_ENABLED`). |
| `Providers.lua` | Cooldown casts mark cooldown generation dirty instead of being skipped | VERIFIED | `Providers.lua:101-108` — `entry.trackerType == "cooldown"` branch now calls `ns:MarkCooldownsDirty()` then `return nil`; `grep -n 'Phase 38' Providers.lua` shows only the permanent explanatory comment (the "future owner" marker is gone), and `UserSpellProviderMixin:OnTrigger` still has exactly one `return {` (the buff proc). |
| `BuffEngine.lua` | Cooldown entries take part in preview; three mutation choke points stamp tracker generation | VERIFIED | `BuffEngine.lua:340-345` (preview seam deleted, comment explains why no type branch is needed), `269-271`/`298-300`/`324-326` (`AddTrackedBuff`/`RemoveTrackedBuff`/`SetBuffSection`, each nil-guarded `ns:MarkTrackersDirty()` call). |
| `Display.lua` | `ChargeCount` widget, four cooldown helpers, generation-stamped slot-count cache, cooldown branch in `RenderIconContainer`, cooldown skip in `RenderBarContainer` | VERIFIED | `Display.lua:336-357` (widget), `539-663` (`RefreshCooldownSlotCounts`, `ApplyCooldownHandle`, `SetChargeText`, `ApplyChargeCount`, `ApplyCooldownSlot` — zero `{` across all five), `698` (bar skip), `823` (`hasActiveIcons` includes cooldown slot count), `915-925` (cooldown branch, positioned between timer and placeholder branches exactly as specified). |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Core.lua eventFrame` | `ns:MarkCooldownsDirty` | `SPELL_UPDATE_COOLDOWN`/`SPELL_UPDATE_CHARGES`/`SPELLS_CHANGED`/`PLAYER_ENTERING_WORLD`/`PLAYER_REGEN_ENABLED` branches | WIRED | `Core.lua:664-699`, four distinct call sites as designed (two events share one branch). |
| `BuffEngine.lua` mutation functions | `ns:MarkTrackersDirty` | direct call at each of the three choke points | WIRED | `BuffEngine.lua:269,298,324` — exactly three call sites, each nil-guarded the same way as the neighboring `RebuildRankIndex` calls. |
| `Display.lua RenderIconContainer` | `C_Spell.GetSpellCooldownDuration` | `ApplyCooldownSlot`, gated on `ns.cooldownGeneration` | WIRED | `Display.lua:654-662,575`. Exactly one call site, inside the generation-change guard. |
| `Display.lua icon.cooldown` | `LuaDurationObject` | `Cooldown:SetCooldownFromDurationObject(handle)` | WIRED | `Display.lua:577`. Handle passed straight through, never inspected. |
| `Display.lua ns:UpdateDisplay` | `ns.trackerGeneration` | `RefreshCooldownSlotCounts` early-out on unchanged generation | WIRED | `Display.lua:539-543,998-1000`. Called exactly once, before the container loop. |
| `Display.lua ApplyChargeCount` | `C_Spell.GetSpellCharges` | `ns:CanReadTable` guard, `issecretvalue` on the only comparison | WIRED | `Display.lua:602-626`. Confirmed `info.currentCharges` is indexed *inside* `pcall(SetChargeText, ..., info)` (line 588-590, 624) rather than as a pre-evaluated `pcall` argument — the exact blocker pattern named in the verification brief was checked for and is absent. |

### Data-Flow Trace (Level 4)

| Concern | Trace | Status |
|---|---|---|
| A cooldown proc never reaches `ns.activeTimers` or the cancellation scan | `git diff 7bd1f27~1..fa19683 -- BuffEngine.lua Providers.lua Display.lua` shows zero touched lines inside `ns:GetActiveTimers` or `ns:ScanActiveTimersForCancellation`; `grep -n 'ScanActiveTimersForCancellation' Display.lua` returns nothing. `Providers.lua:106-108` returns `nil` for a cooldown cast instead of a proc, so nothing is ever inserted. | VERIFIED — excluded by construction, not by a guard. |
| Charge-capability cache cannot be poisoned by a first restricted sighting | `Display.lua:616-619`: `chargeCapable[spellID]` is written only inside `if not issecretvalue(maxCharges) and type(maxCharges) == "number"`; when unmet, the key stays unset and `shown = chargeCapable[spellID] == true` evaluates false — no throw, no stale true value written from a secret. | VERIFIED |
| Preview proc cannot leak into the live/secret path | `BuffEngine.lua:351-361`: synthetic proc built solely from `entry.duration` (a number the user typed) and written only to `ns.previewTimers`, never `ns.activeTimers`; `ns:GetActiveTimers` (`BuffEngine.lua:160-183`) merges the two tables with real-priority but never promotes a preview proc into `ns.activeTimers` itself — the tables stay physically separate for the life of the entry. | VERIFIED |
| Icon cache "nil vs never-populated" trap | `Display.lua:642`: `if icon.cachedSpellID ~= spellID or icon.cachedIcon == nil then` — the `3c1acf2` fix's guard shape is present at the new cooldown call site, matching the buff-path idiom at lines 764 and 946. | VERIFIED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Exactly one `GetSpellCooldownDuration` call site | `grep -n 'GetSpellCooldownDuration(' Display.lua` | line 575 only | PASS |
| Exactly one `GetSpellCharges` call site | `grep -n 'GetSpellCharges(' Display.lua` | line 608 only | PASS |
| Exactly one `SetCooldownFromDurationObject` call | `grep -n 'SetCooldownFromDurationObject(' Display.lua` | line 577 only | PASS |
| No `ScanActiveTimersForCancellation` reference in Display.lua | `grep -n 'ScanActiveTimersForCancellation' Display.lua` | no hits | PASS |
| No new flavour check introduced | `grep -n 'GetBuildInfo\|CLIENT_HAS_SPELL_RANKS' Display.lua` | no hits | PASS |
| `CLIENT_HAS_SPELL_RANKS` still one definition, one reader addon-wide | `grep -rn 'CLIENT_HAS_SPELL_RANKS' *.lua` | `Core.lua:336` (def), `CDMTab.lua:941` (reader) | PASS |
| `CURRENT_SCHEMA_VERSION` unchanged, no `ver < 5` block | `grep -n 'CURRENT_SCHEMA_VERSION\|ver < 5' BuffEngine.lua` | `= 4` only, no `ver < 5` | PASS |
| `stealMode` gains no new behavioral reader | `grep -rn 'stealMode' *.lua` | only pre-existing checkbox write/sync + default seed | PASS |
| No `C_Item` cooldown/trinket work added | `grep -rn 'C_Item' *.lua` | only pre-existing `Providers.lua:466` Trinket/Pot scan | PASS |
| `CDMTab.lua` untouched | `git diff --stat 7bd1f27~1..fa19683 -- CDMTab.lua` | empty | PASS |
| Exactly the four expected files touched | `git diff --stat 7bd1f27~1..fa19683` | `Core.lua`, `BuffEngine.lua`, `Providers.lua`, `Display.lua` | PASS |
| `NumberFontNormalSmall` not used in code | `grep -n 'NumberFontNormalSmall' Display.lua \| grep -v -- '--'` | empty | PASS |
| `{` count unchanged in the three render-path functions | manual `awk`/`grep` scan of `ns:UpdateDisplay`, `RenderBarContainer`, `RenderIconContainer` | 0 / 1 / 1 — the two pre-existing `bar.proc = {...}` / `icon.proc = {...}` placeholder constructors only | PASS |
| Zero `{` in the four new Display.lua cooldown helpers | manual scan of lines 539-663 | 0 | PASS |
| Debt markers | `grep -n 'TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER' Core.lua BuffEngine.lua Providers.lua Display.lua` | no hits | PASS |
| `stylua --check .` | `stylua --check .` from repo root | exit 0 | PASS |
| `CHANGELOG.md` untouched | `git diff --stat 7bd1f27~1..fa19683 -- CHANGELOG.md` | empty | PASS |
| All six commits exist | `git show --oneline -s` for each of `7bd1f27,ad6dc5c,ba9a163,31ccdbf,3c4d552,fa19683` | all present | PASS |

### Probe Execution

`find scripts -path '*/tests/probe-*.sh' -type f` returns nothing, and no plan/summary in this phase references a probe script. SKIPPED — no runnable entry points; this is a WoW addon with no headless test harness (consistent with the verification-reality note and with Phase 37's precedent).

### Anti-Patterns Found

None in the four modified files.

### Human Verification Required

See YAML frontmatter `human_verification` block, folded in from Plan 02's own end-of-plan checklist rather than re-derived. All seven items require the Forever beta client and were not attempted by either plan (both explicitly defer them to Phase 42's end-to-end pass). None of the seven are code gaps — the underlying mechanism for each is implemented and verified above at the code level:

- CD-02's live-CDR jump and in-combat survival — the invalidation-counter plumbing is wired and the "nothing is read" contract holds by inspection, but only a live secret-bearing handle in restricted combat proves the sweep actually reacts.
- CD-03's multi-charge display and pixel match — font/anchor/frame-order are verified byte-for-byte against `wow-ui-source`'s `CooldownViewer.xml`, but no real multi-charge spell was exercised.
- CD-04's CDM-independent spell — confirmed no `C_CooldownViewer` call exists anywhere in the render path, but a live Escape Artist test is the concrete proof.
- CD-05's visual preview — the mechanism reuses the existing buff preview path with zero type branching, but the demo sweep's appearance is only observable live.
- The cooldown-only container's `hideWhenInactive` exemption — the cache and boolean-OR are correct by reading, but container visibility is a runtime behavior.
- The clean-reload/combat/EditMode/combat sequence — no code path was found that could throw (every secret-adjacent read is `issecretvalue`-guarded or `pcall`-wrapped), but absence of a Lua error is not provable statically.

`CD-06`'s persistence half is separately not verifiable until Phase 44 on retail, per the task brief and `38-CONTEXT.md` — recorded as half-satisfied above, not as a gap.

### Gaps Summary

No code-level gaps found. Every observable truth, artifact, key link, and data-flow concern traces to real, substantive, wired code — not a stub. The phase's highest-risk code path (`ApplyChargeCount`'s secret-charge handling) was read line-by-line against the specific failure mode named in the verification brief (`pcall(f, obj, info.currentCharges)` indexing outside the protected call) and confirmed absent — the shipped form (`SetChargeText` receiving `info` itself, indexing inside) is correct. The hot-path discipline claim was independently re-counted (not taken from the SUMMARY table): zero new table constructors in `ns:UpdateDisplay`/`RenderBarContainer`/`RenderIconContainer`, both pre-existing placeholder constructors accounted for, and both new API calls (`GetSpellCooldownDuration`, `GetSpellCharges`) confirmed to sit behind the generation/key guard rather than firing per tick. The scope fence held: no bars for cooldowns, no `C_Item` work, no steal-mode work, schema version unchanged, `CLIENT_HAS_SPELL_RANKS` still one definition/one reader, `CDMTab.lua` and `CHANGELOG.md` both untouched.

The phase is not closed because both plans are non-visual by design and defer all in-game confirmation to Phase 42 — seven items require the Forever beta client, none of which are code gaps. `CD-06`'s persistence half additionally requires retail (Phase 44). Status is `human_needed`, not `gaps_found`.

---

*Verified: 2026-09-21*
*Verifier: Claude (gsd-verifier)*
