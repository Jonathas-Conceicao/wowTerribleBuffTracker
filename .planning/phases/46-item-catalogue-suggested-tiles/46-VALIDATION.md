---
phase: 46
slug: item-catalogue-suggested-tiles
status: complete
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-24
---

# Phase 46 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

**Read `46-RESEARCH.md` § Validation Architecture first.** This file is the contract; that section
is the reasoning behind it, with the full in-game check list.

---

## Test Infrastructure

**There is no test runner, and none is planned.** This is a World of Warcraft addon: the only
runtime is the game client, and there is no headless harness that can load `Blizzard_CooldownViewer`,
populate a player's bags and render a frame. `.planning/ROADMAP.md` records this plainly — "No test
suite exists. No build manifest, no `luacheck`, no automated regression gate. Every claim in v0.4.0
rests on in-game observation."

Phase 46 does not change that. Filling the table below with a framework name would be a fabrication,
so it states the real position instead.

| Property | Value |
|----------|-------|
| **Framework** | none — no test runner exists for this project |
| **Config file** | none |
| **Quick run command** | `stylua .` (formatting gate, not a test) |
| **Full suite command** | none — the phase gate is the in-game check list below |
| **Estimated runtime** | static assertions: seconds. In-game gate: user-driven, two clients |

Verification splits in two, and neither half substitutes for the other:

- **Static assertions** — provable by a grep or a script before the client ever loads.
- **In-game human checks** — the only route to ITEM-01, ITEM-03, ITEM-08 and ITEM-10.

---

## Sampling Rate

- **After every task commit:** run `stylua .` from the repo root (bare, no flags — the repo-root
  `stylua.toml` pins `line_endings = "Windows"`). Then run the static assertions for whatever the
  task touched.
- **After every plan wave:** re-run the full static assertion table.
- **Before `/gsd-verify-work`:** the five in-game checks, on Forever first (every measured fact in
  999.6 came from there), then retail.
- **Max feedback latency:** static — immediate. In-game — deferred to the phase gate, because a
  client restart is required whenever `TerribleBuffTracker.toc` changes (`/reload` never re-reads
  the AddOns folder).

---

## Static Assertions

Each is checkable without WoW running. These are the executor's per-task gate.

| ID | Check | Method | Proves |
|----|-------|--------|--------|
| S1 | stylua clean | `stylua .` from repo root, then `git diff --stat` is empty | No formatting drift, and no invisible CRLF→LF reflow |
| S2 | Line endings held | `git ls-files --eol <touched files>` reports `w/crlf` for every `.lua` and `.md` | The documented blind spot — `git diff` cannot see this, only `ls-files --eol` can |
| S3 | No flavour check introduced | `test "$(git diff <base>..HEAD -- <changed files> \| grep '^+' \| grep -cE 'buildInterfaceVersion\|GetBuildInfo\|wow_classic\|classicVersion')" = "0"` | ITEM-10's one-code-path constraint, and the locked "no second flavour check" rule at `Core.lua:~520`. **Must be diff-scoped:** `Core.lua:565-576` holds Phase 37's sanctioned one-off, so a whole-file grep can never return zero |
| S4 | Secret guard ordering | Every new read of a `C_Item.*` / `C_Container.*` value has `issecretvalue(v)` evaluated **before** `type(v)` | The locked rule. `type()` reports `"number"` for a secret number and passes on its own |
| S5 | One TOC, both interfaces | `grep "^## Interface:" TerribleBuffTracker.toc` still lists `120100, 16001`; any new file appears exactly once in the file list | No flavour-forked file (CLAUDE.md) |
| S6 | Load order | If a new `.lua` is added, it is listed after `Core.lua` and before `CDMTab.xml` in the TOC | `ns.ITEM_KEY_PREFIX` / `ns:ItemKeyItemID` are available as upvalues when `CDMTab.lua` runs |
| S7 | `item:` keys stay inert | Source read: an `item:<itemID>` key matches neither `ns:CooldownKeySpellID` nor `ns.SUGGESTED_KEYS` membership, so `AddSuggestedTracker` (`CDMTab.lua:101`) returns without creating an entry | Phase 46 cannot create a malformed tracker. Drop behaviour is Phase 47's |
| S8 | Catalogue is itemID-keyed | Source read: the catalogue table is indexed by itemID; bag and slot appear only inside the discovery walk and are never stored | ITEM-01 |
| S9 | Exclusions are taxonomy-driven | Source read: the filter tests `classID` and `subClassID` from `C_Item.GetItemInfoInstant`, with no item-name matching anywhere | ITEM-08 — and name matching would break on a non-English client |
| S10 | Pooled tile state rewritten | Source read: every pooled tile writes or explicitly hides the count fontstring on every render pass | The documented pooling trap (`CDMTab.lua:786`, `:818`) |

