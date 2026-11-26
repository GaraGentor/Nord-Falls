extends ScrollContainer

## Horizontale Kartenhand: per Mausrad, Wischen oder Ziehen scrollbar (auch zwischen den Karten),
## nach dem Loslassen gleitet sie mit Schwung aus. Gescrollt werden kann immer, auch im Zug der Gegner
## (die Hand liegt über dem Eingabe-Blocker), ausspielen nur, wenn can_play es erlaubt.

const CARD_SCENE = preload("res://script/scenes/battle/battle_card.tscn")
const WHEEL_STEP := 60.0
const SCROLL_SMOOTH := 14.0
## ab so vielen Pixeln wird ein Druck zwischen den Karten zum Wischen
const SWIPE_THRESHOLD := 8.0
## Schwung nach dem Loslassen: Abbremsen pro Sekunde, darunter steht die Hand
const FRICTION := 5.0
const MIN_FLING_SPEED := 40.0
const MAX_FLING_SPEED := 4000.0

@export var card_container: HBoxContainer

## Dürfen Karten gerade ausgespielt (gezogen) werden? Setzt der Kampf (nicht im Zug der Gegner).
var can_play: Callable = func() -> bool: return true

var _target_scroll := 0.0
var _mon: Monster
## Wischgeschwindigkeit in Pixel pro Sekunde, geglättet
var _velocity := 0.0
var _last_swipe_usec := 0
var _flinging := false
## Druck auf eine freie Stelle der Hand (zwischen den Karten)
var _gap_pressed := false
var _gap_swiping := false
var _gap_press_x := 0.0

func _ready() -> void:
	Events.call_skill_card.connect(func(_skill): refresh_playable.call_deferred())
	# Element-Leihgabe: Karten zeigen das geliehene Element bzw. beim Ziehen einer Kugel die Vorschau
	Events.element_loans_changed.connect(refresh_playable)

func show_mon(mon: Monster) -> void:
	_mon = mon
	for c in card_container.get_children():
		c.queue_free()
	for skill in mon._skills:
		var card = CARD_SCENE.instantiate()
		card.mon = mon
		card.skill = skill
		card.hand = self
		card_container.add_child(card)
	stop_fling()
	_target_scroll = 0.0
	scroll_horizontal = 0
	refresh_playable()

## Karten ausgrauen, deren Kosten das Monster gerade nicht zahlen kann, deren Element ihm fehlt,
## deren Abklingzeit noch läuft oder die passiv sind
func refresh_playable() -> void:
	if _mon == null:
		return
	for card in card_container.get_children():
		if not card.is_queued_for_deletion():
			card.show_state(_mon)
			card.playable = _mon._computed_moves >= Skills.skill_cost(_mon, card.skill) and Skills.is_playable(_mon, card.skill)
			card.loan_dim = ElementLoan.preview_dims(_mon, card.skill)

## Wischen um amount Pixel (von einer Karte oder einer freien Stelle der Hand)
func swipe_by(amount: float) -> void:
	_flinging = false
	var now := Time.get_ticks_usec()
	var seconds := maxf((now - _last_swipe_usec) / 1_000_000.0, 0.001)
	_last_swipe_usec = now
	_velocity = lerpf(_velocity, amount / seconds, 0.4)
	_target_scroll = clampf(_target_scroll + amount, 0.0, _max_scroll())
	scroll_horizontal = int(_target_scroll)

## Finger losgelassen: mit dem Schwung des Wischens weitergleiten
func end_swipe() -> void:
	# lag die letzte Bewegung schon eine Weile zurück, hat der Finger angehalten: kein Schwung
	if Time.get_ticks_usec() - _last_swipe_usec > 100_000:
		_velocity = 0.0
	_velocity = clampf(_velocity, -MAX_FLING_SPEED, MAX_FLING_SPEED)
	_flinging = absf(_velocity) > MIN_FLING_SPEED

func stop_fling() -> void:
	_flinging = false
	_velocity = 0.0

func _max_scroll() -> float:
	return maxf(0.0, card_container.get_parent().size.x - size.x)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index != MOUSE_BUTTON_LEFT:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				stop_fling()
				_target_scroll = clampf(_target_scroll - WHEEL_STEP, 0.0, _max_scroll())
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				stop_fling()
				_target_scroll = clampf(_target_scroll + WHEEL_STEP, 0.0, _max_scroll())
				accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# freie Stelle zwischen den Karten: Ziehen scrollt die Hand
		if event.pressed:
			stop_fling()
			_gap_pressed = true
			_gap_swiping = false
			_gap_press_x = event.global_position.x
		else:
			if _gap_swiping:
				end_swipe()
			_gap_pressed = false
			_gap_swiping = false
		accept_event()
	elif event is InputEventMouseMotion and _gap_pressed:
		if not _gap_swiping and absf(event.global_position.x - _gap_press_x) > SWIPE_THRESHOLD:
			_gap_swiping = true
			_last_swipe_usec = Time.get_ticks_usec()
		if _gap_swiping:
			swipe_by(-event.relative.x)
		accept_event()
	elif event is InputEventPanGesture:
		swipe_by(event.delta.x * 10.0)
		accept_event()
	elif event is InputEventScreenDrag or event is InputEventScreenTouch:
		# Touch wird als Maus emuliert, sonst würde der eingebaute Touch-Scroll doppelt scrollen
		accept_event()

func _process(scaled_delta: float) -> void:
	# die Kampfgeschwindigkeit (Engine.time_scale) soll das Scrollen nicht beschleunigen
	var delta := scaled_delta / maxf(Engine.time_scale, 0.001)
	if _flinging:
		_target_scroll = clampf(_target_scroll + _velocity * delta, 0.0, _max_scroll())
		_velocity *= maxf(1.0 - FRICTION * delta, 0.0)
		if absf(_velocity) < MIN_FLING_SPEED or _target_scroll <= 0.0 or _target_scroll >= _max_scroll():
			stop_fling()
	var current := float(scroll_horizontal)
	if absf(current - _target_scroll) > 0.5:
		var step := maxf(absf(_target_scroll - current) * delta * SCROLL_SMOOTH, 2.0)
		scroll_horizontal = roundi(move_toward(current, _target_scroll, step))
