extends Control

## Züge-Zahl mit Partikeln im "Lebende Pixel"-Look: übrige Züge eigener Monster im Kampf (BattleMonCard),
## Kosten auf den Skill-Karten (battle_card) und freigeschaltete Züge einer Art (Info-Panels).

const EMPTY_COLOR := Color(0.55, 0.55, 0.55)

@export var label: Label
@export var particles: MovesParticlesView
## Wie weit die Partikel fliegen, kleiner für kleine Zahlen (Monster-Karte, Skill-Karte)
@export var particle_range := 1.0

func _ready() -> void:
	particles.set_range(particle_range)
	resized.connect(_center)
	_center()

func set_moves(moves: int, max_moves: int) -> void:
	tooltip_text = "%s %d/%d" % [tr("BATTLE_MON_MOVES"), moves, max_moves]
	show_number(moves)

## Zahl zeigen, Partikel laufen nur über 0. pop: kurz groß und hell aufleuchten,
## dim_empty: bei 0 ist die Zahl grau.
func show_number(value: int, pop := true, dim_empty := false) -> void:
	label.text = str(value)
	label.add_theme_color_override("font_color", EMPTY_COLOR if dim_empty and value <= 0 else Color.WHITE)
	if pop:
		particles.restart()
	particles.emitting = value > 0
	if pop:
		_pop()

func _pop() -> void:
	pivot_offset = size / 2
	scale = Vector2.ONE * 1.6
	modulate = Color(2, 2, 2)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)

func _center() -> void:
	particles.center_on(size / 2)
