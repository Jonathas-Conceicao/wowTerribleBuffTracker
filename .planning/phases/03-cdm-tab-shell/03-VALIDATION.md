---
phase: 3
slug: cdm-tab-shell
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game testing (WoW addon — no automated framework) |
| **Config file** | none |
| **Quick run command** | `stylua *.lua && ./scripts/install.bat` then `/reload` in-game |
| **Full suite command** | All 5 manual scenarios below |
| **Estimated runtime** | ~3 minutes |

---

## Sampling Rate

- **After every task commit:** `stylua` + `install.bat`, then `/reload` in-game
- **After every plan wave:** All 5 manual test scenarios
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| TBT tab visible in CDM settings | TAB-01 | WoW client required | Open CDM settings; verify "TBT Buffs" lateral tab button appears alongside Spells/Auras tabs |
| TBT panel shows on tab click | TAB-02 | WoW client required | Click TBT tab; verify TBT content panel shows and CDM scroll frame hides |
| CDM tab restores CDM content | TAB-02 | WoW client required | Click Spells or Auras tab; verify CDM scroll frame shows and TBT panel hides |
| /tbt opens CDM + TBT tab | TAB-07 | WoW client required | Type /tbt; verify CDM settings opens with TBT tab selected |
| ConfigUI.lua removed | TAB-07 | Code review | grep for ToggleConfigUI in codebase; confirm ConfigUI.lua absent from TOC |

---

## Validation Sign-Off

- [x] All tasks have manual verify instructions
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
