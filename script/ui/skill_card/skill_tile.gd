class_name SkillTile

## Klickbare Kachel einer Ei-Attacke auf Kartenpapier: Name, Schadensart, Kosten, Abklingzeit, Stärke und Stufe.
## Ei-Attacken-Auswahl und Monster-Dialog auf der Karte.

const HEIGHT := 118.0
const TEXT_COLOR := IronPlate.TEXT_COLOR
const LOCKED_COLOR := Color(0.65, 0.65, 0.65)
const MISSING_COLOR := Color(1, 0.45, 0.45)
const PHYSICAL_TEXTURE := preload("res://assets/ui/icons/fist.svg")
const MAGIC_TEXTURE := preload("res://assets/ui/icons/sparkle.svg")

## locked_label: Text auf gesperrten Attacken (leer = nicht gesperrt)
static func create(skill: Dictionary, mon: Monster, locked_label := "") -> Button:
	var locked := locked_label != ""
	var color := Helper.color_by_type(skill.nature)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE

	# Inhalt als eigene Controls, damit Schadensart und Stärke als Icons erscheinen
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 4)
	margin.add_child(lines)

	var tint := LOCKED_COLOR if locked else TEXT_COLOR
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(name_row)
	var name_label := _label(TranslationServer.translate(skill.name), 18, LOCKED_COLOR if locked else SkillCardPaper.readable_color(color))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(name_label)
	name_row.add_child(_icon(PHYSICAL_TEXTURE if Skills.is_physical(skill) else MAGIC_TEXTURE, 20, tint))

	var stats_row := HBoxContainer.new()
	stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_row.add_theme_constant_override("separation", 6)
	lines.add_child(stats_row)
	stats_row.add_child(_label(TranslationServer.translate("CONFIGURATOR_SKILL_STATS").format({"cost": skill.cost, "cooldown": skill.cooldown}), 16, tint))
	stats_row.add_child(_label(Helper.format_number(skill.value), 16, tint))

	if locked:
		lines.add_child(_label(TranslationServer.translate(locked_label), 15, LOCKED_COLOR))
	else:
		lines.add_child(_label(TranslationServer.translate("CONFIGURATOR_TIER").format({"tier": skill.tier}), 15, TEXT_COLOR))
		if not Skills.can_use(mon, skill):
			# wählbar, aber erst spielbar, wenn das Monster die fehlenden Elemente bekommt (z. B. im Shop)
			lines.add_child(_label(Skills.missing_elements_text(mon, skill), 14, MISSING_COLOR))
	SkillCardPaper.attach(card, skill, locked)
	return card

static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

static func _icon(texture: Texture2D, icon_size: int, color: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = color
	return icon
