# Forever platform findings — WoWUI Discord community FAQ

**Source:** WoWUI Discord community FAQ, relayed by the user 2026-09-19.
**Status:** intake and analysis only. Nothing here has been implemented.

This is **community-reported information, not first-party documentation.** Where a claim contradicts
something TBT verified in-game, both are recorded below rather than one overwriting the other. Where a
claim was checkable from this repo, it was checked, and the evidence is given.

---

## 1. Interface version `16001` — CONFIRMS what we ship

No change needed. `TerribleBuffTracker_Camelot.toc` declares `## Interface: 16001`, derived
independently as `1` + pad2(`60`) + pad2(`01`) from build `1.60.1`, and confirmed in-game on
`1.60.1.69913`. `check-toc.ps1` asserts the `16xxx` range rather than the exact value, so a routine beta
bump will not fail the guard.

## 2. "Forever is classed as mainline, this is intentional" — CONTRADICTS a recorded assumption ⚠

**This is the most significant item in the FAQ**, because it invalidates an assumption v0.3's
architecture was built on.

`research/STACK.md` line 121 recorded, at MEDIUM confidence:

> "Since TBT is deliberately using **two physical files** instead, each file is only ever discovered
> under its own flavor already."

The FAQ says the opposite: `_Mainline.toc` **also loads on Forever**, deliberately, and the community's
recommended fix is to move to a **single-TOC setup**. The MEDIUM confidence was the right call and the
assumption did not hold.

**What this does and does not break for TBT:**

| Context | State | Risk |
|---|---|---|
| Published zips | Each carries exactly one TOC — `.pkgmeta-camelot` ignores `_Mainline.toc` and vice versa. Verified by unzipping the real v0.3.0 assets | **None.** An end user never has both files |
| Deployed dev copies, right now | `_classic_beta_` holds only `_Camelot.toc`; `_retail_` holds only `_Mainline.toc` (checked on disk 2026-09-19) | **None currently** |
| Deployed dev copies after the next `install.bat` run | `install.bat` copies **both** TOCs to **every** client by design, so Forever would hold both again | **Live risk.** Two loadable TOCs in one folder on Forever |

**The honest gap in our own record:** `TOC-02` is marked verified because the addon loaded on Forever and
worked. That evidence does not distinguish *which* TOC the client read. If `_Mainline.toc` is also
loadable on Forever, the Forever pass may have been running `_Mainline.toc` at Interface 120100 the whole
time. It probably was not — a 120100 TOC would likely have been flagged out-of-date on a 16001 client,
and the deployed folder currently holds only `_Camelot.toc` — but "probably" is the accurate word, and
the run-sheet never captured a discriminating check. **A future Forever session should print
`C_AddOns.GetAddOnMetadata("TerribleBuffTracker", "Interface")` and settle it.**

**Also relevant:** `RETAIL-REGRESSION-PASS.md` records "it copies both TOCs to every client and the
client ignores the one whose flavour does not match" as a harmless-by-design note. That reasoning rests
on the assumption this FAQ contradicts, at least in the Forever direction.

→ Raised as backlog **Phase 999.3**.

## 3. SavedVariables writing is broken — CONFIRMS our known issue, with a nuance worth keeping

The FAQ: *"Writing to SavedVariables is broken, expect none of your ingame addon changes to stay between
UI reloads."*

This independently confirms what v0.3.0 shipped as a known issue, and confirms it is platform-wide
rather than a TBT defect. Good — the `CHANGELOG.md` / `README.md` wording stands.

**The nuance, recorded rather than smoothed over:** the FAQ says changes do not survive a **UI reload**.
TBT observed the opposite for `/reload` — Edit Mode container positions *did* survive it — and only lost
data across a full **logout/login**. The likely reconciliation is that the client holds the variables in
memory across `/reload` and never re-reads the file, so an in-memory value persists while the on-disk
value is stale. Either way the practical rule is identical and already recorded: **do not trust Forever
SavedVariables, and never use `/reload` to test persistence.**

## 4. `UnitName("player")` returns a full name, `UnitName("target")` does not — NO IMPACT

Checked: `grep -rn 'UnitName' *.lua` returns **zero matches**. TBT never calls it. Nothing to do.

Worth remembering only if TBT ever adds anything unit-name-driven, since the FAQ itself flags this as
unsettled ("we're not yet sure the final state this will end up in").

## 5. No realms on Forever; use "Rulesets" as a makeshift realm name — NO IMPACT TODAY

Checked: zero matches for `GetRealmName`, `GetNormalizedRealmName`, `realm`, or
`SavedVariablesPerCharacter` anywhere in the Lua or either TOC. TBT declares only
`## SavedVariables: TerribleBuffTrackerDB` — **account-wide, no per-character or per-realm scoping** — so
there is no realm name to substitute.

This becomes relevant the moment TBT gains per-character or per-profile settings. The AceDB reference in
the FAQ is the pattern to follow if that ever happens; TBT uses no external libraries today, which is a
locked constraint.

## 6. New TOC load-gating directives — a real architectural alternative ⚠

The FAQ documents capabilities beyond what `research/STACK.md` captured:

| Directive | Effect |
|---|---|
| `## AllowLoadGameType: standard` | Addon loads on retail only |
| `myfile.lua [AllowLoadGameType standard]` | **Per-file** conditional loading |
| `myfile.lua [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]` | Forever only — FAQ warns this form **will change** |
| `## Title: My Title [AllowLoadGameType standard]` | **Conditional metadata**, per game type |
| `_Standard.toc` | Recognised in patch 12.1.5 as retail-only |

Conditional metadata is the piece that matters: it is what would let **one** TOC carry both
`## Interface:` values and both `## Notes:` strings — exactly and only the two lines our two TOCs differ
on. A single-TOC TBT looks technically feasible.

**But it is not a free win, and it collides with a locked user decision.** One TOC means one package that
loads everywhere, which is the "single multi-flavour zip" option the user **explicitly rejected** in
favour of two flavour-pure zips so each download carries only its own client's files. A migration would
also retire `check-toc.ps1`, both `.pkgmeta-*` files and the CI matrix — machinery that works, is
guard-verified, and shipped. Trading it away needs a reason better than novelty.

Against that: it would delete the entire class of bug in item 2, and the community explicitly recommends
it.

**This is the user's decision, not a cleanup task.** Do not migrate unprompted.

→ Raised as backlog **Phase 999.3**.

---

## Follow-ups raised from this FAQ

- **Phase 999.3** — evaluate the single-TOC migration, and settle which TOC Forever actually loads.
- Nothing else here requires action. Items 1, 3, 4 and 5 are confirmations or no-ops.

## Unverified claims — do not treat as settled

Everything in this document is second-hand except where a check is shown inline. The FAQ itself flags two
of its own items as in flux (`UnitName` behaviour, and the `ExcludeLoadGameType` syntax). The FAQ also
points at a Discord channel for the latest known Forever bugs, which was not read.
