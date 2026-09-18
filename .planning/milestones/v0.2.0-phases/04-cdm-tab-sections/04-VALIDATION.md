---
phase: 4
slug: cdm-tab-sections
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game testing (WoW addon — no automated framework) |
| **Config file** | none |
| **Quick run command** | `stylua *.lua && ./scripts/install.bat` then `/reload` in-game |
| **Full suite command** | All manual scenarios below |
| **Estimated runtime** | ~5 minutes |

---

## Manual-Only Verifications

| Behavior | Requirement | Test Instructions |
|----------|-------------|-------------------|
| 4 sections visible | TAB-03 | Open CDM, click TBT tab; verify Tracked Bars, Tracked Buffs, Not Displayed, Suggested sections all show |
| Sections collapsible | TAB-03 | Click each section header; verify content toggles |
| Icons in correct sections | TAB-03 | Verify each tracked buff icon appears in section matching its `section` value |
| Add button works | TAB-04 | Click Add in Suggested; enter Spell ID + Duration; verify dialog accepts and closes |
| New buff in Not Displayed | TAB-05 | After adding via dialog, verify new buff icon appears in Not Displayed section |
| Delete zone visible | TAB-06 | Verify delete drop zone visual is present in Not Displayed section |
| Right-click context menu | TAB-03 | Right-click buff icon; verify Move to Bars/Buffs/Remove options appear |
| Context menu moves buff | TAB-03 | Use context menu to move buff between sections; verify icon moves |
| No Lua errors | — | Verify no taint or other errors during all interactions |

---

## Validation Sign-Off

- [x] All tasks have manual verify instructions
- [x] No watch-mode flags
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
