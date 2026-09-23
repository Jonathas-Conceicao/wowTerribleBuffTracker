// Dry-run TBT's ADDON_LOADED sequence against a real SavedVariables file, without a game client.
//
//   node scripts/migrate-dryrun.js <path-to-TerribleBuffTracker.lua> [...]
//
// Why this exists: the v4, v5 and v6 migrations had never executed against a genuine v0.3.0
// database. Forever writes its own file but it is already v6, so it exercises nothing. This
// reproduces the ordering Core.lua and BuffEngine.lua actually use -- the ADDON_LOADED defaults
// and ns.EnsureContainerSettings FIRST, then the migration blocks, with `ver` read once before
// any of them -- and prints what each step does to the real data.
//
// It is a prediction, not a substitute for the in-game pass (Phase 44, criterion 3a). Keep the
// registry and the three migration blocks below in step with Core.lua and BuffEngine.lua; if they
// drift, this lies confidently.
// Faithful to Core.lua (defaults + EnsureContainerSettings) and BuffEngine.lua (v4/v5/v6).
const fs = require('fs');

// --- a parser for the restricted Lua subset SavedVariables emits -----------------
function parse(src) {
  let i = src.indexOf('=') + 1;
  const ws = () => { while (i < src.length && /[\s,]/.test(src[i])) i++; };
  function value() {
    ws();
    if (src[i] === '{') return table();
    if (src[i] === '"') {
      let j = ++i, out = '';
      while (src[j] !== '"') { out += src[j]; j++; }
      i = j + 1;
      return out;
    }
    let j = i;
    while (j < src.length && /[^\s,}]/.test(src[j])) j++;
    const lit = src.slice(i, j); i = j;
    if (lit === 'true') return true;
    if (lit === 'false') return false;
    if (lit === 'nil') return null;
    return Number(lit);
  }
  function table() {
    i++; // {
    // Map preserves key TYPE, which the v6 migration branches on.
    const m = new Map();
    for (;;) {
      ws();
      if (src[i] === '}') { i++; return m; }
      if (src[i] !== '[') throw new Error('expected [ at ' + i + ': ' + src.slice(i, i + 40));
      i++;
      let key;
      if (src[i] === '"') { let j = ++i, s = ''; while (src[j] !== '"') { s += src[j]; j++; } i = j + 1; key = s; }
      else { let j = i; while (src[j] !== ']') j++; key = Number(src.slice(i, j)); i = j; }
      if (src[i] !== ']') throw new Error('expected ]');
      i++; ws();
      if (src[i] !== '=') throw new Error('expected =');
      i++;
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
];
const BY_KEY = Object.fromEntries(CONTAINERS.map(d => [d.key, d]));
const GROWTH_CENTERED = 2;
const category = d => (d && d.category) || 'buffs';
const defaultGrowth = d => (d.kind !== 'bar' && category(d) === 'buffs') ? GROWTH_CENTERED : 0;

function run(path) {
  const db = parse(fs.readFileSync(path, 'utf8'));
  const log = [];
  const g = k => db.get(k);

  log.push(`schemaVersion in  : ${g('schemaVersion')}`);

  // --- Core.lua ADDON_LOADED defaults, in source order -------------------------
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

  log.push(`schemaVersion out : ${g('schemaVersion')}`);

  // --- what survived -----------------------------------------------------------
  const tb = g('trackedBuffs');
  log.push(`trackers kept     : ${tb.size} -> ${[...tb.keys()].join(', ')}`);
  const pos = g('editModePositions');
  log.push(`positions kept    : ${pos ? [...pos.keys()].join(', ') : '(none)'}`);
  log.push(`growthDirection   : ${CONTAINERS.map(d => d.key + '=' + cset.get(d.key).get('growthDirection')).join('  ')}`);
  return log;
}

for (const p of process.argv.slice(2)) {
  console.log('\n######## ' + p.split(/[\/]/).pop() + ' ########');
  try { console.log(run(p).map(s => '  ' + s).join('\n')); }
  catch (e) { console.log('  FAILED: ' + e.message); }
}
