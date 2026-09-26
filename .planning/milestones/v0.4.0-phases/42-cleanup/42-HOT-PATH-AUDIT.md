# Phase 42 — Hot-Path and Duplication Audit

**Written:** 2026-09-22, after plans 42-01 through 42-05 landed (`295c601`..`a28610e`).
**Scope:** `ns:UpdateDisplay` and everything it reaches, plus the Merge Mode event path.
**Satisfies:** ROADMAP Phase 42 success criteria 1, 2 and 4, and 42-CONTEXT.md **D6**.

This document exists because a cleanup phase that only edits code leaves no way to tell
"examined and justified" apart from "never looked at". Phase 42 also runs *before* its own
verification pass — the 42/43 swap of 2026-09-22 means nothing here has been exercised in game —
so the record of what was read and deliberately left alone is the thing Phase 43 and the next
reader of the render path actually inherit.

**Every verdict below is either *removed* (naming the commit) or *justified* (naming the reason it
must stay).** Nothing says "looks fine". Every claim about the code was re-derived from the file as
it ships, not copied from the plan that predicted it; where the plan and the code disagreed, the
code won and the disagreement is recorded.

---

## Section 0 — The three structures that must not be "simplified"

Restated first because everything below reads `MergeMode.lua` and `Display.lua` closely, which is
exactly the condition under which these look like waste (42-CONTEXT.md **D5**).

| Structure | Why it is not redundancy | Checked |
|-----------|--------------------------|---------|
| **One aura container per merged entry per unit** (`MergeMode.lua`) | An aura FRAME carries `DenyTaintedAccessWhenAurasAreSecret` and cannot be moved in combat; the CONTAINER carries no such restriction. TBT moves containers, never frames. Collapsing back to one container per unit breaks Centered growth outright. | `auraContainers[unit][cooldownID]` is still two-level (`MergeMode.lua:868-875`); `ns:PlaceMergeAura` still walks `#AURA_UNITS` and moves the *container*, never the frame (`MergeMode.lua:1015-1025`). |
| **`ns:GridSlotPlacement` as the single source of grid arithmetic** (`Display.lua`) | Display and MergeMode drifted three separate times when each derived it. Inlining it "to save a call" is a regression. | `grep -c 'function ns:GridSlotPlacement' Display.lua` → **1**. Not inlined, duplicated or specialised. |
| **`entry.cdmShown`, stamped from Blizzard's own CDM item frames** | The aura APIs are secret in combat and the engine's own visible count is unreadable. The CDM's `IsShown()` is the one plain boolean available. | `SlotDraws` (`Display.lua:86-88`) still answers the merged case from `entry.cdmShown == true` and from nothing else. |

**The per-entry container count is a cost this audit records and justifies. It is never a finding to
remove.**

---

## Section 1 — Hot-path findings

The tick is `UPDATE_INTERVAL = 0.05` (`Display.lua:8`), i.e. **20 Hz**, running `ns:UpdateDisplay`
once per tick over every registered container. Phase 36 made `ns.CONTAINERS` unbounded, so "per
container per tick" is now a cost that grows with the player's configuration rather than a fixed
four.

