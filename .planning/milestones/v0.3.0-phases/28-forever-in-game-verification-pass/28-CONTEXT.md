# Phase 28: Forever In-Game Verification Pass - Context

**Gathered:** 2026-09-18
**Status:** Ready for planning — **execution is human-gated**
**Mode:** Auto-generated (autonomous run — user unavailable)

<domain>
## Phase Boundary

Confirm TBT works end-to-end on a live WoW Forever beta character, and resolve every genuine unknown this milestone carries by observing the real client rather than inferring from source.

Requirements owned: VER-02, VER-03, VER-04, VER-05, VER-06, VER-07, VER-08, PAR-02.

**Not this phase:** any new capability. PAR-02 permits only narrow defensive reads to fix a Forever-only Lua error — never a flavor branch, never a feature.

</domain>

<execution_gate>
## ⛔ This Phase Cannot Be Executed Autonomously

Every requirement in this phase requires a human at a running WoW Forever client. An agent cannot launch the game, log in, cast a spell, or read an AddOns list. There is no honest way to mark VER-02 through VER-08 complete without that.

**What the autonomous run produces:** a `28-VERIFICATION-CHECKLIST.md` artifact — the ordered steps, expected results, and a place to record findings — plus the deferred fast-follow slot for PAR-02.

**What the autonomous run must NOT do:** claim any VER requirement passed, generate a VERIFICATION.md with `status: passed`, or infer Forever behavior from the Midnight source tree.

**Precondition before a human runs this:** Phase 25's dual gate must have passed (retail loads from `_Mainline.toc`, Forever shows and loads from `_Camelot.toc`), and Phase 26's `install.bat` must have deployed to the Forever client.

</execution_gate>

<decisions>
## Implementation Decisions

### Checklist ordering

- **D-01:** Use the consolidated 12-step checklist from `.planning/research/SUMMARY.md` §"In-Game Verification Checklist" as the source. It is already deduplicated across all four research documents and ordered by risk/payoff. Do not re-derive it.
- **D-02:** **Step 4 (cast detection) is the highest-priority item and should be attempted early**, even though the checklist runs in order. It resolves whether `UNIT_SPELLCAST_SUCCEEDED` delivers a usable spellID on Forever — the single unknown TBT's entire detection architecture rests on. If it fails, most later steps become moot and the milestone needs re-scoping.

### Recording findings

- **D-03:** Every observation must be recorded against a **named beta build and interface number**, re-derived from the live client's `.build.info` at the time of testing — not copied from `PROJECT.md`'s pinned `16001`. The beta moves; a finding without a build number is not reproducible.
- **D-04:** VER-08 specifically requires recording *which* degraded state appears on the Trinket/Pot tiles — a neutral placeholder versus a real-but-wrong retail item name and icon. This is the empirical answer to the research conflict adjudicated in SUMMARY.md, and it also validates Phase 27's fix. Record it either way, even though the fix is correct regardless of the answer.

### Known platform noise — do not misattribute to TBT

- **D-05:** Third-party reports against build `1.60.1.69893` claim **addon SavedVariables are written on logout but never read back**. If TBT's config or Edit Mode positions do not persist across `/reload` on Forever, check whether other installed addons show the same symptom before concluding it is a TBT regression.
- **D-06:** The beta client **stops delivering Lua errors after 100 in a single session** until the next `/reload`. Test with a minimal addon list and `/reload` between sessions rather than one long accumulating session, or TBT's own errors may go silently unreported.
- **D-07:** Third-party reports describe **every `C_CooldownViewer` category as empty on Forever**, even for known spells. TBT never reads that category data, so an empty Blizzard CDM list is not a TBT failure.
- **D-08:** Trinket and Pot tiles being empty is **expected, not a bug** — their catalogs are current-retail-season spellIDs no Forever character can produce. Lust is genuinely uncertain rather than confirmed-empty: Bloodlust (2825) and Heroism (32182) are old, stable IDs that may well exist, while Time Warp / Fury of the Aspects / Harrier's Cry depend on specs that may not exist at Forever's beta level cap.

### PAR-02 fast-follow

- **D-09:** Any Forever-only Lua error found gets a **narrow defensive read** — a nil-check or a guarded call at the exact failing site. Never a `WOW_PROJECT_ID` branch, never a new code path, never a feature. This is the milestone's parity-only constraint.
- **D-10:** If a Forever-only error is found, it becomes its own plan within this phase rather than an ad-hoc edit, so it gets a commit and a SUMMARY entry like any other work.

