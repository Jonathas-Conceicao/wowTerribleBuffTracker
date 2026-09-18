---
phase: 1
slug: data-migration
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-28
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game testing (WoW addon — no automated framework) |
| **Config file** | none |
| **Quick run command** | `stylua BuffEngine.lua Display.lua && ./scripts/install.bat` then `/reload` in-game |
| **Full suite command** | All 4 manual scenarios below |
| **Estimated runtime** | ~2 minutes (deploy + load + verify) |

---

## Sampling Rate

- **After every task commit:** `stylua` + `install.bat`, then `/reload` in-game
- **After every plan wave:** All 4 manual test scenarios
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds (deploy + game reload)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | MIG-01 | manual | `/reload` + check config UI shows existing buffs | N/A | pending |
| 01-01-02 | 01 | 1 | MIG-02 | manual | Inspect SavedVariables for correct section values | N/A | pending |
| 01-01-03 | 01 | 1 | MIG-01 | manual | Run migration twice, verify section not overwritten | N/A | pending |
| 01-01-04 | 01 | 1 | D-05 | manual | Add new buff, verify section="hidden" | N/A | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No test framework to install for WoW addons.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Existing buffs preserved | MIG-01 | WoW client required | Create v0.1-style DB with tracked buffs, load addon, verify all entries in config UI |
| displayMode/enabled mapped to section | MIG-02 | WoW client required | Inspect SavedVariables or add print to migration, verify correct section values |
| Second upgrade no overwrite | MIG-01 | WoW client required | Run migration, change section in-game, /reload, verify section unchanged |
| New buffs default hidden | D-05 | WoW client required | Add new buff via config UI, inspect ns.db.trackedBuffs[id].section == "hidden" |

---

## Validation Sign-Off

- [x] All tasks have manual verify instructions
- [x] Sampling continuity: manual check after each task
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
