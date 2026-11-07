class_name SpeechBubble
extends PanelContainer

## Sprechblase eines NPCs: eine Eisenplatte im Pixel-Look, say() blendet den Text ein.
## Der Zipfel zeigt zum NPC, standardmäßig nach rechts: der Host legt die Blase dann links neben dessen Kopf.

const FONT_SIZE := 22
const MARGIN := 16
const TAIL_TEXTURE = preload("res://assets/ui/jailer/bubble_tail.svg")
const TAIL_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const FONT = preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
## der Zipfel überdeckt den Rand der Platte und sitzt auf Höhe des Texts
const TAIL_POSITION := Vector2(-6, 12)
const TAIL_SIZE := Vector2(24, 28)
## Anzeigedauer: Grundzeit plus etwas Lesezeit pro Zeichen
const BASE_SECONDS := 2.5
const SECONDS_PER_CHAR := 0.04
const FADE_SECONDS := 0.2

var _label: Label
var _tween: Tween
var _width: float
## bleibt stehen, bis der nächste Text kommt
var _stays: bool
## NPC steht links der Blase, sie wächst beim Einblenden von dort aus
var _tail_left: bool
## NPC steht unter der Blase (Lagerfeuer), der Host legt sie darüber und sie wächst von unten
var _tail_down: bool
var _tail_holder: Node2D

func _init(width: float, stays := false, tail_left := false, tail_down := false) -> void:
	_width = width
	_stays = stays
	_tail_left = tail_left
	_tail_down = tail_down
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	IronPlate.frame(self, _label, MARGIN, MARGIN)
	_label.custom_minimum_size.x = _width - 2 * MARGIN
	_label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	# Node2D, damit der Container den Zipfel nicht in die Fläche zieht
	_tail_holder = Node2D.new()
	_tail_holder.position = Vector2(-TAIL_POSITION.x - TAIL_SIZE.x, TAIL_POSITION.y) if _tail_left else Vector2(_width, 0) + TAIL_POSITION
	add_child(_tail_holder)
	var tail := TextureRect.new()
	tail.texture = TAIL_TEXTURE
	tail.flip_h = _tail_left
	tail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tail.size = TAIL_SIZE
	tail.material = TAIL_MATERIAL
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail_holder.add_child(tail)
	if _tail_down:
		# gedreht zeigt der Zipfel nach unten, seine Höhe hängt von der Textlänge ab
		_tail_holder.rotation = PI / 2
		tail.position = Vector2(TAIL_POSITION.x, -TAIL_SIZE.y / 2)
		resized.connect(_follow_bottom)

func _follow_bottom() -> void:
	_tail_holder.position = Vector2(size.x / 2, size.y)
	pivot_offset = _tail_holder.position

func say(text: String) -> void:
	_label.text = text
	reset_size()
	visible = true
	if not _tail_down:
		pivot_offset = Vector2.ZERO if _tail_left else Vector2(_width, 0)
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	scale = Vector2(0.9, 0.9)
	_tween = create_tween()
	_tween.set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_property(self, "scale", Vector2.ONE, FADE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _stays:
		return
	_tween.chain().tween_interval(BASE_SECONDS + text.length() * SECONDS_PER_CHAR)
	_tween.chain().tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.chain().tween_callback(hide)
