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
		name_label.text = Helper.mon_display_name(mon._name)
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
	# KP unter dem Bild des Monsters, damit man sieht, wie viel ihm nach dem Kampf noch bleibt
	_hp_bar = LivingBar.new()
	_hp_bar.glow_when_full = false
	_hp_bar.glint = false
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

## KP-Balken in der Farbe wie im Kampf (grün, orange, rot), nach dem Level-Up mit den neuen Max-KP
func _refresh_hp(animate: bool) -> void:
	if _hp_bar == null or mon == null:
		return
	var max_hp: float = mon.hp()
	var current: float = maxf(max_hp - mon._lost_hp, 0.0)
	var share := current / max_hp if max_hp > 0 else 0.0
	_hp_bar.color = BattleMonCard.hp_color(share)
	_hp_bar.set_text("%s %d / %d" % [tr("STAT_HP").trim_suffix(":"), roundi(current), roundi(max_hp)])
	_hp_bar.set_share(share, animate)

func trigger_level_up() -> bool:
	level_label.position = Vector2(level_label.position.x, 0)
	level_label.visible = true
	grid.show_p_labels(get_labels())
	_refresh_hp(true)
	await get_tree().create_tween().tween_property(level_label, "position", Vector2(level_label.position.x, size.y), 2).finished
	level_label.visible = false
	return true

func get_labels() -> Array[String]:
	var old_hp = mon.hp()
	var old_attack = mon.attack()
	var old_defense = mon.defense()
	var old_s_attack = mon.s_attack()
	var old_s_defense = mon.s_defense()
	var old_speed = mon.speed()
	mon.upgrade_by_level(Relics.modify("level_up_levels", 1, mon))
	grid.init_with_mon(mon)
	return [
		gain_text(old_hp, mon.hp()),
		gain_text(old_attack, mon.attack()),
		gain_text(old_defense, mon.defense()),
		gain_text(old_s_attack, mon.s_attack()),
		gain_text(old_s_defense, mon.s_defense()),
		gain_text(old_speed, mon.speed()),
		"",
	]

## Das Grid zeigt die Werte abgeschnitten (int), also zählt der Unterschied der angezeigten Zahlen.
## Springt die angezeigte Zahl nicht, bleibt das Feld leer.
func gain_text(old_val: float, new_val: float) -> String:
	var shown_diff := int(new_val) - int(old_val)
	return " %+d" % shown_diff if shown_diff != 0 else ""

func _play() -> bool:
	mon._level_progress += 1
	if mon._level_progress == 1:
		await get_tree().create_tween().tween_property(pg1, "value", 10, .5).finished
	if mon._level_progress == 2:
		await get_tree().create_tween().tween_property(pg2, "value", 10, .5).finished
		await trigger_level_up()
		pg1.value = 0
		pg2.value = 0
		mon._level_progress = 0
	return true
