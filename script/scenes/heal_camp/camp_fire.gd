extends Control

## Lagerfeuer in der Mitte des Heilungs-Camps: die Flammen flackern um ihren Fußpunkt, der Schein pulsiert mit.
## Es lebt: die Augen auf der inneren Flamme blinzeln, nach dem Füttern brennt es eine Weile schneller und größer.

@export var outer_flame: Control
@export var inner_flame: Control
@export var glow: Control
@export var embers: CPUParticles2D
@export var eyes: Control
@export var logs: Control

const OUTER_FLICKER := 0.09
const INNER_FLICKER := 0.14
const MAX_LEAN_DEGREES := 3.0
const FLICKER_SECONDS := Vector2(0.09, 0.18)
const GLOW_ALPHA := Vector2(0.65, 1.0)
## so viel schneller brennt das Feuer nach dem Füttern
const FED_SPEED := 1.7
## jeder Bissen macht die Flammen so viel größer, höchstens bis MAX_GROWTH
const GROWTH_PER_BITE := 0.1
const MAX_GROWTH := 1.4
const GROW_SECONDS := 0.2
const FED_SECONDS := 1.5
const SHRINK_SECONDS := 1.0
const BLINK_PAUSE := Vector2(1.5, 4.5)
const BLINK_SECONDS := 0.07
const BLINK_CLOSED := 0.1

var _speed := 1.0
var _growth := 1.0
var _calm_down: Tween
## eigenes Material der äußeren Flamme und der Scheite, es trägt den goldenen Umriss (set_gold)
var _outline_material: ShaderMaterial

func _ready() -> void:
	_outline_material = outer_flame.material.duplicate()
	outer_flame.material = _outline_material
	logs.material = _outline_material
	_flicker(outer_flame, OUTER_FLICKER)
	_flicker(inner_flame, INNER_FLICKER)
	_pulse_glow()
	_blink()

## Jeder weitere Bissen lässt das Feuer weiter wachsen und verlängert das schnelle Brennen
func eat() -> void:
	_set_speed(FED_SPEED)
	if _calm_down:
		_calm_down.kill()
	_calm_down = create_tween()
	_calm_down.tween_property(self, "_growth", minf(_growth + GROWTH_PER_BITE, MAX_GROWTH), GROW_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_calm_down.tween_interval(FED_SECONDS)
	_calm_down.tween_property(self, "_growth", 1.0, SHRINK_SECONDS).set_trans(Tween.TRANS_SINE)
	_calm_down.tween_callback(_set_speed.bind(1.0))

## Goldener Umriss ums Feuer: die Essenz in der Hand schwebt darüber
func set_gold(gold: bool) -> void:
	RewardDialog.set_outline(_outline_material, gold)

## So viel höher als sonst reichen die Flammen gerade
func flame_lift() -> float:
	return outer_flame.size.y * (_growth - 1.0)

func _set_speed(speed: float) -> void:
	_speed = speed
	embers.speed_scale = speed

func _flicker(flame: Control, amount: float) -> void:
	var seconds := randf_range(FLICKER_SECONDS.x, FLICKER_SECONDS.y) / _speed
	var stretch := randf_range(-amount, amount)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	# wird die Flamme höher, wird sie auch schmaler
	tween.tween_property(flame, "scale", Vector2(1.0 - stretch * 0.6, 1.0 + stretch) * _growth, seconds)
	tween.tween_property(flame, "rotation_degrees", randf_range(-MAX_LEAN_DEGREES, MAX_LEAN_DEGREES), seconds)
	tween.chain().tween_callback(_flicker.bind(flame, amount))

func _blink() -> void:
	var tween := create_tween()
	tween.tween_interval(randf_range(BLINK_PAUSE.x, BLINK_PAUSE.y))
	tween.tween_property(eyes, "scale:y", BLINK_CLOSED, BLINK_SECONDS)
	tween.tween_property(eyes, "scale:y", 1.0, BLINK_SECONDS)
	tween.tween_callback(_blink)

func _pulse_glow() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "modulate:a", randf_range(GLOW_ALPHA.x, GLOW_ALPHA.y), randf_range(0.2, 0.4) / _speed)
	tween.tween_callback(_pulse_glow)
