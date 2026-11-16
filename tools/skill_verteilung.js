// Skill-Verteilung der Arten nach den Regeln aus todo_skill_balance.txt / skill_verteilung.txt
//
//   node tools/skill_verteilung.js             verteilt neu: schreibt monmap.gd und skill_verteilung.txt
//   node tools/skill_verteilung.js --nur-text  nur skill_verteilung.txt (Vorschau, monmap.gd bleibt)
//
// Liest bei jedem Lauf script/globals/monmap.gd (Seltenheit, Element, preferred_stats, affinity, affinity_triple)
// und script/globals/skills.gd (welche Skills es gibt). Kein Zufall: gleiche Daten -> gleiche Verteilung.
// Geschrieben werden default_egg_skills, unlockable_egg_skills und milestone_egg_skills. bounty_egg_skills bleibt.
//   - Arten mit "skills_manual": true werden nicht angefasst (von Hand gepflegt).
//   - Startmonster (STARTERS) behalten Start-Skills und Ei-Attacken, bekommen nur die Meilensteine.
//   - Geplante Skills, die es in skills.gd noch nicht gibt, kommen nicht in monmap.gd (sonst Warnung beim Start),
//     sondern stehen mit * in skill_verteilung.txt. Sobald es sie gibt, nimmt der nächste Lauf sie mit.
// Neben-Element ab Selten: "affinity" (Zweier-Kombi), ab Legendär zusätzlich "affinity_triple" (Dreier-Kombi) in monmap.gd.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const MONMAP = path.join(ROOT, 'script/globals/monmap.gd');
const SKILLS = path.join(ROOT, 'script/globals/skills.gd');
const PLAN = path.join(ROOT, 'skill_verteilung.txt');
const MARK_START = '### AUTOMATISCH ERZEUGT AB HIER (tools/skill_verteilung.js) ###';
const MARK_END = '### AUTOMATISCH ERZEUGT BIS HIER ###';
const ONLY_TEXT = process.argv.includes('--nur-text');

// ─────────────────────────
// Daten-Tabellen

const STARTERS = ['2', '4', '5', '82']; // wie State.INITIAL_MONS
const ORDER = ['atk', 's_atk', 'def', 's_def']; // Gleichstand der Kategorien
const CAT = { atk: 'PHYS', s_atk: 'MAG', def: 'ARMOR', s_def: 'WARD' };
const STATNAME = { atk: 'Ang.', s_atk: 'Sp. Ang.', def: 'Vert.', s_def: 'Sp. Vert.', hp: 'KP', speed: 'Init.' };
const isAtk = c => c === 'atk' || c === 's_atk';

