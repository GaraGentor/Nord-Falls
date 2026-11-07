extends Control

## Ordnet alle Kinder gleichmäßig auf einem Kreis an.
## Bei angle_offset = 0 steht das erste Kind oben (12 Uhr), die weiteren folgen im Uhrzeigersinn.
## Die Kinder werden nur verschoben, nicht gedreht, damit die Monster aufrecht bleiben.
## Der Platz auf dem Kreis kommt aus dem Meta-Wert "slot", nicht aus der Reihenfolge der Kinder.
## So kann ein Kind zum Zeichnen nach vorne geholt werden, ohne seinen Platz zu verlieren.
## Ring und Pentagramm (wheel_ring.gdshader) liegen dahinter und drehen sich mit.

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
	var children := get_children()
	for i in range(children.size()):
		var child: Control = children[i]
		var slot: int = child.get_meta("slot", i)
		var angle := -PI / 2 + float(slot) * step - angle_offset
		child.position = center + Vector2(cos(angle), sin(angle)) * r - child.size / 2
