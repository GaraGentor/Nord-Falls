class_name JudgementDialog
extends Control

## Modaler Dialog im Judgement-Screen: zu vergessende Attacke wählen (Einverleiben, Skill-Belohnungen),
## auch für ein Erbstück im Letzten Willen (last_will_screen.gd), und einfache Rückfragen.
## Alle Abläufe laufen per await und liefern das Ergebnis zurück.

signal _choice(result: Dictionary)

const GOLD := SkillDetailPopup.GOLD
const TEXT_COLOR := IronPlate.TEXT_COLOR
const MUTED := IronPlate.TEXT_COLOR
const FLAT_THEME = preload("res://script/scenes/battle/flat_button_theme.tres")
const PANEL_WIDTH := 900.0
## Skill-Karten mit Kopf- und Fußzeile (SkillCardFace) brauchen etwas mehr Höhe als die übrigen Karten
const SKILL_CARD_HEIGHT := 185.0
## Platz für Überschrift, Hinweis, Knöpfe und Ränder; der Rest der Bildschirmhöhe gehört den Karten (scrollt)
const SCROLL_RESERVED_HEIGHT := 300.0
const MIN_SCROLL_HEIGHT := 200.0

var _panel: PanelContainer
var _title: Label
var _warning: Label
var _content: HFlowContainer
var _scroll: ScrollContainer
var _cancel: Button
var _confirm: Button

func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	IronPlate.frame(_panel, box, 20, 20)

	_title = _label(32, GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_warning = _label(24, GOLD)
	box.add_child(_warning)
	# viele Karten scrollen, statt den Dialog über den Bildschirm wachsen zu lassen
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	# auf dem Handy fangen die Karten den Finger ab, ohne DragScroll käme Godots Touch-Scroll nie an
	DragScroll.attach(_scroll)
	_content = HFlowContainer.new()
	_content.alignment = FlowContainer.ALIGNMENT_CENTER
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	_content.add_theme_constant_override("h_separation", 12)
	_content.add_theme_constant_override("v_separation", 12)
	# Platz für die Rand-Effekte der Skill-Karten (SkillCardPaper.FLAME_PAD), sonst schneidet die Scrollview sie ab
	var flame_margin := SkillCardPaper.flame_margin()
	flame_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(flame_margin)
	flame_margin.add_child(_content)
	_content.minimum_size_changed.connect(_fit_scroll)
	get_viewport().size_changed.connect(_fit_scroll)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_cancel = _action_button("COMMON_CANCEL", {"cancel": true})
	_confirm = _action_button("", {"confirm": true})
	_confirm.add_theme_color_override("font_color", GOLD)
	for button in [_cancel, _confirm]:
		buttons.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_choice.emit({"cancel": true})
		get_viewport().set_input_as_handled()

## Nur die Wahl, welcher Skill für skill weicht (Skill-Belohnung, Trainer, neues Element über SkillReplacePicker):
## Liefert den Index oder -1 bei Abbruch.
func pick_replace(mon: Monster, skill: Dictionary) -> int:
	_reset("")
	_title.text = tr("JUDGEMENT_TEACH_PICK_REPLACE").format({
		"mon": Helper.mon_battle_name(mon), "max": Skills.MAX_SKILLS, "skill": _skill_name(skill)})
	for i in mon._skills.size():
		var card = _skill_card(mon._skills[i], "", mon)
		card.pressed.connect(_choice.emit.bind({"value": i}))
	visible = true
	var result: Dictionary = await _choice
	visible = false
	return result.get("value", -1)

func confirm(title: String, text: String, confirm_label: String) -> bool:
	_reset(text)
	_title.text = title
	_confirm.visible = true
	_confirm.text = confirm_label
	visible = true
	var result: Dictionary = await _choice
	visible = false
	return result.has("confirm")

# ─────────────────────────
# Aufbau

## Karten so hoch wie nötig, höchstens bis der Dialog den Bildschirm füllt, darüber scrollen sie
func _fit_scroll() -> void:
	var limit := maxf(get_viewport_rect().size.y - SCROLL_RESERVED_HEIGHT, MIN_SCROLL_HEIGHT)
	_scroll.custom_minimum_size.y = minf(_content.get_parent().get_combined_minimum_size().y, limit)

func _reset(warning: String) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	_warning.text = warning
	_warning.visible = warning != ""
	_confirm.visible = false
	_cancel.text = "COMMON_CANCEL"
	_panel.custom_minimum_size.x = PANEL_WIDTH

func _skill_name(skill: Dictionary) -> String:
	return tr(skill.name) if skill.get("scouted", true) else tr("BATTLE_UNKNOWN_SKILL").format(skill)

## Aufbau wie die Kampfkarte (SkillCardFace): oben Kosten, Sterne, Abklingzeit, unten Gesamtwert und Element.
## mon: Besitzer für den Gesamtwert (null = Formel). Unbekannte Skills zeigen nur Sterne und Element.
func _skill_card(skill: Dictionary, note: String, mon: Monster = null) -> Button:
	var card := _card(Vector2(270, SKILL_CARD_HEIGHT))
	var lines := _card_lines(card)
	var scouted: bool = skill.get("scouted", true)
	var top_row := SkillCardFace.TopRow.new()
	lines.add_child(top_row)
	top_row.show_skill(skill, scouted)
	var name_label := _label(SkillCardFace.TITLE_SIZE, SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))
	name_label.text = _skill_name(skill)
	lines.add_child(name_label)
	# einheitliche Titelgröße, höchstens zwei Zeilen, lange Namen werden kleiner
	top_row.set_title(name_label)
	var desc := _label(SkillCardFace.TEXT_SIZE, MUTED)
	desc.max_lines_visible = 3
	desc.size_flags_vertical = SIZE_EXPAND_FILL
	desc.text = Helper.skill_description(skill) if scouted else tr("BATTLE_UNKNOWN_SKILL_HINT")
	lines.add_child(desc)
	if note != "":
		var note_label := _label(SkillCardFace.TEXT_SIZE, GOLD)
		note_label.text = note
		lines.add_child(note_label)
	var bottom_row := SkillCardFace.BottomRow.new()
	lines.add_child(bottom_row)
	bottom_row.show_skill(skill, mon, scouted)
	SkillCardPaper.attach(card, skill, false, scouted)
	SkillCardPaper.make_room_for_flames(_content)
	# Text nicht auf den Papierrahmen setzen
	for side in ["left", "right", "top", "bottom"]:
		lines.get_parent().add_theme_constant_override("margin_" + side, 16)
	return card

func _card(min_size: Vector2) -> Button:
	var card := Button.new()
	card.theme = FLAT_THEME
	card.custom_minimum_size = min_size
	RewardDialog.clear_button_styles(card, StyleBoxEmpty.new())
	# Hover zeigt der Rand der Platte; Skill-Karten ersetzen sie durch ihr Papier
	var plate := IronPlate.back(card)
	card.mouse_entered.connect(plate.set_rim.bind(GOLD))
	card.mouse_exited.connect(plate.set_rim.bind(IronPlate.RIM))
	_content.add_child(card)
	return card

func _disable(card: Button) -> void:
	card.disabled = true
	card.modulate.a = 0.45

func _card_lines(card: Button) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(margin)
	var lines := VBoxContainer.new()
	lines.mouse_filter = MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 4)
	margin.add_child(lines)
	return lines

func _action_button(text_key: String, result: Dictionary) -> Button:
	var button := RewardDialog.plate_button(text_key)
	button.custom_minimum_size = Vector2(180, 44)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(_choice.emit.bind(result))
	return button

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label
