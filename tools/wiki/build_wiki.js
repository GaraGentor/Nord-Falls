#!/usr/bin/env node
// Baut wiki/index.html aus dem Spiel-Quellcode (GDScript + Übersetzungen).
// Aufruf aus dem Projektordner:  node tools/wiki/build_wiki.js
//
// Die Daten werden direkt aus den Konstanten/Listen der Skripte gelesen (Monmap.mons, Skills.*,
// Relics.RELICS, Gems.STATS, ColorMap, Map.map_settings, ...). Kommen dort neue Einträge dazu,
// reicht es, das Skript erneut auszuführen. Nur wenn sich die *Struktur* ändert (neue Datei,
// umbenannte Variable), muss hier etwas angepasst werden.

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const OUT_DIR = path.join(ROOT, "wiki");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8").replace(/\r\n/g, "\n");
const warnings = [];

// ─────────────────────────
// GDScript-Helfer

// Entfernt #-Kommentare, ohne Strings ("#CFEFFF") zu zerstören.
function stripComments(src) {
	let out = "";
	let quote = null;
	for (let i = 0; i < src.length; i++) {
		const c = src[i];
		if (quote) {
			out += c;
			if (c === "\\") out += src[++i] ?? "";
			else if (c === quote) quote = null;
		} else if (c === '"' || c === "'") {
			quote = c;
			out += c;
		} else if (c === "#") {
			while (i < src.length && src[i] !== "\n") i++;
			out += "\n";
		} else {
			out += c;
		}
	}
	return out;
}

// Liest ab start einen geklammerten Ausdruck ([...], {...}, (...)) inkl. verschachtelter Klammern.
function readBracketed(src, start) {
	const open = src[start];
	const close = { "[": "]", "{": "}", "(": ")" }[open];
	let depth = 0;
	let quote = null;
	for (let i = start; i < src.length; i++) {
		const c = src[i];
		if (quote) {
			if (c === "\\") i++;
			else if (c === quote) quote = null;
			continue;
		}
		if (c === '"' || c === "'") quote = c;
		else if (c === "[" || c === "{" || c === "(") depth++;
		else if (c === "]" || c === "}" || c === ")") {
			depth--;
			if (depth === 0) return src.slice(start, i + 1);
		}
	}
	throw new Error("Klammer nicht geschlossen: " + src.slice(start, start + 60));
}

// Rohtext des Werts von `var/const NAME = ...` (Literal mit Klammern oder Rest der Zeile).
function rawValue(src, name) {
	const m = new RegExp(`^\\s*(?:var|const)\\s+${name}\\s*(?::\\s*[\\w\\[\\]]+\\s*)?:?=\\s*`, "m").exec(src);
	if (!m) return null;
	const start = m.index + m[0].length;
	if ("[{(".includes(src[start])) return readBracketed(src, start);
	return src.slice(start, src.indexOf("\n", start)).trim();
}

// enum NAME { A, B = 1 << 2, ... } -> { A: 0, B: 4 }
function parseEnum(src, name) {
	const m = new RegExp(`enum\\s+${name}\\s*\\{`).exec(src);
	if (!m) return {};
	const body = readBracketed(src, m.index + m[0].length - 1).slice(1, -1);
	const result = {};
	let next = 0;
	for (const part of body.split(",").map((s) => s.trim()).filter(Boolean)) {
		const [key, expr] = part.split("=").map((s) => s.trim());
		const value = expr !== undefined ? Function(`return (${expr})`)() : next;
		result[key] = value;
		next = value + 1;
	}
	return result;
}

// Kontext, in dem GDScript-Ausdrücke als JS ausgewertet werden.
const ctx = { enums: {}, helpers: {} };

