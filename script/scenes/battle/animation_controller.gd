extends Node

var duration := 0.12

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.monster_hit_monster.connect(_play_hit_animation)

## Nur der Angreifer zuckt zusammen, damit man sieht, wer angreift.
## Was das Ziel abbekommt, zeigen die Effekte über dem Monster (BattleVfx, Events.skill_vfx).
func _play_hit_animation(from: Control, _to: Control) -> void:
	_atk(from)

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
