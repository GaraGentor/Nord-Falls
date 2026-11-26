class_name JudgementDropZone
extends PanelContainer

## Ablagefläche im Judgement-Screen: Team-Plätze, die Fang-Seite links und die Tasche.
## Nimmt gezogene Monster ({"judgement_mon"}) oder Fähigkeiten ({"judgement_skill", "owner"}) an.
## check(data) liefert "" wenn die Ablage erlaubt ist, sonst den Grund dagegen ("-" = ergibt hier keinen Sinn).
## Mit einem echten Grund (Text) nimmt die Fläche die Ablage trotzdem an, damit der Screen den Grund anzeigen kann.

signal dropped(data: Dictionary)

var check: Callable
# Frame, in dem zuletzt etwas über die Fläche gezogen wurde
var _hover_frame := -10

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS

func is_drag_hovered() -> bool:
	return Engine.get_process_frames() - _hover_frame < 3

static func is_judgement_data(data: Variant) -> bool:
	return data is Dictionary and (data.has("judgement_mon") or data.has("judgement_skill"))

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not is_judgement_data(data):
		return false
	_hover_frame = Engine.get_process_frames()
	return check.is_valid() and check.call(data) != "-"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.emit(data)
