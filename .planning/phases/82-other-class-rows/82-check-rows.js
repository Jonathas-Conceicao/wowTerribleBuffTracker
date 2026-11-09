#!/usr/bin/env node
// Phase 82 source gate (MREM-08..16). No Lua interpreter exists on this machine, so the reminder
// table is checked by parsing Providers.lua's text.
//
// Usage: node 82-check-rows.js [--base <rev> | --base-file <path>] [path/to/Providers.lua]
//   The baseline is the Providers.lua of the last commit that touched it and is not a Phase 82
//   commit (subject "<type>(82-NN): ..."). That is Phase 81's result when Phase 81 has run, else
//   Phase 80's, so the gate never depends on what Phase 81 added. --base / --base-file override it.
// Exit 0 = every check passed; exit 1 = at least one FAIL line printed.

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const argv = process.argv.slice(2);
const opt = (name) => {
	const i = argv.indexOf(name);
	if (i < 0) return null;
	const v = argv[i + 1];
	argv.splice(i, 2);
	return v;
};
const baseRev = opt("--base");
const baseFile = opt("--base-file");
const repo = path.resolve(__dirname, "..", "..", "..");
const file = argv[0] || path.join(repo, "Providers.lua");

const sh = (cmd) => execSync(cmd, { cwd: repo, encoding: "utf8", maxBuffer: 1 << 26 });
let base, baseName;
if (baseFile) {
	base = fs.readFileSync(baseFile, "utf8");
	baseName = baseFile;
} else {
	const rev = baseRev || sh(`git log -1 --format=%H --invert-grep -E "--grep=^[a-z]+\\(82-" -- Providers.lua`).trim();
	base = sh(`git show ${rev}:Providers.lua`);
	baseName = rev.slice(0, 7);
}
const raw = fs.readFileSync(file, "utf8");

let failures = 0;
const fail = (m) => {
	failures++;
	console.log("FAIL: " + m);
};
const ok = (m) => console.log("ok:   " + m);
const check = (cond, m) => (cond ? ok(m) : fail(m));
const done = () => {
	console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed");
	process.exit(failures ? 1 : 0);
};
console.log(`baseline: ${baseName}`);

// The thirteen Phase 82 rows, in table order. Demonic Sacrifice (the only row with an auraID) last.
const NEW_ROWS = [
	"MetaReminderRow(11735, 30)",
	"MetaReminderRow(696, 30)",
	"MetaReminderRow(10432, 10)",
	"MetaReminderRow(408510, 10)",
	"MetaReminderRow(10952, 10)",
	"MetaReminderRow(15473, 0)",
	"MetaReminderRow(19312, 10)",
	"MetaReminderRow(10958, 10)",
	"MetaReminderRow(10293, 0)",
	"MetaReminderRow(25296, 0)",
	"MetaReminderRow(10170, 10)",
	"MetaReminderRow(10174, 10)",
	"MetaReminderRow(18788, 120, nil, nil, nil, { auraID = 18789 })",
];
// The seven Phase 82 group calls, appended in this order after every baseline call in the block.
const NEW_GROUPS = [
	[11735, 696],
	[10432, 408510],
	[10958, 976, 10957, 27683],
	[10293, 465, 10290, 643, 10291, 1032, 10292, 7294, 10298, 10299, 10300, 10301, 19746, 19876, 19895, 19896, 19888, 19897, 19898, 19891, 19899, 19900],
	[25296, 13163, 5118, 13159, 20043, 20190, 13161],
	[10170, 10174, 1008, 8455, 10169, 604, 8450, 8451, 10173],
	[18788, 18790, 18791, 18792],
];
// In no code in the reminder table: Viper, Falcon, Sanctity Aura, Soul Link, SoD/NPC IDs, the
// retired blessings, and the dropped detection/tracking skills (MREM-17).
const FORBIDDEN_CODE_IDS = [
	34074, 469145, 20218, 19028, 25228, 428741, 403619, 450086, 1283419, 1213334, 1233344, 1038, 19979,
	132, 2970, 11743, 1494, 19878, 19879, 19880, 19882, 19883, 19884, 19885, 5225, 2383, 2580, 5500, 5502,
];
// Never anywhere in Providers.lua, comments included.
const FORBIDDEN_ANYWHERE = [34074, 469145];
const RETAIL_ANCHOR = "-- The retail rows (user data 2026-09-30, MREM-04/MREM-05).";

