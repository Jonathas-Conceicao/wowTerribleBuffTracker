---
phase: 11
slug: cleanup
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-04
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game verification + stylua |
| **Config file** | none |
| **Quick run command** | `stylua --check *.lua` |
| **Full suite command** | `stylua --check *.lua && ./scripts/install.bat` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `stylua --check` on modified files
- **After every plan wave:** Deploy via `./scripts/install.bat` and verify in-game
- **Max feedback latency:** 5 seconds

---

## Manual-Only Verifications

| Behavior | Why Manual | Test Instructions |
|----------|------------|-------------------|
| Preview preserves running buffs | Requires live WoW | Cast tracked buff, open CDM tab, verify timer still running, close CDM, verify timer restored |
| ResolveSuggestedSpellID renders correctly | Visual verification | Open CDM, verify lust icon shows class-aware spell in all sections |

---

## Validation Sign-Off

- [x] All tasks have automated verify or manual verification mapped
- [x] Sampling continuity: stylua runs after every commit
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
