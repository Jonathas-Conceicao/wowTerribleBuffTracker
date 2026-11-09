#!/usr/bin/env node
// Phase 80 source gate (RALT-04..07, MREM-06). No Lua interpreter exists on this machine, so the
// reminder table is checked by parsing Providers.lua's text.
//
// Usage: node 80-check-groups.js [--exact] [path/to/Providers.lua]
//   --exact  the Forever block holds ONLY Phase 80's nine calls (Phase 80's own gate).
//            Without it, later calls appended by Phases 81-82 are allowed after the nine.
// Exit 0 = every check passed; exit 1 = at least one FAIL line printed.
//
// Baseline: commit 5c0001e (the milestone's last commit before Phase 80). MetaReminderRow and
// MetaReminderGroup bodies and every row except 1038/19979 must match it byte for byte.

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const args = process.argv.slice(2);
const exact = args.includes("--exact");
const repo = path.resolve(__dirname, "..", "..", "..");
const file = args.find((a) => a !== "--exact") || path.join(repo, "Providers.lua");
const BASE = "5c0001e";

const raw = fs.readFileSync(file, "utf8");
const base = execSync(`git show ${BASE}:Providers.lua`, { cwd: repo, encoding: "utf8", maxBuffer: 1 << 26 });

let failures = 0;
const fail = (m) => {
	failures++;
	console.log("FAIL: " + m);
};
const ok = (m) => console.log("ok:   " + m);
const check = (cond, m) => (cond ? ok(m) : fail(m));

// The nine Phase 80 calls, research §12.3 verbatim, blessings call without 1038/19979.
const EXPECTED = [
	[1459, 1460, 1461, 10156, 10157, 23028],
	[10938, 1243, 1244, 1245, 2791, 10937, 21562, 21564],
	[27841, 14752, 14818, 14819, 27681],
	[9885, 1126, 5232, 6756, 5234, 8907, 9884, 21849, 21850],
	[9910, 467, 782, 1075, 8914, 9756],
	[25289, 6673, 5242, 6192, 11549, 11550, 11551],
	[20906, 19506, 20905],
	[11767, 6307, 7804, 7805, 11766],
	[20217, 25291, 25290, 19740, 19834, 19835, 19836, 19837, 19838, 19742, 19850, 19852, 19853, 19854, 25898, 25782, 25916, 25894, 25918],
];
const RETAIL_DEVOTION = "465,317920,32223";
const FORBIDDEN_CODE_IDS = [1038, 19979, 25895, 25890, 7871, 7872, 7873, 11768, 11769, 20318, 20319, 20320, 20321, 20397];

// 0. Line endings: CRLF everywhere, never the stylua CRCRLF.
check(!raw.includes("\r\r"), "no CRCRLF (stylua comment-in-expression trap)");
check(!/[^\r]\n/.test(raw), "every line ends in CRLF");

const lines = raw.split(/\r?\n/);
const baseLines = base.split(/\r?\n/);
const code = (l) => l.replace(/--.*$/, "");

// Extract a top-level function's text from its declaration to its first column-0 "end".
function fnText(ls, decl) {
	const s = ls.findIndex((l) => l.startsWith(decl));
	if (s < 0) return null;
	const e = ls.findIndex((l, i) => i > s && /^end\s*$/.test(l));
	return ls.slice(s, e + 1).join("\n");
}

// 1. MetaReminderRow / MetaReminderGroup unchanged.
for (const decl of ["local function MetaReminderRow(", "local function MetaReminderGroup("]) {
	const a = fnText(lines, decl);
	check(a !== null && a === fnText(baseLines, decl), `${decl.slice(15, -1)} body identical to ${BASE}`);
}

