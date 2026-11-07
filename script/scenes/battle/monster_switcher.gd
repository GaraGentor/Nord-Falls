extends Control

@export var mon1: TextureRect
@export var mon2: TextureRect

@export var btn: Button

var mon1_in_front: bool = true

var debug: bool = false

var front_pos
var back_pos

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_start()
	Events.monster_faints.connect(_deactivate_fainted_mon)

func _start(needs_to_select: bool = false, _mon: Monster = null):
	if State.mons.size() == 0:
		return
	var m: Array[Monster] = State.mons.filter(func(mon: Monster): return mon.is_alive())
	if m.size() == 0:
		return
	Monmap.show_on(mon1, m[0]._name, Monmap.SMALL)
	if needs_to_select:
		var index = State.mons.find(m[0])
		Monmap.show_on(mon2, m[0]._name, Monmap.SMALL)
		Events.select_mon.emit(index+1)
	if m.size() == 2:
		mon2.visible = true
		Monmap.show_on(mon2, m[1]._name, Monmap.SMALL)
	if debug:
		btn.disabled = false
		mon2.visible = true
	front_pos = mon1.global_position
	back_pos = mon2.global_position

func _deactivate_fainted_mon(mon:Monster) -> void:
	var found = State.mons.find(mon)
	if found > -1:
		_start(true, mon)

func tween_mon_back(mon: TextureRect, to_pos, callback) -> void:
	var tween := create_tween()
	# Position nach rechts verschieben (z.B. 200 Pixel)
	tween.tween_property(mon, "global_position:x", mon.global_position.x, .3)
	# Skalierung verkleinern (auf 50%)
	tween.tween_property(mon, "scale", Vector2(0.5, 0.5), .3)
	# Modulate auf Schwarz färben
	tween.tween_property(mon, "modulate", Color.BLACK, .3)
	tween.tween_property(mon, "global_position:x", to_pos, .3)
	tween.finished.connect(
		func():
		if callback: 
			callback.call()
	)

func tween_mon_front(mon: TextureRect, to_pos, callback) -> void:
	var tween2 := create_tween()
	# Position nach rechts verschieben (z.B. 200 Pixel)
	tween2.tween_property(mon, "global_position:x", mon.global_position.x, .3)
	# Skalierung verkleinern (auf 50%)
	tween2.tween_property(mon, "scale", Vector2(1, 1), .3)
	# Modulate auf Schwarz färben
	tween2.tween_property(mon, "modulate", Color.WHITE, .3)
	tween2.tween_property(mon, "global_position:x", to_pos, .3)
	tween2.finished.connect(
		func():
		if callback: 
			callback.call()
	)

func finish_callback() -> void:
	print("finish")
	btn.disabled = false
	pass

func _on_button_pressed() -> void:
	if State.mons.filter(func(mon:Monster): return mon.is_alive()).size() < 2:
		return
	btn.disabled = true
	if mon1_in_front:
		tween_mon_back(mon1, back_pos, null)
		tween_mon_front(mon2, front_pos, finish_callback)
		mon1_in_front = false
		Events.select_mon.emit(2)
	else:
		tween_mon_back(mon2,back_pos, null)
		tween_mon_front(mon1,front_pos, finish_callback)
		mon1_in_front = true
		Events.select_mon.emit(1)
	print("animations finished")

	
