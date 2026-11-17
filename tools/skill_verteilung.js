// Skill-Verteilung der Arten nach den Regeln aus todo_skill_balance.txt / skill_verteilung.txt
//
//   node tools/skill_verteilung.js             verteilt neu: schreibt monmap.gd und skill_verteilung.txt
//   node tools/skill_verteilung.js --nur-text  nur skill_verteilung.txt (Vorschau, monmap.gd bleibt)
//   node tools/skill_verteilung.js --seed=abc  Meilensteine mit einem anderen Seed neu würfeln
//
// Liest bei jedem Lauf script/globals/monmap.gd (Seltenheit, Element, preferred_stats, affinity, affinity_triple)
// und script/globals/skills.gd (welche Skills es gibt). Skills: kein Zufall, gleiche Daten -> gleiche Verteilung.
// Meilensteine (welche Bedingung pro Art) werden gewürfelt, mit festem Seed pro Art (MILESTONE_SEED + Name):
// ein neuer Lauf würfelt dasselbe, solange Seed und Tabellen (MILESTONE_SLOTS) gleich bleiben.
// Geschrieben werden default_egg_skills, unlockable_egg_skills, milestone_egg_skills und bounty_egg_skills,
// dazu die Liste Skills.BOUNTIES in skills.gd (ein gewürfeltes Kopfgeld pro Art, siehe BOUNTY_DEPTH).
// Danach sortiert es die Skill-Listen in skills.gd: Pool (Start/Ei-Attacke), milestone_skills (nur Meilenstein),
// reward_skills (von keiner Art benutzt, ab Stufe 2: nur im Couvert), draft_skills (unbenutzt, Stufe 1).
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
const SEED_ARG = process.argv.find(a => a.startsWith('--seed='));
const MILESTONE_SEED = SEED_ARG ? SEED_ARG.slice(7) : 'meilensteine-1';

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

