extends Control

@export var grid: GridContainer
@export var monster_texture: TextureRect

@export var name_label: Label
@export var level_label: Label

@export var pg1: ProgressBar
@export var pg2: ProgressBar

var mon: Monster:
	set(_mon):
		mon = _mon
		grid.init_with_mon(mon)
		Monmap.show_on(monster_texture, mon._name, Monmap.MEDIUM)
		name_label.text = Helper.mon_display_name(mon._name)

func init_with_mon(_mon: Monster):
	mon = _mon
	if mon._level_progress == 1:
		pg1.value = 10

func trigger_level_up() -> bool:
	level_label.position = Vector2(level_label.position.x, 0)
	level_label.visible = true
	grid.show_p_labels(get_labels())
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
	var hp_diff = mon.hp() - old_hp
	var attack_diff = mon.attack() - old_attack
	var defense_diff = mon.defense() - old_defense
	var s_attack_diff = mon.s_attack() - old_s_attack
	var s_defense_diff = mon.s_defense() - old_s_defense
	var speed_diff = mon.speed() - old_speed
	
	return [floor_val(hp_diff),floor_val(attack_diff),floor_val(defense_diff),floor_val(s_attack_diff),floor_val(s_defense_diff), floor_val(speed_diff), ""]

func floor_val(_val: float) -> String:
	return " + %d" % floori(_val)

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
