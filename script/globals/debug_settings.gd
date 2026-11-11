extends Node

## Einstellungen des Debug-Menüs in einer eigenen Datei, unabhängig von den Spielständen.
## Fertige Builds ignorieren die Datei und nutzen immer die Standardwerte.

const PATH := "user://debug_settings.json"
const STATS := ["hp", "atk", "def", "s_atk", "s_def", "speed"]
const MAX_RESERVED := 100
## Globales Wachstum pro Stufe (Mon._base_stat), skaliert den Zuwachs aller Werte aller Monster im gleichen Verhältnis:
## DEFAULT_GROWTH = Wachstum wie gewohnt aus der BST, 0 = kein Wachstum, halber Wert = halber Zuwachs, doppelter = doppelter.
## Stufe 1 bleibt immer gleich.
const DEFAULT_GROWTH := 8.0
## Bereich und kleinster Schritt im Debug-Menü
const GROWTH_RANGE := [0.0, 100.0]
const GROWTH_STEP := 0.5
## Die Datei ist nach Kampfmodus gegliedert, weil der Branch new-conzept dieselbe Datei nutzt. Hier gibt es nur diesen Modus.
const MODE := "classic"

## Schadensformel (Skills.calc_damage), im Debug-Menü umschaltbar:
## classic   = atk · 2·atk/(atk+def)  (bisher: Angriff zählt etwa 3x so viel wie Verteidigung)
## symmetric = Grundwert der Stufe · 2·a^k/(a^k+d^k), begrenzt auf [min_factor, max_factor]
## pokemon   = (floor(2·L/5)+2) · Wert · atk/def / 50 + 2, mit floor wie im Original
const FORMULAS := ["classic", "symmetric", "pokemon"]
## Standard = Verhalten wie bisher. level_offset 0 = Werte linear zur Stufe, hp_scale 1 = KP wie bisher.
const DAMAGE_DEFAULTS := {"formula": "classic", "exponent": 2.0, "min_factor": 0.25, "max_factor": 2.0, "level_offset": 0.0, "hp_scale": 1.0}
## Empfehlung aus tools/damage_sim.js: symmetrisch, Boden 0.25, Stufen-Sockel 10, KP x3 (etwa 7 Treffer bis K.O.)
const DAMAGE_RECOMMENDED := {"formula": "symmetric", "exponent": 2.0, "min_factor": 0.25, "max_factor": 2.0, "level_offset": 10.0, "hp_scale": 3.0}
## [min, max, Schritt] pro Zahlen-Einstellung
const DAMAGE_RANGES := {
	"exponent": [0.5, 4.0, 0.25],
	"min_factor": [0.0, 1.0, 0.05],
	"max_factor": [1.0, 4.0, 0.25],
	"level_offset": [0.0, 50.0, 1.0],
	"hp_scale": [0.5, 6.0, 0.25],
}

## Kampfmodus -> Wert -> Prozent der BST, die fest diesem Wert gehören
var _reserved := {MODE: {}}
## Kampfmodus -> globales Wachstum pro Stufe (fehlt = DEFAULT_GROWTH)
var _growth := {}
## Kampfmodus -> Einstellungen der Schadensformel (fehlende Keys = DAMAGE_DEFAULTS)
var _damage := {}
## alles aus der Datei, auch Einträge, die dieser Branch nicht kennt
var _other := {}

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
		_other = parsed
		_reserved.merge(parsed.get("reserved_stats", {}), true)
		_growth.merge(parsed.get("growth_per_level", {}), true)
		_damage.merge(parsed.get("damage_formula", {}), true)
		_disabled_relics = parsed.get("disabled_relics", [])

func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		# fremde Einträge (z. B. "growth_stats" vom Branch new-conzept) bleiben erhalten
		var data := _other.duplicate()
		data.merge({"reserved_stats": _reserved, "growth_per_level": _growth, "damage_formula": _damage, "disabled_relics": _disabled_relics}, true)
		file.store_string(JSON.stringify(data))

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

## Globales Wachstum pro Stufe (fehlt = DEFAULT_GROWTH)
func growth() -> float:
	return float(_growth.get(MODE, DEFAULT_GROWTH))

func set_growth(value: float) -> void:
	_growth[MODE] = clampf(snappedf(value, GROWTH_STEP), GROWTH_RANGE[0], GROWTH_RANGE[1])
	save()

func reset_growth() -> void:
	_growth.erase(MODE)
	save()

## Faktor auf den üblichen Zuwachs pro Stufe. Beispiel: bei 8 bekommt ATK +10 und Initiative +20 pro Stufe,
## bei 4 dann +5 und +10, bei 0 nichts mehr.
func growth_factor() -> float:
	return growth() / DEFAULT_GROWTH

## Faktor einer Stufe auf den Wert von Stufe 1 (Mon._base_stat).
## Ohne Sockel wächst er linear (Stufe 10 = 10x Stufe 1). Mit Sockel ist er so normiert, dass die Startstufe gleich bleibt,
## danach wächst er langsamer: bei Sockel 10 hat Stufe 7 nur 17/15 der Werte von Stufe 5 statt 7/5.
func level_scale(level: int) -> float:
	var offset := float(damage_setting("level_offset"))
	var curve := float(level)
	if offset > 0.0:
		var start := float(State.INITIAL_LEVEL)
		curve = start * (level + offset) / (start + offset)
	return 1.0 + (curve - 1.0) * growth_factor()

# ─────────────────────────
# Schadensformel

func damage_setting(key: String):
	return _damage.get(MODE, {}).get(key, DAMAGE_DEFAULTS[key])

func set_damage_setting(key: String, value) -> void:
	if DAMAGE_RANGES.has(key):
		var r: Array = DAMAGE_RANGES[key]
		value = clampf(snappedf(float(value), r[2]), r[0], r[1])
	if not _damage.has(MODE):
		_damage[MODE] = {}
	_damage[MODE][key] = value
	save()

func set_damage_settings(values: Dictionary) -> void:
	_damage[MODE] = values.duplicate()
	save()

func reset_damage() -> void:
	_damage.erase(MODE)
	save()

func damage_formula() -> String:
	var formula = damage_setting("formula")
	return formula if FORMULAS.has(formula) else DAMAGE_DEFAULTS.formula

func hp_scale() -> float:
	return float(damage_setting("hp_scale"))