// 0. Line endings.
check(!raw.includes("\r\r"), "no CRCRLF (stylua comment-in-expression trap)");
check(!/[^\r]\n/.test(raw), "every line ends in CRLF");

const lines = raw.split(/\r?\n/);
const baseLines = base.split(/\r?\n/);
const code = (l) => l.replace(/--.*$/, "");
const comment = (l) => {
	const i = l.indexOf("--");
	return i < 0 ? "" : l.slice(i);
};
const isRow = (l) => l.startsWith("MetaReminderRow(");
const rowCode = (l) => code(l).trim();

function fnText(ls, decl) {
	const s = ls.findIndex((l) => l.startsWith(decl));
	if (s < 0) return null;
	const e = ls.findIndex((l, i) => i > s && /^end\s*$/.test(l));
	return ls.slice(s, e + 1).join("\n");
}

// 1. MetaReminderRow / MetaReminderGroup unchanged against the baseline.
for (const decl of ["local function MetaReminderRow(", "local function MetaReminderGroup("]) {
	const a = fnText(lines, decl);
	check(a !== null && a === fnText(baseLines, decl), `${decl.slice(15, -1)} body identical to baseline`);
}

// 2. Rows.
const rowIdx = lines.map((l, i) => (isRow(l) ? i : -1)).filter((i) => i >= 0);
const newIdx = [];
NEW_ROWS.forEach((r) => {
	const hits = rowIdx.filter((i) => rowCode(lines[i]) === r);
	check(hits.length === 1, `row ${r} present exactly once (found ${hits.length})`);
	newIdx.push(hits.length === 1 ? hits[0] : -1);
	check(!rowIdx.some((i) => i !== hits[0] && new RegExp(`^MetaReminderRow\\(${r.match(/\d+/)[0]},`).test(lines[i])), `no other row keyed on ${r.match(/\d+/)[0]}`);
});
const placed = newIdx.every((i) => i >= 0);
if (placed) {
	check(newIdx.every((v, k) => k === 0 || v > newIdx[k - 1]), "the new rows are in the planned order, Demonic Sacrifice 18788 last");
	const span = lines.slice(newIdx[0], newIdx[newIdx.length - 1] + 1);
	check(span.every((l) => /^\s*(--.*)?$/.test(l) || NEW_ROWS.includes(rowCode(l))), "the new rows form one run (only blank and comment lines between them)");
	const anchor = lines.indexOf(RETAIL_ANCHOR);
	check(anchor > newIdx[newIdx.length - 1] && lines.slice(newIdx[newIdx.length - 1] + 1, anchor).every((l) => /^\s*(--.*)?$/.test(l)), "18788 is the last row before the retail-rows comment (only blank/comment lines between)");
	newIdx.forEach((i) => {
		const c = comment(lines[i]);
		check(/^-- (Warlock|Shaman|Priest|Paladin|Hunter|Mage): /.test(c) && c.includes("(unverified in game)"), `row ${rowCode(lines[i]).slice(16, -1)}: trailing comment "-- <Class>: ..." with "(unverified in game)"`);
		check(!/\b465\b/.test(lines[i]), `row ${rowCode(lines[i]).slice(16, -1)} line does not name 465`);
	});
}
const rest = lines.filter((l) => isRow(l) && !NEW_ROWS.includes(rowCode(l)));
const baseRows = baseLines.filter(isRow);
check(JSON.stringify(rest) === JSON.stringify(baseRows), `every baseline row (retail, both, Forever) byte-identical and in order, and no row added beyond the thirteen (baseline ${baseRows.length}, other rows ${rest.length})`);

