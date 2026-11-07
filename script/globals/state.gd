extends Node

var current_map: Array = []

# settings
var SETTING_LEVEL = 35
# Startstufe der eigenen Monster und Mindeststufe aller Monster (Monster._init, battle.gd)
var INITIAL_LEVEL = 5
var INITIAL_MONS = ["2", "4", "5", "8"]

var mons: Array[Monster] = []
# Art des Start-Monsters (Ei), sammelt den Meilenstein-Fortschritt
var starter_name := ""
# Das Start-Monster selbst: Meilensteine zählen nur, solange genau dieses Exemplar noch im Team ist
var starter: Monster
var enemy_mons: Array[Monster] = []
var catched_mons: Array[Monster] = []
# Im letzten gewonnenen Kampf gefallene eigene Monster, warten auf Wiederbelebung oder Letzten Willen (judgement.gd)
var fainted_own_mons: Array[Monster] = []
var fainted_enemy_mons: Array[Monster] = []
# IDs der gesammelten Relics (siehe Relics.RELICS)
var relics: Array[String] = []
var overall_progress_level := 0
var map_progress_level := 0
var map_level := 0
# normale Kämpfe im aktuellen Biom, bestimmt Stufe und Aktionen der Gegner (siehe Map.ENCOUNTERS)
var biome_fight_index := 0
# Element-Masken der Biome pro Tiefe, einmal pro Run gewürfelt (siehe Map.generate_biome_path)
var biome_path: Array[int] = []
# Monster-Arten, die pro Tiefe wild auftauchen können, zusammen mit biome_path gewürfelt (siehe Map.generate_biome_pools)
var biome_pools: Array = []


# Stats pro Monster-Art, einmal pro Run gewürfelt: name -> {"best_points": int, "growth": Growth}
var rolled_mon_stats: Dictionary = {}

# Monster-Arten, die in diesem Run schon besiegt wurden
var defeated_mon_names: Array[String] = []
# Monster-Arten, die in diesem Run schon gefangen wurden (deren Stats und genaue HP sind im Kampf sichtbar)
var caught_mon_names: Array[String] = []
# Im Kampf durch Treffer aufgedeckte Einzelwerte pro Art: name -> Array der Stat-Keys (siehe Skills.reveal_stats_by_hit)
var revealed_mon_stats: Dictionary = {}

var is_boss_fight: bool = false
var is_final_boss: bool = false
# Boss-Feld mitten auf der Karte: Kampf in Boss-Stärke, beendet das Biom aber nicht
var is_map_boss: bool = false
# Beute in die Tasche gezogen: beim nächsten Betreten der Karte nacheinander abhandeln (world_map.gd show_pending_rewards)
var pending_relic_reward: bool = false
var pending_skill_reward: bool = false
var pending_gem_rewards: int = 0
# Einzigartige Skills, die in diesem Run schon jemand gelernt hat, sie kommen kein zweites Mal (Skills.reward_offers)
var taught_reward_skills: Array[String] = []

# money
signal ep_changed(ep)
var ep: int = 0:
	set(val):
		if val > ep:
			run_ep_earned += val - ep
		ep = val
		ep_changed.emit(ep)

# shards to perma upgrade mons
signal boss_shards_changed(ep)
var boss_shards: int = 0:
	set(val):
		boss_shards = val
		boss_shards_changed.emit(boss_shards)

# Schlüssel des aktuellen Runs, öffnen Schatzkisten (treasure.gd)
signal keys_changed(keys)
var keys: int = 0:
	set(val):
		keys = val
		keys_changed.emit(keys)

# Rabatt-Gutscheine des aktuellen Runs, das Ablegen auf Kasse oder Trainer verbraucht einen (ShopDialog)
signal coupons_changed(coupons)
var coupons: int = 0:
	set(val):
		coupons = val
		coupons_changed.emit(coupons)


var killed_monsters: int = 0
# im Kampf verdiente Monster Essenz: liegt auf dem Schlachtfeld, bis sie im Level-Up-Screen in die Tasche gezogen wird
var pending_ep: int = 0
# im Kampf gefundene Schlüssel, liegen genauso auf dem Schlachtfeld wie die Essenz
var pending_keys: int = 0
# Zufallsbeute besiegter Monster, liegt genauso auf dem Schlachtfeld
var pending_gems: int = 0
var pending_coupons: int = 0
# nach einem Boss-Sieg: Kiste und Couvert auf dem Schlachtfeld, ohne sie in der Tasche gibt es weder Relic noch Skill
var pending_relic_chest: bool = false
var pending_skill_envelope: bool = false
# nach einem Biom-Boss: Boss Tränen auf dem Schlachtfeld
var pending_boss_shards: int = 0

