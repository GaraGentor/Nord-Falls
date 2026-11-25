class_name ChoiceDialog
extends InfoDialog

## Frage mit zwei Antworten im Rahmen der Info-Dialoge: Titel, Text, links "Nein", rechts "Ja" (gold).
## Das Ergebnis kommt über chosen (true = Ja). Startabfrage und Überspringen des Tutorials (Tutorial).
## dismissable: Klick daneben und Esc zählen als Nein; sonst muss man eine Antwort wählen.

signal chosen(yes: bool)

const ANSWER_MIN_WIDTH := 220.0

var _question_title: String
var _question_text: String
var _yes_text: String
var _no_text: String
var _dismissable: bool
var _answered := false

## Hängt die Frage an host (eine Ebene über dessen CanvasLayer) und liefert den Dialog zurück: await dialog.chosen
static func ask(host: Node, title: String, text: String, yes: String, no: String, dismissable := true) -> ChoiceDialog:
	return InfoDialog.present(host, ChoiceDialog.new(title, text, yes, no, dismissable))

func _init(title: String, text: String, yes: String, no: String, dismissable: bool) -> void:
	super()
	_question_title = title
	_question_text = text
	_yes_text = yes
	_no_text = no
	_dismissable = dismissable

func _has_close_button() -> bool:
	return false

func _build(content: VBoxContainer) -> void:
	content.add_child(_title(_question_title, SkillDetailPopup.GOLD))
	var text := _note(_question_text, IronPlate.TEXT_COLOR)
	text.modulate.a = 1.0
	content.add_child(text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	content.add_child(buttons)
	buttons.add_child(_answer_button(_no_text, IronPlate.TEXT_COLOR, false))
	buttons.add_child(_answer_button(_yes_text, SkillDetailPopup.GOLD, true))

func _answer_button(text: String, color: Color, yes: bool) -> Button:
	var button := RewardDialog.plate_button(text)
	button.custom_minimum_size.x = ANSWER_MIN_WIDTH
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", color)
	button.pressed.connect(_answer.bind(yes))
	return button

func _answer(yes: bool) -> void:
	if _answered:
		return
	_answered = true
	chosen.emit(yes)
	super.close()

## Klick daneben oder Esc (InfoDialog): Nein, wenn erlaubt
func close() -> void:
	if _dismissable:
		_answer(false)
