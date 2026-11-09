class_name SettingsDialog
extends InfoDialog

## Einstellungen (GameSettings) als Dialog, erreichbar über das Zahnrad im Startbildschirm und im Header der Karte.
## Fährt von unten herein. Neue Einstellungen kommen als weitere Abschnitte in _build.

const GEAR_ICON := preload("res://assets/ui/icons/gear.svg")
const OPTION_WIDTH := 170
const CAPTION_WIDTH := 200
const SLIDE_DISTANCE := 160.0
## nicht gewählte Option abgedunkelt, wie die Schalter im Debug-Menü
const UNPICKED_COLOR := Color(0.65, 0.65, 0.65)

## Wählbare Option -> Wert, den sie setzt (für das Hervorheben der aktiven)
var _window_buttons := {}

## Zahnrad-Button mit Eisenplatte, öffnet den Dialog über host
static func make_button(host: Node) -> Button:
	var button := Button.new()
	button.tooltip_text = "SETTINGS_TITLE"
	button.icon = GEAR_ICON
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	RewardDialog.clear_button_styles(button, StyleBoxEmpty.new())
	IronPlate.back(button)
	button.pressed.connect(func(): InfoDialog.present(host, SettingsDialog.new()))
	return button

func _build(content: VBoxContainer) -> void:
	content.add_child(_title(tr("SETTINGS_TITLE"), SkillDetailPopup.GOLD))
	if GameSettings.has_window_mode():
		content.add_child(_section(tr("SETTINGS_DISPLAY")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var caption := _text(tr("SETTINGS_WINDOW_MODE"), IronPlate.TEXT_COLOR, ROW_FONT_SIZE)
		caption.custom_minimum_size.x = CAPTION_WIDTH
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(caption)
		row.add_child(_option_button(tr("SETTINGS_WINDOWED"), false))
		row.add_child(_option_button(tr("SETTINGS_FULLSCREEN"), true))
		content.add_child(row)
		content.add_child(_note(tr("SETTINGS_FULLSCREEN_HINT"), IronPlate.TEXT_COLOR))
		GameSettings.changed.connect(_refresh)
		_refresh()
	else:
		content.add_child(_note(tr("SETTINGS_NONE"), IronPlate.TEXT_COLOR))

func _option_button(text: String, fullscreen: bool) -> Button:
	var button := RewardDialog.plate_button(text)
	button.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	button.custom_minimum_size.x = OPTION_WIDTH
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.pressed.connect(GameSettings.set_fullscreen.bind(fullscreen))
	_window_buttons[button] = fullscreen
	return button

## Aktive Option hell mit goldener Schrift, die andere abgedunkelt
func _refresh() -> void:
	for button: Button in _window_buttons:
		var active: bool = _window_buttons[button] == GameSettings.fullscreen
		button.modulate = Color.WHITE if active else UNPICKED_COLOR
		button.add_theme_color_override("font_color", SkillDetailPopup.GOLD if active else IronPlate.TEXT_COLOR)

func _exit_tree() -> void:
	if GameSettings.changed.is_connected(_refresh):
		GameSettings.changed.disconnect(_refresh)

## Panel fährt von unten hoch
func _animate_in() -> void:
	var target_y := _panel.position.y
	_panel.position.y = target_y + SLIDE_DISTANCE
	_panel.modulate.a = 0
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "position:y", target_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
