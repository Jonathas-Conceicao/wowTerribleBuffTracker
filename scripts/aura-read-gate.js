// DTRK-06 static proof: an aura TBT cannot read must never be treated as absent. The one reader
// that guarantees this is ns:ReadPlayerAura (BuffEngine.lua) -- it asks
// C_Secrets.ShouldSpellAuraBeSecret FIRST, and only reads C_UnitAuras.GetPlayerAuraBySpellID when
// the predicate says the read is safe. This gate proves STATICALLY that every reference to an aura
// API in the shipped Lua sits inside one of the three allowlisted readers, so Phase 56's aura-ID
// path and Phase 57's aura-state cache cannot bypass it without the gate going red.
//
//   node scripts/aura-read-gate.js              -- scan the shipped TOC file list, exit 1 on any
//                                                   bypass or a broken predicate order
//   node scripts/aura-read-gate.js --selftest    -- run the scanner against embedded fixtures
//
// Adding a reader to the allowlist below is a reviewed decision, not a fix for a failing gate --
// it widens the set of places that are trusted to hold a secret aura correctly. Each allowlist row
// carries a one-line reason so that decision is visible in the diff that adds it.
//
// The other two readers (Core.lua's CollectPlayerBuffs, MergeMode.lua's TryResolveFromSpellID)
// are not gated the same way ns:ReadPlayerAura is -- CollectPlayerBuffs is the out-of-combat
// Suggested catalogue scan and never decides a tracker's end; TryResolveFromSpellID is Merge
// Mode's duration resolution, itself gated by ShouldSpellAuraBeSecret at MergeMode.lua ~625. Only
// ns:ReadPlayerAura's predicate-then-read order is asserted directly (see checkPredicateOrder).
//
// Known limits (static text, not a Lua evaluator): an API name assembled at runtime (a string
// concatenation, or a name held in a variable and used as `_G[name]`) cannot be seen. Everything
// that NAMES an aura API in code -- a dotted or bracketed member, an alias of the namespace, a bare
// global, a string-literal index into a table -- is flagged.
const fs = require('fs');
const path = require('path');

// --- detection -----------------------------------------------------------------------------
// Run against CODE only: comments removed and string-literal contents blanked (see lexLua), so a
// comment or a chat string that names an API is never a hit, and a " --" inside a string can never
// hide the read that follows it on the same line.
//
// \bC_UnitAuras\b flags the namespace itself, not only a dotted call: an alias
// (`local UA = C_UnitAuras`), a bracket index (`C_UnitAuras["GetPlayerAuraBySpellID"]`), a spaced
// member (`C_UnitAuras . X`) and a function passed by value (MergeMode.lua's
// SafeAuraCall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)) all contain it. The shipped tree only
// names C_UnitAuras outside the three readers in comments.
//
// The bare names cover the old globals (UnitAura/UnitBuff/UnitDebuff and the slot APIs), the
// namespace's members reached any other way, and C_TooltipInfo's aura tooltips, which carry the
// same aura data, and AuraUtil's aura walkers. Word boundaries keep ns:OnUnitAura (no boundary
// before "Unit") out of it.
const AURA_NAMES =
  'Unit(?:Aura|Buff|Debuff)\\w*' +
  '|Get(?:Player|Unit)Aura\\w*' +
  '|GetAuraDataBy\\w+' +
  '|GetAuraSlots' +
  '|Get(?:Buff|Debuff)DataBy\\w+' +
  '|GetCooldownAuraBySpellID' +
  '|GetUnit(?:Buff|Debuff)' +
  '|ForEachAura|FindAura\\w*|UnpackAuraData';
const DETECT_RE = new RegExp('\\bC_UnitAuras\\b|\\b(?:' + AURA_NAMES + ')\\b');
// A string literal used as an index or a rawget key reaches a global or a member with no
// identifier in the code at all: `_G["UnitAura"]`, `AuraUtil["ForEachAura"]`,
// `rawget(_G, "C_UnitAuras")`. Checked against the code WITH strings kept. A string that is merely
// a value (Core.lua's `{ "UnitAura", "UnitBuff", "UnitDebuff" }`, Enum.TooltipDataType member
// names) is not an index and is not flagged.
const STRING_INDEX_RE = new RegExp(
  '(?:\\[\\s*|\\brawget\\s*\\(\\s*[\\w.]+\\s*,\\s*)(["\'])(?:C_UnitAuras|AuraUtil|' + AURA_NAMES + ')\\1'
);

