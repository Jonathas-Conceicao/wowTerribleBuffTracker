// Dry-run TBT's ADDON_LOADED sequence against a real SavedVariables file, without a game client.
//
//   node scripts/migrate-dryrun.js <path-to-TerribleBuffTracker.lua> [...]
//   node scripts/migrate-dryrun.js --selftest
//
// Why this exists: the v4, v5 and v6 migrations had never executed against a genuine v0.3.0
// database. Forever writes its own file but it is already v6, so it exercises nothing. This
// reproduces the ordering Core.lua and BuffEngine.lua actually use -- the ADDON_LOADED defaults
// and ns.EnsureContainerSettings FIRST, then the migration blocks, with `ver` read once before
// any of them -- and prints what each step does to the real data.
//
// Covers schema v1 through v12 (Phase 53, NAME-02; Phase 57.1, ADD-07; Phase 57.2, REM-04; Phase 57.5, RALT-02;
// Phase 67, MIG-03). v7 (ns:MigrateRacialKeys) drops the legacy "racial"/"racial2" slots: Phase 67
// removed racials, so it never reads the race. v8 (the canonical kind + `<kind>:<id>` re-key)
// classifies every legacy cooldown as userCd, because no racial catalogue exists to identify one
// against. v9 (Phase 57.1) drops the saved `detailed` mode flag, clearing the four Advanced keys
// (auraID, keepOnAuraLoss, visibility, endOnCast) only on records whose `detailed` was not true.
// v10 (Phase 57.2) turns every userBuff saved with visibility "absent" into a userReminder, and
// drops every other visibility value and the cooldown aura ID. v11 (Phase 57.5) moves every
// reminder's "Ends when you cast" list (endOnCast) into its "Also satisfied by" list
// (alternatives); buff and cooldown trackers keep endOnCast. v12 (Phase 67, MIG-03) drops racial
// trackers, identified by key shape only (metaSkill:<id>, metaSkillCd:<id>, racial, racial2).
//
// `--selftest` runs the migration mirror against embedded v0.4.1-shaped, pre-v7 and racial-bearing
// fixtures with hard assertions -- there is no Lua test runner and the only real runtime is the WoW
// client, so this is the closest thing to an automated test the migration has. It is written from
// the locked decisions in 53-CONTEXT.md and 67-CONTEXT.md, so it is the SPEC the Lua migration is
// reconciled against -- not a transcription of whatever the Lua ends up doing.
//
// It is a prediction, not a substitute for the in-game pass (plan 53-05). Keep the registry and
// the migration blocks below in step with Core.lua and BuffEngine.lua; if they drift, this lies
// confidently.
const fs = require('fs');
const path = require('path');

// --- canonical kind strings -------------------------------------------------------
// MUST stay byte-identical to Core.lua's ns.KIND / ns.META_KEY (plan 53-02) -- these are the
// spec this dry-run is reconciled against, not a transcription of whatever the Lua ends up doing.
const KIND = {
  USER_BUFF: 'userBuff',
  USER_CD: 'userCd',
  USER_REMINDER: 'userReminder',
  META_SKILL: 'metaSkill',
  META_REMINDER: 'metaReminder',
  META_ITEM: 'metaItem',
  USER_ITEM: 'userItem',
};
const META_KEY = {
  LUST: 'metaSkill:lust',
  TRINKET: 'metaItem:trinket',
  POT: 'metaItem:pot',
};
const SPELL_KINDS = new Set([KIND.USER_BUFF, KIND.USER_CD, KIND.META_SKILL]);
const KNOWN_KINDS = new Set([KIND.USER_BUFF, KIND.USER_CD, KIND.USER_REMINDER, KIND.META_SKILL, KIND.META_REMINDER, KIND.META_ITEM, KIND.USER_ITEM]);
// Mirrors Core.lua's ns.REMINDER_KINDS (Phase 57.5): the kinds schema v11 converts.
const REMINDER_KINDS = new Set([KIND.USER_REMINDER, KIND.META_REMINDER]);

// --- a parser for the Lua subset SavedVariables emits ----------------------------
// Handles what the WoW client actually writes (WR-03): `["key"] = v` and `[n] = v` entries,
// implicit-index array entries (`{ ... }, -- [1]`), `--` line comments (and `--[[ ]]` block
// comments), and backslash escapes inside quoted strings. Anything else throws with the offset.
function parse(src) {
  let i = src.indexOf('=') + 1;
  if (i === 0) throw new Error('no "=" found -- not a SavedVariables file');
  const fail = (what) => { throw new Error(`expected ${what} at ${i}: ${JSON.stringify(src.slice(i, i + 40))}`); };
  // Skips whitespace, list separators and comments.
  const ws = () => {
    for (;;) {
      while (i < src.length && /[\s,;]/.test(src[i])) i++;
      if (src[i] === '-' && src[i + 1] === '-') {
        const block = src.slice(i + 2).match(/^\[(=*)\[/);
        if (block) {
          const close = ']' + block[1] + ']';
          const end = src.indexOf(close, i);
          i = end === -1 ? src.length : end + close.length;
        } else {
          while (i < src.length && src[i] !== '\n') i++;
        }
        continue;
      }
      return;
    }
  };
  const ESCAPES = { n: '\n', t: '\t', r: '\r', a: '\x07', b: '\b', f: '\f', v: '\v', '\\': '\\', '"': '"', "'": "'", '\n': '\n' };
  function str() {
    const quote = src[i++];
    let out = '';
    while (i < src.length && src[i] !== quote) {
      if (src[i] === '\\') {
        const c = src[i + 1];
        const dec = src.slice(i + 1).match(/^\d{1,3}/);
        if (dec) { out += String.fromCharCode(Number(dec[0])); i += 1 + dec[0].length; continue; }
        out += c in ESCAPES ? ESCAPES[c] : c;
        i += 2;
        continue;
      }
      out += src[i++];
    }
    if (src[i] !== quote) fail('closing quote');
    i++;
    return out;
  }
  function value() {
    ws();
    if (src[i] === '{') return table();
    if (src[i] === '"' || src[i] === "'") return str();
    let j = i;
    while (j < src.length && /[^\s,;}\]]/.test(src[j])) j++;
    const lit = src.slice(i, j);
    if (lit === '') fail('a value');
    i = j;
    if (lit === 'true') return true;
    if (lit === 'false') return false;
    if (lit === 'nil') return null;
    const n = Number(lit);
    if (Number.isNaN(n)) { i -= lit.length; fail('a number, string, boolean or table'); }
    return n;
  }
  function table() {
    i++; // {
    // Map preserves key TYPE, which the v6 migration branches on.
    const m = new Map();
    let nextIndex = 1;
    for (;;) {
      ws();
      if (i >= src.length) fail('}');
      if (src[i] === '}') { i++; return m; }
      let key;
      if (src[i] === '[') {
        i++; ws();
        key = value();
        ws();
        if (src[i] !== ']') fail(']');
        i++; ws();
        if (src[i] !== '=') fail('=');
        i++;
      } else {
        const ident = src.slice(i).match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/);
        if (ident) {
          key = ident[1];
          i += ident[0].length;
        } else {
          // Implicit-index array entry, e.g. `{ ... }, -- [1]`.
          key = nextIndex++;
        }
      }
      m.set(key, value());
    }
  }
  return value();
}

// --- the registry, transcribed from Core.lua ns.CONTAINERS -----------------------
const CONTAINERS = [
  { key: 'buffs',     kind: 'icon', category: 'buffs' },
  { key: 'bars',      kind: 'bar',  category: 'buffs' },
  { key: 'essential', kind: 'icon', category: 'spells' },
  { key: 'utility',   kind: 'icon', category: 'spells' },
  { key: 'reminders', kind: 'icon', category: 'reminders' },
];
const BY_KEY = Object.fromEntries(CONTAINERS.map(d => [d.key, d]));
const GROWTH_CENTERED = 2;
const category = d => (d && d.category) || 'buffs';
// Phase 57.2 (plan 02's Core.lua change): every non-bar container outside the 'spells' category
// centres, so the reminders container centres like buffs. The v5 block below keeps its own
// historical `category(def) === 'buffs'` test.
const defaultGrowth = d => (d.kind !== 'bar' && category(d) !== 'spells') ? GROWTH_CENTERED : 0;

// --- schema v7: legacy racial slots dropped (mirrors ns:MigrateRacialKeys, BuffEngine.lua) ----
// Phase 67 removed racials, so the pre-v7 "racial"/"racial2" slots address nothing: they are dropped
// rather than re-keyed, and the race is never read. Gates on a LITERAL 7 (53-CONTEXT "Pin v7
// first" -- CURRENT_SCHEMA_VERSION cannot be reused here once v8 exists). Reads schemaVersion FRESH
// on every call, matching the live function.
function migrateV7(db, log) {
  const schemaVersion = db.get('schemaVersion') || 0;
  if (schemaVersion >= 7) return;

  const tb = db.get('trackedBuffs');
  for (const oldKey of ['racial', 'racial2']) {
    if (!tb.has(oldKey)) continue;
    tb.delete(oldKey);
    log.push(`v7: ${oldKey} dropped (legacy racial slot)`);
  }
  db.set('schemaVersion', 7);
}

