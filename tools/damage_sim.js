// Simulation der Schadensformeln: aktuelle Formel vs. Pokémon-Formel vs. vorgeschlagene Variante.
// Aufruf:  node tools/damage_sim.js [Skill-Wert=40] [KP-Multiplikator der Variante=3] ["eigen" = Grundschaden aus eigener BST]
// Liest die Arten (preferred_stats + stats) direkt aus script/globals/monmap.gd.
// Vereinfachungen: keine Edelsteine, Buffs, Schilde, Relikte; Element neutral; Anteile ohne ±15 %-Zufall.

const fs = require("fs");
const path = require("path");

// ── Konstanten wie im Spiel ──────────────────────────────
const STAT_SCALE = 8.0;      // mon.gd
const SETTING_LEVEL = 35;    // state.gd
const INITIAL_LEVEL = 5;     // state.gd
const SKILL_VALUE = Number(process.argv[2] || 40);

// ── Parameter der Variante (= "EMPFEHLUNG" im Debug-Menü, DebugSettings.DAMAGE_RECOMMENDED) ──
const LEVEL_OFFSET = 10;     // Sockel: je größer, desto weniger zählen Stufenunterschiede
const HP_SCALE = Number(process.argv[3] || 3); // KP-Multiplikator der Variante: steuert die Kampflänge (Treffer bis K.O.)
const EXPONENT = 2.0;        // k in 2·a^k/(a^k+d^k)
const MIN_FACTOR = 0.25;     // Boden: sehr hohe Verteidigung drückt den Schaden höchstens auf 1/4
const MAX_FACTOR = 2.0;      // Deckel
const FIXED_BASE = process.argv[4] !== "eigen"; // "FESTE BST": Grundschaden aus Referenz-BST statt eigener BST
const REF_BST = 210;

// ── Arten aus monmap.gd lesen ────────────────────────────
function loadSpecies() {
	const src = fs.readFileSync(path.join(__dirname, "..", "script", "globals", "monmap.gd"), "utf8");
	const re = /"name":\s*"([^"]+)"[\s\S]*?"stats":\s*\[(\d+),\s*(\d+)\][\s\S]*?"preferred_stats":\s*\{([^}]*)\}/g;
	const list = [];
	let m;
	while ((m = re.exec(src))) {
		const shares = {};
		for (const [, k, v] of m[4].matchAll(/"(\w+)":\s*([\d.]+)/g)) shares[k] = Number(v) / 100;
		list.push({ name: m[1], bst: (Number(m[2]) + Number(m[3])) / 2, shares });
	}
	return list;
}

// ── Werte ────────────────────────────────────────────────
// aktuell: linear ab Stufe 1 (mon.gd _base_stat, Growth-Faktor 1)
function statNow(sp, stat, level) {
	return sp.shares[stat] * (sp.bst / SETTING_LEVEL) * STAT_SCALE * level;
}
// Variante: mit Sockel, so normiert, dass Stufe 5 genau gleich bleibt wie heute
function statOffset(sp, stat, level) {
	const l1 = sp.shares[stat] * (sp.bst / SETTING_LEVEL) * STAT_SCALE;
	return l1 * INITIAL_LEVEL * (level + LEVEL_OFFSET) / (INITIAL_LEVEL + LEVEL_OFFSET);
}

function makeMon(sp, level, statFn, mods = {}) {
	const s = {};
	for (const k of ["hp", "atk", "def", "s_atk", "s_def", "speed"]) s[k] = statFn(sp, k, level) * (mods[k] || 1);
	if (statFn === statOffset) s.hp *= HP_SCALE;
	return { sp, level, ...s };
}

// Angreifer nimmt seine bessere Angriffsart
function pick(from, to) {
	return from.atk >= from.s_atk ? [from.atk, to.def] : [from.s_atk, to.s_def];
}

// ── Formeln ──────────────────────────────────────────────
const FORMULAS = {
	aktuell: {
		stat: statNow,
		dmg(from, to, v) {
			const [a, d] = pick(from, to);
			return Math.ceil(a * (v / 100) * (2 * a / Math.max(a + d, 0.001)));
		},
	},
	pokemon: {
		stat: statNow,
		dmg(from, to, v) {
			const [a, d] = pick(from, to);
			const lf = Math.floor((2 * from.level) / 5) + 2;
			return Math.floor(Math.floor(lf * v * a / d) / 50) + 2;
		},
	},
	variante: {
		stat: statOffset,
		dmg(from, to, v) {
			const [a, d] = pick(from, to);
			// Grundschaden = typischer Angriffswert (1/6 Anteil) auf Stufe des Angreifers -> Angriff zählt nur im Verhältnis
			const typical = (1 / 6) * ((FIXED_BASE ? REF_BST : from.sp.bst) / SETTING_LEVEL) * STAT_SCALE * INITIAL_LEVEL
				* (from.level + LEVEL_OFFSET) / (INITIAL_LEVEL + LEVEL_OFFSET);
			// wie Skills.stat_damage "symmetric": symmetrisch, begrenzt auf [Boden, Deckel]
			const ak = Math.pow(a, EXPONENT);
			const factor = Math.min(Math.max(2 * ak / Math.max(ak + Math.pow(d, EXPONENT), 0.001), MIN_FACTOR), MAX_FACTOR);
			return Math.ceil(typical * (v / 100) * factor);
		},
	},
};