// Meilensteine (Schlüssel wie Skills.MILESTONES in skills.gd). Pro Art drei Plätze, pro Platz wird eine Bedingung
// gewürfelt [Schlüssel, Gewicht]. Alles gilt innerhalb EINES Runs mit der Art als Start-Monster.
// Standard: Gewöhnlich/Ungewöhnlich Boss 1 + Boss 3, ab Selten Boss 2 + Boss 4, dritter Platz Chaos
// (bei Gewöhnlich/Ungewöhnlich manchmal nur "ein neues Element"). Den Endboss gibt es als Meilenstein nicht mehr.
const MILESTONE_SLOTS = {
  low: [
    [['boss_1', 55], ['kills_5', 25], ['finisher_1', 20]],
    [['boss_3', 50], ['kills_10', 15], ['flawless_2', 15], ['bounty', 10], ['finisher_2', 10]],
    [['chaos', 60], ['new_element', 40]],
  ],
  high: [
    [['boss_2', 50], ['kills_8', 20], ['flawless_1', 15], ['finisher_2', 15]],
    [['boss_4', 50], ['kills_15', 15], ['flawless_3', 10], ['bounty', 15], ['finisher_3', 10]],
    [['chaos', 100]],
  ],
};
// Schwierigkeit: die drei Meilenstein-Skills (schwach -> stark) gehen in dieser Reihenfolge an die Bedingungen
const MILESTONE_DIFFICULTY = {
  boss_1: 1, finisher_1: 1.5, kills_5: 2, flawless_1: 2, new_element: 2, boss_2: 2, finisher_2: 2.5, kills_8: 2.5,
  boss_3: 3, flawless_2: 3, kills_10: 3, bounty: 3.5, finisher_3: 3.5, boss_4: 4, kills_15: 4, flawless_3: 4, chaos: 5,
};
const MILESTONE_LABEL = {
  boss_1: 'Boss 1', boss_2: 'Boss 2', boss_3: 'Boss 3', boss_4: 'Boss 4', flawless_1: 'Boss 1 ohne K.O.', flawless_2: 'Boss 2 ohne K.O.',
  flawless_3: 'Boss 3 ohne K.O.', finisher_1: '1x letzter Boss-Treffer', finisher_2: '2x letzter Boss-Treffer', finisher_3: '3x letzter Boss-Treffer',
  kills_5: '5 K.O.s', kills_8: '8 K.O.s', kills_10: '10 K.O.s', kills_15: '15 K.O.s', bounty: 'Kopfgeld', new_element: 'neues Element', chaos: 'Chaos',
};
// kleiner Zufallsgenerator mit Seed (xmur3 + mulberry32), damit jeder Lauf gleich würfelt
function rng(seedText) {
  let h = 1779033703 ^ seedText.length;
  for (let i = 0; i < seedText.length; i++) { h = Math.imul(h ^ seedText.charCodeAt(i), 3432918353); h = (h << 13) | (h >>> 19); }
  let a = h >>> 0;
  return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function rollMilestones(mon) {
  const rand = rng(MILESTONE_SEED + ':' + mon.id);
  const slots = MILESTONE_SLOTS[['COMMON', 'UNCOMMON'].includes(mon.rarity) ? 'low' : 'high'];
  return slots.map(options => {
    let roll = rand() * options.reduce((s, [, w]) => s + w, 0);
    for (const [key, w] of options) if ((roll -= w) < 0) return key;
    return options[options.length - 1][0];
  });
}
// Bedingungen nach Schwierigkeit sortieren und die Skills (schwach -> stark) zuordnen
function assignMilestones(mon, skills) {
  const keys = rollMilestones(mon).map((k, i) => [k, i])
    .sort((x, y) => MILESTONE_DIFFICULTY[x[0]] - MILESTONE_DIFFICULTY[y[0]] || x[1] - y[1]).map(([k]) => k);
  return Object.fromEntries(keys.map((k, i) => [k, skills[i]]));
}

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
    bountyTarget: /\n\t\t"bounty_target":/.test(body),
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
const passiveT4 = co => planned(`SKILL_PASSIVE_${co}_T4`, 'Stufe 4, Passiv element_power 15 mit passive_element = Kombi (Angriffe mit allen Elementen der Kombi +15 %), "trainer": false, nur Meilenstein');
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
      p.ms = [base(el, k2, 2), base(el, k1, 3), base(el, k2, 3)];
      break;
    case 'UNCOMMON':
      if (isAtk(k1)) p.def = [t1.strong(el, k1), t1.thrust(el, k1), lightOf(el, k2)];
      else p.def = [t1.shield(el, k1), t1.thrust(el, ba), k2 === ba ? t1.strike(el, k2) : lightOf(el, k2)];
      p.egg = [weakOf(el, k4), base(el, k2, 2), base(el, k1, 3), buffT2(el, k1)];
      p.ms = [base(el, k3, 2), base(el, k1, 2), base(el, k2, 3)];
      break;
    case 'RARE':
      p.def = [base(el, k1, 2), isAtk(k2) ? t1.strong(el, k2) : t1.shield(el, k2), t1.small(el, ba)];
      p.egg = [base(el, k1, 3), base(el, k2, 3), base(el, k3, 2), isAtk(k1) ? buffT2(el, k1) : passiveT3(el)];
      p.ms = [base(el, k2, 2), combo(co, k2, 0), combo(co, k1, 0)];
      break;
    case 'EPIC':
      p.def = [base(el, k1, 3), base(el, k2, 2), t1.small(el, ba)];
      p.egg = [base(el, k2, 3), swift(el, k1), base(el, k3, 3), buffT3(el, k1)];
      p.ms = [combo(co, k2, 0), combo(co, k1, 0), epicPassive(el, co, cs)];
      break;
    case 'LEGENDARY':
    case 'MYTHIC':
      p.def = [base(el, k1, 3), base(el, k2, 3), swift(el, ba)];
      p.egg = [combo(co, k1, 1), combo(co, k2, 1), mon.rarity === 'MYTHIC' ? top(tri) : top(co), buffT4(co)];
      p.ms = mon.rarity === 'MYTHIC'
        ? [combo(tri, k1, 1), top(co), passiveT4(co)]
        : [combo(tri, k1, 0), combo(tri, k1, 1), passiveT4(co)];
      break;
  }
  // Meilenstein-Skills (schwach -> stark) auf die gewürfelten Bedingungen verteilen
  p.ms = assignMilestones(mon, p.ms);
  if (STARTERS.includes(mon.id)) { p.def = mon.def; p.egg = mon.unl; }
  // Kopfgeld-Ei-Attacke: der erste Kandidat, den es gibt und den die Art noch nicht hat
  const taken = new Set([...p.def, ...p.egg, ...Object.values(p.ms)]);
  const bountyCandidates = {
    COMMON: () => [base(el, k3, 3), base(el, k4, 2), base(el, k4, 3)],
    UNCOMMON: () => [base(el, k3, 3), base(el, k4, 3), base(el, k2, 2)],
    RARE: () => [combo(co, k3, 0), combo(co, k4, 0), base(el, k4, 3)],
    EPIC: () => [combo(co, k3, 0), combo(co, k4, 0), base(el, k4, 3)],
    LEGENDARY: () => [combo(tri, k2, 0), combo(tri, k2, 1), combo(co, k3, 1)],
    MYTHIC: () => [combo(tri, k2, 1), combo(tri, k3, 1), combo(co, k3, 1)],
  }[mon.rarity]();
  p.bounty = bountyCandidates.find(s => exists(s) && !taken.has(s)) || null;
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
// Kopfgelder: pro Art eins, Ziel ist ein zufälliges Alpha-Monster. Je seltener die Art, die die Attacke bekommt,
// desto tiefer liegt das Kopfgeld (min_depth = Biom - 1). Stufen-Bonus nach Tiefe. Gewürfelt mit Seed wie die Meilensteine.
const BOUNTY_DEPTH = { COMMON: 0, UNCOMMON: 1, RARE: 2, EPIC: 3, LEGENDARY: 4, MYTHIC: 4 };
const BOUNTY_LEVEL_BONUS = [2, 2, 3, 3, 4];
const RARITY_ORDER = ['COMMON', 'UNCOMMON', 'RARE', 'EPIC', 'LEGENDARY', 'MYTHIC'];
const bountyTargets = mons.filter(m => !m.manual && !m.bountyTarget && m.rarity !== 'MYTHIC');
const bounties = [];
for (const mon of mons) {
  const p = plans.get(mon.id);
  if (!p || !p.bounty) continue;
  const rand = rng(MILESTONE_SEED + ':bounty:' + mon.id);
  // Ziel höchstens so selten wie die belohnte Art (ab Legendär alles bis Legendär)
  const cap = RARITY_ORDER.indexOf(mon.rarity);
  const options = bountyTargets.filter(t => RARITY_ORDER.indexOf(t.rarity) <= cap);
  const target = options[Math.floor(rand() * options.length)];
  const depth = BOUNTY_DEPTH[mon.rarity];
  const key = 'alpha_' + mon.id;
  bounties.push({ key, mon: target.id, label: target.label, level_bonus: BOUNTY_LEVEL_BONUS[depth], min_depth: depth, owner: mon.id });
  p.bountyKey = key;
}