// --- schema v8: canonical kind + `<kind>:<id>` re-key -----------------------------------------
// Runs only after v7 has completed (schemaVersion in [7, 8)). Every legacy cooldown (numeric key
// with trackerType 'cooldown', or "cd:<id>") becomes a user cooldown, EXCEPT one whose id is in the
// frozen LEGACY_RACIAL_CD list below: that is a v0.4.x racial cooldown tile, and it is dropped
// (MIG-03, Phase 67 review WR-01). Collects every key FIRST (into a plain array snapshot), then
// moves each entry table to its new key -- never rebuilds a record.
//
// Frozen: every spellID the v0.4.0-v0.5.1 racial catalogue offered as a racial cooldown tile. History,
// not a catalogue -- this list must never grow. Mirrors LEGACY_RACIAL_CD in ns:MigrateKindKeys.
const LEGACY_RACIAL_CD = new Set([
  20600, 1259718, 20572, 1299026, 20594, 20580, 1259799, 20577, 7744,
  20549, 20552, 1259817, 20589, 20554, 1260270, 1259416, 1259705, 1259686,
]);
function migrateV8(db, log) {
  const schemaVersion = db.get('schemaVersion') || 0;
  if (schemaVersion < 7 || schemaVersion >= 8) return;

  const tb = db.get('trackedBuffs');
  const keys = [...tb.keys()];

  for (const oldKey of keys) {
    const entry = tb.get(oldKey);
    let newKey = null, kind = null, id = null, dropRacial = false;

    if (typeof oldKey === 'number') {
      const trackerType = entry.get('trackerType');
      if (trackerType == null || trackerType === 'buff') {
        newKey = `${KIND.USER_BUFF}:${oldKey}`;
        kind = KIND.USER_BUFF;
        id = oldKey;
      } else if (trackerType === 'cooldown') {
        // Defensive only -- v6 should already have moved this to "cd:<id>". Classify exactly
        // like a cd:N key below in case one somehow reached v8 unrekeyed.
        if (LEGACY_RACIAL_CD.has(oldKey)) dropRacial = true;
        else { newKey = `${KIND.USER_CD}:${oldKey}`; kind = KIND.USER_CD; id = oldKey; }
      }
      // anything else (e.g. an already-numeric key with an unrecognised trackerType) is left
      // exactly as it is.
    } else if (typeof oldKey === 'string') {
      let m;
      if ((m = oldKey.match(/^cd:(\d+)$/))) {
        const n = Number(m[1]);
        if (LEGACY_RACIAL_CD.has(n)) dropRacial = true;
        else { newKey = `${KIND.USER_CD}:${n}`; kind = KIND.USER_CD; id = n; }
      } else if ((m = oldKey.match(/^item:(\d+)$/))) {
        const n = Number(m[1]);
        newKey = `${KIND.META_ITEM}:${n}`; kind = KIND.META_ITEM; id = n;
      } else if ((m = oldKey.match(/^racial:(\d+)$/))) {
        const n = Number(m[1]);
        newKey = `${KIND.META_SKILL}:${n}`; kind = KIND.META_SKILL; id = n;
      } else if (oldKey === 'lust') {
        newKey = META_KEY.LUST; kind = KIND.META_SKILL;
      } else if (oldKey === 'trinket') {
        newKey = META_KEY.TRINKET; kind = KIND.META_ITEM;
      } else if (oldKey === 'pot') {
        newKey = META_KEY.POT; kind = KIND.META_ITEM;
      } else if ((m = oldKey.match(/^([A-Za-z]+):/)) && KNOWN_KINDS.has(m[1])) {
        // Already canonical -- key unchanged, only trackerType is (re)stamped. No id, so no
        // spellID/itemID backfill below.
        newKey = oldKey; kind = m[1];
      }
      // anything else (an unrecognised string key) is left exactly as it is.
    }

    if (dropRacial) {
      tb.delete(oldKey);
      log.push(`v8: ${oldKey} dropped (legacy racial cooldown)`);
      continue;
    }
    if (newKey == null) continue;

    if (newKey !== oldKey) {
      if (tb.has(newKey)) {
        // T-49-08 precedent: drop rather than clobber. Never reached by a real v0.4.1 database,
        // since the mapping is injective.
        tb.delete(oldKey);
        log.push(`v8: ${oldKey} dropped (${newKey} already occupied)`);
        continue;
      }
      tb.delete(oldKey);
      entry.set('key', newKey);
      tb.set(newKey, entry);
      log.push(`v8: ${oldKey} -> ${newKey} (${kind})`);
    } else {
      entry.set('key', newKey);
    }

    entry.set('trackerType', kind);
    if (SPELL_KINDS.has(kind) && entry.get('spellID') == null && id != null) {
      entry.set('spellID', id);
    }
    if (kind === KIND.META_ITEM && entry.get('itemID') == null && id != null) {
      entry.set('itemID', id);
    }
  }

  db.set('schemaVersion', 8);
}

// --- schema v9: drop the saved `detailed` mode flag (Phase 57.1, ADD-07) ----------------------
// Mirrors ns:MigrateDropDetailedFlag, BuffEngine.lua. Runs only after v8 has completed
// (schemaVersion in [8, 9)) -- the four Advanced keys this block clears only ever lived on an
// already-canonical entry, so there is nothing here to classify the way v7/v8 do. For every
// entry whose `detailed` was not exactly true, the four Advanced keys (auraID, keepOnAuraLoss,
// visibility, endOnCast) are cleared -- they were switched off under the old mode flag, and
// clearing them keeps current behaviour now that the runtime gates key on the values themselves.
// `detailed` is deleted unconditionally afterwards, whether or not it was present, matching the
// Lua's unconditional `entry.detailed = nil`.
function migrateV9(db, log) {
  const schemaVersion = db.get('schemaVersion') || 0;
  if (schemaVersion < 8 || schemaVersion >= 9) return;

  const tb = db.get('trackedBuffs');
  const ADVANCED_FIELDS = ['auraID', 'keepOnAuraLoss', 'visibility', 'endOnCast'];
  for (const [key, entry] of tb) {
    if (!(entry instanceof Map)) continue;
    let cleared = 0;
    if (entry.get('detailed') !== true) {
      for (const field of ADVANCED_FIELDS) {
        if (entry.has(field)) {
          entry.delete(field);
          cleared++;
        }
      }
    }
    entry.delete('detailed');
    if (cleared) {
      log.push(`v9: ${key} drop detailed, clear ${cleared} Advanced keys`);
    }
  }

  db.set('schemaVersion', 9);
}

// --- schema v10: absent-visibility buffs become reminders (Phase 57.2, REM-04) ----------------
// Mirrors ns:MigrateBuffReminders, BuffEngine.lua. Runs only after v9 has completed
// (schemaVersion in [9, 10)). Migrants (a userBuff whose visibility is 'absent') are collected
// FIRST, then re-keyed, never while walking the map. Every other entry loses `visibility`, and a
// userCd also loses `auraID` (the cooldown aura ID fed only the visibility watch). A migrant is
// the SAME Map moved to `userReminder:<id>`: only visibility is dropped (duration,
// keepOnAuraLoss and endOnCast are kept, since a reminder is a buff tracker in its own category,
// user decision 2026-09-29), section becomes 'reminders' unless it is 'hidden'. When
// `userReminder:<id>` already exists the existing record wins and the migrant is dropped
// (57.2-CONTEXT).
function migrateV10(db, log) {
  const schemaVersion = db.get('schemaVersion') || 0;
  if (schemaVersion < 9 || schemaVersion >= 10) return;

  const tb = db.get('trackedBuffs');
  const migrants = [];
  for (const [key, entry] of tb) {
    if (!(entry instanceof Map)) continue;
    if (entry.get('trackerType') === KIND.USER_BUFF && entry.get('visibility') === 'absent') {
      migrants.push(key);
      continue;
    }
    if (entry.has('visibility')) {
      entry.delete('visibility');
      log.push(`v10: ${key} drop visibility`);
    }
    if (entry.get('trackerType') === KIND.USER_CD && entry.has('auraID')) {
      entry.delete('auraID');
      log.push(`v10: ${key} drop cooldown auraID`);
    }
  }

  for (const oldKey of migrants) {
    const entry = tb.get(oldKey);
    let id = entry.get('spellID');
    if (typeof id !== 'number') {
      const m = typeof oldKey === 'string' ? oldKey.match(/^userBuff:(\d+)$/) : null;
      id = m ? Number(m[1]) : null;
    }
    if (id == null) {
      entry.delete('visibility');
      log.push(`v10: ${oldKey} has no spell ID -- visibility dropped, stays a buff`);
      continue;
    }
    const newKey = `${KIND.USER_REMINDER}:${id}`;
    tb.delete(oldKey);
    if (tb.has(newKey)) {
      log.push(`v10: ${oldKey} dropped (${newKey} already exists)`);
      continue;
    }
    entry.delete('visibility');
    entry.set('trackerType', KIND.USER_REMINDER);
    entry.set('key', newKey);
    entry.set('spellID', id);
    if (entry.get('section') !== 'hidden') entry.set('section', 'reminders');
    tb.set(newKey, entry);
    log.push(`v10: ${oldKey} -> ${newKey} (${entry.get('section')})`);
  }

  db.set('schemaVersion', 10);
}

// --- schema v11: reminder cast rules become alternatives (Phase 57.5, RALT-02) ----------------
// Mirrors ns:MigrateReminderAlternatives, BuffEngine.lua. Runs only after v10 has completed
// (schemaVersion in [10, 11)). For reminders only (REMINDER_KINDS), "Ends when you cast" becomes
// "Also satisfied by" (RALT-01, the one deliberate divergence from "reminders are buffs", user
// decision 2026-09-29). For every reminder entry with an endOnCast:
// - a table's valid IDs (57.5 review IN-02: its ipairs sequence -- keys 1, 2, ... up to the first
//   missing one -- positive numbers only, first occurrence only) become `alternatives` as the SAME
//   table, reduced to exactly those IDs, when there is no alternatives list;
// - when there is one (only possible by hand-editing), each valid ID not already in it is appended
//   after its ipairs border (never over an existing key of a sparse list);
// - a table with no valid ID (empty, hash-only, junk) or a non-table value is dropped.
// endOnCast is then deleted. Buff and cooldown trackers keep endOnCast untouched.
//
// BuffEngine.lua's AppendAlternativeID filter, mirrored: appends id at count + 1 and returns the new
// count, or returns count for a non-positive, non-number or duplicate id.
function appendAlternativeID(list, count, id) {
  if (typeof id !== 'number' || !(id > 0)) return count;
  for (let j = 1; j <= count; j++) if (list.get(j) === id) return count;
  list.set(count + 1, id);
  return count + 1;
}

// The ipairs sequence of a parsed table: values at keys 1, 2, ... up to the first missing one
// (a parsed `nil` is null, which Lua would not store).
function ipairsValues(m) {
  const out = [];
  for (let i = 1; m.has(i) && m.get(i) !== null; i++) out.push(m.get(i));
  return out;
}

function migrateV11(db, log) {
  const schemaVersion = db.get('schemaVersion') || 0;
  if (schemaVersion < 10 || schemaVersion >= 11) return;

  const tb = db.get('trackedBuffs');
  for (const [key, entry] of tb) {
    if (!(entry instanceof Map)) continue;
    if (!REMINDER_KINDS.has(entry.get('trackerType')) || !entry.has('endOnCast')) continue;
    const rule = entry.get('endOnCast');
    entry.delete('endOnCast');
    if (!(rule instanceof Map)) {
      log.push(`v11: ${key} non-table endOnCast dropped`);
      continue;
    }
    const ids = ipairsValues(rule);
    const alternatives = entry.get('alternatives');
    if (!(alternatives instanceof Map)) {
      // The SAME table, reduced to exactly the valid IDs.
      rule.clear();
      let count = 0;
      for (const id of ids) count = appendAlternativeID(rule, count, id);
      if (count > 0) {
        entry.set('alternatives', rule);
        log.push(`v11: ${key} endOnCast -> alternatives`);
      } else {
        log.push(`v11: ${key} endOnCast with no valid ID dropped`);
      }
    } else {
      let count = ipairsValues(alternatives).length;
      const before = count;
      for (const id of ids) count = appendAlternativeID(alternatives, count, id);
      log.push(`v11: ${key} endOnCast merged into alternatives (+${count - before})`);
    }
  }

  db.set('schemaVersion', 11);
}

// --- schema v12: racial trackers dropped (Phase 67, MIG-03) ----------------------------------
// Mirrors ns:MigrateDropRacials, BuffEngine.lua; runs only when schemaVersion is in [11, 12).
// Racial trackers are identified by key shape, never by a catalogue: metaSkill:<digits> (racial
// buffs), metaSkillCd:<digits> (racial cooldowns) and the legacy racial/racial2 slots.
// metaSkill:lust has no numeric id and is kept. Keys are collected FIRST, then deleted. The
// patterns are frozen literals, not KIND, since the metaSkillCd kind is deleted from the Lua.
function migrateV12(db, log) {
  const schemaVersion = db.get('schemaVersion') || 0;
  if (schemaVersion < 11 || schemaVersion >= 12) return;

  const tb = db.get('trackedBuffs');
  const drop = [];
  for (const key of tb.keys()) {
    if (typeof key !== 'string') continue;
    if (/^metaSkill:\d+$/.test(key) || /^metaSkillCd:\d+$/.test(key) || key === 'racial' || key === 'racial2') {
      drop.push(key);
    }
  }
  for (const key of drop) {
    tb.delete(key);
    log.push(`v12: ${key} dropped (racial)`);
  }
  if (!drop.length) log.push('v12: no racial trackers');

  db.set('schemaVersion', 12);
}