// Exact file + enclosing-function pairs trusted to hold a direct aura read.
const ALLOWLIST = [
  {
    file: 'BuffEngine.lua',
    func: 'ns:ReadPlayerAura',
    reason: 'the gated reader -- asks C_Secrets.ShouldSpellAuraBeSecret before any read',
  },
  {
    file: 'Core.lua',
    func: 'CollectPlayerBuffs',
    reason: 'out-of-combat Suggested catalogue scan, never decides a tracker\'s end',
  },
  {
    file: 'MergeMode.lua',
    func: 'TryResolveFromSpellID',
    reason: 'Merge Mode duration resolution, gated by ShouldSpellAuraBeSecret at MergeMode.lua ~625',
  },
];

function isAllowed(file, func) {
  return ALLOWLIST.some(a => a.file === file && a.func === func);
}

// --- lexer -----------------------------------------------------------------------------------
// A small Lua lexer, just enough to tell code from comments and strings. Returns one entry per
// source line, { code, withStrings }:
//   code         comments removed, every string literal's CONTENT replaced by spaces (the quotes
//                or long brackets stay), so identifier hits come from code alone
//   withStrings  comments removed, strings intact -- for STRING_INDEX_RE
// Handles "--" line comments, --[[ ]] / --[==[ ]==] block comments, '...' and "..." with
// backslash escapes, and [[ ]] / [==[ ]==] long strings, all across lines. Newlines are always
// kept, so line numbers match the source.
function longBracketLevel(text, i) {
  // text[i] is "[": returns the level of a long bracket opener starting here, or -1.
  let j = i + 1;
  while (text[j] === '=') {
    j++;
  }
  return text[j] === '[' ? j - i - 1 : -1;
}

function lexLua(text) {
  let code = '';
  let withStrings = '';
  let i = 0;
  const n = text.length;
  const put = (c, s) => {
    code += c;
    withStrings += s === undefined ? c : s;
  };
  // Consumes a long-bracket body starting after its opener; emit(ch) receives every char up to and
  // including the closer.
  const longBody = (level, emit) => {
    const closer = ']' + '='.repeat(level) + ']';
    while (i < n) {
      if (text.startsWith(closer, i)) {
        for (const ch of closer) {
          emit(ch, true);
        }
        i += closer.length;
        return;
      }
      emit(text[i], false);
      i++;
    }
  };
  while (i < n) {
    const c = text[i];
    if (c === '-' && text[i + 1] === '-') {
      i += 2;
      const level = text[i] === '[' ? longBracketLevel(text, i) : -1;
      if (level >= 0) {
        i += level + 2;
        put(' ');
        longBody(level, ch => {
          if (ch === '\n') {
            put('\n');
          }
        });
      } else {
        while (i < n && text[i] !== '\n') {
          i++;
        }
      }
      continue;
    }
    if (c === '"' || c === "'") {
      put(c);
      i++;
      while (i < n && text[i] !== c && text[i] !== '\n') {
        if (text[i] === '\\' && i + 1 < n) {
          // An escape consumes the next char, so an escaped quote never ends the string. An
          // escaped line break (LF or CRLF) continues the string on the next line.
          let esc = text[i + 1];
          if (esc === '\r' && text[i + 2] === '\n') {
            esc = '\r\n';
          }
          const isBreak = esc === '\n' || esc === '\r\n';
          put(isBreak ? ' ' + esc : '  ', '\\' + esc);
          i += 1 + esc.length;
          continue;
        }
        put(' ', text[i]);
        i++;
      }
      if (i < n && text[i] === c) {
        put(c);
        i++;
      }
      continue;
    }
    if (c === '[') {
      const level = longBracketLevel(text, i);
      if (level >= 0) {
        const opener = text.slice(i, i + level + 2);
        put(opener);
        i += level + 2;
        longBody(level, (ch, isCloser) => {
          if (isCloser) {
            put(ch);
          } else if (ch === '\n' || ch === '\r') {
            put(ch);
          } else {
            put(' ', ch);
          }
        });
        continue;
      }
    }
    put(c);
    i++;
  }
  const codeLines = toLines(code);
  const strLines = toLines(withStrings);
  return codeLines.map((line, idx) => ({ code: line, withStrings: strLines[idx] || '' }));
}

