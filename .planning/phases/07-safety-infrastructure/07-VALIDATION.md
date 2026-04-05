---
phase: 7
slug: safety-infrastructure
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-04
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual in-game verification (WoW addon — no automated test framework) |
| **Config file** | none |
| **Quick run command** | `./scripts/install.bat` then `/tbt` in-game |
| **Full suite command** | `stylua --check *.lua` |
| **Estimated runtime** | ~5 seconds (stylua), manual testing varies |

---

## Sampling Rate

- **After every task commit:** Run `stylua --check *.lua`
- **After every plan wave:** Deploy via `./scripts/install.bat` and verify in-game
- **Before `/gsd:verify-work`:** Full stylua check + manual in-game verification
- **Max feedback latency:** 5 seconds (stylua)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | AURA-01 | code review | `grep -c "RegisterUnitEvent.*UNIT_AURA.*player" Core.lua` | N/A | pending |
| 07-01-02 | 01 | 1 | AURA-02 | code review | `grep -c "ShouldAurasBeSecret" BuffEngine.lua` | N/A | pending |
| 07-01-03 | 01 | 1 | AURA-03 | code review | `grep -c "PLAYER_REGEN_ENABLED\|ZONE_CHANGED_NEW_AREA" Core.lua` | N/A | pending |
| 07-01-04 | 01 | 1 | ZONE-02 | code review | `grep -c "isFullUpdate" BuffEngine.lua` | N/A | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No test framework setup needed — WoW addon testing is manual/in-game.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| UNIT_AURA fires only for player | AURA-01 | Requires live WoW client with party members | Group with another player, verify no handler calls for their aura changes via /tbt debug |
| Blocked flag activates in M+ | AURA-02 | Requires active M+ keystone | Enter M+ dungeon, verify /tbt debug shows "aura check blocked" |
| Blocked flag clears after combat | AURA-03 | Requires combat encounter outside M+ | Cast tracked buff, enter/leave combat, verify /tbt debug shows unblock |
| isFullUpdate suppression | ZONE-02 | Requires zone transition | Hearth or enter dungeon, verify timers not falsely cancelled |
| Preview mode survives aura events | N/A | Requires preview mode active during non-secret context | Start preview via CDM tab, verify timers persist |

---

## Validation Sign-Off

- [x] All tasks have automated verify or manual verification mapped
- [x] Sampling continuity: stylua runs after every commit
- [x] Wave 0 covers all MISSING references — N/A (no framework needed)
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