// --- Core.lua defaults + ns:InitBuffEngine's migration chain, on an already-parsed db --------
// Split out of run() so --selftest can replay the exact same sequence a real login runs, without
// going through a file on disk. The one real entry point is ADDON_LOADED (v1..v12); the
// world-entry retry was removed in Phase 67 (v7 no longer needs a readable race), so every step now
// completes on ADDON_LOADED and a single migrate() call models the whole login.
function migrate(db, log) {
  const g = k => db.get(k);

  // --- Core.lua ADDON_LOADED defaults, in source order -------------------------
  if (g('dialogStyle') != null) { db.delete('dialogStyle'); log.push('clear dialogStyle (dev-only)'); }
  if (g('tbtVisible') == null)     { db.set('tbtVisible', true);        log.push('seed tbtVisible = true'); }
  if (g('mergeMode') == null)      { db.set('mergeMode', false);        log.push('seed mergeMode = false'); }
  if (!g('containerSettings'))     { db.set('containerSettings', new Map()); }
  if (!g('userContainers'))        { db.set('userContainers', new Map()); log.push('seed userContainers = {}'); }
  if (g('nextContainerId') == null){ db.set('nextContainerId', 1);      log.push('seed nextContainerId = 1'); }

  // EnsureContainerSettings runs BEFORE InitBuffEngine -- ordering matters for v5.
  const cset = g('containerSettings');
  for (const def of CONTAINERS) {
    let cs = cset.get(def.key);
    if (!cs) {
      cs = new Map(Object.entries({
        orientation: def.kind === 'bar' ? 1 : 0,
        growthDirection: defaultGrowth(def),
        scale: 100, padding: 5, opacity: 100, visibility: 0,
        hideWhenInactive: true, showTimer: true, showTooltips: true,
      }));
      if (def.kind === 'bar') { cs.set('barWidth', 100); cs.set('displayMode', 0); }
      else cs.set('itemsPerRow', 12);
      cset.set(def.key, cs);
      log.push(`seed containerSettings.${def.key} (new container, growthDirection=${cs.get('growthDirection')})`);
    } else {
      for (const [k, v] of [['hideWhenInactive', true], ['showTimer', true], ['showTooltips', true], ['opacity', 100]])
        if (cs.get(k) == null) { cs.set(k, v); log.push(`backfill ${def.key}.${k} = ${v}`); }
      if (def.kind === 'bar' && cs.get('displayMode') == null) { cs.set('displayMode', 0); log.push(`backfill ${def.key}.displayMode = 0`); }
      if (def.kind !== 'bar' && cs.get('itemsPerRow') == null) { cs.set('itemsPerRow', 12); log.push(`backfill ${def.key}.itemsPerRow = 12`); }
    }
  }

  // --- BuffEngine.lua migrations. `ver` is read ONCE, before any block runs. ----
  const ver = g('schemaVersion') || 0;

  // v1-v3 mirror BuffEngine.lua's first three blocks (WR-03), so a pre-v4 file is not predicted
  // to keep a hidden `lust` that v3 deletes. v1/v2 iterate trackedBuffs in Lua `pairs` order,
  // which is unspecified -- the layoutOrder values v2 backfills may differ in-game; the SET of
  // trackers and their sections will not.
  if (!g('trackedBuffs')) db.set('trackedBuffs', new Map());

  if (ver < 1) {
    for (const [key, e] of g('trackedBuffs')) {
      if (e.get('section') == null) {
        const section = e.get('enabled') === false ? 'hidden' : e.get('displayMode') === 'buff' ? 'buffs' : 'bars';
        e.set('section', section);
        log.push(`v1: ${key}.section = ${section}`);
      }
      e.delete('enabled');
      e.delete('displayMode');
    }
    db.set('schemaVersion', 1);
  }

  if (ver < 2) {
    let order = 1;
    for (const [key, e] of g('trackedBuffs')) {
      if (e.get('layoutOrder') == null) { e.set('layoutOrder', order); log.push(`v2: ${key}.layoutOrder = ${order} (pairs order in-game)`); order++; }
    }
    db.set('schemaVersion', 2);
  }

  if (ver < 3) {
    const lust = g('trackedBuffs').get('lust');
    if (lust && lust.get('section') === 'hidden') { g('trackedBuffs').delete('lust'); log.push('v3: hidden auto-seeded lust removed'); }
    db.set('schemaVersion', 3);
  }

  if (ver < 4) {
    const pos = g('editModePositions');
    if (pos) {
      if (pos.get('icons') && !pos.get('buffs')) { pos.set('buffs', pos.get('icons')); log.push('v4: editModePositions.icons -> .buffs (position preserved)'); }
      pos.delete('icons');
    } else log.push('v4: no editModePositions -- no-op');
    db.set('schemaVersion', 4);
  }

  if (ver < 5) {
    let n = 0;
    for (const [key, cs] of cset) {
      const def = BY_KEY[key];
      if (def && cs.get('growthDirection') === 0 && def.kind !== 'bar' && category(def) === 'buffs') {
        cs.set('growthDirection', GROWTH_CENTERED);
        log.push(`v5: containerSettings.${key}.growthDirection 0 -> 2 (Centered)  <-- REWRITES AN EXISTING SETTING`);
        n++;
      }
    }
    if (!n) log.push('v5: nothing rewritten');
    db.set('schemaVersion', 5);
  }

  if (ver < 6) {
    const tb = g('trackedBuffs');
    const rekey = [];
    for (const [key, e] of tb) if (typeof key === 'number' && e.get('trackerType') === 'cooldown') rekey.push(key);
    for (const key of rekey) { const e = tb.get(key); tb.delete(key); tb.set('cd:' + key, e); log.push(`v6: ${key} -> cd:${key}`); }
    if (!rekey.length) log.push('v6: no cooldown trackers to re-key -- no-op');
    db.set('schemaVersion', 6);
  }

  // Schema v7, then v8, then v9, then v10, then v11, then v12 -- the same order ns:InitBuffEngine
  // uses (plan 53-02, 57.1-01, 57.2-01, 57.5-01, 67-01). Each gates and no-ops internally exactly
  // like the live Lua does.
  migrateV7(db, log);
  migrateV8(db, log);
  migrateV9(db, log);
  migrateV10(db, log);
  migrateV11(db, log);
  migrateV12(db, log);
}

// Read-only: parses and migrates in memory, never writes the input file.
function run(filePath) {
  const db = parse(fs.readFileSync(filePath, 'utf8'));
  const log = [];

  log.push(`schemaVersion in  : ${db.get('schemaVersion')}`);
  migrate(db, log);
  log.push(`schemaVersion out : ${db.get('schemaVersion')}`);

  // --- what survived -----------------------------------------------------------
  const tb = db.get('trackedBuffs');
  const dropped = log
    .map(line => line.match(/^v(?:7|12): (\S+) dropped \((?:legacy racial slot|racial)\)$/))
    .filter(Boolean)
    .map(m => m[1]);
  log.push(`trackers dropped  : ${dropped.length} -> ${dropped.join(', ')}`);
  log.push(`trackers kept     : ${tb.size} -> ${[...tb.keys()].join(', ')}`);
  const pos = db.get('editModePositions');
  log.push(`positions kept    : ${pos ? [...pos.keys()].join(', ') : '(none)'}`);
  const cset = db.get('containerSettings');
  log.push(`growthDirection   : ${CONTAINERS.map(d => d.key + '=' + cset.get(d.key).get('growthDirection')).join('  ')}`);
  return log;
}

// --- --selftest: embedded fixtures and hard assertions ----------------------------------------
// SavedVariables syntax, so these go through the same parse() a real file does. Fixtures A-B match
// plan 53-01's <feature><behavior> block exactly; Fixture D is shaped like a client-written file.

// Fixture A: v0.4.1 shape, schemaVersion 7 (v7 already complete). Its racial rows are dropped: the racial
// cooldowns (cd:20572, cd:20554) by v8, the racial buff (racial:20572, via metaSkill:20572) by v12.
const FIXTURE_A = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 7,
	["tbtVisible"] = true,
	["mergeMode"] = false,
	["containerSettings"] = {},
	["userContainers"] = {},
	["nextContainerId"] = 1,
	["editModePositions"] = {},
	["trackedBuffs"] = {
		[1719] = { ["trackerType"] = "buff", ["spellID"] = 1719, ["section"] = "buffs", ["layoutOrder"] = 1, ["coverAllRanks"] = true, ["duration"] = 12, ["label"] = "Recklessness" },
		["cd:1719"] = { ["trackerType"] = "cooldown", ["spellID"] = 1719, ["section"] = "essential", ["layoutOrder"] = 2, ["duration"] = 90 },
		["lust"] = { ["key"] = "lust", ["section"] = "bars", ["layoutOrder"] = 3, ["duration"] = 40, ["label"] = "Lust" },
		["trinket"] = { ["section"] = "bars", ["layoutOrder"] = 4 },
		["pot"] = { ["section"] = "hidden", ["layoutOrder"] = 5 },
		["racial:20572"] = { ["key"] = "racial:20572", ["spellID"] = 20572, ["duration"] = 15, ["section"] = "buffs", ["layoutOrder"] = 6 },
		["cd:20572"] = { ["trackerType"] = "cooldown", ["spellID"] = 20572, ["duration"] = 120, ["section"] = "utility", ["layoutOrder"] = 7 },
		["cd:20554"] = { ["trackerType"] = "cooldown", ["spellID"] = 20554, ["section"] = "hidden", ["layoutOrder"] = 8 },
		["item:241308"] = { ["trackerType"] = "item", ["itemID"] = 241308, ["iconOverride"] = 4622276, ["duration"] = 0, ["section"] = "utility", ["layoutOrder"] = 9 },
		[6673] = { ["section"] = "bars", ["layoutOrder"] = 10 },
	},
}
`;

// Fixture B: pre-v7, schemaVersion 6, legacy two-slot racial layout.
const FIXTURE_B = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 6,
	["tbtVisible"] = true,
	["mergeMode"] = false,
	["containerSettings"] = {},
	["userContainers"] = {},
	["nextContainerId"] = 1,
	["editModePositions"] = {},
	["trackedBuffs"] = {
		["racial"] = { ["section"] = "buffs", ["layoutOrder"] = 1 },
		["racial2"] = { ["section"] = "bars", ["layoutOrder"] = 2 },
		[1719] = { ["trackerType"] = "buff", ["spellID"] = 1719, ["section"] = "buffs", ["layoutOrder"] = 3 },
	},
}
`;

