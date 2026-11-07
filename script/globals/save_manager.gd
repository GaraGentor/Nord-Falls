extends Node

const SAVE_PATH := "user://savegame.json"
# Biom-Boss-Siege, bis in der Ei-Auswahl der Neu-Würfeln-Button erscheint (für Spieler unsichtbar)
const REROLL_CHARGES_NEEDED := 3

var save_data := {
	"version": 1,
	"boss_shards": 0,
	"monsters": {},
	"skills": {},
	"catched_monsters": [],
	"seen_monsters": [],
	# freigeschaltete Ei-Attacken: Monster-Name -> [Skill-Namen]
	"egg_skills": {},
	# Meilenstein-Fortschritt pro Art als Start-Monster: Monster-Name -> {Zähler -> Anzahl} (siehe Skills.MILESTONES)
	# freigeschaltete Meilenstein-Ei-Attacken landen wie die anderen in egg_skills
	"milestones": {},
	"reroll_charges": 0,
	# wurden die gespeicherten Eier neu gewürfelt? Dann verbraucht der nächste Aufbruch die Ladungen
	"eggs_rerolled": false,
	# Eier der Start-Auswahl (Helper.egg_to_save), bleiben bis zum nächsten Run-Ende gleich
	"starter_eggs": [],
	# Biom-Pfad und Monster-Pools pro Tiefe (Map.load_biome_path), bleiben ebenfalls bis zum nächsten Run-Ende gleich
	"biome_path": [],
	"biome_pools": [],
}

# Called when the node enters the scene tree for the first time.
func _ready():
	load_game()

func save_game():
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		save_game()
		return
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	
	var parsed: Dictionary = JSON.parse_string(content)
	if typeof(parsed) == TYPE_DICTIONARY:
		# neue Felder in alten Spielständen ergänzen
		parsed.merge(save_data)
		save_data = parsed

func add_boss_shard(amount := 1):
	save_data["boss_shards"] += amount
	save_game()

func subtract_boss_shard(amount:=1):
	save_data["boss_shards"] -= amount
	save_game()

func add_mon_upgrade(monster_name = "1"):
	if not save_data["monsters"].has(monster_name):
		save_data["monsters"][monster_name] = {
			"upgrade": 1,
		}
	else:
		save_data["monsters"][monster_name] = {
			"upgrade": save_data["monsters"][monster_name]["upgrade"] + 1
		}
	save_game()

func add_seen_mon(monster_name = "1"):
	if not save_data["seen_monsters"].has(monster_name):
		save_data["seen_monsters"].append(monster_name)
	save_game()

func unlock_egg_skill(monster_name: String, skill_name: String):
	if not save_data["egg_skills"].has(monster_name):
		save_data["egg_skills"][monster_name] = []
	if not save_data["egg_skills"][monster_name].has(skill_name):
		save_data["egg_skills"][monster_name].append(skill_name)
	save_game()

func lock_egg_skill(monster_name: String, skill_name: String):
	save_data["egg_skills"].get(monster_name, []).erase(skill_name)
	save_game()

func is_egg_skill_unlocked(monster_name: String, skill_name: String) -> bool:
	return save_data["egg_skills"].get(monster_name, []).has(skill_name)

func add_milestone_progress(monster_name: String, stat: String, amount := 1):
	if not save_data["milestones"].has(monster_name):
		save_data["milestones"][monster_name] = {}
	save_data["milestones"][monster_name][stat] = get_milestone_progress(monster_name, stat) + amount
	save_game()

func get_milestone_progress(monster_name: String, stat: String) -> int:
	return int(save_data["milestones"].get(monster_name, {}).get(stat, 0))

func add_reroll_charge():
	save_data["reroll_charges"] = mini(int(save_data["reroll_charges"]) + 1, REROLL_CHARGES_NEEDED)
	save_game()

func has_full_reroll_charges() -> bool:
	return int(save_data["reroll_charges"]) >= REROLL_CHARGES_NEEDED

func set_reroll_charges(amount: int):
	save_data["reroll_charges"] = amount
	save_game()

func spend_reroll_charges():
	save_data["reroll_charges"] = 0
	save_data["eggs_rerolled"] = false
	save_game()

func set_starter_eggs(eggs: Array):
	save_data["starter_eggs"] = eggs
	save_game()

func set_biome_path(path: Array, pools: Array):
	save_data["biome_path"] = path
	save_data["biome_pools"] = pools
	save_game()

# Nach Sieg oder Niederlage: der nächste Run würfelt Eier und Biom-Pfad neu
func clear_run_start():
	save_data["starter_eggs"] = []
	save_data["biome_path"] = []
	save_data["biome_pools"] = []
	save_game()

func add_catched_monster_mon(monster_name = "1"):
	if not save_data["catched_monsters"].has(monster_name):
		save_data["catched_monsters"].append(monster_name)
	save_game()
