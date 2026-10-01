#!/usr/bin/env node
// Converts every PNG in Media/Source to an uncompressed BLP2 (BGRA8888, full mip chain) in
// Media/Textures. No dependencies: PNG decoding uses node's zlib, BLP writing is by hand.
// Usage: node scripts/png2blp.js [file.png ...]   (no arguments converts the whole folder)
//
// Uncompressed BGRA matches Blizzard's own interface/common/commonsidetab.blp (compression 3,
// alphaDepth 8, alphaType 8). Mips are generated so the 64px source stays clean when drawn at
// 30px. Mip colour is alpha-weighted, so transparent pixels never darken the outline.

"use strict";
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const repo = path.resolve(__dirname, "..");
const srcDir = path.join(repo, "Media", "Source");
const outDir = path.join(repo, "Media", "Textures");

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function fail(msg) {
	console.error("ERROR: " + msg);
	process.exit(1);
}

// Decodes an 8-bit, non-interlaced PNG of any colour type into RGBA.
function decodePng(file) {
	const b = fs.readFileSync(file);
	if (b.length < 8 || !b.subarray(0, 8).equals(PNG_SIGNATURE)) fail(file + " is not a PNG");
	let w, h, depth, type, interlace, palette, trns;
	const idat = [];
	for (let p = 8; p < b.length; ) {
		const len = b.readUInt32BE(p);
		const kind = b.toString("latin1", p + 4, p + 8);
		const data = b.subarray(p + 8, p + 8 + len);
		if (kind === "IHDR") {
			w = data.readUInt32BE(0);
			h = data.readUInt32BE(4);
			depth = data[8];
			type = data[9];
			interlace = data[12];
		} else if (kind === "PLTE") palette = data;
		else if (kind === "tRNS") trns = data;
		else if (kind === "IDAT") idat.push(data);
		else if (kind === "IEND") break;
		p += 12 + len;
	}
	if (depth !== 8) fail(file + ": only 8-bit PNGs are supported (got " + depth + "-bit)");
	if (interlace) fail(file + ": interlaced PNGs are not supported");
	const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[type];
	if (!channels) fail(file + ": unknown PNG colour type " + type);

	const raw = zlib.inflateSync(Buffer.concat(idat));
	const stride = w * channels;
	// A short buffer would decode the missing rows as transparent black instead of failing.
	if (raw.length < h * (stride + 1)) fail(file + ": image data truncated");
	const pix = Buffer.alloc(stride * h);
	for (let y = 0; y < h; y++) {
		const filter = raw[y * (stride + 1)];
		if (filter > 4) fail(file + ": invalid filter type " + filter + " on row " + y);
		const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
		for (let x = 0; x < stride; x++) {
			const a = x >= channels ? pix[y * stride + x - channels] : 0;
			const up = y > 0 ? pix[(y - 1) * stride + x] : 0;
			const c = y > 0 && x >= channels ? pix[(y - 1) * stride + x - channels] : 0;
			let v = line[x];
			if (filter === 1) v += a;
			else if (filter === 2) v += up;
			else if (filter === 3) v += (a + up) >> 1;
			else if (filter === 4) {
				const pp = a + up - c;
				const pa = Math.abs(pp - a),
					pb = Math.abs(pp - up),
					pc = Math.abs(pp - c);
				v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c;
			}
			pix[y * stride + x] = v & 255;
		}
	}

	const rgba = Buffer.alloc(w * h * 4);
	for (let i = 0; i < w * h; i++) {
		const s = pix.subarray(i * channels, (i + 1) * channels);
		let r, g, bl, al;
		if (type === 0) [r, g, bl, al] = [s[0], s[0], s[0], trns && trns.readUInt16BE(0) === s[0] ? 0 : 255];
		else if (type === 2) {
			// tRNS for RGB holds one 16-bit key colour; pixels matching it are fully transparent.
			const key =
				trns &&
				trns.length >= 6 &&
				trns.readUInt16BE(0) === s[0] &&
				trns.readUInt16BE(2) === s[1] &&
				trns.readUInt16BE(4) === s[2];
			[r, g, bl, al] = [s[0], s[1], s[2], key ? 0 : 255];
		}
		else if (type === 3) {
			if (!palette || s[0] * 3 + 2 >= palette.length) fail(file + ": palette index out of range");
			[r, g, bl] = palette.subarray(s[0] * 3, s[0] * 3 + 3);
			al = trns && s[0] < trns.length ? trns[s[0]] : 255;
		} else if (type === 4) [r, g, bl, al] = [s[0], s[0], s[0], s[1]];
		else [r, g, bl, al] = s;
		rgba.set([r, g, bl, al], i * 4);
	}
	return { w, h, rgba };
}

