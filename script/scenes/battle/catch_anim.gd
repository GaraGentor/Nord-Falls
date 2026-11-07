extends Control

## Hypnose: über der Spirale locken nacheinander zwei Sätze, das Monster wiegt sich im Takt.
## Geschafft: goldene Funken sprühen aus dem Monster. Nicht geschafft: pechschwarze Funken regnen von oben.

const CALLS := ["BATTLE_CATCH_CALL_1", "BATTLE_CATCH_CALL_2"]
## Satz tippt sich ein, bleibt kurz stehen und verblasst
const CALL_TYPE_SECONDS := 0.9
const CALL_HOLD_SECONDS := 0.5
const CALL_FADE_SECONDS := 0.25
const RESULT_SECONDS := 3.0
const SWAY_SECONDS := 0.7
const SWAY_SCALE := Vector2(1.06, 1.06)
const FAILED_MON_COLOR := Color(0.25, 0.22, 0.3)
const GOLD := Color(1.0, 0.84, 0.35)
const GOLD_END := Color(1.0, 0.55, 0.1, 0.0)

var catched: bool = false

@export var msg: Label

@onready var _spiral: Control = $TextureRect
@onready var _mon_texture: TextureRect = $TextureRect/MonTexture
@onready var _call_label: Label = $TextureRect/Label

var _sway: Tween
var _particles: CPUParticles2D

func _catch_animation(mon: Monster) -> void:
	Monmap.show_on(_mon_texture, mon._name, Monmap.LARGE)
	_mon_texture.modulate = Color.WHITE
	_mon_texture.pivot_offset = _mon_texture.size / 2
	_call_label.text = ""
	visible = true
	_start_sway()
	for call_key in CALLS:
		await _say(tr(call_key))
	_stop_sway()
	catch_mon(mon)
	display_progress(mon)

## Das Monster wiegt sich, solange gelockt wird
func _start_sway() -> void:
	_sway = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	_sway.tween_property(_mon_texture, "scale", SWAY_SCALE, SWAY_SECONDS)
	_sway.tween_property(_mon_texture, "scale", Vector2.ONE, SWAY_SECONDS)

func _stop_sway() -> void:
	_sway.kill()
	_mon_texture.scale = Vector2.ONE

func _say(text: String) -> void:
	_call_label.text = text
	_call_label.visible_ratio = 0.0
	_call_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_call_label, "visible_ratio", 1.0, CALL_TYPE_SECONDS)
	tween.tween_interval(CALL_HOLD_SECONDS)
	tween.tween_property(_call_label, "modulate:a", 0.0, CALL_FADE_SECONDS)
	await tween.finished

func catch_mon(mon: Monster) -> void:
	catched = Helper.will_catch_mon(mon)
	if catched:
		Events.mon_is_catched.emit(mon)
		mon.unlock_skills()
		# Zusatzaktionen gibt es für eigene Monster nur über den Kerkermeister
		mon._initial_moves = Monster.BASE_MOVES
		State.catched_mons.append(mon)
		State.mark_mon_caught(mon._name)
		State.run_catches += 1
		State.enemy_mons.remove_at(State.enemy_mons.find(mon))

func display_progress(mon: Monster) -> void:
	if catched:
		msg.text = tr("BATTLE_CATCH_SUCCESS")
		_spawn_gold_sparkles()
	else:
		msg.text = tr("BATTLE_CATCH_FAILED")
		_spawn_black_rain()
		create_tween().tween_property(_mon_texture, "modulate", FAILED_MON_COLOR, 0.6)
	msg.visible = true
	await get_tree().create_timer(RESULT_SECONDS).timeout
	visible = false
	msg.visible = false
	_particles.queue_free()
	_particles = null
	Events.finish_catching.emit(catched, mon)

func _new_particles(amount: int, lifetime: float) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	var pixel := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	particles.texture = ImageTexture.create_from_image(pixel)
	particles.amount = amount
	particles.lifetime = lifetime
	# unter den Texten, über dem Monster
	_spiral.add_child(particles)
	_spiral.move_child(particles, _mon_texture.get_index() + 1)
	_particles = particles
	return particles

## Goldene Funken sprühen rundum aus dem Monster und sinken dann ab
func _spawn_gold_sparkles() -> void:
	var sparkles := _new_particles(140, 1.6)
	sparkles.position = _mon_texture.get_rect().get_center()
	sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 90.0
	sparkles.direction = Vector2.UP
	sparkles.spread = 180.0
	sparkles.initial_velocity_min = 120.0
	sparkles.initial_velocity_max = 420.0
	sparkles.gravity = Vector2(0, 160)
	sparkles.scale_amount_min = 4.0
	sparkles.scale_amount_max = 10.0
	sparkles.explosiveness = 0.35
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color.WHITE, GOLD, GOLD_END])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	sparkles.color_ramp = ramp

## Pechschwarze Funken regnen von oben über die ganze Breite
func _spawn_black_rain() -> void:
	var rain := _new_particles(320, 1.8)
	rain.position = Vector2(_spiral.size.x / 2, -20.0)
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(_spiral.size.x / 2, 10.0)
	rain.direction = Vector2.DOWN
	rain.spread = 4.0
	rain.initial_velocity_min = 260.0
	rain.initial_velocity_max = 520.0
	rain.gravity = Vector2(0, 180)
	rain.scale_amount_min = 4.0
	rain.scale_amount_max = 12.0
	rain.color = Color.BLACK
