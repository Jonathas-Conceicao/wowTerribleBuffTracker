---
phase: 10
slug: lust-tracking
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-04
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game verification (WoW addon) |
| **Config file** | none |
| **Quick run command** | `stylua --check BuffEngine.lua CDMTab.lua` |
| **Full suite command** | `stylua --check *.lua` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `stylua --check` on modified files
- **After every plan wave:** Deploy via `./scripts/install.bat` and verify in-game
- **Before `/gsd:verify-work`:** Full stylua check + manual in-game verification
- **Max feedback latency:** 5 seconds

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sated debuff triggers lust timer | LUST-01 | Requires live WoW, lust cast | Have party member cast lust, verify timer auto-starts |
| Single CDM tab entry | LUST-02 | Visual verification | Open CDM tab, verify one "Lust / Heroism" icon |
| Class-aware icon | LUST-03 | Requires specific class character | Check icon on Shaman vs Mage vs other class |
| Tooltip gray text | LUST-04 | Visual verification | Hover lust icon, verify gray "Matches all..." line |
| Drums trigger | LUST-05 | Requires drums consumable | Use drums, verify timer starts |
| Drums debuff spellID | Research | Unconfirmed spellID | Use drums in-game, /tbt debug to check detected debuff ID |

---

## Validation Sign-Off

- [x] All tasks have automated verify or manual verification mapped
- [x] Sampling continuity: stylua runs after every commit
- [x] Wave 0 — N/A
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
