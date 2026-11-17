extends Node

const SAVE_PATH := "user://savegame.json"
# Biom-Boss-Siege, bis in der Ei-Auswahl der Neu-Würfeln-Button erscheint (für Spieler unsichtbar)
const REROLL_CHARGES_NEEDED := 3

## Leerer Spielstand: Vorlage für neue Spielstände und für "Spielstand löschen" (Debug-Menü)
const DEFAULT_DATA := {
	"version": 1,
	"boss_shards": 0,
	"monsters": {},
	"skills": {},
	"catched_monsters": [],
	"seen_monsters": [],
	# freigeschaltete Ei-Attacken: Monster-Name -> [Skill-Namen]
	"egg_skills": {},
	# alter Meilenstein-Fortschritt über mehrere Runs, wird nicht mehr benutzt (Meilensteine gelten jetzt pro Run,
	# siehe Skills.MILESTONES). Freigeschaltete Meilenstein-Ei-Attacken landen wie die anderen in egg_skills
	"milestones": {},
	# zuletzt im Ei-Konfigurator gewählte Ei-Attacken pro Art: Monster-Name -> [Skill-Namen], nächstes Mal vorausgewählt
	"egg_loadouts": {},
	"reroll_charges": 0,
	# wurden die gespeicherten Eier neu gewürfelt? Dann verbraucht der nächste Aufbruch die Ladungen
	"eggs_rerolled": false,
	# Eier der Start-Auswahl (Helper.egg_to_save), bleiben bis zum nächsten Run-Ende gleich
	"starter_eggs": [],
	# Biom-Pfad und Monster-Pools pro Tiefe (Map.load_biome_path), bleiben ebenfalls bis zum nächsten Run-Ende gleich
	"biome_path": [],
	"biome_pools": [],
	# interaktives Tutorial (siehe Tutorial): gesehene Sequenzen, done = ausgeschaltet, abgeschlossen oder übersprungen (neue Spielstände starten mit Tutorial)
	"tutorial_seen": [],
	"tutorial_done": false,
	# beendete Runs insgesamt und davon verlorene (Fehlschläge, stehen in der Ei-Auswahl unter Anleitung und Sammlung)
	"runs": 0,
	"failed_runs": 0,
	# Runs mit mehr als einer Boss Träne bis zum nächsten Kerkermeister im ersten Biom (Map.generate_run_jailer), 0 = noch nicht gewürfelt
	"runs_until_jailer": 0,
}

var save_data: Dictionary = DEFAULT_DATA.duplicate(true)

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
		parsed.merge(DEFAULT_DATA.duplicate(true))
		save_data = parsed
		_drop_removed_mons()

## Aus dem Spiel entfernte Monster-Arten (Schlundwurm, Lavaritter, Leerwurm, Nachthydra, Höllenwächter, Schattenreißer).
## Hier fest eingetragen, weil SaveManager vor Monmap geladen wird.
const REMOVED_MONS := ["32", "34", "35", "44", "58", "65"]

## Alte Spielstände: entfernte Arten fliegen raus, sonst stürzen Ei-Auswahl, Pools und Sammlung
## bei Monmap.mon_metainfos_by_name ab.
func _drop_removed_mons() -> void:
	var keep := func(mon_name): return not REMOVED_MONS.has(str(mon_name))
	save_data["catched_monsters"] = save_data["catched_monsters"].filter(keep)
	save_data["seen_monsters"] = save_data["seen_monsters"].filter(keep)
	for key in ["monsters", "egg_skills", "milestones", "egg_loadouts"]:
		for mon_name in REMOVED_MONS:
			save_data[key].erase(mon_name)
	# Eier und Biom-Pools mit entfernten Arten neu würfeln lassen
	if save_data["starter_eggs"].any(func(egg): return not keep.call(egg.get("name", ""))):
		save_data["starter_eggs"] = []
	save_data["biome_pools"] = save_data["biome_pools"].map(func(pool): return pool.filter(keep))

## Debug-Menü: Freigeschaltetes und der laufende Run sind weg, wie nach einer Neuinstallation.
## Einstellungen (settings.cfg) und Debug-Einstellungen bleiben.
func reset_game():
	save_data = DEFAULT_DATA.duplicate(true)
	save_game()

## Zählt einen Run herunter. true, wenn in diesem Run der Kerkermeister dran ist (danach wird neu gewürfelt).
func jailer_run_due(min_runs: int, max_runs: int) -> bool:
	var left := int(save_data["runs_until_jailer"])
	if left <= 0:
		left = randi_range(min_runs, max_runs)
	left -= 1
	var due := left <= 0
	save_data["runs_until_jailer"] = left
	save_game()
	return due

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

## Sammlung: Art wurde gesehen (Gegner im Kampf oder ausgebrütetes Start-Ei)
func add_seen_mon(monster_name = "1"):
	if save_data["seen_monsters"].has(monster_name):
		return
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

## Zuletzt gewählte Ei-Attacken der Art (leer = noch nie gewählt)
func get_egg_loadout(monster_name: String) -> Array:
	return save_data["egg_loadouts"].get(monster_name, []).duplicate()

func set_egg_loadout(monster_name: String, skill_names: Array) -> void:
	save_data["egg_loadouts"][monster_name] = skill_names.duplicate()
	save_game()

func is_egg_skill_unlocked(monster_name: String, skill_name: String) -> bool:
	return save_data["egg_skills"].get(monster_name, []).has(skill_name)

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

## Zählt einen beendeten Run, verlorene zusätzlich als Fehlschlag
func add_finished_run(won: bool):
	save_data["runs"] = int(save_data["runs"]) + 1
	if not won:
		save_data["failed_runs"] = int(save_data["failed_runs"]) + 1
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
