class_name LivingBar
extends Control

## Balken mit lebenden Pixeln, Wert 0..1 über share (mit set_share(..., true) animiert). Zwei Looks:
## - Standard (Level-Up): Füllung mit living_bar.gdshader (Verlauf, Funken) in einer Eisenplatte, heller Streifen
##   und Glanz, der regelmäßig darüberläuft. Voll blitzt er auf und leuchtet, sonst bleibt er etwas gedämpft.
## - battle_look (KP-Leisten wie im Kampf, BattleMonCard): dunkle Spur, Füllung mit hp_bar_material, ohne Platte und Glanz.

const FILL_SHADER := preload("res://script/ui/living_bar/living_bar.gdshader")
const BATTLE_MATERIAL := preload("res://script/ui/shader/hp_bar_material.tres")
const TRACK_COLOR := Color(0.024, 0.031, 0.047)
## Innenabstand der Füllung zur Platte (battle_look: keiner)
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
const FONT_SIZE := 13

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
## Aussehen der KP-Leisten im Kampf (vor dem Einhängen setzen)
var battle_look := false
var font_size := FONT_SIZE
var share := 0.0

var _plate: IronPlate
var _track: ColorRect
var _clip: Control
var _fill: ColorRect
var _shine: ColorRect
var _glint: ColorRect
var _label: Label
var _text := ""
var _time := 0.0
var _tween: Tween

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

## KP-Leiste wie im Kampf: Farbe nach Anteil (grün, orange, rot) und "aktuell / max" darauf
static func hp_bar(current: float, max_hp: float, text := "") -> LivingBar:
	var bar := LivingBar.new()
	bar.battle_look = true
	bar.glow_when_full = false
	bar.glint = false
	bar.set_hp(current, max_hp, text)
	return bar

func set_hp(current: float, max_hp: float, text := "", animate := false) -> void:
	var value := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0 else 0.0
	color = BattleMonCard.hp_color(value)
	set_text(text if text != "" else "%d / %d" % [roundi(current), roundi(max_hp)])
	set_share(value, animate)

func _ready() -> void:
	if not battle_look:
		_plate = IronPlate.new()
		_plate.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(_plate)
	_track = ColorRect.new()
	_track.color = TRACK_COLOR
	_track.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_track)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_clip)
	_fill = ColorRect.new()
	_fill.material = BATTLE_MATERIAL if battle_look else _fill_material()
	_fill.mouse_filter = MOUSE_FILTER_IGNORE
	_clip.add_child(_fill)
	_shine = ColorRect.new()
	_shine.mouse_filter = MOUSE_FILTER_IGNORE
	_shine.visible = not battle_look
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
	_label.add_theme_font_size_override("font_size", font_size)
	_label.text = _text
	add_child(_label)
	color = color
	resized.connect(_layout)
	_layout()

## Text mitten auf dem Balken, z. B. "123 / 150"
func set_text(text: String) -> void:
	_text = text
	if _label:
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
	if glow_when_full and share >= 1.0 and not was_full and _clip:
		_flash()

func _flash() -> void:
	if _plate:
		_plate.set_rim(SkillDetailPopup.GOLD)
	var flash := create_tween()
	flash.tween_property(_clip, "modulate", FLASH_COLOR, FLASH_SECONDS * 0.3)
	flash.tween_property(_clip, "modulate", Color.WHITE, FLASH_SECONDS * 0.7)

func _layout() -> void:
	if _clip == null:
		return
	var inset := 0.0 if battle_look else INSET
	var inner := size - Vector2(inset, inset) * 2
	_track.position = Vector2(inset, inset)
	_track.size = inner
	_clip.position = Vector2(inset, inset)
	_clip.size = Vector2(inner.x * share, inner.y)
	_fill.size = inner
	_shine.size = Vector2(inner.x, roundf(inner.y * SHINE_SHARE))
	_glint.size = Vector2(GLINT_WIDTH, inner.y)
	var full := glow_when_full and share >= 1.0
	_fill.modulate = Color.WHITE if full or not glow_when_full else Color(IDLE_SHADE, IDLE_SHADE, IDLE_SHADE)
	if _plate and not full:
		_plate.set_rim(IronPlate.RIM)

func _process(delta: float) -> void:
	if _glint == null:
		return
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