### Claude's Discretion

The whole phase was auto-discussed. The decisions above are procedural rather than design choices — the substance comes from the research checklist, which the user has already seen summarized.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The checklist itself
- `.planning/research/SUMMARY.md` §"In-Game Verification Checklist (consolidated, deduplicated, ordered by risk/payoff)" — the 12 steps, authoritative
- `.planning/research/SUMMARY.md` §"Features expected to be empty/meaningless on Forever - not bugs"
- `.planning/research/SUMMARY.md` §"Genuine unknowns - only in-game testing can resolve these"
- `.planning/research/SUMMARY.md` §"Platform/beta caveats that could cause false bug reports against TBT"
- `.planning/research/FEATURES.md` — the per-capability compatibility matrix and its confidence ratings; explains *why* each step is on the list

### Phase scope
- `.planning/ROADMAP.md` — Phase 28 goal, dependencies, six success criteria
- `.planning/REQUIREMENTS.md` — VER-02..08 and PAR-02 exact wording
- `.planning/PROJECT.md` — Constraints (parity-only), Context (Forever install path, interface number)

### Depends on
- `.planning/phases/25-toc-split-retail-regression-gate/25-CONTEXT.md` — D-09 lists what was explicitly deferred *from* Phase 25's gate *to* this phase; those items are this phase's inbox
- `.planning/phases/27-provider-at-rest-defensive-fix/27-CONTEXT.md` — D-03/D-04 explain what the Trinket/Pot tiles should now render, which VER-08 is checking

### Code, if a fast-follow fix is needed
- `Core.lua` — event registration, `PLAYER_ENTERING_WORLD`, load print
- `BuffEngine.lua` — `OnSpellCastSucceeded`, `OnUnitAura`, `ScanActiveTimersForCancellation`
- `CDMTab.lua` — CDM attach and tab injection
- `C:\Users\jonat\Repositories\wow-ui-source` branch `live` — **read-only**, never check out another branch

</canonical_refs>

<code_context>
## Existing Code Insights

### Established Patterns
- TBT hard-requires Blizzard's Cooldown Manager; there is no standalone fallback. `Blizzard_CooldownViewer` is confirmed present on Forever with `## AllowLoadGameType: standard, camelot`, and every CDM file TBT touches diffed clean against Midnight 12.1.
- `Blizzard_EditMode` is likewise present and unchanged in the APIs TBT uses.
- The secret-value API surface (`C_Secrets.ShouldAurasBeSecret`, `ShouldSpellAuraBeSecret`, `C_UnitAuras.GetPlayerAuraBySpellID`) is byte-identical to Midnight's.

### The genuine unknown
- `UNIT_SPELLCAST_SUCCEEDED` is a core client/server event, not scripted Lua — **invisible to any source diff**. Whether it delivers a usable numeric spellID on Forever cannot be determined from research at all. Checklist step 4 is the only way to know.

### Integration Points
- Deployment to the Forever client comes from Phase 26's `install.bat`, which copies both TOCs to `_classic_beta_`.

</code_context>

<specifics>
## Specific Ideas

- The user's Phase 25 decision deliberately narrowed that phase's Forever check to "appears in the AddOns list and loads with no Lua error", explicitly deferring CDM reachability, SavedVariables persistence, and empty tiles to **this** phase. Those three are this phase's opening items, not rediscoveries.

</specifics>

<deferred>
## Deferred Ideas

- **`COMBAT_LOG_EVENT_UNFILTERED` availability on Forever** — record as an observation only if it surfaces. TBT is not changing its detection strategy this milestone regardless of the answer; a detection rewrite is a milestone of its own.
- **Forever-appropriate lust / trinket / pot catalogs** — `FCON-01..03`, a future milestone. Empty tiles are in scope to *record*, not to *fix*.

</deferred>

<deferred_questions>
## Deferred Questions for Human Review

1. **This phase is blocked on you.** It cannot progress without a human at a Forever client. The autonomous run produces the checklist and stops.
2. **If checklist step 4 fails** — `UNIT_SPELLCAST_SUCCEEDED` not delivering a usable spellID on Forever — the milestone's premise is broken and v0.3 needs re-scoping, not patching. That is a decision for you, not a fast-follow fix.

</deferred_questions>

---

*Phase: 28-Forever In-Game Verification Pass*
*Context gathered: 2026-09-18 (autonomous)*
