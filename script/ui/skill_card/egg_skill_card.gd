class_name EggSkillCard
extends PanelContainer

## Große Karte einer Ei-Attacke für die Ei-Auswahl, aufgebaut wie die Spielkarte im Kampf.
## Kosten, Schadensart und Name stehen fest. Nur die Beschreibung darunter scrollt:
## von selbst, wenn sie nicht passt, und per Mausrad / Leiste auch von Hand. Nach eigenem Scrollen
## setzt das automatische Scrollen erst nach einer Weile Ruhe wieder ein.
## Gesperrte Attacken liegen unter zwei gekreuzten Ketten, mittig steht, wie man sie freischaltet.

const HEIGHT := 210.0
const THEME := preload("res://script/ui/materials/battle_labels.tres")
const MOVES_BADGE := preload("res://script/ui/moves_badge/moves_badge.tscn")
const TEXT_COLOR := IronPlate.TEXT_COLOR
const SUBTLE_COLOR := Color(0.7, 0.68, 0.64)
const MISSING_COLOR := Color(1, 0.45, 0.45)
const LOCKED_TINT := Color(0.5, 0.5, 0.5)
const GOLD := SkillCardPaper.GOLD
## Pixel pro Sekunde beim automatischen Scrollen nach unten, zurück nach oben geht es schneller
const AUTO_SCROLL_SPEED := 14.0
const AUTO_SCROLL_BACK_FACTOR := 4.0
## Pause oben und unten, bevor es weitergeht
const AUTO_SCROLL_PAUSE := 1.6
## so viele Sekunden nach dem letzten eigenen Scrollen setzt das automatische wieder ein
const AUTO_SCROLL_RESUME := 4.0

var _scroll: ScrollContainer
var _paper: SkillCardPaper
## genaue Position des automatischen Scrollens (scroll_vertical kennt nur ganze Pixel)
var _auto_pos := 0.0
## zuletzt selbst gesetzter Wert, weicht scroll_vertical davon ab, hat der Spieler gescrollt
var _set_value := 0
var _direction := 1
var _wait := AUTO_SCROLL_PAUSE
var _idle := AUTO_SCROLL_RESUME

## locked_label/locked_hint: gesperrte Attacke, Texte mittig auf den Ketten (leer = nicht gesperrt)
static func create(skill: Dictionary, mon: Monster, locked_label := "", locked_hint := "") -> EggSkillCard:
	var card := EggSkillCard.new()
	card._build(skill, mon, locked_label, locked_hint)
	return card

