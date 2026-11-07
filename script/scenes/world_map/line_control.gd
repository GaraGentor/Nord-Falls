class_name UILine
extends Control

## Weg zwischen zwei Feldern. Gestrichelt in der Tintenfarbe des Bioms, leuchtend, sobald er begehbar ist.

enum LineState { LOCKED, WALKABLE, PASSED }

## Verbindungspunkte
@export var from_node: Control
@export var to_node: Control

@export var width := 4.0

@export_group("Wellen-Effekt")
## Farbe des Glow-/Wellen-Effekts
@export var wave_color := Color(0.4, 0.9, 1.0):
	set(value):
		wave_color = value
		_update_shader_params()
## Intensität der Welle (steuert sowohl die geometrische Auslenkung als auch die Leuchtkraft)
@export_range(0.0, 5.0, 0.05) var wave_intensity := 1.0:
	set(value):
		wave_intensity = value
		_update_shader_params()
## Geschwindigkeit der wandernden Welle
@export_range(0.0, 10.0, 0.05) var wave_speed := 2.0:
	set(value):
		wave_speed = value
		_update_shader_params()

@export_group("Feinabstimmung")
## Anzahl der Wellenberge über die gesamte Linienlänge
@export var wave_frequency := 3.0
## Auflösung der Linie (mehr Segmente = glattere Welle, aber etwas teurer)
@export_range(4, 128, 1) var segments := 32

## gesperrte und abgelaufene Wege treten hinter die Karte zurück
const LOCKED_ALPHA := 0.6
const PASSED_ALPHA := 0.22
const DASH := 12.0
const THIN_WIDTH := 3.0
## Heller Saum um den begehbaren Weg
const HALO_WIDTH := 2.6
const HALO_ALPHA := 0.28

var state := LineState.LOCKED
var ink := Color.WHITE
var accent := Color.GOLD

var _time := 0.0
var _shader_material: ShaderMaterial

const WAVE_SHADER: Shader = preload("res://script/scenes/world_map/ui_line_wave.gdshader")


func _ready() -> void:
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = WAVE_SHADER
	_update_shader_params()
	_apply_state()
	# Items/UILine ist nur die Vorlage zum Duplizieren und verbindet nichts
	if not from_node or not to_node:
		set_process(false)
		return
	# Gesperrte Wege zeichnen nicht jeden Frame neu, müssen aber dem Layout folgen
	from_node.item_rect_changed.connect(queue_redraw)
	to_node.item_rect_changed.connect(queue_redraw)
	from_node._path._ui_item.item_rect_changed.connect(queue_redraw)
	if not to_node is Button:
		to_node._path._ui_item.item_rect_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func set_state(new_state: LineState) -> void:
	state = new_state
	if is_node_ready():
		_apply_state()


func apply_look(new_ink: Color, new_accent: Color) -> void:
	ink = new_ink
	accent = new_accent
	# Der Lichtpuls ist eine aufgehellte Version der Wegfarbe
	wave_color = new_accent.lerp(Color.WHITE, 0.5)
	queue_redraw()


## Start und Ende des Wegs in globalen Koordinaten
func endpoints() -> Array[Vector2]:
	var end: Vector2
	if to_node is Button:
		# Der Boss-Button ist kein Feld im Grid und füllt sein ganzes Panel: Der Weg endet unten am Icon in der Mitte
		var boss_rect := to_node.get_global_rect()
		end = boss_rect.get_center() + Vector2(0.0, to_node.icon.get_height() * 0.5)
	else:
		end = rect_center_bottom(to_node._path._ui_item.get_global_rect())
	return [rect_center_top(from_node._path._ui_item.get_global_rect()), end]


func _apply_state() -> void:
	var walkable := state == LineState.WALKABLE
	set_process(walkable)
	material = _shader_material if walkable else null
	queue_redraw()


func _update_shader_params() -> void:
	if not _shader_material:
		return
	_shader_material.set_shader_parameter("glow_color", wave_color)
	_shader_material.set_shader_parameter("glow_intensity", wave_intensity * 1.5)
	_shader_material.set_shader_parameter("glow_speed", wave_speed)


func _draw() -> void:
	if not from_node or not to_node:
		return

	var origin := get_global_rect().position
	var ends := endpoints()
	var a := ends[0] - origin
	var b := ends[1] - origin

	if a.distance_to(b) < 0.01:
		return

	match state:
		LineState.LOCKED:
			draw_dashed_line(a, b, Color(ink, LOCKED_ALPHA), THIN_WIDTH, DASH)
		LineState.PASSED:
			draw_line(a, b, Color(ink, PASSED_ALPHA), THIN_WIDTH)
		LineState.WALKABLE:
			_draw_ribbon(a, b, width * HALO_WIDTH, Color(accent, HALO_ALPHA))
			_draw_ribbon(a, b, width, accent)


func _draw_ribbon(a: Vector2, b: Vector2, ribbon_width: float, ribbon_color: Color) -> void:
	var diff := b - a
	var dir := diff.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var half_width := ribbon_width * 0.5
	var amplitude := wave_intensity * 8.0

	var left_points := PackedVector2Array()
	var right_points := PackedVector2Array()
	var uvs_left := PackedVector2Array()
	var uvs_right := PackedVector2Array()

	for i in segments + 1:
		var t := float(i) / float(segments)
		var base_point := a.lerp(b, t)
		# Sinus-Welle, an beiden Enden ausgeblendet, damit sie exakt an den Nodes andockt
		var fade := sin(t * PI)
		var offset := sin(t * wave_frequency * TAU - _time * wave_speed) * amplitude * fade
		var center := base_point + perp * offset

		left_points.append(center - perp * half_width)
		right_points.append(center + perp * half_width)
		uvs_left.append(Vector2(t, 0.0))
		uvs_right.append(Vector2(t, 1.0))

	# Linke Seite hin, rechte Seite zurück -> ergibt ein geschlossenes Band (Ribbon)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	points.append_array(left_points)
	uvs.append_array(uvs_left)
	for i in range(right_points.size() - 1, -1, -1):
		points.append(right_points[i])
		uvs.append(uvs_right[i])

	draw_polygon(points, PackedColorArray([ribbon_color]), uvs)


func rect_center_top(r: Rect2) -> Vector2:
	return Vector2(
		r.position.x + r.size.x * 0.5,
		r.position.y
	)


func rect_center_bottom(r: Rect2) -> Vector2:
	return Vector2(
		r.position.x + r.size.x * 0.5,
		r.position.y + r.size.y
	)