// A column-0 "function" (optionally "local function") line opens a reader; the NEXT column-0
// "end" line closes it. A hit between a close and the next open belongs to no reader at all and
// is attributed to "(top level)" -- it can never be allowlisted, by construction. Boundaries are
// read off the lexed CODE line, so a comment or a long string can never open or close a reader.
const FUNC_OPEN_RE = /^(local\s+)?function\s+([\w.:]+)/;
const FUNC_CLOSE_RE = /^end(\s|$)/;

function toLines(text) {
  return text.split('\n').map(l => (l.endsWith('\r') ? l.slice(0, -1) : l));
}

// Scans one file's text for aura-API hits, attributing each to its enclosing column-0 function.
// One hit per line at most (the first match).
function scanFile(name, text) {
  const lines = lexLua(text);
  const hits = [];
  let currentFunction = null;
  for (let i = 0; i < lines.length; i++) {
    const { code, withStrings } = lines[i];
    const lineNo = i + 1;
    const openMatch = code.match(FUNC_OPEN_RE);
    if (openMatch) {
      currentFunction = openMatch[2];
    } else if (currentFunction !== null && FUNC_CLOSE_RE.test(code)) {
      currentFunction = null;
    }
    const hit = code.match(DETECT_RE) || withStrings.match(STRING_INDEX_RE);
    if (hit) {
      hits.push({ file: name, line: lineNo, func: currentFunction || '(top level)', text: hit[0] });
    }
  }
  return hits;
}

function scanFiles(files) {
  const hits = [];
  for (const f of files) {
    hits.push(...scanFile(f.name, f.text));
  }
  return hits;
}

function classify(hits) {
  const violations = [];
  const allowed = [];
  for (const h of hits) {
    if (isAllowed(h.file, h.func)) {
      allowed.push(h);
    } else {
      violations.push(h);
    }
  }
  return { violations, allowed };
}

// Asserts ns:ReadPlayerAura's body (BuffEngine.lua) GATES its read on the secrecy predicate:
//   if C_Secrets.ShouldSpellAuraBeSecret(...) then
//       return nil, false
// as consecutive CODE lines (lexed, so a comment naming the predicate counts for nothing), and
// that block sits BEFORE the first aura read in the function (any DETECT_RE hit, not only
// GetPlayerAuraBySpellID). A predicate whose result is discarded (`local _ = ...`), negated, or
// asked after the read fails. Returns { checked, ok } -- checked is false when BuffEngine.lua is
// absent from the file list, or ns:ReadPlayerAura itself cannot be found, so a missing gate
// reader can never silently report success.
const PREDICATE_IF_RE = /^\s*if\s+C_Secrets\s*\.\s*ShouldSpellAuraBeSecret\s*\(.*\)\s*then\s*$/;
const RETURN_UNREADABLE_RE = /^\s*return\s+nil\s*,\s*false\s*$/;

function checkPredicateOrder(files) {
  const be = files.find(f => f.name === 'BuffEngine.lua');
  if (!be) {
    return { checked: false, ok: false };
  }
  // Non-blank code lines of the function body, in order.
  const body = [];
  let inFunc = false;
  let found = false;
  for (const { code } of lexLua(be.text)) {
    if (!inFunc) {
      if (/^function\s+ns:ReadPlayerAura\b/.test(code)) {
        inFunc = true;
        found = true;
      }
      continue;
    }
    if (FUNC_CLOSE_RE.test(code)) {
      break;
    }
    if (code.trim() !== '') {
      body.push(code);
    }
  }
  if (!found) {
    return { checked: false, ok: false };
  }
  let gateAt = -1;
  let readAt = -1;
  for (let i = 0; i < body.length; i++) {
    if (gateAt < 0 && PREDICATE_IF_RE.test(body[i]) && i + 1 < body.length && RETURN_UNREADABLE_RE.test(body[i + 1])) {
      gateAt = i;
    }
    if (readAt < 0 && DETECT_RE.test(body[i])) {
      readAt = i;
    }
  }
  const ok = gateAt >= 0 && readAt >= 0 && gateAt < readAt;
  return { checked: true, ok };
}

