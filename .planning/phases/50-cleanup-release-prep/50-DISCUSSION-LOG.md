# Phase 50: Cleanup & Release Prep - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-25
**Phase:** 50-cleanup-release-prep
**Areas discussed:** F-3 scope (reversed mid-discussion), SC3 dispel-border dirty check, Release copy
**Areas offered but not selected:** Refactor boundary

---

## F-3 scope — does the aura-icon swap belong in this phase?

**Four questions were answered here, and then the whole area was reversed.** The answers are kept
because they are the scope F-3 now carries into backlog 999.8 — it does not need re-deciding when it
is picked up.

### Q1 — Where should F-3 land?

| Option | Description | Selected |
|--------|-------------|----------|
| Fold into Phase 50 | Three rows, data already present, one icon-resolution site; 51/52 review it alongside everything else | ✓ (later reversed) |
| Its own Phase 49.1 | Keeps Phase 50 process-only, matching 48.1's insertion; costs a plan cycle and reopens a closed phase's numbering | |
| Defer past v0.4.1 | Racials work correctly today; a cast icon on a divergent racial is cosmetic | **(effectively the outcome)** |

### Q2 — Which tiles get the aura's icon?

| Option | Description | Selected |
|--------|-------------|----------|
| Buff tile only | The buff tile shows the aura; the cooldown tile keeps the cast's icon because it counts the cast | ✓ |
| Both tiles | One racial reads as one thing everywhere; costs honesty on the cooldown tile | |
| Buff tile, only where the cast icon is a placeholder | Swap only on the 134400 question mark; needs an in-game check that this is even the failing case | |

### Q3 — How wide should "aura and skill id doesn't match" reach?

| Option | Description | Selected |
|--------|-------------|----------|
| Racials only | The racial table is the only place TBT holds an explicit auraID, so the only place the mismatch is knowable | ✓ |
| Racials plus user-added buff trackers | TBT has no aura ID for a user tracker and no way to learn one in combat — a new read surface | |
| Anywhere TBT knows both IDs | Adds trinkets and pots, but item-vs-spell is a different mismatch needing its own rule | |

### Q4 — Gate it, or waive it?

| Option | Description | Selected |
|--------|-------------|----------|
| Gate on Cannibalize only | One undead character; the other two rows are the same code with different numbers | |
| Gate all three | Needs an Alliance and a Horde Skyborne as well | |
| Ship it unobserved, like G8 | A third waiver on the release | |

**User's choice:** free text — *"I'll test all of them, do all, I test and confirm all of them."*

### Reversal

**User's choice:** *"Ok, huge change of plans, let's not do any of this icon swap from skill to aura
on racials, note it in the backlog for later, I wanna finish this milestone faster and this raises
too much questions and tests, let's speed things up."*

**Notes:** F-3 had been folded into Phase 50 on Claude's initiative earlier the same day, not at the
user's request. The reversal is correct on the phase's own terms — a user-visible behaviour change
does not belong in a process phase, and gating three rows needs an undead plus both Skyborne
characters. Captured as CONTEXT.md D-01 and ROADMAP backlog 999.8.

---

## SC3 — the dispel-border dirty check

Presented with the code read first: the out-of-combat path already dirty-checks and sets nothing once
settled; only the in-combat secret path re-issues, for the one or two entries carrying a border. The
argument offered for acting now was timing, not performance — Phases 51 and 52 are two full review
passes and verify anything that lands before them for free.

| Option | Description | Selected |
|--------|-------------|----------|
| Implement it, early in the phase | Key on entry identity (cooldownID), clear the stamp when a pooled widget changes slot — the `_cdKey` pattern Display.lua already uses; 51/52 verify it for free | ✓ |
| Drop it — keep the relay as-is | Fastest; removes SC3 and records why so it isn't rediscovered as an oversight | |
| Backlog it with F-3 | Keeps Phase 50 to duplication, hot paths, scripts and docs only | |

**Notes:** A first attempt at this question was rejected by the user in favour of clarifying F-3
first; it was re-asked unchanged after the reversal, alongside the release-copy question, to save a
turn at the user's request to speed up.

---

## Release copy

| Option | Description | Selected |
|--------|-------------|----------|
| Claude drafts all of it, user edits CHANGELOG | README and store copy written directly; CHANGELOG handed over as a proposed entry rather than appended | partially |
| Claude drafts everything including the CHANGELOG append | Fastest, but against CLAUDE.md's standing rule | |
| Claude drafts README and store copy only | User writes the CHANGELOG from scratch | |

**User's choice:** free text — *"no README changes, draft the CHANGELOG i'll edit it later."*

**Notes:** This narrows ROADMAP Success Criterion 5, which names README and the CurseForge/Wago copy
alongside the CHANGELOG. There is no separate store-copy file in the repo — the store copy is
packaged from README — so "no README changes" covers both. Captured as D-07 and D-08.

---

## Claude's Discretion

**Refactor boundary** was offered as a gray area and not selected, so the calls are Claude's, bounded
by the user's stated preference for speed and by the standing split between `CLAUDE.md`'s
"unify what the milestone introduced" and `PROJECT.md`'s "No refactors during cleanup phases":

- The three key parsers (`cd:`, `item:`, `racial:`) — two milestone-introduced, one protected.
- The three racial def lookups — all three milestone-introduced, squarely in scope.
- The icon/bar pandemic FX split — documented divergence, probably not duplication.
- REQUIREMENTS.md's stale traceability rows for RACE-07/08/10 — flagged to the user during
  discussion, no objection raised.
- The leftover executor worktree at `.claude/worktrees/agent-ad696cb1`.

Full reasoning in CONTEXT.md § "Claude's Discretion".

## Deferred Ideas

- **999.8** — the aura-icon swap for divergent racials, written to the ROADMAP backlog with its full
  scope intact.
- **G8 retest** — the opportunistic Skyborne retest noted during the F-3 discussion lost its free
  ride when F-3 was deferred. G8 stays waived.
- **`tools/TBTProbe/`** — 2,389 lines of probe scaffolding, no decision taken; predates this
  milestone and is therefore protected unless the user asks.
- **999.5** — cooldown icon grey through the GCD. `todo.match-phase 50` returned zero matches; not
  folded.