// 2. Rows: every baseline row except 1038 and 19979, unchanged and in order; no row added.
const rowsOf = (ls) => ls.filter((l) => l.startsWith("MetaReminderRow("));
const baseRows = rowsOf(baseLines).filter((l) => !/^MetaReminderRow\((1038|19979),/.test(l));
const rows = rowsOf(lines);
check(!rows.some((l) => /^MetaReminderRow\((1038|19979),/.test(l)), "rows 1038 and 19979 removed (MREM-06)");
check(JSON.stringify(rows) === JSON.stringify(baseRows), "every other row (retail, both, Forever) byte-identical to baseline, none added");

// 3. Exactly one Forever block, after the last row.
const ifIdx = lines.map((l, i) => (/^if ns\.CLIENT_IS_FOREVER then\s*$/.test(l) ? i : -1)).filter((i) => i >= 0);
check(ifIdx.length === 1, `exactly one column-0 "if ns.CLIENT_IS_FOREVER then" (found ${ifIdx.length})`);
if (ifIdx.length !== 1) {
	console.log(`\n${failures} check(s) failed`);
	process.exit(1);
}
const s = ifIdx[0];
const e = lines.findIndex((l, i) => i > s && /^end\s*$/.test(l));
const lastRow = lines.reduce((acc, l, i) => (l.startsWith("MetaReminderRow(") ? i : acc), -1);
check(e > s, "the block closes with a column-0 end");
check(s > lastRow, "the block sits after every MetaReminderRow call");
const block = lines.slice(s + 1, e);

// 4. Comment above the block names the five shared IDs (RALT-04 reason).
let c = s - 1;
const above = [];
while (c >= 0 && /^\s*--/.test(lines[c])) above.unshift(lines[c--]);
const aboveText = above.join("\n");
check(above.length > 0 && [21562, 1459, 1126, 6673, 465].every((id) => aboveText.includes(String(id))), "comment directly above the block names 21562, 1459, 1126, 6673 and 465");

// 5. No comment on a code line inside the block (comments go on their own line above each call).
check(block.every((l) => /^\s*(--.*)?$/.test(l) || !l.includes("--")), "no trailing or in-expression comment inside the block");

// 6. The block's calls.
const blockCode = block.map(code).join("\n");
const calls = [...blockCode.matchAll(/MetaReminderGroup\(([^)]*)\)/g)].map((m) => m[1].split(",").map((x) => x.trim()).filter(Boolean).map(Number));
const strip = blockCode.replace(/MetaReminderGroup\([^)]*\)/g, "").trim();
check(strip === "", "the block contains nothing but MetaReminderGroup calls and comments");
EXPECTED.forEach((exp, i) => check(JSON.stringify(calls[i]) === JSON.stringify(exp), `call ${i + 1} = MetaReminderGroup(${exp[0]}, …) exactly per §12.3 (got ${calls[i] ? calls[i][0] + ", … (" + calls[i].length + " ids)" : "none"})`));
if (exact) check(calls.length === EXPECTED.length, `--exact: the block holds exactly ${EXPECTED.length} calls (found ${calls.length})`);
else ok(`${Math.max(0, calls.length - EXPECTED.length)} later-phase call(s) after Phase 80's nine`);

// 7. Outside the block, the only group call is the retail Devotion one, unchanged.
const tblStart = lines.findIndex((l) => l.startsWith("local function MetaReminderGroup("));
const tblEnd = lines.findIndex((l) => l.startsWith("function ns:MetaReminderDef("));
const outside = lines.slice(tblStart + 1, tblEnd).filter((_, k) => k + tblStart + 1 < s || k + tblStart + 1 > e);
const outsideCalls = [...outside.map(code).join("\n").matchAll(/MetaReminderGroup\(([^)]*)\)/g)].map((m) => m[1].replace(/\s/g, ""));
check(JSON.stringify(outsideCalls) === JSON.stringify([RETAIL_DEVOTION]), `outside the block only MetaReminderGroup(465, 317920, 32223) remains (found ${JSON.stringify(outsideCalls)})`);

// 8. Removed / excluded IDs appear in no code in the reminder table (comments may name them).
const tableCode = lines.slice(tblStart, tblEnd).map(code).join("\n");
const leaked = FORBIDDEN_CODE_IDS.filter((id) => new RegExp(`\\b${id}\\b`).test(tableCode));
check(leaked.length === 0, `no code in the reminder table uses 1038, 19979, Greater Salvation/Light or Blood Pact's extra IDs (found ${leaked.join(", ") || "none"})`);

console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed");
process.exit(failures ? 1 : 0);
