class_name DragScroll
extends Node

## Ziehen mit Finger (oder Maus) scrollt einen ScrollContainer, auch wenn der Druck auf einem Button
## oder einem anderen Control beginnt, das die Maus abfängt. Dort kommt der eingebaute Touch-Scroll
## von Godot nie an, weil der Druck schon vom Kind verbraucht wird.
## Erst ab DEADZONE Pixeln wird aus dem Tippen ein Ziehen, dann löst der Button beim Loslassen nicht aus.
## Nach dem Loslassen gleitet die Liste mit Schwung aus.
##
## Benutzung: DragScroll.attach(scroll_container)

const DEADZONE := 14.0
## Schwung nach dem Loslassen: Abbremsen pro Sekunde, darunter steht die Liste
const FRICTION := 5.0
const MIN_FLING_SPEED := 30.0
const MAX_FLING_SPEED := 4000.0
## so weit außerhalb wird das Loslassen nach einem Ziehen gemeldet, damit kein Button auslöst
const NOWHERE := Vector2(-100000, -100000)

var _scroll: ScrollContainer
var _pressing := false
var _dragging := false
var _press_pos := Vector2.ZERO
## genaue Scroll-Position (scroll_vertical/-horizontal kennen nur ganze Pixel)
var _pos := Vector2.ZERO
var _velocity := Vector2.ZERO
var _last_motion_usec := 0
## Bewegungen seit dem Druck. Erst nach der ersten hat die GUI das Control unter dem Finger aktualisiert
## (beim Touch gibt es vor dem Druck keine Bewegung, der alte Wert kann noch vom letzten Tippen stammen).
var _motions := 0

static func attach(scroll: ScrollContainer) -> DragScroll:
	var drag := DragScroll.new()
	drag._scroll = scroll
	scroll.add_child(drag)
	return drag

func _ready() -> void:
	set_process(false)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event)
		elif _pressing:
			_on_release(event)
	elif event is InputEventMouseMotion and _pressing:
		_on_motion(event)
	elif event is InputEventScreenDrag and _dragging:
		# die Maus-Emulation des Fingers erledigt das Scrollen, der eingebaute Touch-Scroll soll nicht mitscrollen
		get_viewport().set_input_as_handled()

func _on_press(event: InputEventMouseButton) -> void:
	set_process(false)
	_velocity = Vector2.ZERO
	if not _scroll.is_visible_in_tree() or not _scroll.get_global_rect().has_point(event.global_position):
		return
	_pressing = true
	_dragging = false
	_press_pos = event.global_position
	_motions = 0
	_pos =Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical)

func _on_motion(event: InputEventMouseMotion) -> void:
	_motions += 1
	# hat ein Control unter dem Finger ein Drag & Drop begonnen (z. B. nach langem Drücken), scrollt die Liste nicht
	if get_viewport().gui_is_dragging():
		_pressing = false
		_dragging = false
		return
	if not _dragging:
		if _motions < 2 or event.global_position.distance_to(_press_pos) < DEADZONE:
			return
		# Nur ziehen, wenn der Finger wirklich auf dem ScrollContainer liegt und nicht auf etwas darüber
		# (Dialog, Legende ...). Das weiß die GUI erst nach der ersten Bewegung, solange warten.
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered == null:
			return
		if hovered != _scroll and not _scroll.is_ancestor_of(hovered):
			_pressing = false
			return
		_dragging = true
		_last_motion_usec = Time.get_ticks_usec()
	var now := Time.get_ticks_usec()
	var seconds := maxf((now - _last_motion_usec) / 1_000_000.0, 0.001)
	_last_motion_usec = now
	# geglättet, damit ein einzelnes Zucken am Ende den Schwung nicht bestimmt
	_velocity = _velocity.lerp(-event.relative / seconds, 0.4)
	_scroll_by(-event.relative)
	get_viewport().set_input_as_handled()

func _on_release(event: InputEventMouseButton) -> void:
	_pressing = false
	if not _dragging:
		return
	_dragging = false
	# Der Button unter dem Finger bekommt das Loslassen weit außerhalb und löst deshalb nicht aus
	event.position = NOWHERE
	event.global_position = NOWHERE
	# lag die letzte Bewegung schon eine Weile zurück, hat der Finger angehalten: kein Schwung
	if Time.get_ticks_usec() - _last_motion_usec > 100_000:
		_velocity = Vector2.ZERO
	_velocity = _velocity.limit_length(MAX_FLING_SPEED)
	set_process(_velocity.length() > MIN_FLING_SPEED)

func _process(delta: float) -> void:
	_scroll_by(_velocity * delta)
	_velocity *= maxf(1.0 - FRICTION * delta, 0.0)
	if _velocity.length() < MIN_FLING_SPEED:
		set_process(false)

func _scroll_by(amount: Vector2) -> void:
	var h_bar := _scroll.get_h_scroll_bar()
	var v_bar := _scroll.get_v_scroll_bar()
	if _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_pos.x = clampf(_pos.x + amount.x, 0.0, maxf(h_bar.max_value - h_bar.page, 0.0))
		_scroll.scroll_horizontal = int(_pos.x)
	if _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_pos.y = clampf(_pos.y + amount.y, 0.0, maxf(v_bar.max_value - v_bar.page, 0.0))
		_scroll.scroll_vertical = int(_pos.y)
