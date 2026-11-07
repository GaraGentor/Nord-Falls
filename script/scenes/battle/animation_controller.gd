extends Node

var duration := 0.12
var strength := 0.15

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.monster_hit_monster.connect(_play_hit_animation)

func _play_hit_animation(from: Control, to: Control) -> void:
	_atk(from)
	_wobble(to)

func _atk(from):
	var _duration := 0.1
	var pause := 0.05
	var shrink_amount := 0.8
	var t := get_tree().create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_OUT)

	# Schrumpfen
	t.tween_property(from, "scale", Vector2(shrink_amount, shrink_amount), _duration)

	# kurze Pause
	t.tween_interval(pause)

	# zurück zur normalen Größe
	t.tween_property(from, "scale", Vector2.ONE, duration)

func _wobble(to):
	var t := get_tree().create_tween()
	t.set_trans(Tween.TRANS_BACK)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(to, "scale", Vector2(1.0 + strength, 1.0 - strength), duration)
	t.tween_property(to, "scale", Vector2(1.0 - strength, 1.0 + strength), duration)
	t.tween_property(to, "scale", Vector2.ONE, duration)
