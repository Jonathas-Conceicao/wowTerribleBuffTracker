---
phase: 2
slug: edit-mode-containers
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game testing (WoW addon — no automated framework) |
| **Config file** | none |
| **Quick run command** | `stylua *.lua && ./scripts/install.bat` then `/reload` in-game |
| **Full suite command** | All 5 manual scenarios below |
| **Estimated runtime** | ~3 minutes (deploy + load + Edit Mode scenarios) |

---

## Sampling Rate

- **After every task commit:** `stylua` + `install.bat`, then `/reload` in-game
- **After every plan wave:** All 5 manual test scenarios
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | How to Verify | Status |
|---------|------|------|-------------|-----------|---------------|--------|
| 02-xx-01 | xx | 1 | EDM-01 | manual | Enter Edit Mode; verify drag handles on both containers; drag each | pending |
| 02-xx-02 | xx | 1 | EDM-02 | manual | Open Edit Mode; find TBT checkbox in sidebar; uncheck/recheck | pending |
| 02-xx-03 | xx | 1 | EDM-03 | manual | Delete DB, /reload; containers at default positions | pending |
| 02-xx-04 | xx | 1 | EDM-04 | manual | Move container, exit Edit Mode, /reload; same position | pending |
| 02-xx-05 | xx | 1 | EDM-05 | manual | Set TBT position, change CDM bar width; TBT does not move | pending |

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No test framework to install for WoW addons.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Two movable containers in Edit Mode | EDM-01 | WoW client required | Enter Edit Mode; verify drag handles; drag each container |
| Sidebar checkbox toggles both | EDM-02 | WoW client required | Find TBT checkbox; uncheck → both hide; recheck → both show |
| Fresh install defaults | EDM-03 | WoW client required | `/run TerribleBuffTrackerDB = nil`; `/reload`; check positions |
| Position persists across /reload | EDM-04 | WoW client required | Move container; exit Edit Mode; /reload; verify position |
| CDM layout refresh no move | EDM-05 | WoW client required | Set TBT position; change CDM settings; verify no move |

---

## Validation Sign-Off

- [x] All tasks have manual verify instructions
- [x] Sampling continuity: manual check after each task
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
