class_name DamageSim
extends RefCounted

## Live-Simulation des Schadens für das Debug-Menü.
## Rechnet mit den echten Arten aus der Monmap und Skills.stat_damage, also genau wie im Kampf:
## Schaden = fester Wert + Anteil x (Sp.) Angriff, die Verteidigung des Ziels zählt nicht.
## Vereinfachungen: keine Trophäen, Buffs, Schilde, Relikte; Element neutral; Anteile ohne ±15 %-Zufall.

## Beispiel-Angriffe: [Name, fester Schaden, Anteil vom Angriff]
const ATTACKS := [["leicht 5+0.2", 5.0, 0.2], ["mittel 8+0.3", 8.0, 0.3], ["Bsp. 20+0.7", 20.0, 0.7]]
## Angriff für Duelle und Vorteile (Leichter Stoß)
const DUEL_ATTACK := 0
const LEVELS := [5, 10, 15, 20, 25, 30, 35]
const LABEL_WIDTH := 22
const CELL_WIDTH := 16

## columns: [[Titel, Einstellungen], ...] für die Vergleichstabellen, leer = bisher gegen eingestellt
static func report(columns := []) -> String:
	if columns.is_empty():
		columns = [["bisher", DebugSettings.DAMAGE_DEFAULTS], ["eingestellt", DebugSettings.damage_settings()]]
	var species := _species()
	var glass: Dictionary = _best(species, func(sp): return maxf(sp.shares.atk, sp.shares.s_atk))
	var tank: Dictionary = _best(species, func(sp): return (sp.shares.def + sp.shares.s_def) / 2.0 + sp.shares.hp)
	var even: Dictionary = _best(species, func(sp): return -absf(maxf(sp.shares.atk, sp.shares.s_atk) - ((sp.shares.def + sp.shares.s_def) / 2.0 + sp.shares.hp) / 1.5))
	var out := PackedStringArray()
	out.append("SIMULATION (Element neutral, ohne Schilde) | Angreifer = Art %s, Tank = Art %s, ausgeglichen = Art %s" % [
		glass.name, tank.name, even.name])

	out.append("\n1) Schaden und Treffer bis K.O. nach Stufe, ausgeglichen gegen ausgeglichen (eingestellt)")
	var head := "Stufe (Ang. / KP)".rpad(LABEL_WIDTH)
	for attack in ATTACKS:
		head += String(attack[0]).lpad(CELL_WIDTH)
	out.append(head)
	for level in LEVELS:
		var a := _mon(even, level)
		var t := _mon(even, level)
		var line := ("%d (%d / %d)" % [level, roundi(_attack_stat(a)), roundi(t.hp)]).rpad(LABEL_WIDTH)
		for attack in ATTACKS:
			var d := _damage(a, attack)
			line += ("%d (%dx)" % [d, _hits(d, t)]).lpad(CELL_WIDTH)
		out.append(line)

	out.append("\n2) Treffer bis K.O. bei Stufenunterschied (%s)" % ATTACKS[DUEL_ATTACK][0])
	out.append(_head(columns))
	for pair in [[5, 5], [7, 5], [5, 7], [10, 5], [15, 5], [5, 15], [21, 20], [35, 35]]:
		out.append(_row("Stufe %d -> %d" % pair, columns, func():
			var a := _mon(even, pair[0])
			var t := _mon(even, pair[1])
			var d := _damage(a, ATTACKS[DUEL_ATTACK])
			return "%d (%d/%d)" % [_hits(d, t), d, roundi(t.hp)]))

	out.append("\n3) Kampfkraft-Vorteil der höheren Stufe im Duell")
	out.append(_head(columns))
	for pair in [[6, 5], [7, 5], [10, 5], [15, 5], [12, 10], [21, 20]]:
		out.append(_row("%d vs %d" % pair, columns, func():
			return "%.2fx" % _advantage(_mon(even, pair[0]), _mon(even, pair[1]))))

	out.append("\n4) Duelle gleicher Stufe (10): Sieger und Rest-KP")
	out.append(_head(columns))
	for duel in [[glass, tank, "Angreifer vs Tank"], [glass, even, "Angreifer vs Ausgegl."], [tank, even, "Tank vs Ausgegl."]]:
		out.append(_row(duel[2], columns, func():
			var r := _duel(_mon(duel[0], 10), _mon(duel[1], 10))
			var names: PackedStringArray = duel[2].split(" vs ")
			return "%s %d%%" % [names[0] if r.a_wins else names[1], roundi(r.rest * 100)]))

	out.append("\n5) BST-Vorteil im Duell (Stufe 10, gleich verteilte Werte)")
	out.append(_head(columns))
	for pair in [[220, "Uncommon 220"], [240, "Epic 240"], [255, "Legendary 255"], [270, "Mythic 270"], [280, "Mythic 280"]]:
		out.append(_row(pair[1] + " vs 200", columns, func():
			return "%.2fx" % _advantage(_mon(_even_species(pair[0]), 10), _mon(_even_species(200), 10))))
	return "\n".join(out)