func _build(skill: Dictionary, mon: Monster, locked_label: String, locked_hint: String) -> void:
	var locked := locked_label != ""
	theme = THEME
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_paper = SkillCardPaper.attach(self, skill, locked)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_bottom", 11)
	if locked:
		margin.modulate = LOCKED_TINT
	add_child(margin)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 4)
	margin.add_child(lines)

	# oben: Kosten und Schadensart
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(top_row)
	var badge = MOVES_BADGE.instantiate()
	badge.custom_minimum_size = Vector2(30, 28)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.label.add_theme_font_size_override("font_size", 16)
	badge.label.add_theme_constant_override("outline_size", 4)
	badge.show_number(skill.cost, false)
	_ignore_mouse(badge)
	top_row.add_child(badge)
	var type_icon := TextureRect.new()
	type_icon.texture = Skills.kind_icon(skill)
	type_icon.custom_minimum_size = Vector2(22, 22)
	type_icon.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	type_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(type_icon)

	var name_label := _label(tr(skill.name), 18, SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(name_label)
	var info := _label("%s · %s %d" % [tr("CONFIGURATOR_TIER").format({"tier": skill.tier}), tr("SKILL_HEADER_CD"), skill.cooldown], 12, SUBTLE_COLOR)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(info)

	# Mitte: nur die Beschreibung scrollt
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# PASS: Klick und Ziehen gehen weiter an die Karte (Drag & Drop), das Mausrad scrollt den Text
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	lines.add_child(_scroll)
	# wichtige Stellen gelb (Helper.highlight), daher RichTextLabel mit der Schrift der übrigen Labels
	var description := RichTextLabel.new()
	description.bbcode_enabled = true
	description.fit_content = true
	description.scroll_active = false
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_font_override("normal_font", THEME.get_font("font", "Label"))
	description.add_theme_font_size_override("normal_font_size", 13)
	description.add_theme_color_override("default_color", TEXT_COLOR)
	description.text = Helper.skill_description(skill, true)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 1
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(description)

	if not locked and not Skills.can_use(mon, skill):
		# wählbar, aber erst spielbar, wenn das Monster die fehlenden Elemente bekommt (z. B. im Shop)
		var missing := _label(Skills.missing_elements_text(mon, skill), 12, MISSING_COLOR)
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing.custom_minimum_size.x = 1
		lines.add_child(missing)

	if locked:
		set_process(false)
		add_child(_build_lock(locked_label, locked_hint))

## Zwei gekreuzte Ketten über der Karte, mittig eine Plakette mit dem Freischalt-Hinweis
func _build_lock(locked_label: String, locked_hint: String) -> Control:
	var chains := ChainOverlay.new()
	chains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := MarginContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		center.add_theme_constant_override("margin_" + side, 14)
	chains.add_child(center)
	var plate := PanelContainer.new()
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	style.border_color = ChainOverlay.METAL
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", style)
	center.add_child(plate)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override("separation", 4)
	plate.add_child(texts)
	var title := _label(tr(locked_label), 14, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 1
	texts.add_child(title)
	var hint := _label(tr(locked_hint), 12, TEXT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 1
	texts.add_child(hint)
	return chains

## Angeklickte Karte leuchtet am Rahmen
func set_selected(selected: bool) -> void:
	_paper.set_glow(SkillCardPaper.SELECTED_GLOW if selected else 0.0)

func _process(delta: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	var max_scroll := maxf(bar.max_value - bar.page, 0.0)
	if max_scroll < 1.0:
		return
	if _scroll.scroll_vertical != _set_value:
		# der Spieler hat selbst gescrollt: von dort aus später weiter
		_idle = 0.0
		_wait = 0.0
		_set_value = _scroll.scroll_vertical
		_auto_pos = _set_value
		return
	_idle += delta
	if _idle < AUTO_SCROLL_RESUME:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var speed := AUTO_SCROLL_SPEED * (1.0 if _direction > 0 else AUTO_SCROLL_BACK_FACTOR)
	_auto_pos = clampf(_auto_pos + _direction * speed * delta, 0.0, max_scroll)
	if (_direction > 0 and _auto_pos >= max_scroll) or (_direction < 0 and _auto_pos <= 0.0):
		_direction = -_direction
		_wait = AUTO_SCROLL_PAUSE
	_scroll.scroll_vertical = int(_auto_pos)
	_set_value = _scroll.scroll_vertical

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

## Ketten von oben rechts nach unten links und von oben links nach unten rechts.
## Glieder wechseln sich ab: flach liegend (Ring) und hochkant (Strich).
class ChainOverlay extends Control:
	const METAL := Color(0.62, 0.6, 0.57)
	const SHINE := Color(0.88, 0.86, 0.82)
	const SHADOW := Color(0.05, 0.04, 0.04, 0.9)
	const LINK_LENGTH := 26.0
	const LINK_STEP := 19.0
	const SEGMENTS := 16

	func _ready() -> void:
		clip_contents = true
		resized.connect(queue_redraw)

	func _draw() -> void:
		_draw_chain(Vector2(size.x, 0), Vector2(0, size.y))
		_draw_chain(Vector2.ZERO, size)

	func _draw_chain(from: Vector2, to: Vector2) -> void:
		var length := from.distance_to(to)
		if length < 1.0:
			return
		var dir := (to - from) / length
		var perp := Vector2(-dir.y, dir.x)
		var count := maxi(roundi(length / LINK_STEP), 1)
		var step := length / count
		var half := LINK_LENGTH / 2.0
		# erst die flachen Ringe, darüber die hochkant stehenden Glieder, die sie verbinden
		for flat in [true, false]:
			for i in range(0, count + 1):
				if (i % 2 == 0) != flat:
					continue
				var center := from + dir * (i * step)
				if flat:
					var points := PackedVector2Array()
					for s in SEGMENTS + 1:
						var t := TAU * s / SEGMENTS
						points.append(center + dir * cos(t) * half + perp * sin(t) * half * 0.55)
					draw_polyline(points, SHADOW, 6.0, true)
					draw_polyline(points, METAL, 3.0, true)
					# Glanzlicht auf der oberen Hälfte
					draw_polyline(points.slice(SEGMENTS / 2, SEGMENTS + 1), SHINE, 1.0, true)
				else:
					var a := center - dir * half
					var b := center + dir * half
					draw_line(a, b, SHADOW, 7.0, true)
					draw_line(a, b, METAL, 4.0, true)
					draw_line(a + perp, b + perp, SHINE, 1.0, true)
