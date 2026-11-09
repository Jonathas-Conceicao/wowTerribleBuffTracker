// DOC-07: docs/REMINDERS.md is the human-review list of every built-in reminder. This check proves
// that the doc and the reminder table in Providers.lua name the same IDs, per client and overall,
// so the doc cannot drift from the code without the check going red.
//
//   node scripts/reminders-doc-check.js              -- check Providers.lua against docs/REMINDERS.md,
//                                                       exit 1 on any mismatch
//   node scripts/reminders-doc-check.js --selftest   -- run the checker against embedded fixtures
//   --code <path> / --doc <path>                     -- read another file instead (for gates)
//
// Code side: every MetaReminderRow first argument, auraID and useItems item ID, and every
// MetaReminderGroup ID. Comments are stripped first, so an ID named in prose (the retired-blessings
// note) is never counted. A row's client is its opts.client ("forever" when absent); a group inside
// an `if ns.CLIENT_IS_FOREVER then ... end` block counts on Forever only, a group outside one counts
// on every client where one of its IDs is a row.
//
// Doc side: every wowhead link under `## Forever` and `## Retail`. Forever links must be
// /forever/spell= or /forever/item=, retail links spell= or item=; any other path fails. Links
// under `## Not included` are not collected, but one to a row ID fails. Each row also needs a table
// line in its section, under its class, with the right Duration and Verified cells.
//
// Known limits (static text, not a Lua evaluator): a row or group built at runtime (a loop, a
// variable holding an ID) cannot be seen. The row's class and verified status are read from its
// trailing `-- <Class>: <name>` comment, which is a convention, not code.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DEFAULT_CODE = path.join(ROOT, 'Providers.lua');
const DEFAULT_DOC = path.join(ROOT, 'docs', 'REMINDERS.md');

const CLIENTS = ['forever', 'retail'];
const CLIENT_LABEL = { forever: 'Forever', retail: 'Retail' };
const VALID_CLIENTS = new Set(['forever', 'retail', 'both']);

// --- Lua lexing ----------------------------------------------------------------------------------
function longBracketLevel(text, i) {
  // text[i] is "[": returns the level of a long bracket opener starting here, or -1.
  let j = i + 1;
  while (text[j] === '=') {
    j++;
  }
  return text[j] === '[' ? j - i - 1 : -1;
}

function keepBreak(ch) {
  return ch === '\n' || ch === '\r' ? ch : ' ';
}

// Two views of the text, both the SAME length as the input so an offset means the same place in
// all three: noComments has every comment blanked (line breaks kept) and strings intact, so a
// `client = "..."` value stays readable; blank also blanks string and long-string contents, so no
// keyword, call or ID inside a string is ever seen. A `--` inside a string is never a comment.
function lexLua(text) {
  const n = text.length;
  const a = new Array(n);
  const b = new Array(n);
  const set = (k, ca, cb) => {
    a[k] = ca;
    b[k] = cb === undefined ? ca : cb;
  };
  const longEnd = (from, level) => {
    const closer = ']' + '='.repeat(level) + ']';
    const k = text.indexOf(closer, from);
    return k < 0 ? n : k + closer.length;
  };
  let i = 0;
  while (i < n) {
    const c = text[i];
    if (c === '-' && text[i + 1] === '-') {
      const level = text[i + 2] === '[' ? longBracketLevel(text, i + 2) : -1;
      let end;
      if (level >= 0) {
        end = longEnd(i + 2 + level + 2, level);
      } else {
        const k = text.indexOf('\n', i);
        end = k < 0 ? n : k;
      }
      for (let k = i; k < end; k++) {
        set(k, keepBreak(text[k]));
      }
      i = end;
      continue;
    }
    if (c === '"' || c === "'") {
      set(i, c);
      i++;
      while (i < n && text[i] !== c && text[i] !== '\n') {
        if (text[i] === '\\' && i + 1 < n) {
          // An escape consumes the next char (CR LF together), so an escaped quote never ends it.
          const len = text[i + 1] === '\r' && text[i + 2] === '\n' ? 3 : 2;
          for (let k = i; k < i + len; k++) {
            set(k, text[k], keepBreak(text[k]));
          }
          i += len;
          continue;
        }
        set(i, text[i], ' ');
        i++;
      }
      if (i < n && text[i] === c) {
        set(i, c);
        i++;
      }
      continue;
    }
    if (c === '[') {
      const level = longBracketLevel(text, i);
      if (level >= 0) {
        const end = longEnd(i + level + 2, level);
        for (let k = i; k < end; k++) {
          set(k, text[k], keepBreak(text[k]));
        }
        i = end;
        continue;
      }
    }
    set(i, c);
    i++;
  }
  return { noComments: a.join(''), blank: b.join('') };
}

