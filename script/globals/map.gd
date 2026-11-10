extends Node

enum PATH_TYPE {
	COMBAT = 0,
	BOSS,
	CAMP,
	SHOP,
	TRAINER,
	JAILER,
	EVENT,
	TREASURE,
	GEM,
	# Rastlager am Ende jedes Pfads vor dem Boss: Ausruhen, Laden und Trainer (hub_camp.gd)
	HUB,
}

class path:
	var _type = PATH_TYPE.COMBAT
	var _pos = Vector3.ZERO
	var _path = []
	var _ui_item = null
	# Gegner dieses Felds, stehen seit dem Betreten des Bioms fest (generate_encounters). Stufe und Aktionen kommen erst im Kampf.
	var _enemies: Array[Monster] = []
	var _name_map = {
		0: "COMBAT",
		1: "BOSS",
		2: "CAMP",
		3: "SHOP",
		4: "TRAINER",
		5: "JAILER",
		6: "EVENT",
		7: "TREASURE",
		8: "GEM",
		9: "HUB",
	}

	func _init(pos: Vector3):
		_pos = pos
	
	func get_name() -> String:
		return _name_map[_type]

# Icon pro Feldtyp, auf der Karte und in der Legende (world_map.gd, map_legend.gd)
const ICONS := {
	PATH_TYPE.COMBAT: preload("res://assets/ui/map/node_combat.svg"),
	PATH_TYPE.BOSS: preload("res://assets/ui/map/node_boss.svg"),
	PATH_TYPE.CAMP: preload("res://assets/ui/map/node_camp.svg"),
	PATH_TYPE.HUB: preload("res://assets/ui/map/node_hub.svg"),
	PATH_TYPE.SHOP: preload("res://assets/ui/map/node_shop.svg"),
	PATH_TYPE.TRAINER: preload("res://assets/ui/map/node_trainer.svg"),
	PATH_TYPE.JAILER: preload("res://assets/ui/map/node_jailer.svg"),
	PATH_TYPE.EVENT: preload("res://assets/ui/map/node_event.svg"),
	PATH_TYPE.TREASURE: preload("res://assets/ui/map/node_treasure.svg"),
	PATH_TYPE.GEM: preload("res://assets/ui/map/node_gem.svg"),
}

# Übersetzungs-Key des Feldnamens (MAP_NODE_COMBAT ...), die Beschreibung hängt "_DESC" an
func type_label(type: PATH_TYPE) -> String:
	return "MAP_NODE_" + PATH_TYPE.keys()[type]

var max_rows = 8
var max_cols = 3
#var path = 

var map_settings = {
	0: {"paths":6, "special_nodes": 1, "bosses": [], "lines": 1, "tresures": [4], "shops": [], "trainers": [], "jailer": [], "gems": [3]},
	1: {"paths":8, "special_nodes": 2, "bosses": [3], "lines": 2, "tresures": [1], "shops": [], "trainers": [5], "jailer": [], "gems": [6]},
	2: {"paths":11, "special_nodes": 3, "bosses": [5], "lines": 2, "tresures": [2], "shops": [6], "trainers": [], "jailer": [0], "gems": [8]},
	3: {"paths":14, "special_nodes": 4, "bosses": [7], "lines": 3, "tresures": [7], "shops": [5], "trainers": [8], "jailer": [2], "gems": [10]},
	4: {"paths":17, "special_nodes": 6, "bosses": [6,12], "lines": 3, "tresures": [2,8], "shops": [9], "trainers": [], "jailer": [], "gems": [4,14]},
}

enum EVENT_TYPE {
	CAMP = 0,
	WHEEL,
	VOID,
}

# Was ein EVENT-Feld auslöst, Wahrscheinlichkeit in Prozent (alle zusammen sollten 100 ergeben)
var event_chances = {
	EVENT_TYPE.CAMP: 40,
	EVENT_TYPE.WHEEL: 40,
	EVENT_TYPE.VOID: 20,
}

