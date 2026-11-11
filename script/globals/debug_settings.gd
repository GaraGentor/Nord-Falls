extends Node

## Einstellungen des Debug-Menüs in einer eigenen Datei, unabhängig von den Spielständen.
## Fertige Builds ignorieren die Datei und nutzen immer die Standardwerte.

const PATH := "user://debug_settings.json"
const STATS := ["hp", "atk", "def", "s_atk", "s_def", "speed"]
const MAX_RESERVED := 100
## Wachstum pro Stufe in Prozent (Mon._base_stat): 100 = wie bisher linear, 60 = jede Stufe bringt nur 60 % dazu.
## Stufe 1 bleibt immer gleich. Bereich für das Debug-Menü:
const DEFAULT_GROWTH := 100
const GROWTH_RANGE := [10, 200]
## Die Datei ist nach Kampfmodus gegliedert, weil der Branch new-conzept dieselbe Datei nutzt. Hier gibt es nur diesen Modus.
const MODE := "classic"

## Kampfmodus -> Wert -> Prozent der BST, die fest diesem Wert gehören
var _reserved := {MODE: {}}
## Kampfmodus -> Wert -> Wachstum pro Stufe in Prozent (fehlt = DEFAULT_GROWTH)
var _growth := {MODE: {}}

## IDs der Relics, die im Debug-Menü ausgeschaltet wurden (siehe Relics.is_active)
var _disabled_relics := []

## Im Debug-Menü gewählte Gegnerzahl für den nächsten Kampf, 0 = wie im normalen Spiel. Wird nicht gespeichert.
var next_enemy_count := 0
## Im Debug-Menü gewählte Boss-Relikte (Array von IDs) des nächsten Boss-Kampfs und Trophäen
## (Stat-Key -> Anzahl) für jeden seiner Bosse, null = wie im normalen Spiel. Werden nicht gespeichert.
var next_boss_relics = null
var next_boss_trophies = null

func _ready() -> void:
	if not OS.is_debug_build() or not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_reserved.merge(parsed.get("reserved_stats", {}), true)
		_growth.merge(parsed.get("growth_stats", {}), true)
		_disabled_relics = parsed.get("disabled_relics", [])

func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"reserved_stats": _reserved, "growth_stats": _growth, "disabled_relics": _disabled_relics}))

func is_relic_disabled(id: String) -> bool:
	return _disabled_relics.has(id)

func set_relic_disabled(id: String, disabled: bool) -> void:
	_disabled_relics.erase(id)
	if disabled:
		_disabled_relics.append(id)
	save()

## Gewählte Gegnerzahl, sonst usual_count. Die Wahl gilt nur für einen Kampf.
func take_enemy_count(usual_count: int) -> int:
	var count := next_enemy_count if next_enemy_count > 0 else usual_count
	next_enemy_count = 0
	return count

## Gewählte Boss-Relikte oder null, gilt nur für einen Kampf
func take_boss_relics():
	var relics = next_boss_relics
	next_boss_relics = null
	return relics

## Gewählte Boss-Trophäen oder null, gilt nur für einen Kampf
func take_boss_trophies():
	var trophies = next_boss_trophies
	next_boss_trophies = null
	return trophies

## Reservierter Anteil eines Werts in Prozent
func reserved(stat: String) -> int:
	return int(_reserved[MODE].get(stat, 0))

func reserved_total() -> int:
	var total := 0
	for stat in STATS:
		total += reserved(stat)
	return total

## Über alle Werte hinweg kann höchstens die ganze BST reserviert werden
func set_reserved(stat: String, percent: int) -> void:
	var others := reserved_total() - reserved(stat)
	_reserved[MODE][stat] = clampi(percent, 0, MAX_RESERVED - others)
	save()

func reset_reserved() -> void:
	_reserved[MODE] = {}
	save()

## Anteil an der BST nach Reserve: fester Teil plus der übliche Anteil am Rest.
## Beispiel: 40 % KP reserviert, üblicher KP-Anteil 15 % -> 0,4 + 0,6 * 0,15 = 49 %.
func effective_share(stat: String, usual_share: float) -> float:
	return reserved(stat) / 100.0 + (1.0 - reserved_total() / 100.0) * usual_share

## Wachstum pro Stufe eines Werts in Prozent
func growth(stat: String) -> int:
	return int(_growth[MODE].get(stat, DEFAULT_GROWTH))

func set_growth(stat: String, percent: int) -> void:
	_growth[MODE][stat] = clampi(percent, GROWTH_RANGE[0], GROWTH_RANGE[1])
	save()

func reset_growth() -> void:
	_growth[MODE] = {}
	save()

## Stufe, mit der ein Wert rechnet: 1 + (Stufe - 1) * Wachstum. Bei 100 % genau die Stufe.
func growth_level(stat: String, level: float) -> float:
	return 1.0 + (level - 1.0) * growth(stat) / 100.0