// ─────────────────────────
// monmap.gd schreiben

const KEYS = [['default_egg_skills', '[', ']'], ['unlockable_egg_skills', '[', ']'], ['milestone_egg_skills', '{', '}'], ['bounty_egg_skills', '{', '}']];
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
  if (p.bounty && p.bountyKey) lines.push(`\t\t"bounty_egg_skills": {"${p.bountyKey}": "${p.bounty}"},`);
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
// skills.gd: Skill-Listen neu einsortieren (siehe Kommentar "Skill-Listen" dort)
//   Start-Skill oder Ei-Attacke einer Art -> Pool-Liste nach Art des Skills
//   nur Meilenstein                       -> milestone_skills
//   von keiner Art benutzt, ab Stufe 2    -> reward_skills (nur im Couvert)
//   von keiner Art benutzt, Stufe 1       -> draft_skills
// starter_skills, standard_skills, bounty_skills und ascension_skills bleiben unberührt.

const MANAGED = ['egg_skills', 'defensive_skills', 'buff_skills', 'passive_skills', 'area_skills', 'milestone_skills', 'bounty_skills', 'reward_skills', 'draft_skills'];
// Baustein -> [Pool-Liste, Index des Arguments "tier" (null = immer Stufe 1)]
const BUILDERS = {
  _flat_attack_skill: ['egg_skills', null], _attack_skill: ['egg_skills', 5],
  _flat_shield_skill: ['defensive_skills', null], _shield_skill: ['defensive_skills', 5], _cross_shield_skill: ['defensive_skills', 5],
  _buff_skill: ['buff_skills', 5], _team_buff_skill: ['buff_skills', 5], _boon_skill: ['buff_skills', 7],
  _passive_skill: ['passive_skills', 3], _area_skill: ['area_skills', 3],
};
const ELEM_ORDER = ['FIRE', 'WATER', 'EARTH', 'AIR', 'STEAM', 'LIGHTNING', 'MAGMA', 'ICE', 'DUST', 'MUD', 'THUNDERSTORM', 'VOLCANO', 'ASH_STORM', 'SWAMP', 'CHAOS'];
const ELEM_DE = { FIRE: 'Feuer', WATER: 'Wasser', EARTH: 'Erde', AIR: 'Luft', STEAM: 'Dampf', LIGHTNING: 'Blitz', MAGMA: 'Magma', ICE: 'Eis', DUST: 'Staub',
  MUD: 'Schlamm', THUNDERSTORM: 'Gewitter', VOLCANO: 'Vulkan', ASH_STORM: 'Aschesturm', SWAMP: 'Sumpf', CHAOS: 'Chaos' };

