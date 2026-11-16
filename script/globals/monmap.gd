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
		# default_egg_skills = Start-Skills (Skills.starter_skills) im Element der Art, nach ihrem höchsten Kampfwert
		# (Gleichstand: Ang. vor Sp. Ang. vor Vert. vor Sp. Vert.):
		#   Ang.: Leichter Stoß, Leichter Schlag, Nutzloser Schild (Rüstung)
		#   Sp. Ang.: dasselbe magisch, Nutzloser Magie-Schild
		#   Vert.: Nutzloser Stoß, Leichter Schild (Rüstung), Nutzloser Magie-Schild
		#   Sp. Vert.: Nutzloser Stoß, Leichter Magie-Schild, Nutzloser Schild (Rüstung)
		#   Nutzloser Stoß ist magisch, wenn Sp. Ang. höher als Ang. ist.
		# Optional, vorerst leer: unlockable_egg_skills (durch Opfern), milestone_egg_skills (Skills.MILESTONES),
		# bounty_egg_skills (Skills.BOUNTIES)
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Leuchtkrabbe: Krabbe mit Leuchtturm auf dem Panzer
	{
		"name": "2",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 14, "def": 25, "s_atk": 14, "s_def": 19, "speed": 10},
		"max_upgrades": 2,
		# Startmonster (Tank): zusätzlich Leichter Wasserschild (Sp. Vert., ergänzt den Muschelschild) und Leichte Rückhand
		"default_egg_skills": ["SKILL_WATER_PHYS_WEAK_THRUST", "SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_WARD_WEAK",
			"SKILL_WATER_WARD_PLAIN", "SKILL_WATER_PHYS_BACKHAND"],
	},
	# Schattflaum: Federgeist aus violettem Rauch
	{
		"name": "3",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 8, "def": 12, "s_atk": 27, "s_def": 21, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Hackschupp: Echse mit Beil und Schuppenpanzer
	{
		"name": "4",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 16, "atk": 27, "def": 22, "s_atk": 8, "s_def": 12, "speed": 15},
		"max_upgrades": 2,
		# Startmonster (Angreifer): zusätzlich Kleiner Punch und Punch
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK",
			"SKILL_FIRE_PHYS_SMALL_PUNCH", "SKILL_FIRE_PHYS_PUNCH"],
	},
	# Glotzlibelle: Libelle mit Stielaugen
	{
		"name": "5",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 13, "atk": 18, "def": 11, "s_atk": 20, "s_def": 14, "speed": 24},
		"max_upgrades": 2,
		# Startmonster (Angreifer): zusätzlich Kleine Windkanone und Windkanone
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK",
			"SKILL_AIR_MAG_SMALL_CANNON", "SKILL_AIR_MAG_CANNON"],
	},
	# Borkenhieb: Baumkrieger mit zwei Runenäxten
	{
		"name": "6",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 19, "atk": 28, "def": 20, "s_atk": 7, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Hainschwestern: vier Baumfeen unter einer Krone
	{
		"name": "7",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 17, "atk": 8, "def": 14, "s_atk": 25, "s_def": 24, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_LIGHT_THRUST", "SKILL_EARTH_MAG_LIGHT_STRIKE", "SKILL_EARTH_WARD_WEAK"],
	},
	# Glutmolch: Lavamolch mit brennendem Schwanz
	{
		"name": "8",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 17, "atk": 16, "def": 15, "s_atk": 24, "s_def": 14, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_WARD_WEAK"],
	},
	# Quallolotl: Gallert-Axolotl mit Wasserbauch und Quallententakeln
	{
		"name": "9",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 24, "atk": 10, "def": 14, "s_atk": 20, "s_def": 22, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_WEAK_THRUST", "SKILL_WATER_WARD_LIGHT", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Glutkoloss: Lavagolem mit glühendem Kern und Felsfäusten
	{
		"name": "10",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 24, "atk": 26, "def": 24, "s_atk": 8, "s_def": 10, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Wolkenkauz: Wolkeneule auf einem kleinen Wirbelsturm
	{
		"name": "11",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 15, "atk": 10, "def": 12, "s_atk": 24, "s_def": 19, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Sturmgreif: Greif mit Blitzschwingen und Wirbelsturmschweifen
	{
		"name": "12",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [230, 250],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 12, "s_atk": 22, "s_def": 10, "speed": 19},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_LIGHT_THRUST", "SKILL_AIR_PHYS_LIGHT_STRIKE", "SKILL_AIR_ARMOR_WEAK"],
	},
	# Kristallwühler: Felsbestie mit Bernsteinkristallen auf dem Rücken
	{
		"name": "13",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 27, "s_atk": 6, "s_def": 15, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_WEAK_THRUST", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_WARD_WEAK"],
	},
	# Frostfähe: Eisfüchsin mit kristallenen Schweifen
	{
		"name": "14",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 20, "def": 12, "s_atk": 20, "s_def": 14, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_LIGHT_THRUST", "SKILL_WATER_PHYS_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Nebelspuk: Nebelgeist mit Dunstschwaden und violetten Augen, Luftwesen
	{
		"name": "15",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 6, "def": 14, "s_atk": 26, "s_def": 24, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Funkenigel: Igel mit elektrisch geladenen Stacheln
	{
		"name": "16",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 14, "def": 22, "s_atk": 22, "s_def": 10, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_WARD_WEAK"],
	},
	# Glutskorpion: Lavaskorpion mit brennendem Stachel (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "17",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 22, "s_atk": 14, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Dünenhorn: Sandkäfer mit Bernsteinhörnern (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "18",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 15, "atk": 22, "def": 18, "s_atk": 10, "s_def": 13, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Reifwolf: Eiswolf mit Kristallmähne (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "19",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 24, "def": 12, "s_atk": 18, "s_def": 12, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_LIGHT_THRUST", "SKILL_WATER_PHYS_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Dampfhorn: Steinstier mit Dampfwolken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "20",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 22, "atk": 14, "def": 22, "s_atk": 18, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_WEAK_THRUST", "SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_WARD_WEAK"],
	},
	# Dünenstachler: Sandskorpion im Staubwirbel, flinker physischer Angreifer mit Scheren und Giftstachel, Neben-Element Staub
	{
		"name": "21",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 26, "def": 16, "s_atk": 8, "s_def": 12, "speed": 24},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Schlammschlund: Moorkröte mit Wurzelschwanz, Erdwesen (Platzhalter: Werte folgen beim Balancing)
	{
		"name": "22",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 24, "atk": 18, "def": 18, "s_atk": 12, "s_def": 18, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Aschrücken: Magmaechse mit Lavaschwanz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "23",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 22, "s_atk": 12, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Voltkäfer: Panzerkäfer unter Strom (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "24",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 24, "s_atk": 14, "s_def": 12, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_WEAK_THRUST", "SKILL_AIR_ARMOR_LIGHT", "SKILL_AIR_WARD_WEAK"],
	},
	# Moorpanzer: uralte Sumpfschildkröte mit Teich auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "25",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 26, "atk": 14, "def": 26, "s_atk": 12, "s_def": 16, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_WEAK_THRUST", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_WARD_WEAK"],
	},
	# Aschwirbel: Rauchgeist im Glutsturm (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "26",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 10, "def": 12, "s_atk": 26, "s_def": 18, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Donnerhorn: gehörnte Gewitterwolke (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "27",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [215, 235],
		"preferred_stats": {"hp": 16, "atk": 12, "def": 14, "s_atk": 26, "s_def": 18, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Dünenbrecher: Sandsteinnashorn (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "28",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 20, "atk": 28, "def": 24, "s_atk": 6, "s_def": 12, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Sturmdschinn: gepanzerter Wirbelsturm mit Blitzklauen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "29",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 16, "def": 12, "s_atk": 26, "s_def": 14, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Vulkanfaust: Vulkangolem mit Lavafäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "30",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 28, "def": 22, "s_atk": 8, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Staubkönig: gekrönter Sandgeist mit rotem Herz (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "31",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 14, "s_atk": 26, "s_def": 20, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_LIGHT_THRUST", "SKILL_EARTH_MAG_LIGHT_STRIKE", "SKILL_EARTH_WARD_WEAK"],
	},
	# Blutmähne: Mantikor mit Runenpanzer (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "33",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [260, 280],
		"preferred_stats": {"hp": 16, "atk": 26, "def": 16, "s_atk": 12, "s_def": 12, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Leerwurm: Schuppenwyrm mit violetten Flammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "35",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [260, 280],
		"preferred_stats": {"hp": 14, "atk": 16, "def": 12, "s_atk": 24, "s_def": 16, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Staubgreifer: Sandgeist mit Steinklingen an langen Ranken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "36",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 12, "atk": 22, "def": 12, "s_atk": 16, "s_def": 14, "speed": 24},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Mooskoloss: Baumriese aus Moos und Wurzeln mit Kristallkrone (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "37",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 24, "atk": 16, "def": 18, "s_atk": 18, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_LIGHT_THRUST", "SKILL_EARTH_MAG_LIGHT_STRIKE", "SKILL_EARTH_WARD_WEAK"],
	},
	# Gorgonatter: Riesenschlange mit Schlangenhaupt (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "38",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [245, 265],
		"preferred_stats": {"hp": 15, "atk": 14, "def": 13, "s_atk": 26, "s_def": 16, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_WARD_WEAK"],
	},
	# Frostgürtler: Gürteltier aus Eisplatten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "39",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 20, "def": 28, "s_atk": 8, "s_def": 16, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_WEAK_THRUST", "SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_WARD_WEAK"],
	},
	# Runenskarab: gekrönter Käfer mit Runenpanzer und Geisterflammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "40",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [230, 250],
		"preferred_stats": {"hp": 16, "atk": 22, "def": 22, "s_atk": 14, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Glutroller: eingerollte Lavakugel auf Steinfüßen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "41",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 20, "def": 22, "s_atk": 14, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_WEAK_THRUST", "SKILL_FIRE_ARMOR_LIGHT", "SKILL_FIRE_WARD_WEAK"],
	},
	# Smogfaust: Giftwolke mit zwei Riesenfäusten (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "42",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 14, "s_atk": 16, "s_def": 14, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_PHYS_LIGHT_THRUST", "SKILL_AIR_PHYS_LIGHT_STRIKE", "SKILL_AIR_ARMOR_WEAK"],
	},
	# Knochenschläger: Skelettkrieger mit Morgenstern in violetten Flammen (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "43",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [215, 235],
		"preferred_stats": {"hp": 13, "atk": 27, "def": 12, "s_atk": 14, "s_def": 12, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Vulkanpanzer: Schildkröte mit rauchendem Vulkan auf dem Rücken (Platzhalter: Typ, Werte und Attacken folgen beim Balancing)
	{
		"name": "45",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 22, "atk": 18, "def": 26, "s_atk": 18, "s_def": 10, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_WEAK_THRUST", "SKILL_FIRE_ARMOR_LIGHT", "SKILL_FIRE_WARD_WEAK"],
	},
	# Glutechse: Echse mit Lavagestein-Haut und Flammenkamm, Neben-Element Magma
	{
		"name": "46",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 18, "atk": 24, "def": 22, "s_atk": 12, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Schwertflosser: Schwertfisch-Krieger mit langem Speer-Schnabel, Neben-Element Eis
	{
		"name": "47",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 13, "atk": 27, "def": 12, "s_atk": 14, "s_def": 12, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_LIGHT_THRUST", "SKILL_WATER_PHYS_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Korallenkönig: dicker Fischkönig mit Krone und Korallenzepter, Neben-Element Schlamm
	{
		"name": "48",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 24, "atk": 10, "def": 16, "s_atk": 20, "s_def": 22, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_WEAK_THRUST", "SKILL_WATER_WARD_LIGHT", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Lohenteufel: Dämon aus glühendem Gestein in lodernden Flammen, Neben-Element Blitz
	{
		"name": "49",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 22, "def": 12, "s_atk": 26, "s_def": 12, "speed": 14},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_WARD_WEAK"],
	},
	# Keulenschwanz: gepanzerte Urechse mit Hörnern und Stachelkeule am Schwanz, Neben-Element Schlamm
	{
		"name": "50",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 28, "s_atk": 6, "s_def": 14, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_WEAK_THRUST", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_WARD_WEAK"],
	},
	# Sonnensphinx: geflügelter Goldlöwe mit Krone, Neben-Elemente Staub und Blitz
	{
		"name": "51",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [245, 265],
		"preferred_stats": {"hp": 16, "atk": 20, "def": 14, "s_atk": 22, "s_def": 16, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Strudeldrache: Seedrache, der Wasserstrudel um sich zieht (mythisch, nur bei Bossen)
	{
		"name": "52",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [260, 280],
		"preferred_stats": {"hp": 18, "atk": 16, "def": 14, "s_atk": 24, "s_def": 16, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_WARD_WEAK"],
	},
	# Reifdrache: schlanker Himmelsdrache in Eisblau, Neben-Element Eis
	{
		"name": "53",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 12, "def": 12, "s_atk": 26, "s_def": 18, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Splitterkoloss: Felsbestie mit leuchtenden Kristalladern, Neben-Element Staub
	{
		"name": "54",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 22, "atk": 18, "def": 24, "s_atk": 16, "s_def": 14, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_WEAK_THRUST", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_WARD_WEAK"],
	},
	# Stahlhai: gepanzerter Mecha-Hai auf vier Beinen mit Flossenschwanz, Neben-Element Dampf
	{
		"name": "55",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 16, "atk": 26, "def": 24, "s_atk": 10, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_LIGHT_THRUST", "SKILL_WATER_PHYS_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Spukhütte: morsche, von Ranken überwucherte Hütte auf Wurzelbeinen, Neben-Element Schlamm
	{
		"name": "56",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 22, "atk": 14, "def": 26, "s_atk": 18, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_WEAK_THRUST", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_WARD_WEAK"],
	},
	# Rochenklinge: Mantarochen-Krieger mit Muschelschwert, Neben-Element Eis
	{
		"name": "57",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [215, 235],
		"preferred_stats": {"hp": 14, "atk": 26, "def": 12, "s_atk": 16, "s_def": 12, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_LIGHT_THRUST", "SKILL_WATER_PHYS_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Schattenreißer: dunkler Dämon mit Schädelmaske und glühend roten Adern, Neben-Elemente Magma und Blitz
	{
		"name": "58",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 16, "atk": 28, "def": 14, "s_atk": 18, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Sandseelen: Sandkoloss aus vielen gequälten Gesichtern, Neben-Element Staub
	{
		"name": "59",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 20, "atk": 14, "def": 16, "s_atk": 26, "s_def": 14, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_LIGHT_THRUST", "SKILL_EARTH_MAG_LIGHT_STRIKE", "SKILL_EARTH_WARD_WEAK"],
	},
	# Moorgeist: Moos- und Wurzelgespenst mit Totenschädel, Neben-Element Schlamm
	{
		"name": "60",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 12, "s_atk": 28, "s_def": 20, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_WARD_WEAK"],
	},
	# Rankenrachen: Pflanzenbestie mit Giftflecken und triefendem Maul (mythisch, nur bei Bossen)
	{
		"name": "61",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [260, 280],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 18, "s_atk": 14, "s_def": 12, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Gewitterfürst: Sturmwesen aus Gewitterwolken und blitzenden Klauen, Neben-Elemente Blitz und Eis
	{
		"name": "62",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 18, "def": 12, "s_atk": 28, "s_def": 12, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Spaltknochen: dreiäugiges Kristallskelett zwischen schwebenden Stein- und Zahnradsplittern, Neben-Element Staub
	{
		"name": "63",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 14, "def": 12, "s_atk": 24, "s_def": 18, "speed": 18},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Frostklumpen: runder Eisschleim mit Kristallstacheln und -klauen, Neben-Element Eis
	{
		"name": "64",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 20, "atk": 12, "def": 18, "s_atk": 22, "s_def": 16, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_WARD_WEAK"],
	},
	# Kristallschlund: dunkle Bestie mit eisblauen Kristallen auf dem Rücken
	{
		"name": "66",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 26, "def": 24, "s_atk": 10, "s_def": 12, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Sandgolem: Riese aus festgebackenem Sand, um den Staub wirbelt
	{
		"name": "67",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 22, "atk": 22, "def": 26, "s_atk": 8, "s_def": 12, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_WEAK_THRUST", "SKILL_EARTH_ARMOR_LIGHT", "SKILL_EARTH_WARD_WEAK"],
	},
	# Glutkerker: Lavagestein-Käfig mit glühendem Feuerkern
	{
		"name": "68",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [230, 250],
		"preferred_stats": {"hp": 18, "atk": 16, "def": 22, "s_atk": 26, "s_def": 12, "speed": 6},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_WARD_WEAK"],
	},
	# Lichtweber: schwebender Lichtgeist aus verflochtenen goldenen Ranken
	{
		"name": "69",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [245, 265],
		"preferred_stats": {"hp": 14, "atk": 8, "def": 12, "s_atk": 28, "s_def": 22, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Scherenhorn: grüner Panzerkäfer mit rosa Riesenschere und Hornstachel
	{
		"name": "70",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [200, 220],
		"preferred_stats": {"hp": 18, "atk": 26, "def": 22, "s_atk": 10, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_PHYS_LIGHT_THRUST", "SKILL_EARTH_PHYS_LIGHT_STRIKE", "SKILL_EARTH_ARMOR_WEAK"],
	},
	# Sonnenwächter: silberner Ritter mit Sonnenring und Flammenhand
	{
		"name": "71",
		"rarity": Enums.MON_RARITY.LEGENDARY,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [245, 265],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 20, "s_atk": 18, "s_def": 14, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_PHYS_LIGHT_THRUST", "SKILL_FIRE_PHYS_LIGHT_STRIKE", "SKILL_FIRE_ARMOR_WEAK"],
	},
	# Piñatadrache: bunter Papierdrache, der Konfetti verstreut
	{
		"name": "72",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [215, 235],
		"preferred_stats": {"hp": 18, "atk": 18, "def": 14, "s_atk": 20, "s_def": 14, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Moorschrecken: gehörnter Sumpfdämon mit Moos- und Algenpanzer
	{
		"name": "73",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [230, 250],
		"preferred_stats": {"hp": 18, "atk": 26, "def": 16, "s_atk": 18, "s_def": 12, "speed": 10},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_LIGHT_THRUST", "SKILL_WATER_PHYS_LIGHT_STRIKE", "SKILL_WATER_ARMOR_WEAK"],
	},
	# Blattfee: Ahornblatt-Fee mit gläsernen Flügeln
	{
		"name": "74",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 12, "s_atk": 24, "s_def": 20, "speed": 20},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Irrflamme: kleines türkisfarbenes Irrlicht
	{
		"name": "75",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [190, 210],
		"preferred_stats": {"hp": 14, "atk": 10, "def": 10, "s_atk": 26, "s_def": 18, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_WARD_WEAK"],
	},
	# Glühzirpe: goldener Leuchtkäfer mit langen Fühlern
	{
		"name": "76",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.AIR,
		"stats": [200, 220],
		"preferred_stats": {"hp": 14, "atk": 12, "def": 12, "s_atk": 22, "s_def": 18, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_AIR_MAG_LIGHT_THRUST", "SKILL_AIR_MAG_LIGHT_STRIKE", "SKILL_AIR_WARD_WEAK"],
	},
	# Phönixglut: Feuerkugel in einem Wirbel aus Phönixflammen
	{
		"name": "77",
		"rarity": Enums.MON_RARITY.EPIC,
		"initial_type": Enums.MON_TYPES.FIRE,
		"stats": [230, 250],
		"preferred_stats": {"hp": 14, "atk": 12, "def": 10, "s_atk": 28, "s_def": 14, "speed": 22},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_FIRE_MAG_LIGHT_THRUST", "SKILL_FIRE_MAG_LIGHT_STRIKE", "SKILL_FIRE_WARD_WEAK"],
	},
	# Denkwurzel: riesiges Gehirn auf einem knorrigen Wurzelstamm
	{
		"name": "78",
		"rarity": Enums.MON_RARITY.RARE,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [215, 235],
		"preferred_stats": {"hp": 20, "atk": 6, "def": 16, "s_atk": 28, "s_def": 22, "speed": 8},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_EARTH_MAG_LIGHT_THRUST", "SKILL_EARTH_MAG_LIGHT_STRIKE", "SKILL_EARTH_WARD_WEAK"],
	},
	# Seherdämon: gehörnter Dämon mit Augenstab und Schlange (mythisch, nur bei Bossen)
	{
		"name": "79",
		"rarity": Enums.MON_RARITY.MYTHIC,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [260, 280],
		"preferred_stats": {"hp": 18, "atk": 16, "def": 14, "s_atk": 26, "s_def": 14, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_WARD_WEAK"],
	},
	# Strudelseele: blaue Seelenkugel mit schwarzen Flammen und Wasserwirbeln
	{
		"name": "80",
		"rarity": Enums.MON_RARITY.UNCOMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [200, 220],
		"preferred_stats": {"hp": 16, "atk": 10, "def": 14, "s_atk": 24, "s_def": 20, "speed": 16},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_MAG_LIGHT_THRUST", "SKILL_WATER_MAG_LIGHT_STRIKE", "SKILL_WATER_WARD_WEAK"],
	},
	# Panzerspinne: mechanische Spinne mit grün leuchtenden Adern
	{
		"name": "81",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.WATER,
		"stats": [190, 210],
		"preferred_stats": {"hp": 16, "atk": 24, "def": 26, "s_atk": 10, "s_def": 12, "speed": 12},
		"max_upgrades": 2,
		"default_egg_skills": ["SKILL_WATER_PHYS_WEAK_THRUST", "SKILL_WATER_ARMOR_LIGHT", "SKILL_WATER_WARD_WEAK"],
	},
	# Mooswürfel: bemooster Grasblock mit Knopfaugen, Startmonster (Tank mit Schwerpunkt Sp. Vert.)
	{
		"name": "82",
		"rarity": Enums.MON_RARITY.COMMON,
		"initial_type": Enums.MON_TYPES.EARTH,
		"stats": [190, 210],
		"preferred_stats": {"hp": 22, "atk": 8, "def": 20, "s_atk": 14, "s_def": 28, "speed": 8},
		"max_upgrades": 2,
		# Sp. Vert. am höchsten: Nutzloser Erdstoß, Leichter Kristallschild, Nutzloser Steinschild,
		# als Startmonster zusätzlich Leichter Schild (Vert., ergänzt den Kristallschild) und Leichte Erdkanone
		"default_egg_skills": ["SKILL_EARTH_MAG_WEAK_THRUST", "SKILL_EARTH_WARD_LIGHT", "SKILL_EARTH_ARMOR_WEAK",
			"SKILL_EARTH_ARMOR_PLAIN", "SKILL_EARTH_MAG_LIGHT_CANNON"],
	},
]