// --- shipped file list -----------------------------------------------------------------------
// Discovered the way the client loads the addon (WR-03, 56-REVIEW): every non-comment TOC line in
// order; a .lua line is a file, a .xml line is walked. Inside an XML file (comments removed),
// <Script file="..."> and <Include file="..."> are resolved RELATIVE TO THAT XML FILE and followed
// recursively -- a .lua target is a file, a .xml target is walked in turn. Lua written INLINE in
// XML (a <Script> body, or an <OnLoad>/<OnEvent>/... handler body) is scanned too, as the XML
// file itself with everything else blanked, so its hits keep their line numbers and, belonging to
// no Lua function, are always "(top level)" violations. A file named anywhere but missing on disk
// throws, which fails the gate: the client would fail to load it too.
//
// read(relPath) returns a file's text; relPath uses "/" and is relative to the addon root. The
// selftest passes an in-memory map; the gate reads the real tree.
const TOC_NAME = 'TerribleBuffTracker.toc';
const XML_FILE_REF_RE = /<(?:Script|Include)\b[^>]*?\bfile\s*=\s*(["'])(.*?)\1/g;
const XML_INLINE_LUA_RE = /<(Script|On[A-Za-z]+)\b[^>]*?(?<!\/)>([\s\S]*?)<\/\1\s*>/g;

function normalizeRel(p) {
  return path.posix.normalize(p.replace(/\\/g, '/'));
}

function stripXmlComments(text) {
  // Same length out as in, newlines kept, so offsets and line numbers still match the source.
  return text.replace(/<!--[\s\S]*?-->/g, m => m.replace(/[^\n]/g, ' '));
}

function inlineLuaOf(xml) {
  let found = false;
  const out = xml.replace(/[^\r\n]/g, ' ').split('');
  for (const m of xml.matchAll(XML_INLINE_LUA_RE)) {
    const body = m[2];
    if (body.trim() === '') {
      continue;
    }
    found = true;
    const start = m.index + m[0].indexOf('>') + 1;
    for (let k = 0; k < body.length; k++) {
      out[start + k] = body[k];
    }
  }
  return found ? out.join('') : null;
}

function discoverShippedFiles(read) {
  const files = [];
  const seen = new Set();
  const addLua = rel => {
    if (!seen.has(rel)) {
      seen.add(rel);
      files.push({ name: rel, text: read(rel) });
    }
  };
  const walkXml = rel => {
    if (seen.has(rel)) {
      return;
    }
    seen.add(rel);
    const xml = stripXmlComments(read(rel));
    const dir = path.posix.dirname(rel);
    for (const m of xml.matchAll(XML_FILE_REF_RE)) {
      const target = normalizeRel(path.posix.join(dir, m[2].replace(/\\/g, '/')));
      if (/\.lua$/i.test(target)) {
        addLua(target);
      } else if (/\.xml$/i.test(target)) {
        walkXml(target);
      }
    }
    const inline = inlineLuaOf(xml);
    if (inline !== null) {
      files.push({ name: rel, text: inline });
    }
  };
  for (const line of toLines(read(TOC_NAME))) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    const rel = normalizeRel(trimmed);
    if (/\.lua$/i.test(rel)) {
      addLua(rel);
    } else if (/\.xml$/i.test(rel)) {
      walkXml(rel);
    }
  }
  return files;
}

function loadShippedFiles() {
  const root = path.join(__dirname, '..');
  return discoverShippedFiles(rel => fs.readFileSync(path.join(root, rel), 'utf8'));
}

// --- gate ------------------------------------------------------------------------------------
function runGate() {
  const files = loadShippedFiles();
  const { violations, allowed } = classify(scanFiles(files));
  const predicate = checkPredicateOrder(files);

  for (const v of violations) {
    console.log(`FAIL ${v.file}:${v.line} ${v.func} ${v.text}`);
  }

  let ok = violations.length === 0;
  if (!predicate.checked) {
    console.log('FAIL BuffEngine.lua: ns:ReadPlayerAura not found -- predicate gate cannot be verified');
    ok = false;
  } else if (!predicate.ok) {
    console.log(
      'FAIL BuffEngine.lua: ns:ReadPlayerAura does not gate its read with "if C_Secrets.ShouldSpellAuraBeSecret(...) then return nil, false" before the first aura read'
    );
    ok = false;
  }

  if (ok) {
    const readers = new Set(allowed.map(a => `${a.file}:${a.func}`)).size;
    console.log(`AURA-READ GATE PASS (${allowed.length} reads in ${readers} allowlisted readers)`);
    process.exitCode = 0;
  } else {
    process.exitCode = 1;
  }
}

// --- --selftest: embedded fixtures and hard assertions ----------------------------------------
const FIXTURE_CLEAN = `
local _, ns = ...

function ns:ReadPlayerAura(spellID)
	if C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return nil, false
	end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	return aura, true
end
`;

const FIXTURE_BYPASS = `
local _, ns = ...

local function Visible(entry)
	local a = C_UnitAuras.GetPlayerAuraBySpellID(entry.auraID)
	return a ~= nil
end
`;

const FIXTURE_COMMENT = `
local _, ns = ...

-- C_UnitAuras.GetPlayerAuraBySpellID(x)
`;

const FIXTURE_NO_PREDICATE = `
local _, ns = ...

function ns:ReadPlayerAura(spellID)
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	return aura, true
end
`;

const FIXTURE_TOP_LEVEL = `
local _, ns = ...

function ns:ReadPlayerAura(spellID)
	if C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return nil, false
	end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	return aura, true
end

local leaked = C_UnitAuras.GetPlayerAuraBySpellID(999)
`;

// WR-02 (56-REVIEW): the predicate is named only in a comment -- the gate block is gone.
const FIXTURE_PREDICATE_COMMENT_ONLY = `
local _, ns = ...

function ns:ReadPlayerAura(spellID)
	-- asks C_Secrets.ShouldSpellAuraBeSecret(spellID) first
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	return aura, true
end
`;

// WR-02: the predicate is asked but its answer is discarded, so the read is unconditional.
const FIXTURE_PREDICATE_DISCARDED = `
local _, ns = ...

function ns:ReadPlayerAura(spellID)
	local _ = C_Secrets.ShouldSpellAuraBeSecret(spellID)
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	return aura, true
end
`;

// WR-02: a correct gate block, but only AFTER the read.
const FIXTURE_PREDICATE_AFTER_READ = `
local _, ns = ...

function ns:ReadPlayerAura(spellID)
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	if C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return nil, false
	end
	return aura, true
end
`;

// WR-01 (56-REVIEW): every bypass shape the review demonstrated, each on the line after
// "local function Visible(entry)". Each must produce exactly 1 violation attributed to Visible.
const BYPASS_SHAPES = [
  ['namespace alias', 'local UA = C_UnitAuras'],
  ['bracket index', 'local a = C_UnitAuras["GetPlayerAuraBySpellID"](entry.auraID)'],
  ['spaced member', 'local a = C_UnitAuras . GetPlayerAuraBySpellID(entry.auraID)'],
  ['bare GetPlayerAuraBySpellID', 'local a = GetPlayerAuraBySpellID(entry.auraID)'],
  ['bare UnitAuraBySlot', 'local a = UnitAuraBySlot("player", 1)'],
  ['bare UnitAuraSlots', 'local a = UnitAuraSlots("player", "HELPFUL")'],
  ['C_TooltipInfo.GetUnitBuff', 'local a = C_TooltipInfo.GetUnitBuff("player", 1)'],
  ['C_TooltipInfo.GetUnitAura', 'local a = C_TooltipInfo.GetUnitAura("player", 1, "HELPFUL")'],
  ['" --" inside a string', 'print("a --", C_UnitAuras.GetPlayerAuraBySpellID(1))'],
  ['_G string index', 'local a = _G["UnitAura"]("player", 1)'],
  ['rawget string key', 'local UA = rawget(_G, "C_UnitAuras")'],
  ['alias of a bare global', 'local ua = UnitBuff'],
];

function bypassFixture(line) {
  return `\nlocal _, ns = ...\n\nlocal function Visible(entry)\n\t${line}\n\treturn a ~= nil\nend\n`;
}

// Text that names an aura API but reads nothing: must produce 0 hits.
const NON_READ_SHAPES = [
  ['API name inside a chat string', 'print("C_UnitAuras.GetPlayerAuraBySpellID is secret")'],
  ['block comment across lines', '--[[\nlocal a = C_UnitAuras.GetPlayerAuraBySpellID(1)\n]]'],
  ['long string across lines', 'local s = [==[\nC_UnitAuras.GetPlayerAuraBySpellID(1)\n]==]'],
  ['names as table values', 'for _, m in ipairs({ "UnitAura", "UnitBuff", "UnitDebuff" }) do end'],
  ['ns:OnUnitAura handler name', 'ns:OnUnitAura(updateInfo)'],
];

// WR-03 (56-REVIEW): an in-memory addon tree. The TOC lists a Lua file and an XML file in a
// subfolder; that XML loads a Lua file beside it, includes a deeper XML (backslash path, as WoW
// accepts) that loads another, carries an inline OnLoad handler that reads an aura, and names a
// file only inside an XML comment, which must never be followed.
const FIXTURE_TREE = {
  'TerribleBuffTracker.toc': '## Interface: 120100\r\n## Title: x\r\n\r\nA.lua\r\nSub\\X.xml\r\n',
  'A.lua': 'local _, ns = ...\r\n',
  'Sub/X.xml': [
    '<Ui>',
    '\t<!-- <Script file="Ghost.lua"/> -->',
    '\t<Script file="B.lua"/>',
    '\t<Include file="Deep\\Y.xml"/>',
    '\t<Frame name="F">',
    '\t\t<Scripts>',
    '\t\t\t<OnLoad>',
    '\t\t\t\tlocal a = C_UnitAuras.GetPlayerAuraBySpellID(1)',
    '\t\t\t</OnLoad>',
    '\t\t</Scripts>',
    '\t</Frame>',
    '</Ui>',
  ].join('\r\n'),
  'Sub/B.lua': 'local _, ns = ...\r\n',
  'Sub/Deep/Y.xml': '<Ui>\r\n\t<Script file="C.lua"/>\r\n</Ui>\r\n',
  'Sub/Deep/C.lua': 'local _, ns = ...\r\n',
};

function readFixtureTree(rel) {
  if (!(rel in FIXTURE_TREE)) {
    throw new Error(`fixture tree has no ${rel}`);
  }
  return FIXTURE_TREE[rel];
}

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

  // (a) ReadPlayerAura asks the predicate then reads -- 0 violations.
  runCase('gated ReadPlayerAura -> 0 violations', expect => {
    const { violations } = classify(scanFiles([{ name: 'BuffEngine.lua', text: FIXTURE_CLEAN }]));
    expect(violations.length === 0, `expected 0 violations, got ${violations.length}`);
  });

  // (b) a direct read inside an un-allowlisted function -- exactly 1 violation naming it.
  runCase('bypass in Visible -> 1 violation naming Visible', expect => {
    const { violations } = classify(scanFiles([{ name: 'Providers.lua', text: FIXTURE_BYPASS }]));
    expect(violations.length === 1, `expected 1 violation, got ${violations.length}`);
    expect(
      violations[0] && violations[0].func === 'Visible',
      `expected violation naming Visible, got ${violations[0] && violations[0].func}`
    );
  });

  // (c) a comment-only line -- 0 violations, 0 hits at all.
  runCase('comment-only line -> 0 violations', expect => {
    const { violations, allowed } = classify(scanFiles([{ name: 'Comment.lua', text: FIXTURE_COMMENT }]));
    expect(violations.length === 0 && allowed.length === 0, `expected 0 hits, got ${violations.length + allowed.length}`);
  });

  // (i) WR-03: TOC + XML discovery follows Script and Include recursively, relative to each XML,
  // and never follows a reference that only appears inside an XML comment.
  runCase('discovery follows TOC, Script and nested Include; skips XML comments', expect => {
    const names = discoverShippedFiles(readFixtureTree).map(f => f.name);
    for (const want of ['A.lua', 'Sub/B.lua', 'Sub/Deep/C.lua']) {
      expect(names.includes(want), `expected ${want} to be discovered, got ${names.join(', ')}`);
    }
    expect(!names.some(n => /Ghost/.test(n)), 'a file named only in an XML comment was followed');
  });

  // (j) WR-03: Lua written inline in XML is scanned, as a (top level) violation with its real line.
  runCase('inline XML handler read -> 1 violation, (top level), real line', expect => {
    const { violations } = classify(scanFiles(discoverShippedFiles(readFixtureTree)));
    expect(violations.length === 1, `expected 1 violation, got ${violations.length}`);
    const v = violations[0] || {};
    expect(v.file === 'Sub/X.xml' && v.func === '(top level)' && v.line === 8, `got ${v.file}:${v.line} ${v.func}`);
  });

  // (k) WR-03: the real tree reaches CDMTab.lua through CDMTab.xml, with no special case.
  runCase('real tree discovers CDMTab.lua through CDMTab.xml', expect => {
    const names = loadShippedFiles().map(f => f.name);
    expect(names.includes('CDMTab.lua'), `CDMTab.lua not discovered: ${names.join(', ')}`);
  });

  // (d) the predicate line removed -- predicate check fails even though the read is allowlisted.
  runCase('missing predicate -> predicate check fails', expect => {
    const predicate = checkPredicateOrder([{ name: 'BuffEngine.lua', text: FIXTURE_NO_PREDICATE }]);
    expect(predicate.checked === true, 'expected ns:ReadPlayerAura to be found');
    expect(predicate.ok === false, 'expected the predicate-order check to fail');
  });

  // (e) vacuity guard: the REAL shipped tree must report at least 1 allowlisted read, and 0
  // violations -- an empty or misconfigured file list can never pass silently.
  runCase('vacuity guard: real shipped files report >= 1 allowlisted read', expect => {
    const files = loadShippedFiles();
    const { violations, allowed } = classify(scanFiles(files));
    expect(
      violations.length === 0,
      `real tree should have 0 violations, got ${violations.length}: ${violations.map(v => `${v.file}:${v.line}`).join(', ')}`
    );
    expect(allowed.length >= 1, `expected at least 1 allowlisted read, got ${allowed.length}`);
  });

  // (f) a read placed AFTER the allowlisted function's closing column-0 end (top-level code) --
  // exactly 1 violation, attributed to "(top level)" -- proves the closed-function rule works.
  runCase('top-level bypass after closed function -> 1 violation, (top level)', expect => {
    const { violations } = classify(scanFiles([{ name: 'BuffEngine.lua', text: FIXTURE_TOP_LEVEL }]));
    expect(violations.length === 1, `expected 1 violation, got ${violations.length}`);
    expect(
      violations[0] && violations[0].func === '(top level)',
      `expected (top level), got ${violations[0] && violations[0].func}`
    );
  });

  // (d2) WR-02: the gate must be CODE, gate the read, and come first. Each shape fails the check.
  for (const [label, text] of [
    ['predicate named only in a comment', FIXTURE_PREDICATE_COMMENT_ONLY],
    ['predicate result discarded', FIXTURE_PREDICATE_DISCARDED],
    ['predicate block after the read', FIXTURE_PREDICATE_AFTER_READ],
  ]) {
    runCase(`${label} -> predicate check fails`, expect => {
      const predicate = checkPredicateOrder([{ name: 'BuffEngine.lua', text }]);
      expect(predicate.checked === true, 'expected ns:ReadPlayerAura to be found');
      expect(predicate.ok === false, 'expected the predicate-order check to fail');
    });
  }

  // (d3) the gated fixture and the REAL BuffEngine.lua both pass the stricter check.
  runCase('gated fixture and real BuffEngine.lua -> predicate check passes', expect => {
    const fixture = checkPredicateOrder([{ name: 'BuffEngine.lua', text: FIXTURE_CLEAN }]);
    expect(fixture.checked && fixture.ok, 'expected the gated fixture to pass');
    const real = checkPredicateOrder(loadShippedFiles());
    expect(real.checked && real.ok, 'expected the real ns:ReadPlayerAura to pass');
  });

  // (g) WR-01: one case per bypass shape -- exactly 1 violation, attributed to Visible.
  for (const [label, line] of BYPASS_SHAPES) {
    runCase(`bypass shape: ${label} -> 1 violation naming Visible`, expect => {
      const { violations } = classify(scanFiles([{ name: 'Providers.lua', text: bypassFixture(line) }]));
      expect(violations.length === 1, `expected 1 violation, got ${violations.length}`);
      expect(
        violations[0] && violations[0].func === 'Visible',
        `expected violation naming Visible, got ${violations[0] && violations[0].func}`
      );
    });
  }

  // (h) WR-01: text that names an API but reads nothing -- 0 hits, so widening the patterns did not
  // buy false positives.
  for (const [label, line] of NON_READ_SHAPES) {
    runCase(`non-read shape: ${label} -> 0 hits`, expect => {
      const { violations, allowed } = classify(scanFiles([{ name: 'Providers.lua', text: bypassFixture(line) }]));
      expect(
        violations.length === 0 && allowed.length === 0,
        `expected 0 hits, got ${violations.length + allowed.length}: ${violations.map(v => v.text).join(', ')}`
      );
    });
  }

  if (failures === 0) {
    console.log(`AURA-READ SELFTEST PASS (${caseCount} cases)`);
    process.exitCode = 0;
  } else {
    console.log(`AURA-READ SELFTEST FAIL (${failures}/${caseCount} cases failed)`);
    process.exitCode = 1;
  }
}

// --- CLI ---------------------------------------------------------------------------------------
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  runGate();
}