| # | Site | What it costs | Verdict | Reason |
|---|------|---------------|---------|--------|
| H1 | `ns:PlaceMergeAura` — four stamp tables (`MergeMode.lua:770`, compared at `:1005-1008`) | Four table indexes and four equality tests per merged entry per tick, on the unchanged path | **Justified** | A packed string key would allocate **one string per merged entry per tick at 20 Hz** purely to discover that nothing moved. The four comparisons exist to avoid exactly that allocation. The shape is still four separate tables, as D6 predicted. |
| H2 | `ApplyUserCooldown` (`Display.lua:887-935`), called from `ApplyCooldownSlot` every tick | Two number comparisons, three stamp tests and one table index. **No API call, no allocation** on the steady path | **Justified** | Nothing fires an event when a *TBT-owned* cooldown ends — the duration is a number the player typed, not a game handle — so the grey has to come off by the clock. Generation-gating it would leave a stale grey until an unrelated event moved `ns.cooldownGeneration`. |
| H3 | `ns:GetContainerCategory(def)` (`Core.lua:109-111`), called from `RenderIconContainer:1457` | One field read and an `or` fallback, per container per tick | **Justified** | Re-derived rather than trusted from the database so a `growthDirection` left behind by a container that **changed category** cannot produce a layout its dropdown never offered. Caching it would reintroduce exactly the stale-value class it guards. |
| H4 | The centred pre-pass (`RenderIconContainer:1462-1471`) | A second walk of `#slots` calling `SlotDraws`, per container per tick | **Justified** | Gated on `if centered then`, so a non-centred container pays **nothing**. Centering cannot place the first icon without knowing `drawnCount`, and `SlotDraws` allocates nothing (`Display.lua:86-96` — branch chain over already-computed fields, no table, no closure, no API call). |
| H5 | `ns:UpdateDisplay`'s `wipe(timersByContainer[def.key])` loop (`Display.lua:1715-1717`) | One `wipe()` per registered container per tick, over an unbounded `ns.CONTAINERS` | **Justified** | The per-key lists are constructed **once**, in `ns.AllocateContainerRuntime`, and only ever wiped here — `Display.lua:102-110` makes that contract explicit and names a table constructor in `UpdateDisplay` as the thing it exists to forbid. `wipe()` on an already-small list is a C call with no allocation; the alternative (a fresh table per container per tick) is strictly worse and grows the same way. |
| H6 | `RefreshCooldownSlotCounts` (`Display.lua:682-704`) | One integer compare and a return on the unchanged path | **Justified** | Confirmed still gated on `ns.trackerGeneration`. The obvious alternative — walking `ns.db.trackedBuffs` before the visibility test — costs a full `pairs()` per container per tick on the **hidden** path, which is the common one. Note the deliberate non-stamp when `ns.db.trackedBuffs` is not ready yet: the counts are retried next tick rather than cached as "no cooldown slots exist". |
| H7 | `MergedSlotsFor` / `BuildActiveByKey` / `AppendMergedSlots` (42-05, `Display.lua:1152/1165/1176`) | One Lua call each, **once per container per tick** | **Justified** | Call-site audit: `MergedSlotsFor` at `:1190` (bar) and `:1401` (icon); `BuildActiveByKey` at `:1208` and `:1444`; `AppendMergedSlots` at `:1233` and `:1442`. Two call sites each, both outside any per-widget loop. `MergedSlotsFor` returns **two values, not a table** (`return merged, merged and #merged or 0`), so the once-per-container-per-tick helper allocates nothing. |
| H8 | `ApplyCachedIcon` (42-05, `Display.lua:735`) | One Lua call **per rendered widget per tick** | **Justified** — with a correction, see §1a | It *replaces* an inline block at the same point rather than adding work: the steady path gains one Lua call and loses nothing. The cache test it guards (`cachedSpellID ~= spellID or cachedIcon == nil`) is unchanged, and still avoids an `ns:GetSpellIcon` lookup per widget per tick. |
| H9 | `ClearCooldownStamps` (42-04, `Display.lua:762`) | **Zero** on the steady path | **Justified** | Both call sites (`:1513`, `:1576`) keep their `if icon._cdKey then` guard outside the helper. A widget not coming off a cooldown slot pays one nil test and never enters the call. Folding the guard in would have converted that nil test into a function call — the helper's own comment now asserts this so the next reader does not "finish the job". |
| H10 | The placeholder tooltip payload (`bar._placeholderProc` / `icon._placeholderProc`, 42-04) | **Nothing** on the second and subsequent ticks | **Removed** — `c2b89b2` | Was a fresh table constructor per *inactive* placeholder slot per container per tick whenever `hide when inactive` is off, in combat, at 20 Hz. Now one nil test plus three unconditional field overwrites into a per-widget owned table (`Display.lua:1303-1307`, `:1631-1635`). `grep -v '^\s*--' Display.lua \| grep -c 'proc = { spellID'` → **0**: no table constructor is assigned to `.proc` in executable code any more. |
| H11 | `ns.mergeShownSlots` / `ns.mergeItemFrames` | One table index and one `#` per container per tick | **Justified** | Both are built **event-driven only** and never rebuilt in the render path. Writers: `ns:RefreshMergeShownSlots` (`MergeMode.lua:545-…`) and `CollectShownCooldownIDs` (`:334-364`), reached only through `ns:QueueMergeShownSlots`. Readers in the render path: `Display.lua:1017`, `:1123`, `:1153` — all plain indexes. `RefreshMergeShownSlots`'s own header states the invariant: "never called from `ns:UpdateDisplay` or any `OnUpdate`". |
| H12 | `ns:QueueMergeShownSlots` / `ns:QueueMergeMirror` — `C_Timer.After(0)` + single-flight flag (`MergeMode.lua:1028-1076`) | One boolean test on the coalesced path; one timer object per frame at most | **Justified and load-bearing — a structure to protect, not a cost to remove** | See §1b. |
| H13 | `ns:RefreshMergeAuraGroups` / `SyncEntryContainers` — `{ includeSpellIDs = includeSet }` (`MergeMode.lua:879`, `:910`, `:968`) | One table constructor **per entry per unit per refresh** | **Justified** | It is **event-driven** — a configuration change — not per-tick. `ns:RefreshMergeAuraGroups` is reached from Merge Mode toggles, CDM data changes and Edit Mode exits, never from `ns:UpdateDisplay`. This is the whole argument, and it is stated explicitly here so the next reader does not mistake it for the per-tick allocation that D2 removed (H10). The `includeSet` **payload** is already pooled: `slotFilters[id]` is created once per entry and wiped in place (`:764-767`, `:850-855`). Only the one-field wrapper is fresh, and making it a pooled table would mean handing the engine a table TBT later mutates, which is worse. |
| H14 | `ns:GetActiveTimers` (`BuffEngine.lua:194-222`), called once per tick from `ns:UpdateDisplay:1704` | **Two tables (`result`, `sorted`) plus one comparator closure, per tick, unconditionally** | **Justified by the scope fence — carried, not fixed** | See §1c. This is the largest remaining per-tick allocation in the path and it is **out of this phase's scope**: the function is from the initial commit and its `result`/`sorted`/inline-closure shape is from v0.2.4 (`4cd64fc`), far earlier than Phase 31. `PROJECT.md`'s "No refactors during cleanup phases" protects it, and D1's override extends only to the two render functions. Recorded so it is inherited rather than rediscovered. |