// Ersetzt Lambdas `func(a): body` durch ihren Quelltext als String (nur zur Anzeige).
// Der Body endet am Zeilenende, an einem Komma oder an einer schließenden Klammer auf oberster Ebene.
function lambdasToStrings(src, store) {
	const re = /\bfunc\s*\(/g;
	let out = "";
	let last = 0;
	for (let m; (m = re.exec(src)); ) {
		const args = readBracketed(src, m.index + m[0].length - 1);
		let i = m.index + m[0].length - 1 + args.length;
		const colon = src.indexOf(":", i);
		let depth = 0, quote = null, j = colon + 1;
		for (; j < src.length; j++) {
			const c = src[j];
			if (quote) { if (c === "\\") j++; else if (c === quote) quote = null; continue; }
			if (c === '"' || c === "'") quote = c;
			else if ("([{".includes(c)) depth++;
			else if (")]}".includes(c)) { if (depth === 0) break; depth--; }
			else if ((c === "," && depth === 0) || c === "\n") break;
		}
		const text = ("func" + args + src.slice(i, j)).replace(/\s+/g, " ").trim();
		store.push(text);
		out += src.slice(last, m.index) + `"@@LAMBDA${store.length - 1}@@"`;
		last = j;
		re.lastIndex = j;
	}
	return out + src.slice(last);
}

// Wendet fn nur auf Code an, nicht auf String-Literale.
function mapCode(src, fn) {
	return src.split(/("(?:[^"\\]|\\.)*")/).map((part, i) => (i % 2 ? part : fn(part))).join("");
}

// Übersetzt ein GDScript-Literal so weit nach JS, dass es ausgewertet werden kann.
function gdToJs(expr) {
	const lambdas = [];
	let js = lambdasToStrings(stripComments(expr), lambdas);
	js = js.replace(/\b(?:pre)?load\(\s*("[^"]*")\s*\)/g, "$1");
	js = mapCode(js, (code) => {
		code = code.replace(/\bColor\(([^)]*)\)/g, "[$1]");
		code = code.replace(/\b(\w+)\.(\w+)\.(\w+)\b|\b(Rarity|PATH_TYPE)\.(\w+)\b/g, (all, a, b, c, d, e) => {
			const [group, key] = a ? [b, c] : [d, e];
			const values = ctx.enums[group];
			if (!values || !(key in values)) return all;
			// Elemente sind Bitmasken (werden mit | kombiniert), alles andere als Name lesbarer
			return group === "MON_TYPES" ? String(values[key]) : JSON.stringify(key);
		});
		code = code.replace(/\band\b/g, "&&").replace(/\bor\b/g, "||").replace(/\bnot\b/g, "!");
		return code;
	});
	// "a" if cond else "b"  ->  ((cond) ? "a" : "b")
	js = js.replace(/("[^"\n]*"|[\w.]+)[ \t]+if[ \t]+([^\n]+?)[ \t]+else[ \t]+("[^"\n]*"|[\w.]+)/g, "(($2) ? $1 : $3)");
	return js.replace(/"@@LAMBDA(\d+)@@"/g, (_, i) => JSON.stringify(lambdas[i]));
}

function evalGd(expr, label) {
	const js = gdToJs(expr);
	try {
		const names = Object.keys(ctx.helpers);
		return Function(...names, `"use strict"; return (${js});`)(...names.map((n) => ctx.helpers[n]));
	} catch (err) {
		warnings.push(`${label}: konnte nicht gelesen werden (${err.message})`);
		return null;
	}
}

function readVar(src, name, label) {
	const raw = rawValue(src, name);
	if (raw === null) {
		warnings.push(`${label}: Variable ${name} nicht gefunden`);
		return null;
	}
	return evalGd(raw, `${label} ${name}`);
}

// func NAME(a: T, b: T) -> Dictionary:\n\treturn {...}  ->  JS-Funktion (für Skill-Baukästen wie _egg_skill)
function readBuilder(src, name) {
	const m = new RegExp(`func\\s+${name}\\s*\\(([^)]*)\\)[^:]*:\\s*return\\s*`).exec(src);
	if (!m) {
		warnings.push(`Funktion ${name} nicht gefunden`);
		return () => ({});
	}
	const params = m[1].split(",").map((p) => p.split(":")[0].trim()).filter(Boolean);
	const body = gdToJs(readBracketed(src, m.index + m[0].length));
	// Baukästen dürfen andere Helfer aufrufen (z. B. _skill_cost), die stehen erst beim Aufruf fest
	return (...args) => {
		const names = Object.keys(ctx.helpers);
		return Function(...names, ...params, `"use strict"; return (${body});`)(...names.map((n) => ctx.helpers[n]), ...args);
	};
}

// ─────────────────────────
// Übersetzungen (CSV mit Anführungszeichen und Zeilenumbrüchen)

function parseCsv(text) {
	const rows = [];
	let row = [], field = "", quoted = false;
	for (let i = 0; i < text.length; i++) {
		const c = text[i];
		if (quoted) {
			if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
			else if (c === '"') quoted = false;
			else field += c;
		} else if (c === '"') quoted = true;
		else if (c === ",") { row.push(field); field = ""; }
		else if (c === "\n") { row.push(field); rows.push(row); row = []; field = ""; }
		else field += c;
	}
	if (field || row.length) { row.push(field); rows.push(row); }
	return rows;
}

function readTranslations() {
	const [header, ...rows] = parseCsv(read("localization/translations.csv"));
	const langs = header.slice(1).map((l) => l.trim());
	const tr = {};
	for (const lang of langs) tr[lang] = {};
	for (const row of rows) {
		if (!row[0]) continue;
		langs.forEach((lang, i) => (tr[lang][row[0].trim()] = (row[i + 1] ?? "").trim()));
	}
	return { langs, tr };
}

// ─────────────────────────
// Daten sammeln

function collect() {
	const enumsSrc = read("script/globals/enums.gd");
	for (const name of ["MON_TYPES", "CARD_TARGETS", "SKILL_DAMAGE_TYPE", "MON_RARITY"]) ctx.enums[name] = parseEnum(enumsSrc, name);

	const relicsSrc = read("script/globals/relics.gd");
	ctx.enums.Rarity = parseEnum(relicsSrc, "Rarity");
	const mapSrc = read("script/globals/map.gd");
	ctx.enums.PATH_TYPE = parseEnum(mapSrc, "PATH_TYPE");

	// Elemente + Kombinationen aus ColorMap.get_combo (match-Zweige)
	const colorSrc = stripComments(read("script/globals/color_map.gd"));
	const combos = [];
	const caseRe = /^\s*([^\n]+?):\s*\n\s*return\s*(\{[^}]*\})/gm;
	for (let m; (m = caseRe.exec(colorSrc)); ) {
		if (m[1].trim() === "_") continue;
		const mask = evalGd(m[1], "ColorMap-Zweig");
		const info = evalGd(m[2], "ColorMap-Wert");
		if (typeof mask === "number" && info && mask > 0) combos.push({ mask, ...info });
	}

	// Skills
	const skillsSrc = read("script/globals/skills.gd");
	// Skills._skill_cost: 1 Aktion + 1 pro erreichter Schwelle aus COST_THRESHOLDS
	const costThresholds = readVar(skillsSrc, "COST_THRESHOLDS", "Skills") ?? [];
	ctx.helpers._skill_cost = (value) => 1 + costThresholds.filter((threshold) => value >= threshold).length;
	// Alle Skill-Baukästen (func _xyz_skill(...): return ...), so laufen neue Baukästen automatisch mit
	for (const m of skillsSrc.matchAll(/^func\s+(_\w*skill)\s*\([^)]*\)[^:\n]*:\s*return\b/gm)) {
		ctx.helpers[m[1]] = readBuilder(skillsSrc, m[1]);
	}
	ctx.helpers._with = (skill, extra) => Object.assign(skill, extra);
	// Welche Listen es gibt, steht in get_skill(); so tauchen neue Listen automatisch auf
	const listNames = (/for list in \[([^\]]*)\]/.exec(skillsSrc)?.[1] ?? "attack_skills, defensive_skills, buff_skills, egg_skills")
		.split(",").map((s) => s.trim()).filter(Boolean);
	const skills = [];
	for (const list of listNames) {
		for (const skill of readVar(skillsSrc, list, "Skills") ?? []) {
			const { handle, ...rest } = skill;
			skills.push({ ...rest, list });
		}
	}

	const monmapSrc = read("script/globals/monmap.gd");
	const helperSrc = read("script/globals/helper.gd");
	const gemsSrc = read("script/scenes/gems/gems.gd");

	// Bildpfad wie in Monmap.texture(), dort steht er nicht als Feld in den Daten
	const mons = readVar(monmapSrc, "mons", "Monmap") ?? [];
	for (const mon of mons) {
		const image = `assets/mons/${mon.name}/${mon.name}_frontx256.png`;
		if (fs.existsSync(path.join(ROOT, image))) mon.image = "res://" + image;
		else warnings.push(`Monster ${mon.name}: Bild ${image} nicht gefunden`);
	}

	const relics = readVar(relicsSrc, "RELICS", "Relics") ?? {};
	for (const relic of Object.values(relics)) {
		relic.hooks = Object.fromEntries(Object.entries(relic.hooks ?? {}).map(([k, v]) => [k, String(v)]));
	}
	const knownHooks = [...relicsSrc.matchAll(/^##\s*-\s*"(\w+)":\s*(.+)$/gm)].map((m) => ({ key: m[1], desc: m[2] }));

	return {
		enums: ctx.enums,
		elements: {
			base: ctx.enums.MON_TYPES,
			combos,
			strongAgainst: readVar(skillsSrc, "STRONG_AGAINST", "Skills"),
			elementBonus: readVar(skillsSrc, "ELEMENT_BONUS", "Skills"),
		},
		skills,
		skillLists: listNames,
		tierWeights: readVar(skillsSrc, "TIER_WEIGHTS", "Skills"),
		depthTierBonus: readVar(skillsSrc, "DEPTH_TIER_BONUS", "Skills"),
		maxSkills: readVar(skillsSrc, "MAX_SKILLS", "Skills"),
		milestones: readVar(skillsSrc, "MILESTONES", "Skills") ?? [],
		bounties: readVar(skillsSrc, "BOUNTIES", "Skills") ?? [],
		bountyChance: readVar(skillsSrc, "BOUNTY_CHANCE", "Skills"),
		mons,
		catch: {
			rarityBase: readVar(helperSrc, "CATCH_RARITY_BASE", "Helper"),
			hpWeight: readVar(helperSrc, "CATCH_HP_WEIGHT", "Helper"),
			levelStep: readVar(helperSrc, "CATCH_LEVEL_STEP", "Helper"),
			chanceRange: readVar(helperSrc, "CATCH_CHANCE_RANGE", "Helper"),
		},
		relics,
		relicHooks: knownHooks,
		gems: {
			stats: readVar(gemsSrc, "STATS", "Gems") ?? {},
			bonusByDepth: readVar(gemsSrc, "BONUS_BY_DEPTH", "Gems") ?? [],
			choices: readVar(gemsSrc, "GEM_CHOICES", "Gems"),
		},
		map: {
			settings: readVar(mapSrc, "map_settings", "Map") ?? {},
			maxRows: readVar(mapSrc, "max_rows", "Map"),
			maxCols: readVar(mapSrc, "max_cols", "Map"),
		},
		...readTranslations(),
	};
}

// ─────────────────────────
// Ausgabe

function build() {
	const data = collect();
	data.generatedAt = new Date().toISOString();
	data.git = (() => {
		try {
			return require("child_process").execSync("git rev-parse --short HEAD", { cwd: ROOT }).toString().trim();
		} catch {
			return "";
		}
	})();
	data.warnings = warnings;

	const template = fs.readFileSync(path.join(__dirname, "template.html"), "utf8");
	// </script im JSON würde den Script-Block beenden
	const json = JSON.stringify(data).replace(/</g, "\\u003c");
	const html = template.replace("/*__WIKI_DATA__*/null", () => json);

	fs.mkdirSync(OUT_DIR, { recursive: true });
	// Godot soll den Ordner nicht importieren
	fs.writeFileSync(path.join(OUT_DIR, ".gdignore"), "");
	fs.writeFileSync(path.join(OUT_DIR, "index.html"), html);

	console.log(`Wiki gebaut: ${path.relative(ROOT, path.join(OUT_DIR, "index.html"))}`);
	console.log(`  ${data.mons.length} Monster, ${data.skills.length} Skills, ${Object.keys(data.relics).length} Relikte, ` +
		`${Object.keys(data.gems.stats).length} Trophäen, ${data.elements.combos.length} Elemente`);
	for (const w of warnings) console.warn("  WARNUNG: " + w);
}

build();
