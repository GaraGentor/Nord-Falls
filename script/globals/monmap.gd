extends Node

func mon_metainfos_by_name(name: String) -> Dictionary:
	return mons.filter(func(mon): return mon.name == name)[0]

## Vorhandene Bildgrößen unter assets/mons/<name>/ (<name>_front.png ist 1024, kleinere heißen <name>_frontx512.png usw.)
const FRONT_SIZES := [64, 128, 256, 512, 1024]
const BACK_SIZES := [256, 512, 1024]

## Typische Platzhaltergrößen, damit die Aufrufer nicht raten müssen
const TINY := 64      # Initiative-Rad, Ziele in den Absichten über den Monstern
const ICON := 128     # kleine Portraits
const SMALL := 256    # Kampffeld, Karten, Ziele, Widgets
const MEDIUM := 512   # große Panels
const LARGE := 1024

## Bild einer Monster-Art in der kleinsten Auflösung, die `display_size` Pixel noch scharf füllt.
## Zu große Bilder werden beim Verkleinern körnig, zu kleine unscharf.
## back = Rückansicht (eigene Monster im Kampf)
func texture(name: String, display_size: float, back := false) -> Texture2D:
	var sizes = BACK_SIZES if back else FRONT_SIZES
	var size: int = sizes.back()
	for s in sizes:
		if s >= display_size:
			size = s
			break
	var view = "back" if back else "front"
	var suffix = "" if size == LARGE else "x%d" % size
	return load("res://assets/mons/%s/%s_%s%s.png" % [name, name, view, suffix])

## "Lebende Pixel" mit animiertem Dithering für Icons, Eier und Requisiten (siehe living_pixels.gdshader)
const LIVING_MATERIAL := preload("res://script/ui/shader/living_pixels_material.tres")
## Für alle Monsterbilder: "Lebende Pixel" plus Atmen und Wiegen (siehe monster_living.gdshader)
const MONSTER_MATERIAL := preload("res://script/ui/shader/monster_living_material.tres")
## Umriss für alles Ausgewählte und Hervorgehobene: gedämpftes Gold
const SELECTED_OUTLINE_COLOR := Color(0.858824, 0.717647, 0.45098)
## wie MONSTER_MATERIAL, zusätzlich mit goldenem Umriss (ausgewähltes Monster)
var monster_selected_material: ShaderMaterial
## Umriss des ausgewählten Monsters im Kampf: kräftiger goldener Rand, damit die Auswahl klar zu sehen ist
const BATTLE_OUTLINE_COLOR := Color(0.858824, 0.717647, 0.45098, 0.9)
const BATTLE_OUTLINE_THICKNESS := 4.0
## wie MONSTER_MATERIAL, zusätzlich mit goldenem Umriss (Monster, dessen Werte im Kampf angezeigt werden)
var monster_battle_selected_material: ShaderMaterial

func _init() -> void:
	monster_selected_material = MONSTER_MATERIAL.duplicate()
	monster_selected_material.set_shader_parameter("outline_color", SELECTED_OUTLINE_COLOR)
	monster_battle_selected_material = MONSTER_MATERIAL.duplicate()
	monster_battle_selected_material.set_shader_parameter("outline_color", BATTLE_OUTLINE_COLOR)
	monster_battle_selected_material.set_shader_parameter("outline_thickness", BATTLE_OUTLINE_THICKNESS)

## Monsterbild samt Monster-Material auf ein TextureRect setzen
func show_on(rect: TextureRect, name: String, display_size: float, back := false) -> void:
	rect.texture = texture(name, display_size, back)
	rect.material = MONSTER_MATERIAL