# Würfelt anhand von event_chances, welches Ereignis ein EVENT-Feld auslöst.
# Der Void kommt nur, wenn sich mindestens ein Relikt tauschen lässt.
func roll_event() -> EVENT_TYPE:
	var events = event_chances.keys().filter(func(event): return event != EVENT_TYPE.VOID or Relics.can_swap())
	var weights = events.map(func(event): return event_chances[event])
	return events[pick_weighted_index(range(events.size()), weights)]

var all_nodes = []
var starting_nodes = []

# Felder, die man nie betreten muss (generate_optional_tiles), und was stattdessen entsteht, wenn es keine Alternative gibt
const OPTIONAL_TYPES := [PATH_TYPE.TREASURE, PATH_TYPE.GEM]
const SPECIAL_FALLBACKS := [PATH_TYPE.CAMP, PATH_TYPE.SHOP, PATH_TYPE.TRAINER, PATH_TYPE.JAILER, PATH_TYPE.EVENT]

const MAX_BIOME_TIER = 4

# Pfad und Pools aus dem Spielstand, neu gewürfelt wird nur ohne gespeicherte (erster Start oder nach einem Run-Ende).
func load_biome_path() -> Array[int]:
	var saved_path: Array = SaveManager.save_data["biome_path"]
	if saved_path.is_empty():
		var biomes := generate_biome_path()
		SaveManager.set_biome_path(biomes, State.biome_pools)
		return biomes
	# JSON liefert Zahlen als float und untypisierte Arrays
	State.biome_path.assign(saved_path.map(func(mask): return int(mask)))
	State.biome_pools = []
	for saved_pool in SaveManager.save_data["biome_pools"]:
		var pool: Array[String] = []
		pool.assign(saved_pool)
		State.biome_pools.append(pool)
	return State.biome_path

# Würfelt pro Run einen Biom-Pfad (Element-Masken aus ColorMap), eine Tiefe pro map_settings-Eintrag.
# Tiefe 1 ist immer ein Einzelelement, die letzte Tiefe immer Chaos (alle 4 Elemente).
func generate_biome_path() -> Array[int]:
	var depth = map_settings.size()
	var biomes: Array[int] = []
	var prev = 0
	for i in depth:
		var tier = MAX_BIOME_TIER
		if i < depth - 1:
			tier = min(1 + roundi(float(i) * (MAX_BIOME_TIER - 1) / max(depth - 1, 1)), MAX_BIOME_TIER - 1)
		var candidates = get_biomes_of_tier(tier).filter(func(mask): return not biomes.has(mask))
		if candidates.is_empty():
			candidates = get_biomes_of_tier(tier)
		# bevorzugt Biome, die möglichst viele Elemente des vorherigen Bioms teilen
		var best_shared = candidates.map(func(mask): return count_elements(mask & prev)).max()
		candidates = candidates.filter(func(mask): return count_elements(mask & prev) == best_shared)
		prev = candidates.pick_random()
		biomes.append(prev)
	State.biome_path = biomes
	generate_biome_pools(biomes)
	return biomes

# Arten, die pro Biom wild auftauchen können
const BIOME_POOL_SIZE = 4
# Würfelt für jede Tiefe einen Pool an Monster-Arten (State.biome_pools).
# Die Plätze werden reihum auf die Elemente des Bioms verteilt (Dampf: 2x Wasser, 2x Feuer), damit die Basis-Arten
# des Bioms auftauchen. Gibt es für ein Element keine Art mehr, wird mit beliebigen Arten aufgefüllt.
# Seltene Arten sind am Anfang unwahrscheinlicher (episch in Tiefe 1: 1/7), in der letzten Tiefe zählt nur noch das Element.
func generate_biome_pools(biomes: Array[int]) -> void:
	State.biome_pools = []
	for i in biomes.size():
		var t = float(i) / max(biomes.size() - 1, 1)
		var candidates = Monmap.mons.filter(func(meta): return not meta.has("bounty_target"))
		var weights = candidates.map(func(meta): return pool_weight(meta.rarity, t))
		var elements = Enums.MON_TYPES.values().filter(func(element): return biomes[i] & element)
		elements.shuffle()
		var pool: Array[String] = []
		while pool.size() < BIOME_POOL_SIZE and not candidates.is_empty():
			var element = elements[pool.size() % elements.size()] if not elements.is_empty() else 0
			var indices = range(candidates.size()).filter(func(index): return candidates[index].initial_type & element)
			if indices.is_empty():
				indices = range(candidates.size())
			var index = pick_weighted_index(indices, weights)
			pool.append(candidates[index].name)
			candidates.remove_at(index)
			weights.remove_at(index)
		State.biome_pools.append(pool)

