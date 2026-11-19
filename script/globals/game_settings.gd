extends Node

## Einstellungen des Spielers, gespeichert in user://settings.cfg (getrennt vom Spielstand, siehe SaveManager).
## Fenstermodus gibt es nur auf dem PC, auf dem Handy läuft das Spiel immer im Vollbild.
## Außerdem: F11 und Alt+Enter schalten das Vollbild um, und pixel_scale hält die Pixel-Shader bei jeder
## Fenstergröße so grob wie in der Grundauflösung (Stretch-Modus canvas_items, siehe living_pixels.gdshader).

signal changed

const PATH := "user://settings.cfg"

var fullscreen := false
## Rand-Effekte der Skill-Karten (Flammen, Wellen, Funken, Tropfen; SkillCardPaper)
var card_effects := true
## großes Art-Symbol als Wasserzeichen auf den Skill-Karten (SkillCardPaper)
var card_watermark := true
## Easy Mode: die Relikte aus Relics.EASY_MODE_RELICS (alle Werte und Fähigkeiten der Gegner) gelten in jedem Run
## als gesammelt und werden deshalb nirgends mehr angeboten
var easy_mode := false
## Das Relikt Relics.ENEMY_HP_RELIC (genaue HP der Gegner) gilt in jedem Run als gesammelt, unabhängig vom Easy Mode
var show_enemy_hp := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_apply_window_mode()
	get_tree().root.size_changed.connect(_update_pixel_scale)
	_update_pixel_scale()

## Fenster/Vollbild nur auf dem PC (Windows, Linux, macOS), nicht auf Handy oder im Browser
func has_window_mode() -> bool:
	return OS.has_feature("pc")

func set_fullscreen(on: bool) -> void:
	if fullscreen == on:
		return
	fullscreen = on
	_apply_window_mode()
	_save()
	changed.emit()

func set_card_effects(on: bool) -> void:
	if card_effects == on:
		return
	card_effects = on
	_save()
	changed.emit()

func set_card_watermark(on: bool) -> void:
	if card_watermark == on:
		return
	card_watermark = on
	_save()
	changed.emit()

func set_easy_mode(on: bool) -> void:
	if easy_mode == on:
		return
	easy_mode = on
	_save()
	changed.emit()
	Relics.relics_changed.emit()

func set_show_enemy_hp(on: bool) -> void:
	if show_enemy_hp == on:
		return
	show_enemy_hp = on
	_save()
	changed.emit()
	Relics.relics_changed.emit()

func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)

func _input(event: InputEvent) -> void:
	if not has_window_mode() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

func _apply_window_mode() -> void:
	if not has_window_mode():
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)

## Bildschirmpixel pro Spielpixel: wie stark das 1280x720-Layout gerade vergrößert ist
func _update_pixel_scale() -> void:
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var window := Vector2(get_tree().root.size)
	var scale := minf(window.x / base.x, window.y / base.y)
	RenderingServer.global_shader_parameter_set(&"pixel_scale", maxf(scale, 0.01))

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	fullscreen = config.get_value("display", "fullscreen", false)
	card_effects = config.get_value("display", "card_effects", true)
	card_watermark = config.get_value("display", "card_watermark", true)
	easy_mode = config.get_value("gameplay", "easy_mode", false)
	show_enemy_hp = config.get_value("gameplay", "show_enemy_hp", false)

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "card_effects", card_effects)
	config.set_value("display", "card_watermark", card_watermark)
	config.set_value("gameplay", "easy_mode", easy_mode)
	config.set_value("gameplay", "show_enemy_hp", show_enemy_hp)
	config.save(PATH)
