class_name BiomeInfoDialog
extends Control

## Stärken und Schwächen eines Bioms: welche Elemente hier hart treffen bzw. abprallen (Angriff) und welche
## eigenen Elemente hier in Gefahr sind bzw. gut standhalten (Verteidigung). Links zeigt der Element-Kreis,
## woher das kommt. Öffnet sich über BiomeInfoDialog.open auf einer eigenen Ebene über allem anderen.

const LAYER := 50
const RULE_WIDTH := 640.0
const ENTRIES_WIDTH := 460.0
const SECTION_FONT_SIZE := 22
const ROW_FONT_SIZE := 16
const NOTE_FONT_SIZE := 15
const STRONG_COLOR := Color(0.55, 0.9, 0.45)
const WEAK_COLOR := SkillDetailPopup.MISSING_COLOR
const NEUTRAL_COLOR := Color(0.62, 0.62, 0.58)

var _mask: int
var _depth: int
var _panel: PanelContainer

## Öffnet den Dialog für das Biom mask (depth: Tiefe ab 0, -1 = ohne Tiefe im Titel) über host
static func open(host: Node, mask: int, depth := -1) -> BiomeInfoDialog:
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	var dialog := BiomeInfoDialog.new(mask, depth)
	layer.add_child(dialog)
	host.add_child(layer)
	return dialog

func _init(mask: int, depth: int) -> void:
	_mask = mask
	_depth = depth
	theme = RewardDialog.FONT_THEME
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Klick neben das Panel schließt
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)

	var combo := ColorMap.get_combo(_mask)
	var color := Color(combo.color)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	IronPlate.frame(_panel, content, 28, 22).set_rim(color)

	content.add_child(_title(combo, color))
	content.add_child(_elements_row())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	content.add_child(columns)
	var cycle := ElementCycle.new()
	cycle.biome = _mask
	cycle.size_flags_vertical = SIZE_SHRINK_CENTER
	columns.add_child(cycle)
	var lists := VBoxContainer.new()
	lists.add_theme_constant_override("separation", 14)
	lists.size_flags_vertical = SIZE_SHRINK_CENTER
	columns.add_child(lists)
	_add_attack_section(lists)
	_add_defense_section(lists)

	content.add_child(_note(tr("BIOME_INFO_LEGEND"), IronPlate.TEXT_COLOR))
	var close_button := RewardDialog.plate_button(tr("BIOME_INFO_CLOSE"))
	close_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	close_button.focus_mode = FOCUS_NONE
	close_button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	close_button.pressed.connect(close)
	content.add_child(close_button)
	_animate_in.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	# die eigene Ebene geht mit
	get_parent().queue_free()

## Panel federt aus der Mitte auf
func _animate_in() -> void:
	_panel.pivot_offset = _panel.size / 2
	_panel.scale = Vector2(0.9, 0.9)
	_panel.modulate.a = 0
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)

func _title(combo: Dictionary, color: Color) -> Label:
	var title := Label.new()
	title.theme = RewardDialog.LABEL_THEME
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", color.lightened(0.4))
	if _depth >= 0:
		title.text = tr("MAP_HEADER_BIOME").format({"biome": tr(combo.label), "depth": _depth + 1})
	else:
		title.text = tr(combo.label)
	return title

## "Monster hier: [Erde] [Wasser]"
func _elements_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 6)
	row.add_child(_text(tr("BIOME_INFO_ELEMENTS"), IronPlate.TEXT_COLOR, ROW_FONT_SIZE))
	for element in _biome_elements():
		RewardDialog.add_element_chip(row, element)
	return row

## Eigene Angriffe gegen die Monster hier: Element des Angriffs gegen alle Elemente des Bioms
func _add_attack_section(box: VBoxContainer) -> void:
	box.add_child(_section(tr("BIOME_INFO_ATTACK")))
	var strong := []
	var weak := []
	var neutral := []
	for element in Enums.MON_TYPES.values():
		var multiplier := Skills.element_multiplier(element, _mask)
		var entry := [element, "x" + Helper.format_number(multiplier)]
		if multiplier > 1.0:
			strong.append(entry)
		elif multiplier < 1.0:
			weak.append(entry)
		else:
			neutral.append([element, ""])
	box.add_child(_row(tr("BIOME_INFO_STRONG"), STRONG_COLOR, strong))
	box.add_child(_row(tr("BIOME_INFO_WEAK"), WEAK_COLOR, weak))
	if not neutral.is_empty():
		box.add_child(_row(tr("BIOME_INFO_NEUTRAL"), NEUTRAL_COLOR, neutral))