## Gewicht einer Art im Biom-Pool bei Fortschritt t (0 = erstes, 1 = letztes Biom), gewöhnlich = 1
func pool_weight(rarity: int, t: float) -> float:
	return 1.0 / (1.0 + 2.0 * rarity * (1.0 - t))

## Ab dieser Gewichtung (im Vergleich zu gewöhnlichen Arten) gilt eine Art als häufig (Sammlung)
const COMMON_POOL_SHARE := 1.0 / 3.0

## Erstes Biom (0-basiert), in dem Arten dieser Seltenheit häufig im Pool landen (Sammlung)
func usual_depth(rarity: int) -> int:
	var depths := ENCOUNTERS.size()
	for i in depths:
		if pool_weight(rarity, float(i) / max(depths - 1, 1)) >= COMMON_POOL_SHARE - 0.0001:
			return i
	return depths - 1

# Zieht einen der Indizes, gewichtet nach weights[index].
func pick_weighted_index(indices: Array, weights: Array) -> int:
	var roll = randf() * indices.reduce(func(sum, index): return sum + weights[index], 0.0)
	for index in indices:
		roll -= weights[index]
		if roll < 0.0:
			return index
	return indices.back()

func get_biomes_of_tier(tier: int) -> Array:
	var all_elements = Enums.MON_TYPES.values().reduce(func(acc, e): return acc | e, 0)
	var result = []
	for mask in range(1, all_elements + 1):
		if count_elements(mask) == tier:
			result.append(mask)
	return result

func count_elements(mask: int) -> int:
	var count = 0
	while mask:
		count += mask & 1
		mask >>= 1
	return count

## Feste Begegnungstabelle pro Biom-Tiefe (map_level), unabhängig vom eigenen Team.
## Werte werden über die Kämpfe im Biom von Anfang bis Ende interpoliert:
## - fights: erwartete normale Kämpfe im Biom (danach bleibt es beim Endwert)
## - level: [Stufe beim ersten Kampf, Stufe beim letzten Kampf]
## - offset: zufällige Abweichung pro Monster [min, max]
## - counts: Gewichte für 1/2/3 Gegner [am Anfang, am Ende]
## - moves: Gewichte für 1/2/3 Aktionen pro Zug, je Gegner gewürfelt [am Anfang, am Ende].
##   Eigene Monster kommen nur über den Kerkermeister auf mehr Aktionen, teure Skills (Kosten 2-3)
##   und die späten Biome verlangen daher gefangene, stärkere Monster und Verbesserungen.
## Ein Team, das jeden Kampf ausfechtet (2 K.O.s = +1 Stufe), liegt etwa gleichauf;
## wer lieber alles fängt, levelt nicht und fällt zurück.
const ENCOUNTERS := [
	# Biom 1: Einstieg, fast nur Einzelkämpfe auf gleicher oder niedrigerer Stufe (nie unter State.INITIAL_LEVEL)
	{"fights": 4, "level": [4, 6], "offset": [-1, 0], "counts": [[100, 0, 0], [70, 30, 0]],
		"moves": [[100, 0, 0], [90, 10, 0]]},
	# Biom 2: Doppelkämpfe werden normal
	{"fights": 4, "level": [7, 11], "offset": [-1, 1], "counts": [[70, 30, 0], [40, 50, 10]],
		"moves": [[85, 15, 0], [65, 30, 5]]},
	# Biom 3: erste 3er-Gruppen
	{"fights": 5, "level": [12, 17], "offset": [-1, 1], "counts": [[40, 50, 10], [15, 55, 30]],
		"moves": [[60, 35, 5], [40, 45, 15]]},
	# Biom 4: gleiche oder höhere Stufe
	{"fights": 6, "level": [18, 25], "offset": [0, 1], "counts": [[15, 55, 30], [5, 40, 55]],
		"moves": [[40, 45, 15], [20, 50, 30]]},
	# Biom 5: 3 gegen 2 ist die Regel
	{"fights": 7, "level": [26, 35], "offset": [0, 2], "counts": [[5, 35, 60], [0, 20, 80]],
		"moves": [[20, 50, 30], [5, 45, 50]]},
]