---

## In-Game Human Checks (phase gate)

The only route to this phase's four requirements. Run on **Forever first**, then retail.

| ID | Requirement | Check | Pass condition |
|----|-------------|-------|----------------|
| G1 | ITEM-01 | Open the CDM carrying potions, a healthstone, a quest item, a recipe, a key, a trade good and a bandage. Split one potion stack across two bags | Catalogue lists each itemID **once**, regardless of how many slots hold it |
| G2 | ITEM-03 | Inspect each Suggested item tile | Shows the item's own icon (not the 134400 placeholder) and a count matching the bag count |
| G3 | ITEM-03 | Use one item down to a smaller stack, then trigger a re-scan with the CDM open | Count updates without reopening the CDM |
| G4 | ITEM-08 | Look for the excluded classes | Quest item, recipe, key, trade good and **bandage** are all absent |
| G5 | ITEM-08 | Look for the known `0/8` residue (glue, campfire kit, lute, crate) | Still **present**. This is accepted documented behaviour per 999.6 §1, not a bug — failing it would mean the filter over-reached |
| G6 | ITEM-10 | Repeat G1–G5 on Midnight retail, out of combat first, then in combat if reachable | Identical tiles out of combat. In combat, a secret value must **degrade** (no count shown) rather than error |
| G7 | — | Drag an item tile into a container | Documented no-op: ghost clears, no tile appears in the target, the item stays in Suggested. A tracker appearing here would be a defect |

G6's in-combat half is the one genuinely unmeasured area in this phase — both probe runs were
Forever-only, so retail's item-count/cooldown secrecy under combat restriction is unknown. S4's guard
is what makes shipping it safe regardless; G6 is where the real answer first gets observed, and
Phase 52's retail review pass is where it gets confirmed under raid and M+ conditions.

---

## Per-Task Verification Map

One row per task across Plans 01-04, filled from the real Plan 04 sweep results (2026-09-24).