# ─────────────────────────
# Tabellen

static func _head(columns: Array) -> String:
	var line := "".rpad(LABEL_WIDTH)
	for column in columns:
		line += String(column[0]).lpad(CELL_WIDTH)
	return line

## Eine Zeile: cell wird pro Spalte mit deren Einstellungen gerechnet
static func _row(label: String, columns: Array, cell: Callable) -> String:
	var line := label.rpad(LABEL_WIDTH)
	for column in columns:
		line += String(DebugSettings.with_damage_settings(column[1], cell)).lpad(CELL_WIDTH)
	return line

# ─────────────────────────
# Monster und Kampf

static func _species() -> Array:
	var list := []
	for meta in Monmap.mons:
		if not meta.has("preferred_stats") or not meta.has("stats"):
			continue
		var shares := {}
		for stat in DebugSettings.STATS:
			shares[stat] = meta.preferred_stats[stat] / 100.0
		list.append({"name": meta.name, "bst": roundi((meta.stats[0] + meta.stats[1]) / 2.0), "shares": shares})
	return list

static func _even_species(bst: int) -> Dictionary:
	var shares := {}
	for stat in DebugSettings.STATS:
		shares[stat] = 1.0 / DebugSettings.STATS.size()
	return {"name": "bst%d" % bst, "bst": bst, "shares": shares}

## Art mit dem höchsten Wert von score
static func _best(species: Array, score: Callable) -> Dictionary:
	var best: Dictionary = species[0]
	for sp in species:
		if score.call(sp) > score.call(best):
			best = sp
	return best

## Werte wie Monster._base_stat (mit Reserve, Growth, Stufen-Sockel) und hp() (KP-Multiplikator)
static func _mon(sp: Dictionary, level: int) -> Dictionary:
	var mon := {"bst": sp.bst, "level": level}
	for stat in DebugSettings.STATS:
		var share := DebugSettings.effective_share(stat, sp.shares[stat])
		mon[stat] = share * Helper.points_per_level(sp.bst) * Monster.STAT_SCALE * DebugSettings.level_scale(level)
	mon.hp *= DebugSettings.hp_scale()
	return mon

## Der Angreifer nimmt seine bessere Angriffsart
static func _attack_stat(mon: Dictionary) -> float:
	return maxf(mon.atk, mon.s_atk)

## Schaden wie Skills.calc_damage, attack = Eintrag aus ATTACKS
static func _damage(from: Dictionary, attack: Array) -> float:
	return Skills.stat_damage(_attack_stat(from), attack[1], attack[2], 1.0)

static func _hits(damage: float, target: Dictionary) -> int:
	return ceili(roundi(target.hp) / maxf(damage, 1.0))

## Wie viel schneller a das Ziel b besiegt als umgekehrt (ungerundet)
static func _advantage(a: Dictionary, b: Dictionary) -> float:
	var speed_a: float = _damage(a, ATTACKS[DUEL_ATTACK]) / b.hp
	var speed_b: float = _damage(b, ATTACKS[DUEL_ATTACK]) / a.hp
	return speed_a / maxf(speed_b, 0.0001)

## 1 gegen 1, beide mit dem Duell-Angriff, der Schnellere zuerst
static func _duel(a: Dictionary, b: Dictionary) -> Dictionary:
	var hp_a := float(roundi(a.hp))
	var hp_b := float(roundi(b.hp))
	var damage_a := _damage(a, ATTACKS[DUEL_ATTACK])
	var damage_b := _damage(b, ATTACKS[DUEL_ATTACK])
	var a_turn: bool = a.speed >= b.speed
	for i in 400:
		if a_turn:
			hp_b -= damage_a
		else:
			hp_a -= damage_b
		if hp_b <= 0:
			return {"a_wins": true, "rest": hp_a / roundi(a.hp)}
		if hp_a <= 0:
			return {"a_wins": false, "rest": hp_b / roundi(b.hp)}
		a_turn = not a_turn
	return {"a_wins": true, "rest": 0.0}