function lineAt(text, offset) {
  let line = 1;
  for (let k = text.indexOf('\n'); k >= 0 && k < offset; k = text.indexOf('\n', k + 1)) {
    line++;
  }
  return line;
}

// Offset of the paren or brace closing the one at `open`, or -1. Parens and braces share a depth.
function matchClose(blank, open) {
  let depth = 0;
  for (let k = open; k < blank.length; k++) {
    const ch = blank[k];
    if (ch === '(' || ch === '{') {
      depth++;
    } else if (ch === ')' || ch === '}') {
      depth--;
      if (depth === 0) {
        return k;
      }
    }
  }
  return -1;
}

// Top-level argument ranges [start, end) between from and to.
function splitArgs(blank, from, to) {
  const ranges = [];
  let depth = 0;
  let start = from;
  for (let k = from; k < to; k++) {
    const ch = blank[k];
    if (ch === '(' || ch === '{' || ch === '[') {
      depth++;
    } else if (ch === ')' || ch === '}' || ch === ']') {
      depth--;
    } else if (ch === ',' && depth === 0) {
      ranges.push([start, k]);
      start = k + 1;
    }
  }
  if (blank.slice(start, to).trim() !== '') {
    ranges.push([start, to]);
  }
  return ranges;
}

function integersIn(s) {
  return (s.match(/\b\d+\b/g) || []).map(Number);
}

// [start, end) spans of every `if ns.CLIENT_IS_FOREVER then ... end` block, found by keyword
// depth: function / if / do / repeat open, end / until close (for and while open through their do).
function foreverBlocks(blank, problems) {
  const spans = [];
  const open = /\bif\s+ns\.CLIENT_IS_FOREVER\s+then\b/g;
  let m;
  while ((m = open.exec(blank))) {
    const kw = /\b(function|if|do|repeat|end|until)\b/g;
    kw.lastIndex = m.index;
    let depth = 0;
    let end = -1;
    let k;
    while ((k = kw.exec(blank))) {
      depth += k[1] === 'end' || k[1] === 'until' ? -1 : 1;
      if (depth === 0) {
        end = k.index + k[0].length;
        break;
      }
    }
    if (end < 0) {
      problems.push(`Providers.lua line ${lineAt(blank, m.index)}: the Forever block never closes`);
      end = blank.length;
    }
    spans.push([m.index, end]);
    open.lastIndex = end;
  }
  return spans;
}