| Task ID | Plan | Wave | Requirement | Static gate | In-game gate | Status |
|---------|------|------|-------------|-------------|--------------|--------|
| 46-01-T1 | 01 | 1 | ITEM-01, ITEM-08, ITEM-10 | S1, S2, S6, S7 | — | PASS |
| 46-01-T2 | 01 | 1 | ITEM-01, ITEM-08, ITEM-10 | S1, S2, S3, S4, S8, S9 | Answers G1, G4, G5 | PASS |
| 46-02-T1 | 02 | 2 | ITEM-01, ITEM-10 | S1, S2, S4 | Answers G2 (icon half) | PASS |
| 46-02-T2 | 02 | 2 | ITEM-01, ITEM-10 | S1, S2, S3 | Answers G3 | PASS |
| 46-02-T3 | 02 | 2 | ITEM-01, ITEM-10 | S1, S2 | Answers G3 (count updates without reopening CDM) | PASS |
| 46-03-T1 | 03 | 3 | ITEM-03, ITEM-10 | S1, S2, S10 | Answers G2 (count half) | PASS |
| 46-03-T2 | 03 | 3 | ITEM-03, ITEM-10 | S1, S2, S3, S7, S10 | Answers G1, G2, G4, G5, G7 | PASS |
| 46-04-T1 | 04 | 4 | ITEM-01, ITEM-03, ITEM-08, ITEM-10 | S1, S2, S3, S4, S5, S6, S7, S8, S9, S10 (full sweep) | — | PASS (S2 discrepancy noted below, out of this plan's file scope) |
| 46-04-T2 | 04 | 4 | ITEM-01, ITEM-03, ITEM-08, ITEM-10 | — (fills this table, deploys) | — | PASS |
| 46-04-T3 | 04 | 4 | ITEM-01, ITEM-03, ITEM-08, ITEM-10 | — | G1, G2, G3, G4, G5, G6, G7 | NOT STARTED — awaiting human verification |

**What "Status" means here:** this project has no test runner (see "Test Infrastructure" above), so
nothing in this table was ever going to mean "unit tests passed." A row's Status is PASS only when
the static assertions actually named in its Static gate column were run against the shipped source
with recorded evidence (46-04-SUMMARY.md carries that evidence) — a task whose only gate is an
in-game check cannot be marked PASS until a human has actually run it. `nyquist_compliant` and
`wave_0_complete` in this file's front matter stay `false` for the same reason: they will not
become `true` until 46-04-T3's G1..G7 checklist has been answered by the user on both clients, which
is the only route to ITEM-01, ITEM-03, ITEM-08 and ITEM-10 that exists for this project.

**46-04-T1 S2 discrepancy (not fixed by this plan):** `git ls-files --eol` on the three prior-wave
summaries — `46-01-SUMMARY.md`, `46-02-SUMMARY.md`, `46-03-SUMMARY.md` — reports `w/lf`, not
`w/crlf`, while every other `.md` in this phase directory (including this plan's own `46-04-PLAN.md`)
correctly reports `w/crlf`. `core.autocrlf` is `true` and `.md` files fall under the bare
`* text=auto` in `.gitattributes` (no `eol=crlf` pin exists for `.md`), so a fresh checkout of those
blobs would produce `w/crlf` — these three were written directly to disk (not checked out) and
committed as-is, so they never got the checkout-time LF->CRLF conversion. This is a live instance of
the exact blind spot T-46-12 and CLAUDE.md's `.gitattributes` note describe, on files this plan's
`files_modified` list does not include. Left unedited rather than "fixed" out of scope; flagged here
for the user to decide whether a follow-up touches them.

---

## Environment Availability

| Dependency | Required by | Available | Notes |
|------------|-------------|-----------|-------|
| stylua | S1, CLAUDE.md mandate | yes | `~/.cargo/bin/stylua`; run bare from repo root |
| git (`ls-files --eol`) | S2 | yes | The only tool that can see a CRLF reflow |
| Midnight retail client | G6 | yes | `World of Warcraft\_retail_` |
| WoW Forever beta client | G1–G5, G7 | yes | `World of Warcraft\_classic_beta_`, build 1.60.1 |
| `wow-ui-source` snapshot | research citations only | yes | read-only; a snapshot cannot prove absence |

No missing dependency. This phase introduces no new tool, library or service.

---

## Security Domain

ASVS applies only narrowly here: a single-player client addon with no network surface, no
authentication and no server-side trust boundary. It reads client-local data and writes to
`TerribleBuffTrackerDB`.

| Category | Applies | Control |
|----------|---------|---------|
| V5 Input Validation | Yes, narrow | `issecretvalue()`-then-`type()` on every Blizzard API read (S4). The real trust boundary is "is this value the shape I expect" |
| V2/V3/V4/V6 | No | No auth, no sessions, no multi-user boundary, no cryptography |

| Threat | STRIDE | Mitigation |
|--------|--------|------------|
| Secret-value type confusion — a secret number passes `type(v) == "number"` | Tampering (of TBT's own logic) | S4, on every new read |
| CDM frame taint | Tampering (taint propagation) | The scan hangs off the existing `StartPreview()` / `cdmWatcher` visibility poll, never a `HookScript` on a CDM frame. Established pattern; this phase adds no new CDM surface |
