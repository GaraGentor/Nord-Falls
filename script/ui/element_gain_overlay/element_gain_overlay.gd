extends CanvasLayer

## Belohnung für den Aufstieg in ein Kombi-Element: Trinkt ein Monster einen Element-Trank und wird dadurch z. B. von
## Wasser zu Dampf, lernt es den Aufstiegs-Skill dieses Elements (Skills.ascension_skills, Chaos hat keinen).
## Wie bei den Boss-Relikten (BossRelicOverlay) wird alles abgedunkelt, in der Mitte steht die neue Fähigkeit,
## ein Klick auf OK bestätigt. Hat das Monster schon alle Plätze belegt, wählt man stattdessen, welcher Skill weicht.

const SCRIPT_PATH := "res://script/ui/element_gain_overlay/element_gain_overlay.gd"
const THEME := preload("res://script/ui/materials/pixel_font_theme.tres")
const FLAT_BUTTON_THEME := preload("res://script/scenes/battle/flat_button_theme.tres")
## über Dialogen, Shop und Tutorial
const LAYER := 110
const BACKDROP_COLOR := Color(0, 0, 0, 0.8)
const GOLD := Color(0.858824, 0.717647, 0.45098)
const TEXT_COLOR := Color(0.92, 0.9, 0.85)
const FADE_SECONDS := 0.3
const TITLE_FONT_SIZE := 40
const TEXT_FONT_SIZE := 20
const BUTTON_FONT_SIZE := 26
const BUTTON_MIN_WIDTH := 240
const TEXT_WIDTH := 560
const CARD_WIDTH := 280
const CARD_POP_SECONDS := 0.35
const CARD_START_SCALE := 0.6

## Nach dem Trinken aufrufen (old_type = Typ vor dem Trank). Ohne Aufstiegs-Skill passiert nichts.
## Läuft für sich (auch wenn der Dialog mit dem Trank schon zu ist), man muss nicht darauf warten.
static func reward(mon: Monster, old_type: int) -> void:
	if mon._type == old_type:
		return
	var skill := Skills.ascension_skill(mon._type)
	if skill.is_empty() or Skills.knows_skill(mon, skill.name):
		return
	var overlay: CanvasLayer = load(SCRIPT_PATH).new()
	(Engine.get_main_loop() as SceneTree).root.add_child(overlay)
	await overlay._play(mon, skill)
	overlay.queue_free()

var _root: Control

func _play(mon: Monster, skill: Dictionary) -> void:
	layer = LAYER
	_root = Control.new()
	_root.theme = THEME
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var element := tr(ColorMap.get_combo(mon._type).label)
	box.add_child(_label(tr("ELEMENT_GAIN_TITLE").format({"element": element}), TITLE_FONT_SIZE,
		SkillCardPaper.readable_color(Helper.color_by_type(mon._type))))
	var text := _label(tr("ELEMENT_GAIN_TEXT").format({"mon": Helper.mon_battle_name(mon), "element": element}), TEXT_FONT_SIZE, TEXT_COLOR)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = TEXT_WIDTH
	box.add_child(text)

	var card_row := CenterContainer.new()
	card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(card_row)
	var card := EggSkillCard.create(skill, mon)
	card.custom_minimum_size.x = CARD_WIDTH
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0
	card_row.add_child(card)

	var full := mon._skills.size() >= Skills.MAX_SKILLS
	var button_row := CenterContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(button_row)
	var button: Button = null
	var picker: SkillReplacePicker = null
	if full:
		# kein freier Platz: hier entscheidet sich, welcher Skill weicht (Abbrechen = neuen Skill nicht lernen)
		picker = SkillReplacePicker.new(mon)
		var panel := PanelContainer.new()
		IronPlate.frame(panel, picker, 20, 14)
		button_row.add_child(panel)
	else:
		button = _plate_button(tr("ELEMENT_GAIN_OK"))
		button_row.add_child(button)

	_root.modulate.a = 0.0
	await create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SECONDS).finished
	await get_tree().process_frame
	card.pivot_offset = card.size / 2
	card.scale = Vector2.ONE * CARD_START_SCALE
	var pop := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(card, "modulate:a", 1.0, CARD_POP_SECONDS)
	pop.tween_property(card, "scale", Vector2.ONE, CARD_POP_SECONDS)

	var learned := Skills.learnable_copy(skill)
	if full:
		var index: int = await picker.picked
		if index != -1:
			mon._skills[index] = learned
	else:
		await button.pressed
		mon._skills.append(learned)
	await create_tween().tween_property(_root, "modulate:a", 0.0, FADE_SECONDS).finished

## Text-Button auf einer Eisenplatte wie bei den Boss-Relikten, Gold beim Drüberfahren
func _plate_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = FLAT_BUTTON_THEME
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.x = BUTTON_MIN_WIDTH
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, GOLD)
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 24
	padding.content_margin_right = 24
	padding.content_margin_top = 12
	padding.content_margin_bottom = 12
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, padding)
	IronPlate.back(button)
	return button

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