### §1a — `ApplyCachedIcon` is per-widget, and 42-05's own constraint says helpers never are

Plan 42-05's `<constraints>` and its threat entry **T-42-12** both assert *"Helpers are called once
per container per tick, never per widget"*. Its Task 2 then mandates `ApplyCachedIcon` **by name**,
with a call-count assertion, and that helper is called once per rendered **widget** per tick
(`Display.lua:945`, `:1319`, `:1643` — three call sites, all inside per-widget code).

The helper was built as Task 2 specifies and is correct: it replaces an existing inline block at the
same point, so it adds no per-tick work. **What is false is the constraint's wording, not the code.**
Recorded here so a future reader auditing against T-42-12 does not read `ApplyCachedIcon` as a
violation and "fix" it by inlining the block back into three places.

The same distinction applies to `ClearCooldownStamps` (H9), which is also per-widget but only ever
*entered* when a pooled widget is actually leaving a cooldown slot.

### §1b — Why the two Merge Mode deferrals must stay deferred

Both `ns:QueueMergeShownSlots` and `ns:QueueMergeMirror` defer through `C_Timer.After(0)` behind a
single-flight boolean. Neither is a scheduling nicety and neither may be made inline.

- **`QueueMergeShownSlots`** reads a state Blizzard is in the middle of computing. TBT's event frame
  and the CDM viewers register for the same events (`UNIT_AURA`, `PLAYER_TARGET_CHANGED`,
  `PLAYER_TOTEM_UPDATE`, `BAG_UPDATE_COOLDOWN`), and the order in which two frames receive one event
  is undefined. Reading the shown flags inline is a coin flip between the state before Blizzard's
  handler ran and the state after — a buff could appear in TBT a whole aura event late.
- **`QueueMergeMirror`** became load-bearing the moment the mirror started reading the viewers' item
  frames. TBT registers `CooldownViewerSettings.OnDataChanged` at addon load; the CDM viewers
  register it from their own `OnShow`, which happens later; and `CallbackRegistryMixin` fires
  callbacks **in registration order**. So TBT's callback runs *before* the viewers have rebuilt their
  item pools. An inline mirror would see the configuration as it was before the player's edit — the
  exact reported symptom "a buff I just added to the CDM never shows up in TBT".

`C_Timer.After(0)` puts both reads after every synchronous handler for the event, whatever order
anything registered in. The single-flight flag additionally **coalesces a `UNIT_AURA` burst into one
refresh per frame**, which makes the guard a performance win as well as a correctness one. Removing
either the deferral or the guard is a regression in both directions at once.

### §1c — The one hot-path cost this phase did not remove

`ns:GetActiveTimers` runs once per tick, before the container loop, and allocates:

1. `local result = {}` — one table,
2. `local sorted = {}` — a second table,
3. `table.sort(sorted, function(a, b) return a.expiresAt < b.expiresAt end)` — **one closure**, built
   fresh on every call.

At 20 Hz that is 60 allocations a second in combat, for a list whose contents usually did not change.
The contrast with `Display.lua:114-119` is sharp and worth naming: `ByLayoutOrder` was hoisted to
module level precisely *"so neither render function allocates a closure per tick"*, and this call
site does the very thing that hoist exists to prevent.

**It is still justified here, and the reason is the fence, not the cost.** The function predates
Phase 31 by a wide margin, it is not one of the two render functions D1 explicitly opened, and
`PROJECT.md`'s no-refactor decision covers it. Changing it would also be unverifiable: this phase
runs before Phase 43, and `ns:GetActiveTimers` feeds every timer TBT draws.

**Carried to:** `.planning/todos/2026-09-22-getactivetimers-allocates-two-tables-and-a-closure-per-tick.md`.

### §1d — Two smaller precision corrections to D6's wording

- `ApplyCooldownSlot`'s comment (and D6's summary of it) says `ApplyUserCooldown` costs *"two number
  comparisons and two stamp tests"*. The body has **three** stamp tests: `icon._lastStart ~= nil`
  (`Display.lua:906`) joined the original `_userCdState` and `_userCdGrey` pair when the
  preview-sweep bug was fixed, and the comment above the call was not updated with it. The claim the
  sentence is actually making — **no API call and no allocation** — is true either way. Not corrected
  here, because Task 1 of this plan changes no source file; it is a one-word fix for whoever next
  edits that block.
- D6 describes the centred pre-pass as walking `#slots` "a second time". It walks it a second time
  *only when `centered` is true*; `capacity = math.min(#slots, perRow)` on the line above is computed
  unconditionally but is a single `#`, not a walk.

---

## Section 2 — Duplication verdicts

One row per candidate from 42-CONTEXT.md's `<code_context>`. Each was re-checked against the shipped
code, not copied from the planning estimate — and three of the four estimates turned out to be
wrong about the *count*, which is itself the finding.

