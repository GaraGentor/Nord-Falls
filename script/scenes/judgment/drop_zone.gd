class_name JudgementDropZone
extends PanelContainer

## Ablagefläche im Judgement-Screen: nimmt gezogene Monster an oder per Klick das gerade ausgewählte.
## check(data) liefert "" wenn das Monster hier abgelegt werden darf, sonst den Grund dagegen.

signal dropped(data: Dictionary)
signal clicked

var check: Callable
# Frame, in dem zuletzt ein Monster über die Fläche gezogen wurde
var _hover_frame := -10

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()

func is_drag_hovered() -> bool:
	return Engine.get_process_frames() - _hover_frame < 3

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("judgement_mon"):
		return false
	_hover_frame = Engine.get_process_frames()
	return check.is_valid() and check.call(data) == ""

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.emit(data)