## Bosse pro Biom: Anzahl, Stufen über der Endstufe des Bioms und Mindest-Aktionen pro Zug
## (gewürfelt wird wie am Ende des Bioms, der Endboss hat immer 3)
const BOSS_ENCOUNTERS := [
	{"count": 1, "level_bonus": 2, "min_moves": 1},
	{"count": 2, "level_bonus": 1, "min_moves": 2},
	{"count": 2, "level_bonus": 2, "min_moves": 2},
	{"count": 3, "level_bonus": 1, "min_moves": 2},
	{"count": 3, "level_bonus": 2, "min_moves": 3},
]

# Gegner des Biom-Bosses, stehen wie die der Felder seit dem Betreten des Bioms fest
var boss_enemies: Array[Monster] = []
# Gegner des gerade betretenen Felds, der Kampf holt sie sich beim Start ab (battle.gd _generate_battle)
var pending_enemies: Array[Monster] = []

func encounter_depth() -> int:
	return clampi(State.map_level, 0, ENCOUNTERS.size() - 1)

# Fortschritt im Biom 0..1 nach so vielen normalen Kämpfen
func fight_progress(fight_index: int) -> float:
	return clampf(float(fight_index) / max(ENCOUNTERS[encounter_depth()].fights - 1, 1), 0.0, 1.0)

## Zieht 1-3 (Gegneranzahl oder Aktionen) mit zwischen Biom-Anfang und -Ende interpolierten Gewichten.
func roll_weighted(counts: Array, t: float) -> int:
	var weights = []
	for i in 3:
		weights.append(lerpf(counts[0][i], counts[1][i], t))
	var roll = randf() * weights.reduce(func(a, b): return a + b, 0.0)
	for i in 3:
		roll -= weights[i]
		if roll < 0.0:
			return i + 1
	return 1

# Würfelt die Gegner aller Kampf- und Boss-Felder und des Biom-Bosses
func generate_encounters(grid: Array) -> void:
	boss_enemies = roll_boss_enemies()
	for column in grid:
		for node in column:
			if node == null:
				continue
			if node._type == PATH_TYPE.COMBAT:
				node._enemies = roll_fight_enemies(_fights_before(grid, node))
			elif node._type == PATH_TYPE.BOSS:
				node._enemies = roll_boss_enemies()

# Wie viele normale Kämpfe auf dem Weg zu diesem Feld höchstens liegen (Zeilen des Pfads, in denen ein Kampf-Feld liegt).
# Die Anzahl der Gegner steigt damit wie bisher, solange man Kämpfe nicht ausweicht.
func _fights_before(grid: Array, node: path) -> int:
	var fights := 0
	for row in int(node._pos.y):
		if _line_nodes(grid, int(node._pos.z), row).any(func(other: path): return other._type == PATH_TYPE.COMBAT):
			fights += 1
	return fights

# forced_count > 0 legt die Anzahl fest (Debug-Menü)
func roll_fight_enemies(fight_index: int, forced_count := 0) -> Array[Monster]:
	var count := forced_count if forced_count > 0 else roll_weighted(ENCOUNTERS[encounter_depth()].counts, fight_progress(fight_index))
	var enemies := Helper.generate_mons({"count": count})
	# kam kein Kopfgeld-Monster von selbst, wird in normalen Kämpfen selten eins eingestreut
	if not enemies.any(func(mon): return mon._bounty != ""):
		var bounty = _roll_bounty()
		if not bounty.is_empty():
			enemies[0] = Helper.generate_mons({"count": 1, "bounty": bounty})[0]
	return enemies

