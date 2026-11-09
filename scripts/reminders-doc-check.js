// DOC-07: docs/REMINDERS.md is the human-review list of every built-in reminder. This check proves
// that the doc and the reminder table in Providers.lua name the same IDs per client (and so
// overall, since every ID belongs to a client), and that each row's "Also satisfied by" cell is the
// group the row is really in, so the doc cannot drift from the code without the check going red.
//
//   node scripts/reminders-doc-check.js              -- check Providers.lua against docs/REMINDERS.md,
//                                                       exit 1 on any mismatch
//   node scripts/reminders-doc-check.js --selftest   -- run the checker against embedded fixtures
//   --code <path> / --doc <path>                     -- read another file instead (for gates)
//   any other argument, or --code / --doc with no value, exits 2 without checking anything.
//
// Code side: every MetaReminderRow first argument, auraID and useItems item ID, and every
// MetaReminderGroup ID. Comments are stripped first, so an ID named in prose (the retired-blessings
// note) is never counted. A row's client is its opts.client ("forever" when absent); a group
// directly inside the `if ns.CLIENT_IS_FOREVER then ... end` block counts on Forever only, a group
// at file top level counts on every client where one of its IDs is a row. Anything this cannot
// classify fails rather than being guessed: a group in any other block (another if, a function, a
// loop), an else / elseif branch on the Forever block, a row not at file top level, and a group,
// auraID or useItems value that is not an integer literal. A second row for the same ID on an
// overlapping client fails, and so does a row named by two groups on one client (at runtime the
// later group REPLACES the earlier one's alternatives).
//
// Doc side: every wowhead link under `## Forever` and `## Retail`. Forever links must be
// /forever/spell= or /forever/item=, retail links spell= or item=; any other path fails. Links
// under `## Not included` are not collected, but one to a row ID fails. Each row also needs a table
// line in its section, under its class, with the right Duration, Verified and "Also satisfied by"
// cells. "Also satisfied by" must link exactly the other IDs of the row's group, say `none` when
// the row has no group, or say `<Name> group, below` when a `**<Name> group**` paragraph under the
// same class links the group's IDs (the row's own ID may be linked there or not).
//
// Known limits (static text, not a Lua evaluator): a row or group built at runtime (a loop, a
// variable holding an ID) cannot be seen. The row's class and verified status are read from its
// trailing `-- <Class>: <name>` comment, which is a convention, not code.
//
// Verified (review WR-06): a row is `unverified` when its trailing comment contains the word
// "unverified" anywhere, and `yes` otherwise. The rule is kept on purpose, so read it as a contract
// on the comments: every new row MUST carry "(unverified in game)" until someone checks it in game,
// and no row comment may use the word for anything else ("was unverified until ..." flips a
// verified row). Whether a `yes` row really was checked in game (it predates v0.5.6) is not in the
// code at all, so this check cannot prove it; the human review pass owns that.
const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');

const ROOT = path.join(__dirname, '..');
const DEFAULT_CODE = path.join(ROOT, 'Providers.lua');
const DEFAULT_DOC = path.join(ROOT, 'docs', 'REMINDERS.md');

const CLIENTS = ['forever', 'retail'];
const CLIENT_LABEL = { forever: 'Forever', retail: 'Retail' };
const VALID_CLIENTS = new Set(['forever', 'retail', 'both']);
const W = 'https://www.wowhead.com/';

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

// Every block in the file as { start, end, forever, branchAt }, found by keyword depth: function /
// if / do / repeat open, end / until close (for and while open through their do; `elseif` never
// matches \bif\b). Only the exact `if ns.CLIENT_IS_FOREVER then` opener is a Forever block; any other
// gate (`== true`, `not`, a local alias) is an ordinary if, so a group under it is reported as
// unclassifiable instead of being counted on every client. branchAt is the offset of the Forever
// block's first else / elseif: a call after it runs on the OTHER client, so it is never Forever.
const FOREVER_IF_RE = /if\s+ns\.CLIENT_IS_FOREVER\s+then\b/y;

