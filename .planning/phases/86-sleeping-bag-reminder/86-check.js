#!/usr/bin/env node
// Phase 86 source gate (SBAG-01..04). No Lua interpreter exists on this machine, so Providers.lua,
// Core.lua and ReminderClick.lua are checked by parsing their text.
//
// Usage: node 86-check.js [--root <dir>]
//   --root  read the three files from <dir> instead of the repo (planner's mock test only).
// Baseline, per file: the last commit that touched it and is not a Phase 86 commit (subject
// "<type>(86-NN): ..."), so the gate never depends on what Phase 86 itself committed.
// Exit 0 = every check passed; exit 1 = at least one FAIL line printed.

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const argv = process.argv.slice(2);
const ri = argv.indexOf("--root");
const repo = path.resolve(__dirname, "..", "..", "..");
const root = ri >= 0 ? path.resolve(argv[ri + 1]) : repo;

const sh = (cmd) => execSync(cmd, { cwd: repo, encoding: "utf8", maxBuffer: 1 << 26 });
const baseOf = (f) => {
	const rev = sh(`git log -1 --format=%H --invert-grep -E "--grep=^[a-z]+\\(86[-)]" -- ${f}`).trim();
	return { rev: rev.slice(0, 7), text: sh(`git show ${rev}:${f}`) };
};

let failures = 0;
const fail = (m) => {
	failures++;
	console.log("FAIL: " + m);
};
const ok = (m) => console.log("ok:   " + m);
const check = (cond, m) => (cond ? ok(m) : fail(m));

const code = (l) => l.replace(/--.*$/, "");
// Comments stripped, blank lines dropped, whitespace collapsed: the code of a line list as one string.
const norm = (ls) =>
	(ls || [])
		.map((l) => code(l).trim())
		.filter(Boolean)
		.join(" ")
		.replace(/\s+/g, " ");
const codeLines = (ls) => ls.map((l) => code(l).trim()).filter(Boolean);
// A top-level function from its declaration to its first column-0 "end": [start, end] or null.
const fnRange = (ls, decl) => {
	const s = ls.findIndex((l) => l.startsWith(decl));
	if (s < 0) return null;
	const e = ls.findIndex((l, i) => i > s && /^end\s*$/.test(l));
	return e < 0 ? null : [s, e];
};
const fnLines = (ls, decl) => {
	const r = fnRange(ls, decl);
	return r ? ls.slice(r[0], r[1] + 1) : null;
};
// Code-line diff (comments stripped, blanks dropped): { added, removed }. Prefix/suffix trim, then LCS.
const diffOf = (aLines, bLines) => {
	const a = codeLines(aLines);
	const b = codeLines(bLines);
	let p = 0;
	while (p < a.length && p < b.length && a[p] === b[p]) p++;
	let s = 0;
	while (s < a.length - p && s < b.length - p && a[a.length - 1 - s] === b[b.length - 1 - s]) s++;
	const A = a.slice(p, a.length - s);
	const B = b.slice(p, b.length - s);
	const n = A.length;
	const m = B.length;
	const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
	for (let i = n - 1; i >= 0; i--)
		for (let j = m - 1; j >= 0; j--) dp[i][j] = A[i] === B[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
	const added = [];
	const removed = [];
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (A[i] === B[j]) {
			i++;
			j++;
		} else if (dp[i + 1][j] >= dp[i][j + 1]) removed.push(A[i++]);
		else added.push(B[j++]);
	}
	while (i < n) removed.push(A[i++]);
	while (j < m) added.push(B[j++]);
	return { added, removed };
};
const readCur = (f) => fs.readFileSync(path.join(root, f), "utf8");
const eol = (f, raw) => {
	check(!raw.includes("\r\r"), `${f}: no CRCRLF (stylua comment-in-expression trap)`);
	check(!/[^\r]\n/.test(raw), `${f}: every line ends in CRLF`);
};
const load = (f) => {
	const base = baseOf(f);
	const raw = readCur(f);
	console.log(`${f} baseline: ${base.rev}`);
	eol(f, raw);
	return { cur: raw.split(/\r?\n/), base: base.text.split(/\r?\n/) };
};

// ---------------------------------------------------------------------------------------------
// Providers.lua (SBAG-01 row, SBAG-02 offer, SBAG-03 accessor)
// ---------------------------------------------------------------------------------------------
const P = "Providers.lua";
const { cur: pl, base: pb } = load(P);

const ROW =
	"MetaReminderRow(429959, 120, nil, nil, false, { offerItem = 211527, useItems = { { 211527, 1 } } })";
const OFFER_LINE = "\t\tofferItem = opts and opts.offerItem or nil,";

