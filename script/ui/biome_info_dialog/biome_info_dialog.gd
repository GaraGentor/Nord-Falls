class_name BiomeInfoDialog
extends InfoDialog

## Stärken und Schwächen eines Bioms: welche Elemente hier hart treffen bzw. abprallen (Angriff) und welche
## eigenen Elemente hier in Gefahr sind bzw. gut standhalten (Verteidigung). Links zeigt der Element-Kreis,
## woher das kommt.

const ENTRIES_WIDTH := 460.0

var _mask: int
var _depth: int

## Öffnet den Dialog für das Biom mask (depth: Tiefe ab 0, -1 = ohne Tiefe im Titel) über host
static func open(host: Node, mask: int, depth := -1) -> InfoDialog:
	return InfoDialog.present(host, BiomeInfoDialog.new(mask, depth))

func _init(mask: int, depth: int) -> void:
	super()
	_mask = mask
	_depth = depth

func _accent() -> Color:
	return Color(ColorMap.get_combo(_mask).color)

func _build(content: VBoxContainer) -> void:
	var combo := ColorMap.get_combo(_mask)
	var title := tr(combo.label)
	if _depth >= 0:
		title = tr("MAP_HEADER_BIOME").format({"biome": title, "depth": _depth + 1})
	content.add_child(_title(title, _accent().lightened(0.4)))
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

## "Monster hier: [Erde] [Wasser]"
func _elements_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 6)
	row.add_child(_text(tr("BIOME_INFO_ELEMENTS"), IronPlate.TEXT_COLOR, ROW_FONT_SIZE))
	for element in ElementGlyph.elements_of(_mask):
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
	_row(box, tr("BIOME_INFO_STRONG"), STRONG_COLOR, strong)
	_row(box, tr("BIOME_INFO_WEAK"), WEAK_COLOR, weak)
	if not neutral.is_empty():
		_row(box, tr("BIOME_INFO_NEUTRAL"), NEUTRAL_COLOR, neutral)

## Eigene Monster eines Elements gegen die Angriffe der Elemente hier
func _add_defense_section(box: VBoxContainer) -> void:
	box.add_child(_section(tr("BIOME_INFO_DEFENSE")))
	var danger := []
	var safe := []
	for element in Enums.MON_TYPES.values():
		for attacker in ElementGlyph.elements_of(_mask):
			if Skills.STRONG_AGAINST[attacker] == element:
				danger.append([element, tr("BIOME_INFO_BY").format({"element": tr(ColorMap.get_combo(attacker).label)})])
			elif Skills.STRONG_AGAINST[element] == attacker:
				safe.append([element, tr("BIOME_INFO_AGAINST").format({"element": tr(ColorMap.get_combo(attacker).label)})])
	_row(box, tr("BIOME_INFO_DANGER"), WEAK_COLOR, danger)
	_row(box, tr("BIOME_INFO_SAFE"), STRONG_COLOR, safe)

## Beschriftete Zeile, je Eintrag [element, Zusatz] ein Chip mit kleinem Zusatztext
func _row(box: VBoxContainer, caption: String, color: Color, entries: Array) -> void:
	var flow := _captioned_row(box, caption, color, ENTRIES_WIDTH)
	if entries.is_empty():
		flow.add_child(_none_label())
	for entry in entries:
		flow.add_child(_chip_entry(entry[0], entry[1], color))

## Element-Kreis Wasser > Feuer > Luft > Erde > Wasser als Raute. Die Elemente sind Platten wie die
## Element-Chips, die des Bioms leuchten golden, die anderen sind abgedunkelt. Pfeile zu ihnen hin
## (deine Angriffe treffen hart) sind grün, Pfeile von ihnen weg (Gefahr) rot.
## Auf den farbigen Pfeilen wandern Pixel in Angriffsrichtung, wie die Ketten im Biom-Pfad.
class ElementCycle extends Control:
	const SIZE := Vector2(270, 280)
	const RADIUS := 82.0
	const NODE_SIZE := 40.0
	const PIXEL := 2.0
	const ARROW_GAP := 10.0
	const HEAD := 8.0
	const LINE_WIDTH := 2.0
	const PIXEL_SPEED := 0.6
	const LABEL_FONT_SIZE := 15
	const DIM := Color(0.42, 0.42, 0.4, 0.55)
	const INACTIVE_DARKEN := 0.55

	var biome := 0:
		set(value):
			biome = value
			_tint_plates()
	var _time := 0.0
	var _plates: Array[IronPlate] = []

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = TEXTURE_FILTER_NEAREST
		for i in ElementGlyph.level(ElementGlyph.ALL_ELEMENTS):
			var plate := IronPlate.new()
			plate.size = Vector2(NODE_SIZE, NODE_SIZE)
			add_child(plate)
			_plates.append(plate)
		_tint_plates()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
			for i in _plates.size():
				_plates[i].position = _point(i) - Vector2(NODE_SIZE, NODE_SIZE) / 2

	## Platten in der Farbe ihres Elements wie die Element-Chips, nicht betroffene abgedunkelt
	func _tint_plates() -> void:
		var order := ElementGlyph.elements_of(ElementGlyph.ALL_ELEMENTS)
		for i in _plates.size():
			var color := Helper.color_by_type(order[i])
			_plates[i].tint_element(color if biome & order[i] else color.darkened(INACTIVE_DARKEN))

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _point(index: int) -> Vector2:
		var angle := -PI / 2 + index * TAU / 4
		return (size / 2 + Vector2(cos(angle), sin(angle)) * RADIUS).round()

	func _draw() -> void:
		# alle Grundelemente, beginnend oben mit Wasser, im Uhrzeigersinn
		var order := ElementGlyph.elements_of(ElementGlyph.ALL_ELEMENTS)
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
			# pulsierender goldener Rahmen in groben Pixelschritten, die Platte liegt darüber
			var grow := roundf((sin(_time * 3.0) * 0.5 + 0.5) * 2.0) * 2.0 + 2.0
			draw_rect(Rect2(center - half - Vector2(grow, grow), half * 2 + Vector2(grow, grow) * 2), SkillDetailPopup.GOLD, false, PIXEL)

		var font := get_theme_font("font", "Label")
		var text := tr(ColorMap.get_combo(element).label)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var baseline := center + Vector2(-text_size.x / 2, half.y + 10 + font.get_ascent(LABEL_FONT_SIZE))
		if label_above:
			baseline.y = center.y - half.y - 10 - font.get_descent(LABEL_FONT_SIZE)
		var text_color := color.lightened(0.35) if active else DIM
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, 4, Color.BLACK)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, text_color)
