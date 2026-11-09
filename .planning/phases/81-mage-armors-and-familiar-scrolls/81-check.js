#!/usr/bin/env node
// Phase 81 source gate (MREM-07, MREM-18, CLICK-07). No Lua interpreter exists on this machine, so
// Providers.lua, ReminderClick.lua and Core.lua are checked by parsing their text.
//
// Usage: node 81-check.js [--root <dir>]
//   --root  read the three files from <dir> instead of the repo (planner's mock test only).
// Baseline, per file: the last commit that touched it and is not a Phase 81 commit (subject
// "<type>(81-NN): ..."). That is Phase 80's result (or Phase 82's, if 82 ran first), so the gate
// never depends on what Phase 81 itself committed.
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
	const rev = sh(`git log -1 --format=%H --invert-grep -E "--grep=^[a-z]+\\(81-" -- ${f}`).trim();
	return { rev: rev.slice(0, 7), text: sh(`git show ${rev}:${f}`) };
};

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

const code = (l) => l.replace(/--.*$/, "");
const comment = (l) => {
	const i = l.indexOf("--");
	return i < 0 ? "" : l.slice(i);
};
const isCommentOrBlank = (l) => /^\s*(--.*)?$/.test(l);
// A top-level function from its declaration to its first column-0 "end": [start, end] or null.
const fnRange = (ls, decl) => {
	const s = ls.findIndex((l) => l.startsWith(decl));
	if (s < 0) return null;
	const e = ls.findIndex((l, i) => i > s && /^end\s*$/.test(l));
	return [s, e];
};
const fnLines = (ls, decl) => {
	const r = fnRange(ls, decl);
	return r ? ls.slice(r[0], r[1] + 1) : null;
};
const fnText = (ls, decl) => {
	const f = fnLines(ls, decl);
	return f ? f.join("\n") : null;
};
// Line diff against the baseline: { added: [...], removed: [...] }. Pure JS on lines split at
// /\r?\n/ (no git, so no autocrlf or .gitattributes normalisation): common prefix and suffix
// trimmed, then an LCS over the changed middle.
const diffOf = (baseText, curText) => {
	const a = baseText.split(/\r?\n/);
	const b = curText.split(/\r?\n/);
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

// ---------------------------------------------------------------------------------------------
// Providers.lua (MREM-07, MREM-18, CLICK-07 data side)
// ---------------------------------------------------------------------------------------------
const P = "Providers.lua";
const pBase = baseOf(P);
const pRaw = readCur(P);
console.log(`${P} baseline: ${pBase.rev}`);
eol(P, pRaw);
const pl = pRaw.split(/\r?\n/);
const pb = pBase.text.split(/\r?\n/);

const USE_ITEMS_LINE = "\t\tuseItems = opts and opts.useItems or nil,";
const ARMOR_ROWS = ["MetaReminderRow(10220, 30)", "MetaReminderRow(22783, 30)"];
const FAMILIAR_ROW = "MetaReminderRow(1302303, 60, 1296017, nil, false, { useItems = { { 277493, 25 }, { 277483, 16 }, { 275069, 5 } } })";
const NEW_ROWS = [...ARMOR_ROWS, FAMILIAR_ROW];
const NEW_GROUPS = [
	[7301, 10220, 22783],
	[1302303, 1302285, 1296202],
];
const FROST_ROW = "MetaReminderRow(7301, 30) -- Mage: Frost Armor";

// P1. MetaReminderGroup, ns:ReminderCastID, ns:ReminderCastUnit unchanged.
for (const decl of ["local function MetaReminderGroup(", "function ns:ReminderCastID(", "function ns:ReminderCastUnit("]) {
	const a = fnText(pl, decl);
	check(a !== null && a === fnText(pb, decl), `${P}: ${decl.replace(/^(local )?function /, "").slice(0, -1)} body identical to baseline`);
}

// P2. MetaReminderRow = baseline body plus exactly the one useItems line inside the def table.
{
	const cur = fnLines(pl, "local function MetaReminderRow(") || [];
	const hits = cur.filter((l) => l === USE_ITEMS_LINE).length;
	check(hits === 1, `${P}: MetaReminderRow has the line "useItems = opts and opts.useItems or nil," exactly once, two tabs in (found ${hits})`);
	const di = cur.indexOf(USE_ITEMS_LINE);
	const defOpen = cur.findIndex((l) => l === "\tlocal def = {");
	const defClose = cur.findIndex((l, i) => i > defOpen && l === "\t}");
	check(di > defOpen && di < defClose && defOpen >= 0, `${P}: the useItems line sits inside MetaReminderRow's "local def = {" table`);
	check(JSON.stringify(cur.filter((l) => l !== USE_ITEMS_LINE)) === JSON.stringify(fnLines(pb, "local function MetaReminderRow(")), `${P}: MetaReminderRow is otherwise byte-identical to baseline`);
}

// P3. Rows: the baseline rows unchanged and in order, plus the three new rows directly after Frost Armor.
{
	const rows = pl.filter((l) => l.startsWith("MetaReminderRow("));
	const baseRows = pb.filter((l) => l.startsWith("MetaReminderRow("));
	const fi = rows.indexOf(FROST_ROW);
	check(fi >= 0 && baseRows.includes(FROST_ROW), `${P}: Frost Armor row unchanged ("${FROST_ROW}")`);
	const got = fi >= 0 ? rows.slice(fi + 1, fi + 1 + NEW_ROWS.length) : [];
	NEW_ROWS.forEach((r, k) => {
		const l = got[k] || "";
		check(code(l).trim() === r, `${P}: row ${k + 1} after Frost Armor is ${r} (got ${code(l).trim() || "none"})`);
		check(/^-- Mage: /.test(comment(l)) && comment(l).includes("(unverified in game)"), `${P}: row ${r.slice(16, r.indexOf(","))} has a trailing "-- Mage: ..." comment with "(unverified in game)"`);
	});
	const rest = rows.filter((l) => !NEW_ROWS.includes(code(l).trim()));
	check(JSON.stringify(rest) === JSON.stringify(baseRows), `${P}: every baseline row byte-identical and in order, no other row added (baseline ${baseRows.length}, other rows ${rest.length})`);
	const fam = rows.find((l) => code(l).trim() === FAMILIAR_ROW) || "";
	check(fam.includes("1296017") && !/277483, 16 \}, \{ 277493/.test(fam), `${P}: familiar row: knownID 1296017, castID false, useItems Cat > Frog > Rat (never sorted by ID)`);
	check(!pl.some((l) => /^\s*MetaReminderRow\((30482|428741),/.test(l)), `${P}: no Molten Armor row`);
}

// P4. Forever block: the baseline calls unchanged, then the two Phase 81 calls appended last.
const blockOf = (ls) => {
	const idx = ls.map((l, i) => (/^if ns\.CLIENT_IS_FOREVER then\s*$/.test(l) ? i : -1)).filter((i) => i >= 0);
	const s = idx.length ? idx[0] : -1;
	const e = s < 0 ? -1 : ls.findIndex((l, i) => i > s && /^end\s*$/.test(l));
	return { s, e, n: idx.length };
};
const callsOf = (ls) =>
	[...ls.map(code).join("\n").matchAll(/MetaReminderGroup\(([^)]*)\)/g)].map((m) =>
		m[1]
			.split(",")
			.map((x) => x.trim())
			.filter(Boolean)
			.map(Number)
	);
const B = blockOf(pl);
const BB = blockOf(pb);
check(B.n === 1 && B.e > B.s, `${P}: exactly one column-0 Forever block (found ${B.n})`);
if (B.n === 1 && BB.n === 1) {
	const lastRow = pl.reduce((acc, l, i) => (l.startsWith("MetaReminderRow(") ? i : acc), -1);
	check(B.s > lastRow, `${P}: the block sits after every MetaReminderRow call`);
	const block = pl.slice(B.s + 1, B.e);
	const calls = callsOf(block);
	const baseCalls = callsOf(pb.slice(BB.s + 1, BB.e));
	check(block.every((l) => isCommentOrBlank(l) || !l.includes("--")), `${P}: no trailing or in-expression comment inside the block`);
	check(JSON.stringify(calls.slice(0, baseCalls.length)) === JSON.stringify(baseCalls), `${P}: the block's first ${baseCalls.length} calls are the baseline's, unchanged and in order`);
	const added = calls.slice(baseCalls.length);
	check(added.length === NEW_GROUPS.length, `${P}: exactly ${NEW_GROUPS.length} calls appended after them (found ${added.length})`);
	NEW_GROUPS.forEach((exp, i) => check(JSON.stringify(added[i]) === JSON.stringify(exp), `${P}: appended call ${i + 1} = MetaReminderGroup(${exp.join(", ")}) (got ${added[i] ? added[i].join(", ") : "none"})`));
	const starts = block.map((l, i) => (/^\tMetaReminderGroup\(/.test(l) ? i : -1)).filter((i) => i >= 0).slice(baseCalls.length);
	check(starts.length === NEW_GROUPS.length && starts.every((i) => i > 0 && /^\t--/.test(block[i - 1])), `${P}: each appended call has a one-tab comment line directly above it`);
	// The familiar is in no call with Arcane Intellect or an armor; no Phase 81 row is in two calls.
	const famCalls = calls.filter((c) => c.some((id) => [1302303, 1302285, 1296202].includes(id)));
	check(famCalls.length === 1 && !famCalls[0].some((id) => [1459, 7301, 10220, 22783].includes(id)), `${P}: the familiar tiers are in one call, without Arcane Intellect or an armor`);
	const dup = [7301, 10220, 22783, 1302303].filter((id) => calls.filter((c) => c.includes(id)).length > 1);
	check(dup.length === 0, `${P}: no Phase 81 row ID appears in two group calls (found ${dup.join(", ") || "none"})`);
	// Outside the block: the same group calls as the baseline.
	const outside = (ls, b) => {
		const a = ls.findIndex((l) => l.startsWith("local function MetaReminderGroup("));
		const z = ls.findIndex((l) => l.startsWith("function ns:MetaReminderDef("));
		return ls.slice(a + 1, z).filter((_, k) => k + a + 1 < b.s || k + a + 1 > b.e);
	};
	check(JSON.stringify(callsOf(outside(pl, B))) === JSON.stringify(callsOf(outside(pb, BB))), `${P}: the group calls outside the block are the baseline's`);
}

// P5. The accessor ns:ReminderUseItems, between ns:ReminderCastID and ns:ReminderCastUnit.
{
	const r = fnRange(pl, "function ns:ReminderUseItems(entry)");
	const castR = fnRange(pl, "function ns:ReminderCastID(");
	const unitR = fnRange(pl, "function ns:ReminderCastUnit(");
	check(r !== null && pl.filter((l) => l.startsWith("function ns:ReminderUseItems(")).length === 1, `${P}: function ns:ReminderUseItems(entry) defined exactly once`);
	if (r && castR && unitR) {
		check(r[0] > castR[1] && r[1] < unitR[0], `${P}: ns:ReminderUseItems sits after ns:ReminderCastID and before ns:ReminderCastUnit`);
		const body = pl.slice(r[0] + 1, r[1]).map(code).join("\n");
		check(body.includes("ns.KIND.META_REMINDER") && body.includes("metaReminderDefsBySpellID[entry.spellID]") && body.includes(".useItems"), `${P}: ns:ReminderUseItems reads metaReminderDefsBySpellID[entry.spellID].useItems for a metaReminder only`);
		check(!body.includes("{") && !/C_\w+\./.test(body) && !/\bpairs\(|\bipairs\(/.test(body), `${P}: ns:ReminderUseItems builds no table, calls no game API and loops over nothing`);
	}
}

// P6. Diff vs baseline: no code line removed; every added code line is one of Phase 81's.
{
	const d = diffOf(pBase.text, pRaw);
	const removedCode = d.removed.filter((l) => !isCommentOrBlank(l));
	check(removedCode.length === 0, `${P}: no code line removed or changed (found ${removedCode.length}: ${removedCode.slice(0, 3).join(" | ")})`);
	const r = fnRange(pl, "function ns:ReminderUseItems(entry)");
	const accessor = r ? pl.slice(r[0], r[1] + 1) : [];
	const allowed = (l) =>
		l === USE_ITEMS_LINE ||
		NEW_ROWS.includes(code(l).trim()) ||
		NEW_GROUPS.some((g) => l === `\tMetaReminderGroup(${g.join(", ")})`) ||
		accessor.includes(l);
	const stray = d.added.filter((l) => !isCommentOrBlank(l) && !allowed(l));
	check(stray.length === 0, `${P}: every added code line is the useItems line, a new row, a new group call or the accessor (stray: ${stray.slice(0, 3).join(" | ") || "none"})`);
}

// ---------------------------------------------------------------------------------------------
// ReminderClick.lua (CLICK-07)
// ---------------------------------------------------------------------------------------------
const R = "ReminderClick.lua";
const rBase = baseOf(R);
const rRaw = readCur(R);
console.log(`${R} baseline: ${rBase.rev}`);
eol(R, rRaw);
const rl = rRaw.split(/\r?\n/);
const rb = rBase.text.split(/\r?\n/);
const bodyCode = (ls, decl) => (fnLines(ls, decl) || []).map(code);
const has = (arr, s) => arr.some((l) => l.includes(s));
const trimmed = (arr) => arr.map((l) => l.trim());

// R1. CreateOverlay still writes type1 = "spell" and seeds the cache with it.
{
	const c = trimmed(bodyCode(rl, "local function CreateOverlay("));
	check(c.includes('overlay:SetAttribute("type1", "spell")'), `${R}: CreateOverlay still writes type1 = "spell"`);
	check(c.includes('overlay._actionType = "spell"'), `${R}: CreateOverlay seeds overlay._actionType = "spell", so a spell overlay never rewrites type1`);
}

// R2. PickUseItem: a file-local declared above Flush (upvalue order trap), guarded reads.
{
	const pr = fnRange(rl, "local function PickUseItem(");
	const fr = fnRange(rl, "local function Flush(");
	check(pr !== null, `${R}: local function PickUseItem( is defined`);
	if (pr && fr) {
		check(pr[1] < fr[0], `${R}: PickUseItem is declared above Flush`);
		const c = rl.slice(pr[0], pr[1] + 1).map(code).join("\n");
		check(/C_Item and C_Item\.GetItemCount/.test(c) || /not \(C_Item and C_Item\.GetItemCount\)/.test(c), `${R}: PickUseItem returns nil when C_Item.GetItemCount is missing`);
		check(c.includes("pcall(C_Item.GetItemCount"), `${R}: PickUseItem reads the count through pcall(C_Item.GetItemCount, ...)`);
		check(c.includes('UnitLevel("player")'), `${R}: PickUseItem reads UnitLevel("player")`);
		check((c.match(/issecretvalue\(/g) || []).length >= 2, `${R}: PickUseItem tests the level and the count with issecretvalue before comparing`);
		check(c.includes('"item:"'), `${R}: PickUseItem returns the "item:<id>" attribute string`);
		check(!/sort\(/.test(c), `${R}: PickUseItem never sorts the list (the order is the tier order)`);
	}
}

// R3. Place: item path written only on change, the other action attribute cleared, unit unchanged.
{
	const pl3 = fnLines(rl, "local function Place(") || [];
	check(pl3[0] === "local function Place(overlay, icon, castName, itemAttr, unit)", `${R}: Place signature is (overlay, icon, castName, itemAttr, unit) (got ${pl3[0] || "none"})`);
	const t = trimmed(pl3.map(code));
	const guarded = (guard, write) => {
		const i = t.indexOf(write);
		return i > 0 && t[i - 1] === guard;
	};
	check(t.includes('local actionType = itemAttr and "item" or "spell"'), `${R}: Place derives actionType from itemAttr`);
	check(t.includes("local spellAttr = not itemAttr and castName or nil"), `${R}: Place clears the spell attribute for an item overlay`);
	check(guarded("if overlay._actionType ~= actionType then", 'overlay:SetAttribute("type1", actionType)'), `${R}: type1 is written in Place, on change only`);
	check(guarded("if overlay._castName ~= spellAttr then", 'overlay:SetAttribute("spell", spellAttr)'), `${R}: spell is written on change only, from spellAttr`);
	check(guarded("if overlay._itemAttr ~= itemAttr then", 'overlay:SetAttribute("item", itemAttr)'), `${R}: item is written on change only (nil clears it for a reused overlay)`);
	check(guarded("if overlay._unit ~= unit then", 'overlay:SetAttribute("unit", unit)'), `${R}: the unit write is unchanged`);
	check(!t.some((l) => /^overlay:SetAttribute\("spell", castName\)$/.test(l)), `${R}: the old spell write from castName is replaced, not duplicated`);
}

// R4. Flush: combat guard first, WR-05 unchanged, the item pick, Place with itemAttr.
{
	const f = trimmed(bodyCode(rl, "local function Flush("));
	check(f[1] === "if InCombatLockdown() then", `${R}: Flush still opens with the InCombatLockdown() guard`);
	check(f.includes("local castID = entry and ns:ReminderCastID(entry)"), `${R}: the castID line is unchanged`);
	check(f.includes("if castID and ns:ResolveSpellKnown(castID, false) ~= true then"), `${R}: the WR-05 known check is unchanged`);
	check(has(f, "ns:ReminderUseItems(entry)") && has(f, "PickUseItem("), `${R}: Flush asks ns:ReminderUseItems(entry) and picks with PickUseItem`);
	check(f.includes("if castName or itemAttr then"), `${R}: Flush places an overlay for a resolved spell name or a picked item`);
	check(f.includes("if Place(overlay, icon, castName, itemAttr, ns:ReminderCastUnit(entry)) then"), `${R}: Flush passes itemAttr to Place`);
	check(f.includes("elseif castID then"), `${R}: the unresolved-name skip is unchanged (no skip for "no usable scroll")`);
}

// R5. Everything outside CreateOverlay, PickUseItem, Place and Flush: code unchanged.
{
	const strip = (ls) => {
		const drop = new Set();
		for (const d of ["local function CreateOverlay(", "local function PickUseItem(", "local function Place(", "local function Flush("]) {
			const r = fnRange(ls, d);
			if (r) for (let i = r[0]; i <= r[1]; i++) drop.add(i);
		}
		return ls.filter((l, i) => !drop.has(i) && !isCommentOrBlank(l));
	};
	check(JSON.stringify(strip(rl)) === JSON.stringify(strip(rb)), `${R}: every code line outside CreateOverlay/PickUseItem/Place/Flush is byte-identical to baseline (state driver, combat deferral, events)`);
}

// ---------------------------------------------------------------------------------------------
// Core.lua (CLICK-07: re-pick after a bag change)
// ---------------------------------------------------------------------------------------------
const C = "Core.lua";
const cBase = baseOf(C);
const cRaw = readCur(C);
console.log(`${C} baseline: ${cBase.rev}`);
eol(C, cRaw);
{
	const cl = cRaw.split(/\r?\n/);
	const d = diffOf(cBase.text, cRaw);
	const addedCode = d.added.filter((l) => !isCommentOrBlank(l));
	check(d.removed.filter((l) => !isCommentOrBlank(l)).length === 0, `${C}: no code line removed or changed`);
	check(JSON.stringify(addedCode) === JSON.stringify(["\t\t\tns:MarkReminderClicksDirty()"]), `${C}: the only added code line is one ns:MarkReminderClicksDirty() call (found ${JSON.stringify(addedCode)})`);
	const s = cl.indexOf('\t\tif event == "BAG_UPDATE_DELAYED" then');
	const e = s < 0 ? -1 : cl.findIndex((l, i) => i > s && l === "\t\tend");
	const inside = s >= 0 && e > s ? cl.slice(s + 1, e) : [];
	check(inside.includes("\t\t\tns:ReconcileTrackedItemCounts()") && inside.includes("\t\t\tns:MarkReminderClicksDirty()"), `${C}: the call sits in the existing BAG_UPDATE_DELAYED-only branch, beside ns:ReconcileTrackedItemCounts()`);
	check(!cl.some((l) => /RegisterEvent\(.*PLAYER_LEVEL_UP/.test(code(l))), `${C}: no PLAYER_LEVEL_UP hook`);
}

done();
