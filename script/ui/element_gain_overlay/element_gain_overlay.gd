extends CanvasLayer

## Belohnung für ein neues Element: Trinkt ein Monster einen Element-Trank und wird dadurch z. B. von Wasser zu Dampf,
## darf es eine neue Fähigkeit lernen. Zur Wahl stehen der Aufstiegs-Skill des neuen Kombi-Elements
## (Skills.ascension_skills, Chaos hat keinen) und die Standard-Skills des getrunkenen Grundelements, die zu seinen
## beiden besten Kampfwerten passen (Skills.standard_skills). So kommt man an alle Standard-Skills.
## Wie bei den Boss-Relikten (BossRelicOverlay) wird alles abgedunkelt, in der Mitte stehen die Karten mit je einem
## Lernen-Knopf, darunter "Nichts lernen". Hat das Monster schon alle Plätze belegt, wählt man danach, welcher Skill weicht.

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

## So viele Standard-Skills des neuen Grundelements stehen zur Wahl (nach den besten Kampfwerten des Monsters)
const STANDARD_OFFERS := 2

## Nach dem Trinken aufrufen (old_type = Typ vor dem Trank). Gibt es nichts Neues zu lernen, passiert nichts.
## Läuft für sich (auch wenn der Dialog mit dem Trank schon zu ist), man muss nicht darauf warten.
static func reward(mon: Monster, old_type: int) -> void:
	if mon._type == old_type:
		return
	var offers := offers_for(mon, old_type)
	if offers.is_empty():
		return
	var overlay: CanvasLayer = load(SCRIPT_PATH).new()
	(Engine.get_main_loop() as SceneTree).root.add_child(overlay)
	await overlay._play(mon, offers)
	overlay.queue_free()

## Aufstiegs-Skill (falls es einen gibt) und Standard-Skills der neuen Grundelemente, die das Monster noch nicht kennt
static func offers_for(mon: Monster, old_type: int) -> Array:
	var offers := []
	var ascension := Skills.ascension_skill(mon._type)
	if not ascension.is_empty() and not Skills.knows_skill(mon, ascension.name):
		offers.append(ascension)
	var categories := Skills.categories_by_stat(mon)
	for element in Enums.MON_TYPES.values():
		if not (mon._type & element) or old_type & element:
			continue
		var added := 0
		for category in categories:
			var skill := Skills.standard_skill(element, category)
			if added < STANDARD_OFFERS and not skill.is_empty() and not Skills.knows_skill(mon, skill.name):
				offers.append(skill)
				added += 1
	return offers

var _root: Control

func _play(mon: Monster, offers: Array) -> void:
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

	# eine Spalte pro Angebot: Karte, darunter ihr Lernen-Knopf
	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 24)
	card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(card_row)
	var cards := []
	for i in offers.size():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 12)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_row.add_child(column)
		var card := EggSkillCard.create(offers[i], mon)
		card.custom_minimum_size.x = CARD_WIDTH
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.modulate.a = 0.0
		column.add_child(card)
		cards.append(card)
		var learn := _plate_button(tr("ELEMENT_GAIN_LEARN"))
		learn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		learn.pressed.connect(_chosen.emit.bind(i))
		column.add_child(learn)

	var button_row := CenterContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(button_row)
	var skip := _plate_button(tr("ELEMENT_GAIN_SKIP"))
	skip.pressed.connect(_chosen.emit.bind(-1))
	button_row.add_child(skip)

	_root.modulate.a = 0.0
	await create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SECONDS).finished
	await get_tree().process_frame
	var pop := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for card: Control in cards:
		card.pivot_offset = card.size / 2
		card.scale = Vector2.ONE * CARD_START_SCALE
		pop.tween_property(card, "modulate:a", 1.0, CARD_POP_SECONDS)
		pop.tween_property(card, "scale", Vector2.ONE, CARD_POP_SECONDS)

	var choice: int = await _chosen
	if choice != -1:
		var learned := Skills.learnable_copy(offers[choice])
		if mon._skills.size() >= Skills.MAX_SKILLS:
			# kein freier Platz: hier entscheidet sich, welcher Skill weicht (Abbrechen = neuen Skill nicht lernen)
			card_row.queue_free()
			skip.queue_free()
			var picker := SkillReplacePicker.new(mon)
			var panel := PanelContainer.new()
			IronPlate.frame(panel, picker, 20, 14)
			button_row.add_child(panel)
			var index: int = await picker.picked
			if index != -1:
				mon._skills[index] = learned
		else:
			mon._skills.append(learned)
	await create_tween().tween_property(_root, "modulate:a", 0.0, FADE_SECONDS).finished

## Index des gewählten Angebots, -1 = nichts lernen
signal _chosen(index: int)

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
