class_name SettingsDialog
extends InfoDialog

## Einstellungen (GameSettings, Tutorial) als Dialog, erreichbar über das Zahnrad im Startbildschirm und im Header der Karte.
## Fährt von unten herein. Neue Einstellungen kommen als weitere Abschnitte in _build.

const GEAR_ICON := preload("res://assets/ui/icons/gear.svg")
const CHECK_ON_ICON := preload("res://assets/ui/icons/check_go.svg")
const CHECK_OFF_ICON := preload("res://assets/ui/icons/check_empty.svg")
const OPTION_WIDTH := 170
const CAPTION_WIDTH := 200
const CHECK_SIZE := Vector2(40, 40)
const SLIDE_DISTANCE := 160.0
## nicht gewählte Option abgedunkelt, wie die Schalter im Debug-Menü
const UNPICKED_COLOR := Color(0.65, 0.65, 0.65)

## Wählbare Option -> Wert, den sie setzt (für das Hervorheben der aktiven)
var _window_buttons := {}

## Zahnrad-Button mit Eisenplatte, öffnet den Dialog über host.
## Das Zahnrad selbst hat "Lebende Pixel" wie die anderen Symbol-Knöpfe (RewardDialog.icon_button).
static func make_button(host: Node) -> Button:
	var button := Button.new()
	button.tooltip_text = "SETTINGS_TITLE"
	button.icon = GEAR_ICON
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.material = RewardDialog.ICON_BUTTON_MATERIAL
	RewardDialog.clear_button_styles(button, StyleBoxEmpty.new())
	button.add_theme_color_override("icon_hover_color", RewardDialog.BUTTON_HOVER_COLOR)
	button.add_theme_color_override("icon_hover_pressed_color", RewardDialog.BUTTON_HOVER_COLOR)
	IronPlate.back(button)
	button.pressed.connect(func(): InfoDialog.present(host, SettingsDialog.new()))
	return button

## Checkbox im Pixel-Look: Eisenplatte, angehakt mit grünem Haken (wie der Los-Knopf im Konfigurator),
## mit "Lebenden Pixeln" wie die anderen Symbol-Knöpfe. Ein Klick auf die Beschriftung daneben schaltet mit.
static func make_check(text: String, on: bool, on_toggled: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var check := RewardDialog.icon_button(CHECK_ON_ICON if on else CHECK_OFF_ICON)
	check.toggle_mode = true
	check.button_pressed = on
	check.custom_minimum_size = CHECK_SIZE
	check.size = CHECK_SIZE
	check.focus_mode = Control.FOCUS_NONE
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	check.toggled.connect(func(pressed: bool):
		check.icon = CHECK_ON_ICON if pressed else CHECK_OFF_ICON
		on_toggled.call(pressed))
	row.add_child(check)
	var caption := Label.new()
	caption.text = text
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	caption.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	caption.mouse_filter = Control.MOUSE_FILTER_STOP
	caption.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	caption.mouse_entered.connect(func(): caption.add_theme_color_override("font_color", SkillDetailPopup.GOLD))
	caption.mouse_exited.connect(func(): caption.add_theme_color_override("font_color", IronPlate.TEXT_COLOR))
	caption.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			check.button_pressed = not check.button_pressed)
	row.add_child(caption)
	return row

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
	content.add_child(_section(tr("SETTINGS_TUTORIAL")))
	var tutorial_check := make_check(tr("SETTINGS_TUTORIAL_TOGGLE"), Tutorial.is_enabled(), _on_tutorial_toggled)
	tutorial_check.size_flags_horizontal = SIZE_SHRINK_BEGIN
	content.add_child(tutorial_check)
	content.add_child(_note(tr("SETTINGS_TUTORIAL_HINT"), IronPlate.TEXT_COLOR))

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

## Eingeschaltet geht es sofort los: der Dialog schließt sich, die Szene startet ihre Sequenz (Tutorial.enabled_changed)
func _on_tutorial_toggled(on: bool) -> void:
	if on:
		close()
	Tutorial.set_enabled(on)

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