## Bosse sind immer seltene oder legendäre Arten und tragen Trophäen. Die Boss-Relikte würfelt erst der Kampf (BossRelics).
func roll_boss_enemies(forced_count := 0) -> Array[Monster]:
	var depth := encounter_depth()
	var count: int = forced_count if forced_count > 0 else BOSS_ENCOUNTERS[depth].count
	var species := []
	for i in count:
		species.append(BossRelics.roll_species(depth))
	var bosses := Helper.generate_mons({"count": count, "species": species})
	for boss in bosses:
		BossRelics.add_trophies(boss, BossRelics.default_trophies(depth))
	return bosses

## Nur solange ein Team-Monster mit dem Kopfgeld noch etwas freischalten kann (sonst kommen sie nur noch von selbst).
func _roll_bounty() -> Dictionary:
	var open = Skills.get_open_bounties(State.mons, encounter_depth())
	if open.is_empty() or randf() > Skills.BOUNTY_CHANCE:
		return {}
	return open.pick_random()

func generate_starting_points():
	all_nodes = []
	starting_nodes = []
	var map_setting = map_settings[State.map_level]
	var lines = map_setting["lines"]
	var paths = map_setting["paths"]
	var y_grid = []
	for i in paths:
		y_grid.append(null)
	var grid = [y_grid.duplicate(),y_grid.duplicate(),y_grid.duplicate(),y_grid.duplicate(),y_grid.duplicate(),y_grid.duplicate(),y_grid.duplicate(),y_grid.duplicate()]
	var pick_starting_points = [0,1,2,3,4,5,6,7]
	for i in lines:
		var rand_pick = pick_starting_points.pick_random()
		var index_to_remove = pick_starting_points.find(rand_pick)
		var nn = path.new(Vector3(rand_pick, 0, i))
		grid[rand_pick][0] = nn
		all_nodes.append(nn)
		pick_starting_points.remove_at(index_to_remove)
		starting_nodes.append(rand_pick)
	generate_grid(grid)

func generate_grid(grid: Array):
	var map_setting = map_settings[State.map_level]
	var paths = map_setting["paths"]
	#for sp in starting_points:
	for x_path in grid.size():
		if grid[x_path][0] != null:
			for y_path in paths:
				var nn = path.new(Vector3(x_path,y_path,x_path))
				grid[x_path][y_path] = nn
				all_nodes.append(nn)
				
	generate_additional_nodes_per_path(grid)
	generate_last_fire_camps(grid)
	generate_hard_node_tiles(grid, "bosses", PATH_TYPE.BOSS)
	generate_hard_node_tiles(grid, "shops", PATH_TYPE.SHOP)
	generate_hard_node_tiles(grid, "trainers", PATH_TYPE.TRAINER)
	generate_optional_tiles(grid, "tresures", PATH_TYPE.TREASURE)
	generate_optional_tiles(grid, "gems", PATH_TYPE.GEM)
	generate_specials(grid)
	generate_encounters(grid)
	print_new_map(grid)
	State.current_map = grid

func generate_additional_nodes_per_path(grid: Array):
	var y_start_row = 0
	
	for i in starting_nodes:
		print("start_row:::", i)
		var y_row_size = grid[i].size()
		for y_row in y_row_size:
			if y_start_row == 0:
				y_start_row+= 1
				continue
			var r = randi_range(-1, 1)
			print("r:::", i + r)
			if i + r == -1:
				continue
			if i + r == 8:
				continue
			# check if there is already another path in it.
			if starting_nodes.has(i + r):
				continue
			var np = path.new(Vector3(i + r,y_row,i))
			grid[i + r][y_row] = np
			all_nodes.append(np)


func generate_specials(grid: Array):
	var map_setting = map_settings[State.map_level]
	var special_nodes = map_setting["special_nodes"]
	for i in starting_nodes:
		for j in special_nodes:
			var all_nodes_that_can_be_transformed = all_nodes.filter(func(_path: path): return _path._pos.z == i and _path._type == PATH_TYPE.COMBAT)
			if all_nodes_that_can_be_transformed.size() >= 1:
				var what_special_node = randi_range(1, PATH_TYPE.GEM)
				var np = all_nodes_that_can_be_transformed.pick_random()
				if OPTIONAL_TYPES.has(what_special_node) and not _has_alternative(grid, np):
					what_special_node = SPECIAL_FALLBACKS.pick_random()
				np._type = what_special_node

