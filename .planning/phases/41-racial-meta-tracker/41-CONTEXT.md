# Phase 41: Racial Meta-Tracker (Eureka! only) - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning
**Mode:** Decisions taken with the user up front, before the autonomous run

<domain>
## Phase Boundary

A Racial tile in the Suggested section that ships **one** racial done properly — Eureka!, with
cast-driven stack consumption — and labels everything else honestly.

In scope: the Racial tile, Eureka!'s behaviour, and the "not yet supported" presentation.
Out of scope: the rest of the racial catalog. The user supplies each racial's spec individually, and
**the next minor milestone completes it for both retail and Forever**.
</domain>

<decisions>
## Implementation Decisions

### One tile, resolving to the player's racial
- A single **Racial** entry in Suggested, resolving to whatever racial the character actually has —
  exactly how the Lust tile already resolves per class.
- A gnome sees Eureka! and it works. Anyone else sees their own racial, greyed, with a tooltip saying it
  is not supported yet.
- Rejected: listing every racial across all races (floods the section with entries the character can
  never use), and hiding the tile unless supported (nobody else learns the feature exists).

### Eureka! behaviour — as prototyped 2026-09-20
- Spell ID `1259817`. Starts on cast with **3 stacks and a 15s duration**.
- Each qualifying cast drops the displayed stack count; the tracker **ends early** when the last stack is
  spent.
- **The nominal 15s timer always runs as a backstop.** This is a design requirement, not a fallback: the
  cast-driven model can never self-verify in combat, because the aura APIs hard-error for tainted
  callers under restriction.
- A qualifying cast is one where `C_Spell.IsSpellHarmful` is not false and `C_Spell.IsAutoAttackSpell`
  is not true.

### Accepted imprecision — do not re-open this as a bug
`C_Spell.IsSpellHarmful` means "can target an enemy", **not** "deals damage". Frost Nova consumed a
Eureka! stack the game did not. The user accepted this explicitly on 2026-09-20: over-consuming is
preferred to under-consuming, because the failure mode is a tracker ending early rather than showing a
buff the player no longer has. Polymorph and similar will behave the same way. This is recorded in
`REQUIREMENTS.md` under Out of Scope and in the phase's success criteria as accepted behaviour.

### Unsupported racials
- Shown as "not yet supported", explaining themselves in a tooltip in the CDM preview.
- **They start no timer when cast.** An unsupported racial must be inert, not silently half-working.

### The escape hatch
A user can build their own tracker for any unsupported racial through the normal add flow, and it
behaves like any other buff tracker. Nothing about the Racial tile blocks that.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LustProvider` is the closest analogue and the model to follow: a meta tile with a per-character
  resolution step (`CLASS_LUST_SPELL`, `GetHunterLustSpell`) and a catalog colocated in `Providers.lua`.
- `META-01`'s `HasResolvableCatalog` + the memoised `ns:IsSuggestedKeyResolvable` already decide whether
  a Suggested tile is worth rendering on this client — the "greyed / not supported" state is a variation
  on machinery that exists.
- `PAR-02`'s resolve-before-`SetSpellByID` guard: a numeric spellID is not proof the client knows the
  spell, and `SetSpellByID` on an unknown spell renders an empty tooltip frame.
- The cast-driven stack tracker was fully prototyped in `tools/TBTProbe/Probe.lua` (`/tbtp track`), with
  a validated log showing early expiry.

### Established Patterns
- Providers are stateless; `BuffEngine` owns all lifecycle. Providers self-govern secret/preview safety,
  and the dispatcher stays dumb and uniform.
- `proc.key` is the stable slot identity; `proc.spellID` is a derived numeric. Do not invert.
- `UNIT_SPELLCAST_SUCCEEDED` is not restricted for the player, and its spellID is always safe to use.

### Integration Points
- `SUGGESTED_BUFFS` and the Suggested section render path in `CDMTab.lua`.
- Stack display: no existing tracker shows a stack count, so this needs a widget addition. Phase 38 adds
  a charge count to cooldown icons in Blizzard's CDM style — reuse that text treatment rather than
  inventing a second one.
</code_context>

<specifics>
## Specific Ideas

"Eureka will works as we prototyped, all racials will be handled as 'special cases' and detailed by me
how to handle, I'll detail every single one of them for both retail and forever. Unsupported racials
will have a tooltip info on CDM preview and not work until implemented by us. Players can create custom
ones if they want and have it work as they see fit."

Narrowed later the same day: **Eureka! only this milestone**, the rest in the next minor one.
</specifics>

<deferred>
## Deferred Ideas

- The full racial catalog for retail and Forever — next minor milestone, spec supplied by the user per
  racial.
- Distinguishing genuinely damaging spells from merely harmful ones, which would remove the
  over-consumption. No readable API offers it; accepted as-is.
</deferred>
