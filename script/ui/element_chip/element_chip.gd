extends Control

const DARK_TEXT := Color(0.1, 0.1, 0.12)
const LIGHT_BACKGROUND := 0.6
## Eisenplatte in der Farbe des Elements: feinere Pixel und weniger Flecken als die großen Platten,
## damit die Fläche auf der kleinen Größe ruhig bleibt und die Farbe gut zu erkennen ist
const PLATE_PIXEL_SIZE := 2.0
const PLATE_MOTTLE := 0.12
## Verlauf nach unten; helle Flächen bleiben hell, sonst verliert der dunkle Text an Kontrast
const PLATE_SHADE := 0.3
const PLATE_SHADE_LIGHT := 0.05
const PLATE_RIM_LIGHT := 0.4

@export var label: Label
@export var plate: IronPlate

func _ready() -> void:
	pass
	#_init_label("")
# Called when the node enters the scene tree for the first time.
func _init_color(mon: Monster) -> void:
	label.text = tr(Helper.type_name_by_mon(mon))
	_set_background(Helper.color_by_mon(mon))

func _init_with_element(data) -> void:
	label.text = tr(data.label)
	_set_background(data.color)

func _set_background(color: Color) -> void:
	# auf hellen Farben (Luft) ist weißer Text nicht lesbar
	var light := color.get_luminance() > LIGHT_BACKGROUND
	label.add_theme_color_override("font_color", DARK_TEXT if light else Color.WHITE)
	var plate_material := plate.material as ShaderMaterial
	plate_material.set_shader_parameter("pixel_size", PLATE_PIXEL_SIZE)
	plate_material.set_shader_parameter("mottle", PLATE_MOTTLE)
	plate_material.set_shader_parameter("fill_top", color)
	plate_material.set_shader_parameter("fill_bottom", color.darkened(PLATE_SHADE_LIGHT if light else PLATE_SHADE))
	plate.set_rim(color.lightened(PLATE_RIM_LIGHT))

func _init_label(text: String) -> void:
	label.text = "FIRE"

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
