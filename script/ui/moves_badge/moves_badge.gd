extends Control

## Zug-Rune: Züge-Zahl auf einem pixeligen Eisen-Rhombus mit Goldrand, innen glüht eine Glut (moves_rune.gdshader).
## Für übrige Züge eigener Monster im Kampf (BattleMonCard), Kosten auf den Skill-Karten (battle_card)
## und freigeschaltete Züge einer Art (Info-Panels).

const SHADER := preload("res://script/ui/moves_badge/moves_rune.gdshader")
const TEXT_COLOR := Color(1.0, 0.95, 0.85)
const EMPTY_TEXT_COLOR := Color(0.55, 0.55, 0.55)
## So lange glimmt die Glut auf oder verlischt
const CHARGE_TIME := 0.5

@export var label: Label
@export var rune: ColorRect

var _material := ShaderMaterial.new()
var _charge_tween: Tween

func _init() -> void:
	_material.set_shader_parameter("charge", 1.0)

func _ready() -> void:
	_material.shader = SHADER
	rune.material = _material
	rune.resized.connect(_sync_size)
	_sync_size()

func set_moves(moves: int, max_moves: int) -> void:
	tooltip_text = "%s %d/%d" % [tr("BATTLE_MON_MOVES"), moves, max_moves]
	show_number(moves)

## Zahl zeigen. pop: kurz groß und hell aufleuchten,
## dim_empty: bei 0 verlischt die Glut und die Rune wird kaltes Eisen.
func show_number(value: int, pop := true, dim_empty := false) -> void:
	label.text = str(value)
	var empty := dim_empty and value <= 0
	label.add_theme_color_override("font_color", EMPTY_TEXT_COLOR if empty else TEXT_COLOR)
	_set_charge(0.0 if empty else 1.0, pop)
	if pop:
		_pop()

func _set_charge(target: float, animate: bool) -> void:
	if _charge_tween:
		_charge_tween.kill()
	if not animate or not is_inside_tree():
		_material.set_shader_parameter("charge", target)
		return
	var from: float = _material.get_shader_parameter("charge")
	_charge_tween = create_tween()
	_charge_tween.tween_method(func(v: float): _material.set_shader_parameter("charge", v), from, target, CHARGE_TIME)

func _sync_size() -> void:
	_material.set_shader_parameter("rect_size", rune.size)

func _pop() -> void:
	pivot_offset = size / 2
	scale = Vector2.ONE * 1.5
	modulate = Color(1.8, 1.8, 1.8)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)