// Stufe 2 / Stufe 3 pro Grundelement und Kategorie (draft_skills)
const BASE = {
  FIRE: { atk: ['FLAME_FIST', 'BLAZE_RUSH'], s_atk: ['SPARK_SHOT', 'FIREBALL'], def: ['CINDER_PLATE', 'FLAME_WALL'], s_def: ['HEAT_VEIL', 'PHOENIX_AURA'] },
  WATER: { atk: ['TIDE_SLAP', 'BREAKER'], s_atk: ['BUBBLE_BEAM', 'HYDRO_LANCE'], def: ['SHELL', 'CORAL_WALL'], s_def: ['MIST_VEIL', 'TIDAL_DOME'] },
  EARTH: { atk: ['BOULDER_BASH', 'QUAKE_STOMP'], s_atk: ['PEBBLE_STORM', 'GEO_PULSE'], def: ['STONE_SKIN', 'GRANITE_BASTION'], s_def: ['CLAY_SEAL', 'CRYSTAL_SEAL'] },
  AIR: { atk: ['GUST_KICK', 'CYCLONE_CLAW'], s_atk: ['WIND_BLADE', 'TEMPEST_RAY'], def: ['DRAFT_GUARD', 'GALE_WALL'], s_def: ['BREEZE_VEIL', 'SKY_DOME'] },
};
// Kombis pro Kategorie [leicht, stark] + Top (Stufe 4).
// Zweier: leicht = Stufe 2 (CD 1), stark = Stufe 3. Dreier: leicht = Stufe 3 (CD 1), stark = Stufe 3 (CD 3).
const COMBO = {
  STEAM: { atk: ['HOT_JAB', 'SCALD_STRIKE'], s_atk: ['VAPOR_PUFF', 'STEAM_JET'], def: ['STEAM_COAT', 'VAPOR_PLATE'], s_def: ['HAZE_SHIELD', 'FOG_BARRIER'], top: 'PHYS_STEAM_HAMMER' },
  LIGHTNING: { atk: ['SHOCK_TAP', 'VOLT_PUNCH'], s_atk: ['SPARK_BOLT', 'ARC_BOLT'], def: ['CHARGE_PLATE', 'STATIC_PLATE'], s_def: ['ION_VEIL', 'SPARK_FIELD'], top: 'MAG_THUNDERCLAP' },
  MAGMA: { atk: ['EMBER_KNUCKLE', 'LAVA_FIST'], s_atk: ['LAVA_SPIT', 'MAGMA_BURST'], def: ['PUMICE_SKIN', 'OBSIDIAN_PLATE'], s_def: ['HEAT_SHIMMER', 'EMBER_CRUST'], top: 'PHYS_ERUPTION_SLAM' },
  ICE: { atk: ['FROST_BITE', 'ICICLE_JAB'], s_atk: ['SNOW_FLURRY', 'FROST_RAY'], def: ['RIME_COAT', 'ICE_PLATE'], s_def: ['SNOW_VEIL', 'FROST_MIRROR'], top: 'MAG_BLIZZARD' },
  DUST: { atk: ['GRIT_PUNCH', 'SAND_CLAW'], s_atk: ['DUST_SHOT', 'DUST_DEVIL'], def: ['SANDSTONE_SKIN', 'DUNE_WALL'], s_def: ['DUST_CLOAK', 'SAND_VEIL'], top: 'MAG_SANDSTORM' },
  MUD: { atk: ['MUD_PUNCH', 'MUD_SLAM'], s_atk: ['SLUDGE_SHOT', 'BOG_PULSE'], def: ['MUD_COAT', 'CLAY_SHELL'], s_def: ['PEAT_SEAL', 'SILT_SEAL'], top: 'ARMOR_LANDSLIDE_WALL' },
  THUNDERSTORM: { atk: ['SQUALL_STRIKE', 'STORM_FIST'], s_atk: ['STATIC_RAIN', 'CHAIN_LIGHTNING'], def: ['RAIN_GUARD', 'STORM_PLATE'], s_def: ['STORM_VEIL', 'CLOUD_DOME'], top: 'MAG_SKYFALL' },
  VOLCANO: { atk: ['VOLCANIC_FIST', 'CALDERA_CRUSH'], s_atk: ['FUME_BURST', 'PYROCLAST'], def: ['LAVA_CRUST', 'BASALT_FORT'], s_def: ['STEAM_VENT', 'GEYSER_SHIELD'], top: 'PHYS_MAGMA_TITAN' },
  ASH_STORM: { atk: ['SOOT_STRIKE', 'CINDER_CLAW'], s_atk: ['EMBER_GUST', 'ASH_CYCLONE'], def: ['CINDER_SHELL', 'SLAG_ARMOR'], s_def: ['SMOKE_SCREEN', 'SOOT_VEIL'], top: 'PHYS_ASHEN_ROLLER' },
  SWAMP: { atk: ['REED_WHIP', 'ROOT_LASH'], s_atk: ['SPORE_PUFF', 'MIASMA_CLOUD'], def: ['MOSS_HIDE', 'MANGROVE_WALL'], s_def: ['BOG_MIST', 'MARSH_MIST'], top: 'MAG_BOG_MAW' },
};
// Elemente -> Kombi-Name (für affinity in monmap.gd)
const COMBO_ELEMENTS = {
  STEAM: ['FIRE', 'WATER'], LIGHTNING: ['FIRE', 'AIR'], MAGMA: ['EARTH', 'FIRE'], ICE: ['AIR', 'WATER'], DUST: ['EARTH', 'AIR'], MUD: ['EARTH', 'WATER'],
  THUNDERSTORM: ['AIR', 'WATER', 'FIRE'], VOLCANO: ['EARTH', 'FIRE', 'WATER'], ASH_STORM: ['EARTH', 'AIR', 'FIRE'], SWAMP: ['EARTH', 'AIR', 'WATER'],
};
const comboOf = elements => {
  const key = [...elements].sort().join('|');
  const hit = Object.entries(COMBO_ELEMENTS).find(([, els]) => [...els].sort().join('|') === key);
  return hit ? hit[0] : null;
};
const ELEM_PASSIVE = { FIRE: 'element_power (Feuer-Angriffe +10 %)', AIR: 'magic_power (magische Angriffe +10 %)', EARTH: 'shield_power (Rüstung +10 %)', WATER: 's_shield_power (Magie-Schilde +10 %)' };

