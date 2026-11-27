class_name SurrenderFlag
extends PanelContainer

## Unterhosen-Flagge in der unteren Leiste des Kampfs (zwischen Geschwindigkeit/Auto und Hypnose, battle.gd
## _build_bottom_bar): Kampf aufgeben. pressed meldet den Klick, die Sicherheitsabfrage stellt battle.gd.
## Gleicher Stil wie die Knöpfe von BattleControls, so hoch wie deren beide Knöpfe übereinander.
## Statt eines weißen Tuchs hängt eine Unterhose an der Stange, als Pixel-Art mit "Lebende Pixel"-Shader.

signal pressed

const SIZE := Vector2(56, BattleControls.SIZE.y * 2 + 6)
## Bildschirmpixel pro Bildpixel der Pixel-Art
const ART_PIXEL := 2.0
const POLE_LIGHT := Color8(150, 116, 78)
const POLE_SHADE := Color8(104, 78, 50)
const KNOB := Color8(214, 176, 82)
const ROPE := Color8(190, 170, 130)
const CLOTH_LIGHT := Color8(250, 248, 240)
const CLOTH_MID := Color8(226, 222, 210)
const CLOTH_SHADE := Color8(186, 180, 166)
const BAND := Color8(120, 160, 210)
const BAND_SHADE := Color8(86, 120, 170)
const HEART := Color8(222, 64, 84)
const OUTLINE := Color8(36, 30, 28)
## "K" Knauf, "P" Stange, "r" Schnur, "B" Bund, "#" Stoff, "s" Naht, "h" Herzchen
const ART := [
	"KK....................",
	"KK....................",
	"PPr.BBBBBBBBBBBBBBB...",
	"PP.rBBBBBBBBBBBBBBB...",
	"PP.r###############...",
	"PPr.#####h####h####...",
	"PP..###############...",
	"PP..#######s#######...",
	"PP..###h###s###h###...",
	"PP...######s######....",
	"PP....#####s#####.....",
	"PP......###s###.......",
	"PP.......#####........",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
	"PP....................",
]

static var _texture: ImageTexture
static var _material: ShaderMaterial

var _style: StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = SIZE
	_style = StyleBoxFlat.new()
	_style.bg_color = BattleControls.BACKGROUND
	_style.border_color = BattleControls.BORDER
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", _style)
	tooltip_text = tr("BATTLE_SURRENDER_TOOLTIP")
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): _style.border_color = BattleControls.BORDER_HOVER)
	mouse_exited.connect(func(): _style.border_color = BattleControls.BORDER)
	var art := TextureRect.new()
	art.texture = texture()
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.custom_minimum_size = art.texture.get_size() * ART_PIXEL
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.material = living_material()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		pressed.emit()

## Lebende Pixel mit einem Partikel je Bildpixel, sonst verwischt die kleine Pixel-Art
static func living_material() -> ShaderMaterial:
	if _material == null:
		_material = Monmap.LIVING_MATERIAL.duplicate()
		_material.set_shader_parameter("pixel_size", ART_PIXEL)
		_material.set_shader_parameter("min_cells", 8.0)
		_material.set_shader_parameter("amplitude", 0.12)
	return _material

## Stange mit Unterhose, Pixel für Pixel erzeugt; Stoff oben hell, unten schattiert, außen ein dunkler Umriss
static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image())
	return _texture

static func _image() -> Image:
	var w: int = ART[0].length()
	var h: int = ART.size()
	var image := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := _color(x, y)
			if c.a > 0.0:
				image.set_pixel(x + 1, y + 1, c)
	var outline: Array[Vector2i] = []
	for y in h + 2:
		for x in w + 2:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var n: Vector2i = Vector2i(x, y) + d
				# die dünne Schnur bekommt keinen Umriss, sonst wird sie zum Klotz
				if n.x >= 0 and n.y >= 0 and n.x < w + 2 and n.y < h + 2 and image.get_pixelv(n).a > 0.0 \
						and _char(n.x - 1, n.y - 1) != "r":
					outline.append(Vector2i(x, y))
					break
	for p in outline:
		image.set_pixelv(p, OUTLINE)
	return image

static func _char(x: int, y: int) -> String:
	if x < 0 or y < 0 or y >= ART.size() or x >= ART[y].length():
		return "."
	return ART[y][x]

static func _cloth(x: int, y: int) -> bool:
	return _char(x, y) in ["#", "s", "h"]

static func _color(x: int, y: int) -> Color:
	match _char(x, y):
		"K":
			return KNOB
		"P":
			return POLE_LIGHT if _char(x - 1, y) != "P" else POLE_SHADE
		"r":
			return ROPE
		"B":
			return BAND if _char(x, y - 1) != "B" else BAND_SHADE
		"h":
			return HEART
		"s":
			return CLOTH_SHADE
		"#":
			if not _cloth(x, y + 1) or not _cloth(x + 1, y) or not _cloth(x - 1, y):
				return CLOTH_SHADE
			return CLOTH_LIGHT if _char(x, y - 1) == "B" else CLOTH_MID
	return Color(0, 0, 0, 0)