## Eigene Monster eines Elements gegen die Angriffe der Elemente hier
func _add_defense_section(box: VBoxContainer) -> void:
	box.add_child(_section(tr("BIOME_INFO_DEFENSE")))
	var danger := []
	var safe := []
	for element in Enums.MON_TYPES.values():
		for attacker in _biome_elements():
			if Skills.STRONG_AGAINST[attacker] == element:
				danger.append([element, tr("BIOME_INFO_BY").format({"element": tr(ColorMap.get_combo(attacker).label)})])
			elif Skills.STRONG_AGAINST[element] == attacker:
				safe.append([element, tr("BIOME_INFO_AGAINST").format({"element": tr(ColorMap.get_combo(attacker).label)})])
	box.add_child(_row(tr("BIOME_INFO_DANGER"), WEAK_COLOR, danger))
	box.add_child(_row(tr("BIOME_INFO_SAFE"), STRONG_COLOR, safe))

func _biome_elements() -> Array:
	return Enums.MON_TYPES.values().filter(func(element): return _mask & element)

func _section(text: String) -> Label:
	var label := _text(text, SkillDetailPopup.GOLD, SECTION_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

## Beschriftung links, daneben je Eintrag [element, Zusatz] ein Chip mit kleinem Zusatztext
func _row(caption: String, color: Color, entries: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size.y = 32
	var marker := ColorRect.new()
	marker.color = color
	marker.custom_minimum_size = Vector2(6, 0)
	row.add_child(marker)
	var label := _text(caption, color, ROW_FONT_SIZE)
	label.custom_minimum_size.x = 150
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(label)
	# bei vielen Einträgen (Chaos) umbrechen statt den Dialog zu verbreitern
	var flow := HFlowContainer.new()
	flow.custom_minimum_size.x = ENTRIES_WIDTH
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 6)
	row.add_child(flow)
	if entries.is_empty():
		var none := _text(tr("BIOME_INFO_NONE"), NEUTRAL_COLOR, ROW_FONT_SIZE)
		none.custom_minimum_size.y = 32
		flow.add_child(none)
	for entry in entries:
		var item := HBoxContainer.new()
		item.custom_minimum_size.y = 32
		item.add_theme_constant_override("separation", 4)
		RewardDialog.add_element_chip(item, entry[0])
		if entry[1] != "":
			item.add_child(_text(entry[1], color, NOTE_FONT_SIZE))
		flow.add_child(item)
	return row

func _note(text: String, color: Color) -> Label:
	var label := _text(text, color, NOTE_FONT_SIZE)
	label.custom_minimum_size.x = RULE_WIDTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate.a = 0.8
	return label

func _text(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## Element-Kreis Wasser > Feuer > Luft > Erde > Wasser als Raute. Elemente des Bioms leuchten golden,
## Pfeile zu ihnen hin (deine Angriffe treffen hart) sind grün, Pfeile von ihnen weg (Gefahr) rot.
## Auf den farbigen Pfeilen wandern Pixel in Angriffsrichtung, wie die Ketten im Biom-Pfad.
class ElementCycle extends Control:
	const SIZE := Vector2(270, 280)
	const RADIUS := 82.0
	const NODE_SIZE := 40.0
	const PIXEL := 4.0
	const ARROW_GAP := 10.0
	const HEAD := 10.0
	const LINE_WIDTH := 4.0
	const PIXEL_SPEED := 0.6
	const LABEL_FONT_SIZE := 15
	const DIM := Color(0.42, 0.42, 0.4, 0.55)

	var biome := 0
	var _time := 0.0

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	## Reihenfolge im Kreis, beginnend oben mit Wasser, im Uhrzeigersinn
	func _order() -> Array:
		var order := [Enums.MON_TYPES.WATER]
		while order.size() < Skills.STRONG_AGAINST.size():
			order.append(Skills.STRONG_AGAINST[order.back()])
		return order

	func _point(index: int) -> Vector2:
		var angle := -PI / 2 + index * TAU / 4
		return (size / 2 + Vector2(cos(angle), sin(angle)) * RADIUS).round()

	func _draw() -> void:
		var order := _order()
		for i in order.size():
			_draw_arrow(order[i], order[(i + 1) % order.size()], _point(i), _point((i + 1) % order.size()))
		for i in order.size():
			# oben steht der Name über dem Feld, sonst läge er auf den Pfeilen
			_draw_node(order[i], _point(i), i == 0)

	func _draw_arrow(attacker: int, target: int, from: Vector2, to: Vector2) -> void:
		var direction := (to - from).normalized()
		var start := from + direction * (NODE_SIZE / 2 + ARROW_GAP)
		var end := to - direction * (NODE_SIZE / 2 + ARROW_GAP)
		var hits := biome & target != 0
		var threatens := biome & attacker != 0
		var start_color := WEAK_COLOR if threatens else (STRONG_COLOR if hits else DIM)
		var end_color := STRONG_COLOR if hits else (WEAK_COLOR if threatens else DIM)
		var middle := start.lerp(end, 0.5)
		draw_line(start, middle, start_color, LINE_WIDTH)
		draw_line(middle, end - direction * HEAD * 0.5, end_color, LINE_WIDTH)
		var side := direction.orthogonal() * HEAD * 0.7
		draw_colored_polygon(PackedVector2Array([end, end - direction * HEAD + side, end - direction * HEAD - side]), end_color)
		if not (hits or threatens):
			return
		# zwei Pixel wandern versetzt den Pfeil entlang
		for offset in [0.0, 0.5]:
			var t := fmod(_time * PIXEL_SPEED + offset, 1.0)
			var spot := start.lerp(end - direction * HEAD, t).snapped(Vector2(PIXEL, PIXEL))
			draw_rect(Rect2(spot - Vector2(PIXEL, PIXEL) / 2, Vector2(PIXEL, PIXEL)), Color(1, 1, 1, sin(t * PI)))

	func _draw_node(element: int, center: Vector2, label_above: bool) -> void:
		var color := Helper.color_by_type(element)
		var active := biome & element != 0
		var half := Vector2(NODE_SIZE, NODE_SIZE) / 2
		if active:
			# pulsierender goldener Rahmen in groben Pixelschritten
			var grow := roundf((sin(_time * 3.0) * 0.5 + 0.5) * 2.0) * 2.0 + 4.0
			draw_rect(Rect2(center - half - Vector2(grow, grow), half * 2 + Vector2(grow, grow) * 2), SkillDetailPopup.GOLD)
			draw_rect(Rect2(center - half - Vector2(2, 2), half * 2 + Vector2(4, 4)), Color(0.08, 0.08, 0.1))
		var fill := color if active else color.darkened(0.55)
		draw_rect(Rect2(center - half, half * 2), fill)
		# helle Kante oben links, dunkle unten rechts wie bei den Platten
		draw_rect(Rect2(center - half, Vector2(NODE_SIZE, PIXEL)), fill.lightened(0.3))
		draw_rect(Rect2(center - half, Vector2(PIXEL, NODE_SIZE)), fill.lightened(0.3))
		draw_rect(Rect2(center + Vector2(-half.x, half.y - PIXEL), Vector2(NODE_SIZE, PIXEL)), fill.darkened(0.3))
		draw_rect(Rect2(center + Vector2(half.x - PIXEL, -half.y), Vector2(PIXEL, NODE_SIZE)), fill.darkened(0.3))

		var font := get_theme_font("font", "Label")
		var text := tr(ColorMap.get_combo(element).label)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var baseline := center + Vector2(-text_size.x / 2, half.y + 10 + font.get_ascent(LABEL_FONT_SIZE))
		if label_above:
			baseline.y = center.y - half.y - 10 - font.get_descent(LABEL_FONT_SIZE)
		var text_color := color.lightened(0.35) if active else DIM
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, 4, Color.BLACK)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, text_color)