// Halves an RGBA image with an alpha-weighted 2x2 box filter.
function halve(img) {
	const w = Math.max(1, img.w >> 1),
		h = Math.max(1, img.h >> 1);
	const out = Buffer.alloc(w * h * 4);
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			let r = 0,
				g = 0,
				b = 0,
				a = 0,
				n = 0;
			for (let dy = 0; dy < 2; dy++) {
				for (let dx = 0; dx < 2; dx++) {
					const sx = Math.min(img.w - 1, x * 2 + dx),
						sy = Math.min(img.h - 1, y * 2 + dy);
					const i = (sy * img.w + sx) * 4;
					const al = img.rgba[i + 3];
					r += img.rgba[i] * al;
					g += img.rgba[i + 1] * al;
					b += img.rgba[i + 2] * al;
					a += al;
					n++;
				}
			}
			const o = (y * w + x) * 4;
			if (a > 0) out.set([Math.round(r / a), Math.round(g / a), Math.round(b / a)], o);
			out[o + 3] = Math.round(a / n);
		}
	}
	return { w, h, rgba: out };
}

function toBgra(img) {
	const out = Buffer.alloc(img.rgba.length);
	for (let i = 0; i < img.rgba.length; i += 4) {
		out[i] = img.rgba[i + 2];
		out[i + 1] = img.rgba[i + 1];
		out[i + 2] = img.rgba[i];
		out[i + 3] = img.rgba[i + 3];
	}
	return out;
}

function writeBlp(img, file) {
	const isPow2 = (n) => n > 0 && (n & (n - 1)) === 0;
	if (!isPow2(img.w) || !isPow2(img.h)) fail(file + ": " + img.w + "x" + img.h + " is not a power of two");

	const mips = [toBgra(img)];
	for (let m = img; (m.w > 1 || m.h > 1) && mips.length < 16; ) {
		m = halve(m);
		mips.push(toBgra(m));
	}

	const header = Buffer.alloc(1172); // 20 header + 16 offsets + 16 sizes + 256-entry palette
	header.write("BLP2", 0, "latin1");
	header.writeUInt32LE(1, 4); // type: DirectX-style, not JPEG
	header[8] = 3; // compression: uncompressed BGRA
	header[9] = 8; // alpha depth
	header[10] = 8; // alpha type
	header[11] = 1; // has mips
	header.writeUInt32LE(img.w, 12);
	header.writeUInt32LE(img.h, 16);
	let offset = header.length;
	mips.forEach((m, i) => {
		header.writeUInt32LE(offset, 20 + i * 4);
		header.writeUInt32LE(m.length, 84 + i * 4);
		offset += m.length;
	});
	fs.writeFileSync(file, Buffer.concat([header, ...mips]));
	return mips.length;
}

if (process.argv.length <= 2 && !fs.existsSync(srcDir)) fail("missing " + srcDir);
const inputs = process.argv.length > 2
	? process.argv.slice(2).map((f) => path.resolve(f))
	: fs.readdirSync(srcDir).filter((f) => /\.png$/i.test(f)).map((f) => path.join(srcDir, f));
if (inputs.length === 0) fail("no PNGs found in " + srcDir);

const outName = (input) => path.basename(input).replace(/\.png$/i, ".blp");
const seen = new Map();
for (const input of inputs) {
	const key = outName(input).toLowerCase();
	if (seen.has(key)) fail(seen.get(key) + " and " + input + " both write " + outName(input));
	seen.set(key, input);
}

fs.mkdirSync(outDir, { recursive: true });
for (const input of inputs) {
	const img = decodePng(input);
	const out = path.join(outDir, outName(input));
	const levels = writeBlp(img, out);
	console.log(path.relative(repo, input) + " -> " + path.relative(repo, out) + " (" + img.w + "x" + img.h + ", " + levels + " mips)");
}

// A BLP whose PNG was removed or renamed keeps deploying and shipping. Report it; never delete.
const sources = new Set(
	(fs.existsSync(srcDir) ? fs.readdirSync(srcDir) : [])
		.filter((f) => /\.png$/i.test(f))
		.map((f) => f.replace(/\.png$/i, "").toLowerCase()),
);
for (const f of fs.readdirSync(outDir)) {
	if (/\.blp$/i.test(f) && !sources.has(f.replace(/\.blp$/i, "").toLowerCase()))
		console.warn("WARNING: " + path.join("Media", "Textures", f) + " has no matching PNG in Media/Source");
}