## Farbe und Übersetzungs-Key pro Seltenheit (Ei-Färbung, Seltenheits-Chip im Kampf)
const RARITY_COLORS := {
	Enums.MON_RARITY.COMMON: Color(0.75, 0.75, 0.75),
	Enums.MON_RARITY.UNCOMMON: Color(0.35, 0.85, 0.35),
	Enums.MON_RARITY.RARE: Color(0.3, 0.6, 1.0),
	Enums.MON_RARITY.EPIC: Color(0.75, 0.35, 1.0),
	Enums.MON_RARITY.LEGENDARY: Color(1.0, 0.65, 0.15),
	# Dunkelrot bis Schwarz: als Text noch lesbar, das Ei wird fast schwarz (egg_material)
	Enums.MON_RARITY.MYTHIC: Color(0.6, 0.05, 0.07),
}
## Ei-Färbung mythischer Arten: Blutrot, das ins Schwarze geht
const MYTHIC_EGG_TINT := Color(0.25, 0.0, 0.02)
const RARITY_LABELS := {
	Enums.MON_RARITY.COMMON: "RARITY_COMMON",
	Enums.MON_RARITY.UNCOMMON: "RARITY_UNCOMMON",
	Enums.MON_RARITY.RARE: "RARITY_RARE",
	Enums.MON_RARITY.EPIC: "RARITY_EPIC",
	Enums.MON_RARITY.LEGENDARY: "RARITY_LEGENDARY",
	Enums.MON_RARITY.MYTHIC: "RARITY_MYTHIC",
}

func rarity_of(name: String) -> int:
	return mon_metainfos_by_name(name).get("rarity", Enums.MON_RARITY.COMMON)

## Lebende-Pixel-Material für Eier, je seltener die Art, desto kräftiger eingefärbt (gewöhnlich bleibt naturbraun)
var _egg_materials := {}

func egg_material(rarity: int, selected := false) -> ShaderMaterial:
	var key = rarity * 2 + int(selected)
	if not _egg_materials.has(key):
		var mat: ShaderMaterial = LIVING_MATERIAL.duplicate()
		var tint: Color = MYTHIC_EGG_TINT if rarity == Enums.MON_RARITY.MYTHIC else RARITY_COLORS[rarity]
		tint.a = 0.0 if rarity == Enums.MON_RARITY.COMMON else minf(0.45 + 0.1 * rarity, 0.95)
		mat.set_shader_parameter("tint_color", tint)
		if selected:
			mat.set_shader_parameter("outline_color", SELECTED_OUTLINE_COLOR)
		_egg_materials[key] = mat
	return _egg_materials[key]

