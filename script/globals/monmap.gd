extends Node

func mon_metainfos_by_name(name: String) -> Dictionary:
	return mons.filter(func(mon): return mon.name == name)[0]

## Gibt es diese Art (noch)?
func has_mon(name: String) -> bool:
	return mons.any(func(mon): return mon.name == name)

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
	_add_starter_bounties()
	_drop_missing_egg_skills()

## Starter-Kopfgelder (Skills.STARTER_BOUNTIES) stehen nicht in den Arten selbst (tools/skill_verteilung.js schreibt
## bounty_egg_skills neu), sie kommen hier dazu
func _add_starter_bounties() -> void:
	for bounty in Skills.STARTER_BOUNTIES:
		if not has_mon(bounty.owner):
			continue
		var meta := mon_metainfos_by_name(bounty.owner)
		if not meta.has("bounty_egg_skills"):
			meta["bounty_egg_skills"] = {}
		meta.bounty_egg_skills[bounty.key] = bounty.skill

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
		"preferred_stats": {"hp": 15, "atk": 15, "def": 12, "s_atk": 25, "speed": 18},
		# default_egg_skills (Start), unlockable_egg_skills (durch Fangen & Opfern) und milestone_egg_skills (Skills.MILESTONES)
		# schreibt tools/skill_verteilung.js nach den Regeln in skill_verteilung.txt (Kategorien nach preferred_stats,
		# Gleichstand: Ang. vor Sp. Ang. vor Vert.). Nicht von Hand ändern, sondern das Skript neu laufen lassen:
		#   node tools/skill_verteilung.js
		# Gewöhnliche Arten starten nach ihrem höchsten Kampfwert:
		#   Ang.: Leichter Stoß, Leichter Schlag, Nutzloser Schild
		#   Sp. Ang.: dasselbe magisch, Nutzloser Schild
		#   Vert.: Nutzloser Stoß, Leichter Schild, Nutzloser Stoß der anderen Angriffsart
		#   Der erste Nutzlose Stoß ist magisch, wenn Sp. Ang. höher als Ang. ist.
		# Ab Selten: "affinity" = Neben-Element (Zweier-Kombi), ab Legendär "affinity_triple" (Dreier-Kombi).
		# "skills_manual": true = Skills von Hand gepflegt, das Skript lässt die Art aus.
		# Optional: bounty_egg_skills (Skills.BOUNTIES), von Hand
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_AIR_ARMOR_PLAIN", "SKILL_AIR_ARMOR_DRAFT_GUARD", "SKILL_AIR_MAG_WIND_BLADE"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_AIR_PHYS_GUST_KICK",
			"boss_3": "SKILL_AIR_MAG_TEMPEST_RAY",
			"triple": "SKILL_AIR_PHYS_CYCLONE_CLAW",
		},
		"bounty_egg_skills": {"alpha_1": "SKILL_AIR_ARMOR_GALE_WALL"},
	},
	# Leuchtkrabbe: Krabbe mit Leuchtturm auf dem Panzer
	{
		"name": "2",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 14, "def": 25, "s_atk": 14, "speed": 10},
		"max_upgrades": 2,
		# Startmonster (Tank), durch Fangen & Opfern: Leichter Schild und Leichte Rückhand
		"default_egg_skills": ["SKILL_WATER_PHYS_STARTER_JAB", "SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_MAG_STARTER_PULSE"],
		"unlockable_egg_skills": ["SKILL_WATER_ARMOR_PLAIN", "SKILL_WATER_PHYS_BACKHAND"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_WATER_PHYS_TIDE_SLAP",
			"kills_10": "SKILL_WATER_ARMOR_CORAL_WALL",
			"triple": "SKILL_WATER_PHYS_BREAKER",
		},
		"bounty_egg_skills": {"alpha_2": "SKILL_WATER_MAG_HYDRO_LANCE"},
	},
	# Schattflaum: Federgeist aus violettem Rauch
	{
		"name": "3",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 8, "def": 12, "s_atk": 27, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_CANNON", "SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BACKHAND", "SKILL_FIRE_ARMOR_CINDER_PLATE", "SKILL_FIRE_MAG_FIREBALL", "SKILL_FIRE_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_FIRE_BUFF_FIGHTING_SPIRIT",
			"kills_10": "SKILL_FIRE_MAG_SPARK_SHOT",
			"triple": "SKILL_FIRE_ARMOR_FLAME_WALL",
		},
		"bounty_egg_skills": {"alpha_3": "SKILL_FIRE_PHYS_BLAZE_RUSH"},
	},
	# Hackschupp: Echse mit Beil und Schuppenpanzer
	{
		"name": "4",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 16, "atk": 27, "def": 22, "s_atk": 8, "speed": 15},
		"max_upgrades": 2,
		# Startmonster (Angreifer), durch Fangen & Opfern: Kleiner Punch und Punch
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_STARTER"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_SMALL_PUNCH", "SKILL_FIRE_PHYS_PUNCH"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_FIRE_ARMOR_CINDER_PLATE",
			"bounty": "SKILL_FIRE_PHYS_BLAZE_RUSH",
			"triple": "SKILL_FIRE_ARMOR_FLAME_WALL",
		},
		"bounty_egg_skills": {"alpha_4": "SKILL_FIRE_MAG_FIREBALL"},
	},
	# Glotzlibelle: Libelle mit Stielaugen
	{
		"name": "5",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 13, "atk": 18, "def": 11, "s_atk": 20, "speed": 24},
		"max_upgrades": 2,
		# Startmonster (Angreifer), durch Fangen & Opfern: Kleine Windkanone und Windkanone
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_ARMOR_STARTER"],
		"unlockable_egg_skills": ["SKILL_AIR_MAG_SMALL_CANNON", "SKILL_AIR_MAG_CANNON"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_AIR_PHYS_GUST_KICK",
			"new_element": "SKILL_AIR_MAG_TEMPEST_RAY",
			"finisher_2": "SKILL_AIR_PHYS_CYCLONE_CLAW",
		},
		"bounty_egg_skills": {"alpha_5": "SKILL_AIR_ARMOR_GALE_WALL"},
	},
	# Borkenhieb: Baumkrieger mit zwei Runenäxten
	{
		"name": "6",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [215, 235],
		"preferred_stats": {"hp": 19, "atk": 28, "def": 20, "s_atk": 7, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_BOULDER_BASH", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_BUFF_BATTLE_FRENZY", "SKILL_EARTH_BUFF_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_EARTH_ARMOR_STONE_SKIN",
			"boss_4": "SKILL_MUD_ARMOR_MUD_COAT",
			"triple": "SKILL_MUD_PHYS_MUD_PUNCH",
		},
		"bounty_egg_skills": {"alpha_6": "SKILL_MUD_MAG_SLUDGE_SHOT"},
	},
	# Hainschwestern: vier Baumfeen unter einer Krone
	{
		"name": "7",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [230, 250],
		"preferred_stats": {"hp": 17, "atk": 8, "def": 14, "s_atk": 25, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_GEO_PULSE", "SKILL_EARTH_ARMOR_STONE_SKIN", "SKILL_EARTH_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_MAG_GEO_PULSE_SWIFT", "SKILL_EARTH_BUFF_EXTRA_CLUB", "SKILL_EARTH_BUFF_TEAM_S_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_MUD_ARMOR_MUD_COAT",
			"flawless_3": "SKILL_MUD_MAG_SLUDGE_SHOT",
			"triple": "SKILL_PASSIVE_BULWARK_MASTER",
		},
		"bounty_egg_skills": {"alpha_7": "SKILL_MUD_PHYS_MUD_PUNCH"},
	},
	# Glutmolch: Lavamolch mit brennendem Schwanz
	{
		"name": "8",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 17, "atk": 16, "def": 15, "s_atk": 24, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_CANNON", "SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_FIRE_ARMOR_PLAIN", "SKILL_FIRE_PHYS_FLAME_FIST", "SKILL_FIRE_MAG_FIREBALL", "SKILL_FIRE_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_FIRE_BUFF_SPARK_STRIKE",
			"new_element": "SKILL_FIRE_MAG_SPARK_SHOT",
			"boss_3": "SKILL_FIRE_PHYS_BLAZE_RUSH",
		},
		"bounty_egg_skills": {"alpha_8": "SKILL_FIRE_ARMOR_FLAME_WALL"},
	},
	# Quallolotl: Gallert-Axolotl mit Wasserbauch und Quallententakeln
	{
		"name": "9",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 24, "atk": 10, "def": 14, "s_atk": 20, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_CANNON", "SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BACKHAND", "SKILL_WATER_ARMOR_SHELL", "SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_WATER_BUFF_FIGHTING_SPIRIT",
			"new_element": "SKILL_WATER_MAG_BUBBLE_BEAM",
			"boss_3": "SKILL_WATER_ARMOR_CORAL_WALL",
		},
		"bounty_egg_skills": {"alpha_9": "SKILL_WATER_PHYS_BREAKER"},
	},
	# Glutkoloss: Lavagolem mit glühendem Kern und Felsfäusten
	{
		"name": "10",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE,  # Neben-Element Magma
		"stats": [215, 235],
		"preferred_stats": {"hp": 24, "atk": 26, "def": 24, "s_atk": 8, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_FLAME_FIST", "SKILL_FIRE_ARMOR_LIGHT", "SKILL_FIRE_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_ARMOR_FLAME_WALL", "SKILL_FIRE_BUFF_BATTLE_FRENZY", "SKILL_FIRE_BUFF_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_FIRE_ARMOR_CINDER_PLATE",
			"boss_4": "SKILL_MAGMA_ARMOR_PUMICE_SKIN",
			"triple": "SKILL_MAGMA_PHYS_EMBER_KNUCKLE",
		},
		"bounty_egg_skills": {"alpha_10": "SKILL_MAGMA_MAG_LAVA_SPIT"},
	},
	# Wolkenkauz: Wolkeneule auf einem kleinen Wirbelsturm
	{
		"name": "11",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 15, "atk": 10, "def": 12, "s_atk": 24, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_AIR_PHYS_BACKHAND", "SKILL_AIR_PHYS_GUST_KICK", "SKILL_AIR_MAG_WIND_BLADE"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_AIR_ARMOR_DRAFT_GUARD",
			"new_element": "SKILL_AIR_MAG_TEMPEST_RAY",
			"bounty": "SKILL_AIR_ARMOR_GALE_WALL",
		},
		"bounty_egg_skills": {"alpha_11": "SKILL_AIR_PHYS_CYCLONE_CLAW"},
	},
	# Sturmgreif: Greif mit Blitzschwingen und Wirbelsturmschweifen
	{
		"name": "12",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR,  # Neben-Element Blitz
		"stats": [230, 250],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 12, "s_atk": 22, "speed": 19},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_MAG_WIND_BLADE", "SKILL_AIR_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_PHYS_CYCLONE_CLAW_SWIFT", "SKILL_AIR_BUFF_TAILWIND", "SKILL_CHAOS_BOON_COURAGE"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_LIGHTNING_MAG_SPARK_BOLT",
			"kills_15": "SKILL_LIGHTNING_PHYS_SHOCK_TAP",
			"triple": "SKILL_PASSIVE_BATTLE_FERVOR",
		},
		"bounty_egg_skills": {"alpha_12": "SKILL_LIGHTNING_ARMOR_CHARGE_PLATE"},
	},
	# Kristallwühler: Felsbestie mit Bernsteinkristallen auf dem Rücken
	{
		"name": "13",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"stats": [215, 235],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 27, "s_atk": 6, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_ARMOR_STONE_SKIN", "SKILL_EARTH_PHYS_PUNCH", "SKILL_EARTH_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_BUFF_EXTRA_SHIELD", "SKILL_PASSIVE_EARTH_POWER"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_EARTH_PHYS_BOULDER_BASH",
			"boss_4": "SKILL_DUST_PHYS_GRIT_PUNCH",
			"triple": "SKILL_DUST_ARMOR_SANDSTONE_SKIN",
		},
		"bounty_egg_skills": {"alpha_13": "SKILL_DUST_MAG_DUST_SHOT"},
	},
	# Frostfähe: Eisfüchsin mit kristallenen Schweifen
	{
		"name": "14",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Neben-Element Eis
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 20, "def": 12, "s_atk": 20, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_TIDE_SLAP", "SKILL_WATER_MAG_CANNON", "SKILL_WATER_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_BUFF_BATTLE_FRENZY", "SKILL_WATER_BUFF_ATK"],
		"milestone_egg_skills": {
			"finisher_2": "SKILL_WATER_MAG_BUBBLE_BEAM",
			"kills_15": "SKILL_ICE_MAG_SNOW_FLURRY",
			"triple": "SKILL_ICE_PHYS_FROST_BITE",
		},
		"bounty_egg_skills": {"alpha_14": "SKILL_ICE_ARMOR_RIME_COAT"},
	},
	# Nebelspuk: Nebelgeist mit Dunstschwaden und violetten Augen, Luftwesen
	{
		"name": "15",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 6, "def": 14, "s_atk": 26, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_CANNON", "SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_AIR_PHYS_BACKHAND", "SKILL_AIR_ARMOR_DRAFT_GUARD", "SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_AIR_BUFF_FIGHTING_SPIRIT",
			"finisher_2": "SKILL_AIR_MAG_WIND_BLADE",
			"triple": "SKILL_AIR_ARMOR_GALE_WALL",
		},
		"bounty_egg_skills": {"alpha_15": "SKILL_AIR_PHYS_CYCLONE_CLAW"},
	},
	# Funkenigel: Igel mit elektrisch geladenen Stacheln
	{
		"name": "16",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 14, "def": 22, "s_atk": 22, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BACKHAND", "SKILL_FIRE_PHYS_FLAME_FIST", "SKILL_FIRE_MAG_SPARK_SHOT"],
		"milestone_egg_skills": {
			"finisher_1": "SKILL_FIRE_ARMOR_CINDER_PLATE",
			"new_element": "SKILL_FIRE_MAG_FIREBALL",
			"boss_3": "SKILL_FIRE_ARMOR_FLAME_WALL",
		},
		"bounty_egg_skills": {"alpha_16": "SKILL_FIRE_PHYS_BLAZE_RUSH"},
	},
	# Glutskorpion: Lavaskorpion mit brennendem Stachel (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "17",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 22, "s_atk": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_PUNCH", "SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_FIRE_MAG_LIGHT_CANNON", "SKILL_FIRE_ARMOR_CINDER_PLATE", "SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_BUFF_ATK"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_FIRE_BUFF_FIGHTING_SPIRIT",
			"new_element": "SKILL_FIRE_PHYS_FLAME_FIST",
			"flawless_2": "SKILL_FIRE_ARMOR_FLAME_WALL",
		},
		"bounty_egg_skills": {"alpha_17": "SKILL_FIRE_MAG_FIREBALL"},
	},
	# Dünenhorn: Sandkäfer mit Bernsteinhörnern, flinker physischer Angreifer, Neben-Element Staub
	{
		"name": "18",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"stats": [215, 235],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 18, "s_atk": 10, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_GUST_KICK", "SKILL_AIR_ARMOR_LIGHT", "SKILL_AIR_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_ARMOR_GALE_WALL", "SKILL_AIR_BUFF_BATTLE_FRENZY", "SKILL_AIR_BUFF_ATK"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_AIR_ARMOR_DRAFT_GUARD",
			"boss_4": "SKILL_DUST_ARMOR_SANDSTONE_SKIN",
			"triple": "SKILL_DUST_PHYS_GRIT_PUNCH",
		},
		"bounty_egg_skills": {"alpha_18": "SKILL_DUST_MAG_DUST_SHOT"},
	},
	# Reifwolf: Eiswolf mit Kristallmähne (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "19",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Neben-Element Eis
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 24, "def": 12, "s_atk": 18, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_TIDE_SLAP", "SKILL_WATER_MAG_CANNON", "SKILL_WATER_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_BUFF_BATTLE_FRENZY", "SKILL_WATER_BUFF_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_WATER_MAG_BUBBLE_BEAM",
			"bounty": "SKILL_ICE_MAG_SNOW_FLURRY",
			"triple": "SKILL_ICE_PHYS_FROST_BITE",
		},
		"bounty_egg_skills": {"alpha_19": "SKILL_ICE_ARMOR_RIME_COAT"},
	},
	# Dampfhorn: Steinstier mit Dampfwolken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "20",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 22, "atk": 14, "def": 22, "s_atk": 18, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BACKHAND", "SKILL_WATER_MAG_BUBBLE_BEAM", "SKILL_WATER_ARMOR_CORAL_WALL", "SKILL_WATER_BUFF_DEF"],
		"milestone_egg_skills": {
			"finisher_1": "SKILL_WATER_BUFF_WAVE_SHIELD",
			"new_element": "SKILL_WATER_ARMOR_SHELL",
			"finisher_2": "SKILL_WATER_MAG_HYDRO_LANCE",
		},
		"bounty_egg_skills": {"alpha_20": "SKILL_WATER_PHYS_BREAKER"},
	},
	# Dünenstachler: Sandskorpion im Staubwirbel, flinker physischer Angreifer mit Scheren und Giftstachel, Neben-Element Staub
	{
		"name": "21",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 26, "def": 16, "s_atk": 8, "speed": 24},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_EARTH_MAG_LIGHT_CANNON", "SKILL_EARTH_MAG_PEBBLE_STORM", "SKILL_EARTH_PHYS_BOULDER_BASH"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_EARTH_ARMOR_STONE_SKIN",
			"new_element": "SKILL_EARTH_PHYS_QUAKE_STOMP",
			"flawless_2": "SKILL_EARTH_ARMOR_GRANITE_BASTION",
		},
		"bounty_egg_skills": {"alpha_21": "SKILL_EARTH_MAG_GEO_PULSE"},
	},
	# Schlammschlund: Moorkröte mit Wurzelschwanz, Erdwesen (Platzhalter: Werte folgen beim Balancing)
	{
		"name": "22",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 24, "atk": 18, "def": 18, "s_atk": 12, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_EARTH_MAG_LIGHT_CANNON", "SKILL_EARTH_MAG_PEBBLE_STORM", "SKILL_EARTH_PHYS_BOULDER_BASH"],
		"milestone_egg_skills": {
			"finisher_1": "SKILL_EARTH_ARMOR_STONE_SKIN",
			"boss_3": "SKILL_EARTH_PHYS_QUAKE_STOMP",
			"triple": "SKILL_EARTH_ARMOR_GRANITE_BASTION",
		},
		"bounty_egg_skills": {"alpha_22": "SKILL_EARTH_MAG_GEO_PULSE"},
	},
	# Aschrücken: Magmaechse mit Lavaschwanz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "23",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE,  # Neben-Element Magma
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 22, "s_atk": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_FLAME_FIST", "SKILL_FIRE_ARMOR_LIGHT", "SKILL_FIRE_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_ARMOR_FLAME_WALL", "SKILL_FIRE_BUFF_BATTLE_FRENZY", "SKILL_FIRE_BUFF_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_FIRE_ARMOR_CINDER_PLATE",
			"finisher_3": "SKILL_MAGMA_ARMOR_PUMICE_SKIN",
			"triple": "SKILL_MAGMA_PHYS_EMBER_KNUCKLE",
		},
		"bounty_egg_skills": {"alpha_23": "SKILL_MAGMA_MAG_LAVA_SPIT"},
	},
	# Voltkäfer: Panzerkäfer unter Strom (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "24",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 24, "s_atk": 14, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_ARMOR_LIGHT", "SKILL_AIR_PHYS_LIGHT_THRUST", "SKILL_AIR_PHYS_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_AIR_MAG_LIGHT_CANNON", "SKILL_AIR_PHYS_GUST_KICK", "SKILL_AIR_ARMOR_GALE_WALL", "SKILL_AIR_BUFF_DEF"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_AIR_BUFF_WIND_MANTLE",
			"new_element": "SKILL_AIR_ARMOR_DRAFT_GUARD",
			"bounty": "SKILL_AIR_PHYS_CYCLONE_CLAW",
		},
		"bounty_egg_skills": {"alpha_24": "SKILL_AIR_MAG_TEMPEST_RAY"},
	},
	# Moorpanzer: uralte Sumpfschildkröte mit Teich auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "25",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [230, 250],
		"preferred_stats": {"hp": 26, "atk": 14, "def": 26, "s_atk": 12, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_PHYS_BOULDER_BASH", "SKILL_EARTH_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_ARMOR_GRANITE_BASTION_SWIFT", "SKILL_EARTH_BUFF_EXTRA_CLUB", "SKILL_EARTH_BUFF_TEAM_DEF"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_MUD_PHYS_MUD_PUNCH",
			"flawless_3": "SKILL_MUD_ARMOR_MUD_COAT",
			"triple": "SKILL_PASSIVE_BULWARK_MASTER",
		},
		"bounty_egg_skills": {"alpha_25": "SKILL_MUD_MAG_SLUDGE_SHOT"},
	},
	# Aschwirbel: Rauchgeist im Glutsturm (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "26",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 10, "def": 12, "s_atk": 26, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_CANNON", "SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BACKHAND", "SKILL_FIRE_ARMOR_CINDER_PLATE", "SKILL_FIRE_MAG_FIREBALL", "SKILL_FIRE_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_FIRE_BUFF_SPARK_STRIKE",
			"new_element": "SKILL_FIRE_MAG_SPARK_SHOT",
			"flawless_2": "SKILL_FIRE_ARMOR_FLAME_WALL",
		},
		"bounty_egg_skills": {"alpha_26": "SKILL_FIRE_PHYS_BLAZE_RUSH"},
	},
	# Donnerhorn: gehörnte Gewitterwolke (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "27",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR,  # Neben-Element Blitz
		"stats": [215, 235],
		"preferred_stats": {"hp": 16, "atk": 12, "def": 14, "s_atk": 26, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_WIND_BLADE", "SKILL_AIR_ARMOR_LIGHT", "SKILL_AIR_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_ARMOR_GALE_WALL", "SKILL_AIR_BUFF_BATTLE_FRENZY", "SKILL_AIR_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_AIR_ARMOR_DRAFT_GUARD",
			"kills_15": "SKILL_LIGHTNING_ARMOR_CHARGE_PLATE",
			"triple": "SKILL_LIGHTNING_MAG_SPARK_BOLT",
		},
		"bounty_egg_skills": {"alpha_27": "SKILL_LIGHTNING_PHYS_SHOCK_TAP"},
	},
	# Dünenbrecher: Sandsteinnashorn (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "28",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE,  # Neben-Element Magma
		"stats": [230, 250],
		"preferred_stats": {"hp": 20, "atk": 28, "def": 24, "s_atk": 6, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_ARMOR_CINDER_PLATE", "SKILL_FIRE_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_FIRE_ARMOR_FLAME_WALL", "SKILL_FIRE_PHYS_BLAZE_RUSH_SWIFT", "SKILL_FIRE_BUFF_EMBER_HEAT", "SKILL_CHAOS_BOON_COURAGE"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_MAGMA_ARMOR_PUMICE_SKIN",
			"kills_15": "SKILL_MAGMA_PHYS_EMBER_KNUCKLE",
			"triple": "SKILL_PASSIVE_FIRE_POWER",
		},
		"bounty_egg_skills": {"alpha_28": "SKILL_MAGMA_MAG_LAVA_SPIT"},
	},
	# Sturmdschinn: gepanzerter Wirbelsturm mit Blitzklauen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "29",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR,  # Neben-Element Blitz
		"affinity_triple": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Gewitter
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 18, "s_atk": 26, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_ARMOR_GALE_WALL", "SKILL_AIR_MAG_TEMPEST_RAY_SWIFT"],
		"unlockable_egg_skills": ["SKILL_LIGHTNING_MAG_ARC_BOLT", "SKILL_LIGHTNING_ARMOR_STATIC_PLATE", "SKILL_LIGHTNING_MAG_THUNDERCLAP", "SKILL_CHAOS_BUFF_YIN_YANG"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_THUNDERSTORM_MAG_STATIC_RAIN",
			"bounty": "SKILL_THUNDERSTORM_MAG_CHAIN_LIGHTNING",
			"triple": "SKILL_PASSIVE_LIGHTNING_T4",
		},
		"bounty_egg_skills": {"alpha_29": "SKILL_THUNDERSTORM_ARMOR_RAIN_GUARD"},
	},
	# Vulkanfaust: Vulkangolem mit Lavafäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "30",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE,  # Neben-Element Magma
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER,  # Dreier-Kombi Vulkan
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 28, "def": 22, "s_atk": 8, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_ARMOR_FLAME_WALL", "SKILL_FIRE_PHYS_BLAZE_RUSH_SWIFT"],
		"unlockable_egg_skills": ["SKILL_MAGMA_PHYS_LAVA_FIST", "SKILL_MAGMA_ARMOR_OBSIDIAN_PLATE", "SKILL_MAGMA_PHYS_ERUPTION_SLAM", "SKILL_CHAOS_BUFF_BUDDHA_FIST"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_VOLCANO_PHYS_VOLCANIC_FIST",
			"boss_4": "SKILL_VOLCANO_PHYS_CALDERA_CRUSH",
			"triple": "SKILL_PASSIVE_MAGMA_T4",
		},
		"bounty_egg_skills": {"alpha_30": "SKILL_VOLCANO_ARMOR_LAVA_CRUST"},
	},
	# Staubkönig: gekrönter Sandgeist mit rotem Herz (Luft, physischer Angreifer, Neben-Element Staub)
	{
		"name": "31",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Aschesturm
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 26, "def": 14, "s_atk": 10, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_ARMOR_GALE_WALL", "SKILL_AIR_PHYS_CYCLONE_CLAW_SWIFT"],
		"unlockable_egg_skills": ["SKILL_DUST_PHYS_SAND_CLAW", "SKILL_DUST_ARMOR_DUNE_WALL", "SKILL_DUST_MAG_SANDSTORM", "SKILL_CHAOS_BUFF_BUDDHA_FIST"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_ASH_STORM_PHYS_SOOT_STRIKE",
			"boss_4": "SKILL_ASH_STORM_PHYS_CINDER_CLAW",
			"triple": "SKILL_PASSIVE_DUST_T4",
		},
		"bounty_egg_skills": {"alpha_31": "SKILL_ASH_STORM_ARMOR_CINDER_SHELL"},
	},
	# Blutmähne: Mantikor mit Runenpanzer (Erde, Neben-Element Staub)
	{
		"name": "33",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Aschesturm
		"stats": [245, 265],
		"preferred_stats": {"hp": 16, "atk": 22, "def": 20, "s_atk": 12, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_PHYS_QUAKE_STOMP_SWIFT"],
		"unlockable_egg_skills": ["SKILL_DUST_PHYS_SAND_CLAW", "SKILL_DUST_ARMOR_DUNE_WALL", "SKILL_DUST_MAG_SANDSTORM", "SKILL_CHAOS_BUFF_BUDDHA_FIST"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_ASH_STORM_PHYS_SOOT_STRIKE",
			"flawless_3": "SKILL_ASH_STORM_PHYS_CINDER_CLAW",
			"triple": "SKILL_PASSIVE_DUST_T4",
		},
		"bounty_egg_skills": {"alpha_33": "SKILL_ASH_STORM_ARMOR_CINDER_SHELL"},
	},
	# Staubgreifer: Sandgeist mit Steinklingen an langen Ranken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "36",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 22, "def": 12, "s_atk": 16, "speed": 24},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_PUNCH", "SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_MAG_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_EARTH_ARMOR_PLAIN", "SKILL_EARTH_MAG_PEBBLE_STORM", "SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_BUFF_ATK"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_EARTH_BUFF_FIGHTING_SPIRIT",
			"new_element": "SKILL_EARTH_PHYS_BOULDER_BASH",
			"flawless_2": "SKILL_EARTH_MAG_GEO_PULSE",
		},
		"bounty_egg_skills": {"alpha_36": "SKILL_EARTH_ARMOR_GRANITE_BASTION"},
	},
	# Mooskoloss: Baumriese aus Moos und Wurzeln mit Kristallkrone (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "37",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [230, 250],
		"preferred_stats": {"hp": 24, "atk": 16, "def": 18, "s_atk": 18, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_GEO_PULSE", "SKILL_EARTH_ARMOR_STONE_SKIN", "SKILL_EARTH_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_MAG_GEO_PULSE_SWIFT", "SKILL_EARTH_BUFF_EXTRA_CLUB", "SKILL_EARTH_BUFF_TEAM_S_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_MUD_ARMOR_MUD_COAT",
			"kills_15": "SKILL_MUD_MAG_SLUDGE_SHOT",
			"triple": "SKILL_PASSIVE_BULWARK_MASTER",
		},
		"bounty_egg_skills": {"alpha_37": "SKILL_MUD_PHYS_MUD_PUNCH"},
	},
	# Gorgonatter: Riesenschlange mit Schlangenhaupt (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "38",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Dreier-Kombi Sumpf
		"stats": [245, 265],
		"preferred_stats": {"hp": 15, "atk": 14, "def": 13, "s_atk": 26, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_MAG_HYDRO_LANCE_SWIFT"],
		"unlockable_egg_skills": ["SKILL_MUD_MAG_BOG_PULSE", "SKILL_MUD_PHYS_MUD_SLAM", "SKILL_MUD_ARMOR_LANDSLIDE_WALL", "SKILL_CHAOS_BUFF_YIN_YANG"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_SWAMP_MAG_SPORE_PUFF",
			"boss_4": "SKILL_SWAMP_MAG_MIASMA_CLOUD",
			"triple": "SKILL_PASSIVE_MUD_T4",
		},
		"bounty_egg_skills": {"alpha_38": "SKILL_SWAMP_PHYS_REED_WHIP"},
	},
	# Frostgürtler: Gürteltier aus Eisplatten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "39",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Neben-Element Eis
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 20, "def": 28, "s_atk": 8, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_ARMOR_SHELL", "SKILL_WATER_PHYS_PUNCH", "SKILL_WATER_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_WATER_ARMOR_CORAL_WALL", "SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_BUFF_EXTRA_SHIELD", "SKILL_PASSIVE_WATER_POWER"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_WATER_PHYS_TIDE_SLAP",
			"flawless_3": "SKILL_ICE_PHYS_FROST_BITE",
			"triple": "SKILL_ICE_ARMOR_RIME_COAT",
		},
		"bounty_egg_skills": {"alpha_39": "SKILL_ICE_MAG_SNOW_FLURRY"},
	},
	# Runenskarab: gekrönter Käfer mit Runenpanzer und Geisterflammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "40",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"stats": [230, 250],
		"preferred_stats": {"hp": 16, "atk": 22, "def": 22, "s_atk": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_ARMOR_DRAFT_GUARD", "SKILL_AIR_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_AIR_ARMOR_GALE_WALL", "SKILL_AIR_PHYS_CYCLONE_CLAW_SWIFT", "SKILL_AIR_BUFF_TAILWIND", "SKILL_CHAOS_BOON_COURAGE"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_DUST_ARMOR_SANDSTONE_SKIN",
			"bounty": "SKILL_DUST_PHYS_GRIT_PUNCH",
			"triple": "SKILL_PASSIVE_AIR_POWER",
		},
		"bounty_egg_skills": {"alpha_40": "SKILL_DUST_MAG_DUST_SHOT"},
	},
	# Glutroller: eingerollte Lavakugel auf Steinfüßen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "41",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 20, "def": 22, "s_atk": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_WEAK_THRUST", "SKILL_FIRE_ARMOR_LIGHT", "SKILL_FIRE_MAG_WEAK_THRUST"],
		"unlockable_egg_skills": ["SKILL_FIRE_MAG_LIGHT_CANNON", "SKILL_FIRE_MAG_SPARK_SHOT", "SKILL_FIRE_ARMOR_CINDER_PLATE"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_FIRE_PHYS_FLAME_FIST",
			"new_element": "SKILL_FIRE_ARMOR_FLAME_WALL",
			"flawless_2": "SKILL_FIRE_PHYS_BLAZE_RUSH",
		},
		"bounty_egg_skills": {"alpha_41": "SKILL_FIRE_MAG_FIREBALL"},
	},
	# Smogfaust: Giftwolke mit zwei Riesenfäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "42",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 14, "s_atk": 16, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_PUNCH", "SKILL_AIR_PHYS_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_AIR_ARMOR_PLAIN", "SKILL_AIR_MAG_WIND_BLADE", "SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_BUFF_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_AIR_BUFF_GUST",
			"boss_3": "SKILL_AIR_PHYS_GUST_KICK",
			"triple": "SKILL_AIR_MAG_TEMPEST_RAY",
		},
		"bounty_egg_skills": {"alpha_42": "SKILL_AIR_ARMOR_GALE_WALL"},
	},
	# Knochenschläger: Skelettkrieger mit Morgenstern in violetten Flammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "43",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR,  # Neben-Element Blitz
		"stats": [215, 235],
		"preferred_stats": {"hp": 13, "atk": 27, "def": 12, "s_atk": 14, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_FLAME_FIST", "SKILL_FIRE_MAG_CANNON", "SKILL_FIRE_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_MAG_FIREBALL", "SKILL_FIRE_BUFF_BATTLE_FRENZY", "SKILL_FIRE_BUFF_ATK"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_FIRE_MAG_SPARK_SHOT",
			"bounty": "SKILL_LIGHTNING_MAG_SPARK_BOLT",
			"triple": "SKILL_LIGHTNING_PHYS_SHOCK_TAP",
		},
		"bounty_egg_skills": {"alpha_43": "SKILL_LIGHTNING_ARMOR_CHARGE_PLATE"},
	},
	# Vulkanpanzer: Schildkröte mit rauchendem Vulkan auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "45",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE,  # Neben-Element Magma
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER,  # Dreier-Kombi Vulkan
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 18, "def": 26, "s_atk": 18, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_ARMOR_FLAME_WALL", "SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_PHYS_BLAZE_RUSH_SWIFT"],
		"unlockable_egg_skills": ["SKILL_MAGMA_ARMOR_OBSIDIAN_PLATE", "SKILL_MAGMA_PHYS_LAVA_FIST", "SKILL_MAGMA_PHYS_ERUPTION_SLAM", "SKILL_CHAOS_BUFF_GOLDEN_SHIELD"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_VOLCANO_ARMOR_LAVA_CRUST",
			"boss_4": "SKILL_VOLCANO_ARMOR_BASALT_FORT",
			"triple": "SKILL_PASSIVE_MAGMA_T4",
		},
		"bounty_egg_skills": {"alpha_45": "SKILL_VOLCANO_PHYS_VOLCANIC_FIST"},
	},
	# Glutechse: Echse mit Lavagestein-Haut und Flammenkamm, Neben-Element Magma
	{
		"name": "46",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 24, "def": 22, "s_atk": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_FIRE_MAG_LIGHT_CANNON", "SKILL_FIRE_MAG_SPARK_SHOT", "SKILL_FIRE_PHYS_FLAME_FIST"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_FIRE_ARMOR_CINDER_PLATE",
			"new_element": "SKILL_FIRE_PHYS_BLAZE_RUSH",
			"bounty": "SKILL_FIRE_ARMOR_FLAME_WALL",
		},
		"bounty_egg_skills": {"alpha_46": "SKILL_FIRE_MAG_FIREBALL"},
	},
	# Schwertflosser: Schwertfisch-Krieger mit langem Speer-Schnabel, Neben-Element Eis
	{
		"name": "47",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 13, "atk": 27, "def": 12, "s_atk": 14, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_PUNCH", "SKILL_WATER_PHYS_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_WATER_ARMOR_PLAIN", "SKILL_WATER_MAG_BUBBLE_BEAM", "SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_BUFF_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_WATER_BUFF_CURRENT",
			"boss_3": "SKILL_WATER_PHYS_TIDE_SLAP",
			"triple": "SKILL_WATER_MAG_HYDRO_LANCE",
		},
		"bounty_egg_skills": {"alpha_47": "SKILL_WATER_ARMOR_CORAL_WALL"},
	},
	# Korallenkönig: dicker Fischkönig mit Krone und Korallenzepter, Neben-Element Schlamm
	{
		"name": "48",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [190, 210],
		"preferred_stats": {"hp": 24, "atk": 10, "def": 16, "s_atk": 20, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BACKHAND", "SKILL_WATER_PHYS_TIDE_SLAP", "SKILL_WATER_MAG_BUBBLE_BEAM"],
		"milestone_egg_skills": {
			"finisher_1": "SKILL_WATER_ARMOR_SHELL",
			"new_element": "SKILL_WATER_MAG_HYDRO_LANCE",
			"boss_3": "SKILL_WATER_ARMOR_CORAL_WALL",
		},
		"bounty_egg_skills": {"alpha_48": "SKILL_WATER_PHYS_BREAKER"},
	},
	# Lohenteufel: Dämon aus glühendem Gestein in lodernden Flammen, Neben-Element Blitz
	{
		"name": "49",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE,  # Neben-Element Magma
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 12, "s_atk": 26, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_FIREBALL", "SKILL_FIRE_PHYS_FLAME_FIST", "SKILL_FIRE_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_MAG_FIREBALL_SWIFT", "SKILL_FIRE_BUFF_EMBER_HEAT", "SKILL_FIRE_BUFF_TEAM_S_ATK"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_MAGMA_PHYS_EMBER_KNUCKLE",
			"boss_4": "SKILL_MAGMA_MAG_LAVA_SPIT",
			"triple": "SKILL_PASSIVE_FIRE_POWER",
		},
		"bounty_egg_skills": {"alpha_49": "SKILL_MAGMA_ARMOR_PUMICE_SKIN"},
	},
	# Keulenschwanz: gepanzerte Urechse mit Hörnern und Stachelkeule am Schwanz, Neben-Element Schlamm
	{
		"name": "50",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 28, "s_atk": 6, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_EARTH_MAG_LIGHT_CANNON", "SKILL_EARTH_PHYS_BOULDER_BASH", "SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_BUFF_DEF"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_EARTH_BUFF_STONE_SKIN",
			"kills_10": "SKILL_EARTH_ARMOR_STONE_SKIN",
			"triple": "SKILL_EARTH_PHYS_QUAKE_STOMP",
		},
		"bounty_egg_skills": {"alpha_50": "SKILL_EARTH_MAG_GEO_PULSE"},
	},
	# Sonnensphinx: geflügelter Goldlöwe mit Krone, Neben-Elemente Staub und Blitz (mythisch, nur bei Bossen)
	{
		"name": "51",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Aschesturm
		"stats": [260, 280],
		"preferred_stats": {"hp": 16, "atk": 20, "def": 14, "s_atk": 22, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_MAG_TEMPEST_RAY_SWIFT"],
		"unlockable_egg_skills": ["SKILL_DUST_MAG_DUST_DEVIL", "SKILL_DUST_PHYS_SAND_CLAW", "SKILL_ASH_STORM_PHYS_ASHEN_ROLLER", "SKILL_CHAOS_BUFF_YIN_YANG"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_ASH_STORM_MAG_ASH_CYCLONE",
			"bounty": "SKILL_DUST_MAG_SANDSTORM",
			"triple": "SKILL_PASSIVE_DUST_T4",
		},
		"bounty_egg_skills": {"alpha_51": "SKILL_ASH_STORM_PHYS_CINDER_CLAW"},
	},
	# Strudeldrache: Seedrache, der Wasserstrudel um sich zieht
	{
		"name": "52",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Neben-Element Eis
		"stats": [230, 250],
		"preferred_stats": {"hp": 18, "atk": 16, "def": 14, "s_atk": 24, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_PHYS_TIDE_SLAP", "SKILL_WATER_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_MAG_HYDRO_LANCE_SWIFT", "SKILL_WATER_BUFF_BATTLE_FRENZY", "SKILL_CHAOS_BOON_COURAGE"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_ICE_PHYS_FROST_BITE",
			"boss_4": "SKILL_ICE_MAG_SNOW_FLURRY",
			"triple": "SKILL_PASSIVE_WATER_POWER",
		},
		"bounty_egg_skills": {"alpha_52": "SKILL_ICE_ARMOR_RIME_COAT"},
	},
	# Reifdrache: schlanker Himmelsdrache in Eisblau, Neben-Element Eis
	{
		"name": "53",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Neben-Element Eis
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 12, "def": 12, "s_atk": 26, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_PHYS_GUST_KICK", "SKILL_AIR_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_MAG_TEMPEST_RAY_SWIFT", "SKILL_AIR_BUFF_TAILWIND", "SKILL_CHAOS_BOON_COURAGE"],
		"milestone_egg_skills": {
			"finisher_2": "SKILL_ICE_PHYS_FROST_BITE",
			"kills_15": "SKILL_ICE_MAG_SNOW_FLURRY",
			"triple": "SKILL_PASSIVE_AIR_POWER",
		},
		"bounty_egg_skills": {"alpha_53": "SKILL_ICE_ARMOR_RIME_COAT"},
	},
	# Splitterkoloss: Felsbestie mit leuchtenden Kristalladern, Neben-Element Staub
	{
		"name": "54",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"stats": [215, 235],
		"preferred_stats": {"hp": 22, "atk": 18, "def": 24, "s_atk": 16, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_ARMOR_STONE_SKIN", "SKILL_EARTH_PHYS_PUNCH", "SKILL_EARTH_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_BUFF_EXTRA_SHIELD", "SKILL_PASSIVE_EARTH_POWER"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_EARTH_PHYS_BOULDER_BASH",
			"boss_4": "SKILL_DUST_PHYS_GRIT_PUNCH",
			"triple": "SKILL_DUST_ARMOR_SANDSTONE_SKIN",
		},
		"bounty_egg_skills": {"alpha_54": "SKILL_DUST_MAG_DUST_SHOT"},
	},
	# Stahlhai: gepanzerter Mecha-Hai auf vier Beinen mit Flossenschwanz, Neben-Element Dampf
	{
		"name": "55",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER,  # Neben-Element Dampf
		"stats": [215, 235],
		"preferred_stats": {"hp": 16, "atk": 26, "def": 24, "s_atk": 10, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_TIDE_SLAP", "SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_ARMOR_CORAL_WALL", "SKILL_WATER_BUFF_BATTLE_FRENZY", "SKILL_WATER_BUFF_ATK"],
		"milestone_egg_skills": {
			"finisher_2": "SKILL_WATER_ARMOR_SHELL",
			"boss_4": "SKILL_STEAM_ARMOR_STEAM_COAT",
			"triple": "SKILL_STEAM_PHYS_HOT_JAB",
		},
		"bounty_egg_skills": {"alpha_55": "SKILL_STEAM_MAG_VAPOR_PUFF"},
	},
	# Rochenklinge: Mantarochen-Krieger mit Muschelschwert, Neben-Element Eis
	{
		"name": "57",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER,  # Neben-Element Dampf
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 26, "def": 12, "s_atk": 16, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_TIDE_SLAP", "SKILL_WATER_MAG_CANNON", "SKILL_WATER_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_BUFF_BATTLE_FRENZY", "SKILL_WATER_BUFF_ATK"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_WATER_MAG_BUBBLE_BEAM",
			"flawless_3": "SKILL_STEAM_MAG_VAPOR_PUFF",
			"triple": "SKILL_STEAM_PHYS_HOT_JAB",
		},
		"bounty_egg_skills": {"alpha_57": "SKILL_STEAM_ARMOR_STEAM_COAT"},
	},
	# Sandseelen: Sandkoloss aus vielen gequälten Gesichtern, Neben-Element Staub
	{
		"name": "59",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 20, "atk": 14, "def": 16, "s_atk": 26, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_CANNON", "SKILL_EARTH_MAG_LIGHT_THRUST", "SKILL_EARTH_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_EARTH_PHYS_BACKHAND", "SKILL_EARTH_ARMOR_STONE_SKIN", "SKILL_EARTH_MAG_GEO_PULSE", "SKILL_EARTH_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_EARTH_BUFF_MOMENTUM",
			"finisher_2": "SKILL_EARTH_MAG_PEBBLE_STORM",
			"triple": "SKILL_EARTH_ARMOR_GRANITE_BASTION",
		},
		"bounty_egg_skills": {"alpha_59": "SKILL_EARTH_PHYS_QUAKE_STOMP"},
	},
	# Moorgeist: Moos- und Wurzelgespenst mit Totenschädel, Neben-Element Schlamm
	{
		"name": "60",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 12, "s_atk": 28, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_ARMOR_SHELL", "SKILL_WATER_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_WATER_ARMOR_CORAL_WALL", "SKILL_WATER_MAG_HYDRO_LANCE_SWIFT", "SKILL_WATER_BUFF_BATTLE_FRENZY", "SKILL_CHAOS_BOON_COURAGE"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_MUD_ARMOR_MUD_COAT",
			"finisher_3": "SKILL_MUD_MAG_SLUDGE_SHOT",
			"triple": "SKILL_PASSIVE_BULWARK_MASTER",
		},
		"bounty_egg_skills": {"alpha_60": "SKILL_MUD_PHYS_MUD_PUNCH"},
	},
	# Rankenrachen: Pflanzenbestie mit Giftflecken und triefendem Maul
	{
		"name": "61",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [230, 250],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 18, "s_atk": 14, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_ARMOR_STONE_SKIN", "SKILL_EARTH_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_PHYS_QUAKE_STOMP_SWIFT", "SKILL_EARTH_BUFF_EXTRA_CLUB", "SKILL_EARTH_BUFF_TEAM_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_MUD_ARMOR_MUD_COAT",
			"boss_4": "SKILL_MUD_PHYS_MUD_PUNCH",
			"triple": "SKILL_PASSIVE_BULWARK_MASTER",
		},
		"bounty_egg_skills": {"alpha_61": "SKILL_MUD_MAG_SLUDGE_SHOT"},
	},
	# Gewitterfürst: Sturmwesen aus Gewitterwolken und blitzenden Klauen (Wasser, Neben-Element Dampf)
	{
		"name": "62",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER,  # Neben-Element Dampf
		"affinity_triple": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Gewitter
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 18, "def": 12, "s_atk": 28, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_MAG_HYDRO_LANCE_SWIFT"],
		"unlockable_egg_skills": ["SKILL_STEAM_MAG_STEAM_JET", "SKILL_STEAM_PHYS_SCALD_STRIKE", "SKILL_STEAM_PHYS_STEAM_HAMMER", "SKILL_CHAOS_BUFF_YIN_YANG"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_THUNDERSTORM_MAG_STATIC_RAIN",
			"boss_4": "SKILL_THUNDERSTORM_MAG_CHAIN_LIGHTNING",
			"triple": "SKILL_PASSIVE_STEAM_T4",
		},
		"bounty_egg_skills": {"alpha_62": "SKILL_THUNDERSTORM_PHYS_SQUALL_STRIKE"},
	},
	# Spaltknochen: dreiäugiges Kristallskelett zwischen schwebenden Stein- und Zahnradsplittern, Neben-Element Staub
	{
		"name": "63",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 14, "def": 12, "s_atk": 24, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_CANNON", "SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_PHYS_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_AIR_ARMOR_PLAIN", "SKILL_AIR_PHYS_GUST_KICK", "SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_AIR_BUFF_UPDRAFT",
			"flawless_2": "SKILL_AIR_MAG_WIND_BLADE",
			"triple": "SKILL_AIR_PHYS_CYCLONE_CLAW",
		},
		"bounty_egg_skills": {"alpha_63": "SKILL_AIR_ARMOR_GALE_WALL"},
	},
	# Frostklumpen: runder Eisschleim mit Kristallstacheln und -klauen, Neben-Element Eis
	{
		"name": "64",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 20, "atk": 12, "def": 18, "s_atk": 22, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BACKHAND", "SKILL_WATER_PHYS_TIDE_SLAP", "SKILL_WATER_MAG_BUBBLE_BEAM"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_WATER_ARMOR_SHELL",
			"flawless_2": "SKILL_WATER_MAG_HYDRO_LANCE",
			"triple": "SKILL_WATER_ARMOR_CORAL_WALL",
		},
		"bounty_egg_skills": {"alpha_64": "SKILL_WATER_PHYS_BREAKER"},
	},
	# Kristallschlund: dunkle Bestie mit eisblauen Kristallen auf dem Rücken
	{
		"name": "66",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR,  # Neben-Element Staub
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 24, "s_atk": 10, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_BOULDER_BASH", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_PHYS_SMALL_PUNCH"],
		"unlockable_egg_skills": ["SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_BUFF_BATTLE_FRENZY", "SKILL_EARTH_BUFF_ATK"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_EARTH_ARMOR_STONE_SKIN",
			"boss_4": "SKILL_DUST_ARMOR_SANDSTONE_SKIN",
			"triple": "SKILL_DUST_PHYS_GRIT_PUNCH",
		},
		"bounty_egg_skills": {"alpha_66": "SKILL_DUST_MAG_DUST_SHOT"},
	},
	# Sandgolem: Riese aus festgebackenem Sand, um den Staub wirbelt
	{
		"name": "67",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 26, "s_atk": 8, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_WEAK_THRUST", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_MAG_WEAK_THRUST"],
		"unlockable_egg_skills": ["SKILL_EARTH_MAG_LIGHT_CANNON", "SKILL_EARTH_MAG_PEBBLE_STORM", "SKILL_EARTH_ARMOR_STONE_SKIN"],
		"milestone_egg_skills": {
			"finisher_1": "SKILL_EARTH_PHYS_BOULDER_BASH",
			"new_element": "SKILL_EARTH_ARMOR_GRANITE_BASTION",
			"flawless_2": "SKILL_EARTH_PHYS_QUAKE_STOMP",
		},
		"bounty_egg_skills": {"alpha_67": "SKILL_EARTH_MAG_GEO_PULSE"},
	},
	# Glutkerker: Lavagestein-Käfig mit glühendem Feuerkern
	{
		"name": "68",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE,  # Neben-Element Magma
		"stats": [230, 250],
		"preferred_stats": {"hp": 18, "atk": 16, "def": 22, "s_atk": 26, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_FIREBALL", "SKILL_FIRE_ARMOR_CINDER_PLATE", "SKILL_FIRE_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_FIRE_ARMOR_FLAME_WALL", "SKILL_FIRE_MAG_FIREBALL_SWIFT", "SKILL_FIRE_BUFF_EMBER_HEAT", "SKILL_FIRE_BUFF_TEAM_S_ATK"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_MAGMA_ARMOR_PUMICE_SKIN",
			"boss_4": "SKILL_MAGMA_MAG_LAVA_SPIT",
			"triple": "SKILL_PASSIVE_FIRE_POWER",
		},
		"bounty_egg_skills": {"alpha_68": "SKILL_MAGMA_PHYS_EMBER_KNUCKLE"},
	},
	# Lichtweber: schwebender Lichtgeist aus verflochtenen goldenen Ranken
	{
		"name": "69",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Neben-Element Eis
		"affinity_triple": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Gewitter
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 8, "def": 12, "s_atk": 28, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_ARMOR_GALE_WALL", "SKILL_AIR_MAG_TEMPEST_RAY_SWIFT"],
		"unlockable_egg_skills": ["SKILL_ICE_MAG_FROST_RAY", "SKILL_ICE_ARMOR_ICE_PLATE", "SKILL_ICE_MAG_BLIZZARD", "SKILL_CHAOS_BUFF_YIN_YANG"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_THUNDERSTORM_MAG_STATIC_RAIN",
			"kills_15": "SKILL_THUNDERSTORM_MAG_CHAIN_LIGHTNING",
			"triple": "SKILL_PASSIVE_ICE_T4",
		},
		"bounty_egg_skills": {"alpha_69": "SKILL_THUNDERSTORM_ARMOR_RAIN_GUARD"},
	},
	# Scherenhorn: grüner Panzerkäfer mit rosa Riesenschere und Hornstachel
	{
		"name": "70",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 18, "atk": 26, "def": 22, "s_atk": 10, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_PUNCH", "SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_EARTH_MAG_LIGHT_CANNON", "SKILL_EARTH_ARMOR_STONE_SKIN", "SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_BUFF_ATK"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_EARTH_BUFF_FIGHTING_SPIRIT",
			"flawless_2": "SKILL_EARTH_PHYS_BOULDER_BASH",
			"triple": "SKILL_EARTH_ARMOR_GRANITE_BASTION",
		},
		"bounty_egg_skills": {"alpha_70": "SKILL_EARTH_MAG_GEO_PULSE"},
	},
	# Sonnenwächter: silberner Ritter mit Sonnenring und Flammenhand (mythisch, nur bei Bossen)
	{
		"name": "71",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR,  # Neben-Element Blitz
		"affinity_triple": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Gewitter
		"stats": [260, 280],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 20, "s_atk": 18, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_ARMOR_FLAME_WALL", "SKILL_FIRE_PHYS_BLAZE_RUSH_SWIFT"],
		"unlockable_egg_skills": ["SKILL_LIGHTNING_PHYS_VOLT_PUNCH", "SKILL_LIGHTNING_ARMOR_STATIC_PLATE", "SKILL_THUNDERSTORM_MAG_SKYFALL", "SKILL_CHAOS_BOON_RESPECT_SLAP"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_THUNDERSTORM_PHYS_STORM_FIST",
			"boss_4": "SKILL_LIGHTNING_MAG_THUNDERCLAP",
			"triple": "SKILL_PASSIVE_DENSE_CLOUDS",
		},
		"bounty_egg_skills": {"alpha_71": "SKILL_THUNDERSTORM_ARMOR_STORM_PLATE"},
	},
	# Piñatadrache: bunter Papierdrache, der Konfetti verstreut
	{
		"name": "72",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.AIR,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR,  # Neben-Element Blitz
		"stats": [215, 235],
		"preferred_stats": {"hp": 18, "atk": 18, "def": 14, "s_atk": 20, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_WIND_BLADE", "SKILL_AIR_PHYS_PUNCH", "SKILL_AIR_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_PHYS_CYCLONE_CLAW", "SKILL_AIR_BUFF_BATTLE_FRENZY", "SKILL_AIR_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_AIR_PHYS_GUST_KICK",
			"boss_4": "SKILL_LIGHTNING_PHYS_SHOCK_TAP",
			"triple": "SKILL_LIGHTNING_MAG_SPARK_BOLT",
		},
		"bounty_egg_skills": {"alpha_72": "SKILL_LIGHTNING_ARMOR_CHARGE_PLATE"},
	},
	# Moorschrecken: gehörnter Sumpfdämon mit Moos- und Algenpanzer (mythisch, nur bei Bossen)
	{
		"name": "73",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Dreier-Kombi Sumpf
		"stats": [260, 280],
		"preferred_stats": {"hp": 18, "atk": 26, "def": 16, "s_atk": 18, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_QUAKE_STOMP", "SKILL_EARTH_MAG_GEO_PULSE", "SKILL_EARTH_PHYS_QUAKE_STOMP_SWIFT"],
		"unlockable_egg_skills": ["SKILL_MUD_PHYS_MUD_SLAM", "SKILL_MUD_MAG_BOG_PULSE", "SKILL_SWAMP_MAG_BOG_MAW", "SKILL_CHAOS_BOON_RESPECT_SLAP"],
		"milestone_egg_skills": {
			"finisher_2": "SKILL_SWAMP_PHYS_ROOT_LASH",
			"bounty": "SKILL_MUD_ARMOR_LANDSLIDE_WALL",
			"triple": "SKILL_PASSIVE_SWAMP_FIELD",
		},
		"bounty_egg_skills": {"alpha_73": "SKILL_SWAMP_MAG_MIASMA_CLOUD"},
	},
	# Blattfee: Ahornblatt-Fee mit gläsernen Flügeln
	{
		"name": "74",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 12, "s_atk": 24, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_AIR_PHYS_BACKHAND", "SKILL_AIR_PHYS_GUST_KICK", "SKILL_AIR_MAG_WIND_BLADE"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_AIR_ARMOR_DRAFT_GUARD",
			"finisher_2": "SKILL_AIR_MAG_TEMPEST_RAY",
			"triple": "SKILL_AIR_ARMOR_GALE_WALL",
		},
		"bounty_egg_skills": {"alpha_74": "SKILL_AIR_PHYS_CYCLONE_CLAW"},
	},
	# Irrflamme: kleines türkisfarbenes Irrlicht
	{
		"name": "75",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 10, "s_atk": 26, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
		"unlockable_egg_skills": ["SKILL_FIRE_ARMOR_PLAIN", "SKILL_FIRE_ARMOR_CINDER_PLATE", "SKILL_FIRE_MAG_SPARK_SHOT"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_FIRE_PHYS_FLAME_FIST",
			"bounty": "SKILL_FIRE_MAG_FIREBALL",
			"triple": "SKILL_FIRE_PHYS_BLAZE_RUSH",
		},
		"bounty_egg_skills": {"alpha_75": "SKILL_FIRE_ARMOR_FLAME_WALL"},
	},
	# Glühzirpe: goldener Leuchtkäfer mit langen Fühlern
	{
		"name": "76",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 12, "def": 12, "s_atk": 22, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_CANNON", "SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_PHYS_LIGHT_STRIKE"],
		"unlockable_egg_skills": ["SKILL_AIR_ARMOR_PLAIN", "SKILL_AIR_PHYS_GUST_KICK", "SKILL_AIR_MAG_TEMPEST_RAY", "SKILL_AIR_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_AIR_BUFF_FIGHTING_SPIRIT",
			"new_element": "SKILL_AIR_MAG_WIND_BLADE",
			"finisher_2": "SKILL_AIR_PHYS_CYCLONE_CLAW",
		},
		"bounty_egg_skills": {"alpha_76": "SKILL_AIR_ARMOR_GALE_WALL"},
	},
	# Phönixglut: Feuerkugel in einem Wirbel aus Phönixflammen
	{
		"name": "77",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR,  # Neben-Element Blitz
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 12, "def": 10, "s_atk": 28, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_FIREBALL", "SKILL_FIRE_PHYS_FLAME_FIST", "SKILL_FIRE_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_FIRE_PHYS_BLAZE_RUSH", "SKILL_FIRE_MAG_FIREBALL_SWIFT", "SKILL_FIRE_BUFF_EMBER_HEAT", "SKILL_FIRE_BUFF_TEAM_S_ATK"],
		"milestone_egg_skills": {
			"flawless_1": "SKILL_LIGHTNING_PHYS_SHOCK_TAP",
			"boss_4": "SKILL_LIGHTNING_MAG_SPARK_BOLT",
			"triple": "SKILL_PASSIVE_STORM_SPIRIT",
		},
		"bounty_egg_skills": {"alpha_77": "SKILL_LIGHTNING_ARMOR_CHARGE_PLATE"},
	},
	# Denkwurzel: riesiges Gehirn auf einem knorrigen Wurzelstamm
	{
		"name": "78",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"affinity": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER,  # Neben-Element Schlamm
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 6, "def": 16, "s_atk": 28, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_PEBBLE_STORM", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_MAG_SMALL_CANNON"],
		"unlockable_egg_skills": ["SKILL_EARTH_MAG_GEO_PULSE", "SKILL_EARTH_ARMOR_GRANITE_BASTION", "SKILL_EARTH_BUFF_BATTLE_FRENZY", "SKILL_EARTH_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_EARTH_ARMOR_STONE_SKIN",
			"finisher_3": "SKILL_MUD_ARMOR_MUD_COAT",
			"triple": "SKILL_MUD_MAG_SLUDGE_SHOT",
		},
		"bounty_egg_skills": {"alpha_78": "SKILL_MUD_PHYS_MUD_PUNCH"},
	},
	# Seherdämon: gehörnter Dämon mit Augenstab und Schlange (mythisch, nur bei Bossen)
	{
		"name": "79",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Neben-Element Eis
		"affinity_triple": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER,  # Dreier-Kombi Sumpf
		"stats": [260, 280],
		"preferred_stats": {"hp": 18, "atk": 16, "def": 14, "s_atk": 26, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_MAG_HYDRO_LANCE_SWIFT"],
		"unlockable_egg_skills": ["SKILL_ICE_MAG_FROST_RAY", "SKILL_ICE_PHYS_ICICLE_JAB", "SKILL_SWAMP_MAG_BOG_MAW", "SKILL_CHAOS_BUFF_YIN_YANG"],
		"milestone_egg_skills": {
			"kills_8": "SKILL_SWAMP_MAG_MIASMA_CLOUD",
			"boss_4": "SKILL_ICE_MAG_BLIZZARD",
			"triple": "SKILL_PASSIVE_SWAMP_FIELD",
		},
		"bounty_egg_skills": {"alpha_79": "SKILL_SWAMP_PHYS_ROOT_LASH"},
	},
	# Gezeitenritter: Ritter in perlweißer Rüstung mit rotem Helmbusch und leuchtendem Dreizack, Neben-Element Dampf
	# (mythisch, nur bei Bossen)
	{
		"name": "85",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"affinity": Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER,  # Neben-Element Dampf
		"affinity_triple": Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE,  # Dreier-Kombi Gewitter
		"stats": [260, 280],
		"preferred_stats": {"hp": 16, "atk": 26, "def": 18, "s_atk": 14, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_BREAKER", "SKILL_WATER_ARMOR_CORAL_WALL", "SKILL_WATER_PHYS_BREAKER_SWIFT"],
		"unlockable_egg_skills": ["SKILL_STEAM_PHYS_SCALD_STRIKE", "SKILL_STEAM_ARMOR_VAPOR_PLATE", "SKILL_THUNDERSTORM_MAG_SKYFALL", "SKILL_CHAOS_BOON_RESPECT_SLAP"],
		"milestone_egg_skills": {
			"boss_2": "SKILL_THUNDERSTORM_PHYS_STORM_FIST",
			"boss_4": "SKILL_STEAM_PHYS_STEAM_HAMMER",
			"triple": "SKILL_PASSIVE_DENSE_CLOUDS",
		},
		"bounty_egg_skills": {"alpha_85": "SKILL_THUNDERSTORM_ARMOR_STORM_PLATE"},
	},
	# Strudelseele: blaue Seelenkugel mit schwarzen Flammen und Wasserwirbeln
	{
		"name": "80",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 10, "def": 14, "s_atk": 24, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_CANNON", "SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_ARMOR_LIGHT"],
		"unlockable_egg_skills": ["SKILL_WATER_PHYS_BACKHAND", "SKILL_WATER_ARMOR_SHELL", "SKILL_WATER_MAG_HYDRO_LANCE", "SKILL_WATER_BUFF_S_ATK"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_WATER_BUFF_FIGHTING_SPIRIT",
			"boss_3": "SKILL_WATER_MAG_BUBBLE_BEAM",
			"triple": "SKILL_WATER_ARMOR_CORAL_WALL",
		},
		"bounty_egg_skills": {"alpha_80": "SKILL_WATER_PHYS_BREAKER"},
	},
	# Panzerspinne: mechanische Spinne mit grün leuchtenden Adern
	{
		"name": "81",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 26, "s_atk": 10, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_WEAK_THRUST", "SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_MAG_WEAK_THRUST"],
		"unlockable_egg_skills": ["SKILL_WATER_MAG_LIGHT_CANNON", "SKILL_WATER_MAG_BUBBLE_BEAM", "SKILL_WATER_ARMOR_SHELL"],
		"milestone_egg_skills": {
			"boss_1": "SKILL_WATER_PHYS_TIDE_SLAP",
			"new_element": "SKILL_WATER_ARMOR_CORAL_WALL",
			"boss_3": "SKILL_WATER_PHYS_BREAKER",
		},
		"bounty_egg_skills": {"alpha_81": "SKILL_WATER_MAG_HYDRO_LANCE"},
	},
	# Mooswürfel: bemooster Grasblock mit Knopfaugen, Startmonster (Tank)
	{
		"name": "82",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 22, "atk": 8, "def": 20, "s_atk": 14, "speed": 8},
		"max_upgrades": 2,
		# Eigene Start-Skills: Moospuls (magisch), Leichter Steinschild, Moosstoß (physisch),
		# als Startmonster durch Fangen & Opfern: Schild (Vert.) und Leichte Erdkanone
		"default_egg_skills": ["SKILL_EARTH_MAG_STARTER_PULSE", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_PHYS_STARTER_JAB"],
		"unlockable_egg_skills": ["SKILL_EARTH_ARMOR_PLAIN", "SKILL_EARTH_MAG_LIGHT_CANNON"],
		"milestone_egg_skills": {
			"kills_5": "SKILL_EARTH_MAG_PEBBLE_STORM",
			"kills_10": "SKILL_EARTH_ARMOR_GRANITE_BASTION",
			"triple": "SKILL_EARTH_MAG_GEO_PULSE",
		},
		"bounty_egg_skills": {"alpha_82": "SKILL_EARTH_PHYS_QUAKE_STOMP"},
	},
	# Weltenfresser: gehörnte Schattenwolke mit Reißzähnen und Rauchranken, Endboss des Runs (Chaos, alle vier Elemente).
	# final_boss: taucht weder wild noch als normaler Boss auf, nur als Hauptgegner im Boss-Kampf des letzten Bioms
	# (Map.roll_boss_enemies). Im Endboss-Kampf kann nicht gefangen werden.
	{
		"name": "84",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER | Enums.MON_TYPES.AIR,
		"final_boss": true,
		"skills_manual": true,
		"stats": [285, 305],
		"preferred_stats": {"hp": 22, "atk": 18, "def": 14, "s_atk": 24, "speed": 8},
		"max_upgrades": 2,
		# Sp. Ang. am höchsten, eine Basis-Attacke je Element
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_WATER_MAG_LIGHT_THRUST",
			"SKILL_EARTH_ARMOR_WEAK"],
	},
]