// An Kommas auf oberster Ebene trennen (Klammern und Strings zählen mit)
function splitTop(s) {
  const parts = [];
  let depth = 0, inStr = false, cur = '';
  for (const ch of s) {
    if (inStr) { cur += ch; if (ch === '"') inStr = false; continue; }
    if (ch === '"') inStr = true;
    else if ('([{'.includes(ch)) depth++;
    else if (')]}'.includes(ch)) depth--;
    else if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim()) parts.push(cur);
  return parts.map(p => p.trim()).filter(Boolean);
}
// Inhalt zwischen der Klammer bei open und ihrem Gegenstück
function matching(s, open) {
  let depth = 0, inStr = false;
  for (let i = open; i < s.length; i++) {
    const ch = s[i];
    if (inStr) { if (ch === '"') inStr = false; continue; }
    if (ch === '"') inStr = true;
    else if ('([{'.includes(ch)) depth++;
    else if (')]}'.includes(ch) && --depth === 0) return i;
  }
  throw new Error('Klammer ohne Gegenstück');
}
function readList(text, name) {
  const head = text.indexOf(`var ${name} = [`);
  if (head < 0) throw new Error(`skills.gd: var ${name} fehlt`);
  const open = text.indexOf('[', head), close = matching(text, open);
  const body = text.slice(open + 1, close).split(/\r?\n/).filter(l => !l.trim().startsWith('#')).join('\n');
  return { start: head, end: close + 1, entries: splitTop(body) };
}
function describe(entry, order) {
  const name = (entry.match(/"(SKILL_\w+)"/) || [])[1];
  const builder = Object.keys(BUILDERS).find(bd => entry.includes(bd + '('));
  if (!name || !builder) throw new Error('Skill nicht erkannt: ' + entry.slice(0, 80));
  const open = entry.indexOf(builder + '(') + builder.length;
  const args = splitTop(entry.slice(open + 1, matching(entry, open)));
  const tierArg = BUILDERS[builder][1];
  const tier = tierArg === null ? 1 : +args[tierArg];
  // "wild": false braucht es nicht mehr, Meilenstein-Skills liegen in milestone_skills
  let clean = entry.replace(/\{\s*"wild": false\s*\}/g, '{}').replace(/,\s*"wild": false/g, '').replace(/"wild": false,\s*/g, '').replace(/^_with\(([\s\S]*),\s*\{\s*\}\)$/, '$1');
  return { name, builder, tier, nature: args[1], pool: BUILDERS[builder][0], text: clean, order };
}

function sortSkillLists() {
  let text = fs.readFileSync(SKILLS, 'utf8');
  const skills = [];
  for (const list of MANAGED) readList(text, list).entries.forEach(e => skills.push(describe(e, skills.length)));
  // Wer wird wie benutzt?
  const pool = new Set(), ms = new Set(), bs = new Set();
  const msOf = body => { const x = body.match(/"milestone_egg_skills": \{([^}]*)\}/); return x ? (x[1].match(/SKILL_\w+/g) || []) : []; };
  for (const mon of mons) {
    if (mon.manual) { [...mon.def, ...mon.unl].forEach(s => pool.add(s)); msOf(mon.body).forEach(s => ms.add(s)); continue; }
    const p = plans.get(mon.id);
    real([...p.def, ...p.egg]).forEach(s => pool.add(s));
    real(Object.values(p.ms)).forEach(s => ms.add(s));
    if (p.bounty) bs.add(p.bounty);
  }
  const target = s => pool.has(s.name) ? s.pool : ms.has(s.name) ? 'milestone_skills' : bs.has(s.name) ? 'bounty_skills'
    : s.tier >= 2 ? 'reward_skills' : 'draft_skills';
  const elemIndex = s => { const i = ELEM_ORDER.indexOf(s.nature); return i < 0 ? ELEM_ORDER.length : i; };
  const counts = {};
  // von hinten ersetzen, damit die Positionen stimmen
  for (const list of [...MANAGED].sort((x, y) => readList(text, y).start - readList(text, x).start)) {
    const mine = skills.filter(s => target(s) === list).sort((x, y) => elemIndex(x) - elemIndex(y) || x.tier - y.tier || x.order - y.order);
    counts[list] = mine.length;
    let out = `var ${list} = [`;
    if (mine.length) {
      let last = null;
      for (const s of mine) {
        if (s.nature !== last) { out += `\n\t# ${ELEM_DE[s.nature] || s.nature}`; last = s.nature; }
        const lines = s.text.split(/\r?\n/).map(l => l.trim());
        out += '\n\t' + lines[0] + lines.slice(1).map(l => '\n\t\t' + l).join('') + ',';
      }
      out += '\n]';
    } else out += ']';
    const { start, end } = readList(text, list);
    text = text.slice(0, start) + out + text.slice(end);
  }
  const before = fs.readFileSync(SKILLS, 'utf8');
  if (text !== before) fs.writeFileSync(SKILLS, text);
  return { counts, changed: text !== before, reward: skills.filter(s => target(s) === 'reward_skills') };
}

