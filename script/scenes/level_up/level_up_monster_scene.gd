extends Control

## Level-Up eines Team-Monsters: Werte, zwei K.O.-Balken (2 K.O.s = +1 Stufe) und die KP, die ihm noch bleiben.
## Die Balken sind LivingBars, die ProgressBars aus der Szene halten nur den Platz und den Wert (für Tweens).

const HP_BAR_HEIGHT := 18.0
const KO_BAR_HEIGHT := 30.0
## sattes Gold der K.O.-Balken, voll leuchten sie heller (LivingBar)
const KO_BAR_COLOR := Color(0.95, 0.62, 0.16)

@export var grid: GridContainer
@export var monster_texture: TextureRect

@export var name_label: Label
@export var level_label: Label

@export var pg1: ProgressBar
@export var pg2: ProgressBar

var _ko_bars: Array[LivingBar] = []
var _hp_bar: LivingBar

var mon: Monster:
	set(_mon):
		mon = _mon
		grid.init_with_mon(mon)
		Monmap.show_on(monster_texture, mon._name, Monmap.MEDIUM)
		_refresh_name()
		_refresh_hp(false)

func _ready() -> void:
	for pg in [pg1, pg2]:
		pg.add_theme_stylebox_override("background", StyleBoxEmpty.new())
		pg.add_theme_stylebox_override("fill", StyleBoxEmpty.new())
		pg.custom_minimum_size.y = KO_BAR_HEIGHT
		var bar := LivingBar.new()
		bar.color = KO_BAR_COLOR
		bar.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		pg.add_child(bar)
		pg.value_changed.connect(func(value: float): bar.set_share(value / pg.max_value))
		bar.set_share(pg.value / pg.max_value)
		_ko_bars.append(bar)
	# KP unter dem Bild des Monsters wie im Kampf, damit man sieht, wie viel ihm nach dem Kampf noch bleibt
	_hp_bar = LivingBar.hp_bar(0, 1)
	_hp_bar.custom_minimum_size = Vector2(0, HP_BAR_HEIGHT)
	_hp_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	var hp_margin := MarginContainer.new()
	for side in ["left", "right"]:
		hp_margin.add_theme_constant_override("margin_" + side, 24)
	hp_margin.add_child(_hp_bar)
	monster_texture.get_parent().add_child(hp_margin)
	if mon:
		_refresh_hp(false)

func init_with_mon(_mon: Monster):
	mon = _mon
	if mon._level_progress == 1:
		pg1.value = 10

## Name mit aktueller Stufe, damit man immer sieht, welche Stufe das Monster gerade hat
func _refresh_name() -> void:
	name_label.text = tr("MAP_TEAM_ENTRY").format({"name": Helper.mon_display_name(mon._name), "level": mon._level})

## KP-Balken in der Farbe wie im Kampf (grün, orange, rot), nach dem Level-Up mit den neuen Max-KP
func _refresh_hp(animate: bool) -> void:
	if _hp_bar == null or mon == null:
		return
	var max_hp: float = mon.hp()
	var current: float = maxf(max_hp - mon._lost_hp, 0.0)
	_hp_bar.set_hp(current, max_hp, "%s %d / %d" % [tr("STAT_HP").trim_suffix(":"), roundi(current), roundi(max_hp)], animate)

## Stufe vor dem letzten verbuchten Level-Up (get_labels), für "Lv. 5 -> 6" in der Animation
var _level_before := 0

func trigger_level_up(gains: Array[String], from_level: int, to_level: int) -> bool:
	level_label.text = tr("LEVEL_UP_TITLE") + "\n" + tr("LEVEL_UP_LEVELS").format({"from": from_level, "to": to_level})
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.position = Vector2(level_label.position.x, 0)
	level_label.visible = true
	grid.show_p_labels(gains)
	_refresh_hp(true)
	await get_tree().create_tween().tween_property(level_label, "position", Vector2(level_label.position.x, size.y), 2).finished
	if not is_inside_tree():
		return false
	level_label.visible = false
	return true

## Zuwachs je Zeile des Grids: Reihenfolge und Werte kommen aus grid.map, damit jedes (+) neben seinem Wert steht
## (früher fest verdrahtet, nach dem Umbau der Werte standen Verteidigung und Sp. Angriff vertauscht)
func get_labels() -> Array[String]:
	var old_values := []
	for obj in grid.map:
		old_values.append(obj.value.call(mon))
	_level_before = mon._level
	mon.upgrade_by_level(1)
	grid.init_with_mon(mon)
	_refresh_name()
	var labels: Array[String] = []
	for i in grid.map.size():
		labels.append(gain_text(old_values[i], grid.map[i].value.call(mon)))
	return labels

## Das Grid zeigt die Werte abgeschnitten (int), also zählt der Unterschied der angezeigten Zahlen.
## Springt die angezeigte Zahl nicht, bleibt das Feld leer.
func gain_text(old_val: float, new_val: float) -> String:
	var shown_diff := int(new_val) - int(old_val)
	return " %+d" % shown_diff if shown_diff != 0 else ""

## K.O.s, die noch nicht verbucht sind (play_kills)
var _remaining := 0
var _finished := false

## Spielt die K.O.s nacheinander ab. Jeder K.O. wird zuerst verbucht (Fortschritt, Level-Up), dann animiert:
## so kann finish_now jederzeit den Rest ohne Animation verbuchen (OK-Knopf während der Animation).
## Beide Monster laufen parallel (level_up.gd wartet nicht auf das erste).
## Jeder K.O. ist eine halbe Stufe, "boss_kill_progress" gibt pro besiegtem Boss halbe Stufen extra
## (Doppeltes Wachstum), die wie weitere K.O.s abgespielt werden.
func play_kills(kills: int, boss_kills := 0) -> void:
	_remaining = kills + boss_kills * Relics.modify("boss_kill_progress", 0, mon)
	while _remaining > 0 and not _finished:
		_remaining -= 1
		var gains := _apply_kill()
		await _animate_kill(gains)
		if not is_inside_tree():
			return

## Restliche K.O.s sofort verbuchen, ohne Animation
func finish_now() -> void:
	_finished = true
	while _remaining > 0:
		_remaining -= 1
		_apply_kill()

## Eine halbe Stufe: Fortschritt, bei der zweiten ein Level-Up. Gibt die (+)-Texte zurück, leer ohne Level-Up
func _apply_kill() -> Array[String]:
	mon._level_progress += 1
	if mon._level_progress < 2:
		return []
	mon._level_progress = 0
	return get_labels()

func _animate_kill(gains: Array[String]) -> void:
	if gains.is_empty():
		await get_tree().create_tween().tween_property(pg1, "value", 10, .5).finished
		return
	await get_tree().create_tween().tween_property(pg2, "value", 10, .5).finished
	if not is_inside_tree() or _finished:
		return
	await trigger_level_up(gains, _level_before, mon._level)
	if not is_inside_tree():
		return
	pg1.value = 0
	pg2.value = 0