const hitsToKo = (dmg, hp) => Math.ceil(Math.round(hp) / Math.max(dmg, 1));

// Duell 1 gegen 1, beide mit demselben Skill-Wert, schnellerer zuerst. Ergebnis: Rest-KP des Siegers in %.
function duel(f, a, b, v) {
	let hpA = Math.round(a.hp), hpB = Math.round(b.hp);
	const dA = f.dmg(a, b, v), dB = f.dmg(b, a, v);
	let aTurn = a.speed >= b.speed;
	for (let i = 0; i < 200; i++) {
		if (aTurn) hpB -= dA; else hpA -= dB;
		if (hpB <= 0) return { winner: "A", rest: hpA / Math.round(a.hp) };
		if (hpA <= 0) return { winner: "B", rest: hpB / Math.round(b.hp) };
		aTurn = !aTurn;
	}
	return { winner: "-", rest: 0 };
}

// ── Ausgabe ──────────────────────────────────────────────
const pad = (s, n) => String(s).padEnd(n);
const lpad = (s, n) => String(s).padStart(n);
const species = loadSpecies();
const byName = Object.fromEntries(species.map((s) => [s.name, s]));
// Archetypen: stärkster Angreifer, stärkster Verteidiger, ausgeglichenstes Monster
const atkOf = (s) => Math.max(s.shares.atk, s.shares.s_atk);
const defOf = (s) => (s.shares.def + s.shares.s_def) / 2 + s.shares.hp;
const glass = [...species].sort((x, y) => atkOf(y) - atkOf(x))[0];
const tank = [...species].sort((x, y) => defOf(y) - defOf(x))[0];
const avg = [...species].sort((x, y) =>
	Math.abs(atkOf(x) - defOf(x) / 1.5) - Math.abs(atkOf(y) - defOf(y) / 1.5))[0];

console.log(`Arten geladen: ${species.length} | Skill-Wert: ${SKILL_VALUE} | LEVEL_OFFSET (Variante): ${LEVEL_OFFSET} | HP_SCALE (Variante): ${HP_SCALE} | Grundschaden: ${FIXED_BASE ? "feste BST " + REF_BST : "eigene BST"}`);
console.log(`Angreifer-Typ: Art ${glass.name}, Verteidiger-Typ: Art ${tank.name}, ausgeglichen: Art ${avg.name}\n`);

// 1) Treffer bis K.O. bei Stufenunterschieden (ausgeglichenes Monster gegen sich selbst)
console.log("1) Treffer bis K.O.  (Angreifer-Stufe -> Ziel-Stufe, Art " + avg.name + " gegen Art " + avg.name + ")");
console.log(pad("Stufen", 12) + Object.keys(FORMULAS).map((k) => lpad(k, 18)).join(""));
for (const [la, lt] of [[5, 5], [6, 5], [7, 5], [5, 7], [10, 5], [15, 5], [5, 15], [12, 10], [21, 20], [32, 30], [35, 35]]) {
	let row = pad(`${la} -> ${lt}`, 12);
	for (const f of Object.values(FORMULAS)) {
		const a = makeMon(avg, la, f.stat), t = makeMon(avg, lt, f.stat);
		const d = f.dmg(a, t, SKILL_VALUE);
		row += lpad(`${hitsToKo(d, t.hp)} (${d}/${Math.round(t.hp)})`, 18);
	}
	console.log(row);
}

// 2) Kampfkraft-Vorteil im Duell: Verhältnis der K.O.-Geschwindigkeiten (stetig, ohne Rundung auf Treffer)
console.log("\n2) Kampfkraft-Vorteil im Duell (wie viel schneller der Höherstufige gewinnt, ungerundet)");
console.log(pad("Stufen", 12) + Object.keys(FORMULAS).map((k) => lpad(k, 12)).join(""));
for (const [h, l] of [[6, 5], [7, 5], [10, 5], [15, 5], [12, 10], [21, 20], [32, 30]]) {
	let row = pad(`${h} vs ${l}`, 12);
	for (const f of Object.values(FORMULAS)) {
		const H = makeMon(avg, h, f.stat), L = makeMon(avg, l, f.stat);
		const speedH = f.dmg(H, L, SKILL_VALUE) / L.hp, speedL = f.dmg(L, H, SKILL_VALUE) / H.hp;
		row += lpad((speedH / speedL).toFixed(2) + "x", 12);
	}
	console.log(row);
}

