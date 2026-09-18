---
phase: 8
slug: aura-scan-and-cancellation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-04
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game verification (WoW addon — no automated test framework) |
| **Config file** | none |
| **Quick run command** | `stylua --check BuffEngine.lua` |
| **Full suite command** | `stylua --check *.lua` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `stylua --check BuffEngine.lua`
- **After every plan wave:** Deploy via `./scripts/install.bat` and verify in-game
- **Before `/gsd:verify-work`:** Full stylua check + manual in-game verification
- **Max feedback latency:** 5 seconds (stylua)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | AURA-04 | code review | `grep -c "ScanActiveTimersForCancellation" BuffEngine.lua` | N/A | pending |
| 08-01-02 | 01 | 1 | AURA-04 | code review | `grep -c 'source = "cast"' BuffEngine.lua` | N/A | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No test framework setup needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cancelled buff timer disappears | AURA-04 | Requires live WoW client | Cast tracked buff, right-click to cancel, verify timer disappears |
| Early-falling buff removed | AURA-04 | Requires dispel or wipe scenario | Use trinket, trigger early removal, verify timer gone |
| Display refreshes once per scan | AURA-04 | Visual verification | Cancel multiple buffs simultaneously, verify no flicker |

---

## Validation Sign-Off

- [x] All tasks have automated verify or manual verification mapped
- [x] Sampling continuity: stylua runs after every commit
- [x] Wave 0 covers all MISSING references — N/A
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