// --- code side -----------------------------------------------------------------------------------
function parseCode(text) {
  const { noComments, blank } = lexLua(text);
  const rawLines = text.split('\n');
  const problems = [];
  const rows = [];
  const groups = [];
  const blocks = foreverBlocks(blank, problems);

  const callRe = /\b(MetaReminderRow|MetaReminderGroup)\s*\(/g;
  let m;
  while ((m = callRe.exec(blank))) {
    const before = blank.slice(Math.max(0, m.index - 40), m.index);
    if (/\bfunction\s+$/.test(before) || /[.:]\s*$/.test(before)) {
      continue; // the local function definitions, or a field of the same name
    }
    const line = lineAt(text, m.index);
    const open = m.index + m[0].length - 1;
    const close = matchClose(blank, open);
    if (close < 0) {
      problems.push(`Providers.lua line ${line}: ${m[1]} call never closes`);
      continue;
    }
    callRe.lastIndex = close;
    const args = splitArgs(blank, open + 1, close);
    const argBlank = r => blank.slice(r[0], r[1]);

    if (m[1] === 'MetaReminderGroup') {
      const ids = integersIn(blank.slice(open + 1, close));
      if (ids.length === 0) {
        problems.push(`Providers.lua line ${line}: MetaReminderGroup names no ID`);
        continue;
      }
      const inForever = blocks.some(s => m.index >= s[0] && m.index < s[1]);
      groups.push({ ids, inForever, line });
      continue;
    }

    const idArg = args[0] && argBlank(args[0]).trim();
    const minArg = args[1] && argBlank(args[1]).trim();
    if (!/^\d+$/.test(idArg || '') || !/^\d+$/.test(minArg || '')) {
      problems.push(`Providers.lua line ${line}: MetaReminderRow needs an integer spell ID and minutes`);
      continue;
    }
    const row = {
      spellID: Number(idArg),
      minutes: Number(minArg),
      client: 'forever',
      auraID: null,
      useItems: [],
      cls: null,
      verified: 'yes',
      line,
    };
    if (args[5]) {
      const optsRaw = noComments.slice(args[5][0], args[5][1]);
      const optsBlank = argBlank(args[5]);
      if (/\bclient\s*=/.test(optsBlank)) {
        const cm = optsRaw.match(/\bclient\s*=\s*["'](\w*)["']/);
        const value = cm ? cm[1] : '?';
        if (!VALID_CLIENTS.has(value)) {
          problems.push(`row ${row.spellID} (line ${line}): client "${value}" is not forever, retail or both`);
          continue;
        }
        row.client = value;
      }
      const am = optsBlank.match(/\bauraID\s*=\s*(\d+)/);
      if (am) {
        row.auraID = Number(am[1]);
      }
      const um = /\buseItems\s*=\s*\{/.exec(optsBlank);
      if (um) {
        const uOpen = um.index + um[0].length - 1;
        const uClose = matchClose(optsBlank, uOpen);
        const inner = optsBlank.slice(uOpen + 1, uClose < 0 ? optsBlank.length : uClose);
        if (inner.includes('{')) {
          // { { itemID, minLevel }, ... }: only the FIRST number of each pair is an item ID.
          for (const pair of inner.match(/\{[^{}]*\}/g) || []) {
            const first = integersIn(pair)[0];
            if (first !== undefined) {
              row.useItems.push(first);
            }
          }
        } else {
          row.useItems = integersIn(inner);
        }
      }
    }
    // The trailing comment on the line holding the closing paren: "-- <Class>: <name> ...".
    const closeLine = lineAt(text, close);
    const lineStart = text.lastIndexOf('\n', close - 1) + 1;
    const tail = (rawLines[closeLine - 1] || '').slice(close - lineStart + 1);
    const cm = tail.match(/--\s*([A-Z][A-Za-z ]*?):/);
    if (!cm) {
      problems.push(`row ${row.spellID} (line ${line}) has no "-- <Class>: <name>" comment`);
      continue;
    }
    row.cls = cm[1];
    row.verified = /unverified/i.test(tail) ? 'unverified' : 'yes';
    rows.push(row);
  }
  return { rows, groups, problems };
}

function rowOn(row, client) {
  return row.client === 'both' || row.client === client;
}

function isRow(code, client, id) {
  return code.rows.some(r => r.spellID === id && rowOn(r, client));
}

function rowCountLine(code) {
  const count = c => code.rows.filter(r => r.client === c).length;
  return `CODE ROWS ${code.rows.length} (forever ${count('forever')}, retail ${count('retail')}, both ${count(
    'both'
  )}), GROUPS ${code.groups.length}`;
}

// { forever, retail }: Map of `spell:<id>` / `item:<id>` -> where the ID comes from; plus problems.
function codeSets(code) {
  const sets = { forever: new Map(), retail: new Map(), problems: [] };
  const add = (client, key, origin) => {
    if (!sets[client].has(key)) {
      sets[client].set(key, origin);
    }
  };
  for (const r of code.rows) {
    for (const c of CLIENTS.filter(c => rowOn(r, c))) {
      add(c, `spell:${r.spellID}`, `row ${r.spellID}`);
      if (r.auraID !== null) {
        add(c, `spell:${r.auraID}`, `auraID of ${r.spellID}`);
      }
      for (const item of r.useItems) {
        add(c, `item:${item}`, `useItems of ${r.spellID}`);
      }
    }
  }
  for (const g of code.groups) {
    const candidates = g.inForever ? ['forever'] : CLIENTS;
    const live = candidates.filter(c => g.ids.some(id => isRow(code, c, id)));
    if (live.length === 0) {
      sets.problems.push(
        `group ${g.ids[0]} names no row on ${g.inForever ? 'Forever' : 'any client'} (line ${g.line})`
      );
      continue;
    }
    for (const c of live) {
      const owner = g.ids.find(id => isRow(code, c, id));
      for (const id of g.ids) {
        add(c, `spell:${id}`, `group of ${owner}`);
      }
    }
  }
  return sets;
}

// --- doc side ------------------------------------------------------------------------------------
const SECTION_KEYS = { Forever: 'forever', Retail: 'retail', 'Not included': 'notIncluded' };
const LINK_RE = /https:\/\/www\.wowhead\.com\/([^\s)\]>"'<]*)/g;
const PATH_RE = /^(forever\/)?(spell|item)=(\d+)(?:[/#?]\S*)?$/;
const SEPARATOR_RE = /^\s*\|[\s:|-]*-[\s:|-]*$/;

function parseDoc(text) {
  const lines = text.split(/\r?\n/);
  const doc = {
    headings: [],
    links: { forever: new Map(), retail: new Map() },
    rows: { forever: new Map(), retail: new Map() },
    notIncludedLinks: [],
    problems: [],
  };
  let section = null;
  let cls = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const ln = i + 1;
    const h2 = line.match(/^## (?!#)(.*?)\s*$/);
    if (h2) {
      doc.headings.push(h2[1]);
      section = SECTION_KEYS[h2[1]] || 'other';
      cls = null;
      continue;
    }
    const h3 = line.match(/^### (.*?)\s*$/);
    if (h3) {
      cls = h3[1];
      continue;
    }

    let m;
    LINK_RE.lastIndex = 0;
    while ((m = LINK_RE.exec(line))) {
      const url = m[0];
      if (section === null) {
        doc.problems.push(`docs line ${ln}: link before the first "## " section: ${url}`);
        continue;
      }
      const pm = m[1].match(PATH_RE);
      if (!pm) {
        doc.problems.push(`docs line ${ln}: not a spell= or item= link (Forever or retail): ${url}`);
        continue;
      }
      const isForeverPath = pm[1] !== undefined;
      const key = `${pm[2]}:${pm[3]}`;
      if (section === 'notIncluded') {
        doc.notIncludedLinks.push({ kind: pm[2], id: Number(pm[3]), ln });
        continue;
      }
      if (section === 'other') {
        doc.problems.push(`docs line ${ln}: link outside Forever, Retail and Not included: ${url}`);
        continue;
      }
      if (section === 'forever' && !isForeverPath) {
        doc.problems.push(`docs line ${ln} (Forever): ${url} is a retail link, use ${W}forever/${m[1]}`);
      } else if (section === 'retail' && isForeverPath) {
        doc.problems.push(`docs line ${ln} (Retail): ${url} is a Forever link, use ${W}${m[1].slice(8)}`);
      }
      if (!doc.links[section].has(key)) {
        doc.links[section].set(key, ln);
      }
    }

    if (/^\s*\|/.test(line) && (section === 'forever' || section === 'retail')) {
      if (SEPARATOR_RE.test(line) || SEPARATOR_RE.test(lines[i + 1] || '')) {
        continue; // the separator, or the header line above it
      }
      const trimmed = line.trim();
      const cells = trimmed.split('|').slice(1, trimmed.endsWith('|') ? -1 : undefined).map(c => c.trim());
      if (!/^\d+$/.test(cells[1] || '')) {
        doc.problems.push(`docs line ${ln}: the second cell must be the Row ID, got "${cells[1] || ''}"`);
        continue;
      }
      const id = Number(cells[1]);
      if (doc.rows[section].has(id)) {
        doc.problems.push(`docs line ${ln}: Row ID ${id} listed twice in ${CLIENT_LABEL[section]}`);
        continue;
      }
      doc.rows[section].set(id, {
        cls,
        spellCell: cells[0],
        duration: cells[2],
        verified: cells[cells.length - 1],
        ln,
      });
    }
  }
  for (const name of Object.keys(SECTION_KEYS)) {
    if (!doc.headings.includes(name)) {
      doc.problems.push(`docs: missing "## ${name}" heading`);
    }
  }
  if (doc.headings.includes('Not included') && doc.headings[doc.headings.length - 1] !== 'Not included') {
    doc.problems.push('docs: "## Not included" must be the last "## " section');
  }
  return doc;
}

// --- comparison ----------------------------------------------------------------------------------
function compare(code, doc) {
  const sets = codeSets(code);
  const problems = [...code.problems, ...sets.problems, ...doc.problems];
  const reported = new Set();

  // Per client section, both ways.
  for (const c of CLIENTS) {
    const label = CLIENT_LABEL[c];
    for (const [key, origin] of sets[c]) {
      if (!doc.links[c].has(key)) {
        problems.push(`missing from docs (${label}): ${key} (${origin})`);
        reported.add(`doc ${key}`);
      }
    }
    for (const [key, ln] of doc.links[c]) {
      if (!sets[c].has(key)) {
        problems.push(`missing from Providers.lua (${label}): ${key} (docs line ${ln})`);
        reported.add(`code ${key}`);
      }
    }
  }

  // Overall, the stated contract checked directly; anything here is already reported above
  // unless the per-section check has a gap.
  const codeAll = new Set([...sets.forever.keys(), ...sets.retail.keys()]);
  const docAll = new Set([...doc.links.forever.keys(), ...doc.links.retail.keys()]);
  for (const key of codeAll) {
    if (!docAll.has(key) && !reported.has(`doc ${key}`)) {
      problems.push(`missing from docs: ${key}`);
    }
  }
  for (const key of docAll) {
    if (!codeAll.has(key) && !reported.has(`code ${key}`)) {
      problems.push(`missing from Providers.lua: ${key}`);
    }
  }

  for (const link of doc.notIncludedLinks) {
    if (link.kind === 'spell' && code.rows.some(r => r.spellID === link.id)) {
      problems.push(`row ${link.id} listed as not included (docs line ${link.ln})`);
    }
  }

  // Each row's table line, in each section of its client.
  for (const c of CLIENTS) {
    const label = CLIENT_LABEL[c];
    for (const r of code.rows.filter(row => rowOn(row, c))) {
      const d = doc.rows[c].get(r.spellID);
      if (!d) {
        problems.push(`row ${r.spellID} (${r.cls}) has no table line in ${label}`);
        continue;
      }
      if (d.cls !== r.cls) {
        problems.push(`row ${r.spellID} (docs line ${d.ln}) sits under "### ${d.cls}", expected "### ${r.cls}"`);
      }
      if (!new RegExp(`wowhead\\.com/(?:forever/)?spell=${r.spellID}(?!\\d)`).test(d.spellCell)) {
        problems.push(`row ${r.spellID} (docs line ${d.ln}): the Spell cell does not link ${r.spellID}`);
      }
      const duration = r.minutes === 0 ? 'permanent' : `${r.minutes} min`;
      if (d.duration !== duration) {
        problems.push(`row ${r.spellID} (docs line ${d.ln}): Duration "${d.duration}", expected "${duration}"`);
      }
      if (d.verified !== r.verified) {
        problems.push(`row ${r.spellID} (docs line ${d.ln}): Verified "${d.verified}", expected "${r.verified}"`);
      }
    }
    for (const [id, d] of doc.rows[c]) {
      if (!isRow(code, c, id)) {
        problems.push(`docs line ${d.ln}: Row ID ${id} is not a ${label} row`);
      }
    }
  }
  return problems;
}

// --- gate --------------------------------------------------------------------------------------
function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : null;
}

function readOrNull(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (e) {
    return null;
  }
}

function runGate() {
  const codePath = argValue('--code') || DEFAULT_CODE;
  const docPath = argValue('--doc') || DEFAULT_DOC;

  const codeText = readOrNull(codePath);
  if (codeText === null) {
    console.log(`FAIL cannot read ${codePath}`);
    process.exitCode = 1;
    return;
  }
  const code = parseCode(codeText);
  console.log(rowCountLine(code));

  const docText = readOrNull(docPath);
  if (docText === null) {
    console.log(`FAIL cannot read ${docPath}`);
    process.exitCode = 1;
    return;
  }
  const problems = compare(code, parseDoc(docText));
  for (const p of problems) {
    console.log(`FAIL ${p}`);
  }
  if (problems.length === 0) {
    const sets = codeSets(code);
    console.log(
      `REMINDERS-DOC CHECK PASS (${sets.forever.size} Forever IDs, ${sets.retail.size} retail IDs, ${code.rows.length} rows)`
    );
    process.exitCode = 0;
  } else {
    process.exitCode = 1;
  }
}

// --- --selftest: embedded fixtures and hard assertions ----------------------------------------
const W = 'https://www.wowhead.com/';

const LUA_FIXTURE = [
  '-- Header prose names 1038, 19979 and 20914; none of them is a row.',
  '--[[ MetaReminderGroup(1038, 19979) ]]',
  'local function MetaReminderRow(spellID, minutes, knownID, petBook, castID, opts)',
  '\tlocal tag = "a -- b"',
  'end',
  'local function MetaReminderGroup(...)',
  'end',
  'MetaReminderRow(1459, 60, nil, nil, nil, { client = "both" }) -- Mage: Arcane Intellect',
  'MetaReminderRow(7301, 30) -- Mage: Frost Armor (unverified in game)',
  'MetaReminderRow(1302303, 60, 1296017, nil, false, { useItems = { { 277493, 25 }, { 277483, 16 }, { 275069, 5 } } }) -- Mage: Familiar scroll; loads when 1296017 is known (unverified in game)',
  'MetaReminderRow(15473, 0) -- Priest: Shadowform (unverified in game)',
  '-- MetaReminderRow(1038, 60) -- Paladin: Blessing of Salvation',
  'MetaReminderRow(474750, 60, nil, nil, nil, { client = "retail", auraID = 474754, allyCast = true }) -- Druid: Symbiotic Relationship',
  'MetaReminderRow(465, 0, nil, nil, nil, { client = "retail" }) -- Paladin: Devotion Aura',
  'MetaReminderGroup(465, 317920, 32223)',
  'if ns.CLIENT_IS_FOREVER then',
  '\tMetaReminderGroup(1459, 1460, 23028)',
  '\tfor i = 1, 2 do',
  '\t\tlocal note = "x -- y"',
  '\tend',
  '\tMetaReminderGroup(',
  '\t\t7301,',
  '\t\t10220,',
  '\t\t22783',
  '\t)',
  '\tMetaReminderGroup(1302303, 1302285)',
  'end',
  '',
].join('\r\n');

const DOC_FIXTURE = [
  '# Built-in reminders',
  '',
  'Intro text with no links.',
  '',
  '## Forever',
  '',
  '### Mage',
  '',
  '| Spell | Row ID | Duration | Also satisfied by | Verified in game |',
  '|---|---|---|---|---|',
  `| [Arcane Intellect](${W}forever/spell=1459) | 1459 | 60 min | [1460](${W}forever/spell=1460), [23028](${W}forever/spell=23028) | yes |`,
  `| [Frost Armor](${W}forever/spell=7301) | 7301 | 30 min | [10220](${W}forever/spell=10220), [22783](${W}forever/spell=22783) | unverified |`,
  `| [Familiar](${W}forever/spell=1302303): [Cat](${W}forever/item=277493), [Frog](${W}forever/item=277483), [Rat](${W}forever/item=275069) | 1302303 | 60 min | [1302285](${W}forever/spell=1302285) | unverified |`,
  '',
  '### Priest',
  '',
  '| Spell | Row ID | Duration | Also satisfied by | Verified in game |',
  '|---|---|---|---|---|',
  `| [Shadowform](${W}forever/spell=15473) | 15473 | permanent | none | unverified |`,
  '',
  '## Retail',
  '',
  '### Mage',
  '',
  '| Spell | Row ID | Duration | Also satisfied by | Verified in game |',
  '|---|---|---|---|---|',
  `| [Arcane Intellect](${W}spell=1459) | 1459 | 60 min | none | yes |`,
  '',
  '### Druid',
  '',
  '| Spell | Row ID | Duration | Also satisfied by | Verified in game |',
  '|---|---|---|---|---|',
  `| [Symbiotic Relationship](${W}spell=474750) (watches aura [474754](${W}spell=474754)) | 474750 | 60 min | none | yes |`,
  '',
  '### Paladin',
  '',
  '| Spell | Row ID | Duration | Also satisfied by | Verified in game |',
  '|---|---|---|---|---|',
  `| [Devotion Aura](${W}spell=465) | 465 | permanent | [317920](${W}spell=317920), [32223](${W}spell=32223) | yes |`,
  '',
  '## Not included',
  '',
  '| Class | Candidate | Reason |',
  '|---|---|---|',
  `| Mage | [Molten Armor](${W}forever/spell=30482) | Not learnable on Forever. |`,
  '',
].join('\n');

function selftest() {
  let failures = 0;
  let caseCount = 0;

  function runCase(name, fn) {
    caseCount++;
    const msgs = [];
    const expect = (cond, msg) => {
      if (!cond) {
        msgs.push(msg);
      }
    };
    try {
      fn(expect);
    } catch (e) {
      msgs.push('threw: ' + (e && e.stack ? e.stack : e));
    }
    if (msgs.length) {
      console.log(`SELFTEST FAIL ${name}: ${msgs.join(' | ')}`);
      failures++;
    } else {
      console.log(`SELFTEST PASS ${name}`);
    }
  }

  const edit = (text, from, to) => {
    if (!text.includes(from)) {
      throw new Error(`fixture edit target not found: ${from}`);
    }
    return text.replace(from, to);
  };
  const check = (lua, doc) => compare(parseCode(lua), parseDoc(doc));
  const show = ps => (ps.length ? ps.join(' / ') : '(none)');
  // Exactly n problems, each one mentioning every given substring.
  const expectProblems = (expect, ps, n, ...subs) => {
    expect(ps.length === n, `expected ${n} problem(s), got ${ps.length}: ${show(ps)}`);
    for (const s of subs) {
      expect(
        ps.some(p => p.includes(s)),
        `no problem mentions "${s}": ${show(ps)}`
      );
    }
  };
  const expectSome = (expect, ps, ...subs) => {
    expect(ps.length >= 1, `expected a problem, got none`);
    for (const s of subs) {
      expect(
        ps.some(p => p.includes(s)),
        `no problem mentions "${s}": ${show(ps)}`
      );
    }
  };

  runCase('clean fixtures -> 0 problems', expect => {
    expectProblems(expect, check(LUA_FIXTURE, DOC_FIXTURE), 0);
  });

  runCase('comments, definitions and useItems minimum levels are never collected', expect => {
    const parsed = parseCode(LUA_FIXTURE);
    const sets = codeSets(parsed);
    const all = new Set([...sets.forever.keys(), ...sets.retail.keys()]);
    for (const id of [1038, 19979, 20914, 1296017, 25, 16, 5]) {
      expect(!all.has(`spell:${id}`) && !all.has(`item:${id}`), `${id} was collected`);
    }
    for (const id of [277493, 277483, 275069]) {
      expect(sets.forever.has(`item:${id}`), `item:${id} not collected`);
    }
    expect(parsed.rows.length === 6, `expected 6 rows, got ${parsed.rows.length}`);
    expect(parsed.groups.length === 4, `expected 4 groups, got ${parsed.groups.length}`);
    expect(
      rowCountLine(parsed) === 'CODE ROWS 6 (forever 3, retail 2, both 1), GROUPS 4',
      `row count line: ${rowCountLine(parsed)}`
    );
  });

  runCase('both row on both clients; Forever-block group Forever only; outside group retail only', expect => {
    const sets = codeSets(parseCode(LUA_FIXTURE));
    expect(sets.forever.has('spell:1459') && sets.retail.has('spell:1459'), '1459 not on both clients');
    expect(sets.forever.has('spell:1460') && !sets.retail.has('spell:1460'), '1460 not Forever-only');
    expect(sets.forever.has('spell:22783'), 'multi-line group member 22783 not collected');
    expect(sets.retail.has('spell:317920') && !sets.forever.has('spell:317920'), '317920 not retail-only');
    expect(sets.retail.has('spell:474754'), 'auraID 474754 not collected');
  });

  runCase('ID removed from the doc -> one "missing from docs" problem', expect => {
    const doc = edit(DOC_FIXTURE, `, [23028](${W}forever/spell=23028)`, '');
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'missing from docs (Forever): spell:23028');
  });

  runCase('extra ID linked in the doc -> one "missing from Providers.lua" problem', expect => {
    const doc = edit(DOC_FIXTURE, '| 30 min | [10220]', `| 30 min | [99999](${W}forever/spell=99999), [10220]`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'missing from Providers.lua (Forever): spell:99999');
  });

  runCase('retail-path link in Forever -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, `${W}forever/spell=23028`, `${W}spell=23028`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'spell=23028');
  });

  runCase('/forever/ link in Retail -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, `${W}spell=32223`, `${W}forever/spell=32223`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'spell=32223');
  });

  runCase('/classic/ link -> one problem, even under Not included', expect => {
    const doc = edit(DOC_FIXTURE, `${W}forever/spell=30482`, `${W}classic/spell=30482`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'classic/spell=30482');
  });

  runCase('useItems ID linked as spell= -> a problem', expect => {
    const doc = edit(DOC_FIXTURE, `${W}forever/item=277483`, `${W}forever/spell=277483`);
    expectSome(expect, check(LUA_FIXTURE, doc), 'item:277483');
  });

  runCase('Not included link to a non-row ID -> ignored', expect => {
    const doc = edit(DOC_FIXTURE, 'Not learnable on Forever. |', `Not learnable on Forever; see [12345](${W}forever/spell=12345). |`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 0);
  });

  runCase('Not included link to a row ID -> a problem', expect => {
    const doc = edit(DOC_FIXTURE, 'Not learnable on Forever. |', `Not learnable; [x](${W}forever/spell=7301). |`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 7301 listed as not included');
  });

  runCase('link in the intro -> a problem', expect => {
    const doc = edit(DOC_FIXTURE, 'Intro text with no links.', `Intro text, see [AI](${W}forever/spell=1459).`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'before the first');
  });

  for (const heading of ['Forever', 'Retail', 'Not included']) {
    runCase(`missing "## ${heading}" -> a problem`, expect => {
      const doc = edit(DOC_FIXTURE, `## ${heading}\n`, `## Renamed ${heading}\n`);
      expectSome(expect, check(LUA_FIXTURE, doc), `missing "## ${heading}"`);
    });
  }

  runCase('"## Not included" not last -> a problem', expect => {
    expectSome(expect, check(LUA_FIXTURE, DOC_FIXTURE + '## Notes\n\nMore.\n'), 'must be the last');
  });

  runCase('wrong Duration cell -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, '| 7301 | 30 min |', '| 7301 | 60 min |');
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 7301', 'Duration');
  });

  runCase('permanent row with a minutes Duration -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, '| 465 | permanent |', '| 465 | 0 min |');
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 465', 'Duration');
  });

  runCase('wrong Verified cell -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, '| 15473 | permanent | none | unverified |', '| 15473 | permanent | none | yes |');
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 15473', 'Verified');
  });

  runCase('row under the wrong ### class -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, '### Priest', '### Warlock');
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 15473', 'Priest');
  });

  runCase('Spell cell not linking the row ID -> one problem', expect => {
    const doc = edit(
      DOC_FIXTURE,
      `| [Shadowform](${W}forever/spell=15473) | 15473 | permanent | none |`,
      `| Shadowform | 15473 | permanent | [15473](${W}forever/spell=15473) |`
    );
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 15473', 'Spell cell');
  });

  runCase('row with no table line in a section of its client -> a problem', expect => {
    const doc = edit(DOC_FIXTURE, `| [Arcane Intellect](${W}spell=1459) | 1459 | 60 min | none | yes |\n`, '');
    expectSome(expect, check(LUA_FIXTURE, doc), 'row 1459', 'no table line in Retail');
  });

  runCase('table line for a row of another client -> a problem', expect => {
    const doc = edit(
      DOC_FIXTURE,
      `| [Shadowform](${W}forever/spell=15473)`,
      `| [Devotion Aura](${W}forever/spell=465) | 465 | permanent | none | yes |\n| [Shadowform](${W}forever/spell=15473)`
    );
    expectSome(expect, check(LUA_FIXTURE, doc), 'Row ID 465 is not a Forever row');
  });

  runCase('Row ID twice in one section -> a problem', expect => {
    const line = `| [Shadowform](${W}forever/spell=15473) | 15473 | permanent | none | unverified |`;
    const doc = edit(DOC_FIXTURE, line, `${line}\n${line}`);
    expectSome(expect, check(LUA_FIXTURE, doc), 'twice');
  });

  runCase('group with no registered row -> a problem', expect => {
    const lua = edit(LUA_FIXTURE, 'MetaReminderGroup(465, 317920, 32223)', 'MetaReminderGroup(465, 317920, 32223)\r\nMetaReminderGroup(55555, 55556)');
    expectProblems(expect, check(lua, DOC_FIXTURE), 1, 'group 55555 names no row');
  });

  runCase('row with no class comment -> a problem', expect => {
    const lua = edit(LUA_FIXTURE, 'MetaReminderRow(15473, 0) -- Priest: Shadowform (unverified in game)', 'MetaReminderRow(15473, 0)');
    expectSome(expect, check(lua, DOC_FIXTURE), 'row 15473', 'comment');
  });

  runCase('unknown client value -> a problem', expect => {
    const lua = edit(LUA_FIXTURE, '{ client = "retail" }) -- Paladin', '{ client = "classic" }) -- Paladin');
    expectSome(expect, check(lua, DOC_FIXTURE), 'client "classic"');
  });

  if (failures === 0) {
    console.log(`REMINDERS-DOC SELFTEST PASS (${caseCount} cases)`);
    process.exitCode = 0;
  } else {
    console.log(`REMINDERS-DOC SELFTEST FAIL (${failures}/${caseCount} cases failed)`);
    process.exitCode = 1;
  }
}

// --- CLI ---------------------------------------------------------------------------------------
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  runGate();
}
