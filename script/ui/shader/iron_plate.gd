class_name IronPlate
extends ColorRect

## Dunkle Eisenplatte als Hintergrund für Schilder, Sprechblasen und Text-Buttons.
## In einem Container füllt sie die Fläche, die Inhalte liegen darüber.

const SHADER = preload("res://script/ui/shader/iron_plate.gdshader")
const RIM := Color(0.31, 0.415, 0.424)
const TEXT_COLOR := Color(0.86, 0.83, 0.72)

## Macht panel zur Platte: sie füllt die ganze Fläche, nur content bekommt den Innenabstand
static func frame(panel: PanelContainer, content: Control, margin_x: int, margin_y: int) -> IronPlate:
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var plate := IronPlate.new()
	panel.add_child(plate)
	var margins := MarginContainer.new()
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_theme_constant_override("margin_left", margin_x)
	margins.add_theme_constant_override("margin_right", margin_x)
	margins.add_theme_constant_override("margin_top", margin_y)
	margins.add_theme_constant_override("margin_bottom", margin_y)
	margins.add_child(content)
	panel.add_child(margins)
	return plate

## Platte hinter einem Control ohne Container-Layout, z. B. einem Button
static func back(control: Control) -> IronPlate:
	var plate := IronPlate.new()
	plate.show_behind_parent = true
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.add_child(plate)
	return plate

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_material := ShaderMaterial.new()
	plate_material.shader = SHADER
	material = plate_material

func set_rim(rim: Color) -> void:
	(material as ShaderMaterial).set_shader_parameter("rim_color", rim)

## Kleine, ruhige Platte in einer Farbe, z. B. für Kennzeichnungen
func tint(color: Color) -> void:
	var plate_material := material as ShaderMaterial
	plate_material.set_shader_parameter("pixel_size", 2.0)
	plate_material.set_shader_parameter("mottle", 0.12)
	plate_material.set_shader_parameter("fill_top", color)
	plate_material.set_shader_parameter("fill_bottom", color.darkened(0.2))
	set_rim(color.lightened(0.4))