| Candidate | Verdict |
|-----------|---------|
| **Mutually-exclusive checkbox-pair idiom in `CDMTab.lua`** | **Unified** in plan 42-03 (`6303f7d`, `bd34973`), as `AddExclusiveCheck` + `WireExclusivePair`. **Correction to D4's estimate:** the idiom appears **twice**, not "at least three times". The third instance was the add dialog's Buff/Cooldown pair, which stopped existing when `ADD-01`/`ADD-02` were dropped as controls by user decision on 2026-09-22 — `REQUIREMENTS.md` records them struck through. The asymmetry (picking Cooldowns also forces Icons, disables Bars and greys its label) was deliberately **not** parameterised into the helper; it stayed in `ApplyCategory`, per D1's "extract what is character-identical, leave what differs at the call site". |
| **Pooled-widget reset blocks in `RenderIconContainer`** | **Unified** in plan 42-04 (`62a6de2`) as `ClearCooldownStamps`. **Correction to the estimate:** there were **two** copies, not three. The placeholder copy's extra `icon._mergedExpiry = nil` stayed **out** of the helper on purpose — the timer branch clears that stamp unconditionally a few lines further down, while the placeholder branch must clear it *inside* the guard because its `entry.isMerged` sub-branch owns it. Collapsing the difference would either wipe a live merged sweep stamp or leave a stale one. Proof the duplication collapsed rather than being wrapped: `_userCdGrey = nil` now appears exactly once in executable code. |
| **`MergeMode.lua`'s filter-building loop, "written twice (create path and re-filter path) inside `SyncEntryContainers`"** | **Does not exist.** Confirmed by reading `MergeMode.lua:845-918`. The loop that fills `includeSet` from `entry.spellID` and `entry.linkedSpellIDs` appears **once**, at `:856-866`, **above** the `for i = 1, #AURA_UNITS` loop. Both the re-filter path (`:877-880`) and the create path (`:905-911`) hand the *same* `includeSet` table to the engine. `grep -c 'includeSet\[' MergeMode.lua` → **2**, and both hits (`:858`, `:863`) are inside that single fill block. **This is a candidate that did not survive contact with the code, not work that was skipped** — there was nothing to unify, and no plan was written for it. |
| **`ns.EnsureContainerSettings` defaults vs the Edit Mode settings popup's control list** | **Real duplication, deliberately not unified.** See §2a — the disagreement is wider than the estimate said, which strengthens rather than weakens the verdict. |

### §2a — The container-settings triplication, in full

The same container settings are stated in **three** places with **different** fallbacks:

| Setting | `ns.EnsureContainerSettings` (`Core.lua:142`) seeds | `RefreshContainerSettings` (`Display.lua:157`) re-states on read | `AddSlider` (`EditModeFrames.lua:406`) falls back to `or minVal` |
|---------|------|------|------|
| `padding` | `5` | `src.padding or 5` | **`0`** |
| `scale` | `100` | `(src.scale or 100)`, then `math.max(0.1, …/100)` | **`50`** |
| `opacity` | `100` | `(src.opacity or 100) / 100` | **`50`** |
| `itemsPerRow` | `12` | `math.max(1, src.itemsPerRow or 12)` | **`1`** |
| `barWidth` | `100` | `src.barWidth or 100` | **`50`** |

All five disagree, not just `padding`. `AddSlider`'s fallback is structural — it is
`ns.db.containerSettings[containerKey][settingKey] or minVal`, where `minVal` is the slider's own
lower bound — so it can never agree with a seeded default unless the default happens to *be* the
minimum.

**Why it is left alone.** Because the three disagree, collapsing them **changes behaviour** for a
partially-populated settings table: a container whose `padding` key is missing renders at `5` today
and would show `0` on the slider, and unifying the three would have to pick one answer for both.
No such table can be produced or observed before Phase 43 — `ns.EnsureContainerSettings` is
idempotent and runs on every container at load, so in practice the keys are always present — which
makes this exactly the kind of untestable behaviour change 42-CONTEXT.md's "no behaviour changes"
constraint forbids in a phase that runs before its own verification pass.

**That is a reason to leave it and to say so in writing. It is not a reason to pretend it is not
duplication.** ROADMAP criterion 1 is therefore annotated **PARTIAL** rather than claimed.

### §2b — The pattern this phase's own plans exhibited: every failed assertion was the assertion's fault

Worth recording on its own, because four independent plans hit the same defect class and a fifth
reader will hit it again. **In Phase 42, not one plan-verification failure was ever a code defect.
Every one was a wrong grep pattern.**

| Plan | Assertion | Why it could not pass | What the code actually was |
|------|-----------|------------------------|----------------------------|
| 42-02 | `grep -c 'icon.cooldown:SetCooldown' Display.lua` = 1 | The unescaped `.` also matches `SetCooldownFromDurationObject` | **4** — one incidental match plus three genuine `icon.cooldown:SetCooldown(` call sites. Unchanged before and after. |
| 42-03 | `grep -c 'UICheckButtonTemplate' CDMTab.lua` < 4 | The literal appears **8** times file-wide, not 4: the four dialog checkboxes plus `rankCheck`, `mergeCheck` and two comment mentions | Four became one, so the count went **8 → 5**. `-lt 4` could only have passed by deleting code the plan forbids touching. |
| 42-04 | `grep -c 'ClearCooldownStamps(icon)' Display.lua` = 2 | The **definition line** `local function ClearCooldownStamps(icon)` contains the same substring | **3** = 1 definition + 2 call sites. |
| 42-05 | `grep -c 'MergedSlotsFor(def)'` = 2, and the same for `BuildActiveByKey(timers)` and `AppendMergedSlots(merged, mergedCount)` | Same definition-line error, three times — and the plan's *own prose* fixes those exact parameter names, so the definition is guaranteed to match | **3** each. Task 2's equivalent assertion (`ApplyCachedIcon(` = 4) *does* count the definition, so the plan was **internally inconsistent** rather than describing different code. |

In all four cases the executor verified the assertion's **intent** directly and changed nothing — no
helper was renamed, no parameter reshaped, no redundant mention added, to make a literal count pass.
That is the right response, and it is the one worth institutionalising: **contriving the source to
satisfy a check is strictly worse than recording that the check was wrong.**

Two rules for the next planner writing a count-gated check:

1. A `grep -c 'Name(args)'` for call sites **will match the definition**. Assert `n+1`, or anchor:
   `grep -cE '^\s+Name\(args\)$'`.
2. Escape the `.` in a method-call literal, or the count picks up every longer identifier that shares
   the prefix.

---

## Section 3 — Out-of-scope findings, carried not fixed

The scope fence held. What it stopped is recorded here so Phase 43 and the next milestone inherit it
rather than rediscovering it.

### 3.1 Nine unreferenced `ns.*` exports in `Providers.lua` — confirmed, left in place

Each has exactly **one writer and zero readers**, verified by counting `ns.<Name>` occurrences on
non-comment lines across `*.lua *.xml`:

| Export | Writers | Code references anywhere |
|--------|---------|--------------------------|
| `ns.SpellProviderBaseMixin` | 1 | 1 (the write itself) |
| `ns.TrinketProviderMixin` | 1 | 1 |
| `ns.PotProviderMixin` | 1 | 1 |
| `ns.LustProviderMixin` | 1 | 1 |
| `ns.UserSpellProviderMixin` | 1 | 1 |
| `ns.TRINKET_SPELLS` | 1 | 1 |
| `ns.POT_SPELLS` | 1 | 1 |
| `ns.TRINKET_ITEM_IDS` | 1 | 1 |
| `ns.POT_ITEM_IDS` | 1 | 1 |

All nine predate v0.4.0 (Phases 17-22), so `PROJECT.md`'s "No refactors during cleanup phases"
protects them. **Verdict: justified by the fence, not deleted.** The tenth member of that set,
`ns.RacialProviderMixin`, *was* deleted — by plan 42-01 (`7b3eb87`) — because Phase 41 added it,
which puts it inside the milestone fence. It now reports 0 writers and 0 references.

Re-run with:

```sh
for n in SpellProviderBaseMixin TrinketProviderMixin PotProviderMixin LustProviderMixin \
         UserSpellProviderMixin TRINKET_SPELLS POT_SPELLS TRINKET_ITEM_IDS POT_ITEM_IDS; do
  w=$(grep -c "^ns\.$n = " Providers.lua)
  r=$(cat *.lua *.xml | grep -vE '^[[:space:]]*--' | grep -c "ns[.:]$n\b")
  echo "$n writers=$w refs=$r"
done
```

### 3.2 Dead-function sweep — **zero** functions with no callers

Two sweeps, because a namespaced function and a file-local function are different shapes and need
different greps.

**Namespaced functions.** Every `function ns.Name` / `function ns:Name` definition across all seven
Lua files, checked for at least one non-comment occurrence of `Name` in `*.lua`, `*.xml` and the TOC
(so an XML-referenced handler cannot be mistaken for dead):

> **87 namespaced functions defined, 0 with no call site anywhere.**

**File-local functions.** Covered by the local sweep in 3.3 below: a `local function` with exactly
one non-comment occurrence in its file is defined and never called. Counts per file —
`BuffEngine.lua` 0, `CDMTab.lua` 24, `Core.lua` 4, `Display.lua` 31, `EditModeFrames.lua` 19,
`MergeMode.lua` 23, `Providers.lua` 9 (**110 local functions**) — and **none** was flagged.

**Verdict: criterion 3's dead-function clause rests on evidence, not on the absence of a check.**

### 3.3 Unused local **variables** — swept separately, and the result is clean

ROADMAP criterion 3 names three categories — *"unused variables, dead functions and stale
comments"* — and `CLAUDE.md`'s GSD Workflow repeats *"unused variables and definitions"*. A
dead-function sweep does not answer the variable half: a `local x = …` that is declared and never
read is a different shape and a different grep. There is no Lua linter in this repo, so the sweep
was built explicitly: extract every `local` declaration (including every name in a multi-assignment
`local a, b, c = …`), then count non-comment occurrences of that name in the same file. **A count of
1 means declared and never used.**

| File | `local` declarations swept | Flagged (occurrences ≤ 1) |
|------|---------------------------:|--------------------------:|
| `BuffEngine.lua` | 31 | **1** |
| `CDMTab.lua` | 241 | 0 |
| `Core.lua` | 64 | 0 |
| `Display.lua` | 168 | 0 |
| `EditModeFrames.lua` | 92 | 0 |
| `MergeMode.lua` | 137 | 0 |
| `Providers.lua` | 112 | 0 |
| **Total** | **845** | **1** |

(`_` is excluded as the conventional throwaway. The sweep is a **superset** of criterion 3's "since
Phase 31" fence — it covers the whole file set at every age — which is what makes a clean result
meaningful.)

**The one flag: `CURRENT_SCHEMA_VERSION`, `BuffEngine.lua:82.**

```lua
local CURRENT_SCHEMA_VERSION = 5
local ver = ns.db.schemaVersion or 0
```

It is declared and never read. Each migration block writes its own literal (`ns.db.schemaVersion = 1`
… ` = 5`), so the constant documents the current schema version rather than driving anything.

**Verdict: justified by the fence — out of scope, carried not fixed.** Two independent reasons:

1. **It predates the fence.** `git log -S'local CURRENT_SCHEMA_VERSION' -- BuffEngine.lua` puts its
   introduction in `d086429` (*v0.2.0 Config & Edit Mode Rework*), long before Phase 31. Phase 36
   only changed its value from `4` to `5`. `PROJECT.md`'s no-refactor decision covers it.
2. **Deleting it would manufacture a comment liar.** `Core.lua:98` reads *"…no schema bump, which is
   why `CURRENT_SCHEMA_VERSION` does not move for this change"*. Removing the local leaves a comment
   naming an identifier that does not exist — precisely the D4 defect class plan 42-02 spent a whole
   plan removing. A correct fix is to make the migration blocks *use* the constant
   (`ns.db.schemaVersion = CURRENT_SCHEMA_VERSION` at the final block), not to delete it, and that is
   a behaviour-adjacent edit to the database migration path with no way to test it before Phase 43.

**Because the only flag in an 845-declaration superset predates Phase 31, the set of unused locals
added *since* Phase 31 is empty.** That is criterion 3's variable clause, closed with evidence.

**Carried to:** `.planning/todos/2026-09-22-current-schema-version-is-declared-and-never-read.md`.

### 3.4 `ns:GetActiveTimers` allocates two tables and a closure per tick

Full argument in §1c. Recorded here too because it is the single most valuable thing on this list
for a future performance phase, and because the fence — not the cost — is the only reason it
survived Phase 42.

### 3.5 The `"spells"` category key still means "Cooldowns" in the UI

`CDMTab.lua:1757` states the rule in the code itself: *"Only the LABEL changes — the category key
stays `"spells"` throughout the code"*. The tab reads **TBT Cooldowns** (`CDMTab.lua:1760`) and the
container list renders `record.category == "spells"` as **Cooldowns** (`:1441`), while
`ns.db.userContainers` and `ns.CONTAINERS` persist and compare the literal `"spells"`
(`Core.lua:69`, `:82`, `:309`).

Renaming it is explicitly deferred (42-CONTEXT.md Deferred Ideas): the key is **persisted**, so it
would need a schema migration to buy nothing but a matching word. **Verdict: justified, deferred by
decision.** Noted here so the mismatch is not read as an oversight by whoever next opens
`CDMTab.lua`.

### 3.6 ROADMAP Block C's checklist still lists the phases in the pre-swap order

`.planning/ROADMAP.md:36-37` still reads *"Phase 42: Forever End-to-End Verification Pass"* and
*"Phase 43: Cleanup"*, while the detailed sections at `:296` and `:313` carry the swapped order
agreed on 2026-09-22 (Phase 42 = Cleanup, Phase 43 = Forever pass). Both bullets are unticked, so
there is no checkbox-crosstalk hazard today — but a reader skimming Block C gets the wrong phase
numbers.

**Verdict: carried, not fixed.** Task 2 of this plan is scoped to appending a PARTIAL annotation to
the Phase 42 success criteria and is explicitly forbidden from rewording anything; correcting the
Block C bullets is a planning-document edit that belongs to the user, who owns the roadmap's
narrative. **Surfaced in the plan summary for a decision.**

### 3.7 Already closed elsewhere — not outstanding

- **The abutting comment blocks in `Display.lua`.** Flagged by 42-02 and correctly declined by
  42-02, 42-04 and 42-05 in turn, each because a blank line is not a comment line and would have
  broken that plan's own diff guarantee. **Fixed in `a28610e`**, outside every plan's diff budget,
  which is what kept all three revertible on their own. Not outstanding; do not re-report it.
- **The `_placeholderProc` hazard was real, and the proof is on file.** 42-04's `.proc` reader
  enumeration found `Providers.lua:848-858` doing `proc.stacks = proc.stacks - 1` on the **live**
  racial timer that `Display.lua:1221` hands straight to `bar.proc`. Reusing `bar.proc` as the
  scratch buffer — the obvious way to fix D2 without a new field — would have wiped a table
  `RacialProviderMixin` is still mutating, i.e. destroyed a running Eureka! stack count. That is the
  concrete justification for the separate `_placeholderProc` field, and it is recorded here rather
  than only in a plan summary because the temptation to "save a field" will recur.

---

## Section 4 — Decisions and criteria closed without a code change

Two of this phase's obligations were already satisfied and would otherwise have left no written
trace. A phase whose record accounts for five of six decisions looks like one that missed the sixth.

### 4.1 D3 — delete `.luarc.json` and `foo.md` — **satisfied**

Both were removed when the phase context was committed. Evidence, not assumption:

```sh
$ git ls-files | grep -iE 'luarc|foo\.md'    # no output, exit 1
$ ls -a | grep -iE 'luarc|foo\.md'           # no output, exit 1
```

Neither is tracked and neither is present in the working tree.

- **`.luarc.json`** was an editor-only Lua Language Server config carrying the machine-specific
  absolute path `C:/Users/jonat/Repositories/vscode-wow-api`. It affected exactly one machine's
  editor and nothing the addon ships.
- **`foo.md`** was a draft addon announcement post whose content is already published on CurseForge,
  Wago and GitHub. Phase 45's DOC-03 writes store copy from the shipped README, not from this draft.

### 4.2 Criterion 4 — "read end to end" — the artifact

The release tooling was read during planning, which is why 42-01 was told not to re-read it. A read
that leaves no record is indistinguishable from one that did not happen, so it is restated here.

| File | What was confirmed correct |
|------|----------------------------|
| `scripts/install.bat` | A five-line wrapper and nothing else: `powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*`, forwarding the exit code. It stays the documented, argument-free entry point; the logic lives in the `.ps1` because batch cannot derive a file set from the TOC without becoming unreadable. |
| `scripts/install.ps1` | Derives the file set **from the TOC** (INST-09) rather than duplicating it; follows XML `file=` references so `CDMTab.xml → CDMTab.lua` is picked up; resolves the extensionless `## IconTexture:` name against `.blp`/`.tga`; **errors out** if the TOC names a file that does not exist; substitutes `git describe`-derived `…-dev` into the **deployed** TOC only, leaving the repo's `@project-version@` keyword intact for the packager (INST-05/06); and prunes files the repo no longer ships (INST-07/08) — safe because SavedVariables live under `WTF\`, never under `Interface\AddOns\`, so pruning cannot touch player data. Exits 1 with a `TBT_WOW_ROOT` hint when no client folder is found. |
| `scripts/release.bat` | Carries the **REL-01 branch guard**: it tags `HEAD` and then pushes `origin main`, so running it from any other branch tags the wrong commit while still pushing main. It refuses unless `HEAD` is `main`, with a deliberate `TBT_ALLOW_BRANCH=1` override that prints a warning. Both `git tag` and `git push` are error-checked. |
| `.github/workflows/release.yml` | Triggers on **any** tag (`tags: "**"`), checks out with `fetch-depth: 0`, extracts the **first `##` section** of `CHANGELOG.md` into `RELEASE_NOTES.md` with a one-line `awk`, then runs `BigWigsMods/packager@v2`. `CF_API_KEY` and `WAGO_API_TOKEN` are still commented out, so it publishes to **GitHub only** until keys are added. `permissions: contents: write` is the minimum the release upload needs. |

**The one defect that read found is fixed by 42-01 (`295c601`):** `.pkgmeta`'s `ignore:` list omitted
`.planning`, so every release zip shipped 334 tracked planning files — roadmaps, requirements, phase
plans, contexts and verification reports — straight into players' AddOns folders. `.github` and
`.gitattributes` were added in the same commit. The fix cannot be confirmed locally, because
BigWigs Packager only runs in CI against a real tag; confirmation belongs to the first release and
is already tracked in `STATE.md`.

---

## Summary of verdicts

| Category | Count | Breakdown |
|----------|------:|-----------|
| Hot-path findings | 14 | 1 **removed** (H10, `c2b89b2`); 13 **justified**, of which 1 (H14) is justified by the scope fence and carried to a todo |
| Duplication candidates | 4 | 2 **unified** (42-03, 42-04); 1 **does not exist**; 1 **real, deliberately not unified** → ROADMAP criterion 1 marked **PARTIAL** |
| Out-of-scope findings | 7 | All **recorded**, none fixed; 2 carried to todo files, 1 surfaced for a user decision |
| Sweeps with evidence | 3 | 87 namespaced functions → 0 dead; 110 local functions → 0 dead; 845 local declarations → 1 flag, and that one predates Phase 31 |
| Criteria closed without a code change | 2 | D3 (both files already gone, verified); criterion 4's "read end to end" (four files, one line each) |

**No source file was modified by the task that produced this document.**