// ─────────────────────────
// Einlesen

const monmapText = fs.readFileSync(MONMAP, 'utf8');
const skillsText = fs.readFileSync(SKILLS, 'utf8');
const NL = monmapText.includes('\r\n') ? '\r\n' : '\n';
const exists = id => skillsText.includes('"' + id + '"');

const listStart = monmapText.indexOf('var mons = [');
const blockRe = /\r?\n\t\{(\r?\n[\s\S]*?)\r?\n\t\}/g;
blockRe.lastIndex = listStart;
const mons = [];
let bm;
while ((bm = blockRe.exec(monmapText))) {
  const body = bm[1];
  const bodyStart = bm.index + bm[0].indexOf(body);
  const g = r => { const x = body.match(r); return x ? x[1] : ''; };
  const ps = {};
  g(/"preferred_stats": \{([^}]*)\}/).split(',').forEach(p => { const [k, v] = p.split(':').map(s => s.replace(/"/g, '').trim()); ps[k] = +v; });
  const list = key => { const x = body.match(new RegExp('"' + key + '": \\[([\\s\\S]*?)\\]')); return x ? (x[1].match(/SKILL_\w+/g) || []) : []; };
  const elems = key => { const x = body.match(new RegExp('"' + key + '": ([^,\\r\\n]+)')); return x ? x[1].match(/MON_TYPES\.(\w+)/g).map(s => s.split('.')[1]) : null; };
  // Anzeigename: oberste Zeile des Kommentars direkt vor dem Block, "Name: Beschreibung"
  const prev = monmapText.slice(0, bm.index).split(/\r?\n/).reverse();
  let before = '';
  for (const l of prev) { if (!l.trim().startsWith('#')) break; before = l; }
  const aff = elems('affinity'), tri = elems('affinity_triple');
  mons.push({
    id: g(/"name": "([^"]+)"/), label: before.replace(/^\s*#\s*/, '').split(':')[0].trim(), rarity: g(/MON_RARITY\.(\w+)/),
    type: g(/"initial_type": ([^,\r\n]+)/).replace(/Enums\.MON_TYPES\./g, ''), ps,
    manual: /\n\t\t"skills_manual": true/.test(body), co: aff && comboOf(aff), tri: tri && comboOf(tri), // manual: nur echte Feldzeile
    def: list('default_egg_skills'), unl: list('unlockable_egg_skills'), body, bodyStart,
  });
}

// ─────────────────────────
// Skill-Bausteine

const NEW = new Map(); // geplante Skills, die es noch nicht gibt
const FALLBACK = {}; // '*ID' -> vorhandener Ersatz, der bis dahin in monmap.gd steht
const planned = (id, desc, fallback) => {
  if (exists(id)) return id;
  NEW.set(id, desc);
  if (fallback) FALLBACK['*' + id] = fallback;
  return '*' + id;
};
const base = (el, c, t) => `SKILL_${el}_${CAT[c]}_${BASE[el][c][t - 2]}`; // t = 2 oder 3
const combo = (co, c, i) => `SKILL_${co}_${CAT[c]}_${COMBO[co][c][i]}`;     // i = 0 leicht, 1 stark
const top = co => `SKILL_${co}_${COMBO[co].top}`;
const t1 = {
  thrust: (el, c) => `SKILL_${el}_${CAT[c]}_LIGHT_THRUST`,   // 5 + 0,2, CD 0
  strike: (el, c) => `SKILL_${el}_${CAT[c]}_LIGHT_STRIKE`,   // 8 + 0,3, CD 1
  weakThrust: (el, c) => `SKILL_${el}_${CAT[c]}_WEAK_THRUST`, // 2 + 0,2
  shield: (el, c) => `SKILL_${el}_${CAT[c]}_LIGHT`,          // 5 + 0,3
  weakShield: (el, c) => `SKILL_${el}_${CAT[c]}_WEAK`,       // 2 + 0,2
  plain: (el, c) => `SKILL_${el}_${CAT[c]}_PLAIN`,           // 5 + 0,3
  strong: (el, c) => c === 'atk' ? `SKILL_${el}_PHYS_PUNCH` : `SKILL_${el}_MAG_CANNON`,             // 12 + 0,4, CD 1
  small: (el, c) => c === 'atk' ? `SKILL_${el}_PHYS_SMALL_PUNCH` : `SKILL_${el}_MAG_SMALL_CANNON`,  // 5 + 0,3, CD 0
  weakForm: (el, c) => c === 'atk' ? `SKILL_${el}_PHYS_BACKHAND` : `SKILL_${el}_MAG_LIGHT_CANNON`,  // 8 + 0,3, CD 1
};
const lightOf = (el, c) => isAtk(c) ? t1.strike(el, c) : t1.shield(el, c);
const weakOf = (el, c) => isAtk(c) ? t1.weakForm(el, c) : t1.plain(el, c);

const buffT2 = (el, st) => planned(`SKILL_${el}_BUFF_${st.toUpperCase()}`, `Stufe 2, Buff: ein eigenes Monster ${STATNAME[st]} +25 % für 2 Züge, CD 2, 1 Aktion`);
const buffT3 = (el, st) => (el === 'FIRE' && st === 'atk') ? 'SKILL_FIRE_BOON_FOCUS_FLAME'
  : el === 'AIR' ? 'SKILL_AIR_BOON_TAILWIND'
  : (el === 'WATER' && isAtk(st)) ? 'SKILL_WATER_BOON_BLOOD_TIDE'
  : planned(`SKILL_${el}_BUFF_TEAM_${st.toUpperCase()}`, `Stufe 3, Buff: ganzes Team ${STATNAME[st]} +12 % für 2 Züge, CD 3, 1 Aktion`);
const buffT4 = co => co === 'LIGHTNING' ? 'SKILL_LIGHTNING_BOON_OVERCHARGE'
  : planned(`SKILL_${co}_BUFF_T4`, 'Stufe 4, Kombi-Buff: Team +15-18 % oder Einzel +35 % für 3 Züge (nach Kombi-Thema), CD 3, 2 Aktionen, "trainer": false');
const passiveT3 = el => planned(`SKILL_PASSIVE_${el}_POWER`, `Stufe 3, Passiv ${ELEM_PASSIVE[el]}`);
const passiveT4 = co => planned(`SKILL_PASSIVE_${co}_T4`, 'Stufe 4, Passiv: z. B. Resonanz (Element-Effekt +30 %) plus Werte-Bonus +10 %, "trainer": false, "wild": false');
const swift = (el, c) => planned(`SKILL_${el}_${CAT[c]}_${BASE[el][c][1]}_SWIFT`, `Stufe 3, schnelle Variante von ${BASE[el][c][1]}: CD 0, 1 Aktion, ca. 12 + 0,30 (Element-Charakter +)`,
  isAtk(c) ? t1.small(el, c) : t1.shield(el, c));
const epicPassive = (el, co, cs) => {
  if (co === 'LIGHTNING') return cs.indexOf('atk') < cs.indexOf('s_atk') ? 'SKILL_PASSIVE_BATTLE_FERVOR' : 'SKILL_PASSIVE_STORM_SPIRIT';
  if (co === 'MUD') return (isAtk(cs[0]) && isAtk(cs[1])) ? 'SKILL_PASSIVE_DEEP_VITALITY' : 'SKILL_PASSIVE_BULWARK_MASTER';
  return passiveT3(el);
};

const categories = ps => [...ORDER].sort((a, b) => (ps[b] - ps[a]) || (ORDER.indexOf(a) - ORDER.indexOf(b)));

// Start-Skills gewöhnlicher Arten (Schema aus dem Kommentar in monmap.gd, nach dem höchsten Kampfwert)
function commonDefault(el, cs, ps) {
  const k1 = cs[0];
  if (isAtk(k1)) return [t1.thrust(el, k1), t1.strike(el, k1), t1.weakShield(el, k1 === 'atk' ? 'def' : 's_def')];
  const weakAtk = ps.s_atk > ps.atk ? 's_atk' : 'atk';
  return [t1.weakThrust(el, weakAtk), t1.shield(el, k1), t1.weakShield(el, k1 === 'def' ? 's_def' : 'def')];
}

// ─────────────────────────
// Die Regeln pro Seltenheit (siehe skill_verteilung.txt Teil B)

function plan(mon) {
  const el = mon.type, cs = categories(mon.ps), [k1, k2, k3, k4] = cs, ba = cs.find(isAtk);
  const { co, tri } = mon;
  const p = { cats: cs, def: [], egg: [], ms: {}, problems: [] };
  if (['RARE', 'EPIC', 'LEGENDARY', 'MYTHIC'].includes(mon.rarity) && !co) p.problems.push('"affinity" fehlt in monmap.gd');
  if (['LEGENDARY', 'MYTHIC'].includes(mon.rarity) && !tri) p.problems.push('"affinity_triple" fehlt in monmap.gd');
  if (co && !COMBO_ELEMENTS[co].includes(el)) p.problems.push(`Neben-Element ${co} enthält das Grundelement ${el} nicht`);
  if (co && tri && !COMBO_ELEMENTS[co].every(e => COMBO_ELEMENTS[tri].includes(e))) p.problems.push(`Dreier-Kombi ${tri} enthält ${co} nicht`);
  if (p.problems.length) return p;
  switch (mon.rarity) {
    case 'COMMON':
      p.def = commonDefault(el, cs, mon.ps);
      p.egg = [weakOf(el, k4), base(el, k3, 2), base(el, k1, 2)];
      p.ms = { boss_1: base(el, k2, 2), boss_5: base(el, k1, 3), game_win: base(el, k2, 3) };
      break;
    case 'UNCOMMON':
      if (isAtk(k1)) p.def = [t1.strong(el, k1), t1.thrust(el, k1), lightOf(el, k2)];
      else p.def = [t1.shield(el, k1), t1.thrust(el, ba), k2 === ba ? t1.strike(el, k2) : lightOf(el, k2)];
      p.egg = [weakOf(el, k4), base(el, k2, 2), base(el, k1, 3), buffT2(el, k1)];
      p.ms = { boss_1: base(el, k3, 2), boss_5: base(el, k1, 2), game_win: base(el, k2, 3) };
      break;
    case 'RARE':
      p.def = [base(el, k1, 2), isAtk(k2) ? t1.strong(el, k2) : t1.shield(el, k2), t1.small(el, ba)];
      p.egg = [base(el, k1, 3), base(el, k2, 3), base(el, k3, 2), isAtk(k1) ? buffT2(el, k1) : passiveT3(el)];
      p.ms = { boss_1: base(el, k2, 2), boss_5: combo(co, k2, 0), game_win: combo(co, k1, 0) };
      break;
    case 'EPIC':
      p.def = [base(el, k1, 3), base(el, k2, 2), t1.small(el, ba)];
      p.egg = [base(el, k2, 3), swift(el, k1), base(el, k3, 3), buffT3(el, k1)];
      p.ms = { boss_1: combo(co, k2, 0), boss_5: combo(co, k1, 0), game_win: epicPassive(el, co, cs) };
      break;
    case 'LEGENDARY':
    case 'MYTHIC':
      p.def = [base(el, k1, 3), base(el, k2, 3), swift(el, ba)];
      p.egg = [combo(co, k1, 1), combo(co, k2, 1), mon.rarity === 'MYTHIC' ? top(tri) : top(co), buffT4(co)];
      p.ms = mon.rarity === 'MYTHIC'
        ? { boss_1: combo(tri, k1, 1), boss_5: top(co), game_win: passiveT4(co) }
        : { boss_1: combo(tri, k1, 0), boss_5: combo(tri, k1, 1), game_win: passiveT4(co) };
      break;
  }
  if (STARTERS.includes(mon.id)) { p.def = mon.def; p.egg = mon.unl; }
  return p;
}

// ─────────────────────────
// Rechnen, prüfen

const plans = new Map();
const unknown = new Set(), problems = [];
for (const mon of mons) {
  if (mon.manual) continue;
  const p = plan(mon);
  plans.set(mon.id, p);
  p.problems.forEach(x => problems.push(`#${mon.id} ${mon.label}: ${x}`));
  for (const s of [...p.def, ...p.egg, ...Object.values(p.ms)]) if (!s.startsWith('*') && !exists(s)) unknown.add(s);
}
if (unknown.size) problems.push('Skills aus den Tabellen gibt es nicht in skills.gd: ' + [...unknown].join(', '));

// ─────────────────────────
// monmap.gd schreiben

const KEYS = [['default_egg_skills', '[', ']'], ['unlockable_egg_skills', '[', ']'], ['milestone_egg_skills', '{', '}']];
// geplante Skills: bis es sie gibt der Ersatz (falls vorgesehen), sonst weglassen
const real = arr => arr.map(s => s.startsWith('*') ? FALLBACK[s] : s).filter(Boolean);

function rewriteBody(body, p) {
  const lines = [];
  lines.push(`\t\t"default_egg_skills": [${real(p.def).map(s => `"${s}"`).join(', ')}],`);
  const egg = real(p.egg);
  if (egg.length) lines.push(`\t\t"unlockable_egg_skills": [${egg.map(s => `"${s}"`).join(', ')}],`);
  const ms = Object.entries(p.ms).map(([k, s]) => [k, real([s])[0]]).filter(([, s]) => s);
  if (ms.length) {
    lines.push('\t\t"milestone_egg_skills": {');
    ms.forEach(([k, s]) => lines.push(`\t\t\t"${k}": "${s}",`));
    lines.push('\t\t},');
  }
  const found = [];
  for (const [key, open, close] of KEYS) {
    const re = new RegExp(`\\r?\\n\\t\\t"${key}": \\${open}[^\\${close}]*\\${close},`);
    const m = body.match(re);
    if (m) found.push({ index: m.index, length: m[0].length });
  }
  // alte Einträge raus, die neuen kommen an die Stelle des letzten (Kommentare dazwischen bleiben davor)
  found.sort((a, b) => b.index - a.index);
  let insertAt = -1;
  if (found.length) {
    insertAt = found[0].index;
    for (const f of found) {
      body = body.slice(0, f.index) + body.slice(f.index + f.length);
      if (f !== found[0]) insertAt -= f.length;
    }
  }
  if (insertAt < 0) {
    const mu = body.match(/\r?\n\t\t"max_upgrades": [^\r\n]*/);
    insertAt = mu ? mu.index + mu[0].length : body.length;
  }
  return body.slice(0, insertAt) + lines.map(l => NL + l).join('') + body.slice(insertAt);
}

let changed = [];
if (!ONLY_TEXT && !problems.length) {
  let out = monmapText;
  for (const mon of [...mons].reverse()) {
    if (mon.manual) continue;
    const nb = rewriteBody(mon.body, plans.get(mon.id));
    if (nb !== mon.body) changed.push(mon.id);
    out = out.slice(0, mon.bodyStart) + nb + out.slice(mon.bodyStart + mon.body.length);
  }
  if (out !== monmapText) fs.writeFileSync(MONMAP, out);
}

// ─────────────────────────
// skill_verteilung.txt (Teil C und D zwischen den Markierungen)

const RLABEL = { COMMON: 'Gewöhnlich', UNCOMMON: 'Ungewöhnlich', RARE: 'Selten', EPIC: 'Episch', LEGENDARY: 'Legendär', MYTHIC: 'Mythisch' };
const short = s => s.replace(/^(\*?)SKILL_/, '$1') + (FALLBACK[s] ? ` (bis dahin ${FALLBACK[s].replace('SKILL_', '')})` : '');
let txt = '';
txt += `Neue Skills, die noch fehlen (${NEW.size}). Sobald es sie in skills.gd gibt, trägt der nächste Lauf sie in monmap.gd ein:\n`;
for (const [id, d] of [...NEW.entries()].sort()) txt += `  ${short(id).padEnd(36)} ${d}\n`;
if (!NEW.size) txt += '  keine\n';
txt += '\n\nTEIL D: VERTEILUNG PRO ART\n==========================\n';
for (const r of Object.keys(RLABEL)) {
  const group = mons.filter(m => m.rarity === r);
  if (!group.length) continue;
  txt += `\n${'='.repeat(110)}\n${RLABEL[r].toUpperCase()} (${group.length} Arten)\n${'='.repeat(110)}\n`;
  for (const mon of group) {
    const ps = mon.ps;
    txt += `\n#${mon.id} ${mon.label}  [${RLABEL[r]}, ${mon.type}${STARTERS.includes(mon.id) ? ', Startmonster' : ''}]\n`;
    if (mon.manual) { txt += '  "skills_manual": true - wird von Hand gepflegt, nicht verändert\n'; continue; }
    const p = plans.get(mon.id);
    txt += `  Werte: KP ${ps.hp} | Ang ${ps.atk} | Vert ${ps.def} | SpAng ${ps.s_atk} | SpVert ${ps.s_def} | Init ${ps.speed}`;
    txt += `   Reihenfolge: ${p.cats.map(c => STATNAME[c]).join(' > ')}\n`;
    if (mon.co) txt += `  Neben-Element: ${mon.co}${mon.tri ? '   Dreier-Kombi: ' + mon.tri : ''}\n`;
    if (p.problems.length) { txt += `  FEHLER: ${p.problems.join('; ')}\n`; continue; }
    txt += `  Start:      ${p.def.map(short).join(', ')}\n`;
    txt += `  Ei-Attacke: ${p.egg.map(short).join(', ')}${STARTERS.includes(mon.id) ? '   (Startmonster: bleibt wie heute)' : ''}\n`;
    txt += `  Meilenst.:  boss_1 ${short(p.ms.boss_1)} | boss_5 ${short(p.ms.boss_5)} | game_win ${short(p.ms.game_win)}\n`;
  }
}
const planText = fs.readFileSync(PLAN, 'utf8');
const a = planText.indexOf(MARK_START), b = planText.indexOf(MARK_END);
if (a < 0 || b < a) {
  console.error(`Markierungen fehlen in skill_verteilung.txt:\n  ${MARK_START}\n  ${MARK_END}`);
  process.exit(1);
}
fs.writeFileSync(PLAN, planText.slice(0, a + MARK_START.length) + '\n' + txt + '\n' + planText.slice(b));

// ─────────────────────────
console.log(`Arten: ${mons.length} (${mons.filter(m => m.manual).length} manuell), noch fehlende Skills: ${NEW.size}`);
if (problems.length) {
  console.log('FEHLER, monmap.gd wurde NICHT geschrieben:\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log(ONLY_TEXT ? 'Nur Text: skill_verteilung.txt aktualisiert.' : `monmap.gd: ${changed.length} Arten geändert${changed.length ? ' (' + changed.reverse().join(', ') + ')' : ''}. skill_verteilung.txt aktualisiert.`);