// P1. The Well-Rested row: once, Forever (no client opt), class "General", "(unverified in game)" last.
{
	const hits = pl.filter((l) => code(l).trim() === ROW);
	check(hits.length === 1, `${P}: exactly one line whose code is ${ROW} (found ${hits.length})`);
	const l = hits[0] || "";
	check(l.startsWith(ROW + " -- General: Well-Rested"), `${P}: the row is at column 0 with a trailing "-- General: Well-Rested ..." comment`);
	check(/\(unverified in game\)\s*$/.test(l), `${P}: the row comment ends with "(unverified in game)"`);
	check(!/client\s*=/.test(code(l)), `${P}: the row has no client opt (nil = Forever only)`);
	const ri2 = pl.indexOf(l);
	const ds = pl.findIndex((x) => x.startsWith("MetaReminderRow(18788, 120,"));
	const rt = pl.findIndex((x) => x.startsWith("-- The retail rows"));
	check(ri2 > ds && ds >= 0 && ri2 < rt, `${P}: the row sits after the Demonic Sacrifice row and before the retail rows`);
	const others = pl.filter((x) => /^\s*MetaReminderRow\(/.test(x) && code(x).trim() !== ROW);
	const baseRows = pb.filter((x) => /^\s*MetaReminderRow\(/.test(x));
	check(JSON.stringify(others) === JSON.stringify(baseRows), `${P}: every baseline row byte-identical and in order, no other row added (baseline ${baseRows.length}, other ${others.length})`);
}

// P2. MetaReminderRow = baseline code plus exactly the one offerItem line inside the def table.
{
	const cur = fnLines(pl, "local function MetaReminderRow(") || [];
	const hits = cur.filter((l) => l === OFFER_LINE).length;
	check(hits === 1, `${P}: MetaReminderRow has "offerItem = opts and opts.offerItem or nil," exactly once, two tabs in (found ${hits})`);
	const di = cur.indexOf(OFFER_LINE);
	const defOpen = cur.findIndex((l) => l === "\tlocal def = {");
	const defClose = cur.findIndex((l, i) => i > defOpen && l === "\t}");
	check(defOpen >= 0 && di > defOpen && di < defClose, `${P}: the offerItem line sits inside MetaReminderRow's "local def = {" table`);
	check(norm(cur.filter((l) => l !== OFFER_LINE)) === norm(fnLines(pb, "local function MetaReminderRow(")), `${P}: MetaReminderRow's code is otherwise identical to baseline`);
}

// P3. ns:MetaReminderOfferItem: one map read, no allocation.
{
	const f = fnLines(pl, "function ns:MetaReminderOfferItem(spellID)");
	check(
		norm(f) === "function ns:MetaReminderOfferItem(spellID) local def = metaReminderDefsBySpellID[spellID] return def and def.offerItem or nil end",
		`${P}: ns:MetaReminderOfferItem(spellID) is "local def = metaReminderDefsBySpellID[spellID]; return def and def.offerItem or nil"`
	);
}

// P4. OfferItemInBags: file-local above ns:MetaReminderSuggestionKeys, guarded item-count read.
{
	const decl = "local function OfferItemInBags(itemID)";
	const oi = pl.findIndex((l) => l.startsWith(decl));
	const si = pl.findIndex((l) => l.startsWith("function ns:MetaReminderSuggestionKeys()"));
	check(oi >= 0 && si > oi, `${P}: ${decl} is declared above ns:MetaReminderSuggestionKeys (upvalue order)`);
	const t = norm(fnLines(pl, decl));
	check(t.includes("if not (C_Item and C_Item.GetItemCount) then return false end"), `${P}: OfferItemInBags returns false when C_Item.GetItemCount is missing`);
	check(t.includes("local ok, count = pcall(C_Item.GetItemCount, itemID)"), `${P}: OfferItemInBags reads the count through pcall`);
	check(/issecretvalue\(count\)/.test(t) && /type\(count\) == "number"/.test(t) && /count > 0/.test(t), `${P}: OfferItemInBags tests issecretvalue(count), type(count) == "number" and count > 0`);
	check(t.length > 0 && !/[{}]/.test(t), `${P}: OfferItemInBags builds no table`);
}

// P5. ns:MetaReminderSuggestionKeys: item-offered rows ask the bags, every other row asks the known spell as before.
{
	const exp =
		"function ns:MetaReminderSuggestionKeys() wipe(metaReminderSuggestionKeys) for _, def in ipairs(META_REMINDER_DEFS) do local offered if def.offerItem then offered = OfferItemInBags(def.offerItem) else offered = ns:ResolveSpellKnown(def.knownID, false) == true end if offered then metaReminderSuggestionKeys[#metaReminderSuggestionKeys + 1] = def.key end end return metaReminderSuggestionKeys end";
	check(norm(fnLines(pl, "function ns:MetaReminderSuggestionKeys()")) === exp, `${P}: ns:MetaReminderSuggestionKeys branches on def.offerItem (OfferItemInBags) and keeps ns:ResolveSpellKnown(def.knownID, false) == true for every other row`);
}

// P6. Unchanged code: the readers, the group helper, the Forever block, and no code line removed
// except the one SuggestionKeys condition the branch replaces.
{
	for (const decl of [
		"local function MetaReminderGroup(",
		"function ns:MetaReminderDef(",
		"function ns:MetaReminderKnownID(",
		"function ns:ReminderCastID(",
		"function ns:ReminderUseItems(",
		"function ns:ReminderCastUnit(",
		"function ns:ApplyMetaReminderDef(",
	]) {
		const a = fnLines(pl, decl);
		check(a !== null && norm(a) === norm(fnLines(pb, decl)), `${P}: ${decl.replace(/^(local )?function /, "").replace(/\($/, "")} code identical to baseline`);
	}
	const blockOf = (ls) => {
		const s = ls.findIndex((l) => /^if ns\.CLIENT_IS_FOREVER then\s*$/.test(l));
		const e = s < 0 ? -1 : ls.findIndex((l, i) => i > s && /^end\s*$/.test(l));
		return s < 0 || e < 0 ? null : ls.slice(s, e + 1);
	};
	const b = blockOf(pl);
	check(b !== null && norm(b) === norm(blockOf(pb)), `${P}: the Forever group block's code is identical to baseline (Well-Rested has no group)`);
	check(!pl.some((l) => /MetaReminderGroup\(/.test(code(l)) && /\b(429959|211527)\b/.test(code(l))), `${P}: no MetaReminderGroup call names 429959 or 211527`);
	const { removed } = diffOf(pb, pl);
	const allowed = ["if ns:ResolveSpellKnown(def.knownID, false) == true then"];
	const bad = removed.filter((l) => !allowed.includes(l));
	check(bad.length === 0, `${P}: no code line removed or changed beyond the replaced SuggestionKeys condition (found ${bad.length}: ${bad.slice(0, 3).join(" | ")})`);
	const doc = (l) => /^--/.test(l) && /offerItem/.test(l);
	const rowFn = fnRange(pl, "local function MetaReminderRow(");
	check(rowFn !== null && pl.slice(Math.max(0, rowFn[0] - 25), rowFn[0]).some(doc), `${P}: the comment block above MetaReminderRow documents offerItem`);
}

// ---------------------------------------------------------------------------------------------
// Core.lua (SBAG-03 load rule and tooltip reason)
// ---------------------------------------------------------------------------------------------
const C = "Core.lua";
const { cur: cl, base: cb } = load(C);
const OFFER_COND = "entry.trackerType == ns.KIND.META_REMINDER and ns.MetaReminderOfferItem and ns:MetaReminderOfferItem(entry.spellID)";
{
	const t = norm(fnLines(cl, "function ns:RebuildTrackerLoad()"));
	const seq = `elseif type(entry.spellID) ~= "number" then loaded = true elseif ${OFFER_COND} then loaded = true else local knownID = entry.spellID`;
	check(t.includes(seq), `${C}: RebuildTrackerLoad loads an item-offered metaReminder (new elseif after the non-number branch, before the known-spell branch)`);
	check((t.match(/ns:ResolveSpellKnown\(knownID, true\) == true/g) || []).length === 1, `${C}: RebuildTrackerLoad still asks ns:ResolveSpellKnown(knownID, true) for every other tracker`);
	const r = norm(fnLines(cl, "function ns:TrackerLoadReason(key)"));
	const rseq = `return LOAD_REASON_NEVER end if entry and ${OFFER_COND} then return nil end if entry and entry.trackerType == ns.KIND.META_REMINDER and ns.MetaReminderKnownID and ns.SpellLabel then`;
	check(r.includes(rseq), `${C}: TrackerLoadReason returns nil for an item-offered row after the Never check, before the SpellLabel branch`);
	const strip = (ls) => {
		let out = ls.slice();
		for (const decl of ["function ns:TrackerLoadReason(key)", "function ns:RebuildTrackerLoad()"]) {
			const rg = fnRange(out, decl);
			if (rg) out = out.slice(0, rg[0]).concat(out.slice(rg[1] + 1));
		}
		return out;
	};
	check(norm(strip(cl)) === norm(strip(cb)), `${C}: every code line outside RebuildTrackerLoad and TrackerLoadReason identical to baseline`);
	const { removed } = diffOf(cb, cl);
	check(removed.length === 0, `${C}: no code line removed or changed (found ${removed.length}: ${removed.slice(0, 3).join(" | ")})`);
	const bi = cl.findIndex((l) => l === '\t\tif event == "BAG_UPDATE_DELAYED" then');
	check(bi >= 0 && cl.slice(bi + 1, bi + 8).some((l) => /^\s*--/.test(l) && /sleeping bag/i.test(l)), `${C}: the BAG_UPDATE_DELAYED re-mark comment names the sleeping bag`);
}

// ---------------------------------------------------------------------------------------------
// ReminderClick.lua (SBAG-04: the click path is reused unchanged; comments only)
// ---------------------------------------------------------------------------------------------
const R = "ReminderClick.lua";
const { cur: rl, base: rb } = load(R);
{
	check(JSON.stringify(codeLines(rl)) === JSON.stringify(codeLines(rb)), `${R}: every code line identical to baseline (the familiar click path is reused as is)`);
	check(rl.slice(0, 15).some((l) => /^--/.test(l) && /sleeping bag/i.test(l)), `${R}: the header comment names the sleeping bag as an item reminder`);
}

console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed");
process.exit(failures ? 1 : 0);
