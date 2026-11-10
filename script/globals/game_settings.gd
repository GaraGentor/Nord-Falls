extends Node

## Einstellungen des Spielers, gespeichert in user://settings.cfg (getrennt vom Spielstand, siehe SaveManager).
## Fenstermodus gibt es nur auf dem PC, auf dem Handy läuft das Spiel immer im Vollbild.
## Außerdem: F11 und Alt+Enter schalten das Vollbild um, und pixel_scale hält die Pixel-Shader bei jeder
## Fenstergröße so grob wie in der Grundauflösung (Stretch-Modus canvas_items, siehe living_pixels.gdshader).

signal changed

const PATH := "user://settings.cfg"

var fullscreen := false

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

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.save(PATH)