// Fixture E: schemaVersion 8 (v8 already complete), canonical keys, for case H (schema v9).
const FIXTURE_E = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 8,
	["trackedBuffs"] = {
		["userBuff:1719"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:1719", ["spellID"] = 1719, ["detailed"] = true, ["auraID"] = 2825, ["keepOnAuraLoss"] = true, ["visibility"] = "absent", ["endOnCast"] = { 6673 }, ["label"] = "Recklessness", ["duration"] = 12, ["section"] = "buffs", ["layoutOrder"] = 1 },
		["userBuff:6673"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:6673", ["spellID"] = 6673, ["detailed"] = false, ["auraID"] = 123, ["visibility"] = "present", ["label"] = "Combustion", ["duration"] = 10, ["section"] = "buffs", ["layoutOrder"] = 2 },
		["userBuff:2825"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:2825", ["spellID"] = 2825, ["auraID"] = 999, ["endOnCast"] = { 1719 }, ["label"] = "Bloodlust", ["duration"] = 40, ["section"] = "bars", ["layoutOrder"] = 3 },
		["userCd:1719"] = { ["trackerType"] = "userCd", ["key"] = "userCd:1719", ["spellID"] = 1719, ["detailed"] = true, ["visibility"] = "present", ["auraID"] = 1719, ["label"] = "Recklessness", ["duration"] = 90, ["section"] = "essential", ["layoutOrder"] = 4 },
	},
}
`;

// Fixture F: schemaVersion 9 (v9 already complete), canonical keys, for case I (schema v10).
const FIXTURE_F = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 9,
	["containerSettings"] = {},
	["trackedBuffs"] = {
		["userBuff:1719"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:1719", ["spellID"] = 1719, ["auraID"] = 2825, ["coverAllRanks"] = true, ["duration"] = 12, ["keepOnAuraLoss"] = true, ["endOnCast"] = { 6673 }, ["visibility"] = "absent", ["label"] = "Recklessness", ["section"] = "buffs", ["layoutOrder"] = 1 },
		["userBuff:6673"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:6673", ["spellID"] = 6673, ["duration"] = 10, ["visibility"] = "absent", ["label"] = "Combustion", ["section"] = "hidden", ["layoutOrder"] = 2 },
		["userBuff:2825"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:2825", ["spellID"] = 2825, ["duration"] = 40, ["visibility"] = "present", ["label"] = "Bloodlust", ["section"] = "bars", ["layoutOrder"] = 3 },
		["userBuff:5555"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:5555", ["spellID"] = 5555, ["duration"] = 20, ["visibility"] = "absent", ["label"] = "Migrant", ["section"] = "buffs", ["layoutOrder"] = 4 },
		["userReminder:5555"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:5555", ["spellID"] = 5555, ["label"] = "Existing", ["section"] = "reminders", ["layoutOrder"] = 5 },
		["userCd:1719"] = { ["trackerType"] = "userCd", ["key"] = "userCd:1719", ["spellID"] = 1719, ["visibility"] = "present", ["auraID"] = 1719, ["endOnCast"] = { 100 }, ["label"] = "Recklessness", ["duration"] = 90, ["section"] = "essential", ["layoutOrder"] = 6 },
		["metaSkill:lust"] = { ["trackerType"] = "metaSkill", ["key"] = "metaSkill:lust", ["duration"] = 40, ["label"] = "Lust", ["section"] = "bars", ["layoutOrder"] = 7 },
	},
}
`;

// Fixture F2: schemaVersion 9, for case J (schema v10's fallback branches, Phase 57.2 review
// WR-04). userBuff:4321 has no spellID and userBuff:778 a non-numeric one: both take the key-parse
// fallback. userBuff:abc has no digits in its key either, so it takes the no-ID branch.
// userBuff:3333 sits in a user container, and userCd:2222 is a cooldown saved "absent".
const FIXTURE_F2 = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 9,
	["containerSettings"] = {},
	["userContainers"] = {
		{ ["key"] = "user1", ["title"] = "Mine", ["kind"] = "icon", ["category"] = "buffs", ["defaultX"] = 300, ["defaultY"] = -320 },
	},
	["nextContainerId"] = 2,
	["trackedBuffs"] = {
		["userBuff:4321"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:4321", ["duration"] = 8, ["visibility"] = "absent", ["label"] = "NoSpellID", ["section"] = "buffs", ["layoutOrder"] = 1 },
		["userBuff:778"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:778", ["spellID"] = "777", ["visibility"] = "absent", ["label"] = "StringSpellID", ["section"] = "buffs", ["layoutOrder"] = 2 },
		["userBuff:abc"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:abc", ["duration"] = 5, ["keepOnAuraLoss"] = true, ["visibility"] = "absent", ["label"] = "NoDigits", ["section"] = "buffs", ["layoutOrder"] = 3 },
		["userBuff:3333"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:3333", ["spellID"] = 3333, ["duration"] = 30, ["endOnCast"] = { 1 }, ["visibility"] = "absent", ["label"] = "InUserContainer", ["section"] = "user1", ["layoutOrder"] = 4 },
		["userCd:2222"] = { ["trackerType"] = "userCd", ["key"] = "userCd:2222", ["spellID"] = 2222, ["auraID"] = 2223, ["visibility"] = "absent", ["duration"] = 60, ["label"] = "CdGate", ["section"] = "essential", ["layoutOrder"] = 5 },
	},
}
`;

// Fixture G: schemaVersion 10 (v10 already complete), for case K (schema v11, Phase 57.5 RALT-02).
const FIXTURE_G = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 10,
	["containerSettings"] = {},
	["trackedBuffs"] = {
		["userReminder:1719"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:1719", ["spellID"] = 1719, ["endOnCast"] = { 6673, 2825 }, ["label"] = "Moved", ["section"] = "reminders", ["layoutOrder"] = 1 },
		["userReminder:3333"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:3333", ["spellID"] = 3333, ["endOnCast"] = { 10, 20 }, ["alternatives"] = { 20, 30 }, ["label"] = "Merged", ["section"] = "reminders", ["layoutOrder"] = 2 },
		["userReminder:4444"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:4444", ["spellID"] = 4444, ["endOnCast"] = {}, ["label"] = "EmptyRule", ["section"] = "reminders", ["layoutOrder"] = 3 },
		["userReminder:7777"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:7777", ["spellID"] = 7777, ["endOnCast"] = 5, ["label"] = "NonTableRule", ["section"] = "reminders", ["layoutOrder"] = 4 },
		["metaReminder:20217"] = { ["trackerType"] = "metaReminder", ["key"] = "metaReminder:20217", ["spellID"] = 20217, ["endOnCast"] = { 1 }, ["label"] = "Kings", ["section"] = "reminders", ["layoutOrder"] = 5 },
		["userReminder:5555"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:5555", ["spellID"] = 5555, ["label"] = "NoRule", ["section"] = "reminders", ["layoutOrder"] = 6 },
		["userBuff:2825"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:2825", ["spellID"] = 2825, ["endOnCast"] = { 1719 }, ["label"] = "Bloodlust", ["section"] = "bars", ["layoutOrder"] = 7 },
		["userCd:1719"] = { ["trackerType"] = "userCd", ["key"] = "userCd:1719", ["spellID"] = 1719, ["endOnCast"] = { 100 }, ["label"] = "Recklessness", ["section"] = "essential", ["layoutOrder"] = 8 },
	},
}
`;

// Fixture H: schemaVersion 10 with hand-edited, malformed reminder tables, for case K's malformed
// sub-case (57.5 review IN-02: the Lua and JS v11 must agree on these).
const FIXTURE_H = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 10,
	["containerSettings"] = {},
	["trackedBuffs"] = {
		["userReminder:1"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:1", ["spellID"] = 1, ["endOnCast"] = { ["x"] = 5 }, ["section"] = "reminders", ["layoutOrder"] = 1 },
		["userReminder:2"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:2", ["spellID"] = 2, ["endOnCast"] = { 0, "a", 5, 5, -2, 7, ["x"] = 9 }, ["section"] = "reminders", ["layoutOrder"] = 2 },
		["userReminder:3"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:3", ["spellID"] = 3, ["endOnCast"] = { [1] = 5, [3] = 9 }, ["section"] = "reminders", ["layoutOrder"] = 3 },
		["userReminder:4"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:4", ["spellID"] = 4, ["endOnCast"] = { 20, 0, 20, 10 }, ["alternatives"] = { [1] = 10, [3] = 30 }, ["section"] = "reminders", ["layoutOrder"] = 4 },
		["userReminder:5"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:5", ["spellID"] = 5, ["endOnCast"] = { 0, -1, "z" }, ["section"] = "reminders", ["layoutOrder"] = 5 },
	},
}
`;

function snapshotFields(entry) {
  const out = {};
  for (const [k, v] of entry) out[k] = v;
  return out;
}

// Asserts a single record survived the move: the SAME object as the one that sat at oldKey
// (moved, not rebuilt), the correct trackerType and entry.key, and every OTHER field byte-equal
// to its pre-migration value -- except a field named in opts.backfilled, which the caller asserts
// separately (only userBuff:6673's spellID in these fixtures).
function assertMoved(expect, tbAfter, snapshot, fieldsBefore, oldKey, newKey, kind, opts) {
  const after = tbAfter.get(newKey);
  expect(after !== undefined, `${newKey}: not found after migration`);
  if (after === undefined) return;
  expect(after === snapshot.get(oldKey), `${newKey}: expected the same object that sat at ${JSON.stringify(oldKey)} (moved, not rebuilt)`);
  expect(after.get('trackerType') === kind, `${newKey}: trackerType expected '${kind}', got '${after.get('trackerType')}'`);
  expect(after.get('key') === newKey, `${newKey}: entry.key expected '${newKey}', got '${after.get('key')}'`);

  const before = fieldsBefore.get(oldKey);
  const backfilled = opts && opts.backfilled;
  for (const k of Object.keys(before)) {
    if (k === 'key' || k === 'trackerType' || k === backfilled) continue;
    expect(after.get(k) === before[k], `${newKey}.${k}: expected ${JSON.stringify(before[k])}, got ${JSON.stringify(after.get(k))}`);
  }
  for (const k of after.keys()) {
    if (k === 'key' || k === 'trackerType' || k === backfilled) continue;
    if (!(k in before)) {
      expect(false, `${newKey}.${k}: unexpected new field (value ${JSON.stringify(after.get(k))})`);
    }
  }
}

// oldKey, newKey, kind, backfilled-field-or-null -- the seven trackers Fixture A keeps.
// racial:20572 is absent on purpose: v8 re-keys it to metaSkill:20572 and v12 then drops it. cd:20572
// and cd:20554 are absent too: they are legacy racial cooldowns, dropped by v8 (WR-01, MIG-03).
const FIXTURE_A_MOVES = [
  [1719, 'userBuff:1719', 'userBuff', null],
  ['cd:1719', 'userCd:1719', 'userCd', null],
  ['lust', 'metaSkill:lust', 'metaSkill', null],
  ['trinket', 'metaItem:trinket', 'metaItem', null],
  ['pot', 'metaItem:pot', 'metaItem', null],
  ['item:241308', 'metaItem:241308', 'metaItem', null],
  [6673, 'userBuff:6673', 'userBuff', 'spellID'],
];

function caseA(expect) {
  const db = parse(FIXTURE_A);
  const tb = db.get('trackedBuffs');
  const snapshot = new Map();
  const fieldsBefore = new Map();
  for (const [k, e] of tb) { snapshot.set(k, e); fieldsBefore.set(k, snapshotFields(e)); }

  migrate(db, []);

  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  expect(tbAfter.size === 7, `trackedBuffs.size expected 7, got ${tbAfter.size}`);
  for (const k of tbAfter.keys()) {
    expect(
      !(typeof k === 'string' && ((k.startsWith('metaSkill:') && k !== 'metaSkill:lust') || k.startsWith('metaSkillCd:'))),
      `${k}: a racial tracker survived v12`
    );
  }
  for (const k of ['userCd:20572', 'userCd:20554', 'cd:20572', 'cd:20554']) {
    expect(!tbAfter.has(k), `${k}: a legacy racial cooldown survived the upgrade`);
  }

  const expectedKeys = new Set(FIXTURE_A_MOVES.map(m => m[1]));
  const actualKeys = new Set(tbAfter.keys());
  expect(
    actualKeys.size === expectedKeys.size && [...expectedKeys].every(k => actualKeys.has(k)),
    `key set expected {${[...expectedKeys].join(', ')}}, got {${[...actualKeys].join(', ')}}`
  );

  for (const [oldKey, newKey, kind, backfilled] of FIXTURE_A_MOVES) {
    assertMoved(expect, tbAfter, snapshot, fieldsBefore, oldKey, newKey, kind, { backfilled });
  }

  const spellBackfill = tbAfter.get('userBuff:6673');
  expect(
    spellBackfill && spellBackfill.get('spellID') === 6673,
    `userBuff:6673: expected spellID backfilled to 6673, got ${spellBackfill && spellBackfill.get('spellID')}`
  );

  return { db, tbAfter };
}

function caseB(expect, prev) {
  if (!prev) { expect(false, 'case A produced no result to continue from'); return; }
  const { db, tbAfter } = prev;
  const keysBefore = new Set(tbAfter.keys());
  const objectsBefore = new Map([...tbAfter]);
  const fieldsBefore = new Map([...tbAfter].map(([k, v]) => [k, snapshotFields(v)]));
  const sizeBefore = tbAfter.size;
  const schemaBefore = db.get('schemaVersion');

  migrate(db, []);

  const tbNow = db.get('trackedBuffs');
  expect(db.get('schemaVersion') === schemaBefore, `schemaVersion changed on second pass: ${schemaBefore} -> ${db.get('schemaVersion')}`);
  expect(tbNow.size === sizeBefore, `trackedBuffs.size changed on second pass: ${sizeBefore} -> ${tbNow.size}`);
  expect(
    tbNow.size === keysBefore.size && [...keysBefore].every(k => tbNow.has(k)),
    'key set changed on second pass'
  );
  for (const [k, obj] of objectsBefore) {
    expect(tbNow.get(k) === obj, `${k}: object identity changed on second pass`);
    const before = fieldsBefore.get(k);
    const after = tbNow.get(k);
    for (const field of Object.keys(before)) {
      expect(after.get(field) === before[field], `${k}.${field}: changed on second pass (${JSON.stringify(before[field])} -> ${JSON.stringify(after.get(field))})`);
    }
  }
}

// Case C: the pre-v7 legacy "racial"/"racial2" slots are dropped WITHOUT reading the race, in one
// pass, and everything else completes the whole chain to v12.
function caseC(expect) {
  const db = parse(FIXTURE_B);
  const buff = db.get('trackedBuffs').get(1719);

  migrate(db, []);

  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  expect(tbAfter.size === 1 && tbAfter.has('userBuff:1719'), `key set expected {userBuff:1719}, got {${[...tbAfter.keys()].join(', ')}}`);
  const e = tbAfter.get('userBuff:1719');
  if (e) {
    expect(e === buff, 'userBuff:1719: expected the same object that sat at 1719');
    expect(e.get('layoutOrder') === 3, `userBuff:1719.layoutOrder expected 3, got ${e.get('layoutOrder')}`);
    expect(e.get('trackerType') === 'userBuff', `userBuff:1719.trackerType expected 'userBuff', got ${e.get('trackerType')}`);
  }
}

// Fixture R: schemaVersion 11 (v11 already complete), racial trackers of both kinds and a legacy key
// next to non-racial ones, for case D (schema v12, Phase 67 MIG-03). userCd:20572 is a USER cooldown of
// a racial's spell and must survive; metaSkill:lust has no numeric id and must survive.
const FIXTURE_R = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 11,
	["containerSettings"] = {},
	["userContainers"] = {
		{ ["key"] = "user1", ["title"] = "Mine", ["kind"] = "icon", ["category"] = "buffs", ["defaultX"] = 300, ["defaultY"] = -320 },
	},
	["nextContainerId"] = 2,
	["trackedBuffs"] = {
		["metaSkill:20572"] = { ["trackerType"] = "metaSkill", ["key"] = "metaSkill:20572", ["spellID"] = 20572, ["duration"] = 15, ["section"] = "buffs", ["layoutOrder"] = 1 },
		["metaSkillCd:20572"] = { ["trackerType"] = "metaSkillCd", ["key"] = "metaSkillCd:20572", ["spellID"] = 20572, ["duration"] = 120, ["section"] = "utility", ["layoutOrder"] = 2 },
		["metaSkill:1299026"] = { ["trackerType"] = "metaSkill", ["key"] = "metaSkill:1299026", ["spellID"] = 1299026, ["duration"] = 8, ["section"] = "bars", ["layoutOrder"] = 3 },
		["metaSkillCd:20554"] = { ["trackerType"] = "metaSkillCd", ["key"] = "metaSkillCd:20554", ["spellID"] = 20554, ["section"] = "hidden", ["layoutOrder"] = 4 },
		["racial2"] = { ["section"] = "bars", ["layoutOrder"] = 5 },
		["metaSkill:lust"] = { ["trackerType"] = "metaSkill", ["key"] = "metaSkill:lust", ["duration"] = 40, ["label"] = "Lust", ["section"] = "bars", ["layoutOrder"] = 6 },
		["userBuff:1719"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:1719", ["spellID"] = 1719, ["duration"] = 12, ["label"] = "Recklessness", ["section"] = "buffs", ["layoutOrder"] = 7 },
		["userCd:20572"] = { ["trackerType"] = "userCd", ["key"] = "userCd:20572", ["spellID"] = 20572, ["duration"] = 120, ["section"] = "utility", ["layoutOrder"] = 8 },
		["userReminder:5555"] = { ["trackerType"] = "userReminder", ["key"] = "userReminder:5555", ["spellID"] = 5555, ["label"] = "Reminder", ["section"] = "reminders", ["layoutOrder"] = 9 },
		["metaReminder:20217"] = { ["trackerType"] = "metaReminder", ["key"] = "metaReminder:20217", ["spellID"] = 20217, ["alternatives"] = { 1 }, ["section"] = "reminders", ["layoutOrder"] = 10 },
		["metaItem:trinket"] = { ["trackerType"] = "metaItem", ["key"] = "metaItem:trinket", ["section"] = "bars", ["layoutOrder"] = 11 },
		["metaItem:241308"] = { ["trackerType"] = "metaItem", ["key"] = "metaItem:241308", ["itemID"] = 241308, ["section"] = "utility", ["layoutOrder"] = 12 },
		["userBuff:3333"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:3333", ["spellID"] = 3333, ["duration"] = 30, ["section"] = "user1", ["layoutOrder"] = 13 },
	},
}
`;

// Case D: v11 -> v12 standalone. Exactly the five racial keys go; every other key is the SAME object
// with byte-equal fields; a second pass changes nothing; a database below 11 is not touched.
function caseD(expect) {
  const db = parse(FIXTURE_R);
  const tb = db.get('trackedBuffs');
  const snapshot = new Map([...tb]);
  const fieldsBefore = new Map([...tb].map(([k, v]) => [k, snapshotFields(v)]));
  const racialKeys = ['metaSkill:20572', 'metaSkillCd:20572', 'metaSkill:1299026', 'metaSkillCd:20554', 'racial2'];

  migrateV12(db, []);

  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  for (const k of racialKeys) expect(!tbAfter.has(k), `${k}: racial tracker should be gone`);
  expect(tbAfter.size === snapshot.size - racialKeys.length, `trackedBuffs.size expected ${snapshot.size - racialKeys.length}, got ${tbAfter.size}`);
  for (const [k, obj] of snapshot) {
    if (racialKeys.includes(k)) continue;
    expect(tbAfter.get(k) === obj, `${k}: expected the same object, kept`);
    const after = tbAfter.get(k);
    const before = fieldsBefore.get(k);
    if (!after) continue;
    for (const field of Object.keys(before)) {
      expect(after.get(field) === before[field], `${k}.${field}: changed`);
    }
    for (const field of after.keys()) expect(field in before, `${k}.${field}: unexpected new field`);
  }
  expect(tbAfter.has('metaSkill:lust'), 'metaSkill:lust must survive v12');
  expect(tbAfter.has('userCd:20572'), 'userCd:20572 (a user cooldown of a racial spell) must survive v12');

  // Second pass: a no-op.
  const keysAfter = [...tbAfter.keys()];
  migrateV12(db, []);
  expect(db.get('schemaVersion') === 12, `second pass: schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  expect(tbAfter.size === keysAfter.length && keysAfter.every(k => tbAfter.has(k)), 'second pass: key set changed');

  // A database below 11 is not touched by v12 (not even its schemaVersion).
  const low = parse(FIXTURE_R);
  low.set('schemaVersion', 10);
  const lowKeys = [...low.get('trackedBuffs').keys()];
  migrateV12(low, []);
  expect(low.get('schemaVersion') === 10, `below 11: schemaVersion expected 10, got ${low.get('schemaVersion')}`);
  const lowTb = low.get('trackedBuffs');
  expect(lowTb.size === lowKeys.length && lowKeys.every(k => lowTb.has(k)), 'below 11: key set changed');
}

// Fixture C: pre-v7, schemaVersion 6, NO legacy racial slot (WR-02).
const FIXTURE_C = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 6,
	["trackedBuffs"] = {
		[1719] = { ["trackerType"] = "buff", ["spellID"] = 1719, ["section"] = "buffs", ["layoutOrder"] = 1 },
		["cd:1719"] = { ["trackerType"] = "cooldown", ["spellID"] = 1719, ["section"] = "essential", ["layoutOrder"] = 2 },
	},
}
`;

// With no "racial"/"racial2" slot, v7 stamps and v8 re-keys in the same pass.
function caseF(expect) {
  const db = parse(FIXTURE_C);
  migrate(db, []);
  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tb = db.get('trackedBuffs');
  expect(tb.has('userBuff:1719'), 'userBuff:1719: missing');
  expect(tb.has('userCd:1719'), 'userCd:1719: missing');
  expect(tb.size === 2, `trackedBuffs.size expected 2, got ${tb.size}`);
}

// Fixture D: exactly what the WoW client writes (WR-03) -- an implicit-index array with `-- [n]`
// comments, an escaped quote and backslash in a label, a nested array -- on a pre-v4 database
// carrying an auto-seeded hidden lust that v3 removes.
const FIXTURE_D = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 2,
	["userContainers"] = {
		{
			["key"] = "user1",
			["name"] = "My \\"Burst\\" \\\\ Row",
			["tags"] = {
				"a", -- [1]
				"b", -- [2]
			},
		}, -- [1]
	},
	["trackedBuffs"] = {
		[1719] = { ["trackerType"] = "buff", ["section"] = "buffs", ["layoutOrder"] = 1, ["label"] = "Say \\"hi\\"" },
		["lust"] = { ["section"] = "hidden", ["layoutOrder"] = 2 },
	},
}
TerribleBuffTrackerDBChar = nil
`;

function caseG(expect) {
  const db = parse(FIXTURE_D);
  const uc = db.get('userContainers');
  expect(uc instanceof Map && uc.size === 1, `userContainers expected 1 array entry, got ${uc && uc.size}`);
  const c1 = uc && uc.get(1);
  expect(c1 && c1.get('name') === 'My "Burst" \\ Row', `userContainers[1].name mis-parsed: ${c1 && JSON.stringify(c1.get('name'))}`);
  const tags = c1 && c1.get('tags');
  expect(tags && tags.get(1) === 'a' && tags.get(2) === 'b', 'nested array entries mis-parsed');
  const label = db.get('trackedBuffs').get(1719).get('label');
  expect(label === 'Say "hi"', `label with escaped quotes mis-parsed: ${JSON.stringify(label)}`);

  migrate(db, []);
  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tb = db.get('trackedBuffs');
  expect(!tb.has('metaSkill:lust') && !tb.has('lust'), 'v3 should have removed the hidden auto-seeded lust');
  expect(tb.has('userBuff:1719') && tb.size === 1, `key set expected {userBuff:1719}, got {${[...tb.keys()].join(', ')}}`);
}

// Proves the comparator used in case A is not vacuous: given a deliberately corrupted expected
// key set (userCd:1719 replaced with the pre-migration literal cd:1719), it MUST report a
// mismatch. If this case's own `expect` were satisfied by a comparator that always passes,
// SELFTEST PASS would be meaningless.
function caseE(expect, prev) {
  if (!prev) { expect(false, 'case A produced no result to reuse'); return; }
  const { tbAfter } = prev;
  const actualKeys = new Set(tbAfter.keys());
  const corrupted = new Set(FIXTURE_A_MOVES.map(m => m[1]));
  corrupted.delete('userCd:1719');
  corrupted.add('cd:1719'); // deliberately wrong expectation
  const matches = corrupted.size === actualKeys.size && [...corrupted].every(k => actualKeys.has(k));
  expect(matches === false, 'comparator did not report a mismatch for a deliberately corrupted expectation -- selftest would be vacuous');
}

// Case H: schema v9 (Phase 57.1, ADD-07) -- detailed=true keeps its Advanced values,
// detailed=false and no-detailed-key both clear them, detailed is gone everywhere, schemaVersion
// ends at 9, and a second pass is a no-op (same object identity, same fields). It calls
// migrateV9 directly, not migrate(): v10 would otherwise convert its "absent" record (case I
// covers v10).
function caseH(expect) {
  const db = parse(FIXTURE_E);
  const tb = db.get('trackedBuffs');
  const snapshot = new Map([...tb]);

  migrateV9(db, []);

  expect(db.get('schemaVersion') === 9, `schemaVersion expected 9, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  expect(tbAfter.size === 4, `trackedBuffs.size expected 4, got ${tbAfter.size}`);

  // userBuff:1719 -- detailed=true keeps all four Advanced values; detailed key is gone.
  const e1719 = tbAfter.get('userBuff:1719');
  expect(e1719 !== undefined, 'userBuff:1719: missing');
  if (e1719) {
    expect(e1719 === snapshot.get('userBuff:1719'), 'userBuff:1719: object identity changed');
    expect(!e1719.has('detailed'), 'userBuff:1719: detailed key should be gone');
    expect(e1719.get('auraID') === 2825, `userBuff:1719.auraID expected 2825, got ${e1719.get('auraID')}`);
    expect(e1719.get('keepOnAuraLoss') === true, `userBuff:1719.keepOnAuraLoss expected true, got ${e1719.get('keepOnAuraLoss')}`);
    expect(e1719.get('visibility') === 'absent', `userBuff:1719.visibility expected 'absent', got ${e1719.get('visibility')}`);
    const endOnCast = e1719.get('endOnCast');
    expect(endOnCast && endOnCast.get(1) === 6673, `userBuff:1719.endOnCast expected [6673], got ${endOnCast && JSON.stringify([...endOnCast.values()])}`);
    expect(e1719.get('label') === 'Recklessness', `userBuff:1719.label expected 'Recklessness', got ${e1719.get('label')}`);
    expect(e1719.get('duration') === 12, `userBuff:1719.duration expected 12, got ${e1719.get('duration')}`);
    expect(e1719.get('section') === 'buffs', `userBuff:1719.section expected 'buffs', got ${e1719.get('section')}`);
    expect(e1719.get('layoutOrder') === 1, `userBuff:1719.layoutOrder expected 1, got ${e1719.get('layoutOrder')}`);
  }

  // userBuff:6673 -- detailed=false clears all four Advanced values; everything else untouched.
  const e6673 = tbAfter.get('userBuff:6673');
  expect(e6673 !== undefined, 'userBuff:6673: missing');
  if (e6673) {
    expect(!e6673.has('detailed'), 'userBuff:6673: detailed key should be gone');
    expect(e6673.get('auraID') === undefined, `userBuff:6673.auraID expected cleared, got ${e6673.get('auraID')}`);
    expect(e6673.get('keepOnAuraLoss') === undefined, `userBuff:6673.keepOnAuraLoss expected cleared, got ${e6673.get('keepOnAuraLoss')}`);
    expect(e6673.get('visibility') === undefined, `userBuff:6673.visibility expected cleared, got ${e6673.get('visibility')}`);
    expect(e6673.get('endOnCast') === undefined, `userBuff:6673.endOnCast expected cleared, got ${e6673.get('endOnCast')}`);
    expect(e6673.get('label') === 'Combustion', `userBuff:6673.label expected 'Combustion', got ${e6673.get('label')}`);
    expect(e6673.get('duration') === 10, `userBuff:6673.duration expected 10, got ${e6673.get('duration')}`);
    expect(e6673.get('section') === 'buffs', `userBuff:6673.section expected 'buffs', got ${e6673.get('section')}`);
    expect(e6673.get('layoutOrder') === 2, `userBuff:6673.layoutOrder expected 2, got ${e6673.get('layoutOrder')}`);
  }

  // userBuff:2825 -- no detailed key at all still clears the same four values.
  const e2825 = tbAfter.get('userBuff:2825');
  expect(e2825 !== undefined, 'userBuff:2825: missing');
  if (e2825) {
    expect(!e2825.has('detailed'), 'userBuff:2825: detailed key should be gone');
    expect(e2825.get('auraID') === undefined, `userBuff:2825.auraID expected cleared, got ${e2825.get('auraID')}`);
    expect(e2825.get('endOnCast') === undefined, `userBuff:2825.endOnCast expected cleared, got ${e2825.get('endOnCast')}`);
    expect(e2825.get('label') === 'Bloodlust', `userBuff:2825.label expected 'Bloodlust', got ${e2825.get('label')}`);
    expect(e2825.get('duration') === 40, `userBuff:2825.duration expected 40, got ${e2825.get('duration')}`);
    expect(e2825.get('section') === 'bars', `userBuff:2825.section expected 'bars', got ${e2825.get('section')}`);
    expect(e2825.get('layoutOrder') === 3, `userBuff:2825.layoutOrder expected 3, got ${e2825.get('layoutOrder')}`);
  }

  // userCd:1719 -- detailed=true keeps its visibility (and auraID).
  const cd1719 = tbAfter.get('userCd:1719');
  expect(cd1719 !== undefined, 'userCd:1719: missing');
  if (cd1719) {
    expect(!cd1719.has('detailed'), 'userCd:1719: detailed key should be gone');
    expect(cd1719.get('visibility') === 'present', `userCd:1719.visibility expected 'present', got ${cd1719.get('visibility')}`);
    expect(cd1719.get('auraID') === 1719, `userCd:1719.auraID expected 1719, got ${cd1719.get('auraID')}`);
    expect(cd1719.get('label') === 'Recklessness', `userCd:1719.label expected 'Recklessness', got ${cd1719.get('label')}`);
    expect(cd1719.get('duration') === 90, `userCd:1719.duration expected 90, got ${cd1719.get('duration')}`);
    expect(cd1719.get('section') === 'essential', `userCd:1719.section expected 'essential', got ${cd1719.get('section')}`);
    expect(cd1719.get('layoutOrder') === 4, `userCd:1719.layoutOrder expected 4, got ${cd1719.get('layoutOrder')}`);
  }

  // Second login is a no-op: same object identity, same fields, schemaVersion unchanged.
  const objectsBefore = new Map([...tbAfter]);
  const fieldsBefore = new Map([...tbAfter].map(([k, v]) => [k, snapshotFields(v)]));
  migrateV9(db, []);
  expect(db.get('schemaVersion') === 9, `second pass: schemaVersion expected 9, got ${db.get('schemaVersion')}`);
  const tbSecond = db.get('trackedBuffs');
  for (const [k, obj] of objectsBefore) {
    expect(tbSecond.get(k) === obj, `${k}: object identity changed on second pass`);
    const before = fieldsBefore.get(k);
    const after = tbSecond.get(k);
    for (const field of Object.keys(before)) {
      expect(after.get(field) === before[field], `${k}.${field}: changed on second pass`);
    }
  }
}

// Case I: schema v10 (Phase 57.2, REM-04) -- a userBuff saved with visibility "absent" becomes
// the SAME object at userReminder:<id> (only visibility dropped; duration, keepOnAuraLoss,
// endOnCast, auraID, coverAllRanks, label, layoutOrder kept, since a reminder is a buff tracker in
// its own category, user decision 2026-09-29; section 'reminders' unless 'hidden'), an
// existing reminder wins a collision, every other visibility and the cooldown aura ID are dropped,
// schemaVersion ends at 10, a second pass is a no-op and a database below 9 is not touched. It
// calls migrateV10 directly, not migrate(): v11 would otherwise move the endOnCast v10 keeps on
// the reminders it creates (case K covers v11).
function caseI(expect) {
  const db = parse(FIXTURE_F);
  const tb = db.get('trackedBuffs');
  const snapshot = new Map([...tb]);
  const fieldsBefore = new Map([...tb].map(([k, v]) => [k, snapshotFields(v)]));

  migrateV10(db, []);

  expect(db.get('schemaVersion') === 10, `schemaVersion expected 10, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  const expectedKeys = ['userReminder:1719', 'userReminder:6673', 'userBuff:2825', 'userReminder:5555', 'userCd:1719', 'metaSkill:lust'];
  expect(
    tbAfter.size === expectedKeys.length && expectedKeys.every(k => tbAfter.has(k)),
    `key set expected {${expectedKeys.join(', ')}}, got {${[...tbAfter.keys()].join(', ')}}`
  );

  // Asserts `after` holds exactly the `want` fields (and no other).
  const assertFields = (name, after, want) => {
    for (const [k, v] of Object.entries(want)) {
      expect(after.get(k) === v, `${name}.${k}: expected ${JSON.stringify(v)}, got ${JSON.stringify(after.get(k))}`);
    }
    for (const k of after.keys()) {
      if (!(k in want)) expect(false, `${name}.${k}: unexpected field (value ${JSON.stringify(after.get(k))})`);
    }
  };

  const r1719 = tbAfter.get('userReminder:1719');
  if (r1719) {
    expect(r1719 === snapshot.get('userBuff:1719'), 'userReminder:1719: expected the same object that sat at userBuff:1719');
    assertFields('userReminder:1719', r1719, {
      trackerType: 'userReminder', key: 'userReminder:1719', spellID: 1719, auraID: 2825,
      coverAllRanks: true, label: 'Recklessness', section: 'reminders', layoutOrder: 1,
      duration: 12, keepOnAuraLoss: true, endOnCast: fieldsBefore.get('userBuff:1719').endOnCast,
    });
  }

  const r6673 = tbAfter.get('userReminder:6673');
  if (r6673) {
    expect(r6673 === snapshot.get('userBuff:6673'), 'userReminder:6673: expected the same object that sat at userBuff:6673');
    assertFields('userReminder:6673', r6673, {
      trackerType: 'userReminder', key: 'userReminder:6673', spellID: 6673,
      label: 'Combustion', section: 'hidden', layoutOrder: 2, duration: 10,
    });
  }

  const b2825 = tbAfter.get('userBuff:2825');
  if (b2825) {
    expect(b2825 === snapshot.get('userBuff:2825'), 'userBuff:2825: object identity changed');
    const want = { ...fieldsBefore.get('userBuff:2825') };
    delete want.visibility;
    assertFields('userBuff:2825', b2825, want);
  }

  const r5555 = tbAfter.get('userReminder:5555');
  if (r5555) {
    expect(r5555 === snapshot.get('userReminder:5555'), 'userReminder:5555: the existing record must win (same object)');
    assertFields('userReminder:5555', r5555, fieldsBefore.get('userReminder:5555'));
  }

  const cd1719 = tbAfter.get('userCd:1719');
  if (cd1719) {
    expect(cd1719 === snapshot.get('userCd:1719'), 'userCd:1719: object identity changed');
    const want = { ...fieldsBefore.get('userCd:1719') };
    delete want.visibility;
    delete want.auraID;
    assertFields('userCd:1719', cd1719, want);
    const endOnCast = cd1719.get('endOnCast');
    expect(endOnCast && endOnCast.get(1) === 100, 'userCd:1719.endOnCast expected [100]');
  }

  const lust = tbAfter.get('metaSkill:lust');
  if (lust) {
    expect(lust === snapshot.get('metaSkill:lust'), 'metaSkill:lust: object identity changed');
    assertFields('metaSkill:lust', lust, fieldsBefore.get('metaSkill:lust'));
  }

  // Second login is a no-op: same keys, same object identity, same fields.
  const objectsAfter = new Map([...tbAfter]);
  const fieldsAfter = new Map([...tbAfter].map(([k, v]) => [k, snapshotFields(v)]));
  migrateV10(db, []);
  expect(db.get('schemaVersion') === 10, `second pass: schemaVersion expected 10, got ${db.get('schemaVersion')}`);
  const tbSecond = db.get('trackedBuffs');
  expect(tbSecond.size === objectsAfter.size, `second pass: size changed ${objectsAfter.size} -> ${tbSecond.size}`);
  for (const [k, obj] of objectsAfter) {
    expect(tbSecond.get(k) === obj, `${k}: object identity changed on second pass`);
    if (tbSecond.get(k)) assertFields(`second pass ${k}`, tbSecond.get(k), fieldsAfter.get(k));
  }

  // A database still below 9 is not touched by v10.
  const low = parse(FIXTURE_F);
  low.set('schemaVersion', 8);
  const lowTb = low.get('trackedBuffs');
  const lowKeys = [...lowTb.keys()];
  migrateV10(low, []);
  expect(low.get('schemaVersion') === 8, `below 9: schemaVersion expected 8, got ${low.get('schemaVersion')}`);
  expect(lowTb.size === lowKeys.length && lowKeys.every(k => lowTb.has(k)), 'below 9: key set changed');
  expect(lowTb.get('userBuff:1719').get('visibility') === 'absent', 'below 9: userBuff:1719.visibility should be untouched');
  expect(lowTb.get('userCd:1719').get('auraID') === 1719, 'below 9: userCd:1719.auraID should be untouched');
}

// Case J: schema v10's fallback branches (Phase 57.2 review WR-04), each mirroring a line of
// ns:MigrateBuffReminders:
// - `type(id) ~= "number"` falls back to ns:KeyNumericID(oldKey, USER_BUFF), which matches
//   ^userBuff:(%d+)$ and tonumber()s the capture. So a missing spellID and a string spellID both
//   key the reminder on the key's digits, and the spellID is written back as that number.
// - `id == nil`: the entry stays a userBuff at its old key and only `visibility` is dropped.
// - `section ~= "hidden"`: a migrant filed in a user container moves to "reminders".
// - A userCd saved "absent" is not a migrant: it loses `visibility` and `auraID` and stays a
//   cooldown.
// It calls migrateV10 directly, not migrate(): v11 would otherwise move the endOnCast v10 keeps
// on the reminders it creates (case K covers v11).
function caseJ(expect) {
  const db = parse(FIXTURE_F2);
  const tb = db.get('trackedBuffs');
  const snapshot = new Map([...tb]);
  const fieldsBefore = new Map([...tb].map(([k, v]) => [k, snapshotFields(v)]));

  migrateV10(db, []);

  expect(db.get('schemaVersion') === 10, `schemaVersion expected 10, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  const expectedKeys = ['userReminder:4321', 'userReminder:778', 'userBuff:abc', 'userReminder:3333', 'userCd:2222'];
  expect(
    tbAfter.size === expectedKeys.length && expectedKeys.every(k => tbAfter.has(k)),
    `key set expected {${expectedKeys.join(', ')}}, got {${[...tbAfter.keys()].join(', ')}}`
  );

  const assertFields = (name, after, want) => {
    for (const [k, v] of Object.entries(want)) {
      expect(after.get(k) === v, `${name}.${k}: expected ${JSON.stringify(v)}, got ${JSON.stringify(after.get(k))}`);
    }
    for (const k of after.keys()) {
      if (!(k in want)) expect(false, `${name}.${k}: unexpected field (value ${JSON.stringify(after.get(k))})`);
    }
  };
  const check = (newKey, oldKey, want) => {
    const after = tbAfter.get(newKey);
    if (!after) return;
    expect(after === snapshot.get(oldKey), `${newKey}: expected the same object that sat at ${oldKey}`);
    assertFields(newKey, after, want);
  };

  // Key-parse fallback, no spellID at all: spellID is backfilled from the key.
  check('userReminder:4321', 'userBuff:4321', {
    trackerType: 'userReminder', key: 'userReminder:4321', spellID: 4321,
    label: 'NoSpellID', section: 'reminders', layoutOrder: 1, duration: 8,
  });

  // Key-parse fallback, non-numeric spellID: the key's digits win and replace the string.
  // This is also the no-duration reminder: it was saved without one, and none is invented.
  check('userReminder:778', 'userBuff:778', {
    trackerType: 'userReminder', key: 'userReminder:778', spellID: 778,
    label: 'StringSpellID', section: 'reminders', layoutOrder: 2,
  });
  expect(!tbAfter.has('userReminder:777'), 'userReminder:777: a string spellID must not key the reminder');

  // No-ID branch: stays a userBuff at its old key, every field but visibility kept.
  const noDigitsWant = { ...fieldsBefore.get('userBuff:abc') };
  delete noDigitsWant.visibility;
  check('userBuff:abc', 'userBuff:abc', noDigitsWant);

  // A migrant in a user container moves to the reminders base container.
  check('userReminder:3333', 'userBuff:3333', {
    trackerType: 'userReminder', key: 'userReminder:3333', spellID: 3333,
    label: 'InUserContainer', section: 'reminders', layoutOrder: 4,
    duration: 30, endOnCast: fieldsBefore.get('userBuff:3333').endOnCast,
  });

  // A cooldown saved "absent" stays a cooldown; visibility and auraID are both dropped.
  const cdWant = { ...fieldsBefore.get('userCd:2222') };
  delete cdWant.visibility;
  delete cdWant.auraID;
  check('userCd:2222', 'userCd:2222', cdWant);
  expect(!tbAfter.has('userReminder:2222') && !tbAfter.has('userReminder:2223'), 'userCd:2222: a cooldown saved "absent" must not become a reminder');

  // Second login is a no-op here too.
  const fieldsAfter = new Map([...tbAfter].map(([k, v]) => [k, snapshotFields(v)]));
  const objectsAfter = new Map([...tbAfter]);
  migrateV10(db, []);
  const tbSecond = db.get('trackedBuffs');
  expect(tbSecond.size === objectsAfter.size, `second pass: size changed ${objectsAfter.size} -> ${tbSecond.size}`);
  for (const [k, obj] of objectsAfter) {
    expect(tbSecond.get(k) === obj, `${k}: object identity changed on second pass`);
    if (tbSecond.get(k)) assertFields(`second pass ${k}`, tbSecond.get(k), fieldsAfter.get(k));
  }
}

// Case K: schema v11 (Phase 57.5, RALT-02) -- for reminders only (userReminder and metaReminder),
// "Ends when you cast" becomes "Also satisfied by" (RALT-01, the one deliberate divergence from
// "reminders are buffs", user decision 2026-09-29). A reminder's non-empty endOnCast becomes its
// `alternatives` as the SAME table, or is merged without duplicates into an existing alternatives
// list; an empty or non-table rule is dropped; endOnCast is gone from every reminder. Buff and
// cooldown trackers keep endOnCast untouched. schemaVersion ends at 11, a second pass is a no-op
// and a database below 10 is not touched.
function caseK(expect) {
  const db = parse(FIXTURE_G);
  const tb = db.get('trackedBuffs');
  const snapshot = new Map([...tb]);
  const fieldsBefore = new Map([...tb].map(([k, v]) => [k, snapshotFields(v)]));

  migrate(db, []);

  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  expect(tbAfter.size === snapshot.size, `trackedBuffs.size expected ${snapshot.size}, got ${tbAfter.size}`);
  for (const [k, obj] of snapshot) {
    expect(tbAfter.get(k) === obj, `${k}: object identity changed`);
  }
  const values = m => (m instanceof Map ? [...m.values()] : null);
  const sameList = (name, got, want) => {
    expect(
      Array.isArray(got) && got.length === want.length && want.every((v, i) => got[i] === v),
      `${name}: expected [${want.join(', ')}], got ${got ? '[' + got.join(', ') + ']' : String(got)}`
    );
  };
  // Every field but endOnCast/alternatives kept, and no other new field.
  const assertRest = (k, entry) => {
    const before = fieldsBefore.get(k);
    for (const f of Object.keys(before)) {
      if (f === 'endOnCast' || f === 'alternatives') continue;
      expect(entry.get(f) === before[f], `${k}.${f}: changed`);
    }
    for (const f of entry.keys()) {
      if (f !== 'alternatives' && !(f in before)) expect(false, `${k}.${f}: unexpected new field`);
    }
  };

  const r1719 = tbAfter.get('userReminder:1719');
  if (r1719) {
    expect(!r1719.has('endOnCast'), 'userReminder:1719: endOnCast should be gone');
    expect(r1719.get('alternatives') === fieldsBefore.get('userReminder:1719').endOnCast, 'userReminder:1719: alternatives should be the SAME table the rule was');
    sameList('userReminder:1719.alternatives', values(r1719.get('alternatives')), [6673, 2825]);
    assertRest('userReminder:1719', r1719);
  }

  const r3333 = tbAfter.get('userReminder:3333');
  if (r3333) {
    expect(!r3333.has('endOnCast'), 'userReminder:3333: endOnCast should be gone');
    expect(r3333.get('alternatives') === fieldsBefore.get('userReminder:3333').alternatives, 'userReminder:3333: alternatives should be the SAME existing table');
    sameList('userReminder:3333.alternatives', values(r3333.get('alternatives')), [20, 30, 10]);
    assertRest('userReminder:3333', r3333);
  }

  for (const k of ['userReminder:4444', 'userReminder:7777']) {
    const e = tbAfter.get(k);
    if (!e) continue;
    expect(!e.has('endOnCast'), `${k}: endOnCast should be gone`);
    expect(!e.has('alternatives'), `${k}: an empty or non-table rule must not become alternatives`);
    assertRest(k, e);
  }

  const kings = tbAfter.get('metaReminder:20217');
  if (kings) {
    expect(!kings.has('endOnCast'), 'metaReminder:20217: endOnCast should be gone');
    sameList('metaReminder:20217.alternatives', values(kings.get('alternatives')), [1]);
    assertRest('metaReminder:20217', kings);
  }

  for (const k of ['userReminder:5555', 'userBuff:2825', 'userCd:1719']) {
    const e = tbAfter.get(k);
    if (!e) continue;
    const before = fieldsBefore.get(k);
    for (const f of Object.keys(before)) expect(e.get(f) === before[f], `${k}.${f}: changed`);
    for (const f of e.keys()) if (!(f in before)) expect(false, `${k}.${f}: unexpected new field`);
  }

  // Second login is a no-op: same keys, same object identity, same fields.
  const fieldsAfter = new Map([...tbAfter].map(([k, v]) => [k, snapshotFields(v)]));
  migrate(db, []);
  expect(db.get('schemaVersion') === 12, `second pass: schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  for (const [k, obj] of snapshot) {
    const e = db.get('trackedBuffs').get(k);
    expect(e === obj, `${k}: object identity changed on second pass`);
    if (!e) continue;
    const before = fieldsAfter.get(k);
    for (const f of Object.keys(before)) expect(e.get(f) === before[f], `second pass ${k}.${f}: changed`);
    for (const f of e.keys()) if (!(f in before)) expect(false, `second pass ${k}.${f}: unexpected new field`);
  }

  // A database still below 10 is not touched by v11.
  const low = parse(FIXTURE_G);
  low.set('schemaVersion', 9);
  migrateV11(low, []);
  expect(low.get('schemaVersion') === 9, `below 10: schemaVersion expected 9, got ${low.get('schemaVersion')}`);
  const lowR = low.get('trackedBuffs').get('userReminder:1719');
  expect(lowR.has('endOnCast') && !lowR.has('alternatives'), 'below 10: userReminder:1719.endOnCast should be untouched');

  caseKMalformed(expect);
}

// Case K's malformed sub-case (57.5 review IN-02), run from caseK so the case count the 57.5 plan
// gates pin stays 12. Hand-edited tables, filtered exactly as ns:MigrateReminderAlternatives
// filters them: the ipairs sequence only, positive numbers only, first occurrence only; a moved
// rule is the SAME table reduced to exactly those IDs; a merge appends after the existing list's
// ipairs border and never overwrites a sparse key; no valid ID drops the rule.
function caseKMalformed(expect) {
  const db = parse(FIXTURE_H);
  const tb = db.get('trackedBuffs');
  const rules = new Map([...tb].map(([k, v]) => [k, v.get('endOnCast')]));
  migrateV11(db, []);
  expect(db.get('schemaVersion') === 11, `malformed: schemaVersion expected 11, got ${db.get('schemaVersion')}`);
  const entries = m => [...m.entries()];
  const exactly = (name, m, want) => {
    const got = m instanceof Map ? entries(m) : null;
    expect(
      got !== null && got.length === want.length && want.every(([k, v], i) => got[i][0] === k && got[i][1] === v),
      `malformed ${name}: expected ${JSON.stringify(want)}, got ${JSON.stringify(got)}`
    );
  };
  for (const k of tb.keys()) expect(!tb.get(k).has('endOnCast'), `malformed ${k}: endOnCast should be gone`);

  // Hash-only and all-junk rules: dropped, no alternatives.
  for (const k of ['userReminder:1', 'userReminder:5']) {
    expect(!tb.get(k).has('alternatives'), `malformed ${k}: a rule with no valid ID must not become alternatives`);
  }
  // Junk, duplicates and a hash key: the SAME table, exactly [5, 7].
  const r2 = tb.get('userReminder:2');
  expect(r2.get('alternatives') === rules.get('userReminder:2'), 'malformed userReminder:2: alternatives should be the SAME table');
  exactly('userReminder:2.alternatives', r2.get('alternatives'), [[1, 5], [2, 7]]);
  // A hole ends the sequence: exactly [5].
  exactly('userReminder:3.alternatives', tb.get('userReminder:3').get('alternatives'), [[1, 5]]);
  // Merge into a sparse list: 20 lands at the border (2), 30 at 3 is kept, 10 is a duplicate.
  const r4 = tb.get('userReminder:4').get('alternatives');
  expect(r4 instanceof Map && r4.get(1) === 10 && r4.get(2) === 20 && r4.get(3) === 30 && r4.size === 3,
    `malformed userReminder:4.alternatives: expected {1: 10, 2: 20, 3: 30}, got ${JSON.stringify(r4 instanceof Map ? entries(r4) : r4)}`);
}

// Case L: the real v9 -> v10 -> v11 chain (Phase 57.5, RALT-02) on Fixture F -- an "absent" buff
// becomes a reminder in v10 (keeping its cast rule), and v11 then moves that rule into its
// alternatives. A cooldown keeps its cast rule.
function caseL(expect) {
  const db = parse(FIXTURE_F);
  const tb = db.get('trackedBuffs');
  const rule = tb.get('userBuff:1719').get('endOnCast');

  migrate(db, []);

  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tbAfter = db.get('trackedBuffs');
  const r1719 = tbAfter.get('userReminder:1719');
  expect(r1719 !== undefined, 'userReminder:1719: missing');
  if (r1719) {
    expect(!r1719.has('endOnCast'), 'userReminder:1719: endOnCast should be gone');
    expect(r1719.get('alternatives') === rule, "userReminder:1719: alternatives should be the SAME table userBuff:1719's endOnCast was");
  }
  const cd1719 = tbAfter.get('userCd:1719');
  expect(cd1719 !== undefined, 'userCd:1719: missing');
  if (cd1719) {
    const endOnCast = cd1719.get('endOnCast');
    expect(endOnCast instanceof Map && endOnCast.size === 1 && endOnCast.get(1) === 100, 'userCd:1719.endOnCast expected [100]');
    expect(!cd1719.has('alternatives'), 'userCd:1719: a cooldown must not gain alternatives');
  }
}

// Fixture M: client-written shape (implicit arrays with `-- [n]` comments, an escaped quote in a
// label) at schemaVersion 11, carrying racial trackers of both kinds, for case M.
const FIXTURE_M = `
TerribleBuffTrackerDB = {
	["schemaVersion"] = 11,
	["userContainers"] = {
		{
			["key"] = "user1",
			["tags"] = {
				"a", -- [1]
			},
		}, -- [1]
	},
	["trackedBuffs"] = {
		["metaSkill:59752"] = { ["trackerType"] = "metaSkill", ["key"] = "metaSkill:59752", ["spellID"] = 59752, ["alternatives"] = {
			1, -- [1]
		}, ["section"] = "buffs", ["layoutOrder"] = 1 },
		["metaSkillCd:59752"] = { ["trackerType"] = "metaSkillCd", ["key"] = "metaSkillCd:59752", ["spellID"] = 59752, ["section"] = "utility", ["layoutOrder"] = 2 },
		["metaSkill:lust"] = { ["trackerType"] = "metaSkill", ["key"] = "metaSkill:lust", ["duration"] = 40, ["section"] = "bars", ["layoutOrder"] = 3 },
		["userBuff:1719"] = { ["trackerType"] = "userBuff", ["key"] = "userBuff:1719", ["spellID"] = 1719, ["label"] = "Say \\"hi\\"", ["section"] = "buffs", ["layoutOrder"] = 4 },
	},
}
`;

// Case M: a client-written file carrying racial trackers runs through the whole migrate() and loses
// only the racial keys.
function caseM(expect) {
  const db = parse(FIXTURE_M);
  const lust = db.get('trackedBuffs').get('metaSkill:lust');
  const buff = db.get('trackedBuffs').get('userBuff:1719');
  expect(buff && buff.get('label') === 'Say "hi"', `label with escaped quotes mis-parsed: ${buff && JSON.stringify(buff.get('label'))}`);

  migrate(db, []);

  expect(db.get('schemaVersion') === 12, `schemaVersion expected 12, got ${db.get('schemaVersion')}`);
  const tb = db.get('trackedBuffs');
  expect(
    tb.size === 2 && tb.has('metaSkill:lust') && tb.has('userBuff:1719'),
    `key set expected {metaSkill:lust, userBuff:1719}, got {${[...tb.keys()].join(', ')}}`
  );
  expect(tb.get('metaSkill:lust') === lust, 'metaSkill:lust: object identity changed');
  expect(tb.get('userBuff:1719') === buff, 'userBuff:1719: object identity changed');
}

function selftest() {
  let failures = 0;
  let caseCount = 0;

  function runCase(name, fn, arg) {
    caseCount++;
    const msgs = [];
    const expect = (cond, msg) => { if (!cond) msgs.push(msg); };
    let result;
    try {
      result = fn(expect, arg);
    } catch (e) {
      msgs.push('threw: ' + (e && e.stack ? e.stack : e));
    }
    if (msgs.length) {
      console.log(`SELFTEST FAIL ${name}: ${msgs.join(' | ')}`);
      failures++;
    } else {
      console.log(`SELFTEST PASS ${name}`);
    }
    return result;
  }

  const resultA = runCase('v0.4.1 -> v12', caseA);
  runCase('second login is a no-op', caseB, resultA);
  runCase('pre-v7 legacy racial slots dropped without reading the race', caseC);
  runCase('v11 -> v12: racial trackers dropped, every other tracker untouched', caseD);
  runCase('comparator can fail', caseE, resultA);
  runCase('pre-v7 with no legacy slot -> v12', caseF);
  runCase('WoW-written file (arrays, comments, escapes), pre-v4 -> v12', caseG);
  runCase('v8 -> v9: detailed flag dropped, switched-off values cleared', caseH);
  runCase('v9 -> v10: absent buffs become reminders, visibility and cooldown aura ID dropped', caseI);
  runCase('v9 -> v10 fallbacks: key-parse, no ID, user container, cooldown saved absent', caseJ);
  runCase('v10 -> v11: reminder cast rules become alternatives, buffs and cooldowns keep theirs', caseK);
  runCase('v9 -> v11 chain: an absent buff becomes a reminder whose cast rule becomes alternatives', caseL);
  runCase('client-written file with racial trackers -> v12', caseM);

  if (failures === 0) {
    console.log(`SELFTEST PASS (${caseCount} cases)`);
    process.exitCode = 0;
  } else {
    console.log(`SELFTEST FAIL (${failures}/${caseCount} cases failed)`);
    process.exitCode = 1;
  }
}

// --- CLI --------------------------------------------------------------------------------------
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rawArgs = process.argv.slice(2);
  for (const p of rawArgs) {
    console.log('\n######## ' + p.split(/[\/]/).pop() + ' ########');
    try { console.log(run(p).map(s => '  ' + s).join('\n')); }
    catch (e) { console.log('  FAILED: ' + e.message); }
  }
}
