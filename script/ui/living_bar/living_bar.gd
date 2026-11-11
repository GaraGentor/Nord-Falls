class_name LivingBar
extends Control

## Balken mit lebenden Pixeln (living_bar.gdshader) in einer Eisenplatte: Füllung zittert und flimmert wie die
## Monster, darüber ein heller Streifen und ein Glanz, der regelmäßig über die Füllung läuft.
## Ist er voll, blitzt er auf und leuchtet in voller Farbe (Level-Up-Balken), sonst bleibt er etwas gedämpft.
## Wert 0..1 über share, mit set_share(..., true) animiert.

const FILL_SHADER := preload("res://script/ui/living_bar/living_bar.gdshader")
const TRACK_COLOR := Color(0.024, 0.031, 0.047)
## Innenabstand der Füllung zur Platte
const INSET := 3.0
## Höhe des hellen Streifens oben, Anteil der Füllhöhe
const SHINE_SHARE := 0.3
const SHINE_ALPHA := 0.35
## Glanz: Breite in Pixeln, Sekunden pro Durchlauf und Pause dazwischen
const GLINT_WIDTH := 18.0
const GLINT_SECONDS := 0.9
const GLINT_PAUSE := 1.6
const GLINT_ALPHA := 0.55
## Nicht volle Balken sind etwas dunkler, volle leuchten
const IDLE_SHADE := 0.82
const FLASH_COLOR := Color(2.2, 2.2, 2.2)
const FLASH_SECONDS := 0.45
const TWEEN_SECONDS := 0.5

## Farbe der Füllung, Standard gold wie die Level-Up-Balken
var color := SkillDetailPopup.GOLD:
	set(value):
		color = value
		if _fill:
			_fill.color = color
			_shine.color = Color(color.lightened(0.6), SHINE_ALPHA)
## Aufblitzen und Leuchten, wenn der Balken voll wird
var glow_when_full := true
## Glanz-Durchlauf über die Füllung
var glint := true
var share := 0.0

var _plate: IronPlate
var _clip: Control
var _fill: ColorRect
var _shine: ColorRect
var _glint: ColorRect
var _label: Label
var _time := 0.0
var _tween: Tween

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

func _ready() -> void:
	_plate = IronPlate.new()
	_plate.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_plate)
	var track := ColorRect.new()
	track.color = TRACK_COLOR
	track.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(track)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_clip)
	_fill = ColorRect.new()
	_fill.material = _fill_material()
	_fill.mouse_filter = MOUSE_FILTER_IGNORE
	_clip.add_child(_fill)
	_shine = ColorRect.new()
	_shine.mouse_filter = MOUSE_FILTER_IGNORE
	_clip.add_child(_shine)
	_glint = ColorRect.new()
	_glint.color = Color(1, 1, 1, 0)
	_glint.mouse_filter = MOUSE_FILTER_IGNORE
	_clip.add_child(_glint)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 13)
	add_child(_label)
	color = color
	resized.connect(_layout)
	_layout()
	track.position = Vector2(INSET, INSET)
	resized.connect(func(): track.size = size - Vector2(INSET, INSET) * 2)
	track.size = size - Vector2(INSET, INSET) * 2

## Text mitten auf dem Balken, z. B. "123 / 150"
func set_text(text: String) -> void:
	_label.text = text

func set_share(value: float, animate := false) -> void:
	value = clampf(value, 0.0, 1.0)
	if _tween:
		_tween.kill()
	if not animate or not is_inside_tree():
		_apply_share(value)
		return
	_tween = create_tween()
	_tween.tween_method(_apply_share, share, value, TWEEN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _tween.finished

func _apply_share(value: float) -> void:
	var was_full := share >= 1.0
	share = value
	_layout()
	if glow_when_full and share >= 1.0 and not was_full:
		_flash()

func _flash() -> void:
	_plate.set_rim(SkillDetailPopup.GOLD)
	var flash := create_tween()
	flash.tween_property(_clip, "modulate", FLASH_COLOR, FLASH_SECONDS * 0.3)
	flash.tween_property(_clip, "modulate", Color.WHITE, FLASH_SECONDS * 0.7)

func _layout() -> void:
	if _clip == null:
		return
	var inner := size - Vector2(INSET, INSET) * 2
	_clip.position = Vector2(INSET, INSET)
	_clip.size = Vector2(inner.x * share, inner.y)
	_fill.size = inner
	_shine.size = Vector2(inner.x, roundf(inner.y * SHINE_SHARE))
	_glint.size = Vector2(GLINT_WIDTH, inner.y)
	var full := glow_when_full and share >= 1.0
	_fill.modulate = Color.WHITE if full or not glow_when_full else Color(IDLE_SHADE, IDLE_SHADE, IDLE_SHADE)
	if not full:
		_plate.set_rim(IronPlate.RIM)

func _process(delta: float) -> void:
	if not glint or share <= 0.0:
		_glint.color.a = 0.0
		return
	_time = fmod(_time + delta, GLINT_SECONDS + GLINT_PAUSE)
	var t := _time / GLINT_SECONDS
	if t > 1.0:
		_glint.color.a = 0.0
		return
	var width := _clip.size.x + GLINT_WIDTH
	_glint.position.x = lerpf(-GLINT_WIDTH, width, t)
	_glint.color.a = sin(t * PI) * GLINT_ALPHA

static var _shared_material: ShaderMaterial

## Ein Material für alle Balken, die Farbe kommt über ColorRect.color
static func _fill_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = FILL_SHADER
	return _shared_material
