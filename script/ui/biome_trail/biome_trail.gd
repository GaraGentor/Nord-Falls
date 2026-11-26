class_name BiomeTrail
extends VBoxContainer

## Kompakter Biom-Pfad für den Karten-Header: oben ein Kästchen pro Biom in seiner Farbe, durch Linien
## verbunden, das aktuelle mit doppeltem Rahmen; darunter "Pfad: <aktuelles Biom>".
## Klick öffnet den großen Pfad (BiomePathDialog).

const BOX := 20.0
const GAP := 30.0
const LINE_WIDTH := 2.0
## doppelter Rahmen ums aktuelle Biom: dunkle Lücke, dann heller Ring
const RING_GAP := 3.0
const RING_WIDTH := 2.0
const PASSED_DARKEN := 0.45
const FUTURE_ALPHA := 0.9
const LABEL_FONT_SIZE := 24
const HOVER_MODULATE := Color(1.25, 1.25, 1.15)

var _biomes: Array = []
var _current := 0
var _dots: Control
var _label: RichTextLabel

func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dots.draw.connect(_draw_dots)
	add_child(_dots)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.scroll_active = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", LABEL_FONT_SIZE)
	add_child(_label)

	mouse_entered.connect(func(): modulate = HOVER_MODULATE)
	mouse_exited.connect(func(): modulate = Color.WHITE)
	gui_input.connect(_on_input)

## biomes: Element-Masken aller Tiefen, current: Tiefe ab 0, in der man gerade ist
func show_path(biomes: Array, current: int) -> void:
	_biomes = biomes
	_current = current
	var count := biomes.size()
	var pad := RING_GAP + RING_WIDTH
	_dots.custom_minimum_size = Vector2(count * BOX + maxi(count - 1, 0) * GAP + pad * 2, BOX + pad * 2)
	_dots.queue_redraw()

	var label_text := ""
	if current >= 0 and current < count:
		var combo = ColorMap.get_combo(biomes[current])
		label_text = "[color=#%s]%s[/color] [color=#%s]%s[/color]" % [
			SkillDetailPopup.GOLD.to_html(false), tr("MAP_HEADER_ROUTE"),
			Color(combo.color).lightened(0.4).to_html(false), tr(combo.label)]
	_label.text = label_text
	tooltip_text = tr("MAP_PATH_HINT")

func _draw_dots() -> void:
	var count := _biomes.size()
	if count == 0:
		return
	var pad := RING_GAP + RING_WIDTH
	var y := pad + BOX / 2
	# Linien zuerst, die Kästchen liegen darüber
	for i in range(1, count):
		var from := Vector2(pad + (i - 1) * (BOX + GAP) + BOX, y)
		var to := Vector2(pad + i * (BOX + GAP), y)
		var line_color := Color(IronPlate.TEXT_COLOR, 0.85 if i <= _current else 0.3)
		_dots.draw_line(from, to, line_color, LINE_WIDTH)
	for i in count:
		var color := Color(ColorMap.get_combo(_biomes[i]).color)
		if i < _current:
			color = color.darkened(PASSED_DARKEN)
		elif i > _current:
			color.a = FUTURE_ALPHA
		var rect := Rect2(pad + i * (BOX + GAP), pad, BOX, BOX)
		_dots.draw_rect(rect, color)
		_dots.draw_rect(rect, Color(0, 0, 0, 0.6), false, 1.0)
		if i == _current:
			var ring := rect.grow(RING_GAP + RING_WIDTH / 2)
			_dots.draw_rect(ring, color.lightened(0.5), false, RING_WIDTH)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		BiomePathDialog.open(self, _biomes, _current)
