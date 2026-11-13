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

## Skills (Autoload vor Monmap) ist hier schon geladen.
func _ready() -> void:
	_drop_missing_egg_skills()

## Sicherheitsnetz: Ei-Attacken, die es in Skills nicht (mehr) gibt, fliegen aus den Listen der Arten.
## Sonst liefert Skills.get_skill {} und Konfigurator, Start-Vorschlag, wilde Monster usw. stürzen ab.
func _drop_missing_egg_skills() -> void:
	for mon in mons:
		for key in ["default_egg_skills", "unlockable_egg_skills"]:
			if not mon.has(key):
				continue
			var kept: Array = []
			for skill_name in mon[key]:
				if Skills.has_skill(skill_name):
					kept.append(skill_name)
				else:
					push_warning("Monmap: Ei-Attacke '%s' von '%s' (%s) gibt es nicht, wird ignoriert" % [skill_name, mon.name, key])
			mon[key] = kept
		for key in ["milestone_egg_skills", "bounty_egg_skills"]:
			if not mon.has(key):
				continue
			for slot in mon[key].keys():
				if not Skills.has_skill(mon[key][slot]):
					push_warning("Monmap: Ei-Attacke '%s' von '%s' (%s.%s) gibt es nicht, wird ignoriert" % [mon[key][slot], mon.name, key, slot])
					mon[key].erase(slot)

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
		# Skill-Listen (Regeln: skill_regeln.txt): default = Standard-Skills der drei besten Kampfwerte, immer wählbar;
		# unlockable = Ei-Attacken, die wilde Monster der Art tragen und durch Opfern freigeschaltet werden;
		# milestone = Meilensteine mit der Art als Start-Monster (Skills.MILESTONES), im Neben-Element der Art;
		# bounty = Kopfgelder, ein Monster der Art muss das Kopfgeld-Monster selbst besiegen (Skills.BOUNTIES)
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FEATHER_PUFF", "SKILL_BREEZE_WARD", "SKILL_BASIC_ATTACK_AIR"],
		"unlockable_egg_skills": ["SKILL_GALE_GUARD", "SKILL_AURORA_VEIL", "SKILL_CLOUD_BURST", "SKILL_TAILWIND_BOND"],
		"milestone_egg_skills": {"boss_1": "SKILL_SNOW_FLURRY", "boss_5": "SKILL_ICE_SPEAR", "game_win": "SKILL_PERMAFROST"},
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
		"default_egg_skills": ["SKILL_BASIC_BLOCK_WATER", "SKILL_MIST_VEIL", "SKILL_SPLASH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_TIDE_VEIL", "SKILL_REEF_WALL", "SKILL_DEEP_CALM"],
		"milestone_egg_skills": {"boss_1": "SKILL_HOT_MIST", "boss_5": "SKILL_GEYSER", "game_win": "SKILL_PRESSURE_VALVE"},
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
		"default_egg_skills": ["SKILL_GUST", "SKILL_CLOUD_COVER", "SKILL_WIND_WALL"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_SKY_VEIL", "SKILL_CLOUD_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_DUST_WHIRR", "boss_5": "SKILL_GRIT_CLOAK", "game_win": "SKILL_SANDSTORM"},
		"bounty_egg_skills": {"alpha_1": "SKILL_RAPTOR_DIVE", "alpha_2": "SKILL_HUNTERS_GALE", "northern_warden": "SKILL_TROPHY_PHANTASM"},
	},
	# Hackschupp: Echse mit Beil und Schuppenpanzer
	{
		"name": "4",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 16, "atk": 27, "def": 22, "s_atk": 8, "s_def": 12, "speed": 15},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_BASIC_BLOCK_FIRE", "SKILL_HEAT_SHIMMER"],
		"unlockable_egg_skills": ["SKILL_EMBER_SPIRAL", "SKILL_FORGE_GUARD", "SKILL_BLAZING_CLEAVE", "SKILL_FIRE_BLOOD"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_FIST", "boss_5": "SKILL_OBSIDIAN_SKIN", "game_win": "SKILL_CALDERA_CRASH"},
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
		"default_egg_skills": ["SKILL_GUST", "SKILL_BASIC_ATTACK_AIR", "SKILL_BREEZE_WARD"],
		"unlockable_egg_skills": ["SKILL_GALE_GUARD", "SKILL_WIND_BLADE", "SKILL_CLOUD_BURST", "SKILL_LIGHT_FEATHER"],
		"milestone_egg_skills": {"boss_1": "SKILL_SAND_FANG", "boss_5": "SKILL_DUNE_RAM", "game_win": "SKILL_SANDSTORM"},
		"bounty_egg_skills": {"alpha_1": "SKILL_RAPTOR_DIVE", "alpha_2": "SKILL_HUNTERS_GALE", "northern_warden": "SKILL_TROPHY_SWARM"},
	},
	# Borkenhieb: Baumkrieger mit zwei Runenäxten
	{
		"name": "6",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 19, "atk": 28, "def": 20, "s_atk": 7, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_STONE_GUARD", "SKILL_AMBER_SHELL"],
		"unlockable_egg_skills": ["SKILL_CRYSTAL_SPIKES", "SKILL_STONE_CIRCLE", "SKILL_TECTONIC_SLAM", "SKILL_ROOT_LASH"],
		"milestone_egg_skills": {"boss_1": "SKILL_MUDWING_DIVE", "boss_5": "SKILL_MUDSLIDE", "game_win": "SKILL_BOG_HEART"},
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
		"default_egg_skills": ["SKILL_EARTH_PULSE", "SKILL_AMBER_SHELL", "SKILL_STONE_GUARD"],
		"unlockable_egg_skills": ["SKILL_GEODE_CRASH", "SKILL_EARTH_DOME", "SKILL_FOURFOLD_BLOOM", "SKILL_STONE_KINSHIP"],
		"milestone_egg_skills": {"boss_1": "SKILL_DUST_WHIRR", "boss_5": "SKILL_SANDSTORM", "game_win": "SKILL_SANDSTORM_EYE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SAP_CLEAVER", "alpha_2": "SKILL_HUNTERS_GROVE", "northern_warden": "SKILL_TROPHY_WILDWOOD"},
	},
	# Glutmolch: Lavamolch mit brennendem Schwanz
	{
		"name": "8",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 17, "atk": 16, "def": 15, "s_atk": 24, "s_def": 14, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EMBER", "SKILL_SCORCHING_CHOP", "SKILL_CINDER_WALL"],
		"unlockable_egg_skills": ["SKILL_FLAME_VEIL", "SKILL_BLAZING_CLEAVE", "SKILL_CORE_BLAST", "SKILL_INNER_FIRE"],
		"milestone_egg_skills": {"boss_1": "SKILL_HOT_MIST", "boss_5": "SKILL_GEYSER", "game_win": "SKILL_STEAM_CLOUD"},
		"bounty_egg_skills": {"alpha_1": "SKILL_HOT_HATCHET", "alpha_2": "SKILL_HUNTERS_BLAZE", "northern_warden": "SKILL_TROPHY_ERUPTION"},
	},
	# Quallolotl: Gallert-Axolotl mit Wasserbauch und Quallententakeln
	{
		"name": "9",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 24, "atk": 10, "def": 14, "s_atk": 20, "s_def": 22, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_MIST_TOUCH", "SKILL_SPLASH", "SKILL_SHELL_GUARD"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_MAELSTROM", "SKILL_TIDE_DOME", "SKILL_SIPHON"],
		"milestone_egg_skills": {"boss_1": "SKILL_SLUDGE_SHOT", "boss_5": "SKILL_CLAY_ARMOR", "game_win": "SKILL_SILT_WAVE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SHARK_BITE", "alpha_2": "SKILL_HUNTERS_TIDE", "northern_warden": "SKILL_TROPHY_TORRENT"},
	},
	# Glutkoloss: Lavagolem mit glühendem Kern und Felsfäusten
	{
		"name": "10",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 24, "atk": 26, "def": 24, "s_atk": 8, "s_def": 10, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_CINDER_WALL", "SKILL_EMBER_SHROUD"],
		"unlockable_egg_skills": ["SKILL_EMBER_SPIRAL", "SKILL_HEARTH_CIRCLE", "SKILL_INFERNO_EXECUTION", "SKILL_SMOLDER_STOMP"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_FIST", "boss_5": "SKILL_CALDERA_CRASH", "game_win": "SKILL_MOLTEN_CORE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_HOT_HATCHET", "alpha_2": "SKILL_HUNTERS_BLAZE", "northern_warden": "SKILL_TROPHY_CALDERA"},
	},
	# Wolkenkauz: Wolkeneule auf einem kleinen Wirbelsturm
	{
		"name": "11",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 15, "atk": 10, "def": 12, "s_atk": 24, "s_def": 19, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_GUST", "SKILL_BREEZE_WARD", "SKILL_BASIC_BLOCK_AIR"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_AURORA_VEIL", "SKILL_CLOUD_BURST", "SKILL_STORM_MIND"],
		"milestone_egg_skills": {"boss_1": "SKILL_SNOW_FLURRY", "boss_5": "SKILL_HOARFROST_VEIL", "game_win": "SKILL_GLACIAL_GRACE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_RAPTOR_DIVE", "alpha_2": "SKILL_HUNTERS_GALE", "northern_warden": "SKILL_TROPHY_TYPHOON"},
	},
	# Sturmgreif: Greif mit Blitzschwingen und Wirbelsturmschweifen
	{
		"name": "12",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [230, 250],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 12, "s_atk": 22, "s_def": 10, "speed": 19},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_GUST", "SKILL_TAILWIND_STRIKE", "SKILL_WIND_WALL"],
		"unlockable_egg_skills": ["SKILL_SKY_VEIL", "SKILL_SKYFALL_STORM", "SKILL_NORTHERN_GALE", "SKILL_STORM_FOCUS"],
		"milestone_egg_skills": {"boss_1": "SKILL_ARC_BOLT", "boss_5": "SKILL_THUNDER_STRIKE", "game_win": "SKILL_BALL_LIGHTNING"},
		"bounty_egg_skills": {"alpha_1": "SKILL_RAPTOR_DIVE", "alpha_2": "SKILL_HUNTERS_GALE", "northern_warden": "SKILL_TROPHY_HURRICANE"},
	},
	# Kristallwühler: Felsbestie mit Bernsteinkristallen auf dem Rücken
	{
		"name": "13",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 27, "s_atk": 6, "s_def": 15, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_STONE_GUARD", "SKILL_BASIC_ATTACK_EARTH", "SKILL_AMBER_SHELL"],
		"unlockable_egg_skills": ["SKILL_CRYSTAL_SPIKES", "SKILL_GEODE_CRASH", "SKILL_MOUNTAIN_WALL", "SKILL_THICK_HIDE"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_FIST", "boss_5": "SKILL_OBSIDIAN_SKIN", "game_win": "SKILL_CALDERA_CRASH"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SAP_CLEAVER", "alpha_2": "SKILL_HUNTERS_GROVE", "northern_warden": "SKILL_TROPHY_AVALANCHE"},
	},
	# Frostfähe: Eisfüchsin mit kristallenen Schweifen
	{
		"name": "14",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 20, "def": 12, "s_atk": 20, "s_def": 14, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BUBBLE_SPRAY", "SKILL_MIST_TOUCH"],
		"unlockable_egg_skills": ["SKILL_CORAL_GUARD", "SKILL_MAELSTROM", "SKILL_NORTHERN_TIDE", "SKILL_VAPOR_COIL"],
		"milestone_egg_skills": {"boss_1": "SKILL_FROST_TAILS", "boss_5": "SKILL_ICE_SPEAR", "game_win": "SKILL_GLACIAL_GRACE"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SHARK_BITE", "alpha_2": "SKILL_HUNTERS_TIDE", "northern_warden": "SKILL_TROPHY_BLIZZARD"},
	},
	# Nebelspuk: Nebelgeist mit Dunstschwaden und violetten Augen
	{
		"name": "15",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 6, "def": 14, "s_atk": 26, "s_def": 24, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_SPLASH", "SKILL_MIST_TOUCH", "SKILL_SHELL_GUARD"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_TIDE_DOME", "SKILL_TIDE_HEART", "SKILL_SHELTER_TIDE"],
		"milestone_egg_skills": {"boss_1": "SKILL_HOT_MIST", "boss_5": "SKILL_GEYSER", "game_win": "SKILL_HOT_SPRING"},
		"bounty_egg_skills": {"alpha_1": "SKILL_SHARK_BITE", "alpha_2": "SKILL_HUNTERS_TIDE", "northern_warden": "SKILL_TROPHY_DELUGE"},
	},
	# Funkenigel: Igel mit elektrisch geladenen Stacheln
	{
		"name": "16",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 14, "def": 22, "s_atk": 22, "s_def": 10, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_SPARK_SPIT", "SKILL_BASIC_BLOCK_FIRE", "SKILL_BASIC_ATTACK_FIRE"],
		"unlockable_egg_skills": ["SKILL_FLAME_VEIL", "SKILL_FORGE_GUARD", "SKILL_CORE_BLAST", "SKILL_BATTLE_FERVOR"],
		"milestone_egg_skills": {"boss_1": "SKILL_ARC_BOLT", "boss_5": "SKILL_VOLT_QUILLS", "game_win": "SKILL_BALL_LIGHTNING"},
		"bounty_egg_skills": {"alpha_1": "SKILL_HOT_HATCHET", "alpha_2": "SKILL_HUNTERS_BLAZE", "northern_warden": "SKILL_TROPHY_SURGE"},
	},
	# Glutskorpion: Lavaskorpion mit brennendem Stachel (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "17",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 22, "s_atk": 14, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_CINDER_WALL", "SKILL_SPARK_SPIT"],
		"unlockable_egg_skills": ["SKILL_FLAME_VEIL", "SKILL_HEARTH_CIRCLE", "SKILL_BLAZING_CLEAVE", "SKILL_SMOLDER_STOMP"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_FIST", "boss_5": "SKILL_MAGMA_BURST", "game_win": "SKILL_CALDERA_CRASH"},
	},
	# Dünenhorn: Sandkäfer mit Bernsteinhörnern (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "18",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 18, "s_atk": 10, "s_def": 13, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_PEBBLE_THROW", "SKILL_BASIC_BLOCK_EARTH", "SKILL_SAND_VEIL"],
		"unlockable_egg_skills": ["SKILL_CRYSTAL_SPIKES", "SKILL_GRANITE_SKIN", "SKILL_GEODE_CRASH", "SKILL_TREMOR"],
		"milestone_egg_skills": {"boss_1": "SKILL_SAND_FANG", "boss_5": "SKILL_DUNE_RAM", "game_win": "SKILL_SANDSTORM_EYE"},
	},
	# Reifwolf: Eiswolf mit Kristallmähne (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "19",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 24, "def": 12, "s_atk": 18, "s_def": 12, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BUBBLE_SPRAY", "SKILL_SHELL_GUARD"],
		"unlockable_egg_skills": ["SKILL_TIDE_VEIL", "SKILL_MAELSTROM", "SKILL_NORTHERN_TIDE"],
		"milestone_egg_skills": {"boss_1": "SKILL_FROST_TAILS", "boss_5": "SKILL_ICE_SPEAR", "game_win": "SKILL_PERMAFROST"},
	},
	# Dampfhorn: Steinstier mit Dampfwolken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "20",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 22, "atk": 14, "def": 22, "s_atk": 18, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_SHELL_GUARD", "SKILL_SPLASH", "SKILL_MIST_TOUCH"],
		"unlockable_egg_skills": ["SKILL_TIDAL_SLAM", "SKILL_MAELSTROM", "SKILL_REEF_WALL", "SKILL_SCALE_SHEEN"],
		"milestone_egg_skills": {"boss_1": "SKILL_HOT_MIST", "boss_5": "SKILL_STEAM_CLOUD", "game_win": "SKILL_PRESSURE_VALVE"},
	},
	# Dünenstachler: Sandskorpion im Staubwirbel (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "21",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 16, "s_atk": 12, "s_def": 14, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_SHARD_SWIPE", "SKILL_BASIC_BLOCK_EARTH", "SKILL_SAND_VEIL"],
		"unlockable_egg_skills": ["SKILL_CRYSTAL_SPIKES", "SKILL_GRANITE_SKIN", "SKILL_GEODE_CRASH"],
		"milestone_egg_skills": {"boss_1": "SKILL_SAND_FANG", "boss_5": "SKILL_DUNE_RAM", "game_win": "SKILL_SANDSTORM"},
	},
	# Schlammschlund: Moorkröte mit Wurzelschwanz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "22",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 24, "atk": 18, "def": 18, "s_atk": 12, "s_def": 18, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_SHELL_GUARD", "SKILL_BASIC_ATTACK_WATER", "SKILL_MIST_VEIL"],
		"unlockable_egg_skills": ["SKILL_UNDERTOW", "SKILL_TIDAL_SLAM", "SKILL_REEF_WALL", "SKILL_TIDE_FEAST"],
		"milestone_egg_skills": {"boss_1": "SKILL_MUDWING_DIVE", "boss_5": "SKILL_MUDSLIDE", "game_win": "SKILL_BOG_HEART"},
	},
	# Aschrücken: Magmaechse mit Lavaschwanz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "23",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 22, "s_atk": 12, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_CINDER_WALL", "SKILL_SPARK_SPIT"],
		"unlockable_egg_skills": ["SKILL_FLAME_VEIL", "SKILL_HEARTH_CIRCLE", "SKILL_INFERNO_EXECUTION", "SKILL_WAR_DRUMS"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_SPIT", "boss_5": "SKILL_MAGMA_BURST", "game_win": "SKILL_CALDERA_CRASH"},
	},
	# Voltkäfer: Panzerkäfer unter Strom (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "24",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 24, "s_atk": 14, "s_def": 12, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WIND_WALL", "SKILL_BASIC_ATTACK_AIR", "SKILL_FEATHER_PUFF"],
		"unlockable_egg_skills": ["SKILL_AURORA_VEIL", "SKILL_SKY_TWISTER", "SKILL_WIND_CIRCLE"],
		"milestone_egg_skills": {"boss_1": "SKILL_STATIC_TALON", "boss_5": "SKILL_VOLT_QUILLS", "game_win": "SKILL_BALL_LIGHTNING"},
	},
	# Moorpanzer: uralte Sumpfschildkröte mit Teich auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "25",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 26, "atk": 14, "def": 26, "s_atk": 12, "s_def": 16, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_STONE_GUARD", "SKILL_AMBER_SHELL", "SKILL_BASIC_ATTACK_EARTH"],
		"unlockable_egg_skills": ["SKILL_BLOSSOM_CHORUS", "SKILL_EARTH_DOME", "SKILL_MOUNTAIN_WALL", "SKILL_SHOULDER_STONE"],
		"milestone_egg_skills": {"boss_1": "SKILL_CLAY_ARMOR", "boss_5": "SKILL_MUDSLIDE", "game_win": "SKILL_BOG_BULWARK"},
	},
	# Aschwirbel: Rauchgeist im Glutsturm (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "26",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 10, "def": 12, "s_atk": 26, "s_def": 18, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_GUST", "SKILL_CLOUD_COVER", "SKILL_WIND_WALL"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_SKY_VEIL", "SKILL_NORTHERN_GALE", "SKILL_HIGH_WINDS"],
		"milestone_egg_skills": {"boss_1": "SKILL_ARC_BOLT", "boss_5": "SKILL_THUNDER_STRIKE", "game_win": "SKILL_STATIC_CHARGE"},
	},
	# Donnerhorn: gehörnte Gewitterwolke (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "27",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [215, 235],
		"preferred_stats": {"hp": 16, "atk": 12, "def": 14, "s_atk": 26, "s_def": 18, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_GUST", "SKILL_CLOUD_COVER", "SKILL_WIND_WALL"],
		"unlockable_egg_skills": ["SKILL_WIND_BLADE", "SKILL_SKY_VEIL", "SKILL_NORTHERN_GALE", "SKILL_STARING_GAZE"],
		"milestone_egg_skills": {"boss_1": "SKILL_SNOW_FLURRY", "boss_5": "SKILL_CRYSTAL_FOCUS", "game_win": "SKILL_GLACIAL_GRACE"},
	},
	# Dünenbrecher: Sandsteinnashorn (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "28",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 20, "atk": 28, "def": 24, "s_atk": 6, "s_def": 12, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_STONE_GUARD", "SKILL_AMBER_SHELL"],
		"unlockable_egg_skills": ["SKILL_BLOSSOM_CHORUS", "SKILL_MOUNTAIN_WALL", "SKILL_TECTONIC_SLAM", "SKILL_THICK_HIDE"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_FIST", "boss_5": "SKILL_CALDERA_CRASH", "game_win": "SKILL_FORGE_FURY"},
	},
	# Sturmdschinn: gepanzerter Wirbelsturm mit Blitzklauen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "29",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 16, "def": 12, "s_atk": 26, "s_def": 14, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_GUST", "SKILL_TAILWIND_STRIKE", "SKILL_CLOUD_COVER"],
		"unlockable_egg_skills": ["SKILL_WIND_CIRCLE", "SKILL_ICE_SPEAR", "SKILL_THUNDER_STRIKE", "SKILL_NORTHERN_GALE"],
		"milestone_egg_skills": {"boss_1": "SKILL_ARC_BOLT", "boss_5": "SKILL_GLACIAL_GRACE", "game_win": "SKILL_BALL_LIGHTNING"},
	},
	# Vulkanfaust: Vulkangolem mit Lavafäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "30",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 28, "def": 22, "s_atk": 8, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_CINDER_WALL", "SKILL_EMBER_SHROUD"],
		"unlockable_egg_skills": ["SKILL_CORE_BLAST", "SKILL_OBSIDIAN_SKIN", "SKILL_STEAM_HAMMER", "SKILL_INFERNO_EXECUTION"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_FIST", "boss_5": "SKILL_CALDERA_CRASH", "game_win": "SKILL_MOLTEN_CORE"},
	},
	# Staubkönig: gekrönter Sandgeist mit rotem Herz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "31",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 14, "s_atk": 26, "s_def": 20, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PULSE", "SKILL_AMBER_SHELL", "SKILL_STONE_GUARD"],
		"unlockable_egg_skills": ["SKILL_GEODE_CRASH", "SKILL_EARTH_DOME", "SKILL_SANDSTORM", "SKILL_MAGMA_BURST"],
		"milestone_egg_skills": {"boss_1": "SKILL_DUST_WHIRR", "boss_5": "SKILL_MAGMA_SPIT", "game_win": "SKILL_SANDSTORM_EYE"},
	},
	# Nachthydra: dreiköpfiger Schattendrache (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "32",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [260, 280],
		"preferred_stats": {"hp": 20, "atk": 20, "def": 16, "s_atk": 18, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_WATER", "SKILL_BUBBLE_SPRAY", "SKILL_SHELL_GUARD"],
		"unlockable_egg_skills": ["SKILL_TIDE_DOME", "SKILL_VENOM_MIRE", "SKILL_LAVA_GEYSER", "SKILL_WORLD_SUNDER"],
		"milestone_egg_skills": {"boss_1": "SKILL_THUNDER_WINGS", "boss_5": "SKILL_MIASMA", "game_win": "SKILL_TIDE_FEAST"},
	},
	# Blutmähne: Mantikor mit Runenpanzer (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "33",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [260, 280],
		"preferred_stats": {"hp": 16, "atk": 26, "def": 16, "s_atk": 12, "s_def": 12, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_STONE_GUARD", "SKILL_POLLEN_DRIFT"],
		"unlockable_egg_skills": ["SKILL_EARTH_DOME", "SKILL_SCORCHED_EARTH", "SKILL_LAVA_GEYSER", "SKILL_CHAOS_RIFT"],
		"milestone_egg_skills": {"boss_1": "SKILL_MIASMA", "boss_5": "SKILL_CINDER_CYCLONE", "game_win": "SKILL_VENOM_MIRE"},
	},
	# Höllenwächter: dreiköpfiger Schattenhund (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "34",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [260, 280],
		"preferred_stats": {"hp": 18, "atk": 24, "def": 16, "s_atk": 14, "s_def": 12, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_CINDER_WALL", "SKILL_SPARK_SPIT"],
		"unlockable_egg_skills": ["SKILL_SUN_HALO", "SKILL_SCORCHED_EARTH", "SKILL_THUNDER_WINGS", "SKILL_LAVA_GEYSER"],
		"milestone_egg_skills": {"boss_1": "SKILL_INFERNO_EXECUTION", "boss_5": "SKILL_CINDER_CYCLONE", "game_win": "SKILL_KINDRED_FLAME"},
	},
	# Leerwurm: Schuppenwyrm mit violetten Flammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "35",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [260, 280],
		"preferred_stats": {"hp": 14, "atk": 16, "def": 12, "s_atk": 24, "s_def": 16, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_GUST", "SKILL_TAILWIND_STRIKE", "SKILL_CLOUD_COVER"],
		"unlockable_egg_skills": ["SKILL_WIND_CIRCLE", "SKILL_THUNDER_WINGS", "SKILL_CINDER_CYCLONE", "SKILL_CHAOS_NOVA"],
		"milestone_egg_skills": {"boss_1": "SKILL_MIASMA", "boss_5": "SKILL_VENOM_MIRE", "game_win": "SKILL_TEMPEST_WRATH"},
	},
	# Staubgreifer: Sandgeist mit Steinklingen an langen Ranken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "36",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 22, "def": 12, "s_atk": 16, "s_def": 14, "speed": 24},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_POLLEN_DRIFT", "SKILL_AMBER_SHELL"],
		"unlockable_egg_skills": ["SKILL_GRANITE_SKIN", "SKILL_BLOSSOM_CHORUS", "SKILL_GEODE_CRASH"],
		"milestone_egg_skills": {"boss_1": "SKILL_SAND_FANG", "boss_5": "SKILL_DUNE_RAM", "game_win": "SKILL_SANDSTORM"},
	},
	# Mooskoloss: Baumriese aus Moos und Wurzeln mit Kristallkrone (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "37",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 24, "atk": 16, "def": 18, "s_atk": 18, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_STONE_GUARD", "SKILL_EARTH_PULSE", "SKILL_AMBER_SHELL"],
		"unlockable_egg_skills": ["SKILL_GEODE_CRASH", "SKILL_FOURFOLD_BLOOM", "SKILL_MOUNTAIN_WALL", "SKILL_LEECH_MIRE"],
		"milestone_egg_skills": {"boss_1": "SKILL_SLUDGE_SHOT", "boss_5": "SKILL_CLAY_ARMOR", "game_win": "SKILL_SILT_WAVE"},
	},
	# Gorgonatter: Riesenschlange mit Schlangenhaupt (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "38",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [245, 265],
		"preferred_stats": {"hp": 15, "atk": 14, "def": 13, "s_atk": 26, "s_def": 16, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_SPLASH", "SKILL_MIST_TOUCH", "SKILL_JELLY_STING"],
		"unlockable_egg_skills": ["SKILL_REEF_WALL", "SKILL_GEYSER", "SKILL_SILT_WAVE", "SKILL_TIDE_HEART"],
		"milestone_egg_skills": {"boss_1": "SKILL_HOT_MIST", "boss_5": "SKILL_SLUDGE_SHOT", "game_win": "SKILL_HOT_SPRING"},
	},
	# Frostgürtler: Gürteltier aus Eisplatten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "39",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 20, "def": 28, "s_atk": 8, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_SHELL_GUARD", "SKILL_BASIC_ATTACK_WATER", "SKILL_MIST_TOUCH"],
		"unlockable_egg_skills": ["SKILL_UNDERTOW", "SKILL_TENTACLE_LASH", "SKILL_REEF_WALL", "SKILL_SCALE_SHEEN"],
		"milestone_egg_skills": {"boss_1": "SKILL_FROST_TAILS", "boss_5": "SKILL_ICE_SPEAR", "game_win": "SKILL_PERMAFROST"},
	},
	# Runenskarab: gekrönter Käfer mit Runenpanzer und Geisterflammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "40",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 16, "atk": 22, "def": 22, "s_atk": 14, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_EARTH", "SKILL_STONE_GUARD", "SKILL_POLLEN_DRIFT"],
		"unlockable_egg_skills": ["SKILL_EARTH_DOME", "SKILL_STONE_CIRCLE", "SKILL_TECTONIC_SLAM", "SKILL_STONE_SOUL"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_SPIT", "boss_5": "SKILL_MAGMA_BURST", "game_win": "SKILL_CALDERA_CRASH"},
	},
	# Glutroller: eingerollte Lavakugel auf Steinfüßen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "41",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 20, "def": 22, "s_atk": 14, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_CINDER_WALL", "SKILL_BASIC_ATTACK_FIRE", "SKILL_EMBER"],
		"unlockable_egg_skills": ["SKILL_FLAME_VEIL", "SKILL_FLAME_CLAW", "SKILL_HEARTH_CIRCLE"],
		"milestone_egg_skills": {"boss_1": "SKILL_SCALD_FANG", "boss_5": "SKILL_GEYSER", "game_win": "SKILL_STEAM_HAMMER"},
	},
	# Smogfaust: Giftwolke mit zwei Riesenfäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "42",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 14, "s_atk": 16, "s_def": 14, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_AIR", "SKILL_FEATHER_PUFF", "SKILL_WIND_WALL"],
		"unlockable_egg_skills": ["SKILL_AURORA_VEIL", "SKILL_CLOUD_BURST", "SKILL_SKY_TWISTER"],
		"milestone_egg_skills": {"boss_1": "SKILL_SAND_FANG", "boss_5": "SKILL_DUNE_RAM", "game_win": "SKILL_SANDSTORM_EYE"},
	},
	# Knochenschläger: Skelettkrieger mit Morgenstern in violetten Flammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "43",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 13, "atk": 27, "def": 12, "s_atk": 14, "s_def": 12, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_BASIC_ATTACK_FIRE", "SKILL_SPARK_SPIT", "SKILL_CINDER_WALL"],
		"unlockable_egg_skills": ["SKILL_FLAME_VEIL", "SKILL_CORE_BLAST", "SKILL_INFERNO_EXECUTION", "SKILL_SMOLDER_STOMP"],
		"milestone_egg_skills": {"boss_1": "SKILL_STATIC_TALON", "boss_5": "SKILL_THUNDER_STRIKE", "game_win": "SKILL_BALL_LIGHTNING"},
	},
	# Schlundwurm: Riesenwurm mit Zahnkranz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "44",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 24, "atk": 22, "def": 16, "s_atk": 10, "s_def": 14, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_PEBBLE_THROW", "SKILL_BASIC_BLOCK_EARTH", "SKILL_SAND_VEIL"],
		"unlockable_egg_skills": ["SKILL_CRYSTAL_SPIKES", "SKILL_GRANITE_SKIN", "SKILL_GEODE_CRASH", "SKILL_IRONBARK"],
		"milestone_egg_skills": {"boss_1": "SKILL_MUDWING_DIVE", "boss_5": "SKILL_MUDSLIDE", "game_win": "SKILL_SILT_WAVE"},
	},
	# Vulkanpanzer: Schildkröte mit rauchendem Vulkan auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "45",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 18, "def": 26, "s_atk": 18, "s_def": 10, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_CINDER_WALL", "SKILL_EMBER", "SKILL_SCORCHING_CHOP"],
		"unlockable_egg_skills": ["SKILL_SUN_HALO", "SKILL_MAGMA_BURST", "SKILL_GEYSER", "SKILL_PRIMAL_ERUPTION"],
		"milestone_egg_skills": {"boss_1": "SKILL_MAGMA_SPIT", "boss_5": "SKILL_OBSIDIAN_SKIN", "game_win": "SKILL_MOLTEN_CORE"},
	},
]
