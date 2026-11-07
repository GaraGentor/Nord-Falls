extends ColorRect

## Rahmen eines Monster-Icons auf dem Rad: pixeliger Ring, ruhig solange das Monster nicht am Zug ist.

const SHADER := preload("res://script/scenes/battle/wheel_icon_frame.gdshader")

## 0 = nicht am Zug, 1 = am Zug. Wird vom TurnWheel getweent.
var active_amount := 0.0:
	set(value):
		active_amount = value
		_frame_material.set_shader_parameter("active_amount", value)

var _frame_material := ShaderMaterial.new()

func _init() -> void:
	_frame_material.shader = SHADER
	material = _frame_material
	resized.connect(func(): _frame_material.set_shader_parameter("rect_size", size))

func setup(frame_color: Color, pulse_color: Color) -> void:
	_frame_material.set_shader_parameter("frame_color", frame_color)
	_frame_material.set_shader_parameter("pulse_color", pulse_color)
