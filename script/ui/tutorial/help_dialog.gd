class_name HelpDialog
extends CanvasLayer

## Nachschlagen während des Runs: das Erklär-Panel vom Startbildschirm (TutorialPanel) als Fenster,
## darunter Tutorial wiederholen oder ausschalten. Öffnet sich über den "?"-Knopf auf Karte und im Kampf (button()).
## Ein Klick neben das Fenster oder Escape schließt es.

const INFO_ICON = preload("res://assets/ui/icons/info.svg")
const FONT_THEME = preload("res://script/ui/materials/pixel_font_theme.tres")
## unter dem Tutorial-Overlay (TutorialOverlay.LAYER), über allem anderen
const LAYER := 90
const DIM := Color(0, 0, 0, 0.6)
const PANEL_SIZE := Vector2(620, 660)
const BUTTON_FONT_SIZE := 18
const STATUS_FONT_SIZE := 15

var _status: Label
var _reset_button: Button
var _off_button: Button

## "?"-Knopf, der das Fenster öffnet
static func button(size: Vector2) -> Button:
	var help := RewardDialog.icon_button(INFO_ICON)
	help.custom_minimum_size = size
	help.size = size
	help.focus_mode = Control.FOCUS_NONE
	help.tooltip_text = TranslationServer.translate("HELP_TITLE")
	help.pressed.connect(func(): help.get_tree().root.add_child(HelpDialog.new()))
	return help

func _init() -> void:
	layer = LAYER

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Klicks neben das Fenster landen beim Abdunkeln darunter und schließen
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme = FONT_THEME
	panel.custom_minimum_size = PANEL_SIZE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	IronPlate.frame(panel, column, 12, 12)
	center.add_child(panel)

	var explanations := TutorialPanel.new()
	explanations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(explanations)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	_status.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	column.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_reset_button = _button("HELP_TUTORIAL_RESET", _on_reset_pressed)
	buttons.add_child(_reset_button)
	_off_button = _button("HELP_TUTORIAL_OFF", _on_off_pressed)
	buttons.add_child(_off_button)
	buttons.add_child(_button("HELP_CLOSE", queue_free))
	_refresh()

func _button(key: String, on_pressed: Callable) -> Button:
	var button := RewardDialog.plate_button(tr(key))
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	return button

## Ausschalten geht nur, solange das Tutorial noch läuft
func _refresh() -> void:
	_off_button.visible = not Tutorial.is_complete()
	_status.text = tr("HELP_TUTORIAL_STATUS_OFF" if Tutorial.is_complete() else "HELP_TUTORIAL_STATUS_ON")

func _on_reset_pressed() -> void:
	Tutorial.reset()
	_refresh()
	_status.text = tr("HELP_TUTORIAL_RESET_DONE")

func _on_off_pressed() -> void:
	Tutorial.skip_all()
	_refresh()

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
