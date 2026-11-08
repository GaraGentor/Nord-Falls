class_name ElementInfoDialog
extends InfoDialog

## Woraus ein Element besteht: oben groß seine Stufe als Punkte in den Farben der Grundelemente, darunter die
## Rechnung "Feuer + Wasser = Dampf", welche kleineren Verschmelzungen darin stecken und worin es selbst steckt.
## Öffnet sich beim Klick auf einen Element-Chip; die Chips im Dialog lassen sich wieder anklicken.

const ENTRIES_WIDTH := 420.0
const GLYPH_DOT_RADIUS := 12.0
const GLYPH_SPAN := 56.0
const GLYPH_LINE_WIDTH := 2.0
const OPERATOR_FONT_SIZE := 26

var _mask: int

static func open(host: Node, mask: int) -> InfoDialog:
	return InfoDialog.present(host, ElementInfoDialog.new(mask))

func _init(mask: int) -> void:
	super()
	_mask = mask

func _accent() -> Color:
	return Color(ColorMap.get_combo(_mask).color)

func _build(content: VBoxContainer) -> void:
	var level := ElementGlyph.level(_mask)
	content.add_child(_big_glyph())
	content.add_child(_title(tr(ColorMap.get_combo(_mask).label), _accent().lightened(0.4)))
	var kind := tr("ELEMENT_INFO_BASE") if level == 1 else tr("ELEMENT_INFO_FUSION").format({"count": level})
	var subtitle := _text(tr("ELEMENT_INFO_LEVEL").format({"level": level, "kind": kind}), SkillDetailPopup.GOLD, ROW_FONT_SIZE)
	content.add_child(subtitle)

	if level >= 2:
		content.add_child(_recipe())
	else:
		content.add_child(_note(tr("ELEMENT_INFO_BASE_DESC"), IronPlate.TEXT_COLOR))

	var lists := VBoxContainer.new()
	lists.add_theme_constant_override("separation", 10)
	lists.size_flags_horizontal = SIZE_SHRINK_CENTER
	content.add_child(lists)
	# kleinere Verschmelzungen darin (ab Stufe 3) und die nächstgrößeren, in denen es steckt
	var contains := _fusions().filter(func(other): return other != _mask and other & _mask == other and ElementGlyph.level(other) >= 2)
	var part_of := _fusions().filter(func(other): return other & _mask == _mask and ElementGlyph.level(other) == level + 1)
	if level >= 3:
		_row(lists, tr("ELEMENT_INFO_CONTAINS"), contains)
	if level < 4:
		_row(lists, tr("ELEMENT_INFO_PART_OF"), part_of)

## Stufe groß als Element-Platten (wie die Element-Chips) in den Farben der Grundelemente
func _big_glyph() -> Control:
	var glyph := ElementGlyph.new()
	glyph.dot_radius = GLYPH_DOT_RADIUS
	glyph.span = GLYPH_SPAN
	glyph.line_width = GLYPH_LINE_WIDTH
	glyph.line_color = IronPlate.TEXT_COLOR
	glyph.plates = true
	glyph.mask = _mask
	glyph.size_flags_horizontal = SIZE_SHRINK_CENTER
	return glyph

## "[Feuer] + [Wasser] = [Dampf]"
func _recipe() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = 36
	row.add_theme_constant_override("separation", 10)
	var elements := ElementGlyph.elements_of(_mask)
	for i in elements.size():
		if i > 0:
			row.add_child(_text("+", IronPlate.TEXT_COLOR, OPERATOR_FONT_SIZE))
		RewardDialog.add_element_chip(row, elements[i])
	row.add_child(_text("=", SkillDetailPopup.GOLD, OPERATOR_FONT_SIZE))
	RewardDialog.add_element_chip(row, _mask)
	return row

func _row(box: VBoxContainer, caption: String, masks: Array) -> void:
	var flow := _captioned_row(box, caption, IronPlate.TEXT_COLOR, ENTRIES_WIDTH)
	if masks.is_empty():
		flow.add_child(_none_label())
	for mask in masks:
		flow.add_child(_chip_entry(mask))

## Alle Kombinationen der Grundelemente, nach Stufe sortiert
func _fusions() -> Array:
	var masks := range(1, ElementGlyph.ALL_ELEMENTS + 1)
	masks.sort_custom(func(a, b): return ElementGlyph.level(a) < ElementGlyph.level(b))
	return masks