var mons = [
	# Böenmähne: gefiederter Sturmschamane mit Weltkugel-Keule
	{
		"name": "1",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		# Bevorzugte Werteverteilung der Art in Prozent (Summe 100), schwankt pro Run um bis zu ±15 % (siehe growth.gd)
		"preferred_stats": {"hp": 15, "atk": 15, "def": 12, "s_atk": 25, "s_def": 15, "speed": 18},
		"max_upgrades": 2,
		# Ei-Attacken, die immer von Beginn an zur Wahl stehen
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		# Ei-Attacken, die wilde Monster dieser Art tragen können und durch Opfern freigeschaltet werden
		"unlockable_egg_skills": ["SKILL_PEBBLE_THROW", "SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE"],
		# Ei-Attacken, die nur über Meilensteine mit dieser Art als Start-Monster freigeschaltet werden (siehe Skills.MILESTONES)
		"milestone_egg_skills": {"boss_1": "SKILL_TAILWIND_STRIKE", "boss_5": "SKILL_CYCLONE", "game_win": "SKILL_NORTHERN_GALE"},
		# Bounty-Hunter-Ei-Attacken: ein Monster dieser Art muss das Kopfgeld-Monster selbst besiegen (siehe Skills.BOUNTIES)
		"bounty_egg_skills": {"alpha_1": "SKILL_RAPTOR_DIVE", "alpha_2": "SKILL_HUNTERS_GALE", "northern_warden": "SKILL_TROPHY_TEMPEST"},
	},
	# Leuchtkrabbe: Krabbe mit Leuchtturm auf dem Panzer
	{
		"name": "2",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 14, "def": 25, "s_atk": 14, "s_def": 19, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_EMBER", "SKILL_TIDAL_SLAM", "SKILL_MAGMA_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_UNDERTOW", "boss_5": "SKILL_MAELSTROM", "game_win": "SKILL_NORTHERN_TIDE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SHARK_BITE", "alpha_2": "SKILL_HUNTERS_TIDE", "northern_warden": "SKILL_TROPHY_TSUNAMI"},
	},
	# Schattflaum: Federgeist aus violettem Rauch
	{
		"name": "3",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 8, "def": 12, "s_atk": 27, "s_def": 21, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_ICE_SPEAR", "SKILL_THUNDER_STRIKE"],
		"milestone_egg_skills": {"boss_1": "SKILL_PLUME_FLURRY", "boss_5": "SKILL_PHANTOM_DRAFT", "game_win": "SKILL_SHADOW_SQUALL"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SILENT_SWOOP", "alpha_2": "SKILL_HUNTERS_HAUNT", "northern_warden": "SKILL_TROPHY_PHANTASM"},
	},
	# Hackschupp: Echse mit Beil und Schuppenpanzer
	{
		"name": "4",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 16, "atk": 27, "def": 22, "s_atk": 8, "s_def": 12, "speed": 15},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_SCORCHING_CHOP", "boss_5": "SKILL_BLAZING_CLEAVE", "game_win": "SKILL_INFERNO_EXECUTION"},
		"bounty_egg_skills": {"alpha_1": "SKILL_HOT_HATCHET", "alpha_2": "SKILL_HUNTERS_BLAZE", "northern_warden": "SKILL_TROPHY_PYRE"},
	},
	# Glotzlibelle: Libelle mit Stielaugen
	{
		"name": "5",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 13, "atk": 18, "def": 11, "s_atk": 20, "s_def": 14, "speed": 24},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_PEBBLE_THROW", "SKILL_WIND_BLADE", "SKILL_ROCK_CRUSH"],
		"milestone_egg_skills": {"boss_1": "SKILL_DUST_WHIRR", "boss_5": "SKILL_STARING_GAZE", "game_win": "SKILL_MUDWING_DIVE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_STINGER_DART", "alpha_2": "SKILL_HUNTERS_GAZE", "northern_warden": "SKILL_TROPHY_SWARM"},
	},
	# Borkenhieb: Baumkrieger mit zwei Runenäxten
	{
		"name": "6",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 19, "atk": 28, "def": 20, "s_atk": 7, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_TIDAL_SLAM", "SKILL_MAGMA_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_ROOT_LASH", "boss_5": "SKILL_TWIN_AXE_SWEEP", "game_win": "SKILL_ANCIENT_TIMBER"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SAP_CLEAVER", "alpha_2": "SKILL_HUNTERS_GROVE", "northern_warden": "SKILL_TROPHY_TIMBERFALL"},
	},
	# Hainschwestern: vier Baumfeen unter einer Krone
	{
		"name": "7",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 17, "atk": 8, "def": 14, "s_atk": 25, "s_def": 24, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_SPLASH", "SKILL_ROCK_CRUSH", "SKILL_CHAOS_NOVA"],
		"milestone_egg_skills": {"boss_1": "SKILL_POLLEN_DRIFT", "boss_5": "SKILL_BLOSSOM_CHORUS", "game_win": "SKILL_FOURFOLD_BLOOM"},
		"bounty_egg_skills": {"alpha_1": "SKILL_THORN_EMBRACE", "alpha_2": "SKILL_HUNTERS_BLOOM", "northern_warden": "SKILL_TROPHY_WILDWOOD"},
	},
	# Glutmolch: Lavamolch mit brennendem Schwanz
	{
		"name": "8",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 17, "atk": 16, "def": 15, "s_atk": 24, "s_def": 14, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_THUNDER_STRIKE", "SKILL_MAGMA_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_SPARK_SPIT", "boss_5": "SKILL_LAVA_TAIL", "game_win": "SKILL_EMBER_SPIRAL"},
		"bounty_egg_skills": {"alpha_1": "SKILL_CINDER_BITE", "alpha_2": "SKILL_HUNTERS_FLAME", "northern_warden": "SKILL_TROPHY_ERUPTION"},
	},
	# Quallolotl: Gallert-Axolotl mit Wasserbauch und Quallententakeln
	{
		"name": "9",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 24, "atk": 10, "def": 14, "s_atk": 20, "s_def": 22, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_WIND_BLADE", "SKILL_ICE_SPEAR"],
		"milestone_egg_skills": {"boss_1": "SKILL_BUBBLE_SPRAY", "boss_5": "SKILL_TENTACLE_LASH", "game_win": "SKILL_TIDE_HEART"},
		"bounty_egg_skills": {"alpha_1": "SKILL_JELLY_STING", "alpha_2": "SKILL_HUNTERS_CURRENT", "northern_warden": "SKILL_TROPHY_TORRENT"},
	},
	# Glutkoloss: Lavagolem mit glühendem Kern und Felsfäusten
	{
		"name": "10",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 24, "atk": 26, "def": 24, "s_atk": 8, "s_def": 10, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_FIST", "boss_5": "SKILL_SMOLDER_STOMP", "game_win": "SKILL_CORE_BLAST"},
		"bounty_egg_skills": {"alpha_1": "SKILL_BOULDER_PUNCH", "alpha_2": "SKILL_HUNTERS_EMBER", "northern_warden": "SKILL_TROPHY_CALDERA"},
	},
	# Wolkenkauz: Wolkeneule auf einem kleinen Wirbelsturm
	{
		"name": "11",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 15, "atk": 10, "def": 12, "s_atk": 24, "s_def": 19, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_SPLASH", "SKILL_WIND_BLADE", "SKILL_ICE_SPEAR"],
		"milestone_egg_skills": {"boss_1": "SKILL_FEATHER_PUFF", "boss_5": "SKILL_CLOUD_BURST", "game_win": "SKILL_SKY_TWISTER"},
		"bounty_egg_skills": {"alpha_1": "SKILL_DOWNDRAFT", "alpha_2": "SKILL_HUNTERS_BREEZE", "northern_warden": "SKILL_TROPHY_TYPHOON"},
	},
	# Sturmgreif: Greif mit Blitzschwingen und Wirbelsturmschweifen
	{
		"name": "12",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [230, 250],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 12, "s_atk": 22, "s_def": 10, "speed": 19},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE", "SKILL_CHAOS_NOVA"],
		"milestone_egg_skills": {"boss_1": "SKILL_STATIC_TALON", "boss_5": "SKILL_THUNDER_WINGS", "game_win": "SKILL_SKYFALL_STORM"},
		"bounty_egg_skills": {"alpha_1": "SKILL_GRYPH_STRIKE", "alpha_2": "SKILL_HUNTERS_THUNDER", "northern_warden": "SKILL_TROPHY_HURRICANE"},
	},
	# Kristallwühler: Felsbestie mit Bernsteinkristallen auf dem Rücken
	{
		"name": "13",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 27, "s_atk": 6, "s_def": 15, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_FLAME_CLAW", "SKILL_MAGMA_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_SHARD_SWIPE", "boss_5": "SKILL_CRYSTAL_SPIKES", "game_win": "SKILL_GEODE_CRASH"},
		"bounty_egg_skills": {"alpha_1": "SKILL_QUARRY_CLAW", "alpha_2": "SKILL_HUNTERS_BOULDER", "northern_warden": "SKILL_TROPHY_AVALANCHE"},
	},
	# Frostfähe: Eisfüchsin mit kristallenen Schweifen
	{
		"name": "14",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 20, "def": 12, "s_atk": 20, "s_def": 14, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_ICE_SPEAR", "SKILL_WIND_BLADE"],
		"milestone_egg_skills": {"boss_1": "SKILL_SNOW_FLURRY", "boss_5": "SKILL_FROST_TAILS", "game_win": "SKILL_GLACIAL_GRACE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_ICICLE_FANG", "alpha_2": "SKILL_HUNTERS_FROST", "northern_warden": "SKILL_TROPHY_BLIZZARD"},
	},
	# Nebelspuk: Nebelgeist mit Dunstschwaden und violetten Augen
	{
		"name": "15",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 6, "def": 14, "s_atk": 26, "s_def": 24, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_EMBER", "SKILL_WIND_BLADE", "SKILL_ICE_SPEAR"],
		"milestone_egg_skills": {"boss_1": "SKILL_MIST_TOUCH", "boss_5": "SKILL_VAPOR_COIL", "game_win": "SKILL_PHANTOM_FOG"},
		"bounty_egg_skills": {"alpha_1": "SKILL_WISP_GRASP", "alpha_2": "SKILL_HUNTERS_MIST", "northern_warden": "SKILL_TROPHY_DELUGE"},
	},
	# Funkenigel: Igel mit elektrisch geladenen Stacheln
	{
		"name": "16",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 14, "def": 22, "s_atk": 22, "s_def": 10, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE", "SKILL_FLAME_CLAW"],
		"milestone_egg_skills": {"boss_1": "SKILL_STATIC_ROLL", "boss_5": "SKILL_VOLT_QUILLS", "game_win": "SKILL_BALL_LIGHTNING"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SHOCK_NIP", "alpha_2": "SKILL_HUNTERS_SPARK", "northern_warden": "SKILL_TROPHY_SURGE"},
	},
	# Glutskorpion: Lavaskorpion mit brennendem Stachel (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "17",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 22, "s_atk": 14, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_MAGMA_BURST", "SKILL_ROCK_CRUSH"],
	},
	# Dünenhorn: Sandkäfer mit Bernsteinhörnern (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "18",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 18, "s_atk": 10, "s_def": 13, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST", "SKILL_TIDAL_SLAM"],
	},
	# Reifwolf: Eiswolf mit Kristallmähne (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "19",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 24, "def": 12, "s_atk": 18, "s_def": 12, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_ICE_SPEAR", "SKILL_WIND_BLADE"],
	},
	# Dampfhorn: Steinstier mit Dampfwolken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "20",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 22, "atk": 14, "def": 22, "s_atk": 18, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_ICE_SPEAR", "SKILL_WIND_BLADE"],
	},
	# Dünenstachler: Sandskorpion im Staubwirbel (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "21",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 16, "s_atk": 12, "s_def": 14, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST", "SKILL_TIDAL_SLAM"],
	},
	# Schlammschlund: Moorkröte mit Wurzelschwanz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "22",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 24, "atk": 18, "def": 18, "s_atk": 12, "s_def": 18, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_ICE_SPEAR", "SKILL_WIND_BLADE"],
	},
	# Aschrücken: Magmaechse mit Lavaschwanz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "23",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 22, "s_atk": 12, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_MAGMA_BURST", "SKILL_ROCK_CRUSH"],
	},
	# Voltkäfer: Panzerkäfer unter Strom (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "24",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 24, "s_atk": 14, "s_def": 12, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE", "SKILL_ICE_SPEAR"],
	},
	# Moorpanzer: uralte Sumpfschildkröte mit Teich auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "25",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 26, "atk": 14, "def": 26, "s_atk": 12, "s_def": 16, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST", "SKILL_TIDAL_SLAM"],
	},
	# Aschwirbel: Rauchgeist im Glutsturm (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "26",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 10, "def": 12, "s_atk": 26, "s_def": 18, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE", "SKILL_ICE_SPEAR"],
	},
	# Donnerhorn: gehörnte Gewitterwolke (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "27",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [215, 235],
		"preferred_stats": {"hp": 16, "atk": 12, "def": 14, "s_atk": 26, "s_def": 18, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE", "SKILL_ICE_SPEAR"],
	},
	# Dünenbrecher: Sandsteinnashorn (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "28",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 20, "atk": 28, "def": 24, "s_atk": 6, "s_def": 12, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST", "SKILL_TIDAL_SLAM"],
	},
	# Sturmdschinn: gepanzerter Wirbelsturm mit Blitzklauen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "29",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 16, "def": 12, "s_atk": 26, "s_def": 14, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE", "SKILL_ICE_SPEAR"],
	},
	# Vulkanfaust: Vulkangolem mit Lavafäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "30",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 28, "def": 22, "s_atk": 8, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_MAGMA_BURST", "SKILL_ROCK_CRUSH"],
	},
	# Staubkönig: gekrönter Sandgeist mit rotem Herz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "31",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 14, "s_atk": 26, "s_def": 20, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST", "SKILL_TIDAL_SLAM"],
	},
	# Nachthydra: dreiköpfiger Schattendrache (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "32",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [260, 280],
		"preferred_stats": {"hp": 20, "atk": 20, "def": 16, "s_atk": 18, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_ICE_SPEAR", "SKILL_CHAOS_NOVA"],
	},
	# Blutmähne: Mantikor mit Runenpanzer (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "33",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [260, 280],
		"preferred_stats": {"hp": 16, "atk": 26, "def": 16, "s_atk": 12, "s_def": 12, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST", "SKILL_CHAOS_NOVA"],
	},
	# Höllenwächter: dreiköpfiger Schattenhund (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "34",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [260, 280],
		"preferred_stats": {"hp": 18, "atk": 24, "def": 16, "s_atk": 14, "s_def": 12, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_MAGMA_BURST", "SKILL_CHAOS_NOVA"],
	},
	# Leerwurm: Schuppenwyrm mit violetten Flammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "35",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [260, 280],
		"preferred_stats": {"hp": 14, "atk": 16, "def": 12, "s_atk": 24, "s_def": 16, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_THUNDER_STRIKE", "SKILL_CHAOS_NOVA"],
	},
	# Staubgreifer: Sandgeist mit Steinklingen an langen Ranken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "36",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 22, "def": 12, "s_atk": 16, "s_def": 14, "speed": 24},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_WIND_BLADE", "SKILL_MAGMA_BURST"],
	},
	# Mooskoloss: Baumriese aus Moos und Wurzeln mit Kristallkrone (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "37",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 24, "atk": 16, "def": 18, "s_atk": 18, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_SPLASH", "SKILL_TIDAL_SLAM"],
	},
	# Gorgonatter: Riesenschlange mit Schlangenhaupt (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "38",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [245, 265],
		"preferred_stats": {"hp": 15, "atk": 14, "def": 13, "s_atk": 26, "s_def": 16, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_ICE_SPEAR", "SKILL_WIND_BLADE"],
	},
	# Frostgürtler: Gürteltier aus Eisplatten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "39",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 20, "def": 28, "s_atk": 8, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BASIC_BLOCK_WATER", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_ICE_SPEAR", "SKILL_ROCK_CRUSH"],
	},
	# Runenskarab: gekrönter Käfer mit Runenpanzer und Geisterflammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "40",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 16, "atk": 22, "def": 22, "s_atk": 14, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST", "SKILL_CHAOS_NOVA"],
	},
	# Glutroller: eingerollte Lavakugel auf Steinfüßen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "41",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 20, "def": 22, "s_atk": 14, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_ROCK_CRUSH", "SKILL_MAGMA_BURST"],
	},
	# Smogfaust: Giftwolke mit zwei Riesenfäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "42",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 14, "s_atk": 16, "s_def": 14, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_BASIC_BLOCK_AIR", "SKILL_GUST"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_PEBBLE_THROW", "SKILL_THUNDER_STRIKE"],
	},
	# Knochenschläger: Skelettkrieger mit Morgenstern in violetten Flammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "43",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 13, "atk": 27, "def": 12, "s_atk": 14, "s_def": 12, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_ROCK_CRUSH", "SKILL_WIND_BLADE"],
	},
	# Schlundwurm: Riesenwurm mit Zahnkranz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "44",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 24, "atk": 22, "def": 16, "s_atk": 10, "s_def": 14, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_BASIC_BLOCK_EARTH", "SKILL_PEBBLE_THROW"],
		"unlockable_egg_skills": ["SKILL_ROCK_CRUSH", "SKILL_TIDAL_SLAM", "SKILL_MAGMA_BURST"],
	},
	# Vulkanpanzer: Schildkröte mit rauchendem Vulkan auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "45",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 18, "def": 26, "s_atk": 18, "s_def": 10, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_CLAW", "SKILL_MAGMA_BURST", "SKILL_ROCK_CRUSH"],
	},
]
