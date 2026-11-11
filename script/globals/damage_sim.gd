class_name DamageSim
extends RefCounted

## Live-Simulation der Schadensformel für das Debug-Menü (wie tools/damage_sim.js).
## Vergleicht "bisher" (DebugSettings.DAMAGE_DEFAULTS) mit den eingestellten Werten.
## Rechnet mit den echten Arten aus der Monmap und Skills.stat_damage, also genau wie im Kampf.
## Vereinfachungen: keine Edelsteine, Buffs, Schilde, Relikte; Element neutral; Anteile ohne ±15 %-Zufall.

const VALUE := 40.0
const LABEL_WIDTH := 22
const CELL_WIDTH := 16

## columns: [[Titel, Einstellungen], ...], leer = bisher gegen eingestellt
static func report(columns := []) -> String:
	if columns.is_empty():
		columns = [["bisher", DebugSettings.DAMAGE_DEFAULTS], ["eingestellt", DebugSettings.damage_settings()]]
	var species := _species()
	var glass: Dictionary = _best(species, func(sp): return maxf(sp.shares.atk, sp.shares.s_atk))
	var tank: Dictionary = _best(species, func(sp): return (sp.shares.def + sp.shares.s_def) / 2.0 + sp.shares.hp)
	var even: Dictionary = _best(species, func(sp): return -absf(maxf(sp.shares.atk, sp.shares.s_atk) - ((sp.shares.def + sp.shares.s_def) / 2.0 + sp.shares.hp) / 1.5))
	var out := PackedStringArray()
	out.append("SIMULATION (Skill-Wert %d, Element neutral) | Angreifer = Art %s, Tank = Art %s, ausgeglichen = Art %s" % [
		VALUE, glass.name, tank.name, even.name])

	out.append("\n1) Treffer bis K.O. (Schaden/KP), ausgeglichen gegen ausgeglichen")
	out.append(_head(columns))
	for pair in [[5, 5], [7, 5], [5, 7], [10, 5], [15, 5], [5, 15], [12, 10], [21, 20], [35, 35]]:
		out.append(_row("Stufe %d -> %d" % pair, columns, func():
			var a := _mon(even, pair[0])
			var t := _mon(even, pair[1])
			var d := _damage(a, t, VALUE)
			return "%d (%d/%d)" % [_hits(d, t), d, roundi(t.hp)]))

	out.append("\n2) Kampfkraft-Vorteil der höheren Stufe im Duell")
	out.append(_head(columns))
	for pair in [[6, 5], [7, 5], [10, 5], [15, 5], [12, 10], [21, 20]]:
		out.append(_row("%d vs %d" % pair, columns, func():
			return "%.2fx" % _advantage(_mon(even, pair[0]), _mon(even, pair[1]))))

	out.append("\n3) Wert der Stats: +20 % auf einen Wert gegen eine Kopie (Stufe 10, physisch)")
	out.append(_head(columns))
	for stat in ["hp", "atk", "def"]:
		out.append(_row("+20 %% %s" % stat, columns, func():
			return "%.2fx" % _advantage(_mon(even, 10, {"s_atk": 0.0, stat: 1.2}), _mon(even, 10, {"s_atk": 0.0}))))

	out.append("\n4) Duelle gleicher Stufe (10): Sieger und Rest-KP")
	out.append(_head(columns))
	for duel in [[glass, tank, "Angreifer vs Tank"], [glass, even, "Angreifer vs Ausgegl."], [tank, even, "Tank vs Ausgegl."]]:
		out.append(_row(duel[2], columns, func():
			var r := _duel(_mon(duel[0], 10), _mon(duel[1], 10))
			var names: PackedStringArray = duel[2].split(" vs ")
			return "%s %d%%" % [names[0] if r.a_wins else names[1], roundi(r.rest * 100)]))

	out.append("\n5) Stufe 15 (Angreifer) trifft Stufe 5: Treffer bis K.O. gegen Tank / Angreifer-Art")
	out.append(_head(columns))
	for value in [25.0, 40.0, 55.0, 70.0, 90.0]:
		out.append(_row("Skill-Wert %d" % value, columns, func():
			var a := _mon(glass, 15)
			var t1 := _mon(tank, 5)
			var t2 := _mon(glass, 5)
			return "%d / %d" % [_hits(_damage(a, t1, value), t1), _hits(_damage(a, t2, value), t2)]))

	out.append("\n6) Tank-Check (Stufe 10): Ziel mit x-facher Verteidigung, Treffer bis K.O.")
	out.append(_head(columns))
	for factor in [1.0, 1.5, 2.0, 3.0, 4.0]:
		out.append(_row("Vert. x%.1f" % factor, columns, func():
			var a := _mon(even, 10)
			var t := _mon(even, 10, {"def": factor, "s_def": factor})
			var d := _damage(a, t, VALUE)
			return "%d (%d/%d)" % [_hits(d, t), d, roundi(t.hp)]))

	out.append("\n7) BST-Vorteil im Duell (Stufe 10, gleich verteilte Werte)")
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
static func _mon(sp: Dictionary, level: int, mods := {}) -> Dictionary:
	var mon := {"bst": sp.bst, "level": level}
	for stat in DebugSettings.STATS:
		var share := DebugSettings.effective_share(stat, sp.shares[stat])
		mon[stat] = share * Helper.points_per_level(sp.bst) * Monster.STAT_SCALE * DebugSettings.level_scale(level) * mods.get(stat, 1.0)
	mon.hp *= DebugSettings.hp_scale()
	return mon

## Schaden wie Skills.calc_damage, der Angreifer nimmt seine bessere Angriffsart
static func _damage(from: Dictionary, to: Dictionary, value: float) -> float:
	var physical: bool = from.atk >= from.s_atk
	var atk: float = from.atk if physical else from.s_atk
	var def: float = to.def if physical else to.s_def
	# wie Monster.typical_stat
	var typical := Helper.points_per_level(DebugSettings.damage_base_bst(from.bst)) * Monster.STAT_SCALE \
		* DebugSettings.level_scale(from.level) / DebugSettings.STATS.size()
	return Skills.stat_damage(atk, def, from.level, typical, value, 1.0)

static func _hits(damage: float, target: Dictionary) -> int:
	return ceili(roundi(target.hp) / maxf(damage, 1.0))

## Wie viel schneller a das Ziel b besiegt als umgekehrt (ungerundet)
static func _advantage(a: Dictionary, b: Dictionary) -> float:
	var speed_a: float = _damage(a, b, VALUE) / b.hp
	var speed_b: float = _damage(b, a, VALUE) / a.hp
	return speed_a / maxf(speed_b, 0.0001)

## 1 gegen 1, beide mit VALUE, der Schnellere zuerst
static func _duel(a: Dictionary, b: Dictionary) -> Dictionary:
	var hp_a := float(roundi(a.hp))
	var hp_b := float(roundi(b.hp))
	var damage_a := _damage(a, b, VALUE)
	var damage_b := _damage(b, a, VALUE)
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