let lists = null;
if (!ONLY_TEXT && !problems.length) lists = sortSkillLists();

// Skills.BOUNTIES in skills.gd neu schreiben (Texte: BOUNTY_HINT / BOUNTY_SOURCE mit {mon} und {biome})
if (!ONLY_TEXT && !problems.length) {
  const text = fs.readFileSync(SKILLS, 'utf8');
  const head = text.indexOf('const BOUNTIES = [');
  if (head < 0) throw new Error('skills.gd: const BOUNTIES fehlt');
  const close = matching(text, text.indexOf('[', head));
  const rows = bounties.map(b => `\t{"key": "${b.key}", "mon": "${b.mon}", "level_bonus": ${b.level_bonus}, "min_depth": ${b.min_depth}, `
    + `"label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},`);
  const out = 'const BOUNTIES = [\n\t# automatisch erzeugt (tools/skill_verteilung.js): key = alpha_<Art, die die Ei-Attacke bekommt>, mon = Ziel\n'
    + rows.join('\n') + '\n]';
  const next = text.slice(0, head) + out + text.slice(close + 1);
  if (next !== text) fs.writeFileSync(SKILLS, next);
}

// ─────────────────────────
// skill_verteilung.txt (Teil C und D zwischen den Markierungen)

const RLABEL = { COMMON: 'Gewöhnlich', UNCOMMON: 'Ungewöhnlich', RARE: 'Selten', EPIC: 'Episch', LEGENDARY: 'Legendär', MYTHIC: 'Mythisch' };
const short = s => s.replace(/^(\*?)SKILL_/, '$1') + (FALLBACK[s] ? ` (bis dahin ${FALLBACK[s].replace('SKILL_', '')})` : '');
let txt = '';
txt += `Neue Skills, die noch fehlen (${NEW.size}). Sobald es sie in skills.gd gibt, trägt der nächste Lauf sie in monmap.gd ein:\n`;
for (const [id, d] of [...NEW.entries()].sort()) txt += `  ${short(id).padEnd(36)} ${d}\n`;
if (!NEW.size) txt += '  keine\n';
if (lists) {
  txt += '\nSkill-Listen in skills.gd nach diesem Lauf:\n';
  for (const [list, n] of Object.entries(lists.counts)) txt += `  ${list.padEnd(18)} ${n}\n`;
  const byTier = {};
  lists.reward.forEach(s => (byTier[s.tier] = byTier[s.tier] || []).push(s.name.replace('SKILL_', '')));
  txt += '\nNur im Couvert (reward_skills, von keiner Art benutzt), dazu kommt der gemeinsame Pool ab Stufe 2:\n';
  for (const tier of Object.keys(byTier).sort()) txt += `  Stufe ${tier}: ${byTier[tier].join(', ')}\n`;
}
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
    txt += `  Meilenst.:  ${Object.entries(p.ms).map(([k, s]) => `${MILESTONE_LABEL[k] || k}: ${short(s)}`).join(' | ')}\n`;
    const bt = bounties.find(b => b.owner === mon.id);
    if (bt) txt += `  Kopfgeld:   ${short(p.bounty)} (Alpha ${bt.label || '#' + bt.mon}, ab Biom ${bt.min_depth + 1}, +${bt.level_bonus} Stufen)\n`;
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
if (lists) console.log(`skills.gd: ${lists.changed ? 'Listen neu sortiert' : 'unverändert'} (${Object.entries(lists.counts).map(([k, v]) => k + ' ' + v).join(', ')})`);