function luaBlocks(blank, problems) {
  const blocks = [];
  const stack = [];
  const kw = /\b(function|if|do|repeat|end|until|else|elseif)\b/g;
  let k;
  while ((k = kw.exec(blank))) {
    const word = k[1];
    if (word === 'end' || word === 'until') {
      const b = stack.pop();
      if (!b) {
        problems.push(`Providers.lua line ${lineAt(blank, k.index)}: "${word}" closes no block`);
        continue;
      }
      b.end = k.index + word.length;
      blocks.push(b);
    } else if (word === 'else' || word === 'elseif') {
      const b = stack[stack.length - 1];
      if (b && b.forever && b.branchAt === null) {
        b.branchAt = k.index;
        problems.push(
          `Providers.lua line ${lineAt(blank, k.index)}: the Forever block has an ${word} branch; ` +
            'a group there runs on the other client, which this check cannot classify'
        );
      }
    } else {
      FOREVER_IF_RE.lastIndex = k.index;
      stack.push({ start: k.index, end: blank.length, forever: word === 'if' && FOREVER_IF_RE.test(blank), branchAt: null });
    }
  }
  for (const b of stack) {
    problems.push(`Providers.lua line ${lineAt(blank, b.start)}: a block opened here never closes`);
    blocks.push(b);
  }
  return blocks;
}

// Where a call at `offset` runs: 'top' (file top level), 'forever' (directly in the Forever block,
// before any else branch), or null (anywhere else, which this check cannot classify).
function placement(blocks, offset) {
  const around = blocks.filter(b => offset > b.start && offset < b.end);
  if (around.length === 0) {
    return 'top';
  }
  const b = around[0];
  if (around.length === 1 && b.forever && (b.branchAt === null || offset < b.branchAt)) {
    return 'forever';
  }
  return null;
}

function overlaps(a, b) {
  return a === b || a === 'both' || b === 'both';
}

