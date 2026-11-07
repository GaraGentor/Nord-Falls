extends ScrollContainer

## Horizontale Kartenhand: per Mausrad, Wischen oder Ziehen scrollbar.

const CARD_SCENE = preload("res://script/scenes/battle/battle_card.tscn")
const WHEEL_STEP := 60.0
const SCROLL_SMOOTH := 14.0

@export var card_container: HBoxContainer

var _target_scroll := 0.0
var _mon: Monster

func _ready() -> void:
	Events.call_skill_card.connect(func(_skill): refresh_playable.call_deferred())

func show_mon(mon: Monster) -> void:
	_mon = mon
	for c in card_container.get_children():
		c.queue_free()
	for skill in mon._skills:
		var card = CARD_SCENE.instantiate()
		card.skill = skill
		card.hand = self
		card_container.add_child(card)
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
			card.playable = _mon._computed_moves >= card.skill.cost and Skills.is_playable(_mon, card.skill)

func swipe_by(amount: float) -> void:
	_target_scroll = clampf(_target_scroll + amount, 0.0, _max_scroll())
	scroll_horizontal = int(_target_scroll)

func _max_scroll() -> float:
	return maxf(0.0, card_container.get_parent().size.x - size.x)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				_target_scroll = clampf(_target_scroll - WHEEL_STEP, 0.0, _max_scroll())
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				_target_scroll = clampf(_target_scroll + WHEEL_STEP, 0.0, _max_scroll())
				accept_event()
	elif event is InputEventPanGesture:
		swipe_by(event.delta.x * 10.0)
		accept_event()

func _process(delta: float) -> void:
	var current := float(scroll_horizontal)
	if absf(current - _target_scroll) > 0.5:
		var step := maxf(absf(_target_scroll - current) * delta * SCROLL_SMOOTH, 2.0)
		scroll_horizontal = roundi(move_toward(current, _target_scroll, step))