# Liegt noch etwas auf dem Schlachtfeld? Dann führt der Weg zur Karte erst über den Level-Up-Bildschirm.
func has_pending_loot() -> bool:
	return pending_ep > 0 or pending_keys > 0 or pending_gems > 0 or pending_coupons > 0 or pending_relic_chest or pending_skill_envelope or pending_boss_shards > 0

# Was noch auf dem Schlachtfeld liegt, ist beim Weitergehen weg.
func clear_pending_loot() -> void:
	pending_ep = 0
	pending_keys = 0
	pending_gems = 0
	pending_coupons = 0
	pending_relic_chest = false
	pending_skill_envelope = false
	pending_boss_shards = 0

# Run-Statistik für den Endbildschirm (run_end.gd). killed_monsters wird beim Level-Up verbraucht, daher eigene Zähler.
var run_won := false
var run_kills := 0
var run_catches := 0
var run_ep_earned := 0
# Monster-Arten im Team beim Run-Ende (bei einer Niederlage stehen sie danach nicht mehr in mons)
var run_team: Array[String] = []
# K.O.s eigener Monster in Reihenfolge, der letzte Eintrag hat den Run beendet (siehe record_own_faint)
var run_deaths: Array[Dictionary] = []
# gegnerische Monster pro Tiefe: Art -> letzte Sichtung (Stufe, Element, Werte), siehe record_sighting
var run_sightings: Array = []
# Stufe der Team-Monster beim Run-Ende: Art -> höchste Stufe
var run_team_levels: Dictionary = {}
signal pos_changed(pos)
# Linie 0 / Zeile 0 hat die Position (0,0,0), daher braucht "noch nicht gestartet" einen eigenen Wert
const NO_MAP_POSITION := Vector3(-1, -1, -1)
var current_map_position: Vector3 = NO_MAP_POSITION:
	set(vec3):
		current_map_position = vec3
		pos_changed.emit(vec3)

var map_progress_elements = []

func _ready() -> void:
	boss_shards = SaveManager.save_data["boss_shards"]

func reset() -> void:
	ep = 0
	keys = 0
	coupons = 0
	map_level = 0
	biome_fight_index = 0
	biome_path = []
	map_progress_level = 0
	overall_progress_level = 0
	relics = []
	mons = []
	starter_name = ""
	starter = null
	enemy_mons = []
	catched_mons = []
	current_map = []
	fainted_own_mons = []
	fainted_enemy_mons = []
	killed_monsters = 0
	clear_pending_loot()
	current_map_position = NO_MAP_POSITION
	is_boss_fight = false
	is_final_boss = false
	is_map_boss = false
	pending_relic_reward = false
	pending_skill_reward = false
	pending_gem_rewards = 0
	taught_reward_skills = []
	rolled_mon_stats = {}
	defeated_mon_names = []
	caught_mon_names = []
	revealed_mon_stats = {}
	run_won = false
	run_kills = 0
	run_catches = 0
	run_ep_earned = 0
	run_team = []
	run_deaths = []
	biome_pools = []
	run_sightings = []
	run_team_levels = {}

# Element-Maske des aktuellen Bioms, 0 wenn kein Biom-Pfad gewürfelt wurde.
func current_biome() -> int:
	return biome_path[map_level] if map_level < biome_path.size() else 0

# Würfelt die Stats für alle Monster-Arten neu.
func roll_mon_stats() -> void:
	rolled_mon_stats = {}
	for meta_data in Monmap.mons:
		rolled_mon_stats[meta_data.name] = {
			"best_points": randi_range(meta_data["stats"][0], meta_data["stats"][1]),
			"growth": Growth.new(meta_data["preferred_stats"]),
		}

# Liefert die für diesen Run festen Stats einer Monster-Art (würfelt beim ersten Zugriff).
func get_mon_stats(mon_name: String) -> Dictionary:
	if rolled_mon_stats.is_empty():
		roll_mon_stats()
	return rolled_mon_stats[mon_name]

