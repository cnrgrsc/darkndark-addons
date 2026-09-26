// Builds DarkndarkTalents/Data/Builds.lua from public data:
//   murlok.io  -> top players per spec/bracket, talent popularity, stats, enchants, gems
//   raider.io  -> each top player's real talent import string (loadout_text)
// For every spec/bracket we pick, per hero tree, the real player loadout that
// best matches murlok's bracket-specific talent popularity (a "typical" build).
//
// Usage:
//   node tools/update-builds.mjs                     all specs
//   node tools/update-builds.mjs paladin/retribution only these specs
// Options (env): PLAYERS=20 (top players sampled per bracket)

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.join(ROOT, "DarkndarkTalents", "Data", "Builds.lua");
const CACHE_DIR = path.join(ROOT, "tools", ".cache");
const PLAYERS = Number(process.env.PLAYERS || 20);
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128 Safari/537.36 DarkndarkTalents-data";

// murlok bracket slug -> addon context key
const BRACKETS = { "m+": "mplus", solo: "solo", "2v2": "2v2", "3v3": "3v3", blitz: "blitz", rbg: "rbg" };

const SPECS = {
	"death-knight/blood": 250, "death-knight/frost": 251, "death-knight/unholy": 252,
	"demon-hunter/havoc": 577, "demon-hunter/vengeance": 581,
	"druid/balance": 102, "druid/feral": 103, "druid/guardian": 104, "druid/restoration": 105,
	"evoker/devastation": 1467, "evoker/preservation": 1468, "evoker/augmentation": 1473,
	"hunter/beast-mastery": 253, "hunter/marksmanship": 254, "hunter/survival": 255,
	"mage/arcane": 62, "mage/fire": 63, "mage/frost": 64,
	"monk/brewmaster": 268, "monk/windwalker": 269, "monk/mistweaver": 270,
	"paladin/holy": 65, "paladin/protection": 66, "paladin/retribution": 70,
	"priest/discipline": 256, "priest/holy": 257, "priest/shadow": 258,
	"rogue/assassination": 259, "rogue/outlaw": 260, "rogue/subtlety": 261,
	"shaman/elemental": 262, "shaman/enhancement": 263, "shaman/restoration": 264,
	"warlock/affliction": 265, "warlock/demonology": 266, "warlock/destruction": 267,
	"warrior/arms": 71, "warrior/fury": 72, "warrior/protection": 73,
};

const STAT_KEYS = { "Critical Strike": "crit", Haste: "haste", Mastery: "mastery", Versatility: "vers" };

