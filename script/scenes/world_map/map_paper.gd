extends Control

## Das Kartenpapier samt Deko. Liegt hinter dem Inhalt und ragt mit dem Rand über ihn hinaus,
## damit Felder und Boss nicht am ausgefransten Papierrand kleben.

const PAPER_SHADER := preload("res://script/scenes/world_map/map_paper.gdshader")
const PAPER_BLEED := 46.0

var deco_layer: MapDecoLayer

var _paper: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = PAPER_SHADER
	_paper = ColorRect.new()
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.material = _material
	add_child(_paper)
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.offset_left = -PAPER_BLEED
	_paper.offset_top = -PAPER_BLEED
	_paper.offset_right = PAPER_BLEED
	_paper.offset_bottom = PAPER_BLEED
	_paper.resized.connect(func(): _material.set_shader_parameter("rect_size", _paper.size))
	deco_layer = MapDecoLayer.new()
	add_child(deco_layer)

func apply_look(look: Dictionary, rng_seed: int) -> void:
	_material.set_shader_parameter("paper_light", Color(look.paper_light))
	_material.set_shader_parameter("paper_dark", Color(look.paper_dark))
	_material.set_shader_parameter("ink", Color(look.ink))
	_material.set_shader_parameter("contour_amount", look.get("contour", 0.5))
	# Shader-Rauschen rechnet mit kleinen Zahlen genauer
	_material.set_shader_parameter("seed", float(rng_seed % 100))
	var crack: Array = look.get("crack", ["#000000", 0.0, 0.0])
	_material.set_shader_parameter("crack_color", Color(crack[0]))
	_material.set_shader_parameter("crack_amount", crack[1])
	_material.set_shader_parameter("crack_pulse", crack[2])