func generate_hard_node_tiles(grid: Array, key, type):
	var map_setting = map_settings[State.map_level]
	var hard_node_positions = map_setting[key]
	for hard_node_position in hard_node_positions:
		var filtered_nodes = all_nodes.filter(func(_path:path): return _path._pos.y == hard_node_position)
		for hard_to_set_node: path in filtered_nodes:
			hard_to_set_node._type = type

# Schatz und Edelstein-Feld sind nie Pflicht: pro Pfad wird nur eins von mehreren Feldern einer Zeile umgewandelt,
# in der Zeile, die der Wunschposition am nächsten liegt. Ein Pfad ganz ohne Abzweigung bekommt keins.
func generate_optional_tiles(grid: Array, key: String, type: PATH_TYPE) -> void:
	for wanted_row in map_settings[State.map_level][key]:
		for line in starting_nodes:
			var choices := _closest_branch(grid, line, wanted_row)
			if not choices.is_empty():
				choices.pick_random()._type = type

# Kampf-Felder der Zeile mit mindestens zwei davon, die wanted_row am nächsten liegt. Zeile 0 bleibt der Einstieg.
func _closest_branch(grid: Array, line: int, wanted_row: int) -> Array:
	var best: Array = []
	var best_distance := -1
	for row in range(1, grid[line].size()):
		var combat := _line_nodes(grid, line, row).filter(func(node: path): return node._type == PATH_TYPE.COMBAT)
		var distance := absi(row - wanted_row)
		if combat.size() >= 2 and (best_distance < 0 or distance < best_distance):
			best = combat
			best_distance = distance
	return best

# Alle Felder eines Pfads in einer Zeile: das Feld auf dem Pfad selbst und seine Abzweigungen
func _line_nodes(grid: Array, line: int, row: int) -> Array:
	var nodes := []
	for column in grid:
		var node = column[row]
		if node != null and node._pos.z == line:
			nodes.append(node)
	return nodes

# Gibt es in der Zeile ein anderes Feld, das man statt node nehmen kann, ohne auf ein optionales Feld zu müssen?
func _has_alternative(grid: Array, node: path) -> bool:
	return _line_nodes(grid, int(node._pos.z), int(node._pos.y)).any(
		func(other: path): return other != node and not OPTIONAL_TYPES.has(other._type))

func generate_last_fire_camps(grid: Array):
	for x_paths in grid:
		var index = grid.find(x_paths)
		var camp_node = path.new(Vector3(index,x_paths.size(),index))
		camp_node._type = PATH_TYPE.HUB
		if starting_nodes.has(index):
			x_paths.append(camp_node)
			all_nodes.append(camp_node)
		else:
			x_paths.append(null)

func print_new_map(map) -> void:
	print("> > > > > > > > > > > > > > > > > > >")
	var print_y = []
	for x in map.size():
		var y_results = []
		for y in map[x].size():
			if map[x][y] != null:
				y_results.append(str(map[x][y]._type))
			else:
				y_results.append("-")
		print_y.append(y_results)
	for i in print_y.size():
		print(print_y[i])
	print("> > > > > > > > > > > > > > > > > > >")

func gen_map():
	var map = []
	# every 2 map levels + 1 max_rows
	var comp_max_rows = max_rows + State.map_level
	var comp_max_cols = max_cols + State.map_level
	var min_cols = State.map_level + 1
	
	var latest_cols = randi_range(min_cols, comp_max_cols)
	var max_generated_cols = 0
	for i in comp_max_rows:
		for j in latest_cols:
			var new_path = path.new(Vector3(j,i, 0))
			map.append(new_path)
		latest_cols += randi_range(-1, 1)
		latest_cols = clamp(latest_cols, min_cols, comp_max_cols)
		if max_generated_cols < latest_cols:
			max_generated_cols = latest_cols
			
	gen_paths(map)
	
	State.current_map = map

func gen_paths(map):
	for i in map:
		var can_move_to = map.filter(func(map_node): return map_node._pos.y == map_node._pos.y + 1)
		i._path = can_move_to

func get_highest_path_node(map: Array):
	var node_map = map.map(func(node): return node._position.y)
	return node_map.unique().max()
	