// --- code side -----------------------------------------------------------------------------------
function parseCode(text) {
  const { noComments, blank } = lexLua(text);
  const rawLines = text.split('\n');
  const problems = [];
  const rows = [];
  const groups = [];
  const blocks = luaBlocks(blank, problems);

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
    const where = placement(blocks, m.index);

    if (m[1] === 'MetaReminderGroup') {
      if (where === null) {
        problems.push(
          `Providers.lua line ${line}: MetaReminderGroup sits in a block other than the Forever block's ` +
            'main branch (another if, a function, a loop, an else), so its client cannot be classified'
        );
        continue;
      }
      // Every argument must be a decimal literal: an identifier or a hex literal would be a member
      // the runtime has and this check cannot see.
      const ids = [];
      for (const r of args) {
        const a = argBlank(r).trim();
        if (/^\d+$/.test(a)) {
          ids.push(Number(a));
        } else {
          problems.push(
            `Providers.lua line ${line}: MetaReminderGroup argument "${noComments.slice(r[0], r[1]).trim()}" is not an integer literal`
          );
        }
      }
      if (ids.length === 0) {
        problems.push(`Providers.lua line ${line}: MetaReminderGroup names no ID`);
        continue;
      }
      groups.push({ ids, inForever: where === 'forever', line });
      continue;
    }

    if (where !== 'top') {
      problems.push(`Providers.lua line ${line}: MetaReminderRow is not at file top level, so its client cannot be classified`);
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
      if (/\bauraID\s*=/.test(optsBlank)) {
        const am = optsBlank.match(/\bauraID\s*=\s*(\d+)\s*(?=[,;}])/);
        if (am) {
          row.auraID = Number(am[1]);
        } else {
          problems.push(`row ${row.spellID} (line ${line}): auraID is not an integer literal`);
        }
      }
      if (/\buseItems\s*=/.test(optsBlank)) {
        const um = /\buseItems\s*=\s*\{/.exec(optsBlank);
        const uOpen = um ? um.index + um[0].length - 1 : -1;
        const uClose = um ? matchClose(optsBlank, uOpen) : -1;
        if (uClose < 0) {
          problems.push(`row ${row.spellID} (line ${line}): useItems is not a table literal`);
        } else {
          // { itemID, ... } or { { itemID, minLevel }, ... }: only the FIRST value of a pair is an
          // item ID, and each one must be an integer literal.
          for (const [s, e] of splitArgs(optsBlank, uOpen + 1, uClose)) {
            const pair = optsBlank.slice(s, e).trim().match(/^\{([^{}]*)\}$/);
            const item = pair ? pair[1].split(',')[0].trim() : optsBlank.slice(s, e).trim();
            if (/^\d+$/.test(item)) {
              row.useItems.push(Number(item));
            } else {
              problems.push(
                `row ${row.spellID} (line ${line}): useItems entry "${optsRaw.slice(s, e).trim()}" has no integer literal item ID`
              );
            }
          }
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
    // See the header (WR-06): the word anywhere in the comment makes the row unverified.
    row.verified = /unverified/i.test(tail) ? 'unverified' : 'yes';
    // A second row for the same ID on an overlapping client appends a second def, and the later
    // one wins at runtime; report that instead of the misleading cell mismatches it would cause.
    const dup = rows.find(r => r.spellID === row.spellID && overlaps(r.client, row.client));
    if (dup) {
      problems.push(
        `row ${row.spellID} (line ${line}) duplicates the row at line ${dup.line} on an overlapping client; the later one wins at runtime`
      );
      continue;
    }
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

// { forever, retail }: Map of `spell:<id>` / `item:<id>` -> where the ID comes from; groupOf, per
// client, the group that sets each row's alternatives at runtime (the LAST one naming it); problems.
function codeSets(code) {
  const sets = {
    forever: new Map(),
    retail: new Map(),
    groupOf: { forever: new Map(), retail: new Map() },
    problems: [],
  };
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
      // MetaReminderGroup overwrites def.alternatives, so a row named by a second group on the same
      // client silently loses the first group's members.
      for (const id of g.ids.filter(x => isRow(code, c, x))) {
        const prev = sets.groupOf[c].get(id);
        if (prev) {
          sets.problems.push(
            `row ${id} is named by the groups at lines ${prev.line} and ${g.line} on ${CLIENT_LABEL[c]}; ` +
              'the later one REPLACES the earlier one at runtime'
          );
        }
        sets.groupOf[c].set(id, g);
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
    // `<class>|<name>` -> { links: Set of keys, ln } for each "**<name> group**" paragraph.
    groupParas: { forever: new Map(), retail: new Map() },
    notIncludedLinks: [],
    problems: [],
  };
  let section = null;
  let cls = null;
  let para = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const ln = i + 1;
    const h2 = line.match(/^## (?!#)(.*?)\s*$/);
    if (h2) {
      doc.headings.push(h2[1]);
      section = SECTION_KEYS[h2[1]] || 'other';
      cls = null;
      para = null;
      continue;
    }
    const h3 = line.match(/^### (.*?)\s*$/);
    if (h3) {
      cls = h3[1];
      para = null;
      continue;
    }
    if (line.trim() === '') {
      para = null;
      continue;
    }
    const gp = line.match(/^\*\*(.+?) group\*\*/);
    if (gp && (section === 'forever' || section === 'retail')) {
      const pkey = `${cls}|${gp[1]}`;
      if (doc.groupParas[section].has(pkey)) {
        doc.problems.push(`docs line ${ln}: "${gp[1]} group" paragraph twice under ### ${cls}`);
      }
      para = { links: new Set(), ln };
      doc.groupParas[section].set(pkey, para);
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
      if (para) {
        para.links.add(key);
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
      const altCell = cells[3] || '';
      const altLinks = new Set();
      for (const am of altCell.matchAll(LINK_RE)) {
        const pm = am[1].match(PATH_RE);
        if (pm) {
          altLinks.add(`${pm[2]}:${pm[3]}`);
        }
      }
      doc.rows[section].set(id, {
        cls,
        spellCell: cells[0],
        duration: cells[2],
        altCell,
        altLinks,
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
function keyList(keys) {
  const ids = [...keys].map(k => k.replace(/^spell:/, '')).sort((a, b) => a.localeCompare(b, 'en', { numeric: true }));
  return ids.length ? ids.join(', ') : 'none';
}

// Why a row's "Also satisfied by" cell is not the row's runtime group, or null when it is. The
// expected set is the other IDs of the group naming the row on this client (empty: no group).
function alternativesProblem(r, d, groupOf, groupParas) {
  const g = groupOf.get(r.spellID);
  const expected = new Set(g ? g.ids.filter(id => id !== r.spellID).map(id => `spell:${id}`) : []);
  let got;
  const ref = d.altCell.match(/^(.+) group, below$/);
  if (ref) {
    const para = groupParas.get(`${d.cls}|${ref[1]}`);
    if (!para) {
      return `names the "${ref[1]} group", but no "**${ref[1]} group**" paragraph follows under ### ${d.cls}`;
    }
    got = new Set([...para.links].filter(k => k !== `spell:${r.spellID}`));
  } else if (d.altCell === 'none') {
    got = new Set();
  } else if (d.altLinks.size === 0) {
    return `is "${d.altCell}"; write none, link the alternatives, or name a group below`;
  } else {
    got = d.altLinks;
  }
  if (got.size === expected.size && [...got].every(k => expected.has(k))) {
    return null;
  }
  return `links ${keyList(got)}, expected ${keyList(expected)}${g ? ` (group at Providers.lua line ${g.line})` : ''}`;
}

function compare(code, doc) {
  const sets = codeSets(code);
  const problems = [...code.problems, ...sets.problems, ...doc.problems];

  // Per client section, both ways. This also covers the overall contract: every code ID belongs to
  // a client's set and every doc link to a client's section, so an overall gap is a section gap.
  for (const c of CLIENTS) {
    const label = CLIENT_LABEL[c];
    for (const [key, origin] of sets[c]) {
      if (!doc.links[c].has(key)) {
        problems.push(`missing from docs (${label}): ${key} (${origin})`);
      }
    }
    for (const [key, ln] of doc.links[c]) {
      if (!sets[c].has(key)) {
        problems.push(`missing from Providers.lua (${label}): ${key} (docs line ${ln})`);
      }
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
      const altProblem = alternativesProblem(r, d, sets.groupOf[c], doc.groupParas[c]);
      if (altProblem) {
        problems.push(`row ${r.spellID} (docs line ${d.ln}): "Also satisfied by" ${altProblem}`);
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
// { selftest, code, doc, error }. A typo'd flag or a --code / --doc with no value is an error, never
// a silent fall-back to the default gate: a plan gate meant to run something else must not PASS.
function parseArgs(argv) {
  const opts = { selftest: false, code: null, doc: null, error: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--selftest') {
      opts.selftest = true;
    } else if (a === '--code' || a === '--doc') {
      const value = argv[i + 1];
      if (value === undefined || value.startsWith('--')) {
        opts.error = `${a} needs a path`;
        return opts;
      }
      opts[a.slice(2)] = value;
      i++;
    } else {
      opts.error = `unknown argument "${a}"`;
      return opts;
    }
  }
  return opts;
}

function readOrNull(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (e) {
    return null;
  }
}

function runGate(cli) {
  const codePath = cli.code || DEFAULT_CODE;
  const docPath = cli.doc || DEFAULT_DOC;

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
  'MetaReminderRow(10170, 10) -- Mage: Amplify Magic (unverified in game)',
  'MetaReminderRow(10174, 10) -- Mage: Dampen Magic (unverified in game)',
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
  '\tMetaReminderGroup(10170, 10174, 1008)',
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
  `| [Amplify Magic](${W}forever/spell=10170) | 10170 | 10 min | Amplify and Dampen group, below | unverified |`,
  `| [Dampen Magic](${W}forever/spell=10174) | 10174 | 10 min | Amplify and Dampen group, below | unverified |`,
  '',
  `**Amplify and Dampen group** (any one up hides both): [10170](${W}forever/spell=10170),`,
  `[10174](${W}forever/spell=10174), [1008](${W}forever/spell=1008).`,
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
    expect(parsed.rows.length === 8, `expected 8 rows, got ${parsed.rows.length}`);
    expect(parsed.groups.length === 5, `expected 5 groups, got ${parsed.groups.length}`);
    expect(
      rowCountLine(parsed) === 'CODE ROWS 8 (forever 5, retail 2, both 1), GROUPS 5',
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

  runCase('ID removed from the doc -> "missing from docs" and the row\'s alternatives cell', expect => {
    const doc = edit(DOC_FIXTURE, `, [23028](${W}forever/spell=23028)`, '');
    expectProblems(expect, check(LUA_FIXTURE, doc), 2, 'missing from docs (Forever): spell:23028', 'row 1459');
  });

  runCase('extra ID linked in the doc -> one "missing from Providers.lua" problem', expect => {
    const doc = edit(
      DOC_FIXTURE,
      `| [Frost Armor](${W}forever/spell=7301) |`,
      `| [Frost Armor](${W}forever/spell=7301), see [99999](${W}forever/spell=99999) |`
    );
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
      `| [Shadowform](${W}forever/spell=15473) | 15473 | permanent | none | unverified |`,
      `| Shadowform | 15473 | permanent | none | unverified |\n\nShadowform is [15473](${W}forever/spell=15473).`
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

  // WR-01: a row named by two groups on one client.
  runCase('row in two groups on one client -> a "REPLACES" problem', expect => {
    const lua = edit(LUA_FIXTURE, '\tMetaReminderGroup(1302303, 1302285)', '\tMetaReminderGroup(1302303, 1302285)\r\n\tMetaReminderGroup(7301, 1302285)');
    expectSome(expect, check(lua, DOC_FIXTURE), 'row 7301 is named by the groups', 'REPLACES');
  });

  // WR-02: the "Also satisfied by" cell against the row's group.
  runCase('alternative moved into another row\'s cell -> a problem for both rows', expect => {
    let doc = edit(DOC_FIXTURE, `, [23028](${W}forever/spell=23028)`, '');
    doc = edit(doc, '| 30 min | [10220]', `| 30 min | [23028](${W}forever/spell=23028), [10220]`);
    expectProblems(expect, check(LUA_FIXTURE, doc), 2, 'row 1459', 'row 7301', 'Also satisfied by');
  });

  runCase('"none" on a grouped row -> a problem', expect => {
    const doc = edit(DOC_FIXTURE, `| 60 min | [1302285](${W}forever/spell=1302285) |`, '| 60 min | none |');
    expectSome(expect, check(LUA_FIXTURE, doc), 'row 1302303', 'Also satisfied by');
  });

  runCase('wrong "group, below" reference -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, '| 10174 | 10 min | Amplify and Dampen group, below |', '| 10174 | 10 min | Blessings group, below |');
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 10174', 'Blessings group');
  });

  runCase('group paragraph missing a member -> a problem for its rows', expect => {
    const doc = edit(DOC_FIXTURE, `, [1008](${W}forever/spell=1008)`, '');
    expectSome(expect, check(LUA_FIXTURE, doc), 'row 10170', 'row 10174', 'Also satisfied by');
  });

  runCase('empty alternatives cell -> one problem', expect => {
    const doc = edit(DOC_FIXTURE, '| 15473 | permanent | none |', '| 15473 | permanent |  |');
    expectProblems(expect, check(LUA_FIXTURE, doc), 1, 'row 15473', 'write none');
  });

  // WR-03: gating the check cannot classify fails loudly.
  for (const branch of ['else', 'elseif ns.SOMETHING then']) {
    runCase(`"${branch.split(' ')[0]}" branch on the Forever block -> a problem`, expect => {
      const lua = edit(
        LUA_FIXTURE,
        '\tMetaReminderGroup(10170, 10174, 1008)\r\nend',
        `\tMetaReminderGroup(10170, 10174, 1008)\r\n${branch}\r\n\tMetaReminderGroup(465, 317920)\r\nend`
      );
      expectSome(expect, check(lua, DOC_FIXTURE), `${branch.split(' ')[0]} branch`, 'cannot be classified');
    });
  }

  runCase('"if ns.CLIENT_IS_FOREVER == true then" -> its groups cannot be classified', expect => {
    const lua = edit(LUA_FIXTURE, 'if ns.CLIENT_IS_FOREVER then', 'if ns.CLIENT_IS_FOREVER == true then');
    expectSome(expect, check(lua, DOC_FIXTURE), 'cannot be classified');
  });

  runCase('group under "if not ns.CLIENT_IS_FOREVER" -> cannot be classified', expect => {
    const lua = edit(
      LUA_FIXTURE,
      'MetaReminderGroup(465, 317920, 32223)\r\n',
      'if not ns.CLIENT_IS_FOREVER then\r\n\tMetaReminderGroup(465, 317920, 32223)\r\nend\r\n'
    );
    expectSome(expect, check(lua, DOC_FIXTURE), 'cannot be classified');
  });

  runCase('Forever gate through a local alias -> cannot be classified', expect => {
    const lua = edit(LUA_FIXTURE, 'if ns.CLIENT_IS_FOREVER then', 'local isForever = ns.CLIENT_IS_FOREVER\r\nif isForever then');
    expectSome(expect, check(lua, DOC_FIXTURE), 'cannot be classified');
  });

  // WR-04: values the check cannot read.
  for (const bad of ['CRUSADER', '0x7DDF']) {
    runCase(`group argument ${bad} -> a problem`, expect => {
      const lua = edit(LUA_FIXTURE, 'MetaReminderGroup(465, 317920, 32223)', `MetaReminderGroup(465, 317920, ${bad})`);
      expectSome(expect, check(lua, DOC_FIXTURE), `"${bad}" is not an integer literal`);
    });
  }

  runCase('non-literal auraID -> a problem', expect => {
    const lua = edit(LUA_FIXTURE, 'auraID = 474754', 'auraID = SYMBIOSIS_AURA');
    expectSome(expect, check(lua, DOC_FIXTURE), 'row 474750', 'auraID is not an integer literal');
  });

  runCase('non-literal useItems table -> a problem', expect => {
    const lua = edit(LUA_FIXTURE, 'useItems = { { 277493, 25 }, { 277483, 16 }, { 275069, 5 } }', 'useItems = SCROLLS');
    expectSome(expect, check(lua, DOC_FIXTURE), 'row 1302303', 'useItems is not a table literal');
  });

  runCase('non-literal useItems item ID -> a problem', expect => {
    const lua = edit(LUA_FIXTURE, '{ 277493, 25 }', '{ CAT_SCROLL, 25 }');
    expectSome(expect, check(lua, DOC_FIXTURE), 'CAT_SCROLL');
  });

  // WR-07: duplicate rows.
  runCase('second row for the same ID and client -> one "duplicates" problem', expect => {
    const row = 'MetaReminderRow(15473, 0) -- Priest: Shadowform (unverified in game)';
    const lua = edit(LUA_FIXTURE, row, `${row}\r\nMetaReminderRow(15473, 60) -- Priest: Shadowform (unverified in game)`);
    expectProblems(expect, check(lua, DOC_FIXTURE), 1, 'row 15473', 'duplicates');
  });

  runCase('retail row for a "both" row\'s ID -> one "duplicates" problem', expect => {
    const lua = edit(
      LUA_FIXTURE,
      'MetaReminderRow(7301, 30)',
      'MetaReminderRow(1459, 60, nil, nil, nil, { client = "retail" }) -- Mage: Arcane Intellect\r\nMetaReminderRow(7301, 30)'
    );
    expectProblems(expect, check(lua, DOC_FIXTURE), 1, 'row 1459', 'duplicates');
  });

  // WR-05: argument parsing, and the exit codes of the real process.
  runCase('arguments: unknown flag and valueless --code / --doc are errors', expect => {
    expect(/--selftst/.test(parseArgs(['--selftst']).error || ''), 'typo flag not rejected');
    expect(/--code needs a path/.test(parseArgs(['--code']).error || ''), 'valueless --code not rejected');
    expect(/--code needs a path/.test(parseArgs(['--code', '--doc', 'x.md']).error || ''), '--code followed by a flag not rejected');
    expect(/unknown argument "stray"/.test(parseArgs(['stray']).error || ''), 'stray positional not rejected');
    const ok = parseArgs(['--doc', 'a.md', '--code', 'b.lua']);
    expect(ok.error === null && ok.doc === 'a.md' && ok.code === 'b.lua' && !ok.selftest, `valid args: ${JSON.stringify(ok)}`);
  });

  runCase('process: a typo flag exits 2 without PASS; an unreadable file exits 1', expect => {
    const run = args => childProcess.spawnSync(process.execPath, [__filename, ...args], { encoding: 'utf8' });
    const typo = run(['--selftst']);
    expect(typo.status === 2, `typo flag exit ${typo.status}`);
    expect(!/PASS/.test(typo.stdout), `typo flag printed PASS: ${typo.stdout}`);
    const missing = run(['--code', path.join(ROOT, 'no-such-file.lua')]);
    expect(missing.status === 1, `unreadable file exit ${missing.status}`);
    expect(/FAIL cannot read/.test(missing.stdout), `unreadable file output: ${missing.stdout}`);
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
const cli = parseArgs(process.argv.slice(2));
if (cli.error) {
  console.log(`USAGE ERROR ${cli.error}; expected [--selftest] [--code <path>] [--doc <path>]`);
  process.exitCode = 2;
} else if (cli.selftest) {
  selftest();
} else {
  runGate(cli);
}
