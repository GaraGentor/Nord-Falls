class_name ElementInfoDialog
extends InfoDialog

## Woraus ein Element besteht: oben groß seine Stufe als Punkte in den Farben der Grundelemente, darunter die
## Rechnung "Feuer + Wasser = Dampf", welche kleineren Verschmelzungen darin stecken und worin es selbst steckt.
## Öffnet sich beim Klick auf einen Element-Chip; die Chips im Dialog lassen sich wieder anklicken.

const ENTRIES_WIDTH := 640.0
const GLYPH_DOT_RADIUS := 12.0
const GLYPH_SPAN := 56.0
const GLYPH_LINE_WIDTH := 2.0
const OPERATOR_FONT_SIZE := 40
## Element-Effekt (_effect_box): dunkle Schrift auf heller Fläche
const EFFECT_TEXT_COLOR := Color(0.13, 0.1, 0.07)
const EFFECT_BORDER := 2
const EFFECT_RADIUS := 10
const EFFECT_PADDING := 14.0

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
	# Glyphe, Name und Stufe bleiben stehen, darunter scrollt alles (mit allen Kombinationen wird es lang)
	content = _scroll_list(content)

	if level >= 2:
		content.add_child(_recipe())
	else:
		content.add_child(_note(tr("ELEMENT_INFO_BASE_DESC"), IronPlate.TEXT_COLOR))
	# was Skills dieses Elements zusätzlich bewirken (ElementEffects)
	var effect := Helper.highlight(ElementEffects.element_effect_text(_mask))
	if effect != "":
		content.add_child(_effect_box(effect))

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
	_add_matchups(lists)

## Element-Effekt auf heller Fläche in der Farbe des Elements mit goldenem Rand, damit die Boni sofort ins Auge fallen
func _effect_box(effect: String) -> Control:
	var box := PanelContainer.new()
	box.size_flags_horizontal = SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = _accent().lightened(0.6)
	style.border_color = SkillDetailPopup.GOLD
	style.set_border_width_all(EFFECT_BORDER)
	style.set_corner_radius_all(EFFECT_RADIUS)
	style.set_content_margin_all(EFFECT_PADDING)
	box.add_theme_stylebox_override("panel", style)
	var label := _note(effect, EFFECT_TEXT_COLOR)
	label.modulate.a = 1.0
	label.add_theme_constant_override("outline_size", 0)
	box.add_child(label)
	return box

## Stärken und Schwächen wie im Biom-Info (BiomeInfoDialog), hier für ein Monster bzw. einen Skill dieses Elements:
## wen seine Angriffe hart treffen, wessen Angriffe es hart treffen und wem es gut standhält.
## Gegen alle Elemente samt Verschmelzungen (sonst klickt man sich durch jedes einzelne), nach Faktor gruppiert.
func _add_matchups(box: VBoxContainer) -> void:
	box.add_child(_section(tr("ELEMENT_INFO_MATCHUPS")))
	var strong := {}
	var weak := {}
	var resists := {}
	for element in _fusions():
		var attack := Skills.element_multiplier(_mask, element)
		if attack > 1.0:
			_group(strong, attack, element)
		var defense := Skills.element_multiplier(element, _mask)
		if defense > 1.0:
			_group(weak, defense, element)
		elif defense < 1.0:
			_group(resists, defense, element)
	_matchup_row(box, tr("ELEMENT_INFO_STRONG"), InfoDialog.STRONG_COLOR, strong, true)
	_matchup_row(box, tr("ELEMENT_INFO_WEAK"), InfoDialog.WEAK_COLOR, weak, true)
	_matchup_row(box, tr("ELEMENT_INFO_RESISTS"), InfoDialog.STRONG_COLOR, resists, false)

static func _group(groups: Dictionary, factor: float, element: int) -> void:
	var key := snappedf(factor, 0.001)
	if not groups.has(key):
		groups[key] = []
	groups[key].append(element)

## Wie _row: je Faktor (der deutlichste zuerst) der Faktor in der Farbe der Zeile, dahinter seine Elemente.
## Faktor und Chips stehen einzeln im Fluss, damit lange Gruppen umbrechen können.
func _matchup_row(box: VBoxContainer, caption: String, color: Color, groups: Dictionary, highest_first: bool) -> void:
	var flow := _captioned_row(box, caption, color, ENTRIES_WIDTH)
	if groups.is_empty():
		flow.add_child(_none_label())
		return
	var factors := groups.keys()
	factors.sort()
	if highest_first:
		factors.reverse()
	for factor: float in factors:
		var label := _text("x" + _factor_text(factor), color, NOTE_FONT_SIZE)
		label.custom_minimum_size.y = 32
		flow.add_child(label)
		for element: int in groups[factor]:
			flow.add_child(_chip_entry(element))

## Bis zu zwei Nachkommastellen, damit x0.25 nicht als x0.3 erscheint
static func _factor_text(factor: float) -> String:
	var text := "%.2f" % factor
	return text.rstrip("0").rstrip(".")

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
