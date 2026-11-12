class_name AutoScrollContainer
extends ScrollContainer

## Scrollt langsam von selbst nach unten, wartet kurz und scrollt wieder nach oben, aber nur,
## wenn der Inhalt nicht hineinpasst (z. B. lange Skill-Beschreibungen auf Karten).
## Scrollt der Spieler selbst (Mausrad / Leiste), setzt das automatische Scrollen erst nach
## einer Weile Ruhe wieder ein und macht von dort aus weiter.
## Gedrückt halten auf hold_area (z. B. die ganze Karte) hält das Scrollen an, bis losgelassen wird.

## Pixel pro Sekunde nach unten, zurück nach oben geht es schneller
@export var speed := 14.0
@export var back_factor := 4.0
## Pause oben und unten, bevor es weitergeht
@export var pause := 1.6
## so viele Sekunden nach dem letzten eigenen Scrollen setzt das automatische wieder ein
@export var resume_after := 4.0
## Solange hier gedrückt gehalten wird (Maus oder Finger), steht das Scrollen still, zum Lesen.
## Leer = der Container selbst. Die Eingabe wird nur beobachtet, nicht verbraucht (Drag & Drop bleibt).
@export var hold_area: Control

## gerade gedrückt gehalten: kein automatisches Scrollen
var _held := false

## genaue Position (scroll_vertical kennt nur ganze Pixel)
var _auto_pos := 0.0
## zuletzt selbst gesetzter Wert, weicht scroll_vertical davon ab, hat der Spieler gescrollt
var _set_value := 0
var _direction := 1
var _wait := 0.0
var _idle := 0.0

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

func _ready() -> void:
	if hold_area == null:
		hold_area = self
	restart()

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		# Loslassen zählt überall, auch wenn die Karte inzwischen weggezogen wurde
		_held = false
	elif is_visible_in_tree() and hold_area.get_global_rect().has_point(hold_area.get_global_mouse_position()):
		_held = true

## Zurück nach oben, mit Pause vor dem ersten Scrollen (z. B. nach neuem Text)
func restart() -> void:
	scroll_vertical = 0
	_auto_pos = 0.0
	_set_value = 0
	_direction = 1
	_wait = pause
	_idle = resume_after

func _process(delta: float) -> void:
	var bar := get_v_scroll_bar()
	var max_scroll := maxf(bar.max_value - bar.page, 0.0)
	if max_scroll < 1.0:
		return
	if scroll_vertical != _set_value:
		# der Spieler hat selbst gescrollt: von dort aus später weiter
		_idle = 0.0
		_wait = 0.0
		_set_value = scroll_vertical
		_auto_pos = _set_value
		return
	if _held:
		return
	_idle += delta
	if _idle < resume_after:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var step := speed * (1.0 if _direction > 0 else back_factor)
	_auto_pos = clampf(_auto_pos + _direction * step * delta, 0.0, max_scroll)
	if (_direction > 0 and _auto_pos >= max_scroll) or (_direction < 0 and _auto_pos <= 0.0):
		_direction = -_direction
		_wait = pause
	scroll_vertical = int(_auto_pos)
	_set_value = scroll_vertical
