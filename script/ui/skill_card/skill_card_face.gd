class_name SkillCardFace
extends RefCounted

## Gemeinsame Teile aller Skill-Karten (Kampfkarte battle_card, Ei-Karte EggSkillCard, Trainer, Gericht):
##  [Kosten, auf der Ecke] Name
##  Beschreibung …
##            [Wert + Art-Symbol]           (BottomRow, groß und mittig)
##  [Sterne]               [Abklingzeit Uhr]
##                                 [Element]
## Der Wert ist Skills.power_text: Schaden bzw. Schild mit den Werten des Monsters, ohne Monster die Formel.
## Er steht fett und VALUE_SIZE_BONUS größer als der Name (BottomRow.set_value_size).
## Passive, Buffs und Debuffs zeigen dort nur ihr Symbol, alles Weitere steht in der Beschreibung.
## Läuft im Kampf die Abklingzeit, stehen dort die restlichen Züge mit Uhr (BottomRow.show_cooldown).

const MOVES_BADGE := preload("res://script/ui/moves_badge/moves_badge.tscn")
const STAR_TEXTURE := preload("res://assets/ui/icons/rarity_star.svg")
const CLOCK_TEXTURE := preload("res://assets/ui/icons/clock.svg")
const PIXEL_FONT := preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
const STAR_COLOR := Color(0.858824, 0.717647, 0.45098, 1)
const TEXT_COLOR := Color(1.0, 0.95, 0.85)
## Hinweis in der Beschreibung der Kampfkarte, wenn Elemente fehlen oder die Abklingzeit läuft (battle_card).
## Wert, Symbole und Abklingzeit selbst stehen in der Elementfarbe.
const COOLDOWN_COLOR := Color(1, 0.45, 0.45)
const STAR_SIZE := 14.0
const ICON_SIZE := 20.0
const FONT_SIZE := 15
const ELEMENT_FONT_SIZE := 13
## Schrift des Werts, bis die Karte die Größe ihres Namens setzt (BottomRow.set_value_size)
const VALUE_FONT_SIZE := 20
## so viel größer als der Name der Karte steht der Wert
const VALUE_SIZE_BONUS := 2
## Art-Symbol neben dem Wert bzw. allein (Passiv, Buff, Debuff), als Vielfaches der Wert-Schriftgröße
const VALUE_ICON_SCALE := 1.3
const ICON_ONLY_SCALE := 1.8
## Gewicht der variablen Pixelschrift für den fetten Wert (Achse wght, 400 normal bis 700 fett)
const BOLD_WEIGHT := 700

## Kosten-Plakette: ragt gerade über die linke obere Ecke der Karte hinaus
const BADGE_SIZE := Vector2(32, 30)
const BADGE_OFFSET := Vector2(-20, -18)
## so weit rückt der Name nach rechts, damit er neben der Plakette beginnt
const TITLE_INDENT := 16

static var _bold_font: FontVariation

## Pixelschrift in fett, einmal erzeugt und von allen Karten geteilt
static func bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = PIXEL_FONT
		_bold_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): BOLD_WEIGHT}
	return _bold_font

## Kosten-Plakette oben links. Die Zeile selbst ist 0 hoch: die Plakette ragt über die Ecke,
## der Name darunter rückt per set_title neben sie.
class TopRow extends Control:
	var cost_badge: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_badge = SkillCardFace.MOVES_BADGE.instantiate()
		cost_badge.custom_minimum_size = SkillCardFace.BADGE_SIZE
		cost_badge.size = SkillCardFace.BADGE_SIZE
		cost_badge.position = SkillCardFace.BADGE_OFFSET
		cost_badge.label.add_theme_font_size_override("font_size", 16)
		cost_badge.label.add_theme_constant_override("outline_size", 4)
		SkillCardFace.ignore_mouse(cost_badge)
		add_child(cost_badge)

	## Name der Karte linksbündig neben der Plakette
	func set_title(title: Label) -> void:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var style := StyleBoxEmpty.new()
		style.content_margin_left = SkillCardFace.TITLE_INDENT
		title.add_theme_stylebox_override("normal", style)

	## known = false: unbekannter Skill eines Gegners, die Kosten bleiben verborgen.
	## cost >= 0: tatsächliche Kosten für das Monster (Skills.skill_cost), sonst die Grundkosten der Karte
	func show_skill(skill: Dictionary, known := true, cost := -1) -> void:
		cost_badge.show_number(cost if cost >= 0 else skill.cost, false)
		cost_badge.modulate.a = 1.0 if known else 0.0