# Setzt die Stats einer Art auf gespeicherte Werte (Ei aus dem Spielstand, siehe Helper.mon_from_egg).
func restore_mon_stats(mon_name: String, best_points: int, growth: Dictionary) -> void:
	var stats = get_mon_stats(mon_name)
	stats.best_points = best_points
	for attr in Growth.ATTRS:
		stats.growth[attr] = growth[attr]

# Ist das Start-Monster noch im Team? K.O. gegangene (battle.gd _clear_fainted_mons) und abgegebene Monster
# (leaving_screen.gd) stehen nicht mehr in mons.
func is_starter_in_team() -> bool:
	return starter != null and mons.has(starter)

func mark_mon_defeated(mon_name: String) -> void:
	if not defeated_mon_names.has(mon_name):
		defeated_mon_names.append(mon_name)

func is_mon_defeated(mon_name: String) -> bool:
	return defeated_mon_names.has(mon_name)

func mark_mon_caught(mon_name: String) -> void:
	if not caught_mon_names.has(mon_name):
		caught_mon_names.append(mon_name)

func reveal_mon_stat(mon_name: String, stat: String) -> void:
	var stats: Array = revealed_mon_stats.get_or_add(mon_name, [])
	if not stats.has(stat):
		stats.append(stat)

func is_mon_stat_revealed(mon_name: String, stat: String) -> bool:
	return revealed_mon_stats.get(mon_name, []).has(stat)

# Art im Team oder in diesem Run schon gefangen: genaue HP von Gegnern dieser Art sind sichtbar
func is_mon_known(mon_name: String) -> bool:
	return caught_mon_names.has(mon_name) or mons.any(func(m: Monster): return m._name == mon_name)

# Merkt sich den Treffer, der ein eigenes Monster K.O. schlägt (für den Endbildschirm).
# Aufruf vor dem Abziehen der HP, hp_left ist also der Rest vor dem tödlichen Treffer.
func record_own_faint(victim: Monster, killer: Monster, skill: Dictionary, damage: float, multiplier: float) -> void:
	run_deaths.append({
		"victim": victim._name,
		"victim_level": victim._level,
		"killer": killer._name,
		"killer_display": Helper.mon_battle_name(killer),
		"killer_level": killer._level,
		"skill": skill.name,
		"damage": damage,
		"multiplier": multiplier,
		"hp_left": maxf(victim.hp() - victim._lost_hp, 0.0),
		"max_hp": victim.hp(),
	})

# Merkt sich ein gegnerisches Monster für die Monster-Suche, spätere Sichtungen derselben Art überschreiben frühere.
func record_sighting(mon: Monster, depth: int) -> void:
	while run_sightings.size() <= depth:
		run_sightings.append({})
	var previous = run_sightings[depth].get(mon._name, {})
	run_sightings[depth][mon._name] = {
		"level": mon._level,
		"type": mon._type,
		"count": previous.get("count", 0) + 1,
		"stats": {
			"hp": mon.hp(), "atk": mon.attack(), "def": mon.defense(),
			"s_atk": mon.s_attack(), "s_def": mon.s_defense(), "speed": mon.speed(),
		},
		"skills": mon._skills.map(func(skill): return {"name": skill.name, "egg": skill.get("egg_skill", false)}),
	}

# Wurde die Art in diesem Run als Gegner gesehen? depth -1 = in irgendeinem Biom
func is_mon_seen(mon_name: String, depth := -1) -> bool:
	if depth >= 0:
		return depth < run_sightings.size() and run_sightings[depth].has(mon_name)
	return run_sightings.any(func(sightings): return sightings.has(mon_name))

# Beendet den Run und merkt sich das Team, die Szene wechselt der Aufrufer (run_end.tscn).
func end_run(won: bool) -> void:
	run_won = won
	# erst das Run-Ende gibt neue Eier und einen neuen Biom-Pfad frei
	SaveManager.clear_run_start()
	run_team.assign(mons.map(func(mon: Monster): return mon._name))
	run_team_levels = {}
	for mon in mons:
		run_team_levels[mon._name] = maxi(run_team_levels.get(mon._name, 0), mon._level)

func stage_clear(progress: int = 1) -> void:
	#for mon in mons:
	#	mon.upgrade_by_level(progress)
	map_progress_level += progress
	overall_progress_level += progress