fs.mkdirSync(CACHE_DIR, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// HTTP with on-disk cache (murlok pages 6h, raider.io profiles 24h)
// ---------------------------------------------------------------------------
async function cachedFetch(url, maxAgeH, asJson) {
	const key = url.replace(/[^a-z0-9]+/gi, "_").slice(0, 180);
	const file = path.join(CACHE_DIR, key + (asJson ? ".json" : ".html"));
	if (fs.existsSync(file) && (Date.now() - fs.statSync(file).mtimeMs) / 3.6e6 < maxAgeH) {
		const txt = fs.readFileSync(file, "utf8");
		return asJson ? JSON.parse(txt) : txt;
	}
	for (let attempt = 1; attempt <= 4; attempt++) {
		const res = await fetch(url, { headers: { "User-Agent": UA } });
		if (res.status === 429 || res.status >= 500) {
			await sleep(2000 * attempt);
			continue;
		}
		const txt = await res.text();
		if (!res.ok) return null;
		fs.writeFileSync(file, txt);
		await sleep(asJson ? 250 : 400); // be polite
		return asJson ? JSON.parse(txt) : txt;
	}
	return null;
}

// ---------------------------------------------------------------------------
// murlok parsing
// ---------------------------------------------------------------------------
// "Herald Of The Sun" -> "Herald of the Sun"
const heroName = (s) => s.replace(/ (Of|The|And)(?= )/g, (m) => m.toLowerCase());
const decode = (s) => s.replace(/&#39;/g, "'").replace(/&amp;/g, "&").replace(/&quot;/g, '"').trim();
const slugify = (s) => s.toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

function section(html, id) {
	// Attribute order varies between pages, so match id anywhere in the tag.
	const m = new RegExp(`<section[^>]*\\sid="${id}"`).exec(html);
	if (!m) return "";
	const end = html.indexOf("<section", m.index + 10);
	return html.slice(m.index, end < 0 ? undefined : end);
}

function parseMurlok(html) {
	// Top players: /character/{region}/{realm}/{name}/pvp|mplus + hero tree + ilvl
	const players = [];
	const top = section(html, "top-ratings");
	const re = /href="\/character\/([a-z]+)\/([^/]+)\/([^/"]+)\/[a-z+]+"[\s\S]*?<div class="h3">([^<]+)<\/div>\s*<div>([^<]+)<\/div>\s*<div>\s*([^<|]+?)\s*\|\s*([^<|]+?)\s*\|\s*(\d+)\s*ilvl[\s\S]*?<div class="h3">([\d,.]+)<\/div>/g;
	for (const m of top.matchAll(re)) {
		players.push({
			region: m[1], realm: decodeURIComponent(m[2]), name: decodeURIComponent(m[3]),
			displayName: decode(m[4]), realmName: decode(m[5]).replace(/\s*\([A-Z]+\)$/, ""),
			hero: heroName(decode(m[7])), ilvl: Number(m[8]), rating: Number(m[9].replace(/[,.]/g, "")),
		});
	}

	// Talent popularity: slug -> count (of 50)
	const popularity = {};
	for (const m of section(html, "talents").matchAll(/talents#([a-z0-9-]+)"[\s\S]*?guide-talent-count">(\d+)</g)) {
		popularity[m[1]] = Math.max(popularity[m[1]] || 0, Number(m[2]));
	}

	// Stats
	const statsHtml = section(html, "stat-priority");
	const pct = {};
	const rating = {};
	for (const m of statsHtml.matchAll(/<span>(\d+)% (Critical Strike|Haste|Mastery|Versatility)<\/span>\s*<span class="h3">\+(\d+)<\/span>/g)) {
		const k = STAT_KEYS[m[2]];
		if (pct[k] === undefined) {
			pct[k] = Number(m[1]);
			rating[k] = Number(m[3]);
		}
	}
	const prioBlock = statsHtml.match(/Stat priority<\/h4>\s*<ol>([\s\S]*?)<\/ol>/);
	const priority = prioBlock ? [...prioBlock[1].matchAll(/<li[^>]*>([^<]+)<\/li>/g)].map((m) => STAT_KEYS[decode(m[1])]).filter(Boolean) : [];

	// Enchants per slot (top pick) and gems
	const enchants = {};
	for (const m of section(html, "enchantments").matchAll(/<h3>([^<]+)<\/h3>[\s\S]*?<h4 class="h3">([^<]+)<\/h4>/g)) {
		enchants[decode(m[1])] = decode(m[2]);
	}
	const gems = [...section(html, "gems").matchAll(/<h4 class="h3">([^<]+)<\/h4>/g)].slice(0, 3).map((m) => decode(m[1]));

	const ilvls = players.map((p) => p.ilvl).filter(Boolean);
	const ilvl = ilvls.length ? Math.round(ilvls.reduce((a, b) => a + b, 0) / ilvls.length) : null;
	const patch = (html.match(/Patch (\d+\.\d+(?:\.\d+)?)/) || [])[1] || null;
	return { players, popularity, stats: { pct, rating, priority }, enchants, gems, ilvl, patch };
}

// ---------------------------------------------------------------------------
// raider.io loadouts
// ---------------------------------------------------------------------------
async function playerLoadout(p, specID) {
	const url = `https://raider.io/api/v1/characters/profile?region=${p.region}&realm=${encodeURIComponent(p.realm)}&name=${encodeURIComponent(p.name)}&fields=talents`;
	const d = await cachedFetch(url, 24, true);
	const t = d && d.talentLoadout;
	if (!t || t.loadout_spec_id !== specID || !t.loadout_text) return null;
	const slugs = new Set();
	for (const n of t.loadout || []) {
		if (n.grantedNode) continue;
		const e = n.node.entries[n.entryIndex] || n.node.entries[0];
		if (e && e.spell && e.spell.name) slugs.add(slugify(e.spell.name));
	}
	return { code: t.loadout_text, slugs };
}

// Average murlok popularity (0-100%) of the talents a loadout takes.
function typicality(l, popularity) {
	let sum = 0, n = 0;
	for (const s of l.slugs) {
		if (popularity[s] !== undefined) { sum += popularity[s]; n++; }
	}
	return n ? Math.round((100 * sum) / n / 50) : 0;
}

// Ranked list of top players with a usable loadout for the addon's player browser.
function playerList(players, loadouts, popularity) {
	const out = [];
	players.forEach((p, i) => {
		const l = loadouts[i];
		if (!l) return;
		out.push({
			rank: i + 1, name: p.displayName || p.name, realm: p.realmName || p.realm, region: p.region.toUpperCase(),
			hero: p.hero, ilvl: p.ilvl, rating: p.rating || null, match: typicality(l, popularity), code: l.code,
		});
	});
	return out;
}

function pickBuilds(players, loadouts, popularity) {
	// Group by hero tree (from murlok), most popular hero tree first.
	const groups = new Map();
	players.forEach((p, i) => {
		const l = loadouts[i];
		if (!l) return;
		if (!groups.has(p.hero)) groups.set(p.hero, []);
		groups.get(p.hero).push(l);
	});
	const heroCounts = {};
	for (const p of players) heroCounts[p.hero] = (heroCounts[p.hero] || 0) + 1;

	const builds = [];
	for (const [hero, list] of groups) {
		// Score = average murlok popularity of the talents this loadout takes.
		let best = null;
		for (const l of list) {
			let sum = 0, n = 0;
			for (const s of l.slugs) {
				if (popularity[s] !== undefined) { sum += popularity[s]; n++; }
			}
			const score = n ? sum / n : 0;
			const dupes = list.filter((o) => o.code === l.code).length;
			const key = score + dupes * 0.5;
			if (!best || key > best.key) best = { key, score, code: l.code };
		}
		builds.push({
			hero,
			code: best.code,
			share: Math.round((100 * heroCounts[hero]) / players.length),
			match: Math.round((100 * best.score) / 50),
			sample: list.length,
		});
	}
	builds.sort((a, b) => b.share - a.share);
	return builds.slice(0, 2);
}

// ---------------------------------------------------------------------------
// Lua output
// ---------------------------------------------------------------------------
function lua(v, indent = "") {
	if (v === null || v === undefined) return "nil";
	if (typeof v === "number") return String(v);
	if (typeof v === "boolean") return v ? "true" : "false";
	if (typeof v === "string") return JSON.stringify(v);
	if (Array.isArray(v)) return "{ " + v.map((x) => lua(x, indent)).join(", ") + " }";
	const inner = indent + "\t";
	const parts = Object.entries(v).map(([k, x]) => {
		const key = /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `[${/^\d+$/.test(k) ? k : JSON.stringify(k)}]`;
		return `${inner}${key} = ${lua(x, inner)},`;
	});
	return "{\n" + parts.join("\n") + "\n" + indent + "}";
}

async function main() {
	const filter = process.argv.slice(2);
	const specKeys = Object.keys(SPECS).filter((k) => !filter.length || filter.includes(k));

	// Merge into existing data so partial runs don't wipe other specs.
	let existing = {};
	const jsonPath = path.join(CACHE_DIR, "builds.json");
	if (fs.existsSync(jsonPath)) existing = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
	const specs = existing.specs || {};
	let patch = existing.patch || null;

	for (const key of specKeys) {
		const specID = SPECS[key];
		const out = { key, contexts: {} };
		for (const [bracket, ctx] of Object.entries(BRACKETS)) {
			const html = await cachedFetch(`https://murlok.io/${key}/${bracket}`, 6, false);
			if (!html) { console.log(`  ${key}/${bracket}: no page`); continue; }
			const m = parseMurlok(html);
			patch = m.patch || patch;
			const sample = m.players.slice(0, PLAYERS);
			const loadouts = [];
			for (const p of sample) loadouts.push(await playerLoadout(p, specID));
			const builds = pickBuilds(sample, loadouts, m.popularity);
			const topPlayers = playerList(sample, loadouts, m.popularity);
			out.contexts[ctx] = { builds, players: topPlayers, stats: m.stats, ilvl: m.ilvl, enchants: m.enchants, gems: m.gems };
			console.log(`${key}/${bracket}: ${builds.map((b) => `${b.hero} ${b.share}% (match ${b.match}%, n=${b.sample})`).join(" | ") || "no builds"}`);
		}
		specs[specID] = out;
	}

	const data = { updated: new Date().toISOString().slice(0, 10), patch, specs };
	fs.writeFileSync(jsonPath, JSON.stringify(data));
	fs.mkdirSync(path.dirname(OUT), { recursive: true });
	fs.writeFileSync(OUT,
		"-- Generated by tools/update-builds.mjs from murlok.io + raider.io. Do not edit by hand.\n" +
		"local _, ns = ...\nns.data = " + lua(data) + "\n");
	console.log(`\nWrote ${OUT} (${Object.keys(specs).length} specs, patch ${patch}, ${data.updated})`);
}

main().catch((e) => { console.error(e); process.exit(1); });
