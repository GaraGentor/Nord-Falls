extends Control

## Ordnet alle Kinder gleichmäßig auf einem Kreis an.
## Bei angle_offset = 0 steht das erste Kind oben (12 Uhr), die weiteren folgen im Uhrzeigersinn.
## Die Kinder werden nur verschoben, nicht gedreht, damit die Monster aufrecht bleiben.
## Der Platz auf dem Kreis kommt aus dem Meta-Wert "slot", nicht aus der Reihenfolge der Kinder.
## So kann ein Kind zum Zeichnen nach vorne geholt werden, ohne seinen Platz zu verlieren.
## Ring und Pentagramm (wheel_ring.gdshader) liegen dahinter und drehen sich mit.
## Die Rundenmarke (goldene Spitze außen am Platz des ersten Monsters der Runde) dreht sich ebenfalls mit:
## zeigt sie wieder nach oben, beginnt eine neue Runde.

const ROUND_MARKER_COLOR := Color(1.0, 0.85, 0.25)
## Grundlinie und Spitze der Rundenmarke, Abstand vom Kreis in Icon-Größen (die Grundlinie liegt hinter dem Icon)
const ROUND_MARKER_BASE := 0.6
const ROUND_MARKER_TIP := 0.95
const ROUND_MARKER_HALF_WIDTH := 0.22

@export var icon_size := 50.0
@export var margin := 8.0
## Fläche mit dem Ring-Shader
@export var ring: ColorRect

## Drehung des Rads im Bogenmaß. Wird vom TurnWheel getweent.
var angle_offset := 0.0:
	set(value):
		angle_offset = value
		layout_circle()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		layout_circle()

func radius() -> float:
	# Platz für das vergrößerte aktive Icon lassen
	return max(0.0, min(size.x, size.y) / 2.0 - icon_size * 0.7 - margin)

func angle_step() -> float:
	var count := get_child_count()
	return TAU / float(count) if count > 0 else 0.0

func layout_circle():
	var center := size / 2
	var step := angle_step()
	var r := radius()
	if ring:
		var ring_material := ring.material as ShaderMaterial
		ring_material.set_shader_parameter("rect_size", ring.size)
		ring_material.set_shader_parameter("radius", r)
		ring_material.set_shader_parameter("wheel_rotation", -angle_offset)
	queue_redraw()
	var children := get_children()
	for i in range(children.size()):
		var child: Control = children[i]
		var slot: int = child.get_meta("slot", i)
		var angle := -PI / 2 + float(slot) * step - angle_offset
		child.position = center + Vector2(cos(angle), sin(angle)) * r - child.size / 2

## Rundenmarke, liegt hinter den Icons (Kinder werden über dem eigenen _draw gezeichnet)
func _draw() -> void:
	if get_child_count() == 0:
		return
	var angle := -PI / 2 - angle_offset
	var dir := Vector2(cos(angle), sin(angle))
	var side := dir.orthogonal() * icon_size * ROUND_MARKER_HALF_WIDTH
	var base := size / 2 + dir * (radius() + icon_size * ROUND_MARKER_BASE)
	var tip := size / 2 + dir * (radius() + icon_size * ROUND_MARKER_TIP)
	var points := PackedVector2Array([tip, base + side, base - side])
	draw_colored_polygon(points, ROUND_MARKER_COLOR)
	var outline := points.duplicate()
	outline.append(tip)
	draw_polyline(outline, Color.BLACK, 2.0, true)
