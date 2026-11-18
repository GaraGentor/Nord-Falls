class_name MovesBadge
extends Control

## Zug-Rune: Züge-Zahl auf einem pixeligen Eisen-Rhombus mit Goldrand, innen glüht eine Glut (moves_rune.gdshader).
## Für übrige Züge eigener Monster im Kampf (BattleMonCard), Kosten auf den Skill-Karten (battle_card)
## und freigeschaltete Züge einer Art (Info-Panels).

const SHADER := preload("res://script/ui/moves_badge/moves_rune.gdshader")
const TEXT_COLOR := Color(1.0, 0.95, 0.85)
const EMPTY_TEXT_COLOR := Color(0.55, 0.55, 0.55)
## So lange glimmt die Glut auf oder verlischt
const CHARGE_TIME := 0.5
const SCENE_PATH := "res://script/ui/moves_badge/moves_badge.tscn"
## Größe der Rune unten links am Bild eines Monsters (Map-Details, Shop, Trainer)
const PORTRAIT_BADGE_SIZE := Vector2(42, 39)

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

func set_moves(moves: int, max_moves: int, pop := true) -> void:
	tooltip_text = "%s %d/%d" % [tr("BATTLE_MON_MOVES"), moves, max_moves]
	show_number(moves, pop)

## Freigeschaltete Züge (Grundzug plus beim Kerkermeister gesprengte Ketten) und die maximal möglichen der Art
static func mon_moves(mon: Monster) -> Vector2i:
	var max_moves: int = Monster.BASE_MOVES + Monmap.mon_metainfos_by_name(mon._name).get("max_upgrades", 0)
	return Vector2i(Monster.BASE_MOVES + mon._upgrades, max_moves)

## Hängt die Rune mit den Zügen des Monsters unten links an sein Bild. Gibt eine Hülle zurück, die das Bild
## (füllt die Hülle, deren Größe von ihm kommt) und die Rune trägt.
static func attach_to_portrait(portrait: Control, mon: Monster) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = portrait.custom_minimum_size
	# genau so breit wie das Bild, damit die Rune am Bild sitzt und nicht am Rand der Spalte
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = portrait.size_flags_vertical
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	portrait.custom_minimum_size = Vector2.ZERO
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(portrait)
	pin_to_picture(portrait, mon)
	return holder

## Setzt die Rune mit den Zügen des Monsters neben picture (gleicher Eltern-Knoten, kein Container) an die
## untere linke Ecke des gezeichneten Bildes. Bei TextureRects mit Seitenverhältnis sitzt sie am Bild selbst,
## nicht am Rand der freien Fläche daneben, und wandert bei Größenänderungen mit.
static func pin_to_picture(picture: Control, mon: Monster) -> MovesBadge:
	var badge: MovesBadge = load(SCENE_PATH).instantiate()
	picture.get_parent().add_child(badge)
	badge.size_flags_horizontal = Control.SIZE_FILL
	badge.size_flags_vertical = Control.SIZE_FILL
	badge.custom_minimum_size = PORTRAIT_BADGE_SIZE
	badge.size = PORTRAIT_BADGE_SIZE
	var moves := mon_moves(mon)
	badge.set_moves(moves.x, moves.y, false)
	var place := func():
		if not is_instance_valid(badge) or not is_instance_valid(picture):
			return
		var rect := _drawn_rect(picture)
		badge.position = picture.position + Vector2(rect.position.x, rect.end.y - PORTRAIT_BADGE_SIZE.y)
	# Größe und Lage des Bildes (das Bild selbst ist da schon gesetzt)
	picture.item_rect_changed.connect(place)
	place.call_deferred()
	return badge

## Fläche, die das Bild in picture tatsächlich einnimmt (lokal zu picture)
static func _drawn_rect(picture: Control) -> Rect2:
	var area := Rect2(Vector2.ZERO, picture.size)
	if not picture is TextureRect or picture.texture == null:
		return area
	var tex_size: Vector2 = picture.texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return area
	match picture.stretch_mode:
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED, TextureRect.STRETCH_KEEP_ASPECT:
			var factor := minf(area.size.x / tex_size.x, area.size.y / tex_size.y)
			var drawn := tex_size * factor
			var offset := (area.size - drawn) / 2 if picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED else Vector2.ZERO
			return Rect2(offset, drawn)
		TextureRect.STRETCH_KEEP_CENTERED:
			return Rect2((area.size - tex_size) / 2, tex_size)
	return area

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