// 3. Forever block.
const blockOf = (ls) => {
	const s = ls.findIndex((l) => /^if ns\.CLIENT_IS_FOREVER then\s*$/.test(l));
	const e = s < 0 ? -1 : ls.findIndex((l, i) => i > s && /^end\s*$/.test(l));
	return { s, e, n: ls.filter((l) => /^if ns\.CLIENT_IS_FOREVER then\s*$/.test(l)).length };
};
const B = blockOf(lines);
const BB = blockOf(baseLines);
check(B.n === 1 && B.e > B.s, `exactly one column-0 Forever block (found ${B.n})`);
if (B.n !== 1 || BB.n !== 1) done();
const lastRow = rowIdx[rowIdx.length - 1];
check(B.s > lastRow, "the block sits after every MetaReminderRow call");
const block = lines.slice(B.s + 1, B.e);
const callsOf = (ls) => [...ls.map(code).join("\n").matchAll(/MetaReminderGroup\(([^)]*)\)/g)].map((m) => m[1].split(",").map((x) => x.trim()).filter(Boolean).map(Number));
const calls = callsOf(block);
const baseCalls = callsOf(baseLines.slice(BB.s + 1, BB.e));
check(block.map(code).join("\n").replace(/MetaReminderGroup\([^)]*\)/g, "").trim() === "", "the block contains nothing but MetaReminderGroup calls and comments");
check(block.every((l) => /^\s*(--.*)?$/.test(l) || !l.includes("--")), "no trailing or in-expression comment inside the block");
check(JSON.stringify(calls.slice(0, baseCalls.length)) === JSON.stringify(baseCalls), `the block's first ${baseCalls.length} calls are the baseline's, unchanged and in order`);
const added = calls.slice(baseCalls.length);
check(added.length === NEW_GROUPS.length, `exactly ${NEW_GROUPS.length} calls appended after them (found ${added.length})`);
NEW_GROUPS.forEach((exp, i) => check(JSON.stringify(added[i]) === JSON.stringify(exp), `appended call ${i + 1} = MetaReminderGroup(${exp.join(", ")}) (got ${added[i] ? added[i].join(", ") : "none"})`));
// Each appended call has its own comment line directly above it.
const callStarts = block.map((l, i) => (/^\s*MetaReminderGroup\(/.test(l) ? i : -1)).filter((i) => i >= 0).slice(baseCalls.length);
check(callStarts.length === NEW_GROUPS.length && callStarts.every((i) => i > 0 && /^\t--/.test(block[i - 1])), "each appended call has a one-tab comment line directly above it");

// 4. No row ID in two group calls (a second call overwrites the row's alternatives).
const foreverRowIds = lines.filter((l) => isRow(l) && !/client = "retail"/.test(l)).map((l) => Number(l.match(/^MetaReminderRow\((\d+)/)[1]));
const dup = foreverRowIds.filter((id) => calls.filter((c) => c.includes(id)).length > 1);
check(dup.length === 0, `no Forever row ID appears in two group calls (found ${dup.join(", ") || "none"})`);

// 5. Outside the block nothing changed: the same group calls, and 465 only where it was.
const tblStart = lines.findIndex((l) => l.startsWith("local function MetaReminderGroup("));
const tblEnd = lines.findIndex((l) => l.startsWith("function ns:MetaReminderDef("));
const bStart = baseLines.findIndex((l) => l.startsWith("local function MetaReminderGroup("));
const bEnd = baseLines.findIndex((l) => l.startsWith("function ns:MetaReminderDef("));
const outside = (ls, a, z, b) => ls.slice(a + 1, z).filter((_, k) => k + a + 1 < b.s || k + a + 1 > b.e);
const out = outside(lines, tblStart, tblEnd, B);
const bout = outside(baseLines, bStart, bEnd, BB);
check(JSON.stringify(callsOf(out)) === JSON.stringify(callsOf(bout)), "the group calls outside the block are the baseline's (retail Devotion only)");
const n465 = (ls) => ls.map(code).filter((l) => /\b465\b/.test(l)).length;
check(n465(out) === n465(bout), `465 in code outside the block only where the baseline has it (${n465(out)} vs ${n465(bout)})`);
check(n465(block) > n465(baseLines.slice(BB.s + 1, BB.e)), "465 added inside the block (the paladin aura call)");

// 6. Forbidden IDs.
const tableCode = lines.slice(tblStart, tblEnd).map(code).join("\n");
const leaked = FORBIDDEN_CODE_IDS.filter((id) => new RegExp(`\\b${id}\\b`).test(tableCode));
check(leaked.length === 0, `no code in the reminder table uses Viper, Falcon, Sanctity, Soul Link, SoD/NPC, retired-blessing or detection/tracking IDs (found ${leaked.join(", ") || "none"})`);
const anywhere = FORBIDDEN_ANYWHERE.filter((id) => new RegExp(`\\b${id}\\b`).test(raw));
check(anywhere.length === 0, `34074 (Viper) and 469145 (Falcon) appear nowhere in the file (found ${anywhere.join(", ") || "none"})`);

// 7. Header records what Phase 82 deliberately left out.
const header = lines.slice(0, lines.indexOf("local META_REMINDER_DEFS = {}")).filter((l) => /^--/.test(l)).join("\n");
check(header.includes("MREM-17") && header.includes("Soul Link") && header.includes("Sanctity Aura"), "the table header comment names the dropped MREM-17 skills, Soul Link and Sanctity Aura");

done();
