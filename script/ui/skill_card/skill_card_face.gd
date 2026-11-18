class_name SkillCardFace
extends RefCounted

## Gemeinsame Zeilen aller Skill-Karten (Kampfkarte battle_card, Ei-Karte EggSkillCard):
## oben   [Kosten]        [Sterne = Stufe]        [Abklingzeit Uhr]
## unten  [Icon Gesamtwert]                         [Element]
## Der Gesamtwert ist Skills.power_text: Schaden bzw. Schild mit den Werten des Monsters, ohne Monster die Formel.
## Buffs, Debuffs und Passive zeigen unten links nur ihr Symbol (Skills.kind_icon), ohne Zahl.

const MOVES_BADGE := preload("res://script/ui/moves_badge/moves_badge.tscn")
const STAR_TEXTURE := preload("res://assets/ui/icons/rarity_star.svg")
const CLOCK_TEXTURE := preload("res://assets/ui/icons/clock.svg")
const STAR_COLOR := Color(0.858824, 0.717647, 0.45098, 1)
const TEXT_COLOR := Color(1.0, 0.95, 0.85)
const STAR_SIZE := 14.0
const ICON_SIZE := 20.0
const FONT_SIZE := 15
const ELEMENT_FONT_SIZE := 13

## Obere Zeile: Kosten links, Sterne genau mittig (beide Seiten dehnen sich gleich), Abklingzeit rechts
class TopRow extends HBoxContainer:
	var cost_badge: Control
	var _stars: HBoxContainer
	var _cooldown: HBoxContainer
	var _cooldown_label: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var left := HBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(left)
		cost_badge = SkillCardFace.MOVES_BADGE.instantiate()
		cost_badge.custom_minimum_size = Vector2(30, 28)
		cost_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cost_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost_badge.label.add_theme_font_size_override("font_size", 16)
		cost_badge.label.add_theme_constant_override("outline_size", 4)
		SkillCardFace.ignore_mouse(cost_badge)
		left.add_child(cost_badge)

		_stars = HBoxContainer.new()
		_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_stars.add_theme_constant_override("separation", 0)
		_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_stars)

		_cooldown = HBoxContainer.new()
		_cooldown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cooldown.alignment = BoxContainer.ALIGNMENT_END
		_cooldown.add_theme_constant_override("separation", 3)
		_cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_cooldown)
		_cooldown_label = SkillCardFace.label(SkillCardFace.FONT_SIZE, SkillCardFace.TEXT_COLOR)
		_cooldown.add_child(_cooldown_label)
		_cooldown.add_child(SkillCardFace.icon(SkillCardFace.CLOCK_TEXTURE, SkillCardFace.ICON_SIZE))

	## known = false: unbekannter Skill eines Gegners, nur die Sterne (Stufe) sind sichtbar.
	## cost >= 0: tatsächliche Kosten für das Monster (Skills.skill_cost), sonst die Grundkosten der Karte
	func show_skill(skill: Dictionary, known := true, cost := -1) -> void:
		cost_badge.show_number(cost if cost >= 0 else skill.cost, false)
		cost_badge.modulate.a = 1.0 if known else 0.0
		var tier: int = skill.get("tier", 1)
		for star in _stars.get_children():
			star.queue_free()
		for i in tier:
			var star := SkillCardFace.icon(SkillCardFace.STAR_TEXTURE, SkillCardFace.STAR_SIZE)
			star.self_modulate = SkillCardFace.STAR_COLOR
			_stars.add_child(star)
		# Passive wirken dauerhaft, eine Abklingzeit gibt es dort nicht
		_cooldown.modulate.a = 0.0 if Skills.is_passive(skill) or not known else 1.0
		_cooldown_label.text = str(skill.get("cooldown", 0))

## Untere Zeile: Icon (Skills.kind_icon) mit dem Gesamtwert links, Element rechts.
## Buffs, Debuffs und Passive zeigen nur ihr Icon, ohne Wert.
class BottomRow extends HBoxContainer:
	var _icon: TextureRect
	var _value: Label
	var _element: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 4)
		_icon = SkillCardFace.icon(null, SkillCardFace.ICON_SIZE)
		add_child(_icon)
		_value = SkillCardFace.label(SkillCardFace.FONT_SIZE, SkillCardFace.TEXT_COLOR)
		add_child(_value)
		_element = SkillCardFace.label(SkillCardFace.ELEMENT_FONT_SIZE, SkillCardFace.TEXT_COLOR)
		_element.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_element.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# lange Kombi-Elemente passen sonst nicht neben den Wert
		_element.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_element.clip_text = true
		add_child(_element)

	## known = false: unbekannter Skill eines Gegners, nur das Element ist sichtbar
	func show_skill(skill: Dictionary, mon: Monster, known := true) -> void:
		_icon.texture = Skills.kind_icon(skill) if known else null
		_value.text = Skills.power_text(skill, mon) if known and not Skills.shows_only_icon(skill) else ""
		_value.visible = _value.text != ""
		var element := tr(ColorMap.get_combo(skill.nature).label)
		_element.text = element
		_element.add_theme_color_override("font_color", SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))

## Kleinste Schrift für den Skill-Namen, falls er selbst so nicht in TITLE_MAX_LINES Zeilen passt
const MIN_TITLE_FONT_SIZE := 9
const TITLE_MAX_LINES := 2

## Skill-Name höchstens TITLE_MAX_LINES Zeilen: passt er bei base_size nicht, wird die Schrift kleiner.
## Rechnet bei jeder Größenänderung neu, die Breite steht erst nach dem Layout fest.
static func fit_title(title: Label, base_size: int) -> void:
	title.set_meta("title_base_size", base_size)
	title.max_lines_visible = TITLE_MAX_LINES
	if not title.has_meta("title_fitting"):
		title.set_meta("title_fitting", true)
		title.resized.connect(func(): _refit_title(title))
	_refit_title(title)

static func _refit_title(title: Label) -> void:
	var base: int = title.get_meta("title_base_size")
	var font := title.get_theme_font("font")
	var width := title.size.x
	var font_size := base
	if font != null and width > 1.0:
		while font_size > MIN_TITLE_FONT_SIZE and _line_count(title.text, font, font_size, width) > TITLE_MAX_LINES:
			font_size -= 1
	if title.get_theme_font_size("font_size") != font_size:
		title.add_theme_font_size_override("font_size", font_size)

static func _line_count(text: String, font: Font, font_size: int, width: float) -> int:
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, flags)
	return roundi(text_size.y / font.get_height(font_size))

static func label(font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_constant_override("outline_size", 4)
	result.add_theme_color_override("font_outline_color", Color.BLACK)
	return result

static func icon(texture: Texture2D, icon_size: float) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.custom_minimum_size = Vector2(icon_size, icon_size)
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)
