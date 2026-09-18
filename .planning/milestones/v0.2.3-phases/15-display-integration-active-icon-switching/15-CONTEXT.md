# Phase 15: Display Integration + Active Icon Switching - Context

**Gathered:** 2026-04-13
**Status:** Ready for planning (verification-only — no implementation needed)

<domain>
## Phase Boundary

While a trinket or pot timer is active, the icon shows the specific cast spell's icon. When the timer expires, the icon reverts to the at-rest resolved icon (equipped trinket / bag pot). No nil-guards or Lua errors during active/expired transitions.

</domain>

<decisions>
## Implementation Decisions

### Phase 15 is satisfied by prior-phase work
- **D-01:** ICON-03 (cast spell icon while active) is already implemented by Phase 13. `OnSpellCastSucceeded` sets `timer.icon = ns:GetSpellIcon(spellID)` using the cast spellID. Display's `if timer then` branch (both bar and icon paths) reads `timer.icon` directly — so the active icon IS the cast spell's icon.
- **D-02:** ICON-04 (revert to at-rest on expiry) is already implemented by Phase 14. When `GetActiveTimers` cleans up an expired timer, the next `UpdateDisplay` tick hits the placeholder branch, which reads `ns.metaIcons[key]` via `GetSuggestedAtRestIcon` and renders the at-rest icon.
- **D-03:** Nil-guard behavior is already in place (`ns:GetSpellIcon` returns 134400 for nil/string, `GetAtRestMetaIcon` returns 134400 on empty cache, CDMTab Suggested nil-fallback exists).

### Verification confirmed in prior phase checkpoints
- User confirmed during Phase 13 checkpoint: trinket cast shows correct icon + label on bar (Nullsight for Vaelgor cast)
- User confirmed during Phase 14 checkpoint: at-rest icon renders correctly, reverts after timer expires naturally
- User confirmed bar progress animates correctly after Display.lua indexing fix (commit 1235344)

### Claude's Discretion
- No implementation work needed
- Verification approach: smoke-test a cast/expiry cycle in-game, confirm no new Lua errors, then mark ICON-03/ICON-04 complete

</decisions>

<canonical_refs>
## Canonical References

### Prior phase artifacts (all satisfy Phase 15 requirements)
- `.planning/phases/13-timer-functions-cast-detection/13-01-SUMMARY.md` — timer.icon set to cast spell icon
- `.planning/phases/14-icon-resolution-caching/14-01-SUMMARY.md` — GetAtRestMetaIcon + placeholder rendering
- `.planning/phases/14-icon-resolution-caching/14-02-SUMMARY.md` — Display.lua placeholder paths + active/expired transitions

### Code locations (verification only, no changes)
- `BuffEngine.lua` OnSpellCastSucceeded fan-out — timer.icon assignment for trinket/pot
- `Display.lua` bar render ~line 455 (if timer) vs 459 (elseif placeholder)
- `Display.lua` icon render ~line 585 (if timer) vs 647 (elseif placeholder)

</canonical_refs>

<code_context>
## Existing Code Insights

- Active → expired transition is purely driven by GetActiveTimers cleanup + UpdateDisplay polling at 0.05s interval. No explicit "on expire" callback needed.
- Preview timer (duration=0) auto-expires each tick, making Display render placeholder immediately — which is desired for at-rest icon display when CDM is open with no active cast.
- metaIconsDirty flag (Phase 14) handles live icon swaps; no interaction with active timer rendering.

</code_context>

<specifics>
## Specific Ideas

- User's quote: "I think this part is already fully covered"
- Plan should be a single verification task with an in-game smoke test checkpoint

</specifics>

<deferred>
## Deferred Ideas

- Async icon retry for uncached items (Future Requirement ICON-08)
- Data storage rework milestone (noted throughout)

</deferred>

---

*Phase: 15-display-integration-active-icon-switching*
*Context gathered: 2026-04-13*
