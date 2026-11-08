class_name IronPlate
extends ColorRect

## Dunkle Eisenplatte als Hintergrund für Schilder, Sprechblasen und Text-Buttons.
## In einem Container füllt sie die Fläche, die Inhalte liegen darüber.

const SHADER = preload("res://script/ui/shader/iron_plate.gdshader")
const RIM := Color(0.31, 0.415, 0.424)
const TEXT_COLOR := Color(0.86, 0.83, 0.72)
## ab dieser Helligkeit gilt eine Füllung als hell (dunkler Text, kaum Verlauf)
const LIGHT_FILL := 0.6
## Element-Platten (tint_element)
const ELEMENT_PIXEL_SIZE := 2.0
const ELEMENT_MOTTLE := 0.12
const ELEMENT_SHADE := 0.3
const ELEMENT_SHADE_LIGHT := 0.05
const ELEMENT_RIM_LIGHT := 0.4

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

## Platte in der Farbe eines Elements wie bei den Element-Chips: feinere Pixel und weniger Flecken als die
## großen Platten, damit die Farbe gut zu erkennen ist. Verlauf nach unten, helle Flächen bleiben hell.
func tint_element(color: Color) -> void:
	var plate_material := material as ShaderMaterial
	plate_material.set_shader_parameter("pixel_size", ELEMENT_PIXEL_SIZE)
	plate_material.set_shader_parameter("mottle", ELEMENT_MOTTLE)
	plate_material.set_shader_parameter("fill_top", color)
	var light := color.get_luminance() > LIGHT_FILL
	plate_material.set_shader_parameter("fill_bottom", color.darkened(ELEMENT_SHADE_LIGHT if light else ELEMENT_SHADE))
	set_rim(color.lightened(ELEMENT_RIM_LIGHT))

## Kleine, ruhige Platte in einer Farbe, z. B. für Kennzeichnungen
func tint(color: Color) -> void:
	var plate_material := material as ShaderMaterial
	plate_material.set_shader_parameter("pixel_size", 2.0)
	plate_material.set_shader_parameter("mottle", 0.12)
	plate_material.set_shader_parameter("fill_top", color)
	plate_material.set_shader_parameter("fill_bottom", color.darkened(0.2))
	set_rim(color.lightened(0.4))