// 3) Wert eines Stats: +20 % auf einen Wert, wie stark verbessert sich das Duell gegen eine Kopie?
console.log("\n3) Wert der Stats: +20 % auf einen Wert, Kampfkraft gegen eine unveränderte Kopie (Stufe 10)");
console.log(pad("Stat +20 %", 12) + Object.keys(FORMULAS).map((k) => lpad(k, 12)).join(""));
for (const stat of ["hp", "atk", "def"]) {
	let row = pad(stat, 12);
	for (const f of Object.values(FORMULAS)) {
		// physischer Angreifer erzwingen, damit atk/def zählen
		const base = makeMon(avg, 10, f.stat, { s_atk: 0 });
		const buffed = makeMon(avg, 10, f.stat, { s_atk: 0, [stat]: 1.2 });
		const speedB = f.dmg(buffed, base, SKILL_VALUE) / base.hp, speedO = f.dmg(base, buffed, SKILL_VALUE) / buffed.hp;
		row += lpad((speedB / speedO).toFixed(2) + "x", 12);
	}
	console.log(row);
}

// 4) Archetypen-Duelle auf gleicher Stufe
console.log("\n4) Duelle gleicher Stufe (Stufe 10): Sieger und Rest-KP");
console.log(pad("Paarung", 22) + Object.keys(FORMULAS).map((k) => lpad(k, 14)).join(""));
for (const [x, y, label] of [[glass, tank, "Angreifer vs Tank"], [glass, avg, "Angreifer vs Ausgegl."], [tank, avg, "Tank vs Ausgegl."]]) {
	let row = pad(label, 22);
	for (const f of Object.values(FORMULAS)) {
		const r = duel(f, makeMon(x, 10, f.stat), makeMon(y, 10, f.stat), SKILL_VALUE);
		const who = r.winner === "A" ? label.split(" vs ")[0] : label.split(" vs ")[1];
		row += lpad(`${who.slice(0, 7)} ${Math.round(r.rest * 100)}%`, 14);
	}
	console.log(row);
}

// 5) One-Shot-Check: Stufe 15 trifft Stufe 5 mit verschiedenen Skill-Werten
console.log(`\n5) One-Shot-Check: Angreifer (Art ${glass.name}) Stufe 15 trifft Tank (Art ${tank.name}) / Angreifer-Art Stufe 5`);
console.log(pad("Skill-Wert", 12) + Object.keys(FORMULAS).map((k) => lpad(k, 22)).join(""));
for (const v of [25, 40, 55, 70, 90]) {
	let row = pad(v, 12);
	for (const f of Object.values(FORMULAS)) {
		const a = makeMon(glass, 15, f.stat);
		const t1 = makeMon(tank, 5, f.stat), t2 = makeMon(glass, 5, f.stat);
		row += lpad(`${hitsToKo(f.dmg(a, t1, v), t1.hp)} / ${hitsToKo(f.dmg(a, t2, v), t2.hp)} Treffer`, 22);
	}
	console.log(row);
}

// 6) Tank-Check: gleiche Stufe 10, das Ziel hat x-fache Verteidigung (wie die Übersicht im Debug-Menü)
console.log(`\n6) Tank-Check (Art ${avg.name}, Stufe 10 -> 10): Ziel mit x-facher Verteidigung, Treffer bis K.O.`);
console.log(pad("Vert. x", 12) + Object.keys(FORMULAS).map((k) => lpad(k, 18)).join(""));
for (const x of [1, 1.5, 2, 3, 4]) {
	let row = pad(x, 12);
	for (const f of Object.values(FORMULAS)) {
		const a = makeMon(avg, 10, f.stat), t = makeMon(avg, 10, f.stat, { def: x, s_def: x });
		const d = f.dmg(a, t, SKILL_VALUE);
		row += lpad(`${hitsToKo(d, t.hp)} (${d}/${Math.round(t.hp)})`, 18);
	}
	console.log(row);
}

// 7) Seltenheit: gleich verteilte Monster mit unterschiedlicher BST, Stufe 10, Vorteil im Duell (ungerundet)
console.log("\n7) BST-Vorteil im Duell (Stufe 10, gleich verteilte Werte): wie viel schneller die höhere BST gewinnt");
const even = (bst) => ({ name: "bst" + bst, bst, shares: { hp: 1 / 6, atk: 1 / 6, def: 1 / 6, s_atk: 1 / 6, s_def: 1 / 6, speed: 1 / 6 } });
console.log(pad("Paarung", 22) + Object.keys(FORMULAS).map((k) => lpad(k, 12)).join(""));
for (const [hi, lo, label] of [[220, 200, "Uncommon vs Common"], [240, 200, "Epic vs Common"], [255, 200, "255 vs Common"],
	[270, 200, "Mythic vs Common"], [280, 200, "280 vs Common"]]) {
	let row = pad(label, 22);
	for (const f of Object.values(FORMULAS)) {
		const H = makeMon(even(hi), 10, f.stat), L = makeMon(even(lo), 10, f.stat);
		const speedH = f.dmg(H, L, SKILL_VALUE) / L.hp, speedL = f.dmg(L, H, SKILL_VALUE) / H.hp;
		row += lpad((speedH / speedL).toFixed(2) + "x", 12);
	}
	console.log(row);
}
