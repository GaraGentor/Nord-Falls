extends Control

## Zeigt die Zugreihenfolge eines Kampfes als Rad und bestimmt, wer am Zug ist.
## Die Reihenfolge ergibt sich aus der Initiative (speed): das schnellste Monster beginnt.
## Das Monster oben auf dem Rad ist am Zug. Nach jedem Zug dreht sich das Rad weiter,
## nach einer vollen Umdrehung beginnt die nächste Runde.

signal turn_for(mon)
signal end_round()

const IconFrame := preload("res://script/scenes/battle/wheel_icon_frame.gd")

const OWN_COLOR := Color("#1f5a33")
const OWN_PULSE_COLOR := Color("#5fcf80")
const ENEMY_COLOR := Color("#6b1030")
const ENEMY_PULSE_COLOR := Color("#e0304f")
const ROTATE_DURATION := 0.45
const ACTIVE_SCALE := 1.35
const INACTIVE_ALPHA := 0.7
## Ring um das Icon des Monsters, dessen Werte gerade angezeigt werden: so weit steht er über und so dick ist er
const SELECTION_RING_GROW := 5
const SELECTION_RING_WIDTH := 3.0

var debug = false

@export var wheel: Control
@export var round_label: Label
@export var debug_button: Button

var order: Array = []
var icons: Array[Control] = []
var current_index := -1
var current_mon: Monster
var round_number := 0
## Monster, dessen Werte gerade angezeigt werden
var selected_mon: Monster

var _rotation_tween: Tween

func _ready() -> void:
	debug_button.visible = debug
	round_label.text = ""
	if debug:
		var mon1:Monster = Helper.generate_mons({"count": 1, "level": randi_range(10,30)})[0]
		var mon2:Monster = Helper.generate_mons({"count": 1, "level": randi_range(10,30)})[0]
		State.mons.append(mon1)
		State.mons.append(mon2)
		var mon3:Monster = Helper.generate_mons({"count": 1, "level": randi_range(10,30)})[0]
		State.enemy_mons.append(mon3)
		start()

## Startet den Kampf mit Runde 1 und gibt dem schnellsten Monster den Zug.
func start() -> void:
	round_number = 0
	_start_round()
	_begin_turn()

## Beendet den aktuellen Zug und gibt den Zug an das nächste Monster weiter.
func next_mon() -> void:
	if order.is_empty():
		return
	current_index += 1
	if current_index >= order.size():
		# volle Umdrehung zurück zum ersten Monster, danach neu aufbauen
		await _rotate_to(order.size())
		if not is_inside_tree():
			return
		end_round.emit()
		_start_round()
	_begin_turn()

## Entfernt ein besiegtes oder gefangenes Monster vom Rad.
func remove_mon(mon: Monster) -> void:
	var index := order.find(mon)
	if index == -1:
		return
	order.remove_at(index)
	var icon := icons[index]
	icons.remove_at(index)
	wheel.remove_child(icon)
	icon.queue_free()
	# Index so anpassen, dass next_mon() beim richtigen Monster weitermacht
	if index <= current_index:
		current_index -= 1
	_update_slots()
	_highlight()
	_rotate_to(maxi(current_index, 0))

## Markiert das Monster auf dem Rad, dessen Werte gerade angezeigt werden.
func set_selected_mon(mon: Monster) -> void:
	selected_mon = mon
	for i in range(icons.size()):
		icons[i].get_meta("selection_ring").visible = order[i] == mon
	_highlight()

func is_own(mon: Monster) -> bool:
	return State.mons.has(mon)

func _start_round() -> void:
	round_number += 1
	round_label.text = tr("TURN_WHEEL_ROUND").format({"round": round_number})
	order = []
	order.append_array(State.mons.filter(func(mon: Monster): return mon.is_alive()))
	order.append_array(State.enemy_mons.filter(func(mon: Monster): return mon.is_alive()))
	# höhere Initiative zuerst, bei Gleichstand beginnen die eigenen Monster
	order.sort_custom(func(a: Monster, b: Monster):
		if a.speed() == b.speed():
			return is_own(a) and not is_own(b)
		return a.speed() > b.speed())
	if round_number == 1:
		order = Relics.modify("first_round_order", order)
	_build_icons()
	current_index = 0
	wheel.angle_offset = 0.0

func _begin_turn() -> void:
	if order.is_empty():
		return
	current_mon = order[current_index]
	_highlight()
	await _rotate_to(current_index)
	if is_inside_tree():
		turn_for.emit(current_mon)

func _build_icons() -> void:
	for icon in icons:
		wheel.remove_child(icon)
		icon.queue_free()
	icons = []
	for mon in order:
		var icon := _create_icon(mon)
		wheel.add_child(icon)
		icons.append(icon)
	_update_slots()

func _update_slots() -> void:
	for i in range(icons.size()):
		icons[i].set_meta("slot", i)
	wheel.layout_circle()

func _create_icon(mon: Monster) -> Control:
	var icon := Panel.new()
	icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon.gui_input.connect(_on_icon_input.bind(mon))
	icon.size = Vector2(wheel.icon_size, wheel.icon_size)
	icon.pivot_offset = icon.size / 2
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.01, 0.02, 0.92)
	style.set_corner_radius_all(int(wheel.icon_size / 2))
	icon.add_theme_stylebox_override("panel", style)

	var texture := TextureRect.new()
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Monmap.show_on(texture, mon._name, Monmap.TINY)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.add_child(texture)
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)

	var frame := IconFrame.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_own(mon):
		frame.setup(OWN_COLOR, OWN_PULSE_COLOR)
	else:
		frame.setup(ENEMY_COLOR, ENEMY_PULSE_COLOR)
	icon.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.set_meta("frame", frame)

	var selection_ring := IconFrame.new()
	selection_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_ring.setup(Monmap.SELECTED_OUTLINE_COLOR, Monmap.SELECTED_OUTLINE_COLOR)
	selection_ring.material.set_shader_parameter("line_width", SELECTION_RING_WIDTH)
	selection_ring.visible = mon == selected_mon
	icon.add_child(selection_ring)
	selection_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, -SELECTION_RING_GROW)
	icon.set_meta("selection_ring", selection_ring)
	return icon

func _on_icon_input(event: InputEvent, mon: Monster) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.SELECT_MONSTER, "mon": mon})

func _highlight() -> void:
	for i in range(icons.size()):
		var icon := icons[i]
		var is_active := i == current_index
		if is_active:
			# zuletzt gezeichnet liegt das aktive Icon über den Nachbarn, aber nicht über anderen UI-Ebenen
			wheel.move_child(icon, -1)
		var tween := create_tween().set_parallel()
		tween.tween_property(icon, "scale", Vector2.ONE * (ACTIVE_SCALE if is_active else 1.0), ROTATE_DURATION)
		tween.tween_property(icon, "modulate:a", 1.0 if is_active or order[i] == selected_mon else INACTIVE_ALPHA, ROTATE_DURATION)
		tween.tween_property(icon.get_meta("frame"), "active_amount", 1.0 if is_active else 0.0, ROTATE_DURATION)

func _rotate_to(index: int) -> void:
	if _rotation_tween:
		_rotation_tween.kill()
	_rotation_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_rotation_tween.tween_property(wheel, "angle_offset", wheel.angle_step() * index, ROTATE_DURATION)
	# Timer statt tween.finished: ein abgebrochener Tween würde sonst nie fertig melden
	await get_tree().create_timer(ROTATE_DURATION).timeout

func _on_button_pressed() -> void:
	next_mon()