## Unterer Teil: mittig groß Wert und Art-Symbol, darunter Sterne (Stufe) links und rechts die Abklingzeit
## über dem Element. Sterne und Element sind auch bei unbekannten Skills sichtbar.
class BottomRow extends VBoxContainer:
	var _power: HBoxContainer
	var _value: Label
	var _kind: TextureRect
	var _stars: HBoxContainer
	var _element: Label
	var _cooldown: HBoxContainer
	var _cooldown_label: Label
	var _cooldown_icon: TextureRect
	## Elementfarbe der Karte, auf dem dunklen Papier lesbar: Wert, Symbole und Abklingzeit
	var _nature_color := SkillCardFace.TEXT_COLOR
	var _value_size := SkillCardFace.VALUE_FONT_SIZE
	## nur das Symbol, ohne Wert (Passiv, Buff, Debuff)
	var _icon_only := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 2)
		_power = HBoxContainer.new()
		_power.alignment = BoxContainer.ALIGNMENT_CENTER
		_power.add_theme_constant_override("separation", 4)
		_power.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Trainer vergrößert die Kartenzeilen, Wert und Symbol hängen schon am Namen
		_power.set_meta("keep_font_size", true)
		add_child(_power)
		_value = SkillCardFace.label(SkillCardFace.VALUE_FONT_SIZE, SkillCardFace.TEXT_COLOR)
		_value.add_theme_font_override("font", SkillCardFace.bold_font())
		_power.add_child(_value)
		_kind = SkillCardFace.icon(null, SkillCardFace.ICON_SIZE)
		_power.add_child(_kind)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		_stars = HBoxContainer.new()
		# auf Höhe des Elements
		_stars.size_flags_vertical = Control.SIZE_SHRINK_END
		_stars.add_theme_constant_override("separation", 0)
		_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(_stars)
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override("separation", 0)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(right)
		_cooldown = HBoxContainer.new()
		_cooldown.alignment = BoxContainer.ALIGNMENT_END
		_cooldown.add_theme_constant_override("separation", 3)
		_cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(_cooldown)
		_cooldown_label = SkillCardFace.label(SkillCardFace.FONT_SIZE, SkillCardFace.TEXT_COLOR)
		_cooldown.add_child(_cooldown_label)
		_cooldown_icon = SkillCardFace.icon(SkillCardFace.CLOCK_TEXTURE, SkillCardFace.ICON_SIZE)
		_cooldown.add_child(_cooldown_icon)
		_element = SkillCardFace.label(SkillCardFace.ELEMENT_FONT_SIZE, SkillCardFace.TEXT_COLOR)
		_element.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# lange Kombi-Elemente passen sonst nicht neben die Sterne
		_element.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_element.clip_text = true
		right.add_child(_element)

	## title_size: Schriftgröße des Kartennamens, der Wert steht VALUE_SIZE_BONUS größer
	func set_value_size(title_size: int) -> void:
		_value_size = title_size + SkillCardFace.VALUE_SIZE_BONUS
		_apply_power_size()

	## mon: Besitzer für den Wert (null = Formel).
	## known = false: unbekannter Skill eines Gegners, Wert, Symbol und Abklingzeit bleiben verborgen.
	func show_skill(skill: Dictionary, mon: Monster = null, known := true) -> void:
		for star in _stars.get_children():
			star.queue_free()
		for i in skill.get("tier", 1):
			var star := SkillCardFace.icon(SkillCardFace.STAR_TEXTURE, SkillCardFace.STAR_SIZE)
			star.self_modulate = SkillCardFace.STAR_COLOR
			_stars.add_child(star)
		_nature_color = SkillCardPaper.readable_color(Helper.color_by_type(skill.nature))
		_element.text = tr(ColorMap.get_combo(skill.nature).label)
		_element.add_theme_color_override("font_color", _nature_color)
		# Passive wirken dauerhaft, eine Abklingzeit gibt es dort nicht
		_cooldown.modulate.a = 0.0 if Skills.is_passive(skill) or not known else 1.0
		_cooldown_label.text = str(skill.get("cooldown", 0))
		_cooldown_label.add_theme_color_override("font_color", _nature_color)
		_cooldown_icon.modulate = _nature_color
		# unsichtbar statt ausgeblendet, damit unbekannte Karten gleich hoch bleiben
		_power.modulate.a = 1.0 if known else 0.0
		_icon_only = Skills.shows_only_icon(skill)
		_value.visible = not _icon_only
		_value.text = "" if _icon_only else Skills.power_text(skill, mon)
		_value.add_theme_color_override("font_color", _nature_color)
		_kind.texture = Skills.kind_icon(skill)
		_kind.modulate = _nature_color
		_apply_power_size()

	## Im Kampf bei laufender Abklingzeit: statt Wert und Art die restlichen Züge mit Uhr.
	## Zurück zum Wert mit show_skill.
	func show_cooldown(turns: int) -> void:
		_icon_only = false
		_value.visible = true
		_value.text = str(turns)
		_value.add_theme_color_override("font_color", _nature_color)
		_kind.texture = SkillCardFace.CLOCK_TEXTURE
		_kind.modulate = _nature_color
		_apply_power_size()

	func _apply_power_size() -> void:
		_value.add_theme_font_size_override("font_size", _value_size)
		var scale := SkillCardFace.ICON_ONLY_SCALE if _icon_only else SkillCardFace.VALUE_ICON_SCALE
		var icon_size := roundf(_value_size * scale)
		_kind.custom_minimum_size = Vector2(icon_size, icon_size)

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
	# Platz für den Text: ohne den Einzug neben der Kosten-Plakette (TopRow.set_title)
	var width := title.size.x
	var style := title.get_theme_stylebox("normal")
	if style != null:
		width -= style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
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
