---
phase: 5
slug: drag-and-drop
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 5 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game testing |
| **Quick run command** | `stylua *.lua && ./scripts/install.bat` then `/reload` |
| **Full suite command** | All manual scenarios below |

## Manual-Only Verifications

| Behavior | Requirement | Test Instructions |
|----------|-------------|-------------------|
| Drag icon between sections | DND-01 | Left-click hold a buff icon, drag to another section, release — verify section changes |
| Ghost follows cursor | DND-02 | During drag, verify ghost copy of icon follows cursor at 50% alpha |
| Section highlights on hover | DND-03 | During drag, move cursor over different sections — verify highlight appears/clears |
| Drop on delete zone removes buff | DND-01 | Drag buff to delete zone in Not Displayed — verify buff removed from DB |
| Drop outside cancels | DND-01 | Drag buff outside all sections, release — verify no change |
| Right-click still works | — | Right-click an icon — verify context menu still appears (coexists with drag) |
| No OnUpdate when idle | — | No drag active — verify no per-frame callback running |

**Approval:** pending
